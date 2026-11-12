#define NOMINMAX
#ifndef MJOLNIR_AUDIO_SMOKE
#define MJOLNIR_ABI_ONLY
#include "MjolnirNativeAudio.cpp"
#else
#include <Windows.h>
#include <filesystem>
#include <fstream>
#include <string>
#include <vector>
#include <memory>
#endif
#include <xaudio2.h>
#include <algorithm>
#include <mmsystem.h>
#include <wrl/client.h>
#include <chrono>
#include <cmath>
#include <complex>
#include <cstring>
#include <iostream>
#include <list>
#include <map>
#include <random>
#include <sstream>

// Mjolnir's in-process player.  Lua drops one-line cue files in queue/:
//   <cue> [lead seconds] [gain]
// Each cue draws from a bank of variations (audio/<bank>_NN.wav), never the
// same take twice in a row, with a little pitch and level drift, the way the
// game's own random containers vary.  Swings are timed so their loudest
// moment lands just before the strike the animation is about to make.

namespace {
using Microsoft::WRL::ComPtr;
constexpr UINT32 Rate = 48000;

struct Clip {
    WAVEFORMATEX format{};
    std::vector<BYTE> pcm;
    std::string name;   // file stem, e.g. throw_01
    UINT32 peak{};      // frame of the loudest 10 ms, where a swing "arrives"
    UINT32 loop_end{};  // where a loop of it wraps: its tail past the sound, at a zero crossing

    UINT32 frames() const { return static_cast<UINT32>(pcm.size() / 4); }
    bool read(const std::filesystem::path& path) {
        std::ifstream file(path, std::ios::binary);
        if (!file) return false;
        auto word = [&] { DWORD value{}; file.read(reinterpret_cast<char*>(&value), 4); return value; };
        if (word() != MAKEFOURCC('R','I','F','F')) return false;
        word();
        if (word() != MAKEFOURCC('W','A','V','E')) return false;
        while (file && file.peek() != EOF) {
            const auto id = word();
            const auto size = word();
            if (!file || size > 4 * 1024 * 1024) return false;
            const auto start = file.tellg();
            if (id == MAKEFOURCC('f','m','t',' ') && size >= 16)
                file.read(reinterpret_cast<char*>(&format), 16);
            if (id == MAKEFOURCC('d','a','t','a')) {
                pcm.resize(size);
                file.read(reinterpret_cast<char*>(pcm.data()), size);
            }
            if (!file) return false;
            file.seekg(start + static_cast<std::streamoff>(size + (size & 1)));
        }
        if (!(format.wFormatTag == WAVE_FORMAT_PCM && format.nChannels == 2 &&
              format.nSamplesPerSec == Rate && format.wBitsPerSample == 16 &&
              format.nBlockAlign == 4 && !pcm.empty() && pcm.size() % 4 == 0)) return false;
        const auto* s = reinterpret_cast<const int16_t*>(pcm.data());
        const UINT32 window = Rate / 100;
        double best = -1;
        for (UINT32 at = 0; at + window <= frames(); at += window / 2) {
            double e = 0;
            for (UINT32 i = at; i < at + window; ++i) e += double(s[2 * i]) * s[2 * i] + double(s[2 * i + 1]) * s[2 * i + 1];
            if (e > best) { best = e; peak = at + window / 2; }
        }
        // Looping: wrap 20 ms after the last moment above 3% of full level,
        // on a zero crossing, so the passes follow on without a long silence
        // or a click.
        int top = 1;
        for (UINT32 i = 0; i < frames() * 2; ++i) top = std::max(top, std::abs(int(s[i])));
        UINT32 end = frames();
        while (end > 0 && std::abs(int(s[2 * (end - 1)])) < top * 3 / 100 && std::abs(int(s[2 * (end - 1) + 1])) < top * 3 / 100) --end;
        end = std::min(frames(), end + Rate / 50);
        while (end < frames() && !(s[2 * (end - 1)] <= 0 && s[2 * end] >= 0)) ++end;
        loop_end = end;
        return true;
    }
};

struct Bank {
    std::vector<Clip> clips;
    int last = -1, before = -1;
    ULONGLONG last_play{};
    // Never the previous take; with four or more, not the one before either.
    const Clip& pick(std::mt19937& rng) {
        int n = static_cast<int>(clips.size()), choice = 0;
        if (n > 1) {
            std::uniform_int_distribution<int> any(0, n - 1);
            do choice = any(rng); while (choice == last || (n >= 4 && choice == before));
        }
        before = last; last = choice;
        return clips[choice];
    }
};

// Which bank each cue plays, whether it is a swing (timed to the strike and
// faded out when the strike lands) and the bank to fall back on.
struct Route { const char* bank; bool swing; float gain; const char* fallback; bool loop = false; };
const std::map<std::string, Route> routes = {
    {"whoosh",          {"whoosh",          true,  1.0f, nullptr}},
    {"switch",          {"whoosh",          true,  1.0f, nullptr}},
    {"heavy",           {"heavy",           true,  1.0f, "whoosh"}},
    {"finisher",        {"heavy",           true,  1.2f, "whoosh"}},
    {"impact",          {"impact",          false, 1.0f, nullptr}},
    {"impact_charged",  {"impact_charged",  false, 1.0f, "impact"}},
    {"heavy_impact",    {"heavy_impact",    false, 1.0f, "impact"}},
    {"finisher_impact", {"finisher_impact", false, 1.0f, "heavy_impact"}},
    {"windup",          {"windup",          true,  0.4f, nullptr}},
    {"recall_pull",     {"recall_pull",     true,  0.65f, nullptr}},
    // Timed like a swing: its loudest moment lands as the hammer leaves the hand.
    {"throw",           {"throw",           true,  1.0f, nullptr}},
    {"throw_impact",    {"throw_impact",    false, 1.0f, "heavy_impact"}},
    {"catch",           {"catch",           false, 1.0f, nullptr}},
    // The hammer in the air, out and back: throw #1's whoosh on a loop, its
    // first pass timed like the throw, until "fly_stop" (the catch) fades it out.
    {"fly",             {"throw",           true,  0.85f, nullptr, true}},
};
// Audio folders from before the banks: one fixed file per cue.
const std::map<std::wstring, std::string> legacy = {
    {L"Mjolnir_ApprovedWhoosh.wav", "whoosh"}, {L"Mjolnir_ApprovedTreeHit.wav", "impact"},
    {L"Mjolnir_HeavyWhoosh.wav", "heavy"}, {L"Mjolnir_HeavyImpact.wav", "heavy_impact"},
    {L"Mjolnir_ApprovedThrow.wav", "throw"},
};

class Playback {
    std::map<std::string, Bank> banks;
    ComPtr<IXAudio2> engine;
    IXAudio2MasteringVoice* output{};
    struct Voice {
        IXAudio2SourceVoice* source;
        float volume;
        bool swing;
        ULONGLONG start_at{};   // 0 once started; swings may wait for their moment
        ULONGLONG fade_start{};
        std::vector<BYTE> head; // faded-in first frames of a trimmed swing
        bool loop{};            // the flight loop: only "fly_stop" (or its time limit) ends it
        ULONGLONG born{};
        float pan = 0, gain = 1, pitch = 1;   // the flight loop, following the hammer
    };
    std::list<Voice> voices;
    std::mt19937 rng{static_cast<unsigned>(GetTickCount64())};
    static constexpr size_t MaxVoices = 24;
    static constexpr ULONGLONG FadeMs = 90;
    static constexpr ULONGLONG LoopLimitMs = 15000;   // a flight can never outlive this

    static void fade(Voice& v, ULONGLONG now) {
        if (v.fade_start) return;
        v.fade_start = v.start_at ? 1 : now;   // not started yet: drop it
    }
    void fade_swings(ULONGLONG now) {
        for (auto& v : voices) if (v.swing && !v.loop) fade(v, now);
    }
    bool looping() const {
        return std::any_of(voices.begin(), voices.end(), [](const Voice& v) { return v.loop && !v.fade_start; });
    }

    // The flight loop: the custom doppler loop (audio/fly_loop_01.wav, made
    // by Mimic.cpp to sound like throw #1: one doppler pass about every 0.6 s,
    // each a little different, seamless).  Played as it is, at its own pitch.
    struct Loop {
        Clip sound;             // the loop (its peak: the first pass, which times the release)
        double period{};        // seconds between passes
        std::string name;
    };
    std::vector<Loop> loops;
    static constexpr double LoopBeat = .24;   // seconds from one pass to the next in fly_loop_01.wav
    static Loop make_loop(const Clip& c) {
        Loop l;
        l.sound = c;
        l.name = c.name;
        l.period = LoopBeat;
        // The release is timed to the first pass, not the loudest of them all.
        const auto* s = reinterpret_cast<const int16_t*>(c.pcm.data());
        const UINT32 window = Rate / 100, first = std::min(c.frames(), static_cast<UINT32>(LoopBeat * Rate));
        double best = -1;
        for (UINT32 p = 0; p + window <= first; p += window / 2) {
            double e = 0;
            for (UINT32 i = p; i < p + window; ++i) e += double(s[2 * i]) * s[2 * i] + double(s[2 * i + 1]) * s[2 * i + 1];
            if (e > best) { best = e; l.sound.peak = p + window / 2; }
        }
        return l;
    }

    // Where the flying hammer is, from the script ("fly_pos <pan> <gain>
    // <pitch>": pan -1 left .. 1 right of the camera, gain from its distance,
    // pitch its slight doppler).  The flight loop glides toward these.
    UINT32 out_channels = 2;
    float follow_pan = 0, follow_gain = 1, follow_pitch = 1;
    ULONGLONG last_idle = 0;
    static constexpr float FollowTime = .06f;   // seconds to glide to a new position
    void place_voice(Voice& v, float fade_gain) {
        // Constant-power pan, the two sides kept a little apart (some width).
        const float angle = (v.pan + 1) * .785398163f;
        const float gl = std::cos(angle) * 1.41421356f, gr = std::sin(angle) * 1.41421356f;
        std::vector<float> m(size_t(2) * out_channels, 0.f);   // [dest][source]
        m[0] = gl * .8f; m[1] = gl * .2f;                       // front left  <- L, R
        if (out_channels > 1) { m[2] = gr * .2f; m[3] = gr * .8f; }   // front right <- L, R
        v.source->SetOutputMatrix(nullptr, 2, out_channels, m.data());
        v.source->SetVolume(v.volume * v.gain * fade_gain);
        v.source->SetFrequencyRatio(v.pitch);
    }
public:
    const std::vector<Loop>& flight_loops() const { return loops; }
    HRESULT result{S_OK};
    std::string inventory;
    ~Playback() {
        for (auto& voice : voices) voice.source->DestroyVoice();
        if (output) output->DestroyVoice();
    }
    bool open(const std::filesystem::path& folder) {
        std::error_code ec;
        for (std::filesystem::directory_iterator it(folder, ec), end; !ec && it != end; it.increment(ec)) {
            const auto path = it->path();
            if (path.extension() != L".wav") continue;
            std::string bank;
            if (auto l = legacy.find(path.filename().wstring()); l != legacy.end()) bank = l->second;
            else {
                const auto stem = path.stem().string();
                const auto cut = stem.find_last_of('_');
                if (cut == std::string::npos || cut + 1 == stem.size() ||
                    !std::all_of(stem.begin() + cut + 1, stem.end(), ::isdigit)) continue;
                bank = stem.substr(0, cut);
            }
            Clip clip;
            clip.name = path.stem().string();
            if (!clip.read(path)) { inventory += "bad " + path.filename().string() + "; "; continue; }
            banks[bank].clips.push_back(std::move(clip));
        }
        for (auto& [name, bank] : banks) inventory += name + " x" + std::to_string(bank.clips.size()) + " ";
        if (auto t = banks.find("fly_loop"); t != banks.end())
            for (const auto& c : t->second.clips) loops.push_back(make_loop(c));
        inventory += "fly loop x" + std::to_string(loops.size()) + " ";
        if (!banks.count("whoosh") || !banks.count("impact")) {
            result = HRESULT_FROM_WIN32(ERROR_INVALID_DATA);
            return false;
        }
        const HRESULT com = CoInitializeEx(nullptr, COINIT_MULTITHREADED);
        result = XAudio2Create(engine.GetAddressOf());
        if (SUCCEEDED(result))
            result = engine->CreateMasteringVoice(&output, XAUDIO2_DEFAULT_CHANNELS,
                XAUDIO2_DEFAULT_SAMPLERATE, 0, nullptr, nullptr, AudioCategory_GameEffects);
        if (SUCCEEDED(com)) CoUninitialize();
        if (SUCCEEDED(result)) { XAUDIO2_VOICE_DETAILS d{}; output->GetVoiceDetails(&d); out_channels = std::max<UINT32>(1, d.InputChannels); }
        return SUCCEEDED(result);
    }

    // Returns a short description for the log, or empty when nothing played.
    std::string play(const std::string& cue, double lead = 0, float gain = 1) {
        const auto now = GetTickCount64();
        if (cue == "fly_stop") {
            bool any = false;
            for (auto& v : voices) if (v.loop && !v.fade_start) { fade(v, now); any = true; }
            return any ? "fly_stop" : "fly_stop (nothing flying)";
        }
        const auto route = routes.find(cue);
        if (route == routes.end() || !output) return {};
        const bool loop = route->second.loop;
        if (loop && looping()) return "fly (already looping)";
        auto bank = banks.find(route->second.bank);
        if (bank == banks.end() && route->second.fallback) bank = banks.find(route->second.fallback);
        if (bank == banks.end() || bank->second.clips.empty()) return {};
        const bool swing = route->second.swing;
        // A burst of the same hit inside 35 ms is one event, not many.
        if (!swing && now - bank->second.last_play < 35) return {};
        bank->second.last_play = now;

        // The flight loop: one of the two circles, picked at random; its
        // opening take sets the timing of the first pass.
        const Loop* circle = nullptr;
        if (loop) {
            if (loops.empty()) return {};
            circle = &loops[std::uniform_int_distribution<size_t>(0, loops.size() - 1)(rng)];
        }
        const Clip& clip = circle ? circle->sound : bank->second.pick(rng);
        std::uniform_real_distribution<float> drift(-1, 1);
        const float ratio = loop ? 1.f : 1 + (swing ? .025f : .018f) * drift(rng);   // the loop keeps its own pitch
        const float volume = route->second.gain * gain * std::pow(10.f, drift(rng) / 20);

        // Swing timing: its loudest moment should land 30 ms before the
        // strike.  Trim the start when the swing is quicker than the clip;
        // hold it back when the windup is longer.
        UINT32 begin = 0; ULONGLONG start_at = 0;
        if (swing && lead > 0) {
            const double arrive = std::max(0.0, lead - .03) * Rate * ratio;
            if (clip.peak > arrive) begin = std::min<UINT32>(static_cast<UINT32>(clip.peak - arrive), clip.frames() * 6 / 10);
            else start_at = now + static_cast<ULONGLONG>((arrive - clip.peak) / (Rate * ratio) * 1000);
        }
        if (!swing) fade_swings(now);
        if (voices.size() >= MaxVoices) {
            // Make room with the oldest one-shot; never the flight loop.
            auto old = std::find_if(voices.begin(), voices.end(), [](const Voice& v) { return !v.loop; });
            if (old != voices.end()) { old->source->DestroyVoice(); voices.erase(old); }
        }

        IXAudio2SourceVoice* voice{};
        if (FAILED(engine->CreateSourceVoice(&voice, &clip.format))) return {};
        voices.push_back({voice, volume, swing && !loop, start_at, 0, {}, loop, now});
        auto& v = voices.back();
        if (loop) { v.pan = follow_pan; v.gain = follow_gain; v.pitch = follow_pitch; place_voice(v, 1); }
        // Starting mid-waveform would click: the first 4 ms of a trimmed
        // swing go out as their own faded copy, then the clip continues.
        const UINT32 fade = Rate / 250;
        bool ok = SUCCEEDED(voice->SetFrequencyRatio(ratio)) && SUCCEEDED(voice->SetVolume(volume));
        if (ok && begin > 0 && begin + fade < clip.frames()) {
            v.head.assign(clip.pcm.begin() + begin * 4, clip.pcm.begin() + (begin + fade) * 4);
            auto* s = reinterpret_cast<int16_t*>(v.head.data());
            for (UINT32 i = 0; i < fade; ++i) {
                const float g = (i + .5f) / fade;
                s[2 * i] = static_cast<int16_t>(s[2 * i] * g);
                s[2 * i + 1] = static_cast<int16_t>(s[2 * i + 1] * g);
            }
            XAUDIO2_BUFFER head{};
            head.AudioBytes = fade * 4;
            head.pAudioData = v.head.data();
            ok = SUCCEEDED(voice->SubmitSourceBuffer(&head));
            begin += fade;
        }
        XAUDIO2_BUFFER buffer{};
        buffer.Flags = XAUDIO2_END_OF_STREAM;
        buffer.AudioBytes = static_cast<UINT32>(clip.pcm.size());
        buffer.pAudioData = clip.pcm.data();
        buffer.PlayBegin = begin;
        if (loop) {
            // From where the timing put it to the end of the circle, then the
            // circle over and over until it is faded out.
            XAUDIO2_BUFFER rest{};
            rest.AudioBytes = static_cast<UINT32>(clip.pcm.size());
            rest.pAudioData = clip.pcm.data();
            rest.PlayBegin = std::min(begin, clip.frames() - 1);
            rest.PlayLength = clip.frames() - rest.PlayBegin;
            if (ok) ok = SUCCEEDED(voice->SubmitSourceBuffer(&rest));
            buffer.PlayBegin = 0;
            buffer.LoopCount = XAUDIO2_LOOP_INFINITE;
        }
        if (!ok || FAILED(voice->SubmitSourceBuffer(&buffer)) || (!start_at && FAILED(voice->Start()))) {
            voice->DestroyVoice();
            voices.pop_back();
            return {};
        }
        std::ostringstream out;
        if (loop) out << cue << ' ' << circle->name << " loop " << clip.frames() / double(Rate) << "s, a pass every " << circle->period << 's';
        else out << cue << " #" << (bank->second.last + 1) << '/' << bank->second.clips.size();
        if (swing && lead > 0) out << " lead=" << lead << (start_at ? " held=" : " trimmed=")
                                   << (start_at ? (start_at - now) / 1000.0 : begin / double(Rate)) << 's';
        return out.str();
    }

    // The hammer moved: where the flight loop should glide to.
    void follow(float pan, float gain, float pitch) {
        follow_pan = std::clamp(pan, -1.f, 1.f);
        follow_gain = std::clamp(gain, 0.f, 1.5f);
        follow_pitch = std::clamp(pitch, .9f, 1.1f);
    }

    bool idle() {
        const auto now = GetTickCount64();
        const float dt = last_idle ? std::min(.1f, (now - last_idle) / 1000.f) : 0.f;
        last_idle = now;
        const float glide = dt > 0 ? 1 - std::exp(-dt / FollowTime) : 0.f;
        voices.remove_if([&](Voice& v) {
            if (v.loop && now - v.born > LoopLimitMs) fade(v, now);   // its stop never came
            if (v.loop && !v.start_at && glide > 0) {
                v.pan += (follow_pan - v.pan) * glide;
                v.gain += (follow_gain - v.gain) * glide;
                v.pitch += (follow_pitch - v.pitch) * glide;
                if (!v.fade_start) place_voice(v, 1);
            }
            if (v.start_at) {
                if (v.fade_start) { v.source->DestroyVoice(); return true; }   // its strike came first
                if (now < v.start_at) return false;
                v.start_at = 0; v.source->Start();
                return false;
            }
            XAUDIO2_VOICE_STATE state{};
            v.source->GetState(&state, XAUDIO2_VOICE_NOSAMPLESPLAYED);
            const bool faded = v.fade_start && now - v.fade_start >= FadeMs;
            if (state.BuffersQueued && !faded) {
                if (v.fade_start) {
                    const float angle = std::min(1.0f, (now - v.fade_start) / float(FadeMs)) * 1.57079633f;
                    v.source->SetVolume(v.volume * v.gain * std::cos(angle));
                }
                return false;
            }
            v.source->DestroyVoice();
            return true;
        });
        return voices.empty();
    }
};
}

#ifdef MJOLNIR_AUDIO_SMOKE
// ApprovedAudioSmoke <audio folder> [whoosh|heavy|throw|windup|recall|all]
// Plays the cues as the game would and fails if a bank is missing or a
// voice cannot start.  "all" plays every take of every bank once.
int wmain(int argc, wchar_t** argv) {
    Playback playback;
    if (argc < 2 || !playback.open(argv[1])) {
        std::cerr << "Audio startup failed: 0x" << std::hex << playback.result << '\n';
        return 1;
    }
    std::cout << "banks: " << playback.inventory << '\n';
    const std::wstring mode = argc > 2 ? argv[2] : L"whoosh";
    // export <folder>: each flight loop, four times round, as a wav to listen
    // to; and the largest sample step at its wrap against anywhere inside.
    if (mode == L"export" && argc > 3) {
        for (const auto& loop : playback.flight_loops()) {
            const auto& pcm = loop.sound.pcm;
            const UINT32 frames = loop.sound.frames();
            const auto* s = reinterpret_cast<const int16_t*>(pcm.data());
            int inside = 0;
            for (UINT32 i = 1; i < frames; ++i) inside = std::max(inside, std::abs(s[2 * i] - s[2 * i - 2]));
            const int wrap = std::abs(s[0] - s[2 * (frames - 1)]);
            // How even the loudness is: quietest and loudest 50 ms, in dB.
            double lo = 1e18, hi = 0;
            for (UINT32 at = 0; at + Rate / 20 <= frames; at += Rate / 20) {
                double e = 0;
                for (UINT32 i = at; i < at + Rate / 20; ++i) e += double(s[2 * i]) * s[2 * i];
                lo = std::min(lo, e); hi = std::max(hi, e);
            }
            std::cout << loop.name << ": " << frames / double(Rate) << "s, wrap step " << wrap << " (largest inside " << inside
                      << "), loudness range " << 10 * std::log10(hi / std::max(1.0, lo)) << " dB\n";
            std::ofstream f(std::filesystem::path(argv[3]) / ("fly_loop_" + loop.name + ".wav"), std::ios::binary);
            const DWORD bytes = static_cast<DWORD>(pcm.size() * 4);
            auto put = [&](DWORD v, int n) { f.write(reinterpret_cast<const char*>(&v), n); };
            f.write("RIFF", 4); put(36 + bytes, 4); f.write("WAVEfmt ", 8); put(16, 4);
            put(1, 2); put(2, 2); put(Rate, 4); put(Rate * 4, 4); put(4, 2); put(16, 2);
            f.write("data", 4); put(bytes, 4);
            for (int k = 0; k < 4; ++k) f.write(reinterpret_cast<const char*>(pcm.data()), pcm.size());
        }
        return 0;
    }
    // follow: the flight loop swept from far left to far right and back, near
    // and far, as the script would send it while the hammer flies.
    if (mode == L"follow") {
        const auto start = playback.play("fly", .17);
        if (start.empty()) { std::cerr << "FAILED cue fly\n"; return 2; }
        std::cout << "  " << start << '\n';
        for (int t = 0; t <= 3000; t += 10) {
            if (t % 50 == 0) {
                const float x = std::sin(t / 3000.f * 6.2831853f);
                playback.follow(x, .45f + .55f * std::abs(std::cos(t / 3000.f * 3.1415926f)), 1 - .03f * x);
            }
            playback.idle(); Sleep(10);
        }
        std::cout << "  " << playback.play("fly_stop") << '\n';
        for (int i = 0; i < 400; ++i) { if (playback.idle()) { std::cout << "PASS: the flight loop followed 60 positions and stopped.\n"; return 0; } Sleep(10); }
        return 3;
    }
    struct Step { const char* cue; double lead; int wait_ms; };
    std::vector<Step> steps;
    if (mode == L"heavy") steps = {{"heavy", .21, 210}, {"heavy_impact", 0, 600}, {"finisher", .22, 220}, {"finisher_impact", 0, 0}};
    else if (mode == L"windup") steps = {{"windup", 0, 40}, {"throw", .17, 0}};
    else if (mode == L"recall") steps = {{"recall_pull", 0, 250}, {"catch", 0, 0}};
    else if (mode == L"throw") steps = {{"fly", .17, 550}, {"throw_impact", 0, 1200}, {"fly", 0, 300}, {"fly_stop", 0, 0}, {"catch", 0, 0}};
    else if (mode == L"all") {
        for (const std::string cue : {"whoosh", "impact", "impact_charged", "heavy", "heavy_impact", "finisher_impact", "throw", "throw_impact", "catch"}) {
            const bool swing = cue == "whoosh" || cue == "heavy";
            for (int i = 0; i < 8; ++i) steps.push_back({routes.find(cue)->first.c_str(), swing ? .2 : 0, 240});
        }
    }
    else steps = {{"whoosh", .19, 190}, {"impact", 0, 420}, {"whoosh", .28, 280}, {"impact_charged", 0, 0}};
    int played = 0;
    for (const auto& s : steps) {
        const auto what = playback.play(s.cue, s.lead);
        if (what.empty()) { std::cerr << "FAILED cue " << s.cue << '\n'; return 2; }
        std::cout << "  " << what << '\n'; ++played;
        for (int t = 0; t < s.wait_ms; t += 10) { playback.idle(); Sleep(10); }
    }
    for (int i = 0; i < 400; ++i) {
        if (playback.idle()) {
            std::cout << "PASS: " << played << " cues reached end of playback on the default audio output.\n";
            return 0;
        }
        Sleep(10);
    }
    return 3;
}
#else
namespace {
class ApprovedAudio final : public RC::CppUserModBase {
    std::filesystem::path root;
    Playback playback;
    bool attempted{};
    bool ready{};
    ULONGLONG next_poll{};
    void log(const std::string& message) {
        std::ofstream(root / L"approved_audio.log", std::ios::app) << message << '\n';
    }
public:
    ApprovedAudio() {
        ModName = L"MjolnirApprovedAudio";
        ModVersion = L"2.0";
        wchar_t filename[MAX_PATH]{};
        GetModuleFileNameW(reinterpret_cast<HMODULE>(&__ImageBase), filename, MAX_PATH);
        root = std::filesystem::path(filename).parent_path().parent_path();
    }
    void on_update() override {
        const auto now = GetTickCount64();
        if (ready) playback.idle();   // every frame, so held swings start on time
        if (now < next_poll) return;
        next_poll = now + 5;
        const auto queue = root / L"queue";
        if (!attempted) {
            attempted = true;
            std::error_code ec;
            std::filesystem::create_directories(queue, ec);
            ready = !ec && playback.open(root / L"audio");
            log(ready ? "READY: XAudio2 output opened; banks: " + playback.inventory
                      : "ERROR: audio initialization " + std::to_string(playback.result) + "; " + playback.inventory);
        }
        if (!ready) return;
        std::error_code ec;
        std::vector<std::filesystem::path> pending;
        for (std::filesystem::directory_iterator it(queue, ec), end; !ec && it != end; it.increment(ec))
            if (it->path().extension() == L".cue") pending.push_back(it->path());
        std::sort(pending.begin(), pending.end());
        for (const auto& path : pending) {
            const auto modified = std::filesystem::last_write_time(path, ec);
            const bool fresh = !ec && std::filesystem::file_time_type::clock::now() - modified < std::chrono::seconds(2);
            std::ifstream file(path);
            std::string line;
            std::getline(file, line);
            file.close();
            std::filesystem::remove(path, ec);
            if (!fresh || ec) continue;
            std::istringstream fields(line);
            std::string cue, lead_text, gain_text;
            fields >> cue;
            if (cue == "fly_pos") {   // the flying hammer moved (many a second: not logged)
                float pan = 0, level = 1, pitch = 1;
                fields >> pan >> level >> pitch;
                if (fields) playback.follow(pan, level, pitch);
                continue;
            }
            fields >> lead_text >> gain_text;
            const double lead = lead_text.empty() ? 0 : std::clamp(std::strtod(lead_text.c_str(), nullptr), 0.0, 2.0);
            const float gain = gain_text.empty() ? 1.f : std::clamp(static_cast<float>(std::strtod(gain_text.c_str(), nullptr)), 0.f, 2.f);
            const auto what = playback.play(cue, lead, gain);
            log(what.empty() ? "SKIPPED: " + line : "PLAYING: " + what);
        }
    }
};
}

extern "C" {
__declspec(dllexport) RC::CppUserModBase* start_mod() { return new ApprovedAudio(); }
__declspec(dllexport) void uninstall_mod(RC::CppUserModBase* mod) { delete mod; }
}
#endif

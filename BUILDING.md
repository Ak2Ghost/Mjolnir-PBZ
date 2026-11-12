# Mjolnir for Phantom Blade Zero - source

Source for every compiled file shipped with the Mjolnir mod, and how to build each one.
The mod's game content (paks) and Lua scripts are data/scripts and need no build.

| Shipped file | Source here | Build |
| --- | --- | --- |
| `MjolnirApprovedAudio/dlls/main.dll` (sound add-on) | `audio/ApprovedAudio.cpp`, `audio/UE4SSCppBase.def` | see 1 |
| `MjolnirUpdater/tools/PBZEdit/PBZEdit.exe` | `pbzedit/` | see 2 |
| `MjolnirUpdater/tools/pack_menu_text/pack_menu_text.exe` | `pack_menu_text/` | see 3 |
| `MjolnirUpdater/tools/retoc/retoc-pbz.exe` | upstream retoc + `retoc/partitioned-ucas.patch` | see 4 |
| `MjolnirUpdater/tools/update_mjolnir.ps1`, `*.bat` | `updater/` (plain script, no build) | - |
| `MjolnirMod/Scripts/*.lua` | `lua/` (plain script, no build) | - |

## 1. Sound add-on (main.dll)
A UE4SS C++ mod that plays the hammer's WAV files with XAudio2. The Lua mod drops small
"cue" text files into `MjolnirApprovedAudio/queue/`; the DLL picks a WAV from `audio/` and plays it.
It only reads its own `audio/` and `queue/` folders and writes `approved_audio.log`.
Requires Visual Studio 2022+ (x64 Native Tools prompt):

    lib /def:UE4SSCppBase.def /machine:x64 /out:UE4SSCppBase.lib
    cl /nologo /std:c++17 /EHsc /O2 /MT /LD ApprovedAudio.cpp /Fe:main.dll UE4SSCppBase.lib xaudio2.lib ole32.lib

`UE4SSCppBase.def` only declares the two `CppUserModBase` constructor/destructor exports of UE4SS.dll (v3.0.1).

## 2. PBZEdit.exe (updater tool)
C# (.NET 10). Edits Unreal assets with UAssetAPI 1.1.0 and reads the game's files with CUE4Parse.
The updater uses: `extract` (read Game.locres from the installed game), `rowdiff` / `locres diff` (find the rows and text
entries another installed mod adds or changes), `transplant` (copy rows into the game's current DataTables) and
`locres merge` (add text entries). It needs `PBZ.usmap`
(the game's type mappings, dumped with UE4SS) next to the exe.

    dotnet publish pbzedit/PBZEdit.csproj -c Release -r win-x64 --self-contained true -p:PublishSingleFile=true -p:IncludeNativeLibrariesForSelfExtract=true -p:DebugType=none

## 3. pack_menu_text.exe (updater tool)
Rust. Writes the mod's English text into a v11 .pak with repak.

    cd pack_menu_text && cargo build --release

## 4. retoc-pbz.exe (updater tool)
retoc by trumank (MIT, https://github.com/trumank/retoc), commit 885a8dae740cb1ce1e41ff2e74f67f9f0c118237,
with one patch that lets it read containers split into several .ucas files (`name_s1.ucas`, ...), which
Phantom Blade Zero uses.

    git clone https://github.com/trumank/retoc && cd retoc
    git checkout 885a8dae740cb1ce1e41ff2e74f67f9f0c118237
    git apply ../partitioned-ucas.patch
    cargo build --release      (output: target/release/retoc.exe, shipped as retoc-pbz.exe)

On first use retoc downloads Epic's Oodle library (oo2core_9_win64.dll) from
https://github.com/WorkingRobot/OodleUE next to itself; that is the updater's only network access.

## What the updater does
`update_mjolnir.ps1` (read it, it is plain PowerShell): reads three DataTables and Game.locres from the
installed game's own containers (never from ~mods), adds Mjolnir's rows/text, packs `zz_Mjolnir_P` with
retoc, verifies it, backs up the old files into `MjolnirUpdater/backup/` and installs into
`ProjectPBZ/Content/Paks/~mods/`. It writes nothing else.

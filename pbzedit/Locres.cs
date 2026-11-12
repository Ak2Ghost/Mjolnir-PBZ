// Unreal localization resource (.locres) reader/writer, version 3
// ("Optimized_CityHash64_UTF16"): namespaces -> keys -> (source hash, string index), plus a shared string
// table with reference counts.  Key/namespace hashes are CityHash64 of the UTF-16 text folded to 32 bits
// (TextKeyUtil::HashString); source hashes are FCrc::StrCrc32 of the source string.  Check() recomputes
// every stored key hash so a wrong hash can never be written unnoticed.
using System.Text;

public sealed class Locres
{
    static readonly byte[] Magic = { 0x0E, 0x14, 0x74, 0x75, 0x67, 0x4A, 0x03, 0xFC, 0x4A, 0x15, 0x90, 0x9D, 0xC3, 0x37, 0x7F, 0x1B };
    public sealed class Entry { public string Key = ""; public uint KeyHash; public uint SourceHash; public string Text = ""; }
    public sealed class Space { public string Name = ""; public uint Hash; public List<Entry> Entries = new(); }
    public List<Space> Spaces = new();

    public static Locres Read(string path)
    {
        using var r = new BinaryReader(File.OpenRead(path));
        if (!r.ReadBytes(16).SequenceEqual(Magic)) throw new Exception("not a .locres (magic)");
        int version = r.ReadByte(); if (version != 3) throw new Exception($"locres version {version}; only 3 is supported");
        long stringsAt = r.ReadInt64();
        long back = r.BaseStream.Position;
        r.BaseStream.Position = stringsAt;
        int n = r.ReadInt32(); var strings = new string[n];
        for (int i = 0; i < n; i++) { strings[i] = ReadF(r); r.ReadInt32(); }
        r.BaseStream.Position = back;
        r.ReadUInt32();   // entry count
        var res = new Locres();
        uint spaces = r.ReadUInt32();
        for (uint s = 0; s < spaces; s++)
        {
            var sp = new Space { Hash = r.ReadUInt32(), Name = ReadF(r) };
            uint keys = r.ReadUInt32();
            for (uint k = 0; k < keys; k++)
            {
                var e = new Entry { KeyHash = r.ReadUInt32(), Key = ReadF(r), SourceHash = r.ReadUInt32() };
                e.Text = strings[r.ReadInt32()];
                sp.Entries.Add(e);
            }
            res.Spaces.Add(sp);
        }
        return res;
    }

    public void Write(string path)
    {
        var table = new List<string>(); var index = new Dictionary<string, int>(StringComparer.Ordinal); var refs = new List<int>();
        int Intern(string t) { if (!index.TryGetValue(t, out var i)) { i = table.Count; index[t] = i; table.Add(t); refs.Add(0); } refs[i]++; return i; }
        using var ms = new MemoryStream(); using var w = new BinaryWriter(ms);
        w.Write(Magic); w.Write((byte)3);
        long offsetAt = ms.Position; w.Write(0L);
        w.Write((uint)Spaces.Sum(s => s.Entries.Count));
        w.Write((uint)Spaces.Count);
        foreach (var sp in Spaces)
        {
            w.Write(sp.Hash); WriteF(w, sp.Name); w.Write((uint)sp.Entries.Count);
            foreach (var e in sp.Entries) { w.Write(e.KeyHash); WriteF(w, e.Key); w.Write(e.SourceHash); w.Write(Intern(e.Text)); }
        }
        long stringsAt = ms.Position;
        w.Write(table.Count);
        for (int i = 0; i < table.Count; i++) { WriteF(w, table[i]); w.Write(refs[i]); }
        ms.Position = offsetAt; w.Write(stringsAt);
        Directory.CreateDirectory(Path.GetDirectoryName(Path.GetFullPath(path))!);
        File.WriteAllBytes(path, ms.ToArray());
    }

    // Adds or replaces an entry; the source hash is that of the text itself (it has no other source).
    public void Set(string space, string key, string text)
    {
        var sp = Spaces.FirstOrDefault(s => s.Name == space);
        if (sp == null) { sp = new Space { Name = space, Hash = HashString(space) }; Spaces.Add(sp); }
        var e = sp.Entries.FirstOrDefault(x => x.Key == key);
        if (e == null) { e = new Entry { Key = key, KeyHash = HashString(key) }; sp.Entries.Add(e); }
        // In this game every entry's source string is its key (all 11142 stock entries: StrCrc32(key)).
        e.Text = text; e.SourceHash = StrCrc32(key);
    }

    // (namespace hashes wrong, key or source hashes wrong) out of all entries
    public (int spaces, int keys, int total) Check()
    {
        int bs = Spaces.Count(s => s.Hash != HashString(s.Name));
        int bk = Spaces.Sum(s => s.Entries.Count(e => e.KeyHash != HashString(e.Key) || e.SourceHash != StrCrc32(e.Key)));
        return (bs, bk, Spaces.Sum(s => s.Entries.Count));
    }

    static string ReadF(BinaryReader r)
    {
        int len = r.ReadInt32();
        if (len == 0) return "";
        if (len > 0) { var b = r.ReadBytes(len); return Encoding.Latin1.GetString(b, 0, len - 1); }
        var u = r.ReadBytes(-len * 2); return Encoding.Unicode.GetString(u, 0, (-len - 1) * 2);
    }
    static void WriteF(BinaryWriter w, string s)
    {
        if (s.Length == 0) { w.Write(0); return; }
        if (s.All(c => c < 128)) { w.Write(s.Length + 1); w.Write(Encoding.ASCII.GetBytes(s)); w.Write((byte)0); }
        else { w.Write(-(s.Length + 1)); w.Write(Encoding.Unicode.GetBytes(s)); w.Write((ushort)0); }
    }

    // ---- hashes ----------------------------------------------------------------------------------------
    public static uint HashString(string s)
    {
        ulong h = CityHash64(Encoding.Unicode.GetBytes(s));
        return unchecked((uint)h + (uint)(h >> 32) * 23u);
    }
    // CUE4Parse's CityHash64, which matches the engine (a hand port of CityHash 1.1 got the 17-32 and 65+
    // byte cases wrong for this game's keys).
    // (CUE4Parse rejects an empty buffer; CityHash64 of nothing is the constant k2.)
    public static ulong CityHash64(byte[] s) => s.Length == 0 ? 0x9ae16a3b2f90404fUL : CUE4Parse.Utils.CityHash.CityHash64(s);
    static readonly uint[] Crc = MakeCrc();
    static uint[] MakeCrc()
    {
        var t = new uint[256];
        for (uint i = 0; i < 256; i++) { uint c = i; for (int k = 0; k < 8; k++) c = (c & 1) != 0 ? 0xEDB88320u ^ (c >> 1) : c >> 1; t[i] = c; }
        return t;
    }
    // FCrc::StrCrc32: each character fed as four bytes, low byte first.
    public static uint StrCrc32(string s)
    {
        uint crc = ~0u;
        foreach (char ch in s) { uint c = ch; for (int i = 0; i < 4; i++) { crc = (crc >> 8) ^ Crc[(crc ^ c) & 0xFF]; c >>= 8; } }
        return ~crc;
    }
}

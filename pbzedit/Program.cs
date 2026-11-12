// Edits legacy (.uasset/.uexp) copies of game assets produced by retoc to-legacy.
// Usage: PBZEdit info <file.uasset>          print imports, exports and top-level properties
//        PBZEdit roundtrip <in> <out>        load and re-save unchanged (sanity check)
//        PBZEdit names <file.uasset> [filter] list the name map (optionally only entries containing filter)
//        PBZEdit clone <in> <out> old=new [old=new ...]
//                                            copy an asset under a new name: each old=new is a substring replacement
//                                            applied in order to every name-map entry and to the package path;
//                                            ^old=new replaces only names that equal old exactly
//        PBZEdit addrow <table.uasset> <out> <srcRow> <newRow> field=value [field=value ...]
//                                            clone a DataTable row under a new name and set fields on the copy:
//                                            soft object fields take /Package/Path.AssetName, name fields take a name
//        PBZEdit setsocket <in> <out> "Socket Name=x,y,z" [...]
//                                            move skeleton/mesh sockets (SkeletalMeshSocket exports) to new relative locations
using UAssetAPI;
using UAssetAPI.PropertyTypes.Structs;
using UAssetAPI.UnrealTypes;
using UAssetAPI.PropertyTypes.Objects;
using UAssetAPI.PropertyTypes.Structs;
using UAssetAPI.ExportTypes;
using UAssetAPI.Unversioned;
using UAssetAPI.UnrealTypes;

// A FlowLocText (Namespace, Key, ValueCache) written the way every working stock field is: the key set and the
// cached text EMPTY (history None).  The game's text library resolves the key only when the cache is empty;
// a filled cache (what this tool wrote before 2026-11-06) showed blank in game.
static void LocKey(StructPropertyData st, string key)
{
    st.Value.OfType<StrPropertyData>().First(m => m.Name.Value.Value == "Key").Value = new FString(key);
    var cache = st.Value.OfType<TextPropertyData>().First(m => m.Name.Value.Value == "ValueCache");
    cache.HistoryType = TextHistoryType.None;
    cache.Namespace = null; cache.Value = null; cache.CultureInvariantString = null;
}
// Portable: PBZ_USMAP, else PBZ.usmap next to this exe, else the original dev path.
string Mappings = Environment.GetEnvironmentVariable("PBZ_USMAP") is { Length: > 0 } envMap ? envMap
    : File.Exists(Path.Combine(AppContext.BaseDirectory, "PBZ.usmap")) ? Path.Combine(AppContext.BaseDirectory, "PBZ.usmap")
    : @"B:\steam\steamapps\common\PBZ\ModWork\Mappings\PBZ.usmap";

// extract <Content\Paks dir> <aes key> <oodle dll> <out dir> <regex>...: save raw game files (e.g. Game.locres)
// from the game's own containers (top folder only, so ~mods is never read) at their game paths.
if (args.Length > 0 && args[0] == "extract")
{
    CUE4Parse.Compression.OodleHelper.Initialize(args[3]);
    var provider = new CUE4Parse.FileProvider.DefaultFileProvider(new DirectoryInfo(args[1]), SearchOption.TopDirectoryOnly, true,
        new CUE4Parse.UE4.Versions.VersionContainer(CUE4Parse.UE4.Versions.EGame.GAME_UE5_7));
    provider.Initialize();
    provider.SubmitKey(new CUE4Parse.UE4.Objects.Core.Misc.FGuid(), new CUE4Parse.Encryption.Aes.FAesKey(args[2]));
    provider.PostMount();
    var rx = args.Skip(5).Select(p => new System.Text.RegularExpressions.Regex(p, System.Text.RegularExpressions.RegexOptions.IgnoreCase)).ToList();
    var hits = provider.Files.Keys.Where(k => rx.Any(r => r.IsMatch(k))).ToList();
    if (hits.Count == 0) { Console.WriteLine("no game file matched"); return 2; }
    foreach (var h in hits)
    {
        var bytes = provider.SaveAsset(h);
        var target = Path.Combine(args[4], h.Replace('/', Path.DirectorySeparatorChar));
        Directory.CreateDirectory(Path.GetDirectoryName(target)!);
        File.WriteAllBytes(target, bytes);
        Console.WriteLine($"extracted {h} ({bytes.Length} bytes)");
    }
    return 0;
}
if (args.Length < 2) { Console.WriteLine("usage: PBZEdit info|roundtrip <file> [out]"); return 1; }
var usmap = new Usmap(Mappings);
if(args[0]=="mappings"){
    System.IO.File.WriteAllText(args[1],Newtonsoft.Json.JsonConvert.SerializeObject(usmap,Newtonsoft.Json.Formatting.Indented));return 0;
}
if(args[0]=="locres"){
    // locres check <file> | dump <file> [filter] | roundtrip <in> <out> | set <in> <out> <namespace> key=value|@file ...
    var lr=Locres.Read(args[2]);
    switch(args[1]){
        case "check":{var (s,k,t)=lr.Check();Console.WriteLine($"{t} entries in {lr.Spaces.Count} namespace(s) [{string.Join(", ",lr.Spaces.Select(x=>"\""+x.Name+"\""))}]; wrong hashes: {s} namespace(s), {k} key(s)");return s+k==0?0:3;}
        case "hashlens":{   // which UTF-16 byte lengths hash wrong (debugging the hash)
            var g=lr.Spaces.SelectMany(s=>s.Entries).GroupBy(e=>{int b=e.Key.Length*2;return b<=16?"0-16":b<=32?"17-32":b<=64?"33-64":"65+";});
            foreach(var x in g.OrderBy(x=>x.Key))Console.WriteLine($"{x.Key}: {x.Count(e=>e.KeyHash!=Locres.HashString(e.Key))} wrong of {x.Count()}");
            return 0;}
        case "dump":{foreach(var sp in lr.Spaces)foreach(var e in sp.Entries)if(args.Length<4||e.Key.Contains(args[3],StringComparison.OrdinalIgnoreCase)||e.Text.Contains(args[3],StringComparison.OrdinalIgnoreCase))Console.WriteLine($"[{sp.Name}] {e.Key} = {e.Text}");return 0;}
        case "roundtrip":{lr.Write(args[3]);bool same=File.ReadAllBytes(args[2]).SequenceEqual(File.ReadAllBytes(args[3]));Console.WriteLine(same?"byte-identical":"DIFFERS");return same?0:4;}
        case "diff":{ // diff <base> <mod.locres> <out list>: keys the mod adds or changes (namespace|key per line)
            var mod=Locres.Read(args[3]);var have=new Dictionary<string,string>();
            foreach(var sp in lr.Spaces)foreach(var e in sp.Entries)have[sp.Name+"|"+e.Key]=e.Text;
            var outl=new List<string>();
            foreach(var sp in mod.Spaces)foreach(var e in sp.Entries)if(!have.TryGetValue(sp.Name+"|"+e.Key,out var t)||t!=e.Text)outl.Add(sp.Name+"|"+e.Key);
            File.WriteAllLines(args[4],outl,new System.Text.UTF8Encoding(false));Console.WriteLine($"{outl.Count} text entr(ies) added or changed by the mod");return 0;}
        case "merge":{ // merge <stock> <out> <mod.locres> <key|prefix*|@list>...: copy matching entries from the mod file
            var src=Locres.Read(args[4]);int n=0;
            var exact=new HashSet<string>();var pats=new List<string>();
            foreach(var a in args.Skip(5)){if(a.StartsWith('@')){foreach(var l in File.ReadAllLines(a[1..],System.Text.Encoding.UTF8))if(l.Length>0)exact.Add(l);}else pats.Add(a);}
            foreach(var sp in src.Spaces)foreach(var e in sp.Entries)
                if(exact.Contains(sp.Name+"|"+e.Key)||pats.Any(p=>p.EndsWith('*')?e.Key.StartsWith(p[..^1],StringComparison.Ordinal):e.Key==p)){lr.Set(sp.Name,e.Key,e.Text);n++;}
            if(n==0&&exact.Count==0)throw new Exception("no matching entries in the mod language file");
            lr.Write(args[3]);var (ms,mk,mt)=lr.Check();Console.WriteLine($"merged {n} entries; wrote {mt} entries -> {args[3]}");return ms+mk==0?0:3;}
        case "set":{
            foreach(var spec in args.Skip(5)){
                var (key,val)=(spec[..spec.IndexOf('=')],spec[(spec.IndexOf('=')+1)..]);
                if(val.StartsWith('@'))val=File.ReadAllText(val[1..],System.Text.Encoding.UTF8).Trim();
                lr.Set(args[4],key,val);Console.WriteLine($"  [{args[4]}] {key} = {val}");
            }
            lr.Write(args[3]);var (s,k,t)=lr.Check();Console.WriteLine($"wrote {t} entries -> {args[3]}");return s+k==0?0:3;}
    }
    throw new Exception("locres: check|dump|roundtrip|set|diff|merge");
}
if(args[0]=="findprop"){
    // findprop <PropName>: the usmap classes/structs that declare a property of that name
    foreach(var s in usmap.Schemas.Values)
        foreach(var p in s.Properties.Values)
            if(p.Name==args[1])Console.WriteLine($"{s.Name} (super {s.SuperType}) : {p.PropertyData.Type}");
    return 0;
}
if(args[0]=="fromjson"){
    var decoded=UAsset.DeserializeJson(System.IO.File.ReadAllText(args[1]));
    decoded.SetEngineVersion(EngineVersion.VER_UE5_7);
    decoded.Mappings=usmap;
    decoded.Write(args[2]);return 0;
}
var asset = new UAsset(args[1], EngineVersion.VER_UE5_7, usmap);

switch (args[0])
{
    case "rowdiff":
    {
        // rowdiff <base table.uasset> <mod table.uasset> <out list.txt>: names of rows the mod adds or changes
        static Dictionary<string, Newtonsoft.Json.Linq.JToken> Rows(UAsset a)
        {
            var j = Newtonsoft.Json.Linq.JObject.Parse(a.SerializeJson(false));
            var d = new Dictionary<string, Newtonsoft.Json.Linq.JToken>();
            foreach (var e in j["Exports"]!) { var data = e["Table"]?["Data"]; if (data == null) continue; foreach (var r in data) d[(string)r["Name"]!] = r; }
            return d;
        }
        var modAsset = new UAsset(args[2], EngineVersion.VER_UE5_7, usmap);
        var b = Rows(asset); var m = Rows(modAsset);
        var changed = m.Where(kv => !b.TryGetValue(kv.Key, out var bv) || !Newtonsoft.Json.Linq.JToken.DeepEquals(bv, kv.Value)).Select(kv => kv.Key).ToList();
        File.WriteAllLines(args[3], changed, new System.Text.UTF8Encoding(false));
        Console.WriteLine($"{changed.Count} row(s) added or changed by the mod ({m.Count} rows in its table, {b.Count} in the game's)");
        return 0;
    }
    case "transplant":
    {
        // transplant <fresh table.uasset> <out.uasset> <mod table.uasset> <row|prefix*> [...]
        // Copies rows from the mod's copy of a DataTable into a fresh copy of the game's table (after a patch),
        // re-binding every name and import to the fresh file.  An existing row of the same name is replaced.
        var srcAsset = new UAsset(args[3], EngineVersion.VER_UE5_7, usmap);
        var dstTable = asset.Exports.OfType<DataTableExport>().FirstOrDefault() ?? throw new Exception("fresh file has no DataTable");
        var srcTable = srcAsset.Exports.OfType<DataTableExport>().FirstOrDefault() ?? throw new Exception("mod file has no DataTable");
        var dstRows = dstTable.Table.Data; var srcRows = srcTable.Table.Data;
        // the row struct must be the same type in both files, or the patch changed the table's layout
        string RowType(DataTableExport t) => t.Table.Data.FirstOrDefault()?.StructType?.ToString() ?? "?";
        if (dstRows.Count > 0 && srcRows.Count > 0 && RowType(dstTable) != RowType(srcTable))
            throw new Exception($"row type changed: game {RowType(dstTable)}, mod {RowType(srcTable)}");
        var wanted = new List<StructPropertyData>();
        var specs = args.Skip(4).SelectMany(a => a.StartsWith('@')
            ? File.ReadAllLines(a[1..], System.Text.Encoding.UTF8).Where(l => l.Length > 0).Select(l => "=" + l)
            : new[] { a }).ToList();
        if (specs.Count == 0) { Console.WriteLine("nothing to transplant"); if (Path.GetFullPath(args[1]) != Path.GetFullPath(args[2])) { File.Copy(args[1], args[2], true); File.Copy(Path.ChangeExtension(args[1], ".uexp"), Path.ChangeExtension(args[2], ".uexp"), true); } return 0; }
        foreach (var spec0 in specs)
        {
            bool exact = spec0.StartsWith('=');
            var spec = exact ? spec0[1..] : spec0;
            var hit = !exact && spec.EndsWith('*')
                ? srcRows.Where(r => r.Name.ToString().StartsWith(spec[..^1], StringComparison.Ordinal)).ToList()
                : srcRows.Where(r => r.Name.ToString() == spec).ToList();
            if (hit.Count == 0) throw new Exception($"mod table has no row matching {spec}");
            wanted.AddRange(hit);
        }
        // schema check: every member the mod row has must exist in a fresh row with the same property type
        var sample = dstRows.FirstOrDefault(r => !wanted.Any(w => w.Name.ToString() == r.Name.ToString()));
        if (sample != null)
            foreach (var w in wanted)
            {
                var have = sample.Value.ToDictionary(p => p.Name.ToString(), p => p.PropertyType.ToString());
                foreach (var p in w.Value)
                    if (!have.TryGetValue(p.Name.ToString(), out var t) || t != p.PropertyType.ToString())
                        throw new Exception($"table layout changed: field {p.Name} ({p.PropertyType}) not in the game's rows as the same type");
                if (have.Count != w.Value.Count)
                    throw new Exception($"table layout changed: game rows have {have.Count} fields, mod row {w.Name} has {w.Value.Count}");
            }
        var seen = new HashSet<object>(ReferenceEqualityComparer.Instance);
        int names = 0, imports = 0;
        FPackageIndex MapImport(FPackageIndex idx)
        {
            if (idx == null || idx.IsNull()) return idx!;
            if (idx.IsExport()) throw new Exception("a transplanted row points at an export of the mod file; not supported");
            var si = idx.ToImport(srcAsset);
            var outer = MapImport(si.OuterIndex);
            FName N(FName f) { asset.AddNameReference(f.Value); return new FName(asset, f.Value, f.Number); }
            for (int i = 0; i < asset.Imports.Count; i++)
            {
                var d = asset.Imports[i];
                if (d.ObjectName.ToString() == si.ObjectName.ToString() && d.ClassName.ToString() == si.ClassName.ToString()
                    && d.ClassPackage.ToString() == si.ClassPackage.ToString()
                    && ((d.OuterIndex == null || d.OuterIndex.IsNull()) ? (outer == null || outer.IsNull()) : (outer != null && d.OuterIndex.Index == outer.Index)))
                    return FPackageIndex.FromImport(i);
            }
            var ni = new Import(N(si.ClassPackage), N(si.ClassName), outer ?? new FPackageIndex(0), N(si.ObjectName), si.bImportOptional);
            asset.Imports.Add(ni); imports++;
            return FPackageIndex.FromImport(asset.Imports.Count - 1);
        }
        object? Rebind(object? o)
        {
            switch (o)
            {
                case null: return null;
                case FName fn: asset.AddNameReference(fn.Value); names++; return new FName(asset, fn.Value, fn.Number);
                case FPackageIndex pi: return MapImport(pi);
                case string or FString or Enum or UAsset or Type or System.Reflection.MemberInfo: return o;
            }
            var t = o.GetType();
            if (t.IsPrimitive || t == typeof(decimal) || t == typeof(Guid)) return o;
            if (!t.IsValueType && !seen.Add(o)) return o;
            if (o is System.Collections.IList && !t.IsArray || o is Array)
            {
                var l = (System.Collections.IList)o;
                for (int i = 0; i < l.Count; i++) l[i] = Rebind(l[i]);
                return o;
            }
            if (o is System.Collections.IDictionary dict)
            {
                var pairs = new List<(object k, object? v)>();
                foreach (System.Collections.DictionaryEntry e in dict) pairs.Add((e.Key, e.Value));
                dict.Clear();
                foreach (var (k, v) in pairs) dict[Rebind(k)!] = Rebind(v);
                return o;
            }
            for (var c = t; c != null && c != typeof(object); c = c.BaseType)
                foreach (var f in c.GetFields(System.Reflection.BindingFlags.Instance | System.Reflection.BindingFlags.Public | System.Reflection.BindingFlags.NonPublic | System.Reflection.BindingFlags.DeclaredOnly))
                {
                    var v = f.GetValue(o);
                    var nv = Rebind(v);
                    // boxed structs (soft object paths, etc.) were rebound in their box: always write those back
                    if (f.FieldType.IsValueType || !ReferenceEquals(v, nv)) f.SetValue(o, nv);
                }
            return o;
        }
        foreach (var w in wanted)
        {
            var row = (StructPropertyData)w.Clone();
            Rebind(row);
            int at = dstRows.FindIndex(r => r.Name.ToString() == w.Name.ToString());
            if (at >= 0) { dstRows[at] = row; Console.WriteLine($"  replaced row {w.Name}"); }
            else { dstRows.Add(row); Console.WriteLine($"  added row {w.Name}"); }
        }
        Directory.CreateDirectory(Path.GetDirectoryName(Path.GetFullPath(args[2]))!);
        asset.Write(args[2]);
        // read the result back and check every transplanted row is there
        var check = new UAsset(args[2], EngineVersion.VER_UE5_7, usmap);
        var back = check.Exports.OfType<DataTableExport>().First().Table.Data;
        foreach (var w in wanted) if (!back.Any(r => r.Name.ToString() == w.Name.ToString())) throw new Exception($"row {w.Name} missing after write");
        Console.WriteLine($"transplanted {wanted.Count} row(s) ({names} names, {imports} new imports); table now {back.Count} rows -> {args[2]}");
        return 0;
    }
    case "takearray":
    {
        var e=asset.Exports.OfType<NormalExport>().First(e=>e.ObjectName.ToString()==args[3]);
        var a=e.Data.OfType<ArrayPropertyData>().First(p=>p.Name.ToString()==args[4]);
        int count=int.Parse(args[5]);if(count<0 || count>a.Value.Length)throw new Exception("Array prefix out of range");
        a.Value=a.Value.Take(count).ToArray();asset.Write(args[2]);return 0;
    }
    case "noopfunction":
    {
        var fn=asset.Exports.OfType<FunctionExport>().First(f=>f.ObjectName.ToString()==args[3]);
        fn.ScriptBytecode=new UAssetAPI.Kismet.Bytecode.KismetExpression[]{
            new UAssetAPI.Kismet.Bytecode.Expressions.EX_Return { ReturnExpression=new UAssetAPI.Kismet.Bytecode.Expressions.EX_Nothing() },
            new UAssetAPI.Kismet.Bytecode.Expressions.EX_EndOfScript()
        };
        asset.Write(args[2]);return 0;
    }
    case "setnestednumber":
    {
        var e=asset.Exports.OfType<NormalExport>().First(e=>e.ObjectName.ToString()==args[3]);
        foreach(var spec in args.Skip(4)) {
            var pair=spec.Split('=',2);var path=pair[0].Split('.');var list=e.Data;
            for(int i=0;i<path.Length-1;i++)list=((StructPropertyData)list.First(p=>p.Name.ToString()==path[i])).Value;
            var p=list.First(p=>p.Name.ToString()==path[^1]);
            if(p is FloatPropertyData f)f.Value=float.Parse(pair[1]);
            else if(p is DoublePropertyData d)d.Value=double.Parse(pair[1]);
            else throw new Exception("Not a numeric property: "+pair[0]);
        }
        asset.Write(args[2]);return 0;
    }
    case "tagset":
    {
        var cdo=asset.Exports.OfType<NormalExport>().First(e=>e.ObjectName.ToString().StartsWith("Default__"));
        var name=FName.FromString(asset,args[3]);
        cdo.Data.RemoveAll(p=>p.Name.ToString()==args[3]);
        cdo.Data.Add(new StructPropertyData(name) {
            StructType=FName.FromString(asset,"GameplayTagContainer"),
            Value=new List<PropertyData>{new GameplayTagContainerPropertyData(name){Value=args.Skip(4).Select(t=>FName.FromString(asset,t)).ToArray()}}
        });
        asset.Write(args[2]);return 0;
    }
    case "arraykeep":
    {
        var e=asset.Exports.OfType<NormalExport>().First(e=>e.ObjectName.ToString()==args[3]);
        var a=e.Data.OfType<ArrayPropertyData>().First(p=>p.Name.ToString()==args[4]);
        var names=args.Skip(5).ToHashSet();
        a.Value=a.Value.Where(p=>p is ObjectPropertyData o && o.Value.Index!=0 && names.Contains(o.Value.IsExport()?o.Value.ToExport(asset).ObjectName.ToString():o.Value.ToImport(asset).ObjectName.ToString())).ToArray();
        asset.Write(args[2]);return 0;
    }
    case "copycurves":
    {
        // Copy only numeric timeline curves; never transfer objects or cooked class layouts.
        var donor = new UAsset(args[3], EngineVersion.VER_UE5_7, usmap);
        var source = donor.Exports.OfType<NormalExport>().First(e => e.ObjectName.ToString() == args[4]);
        var target = asset.Exports.OfType<NormalExport>().First(e => e.ObjectName.ToString() == args[5]);
        var curves = (ArrayPropertyData)source.Data.First(p => p.Name.ToString() == "FloatCurves").Clone();
        void Rebind(PropertyData p) {
            foreach(var f in p.GetType().GetFields())
                if(f.FieldType == typeof(FName) && f.GetValue(p) is FName n) f.SetValue(p,FName.FromString(asset,n.ToString()));
            foreach(var f in p.GetType().GetProperties())
                if(f.CanRead && f.CanWrite && f.PropertyType == typeof(FName) && f.GetValue(p) is FName n) f.SetValue(p,FName.FromString(asset,n.ToString()));
            if(p is StructPropertyData s) foreach(var child in s.Value) Rebind(child);
            if(p is ArrayPropertyData a) foreach(var child in a.Value) Rebind(child);
        }
        Rebind(curves);
        target.Data.RemoveAll(p => p.Name.ToString() == "FloatCurves");
        target.Data.Add(curves);
        asset.Write(args[2]); return 0;
    }
    case "setfield":
    {
        var e=asset.Exports.OfType<NormalExport>().First(x=>x.ObjectName.ToString()==args[3]);
        var st=e.Data.OfType<StructPropertyData>().First(x=>x.Name.ToString()==args[4]);
        foreach(var spec in args.Skip(5)){
            var parts=spec.Split('=',2);var p=st.Value.First(x=>x.Name.ToString()==parts[0]);
            if(p is BoolPropertyData b)b.Value=bool.Parse(parts[1]);
            else if(p is FloatPropertyData f)f.Value=float.Parse(parts[1]);
            else if(p is DoublePropertyData d)d.Value=double.Parse(parts[1]);
            else throw new Exception("Unsupported nested property "+parts[0]);
        }
        asset.Write(args[2]);return 0;
    }
    case "pace":
    {
        double rate=double.Parse(args[3]),cut=double.Parse(args[4]);
        void Number(PropertyData p,double value){if(p is FloatPropertyData f)f.Value=(float)value;else if(p is DoublePropertyData d)d.Value=value;}
        void Walk(PropertyData p){
            var name=p.Name.ToString();
            if(name=="AnimPlayRate")Number(p,rate);
            if(name=="AnimEndTime")Number(p,cut);
            if(name is "SequenceLength" or "SegmentLength")Number(p,cut/rate);
            if(name is "StartDuration" or "ActDuration" or "ComboDuration"){
                if(p is FloatPropertyData f)f.Value/=(float)rate;
                else if(p is DoublePropertyData d)d.Value/=rate;
            }
            if(p is StructPropertyData st)foreach(var child in st.Value)Walk(child);
            if(p is ArrayPropertyData arr)foreach(var child in arr.Value)Walk(child);
        }
        foreach(var e in asset.Exports.OfType<NormalExport>()){
            var actions=e.Data.OfType<ArrayPropertyData>().FirstOrDefault(p=>p.Name.ToString()=="Actions");
            if(e.ObjectName.ToString()=="Main"&&actions!=null){
                var kept=new List<PropertyData>();
                foreach(var row in actions.Value.Cast<StructPropertyData>()){
                    var start=row.Value.First(p=>p.Name.ToString()=="StartTime");
                    double time=start is FloatPropertyData f?f.Value:((DoublePropertyData)start).Value;
                    if(time>=cut)continue;
                    var duration=row.Value.First(p=>p.Name.ToString()=="duration");
                    double length=duration is FloatPropertyData fd?fd.Value:((DoublePropertyData)duration).Value;
                    Number(start,time/rate);Number(duration,Math.Min(length,cut-time)/rate);kept.Add(row);
                }
                actions.Value=kept.ToArray();
            }
            foreach(var p in e.Data)Walk(p);
        }
        asset.Write(args[2]);return 0;
    }
    case "abilitytags":
    {
        // Override native tag defaults without changing the cooked superclass layout.
        var cdo=asset.Exports.OfType<NormalExport>().First(e=>e.ObjectName.ToString().StartsWith("Default__"));
        foreach(var name in new[]{"AbilityTags","ActivationOwnedTags"}) {
            cdo.Data.RemoveAll(p=>p.Name.ToString()==name);
            var fn=FName.FromString(asset,name);
            cdo.Data.Add(new StructPropertyData(fn) {
                StructType=FName.FromString(asset,"GameplayTagContainer"),
                Value=new List<PropertyData>{new GameplayTagContainerPropertyData(fn){Value=new[]{FName.FromString(asset,args[3])}}}
            });
        }
        asset.Write(args[2]);return 0;
    }
    case "clearratecurves":
    {
        int removed=0;
        void WalkRate(PropertyData p) {
            if(p is ArrayPropertyData a) {
                if(p.Name.ToString()=="FloatCurves") {
                    int before=a.Value.Length;
                    a.Value=a.Value.Where(v=>!(v is StructPropertyData s && s.Value.OfType<NamePropertyData>().Any(n=>n.Name.ToString()=="CurveName" && n.Value.ToString()=="Rate"))).ToArray();
                    removed+=before-a.Value.Length;
                }
                foreach(var c in a.Value)WalkRate(c);
            } else if(p is StructPropertyData s)foreach(var c in s.Value)WalkRate(c);
        }
        foreach(var e in asset.Exports.OfType<NormalExport>())foreach(var p in e.Data)WalkRate(p);
        asset.Write(args[2]);Console.WriteLine($"removed {removed} donor rate curves");return 0;
    }
    case "grant":
    {
        string field=args.Length>5?args[5]:"Equip Abilities",className=args.Length>6?args[6]:"LegoAbilityBlueprintGeneratedClass",classPackage=args.Length>7?args[7]:"/Script/LegoAbility";
        string path=args[3],name=args[4];int pi=asset.Imports.FindIndex(i=>i.ObjectName.ToString()==path&&i.ClassName.ToString()=="Package");
        if(pi<0){pi=asset.Imports.Count;asset.Imports.Add(new Import{ObjectName=FName.FromString(asset,path),ClassName=FName.FromString(asset,"Package"),ClassPackage=FName.FromString(asset,"/Script/CoreUObject"),OuterIndex=new FPackageIndex(0)});}
        int ni=asset.Imports.FindIndex(i=>i.ObjectName.ToString()==name&&i.ClassName.ToString()==className);
        if(ni<0){ni=asset.Imports.Count;asset.Imports.Add(new Import{ObjectName=FName.FromString(asset,name),ClassName=FName.FromString(asset,className),ClassPackage=FName.FromString(asset,classPackage),OuterIndex=FPackageIndex.FromImport(pi)});}
        var owner=asset.Exports.OfType<NormalExport>().First(e=>e.Data.Any(p=>p.Name.ToString()=="Equip Abilities"));
        var arr=owner.Data.OfType<ArrayPropertyData>().FirstOrDefault(p=>p.Name.ToString()==field);
        if(arr==null) {
            var seed=owner.Data.OfType<ArrayPropertyData>().First(p=>p.Name.ToString()=="Equip Abilities");
            arr=(ArrayPropertyData)seed.Clone();arr.Name=FName.FromString(asset,field);arr.Value=Array.Empty<PropertyData>();
            owner.Data.Insert(owner.Data.IndexOf(seed)+1,arr);
        }
        if(!arr.Value.OfType<ObjectPropertyData>().Any(v=>v.Value.Index==FPackageIndex.FromImport(ni).Index))arr.Value=arr.Value.Append(new ObjectPropertyData(FName.FromString(asset,field)){Value=FPackageIndex.FromImport(ni)}).ToArray();
        asset.Write(args[2]);return 0;
    }
    case "recalltimeline":
    {
        const string timelineName = "MjolnirRecallAssets";
        var main = asset.Exports.OfType<NormalExport>().Single(e => e.ObjectName.ToString() == "Main");
        var ability = (ClassExport)main.OuterIndex.ToExport(asset);
        var play = asset.Exports.OfType<NormalExport>().Single(e => e.ObjectName.ToString() == "LGAAction_PlayMontage_0");
        var playIndex = FPackageIndex.FromExport(asset.Exports.IndexOf(play));
        var mainActions = main.Data.OfType<ArrayPropertyData>().Single(p => p.Name.ToString() == "Actions");
        IEnumerable<ObjectPropertyData> ActionReferences(ArrayPropertyData array) =>
            array.Value.Cast<StructPropertyData>().Select(p => p.Value.OfType<ObjectPropertyData>()
                .Single(o => o.Name.ToString() == "Action"));
        var existingAction = asset.Exports.FindIndex(e => e.ObjectName.ToString() == "LGAAction_PlayRecallReach");
        if (existingAction >= 0)
        {
            var existingIndex = FPackageIndex.FromExport(existingAction);
            foreach (var actionRef in ActionReferences(mainActions).Where(p => p.Value.Index == existingIndex.Index))
                actionRef.Value = playIndex;
            asset.Write(args[2]);
            return 0;
        }
        var originalRef = play.Data.OfType<ObjectPropertyData>().Single(p => p.Name.ToString() == "MontageToPlay").Value;
        var originalImport = originalRef.ToImport(asset);
        var package = new Import
        {
            ObjectName = FName.FromString(asset, "/Game/Mods/MjolnirHammer/Montages/AM_Mjolnir_RecallArm"),
            ClassName = FName.FromString(asset, "Package"),
            ClassPackage = FName.FromString(asset, "/Script/CoreUObject"),
            OuterIndex = new FPackageIndex(0)
        };
        asset.Imports.Add(package);
        asset.Imports.Add(new Import
        {
            ObjectName = FName.FromString(asset, "AM_Mjolnir_RecallArm"),
            ClassName = originalImport.ClassName,
            ClassPackage = originalImport.ClassPackage,
            OuterIndex = FPackageIndex.FromImport(asset.Imports.Count - 1)
        });
        var reach = FPackageIndex.FromImport(asset.Imports.Count - 1);
        var timelineIndex = FPackageIndex.FromExport(asset.Exports.Count);
        var actionIndex = FPackageIndex.FromExport(asset.Exports.Count + 1);

        NormalExport Copy(NormalExport source, string name, FPackageIndex outer)
        {
            return new NormalExport(asset, source.Extras)
            {
                ObjectName = FName.FromString(asset, name),
                ObjectFlags = source.ObjectFlags,
                OuterIndex = outer,
                ClassIndex = source.ClassIndex,
                SuperIndex = source.SuperIndex,
                TemplateIndex = source.TemplateIndex,
                SerializationBeforeCreateDependencies = source.SerializationBeforeCreateDependencies.ToList(),
                CreateBeforeCreateDependencies = new() { outer },
                CreateBeforeSerializationDependencies = new(),
                SerializationBeforeSerializationDependencies = new(),
                Data = source.Data.Select(p => (PropertyData)p.Clone()).ToList()
            };
        }

        // PBZ only starts the Main timeline automatically. The second timeline
        // keeps a typed montage reference alive for the Lua recall controller.
        var timeline = Copy(main, timelineName, main.OuterIndex);
        foreach (var setting in timeline.Data.OfType<BoolPropertyData>()
            .Where(p => p.Name.ToString() is "bAutoPlay" or "bStopAbility"))
            setting.Value = false;
        var actions = timeline.Data.OfType<ArrayPropertyData>().Single(p => p.Name.ToString() == "Actions");
        var template = mainActions.Value.Cast<StructPropertyData>().Single(p => p.Value.OfType<ObjectPropertyData>()
            .Any(o => o.Name.ToString() == "Action" && o.Value.Index == playIndex.Index));
        var entry = (StructPropertyData)template.Clone();
        entry.Value = template.Value.Select(p => (PropertyData)p.Clone()).ToList();
        entry.Value.OfType<ObjectPropertyData>().Single(p => p.Name.ToString() == "Action").Value = actionIndex;
        actions.Value = new PropertyData[] { entry };
        timeline.CreateBeforeSerializationDependencies.Add(actionIndex);

        var action = Copy(play, "LGAAction_PlayRecallReach", timelineIndex);
        action.Data.OfType<ObjectPropertyData>().Single(p => p.Name.ToString() == "MontageToPlay").Value = reach;
        action.CreateBeforeSerializationDependencies.Add(reach);
        asset.Exports.Add(timeline);
        asset.Exports.Add(action);

        var timelines = ability.Data.OfType<ArrayPropertyData>().Single(p => p.Name.ToString() == "AbilityTimelines");
        var reference = (ObjectPropertyData)timelines.Value[0].Clone();
        reference.Value = timelineIndex;
        timelines.Value = timelines.Value.Append(reference).ToArray();
        ability.CreateBeforeSerializationDependencies.Add(timelineIndex);
        asset.Write(args[2]);
        return 0;
    }
    case "trailset":
    {
        // trailset <in> <out> <tag> <systemPackage> <systemName>: the weapon config's Trails entry <tag> draws
        // <systemPackage>.<systemName> (a NiagaraSystem import is added if missing; other entries untouched).
        string tag = args[3], pkgPath = args[4], sysName = args[5];
        var owner = asset.Exports.OfType<NormalExport>().First(e => e.Data.Any(p => p.Name.ToString() == "Trails"));
        var trails = (MapPropertyData)owner.Data.First(p => p.Name.ToString() == "Trails");
        string KeyTag(PropertyData k) => ((StructPropertyData)k).Value.OfType<NamePropertyData>().First(n => n.Name.ToString() == "TagName").Value.ToString();
        var entry = trails.Value.FirstOrDefault(kv => KeyTag(kv.Key) == tag);
        if (entry.Key == null) throw new Exception($"Trails has no {tag}");
        int pi = asset.Imports.FindIndex(i => i.ObjectName.ToString() == pkgPath && i.ClassName.ToString() == "Package");
        if (pi < 0) { pi = asset.Imports.Count; asset.Imports.Add(new Import { ObjectName = FName.FromString(asset, pkgPath), ClassName = FName.FromString(asset, "Package"), ClassPackage = FName.FromString(asset, "/Script/CoreUObject"), OuterIndex = new FPackageIndex(0) }); }
        int si = asset.Imports.FindIndex(i => i.ObjectName.ToString() == sysName && i.ClassName.ToString() == "NiagaraSystem" && i.OuterIndex.Index == FPackageIndex.FromImport(pi).Index);
        if (si < 0) { si = asset.Imports.Count; asset.Imports.Add(new Import { ObjectName = FName.FromString(asset, sysName), ClassName = FName.FromString(asset, "NiagaraSystem"), ClassPackage = FName.FromString(asset, "/Script/Niagara"), OuterIndex = FPackageIndex.FromImport(pi) }); }
        var particle = ((StructPropertyData)entry.Value).Value.OfType<ObjectPropertyData>().First(p => p.Name.ToString().StartsWith("Particle"));
        particle.Value = FPackageIndex.FromImport(si);
          // Cooked IoStore imports must also appear in the export's preload
          // dependencies. An import table entry alone leaves a new effect unloaded.
          var trailDependency = FPackageIndex.FromImport(si);
          if (!owner.CreateBeforeSerializationDependencies.Any(d => d.Index == trailDependency.Index))
              owner.CreateBeforeSerializationDependencies.Add(trailDependency);
          // Optional presentation settings; existing trailset callers keep their values.
          if (args.Length > 6)
          {
              double scale = double.Parse(args[6], System.Globalization.CultureInfo.InvariantCulture);
              if (!double.IsFinite(scale) || scale <= 0) throw new Exception("trail scale must be positive");
              var settings = ((StructPropertyData)entry.Value).Value;
              var size = (StructPropertyData)settings.First(p => p.Name.ToString().StartsWith("Scale_"));
              ((VectorPropertyData)size.Value[0]).Value = new FVector(scale, scale, scale);
              if (args.Length > 7)
                  settings.OfType<NamePropertyData>().First(p => p.Name.ToString().StartsWith("Slot_")).Value = FName.FromString(asset, args[7]);
          }
        asset.Write(args[2]);
        Console.WriteLine($"Trails: {tag} -> {pkgPath}.{sysName} (import {si})");
        return 0;
    }
    case "materialcopylook":
    {
        var source = new UAsset(args[3], EngineVersion.VER_UE5_7, usmap);
        string ParameterName(StructPropertyData entry) => entry.Value.OfType<StructPropertyData>()
            .Single(p => p.Name.ToString() == "ParameterInfo").Value.OfType<NamePropertyData>()
            .Single(p => p.Name.ToString() == "Name").Value.ToString();
        void Rebind(PropertyData property)
        {
            foreach (var field in property.GetType().GetFields())
                if (field.FieldType == typeof(FName) && field.GetValue(property) is FName name)
                    field.SetValue(property, FName.FromString(asset, name.ToString()));
            foreach (var member in property.GetType().GetProperties())
                if (member.CanRead && member.CanWrite && member.PropertyType == typeof(FName) && member.GetValue(property) is FName name)
                    member.SetValue(property, FName.FromString(asset, name.ToString()));
            if (property is StructPropertyData structure)
                foreach (var child in structure.Value) Rebind(child);
        }
        foreach (var field in new[] { "ScalarParameterValues", "VectorParameterValues" })
        {
            var oldParameters = source.Exports.OfType<NormalExport>().SelectMany(e => e.Data.OfType<ArrayPropertyData>())
                .Single(p => p.Name.ToString() == field);
            var target = asset.Exports.OfType<NormalExport>().SelectMany(e => e.Data.OfType<ArrayPropertyData>())
                .Single(p => p.Name.ToString() == field);
            var names = target.Value.Cast<StructPropertyData>().Select(ParameterName).ToHashSet();
            var additions = oldParameters.Value.Cast<StructPropertyData>().Where(p => !names.Contains(ParameterName(p)))
                .Select(p => (StructPropertyData)p.Clone()).ToArray();
            foreach (var addition in additions) Rebind(addition);
            target.Value = target.Value.Concat(additions).ToArray();
        }
        asset.Write(args[2]);
        return 0;
    }
    case "materialtint":
    {
        var parameters = asset.Exports.OfType<NormalExport>()
            .SelectMany(e => e.Data.OfType<ArrayPropertyData>())
            .Single(p => p.Name.ToString() == "VectorParameterValues");
        var parameter = parameters.Value.Cast<StructPropertyData>().Single(p =>
            p.Value.OfType<StructPropertyData>().Single(s => s.Name.ToString() == "ParameterInfo")
                .Value.OfType<NamePropertyData>().Any(n => n.Name.ToString() == "Name" && n.Value.ToString() == args[3]));
        var color = parameter.Value.OfType<StructPropertyData>().Single(p => p.Name.ToString() == "ParameterValue")
            .Value.OfType<LinearColorPropertyData>().Single();
        var tint = color.Value;
        tint.R = float.Parse(args[4], System.Globalization.CultureInfo.InvariantCulture);
        tint.G = float.Parse(args[5], System.Globalization.CultureInfo.InvariantCulture);
        tint.B = float.Parse(args[6], System.Globalization.CultureInfo.InvariantCulture);
        color.Value = tint;
        asset.Write(args[2]);
        return 0;
    }
    case "niagaraliterals":
    {
        // Patch audited literals as offset=original or offset=original:replacement. Optimized VM data contains
        // constant index mappings; its executable bytecode stays unchanged.
        var exp = asset.Exports[int.Parse(args[3].TrimStart('#'))] as NormalExport ?? throw new Exception("Not a script export");
        var vm = exp.Data.OfType<StructPropertyData>().First(p => p.Name.ToString() == "CachedScriptVM");
        var literals = vm.Value.OfType<ArrayPropertyData>().First(p => p.Name.ToString() == "ScriptLiterals");
        byte[] bytes = literals.Value.Cast<BytePropertyData>().Select(p => Convert.ToByte(p.Value)).ToArray();
        float factor = float.Parse(args[4], System.Globalization.CultureInfo.InvariantCulture);
        if (!float.IsFinite(factor) || factor <= 0 || factor > 1) throw new Exception("Expected a reduction factor");
        foreach (string spec in args.Skip(5))
        {
            var parts = spec.Split('='); int offset = int.Parse(parts[0]);
            float expected = float.Parse(parts[1].Split(':')[0], System.Globalization.CultureInfo.InvariantCulture);
            if (offset < 0 || offset % 4 != 0 || offset + 4 > bytes.Length || BitConverter.ToSingle(bytes, offset) != expected) throw new Exception($"Literal guard failed: {exp.ObjectName} {spec}");
        }
        foreach (string spec in args.Skip(5))
        {
            var parts = spec.Split('=');
            int offset = int.Parse(parts[0]); float original = BitConverter.ToSingle(bytes, offset);
            var values = parts[1].Split(':');
            float replacement = values.Length == 2 ? float.Parse(values[1], System.Globalization.CultureInfo.InvariantCulture) : original * factor;
            byte[] scaled = BitConverter.GetBytes(replacement);
            for (int n = 0; n < 4; n++) ((BytePropertyData)literals.Value[offset + n]).Value = scaled[n];
            Console.WriteLine($"{exp.ObjectName} literal {offset}: {original} -> {replacement}");
        }
        asset.Write(args[2]); return 0;
    }
    case "traildirect":
    {
        // Direct trail actions bypass the weapon's tag map (Giant's Bane / sprint switch).
        string path = args[3]; int dot = path.LastIndexOf('.');
        double scale = double.Parse(args[4], System.Globalization.CultureInfo.InvariantCulture);
        if (dot < 0 || !double.IsFinite(scale) || scale <= 0) throw new Exception("traildirect requires object path and positive scale");
        int changed = 0;
        foreach (var exp in asset.Exports.OfType<NormalExport>().Where(e => e.ObjectName.ToString().StartsWith("GAAction_WeaponTrail_C_")))
        {
            var particle = exp.Data.OfType<SoftObjectPropertyData>().FirstOrDefault(p => p.Name.ToString() == "Niagara Particle");
            if (particle == null) continue;
            particle.Value = new FSoftObjectPath(FName.FromString(asset, path[..dot]), FName.FromString(asset, path[(dot + 1)..]), null);
            foreach (var name in new[] { "FirstSocketName", "Second Socket Name" })
            {
                var socket = exp.Data.OfType<NamePropertyData>().FirstOrDefault(p => p.Name.ToString() == name);
                if (socket == null) { socket = new NamePropertyData(FName.FromString(asset, name)); exp.Data.Add(socket); }
                socket.Value = FName.FromString(asset, "DeflectTopMiddle");
            }
            var transform = exp.Data.OfType<StructPropertyData>().FirstOrDefault(p => p.Name.ToString() == "Transform");
            if (transform == null) { transform = new StructPropertyData(FName.FromString(asset, "Transform"), FName.FromString(asset, "Transform")) { Value = new List<PropertyData>() }; exp.Data.Add(transform); }
            var size = transform.Value.OfType<StructPropertyData>().FirstOrDefault(p => p.Name.ToString() == "Scale3D");
            if (size == null) { size = new StructPropertyData(FName.FromString(asset, "Scale3D"), FName.FromString(asset, "Vector")) { Value = new List<PropertyData>() }; transform.Value.Add(size); }
            size.Value = new List<PropertyData> { new VectorPropertyData(FName.FromString(asset, "Scale3D")) { Value = new FVector(scale, scale, scale) } };
            changed++;
        }
        if (changed == 0) throw new Exception("No direct trail actions found");
        asset.Write(args[2]); Console.WriteLine($"Updated {changed} direct trail actions"); return 0;
    }
    case "trailadd":
    {
        // trailadd <in> <out> <fromTag> <newTag> <systemPackage> <systemName>
        // Copies the weapon config's Trails entry <fromTag> under <newTag>, drawing <systemPackage>.<systemName>
        // (a NiagaraSystem import is added if missing).  The weapon then holds a hard reference to that system,
        // so it loads with the weapon.  Refuses if <newTag> is already a key.
        string fromTag = args[3], newTag = args[4], pkgPath = args[5], sysName = args[6];
        var owner = asset.Exports.OfType<NormalExport>().First(e => e.Data.Any(p => p.Name.ToString() == "Trails"));
        var trails = (MapPropertyData)owner.Data.First(p => p.Name.ToString() == "Trails");
        string KeyTag(PropertyData k) => ((StructPropertyData)k).Value.OfType<NamePropertyData>().First(n => n.Name.ToString() == "TagName").Value.ToString();
        if (trails.Value.Keys.Any(k => KeyTag(k) == newTag)) throw new Exception($"Trails already has {newTag}");
        var from = trails.Value.FirstOrDefault(kv => KeyTag(kv.Key) == fromTag);
        if (from.Key == null) throw new Exception($"Trails has no {fromTag}");
        int pi = asset.Imports.FindIndex(i => i.ObjectName.ToString() == pkgPath && i.ClassName.ToString() == "Package");
        if (pi < 0) { pi = asset.Imports.Count; asset.Imports.Add(new Import { ObjectName = FName.FromString(asset, pkgPath), ClassName = FName.FromString(asset, "Package"), ClassPackage = FName.FromString(asset, "/Script/CoreUObject"), OuterIndex = new FPackageIndex(0) }); }
        int si = asset.Imports.FindIndex(i => i.ObjectName.ToString() == sysName && i.ClassName.ToString() == "NiagaraSystem" && i.OuterIndex.Index == FPackageIndex.FromImport(pi).Index);
        if (si < 0) { si = asset.Imports.Count; asset.Imports.Add(new Import { ObjectName = FName.FromString(asset, sysName), ClassName = FName.FromString(asset, "NiagaraSystem"), ClassPackage = FName.FromString(asset, "/Script/Niagara"), OuterIndex = FPackageIndex.FromImport(pi) }); }
        var key = (StructPropertyData)from.Key.Clone();
        key.Value.OfType<NamePropertyData>().First(n => n.Name.ToString() == "TagName").Value = FName.FromString(asset, newTag);
        var val = (StructPropertyData)from.Value.Clone();
        var particle = val.Value.OfType<ObjectPropertyData>().First(p => p.Name.ToString().StartsWith("Particle"));
        particle.Value = FPackageIndex.FromImport(si);
        trails.Value.Add(key, val);
        asset.Write(args[2]);
        Console.WriteLine($"Trails: {fromTag} copied as {newTag} -> {pkgPath}.{sysName} (import {si})");
        return 0;
    }
    case "aimblock":
    {
        var tag=FName.FromString(asset,args[3]);
        void Block(PropertyData p){
            if(p.Name.ToString()=="IgnoredTags"){
                GameplayTagContainerPropertyData? box=p as GameplayTagContainerPropertyData;
                if(p is StructPropertyData st)box=st.Value.OfType<GameplayTagContainerPropertyData>().FirstOrDefault();
                if(box!=null&&!box.Value.Contains(tag))box.Value=box.Value.Append(tag).ToArray();
            }
            if(p is ArrayPropertyData a)foreach(var c in a.Value)Block(c);
            if(p is StructPropertyData s)foreach(var c in s.Value)Block(c);
        }
        foreach(var e in asset.Exports.OfType<NormalExport>())foreach(var p in e.Data)Block(p);
        asset.Write(args[2]);return 0;
    }
    case "mappingremove":
    {
        string action=args[3];int removed=0;
        void Drop(PropertyData p){
            if(p is ArrayPropertyData a){
                if(p.Name.ToString()=="Mappings"){
                    int before=a.Value.Length;
                    a.Value=a.Value.Where(v=>!(v is StructPropertyData st && st.Value.OfType<ObjectPropertyData>().Any(o=>o.Name.ToString()=="Action" && o.Value.IsImport() && o.Value.ToImport(asset).ObjectName.ToString()==action))).ToArray();removed+=before-a.Value.Length;
                }
                foreach(var c in a.Value)Drop(c);
            }else if(p is StructPropertyData st)foreach(var c in st.Value)Drop(c);
        }
        foreach(var e in asset.Exports.OfType<NormalExport>())foreach(var p in e.Data)Drop(p);
        asset.Write(args[2]);Console.WriteLine($"removed {removed} mappings for {action}");return 0;
    }
    case "hammeroverlay":
    {
        var data=asset.Exports.OfType<NormalExport>().SelectMany(e=>e.Data).OfType<StructPropertyData>().First(p=>p.Name.ToString()=="DefaultKeyMappings");
        var mappings=data.Value.OfType<ArrayPropertyData>().First(p=>p.Name.ToString()=="Mappings");
        string Key(StructPropertyData row)=>row.Value.OfType<StructPropertyData>().First(p=>p.Name.ToString()=="Key").Value.OfType<NamePropertyData>().First().Value.ToString();
        var rows=mappings.Value.Cast<StructPropertyData>().ToArray();
        var template=rows.First(r=>Key(r)=="Gamepad_LeftTriggerAxis");
        var action=template.Value.OfType<ObjectPropertyData>().First(p=>p.Name.ToString()=="Action");
        mappings.Value=new[]{"Gamepad_LeftTriggerAxis","Gamepad_RightTriggerAxis","RightMouseButton","LeftControl"}.Select(key=>{
            var row=(StructPropertyData)template.Clone();
            row.Value.OfType<StructPropertyData>().First(p=>p.Name.ToString()=="Key").Value.OfType<NamePropertyData>().First().Value=FName.FromString(asset,key);
            row.Value.OfType<ObjectPropertyData>().First(p=>p.Name.ToString()=="Action").Value=action.Value;
            return (PropertyData)row;
        }).ToArray();
        asset.Write(args[2]);return 0;
    }
    case "montageblend":
    {
        var exp=asset.Exports.OfType<NormalExport>().First(e=>e.Data.Any(p=>p.Name.ToString()=="SequenceLength"));
        var seed=exp.Data.OfType<StructPropertyData>().First(p=>p.Name.ToString()=="BlendOut");
        void Blend(string name,float duration){
            var b=exp.Data.OfType<StructPropertyData>().FirstOrDefault(p=>p.Name.ToString()==name);
            if(b==null){b=(StructPropertyData)seed.Clone();b.Name=FName.FromString(asset,name);exp.Data.Add(b);}
            var t=b.Value.OfType<FloatPropertyData>().FirstOrDefault(p=>p.Name.ToString()=="BlendTime");
            if(t==null){t=new FloatPropertyData(FName.FromString(asset,"BlendTime"));b.Value.Add(t);}t.Value=duration;
        }
        Blend("BlendIn",float.Parse(args[3]));Blend("BlendOut",float.Parse(args[4]));
        var trigger=exp.Data.OfType<FloatPropertyData>().FirstOrDefault(p=>p.Name.ToString()=="BlendOutTriggerTime");
        if(trigger==null){trigger=new FloatPropertyData(FName.FromString(asset,"BlendOutTriggerTime"));exp.Data.Add(trigger);}trigger.Value=0;
        asset.Write(args[2]);return 0;
    }
    case "limitcombo":
    {
        int removed=0; int maxCombo=args.Length>3?int.Parse(args[3]):5;
        void Walk(PropertyData p) {
            if(p is ArrayPropertyData a) {
                a.Value=a.Value.Where(v=> {
                    if(v is StructPropertyData s && s.Value.FirstOrDefault(x=>x.Name.ToString()=="TriggerTag") is StructPropertyData t && t.Value.OfType<NamePropertyData>().Any(n=>System.Text.RegularExpressions.Regex.IsMatch(n.Value.ToString(),@"\.A{"+(maxCombo+1)+@",}$"))) {removed++;return false;} return true;
                }).ToArray();
                foreach(var v in a.Value) Walk(v);
            } else if(p is StructPropertyData s) foreach(var v in s.Value) Walk(v);
        }
        foreach(var e in asset.Exports.OfType<NormalExport>()) foreach(var p in e.Data) Walk(p);
        asset.Write(args[2]); Console.WriteLine($"removed {removed} sixth-hit bindings"); return 0;
    }
    case "montagewindow":
    {
        var culture = System.Globalization.CultureInfo.InvariantCulture;
        double start = double.Parse(args[3], culture), end = double.Parse(args[4], culture);
        double rate = args.Length > 5 ? double.Parse(args[5], culture) : 1;
        if (!double.IsFinite(start) || !double.IsFinite(end) || start < 0 || end <= start
            || !double.IsFinite(rate) || rate <= 0)
            throw new Exception("Invalid montage window or play rate");
        double length = (end - start) / rate;
        bool wroteRate = false;
        void WalkWindow(PropertyData p){
            string n = p.Name.ToString();
            double? value = n switch
            {
                "AnimStartTime" => start,
                "AnimEndTime" => end,
                "SequenceLength" or "SegmentLength" => length,
                "AnimPlayRate" when args.Length > 5 => rate,
                _ => null
            };
            if (value.HasValue)
            {
                if (p is FloatPropertyData f) f.Value = (float)value.Value;
                else if (p is DoublePropertyData d) d.Value = value.Value;
                else throw new Exception($"Unsupported montage field type for {n}");
                if (n == "AnimPlayRate") wroteRate = true;
            }
            if(p is StructPropertyData st)foreach(var c in st.Value)WalkWindow(c);
            if(p is ArrayPropertyData a)foreach(var c in a.Value)WalkWindow(c);
        }
        foreach(var e in asset.Exports.OfType<NormalExport>())foreach(var p in e.Data)WalkWindow(p);
        if (args.Length > 5 && !wroteRate) throw new Exception("Montage has no serialized AnimPlayRate");
        asset.Write(args[2]);return 0;
    }
    case "montagecatch":
    {
        var culture = System.Globalization.CultureInfo.InvariantCulture;
        float sourceStart = float.Parse(args[3], culture);
        float duration = float.Parse(args[4], culture);
        var montage = asset.Exports.OfType<NormalExport>().Single();
        var length = montage.Data.OfType<FloatPropertyData>().Single(p => p.Name.ToString() == "SequenceLength");
        var slots = montage.Data.OfType<ArrayPropertyData>().Single(p => p.Name.ToString() == "SlotAnimTracks");
        var slot = slots.Value.Cast<StructPropertyData>().Single();
        var track = slot.Value.OfType<StructPropertyData>().Single(p => p.Name.ToString() == "AnimTrack");
        var segments = track.Value.OfType<ArrayPropertyData>().Single(p => p.Name.ToString() == "AnimSegments");
        var hold = segments.Value.Cast<StructPropertyData>().Single();
        var recoil = (StructPropertyData)hold.Clone();
        recoil.Name = FName.FromString(asset, "1");
        recoil.Value = hold.Value.Select(p => (PropertyData)p.Clone()).ToList();
        FloatPropertyData Field(string name) => recoil.Value.OfType<FloatPropertyData>().Single(p => p.Name.ToString() == name);
        float sourceEnd = Field("AnimEndTime").Value;
        if (!float.IsFinite(sourceStart) || sourceStart < 0 || sourceStart >= sourceEnd
            || !float.IsFinite(duration) || duration <= 0)
            throw new Exception("Invalid catch recoil window");
        var startPosition = Field("StartPos");
        startPosition.Value = length.Value;
        startPosition.IsZero = false;
        Field("AnimStartTime").Value = sourceStart;
        Field("AnimPlayRate").Value = (sourceStart - sourceEnd) / duration;
        segments.Value = new PropertyData[] { hold, recoil };
        length.Value += duration;
        asset.Write(args[2]);
        return 0;
    }
    case "montagetrim":
    {
        double end=double.Parse(args[3]);int hits=0;
        void Walk(PropertyData p){
            if(p is FloatPropertyData f && p.Name.ToString() is "SequenceLength" or "SegmentLength" or "AnimEndTime"){f.Value=(float)end;hits++;}
            if(p is DoublePropertyData d && p.Name.ToString() is "SequenceLength" or "SegmentLength" or "AnimEndTime"){d.Value=end;hits++;}
            if(p is StructPropertyData s)foreach(var c in s.Value)Walk(c);
            if(p is ArrayPropertyData a)foreach(var c in a.Value)Walk(c);
        }
        foreach(var e in asset.Exports.OfType<NormalExport>())foreach(var p in e.Data)Walk(p);
        if(hits<2)throw new Exception("Not enough montage segment fields found");
        asset.Write(args[2]);Console.WriteLine($"trimmed {hits} montage fields to {end}");return 0;
    }
    case "aimkeep":
    {
        var names=args.Skip(3).ToHashSet();var e=asset.Exports.OfType<NormalExport>().First(x=>x.Data.Any(p=>p.Name.ToString()=="Bindings"));
        var a=(ArrayPropertyData)e.Data.First(p=>p.Name.ToString()=="Bindings");
        a.Value=a.Value.Where(v=>v is StructPropertyData s && s.Value.OfType<StrPropertyData>().Any(t=>t.Name.ToString()=="Description" && names.Contains(t.Value.Value))).ToArray();
        if(a.Value.Length!=names.Count)throw new Exception("Binding count mismatch");asset.Write(args[2]);return 0;
    }
    case "addcombobinding":
    {
        int AddImport(string path,string name,string cp,string cls){
            int pi=asset.Imports.FindIndex(i=>i.ObjectName.ToString()==path && i.ClassName.ToString()=="Package");
            if(pi<0){pi=asset.Imports.Count;asset.Imports.Add(new Import{ObjectName=FName.FromString(asset,path),ClassName=FName.FromString(asset,"Package"),ClassPackage=FName.FromString(asset,"/Script/CoreUObject"),OuterIndex=new FPackageIndex(0)});}
            int ni=asset.Imports.Count;asset.Imports.Add(new Import{ObjectName=FName.FromString(asset,name),ClassName=FName.FromString(asset,cls),ClassPackage=FName.FromString(asset,cp),OuterIndex=FPackageIndex.FromImport(pi)});return ni;
        }
        var map=(MapPropertyData)asset.Exports.OfType<NormalExport>().SelectMany(x=>x.Data).First(p=>p.Name.ToString()=="Weapon Combos");
        int key=AddImport(args[3],args[4],"/Script/EnhancedInput","InputAction");int val=AddImport(args[5],args[6],"/Script/SGameInputSystem","InputActionBinding");
        map.Value.Add(new ObjectPropertyData(FName.FromString(asset,"Weapon Combos")){Value=FPackageIndex.FromImport(key)},new ObjectPropertyData(FName.FromString(asset,"Weapon Combos")){Value=FPackageIndex.FromImport(val)});
        asset.Write(args[2]);return 0;
    }
    case "radius":
    {
        var st=asset.Exports.OfType<NormalExport>().SelectMany(e=>e.Data).OfType<StructPropertyData>().First(p=>p.Name.ToString()=="ColliderData");
        var p=st.Value.First(v=>v.Name.ToString()=="Radius");
        if(p is FloatPropertyData f)f.Value=float.Parse(args[3]);else if(p is DoublePropertyData d)d.Value=double.Parse(args[3]);else throw new Exception("Radius type unsupported");
        asset.Write(args[2]);return 0;
    }
    case "info":
        Console.WriteLine($"package flags: {asset.PackageFlags}  unversioned: {asset.HasUnversionedProperties}");
        Console.WriteLine($"imports: {asset.Imports.Count}  exports: {asset.Exports.Count}");
        foreach (var imp in asset.Imports.Take(40))
            Console.WriteLine($"  import {imp.ClassName} {imp.ObjectName}");
        foreach (var exp in asset.Exports)
        {
            Console.WriteLine($"  export {exp.GetType().Name} {exp.ObjectName}  serialSize={exp.SerialSize}  extras={exp.Extras?.Length ?? 0}  props={(exp as NormalExport)?.Data.Count}");
            if (exp is NormalExport ne)
                foreach (var p in ne.Data.Take(40))
                    Console.WriteLine($"      {p.Name} : {p.PropertyType}");
        }
        return 0;
    case "roundtrip":
        asset.Write(args[2]);
        Console.WriteLine($"written {args[2]}");
        return 0;
    case "addrow":
    {
        var table = asset.Exports.OfType<DataTableExport>().FirstOrDefault() ?? throw new Exception("no DataTable export");
        var rows = table.Table.Data;
        var src = rows.FirstOrDefault(r => r.Name.Value.Value == args[3]) ?? throw new Exception($"row {args[3]} not found");
        // the new row's name may come from a file too ("@file"): long text keys
        if (args[4].StartsWith('@')) args[4] = File.ReadAllText(args[4][1..], System.Text.Encoding.UTF8).Trim();
        if (rows.Any(r => r.Name.Value.Value == args[4])) throw new Exception($"row {args[4]} already exists");
        var row = (StructPropertyData)src.Clone();
        row.Name = FName.FromString(asset, args[4]);
        foreach (var assignment in args.Skip(5))
        {
            var (field, value) = (assignment[..assignment.IndexOf('=')], assignment[(assignment.IndexOf('=') + 1)..]);
            // "@file" reads the value from a UTF-8 file (shells mangle quotes and long text)
            if (value.StartsWith('@')) value = File.ReadAllText(value[1..], System.Text.Encoding.UTF8).Trim();
            // dotted fields reach into struct members: WeaponSnapSoulData.WeaponConfig
            PropertyData? prop = null; var members = row.Value;
            foreach (var part in field.Split('.'))
            {
                prop = members?.FirstOrDefault(p => p.Name.Value.Value == part) ?? throw new Exception($"field {field} not in row");
                members = (prop as StructPropertyData)?.Value;
            }
            switch (prop)
            {
                case SoftObjectPropertyData soft when value == "":   // clear the reference
                    soft.Value = new FSoftObjectPath(FName.FromString(asset, "None"), FName.FromString(asset, "None"), null);
                    break;
                case SoftObjectPropertyData soft:
                    var dot = value.LastIndexOf('.');
                    soft.Value = new FSoftObjectPath(FName.FromString(asset, value[..dot]), FName.FromString(asset, value[(dot + 1)..]), null);
                    break;
                case NamePropertyData name:
                    name.Value = FName.FromString(asset, value);
                    break;
                case StrPropertyData str:
                    str.Value = new FString(value);
                    break;
                case TextPropertyData text:
                    // localizable text with a key the game's tables don't have, so the source string is shown as-is
                    text.HistoryType = TextHistoryType.Base;
                    text.Namespace = new FString("MjolnirMod");
                    text.Value = new FString($"{args[4]}_{field}");
                    text.CultureInvariantString = new FString(value);
                    break;
                case StructPropertyData st when st.Value.OfType<StrPropertyData>().Any(m => m.Name.Value.Value == "Key")
                                             && st.Value.OfType<TextPropertyData>().Any(m => m.Name.Value.Value == "ValueCache"):
                    // FlowLocText (Namespace, Key, ValueCache): the key isn't in the game's tables, so make the key and
                    // (key only: see LocKey)
                    LocKey(st, value);
                    break;
                case StructPropertyData st:
                    throw new Exception($"field {field} is a {st.StructType} struct: " +
                        string.Join(", ", st.Value.Select(m => $"{m.Name}:{m.GetType().Name}={m.ToString()}")));
                default:
                    throw new Exception($"field {field} is {prop.GetType().Name}, not supported");
            }
            Console.WriteLine($"  {field} = {value}");
        }
        rows.Add(row);
        Directory.CreateDirectory(Path.GetDirectoryName(args[2])!);
        asset.Write(args[2]);
        Console.WriteLine($"added row {args[4]} (copy of {args[3]}), table now {rows.Count} rows -> {args[2]}");
        return 0;
    }
    case "damageset":
    {
        // damageset <in> <out> Tag=value ...: set (or add) entries of a bullet's DamageData map, keyed by gameplay
        // tag (e.g. Damage.Attack.Target.LightningDamage=0.15).  New entries copy an existing key/value pair.
        var exp = asset.Exports.OfType<NormalExport>().FirstOrDefault(e => e.Data.Any(p => p.Name.ToString() == "DamageData" && p is MapPropertyData))
                  ?? throw new Exception("no DamageData map");
        var map = (MapPropertyData)exp.Data.First(p => p.Name.ToString() == "DamageData" && p is MapPropertyData);
        if (map.Value.Count == 0) throw new Exception("DamageData is empty; nothing to copy");
        string TagOf(PropertyData key) => ((StructPropertyData)key).Value.OfType<NamePropertyData>().First(n => n.Name.ToString() == "TagName").Value.ToString();
        foreach (var spec in args.Skip(3))
        {
            var (tag, value) = (spec[..spec.LastIndexOf('=')], float.Parse(spec[(spec.LastIndexOf('=') + 1)..], System.Globalization.CultureInfo.InvariantCulture));
            var pairs = map.Value.ToList();
            var hit = pairs.FirstOrDefault(kv => TagOf(kv.Key) == tag);
            if (hit.Key != null) { ((FloatPropertyData)hit.Value).Value = value; Console.WriteLine($"  {tag} = {value}"); continue; }
            var first = pairs[0];
            var key = (StructPropertyData)first.Key.Clone();
            key.Value.OfType<NamePropertyData>().First(n => n.Name.ToString() == "TagName").Value = FName.FromString(asset, tag);
            var val = (FloatPropertyData)first.Value.Clone(); val.Value = value;
            map.Value.Add(key, val);
            Console.WriteLine($"  + {tag} = {value}");
        }
        asset.Write(args[2]);
        return 0;
    }
    case "tagmapset":
    {
        // tagmapset <in> <out> <MapProp> Tag=value ...: like damageset, for any gameplay-tag -> float map on the
        // first export that has it (e.g. a weapon config's "Weapon Attack Multipliers").  New entries copy the first pair.
        var exp = asset.Exports.OfType<NormalExport>().FirstOrDefault(e => e.Data.Any(p => p.Name.ToString() == args[3] && p is MapPropertyData))
                  ?? throw new Exception($"no {args[3]} map");
        var map = (MapPropertyData)exp.Data.First(p => p.Name.ToString() == args[3] && p is MapPropertyData);
        if (map.Value.Count == 0) throw new Exception($"{args[3]} is empty; nothing to copy");
        string TagOf(PropertyData key) => ((StructPropertyData)key).Value.OfType<NamePropertyData>().First(n => n.Name.ToString() == "TagName").Value.ToString();
        foreach (var spec in args.Skip(4))
        {
            var (tag, value) = (spec[..spec.LastIndexOf('=')], float.Parse(spec[(spec.LastIndexOf('=') + 1)..], System.Globalization.CultureInfo.InvariantCulture));
            var pairs = map.Value.ToList();
            var hit = pairs.FirstOrDefault(kv => TagOf(kv.Key) == tag);
            void Put(PropertyData v) { if (v is FloatPropertyData f) f.Value = value; else if (v is DoublePropertyData d) d.Value = value; else throw new Exception(v.GetType().Name); }
            if (hit.Key != null) { Put(hit.Value); Console.WriteLine($"  {tag} = {value}"); continue; }
            var key = (StructPropertyData)pairs[0].Key.Clone();
            key.Value.OfType<NamePropertyData>().First(n => n.Name.ToString() == "TagName").Value = FName.FromString(asset, tag);
            var val = (PropertyData)pairs[0].Value.Clone(); Put(val);
            map.Value.Add(key, val);
            Console.WriteLine($"  + {tag} = {value}");
        }
        asset.Write(args[2]);
        return 0;
    }
    case "tagreplace":
    {
        // tagreplace <in> <out> <oldTag> <newTag>: swap a tag inside every gameplay tag container of the asset
        var from = args[3]; var to = FName.FromString(asset, args[4]); int n = 0;
        void Walk(PropertyData p)
        {
            if (p is GameplayTagContainerPropertyData g)
                g.Value = g.Value.Select(t => { if (t.ToString() == from) { n++; return to; } return t; }).ToArray();
            else if (p is StructPropertyData s) foreach (var c in s.Value) Walk(c);
            else if (p is ArrayPropertyData a) foreach (var c in a.Value) Walk(c);
        }
        foreach (var e in asset.Exports.OfType<NormalExport>()) foreach (var p in e.Data) Walk(p);
        if (n == 0) throw new Exception($"tag {from} not found");
        asset.Write(args[2]);
        Console.WriteLine($"  {from} -> {args[4]} ({n})");
        return 0;
    }
    case "weaponmoveremove":
    {
        // weaponmoveremove <table.uasset> <out> <row> <index>: drop one entry of a weapon's move list
        var table = asset.Exports.OfType<DataTableExport>().FirstOrDefault() ?? throw new Exception("no DataTable export");
        var row = table.Table.Data.FirstOrDefault(r => r.Name.Value.Value == args[3]) ?? throw new Exception($"row {args[3]} not found");
        var list = row.Value.OfType<ArrayPropertyData>().First(p => p.Name.Value.Value is "WeaponAbilityDesc" or "AbilityDesc");
        int i = int.Parse(args[4]); if (i < 0 || i >= list.Value.Length) throw new Exception("index out of range");
        list.Value = list.Value.Where((_, k) => k != i).ToArray();
        asset.Write(args[2]);
        Console.WriteLine($"move list {args[3]}: removed entry {i} ({list.Value.Length} left)");
        return 0;
    }
    case "rowset":
    {
        // rowset <table.uasset> <out> <row> Field.Sub=value ...: set a field of an existing row.  Path parts may
        // index arrays: WeaponUpLevelDatas[4].GEDatas[0].WeaponTitle.  Values: names, strings, text keys
        // (FlowLocText: key and cached text both set), soft references ("" clears to None); "@file" reads the value.
        var table = asset.Exports.OfType<DataTableExport>().FirstOrDefault() ?? throw new Exception("no DataTable export");
        var row = table.Table.Data.FirstOrDefault(r => r.Name.Value.Value == args[3]) ?? throw new Exception($"row {args[3]} not found");
        foreach (var spec in args.Skip(4))
        {
            var (field, value) = (spec[..spec.IndexOf('=')], spec[(spec.IndexOf('=') + 1)..]);
            if (value.StartsWith('@')) value = File.ReadAllText(value[1..], System.Text.Encoding.UTF8).Trim();
            PropertyData? prop = null; var members = row.Value;
            foreach (var raw in field.Split('.'))
            {
                var m = System.Text.RegularExpressions.Regex.Match(raw, @"^(\w+)(?:\[(\d+)\])?$");
                if (!m.Success) throw new Exception($"bad path part {raw}");
                prop = members?.FirstOrDefault(p => p.Name.Value.Value == m.Groups[1].Value) ?? throw new Exception($"field {field} not in row");
                if (m.Groups[2].Success)
                {
                    var arr = prop as ArrayPropertyData ?? throw new Exception($"{m.Groups[1].Value} is not an array");
                    int i = int.Parse(m.Groups[2].Value);
                    if (i >= arr.Value.Length) throw new Exception($"{raw} is out of range ({arr.Value.Length})");
                    prop = arr.Value[i];
                }
                members = (prop as StructPropertyData)?.Value;
            }
            switch (prop)
            {
                case NamePropertyData n: n.Value = FName.FromString(asset, value); break;
                case StrPropertyData s: s.Value = new FString(value); break;
                case FloatPropertyData f: f.Value = float.Parse(value, System.Globalization.CultureInfo.InvariantCulture); break;
                case DoublePropertyData d: d.Value = double.Parse(value, System.Globalization.CultureInfo.InvariantCulture); break;
                case EnumPropertyData en: en.Value = FName.FromString(asset, value); break;   // e.g. EWeaponLevel::Epic
                case SoftObjectPropertyData soft when value == "":
                    soft.Value = new FSoftObjectPath(FName.FromString(asset, "None"), FName.FromString(asset, "None"), null); break;
                case SoftObjectPropertyData soft:   // /Package/Path.AssetName
                    var dot = value.LastIndexOf('.');
                    soft.Value = new FSoftObjectPath(FName.FromString(asset, value[..dot]), FName.FromString(asset, value[(dot + 1)..]), null); break;
                case ArrayPropertyData arr when value == "[]":
                    arr.Value = Array.Empty<PropertyData>(); break;
                case StructPropertyData st when st.Value.OfType<StrPropertyData>().Any(x => x.Name.Value.Value == "Key")
                                             && st.Value.OfType<TextPropertyData>().Any(x => x.Name.Value.Value == "ValueCache"):
                    LocKey(st, value);
                    break;
                default: throw new Exception($"field {field} is {prop?.GetType().Name}, not supported");
            }
            Console.WriteLine($"  {args[3]}.{field} = {value}");
        }
        asset.Write(args[2]);
        return 0;
    }
    case "setnestedenum":
    {
        // setnestedenum <in> <out> <export> Struct.Field=Value ...: set an enum (or name) field inside a struct property.
        var e = asset.Exports.OfType<NormalExport>().First(x => x.ObjectName.ToString() == args[3]);
        foreach (var spec in args.Skip(4))
        {
            var (path, value) = (spec[..spec.IndexOf('=')].Split('.'), spec[(spec.IndexOf('=') + 1)..]);
            var list = e.Data;
            for (int i = 0; i < path.Length - 1; i++) list = ((StructPropertyData)list.First(p => p.Name.ToString() == path[i])).Value;
            var field = list.FirstOrDefault(p => p.Name.ToString() == path[^1]);
            switch (field)
            {
                case EnumPropertyData en: en.Value = FName.FromString(asset, value); break;
                case BytePropertyData by when by.ByteType == BytePropertyType.FName: by.EnumValue = FName.FromString(asset, value); break;
                case NamePropertyData nm: nm.Value = FName.FromString(asset, value); break;
                case null:
                    // not set explicitly (the default): add it, copying the enum type from the usmap would be needed,
                    // so only allow it when a sibling enum of the same type exists is not attempted -- report instead
                    throw new Exception($"{string.Join('.', path)} is not set explicitly on {args[3]}");
                default: throw new Exception($"{string.Join('.', path)} is {field.GetType().Name}");
            }
            Console.WriteLine($"  {args[3]}.{string.Join('.', path)} = {value}");
        }
        asset.Write(args[2]);
        return 0;
    }
    case "setfloatwhere":
    {
        // setfloatwhere <in> <out> <export> <old> <new>: change every float/double property equal to <old> (within
        // 1e-4) anywhere inside one export to <new>; prints how many changed and fails if none.
        var e = asset.Exports.OfType<NormalExport>().First(x => x.ObjectName.ToString() == args[3]);
        double from = double.Parse(args[4], System.Globalization.CultureInfo.InvariantCulture), to = double.Parse(args[5], System.Globalization.CultureInfo.InvariantCulture);
        int n = 0;
        void Walk(PropertyData p)
        {
            if (p is FloatPropertyData f && Math.Abs(f.Value - from) < 1e-4) { f.Value = (float)to; n++; }
            else if (p is DoublePropertyData d && Math.Abs(d.Value - from) < 1e-4) { d.Value = to; n++; }
            else if (p is VectorPropertyData v)
            {
                var x = v.Value.X; var y = v.Value.Y; var z = v.Value.Z;
                if (Math.Abs(x - from) < 1e-4) { x = to; n++; }
                if (Math.Abs(y - from) < 1e-4) { y = to; n++; }
                if (Math.Abs(z - from) < 1e-4) { z = to; n++; }
                v.Value = new FVector(x, y, z);
            }
            else if (p is StructPropertyData s) foreach (var c in s.Value) Walk(c);
            else if (p is ArrayPropertyData a) foreach (var c in a.Value) Walk(c);
        }
        foreach (var p in e.Data) Walk(p);
        if (n == 0) throw new Exception($"no value {from} in {args[3]}");
        asset.Write(args[2]);
        Console.WriteLine($"  {args[3]}: {n} value(s) {from} -> {to}");
        return 0;
    }
    case "tlcopy":
    {
        // tlcopy <in> <out> <fromTimeline> <toTimeline>: make one ability timeline play exactly what another does
        // (same entries pointing at the same action objects, same length).  The target keeps its own export.
        var src = asset.Exports.OfType<NormalExport>().FirstOrDefault(e => e.ObjectName.ToString() == args[3] && e.Data.Any(p => p.Name.ToString() == "Actions")) ?? throw new Exception($"timeline {args[3]} not found");
        var dst = asset.Exports.OfType<NormalExport>().FirstOrDefault(e => e.ObjectName.ToString() == args[4] && e.Data.Any(p => p.Name.ToString() == "Actions")) ?? throw new Exception($"timeline {args[4]} not found");
        if (asset.Exports[asset.Exports.IndexOf(src)].GetExportClassType().ToString() != asset.Exports[asset.Exports.IndexOf(dst)].GetExportClassType().ToString())
            throw new Exception("timelines are of different classes");
        dst.Data = src.Data.Select(p => (PropertyData)p.Clone()).ToList();
        asset.Write(args[2]);
        Console.WriteLine($"timeline {args[4]} now plays {args[3]} ({((ArrayPropertyData)dst.Data.First(p => p.Name.ToString() == "Actions")).Value.Length} entries) -> {args[2]}");
        return 0;
    }
    case "cdoint":
    {
        // cdoint <in> <out> "<Property Name>" <value>: add (or replace) an int on the class defaults, e.g. an
        // inherited blueprint setting the asset does not override yet ("Ultimate Charge Cost").
        var cdo = asset.Exports.OfType<NormalExport>().First(e => e.ObjectName.ToString().StartsWith("Default__"));
        cdo.Data.RemoveAll(p => p.Name.ToString() == args[3]);
        cdo.Data.Add(new IntPropertyData(FName.FromString(asset, args[3])) { Value = int.Parse(args[4]) });
        asset.Write(args[2]);
        Console.WriteLine($"  {cdo.ObjectName}.{args[3]} = {args[4]} -> {args[2]}");
        return 0;
    }
    case "weaponmove":
    {
        // weaponmove <table.uasset> <out> <row> <index|append> <title> <description>
        // Sets one entry of a weapon's move list (WeaponAbilityDesc: WeaponTitle + WeaponDesc), or appends a copy of
        // the last entry with this text.  Text is written like addrow's FlowLocText: key and cached text are the
        // display string, so whichever the lookup falls back to reads right; the game's rich-text tags work inside.
        var table = asset.Exports.OfType<DataTableExport>().FirstOrDefault() ?? throw new Exception("no DataTable export");
        var row = table.Table.Data.FirstOrDefault(r => r.Name.Value.Value == args[3]) ?? throw new Exception($"row {args[3]} not found");
        // DT_WeaponData rows call it WeaponAbilityDesc; DT_WeaponSnapSoulText rows, AbilityDesc
        var list = row.Value.OfType<ArrayPropertyData>().FirstOrDefault(p => p.Name.Value.Value is "WeaponAbilityDesc" or "AbilityDesc") ?? throw new Exception("row has no move list");
        StructPropertyData entry;
        if (args[4] == "append")
        {
            if (list.Value.Length == 0) throw new Exception("no entry to copy");
            entry = (StructPropertyData)list.Value[^1].Clone();
            list.Value = list.Value.Append(entry).ToArray();
        }
        else entry = (StructPropertyData)list.Value[int.Parse(args[4])];
        void SetText(string field, string value)
        {
            var st = entry.Value.OfType<StructPropertyData>().FirstOrDefault(m => m.Name.Value.Value == field) ?? throw new Exception($"entry has no {field}");
            LocKey(st, value);
        }
        // "@file" reads the text from a UTF-8 file (shells mangle the quotes in rich-text tags).
        string Arg(string a) => a.StartsWith('@') ? File.ReadAllText(a[1..], System.Text.Encoding.UTF8).Trim() : a;
        SetText("WeaponTitle", Arg(args[5]));
        SetText("WeaponDesc", Arg(args[6]));
        asset.Write(args[2]);
        Console.WriteLine($"move list {args[3]}[{args[4]}] = {args[5]} ({list.Value.Length} entries) -> {args[2]}");
        return 0;
    }
    case "setsocket":
    {
        var wanted = args.Skip(3).Select(a => (Name: a[..a.LastIndexOf('=')], Pos: a[(a.LastIndexOf('=') + 1)..].Split(',').Select(double.Parse).ToArray())).ToList();
        var done = new HashSet<string>();
        foreach (var exp in asset.Exports.OfType<NormalExport>())
        {
            var nameProp = exp.Data.OfType<NamePropertyData>().FirstOrDefault(p => p.Name.Value.Value == "SocketName");
            if (nameProp == null) continue;
            var socket = nameProp.Value.Value.Value;
            var w = wanted.FirstOrDefault(x => x.Name == socket);
            if (w.Name == null) { Console.WriteLine($"  keep {socket}"); continue; }
            var loc = exp.Data.OfType<StructPropertyData>().FirstOrDefault(p => p.Name.Value.Value == "RelativeLocation");
            var vec = new FVector(w.Pos[0], w.Pos[1], w.Pos[2]);
            if (loc == null)
            {
                loc = new StructPropertyData(FName.FromString(asset, "RelativeLocation"), FName.FromString(asset, "Vector"))
                { Value = new List<PropertyData> { new VectorPropertyData(FName.FromString(asset, "RelativeLocation")) { Value = vec } } };
                exp.Data.Add(loc);
            }
            else
            {
                var v = loc.Value.OfType<VectorPropertyData>().FirstOrDefault();
                if (v != null) v.Value = vec;
                else loc.Value = new List<PropertyData> { new VectorPropertyData(FName.FromString(asset, "RelativeLocation")) { Value = vec } };
            }
            done.Add(socket);
            Console.WriteLine($"  moved {socket} -> {w.Pos[0]},{w.Pos[1]},{w.Pos[2]}");
        }
        foreach (var w in wanted.Where(w => !done.Contains(w.Name))) Console.WriteLine($"  NOT FOUND {w.Name}");
        asset.Write(args[2]);
        Console.WriteLine($"sockets moved: {done.Count} -> {args[2]}");
        return done.Count == wanted.Count ? 0 : 2;
    }
    case "retarget":
    {
        // every object reference (in any export, at any depth) to import From is pointed at import To instead;
        // To = null clears the reference
        var pairs = args.Skip(3).Select(a => a.Split('=', 2)).ToList();
        FPackageIndex Find(string name)
        {
            for (int i = 0; i < asset.Imports.Count; i++)
                if (asset.Imports[i].ObjectName.Value.Value == name) return FPackageIndex.FromImport(i);
            throw new Exception($"import {name} not found");
        }
        // To = remove drops the reference from any array that holds it
        var map = pairs.ToDictionary(p => Find(p[0]).Index, p => p[1] is "null" or "remove" ? new FPackageIndex(0) : Find(p[1]));
        var remove = pairs.Where(p => p[1] == "remove").Select(p => Find(p[0]).Index).ToHashSet();
        int hits = 0;
        void Walk(PropertyData p)
        {
            switch (p)
            {
                case ObjectPropertyData o when o.Value != null && map.TryGetValue(o.Value.Index, out var to):
                    o.Value = to; hits++; break;
                case StructPropertyData s: foreach (var m in s.Value) Walk(m); break;
                case ArrayPropertyData a:
                    int before = a.Value.Length;
                    a.Value = a.Value.Where(m => !(m is ObjectPropertyData o && o.Value != null && remove.Contains(o.Value.Index))).ToArray();
                    hits += before - a.Value.Length;
                    foreach (var m in a.Value) Walk(m);
                    break;
                case MapPropertyData mp: foreach (var kv in mp.Value) { Walk(kv.Key); Walk(kv.Value); } break;
            }
        }
        foreach (var exp in asset.Exports.OfType<NormalExport>()) foreach (var p in exp.Data) Walk(p);
        asset.Write(args[2]);
        Console.WriteLine($"retargeted {hits} references -> {args[2]}");
        return hits > 0 ? 0 : 2;
    }
    case "setimport":
    {
        // repoint one import: Name=/New/Package|NewName|/Class/Package|ClassName (its package import is renamed too)
        int done = 0;
        foreach (var spec in args.Skip(3))
        {
            var (name, rest) = (spec[..spec.IndexOf('=')], spec[(spec.IndexOf('=') + 1)..].Split('|'));
            var imp = asset.Imports.FirstOrDefault(i => i.ObjectName.Value.Value == name && i.ClassName.Value.Value != "Package")
                      ?? throw new Exception($"import {name} not found");
            var pkg = imp.OuterIndex.IsImport() ? imp.OuterIndex.ToImport(asset) : throw new Exception($"{name} has no package import");
            pkg.ObjectName = FName.FromString(asset, rest[0]);
            imp.ObjectName = FName.FromString(asset, rest[1]);
            imp.ClassPackage = FName.FromString(asset, rest[2]);
            imp.ClassName = FName.FromString(asset, rest[3]);
            Console.WriteLine($"  {name} -> {rest[0]}.{rest[1]} ({rest[3]})");
            done++;
        }
        asset.Write(args[2]);
        Console.WriteLine($"set {done} imports -> {args[2]}");
        return 0;
    }
    case "aimadd":
    {
        // add an input binding to an InputActionBinding (AIM): aimadd <in> <out> <priority> <description> <triggerTag> <required,tags> [ignored,tags]
        // copies an existing binding that has exactly one action, then sets that action and drops its combos
        var exp = asset.Exports.OfType<NormalExport>().First(e => e.Data.Any(p => p.Name.Value.Value == "Bindings"));
        var bindings = (ArrayPropertyData)exp.Data.First(p => p.Name.Value.Value == "Bindings");
        StructPropertyData Member(StructPropertyData s, string n) => (StructPropertyData)s.Value.First(p => p.Name.Value.Value == n);
        PropertyData Field(StructPropertyData s, string n) => s.Value.First(p => p.Name.Value.Value == n);
        // template: any binding with an action or a combo entry (both arrays hold the same action struct)
        PropertyData[] Entries(StructPropertyData b, string n) => ((ArrayPropertyData)Field(Member(b, "NormalData"), n)).Value;
        var src = bindings.Value.Cast<StructPropertyData>().First(b => Entries(b, "Actions").Length + Entries(b, "Combos").Length > 0);
        var template = Entries(src, "Actions").Concat(Entries(src, "Combos")).First();
        var nb = (StructPropertyData)src.Clone();
        ((IntPropertyData)Field(nb, "ActionPriority")).Value = int.Parse(args[3]);
        ((StrPropertyData)Field(nb, "Description")).Value = new FString(args[4]);
        var normal = Member(nb, "NormalData");
        ((ArrayPropertyData)Field(normal, "Combos")).Value = Array.Empty<PropertyData>();
        var action = (StructPropertyData)template.Clone();
        action.Name = Entries(src, "Actions").Length > 0 ? Entries(src, "Actions")[0].Name : FName.FromString(asset, "Actions");
        ((ArrayPropertyData)Field(normal, "Actions")).Value = new PropertyData[] { action };
        ((StrPropertyData)Field(action, "Description")).Value = new FString(args[4]);
        FName[] Tags(int i) => args.Length > i && args[i].Length > 0 ? args[i].Split(',').Select(t => FName.FromString(asset, t)).ToArray() : Array.Empty<FName>();
        // tag containers come wrapped in a struct: StructProperty(GameplayTagContainer) -> GameplayTagContainerPropertyData
        GameplayTagContainerPropertyData TagBox(string n) => Field(action, n) switch
        {
            GameplayTagContainerPropertyData g => g,
            StructPropertyData s => s.Value.OfType<GameplayTagContainerPropertyData>().First(),
            var other => throw new Exception($"{n} is {other.GetType().Name}")
        };
        TagBox("RequiredTags").Value = Tags(6);
        TagBox("IgnoredTags").Value = Tags(7);
        ((NamePropertyData)Member(action, "TriggerTag").Value[0]).Value = FName.FromString(asset, args[5]);
        bindings.Value = bindings.Value.Prepend(nb).ToArray();
        asset.Write(args[2]);
        Console.WriteLine($"added binding '{args[4]}' prio {args[3]} -> {args[5]} ({bindings.Value.Length} bindings) -> {args[2]}");
        return 0;
    }
    case "aimmode":
    {
        var bindings=asset.Exports.OfType<NormalExport>().SelectMany(e=>e.Data).OfType<ArrayPropertyData>().First(p=>p.Name.ToString()=="Bindings");
        var binding=bindings.Value.Cast<StructPropertyData>().Single(b=>b.Value.OfType<StrPropertyData>().Any(p=>p.Name.ToString()=="Description"&&p.Value.Value==args[3]));
        var normal=binding.Value.OfType<StructPropertyData>().First(p=>p.Name.ToString()=="NormalData");
        var actions=normal.Value.OfType<ArrayPropertyData>().First(p=>p.Name.ToString()=="Actions");
        var combos=normal.Value.OfType<ArrayPropertyData>().First(p=>p.Name.ToString()=="Combos");
        var entry=(StructPropertyData)actions.Value.Concat(combos.Value).First().Clone();
        actions.Value=Array.Empty<PropertyData>();combos.Value=Array.Empty<PropertyData>();
        if(args[4] is "action" or "both"){var p=(StructPropertyData)entry.Clone();p.Name=actions.Name;actions.Value=new PropertyData[]{p};}
        if(args[4] is "combo" or "both"){var p=(StructPropertyData)entry.Clone();p.Name=combos.Name;combos.Value=new PropertyData[]{p};}
        if(args[4] is not ("action" or "combo" or "both"))throw new Exception("Expected action, combo or both");
        asset.Write(args[2]);return 0;
    }
    case "tl":
    {
        // edit an ability timeline: tl <in> <out> <timeline> Action=start[:duration] ... -Action (remove)
        // Action is the name of the action object the entry points at (e.g. LGAAction_PlayMontage_0)
        var tl = asset.Exports.OfType<NormalExport>().FirstOrDefault(e => e.ObjectName.Value.Value == args[3] && e.Data.Any(p => p.Name.Value.Value == "Actions"))
                 ?? throw new Exception($"timeline {args[3]} not found");
        var actions = (ArrayPropertyData)tl.Data.First(p => p.Name.Value.Value == "Actions");
        string ActionName(StructPropertyData entry)
        {
            var o = (ObjectPropertyData)entry.Value.First(p => p.Name.Value.Value == "Action");
            return o.Value.IsExport() ? o.Value.ToExport(asset).ObjectName.ToString() : "";   // with the _N suffix
        }
        var list = actions.Value.Cast<StructPropertyData>().ToList();
        if (args.Length == 4) { foreach (var e in list) Console.WriteLine($"  entry: '{ActionName(e)}' fields: {string.Join(",", e.Value.Select(v => v.Name.Value.Value + ":" + v.GetType().Name))}"); return 0; }
        foreach (var spec in args.Skip(4))
        {
            if (spec.StartsWith('-'))
            {
                int n = list.RemoveAll(e => ActionName(e) == spec[1..]);
                Console.WriteLine($"  removed {spec[1..]} ({n})");
                if (n == 0) throw new Exception($"no entry for {spec[1..]}");
                continue;
            }
            var (name, val) = (spec[..spec.IndexOf('=')], spec[(spec.IndexOf('=') + 1)..].Split(':'));
            var entry = list.FirstOrDefault(e => ActionName(e) == name) ?? throw new Exception($"no entry for {name}");
            void Set(string field, string v)
            {
                var p = entry.Value.First(q => q.Name.Value.Value == field);
                switch (p) { case FloatPropertyData f: f.Value = float.Parse(v); break; case DoublePropertyData d: d.Value = double.Parse(v); break; default: throw new Exception($"{field} is {p.GetType().Name}"); }
            }
            Set("StartTime", val[0]);
            if (val.Length > 1) Set("duration", val[1]);
            Console.WriteLine($"  {name} -> start {val[0]}" + (val.Length > 1 ? $" duration {val[1]}" : ""));
        }
        actions.Value = list.ToArray();
        asset.Write(args[2]);
        Console.WriteLine($"timeline {args[3]}: {list.Count} entries -> {args[2]}");
        return 0;
    }
    case "tlappend":
    {
        // Append a timeline entry by cloning an existing serialized row.
        // tlappend <in> <out> <timeline> <templateAction> <newAction> <start> [duration]
        var tl = asset.Exports.OfType<NormalExport>().FirstOrDefault(e => e.ObjectName.Value.Value == args[3] && e.Data.Any(p => p.Name.Value.Value == "Actions"))
                 ?? throw new Exception($"timeline {args[3]} not found");
        var actions = (ArrayPropertyData)tl.Data.First(p => p.Name.Value.Value == "Actions");
        string ActionName(StructPropertyData entry)
        {
            var o = (ObjectPropertyData)entry.Value.First(p => p.Name.Value.Value == "Action");
            return o.Value.IsExport() ? o.Value.ToExport(asset).ObjectName.ToString() : "";
        }
        var template = actions.Value.Cast<StructPropertyData>().FirstOrDefault(e => ActionName(e) == args[4])
                       ?? throw new Exception($"template action {args[4]} not found");
        var target = asset.Exports.OfType<NormalExport>().FirstOrDefault(e => e.ObjectName.ToString() == args[5])
                     ?? throw new Exception($"target action {args[5]} not found");
        var entry = (StructPropertyData)template.Clone();
        var actionRef = (ObjectPropertyData)entry.Value.First(p => p.Name.Value.Value == "Action");
        actionRef.Value = FPackageIndex.FromExport(asset.Exports.IndexOf(target));
        void Set(string field, float value)
        {
            var p = entry.Value.First(q => q.Name.Value.Value == field);
            if (p is FloatPropertyData f) f.Value = value;
            else if (p is DoublePropertyData d) d.Value = value;
            else throw new Exception($"{field} is {p.GetType().Name}");
        }
        Set("StartTime", float.Parse(args[6]));
        Set("duration", args.Length > 7 ? float.Parse(args[7]) : 0f);
        Set("TriggerTimeOffset", 0f);
        Set("EndTriggerTimeOffset", 0f);
        var track = entry.Value.FirstOrDefault(p => p.Name.Value.Value == "TrackIndex");
        if (track is IntPropertyData trackIndex) trackIndex.Value = 99;
        // Give the row its own Guid instead of the template's; derived from the
        // row's identity so rebuilding the same edit gives the same package.
        if (entry.Value.FirstOrDefault(p => p.Name.Value.Value == "Guid") is StructPropertyData guidStruct
            && guidStruct.Value.FirstOrDefault() is GuidPropertyData guid)
            guid.Value = new Guid(System.Security.Cryptography.MD5.HashData(System.Text.Encoding.UTF8.GetBytes($"{Path.GetFileName(args[1])}|{args[3]}|{args[5]}|{args[6]}")));
        actions.Value = actions.Value.Append(entry).ToArray();
        asset.Write(args[2]);
        Console.WriteLine($"timeline {args[3]}: appended {args[5]} at {args[6]} -> {args[2]}");
        return 0;
    }
    case "setprop":
    {
        // setprop <in> <out> <export> Prop=value ... (float / double / int / bool top-level properties)
        var exp = (args[3].StartsWith("#") ? asset.Exports[int.Parse(args[3][1..])] as NormalExport : asset.Exports.OfType<NormalExport>().FirstOrDefault(e => e.ObjectName.ToString() == args[3])) ?? throw new Exception($"export {args[3]} not found");
        foreach (var spec in args.Skip(4))
        {
            var (name, v) = (spec[..spec.IndexOf('=')], spec[(spec.IndexOf('=') + 1)..]);
            var p = exp.Data.FirstOrDefault(q => q.Name.Value.Value == name) ?? throw new Exception($"{name} not set on {args[3]} (only explicit properties can be edited)");
            switch (p)
            {
                case FloatPropertyData f: f.Value = float.Parse(v); break;
                case DoublePropertyData d: d.Value = double.Parse(v); break;
                case IntPropertyData i: i.Value = int.Parse(v); break;
                case BoolPropertyData b: b.Value = bool.Parse(v); break;
                case StructPropertyData s when s.Value.OfType<VectorPropertyData>().Any():
                    var xyz=v.Split(',').Select(double.Parse).ToArray();
                    if(xyz.Length!=3)throw new Exception("Vector requires x,y,z");
                    s.Value.OfType<VectorPropertyData>().First().Value=new FVector(xyz[0],xyz[1],xyz[2]);break;
                default: throw new Exception($"{name} is {p.GetType().Name}");
            }
            Console.WriteLine($"  {args[3]}.{name} = {v}");
        }
        asset.Write(args[2]);
        return 0;
    }
    case "addobjarray":
    {
        // addobjarray <in> <out> <afterProp> <NewProp> <ImportObjectName> ...: add an array of object references to the
        // export that has <afterProp>, right after it (e.g. a weapon config's "Equip Passive Abilities")
        var exp = asset.Exports.OfType<NormalExport>().First(e => e.Data.Any(p => p.Name.Value.Value == args[3]));
        if (exp.Data.Any(p => p.Name.Value.Value == args[4])) throw new Exception($"{args[4]} already set");
        var items = args.Skip(5).Select(n =>
        {
            int i = asset.Imports.FindIndex(x => x.ObjectName.Value.Value == n);
            if (i < 0) throw new Exception($"import {n} not found");
            return (PropertyData)new ObjectPropertyData(FName.FromString(asset, args[4])) { Value = FPackageIndex.FromImport(i) };
        }).ToArray();
        var arr = new ArrayPropertyData(FName.FromString(asset, args[4])) { ArrayType = FName.FromString(asset, "ObjectProperty"), Value = items };
        exp.Data.Insert(exp.Data.FindIndex(p => p.Name.Value.Value == args[3]) + 1, arr);
        asset.Write(args[2]);
        Console.WriteLine($"added {args[4]} [{string.Join(", ", args.Skip(5))}] -> {args[2]}");
        return 0;
    }
    case "kpatch":
    {
        // kpatch <in> <out> <function> <statement> old=new ...: change numeric literals inside one top-level bytecode
        // statement of a blueprint function (statement numbers as printed by kprint.ps1); sizes don't change
        var fn = asset.Exports.OfType<FunctionExport>().FirstOrDefault(f => f.ObjectName.ToString() == args[3]) ?? throw new Exception($"function {args[3]} not found");
        var stmt = fn.ScriptBytecode[int.Parse(args[4])];
        foreach (var spec in args.Skip(5))
        {
            var (from, to) = (double.Parse(spec[..spec.IndexOf('=')]), double.Parse(spec[(spec.IndexOf('=') + 1)..]));
            int hits = 0;
            void Visit(object? o, int depth)
            {
                if (o == null || depth > 40) return;
                var t = o.GetType();
                if (t.Name is "EX_DoubleConst" or "EX_FloatConst")
                {
                    var vp = t.GetField("Value") as System.Reflection.MemberInfo ?? t.GetProperty("Value");
                    object? cur = vp is System.Reflection.FieldInfo fi ? fi.GetValue(o) : ((System.Reflection.PropertyInfo)vp!).GetValue(o);
                    if (Convert.ToDouble(cur) == from)
                    {
                        object nv = t.Name == "EX_FloatConst" ? (object)(float)to : to;
                        if (vp is System.Reflection.FieldInfo f2) f2.SetValue(o, nv); else ((System.Reflection.PropertyInfo)vp).SetValue(o, nv);
                        hits++;
                    }
                    return;
                }
                if (o is UAssetAPI.Kismet.Bytecode.KismetExpression || o is System.Collections.IEnumerable && o is not string)
                {
                    if (o is System.Collections.IEnumerable en && o is not string) { foreach (var e in en) Visit(e, depth + 1); return; }
                    foreach (var f in t.GetFields(System.Reflection.BindingFlags.Public | System.Reflection.BindingFlags.Instance))
                        if (!f.FieldType.IsPrimitive && f.FieldType != typeof(string)) Visit(f.GetValue(o), depth + 1);
                }
            }
            Visit(stmt, 0);
            Console.WriteLine($"  {args[3]}[{args[4]}]: {from} -> {to} ({hits} literal(s))");
            if (hits == 0) throw new Exception("literal not found");
        }
        asset.Write(args[2]);
        return 0;
    }
    case "addint":
    {
        // addint <in> <out> <export> Prop=value: add an int property that isn't set yet, placed in schema order
        // (unversioned packages store properties in the class's declaration order, taken from the usmap)
        var exp = (args[3].StartsWith("#") ? asset.Exports[int.Parse(args[3][1..])] as NormalExport : asset.Exports.OfType<NormalExport>().FirstOrDefault(e => e.ObjectName.ToString() == args[3])) ?? throw new Exception($"export {args[3]} not found");
        var (name, v) = (args[4][..args[4].IndexOf('=')], args[4][(args[4].IndexOf('=') + 1)..]);
        if (exp.Data.Any(p => p.Name.Value.Value == name)) throw new Exception($"{name} already set");
        var order = new List<string>();
        var types = new Dictionary<string, string>();
        // a blueprint default object's class lives in this package (not in the usmap): use its parent class instead
        var cls = exp.ClassIndex.IsExport() && exp.ClassIndex.ToExport(asset) is ClassExport ce
            ? ce.SuperStruct.ToImport(asset).ObjectName.Value.Value
            : exp.GetExportClassType().Value.Value;
        // an instance of a blueprint class (not in the usmap): name its native parent as the 6th argument
        if (!usmap.Schemas.ContainsKey(cls) && args.Length > 5) cls = args[5];
        var chain = new List<UAssetAPI.Unversioned.UsmapSchema>();
        UAssetAPI.Unversioned.UsmapSchema? Schema(string? n) => n != null && usmap.Schemas.ContainsKey(n) ? usmap.Schemas[n] : null;
        for (var s = Schema(cls); s != null; s = Schema(s.SuperType)) chain.Insert(0, s);
        foreach (var s in chain)
            foreach (var p in s.Properties.Values.OrderBy(p => p.SchemaIndex)) { order.Add(p.Name); types[p.Name] = p.PropertyData.Type.ToString(); }
        int Rank(string n) { int i = order.IndexOf(n); return i < 0 ? int.MaxValue : i; }
        if (Rank(name) == int.MaxValue) throw new Exception($"{name} is not a property of {cls} ({string.Join(",", order)})");
        var fname = FName.FromString(asset, name);
        exp.Data.Add(types[name] switch   // the property's own type, from the usmap
        {
            "IntProperty" => new IntPropertyData(fname) { Value = int.Parse(v) },
            "FloatProperty" => new FloatPropertyData(fname) { Value = float.Parse(v) },
            "DoubleProperty" => new DoublePropertyData(fname) { Value = double.Parse(v) },
            "BoolProperty" => new BoolPropertyData(fname) { Value = bool.Parse(v) },
            "StructProperty" when v.StartsWith("tag:") => new StructPropertyData(fname, FName.FromString(asset, "GameplayTag"))
                { Value = new List<PropertyData> { new NamePropertyData(FName.FromString(asset, "TagName")) { Value = FName.FromString(asset, v[4..]) } } },
            var t => throw new Exception($"{name} is a {t}, not supported")
        });
        exp.Data = exp.Data.OrderBy(p => Rank(p.Name.Value.Value)).ToList();
        asset.Write(args[2]);
        Console.WriteLine($"  {args[3]}.{name} = {v}  (order: {string.Join(", ", exp.Data.Select(p => p.Name.Value.Value))})");
        return 0;
    }
    case "setmap":
    {
        // setmap <in> <out> <export> <MapProp> Tag=value ...: set float values in a gameplay-tag-keyed map (e.g. DamageData)
        var exp = (args[3].StartsWith("#") ? asset.Exports[int.Parse(args[3][1..])] as NormalExport : asset.Exports.OfType<NormalExport>().FirstOrDefault(e => e.ObjectName.ToString() == args[3])) ?? throw new Exception($"export {args[3]} not found");
        var map = (MapPropertyData)exp.Data.First(p => p.Name.Value.Value == args[4]);
        foreach (var spec in args.Skip(5))
        {
            var (tag, v) = (spec[..spec.IndexOf('=')], float.Parse(spec[(spec.IndexOf('=') + 1)..]));
            var entry = map.Value.FirstOrDefault(kv => kv.Key is StructPropertyData k && k.Value.OfType<NamePropertyData>().Any(n => n.Value.ToString() == tag));
            if (entry.Value == null) throw new Exception($"{tag} not in {args[4]}");
            switch (entry.Value) { case FloatPropertyData f: f.Value = v; break; case DoublePropertyData d: d.Value = v; break; default: throw new Exception(entry.Value.GetType().Name); }
            Console.WriteLine($"  {args[3]}.{args[4]}[{tag}] = {v}");
        }
        asset.Write(args[2]);
        return 0;
    }
    case "json":   // full UAssetAPI JSON, including Kismet bytecode of blueprint functions
        File.WriteAllText(args[2], asset.SerializeJson(true));
        Console.WriteLine($"json -> {args[2]}");
        return 0;
    case "names":
        foreach (var n in asset.GetNameMapIndexList())
            if (args.Length < 3 || n.Value.Contains(args[2], StringComparison.OrdinalIgnoreCase))
                Console.WriteLine($"  {n.Value}");
        return 0;
    case "renameexport":
    {
        // FNames with numeric suffixes store the suffix separately from the name
        // map. Renaming map strings alone does not rename such an export.
        var target = asset.Exports.Single(e => e.ObjectName.ToString() == args[3]);
        target.ObjectName = FName.FromString(asset, args[4]);
        asset.Write(args[2]);
        Console.WriteLine($"renamed export {args[3]} -> {args[4]}");
        return 0;
    }
    case "clone":
    {
        var pairs = args.Skip(3).Select(a => a.Split('=', 2)).Select(p => (Old: p[0], New: p[1])).ToList();
        // "old=new" replaces substrings; "^old=new" only replaces a name that is exactly "old".
        string Apply(string s)
        {
            foreach (var (o, n) in pairs)
                s = o.StartsWith('^') ? (string.Equals(s, o[1..], StringComparison.OrdinalIgnoreCase) ? n : s) : s.Replace(o, n);
            return s;
        }
        foreach(var cls in asset.Exports.OfType<ClassExport>()) {
            if(!cls.SuperIndex.IsImport())continue;
            var parent=cls.SuperIndex.ToImport(asset);
            if(Apply(parent.ObjectName.ToString())!=parent.ObjectName.ToString())
                throw new InvalidOperationException("Cannot reparent a cooked class with name replacement: rebuild from a compatible donor or override its properties.");
        }
        var list = asset.GetNameMapIndexList();
        int changed = 0;
        for (int i = 0; i < list.Count; i++)
        {
            var before = list[i].Value; var after = Apply(before);
            if (after != before) { asset.SetNameReference(i, new FString(after)); changed++; Console.WriteLine($"  name {before} -> {after}"); }
        }
        var folder = asset.FolderName?.Value;
        if (folder != null) { var nf = Apply(folder); if (nf != folder) { asset.FolderName = new FString(nf); Console.WriteLine($"  package {folder} -> {nf}"); } }
        Directory.CreateDirectory(Path.GetDirectoryName(args[2])!);
        asset.Write(args[2]);
        Console.WriteLine($"cloned {changed} names -> {args[2]}");
        return 0;
    }
}
return 1;







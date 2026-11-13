# Mjolnir for Phantom Blade Zero - source

Source for every compiled file shipped with the Mjolnir mod, and how to build each one.
The mod's game content (paks) and Lua scripts are data/scripts and need no build.

| Shipped file | Source here | Build |
| --- | --- | --- |
| `MjolnirUpdater/tools/PBZEdit/PBZEdit.exe` | `pbzedit/` | see 1 |
| `MjolnirUpdater/tools/pack_menu_text/pack_menu_text.exe` | `pack_menu_text/` | see 2 |
| `MjolnirUpdater/tools/retoc/retoc-pbz.exe` | upstream retoc + `retoc/partitioned-ucas.patch` | see 3 |
| `MjolnirUpdater/tools/update_mjolnir.ps1`, `*.bat` | `updater/` (plain script, no build) | - |
| `MjolnirMod/Scripts/*.lua` | `lua/` (plain script, no build) | - |

## 1. PBZEdit.exe (updater tool)
C# (.NET 10). Edits Unreal assets with UAssetAPI 1.1.0 and reads the game's files with CUE4Parse.
The updater uses: `extract` (read Game.locres from the installed game), `rowdiff` / `locres diff` (find the rows and text
entries another installed mod adds or changes), `transplant` (copy rows into the game's current DataTables) and
`locres merge` (add text entries). It needs `PBZ.usmap`
(the game's type mappings, dumped with UE4SS) next to the exe.

    dotnet publish pbzedit/PBZEdit.csproj -c Release -r win-x64 --self-contained true -p:PublishSingleFile=false -p:DebugType=none

(A normal build: PBZEdit.exe plus the .NET runtime DLLs, no self-extracting bundle.)

## 2. pack_menu_text.exe (updater tool)
Rust. Writes the mod's English text into a v11 .pak with repak.

    cd pack_menu_text && cargo build --release

## 3. retoc-pbz.exe (updater tool)
retoc by trumank (MIT, https://github.com/trumank/retoc), commit 885a8dae740cb1ce1e41ff2e74f67f9f0c118237,
with one patch that lets it read containers split into several .ucas files (`name_s1.ucas`, ...), which
Phantom Blade Zero uses.

    git clone https://github.com/trumank/retoc && cd retoc
    git checkout 885a8dae740cb1ce1e41ff2e74f67f9f0c118237
    git apply ../partitioned-ucas.patch
    cargo build --release      (output: target/release/retoc.exe, shipped as retoc-pbz.exe)

retoc needs Epic's Oodle library (oo2core_9_win64.dll) next to itself. `update_mjolnir.ps1` downloads it once from
https://github.com/WorkingRobot/OodleUE (Sdk/2.9.10/win/redist) and keeps it only if its SHA-256 is
6f5d41a7892ea6b2db420f2458dad2f84a63901c9a93ce9497337b16c195f457 (the hash retoc itself checks), so retoc never downloads.
That is the updater's only network access.

## What the updater does
`update_mjolnir.ps1` (read it, it is plain PowerShell): reads three DataTables and Game.locres from the
installed game's own containers (never from ~mods), adds Mjolnir's rows/text, packs `zz_Mjolnir_P` with
retoc, verifies it, backs up the old files into `MjolnirUpdater/backup/` and installs into
`ProjectPBZ/Content/Paks/~mods/`. It writes nothing else.

## Mjolnir's sounds (no build needed by players)
The sounds in `zz_MjolnirWwise_P` were made with Audiokinetic Wwise 2024.1.9 (the game's version) and the Wwise UE
integration compiled for UE 5.7.4: one random-container event per sound group, cooked as AkAudioEvent assets.
`lua/attack_feedback.lua` posts them through `AkGameplayStatics`.

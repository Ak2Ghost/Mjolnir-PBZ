# Mjolnir Updater for Phantom Blade Zero

The **Mjolnir Updater** keeps the Mjolnir mod working on your own, without waiting for the author:

- **After a game patch** it rebuilds Mjolnir from your installed copy of the game.
- **With other mods** that change the weapon list or English text, it merges their changes with Mjolnir's
  so both keep working.

The mod itself (`Mjolnir-Main.zip`) is on Nexus Mods. This repository hosts the updater and the source of
everything the mod and updater contain.

**Current version: 1.2.0** - see [What's new](#whats-new).

## Download
**[Mjolnir-Updater.zip](../../releases/latest)** from the latest release.

> Why it's here and not on Nexus Mods: Nexus automatically quarantines uploads that contain programs.
> The updater needs three small tools (below), so it's hosted here with their source.

## Install
1. Install Mjolnir first (`Mjolnir-Main.zip` from Nexus Mods).
2. Extract **Mjolnir-Updater.zip** into the game's main folder (Steam: right-click Phantom Blade Zero >
   **Manage > Browse local files**). You get a `MjolnirUpdater` folder next to `ProjectPBZ`.

## Use
Close the game, then run **`MjolnirUpdater\Update Mjolnir.bat`**. Run it:

- **after a game patch**, if Mjolnir stopped working;
- **after installing, updating or removing a mod** that changes weapons or English text.

It takes about a minute and ends with "Mjolnir is updated for this version of the game".
"Already up to date" means nothing Mjolnir depends on changed. "UPDATE STOPPED" means the patch changed something
the updater can't adapt to, and your Mjolnir is left as it was. The previous version is kept in `MjolnirUpdater\backup`.

### What it does
`tools\update_mjolnir.ps1` is plain PowerShell, so you can read it. It:

1. reads the weapon list (`DT_WeaponData`), evolved-weapon text (`DT_WeaponSnapSoulText`), text table (`DT_LocTable`) and
   English text (`Game.locres`) from the game's own files (never from `~mods`);
2. finds installed mods that change those files, and merges the rows and text entries each one adds or changes;
3. adds Mjolnir on top, packs `zz_Mjolnir_P` and checks it;
4. backs up the old files and installs the new ones into `ProjectPBZ\Content\Paks\~mods`.

It writes nothing else.

If it warns that a mod "loads after Mjolnir", rename that mod's `.pak/.utoc/.ucas` files so they sort before
`zz_Mjolnir_P` (for example, add `zy_` in front), then run it again.

### Network
The first run downloads Epic's Oodle compression library (`oo2core_9_win64.dll`, 637 KB), which the game's files are compressed with.
The **script** downloads it (not a tool) from the public OodleUE mirror and keeps it only if its SHA-256 is
`6f5d41a7892ea6b2db420f2458dad2f84a63901c9a93ce9497337b16c195f457`. Nothing else is downloaded or sent.

### Checking the files
`SHA256SUMS.txt` in the zip lists the SHA-256 of every file. The three tools are:

| Tool | What it does | Source |
| --- | --- | --- |
| `tools\PBZEdit\PBZEdit.exe` (+ the .NET runtime's DLLs, signed by Microsoft) | reads and edits the game's tables and text | `pbzedit/` |
| `tools\retoc\retoc-pbz.exe` | unpacks and repacks the game's IoStore containers | upstream retoc + `retoc/` patch |
| `tools\pack_menu_text\pack_menu_text.exe` | packs Mjolnir's English text | `pack_menu_text/` |

## What's new
**1.2.0**
- Mjolnir's sounds now play through the game's own Wwise sound engine, with no DLL.
  The separate Sound Add-On is retired, and nothing in `Mjolnir-Main.zip` gets flagged.
- The flight sound and the throw impact fade with distance.
- The updater uses no self-extracting tool and no tool that downloads anything itself (see [Network](#network)),
  and ships `SHA256SUMS.txt`.

Full list: [CHANGELOG.md](CHANGELOG.md).

## Upgrading from 1.1
Delete `ProjectPBZ\Content\Paks\~mods\zz_MjolnirApprovedAudio_P.*` and the folder `platform\steam\ue4ss\Mods\MjolnirApprovedAudio`
(the old sound add-on), then install the new `Mjolnir-Main.zip` and this updater.

## Uninstall
Delete the `MjolnirUpdater` folder. (To remove Mjolnir itself, see the readme in `Mjolnir-Main.zip`.)

## Source
See **[BUILDING.md](BUILDING.md)**: `pbzedit/` (C#), `pack_menu_text/` (Rust), `retoc/` (patch for retoc),
`updater/` (PowerShell), `lua/` (Mjolnir's UE4SS scripts).

## Credits
UE4SS team (MIT, https://github.com/UE4SS-RE/RE-UE4SS) · retoc by trumank (MIT) · UAssetAPI by atenfyr · CUE4Parse / FModel developers · Audiokinetic Wwise.

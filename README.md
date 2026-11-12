# Mjolnir for Phantom Blade Zero

A storm-forged war hammer for Phantom Blade Zero: its own moveset, a rune glow that lights up as you fight,
custom sounds, and **Asgardian Gale** - throw the hammer, then snap your fingers to call it back.

Everything here is free to use. You never have to wait for the author after a game patch:
the **Mjolnir Updater** rebuilds the mod from your own copy of the game.

## Downloads
Get all files from the **[latest release](../../releases/latest)**:

| File | What it is | Needed? |
| --- | --- | --- |
| `Mjolnir-Main.zip` | The mod: hammer, moves, throw/recall, glow, weapon menu entry | **Yes** |
| `Mjolnir-Sound-AddOn.zip` | Mjolnir's custom swing / impact / throw / recall / catch sounds | Recommended |
| `Mjolnir-Updater.zip` | Re-applies Mjolnir after a game patch, on your own PC | Recommended |

**Requirement:** UE4SS for Phantom Blade Zero (the UE4SS build with Phantom Blade Zero's signatures, from Nexus Mods).
Install it first: `dwmapi.dll` and the `ue4ss` folder go next to `PBZ.exe` in `platform\steam`.
The sound add-on was built against UE4SS v3.0.1.

## Install
1. Open the game's main folder (Steam: right-click Phantom Blade Zero > **Manage > Browse local files**).
   It contains `ProjectPBZ` and `platform`.
2. Install UE4SS for Phantom Blade Zero if you don't have it.
3. Extract **Mjolnir-Main.zip** into the game's main folder (merge folders).
4. Optional: extract **Mjolnir-Sound-AddOn.zip** and **Mjolnir-Updater.zip** there too.
5. Start the game, load a level, press **F9**.

| Key | Action |
| --- | --- |
| F9 | Give and equip Mjolnir |
| F8 | Refresh Mjolnir's weapon menu if it looks wrong |
| L2 / LT | Throw (Asgardian Gale) |
| L2 / LT again | Recall |

Mjolnir turns itself on with `enabled.txt` files; you don't need to edit `mods.txt`. It doesn't overwrite other mods.

## After a game patch
1. Close the game.
2. Open `MjolnirUpdater` in the game's main folder and run **Update Mjolnir.bat**.
3. Wait for "Mjolnir is updated for this version of the game" (about a minute).

The updater reads the game's current weapon list and text from your installed game, adds Mjolnir to them,
rebuilds `zz_Mjolnir_P`, and keeps the previous version in `MjolnirUpdater\backup`.
"Already up to date" means the patch didn't touch Mjolnir's files.
"UPDATE STOPPED" means the patch changed something it can't adapt to (or UE4SS needs an update) - your Mjolnir is left as it was.
The first run downloads Epic's Oodle compression library from GitHub once.

## Uninstall
Delete `ProjectPBZ\Content\Paks\~mods\zz_Mjolnir_P.*` and `zz_MjolnirApprovedAudio_P.*`,
the folders `platform\steam\ue4ss\Mods\MjolnirMod` and `MjolnirApprovedAudio`, and `MjolnirUpdater`.

## Source
Every compiled file in the releases is built from this repository - see **[BUILDING.md](BUILDING.md)**:
`audio/` (sound add-on, C++), `pbzedit/` (C#), `pack_menu_text/` (Rust), `retoc/` (patch for retoc),
`updater/` (PowerShell), `lua/` (the mod's UE4SS scripts).

## Credits
UE4SS team · retoc by trumank (MIT) · UAssetAPI by atenfyr · CUE4Parse / FModel developers.

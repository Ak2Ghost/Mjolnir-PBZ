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
| `UE4SS-for-PBZ.zip` | UE4SS v3.0.1 set up for Phantom Blade Zero (the mod loader Mjolnir runs on) | Only if you don't have UE4SS yet |
| `UE4SS-Signature-Fix-PBZ.zip` | Two text files that make an older UE4SS for Phantom Blade Zero work on the 4 Nov update | If you use UE4SS from elsewhere and Mjolnir does nothing |

**Requirement:** UE4SS for Phantom Blade Zero. If you don't have it, use `UE4SS-for-PBZ.zip` from the release -
it's the exact setup Mjolnir was built and tested on, including the game's UE4SS signatures.
Already have UE4SS for Phantom Blade Zero from elsewhere? Keep it; Mjolnir works with it
(the sound add-on was built against UE4SS v3.0.1).

> Why these files are here and not on Nexus Mods: Nexus automatically quarantines uploads that contain
> programs or DLLs. The sound add-on, the updater and UE4SS all do, so they're hosted here with their source.

## Install
1. Open the game's main folder (Steam: right-click Phantom Blade Zero > **Manage > Browse local files**).
   It contains `ProjectPBZ` and `platform`.
2. No UE4SS yet? Extract **UE4SS-for-PBZ.zip** into the game's main folder (merge folders).
   You should end up with `platform\steam\dwmapi.dll` and `platform\steam\ue4ss\` next to `PBZ.exe`.
3. Extract **Mjolnir-Main.zip** into the game's main folder (merge folders).
4. Optional: extract **Mjolnir-Sound-AddOn.zip** and **Mjolnir-Updater.zip** there too.
5. Start the game, load a level, press **F9**.

| Key | Action |
| --- | --- |
| F9 | Give and equip Mjolnir |
| F8 | Refresh Mjolnir's weapon menu if it looks wrong |
| F7 | Remove Mjolnir from your inventory (equip another weapon first; use before uninstalling) |
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

## Troubleshooting
Mjolnir needs **Phantom Blade Zero Steam build 26367565** (the 4 Nov 2026 update) and UE4SS that works on it.
Open `platform\steam\ue4ss\UE4SS.log` after starting the game:

| What you see | Fix |
| --- | --- |
| No `UE4SS.log` at all | UE4SS isn't installed or isn't loading. Install `UE4SS-for-PBZ.zip`; `dwmapi.dll` must be in `platform\steam` next to `PBZ.exe`. On Steam Deck / Linux add launch option `WINEDLLOVERRIDES="dwmapi=n,b" %command%`. |
| Log exists but no `Starting Lua mod 'MjolnirMod'`, or errors about GNatives / GUObjectArray | Your UE4SS signatures are from before the 4 Nov update. Install `UE4SS-Signature-Fix-PBZ.zip` (or `UE4SS-for-PBZ.zip`). |
| `[MjolnirMod] loaded` but F9 does nothing | Load into a level first (not the main menu), then press F9. |
| Hammer works but makes no custom sounds | Install `Mjolnir-Sound-AddOn.zip`. |
| Mjolnir broke after a game update | Run `MjolnirUpdater\Update Mjolnir.bat`. |

If it still doesn't work, open an issue and attach your `UE4SS.log`.

## Uninstall
1. **In game first:** equip another weapon, press **F7** (removes Mjolnir from your inventory), then save and quit.
   This keeps your save from holding an item the game no longer knows.
2. Then delete the files:

Delete `ProjectPBZ\Content\Paks\~mods\zz_Mjolnir_P.*` and `zz_MjolnirApprovedAudio_P.*`,
the folders `platform\steam\ue4ss\Mods\MjolnirMod` and `MjolnirApprovedAudio`, and `MjolnirUpdater`.
If you installed UE4SS from `UE4SS-for-PBZ.zip` and want it gone too, delete `platform\steam\dwmapi.dll` and `platform\steam\ue4ss`.

## Source
Every compiled file in the releases is built from this repository - see **[BUILDING.md](BUILDING.md)**:
`audio/` (sound add-on, C++), `pbzedit/` (C#), `pack_menu_text/` (Rust), `retoc/` (patch for retoc),
`updater/` (PowerShell), `lua/` (the mod's UE4SS scripts).

## Credits
UE4SS team (MIT, https://github.com/UE4SS-RE/RE-UE4SS) · retoc by trumank (MIT) · UAssetAPI by atenfyr · CUE4Parse / FModel developers.

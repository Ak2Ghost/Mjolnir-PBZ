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
5. Start the game, load a level, press **F1**.

| Key | Action |
| --- | --- |
| F1 | Give and equip Mjolnir |
| F2 | Refresh Mjolnir's weapon menu if it looks wrong |
| L2 / LT | Throw (Asgardian Gale) |
| L2 / LT again | Recall |

**Change the keys** in `platform\steam\ue4ss\Mods\MjolnirMod\Scripts\settings.lua` (open with Notepad). If another mod uses F1 or F2, pick another key there, or add `'CONTROL'` so Mjolnir's key only works with Ctrl held - UE4SS only fires a binding when exactly its modifier keys are held, so Ctrl+F1 never triggers another mod's F1.

Mjolnir turns itself on with `enabled.txt` files; you don't need to edit `mods.txt`. It doesn't overwrite other mods.

## Compatibility with other mods
Mjolnir adds itself to four game files: the weapon list (`DT_WeaponData`), the evolved-weapon text (`DT_WeaponSnapSoulText`),
the text table (`DT_LocTable`) and the English text (`Game.locres`). Unreal can't merge two mods that change the same file -
the one that loads last wins. So if another mod also changes one of these (weapon balance, new weapons, text/translation mods):

1. Install **Mjolnir-Updater.zip**.
2. Run **`MjolnirUpdater\Update Mjolnir.bat`** (game closed). It finds every installed mod that changes those files, works out
   exactly which rows and text entries each one adds or changes, merges them all onto the game's current files, adds Mjolnir on
   top, and lists the mods it merged.
3. Run it again whenever you install, update or remove one of those mods.

If the updater warns that a mod "loads after Mjolnir", rename that mod's `.pak/.utoc/.ucas` files so they sort before
`zz_Mjolnir_P` (for example add `zy_` in front), then run the updater again.

Mods that don't touch those files (graphics, camera/FOV, gameplay tweaks, boss changes) need nothing. Lua mods only clash if they
use the same keys (see above).

## After a game patch
1. Close the game.
2. Open `MjolnirUpdater` in the game's main folder and run **Update Mjolnir.bat**.
3. Wait for "Mjolnir is updated for this version of the game" (about a minute).
   The same updater also merges Mjolnir with other installed mods (see Compatibility).

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
| `[MjolnirMod] loaded` but F1 does nothing | Load into a level first (not the main menu), then press F1. The log line shows the keys in use; another mod may use the same key - change it in `settings.lua`. |
| Hammer works but makes no custom sounds | Install `Mjolnir-Sound-AddOn.zip`. |
| Mjolnir broke after a game update, or another mod's weapons/text disappeared | Run `MjolnirUpdater\Update Mjolnir.bat`. |

If it still doesn't work, open an issue and attach your `UE4SS.log`.

## Uninstall
In game, equip a different weapon and save first. Then delete the files:

Delete `ProjectPBZ\Content\Paks\~mods\zz_Mjolnir_P.*` and `zz_MjolnirApprovedAudio_P.*`,
the folders `platform\steam\ue4ss\Mods\MjolnirMod` and `MjolnirApprovedAudio`, and `MjolnirUpdater`.
If you installed UE4SS from `UE4SS-for-PBZ.zip` and want it gone too, delete `platform\steam\dwmapi.dll` and `platform\steam\ue4ss`.

## Source
Every compiled file in the releases is built from this repository - see **[BUILDING.md](BUILDING.md)**:
`audio/` (sound add-on, C++), `pbzedit/` (C#), `pack_menu_text/` (Rust), `retoc/` (patch for retoc),
`updater/` (PowerShell), `lua/` (the mod's UE4SS scripts).

## Credits
UE4SS team (MIT, https://github.com/UE4SS-RE/RE-UE4SS) · retoc by trumank (MIT) · UAssetAPI by atenfyr · CUE4Parse / FModel developers.

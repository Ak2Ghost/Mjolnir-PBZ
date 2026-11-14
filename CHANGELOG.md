# Changelog

## 1.2.1
- **F3 removes Mjolnir before uninstalling.** Deleting the mod while Mjolnir was still owned left an empty slot in the
  weapon list, because the save keeps the weapon's ID. F3 (with another weapon in hand) takes Mjolnir's entry out of the
  backpack's `Inventories` and `MainWeaponInfos` maps and checks the result with the game's `HasWeapon`. The game's own
  `RemoveWeaponByID` leaves both maps untouched, so it isn't relied on. Key configurable as `remove` in `settings.lua`.

## 1.2.0
- **Sounds through the game's own Wwise engine.** Mjolnir's 61 sounds are cooked Wwise events (`zz_MjolnirWwise_P`),
  posted by the Lua scripts. No DLL; the Sound Add-On (`MjolnirApprovedAudio`, `zz_MjolnirApprovedAudio_P`) is retired.
- Mjolnir's weapon config holds the sound events, so the game keeps them loaded while the hammer is equipped
  (no loading in combat, no stutter).
- The flight sound fades with the hammer's distance (Mjolnir's own Wwise component volume); the throw impact plays at the hit
  with Wwise distance attenuation.
- Updater: PBZEdit is a normal .NET build (no self-extracting bundle); the Oodle library is downloaded by the script and
  checked by SHA-256 (no tool downloads anything); `SHA256SUMS.txt` lists every file.
- GitHub now hosts only the updater; `Mjolnir-Main.zip` is on Nexus Mods.

## 1.1.0
- Keys changed to **F1** (give and equip Mjolnir) and **F2** (refresh its weapon-menu entry). F9/F8 clashed with other mods.
- Keys are configurable in `MjolnirMod/Scripts/settings.lua`, including Ctrl/Shift/Alt combinations.
- **Mjolnir Updater merges other mods:** it detects installed mods that change `DT_WeaponData`, `DT_WeaponSnapSoulText`,
  `DT_LocTable` or the English `Game.locres`, merges the rows and text entries they add or change onto the game's files,
  then adds Mjolnir. It lists the mods it merged and warns about mods that load after Mjolnir.
- UE4SS signatures for Steam build 26367565 are included in `Mjolnir-Main.zip` (also available alone as `UE4SS-Signature-Fix-PBZ.zip`).
- README: Compatibility and Troubleshooting sections.

## 1.0.0
- First release: Mjolnir moveset, Asgardian Gale throw and recall, rune glow, weapon-menu entry, sound add-on,
  self-service patch updater, UE4SS setup for Phantom Blade Zero.

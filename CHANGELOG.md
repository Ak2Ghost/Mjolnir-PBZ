# Changelog

## 1.1.0
- Keys changed to **F1** (give and equip Mjolnir) and **F2** (refresh its weapon-menu entry). F9/F8 clashed with other mods.
- Keys are configurable in `MjolnirMod/Scripts/settings.lua`, including Ctrl/Shift/Alt combinations.
- **Mjolnir Updater merges other mods:** it detects installed mods that change `DT_WeaponData`, `DT_WeaponSnapSoulText`,
  `DT_LocTable` or the English `Game.locres`, merges the rows and text entries they add or change onto the game's files,
  then adds Mjolnir. It lists the mods it merged and warns about mods that load after Mjolnir.
- New download `UE4SS-Signature-Fix-PBZ.zip` (UE4SS signatures for Steam build 26367565).
- README: Compatibility and Troubleshooting sections.

## 1.0.0
- First release: Mjolnir moveset, Asgardian Gale throw and recall, rune glow, weapon-menu entry, sound add-on,
  self-service patch updater, UE4SS setup for Phantom Blade Zero.

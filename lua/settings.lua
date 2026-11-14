-- Mjolnir key settings.  Edit with Notepad, save, restart the game.
-- key:       a UE4SS key name, e.g. 'F9', 'H', 'NUM_FIVE', 'INS' (full list: UE4SS docs, "Key" table)
-- modifiers: any of 'CONTROL', 'SHIFT', 'ALT' - all of them must be held; {} = no modifier
-- Set key = '' to turn a binding off.
-- If another mod uses the same key, change it here (or add 'CONTROL' so it only fires with Ctrl held).
return {
 give    = { key = 'F1', modifiers = {} },  -- give + equip Mjolnir
 menu    = { key = 'F2', modifiers = {} },  -- refresh Mjolnir's weapon menu entry
 remove  = { key = 'F3', modifiers = {} },  -- remove Mjolnir from your weapons (do this before uninstalling)
}

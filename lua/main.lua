-- MjolnirMod: the Mjolnir weapon for Hun.
--   F1 give Mjolnir and equip it
--   F2 check the weapon menu's copy of Mjolnir; refresh it if stale
-- Keys are set in settings.lua (next to this file).
-- The hammer's own controllers (combo sound, throw and return) start once
-- the player is in the world.  Everything logs to UE4SS.log as [MjolnirMod].
local UEHelpers=require('UEHelpers')
local Equipment=require('equipment_bridge')
local Pump=require('game_thread_pump')
local ITEM_ID='Mjolnir'

local function log(msg)print('[MjolnirMod] '..msg..'\n')end

-- Key bindings come from settings.lua; a broken entry falls back to the default.
local DEFAULTS={give={key='F1',modifiers={}},menu={key='F2',modifiers={}}}
local okSettings,SETTINGS=pcall(require,'settings')
if not okSettings or type(SETTINGS)~='table'then log('settings.lua not readable ('..tostring(SETTINGS)..'); using default keys');SETTINGS={}end
local function describe(b)local parts={};for _,m in ipairs(b.modifiers or{})do parts[#parts+1]=m end;parts[#parts+1]=b.key;return table.concat(parts,'+')end
local function bind(name,fn)
 local b=SETTINGS[name];if type(b)~='table'then b=DEFAULTS[name]end
 if type(b.key)~='string'or b.key==''then log(name..': no key (turned off in settings.lua)');return nil end
 local key=Key[b.key]
 if key==nil then log(name..': unknown key '..tostring(b.key)..' in settings.lua; using default');b=DEFAULTS[name];key=Key[b.key]end
 if key==nil then return nil end
 local mods={}
 for _,m in ipairs(b.modifiers or{})do
  local mk=ModifierKey and ModifierKey[m]
  if mk==nil then log(name..': unknown modifier '..tostring(m)..' ignored')else mods[#mods+1]=mk end
 end
 if #mods>0 then RegisterKeyBind(key,mods,fn)else RegisterKeyBind(key,fn)end
 return describe(b)
end

local runtime_started=false
local function start_runtime()
 if runtime_started then return end
 local ok,err=pcall(function()
  require('combo_runtime').start(4)
  require('throw_runtime').start()
 end)
 if ok then runtime_started=true;log('hammer controllers started')
 else log('runtime bootstrap failed: '..tostring(err))end
end

-- The mod's DT_WeaponData override carries the Mjolnir row (this engine has
-- no UDataTable:AddRow); without it the weapon cannot be given.
local function weapon_row_present()
 local dt=StaticFindObject('/Game/PBZContent/DataTable/UI/DT_WeaponData.DT_WeaponData')
 if not(dt and dt:IsValid())then log('DT_WeaponData not loaded');return false end
 local ok,row=pcall(function()return dt:FindRow(ITEM_ID)end)
 if ok and row then return true end
 log('Mjolnir row is not in the weapon table - the mod\'s DT_WeaponData override did not load')
 return false
end

-- F9.  No pre-loading from Lua: objects loaded here have no owner, get
-- garbage-collected, and the backpack was left holding a freed pointer.  The
-- game loads the weapon itself.
local function give_mjolnir()
 start_runtime()
 if not weapon_row_present()then return end
 local bag=FindFirstOf('PBZBackPackSubsystem')
 if not(bag and bag:IsValid())then log('PBZBackPackSubsystem not found');return end
 if Equipment.is_equipped(bag,ITEM_ID,log)==true then log('Mjolnir is already equipped');return end
 -- AddWeaponItem(WeaponID, bIsNormalWeapon, bPushWidget, bIsAddByLoadData,
 -- bAutoEquipment): register ownership quietly; the bridge equips it.
 local ok,err=pcall(function()bag:AddWeaponItem(FName(ITEM_ID),true,false,false,false)end)
 if not ok then log('AddWeaponItem failed: '..tostring(err));return end
 log(Equipment.equip_existing(bag,ITEM_ID,log)==true and'give: Mjolnir equipped'or'give: equip not confirmed (see above)')
end
local GIVE_KEY=bind('give',function()Pump.post('give_mjolnir',give_mjolnir)end)
-- F8: check what the weapon menu is given for Mjolnir; refresh a stale copy
-- (see menu_refresh.lua).  Runs on the game thread like F9.
local MENU_KEY=bind('menu',function()Pump.post('menu_check',function()
 local ok,r=pcall(function()return require('menu_refresh').run()end)
 log('menu: '..(ok and tostring(r)or('check failed: '..tostring(r))))
end)end)

-- ClientRestart: the player is in the world.
RegisterHook('/Script/Engine.PlayerController:ClientRestart',function()
 local pc=UEHelpers.GetPlayerController()
 -- (Mjolnir's menu text ships in the mod's own English language file, not
 -- from a script: registering text from Lua crashed the game on 2026-11-06.)
 if pc and pc:IsValid()and pc.Pawn and pc.Pawn:IsValid()then start_runtime()end
end)
log('loaded; controllers start when the player spawns; '..tostring(GIVE_KEY)..' gives Mjolnir, '..tostring(MENU_KEY)..' refreshes its menu (keys: settings.lua)')
-- Also resume observers after UE4SS reloads scripts while the player is already in a level.
if type(ExecuteInGameThread)=='function'then ExecuteInGameThread(function()
 local pc=UEHelpers.GetPlayerController()
 if pc and pc:IsValid()and pc.Pawn and pc.Pawn:IsValid()then start_runtime()end
end)end

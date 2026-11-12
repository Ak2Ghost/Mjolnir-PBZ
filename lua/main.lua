-- MjolnirMod: the Mjolnir weapon for Hun.
--   F9  give Mjolnir and equip it
--   F8 check the weapon menu's copy of Mjolnir; refresh it if stale
--   F7 remove Mjolnir from the backpack (before uninstalling)
-- The hammer's own controllers (combo sound, throw and return) start once
-- the player is in the world.  Everything logs to UE4SS.log as [MjolnirMod].
local UEHelpers=require('UEHelpers')
local Equipment=require('equipment_bridge')
local Pump=require('game_thread_pump')
local ITEM_ID='Mjolnir'

local function log(msg)print('[MjolnirMod] '..msg..'\n')end

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
 log(Equipment.equip_existing(bag,ITEM_ID,log)==true and'F9: Mjolnir equipped'or'F9: equip not confirmed (see above)')
end
RegisterKeyBind(Key.F9,function()Pump.post('give_mjolnir',give_mjolnir)end)
-- F7: take Mjolnir out of the backpack (do this before uninstalling the mod, so
-- the save never holds an item the game no longer knows).  Uses the game's own
-- PBZBackPackSubsystem:RemoveWeaponByID; its parameters are read at run time.
local function remove_mjolnir()
 local bag=FindFirstOf('PBZBackPackSubsystem')
 if not(bag and bag:IsValid())then log('F7: PBZBackPackSubsystem not found (load into a level first)');return end
 local function has()
  local ok,r=pcall(function()return bag:HasWeapon(FName(ITEM_ID),true)end)
  if ok then return r==true end;log('F7: HasWeapon failed: '..tostring(r));return nil
 end
 if Equipment.is_equipped(bag,ITEM_ID,log)==true then log('F7: Mjolnir is equipped - equip another weapon first, then press F7');return end
 local before=has();log('F7: owns Mjolnir before='..tostring(before))
 if before==false then log('F7: Mjolnir is not in the backpack');return end
 for _,method in ipairs({'DisposeWeapon','RemoveWeaponByID'})do
  local ok,err=pcall(function()return bag[method](bag,FName(ITEM_ID),true)end)
  local now=has()
  log('F7: '..method..(ok and''or(' failed: '..tostring(err)))..'; owns Mjolnir now='..tostring(now))
  if now==false then log('F7: Mjolnir removed - save the game, then uninstall the mod');return end
 end
 log('F7: Mjolnir is still in the backpack')
end
RegisterKeyBind(Key.F7,function()Pump.post('remove_mjolnir',remove_mjolnir)end)
-- F6 (diagnostic): list the backpack's weapon/item functions and what it reports for Mjolnir.
local function diagnose_backpack()
 local bag=FindFirstOf('PBZBackPackSubsystem')
 if not(bag and bag:IsValid())then log('F6: PBZBackPackSubsystem not found');return end
 local cls=bag:GetClass()
 local n=0
 local function sig(fn)
  local parts={};fn:ForEachProperty(function(prop)parts[#parts+1]=prop:GetFName():ToString()..':'..prop:GetClass():GetFName():ToString()end)
  return table.concat(parts,', ')
 end
 local ok,err=pcall(function()
  local c=cls
  while c and c:IsValid()do
   c:ForEachFunction(function(fn)
    local name=fn:GetFName():ToString()
    if name:find('Weapon')or name:find('Item')or name:find('Remove')or name:find('Delete')or name:find('Sell')or name:find('Discard')then
     n=n+1;log('F6: '..c:GetFName():ToString()..':'..name..'('..sig(fn)..')')
    end
   end)
   c=c:GetSuperStruct()
  end
 end)
 if not ok then log('F6: function walk failed: '..tostring(err))end
 log('F6: '..n..' functions listed')
 -- simple no-argument / id-only queries that may show how Mjolnir is held
 for _,q in ipairs({'GetAllWeaponIDs','GetWeaponIDs','GetOwnedWeapons','GetAllWeapons','GetWeaponItems','GetCurrentMainWeaponIndex'})do
  local f=StaticFindObject('/Script/ProjectPBZ.PBZBackPackSubsystem:'..q)
  if f and f:IsValid()then
   local ok2,res=pcall(function()return bag[q](bag)end)
   local text=tostring(res)
   if ok2 and type(res)=='userdata'and res.GetArrayNum then local ok3,cnt=pcall(function()return res:GetArrayNum()end);text='array of '..tostring(cnt)end
   log('F6: '..q..'() -> '..(ok2 and text or('failed: '..tostring(res))))
  end
 end
 for _,q in ipairs({'HasWeapon','HasWeaponByID','IsHaveWeapon','GetWeaponCount','GetItemCount','GetItemNum'})do
  local f=StaticFindObject('/Script/ProjectPBZ.PBZBackPackSubsystem:'..q)
  if f and f:IsValid()then
   local ok2,res=pcall(function()return bag[q](bag,FName(ITEM_ID))end)
   log('F6: '..q..'(Mjolnir) -> '..(ok2 and tostring(res)or('failed: '..tostring(res))))
  end
 end
end
RegisterKeyBind(Key.F6,function()Pump.post('diagnose_backpack',diagnose_backpack)end)
-- F8: check what the weapon menu is given for Mjolnir; refresh a stale copy
-- (see menu_refresh.lua).  Runs on the game thread like F9.
RegisterKeyBind(Key.F8,function()Pump.post('menu_check',function()
 local ok,r=pcall(function()return require('menu_refresh').run()end)
 log('F8: '..(ok and tostring(r)or('check failed: '..tostring(r))))
end)end)

-- ClientRestart: the player is in the world.
RegisterHook('/Script/Engine.PlayerController:ClientRestart',function()
 local pc=UEHelpers.GetPlayerController()
 -- (Mjolnir's menu text ships in the mod's own English language file, not
 -- from a script: registering text from Lua crashed the game on 2026-11-06.)
 if pc and pc:IsValid()and pc.Pawn and pc.Pawn:IsValid()then start_runtime()end
end)
log('loaded; controllers start when the player spawns; F9 gives Mjolnir')
-- Also resume observers after UE4SS reloads scripts while the player is already in a level.
if type(ExecuteInGameThread)=='function'then ExecuteInGameThread(function()
 local pc=UEHelpers.GetPlayerController()
 if pc and pc:IsValid()and pc.Pawn and pc.Pawn:IsValid()then start_runtime()end
end)end

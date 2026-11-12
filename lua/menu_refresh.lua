-- F8: what is the game's menu given for Mjolnir, and is it out of date?
-- The weapon screen kept showing old data (two move-list entries, the blade's
-- perks) although the mod's weapon table carries the new entry.  The menu asks
-- the backpack (PBZBackPackSubsystem) rather than the table, and the backpack
-- may hold a copy taken when Mjolnir was added (F9) and kept in the save.
-- This compares the two and, if the backpack's copy is stale, re-adds Mjolnir
-- so the game takes a fresh one -- only while Mjolnir is not in hand.
-- Function arguments are read from the game first; anything unexpected is
-- logged and nothing is called on a guess.  Everything goes to the log
-- under "menu".
local D=require('runtime_diagnostics')
local M={}
local ROOT='/Script/ProjectPBZ.PBZBackPackSubsystem:'
local TABLE='/Game/PBZContent/DataTable/UI/DT_WeaponData.DT_WeaponData'
local ID='Mjolnir'
local function valid(o)return o~=nil and type(o)~='number'and type(o)~='string'and type(o)~='boolean'and o.IsValid and o:IsValid()end
local function log(m)D.write('menu',m)end

-- A backpack function's parameters ({name,kind}) and return kind, or nil.
function M.signature(method)
 local fn=StaticFindObject(ROOT..method)
 if not valid(fn)then return nil end
 local params,ret={},nil
 fn:ForEachProperty(function(p)
  local name=p:GetFName():ToString();local kind=p:GetClass():GetFName():ToString()
  if name=='ReturnValue'then ret=kind else params[#params+1]={name=name,kind=kind}end
 end)
 return params,ret
end
local function describe(method)
 local params,ret=M.signature(method)
 if not params then return method..'(not reflected)'end
 local parts={};for _,p in ipairs(params)do parts[#parts+1]=p.name..':'..p.kind end
 return method..'('..table.concat(parts,', ')..') -> '..tostring(ret)
end
-- Arguments when the function takes the weapon's ID (and, optionally, the
-- "is a main weapon" flag, which is true for Mjolnir); nil otherwise.
local function by_id(method)
 local params=M.signature(method)
 if not params or params[1]==nil or params[1].kind~='NameProperty'then return nil end
 if #params==1 then return {FName(ID)}end
 if #params==2 and params[2].kind=='BoolProperty'and params[2].name:lower()=='bisnormalweapon'then return {FName(ID),true}end
 return nil
end

-- Small readers that cope with both Lua tables and engine values.
local function count(a)
 if a==nil then return nil end
 if type(a)=='table'and not a.GetArrayNum then return #a end
 local ok,n=pcall(function()return a:GetArrayNum()end);return ok and n or nil
end
-- Array items from the engine come back wrapped (their :get() is the value).
local function unwrap(v)
 if type(v)~='userdata'then return v end
 local ok,g=pcall(function()return v:get()end)
 if ok and g~=nil then return g end
 return v
end
local function item(a,i)local ok,v=pcall(function()return a[i]end);return ok and unwrap(v)or nil end
local function text(v)
 if v==nil then return nil end
 if type(v)=='string'then return v end
 if type(v)=='table'and v.Key~=nil then return text(v.Key)end
 local ok,s=pcall(function()return v:ToString()end);if ok and type(s)=='string'then return s end
 ok,s=pcall(function()return text(v.Key)end);if ok then return s end
 return tostring(v)
end
local function field(v,k)local ok,r=pcall(function()return v[k]end);return ok and r or nil end
-- What the menu would show: move-list titles and the level-5 perk title.
function M.summary(row)
 if row==nil then return nil end
 local moves=field(row,'WeaponAbilityDesc');local n=count(moves)
 if not n then return nil end
 local titles,readable={},true
 for i=1,n do
  local t=text(field(item(moves,i),'WeaponTitle'))
  if t==nil then readable=false end
  titles[#titles+1]=t or'?'
 end
 local levels=field(row,'WeaponUpLevelDatas')
 local perk=text(field(item(field(item(levels,4),'GEDatas'),1),'WeaponTitle'))
 if perk==nil then readable=false end
 return {moves=n,titles=titles,perk5=perk,readable=readable}
end
-- A tag -> number map from the engine (or a Lua table), as text.
function M.map_text(m)
 if m==nil then return 'nil'end
 local parts={}
 local function add(k,v)
  k=unwrap(k);v=unwrap(v)
  local name=text(field(k,'TagName'))or text(k)or'?'
  parts[#parts+1]=tostring(name):gsub('^Damage%.Attack%.Target%.','')..'='..tostring(tonumber(v)or text(v))
 end
 if type(m)=='table'and not m.ForEach then for k,v in pairs(m)do add(k,v)end
 else local ok=pcall(function()m:ForEach(function(k,v)add(k,v)end)end);if not ok then return tostring(m)end end
 table.sort(parts)
 return '{'..table.concat(parts,', ')..'}'
end
local function show(s)
 if not s then return 'unreadable'end
 return string.format('%d move(s) [%s], level-5 perk "%s"',s.moves,table.concat(s.titles,' | '),tostring(s.perk5))
end
local function same(a,b)
 if a.moves~=b.moves or a.perk5~=b.perk5 then return false end
 for i=1,a.moves do if a.titles[i]~=b.titles[i]then return false end end
 return true
end

local function table_copy()
 local dt=StaticFindObject(TABLE)
 if not valid(dt)then return nil,'weapon table not loaded'end
 local ok,row=pcall(function()return dt:FindRow(ID)end)
 if not ok or row==nil then return nil,'Mjolnir is not in the weapon table'end
 return M.summary(row)
end
local function game_copy(bag)
 local args=by_id('GetMainWeaponTableData')
 if not args then return nil,'GetMainWeaponTableData does not take just an ID'end
 local ok,row=pcall(function()return bag:GetMainWeaponTableData(table.unpack(args))end)
 if not ok then return nil,'GetMainWeaponTableData failed: '..tostring(row)end
 return M.summary(row)
end
local function equipped(bag)
 local args=by_id('IsEquipWeaponsByID')
 if not args then return nil end
 local ok,r=pcall(function()return bag:IsEquipWeaponsByID(table.unpack(args))end)
 if ok and type(r)=='boolean'then return r end   -- (not "ok and r or nil": that turns false into nil)
 return nil
end

-- Which pieces of a text key the running game has: its localization entry under "Default"
-- (looked up plain, and with the key as source text -- stock entries' source is their key) and its
-- text-table row.  Read-only: only FindTextInLocalizationTable (safe; it is the text REGISTRATION
-- call that crashed) and FindRow.
M.TEXT_KEYS={'Weapon_FunctionName_Common_BAB','Mjolnir_Name','Mjolnir_Move_Throw','Mjolnir_Move_Standard_Desc','Mjolnir_Perk_Title'}
local LIB='/Script/Engine.Default__KismetTextLibrary'
local LOCTABLE='/Game/PBZContent/DataTable/Localizaion/DT_LocTable.DT_LocTable'
function M.text_probe()
 local lib=StaticFindObject(LIB)
 local dt=StaticFindObject(LOCTABLE)
 for _,k in ipairs(M.TEXT_KEYS)do
  local function find(source)
   if not valid(lib)then return 'no text library'end
   local out={}
   local ok,found,second=pcall(function()return lib:FindTextInLocalizationTable('Default',k,out,source)end)
   if not ok then return 'call failed: '..tostring(found)end
   if found~=true then return 'not found'end
   return '"'..tostring(text(out.OutText)or text(second))..'"'
  end
  local row='table not loaded'
  if valid(dt)then
   local okr,r=pcall(function()return dt:FindRow(k)end)
   row=(okr and r~=nil)and'row present'or'no row'
  end
  log(string.format('F8 text %s: localization %s; with key as source %s; text table %s',k,find(''),find(k),row))
 end
end

-- One F8 press.  Returns what it did: 'fresh', 'refreshed', 'stale-equipped',
-- 'unreadable' or 'failed'.
function M.run()
 local probe_ok,probe_error=pcall(function()require('vfx_probe').run()end)
 if not probe_ok then log('VFX probe failed: '..tostring(probe_error))end
 pcall(M.text_probe)
 local bag=FindFirstOf('PBZBackPackSubsystem')
 if not valid(bag)then log('F8: the backpack is not up yet');return 'failed'end
 for _,m in ipairs({'GetMainWeaponTableData','GetWeaponUpgradeLevelTexts','GetSnapSoulTextData','GetWeaponCombatAttribute','GetWeaponCurrentAttribute','GetWeaponAttackMultipliers','ConvertCombatValueToUIValue','RemoveWeaponByID','AddWeaponItem'})do
  log('F8 signature: '..describe(m))
 end
 local mine,why_t=table_copy()
 local theirs,why_g=game_copy(bag)
 log('F8 weapon table says: '..(mine and show(mine)or why_t))
 log('F8 the backpack says: '..(theirs and show(theirs)or why_g))
 for _,m in ipairs({'GetWeaponCombatAttribute','GetWeaponAttackMultipliers','GetWeaponUpgradeLevelTexts'})do
  local args=by_id(m)
  if args then
   local ok,r=pcall(function()return bag[m](bag,table.unpack(args))end)
   local n=ok and count(r)or nil
   log('F8 '..m..': '..(ok and(n and(n..' item(s), first "'..tostring(text(item(r,1)))..'"')or tostring(text(r)))or('failed: '..tostring(r))))
  end
 end
 -- What the game works out for the menu's Damage / Guard Break (level 1).
 do
  local params=M.signature('GetWeaponCombatAttribute')
  if params and #params==3 and params[3].kind=='IntProperty'then
   local ok,combat=pcall(function()return bag:GetWeaponCombatAttribute(FName(ID),true,1)end)
   log('F8 combat values at level 1: '..(ok and M.map_text(combat)or('failed: '..tostring(combat))))
   if ok and combat~=nil then
    local ok2,ui=pcall(function()return bag:ConvertCombatValueToUIValue(FName(ID),combat,true)end)
    log('F8 menu values at level 1: '..(ok2 and M.map_text(ui)or('failed: '..tostring(ui))))
   end
  end
 end
 if not mine or not theirs or not mine.readable or not theirs.readable then
  log('F8: cannot compare (a copy is unreadable); nothing changed');return 'unreadable'
 end
 if same(mine,theirs)then log('F8: the backpack matches the table; the menu is not reading a stale copy');return 'fresh'end
 if equipped(bag)~=false then log('F8: the backpack copy is out of date; switch to another weapon and press F8 again to refresh it');return 'stale-equipped'end
 local rm=by_id('RemoveWeaponByID')
 if not rm then log('F8: RemoveWeaponByID does not take just an ID; not refreshing');return 'failed'end
 local ok,err=pcall(function()bag:RemoveWeaponByID(table.unpack(rm))end)
 if not ok then log('F8: removing failed: '..tostring(err));return 'failed'end
 ok,err=pcall(function()bag:AddWeaponItem(FName(ID),true,false,false,false)end)
 if not ok then log('F8: re-adding failed: '..tostring(err)..' -- press F9 to add Mjolnir back');return 'failed'end
 local after=game_copy(bag)
 log('F8: refreshed; the backpack now says: '..show(after))
 return 'refreshed'
end
return M

-- F3: take Mjolnir out of the backpack, so the mod can be uninstalled.
-- The save keeps every weapon the player owns by ID.  If the mod's files are
-- removed while Mjolnir is still owned, the game finds no data for that ID
-- and shows an empty placeholder in the weapon list.  Pressing F3 (with
-- another weapon in hand) removes Mjolnir; the game writes that into the save
-- at its next save (rest at a shrine or change area), and then the mod's
-- files can be deleted safely.
-- Function arguments are read from the game first; nothing is called on a guess.
local M={}
local ROOT='/Script/ProjectPBZ.PBZBackPackSubsystem:'
local ID='Mjolnir'
local function alive(o)return o~=nil and type(o)~='number'and type(o)~='string'and type(o)~='boolean'and o.IsValid~=nil and o:IsValid()end

-- The backpack function's parameters ({name,kind,out}), or nil.
local OUT_PARM=0x100
local function signature(method)
 local fn=StaticFindObject(ROOT..method)
 if not alive(fn)then return nil end
 local params={}
 fn:ForEachProperty(function(p)
  local name=p:GetFName():ToString()
  local out=false;pcall(function()out=p:HasAnyPropertyFlags(OUT_PARM)end)
  params[#params+1]={name=name,kind=p:GetClass():GetFName():ToString(),out=out}
 end)
 return params
end
local function show(params)
 local t={};for _,p in ipairs(params)do t[#t+1]=p.name..':'..p.kind..(p.out and'(out)'or'')end
 return table.concat(t,', ')
end
-- Arguments for a function that takes Mjolnir's ID: names get the ID, plain
-- bools get true, out-values get a table to read back.  nil for anything else.
local function build(params)
 local args,outs={},{}
 for _,p in ipairs(params)do
  if p.name=='ReturnValue'then
  elseif p.out then local t={};args[#args+1]=t;outs[#outs+1]={name=p.name,box=t}
  elseif p.kind=='NameProperty'then args[#args+1]=FName(ID)
  elseif p.kind=='BoolProperty'then args[#args+1]=true
  else return nil end
 end
 return args,outs
end
local function truth(v)
 if type(v)=='boolean'then return v end
 if type(v)=='number'then return v~=0 end
 return nil
end
local sig_logged=false
-- true / false / nil (unknown), plus a description for the log.
local function equipped(bag,log)
 local params=signature('IsEquipWeaponsByID')
 if not params then return nil,'IsEquipWeaponsByID not found'end
 if not sig_logged then sig_logged=true;log('remove: IsEquipWeaponsByID('..show(params)..')')end
 local args,outs=build(params)
 if not args then return nil,'unexpected arguments'end
 local ok,r=pcall(function()return bag:IsEquipWeaponsByID(table.unpack(args))end)
 if not ok then return nil,'call failed: '..tostring(r)end
 local v=truth(r)
 if v~=nil then return v,'returned '..tostring(r)end
 for _,o in ipairs(outs)do
  for _,cand in ipairs({o.box[o.name],o.box[1],o.box.Value})do
   local t=truth(cand);if t~=nil then return t,o.name..'='..tostring(cand)end
  end
 end
 return nil,'returned '..type(r)..' '..tostring(r)
end
-- Calls a backpack function that takes Mjolnir's ID.  flag fills its bools.
local function call(bag,method,flag,log)
 local params=signature(method)
 if not params then return nil,method..' not found'end
 local args,outs={},{}
 for _,p in ipairs(params)do
  if p.name=='ReturnValue'then
  elseif p.out then local t={};args[#args+1]=t;outs[#outs+1]=t
  elseif p.kind=='NameProperty'then args[#args+1]=FName(ID)
  elseif p.kind=='BoolProperty'then args[#args+1]=flag
  else return nil,method..'('..show(params)..') has unexpected arguments'end
 end
 local ok,r=pcall(function()return bag[method](bag,table.unpack(args))end)
 if not ok then return nil,method..' failed: '..tostring(r)end
 return r
end
-- Does the backpack still own Mjolnir?  true / false / nil.
local function owns(bag,log)
 local r,why=call(bag,'HasWeapon',true,log)
 if why then log('remove: '..why);return nil end
 return truth(r)
end
local function list(bag)
 local ok,r=pcall(function()return bag:GetAllNormalWeapons()end)
 if not ok or r==nil then return 'unreadable'end
 local n,names=0,{}
 pcall(function()r:ForEach(function(_,e)
  n=n+1
  local v=e;pcall(function()v=e:get()end)
  local s='?';pcall(function()s=v:ToString()end)
  if s=='?'then pcall(function()s=v.WeaponID:ToString()end)end
  if s=='?'then pcall(function()s=v.ItemId:ToString()end)end
  names[#names+1]=s
 end)end)
 return n..' weapons: '..table.concat(names,', ')
end

-- The backpack keeps owned weapons in two maps keyed by weapon ID
-- (found in the game's type data): Inventories and MainWeaponInfos.  The
-- game's RemoveWeaponByID leaves both alone (tested 2026-11-13), so F3 takes
-- Mjolnir's key out of them itself.  Returns a description for the log.
local MAPS={'Inventories','MainWeaponInfos'}
local function has_key(map)
 local found=false
 pcall(function()map:ForEach(function(k)
  local kv=k;pcall(function()kv=k:get()end)
  local s='';pcall(function()s=kv:ToString()end)
  if s==ID then found=true end
 end)end)
 return found
end
local function take_out(bag,log)
 local done={}
 for _,name in ipairs(MAPS)do
  local ok,map=pcall(function()return bag[name]end)
  if not ok or map==nil then done[#done+1]=name..': unreadable'
  elseif not has_key(map)then done[#done+1]=name..': no Mjolnir'
  else
   local okr,err=pcall(function()map:Remove(FName(ID))end)
   done[#done+1]=name..': '..(okr and(has_key(map)and'still there after Remove'or'removed')or('Remove failed: '..tostring(err)))
  end
 end
 return table.concat(done,'; ')
end

-- One F3 press.  Returns 'removed', 'equipped', 'unknown', 'absent' or 'failed'.
function M.run(log)
 local bag=FindFirstOf('PBZBackPackSubsystem')
 if not alive(bag)then log('remove: the backpack is not up yet; load your save first');return 'failed'end
 local e,why=equipped(bag,log)
 if e==true then log('remove: Mjolnir is in your hand. Equip another weapon first, then press the remove key again.');return 'equipped'end
 if e==nil then log('remove: cannot tell whether Mjolnir is equipped ('..why..'); not removing it');return 'unknown'end
 if owns(bag,log)==false then log('remove: Mjolnir is not in your weapons; nothing to remove');return 'absent'end
 local _,err=call(bag,'RemoveWeaponByID',true,log)
 if err then log('remove: '..err)end
 if owns(bag,log)~=false then log('remove: '..take_out(bag,log))end
 local still=owns(bag,log)
 if still==false then
  log('remove: Mjolnir removed. Rest at a shrine (or change area) so the game saves, then quit and uninstall.')
  return 'removed'
 end
 log('remove: the game still lists Mjolnir (owns='..tostring(still)..')')
 return 'failed'
end
return M

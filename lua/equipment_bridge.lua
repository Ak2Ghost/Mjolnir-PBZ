local E={}
local ROOT='/Script/ProjectPBZ.PBZBackPackSubsystem:'
local function valid(o)return o and o:IsValid()end
local function parameters(method)
 local fn=StaticFindObject(ROOT..method);if not valid(fn)then return nil end
 local out={};fn:ForEachProperty(function(prop)
  local name=prop:GetFName():ToString()
  if name~='ReturnValue'then out[#out+1]={name=name,kind=prop:GetClass():GetFName():ToString()}end
 end);return out
end
local function arguments(method,id,index)
 local schema=parameters(method);if not schema then return nil,'function not reflected'end
 local args={}
 for _,p in ipairs(schema)do
  local n=p.name:lower()
  if p.kind=='NameProperty'and(n=='itemid'or n=='weaponid'or n=='newweaponid'or n=='weaponname'or n=='newweaponname')then args[#args+1]=FName(id)
  elseif p.kind=='IntProperty'and(n=='replaceindex'or n=='index'or n=='weaponindex'or n=='slotindex'or n=='mainweaponindex')and index~=nil then args[#args+1]=index
  elseif p.kind=='BoolProperty'and(n=='bisnormalweapon'or n=='bisnormal'or n=='bisnormalequipment'or n=='bismainweapon')then args[#args+1]=true
  else return nil,'unsupported parameter '..p.name..':'..p.kind end
 end
 return args
end
local function call(bag,method,args)return bag[method](bag,table.unpack(args))end
function E.is_equipped(bag,id,log)
 local args,why=arguments('IsEquipWeaponsByID',id,nil)
 if not args then log('equip verification unavailable: '..why);return nil end
 local ok,result=pcall(call,bag,'IsEquipWeaponsByID',args)
 if not ok then log('equip verification failed: '..tostring(result));return nil end
 log('native equipped='..tostring(result));return result==true
end
function E.equip_existing(bag,id,log)
 if E.is_equipped(bag,id,log)==true then return true end
 local schema=parameters('GetCurrentMainWeaponIndex');local index
 if schema and #schema==0 then local ok,result=pcall(function()return bag:GetCurrentMainWeaponIndex()end);if ok then index=tonumber(result)end end
 if index==nil or index<0 or index~=math.floor(index)then log('native equip request skipped: invalid current weapon slot');return false end
 local args,why=arguments('ReplaceWeaponByIndex',id,index)
 if not args then log('native equip request skipped: '..why);return false end
 log('requesting native ReplaceWeaponByIndex for '..id..'; slot='..tostring(index))
 local ok,result=pcall(call,bag,'ReplaceWeaponByIndex',args)
 if not ok then log('native equip request failed: '..tostring(result));return false end
 log('native equip request returned '..tostring(result))
 local verified=E.is_equipped(bag,id,log);return verified==true
end
return E

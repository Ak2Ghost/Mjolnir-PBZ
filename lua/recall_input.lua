-- Early recall listens for a fresh press of the input that throws Mjolnir.
-- Read PBZ's mapped keys so keyboard and controller remaps carry over.
local H=require('UEHelpers');local D=require('runtime_diagnostics')
local R={}
local ACTION='/PBZInput/InputActions/IA_CombatArt.IA_CombatArt'
local EVERY=3
local AXIS=.5
local keys={}            -- {name=..., key={KeyName=FName}}
local last=-100
local said=nil

local function valid(o)return o and o.IsValid and o:IsValid()end
local function say(msg)if said~=msg then said=msg;D.write('input',msg)end end
local function key_name(k)
 local ok,n=pcall(function()return k.KeyName:ToString()end)
 if ok and type(n)=='string'then return n end
 ok,n=pcall(function()return tostring(k.KeyName)end)
 return ok and n or nil
end

-- The keys bound to the ultimate input, or nil and why not.
function R.query()
 local sub=FindFirstOf('EnhancedInputLocalPlayerSubsystem')
 if not valid(sub)then return nil,'no input subsystem yet' end
 local action=StaticFindObject(ACTION)
 if not valid(action)then
  local ok,loaded=pcall(LoadAsset,ACTION)
  action=ok and loaded or StaticFindObject(ACTION)
 end
 if not valid(action)then return nil,'IA_CombatArt not found' end
 local ok,list=pcall(function()return sub:QueryKeysMappedToAction(action)end)
 if not ok or not list then return nil,'the game would not say which keys are bound' end
 local found={}
 local function add(k)
  -- ForEach hands a wrapped element (its :get() is the FKey); a plain list
  -- holds the FKey itself.
  local okg,v=pcall(function()return k:get()end)
  local n=(okg and v and key_name(v))or key_name(k)
  if n and n~=''and n~='None'then found[#found+1]={name=n,key={KeyName=H.FindOrAddFName(n)}}end
 end
 if type(list)=='table'and not list.ForEach then for _,k in ipairs(list)do add(k)end
 else pcall(function()list:ForEach(function(_,k)add(k)end)end)end
 return found
end

function R.update(now, force)
 if not force and now>=last and now-last<EVERY then return end
 last=now
 local ok,found,why=pcall(R.query)
 if not ok then say('early recall: key check failed ('..tostring(found)..')');return end
 if not found then say('early recall: '..tostring(why));return end
 -- Loading and interaction contexts can briefly report an empty mapping.
 -- Keep the last gameplay bindings until PBZ reports their replacement.
 if #found==0 then
  if #keys==0 then say('early recall: nothing is bound to the throw input yet')end
  return
 end
 keys=found
 local names={};for _,k in ipairs(keys)do names[#names+1]=k.name end
 say('early recall listens to the throw input: '..table.concat(names,', '))
end

-- Is any key bound to the ultimate input held right now?
function R.down(pc)
 if not valid(pc)then return false end
 for _,k in ipairs(keys)do
  local ok,d=pcall(function()return pc:IsInputKeyDown(k.key)end)
  if ok and d==true then return true end
  local oka,v=pcall(function()return pc:GetInputAnalogKeyState(k.key)end)
  if oka and tonumber(v)and tonumber(v)>AXIS then return true end
 end
 return false
end
function R.keys()return keys end
return R

-- Read-only snapshots of the actual loaded lightning asset and particle components.
local P={}
local function valid(o)return o and o.IsValid and o:IsValid()end
local function name(o)return valid(o)and o:GetFullName()or 'nil'end
local function log(s)require('runtime_diagnostics').write('vfx',s)end
function P.run()
 local path=require('throw_trail').SYSTEM
 log('private asset '..name(StaticFindObject(path)))
 for _,o in ipairs(FindAllOf('NiagaraSystem')or{})do
  local n=name(o)
  if n:find('Mjolnir',1,true)or n:find('ChangHong_LightningTrail_Body',1,true)then log('loaded '..n)end
 end
 for _,c in ipairs(FindAllOf('NiagaraComponent')or{})do
  if valid(c)then
   pcall(function()
    local a=name(c.Asset);local owner=name(c:GetOwner())
    if a:find('Mjolnir',1,true)or a:find('ChangHong_LightningTrail_Body',1,true)or owner:find('Mjolnir',1,true)then
     log('component '..name(c)..' asset='..a..' active='..tostring(c:IsActive())..' visible='..tostring(c:IsVisible())..' owner='..owner)
    end
   end)
  end
 end
end
return P

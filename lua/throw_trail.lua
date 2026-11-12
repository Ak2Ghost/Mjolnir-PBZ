-- The lightning trail on the thrown hammer.  In flight the hammer is drawn by the return flight's own
-- mesh (return_flight's flyer), not by the weapon, so the game's trail action cannot reach it.  This
-- puts a lightning trail on that mesh from the release to the catch.
-- One particle component on Hun, made once (the same route the flyer itself is made by) and reused: each
-- throw attaches it to the flyer and switches it on; the catch switches it off and the trail fades out.
-- Its particles live in world space and its emitters loop, so it follows the hammer the whole way.
--
-- The throw and swings use Mjolnir's private blue variant of the ChangHong lightning trail.
-- The throw anchors the world-space particles near the center of the flying hammer's head.
local D=require('runtime_diagnostics')
local T={}
T.VERSION='throw-placement-5'
D.write('throw','throw trail module loaded: '..T.VERSION)
T.SYSTEM='/Game/Mods/MjolnirHammer/VFX/NS_Mjolnir_LightningTrail.NS_Mjolnir_LightningTrail'
T.SOCKET='DeflectTopMiddle'   -- the middle of the head (40 cm up the hammer)
T.BLADES_OFF={}               -- (emitters to switch off on the throw; none for this effect)
T.SCALE=1 -- the private effect has its world-space dimensions baked at 0.5; avoid double scaling
-- The world-space particles visibly sit above and behind the socket during flight.
-- Bias their source down and along the current motion, including on recall.
T.LEAD=.018            -- seconds of motion used to lead the trail
local BASE_LEAD_CAP=70 -- preserves the vertical correction from the previous placement
T.MAX_LEAD=85          -- cm of horizontal lead
T.SMOOTH=.5            -- velocity smoothing per frame (0 = raw)
T.DROP=35              -- cm lower
local comp,comp_owner,on,said=nil,nil,false,{}
local pulse_comp,pulse_owner,burst
local RELEASE_DURATION,RECALL_DURATION,CATCH_DURATION,IMPACT_DURATION=.24,.29,.30,.42
local BURST_STEP=1/60
local BURST_WARM_STEPS=7
local parent,last,vel=nil,nil,nil
local frames=0   -- frames followed this throw (for the one placement proof line)
local manual=false
local simulated_at=nil
local function valid(o)return o and o.IsValid and o:IsValid()end
local function once(key,msg)if not said[key]then said[key]=true;D.write('throw',msg)end end
local function v3(p)return {X=tonumber(p.X)or 0,Y=tonumber(p.Y)or 0,Z=tonumber(p.Z)or 0}end

local function make_component(pawn)
 local cls=StaticFindObject('/Script/Niagara.NiagaraComponent')
 -- A boss effect: loaded here if the game has not loaded it (the component holds it once set).
 local sys=StaticFindObject(T.SYSTEM)
 local why=''
 if not valid(sys)and type(LoadAsset)=='function'then
  -- UE4SS's LoadAsset looks the asset up in the asset registry by its OBJECT path ("Package.Asset");
  -- given the package path alone it finds nothing (it did: "could not be loaded", 2026-11-07).
  local okL,s,found,did=pcall(LoadAsset,T.SYSTEM)
  if okL and valid(s)then sys=s
  else
   sys=StaticFindObject(T.SYSTEM)
   why=okL and string.format(' (LoadAsset: found=%s, loaded=%s)',tostring(found),tostring(did))or(' (LoadAsset error: '..tostring(s)..')')
  end
 end
 if not valid(cls)or not valid(sys)then once('missing','throw trail: '..(valid(cls)and('the trail effect could not be loaded'..why)or'no particle component class'));return nil end
 local ok,c=pcall(function()
  return pawn:AddComponentByClass(cls,false,{Rotation={X=0,Y=0,Z=0,W=1},Translation={X=0,Y=0,Z=0},Scale3D={X=1,Y=1,Z=1}},false)
 end)
 if not ok or not valid(c)then once('add','throw trail: could not add a particle component ('..tostring(c)..')');return nil end
 pcall(function()c:Deactivate()end)
 if not pcall(function()c:SetAsset(sys,true)end)then once('asset','throw trail: could not set the trail effect');return nil end
 return c
end

local function component(pawn)
 local owner=pawn:GetFullName()
 if valid(comp)and comp_owner==owner then return comp end
 comp,comp_owner=make_component(pawn),owner
 return comp
end

function T.stop_pulse()
 if not burst then return end
 burst=nil
 if valid(pulse_comp)then
  pulse_comp:Deactivate()
  pulse_comp:SetComponentTickEnabled(true)
 end
end

local function place_burst()
 local origin=burst.origin
 if valid(burst.follow)then
  local head=v3(burst.follow:GetSocketLocation(FName(T.SOCKET)))
  head.Z=head.Z-T.DROP
  origin=head
 end
 local progress=math.min(1,burst.age/burst.duration)
 local angle=progress*2*math.pi
 -- The flight system lays down ribbons along its path. Sweep its source
 -- around the contact to give a short, stationary event visible branches.
 local radius=burst.radius*math.sin(progress*math.pi/2)
 pulse_comp:K2_SetWorldLocation({
  X=origin.X+radius*math.cos(angle),
  Y=origin.Y+radius*math.sin(angle),
  Z=origin.Z+radius*.35
 },false,{},true)
end

local function step_burst(dt)
 burst.age=burst.age+dt
 place_burst()
 if burst.manual then
  local ok=pcall(function()pulse_comp:AdvanceSimulation(1,dt)end)
  if not ok then
   burst.manual=false
   pulse_comp:SetComponentTickEnabled(true)
   once('pulse-native','lightning burst: synchronous simulation unavailable; native ticks restored')
  end
 end
end

local function pulse(pawn,position,now,duration,radius,drop,follow)
 if not valid(pawn)or not position then return false end
 local at=v3(position)
 local owner=pawn:GetFullName()
 if not valid(pulse_comp)or pulse_owner~=owner then
  T.stop_pulse()
  local c=make_component(pawn)
  if not valid(c)then return false end
  c:SetAbsolute(true,false,false)
  pulse_comp,pulse_owner=c,owner
 end
 T.stop_pulse()
 at.Z=at.Z-drop
 burst={origin=at,duration=duration,radius=radius,age=0,last=now,follow=follow}
 place_burst()
 local solo=pcall(function()pulse_comp:SetForceSolo(true)end)
 pulse_comp:Activate(true)
 burst.manual=solo and pcall(function()pulse_comp:SetComponentTickEnabled(false)end)
 for _=1,BURST_WARM_STEPS do
  if not burst.manual then break end
  step_burst(BURST_STEP)
 end
 once('pulse-mode','lightning burst simulation: manual='..tostring(burst.manual))
 return true
end

function T.windup(pawn,held,now,remaining)
 if not valid(held)or not held:IsVisible()then return false end
 local duration=remaining+BURST_WARM_STEPS*BURST_STEP
 if not pulse(pawn,held:GetSocketLocation(FName(T.SOCKET)),now,duration,25,T.DROP,held)then return false end
 once('windup-flash','blue charge following the hammer head through the wind-up')
 return true
end

function T.stop_windup()
 if burst and burst.follow then T.stop_pulse()end
end

function T.catch(pawn,held,now)
 if not valid(held)then return false end
 if not pulse(pawn,held:GetSocketLocation(FName(T.SOCKET)),now,CATCH_DURATION,55,T.DROP)then return false end
 once('catch-flash','blue lightning pulse at the hammer catch')
 return true
end

function T.release(pawn,position,now)
 if not pulse(pawn,position,now,RELEASE_DURATION,40,T.DROP)then return false end
 once('release-flash','blue lightning snap at the hammer release')
 return true
end

function T.recall(pawn,flyer,now)
 if not valid(flyer)then return false end
 if not pulse(pawn,flyer:GetSocketLocation(FName(T.SOCKET)),now,RECALL_DURATION,65,T.DROP)then return false end
 once('recall-flash','blue lightning flash at the start of the hammer recall')
 return true
end

function T.impact(pawn,position,now)
 if not pulse(pawn,position,now,IMPACT_DURATION,95,12)then return false end
 once('impact-flash','blue lightning burst at confirmed hammer contact')
 return true
end

function T.update_pulse(now)
 if not burst then return end
 local elapsed=now-burst.last
 if elapsed<=0 then return end
 burst.last=now
 local left=burst.duration-burst.age
 local dt=math.min(elapsed,left)
 if dt>0 then step_burst(dt)end
 if elapsed>=left then T.stop_pulse()end
end

-- The hammer leaves the hand (or starts home without having been carried out): trail on.
function T.start(pawn,flyer)
 if on or not valid(pawn)or not valid(flyer)then return on end
 local c=component(pawn);if not c then return false end
 -- SnapToTarget (2) for location, rotation and scale: it sits exactly on the socket.
 if not pcall(function()c:K2_AttachToComponent(flyer,FName(T.SOCKET),2,2,2,false)end)then once('attach','throw trail: could not attach to the flying hammer');return false end
 pcall(function()c:SetRelativeScale3D({X=T.SCALE,Y=T.SCALE,Z=T.SCALE})end)
 -- The flyer is moved by Lua after the ordinary Niagara batch can have ticked.
 -- Simulate this one CPU effect immediately after placing the visible mesh,
 -- rather than rendering particles sampled from its previous-frame position.
 local solo_ok=pcall(function()c:SetForceSolo(true)end)
 if not pcall(function()c:Activate(true)end)then once('activate','throw trail: could not switch on');return false end
 manual=solo_ok and pcall(function()c:SetComponentTickEnabled(false)end)
 simulated_at=nil
 once('sync-mode','throw trail synchronization: manual='..tostring(manual)..', solo='..tostring(solo_ok))
 if not manual then once('sync-unavailable','throw trail: synchronous simulation unavailable; using native particle ticks')end
 if #T.BLADES_OFF>0 then
  local off=0
  for _,e in ipairs(T.BLADES_OFF)do if pcall(function()c:SetEmitterEnable(FName(e),false)end)then off=off+1 end end
  once('blades','throw trail: emitters off ('..off..' of '..#T.BLADES_OFF..')')
 end
 on,parent,last,vel,frames=true,flyer,nil,nil,0
 once('first','throw trail on the flying hammer ('..T.SOCKET..', '..T.SCALE..' size, '..T.LEAD..' s lead, '..T.DROP..' cm lower)')
 return true
end

-- Every frame, after the flyer has moved: the trail goes on the head, ahead by the hammer's motion.
function T.follow(now)
 if not on or not valid(comp)or not valid(parent)then return end
 local ok,s=pcall(function()return parent:GetSocketLocation(FName(T.SOCKET))end)
 if not ok or not s then return end
 local p=v3(s)
 if last then
  local dt=now-last.t
  if dt>1e-3 then
   local raw={X=(p.X-last.p.X)/dt,Y=(p.Y-last.p.Y)/dt,Z=(p.Z-last.p.Z)/dt}
   if vel then local k=T.SMOOTH;vel={X=vel.X*k+raw.X*(1-k),Y=vel.Y*k+raw.Y*(1-k),Z=vel.Z*k+raw.Z*(1-k)}
   else vel=raw end
   last={p=p,t=now}
  end
 else last={p=p,t=now}end
 local at={X=p.X,Y=p.Y,Z=p.Z-T.DROP}
 if vel then
  local speed=math.sqrt(vel.X^2+vel.Y^2+vel.Z^2)
  local lead=speed>0 and math.min(T.LEAD,BASE_LEAD_CAP/speed) or 0
  local horizontalLead=lead*T.MAX_LEAD/BASE_LEAD_CAP
  at.X=at.X+vel.X*horizontalLead
  at.Y=at.Y+vel.Y*horizontalLead
  at.Z=at.Z+vel.Z*lead
 end
 local okSet=pcall(function()comp:K2_SetWorldLocation(at,false,{},true)end)
 if manual and okSet then
  local dt=simulated_at and now-simulated_at or 0
  if dt>0 then
   local okSim,why=pcall(function()comp:AdvanceSimulation(1,dt)end)
   if okSim then once('sync','throw trail: particles simulated after the visible hammer moves (same-frame socket pose)')
   else
    manual=false
    pcall(function()comp:SetComponentTickEnabled(true)end)
    once('sync-failed','throw trail: synchronous simulation failed; native ticks restored: '..tostring(why))
   end
  end
  -- Repeated callbacks while paused must neither advance nor rewind particles.
  if not simulated_at or now>simulated_at then simulated_at=now end
 end
 -- Once per throw, a few frames in: proof from the engine that the placement took.
 frames=frames+1
 if frames==6 then
  local okGet,got=pcall(function()return v3(comp:K2_GetComponentLocation())end)
  local fmt=function(q)return q and string.format('(%.0f, %.0f, %.0f)',q.X,q.Y,q.Z)or'?'end
  local off=(okGet and got)and math.sqrt((got.X-at.X)^2+(got.Y-at.Y)^2+(got.Z-at.Z)^2)or nil
  D.write('throw',string.format('throw trail placement: head %s, asked %s, engine says %s (off by %s cm)%s',
   fmt(p),fmt(at),okGet and fmt(got)or'unreadable',off and string.format('%.1f',off)or'?',okSet and''or'; setting the location FAILED'))
  pcall(function()
   D.write('throw',string.format('throw mesh geometry (%s): root %s, middle %s, tip %s, head %s; manual=%s',
    T.VERSION,fmt(v3(parent:K2_GetComponentLocation())),fmt(v3(parent:GetSocketLocation(FName('MeshMiddle')))),
    fmt(v3(parent:GetSocketLocation(FName('MeshStart')))),fmt(p),tostring(manual)))
  end)
 end
 -- Once per throw, ten frames in: every running effect within 10 m of the head (owner, what it hangs
 -- on, how far from the head), to find which effect draws the trail the player sees.
 if frames==10 and T.SURVEY then pcall(T.survey,p,comp)end
 return at
end

T.SURVEY=false -- placement is confirmed; avoid scanning all scene effects during ordinary throws
local function short(o)local ok,n=pcall(function()return o:GetFullName()end);return ok and((n:match('([%w_]+)$'))or n)or'?'end
function T.survey(head,ours)
 local lines={}
 local ours_name='';pcall(function()ours_name=ours:GetFullName()end)
 for _,c in ipairs(FindAllOf('NiagaraComponent')or {})do
  if valid(c)then
   local okA,active=pcall(function()return c:IsActive()end)
   local okL,l=pcall(function()return v3(c:K2_GetComponentLocation())end)
   if okA and active and okL and l then
    local d=math.sqrt((l.X-head.X)^2+(l.Y-head.Y)^2+(l.Z-head.Z)^2)
    if d<1000 then
     local sys='?';pcall(function()sys=short(c.Asset)end)
     local owner='?';pcall(function()owner=short(c:GetOwner())end)
     local par='none';pcall(function()local pa=c:GetAttachParent();if valid(pa)then par=short(pa)..'@'..c:GetAttachSocketName():ToString()end end)
     local mine=false;pcall(function()mine=ours_name~=''and c:GetFullName()==ours_name end)
     lines[#lines+1]=string.format('%s%s owner %s on %s, %.0f cm from the head (dz %+.0f)',mine and'[ours] 'or'',sys,owner,par,d,l.Z-head.Z)
    end
   end
  end
 end
 D.write('throw','effects within 10 m of the flying hammer: '..(#lines>0 and table.concat(lines,' | ')or'none'))
end

-- The catch, or the flight ends any other way: trail off (it fades by itself).
function T.stop()
 if not on then return end
 on,parent,last,vel=false,nil,nil,nil
 if valid(comp)then
  -- Restore normal solo ticking so already-spawned particles can finish fading.
  pcall(function()comp:SetComponentTickEnabled(true)end)
  pcall(function()comp:Deactivate()end)
 end
 manual=false;simulated_at=nil
end
function T.active()return on end
return T

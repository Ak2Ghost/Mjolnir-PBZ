-- Where the throw goes when nothing is targeted.  The dart (the EMei boss's,
-- BD_GA_EMei_Skill_01_02) starts "at the target if there is one, otherwise
-- along the thrower's facing" -- so, unlocked and with no enemy about, it
-- went wherever Hun's body happened to face, not where the camera looks.
-- Now, when the throw starts (its wind-up, the YouLongCha shoot montage)
-- with no lock-on and no enemy within RADIUS, Hun is turned to the camera's
-- heading before the release, so the hammer flies where you are looking.
-- With a lock-on, or an enemy near, the game's own aiming is left alone.
local H=require('UEHelpers');local D=require('runtime_diagnostics')
local A={}
local THROW='YouLongCha_Attack_Shoot_Montage'
local RADIUS=3000       -- cm: an enemy this close keeps the game's own aiming
local TURN_RATE=1440    -- degrees a second Hun turns to the camera
local WINDOW=.3         -- seconds into the wind-up he is turned (the release is at .25)
local seen,seen_pos,aim=false,nil,nil

local function valid(o)return o and o.IsValid and o:IsValid()end
local function id(o)local ok,n=pcall(function()return o:GetFullName()end);return ok and n or''end
local function owned_by(c,pawn)
 local ok,o=pcall(function()return c:GetOwner()end)
 return ok and valid(o)and id(o)==id(pawn)
end
-- Locked onto something (the dart's own aiming asks the same component).
local function locked(pawn)
 for _,c in ipairs(FindAllOf('TargetingComponent')or {})do
  if valid(c)and owned_by(c,pawn)then
   local ok,has=pcall(function()return c:HasLockTarget()end)
   if ok and has==true then return true end
  end
 end
 return false
end
-- A hostile character within RADIUS: its name, or nil.  Only one that
-- clearly reads hostile counts -- counting unreadable ones (characters with
-- no AI controller: bodies, ambient creatures) blocked the aim on every
-- throw with no enemy in sight.
local function candidate(c,pawn)
 return valid(c)and id(c)~=id(pawn)and not id(c):find('Default__',1,true)
end
-- Hostile to the player (a dead enemy loses its controller and stops reading
-- hostile).  pawn defaults to the player's.
function A.hostile(c,pawn)
 pawn=pawn or H.GetPlayerController().Pawn
 local oka,att=pcall(function()return c:GetController():BlueprintGetTeamAttitudeTowards(pawn)end)
 if not oka or att==nil then return false end
 local n=tonumber(att)
 if not n then local okg,g=pcall(function()return att:get()end);n=okg and tonumber(g)or nil end
 return n==2 or tostring(att):find('Hostile',1,true)~=nil
end
-- Every hostile character about (the throw's homing picks from these).
function A.hostiles(pawn)
 local out={}
 for _,c in ipairs(FindAllOf('Character')or {})do
  if candidate(c,pawn)and A.hostile(c,pawn)then out[#out+1]=c end
 end
 return out
end
local function enemy_near(pawn)
 local ok,me=pcall(function()return pawn:K2_GetActorLocation()end)
 if not ok or not me then return nil end
 for _,c in ipairs(FindAllOf('Character')or {})do
  if candidate(c,pawn)then
   local okp,p=pcall(function()return c:K2_GetActorLocation()end)
   if okp and p then
    local dx,dy,dz=p.X-me.X,p.Y-me.Y,p.Z-me.Z
    if dx*dx+dy*dy+dz*dz<=RADIUS*RADIUS and A.hostile(c,pawn)then return id(c)end
   end
  end
 end
 return nil
end
local function camera_yaw()
 local pc=H.GetPlayerController()
 local ok,r=pcall(function()return pc:GetControlRotation()end)
 if ok and r then return tonumber(r.Yaw)end
 local okc,rc=pcall(function()return pc.PlayerCameraManager:GetCameraRotation()end)
 if okc and rc then return tonumber(rc.Yaw)end
end
local function norm(a)a=(a+180)%360-180;return a end
-- Quadrant-safe atan2 that behaves the same in every Lua version.
local function atan2(y,x)
 if x>0 then return math.atan(y/x)end
 if x<0 then return math.atan(y/x)+(y>=0 and math.pi or -math.pi)end
 return y>0 and math.pi/2 or(y<0 and -math.pi/2 or 0)
end

-- Up and down too: turning Hun only sets the heading (the dart starts level).
-- At launch the dart's velocity is pointed at where the camera looks -- AIM_DIST
-- down the camera's line of sight -- keeping its own speed, the pitch kept
-- within MAX_PITCH so it never spikes into the ground or the sky.
local AIM_DIST=4000     -- cm down the line of sight
local MAX_PITCH=45      -- degrees up or down
local aimed=false       -- this throw is camera-aimed
local function forward(pitch,yaw)
 local p,y=math.rad(pitch),math.rad(yaw)
 return {X=math.cos(p)*math.cos(y),Y=math.cos(p)*math.sin(y),Z=math.sin(p)}
end
-- Where the dart should fly from `from` (a unit vector), or nil when this
-- throw is not camera-aimed or the camera cannot be read.
function A.launch_direction(from)
 if not aimed or not from then return nil end
 local pc=H.GetPlayerController()
 local okr,r=pcall(function()return pc:GetControlRotation()end)
 if not okr or not r then return nil end
 local pitch=norm(tonumber(r.Pitch)or 0)
 local f=forward(pitch,tonumber(r.Yaw)or 0)
 local okl,o=pcall(function()return pc.PlayerCameraManager:GetCameraLocation()end)
 local d
 if okl and o then
  local t={X=o.X+f.X*AIM_DIST,Y=o.Y+f.Y*AIM_DIST,Z=o.Z+f.Z*AIM_DIST}
  d={X=t.X-from.X,Y=t.Y-from.Y,Z=t.Z-from.Z}
 else d=f end
 local h=math.sqrt(d.X*d.X+d.Y*d.Y)
 local pit=math.max(-MAX_PITCH,math.min(MAX_PITCH,math.deg(atan2(d.Z,h))))
 local yaw=math.deg(atan2(d.Y,d.X))
 return forward(pit,yaw)
end
function A.aimed()return aimed end

-- Every frame.  busy: the hammer is already out (no new throw to aim).
function A.update(pawn,now,busy)
 local okm,montage,anim=pcall(function()local a=pawn.Mesh:GetAnimInstance();return a:GetCurrentActiveMontage(),a end)
 local name=okm and valid(montage)and id(montage)or''
 if not name:find(THROW,1,true)then seen,seen_pos,aim,aimed=false,nil,nil,false;return end
 local okp,pos=pcall(function()return anim:Montage_GetPosition(montage)end)
 pos=okp and tonumber(pos)or 0
 if seen and seen_pos and pos+.04<seen_pos then seen=false end   -- thrown again straight away
 seen_pos=pos
 if not seen then
  seen=true;aim=nil;aimed=false
  if busy then return end
  if locked(pawn)then D.write('throw','throw left to the game\'s aiming (locked on)');return end
  local foe=enemy_near(pawn)
  if foe then D.write('throw','throw left to the game\'s aiming (an enemy is near: '..foe..')');return end
  local yaw=camera_yaw()
  if not yaw then D.write('throw','throw left to the game\'s aiming (camera unreadable)');return end
  aim={yaw=yaw,untl=now+WINDOW,last=now};aimed=true
  D.write('throw',string.format('throw aimed with the camera (no lock-on, no enemy near): heading %.0f',yaw))
 end
 if not aim or now>aim.untl then return end
 local okr,r=pcall(function()return pawn:K2_GetActorRotation()end)
 if not okr or not r then return end
 local dt=math.max(0,now-aim.last);aim.last=now
 local d=norm(aim.yaw-tonumber(r.Yaw))
 local step=math.max(-TURN_RATE*dt,math.min(TURN_RATE*dt,d))
 if dt==0 then step=0 end
 if math.abs(d)<.5 then return end
 pcall(function()pawn:K2_SetActorRotation({Pitch=0,Yaw=tonumber(r.Yaw)+step,Roll=0},false)end)
end
return A

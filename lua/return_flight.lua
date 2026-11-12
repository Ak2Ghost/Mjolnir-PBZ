-- The thrown hammer, from the hand back to the hand.  It must read as ONE
-- hammer, with weight, the whole way:
--  * the release: in the throw's frame this flyer appears on the held hammer
--    and the dart's own hammer is hidden; the flyer leaves the hand at the
--    dart's speed and merges onto the dart's path (no lurch, no pop);
--  * the flight out: the flyer carries the hammer on the dart's path, head
--    first, its heading smoothed so homing turns never twitch;
--  * the impact: it bites into what it hit and holds there for a beat (a
--    hit-stop);
--  * the bounce -- the first of two separate states, pure physics: it springs
--    off the hit like the Leviathan Axe off a light throw, mostly UP and a
--    little to the player's right, tumbling end over end, slowing under
--    heavy gravity and starting to fall.  Hun has nothing to do with it yet;
--  * the recall -- the second state: on its way down Hun calls it.  It keeps
--    the motion it has and is pulled toward him more and more (never
--    yanked), its tumble dies out and it turns, gradually, to face him on its
--    way back -- no spin;
--  * a throw that hits nothing brakes hard instead of bouncing, then is
--    recalled the same way;
--  * called to his hand: near Hun it turns directly into the held hammer's
--    orientation, ending exactly on its live pose.
--
-- The flyer is its own plain SkeletalMeshComponent on Hun, made once and
-- reused.  The held weapon mesh cannot be moved for this: it renders through
-- PBZ's OptimizationProxy as a static mesh, so moving it moves nothing you
-- can see.  The flyer is placed in world space (absolute), so Hun's own
-- movement never drags it.  It is moved every rendered frame.
local R={}
-- Preserve the close-range cadence. Each meter beyond the first eight costs
-- less time, so long recalls close quickly while the hand approach builds speed.
local CLOSE_DISTANCE=800 -- cm
local CLOSE_SPEED=1600   -- cm/s for the first part of the duration budget
local LONG_SPEED=2600    -- cm/s for distance beyond CLOSE_DISTANCE
local ARRIVE=1.4        -- speed into the hand, x the average
local V_MIN=1500        -- cm/s: the slowest it ever comes into the hand
local ARRIVE_SIDE=.18   -- it comes into the hand from the player's right
local MIN_H,MAX_H=.4,2.6
local PULL=.32          -- fraction of the recall by which Hun's pull carries it fully
local LIMIT=4           -- seconds; the recall can never outlive this
-- As it is pulled, its tumble dies out (SPIN_FADE) and over the first FACE
-- of the recall it turns to face the way it flies -- toward Hun -- gradually.
local SPIN_FADE=.12     -- seconds, time constant of the tumble dying out
local FACE=.48          -- fraction of the recall over which it comes round to face him
local FACE_MISS=.70     -- the same after a miss (it turns right round)
-- Blend into the live grip over the final part of the recall.
local GRIP_BLEND=.2
-- The release.  The dart starts ~1.3 m ahead of the hand: the flyer leaves
-- from the held hammer at the dart's own speed and closes that gap over
-- RELEASE seconds (smoothstep: no speed jump at the hand or at the merge).
local RELEASE=.24
local OUT_TURN=.18      -- seconds from the held orientation to head first (no flip at the hand)
local OUT_SMOOTH=.035   -- heading time constant in flight (homing turns)
local OUT_LIMIT=8       -- a carried flight can never outlive this
local MAX_JUMP_V=20000  -- cm/s: a dart pose moving faster than this between frames is not real
-- The impact.  Hit-stop length comes from the caller (a real hit).
local EMBED=4           -- cm it bites into what it hit
local BITE=.03          -- seconds to bite in
local SHUDDER=4         -- degrees, fading over the hit-stop
local SHUDDER_HZ=14     -- slow enough to read at ~70 fps (24 Hz aliased into jitter)
-- The bounce (the Leviathan Axe off a light throw): it springs off the hit
-- mostly up, a little to the player's right and a little back off the
-- surface, through air drag and heavy gravity, tumbling end over end (head
-- up first), slowing; ~2.5 m up.  Hun calls it on the way down, once it
-- falls at CALL_FALL.
local BOUNCE_UP,BOUNCE_SIDE,BOUNCE_BACK=1500,400,300   -- cm/s off the hit
local DRAG=1.5          -- 1/s
local GRAVITY=3200      -- cm/s^2 (heavy, game-like)
local TUMBLE=720        -- degrees a second end over end off the hit, slowing with the drag
local CALL_FALL=-350    -- cm/s: falling this fast, Hun calls it
-- A throw that hits nothing: it brakes hard (still moving) and is called home.
local STALL=.15
local BRAKE=12          -- 1/s
local MAX_V=6000
local THROW_V=4800      -- cm/s, when its own speed is not known
-- The hammer head is the mesh's +Z end (the weapon's head collider sits at
-- Z=42; the mesh spans -15..54 cm).  Pitching -90 puts +Z on the heading.
local HEAD_PITCH=-90
local HEAD_ROLL=90      -- degrees about the handle: heads up and down, not side to side
local MESH='/Game/Mods/MjolnirHammer/SK_Mjolnir.SK_Mjolnir'
local UP={X=0,Y=0,Z=1}
local flight=nil
local flyer,flyer_owner=nil,nil
-- At the catch the flyer stays drawn one more frame, on the held hammer's
-- exact pose, while the held one comes back: an overlap cannot be seen, a
-- frame with neither (the held mesh draws through a proxy) can.
local linger=nil
local report=nil

local function valid(o)return o and o.IsValid and o:IsValid()end
local function v3(p)return {X=tonumber(p.X)or 0,Y=tonumber(p.Y)or 0,Z=tonumber(p.Z)or 0}end
local function r3(r)return {Pitch=tonumber(r.Pitch)or 0,Yaw=tonumber(r.Yaw)or 0,Roll=tonumber(r.Roll)or 0}end
local function add(a,b,s)return {X=a.X+b.X*s,Y=a.Y+b.Y*s,Z=a.Z+b.Z*s}end
local function sub(a,b)return {X=a.X-b.X,Y=a.Y-b.Y,Z=a.Z-b.Z}end
local function len(a)return math.sqrt(a.X*a.X+a.Y*a.Y+a.Z*a.Z)end
local function unit(a,fallback)local n=len(a);if n<1e-6 then return fallback end;return {X=a.X/n,Y=a.Y/n,Z=a.Z/n}end
local function fmt(p)return p and string.format('(%.0f, %.0f, %.0f)',p.X,p.Y,p.Z)or'?'end
local function smooth(x)x=math.max(0,math.min(1,x));return x*x*(3-2*x)end

-- Quadrant-safe atan2 that behaves the same in every Lua version.
local function atan2(y,x)
 if x>0 then return math.atan(y/x)end
 if x<0 then return math.atan(y/x)+(y>=0 and math.pi or -math.pi)end
 return y>0 and math.pi/2 or(y<0 and -math.pi/2 or 0)
end
local function asin(x)return atan2(x,math.sqrt(math.max(0,1-x*x)))end

-- Unreal's own rotator <-> quaternion conversions (FRotator::Quaternion,
-- FQuat::Rotator), so orientation blends never flip through a gimbal.
function R.quat(r)
 local p,y,ro=math.rad(r.Pitch)/2,math.rad(r.Yaw)/2,math.rad(r.Roll)/2
 local SP,CP,SY,CY,SR,CR=math.sin(p),math.cos(p),math.sin(y),math.cos(y),math.sin(ro),math.cos(ro)
 return {X=CR*SP*SY-SR*CP*CY,Y=-CR*SP*CY-SR*CP*SY,Z=CR*CP*SY-SR*SP*CY,W=CR*CP*CY+SR*SP*SY}
end
function R.rotator(q)
 local X,Y,Z,W=q.X,q.Y,q.Z,q.W
 local test=Z*X-W*Y
 local yaw=math.deg(atan2(2*(W*Z+X*Y),1-2*(Y*Y+Z*Z)))
 if test<-.4999995 then return {Pitch=-90,Yaw=yaw,Roll=-yaw-2*math.deg(atan2(X,W))}end
 if test>.4999995 then return {Pitch=90,Yaw=yaw,Roll=yaw-2*math.deg(atan2(X,W))}end
 return {Pitch=math.deg(asin(2*test)),Yaw=yaw,Roll=math.deg(atan2(-2*(W*X+Y*Z),1-2*(X*X+Y*Y)))}
end
function R.slerp(a,b,t)
 local d=a.X*b.X+a.Y*b.Y+a.Z*b.Z+a.W*b.W
 if d<0 then b={X=-b.X,Y=-b.Y,Z=-b.Z,W=-b.W};d=-d end
 local wa,wb
 if d>.9995 then wa,wb=1-t,t
 else local th=math.acos(d);local s=math.sin(th);wa,wb=math.sin((1-t)*th)/s,math.sin(t*th)/s end
 local q={X=wa*a.X+wb*b.X,Y=wa*a.Y+wb*b.Y,Z=wa*a.Z+wb*b.Z,W=wa*a.W+wb*b.W}
 local n=math.sqrt(q.X^2+q.Y^2+q.Z^2+q.W^2)
 return {X=q.X/n,Y=q.Y/n,Z=q.Z/n,W=q.W/n}
end

-- Hamilton product (Unreal's FQuat a*b: b applied first, then a).
local function qmul(a,b)
 return {X=a.W*b.X+a.X*b.W+a.Y*b.Z-a.Z*b.Y,Y=a.W*b.Y-a.X*b.Z+a.Y*b.W+a.Z*b.X,
  Z=a.W*b.Z+a.X*b.Y-a.Y*b.X+a.Z*b.W,W=a.W*b.W-a.X*b.X-a.Y*b.Y-a.Z*b.Z}
end
-- Turned about the handle so the two heads face up and down in flight
-- (unrolled they face left and right).
local ROLL={X=0,Y=0,Z=math.sin(math.rad(HEAD_ROLL)/2),W=math.cos(math.rad(HEAD_ROLL)/2)}
-- Head-first orientation for a direction of travel.
function R.facing(d)
 local horizontal=math.sqrt(d.X*d.X+d.Y*d.Y)
 local base={Pitch=math.deg(atan2(d.Z,horizontal))+HEAD_PITCH,Yaw=math.deg(atan2(d.Y,d.X)),Roll=0}
 return R.rotator(qmul(R.quat(base),ROLL))
end
-- Pure path maths (kept separate so it can be checked offline).
-- The player's right, for a hammer travelling along dir away from Hun
-- (UE: X forward, Y right).
local function right_of(dir)return unit({X=-dir.Y,Y=dir.X,Z=0},{X=0,Y=1,Z=0})end
-- How long the way home takes from this far.
function R.duration(distance)
 local close=math.min(distance,CLOSE_DISTANCE)
 local duration=close/CLOSE_SPEED+(distance-close)/LONG_SPEED
 return math.max(MIN_H,math.min(MAX_H,duration))
end
-- How fast it reaches the hand on a T-second way home this long.
function R.arrival(distance,T)return math.max(V_MIN,ARRIVE*distance/T)end
-- The way home: a Hermite curve that starts with the hammer's own motion
-- (so it never stops or snaps) and arrives in the hand at R.arrival, coming
-- in from the player's right.  dir is the throw's direction (away from Hun).
-- Returns position and velocity (cm/s) at s in 0..1 of a T-second flight.
function R.home(p0,v0,p1,dir,T,s)
 local D=sub(p1,p0)
 local m0={X=v0.X*T,Y=v0.Y*T,Z=v0.Z*T}
 -- Coming in from the player's right means moving to their left at the end.
 local inn=unit(add(unit(D,dir),right_of(dir),-ARRIVE_SIDE),unit(D,dir))
 local v1=R.arrival(len(D),T)
 local m1={X=inn.X*v1*T,Y=inn.Y*v1*T,Z=inn.Z*v1*T}
 local s2,s3=s*s,s*s*s
 local h00,h10,h01,h11=2*s3-3*s2+1,s3-2*s2+s,-2*s3+3*s2,s3-s2
 local d00,d10,d01,d11=6*s2-6*s,3*s2-4*s+1,-6*s2+6*s,3*s2-2*s
 local p,v={},{}
 for _,k in ipairs({'X','Y','Z'})do
  p[k]=h00*p0[k]+h10*m0[k]+h01*p1[k]+h11*m1[k]
  v[k]=(d00*p0[k]+d10*m0[k]+d01*p1[k]+d11*m1[k])/T
 end
 return p,v
end
-- Where the hammer is going: the held hammer itself (its live pose is where
-- the visible hammer sits in Hun's hand), or the hand bone if unreadable.
local function target(pawn,held)
 if valid(held)then
  local ok,p=pcall(function()return v3(held:K2_GetComponentLocation())end)
  local okr,r=pcall(function()return r3(held:K2_GetComponentRotation())end)
  if ok and p then return p,okr and r or nil end
 end
 local ok,p=pcall(function()return pawn.Mesh:GetSocketLocation(FName('hand_r'))end)
 if ok and p then return v3(p),nil end
 local ok2,a=pcall(function()return pawn:K2_GetActorLocation()end)
 return ok2 and a and add(v3(a),UP,40)or nil,nil
end

-- A return is in progress (the carried flight out is not a return).
function R.active()return flight~=nil and flight.kind=='return'end
-- Where the flying hammer is drawn now (out or back), or nil.
function R.position()return flight and flight.at or nil end
function R.bridging()return flight~=nil and flight.kind=='out'end
-- Which part of the return is playing: 'hitstop', 'bounce', 'stall', 'home', 'align'.
function R.phase()return flight and flight.phase end
-- The mesh that draws the flying hammer (for its trail), or nil.
function R.flyer()return flight and valid(flight.mesh)and flight.mesh or nil end

-- The flying hammer: one plain mesh component on Hun, made on first use.
local function get_flyer(pawn)
 linger=nil   -- flying again: it is not to be hidden
 local owner=pawn:GetFullName()
 if valid(flyer)and flyer_owner==owner then return flyer,'reused'end
 local cls=StaticFindObject('/Script/Engine.SkeletalMeshComponent')
 local mesh=StaticFindObject(MESH)
 if not valid(cls)or not valid(mesh)then return nil,'class or hammer mesh not loaded'end
 local ok,c=pcall(function()
  return pawn:AddComponentByClass(cls,false,{Rotation={X=0,Y=0,Z=0,W=1},Translation={X=0,Y=0,Z=0},Scale3D={X=1,Y=1,Z=1}},false)
 end)
 if not ok or not valid(c)then return nil,'AddComponentByClass failed: '..tostring(c)end
 local set=pcall(function()c:SetSkeletalMeshAsset(mesh)end)
 if not set then return nil,'SetSkeletalMeshAsset failed'end
 pcall(function()c:SetAbsolute(true,true,true)end)
 pcall(function()c:SetVisibility(false,true)end)
 flyer,flyer_owner=c,owner
 return c,'created'
end

local function size_like(f,held)
 if valid(held)then
  pcall(function()local s=held:K2_GetComponentScale();f:SetWorldScale3D({X=tonumber(s.X)or 1,Y=tonumber(s.Y)or 1,Z=tonumber(s.Z)or 1})end)
 end
end
local function pose_of(c)
 local p,r
 pcall(function()p=v3(c:K2_GetComponentLocation())end)
 pcall(function()r=r3(c:K2_GetComponentRotation())end)
 return p,r
end
local function place(f,p,q)
 pcall(function()f.mesh:K2_SetWorldLocationAndRotation(p,R.rotator(q),false,{},true)end)
 f.at,f.q=p,q;f.frames=f.frames+1
end

-- The release: in the frame the dart starts, hide the dart's hammer and
-- show the flyer exactly where the held hammer is; from then on the flyer
-- carries the hammer on the dart's path until the return takes over.
function R.bridge(pawn,held,dart,now)
 if flight or not valid(held)or not valid(dart)then return false end
 local from,from_rot=pose_of(held);if not from or not from_rot then return false end
 local f=get_flyer(pawn);if not f then return false end
 size_like(f,held)
 local d=pose_of(dart)
 flight={kind='out',pawn=pawn,held=held,mesh=f,dart=dart,from_q=R.quat(from_rot),start=now,frames=0,
  offset=d and sub(from,d)or {X=0,Y=0,Z=0},dart_at=d or from,last_t=now}
 flight.heading=flight.from_q
 place(flight,from,flight.from_q)
 pcall(function()f:SetVisibility(true,true)end)
 pcall(function()dart:SetVisibility(false,true)end)
 return true
end

-- One step of the carried flight out.
local function out_tick(f,now)
 local t=now-f.start
 if t>OUT_LIMIT then R.finish();return 'bridged'end
 -- Follow the dart -- but never to where it cannot be: a put-away or
 -- destroyed dart reads the world origin, and following it there once sent
 -- the hammer home from 2.3 km away.  Long real flights are kept.
 if valid(f.dart)then
  local d=pose_of(f.dart)
  local dt=math.max(.001,now-f.last_t)
  if d and math.abs(d.X)+math.abs(d.Y)+math.abs(d.Z)>1 and len(sub(d,f.dart_at))<=MAX_JUMP_V*dt+300 then f.dart_at=d end
 end
 -- The gap to the dart closes smoothly: at the hand it moves exactly as the
 -- dart does, and it is on the dart's path by RELEASE.
 local p=add(f.dart_at,f.offset,1-smooth(t/RELEASE))
 local dt=now-f.last_t
 if dt>0 then
  local v=sub(p,f.at);v={X=v.X/dt,Y=v.Y/dt,Z=v.Z/dt}
  f.vel=v
  if len(v)>50 then
   local want=R.quat(R.facing(v))
   if t<OUT_TURN then f.heading=want
   else f.heading=R.slerp(f.heading,want,1-math.exp(-dt/OUT_SMOOTH))end
  end
 end
 f.last_t=now
 local q=t<OUT_TURN and R.slerp(f.from_q,f.heading,smooth(t/OUT_TURN))or f.heading
 place(f,p,q)
 return 'bridging'
end

-- An axis-angle quaternion (degrees).
local function about(axis,degrees)
 local h=math.rad(degrees)/2;local s=math.sin(h)
 return {X=axis.X*s,Y=axis.Y*s,Z=axis.Z*s,W=math.cos(h)}
end
-- A vector turned by a quaternion.
local function qrotate(q,v)
 local tx,ty,tz=2*(q.Y*v.Z-q.Z*v.Y),2*(q.Z*v.X-q.X*v.Z),2*(q.X*v.Y-q.Y*v.X)
 return {X=v.X+q.W*tx+(q.Y*tz-q.Z*ty),Y=v.Y+q.W*ty+(q.Z*tx-q.X*tz),Z=v.Z+q.W*tz+(q.X*ty-q.Y*tx)}
end
-- The loose part at t seconds after it starts: position, velocity and how
-- far it has tumbled (degrees).  A hit's bounce: air drag on everything,
-- gravity down, tumbling and slowing.  A miss: braking hard along the way
-- it flew, no tumble.
local function loose_at(f,t)
 if f.mode=='hit'then
  local e=math.exp(-DRAG*t)
  local p=add(f.bitten,f.bv,(1-e)/DRAG)
  p.Z=p.Z-(GRAVITY/DRAG)*(t-(1-e)/DRAG)
  return p,{X=f.bv.X*e,Y=f.bv.Y*e,Z=f.bv.Z*e-(GRAVITY/DRAG)*(1-e)},TUMBLE*(1-e)/DRAG,TUMBLE*e
 end
 local e=math.exp(-BRAKE*t)
 return add(f.from,f.dir,f.speed*(1-e)/BRAKE),{X=f.dir.X*f.speed*e,Y=f.dir.Y*f.speed*e,Z=f.dir.Z*f.speed*e},0,0
end
local function tumbled(f,degrees)return degrees~=0 and qmul(about(f.axis,degrees),f.base)or f.base end
-- Plans the impact, the bounce and the recall from the contact pose.
local function plan(f,to)
 f.base=f.from_q or R.quat(R.facing(f.dir))
 if f.mode=='hit'then
  f.bitten=add(f.from,f.dir,EMBED)
  local r=right_of(f.dir)
  f.bv={X=-f.dir.X*BOUNCE_BACK+r.X*BOUNCE_SIDE,Y=-f.dir.Y*BOUNCE_BACK+r.Y*BOUNCE_SIDE,Z=-f.dir.Z*BOUNCE_BACK+BOUNCE_UP}
  -- End over end about the player's right axis, the head going up first.
  f.axis=right_of(f.dir)
  if qrotate(qmul(about(f.axis,10),f.base),{X=0,Y=0,Z=1}).Z<qrotate(f.base,{X=0,Y=0,Z=1}).Z then f.axis={X=-f.axis.X,Y=-f.axis.Y,Z=0}end
  -- Hun calls it on the way down: when it falls at CALL_FALL.
  local gk=GRAVITY/DRAG
  f.loose_t=-math.log((CALL_FALL+gk)/(f.bv.Z+gk))/DRAG
  f.pre=f.stop+f.loose_t
 else
  f.loose_t=STALL
  f.pre=STALL
 end
 -- The recall starts from where it is, with the motion (and tumble) it has.
 f.call_p,f.call_v,f.call_deg,f.call_spin=loose_at(f,f.loose_t)
 f.duration=R.duration(len(sub(to,f.call_p)))
end
-- Starts a return; false and a reason if it cannot be done.
-- held: the hammer Hun holds (its size, and where the flight ends), may be nil.
-- from: where the dart's hammer is now; from_rot: its orientation (optional).
-- hold: a real hit -- the hit-stop length; 0 for a throw that hit nothing.
-- If the flyer is carrying the hammer out, the return takes over from
-- wherever it is drawn, so it is still one hammer.
function R.begin(pawn,held,from,now,from_rot,hold)
 local carried=flight and flight.kind=='out'and flight or nil
 if flight and not carried then return false,'already flying'end
 local vel
 if carried then
  out_tick(carried,now)
  if flight~=carried then carried=nil   -- the carry ran out
  else from,from_rot,vel=carried.at,R.rotator(carried.q),carried.vel end
 end
 if not from then return false,'no dart position'end
 local to=target(pawn,held);if not to then return false,'no hand position'end
 local f,how=get_flyer(pawn);if not f then return false,how end
 size_like(f,held)
 from=v3(from)
 -- Which way it was flying: its own motion, or else away from Hun.
 local away=unit(sub(from,to),{X=1,Y=0,Z=0})
 local speed=vel and math.min(MAX_V,len(vel))or THROW_V
 local dir=(vel and len(vel)>100)and unit(vel,away)or away
 local stop=math.max(0,hold or 0)
 flight={kind='return',pawn=pawn,held=held,mesh=f,from=from,from_q=from_rot and R.quat(r3(from_rot))or nil,
  dir=dir,speed=speed,mode=stop>0 and'hit'or'stall',stop=stop,start=now,frames=0,
  dart=carried and carried.dart or nil}
 plan(flight,to)
 report={flyer=how,from=from,distance=len(sub(to,from)),from_rot=from_rot~=nil,mode=flight.mode,stop=stop,start=now}
 R.tick(now)   -- placed at the contact pose before it is shown
 pcall(function()f:SetVisibility(true,true)end)
 return true,flight.pre+flight.duration
end

-- The frame after the catch: the flyer that stayed on the held hammer goes.
-- Call every frame; safe any time.
function R.flush()
 local m=linger;linger=nil
 if valid(m)then pcall(function()m:SetVisibility(false,true)end)end
end
-- Hides the flyer (while carrying out, the dart gets its hammer back).  Safe any time.
function R.finish()
 local f=flight;flight=nil
 if not f then return end
 if f.kind=='out'then
  if valid(f.dart)then pcall(function()f.dart:SetVisibility(true,true)end)end
 elseif report then report.frames=f.frames end
 if valid(f.mesh)then pcall(function()f.mesh:SetVisibility(false,true)end)end
end
-- A hit reported in the same frame the return began (the game puts the dart
-- away before it reports a solid hit): it was a hit after all.
function R.wedge(now,hold)
 local f=flight
 if not f or f.kind~='return'or f.mode=='hit'or now-f.start>.03 then return false end
 f.mode,f.stop='hit',hold
 local to=target(f.pawn,f.held)
 if to then plan(f,to)end
 if report then report.mode,report.stop='hit',hold end
 return true
end

-- The catch frame: the flyer sits exactly on the held hammer's pose, so
-- swapping one for the other cannot be seen.
function R.catch(f,to,to_rot,now)
 if report then report.catch_gap=report.last and len(sub(to,report.last))or 0 end
 local q=to_rot and R.quat(to_rot)or R.quat(R.facing(sub(to,report and report.last or f.from)))
 place(f,to,q)
 if report then report.final=to;report.last_t=now;report.frames=f.frames end
 -- Still drawn this frame, exactly where the held hammer reappears; gone next frame.
 flight=nil;linger=f.mesh
 return 'arrived',true
end
-- Proof from the engine itself, once mid-flight: where the flyer really is
-- and whether it is visible, against where it was asked to be.
function R.proof(f,p,s)
 if not report then return end
 if s>=.4 and not report.mid then
  local ok,at=pcall(function()return v3(f.mesh:K2_GetComponentLocation())end)
  local okv,vis=pcall(function()return f.mesh:IsVisible()end)
  report.mid={asked=p,actual=ok and at or nil,visible=okv and vis or nil}
 end
 report.last=p
end

-- Moves the hammer one step.  Returns 'flying', 'arrived', 'bridging',
-- 'bridged', or nil (nothing in the air).
function R.tick(now)
 local f=flight;if not f then return nil end
 if f.kind=='out'then return out_tick(f,now)end
 if not valid(f.mesh)or not valid(f.pawn)then R.finish();return 'arrived'end
 local t=now-f.start
 local to,to_rot=target(f.pawn,f.held)
 if t>=f.pre+LIMIT or not to then R.finish();return 'arrived'end
 if report then report.last_t=now end
 if f.mode=='hit'and t<f.stop then
  -- Hit-stop: it bites in and holds, shuddering less and less.
  f.phase='hitstop'
  local fade=1-t/f.stop
  local r=R.rotator(f.base)
  local w=SHUDDER*fade*math.sin(t*2*math.pi*SHUDDER_HZ)
  place(f,add(f.from,f.dir,EMBED*smooth(t/BITE)),R.quat({Pitch=r.Pitch+w,Yaw=r.Yaw+.6*w,Roll=r.Roll}))
  return 'flying'
 end
 if t<f.pre then
  -- The bounce (a hit): pure physics, tumbling end over end.  A miss brakes.
  f.phase=f.mode=='hit'and'bounce'or'stall'
  local p,_,deg=loose_at(f,t-(f.mode=='hit'and f.stop or 0))
  place(f,p,tumbled(f,deg))
  return 'flying'
 end
 -- The recall: it carries on the way the bounce has it (p_b) while the pull
 -- toward Hun's hand (p_h, a smooth path from its call pose, with its call
 -- motion, into the hand) takes over more and more -- never yanked, its
 -- speed continuous.  Its tumble dies out and over the first FACE of the
 -- recall it turns to face the way it flies; near Hun it blends into the
 -- held hammer's exact orientation.
 t=t-f.pre
 local T=f.duration
 local s=math.min(1,t/T)
 if s>=1 then return R.catch(f,to,to_rot,now)end
 local pb,vb=loose_at(f,f.loose_t+t)
 local ph,vh=R.home(f.call_p,f.call_v,to,f.dir,T,s)
 -- The pull has fully taken over by PULL of the way, so the last stretch is
 -- the smooth path alone, gathering speed evenly into the hand (a blend over
 -- the whole way surged mid-flight, then eased into the hand).
 local x=math.min(1,s/PULL)
 -- Ease-out: the pull grows fastest at the call, while the two paths are
 -- still together, and settles gently.
 local w,dw=1-(1-x)^3,3*(1-x)^2/(PULL*T)
 local gap=sub(ph,pb)
 local p=add(pb,gap,w)
 local v={X=vb.X+(vh.X-vb.X)*w+gap.X*dw,Y=vb.Y+(vh.Y-vb.Y)*w+gap.Y*dw,Z=vb.Z+(vh.Z-vb.Z)*w+gap.Z*dw}
 local q=tumbled(f,f.call_deg+f.call_spin*SPIN_FADE*(1-math.exp(-t/SPIN_FADE)))
 -- A miss turns right round (~180 degrees), so it takes longer over it.
 local face=f.mode=='hit'and FACE or FACE_MISS
 if len(v)>50 then q=R.slerp(q,R.quat(R.facing(v)),smooth(math.min(1,s/face)))end
 local left=(1-s)*T
 f.phase='home'
 if left<GRIP_BLEND and to_rot then
  f.phase='align'
  q=R.slerp(q,R.quat(to_rot),smooth(1-left/GRIP_BLEND))
 end
 place(f,p,q);R.proof(f,p,s)
 return 'flying'
end
-- One line for the log after a catch.
function R.describe()
 local r=report;if not r then return 'no return recorded'end
 local m=r.mid or {}
 local off=(m.asked and m.actual)and len(sub(m.asked,m.actual))or nil
 local span=(r.last_t and r.start)and r.last_t-r.start or 0
 local cadence=(r.frames or 0)>1 and span>0 and string.format(' (%.1f ms a frame)',span*1000/((r.frames or 1)-1))or''
 return string.format('flyer %s; from %s%s, %s, %.0f cm; %d frames in %.2f s%s; mid-flight asked %s, engine says %s (off by %s cm), visible=%s; closing step %s cm, ended on the held hammer',
  r.flyer,fmt(r.from),r.from_rot and ' (dart pose)'or'',r.mode=='hit'and string.format('hit-stop %.2f s then bounce',r.stop or 0)or'nothing hit, braked',
  r.distance or 0,r.frames or 0,span,cadence,fmt(m.asked),fmt(m.actual),off and string.format('%.0f',off)or'?',tostring(m.visible),r.catch_gap and string.format('%.0f',r.catch_gap)or'?')
end
return R

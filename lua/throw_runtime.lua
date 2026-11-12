-- The throw.  The game's own dart (the EMei boss's, launched by the
-- HomingThrow ability) owns launch, flight and collision; this script makes
-- it Mjolnir:
--   launch  the dart is styled as the hammer, the hand emptied, and the
--           flyer (return_flight) carries the hammer out on the dart's path;
--           a camera-aimed throw (throw_aim) is pointed where you look
--   hit     the dart's contact (On Trace Hit / OnHitSolid) or its end
--           (Received_Deactivate) hands the hammer to the return flight
--   catch   the return lands in the hand; hand, gate and dart are restored
-- The throw gate (the HasProjectile tag) blocks another throw from the
-- launch to the catch.  If the return flight cannot start, the hand is
-- restored with a quiet, short snap.
local H=require('UEHelpers');local D=require('runtime_diagnostics');local Feedback=require('attack_feedback');local T={}
local Return=require('return_flight')
local Aim=require('throw_aim')
local Homing=require('throw_homing')   -- a throw the game aims homes onto its enemy
local Recall=require('recall_input')   -- the ultimate input calls the hammer back early
local Trail=require('throw_trail')     -- the lightning trail on the flying hammer, release to catch
local Arm=require('recall_arm')
local Glow=require('rune_glow')
-- Early recall: pressing the ultimate input again (a new press -- holding it
-- from the throw does not count) turns the hammer back once it has flown
-- RECALL_MIN; a press before that is kept and acts at RECALL_MIN.
local RECALL_MIN=.5
local flight_dart=nil
local recall_armed,recall_was,recall_req=false,false,false
local stilled={}   -- darts a recall switched off (pooled: switched back on at their next launch)
local function watch_recall(projectile, now)
 flight_dart=projectile
 recall_armed,recall_was,recall_req=false,true,false
 pcall(Recall.update,now,true)
end
-- Up and down: a camera-aimed throw's dart is pointed where the camera looks
-- (turning Hun only sets the heading; the dart starts level).  Its velocity
-- is set at launch and re-checked for AIM_HOLD in case the game's own
-- movement resets it; the log says what the dart ended up doing.
local AIM_HOLD=.12
local aim_dart,aim_until,aim_said=nil,nil,false
local function point_dart(projectile)
 local okm,mv=pcall(function()return projectile.SGameProjectileMovement end)
 if not okm or not(mv and mv.IsValid and mv:IsValid())then
  if not aim_said then aim_said=true;D.write('throw','throw up/down aim: the dart\'s movement cannot be read')end
  return
 end
 local okv,v=pcall(function()return mv.Velocity end)
 if not okv or not v then return end
 local vx,vy,vz=tonumber(v.X)or 0,tonumber(v.Y)or 0,tonumber(v.Z)or 0
 local speed=math.sqrt(vx*vx+vy*vy+vz*vz);if speed<100 then speed=5000 end
 local okp,from=pcall(function()return projectile:K2_GetActorLocation()end)
 local d=Aim.launch_direction(okp and from or nil);if not d then return end
 if(vx*d.X+vy*d.Y+vz*d.Z)/speed>.995 then return end   -- already on it
 pcall(function()mv.Velocity={X=d.X*speed,Y=d.Y*speed,Z=d.Z*speed}end)
 if not aim_said then
  aim_said=true
  local okr,r=pcall(function()return mv.Velocity end)
  local now_d=okr and r and string.format('(%.0f, %.0f, %.0f)',tonumber(r.X)or 0,tonumber(r.Y)or 0,tonumber(r.Z)or 0)or'?'
  D.write('throw',string.format('throw aimed up/down with the camera: pitch %.0f; dart velocity was (%.0f, %.0f, %.0f), now %s',
   math.deg(math.asin(math.max(-1,math.min(1,d.Z)))),vx,vy,vz,now_d))
 end
end
-- Lighter flight out: the dart's bullet data gives it twice normal gravity,
-- so it sagged visibly on the way out.  Its movement's gravity scale is
-- lowered at launch and kept there while it flies out (the game may reset it).
local DART_GRAVITY=.5
local light_dart,light_said=nil,false
local function lighten_dart(projectile)
 local ok,mv=pcall(function()return projectile.SGameProjectileMovement end)
 if not ok or not(mv and mv.IsValid and mv:IsValid())then return end
 local okg,g=pcall(function()return tonumber(mv.ProjectileGravityScale)end)
 if not okg or not g or g<=DART_GRAVITY+1e-3 then return end
 pcall(function()mv.ProjectileGravityScale=DART_GRAVITY end)
 if not light_said then
  light_said=true
  local okn,n=pcall(function()return tonumber(mv.ProjectileGravityScale)end)
  D.write('throw',string.format('dart gravity %.2f -> %s',g,okn and n and string.format('%.2f',n)or'?'))
 end
end
local RESUME=.25      -- seconds the flight sound takes to swell back in after a bounce
local fly_resume=nil  -- false while bouncing, then the time at which the swell began
local hide_next=false -- empty the hand next frame (the flyer is already drawn on it)
local WEDGE=.09   -- a real hit: the hammer's hit-stop before it ricochets back
local started=false;local owner=nil;local owner_id=nil;local active=false
local flight_key=nil      -- the throw's own dart: only its events count
local launch_seen=false   -- launch events work: the scan never adopts a dart itself
local last_scan=-1;local began=0;local missing_since=nil;local hidden={}
local quarantined=false
local fake_recall_until=nil;local last_position=nil
local styled_projectiles={}
local release_key, impact_done
local pending_release,pending_impact
local recall_cue_sent=false
local hit_hooks={}
-- Seamless handoff from the dart's hammer to the flying one (defined below).
local hand_off
local handed_off={}   -- dart key -> its hammer has gone to the flyer; ignore the dart now
local hidden_darts={} -- dart key -> its mesh component, hidden at the handoff
-- Contacts reported in the first moments of a flight are the launch trace
-- touching Hun or the ground, not a hit on anything.
local LAUNCH_GRACE=.06
local OUT='CharacterState.AbilityState.Mojian.HasProjectile'
local function valid(o)return o and o:IsValid()end
local function num(v)
 if type(v)=='number'then return v end
 local ok,n=pcall(function()return v:get()end)
 return ok and tonumber(n)or tonumber(tostring(v))
end
local function id(o)return valid(o)and o:GetFullName()or ''end
-- A real position: a destroyed or pooled dart reads the world origin, and a
-- hammer once flew home from 2.3 km away because of it.
local function plausible(p)
 if not p then return false end
 local x,y,z=tonumber(p.X)or 0,tonumber(p.Y)or 0,tonumber(p.Z)or 0
 return math.abs(x)+math.abs(y)+math.abs(z)>1
end
local function location(o)
 local ok,p=pcall(function()return o:K2_GetActorLocation()end)
 return ok and plausible(p)and p or nil
end
local function owned(o,pawn)
 if not valid(o)then return false end
 local seen={};local queue={o}
 for _=1,8 do
  local q=table.remove(queue,1);if not valid(q)then return false end
  local name=id(q);if name==id(pawn)then return true end
  if not seen[name]then
   seen[name]=true
   for _,method in ipairs({'GetOwner','GetAttachParentActor'})do
    local ok,parent=pcall(function()return q[method](q)end)
    if ok and valid(parent)then queue[#queue+1]=parent end
   end
  end
  if #queue==0 then return false end
 end
 return false
end
-- The throw gate: HomingThrow cannot start while Hun carries this tag.
local function gate_tags()return {GameplayTags={{TagName=H.FindOrAddFName(OUT)}},ParentTags={}}end
local function ability_lib()
 local lib=StaticFindObject('/Script/GameplayAbilities.Default__AbilitySystemBlueprintLibrary')
 return valid(lib)and lib or nil
end
-- true/false when the engine can tell us, nil when it cannot.
local function gate_held(pawn)
 local lib=ability_lib();if not lib then return nil end
 local ok,has=pcall(function()
  local asc=lib:GetAbilitySystemComponent(pawn)
  return asc:HasMatchingGameplayTag({TagName=H.FindOrAddFName(OUT)})
 end)
 if ok and type(has)=='boolean'then return has end
 return nil
end
-- PBZ's own tag route, the one the Mjolnir passive uses to set and clear this
-- gate: AbilityUtils.Add/RemoveLooseGameplayTagForSystem(ASC, tag, false).
-- The engine's AddLooseGameplayTags (a tag container) did not take in game:
-- the gate read open straight after it, every time, and throws got through.
local function pbz_utils()
 local u=StaticFindObject('/Script/SGameUtils.Default__AbilityUtils')
 return valid(u)and u or nil
end
-- Adds (+1) or removes (-1) one gate tag; returns the route used, or nil.
local function gate_tag(pawn,delta)
 local u=pbz_utils();local lib=ability_lib()
 if u and lib then
  local ok=pcall(function()
   local asc=lib:GetAbilitySystemComponent(pawn)
   local tag={TagName=H.FindOrAddFName(OUT)}
   if delta>0 then u:AddLooseGameplayTagForSystem(asc,tag,false)else u:RemoveLooseGameplayTagForSystem(asc,tag,false)end
  end)
  if ok then return 'PBZ system tag'end
 end
 if lib then
  local ok=pcall(function()
   if delta>0 then lib:AddLooseGameplayTags(pawn,gate_tags(),false)else lib:RemoveLooseGameplayTags(pawn,gate_tags(),false)end
  end)
  if ok then return 'engine loose tag'end
 end
end
-- The game lets the gate go when the dart ends, but the hammer is still on
-- its way home: hold the gate until the catch so it cannot be thrown twice
-- (HomingThrow's ActivationBlockedTags include the gate tag).  Ours goes on
-- once per return whatever the tag check says, and again only if the check
-- clearly reads the gate open (something took ours off) -- at most a few
-- times.  Every one we add is counted and the catch removes exactly those,
-- so the throw can never be left locked.
local gate_count,gate_route=0,nil
local GATE_MAX=4
local function hold_gate(pawn,why)
 if gate_count>0 and(gate_held(pawn)~=false or gate_count>=GATE_MAX)then return end
 local before=gate_held(pawn)
 local route=gate_tag(pawn,1)
 if not route then D.write('throw','could not hold the throw gate');return end
 gate_count=gate_count+1;gate_route=route
 D.write('throw',string.format('throw blocked until the catch (%s, %s #%d; the gate read %s before, %s after)',why or'return',route,gate_count,tostring(before),tostring(gate_held(pawn))))
end
local function restore(caught)
 pending_release,pending_impact=nil,nil
 recall_cue_sent=false
 fly_resume=nil
 pcall(Trail.stop_pulse)
 if caught then
  local ok,err=pcall(Arm.catch)
  if not ok then D.state('recall catch pose',tostring(err));pcall(Arm.reset)end
 else pcall(Arm.reset)end
 pcall(Trail.stop)  -- the trail fades as the hammer lands in the hand
 Return.finish()   -- the hammer goes back on the hand before anything else
 if active and valid(owner)then pcall(Feedback.stop_flight,owner)end   -- no flight sound left looping
 for _,entry in pairs(hidden)do
  if valid(entry.mesh)then pcall(function()entry.mesh:SetVisibility(entry.visible,true)end)end
 end
 hidden={}
 if active and valid(owner)then
  if gate_count>0 then
   -- Exactly the ones we added.
   for _=1,gate_count do if not gate_tag(owner,-1)then return false end end
  else
   -- We never held it: release the game's own, as the throw ends here.
   local lib=ability_lib()
   if not lib then return false end
   local ok=pcall(function()lib:RemoveLooseGameplayTags(owner,gate_tags(),false)end)
   if not ok then return false end
  end
 end
 gate_count,gate_route=0,nil
 active=false;flight_key=nil;missing_since=nil;release_key=nil;impact_done=false;return true
end
local function play_release(pawn, projectile)
 local key=id(projectile)
 if release_key==key then return end
 release_key=key
 pcall(Feedback.throw,pawn)
end
-- One impact per throw, only while the hammer is really in flight.  The
-- native hooks fire for launch traces and many times per frame while the
-- projectile is inside an enemy, so neither may produce extra impacts.
-- Hun's own dart from a hook context, or nil.
local function own_dart(context)
 local ok,projectile=pcall(function()return context:get()end)
 if not ok or not valid(projectile)then return nil end
 if not id(projectile):find('BP_Bullet_EMei_Dart_C_',1,true)then return nil end
 local pc=H.GetPlayerController()
 local pawn=valid(pc)and pc.Pawn or nil
 if not valid(pawn) or id(projectile:GetOwnerAvatar())~=id(pawn)then return nil end
 return projectile,pawn
end
local function on_projectile_hit(context,kind)
 if not active or impact_done then return end
 local projectile,pawn=own_dart(context);if not projectile then return end
 -- Only the throw's own dart (a stray one's contacts started false returns).
 if flight_key and id(projectile)~=flight_key then return end
 local t=H.GetGameplayStatics():GetTimeSeconds(pawn)
 if t-began<LAUNCH_GRACE then return end
 impact_done=true
 Glow.strike(id(pawn),t)
 -- The return starts from where the hammer really struck.
 last_position=location(projectile)or last_position
 if last_position then
  pending_impact={X=last_position.X,Y=last_position.Y,Z=last_position.Z}
 end
 pcall(Feedback.throw_impact,pawn)
 D.write('throw','native projectile contact ('..(kind or 'solid')..'); impact cue requested')
 -- The game may already have put the dart away this frame (its put-away
 -- event comes before the solid hit): then wedge the return that started.
 if Return.active()then Return.wedge(t,WEDGE)
 elseif hand_off then hand_off(projectile,pawn,'hit')end
end
-- How many hits a hook's hit array carries; nil if it cannot be read.
local function hit_count(param)
 if param==nil then return nil end
 local ok,arr=pcall(function()return param:get()end)
 if not ok or arr==nil then arr=param end
 for _,read in ipairs({function()return arr:GetArrayNum()end,function()return #arr end})do
  local okn,n=pcall(read)
  if okn and tonumber(n)then return tonumber(n)end
 end
 return nil
end
-- "On Trace Hit" is the dart's attack-trace update: the game calls it as the
-- dart flies whether or not the trace touched anything (its own blueprint
-- checks the length of HitData).  Only an update that carries hits is a hit.
local trace_unreadable_logged=false
-- Every bullet in the game (KillLight's attack volumes too) runs through this
-- hook many times a frame, so nothing is read unless it is Hun's dart in
-- flight: reading another bullet's hit list crashed the game.
local function on_trace_hit(context,hit_data)
 if not active or impact_done then return end
 if not own_dart(context)then return end
 local n=hit_count(hit_data)
 if n==nil then
  if not trace_unreadable_logged then trace_unreadable_logged=true;D.write('throw','trace hit list unreadable; using solid hits and the end of flight only')end
  return
 end
 if n<1 then return end
 on_projectile_hit(context,'trace, '..n..' hit'..(n==1 and''or's'))
end
-- Filled in below, once the functions they call exist.
local launch_hook,deactivate_hook
local function install_hit_hooks()
 local class='/PBZCombatAsset/Prototypes/Bullet/Bullets/BP_PBZ_ProjectileBullet.BP_PBZ_ProjectileBullet_C:'
 local handlers={
  ['OnHitSolid']=function(context)if active and not impact_done then on_projectile_hit(context,'solid')end end,['On Trace Hit']=on_trace_hit,
  -- The game starts every projectile through these; catching the dart here
  -- means even a point-blank throw that ends within one frame is the hammer.
  ['Received_PostStart']=launch_hook,['Received_Deactivate']=deactivate_hook,
 }
 for name,handler in pairs(handlers)do
  local path=class..name
  if not hit_hooks[name] and handler and valid(StaticFindObject(path))then
   hit_hooks[name]=pcall(RegisterHook,path,function(context,...)
    local ok,err=pcall(handler,context,...)
    if not ok then D.write('throw',name..' hook failed: '..tostring(err))end
   end)
   if hit_hooks[name]then D.write('throw','projectile hook installed: '..name)end
  end
 end
end
-- A dart of Hun's in flight (status 2) not handed off yet, or nil.  The
-- launch event normally starts the flight; this scan covers a missed one
-- and notices when the dart has gone.
local function flying_dart(pawn)
 for _,actor in ipairs(FindAllOf('BP_Bullet_EMei_Dart_C')or {})do
  if valid(actor)and not id(actor):find('Default__',1,true)and not handed_off[id(actor)]then
   local ok,running=pcall(function()
    return num(actor:GetStatus())==2 and id(actor:GetOwnerAvatar())==id(pawn)
   end)
   if ok and running then return actor end
  end
 end
end
-- Drops a dart that is not the throw: never drawn, never tracked again.
local function drop_dart(key)
 handed_off[key]=true
 for _,c in ipairs(FindAllOf('SkeletalMeshComponent')or {})do
  local ok,o=pcall(function()return c:GetOwner()end)
  if ok and id(o)==key then pcall(function()c:SetVisibility(false,true)end);hidden_darts[key]=c end
 end
end
-- The hammer Hun holds, for its exact on-screen size.
local function held_mesh(pawn)
 for _,entry in pairs(hidden)do if valid(entry.mesh)then return entry.mesh end end
 for _,mesh in ipairs(FindAllOf('SkeletalMeshComponent')or {})do
  local name=valid(mesh)and id(mesh)or ''
  if name:find('BP_Weapon_Hun_Mjolnir_C_',1,true)and not name:find('Default__',1,true)and owned(mesh:GetOwner(),pawn)then return mesh end
 end
end
-- The thrown hammer is the same size as the one in the hand: the dart and the
-- weapon are scaled differently, so copy the held hammer's world scale.
local function match_size(component,pawn)
 local held=held_mesh(pawn);if not held then return false end
 return pcall(function()
  local s=held:K2_GetComponentScale()
  component:SetWorldScale3D({X=tonumber(s.X)or 1,Y=tonumber(s.Y)or 1,Z=tonumber(s.Z)or 1})
 end)
end
-- Darts are pooled and shared with the EMei enemies, so each styled dart
-- remembers its own mesh and size and gets them back when it is put away.
local function original_look(component)
 local asset
 for _,field in ipairs({'SkeletalMeshAsset','SkinnedAsset','SkeletalMesh'})do
  local ok,a=pcall(function()return component[field]end)
  if ok and valid(a)then asset=a;break end
 end
 local ok,s=pcall(function()return component:K2_GetComponentScale()end)
 return {component=component,asset=asset,scale=ok and s and {X=tonumber(s.X)or 1,Y=tonumber(s.Y)or 1,Z=tonumber(s.Z)or 1}or nil}
end
-- The dart's own flight effect (the EMei dart carries a gold dagger effect,
-- NS_MaskAssassin_Gold_Daggar_001, on its collision).  It flew on the dart's
-- path, not the hammer's, and was the "trail" that sat behind and above the
-- thrown hammer however Mjolnir's own trail was placed (effect survey,
-- 2026-11-07).  On Mjolnir's throws it is hidden; the dart is pooled with the
-- EMei enemies, so it is shown again at the dart's next launch.
local dart_fx={}   -- dart key -> the effect components hidden on it
local function each(list,fn)
 if type(list)=='table'and list[1]~=nil then for _,v in ipairs(list)do fn(v)end return end
 pcall(function()list:ForEach(function(_,e)local ok,v=pcall(function()return e:get()end);fn(ok and v or e)end)end)
end
local fx_said=false
local function hide_dart_fx(projectile)
 local cls=StaticFindObject('/Script/Niagara.NiagaraComponent')
 if not valid(cls)then return end
 local ok,list=pcall(function()return projectile:K2_GetComponentsByClass(cls)end)
 if not ok or not list then return end
 local key=id(projectile)
 each(list,function(c)
  if not valid(c)then return end
  local okv,vis=pcall(function()return c:IsVisible()end)
  if okv and vis then
   if pcall(function()c:SetVisibility(false,true)end)then
    dart_fx[key]=dart_fx[key]or {};table.insert(dart_fx[key],c)
    if not fx_said then
     fx_said=true
     local n='?';pcall(function()n=c.Asset:GetFullName():match('([%w_]+)$')end)
     D.write('throw','the dart\'s own flight effect ('..tostring(n)..') is hidden on the hammer throw')
    end
   end
  end
 end)
end
-- The way that finds it in game: K2_GetComponentsByClass on the dart returned
-- nothing in game (the effect is spawned onto the dart's collision, not listed
-- among its components), while a scan of every effect by owner finds it -- so
-- for the first frames of each throw the effects owned by the dart are hidden
-- that way, and the log says how many.
local DART_SCAN_FRAMES=8
local dart_scan,dart_scan_found=0,0
local function scan_dart_fx(projectile)
 local key=id(projectile)
 for _,c in ipairs(FindAllOf('NiagaraComponent')or {})do
  if valid(c)then
   local okO,o=pcall(function()return c:GetOwner()end)
   if okO and valid(o)and id(o)==key then
    local okv,vis=pcall(function()return c:IsVisible()end)
    if okv and vis and pcall(function()c:SetVisibility(false,true)end)then
     dart_fx[key]=dart_fx[key]or {};table.insert(dart_fx[key],c)
     dart_scan_found=dart_scan_found+1
     local n='?';pcall(function()n=c.Asset:GetFullName():match('([%w_]+)$')end)
     D.write('throw','hid the dart\'s own effect '..tostring(n)..' (by owner scan)')
    end
   end
  end
 end
end
local function show_dart_fx(key)
 local list=dart_fx[key];dart_fx[key]=nil
 for _,c in ipairs(list or {})do if valid(c)then pcall(function()c:SetVisibility(true,true)end)end end
end
-- (Not shown again when the dart is put away -- that is the moment the hammer hits, and it would flash
-- there -- but at the dart's next launch, whoever launches it.)
local function unstyle(projectile)
 local key=id(projectile);local look=styled_projectiles[key]
 if not look then return end
 styled_projectiles[key]=nil
 if type(look)~='table'or not valid(look.component)then return end
 if look.asset then pcall(function()look.component:SetSkeletalMeshAsset(look.asset)end)end
 if look.scale then pcall(function()look.component:SetWorldScale3D(look.scale)end)end
end
local function style_base_projectile(projectile,pawn)
 local key=id(projectile)
 if key=='' or styled_projectiles[key]then return end
 local hammer=StaticFindObject('/Game/Mods/MjolnirHammer/SK_Mjolnir.SK_Mjolnir')
 if not valid(hammer)then D.write('throw','hammer mesh unavailable; preserving native projectile mesh');return end
 for _,component in ipairs(FindAllOf('SkeletalMeshComponent')or {})do
  local ok,component_owner=pcall(function()return component:GetOwner()end)
  if ok and id(component_owner)==key then
   local look=original_look(component)
   local assigned=pcall(function()component:SetSkeletalMeshAsset(hammer)end)
   if not assigned then assigned=pcall(function()component:SetSkeletalMesh(hammer,true)end)end
   if assigned then
    styled_projectiles[key]=look
    local sized=match_size(component,pawn)
    D.write('throw','base EMei Dart projectile styled with Mjolnir mesh'..(sized and '; sized to the held hammer'or'; held hammer size unavailable'))
   else D.write('throw','base projectile mesh swap failed; preserving native mesh')end
   return
  end
 end
 D.write('throw','base projectile has no skeletal mesh component yet')
end
local function begin_fake_recall(pawn,origin,now,reason)
 if fake_recall_until or Return.active()then return end
 last_position=origin or last_position
 -- Fly a hammer home from where the dart ended; the held one stays hidden
 -- until the catch and only lends its size.
 local ok,flying,detail=pcall(Return.begin,pawn,held_mesh(pawn),last_position,now)
 if ok and flying then
  hold_gate(pawn)
  pcall(Trail.start,pawn,Return.flyer())
  pcall(Feedback.recall,pawn,last_position,detail)
  D.write('throw',string.format('hammer flying home (%s); %.2f s',reason,detail))
  return
 end
 fake_recall_until=now+.08
 pcall(Feedback.recall,pawn,last_position)
 D.write('throw','return flight unavailable ('..tostring(ok and detail or flying)..'); quiet hand-snap recall started ('..reason..')')
end
local function hide_hand(pawn)
 if next(hidden)then
  for _,entry in pairs(hidden)do if valid(entry.mesh)then entry.mesh:SetVisibility(false,true)end end
  return
 end
 for _,mesh in ipairs(FindAllOf('SkeletalMeshComponent')or {})do
  if valid(mesh)then
   local name=id(mesh)
   if name:find('BP_Weapon_Hun_Mjolnir_C_',1,true)and not name:find('Default__',1,true)and owned(mesh:GetOwner(),pawn)then
    if not hidden[name]then hidden[name]={mesh=mesh,visible=mesh:IsVisible()}end
    mesh:SetVisibility(false,true)
   end
  end
 end
end
-- Where the dart's hammer is drawn right now, and its mesh component.
local function dart_pose(projectile)
 local look=styled_projectiles[id(projectile)]
 local comp=type(look)=='table'and look.component or nil
 local p,r
 if valid(comp)then
  pcall(function()local l=comp:K2_GetComponentLocation();p={X=tonumber(l.X)or 0,Y=tonumber(l.Y)or 0,Z=tonumber(l.Z)or 0}end)
  pcall(function()local q=comp:K2_GetComponentRotation();r={Pitch=tonumber(q.Pitch)or 0,Yaw=tonumber(q.Yaw)or 0,Roll=tonumber(q.Roll)or 0}end)
 end
 if not plausible(p)then p=nil end
 return p or location(projectile),r,comp
end
-- One hammer, not two: in the same frame, the flyer appears exactly where
-- and how the dart's hammer is, and the dart's hammer is hidden.
hand_off=function(projectile,pawn,reason)
 local key=id(projectile)
 if handed_off[key]or Return.active()or fake_recall_until then return end
 handed_off[key]=true
 local p,r,comp=dart_pose(projectile)
 if p then last_position=p end
 local now=H.GetGameplayStatics():GetTimeSeconds(pawn)
 local ok,flying,detail=pcall(Return.begin,pawn,held_mesh(pawn),last_position,now,r,reason=='hit'and WEDGE or 0)
 if not(ok and flying)then
  D.write('throw','handoff unavailable ('..tostring(ok and detail or flying)..'); the end-of-flight recall will take over')
  handed_off[key]=nil
  return
 end
 if valid(comp)then pcall(function()comp:SetVisibility(false,true)end);hidden_darts[key]=comp end
 hold_gate(pawn)
 pcall(Trail.start,pawn,Return.flyer())   -- (already on if the hammer was carried out)
 pcall(Feedback.recall,pawn,last_position,detail)
 D.write('throw',string.format('hammer flying home (%s, same-frame handoff); %.2f s',reason,detail))
end
-- The moment the game starts a dart.  Any dart this script hid is shown
-- again (the pool is shared with the EMei enemies).  If it is Hun's: make
-- it the hammer, empty the hand and start the flight, in the same frame.
launch_hook=function(context)
 local okp,any=pcall(function()return context:get()end)
 if not okp or not valid(any)then return end
 -- Only darts concern the hammer; every other bullet leaves at once.
 local key=id(any)
 if not key:find('BP_Bullet_EMei_Dart_C_',1,true)then return end
 do
  handed_off[key]=nil
  show_dart_fx(key)   -- a pooled dart gets its own effect back at every launch
  if stilled[key]then stilled[key]=nil;pcall(function()any:SetActorEnableCollision(true)end)end
  if hidden_darts[key]then local c=hidden_darts[key];hidden_darts[key]=nil;if valid(c)then pcall(function()c:SetVisibility(true,true)end)end end
 end
 local projectile,pawn=own_dart(context);if not projectile then return end
 launch_seen=true
 if Return.active()or fake_recall_until or(active and flight_key and flight_key~=key)then
  -- A throw got through while the hammer is still out (on its way, or on
  -- its way home).  There is one hammer: this dart gets no hammer and is not
  -- drawn, and nothing picks it up later.  Says so, with what the gate read.
  drop_dart(key)
  D.write('throw','a throw got through while the hammer was coming back (gate read '..tostring(gate_held(pawn))..', ours x'..gate_count..' via '..tostring(gate_route)..'); that dart is hidden')
  return
 end
 style_base_projectile(projectile,pawn)
 pcall(hide_dart_fx,projectile)
 if quarantined then return end
 if id(pawn)~=owner_id then owner=pawn;owner_id=id(pawn)end
 last_position=location(projectile)or last_position
 local carried=false
 if not active then
  active=true;began=H.GetGameplayStatics():GetTimeSeconds(pawn);impact_done=false;missing_since=nil
  -- This dart is the throw: only its contacts count, and no other throw
  -- starts until the catch -- from the moment the hammer leaves the hand
  -- (a throw made while the first dart was still flying out set off strays).
  flight_key=key
  hold_gate(pawn,'throw')
  watch_recall(projectile,began)
  dart_scan,dart_scan_found=DART_SCAN_FRAMES,0
  -- Lighter gravity on every throw.  The game solves a targeted throw's arc
  -- for the dart's heavy gravity (lightened, one flew 324 m over its target),
  -- so a throw the game aims homes onto that enemy (throw_homing).
  light_dart,light_said=projectile,false;pcall(lighten_dart,projectile)
  if not Aim.aimed()then pcall(Homing.start,projectile,pawn,began)else Homing.stop()end
  -- Camera-aimed: point it where the camera looks, up and down included.
  if Aim.aimed()then aim_dart,aim_until,aim_said=projectile,began+AIM_HOLD,false;pcall(point_dart,projectile)end
  -- How far the dart's hammer starts from the one that just left the hand.
  local gap='?'
  local held=held_mesh(pawn);local start=dart_pose(projectile)
  if valid(held)then
   pcall(function()
    local head=held:GetSocketLocation(FName(Trail.SOCKET))
    if plausible(head)then pending_release={X=head.X,Y=head.Y,Z=head.Z}end
   end)
  end
  if valid(held)and start then pcall(function()local h=held:K2_GetComponentLocation();gap=string.format('%.0f',math.sqrt((start.X-h.X)^2+(start.Y-h.Y)^2+(start.Z-h.Z)^2))end)end
  -- No jump at the throw: the flyer leaves from the held hammer and closes
  -- onto the dart, whose own hammer is hidden until then.
  local look=styled_projectiles[id(projectile)]
  local bridged=type(look)=='table'and valid(look.component)and Return.bridge(pawn,held,look.component,began)
  if bridged then hidden_darts[id(projectile)]=look.component;carried=true;pcall(Trail.start,pawn,Return.flyer())end
  D.write('throw','native flight started (launch event); dart starts '..gap..' cm from the held hammer'..(bridged and'; hammer carried from the hand'or'; not carried'))
  play_release(pawn,projectile)
 end
 -- One hammer: the flyer is drawn on the held hammer this frame, and the
 -- held one goes next frame (an overlap cannot be seen, a gap can).
 if carried then hide_next=true else hide_hand(pawn)end
end
-- A dart that ends without hitting anything hands its hammer over now; then
-- it goes back to the pool with its own mesh and size.
deactivate_hook=function(context)
 if next(styled_projectiles)==nil then return end   -- no hammer dart out: not ours
 local ok,projectile=pcall(function()return context:get()end)
 if not ok or not valid(projectile)then return end
 if active and styled_projectiles[id(projectile)]and valid(owner)and(not flight_key or id(projectile)==flight_key)then hand_off(projectile,owner,'end of flight')end
 unstyle(projectile)
end
-- Called back early: the hammer turns home from where it is (the same flight
-- home as after a hit), and the dart it leaves behind stops flying and can no
-- longer hit anything.
local function recall_early(pawn,now)
 local d=flight_dart
 if not valid(d)then flight_dart=nil;return end
 hand_off(d,pawn,'recall')
 if not Return.active()then D.write('throw','early recall: the hammer could not turn back');return end
 stilled[id(d)]=d
 pcall(function()d:SetActorEnableCollision(false)end)
 pcall(function()local mv=d.SGameProjectileMovement;if valid(mv)then mv:StopMovementImmediately()end end)
 Homing.stop()
 D.write('throw',string.format('early recall after %.2f s of flight',now-began))
end
local function update()
 -- The frame after a catch: the flyer that stayed on the held hammer goes.
 Return.flush()
 local pc=H.GetPlayerController();local pawn=valid(pc)and pc.Pawn or nil
 if hide_next then hide_next=false;if valid(pawn)and(Return.bridging()or Return.active())then hide_hand(pawn)end end
 if not valid(pawn)then
  Glow.reset()
  restore();owner=nil;owner_id=nil;last_scan=-1;fake_recall_until=nil;last_position=nil;return
 end
 local now=H.GetGameplayStatics():GetTimeSeconds(pawn)
 if id(pawn)~=owner_id then
  restore();owner=pawn;owner_id=id(pawn);last_scan=-1;quarantined=false;fake_recall_until=nil;last_position=nil
 end
 local ok_glow,glow_error=pcall(Glow.update,pawn,now,active,Return.flyer(),held_mesh)
 if not ok_glow then D.state('rune glow',tostring(glow_error))end
 pcall(Arm.tick_catch)
 pcall(Trail.update_pulse,now)
 -- A point-blank impact takes priority if both events land in the same frame.
 if pending_impact then
  local position=pending_impact
  pending_impact=nil
  pcall(Trail.impact,pawn,position,now)
 elseif pending_release then
  pcall(Trail.release,pawn,pending_release,now)
 end
 pending_release=nil
 -- A throw starting with nothing targeted goes where the camera looks.
 pcall(Aim.update,pawn,now,active or Return.active()or Return.bridging())
 if aim_dart then
  if active and not Return.active()and now<=aim_until and valid(aim_dart)then pcall(point_dart,aim_dart)
  else aim_dart=nil end
 end
 if light_dart then
  if active and not Return.active()and valid(light_dart)then pcall(lighten_dart,light_dart)
  else light_dart=nil end
 end
 pcall(Homing.update,now,active and not Return.active())
 pcall(Recall.update,now)
 if active and not Return.active()and flight_dart then
  local okd,down=pcall(Recall.down,pc);down=okd and down==true
  if not down then recall_armed=true
  elseif recall_armed and not recall_was then recall_req=true end
  recall_was=down
  -- (The hammer is "carried" -- drawn by the flyer -- for its whole flight
  -- out; the handoff picks it up from there, as at the end of any flight.)
  if recall_req and now-began>=RECALL_MIN then recall_req=false;recall_early(pawn,now)end
 elseif flight_dart and Return.active()then flight_dart=nil end
 -- The carried flight out and the return move every frame; scanning stays
 -- throttled.
 if Return.bridging()then
  Return.tick(now);pcall(Trail.follow,now)
  -- (the dart may start its effect after its launch event: keep it hidden while it flies out)
  if valid(flight_dart)then
   pcall(hide_dart_fx,flight_dart)
   if dart_scan>0 then
    dart_scan=dart_scan-1
    pcall(scan_dart_fx,flight_dart)
    if dart_scan==0 and dart_scan_found==0 then D.write('throw','no effect owned by the dart was found to hide this throw')end
   end
  end
 end
 if Return.bridging()or Return.active()then
  local phase=Return.phase()
  local presence=1
  if Return.active()and(phase=='hitstop'or phase=='bounce')then presence=0;fly_resume=false
  elseif fly_resume~=nil then
   if fly_resume==false then fly_resume=now end
   presence=math.min(1,(now-fly_resume)/RESUME)
  end
  pcall(Feedback.follow,pawn,Return.position(),now,presence)
 else fly_resume=nil end
 if Return.active()then
  -- The throw stays blocked until the catch, every frame: the game lets its
  -- own gate go a moment after the dart ends (after our handoff ran), and
  -- a throw in that gap put a second hammer in the air.
  hold_gate(pawn)
  local state,caught=Return.tick(now)
  if state=='flying'then
   local phase=Return.phase()
   if not recall_cue_sent and (phase=='home'or phase=='align')then
    recall_cue_sent=true
    pcall(Feedback.recall_pull,pawn)
    pcall(Trail.recall,pawn,Return.flyer(),now)
   end
   local ok,message=pcall(Arm.update,pawn,phase)
   if ok and message then D.write('throw',message)end
   if not ok then D.state('recall reach',tostring(message))end
   pcall(Trail.follow,now)
   return
  end
  if restore(caught)then
   if caught then pcall(function()Trail.catch(pawn,held_mesh(pawn),now)end)end
   pcall(Feedback.catch,pawn)
   D.write('throw','hammer caught; hand and input restored; '..Return.describe())
  end
  return
 end
 if last_scan>=0 and now>=last_scan and now-last_scan<.08 then return end
 last_scan=now
 install_hit_hooks()
 local projectile=flying_dart(pawn)
 if projectile and((active and flight_key and id(projectile)~=flight_key)or(not active and launch_seen))then
  -- A dart of Hun's that is not this throw: a stray (one still flying from
  -- an earlier throw).  Adopting one as a "throw" hid the hand after the
  -- catch and made the next throw "hit" at the hand.
  drop_dart(id(projectile))
  D.write('throw','a stray dart of an earlier throw is ignored (hidden)')
  projectile=nil
 end
 if projectile then
  last_position=location(projectile)or last_position
  style_base_projectile(projectile,pawn)
  if fake_recall_until then
   if now>=fake_recall_until and restore()then
    fake_recall_until=nil;pcall(Feedback.catch,pawn);D.write('throw','cosmetic recall catch; hand and input restored')
   else hide_hand(pawn)end
   return
  end
  if quarantined then return end
   if not active then active=true;began=now;impact_done=false;watch_recall(projectile,began);D.write('throw','native flight started');play_release(pawn,projectile)end
  missing_since=nil
  if now-began>6 then
   pcall(function()projectile:K2_DestroyActor()end);quarantined=true
   begin_fake_recall(pawn,last_position,now,'outbound watchdog');return
  end
  hide_hand(pawn)
 else
  quarantined=false
  if fake_recall_until then
   if now>=fake_recall_until and restore()then
    fake_recall_until=nil;pcall(Feedback.catch,pawn);D.write('throw','cosmetic recall catch; hand and input restored')
   end
   return
  end
  if not active then return end
  missing_since=missing_since or now
  if now-missing_since>=.16 then
   -- The generic projectile has retired from a hit, wall, or expiry.  The
   -- cosmetic recall hides that boundary and restores the hand safely.
   begin_fake_recall(pawn,last_position,now,'projectile retirement')
  end
 end
end
function T.start()
 if started then return end;started=true
 -- Every rendered frame: the hammer in the air moves with the picture.
 require('game_thread_pump').frame('throw_hand_state',update)
 D.write('throw','throw controller started')
end
return T

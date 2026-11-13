-- The hammer's sounds, played through the game's own Wwise sound engine.
-- Each cue is a Wwise event cooked into zz_MjolnirWwise_P (Mjolnir's 61 takes
-- in 13 events; Wwise picks a random take per play).  lead = seconds until the
-- moment the sound should peak: the event is posted that long minus the cue's
-- own peak time from now.  No DLL, no files written.
local H=require('UEHelpers')
local D=require('runtime_diagnostics')
local Pump=require('game_thread_pump')
local F={}
local BASE='/Game/Mods/MjolnirHammer/Wwise/Events/Default_Work_Unit/'
local EVENT={whoosh='Play_Mjolnir_Whoosh',heavy='Play_Mjolnir_Heavy',finisher='Play_Mjolnir_Finisher',
 impact='Play_Mjolnir_Impact',heavy_impact='Play_Mjolnir_HeavyImpact',finisher_impact='Play_Mjolnir_FinisherImpact',
 impact_charged='Play_Mjolnir_ImpactCharged',windup='Play_Mjolnir_Windup',throw='Play_Mjolnir_Throw',
 throw_impact='Play_Mjolnir_ThrowImpact',recall_pull='Play_Mjolnir_RecallPull',catch='Play_Mjolnir_Catch',
 fly='Play_Mjolnir_Fly',fly_stop='Stop_Mjolnir_Fly'}
-- Seconds from a take's start to its loudest moment (median over each group's takes).
local PEAK={whoosh=.200,heavy=.225,finisher=.225,throw=.113}
F.EVENT,F.PEAK=EVENT,PEAK
F.FLY_LEVEL=.5   -- the flight loop sits 6 dB under the hits (set in the Wwise project)

local function valid(o)return o and o.IsValid and o:IsValid()end
-- Events are looked up by path on every use (never through a kept pointer), and
-- loaded up front by F.preload() when the player spawns: loading one in combat
-- stalled the game (2026-11-12).  The weapon config's hard references keep them.
local preloaded=false
local function load_asset(package,name,what)
 local path=package..'.'..name
 local e=StaticFindObject(path);if valid(e)then return e end
 if preloaded then D.write('audio',what..' '..name..' was not loaded (unloaded by the game?); loading it now')end
 local reg=StaticFindObject('/Script/AssetRegistry.Default__AssetRegistryHelpers')
 if valid(reg)then local ok,a=pcall(function()return reg:GetAsset({PackageName=FName(package),AssetName=FName(name)})end);if ok and valid(a)then return a end end
 if LoadAsset then local ok,a=pcall(LoadAsset,path);if ok and valid(a)then return a end end
 D.state('audio.'..name,what..' missing: '..name..' (is zz_MjolnirWwise_P installed?)');return nil
end
local function event(name)return load_asset(BASE..name,name,'sound event')end
local api_obj
local function api()
 if not valid(api_obj)then api_obj=StaticFindObject('/Script/AkAudio.Default__AkGameplayStatics')end
 return valid(api_obj)and api_obj or nil
end
-- Post a cue's event on an actor now; returns the playing id (0 = failed).
-- Mjolnir's own Wwise component on the player (socket name MjolnirFly): the
-- flight loop plays here and is faded with this component's volume, which
-- touches no other sound (the game's own sounds use the root component).
local function own_component(actor)
 local a=api();if not(a and valid(actor))then return nil end
 local ok,c=pcall(function()return a:GetAkComponent(actor.RootComponent,{},FName('MjolnirFly'),{X=0,Y=0,Z=0},0)end)
 if ok and valid(c)then return c end
 D.state('audio.comp','could not get Mjolnir\'s Wwise component: '..tostring(c));return nil
end
F.own_component=own_component
F.last_at=nil   -- the hammer's last tracked position (for the impact)
local function post(cue,actor)
 if not valid(actor)then return 0 end
 local a,e=api(),event(EVENT[cue]);if not(a and e)then return 0 end
 local ok,id,how
 if cue=='fly'or cue=='fly_stop'then
  local c=own_component(actor)
  if c then how='own component';ok,id=pcall(function()return c:PostAkEvent(e,0,nil)end)end
 elseif cue=='throw_impact'and F.last_at then
  local at=F.last_at;how=string.format('at the hit (%.0f, %.0f, %.0f)',at.X,at.Y,at.Z)
  ok,id=pcall(function()return a:PostEventAtLocation(e,{X=at.X,Y=at.Y,Z=at.Z},{Pitch=0,Yaw=0,Roll=0},actor)end)
 end
 if not how then how='player';ok,id=pcall(function()return a:PostEvent(e,actor,0,nil,true)end)end
 if not ok then D.write('audio','sound '..EVENT[cue]..' ('..how..') failed: '..tostring(id));return 0 end
 local pid=tonumber(tostring(id))or 0
 -- Proof in the log: the first play of each sound, and every failed one.
 if pid==0 then D.write('audio','sound '..EVENT[cue]..' ('..how..'): Wwise did NOT play it (playing id 0)')
 elseif not F.heard[cue]then F.heard[cue]=pid;D.write('audio','sound '..EVENT[cue]..': playing (id '..pid..', '..how..')')end
 if cue=='fly'and F.on_fly_id then F.on_fly_id(pid)end
 if cue=='throw_impact'then D.write('audio','throw impact: playing id '..pid..' '..how)end
 return pid
end
F.post=post
F.heard={}
-- Timed cues wait on the mod's single game-thread timer (never ExecuteWithDelay:
-- its callbacks run off the game thread and crashed UE4SS's Lua on 2026-11-12).
F.clock=os.clock
local waiting={};local pumping=false
local function tick()
 if #waiting==0 then return end
 local t=F.clock();local keep={}
 for _,w in ipairs(waiting)do if t>=w.at then post(w.cue,w.actor)else keep[#keep+1]=w end end
 waiting=keep
end
F.tick=tick
-- Post so the cue peaks `lead` seconds from now.
local function play(cue,actor,lead)
 if not valid(actor)then return end
 local delay=lead and math.max(0,lead-(PEAK[cue]or 0))or 0
 if delay<.01 then post(cue,actor);return end
 if not pumping then pumping=true;Pump.add('audio_timing',tick)end
 waiting[#waiting+1]={at=F.clock()+delay,cue=cue,actor=actor}
end

local function now(player)
 local ok,t=pcall(function()return H.GetGameplayStatics():GetTimeSeconds(player)end)
 return ok and tonumber(t)or 0
end

-- A swing's air pass; lead = seconds until its strike.
function F.melee_start(player,phase,finisher,weapon_switch,lead)
 local name='whoosh'
 if not weapon_switch then
  if finisher then name='finisher'elseif phase==3 then name='heavy'end
 end
 play(name,player,lead)
end
-- The strike itself.
function F.melee_impact(player,phase,finisher,weapon_switch,charged)
 local name='impact'
 if not weapon_switch then
  if finisher then name='finisher_impact'
  elseif phase==3 then name='heavy_impact'
  elseif charged then name='impact_charged'end
 end
 play(name,player)
end

-- The flight loop's distance fade: the volume of Mjolnir's own component
-- (linear gain; 1 = full).  The throw impact needs none: it plays at the hit,
-- and its Wwise attenuation fades it with distance.
local function set_fly_db(db,actor)
 db=math.max(0,math.min(96,db))
 local c=own_component(actor);if not c then return end
 local gain=db>=96 and 0 or 10^(-db/20)
 local ok,err=pcall(function()c:SetOutputBusVolume(gain)end)
 if not ok then D.state('audio.fade','fade failed: '..tostring(err))end
 F.fly_gain=gain
end
F.set_fly_db=set_fly_db
-- Load every Mjolnir sound now (call at spawn, not in combat).  Mjolnir's weapon
-- config also holds them (its Sounds map), so the engine keeps them loaded.
function F.preload()
 local function clock()local ok,v=pcall(os.clock);return tonumber(ok and v)or 0 end
 local t0=clock();local n,missing=0,{}
 local seen={};local found={}
 for _,name in pairs(EVENT)do if not seen[name]then seen[name]=true
  if event(name)then n=n+1;found[#found+1]=name:gsub('_Mjolnir_','')else missing[#missing+1]=name end end end
 preloaded=true
 D.write('audio',string.format('preloaded %d sound events in %.0f ms%s',n,(clock()-t0)*1000,
  #missing>0 and(' - MISSING: '..table.concat(missing,', '))or''))
 table.sort(found);D.write('audio','in memory: '..table.concat(found,', '))
 return n,missing
end

-- The hammer in the air: one Wwise loop from release through recall until the
-- catch, played from the player and faded by Mjolnir_Fly_Level (no spawned
-- emitter: a game crash on 2026-11-12 came while one was in use).
local fly={on=false,owner=nil,far=0,worst=0,id=0}
F.on_fly_id=function(pid)fly.id=pid;if pid==0 then D.write('audio','flight loop: Wwise did NOT play it (playing id 0)')end end
local function fly_start(player,lead)
 if fly.on then return end
 fly.on,fly.owner=true,player;fly.far,fly.worst,fly.id,fly.checked=0,0,0,false
 set_fly_db(0,player)
 play('fly',player,lead)
end
local function fly_stop(player)
 if not fly.on then return end
 fly.on=false
 -- drop a flight start still waiting on its lead, then stop the loop
 local keep={};for _,w in ipairs(waiting)do if w.cue~='fly' then keep[#keep+1]=w end end;waiting=keep
 post('fly_stop',valid(fly.owner)and fly.owner or player)
 D.write('audio',string.format('flight sound: playing id %s, farthest %.0f m, most faded -%.1f dB',tostring(fly.id),(fly.far or 0)/100,fly.worst or 0))
 fly.owner=nil
end

local last_timed_throw=-100
function F.throw_windup(player)play('windup',player)end
function F.throw(player,lead)
 if not valid(player)then return end
 local t=now(player)
 if lead then last_timed_throw=t
 elseif t-last_timed_throw<.8 then return end
 play('throw',player,lead)   -- the throw itself
 fly_start(player,lead)      -- and the flight loop under it
end
function F.throw_impact(player)play('throw_impact',player)end

-- The pan and level for a hammer at `at`, heard from camera `cam` looking
-- along `rot` (pure maths, tested offline); the level drives the fades.
local NEAR,FAR=900,6000
local DOPPLER,DOPPLER_V=.03,4000
function F.placement(at,cam,rot,previous_d,dt)
 local dx,dy,dz=at.X-cam.X,at.Y-cam.Y,at.Z-cam.Z
 local d=math.sqrt(dx*dx+dy*dy+dz*dz)
 local yaw=math.rad(tonumber(rot.Yaw)or 0)
 local pan=d>1 and(-math.sin(yaw)*dx+math.cos(yaw)*dy)/d or 0
 local x=math.max(0,math.min(1,(d-NEAR)/(FAR-NEAR)))
 local level=(1-x)*(1-x)
 local pitch=1
 if previous_d and dt and dt>0 then
  local closing=(previous_d-d)/dt
  pitch=1+DOPPLER*math.max(-1,math.min(1,closing/DOPPLER_V))
 end
 return pan,level,pitch,d
end
local FOLLOW_EVERY=.05
local follow={t=-1}
local function camera()
 local pc=H.GetPlayerController()
 local cm=pc and pc.PlayerCameraManager
 if not valid(cm)then return nil end
 local okl,l=pcall(function()return cm:GetCameraLocation()end)
 local okr,r=pcall(function()return cm:GetCameraRotation()end)
 if not okl or not okr or not l or not r then return nil end
 return l,r
end
-- Distance fade, in dB: full within FADE_NEAR, then down linearly (in dB) to a
-- floor at FADE_FAR; never silent (the first curve went silent at 60 m and
-- long throws fly 40-130 m).  The Wwise curve maps 0-100 % to 20*log10 dB.
F.FADE_NEAR,F.FADE_FAR=1500,10000      -- cm
F.FLY_FLOOR_DB,F.HIT_FLOOR_DB=-20,-12
local function fade_db(d,floor_db)   -- attenuation in dB (positive), 0 near
 local x=math.max(0,math.min(1,(d-F.FADE_NEAR)/(F.FADE_FAR-F.FADE_NEAR)))
 return -x*floor_db
end
F.fade_db=fade_db
function F.follow(player,at,t,presence)
 if not at or not valid(player)or t-follow.t<FOLLOW_EVERY then return end
 follow.t=t
 local cam=camera();if not cam then return end
 local dx,dy,dz=at.X-cam.X,at.Y-cam.Y,at.Z-cam.Z
 local d=math.sqrt(dx*dx+dy*dy+dz*dz)
 local fly_db=fade_db(d,F.FLY_FLOOR_DB)
 local pres=math.max(0,math.min(1,presence or 1))
 if pres<1 then fly_db=pres<=0 and 96 or math.min(96,fly_db-20*math.log(pres,10))end
 F.last_at={X=at.X,Y=at.Y,Z=at.Z}
 set_fly_db(fly_db,player)
 if fly.on then fly.far=math.max(fly.far or 0,d);if pres>=1 then fly.worst=math.max(fly.worst or 0,fly_db)end
  if fly_db>=10 and not fly.checked then fly.checked=true;D.write('audio',string.format('mid-flight: flight loop at -%.1f dB (component volume %.3f)',fly_db,F.fly_gain or -1))end end
end
function F.follow_reset()follow.t=-1 end
-- Keep the flight loop running under the snap, starting it if needed.
function F.recall(player)fly_start(player)end
function F.recall_pull(player)play('recall_pull',player)end
function F.stop_flight(player)fly_stop(player)end
function F.catch(player)
 if not valid(player)then return end
 fly_stop(player);play('catch',player)
end
return F

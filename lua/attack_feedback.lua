-- The hammer's sounds.  Each cue is a small file dropped in the approved
-- audio player's queue (MjolnirApprovedAudio, an in-process XAudio2 player
-- that picks a take from that cue's bank).  A cue line is "<cue>" or
-- "<cue> <lead>", lead = seconds until the moment the sound should peak.
local H=require('UEHelpers')
local D=require('runtime_diagnostics')
local F={}
-- Queue folder sits beside this mod: Mods/MjolnirApprovedAudio/queue/, found
-- from this script's own path so the install works from any game folder.
local QUEUE=(function()
 local ok,info=pcall(function()return debug.getinfo(1,'S')end)
 local src=((ok and info and info.source)or ''):gsub('^@','')
 local mods=src:match('^(.*[/\\])MjolnirMod[/\\][Ss]cripts[/\\]')
 return (mods or 'ue4ss/Mods/')..'MjolnirApprovedAudio/queue/'
end)()
local sequence=0

local function valid(o)return o and o.IsValid and o:IsValid()end
local function now(player)
 local ok,t=pcall(function()return H.GetGameplayStatics():GetTimeSeconds(player)end)
 return ok and tonumber(t)or 0
end
-- Written as .tmp and renamed, so the player never reads half a cue.
local function cue(player,line)
 if not valid(player)then return false end
 sequence=sequence+1
 local path=QUEUE..string.format('%010d_%08d',os.time(),sequence)
 local file,err=io.open(path..'.tmp','wb')
 if not file then D.state('audio','could not open the audio queue: '..tostring(err));return false end
 local wrote=file:write(line..'\n');local closed=file:close()
 if wrote and closed and os.rename(path..'.tmp',path..'.cue')then return true end
 os.remove(path..'.tmp')
 D.state('audio','could not publish audio cue: '..line)
 return false
end
local function timed(name,lead)return lead and string.format('%s %.3f',name,lead)or name end

-- A swing's air pass; lead = seconds until its strike.
function F.melee_start(player,phase,finisher,weapon_switch,lead)
 local name='whoosh'
 if not weapon_switch then
  if finisher then name='finisher'elseif phase==3 then name='heavy'end
 end
 cue(player,timed(name,lead))
end
-- The strike, at the animation's contact frame.  charged: a later blow in a
-- chain, which carries more of the storm.
function F.melee_impact(player,phase,finisher,weapon_switch,charged)
 local name='impact'
 if not weapon_switch then
  if finisher then name='finisher_impact'
  elseif phase==3 then name='heavy_impact'
  elseif charged then name='impact_charged'end
 end
 cue(player,name)
end
-- The hammer in the air: a loop from release through recall until the catch.
-- lead: seconds until the hammer leaves the hand
-- (from the throw montage), so the first pass peaks at the release.  The
-- flight helper also calls this, without a lead, when the dart starts; that
-- is only a fallback for a throw the montage watcher missed.  The player
-- ignores "fly" while the loop is already going.
local last_timed_throw=-100
function F.throw_windup(player)cue(player,'windup')end
-- The flight loop's level against the rest of the hammer: it is a sustained loop over the throw and
-- the recall while every other hammer sound is a short hit, so at full level it stood out above the
-- moveset.  -6 dB (x0.5) on the loop only; the throw's own release take is untouched.
F.FLY_LEVEL=.5
function F.throw(player,lead)
 local t=now(player)
 if lead then last_timed_throw=t
 elseif t-last_timed_throw<.8 then return end
 F.follow_reset()
 cue(player,string.format('fly_pos 0.000 %.3f 1.0000',F.FLY_LEVEL))   -- it leaves from the hand: centred
 cue(player,timed('throw',lead))            -- the throw itself (a take from the throw bank)
 cue(player,timed('fly',lead))              -- and the flight loop under it
end
function F.throw_impact(player)cue(player,'throw_impact')end
-- The flight loop follows the hammer: where it is against the camera (panned
-- left/right), how far (full up close, fading out, silent when far), and a
-- slight doppler as it comes in or goes away.  Sent ~20 times a second.
local NEAR,FAR=900,6000       -- cm: full volume within NEAR, silent from FAR
local DOPPLER,DOPPLER_V=.03,4000   -- up to 3% pitch, reached at 40 m/s toward or away
local FOLLOW_EVERY=.05
local follow={t=-1,d=nil}
local function camera(player)
 local pc=H.GetPlayerController()
 local cm=pc and pc.PlayerCameraManager
 if not(cm and cm.IsValid and cm:IsValid())then return nil end
 local okl,l=pcall(function()return cm:GetCameraLocation()end)
 local okr,r=pcall(function()return cm:GetCameraRotation()end)
 if not okl or not okr or not l or not r then return nil end
 return l,r
end
-- The pan, level and pitch for a hammer at `at`, heard from camera `cam`
-- looking along `rot` (pure maths: tested offline).
function F.placement(at,cam,rot,previous_d,dt)
 local dx,dy,dz=at.X-cam.X,at.Y-cam.Y,at.Z-cam.Z
 local d=math.sqrt(dx*dx+dy*dy+dz*dz)
 local yaw=math.rad(tonumber(rot.Yaw)or 0)
 -- The camera's right (UE: X forward, Y right).
 local pan=d>1 and(-math.sin(yaw)*dx+math.cos(yaw)*dy)/d or 0
 local x=math.max(0,math.min(1,(d-NEAR)/(FAR-NEAR)))
 local level=(1-x)*(1-x)
 local pitch=1
 if previous_d and dt and dt>0 then
  local closing=(previous_d-d)/dt   -- cm/s toward the camera
  pitch=1+DOPPLER*math.max(-1,math.min(1,closing/DOPPLER_V))
 end
 return pan,level,pitch,d
end
function F.follow(player,at,now,presence)
 if not at or now-follow.t<FOLLOW_EVERY then return end
 local cam,rot=camera(player);if not cam then return end
 local pan,level,pitch,d=F.placement(at,cam,rot,follow.d,follow.t>=0 and now-follow.t or nil)
 follow.t,follow.d=now,d
 level=level*math.max(0,math.min(1,presence or 1))*F.FLY_LEVEL
 cue(player,string.format('fly_pos %.3f %.3f %.4f',pan,level,pitch))
end
function F.follow_reset()follow.t,follow.d=-1,nil end
-- Keep the flight loop running under the snap, starting it if needed.
function F.recall(player)cue(player,'fly')end
function F.recall_pull(player)cue(player,'recall_pull')end
-- The loop stops when the flight ends some other way (safe to repeat).
function F.stop_flight(player)cue(player,'fly_stop')end
-- The loop fades and a soft, closed thunk settles the hammer into the hand.
function F.catch(player)cue(player,'fly_stop');cue(player,'catch')end
return F

-- Read-only native attack observation. Damage, buffering and movement stay in the game.
local H=require('UEHelpers');local D=require('runtime_diagnostics');local Feedback=require('attack_feedback');local C={};local started=false
local Trail=require('throw_trail')
local Glow=require('rune_glow')
local previous;local position;local began;local player_id
local beats, beat_index, swing_sent, first_swing, weapon_switch, chain_hit
local hit_limit=5
local function valid(o)return o and o:IsValid()end
local function attack(name)
 if not name:find('AM_Mjolnir_',1,true)then return end
 -- Throw/retrieval and non-attacking presentation montages stay out of this
 -- system. Draw, switch and sprint montages remain because their abilities
 -- contain native damage frames.
 if name:find('Throw',1,true)or name:find('Recall',1,true)or name:find('Catch',1,true)
  or name:find('BeamPose',1,true)or name:find('Executed',1,true)then return end
 local chain=name:match('AM_Mjolnir_Light(A*)')
 if chain then
  local hit=#chain
  if hit<1 then hit=1 end
  if hit>hit_limit then return end
  return name,math.min(hit,3),'light '..hit,hit>=5,hit
 end
 -- All remaining combat attacks use the same three-phase hammer language.
 if not(name:find('Light',1,true)or name:find('Heavy',1,true)or name:find('Mixed',1,true)or name:find('Strike',1,true)
  or name:find('Thunderheart',1,true)or name:find('Execution',1,true)or name:find('ParryCounter',1,true)
  or name:find('PerfectCounter',1,true)or name:find('GiantsBane',1,true)or name:find('Kill',1,true)
  or name:find('Sprint',1,true)or name:find('Switch',1,true))then return end
 local phase=1
 if name:find('Heavy',1,true)or name:find('Strike',1,true)or name:find('Thunderheart',1,true)
  or name:find('Execution',1,true)or name:find('ParryCounter',1,true)or name:find('PerfectCounter',1,true)
  or name:find('GiantsBane',1,true)then phase=3
 elseif name:find('Mixed',1,true)or name:find('Kill',1,true)or name:find('Switch',1,true)or name:find('SprintDraw',1,true)then phase=2 end
 local suffix=name:match('AM_Mjolnir_([%w_]+)')or''
 local finisher=suffix=='Heavy3' or suffix=='MixedFollow' or suffix=='MixedTwoFollow'
  or suffix=='MixedThreeFollow' or suffix=='MixedFourFollow' or suffix=='KillHeavy'
  or suffix=='KillLight' or suffix=='GiantsBane' or suffix=='Execution01'
 return name,phase,'special '..phase,finisher
end
-- Strike times for the hammer's sound, one per authored blow.  Each is the
-- moment the hammer head moves fastest through its swing, measured from the
-- montages' source animations (MjolnirSoundDesign --sweeplua).  The native
-- damage frames open hit detection 20-110 ms earlier, so cueing on them made
-- the strike sound land before the hammer visibly did.  Blows with no clear
-- sweep near their damage frame keep it (DodgeHeavy 1, Heavy2 2, PerfectCounter 1,
-- Sprint 2, SprintDraw 2, SprintSwitch 1, Execution01 3-4).  LightAAAAA is
-- outside the four-hit cap and keeps its damage frame.
local contact={
 LightA={.879},LightAA={.571},LightAAA={.787},LightAAAA={.837},LightAAAAA={.620},
 AirHeavy={.754},AirLight={.588},AirSwitch={1.037},DodgeHeavy={.251,.787},DodgeLight={.663},
 DrawHeavy={.829},DrawLight={.638},Heavy1={1.096},Heavy2={.304,.530,.796},Heavy3={.538,1.121,1.621},
 KillHeavy={1.537},KillLight={1.712},MixedFollow={.538,1.121,1.621},MixedFour={.438,.704,1.037},
 MixedFourFollow={.171,.504,1.279},MixedOne={.413,1.204},MixedThree={.579,1.662},
 MixedThreeFollow={.821,1.637},MixedTwo={.354,.538,1.204},MixedTwoFollow={.388,.946},
 ParryCounter={.321,.837},PerfectCounter={.592,1.487},Sprint={.329,.509,.796},
 SprintDraw={.221,.455,.712},SprintHeavy={.421,.787},SprintHeavyDraw={.288,.746},
 SprintSwitch={.360,.588},Switch={.929},
 Execution01={.704,1.546,3.600,4.760},
}
-- Montage seconds, measured from the attacking arm and weapon tracks in
-- the source clips, with segment trims and play rates applied.
local swing_onset={
 LightA=.620,LightAA=.240,LightAAA=.320,LightAAAA=.720,LightAAAAA=.440,
 AirHeavy=.350,AirLight=.190,AirSwitch=.950,DodgeHeavy=.140,DodgeLight=.480,
 DrawHeavy=.570,DrawLight=.540,Heavy1=.730,Heavy2=.160,Heavy3=.220,
 KillHeavy_DashSnap=1.123,KillHeavy_Main=1.130,
 KillLight_DashSnap=1.400,KillLight_Main=1.270,
 MixedFollow=.220,MixedFour=.290,MixedFourFollow=.120,MixedOne=.030,
 MixedThree=.570,MixedThreeFollow=.600,MixedTwo=.170,MixedTwoFollow=.200,
 ParryCounter=.270,PerfectCounter=.500,Sprint=.140,SprintDraw=.170,
 SprintHeavy=.190,SprintHeavyDraw=.060,SprintSwitch=.320,Switch=.780,
 Strike=.060,Thunderheart=.180,Execution01=.500,GiantsBane=.060,
}
local function contacts(name,anim,montage,phase)
 local suffix=name:match('AM_Mjolnir_([%w_]+)')or''
 if contact[suffix]then return contact[suffix]end
 -- Kill montages have visual variants (Main/DashSnap) but share the same
 -- native ability damage frame.
 if suffix:find('KillHeavy',1,true)then return contact.KillHeavy end
 if suffix:find('KillLight',1,true)then return contact.KillLight end
 local ok,length=pcall(function()return anim:Montage_GetPlayLength(montage)end)
 length=ok and tonumber(length)or nil
 return {(length and length>.2)and length*(phase>=3 and .42 or .36)or .34}
end
-- The throw (L1 + Triangle) plays the stock YouLongCha shoot montage.  Hun's
-- arm whips through and the hammer is fastest at .25 s, where the ability now
-- launches the dart, so the release sound is cued to land there.
local THROW_MONTAGE='YouLongCha_Attack_Shoot_Montage'
local THROW_RELEASE=.25
local THROW_WINDUP=.04
local throw_name,throw_pos,throw_sent,windup_sent
local windup_weapon
local function mjolnir_in_hand()
 for _,actor in ipairs(FindAllOf and FindAllOf('BP_Weapon_Hun_Mjolnir_C')or {})do
  if valid(actor)and not actor:GetFullName():find('Default__',1,true)then return actor end
 end
 return false
end
local function watch_throw(player,anim,montage,name)
 if not name:find(THROW_MONTAGE,1,true)then
  if throw_name then pcall(Trail.stop_windup)end
  throw_name,windup_weapon=nil,nil
  return
 end
 local pos=anim:Montage_GetPosition(montage)
 if name~=throw_name or(throw_pos and pos+.04<throw_pos)then
  if throw_name then pcall(Trail.stop_windup)end
  throw_name=name
  -- Another weapon's fork skill uses this montage too: only Mjolnir throws sound.
  windup_weapon=mjolnir_in_hand()
  throw_sent=not windup_weapon
  windup_sent=throw_sent
 end
 throw_pos=pos
 if not windup_sent and pos>=THROW_WINDUP then
  windup_sent=true
  if pos<.10 then
   pcall(Feedback.throw_windup,player)
   pcall(function()
    local now=H.GetGameplayStatics():GetTimeSeconds(player)
    Trail.windup(player,windup_weapon.WeaponMesh,now,THROW_RELEASE-pos)
   end)
  end
 end
 if not throw_sent and pos>=.08 then
  throw_sent=true
  pcall(Feedback.throw,player,math.max(0,THROW_RELEASE-pos))
 end
end
local function update()
 local pc=H.GetPlayerController();local player=valid(pc)and pc.Pawn or nil
 if not valid(player)then
  if throw_name then pcall(Trail.stop_windup)end
  Glow.attack(nil,false)
  previous=nil;position=nil;player_id=nil;throw_name=nil;windup_weapon=nil;return
 end
 local id=player:GetFullName()
 if id~=player_id then
  if throw_name then pcall(Trail.stop_windup)end
  previous=nil;position=nil;player_id=id;throw_name=nil;windup_weapon=nil
 end
 local anim=player.Mesh:GetAnimInstance();local montage=valid(anim)and anim:GetCurrentActiveMontage()or nil
 local name=valid(montage)and montage:GetFullName()or ''
 watch_throw(player,anim,montage,name)
 local key,phase,label,finisher,hit=attack(name)
 Glow.attack(id,key~=nil or (windup_weapon and throw_pos<THROW_RELEASE))
 local now=H.GetGameplayStatics():GetTimeSeconds(player)
 if not key then
  if previous then D.write('combo',previous..' ended; elapsed='..string.format('%.3f',now-began)..'; montage position='..string.format('%.3f',position or 0))end
  previous=nil;position=nil;return
 end
 local current=anim:Montage_GetPosition(montage)
 if key~=previous or(position and current+.04<position)then
  if previous then D.write('combo','transition '..previous..' -> '..key..'; previous position='..string.format('%.3f',position))end
  previous=key;began=now
  beats=contacts(key,anim,montage,phase)
  beat_index=1
  swing_sent=false
  local suffix=key:match('AM_Mjolnir_([%w_]+)')or''
  first_swing=swing_onset[suffix] or math.max(0,beats[1]-.18)
  weapon_switch=suffix=='Switch' or suffix=='AirSwitch' or suffix=='SprintSwitch'
  chain_hit=hit
  D.write('combo','native '..label..' started: '..key)
 end
 position=current
 while beats[beat_index] do
  local strike=beats[beat_index]
  local swing=beat_index==1 and first_swing or math.max(beats[beat_index-1]+.04,strike-.22)
  if not swing_sent and current>=swing then
   swing_sent=true
   pcall(Feedback.melee_start,player,phase,finisher and beat_index==#beats,weapon_switch,math.max(0,strike-current))
  end
  if current<strike then break end
  -- The storm gathers through a chain: third light hit on, mixed attacks,
  -- and every follow-up blow inside one animation.  (Light chains carry
  -- their own phase ramp, so phase alone only counts for special attacks.)
  local charged=(chain_hit or 0)>=3 or (not chain_hit and phase==2) or beat_index>1
  Glow.strike(id,now)
  pcall(Feedback.melee_impact,player,phase,finisher and beat_index==#beats,weapon_switch,charged)
  beat_index=beat_index+1
  swing_sent=false
 end
end
function C.start(max_hits)
 if started then return end;started=true
 hit_limit=max_hits or 5
 require('game_thread_pump').add('combo_observer',update)
 D.write('combo','all native Mjolnir melee attacks: cosmetic-only heavy hammer feedback')
end
return C

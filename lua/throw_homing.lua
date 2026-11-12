-- Homing for throws the game aims (locked on, or an enemy near).  The game
-- solves the launch arc once, for the dart's own heavy gravity; with the
-- lighter gravity the hammer climbed over that arc and sailed past.  Now the
-- dart is steered onto the enemy it was thrown at: the hostile closest to its
-- launch line (within RANGE and CONE -- the game pointed it at its target, so
-- that is the one).  Only its direction bends, at most TURN degrees a second,
-- and its speed is kept, so it still reads as a thrown arc, not a missile.
-- Homing ends at the hit, when the recall starts, when the target is gone or
-- no longer hostile (dead), or once the hammer has gone past it.
local D=require('runtime_diagnostics')
local Aim=require('throw_aim')
local M={}
M.TURN=240      -- degrees a second the dart may turn
M.RANGE=6000    -- cm: enemies farther than this are not picked
M.CONE=30       -- degrees off the launch line an enemy may be
local dart,target,name,last=nil,nil,nil,nil

local function valid(o)return o and o.IsValid and o:IsValid()end
local function id(o)local ok,n=pcall(function()return o:GetFullName()end);return ok and n or'?'end
local function loc(a)local ok,p=pcall(function()return a:K2_GetActorLocation()end);return ok and p or nil end
local function movement(p)
 local ok,mv=pcall(function()return p.SGameProjectileMovement end)
 return ok and valid(mv)and mv or nil
end
local function vel(mv)
 local ok,v=pcall(function()return mv.Velocity end)
 if not ok or not v then return nil end
 return tonumber(v.X)or 0,tonumber(v.Y)or 0,tonumber(v.Z)or 0
end

local function stop(why)
 if dart and why then D.write('throw','throw homing ended: '..why)end
 dart,target,name,last=nil,nil,nil,nil
end
M.stop=function()stop(nil)end
function M.active()return dart~=nil end

-- At launch.  Picks the target or says why there is none.
function M.start(projectile,pawn,now)
 stop(nil)
 local mv=movement(projectile);local from=loc(projectile)
 if not mv or not from then D.write('throw','throw homing: the dart cannot be read');return end
 local vx,vy,vz=vel(mv);if not vx then return end
 local sp=math.sqrt(vx*vx+vy*vy+vz*vz);if sp<1 then return end
 local best,best_a,best_d=nil,M.CONE,nil
 local okh,list=pcall(Aim.hostiles,pawn)
 for _,c in ipairs(okh and list or {})do
  local p=loc(c)
  if p then
   local dx,dy,dz=p.X-from.X,p.Y-from.Y,p.Z-from.Z
   local d=math.sqrt(dx*dx+dy*dy+dz*dz)
   if d>1 and d<=M.RANGE then
    local a=math.deg(math.acos(math.max(-1,math.min(1,(vx*dx+vy*dy+vz*dz)/(sp*d)))))
    if a<=best_a then best,best_a,best_d=c,a,d end
   end
  end
 end
 if not best then D.write('throw','throw homing: no enemy along the throw');return end
 dart,target,name,last=projectile,best,id(best),now
 D.write('throw',string.format('throw homing onto %s (%.0f m, %.0f deg off the throw)',name,best_d/100,best_a))
end

-- Every frame.  flying: the dart is still on its way out.
function M.update(now,flying)
 if not dart then return end
 if not flying then stop('the hammer hit or is coming back');return end
 if not valid(dart)then stop('the dart is gone');return end
 if not valid(target)then stop('the target is gone');return end
 local okh,h=pcall(Aim.hostile,target)
 if okh and h==false then stop('the target is no longer hostile');return end
 local mv=movement(dart);local from=loc(dart);local to=loc(target)
 if not mv or not from or not to then return end
 local dt=now-last;last=now;if dt<=0 then return end
 local vx,vy,vz=vel(mv);if not vx then return end
 local sp=math.sqrt(vx*vx+vy*vy+vz*vz);if sp<1 then return end
 local wx,wy,wz=to.X-from.X,to.Y-from.Y,to.Z-from.Z
 local wl=math.sqrt(wx*wx+wy*wy+wz*wz);if wl<1 then return end
 local ux,uy,uz=vx/sp,vy/sp,vz/sp;wx,wy,wz=wx/wl,wy/wl,wz/wl
 local cos=math.max(-1,math.min(1,ux*wx+uy*wy+uz*wz))
 if cos<0 then stop('the hammer went past '..name);return end
 local th=math.acos(cos);if th<1e-4 then return end
 local a=math.min(th,math.rad(M.TURN)*dt)
 local s=math.sin(th);local k1,k2=math.sin(th-a)/s,math.sin(a)/s
 local nx,ny,nz=k1*ux+k2*wx,k1*uy+k2*wy,k1*uz+k2*wz
 pcall(function()mv.Velocity={X=nx*sp,Y=ny*sp,Z=nz*sp}end)
end
return M

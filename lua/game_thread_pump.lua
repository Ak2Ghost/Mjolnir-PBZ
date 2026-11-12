local D=require('runtime_diagnostics');local P={};local callbacks={};local timer=nil
local pending={};local pending_names={}
-- Work that moves things on screen runs every rendered frame: a 16 ms timer
-- only fires every second frame above 60 fps (the hammer measured ~38 moves a
-- second), which reads as judder.  The 16 ms timer keeps it running if the
-- frame loop ever stops.
local frames={};local frame_loop=nil;local last_frame=nil;local frame_count,frame_since=0,nil
local fallback_logged=false
local function run(list,tag)
 for _,entry in ipairs(list)do
  local ok,err=pcall(entry.fn)
  if not ok then D.state(tag..entry.name,tostring(err))end
 end
end
local function frame_tick()
 last_frame=os.clock()
 frame_count=frame_count+1;frame_since=frame_since or last_frame
 if frame_count==120 then D.write('pump',string.format('per-frame loop running: %.1f ms per frame',(last_frame-frame_since)*1000/119))end
 run(frames,'frame.')
 return false
end
local function tick()
 local work=pending;pending={};pending_names={}
 for _,entry in ipairs(work)do
  local ok,err=pcall(entry.fn)
  if not ok then D.write('task.'..entry.name,tostring(err))end
 end
 run(callbacks,'pump.')
 if #frames>0 and(not last_frame or os.clock()-last_frame>.1)then
  if frame_loop and not fallback_logged then fallback_logged=true;D.write('pump','per-frame loop silent; frame work runs on the 16 ms timer')end
  run(frames,'frame.')
 end
 return false
end
local function start()
 if timer then return end
 if type(LoopInGameThreadWithDelay)~='function'then error('Installed UE4SS game-thread timer API unavailable')end
 timer=LoopInGameThreadWithDelay(16,tick)
 D.write('pump','single game-thread timer registered; no async enqueue loop')
end
function P.post(name,fn)
 -- Key handlers only append Lua data. Native work runs from the retained timer.
 if pending_names[name]then return false end
 pending_names[name]=true;pending[#pending+1]={name=name,fn=fn};return true
end
function P.add(name,fn)
 for _,entry in ipairs(callbacks)do if entry.name==name then return end end
 callbacks[#callbacks+1]={name=name,fn=fn}
 start()
end
-- Every rendered frame (falls back to the 16 ms timer).
function P.frame(name,fn)
 for _,entry in ipairs(frames)do if entry.name==name then return end end
 frames[#frames+1]={name=name,fn=fn}
 start()
 if not frame_loop and type(LoopInGameThreadAfterFrames)=='function'then
  local ok,handle=pcall(LoopInGameThreadAfterFrames,1,frame_tick)
  if ok then frame_loop=handle or true;D.write('pump','per-frame game-thread loop registered')
  else D.write('pump','per-frame loop unavailable ('..tostring(handle)..'); frame work runs on the 16 ms timer')end
 end
end
return P

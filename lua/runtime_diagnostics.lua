-- The mod's log: lines go to UE4SS.log as "[MjolnirRuntime] channel: message".
local D={};local previous={}
function D.write(channel,message)
 print('[MjolnirRuntime] '..channel..': '..tostring(message)..'\n')
end
-- Only when the message for a channel changes (for things checked every frame).
function D.state(channel,message)
 message=tostring(message)
 if previous[channel]~=message then previous[channel]=message;D.write(channel,message)end
end
return D

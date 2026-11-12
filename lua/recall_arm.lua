local Arm = {}
local path = '/Game/Mods/MjolnirHammer/Montages/AM_Mjolnir_RecallArm.AM_Mjolnir_RecallArm'
local anim, montage
local raised, played, unavailable, recoiling
local CATCH_POSITION = 3 -- after the held reach in AM_Mjolnir_RecallArm

local function valid(object)
    return object and object.IsValid and object:IsValid()
end

local function busy(instance, reach)
    local current = instance:GetCurrentActiveMontage()
    if not valid(current) then return false end
    local name = current:GetFullName()
    return name ~= reach:GetFullName()
        and not name:find('AM_Mjolnir_Throw', 1, true)
        and not name:find('AM_Mjolnir_HomingThrow', 1, true)
        and not name:find('Hun_ShaChi_YouLongCha_Attack_Shoot_Montage', 1, true)
end

local function lower(blend)
    local was_raised = raised
    raised = false
    if was_raised and valid(anim) and valid(montage) then anim:Montage_Stop(blend, montage) end
end

function Arm.update(pawn, phase)
    if unavailable or (phase ~= 'home' and phase ~= 'align') then return end
    if not valid(anim) then
        local mesh = pawn.Mesh
        if not valid(mesh) then return end
        anim = mesh:GetAnimInstance()
        if not valid(anim) then return end
    end
    -- The throw ability holds the montage. Never load assets during flight.
    if not valid(montage) then montage = StaticFindObject(path) end
    if not valid(montage) then
        unavailable = true
        return 'recall reach montage unavailable'
    end
    if busy(anim, montage) then
        lower(.1)
        return
    end
    if raised and anim:Montage_IsPlaying(montage) then return end
    if (tonumber(anim:Montage_Play(montage, 1, 0, 0, false)) or 0) <= 0 then
        raised, unavailable = false, true
        return 'recall reach montage refused'
    end
    raised = true
    local message = played and 'recall reach resumed' or 'recall reach started'
    played = true
    return message
end

function Arm.reset()
    local instance, reach, was_raised = anim, montage, raised
    anim, montage, raised, played, unavailable, recoiling = nil, nil, false, false, false, false
    if was_raised and valid(instance) and valid(reach) then instance:Montage_Stop(.2, reach) end
end

function Arm.catch()
    if raised and valid(anim) and valid(montage) and not busy(anim, montage)
        and anim:Montage_IsPlaying(montage) then
        anim:Montage_SetPosition(montage, CATCH_POSITION)
        recoiling = true
        return
    end
    Arm.reset()
end

function Arm.tick_catch()
    if not recoiling then return end
    if not valid(anim) or not valid(montage) or not anim:Montage_IsPlaying(montage) then
        raised = false
        Arm.reset()
    elseif busy(anim, montage) then
        lower(.1)
        Arm.reset()
    end
end

return Arm

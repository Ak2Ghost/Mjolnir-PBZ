local D = require('runtime_diagnostics')
local H = require('UEHelpers')
local Glow = {}
local FADE_TIME, FULL = 2, 3
local FLARE_TIME, FLARE_GAIN = .18, 1.5
local owner, attacking_owner, fade_from, lit, next_lookup
local strike_owner, strike_at
local intensity, fade_level = 0, 0
local bindings = {}
local rune_parameter

local function valid(object)
    return object and object.IsValid and object:IsValid()
end

function Glow.attack(owner_id, attacking)
    attacking_owner = attacking and owner_id or nil
end

function Glow.strike(owner_id, now)
    strike_owner, strike_at = owner_id, now
end

local function set(entry, intensity)
    if not valid(entry.material) then return false end
    if entry.intensity ~= intensity then
        -- MI_Mjolnir stores Intensity on material layer 1. Association 0
        -- is LayerParameter in the cooked shader's parameter info.
        rune_parameter = rune_parameter or {Name=H.FindOrAddFName('Intensity'), Association=0, Index=1}
        entry.material:SetScalarParameterValueByInfo(rune_parameter, intensity)
        entry.intensity = intensity
    end
    return true
end

local function bind(mesh)
    if not valid(mesh) then return end
    local name = mesh:GetFullName()
    local entry = bindings[name]
    if entry and valid(entry.material) then
        local installed = mesh:GetMaterial(entry.index)
        if valid(installed) and installed:GetFullName() == entry.material:GetFullName() then return end
    end
    bindings[name] = nil
    for index = 0, mesh:GetNumMaterials() - 1 do
        local source = mesh:GetMaterial(index)
        local source_name = valid(source) and source:GetFullName() or ''
        if source_name:match('%.MI_Mjolnir$') or source_name:match('%.MjolnirRuneGlow$') then
            local material = source
            if source_name:match('%.MI_Mjolnir$') then
                material = mesh:CreateDynamicMaterialInstance(index, source, H.FindOrAddFName('MjolnirRuneGlow'))
            end
            if valid(material) then
                bindings[name] = {material = material, index = index}
                D.write('runes', 'rune intensity bound to ' .. name)
            end
            return
        end
    end
end

function Glow.reset()
    for _, entry in pairs(bindings) do pcall(set, entry, 0) end
    bindings = {}
    owner, fade_from, lit, next_lookup = nil, nil, false, nil
    intensity, fade_level = 0, 0
    strike_owner, strike_at = nil, nil
end

function Glow.update(pawn, now, flying, flyer, find_held)
    local owner_id = pawn:GetFullName()
    if owner_id ~= owner then
        Glow.reset()
        owner = owner_id
    end
    local on = flying or attacking_owner == owner_id
    if on then
        if not lit then next_lookup = nil end
        fade_from = nil
    elseif lit then
        fade_from = now
        fade_level = intensity
        strike_owner, strike_at = nil, nil
    end
    lit = on
    if not on and not fade_from then return end

    if on then
        intensity = FULL
        if strike_owner == owner_id and now >= strike_at then
            intensity = intensity + FLARE_GAIN * math.max(0, 1 - (now - strike_at) / FLARE_TIME)
        end
    else
        intensity = fade_level * math.max(0, 1 - (now - fade_from) / FADE_TIME)
    end
    if not next_lookup or now >= next_lookup then
        next_lookup = now + .15
        pcall(function()bind(find_held(pawn))end)
    end
    pcall(bind, flyer)
    for name, entry in pairs(bindings) do
        local ok, alive = pcall(set, entry, intensity)
        if not ok then D.state('runes.error', tostring(alive)) end
        if not ok or not alive then bindings[name] = nil end
    end
    if intensity == 0 then fade_from = nil end
end

return Glow

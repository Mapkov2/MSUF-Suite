local _, private = ...
local NS = private.NS
local Public, Finite = NS.Public, NS.Finite
local Absorbs = {}
private.Absorbs = Absorbs

local SHARED, OFF = 2, 3
local hidden = { a = 0 }
local positive = { "totalAbsorb", "totalAbsorbOverlay", "overAbsorbGlow" }
local negative = { "myHealAbsorb", "myHealAbsorbOverlay", "myHealAbsorbLeftShadow",
    "myHealAbsorbRightShadow", "overHealAbsorbGlow" }
local states = setmetatable({}, { __mode = "k" })
local shield, healAbsorb

local function Read(config)
    if config.look == 2 then return end
    local p, n = config.nameplateAbsorbMode, config.nameplateHealAbsorbMode
    local shared = p == SHARED or n == SHARED
    local read = shared and NS.HostBridge and NS.HostBridge.SharedNameplateAbsorbs
    local pos, neg
    if read then pos, neg = read() end
    if p == OFF then pos = hidden elseif p ~= SHARED then pos = nil end
    if n == OFF then neg = hidden elseif n ~= SHARED then neg = nil end
    return pos, neg, shared
end

local function Same(old, new)
    return old == new or old and new and old.a == new.a and old.r == new.r
        and old.g == new.g and old.b == new.b and old.texture == new.texture
end

function Absorbs.SharedChanged(config)
    if not Absorbs.shared then return false end
    local pos, neg = Read(config)
    return not Same(shield, pos) or not Same(healAbsorb, neg)
end

function Absorbs.Configure(config)
    local pos, neg, shared = Read(config)
    local positiveChanged, negativeChanged = not Same(shield, pos), not Same(healAbsorb, neg)
    if positiveChanged then shield = pos end
    if negativeChanged then healAbsorb = neg end
    Absorbs.shared, Absorbs.inUse = shared, shield ~= nil or healAbsorb ~= nil
    return positiveChanged or negativeChanged
end

local function CaptureTexture(record)
    local region = record.region
    local atlas = region:GetAtlas()
    if not Public(atlas) then return false end
    if atlas then
        record.atlas = atlas
    else
        local asset, horizontal, vertical = region:GetTexture(), region:GetHorizTile(), region:GetVertTile()
        if not (Public(asset) and Public(horizontal) and Public(vertical)) then return false end
        record.asset, record.horizontal, record.vertical = asset, horizontal, vertical
    end
    record.captured = true
    return true
end

local function SetTexture(record, texture)
    if record.texture == texture then return true end
    if not record.captured and not CaptureTexture(record) then return false end
    local region, applied = record.region
    if texture then
        applied = region:SetTexture(texture, false, false)
    elseif record.atlas then
        applied = region:SetAtlas(record.atlas, false)
    else
        applied = region:SetTexture(record.asset, record.horizontal, record.vertical)
    end
    if not Public(applied) or applied == false then return false end
    record.texture = texture
    return true
end

-- Vertex alpha composes with the existing prediction fade, which uses region
-- alpha. Blizzard continues to show, hide, resize and anchor all parts.
local function PaintRegion(group, index, region, style, alpha, texture, writable)
    local record = group[index]
    if record and record.style == style and record.opacity == alpha then return true end
    if not writable(region) then return false end
    if not record then
        local r, g, b, a = region:GetVertexColor()
        if not (Finite(r) and Finite(g) and Finite(b) and Finite(a)) then return false end
        record = { region = region, r = r, g = g, b = b, a = a }
        group[index] = record
    end
    if not SetTexture(record, texture) then return false end
    if style and index == 1 and style.r then
        region:SetVertexColor(style.r, style.g, style.b, alpha)
    else
        region:SetVertexColor(record.r, record.g, record.b, record.a * alpha)
    end
    record.style, record.opacity = style, alpha
    if not style then group[index] = nil end
    return true
end

local function PaintGroup(group, health, keys, style, writable)
    if group.applied == style and not group.pending then return true end
    local done = true
    local texture = style and style.a > 0 and style.texture or nil
    for index, key in ipairs(keys) do
        local record = group[index]
        local region = record and record.region or style and health[key]
        if not Public(region) then
            done = false
            if index == 1 then texture = nil end
        elseif not region then
            if index == 1 then texture = nil end
        else
            local alpha = style and style.a or 1
            if keys == positive and index == 2 and texture then alpha = 0 end
            if not PaintRegion(group, index, region, style, alpha, index == 1 and texture or nil, writable) then
                done = false
                -- Retain the native overlay if replacing its base texture failed.
                if index == 1 and texture then texture = nil end
            end
        end
    end
    group.pending = not done
    if done then group.applied = style end
    return done
end

local function Unprotected(frame)
    local protected = frame:IsProtected()
    return Public(protected) and protected == false
end

function Absorbs.Apply(uf, health, styled, writable)
    local state = states[uf]
    local pos, neg = styled and shield or nil, styled and healAbsorb or nil
    if not state and not (pos or neg) then return true end
    if state and state.current and state.positive.applied == pos and state.negative.applied == neg then return true end
    if not writable(health) then return not state and Public(health) and not health end
    if NS.InCombat() and not (Unprotected(uf) and Unprotected(health)) then return false end
    if not state then
        state = { positive = {}, negative = {} }
        states[uf] = state
    end
    local p = PaintGroup(state.positive, health, positive, pos, writable)
    local n = PaintGroup(state.negative, health, negative, neg, writable)
    state.current = p and n
    if state.current and not (pos or neg) then states[uf] = nil end
    return state.current
end

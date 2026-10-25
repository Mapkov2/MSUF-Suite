local _, NS = ...

-- Static decoration for Suite-owned bars and icon owners. Creation and style
-- changes call these painters; value, timer and spell events never need them.
local Gloss = {}
NS.GlossMaterial = Gloss
local Bridge = NS.HostBridge
local bars = setmetatable({}, { __mode = "k" })
local icons = setmetatable({}, { __mode = "k" })

local function Clamp(value, fallback, maximum)
    value = tonumber(value)
    if not value or value ~= value then value = fallback end
    return math.max(0, math.min(maximum, value))
end

local function ShowBar(state, shown)
    if not state or state.shown == shown then return end
    state.upper:SetShown(shown)
    state.lower:SetShown(shown)
    state.shown = shown
end

local function NewReflection(owner, path, upper)
    local texture = owner:CreateTexture(nil, "OVERLAY", nil, -1)
    texture:SetTexture(path, "CLAMP", "CLAMP")
    texture:SetBlendMode("ADD")
    texture:SetTexCoord(.125, .875, upper and 0 or 2, upper and 2 or 0)
    return texture
end

local function StyleBar(state, target, path, strength, opacity)
    if state.target ~= target then
        state.upper:SetAllPoints(target)
        state.lower:SetAllPoints(target)
        state.target = target
    end
    if state.path ~= path then
        state.upper:SetTexture(path, "CLAMP", "CLAMP")
        state.lower:SetTexture(path, "CLAMP", "CLAMP")
        state.path = path
    end
    if state.strength ~= strength then
        local upper, lower = strength * .65, strength * .08
        state.upper:SetVertexColor(upper, upper, upper, 1)
        state.lower:SetVertexColor(lower, lower, lower, 1)
        state.strength, state.opacity = strength, nil
    end
    -- SetVertexColor also owns native alpha: restore opacity after RGB writes.
    if state.opacity ~= opacity then
        state.upper:SetAlpha(opacity)
        state.lower:SetAlpha(opacity)
        state.opacity = opacity
    end
    ShowBar(state, true)
end

function Gloss.Available()
    return Bridge.GlossTexture() ~= nil
end

function Gloss.Bar(bar, enabled, strength, opacity)
    if not bar then return false end
    local state = bars[bar]
    if enabled ~= true then ShowBar(state, false) return false end
    strength = Clamp(strength, 50, 100) / 100
    if strength == 0 then ShowBar(state, false) return false end
    local path = Bridge.GlossTexture()
    if not path then ShowBar(state, false) return false end
    local target = bar:GetStatusBarTexture()
    if not target then ShowBar(state, false) return false end
    if not state then
        state = { upper = NewReflection(bar, path, true), lower = NewReflection(bar, path, false), path = path }
        bars[bar] = state
    end
    StyleBar(state, target, path, strength, Clamp(opacity, 1, 1))
    return true
end

local function HideIcon(owner, state)
    if state and state.painted then
        Bridge.PaintIconSkin(owner, nil)
        state.painted = false
    end
    return false
end

function Gloss.Icon(owner, icon, enabled, strength, size)
    if not owner then return false end
    local state = icons[owner]
    if enabled ~= true or not icon then return HideIcon(owner, state) end
    strength = Clamp(strength, 50, 100) / 100
    if strength == 0 then return HideIcon(owner, state) end
    local look = Bridge.IconSkinLook("FRAME_BEVEL", "RECTANGLE", strength)
    if not look then return HideIcon(owner, state) end
    size = math.max(1, tonumber(size) or icon:GetWidth())
    if state and state.painted and state.look == look and state.anchor == icon and state.size == size then return true end
    local painted = Bridge.PaintIconSkin(owner, look, size, size, icon)
    if painted then
        if not state then state = {} icons[owner] = state end
        state.look, state.anchor, state.size, state.painted = look, icon, size, true
    end
    return painted
end

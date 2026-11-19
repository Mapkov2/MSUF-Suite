local _, NS = ...

-- Static decoration for bar fills and icon owners. Creation and style
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
    if state.lower then state.lower:SetShown(shown) end
    state.shown = shown
end

local function NewReflection(owner, path, upper)
    local texture = owner:CreateTexture(nil, "OVERLAY", nil, -1)
    texture:SetTexture(path, "CLAMP", "CLAMP")
    texture:SetBlendMode("ADD")
    texture:SetTexCoord(.125, .875, upper and 0 or 2, upper and 2 or 0)
    return texture
end

local function BarOpacity(state, opacity)
    if not state or state.opacity == opacity then return end
    state.upper:SetAlpha(opacity)
    if state.lower then state.lower:SetAlpha(opacity) end
    state.opacity = opacity
end

local function StyleBar(state, target, path, strength, opacity)
    if state.target ~= target then
        state.upper:SetAllPoints(target)
        if state.lower then state.lower:SetAllPoints(target) end
        state.target = target
    end
    if state.lower and state.path ~= path then
        state.upper:SetTexture(path, "CLAMP", "CLAMP")
        state.lower:SetTexture(path, "CLAMP", "CLAMP")
        state.path = path
    end
    if state.strength ~= strength then
        if state.lower then
            local upper, lower = strength * .65, strength * .08
            state.upper:SetVertexColor(upper, upper, upper, 1)
            state.lower:SetVertexColor(lower, lower, lower, 1)
        else
            state.upper:SetGradient("VERTICAL", CreateColor(1, 1, 1, 0), CreateColor(1, 1, 1, strength * .65))
        end
        state.strength, state.opacity = strength, nil
    end
    -- SetVertexColor also owns native alpha: restore opacity after RGB writes.
    BarOpacity(state, opacity)
    ShowBar(state, true)
end

-- Nameplates already guard access to their native fill before passing it in.
-- Older hosts without the shared material still get a native highlight fade.
function Gloss.Fill(owner, target, strength, opacity)
    local state = bars[owner]
    if not target or not strength or strength <= 0 then ShowBar(state, false) return end
    if not state then
        local path = Bridge.GlossTexture()
        if path then
            state = { upper = NewReflection(owner, path, true), lower = NewReflection(owner, path, false), path = path }
        else
            local sheen = owner:CreateTexture(nil, "OVERLAY", nil, -1)
            sheen:SetTexture("Interface\\Buttons\\WHITE8X8")
            sheen:SetBlendMode("ADD")
            state = { upper = sheen }
        end
        bars[owner] = state
    end
    StyleBar(state, target, state.path, strength / 100, opacity or 1)
    return state.upper, state.lower
end

function Gloss.SetBarOpacity(owner, opacity) BarOpacity(bars[owner], opacity) end

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

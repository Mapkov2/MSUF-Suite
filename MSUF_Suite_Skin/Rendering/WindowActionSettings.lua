local _, NS = ...

-- Window action options (WindowActionSkin.lua, which loads before): the
-- validated option writes and their reset, the read-only status getters and
-- the theme listener that re-applies the glyphs.
local WindowActionSkin = NS.WindowActionSkin
-- WindowActionSkin.lua's settings reader: taken off NS again, so nothing
-- internal stays reachable through _G.MapkoSkin.
local Shared = NS.WindowActionSkinShared
NS.WindowActionSkinShared = nil
local Settings = Shared.Settings
local IsListed = NS.IsListed

function WindowActionSkin.SetOption(key, value)
    if NS.IsCombatLocked() then return false, "combat" end
    local settings = Settings()
    if key == "style" then
        if not IsListed(NS.WindowActionStyles, value) then return false, "invalid value" end
    elseif key == "glyphMode" then
        if not IsListed(NS.WindowActionGlyphModes, value) then return false, "invalid value" end
    elseif key == "weight" then
        if not IsListed(NS.WindowActionWeights, value) then return false, "invalid value" end
    elseif key == "glyphSize" then
        value = tonumber(value)
        if not value or value < 8 or value > 18 then return false, "invalid value" end
        value = math.floor(value + 0.5)
    elseif key == "closeGlyphSize" then
        value = tonumber(value)
        if not value or value < 6 or value > 18 then return false, "invalid value" end
        value = math.floor(value + 0.5)
    elseif key == "glyphOffsetX" or key == "glyphOffsetY" then
        value = tonumber(value)
        if not value or value < -4 or value > 4 then return false, "invalid value" end
        value = math.floor(value + 0.5)
    elseif key == "surfaceInset" then
        value = tonumber(value)
        if not value or value < 0 or value > 6 then return false, "invalid value" end
        value = math.floor(value + 0.5)
    elseif key == "surfaceShape" then
        if not IsListed(NS.WindowActionShapes, value) then return false, "invalid value" end
    elseif key == "surfaceRadius" then
        value = tonumber(value)
        if not IsListed(NS.GeometryRadii, value) then return false, "invalid value" end
    elseif key == "opacity" then
        value = tonumber(value)
        if not value or value < 0.35 or value > 1 then return false, "invalid value" end
    else
        return false, "unknown option"
    end
    settings[key] = value
    WindowActionSkin.RefreshAll()
    NS.Registry.NotifyListeners("windowAction", key)
    return true
end

function WindowActionSkin.ResetRecommended()
    if NS.IsCombatLocked() then return false, "combat" end
    local defaults = NS.Defaults.icons.windowActions
    local settings = Settings()
    for key, value in pairs(defaults) do settings[key] = value end
    local refreshed, reason = WindowActionSkin.RefreshAll()
    NS.Registry.NotifyListeners("windowAction", "reset")
    return refreshed, reason
end

function WindowActionSkin.GetState(button)
    local state = WindowActionSkin.states[button]
    return state and state.visible and state or nil
end
function WindowActionSkin.GetKind(button)
    local state = WindowActionSkin.states[button]
    return state and state.visible and state.kind or nil
end
function WindowActionSkin.GetOwner(button)
    local state = WindowActionSkin.states[button]
    return state and state.visible and state.owner or nil
end
function WindowActionSkin.IsApplied(button)
    local state = WindowActionSkin.states[button]
    return state ~= nil and state.visible == true
end
function WindowActionSkin.GetStatus()
    local count = 0
    for _, state in pairs(WindowActionSkin.states) do
        if state.visible then count = count + 1 end
    end
    return { applied = count, style = Settings().style }
end

-- The color roles ColorRole gives the glyphs. The action surfaces follow the
-- Registry's own surface refreshes (appearance, geometry and their colors);
-- SetOption and ResetRecommended re-apply after a window-action setting.
local GLYPH_COLORS = {
    blizzardClose = true,
    blizzardClosePressed = true,
    blizzardCloseHover = true,
    blizzardCloseDisabled = true,
    blizzardExpand = true,
    blizzardExpandPressed = true,
    blizzardExpandHover = true,
    disabled = true,
}

-- Re-applies only for what the glyphs depend on, once per frame however many
-- settings a color-picker drag writes.
function WindowActionSkin:OnThemeChanged(domain, key)
    if domain == "color" and GLYPH_COLORS[key]
        or domain == "theme" and key ~= "gradient"
        or domain == "profile" then
        NS.Registry.QueueJob(WindowActionSkin.RefreshAll)
    end
end

NS.Registry.AddListener(WindowActionSkin, WindowActionSkin.OnThemeChanged)

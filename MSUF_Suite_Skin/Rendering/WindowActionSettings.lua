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
local forever = (rawget(NS, "Client") or {}).isForever == true
local stateGetters = { normal = "GetNormalTexture", pushed = "GetPushedTexture",
    disabled = "GetDisabledTexture", highlight = "GetHighlightTexture" }

-- The close X has its own style. Older profiles may intentionally keep native
-- expand/minimize art; that choice no longer leaves the X outside our skin.
-- One read-only view is reused on these construction/settings paths. Renderers
-- copy its values into their own specs and never retain this shared view.
local closeSettings = setmetatable({}, { __index = function(options, key) return options.source[key] end })
function WindowActionSkin.ResolveSettings(kind)
    local settings = Settings()
    if kind ~= "close" then return settings end
    local style = settings.closeStyle or NS.Defaults.icons.windowActions.closeStyle
    if style == "global" then return settings end
    closeSettings.source, closeSettings.style = settings, style
    return closeSettings
end

-- Exact addon members and cooperative targets keep their action meaning in
-- Native mode too. Inferred actions still follow their current native art.
function WindowActionSkin.OrientGlyphs(glyphs, slots, cell, direction)
    if direction ~= "left" and direction ~= "right" then return end
    local l, r = cell / slots, (cell + 1) / slots
    for _, glyph in pairs(glyphs) do
        if direction == "left" then glyph:SetTexCoord(r, 0, l, 0, r, 1, l, 1)
        else glyph:SetTexCoord(l, 1, r, 1, l, 0, r, 0) end
    end
end

function WindowActionSkin.ApplyExplicit(button, owner, kind, motion, options)
    return WindowActionSkin.Apply(button, owner, kind, motion, true, options)
end

function WindowActionSkin.GetExplicitKind(button)
    local state = WindowActionSkin.GetState(button)
    return state and state.explicitKind or nil
end

function WindowActionSkin.HasOwnedStates(button)
    local state = WindowActionSkin.states[button]
    if not state or not state.glyphs or not state.nativeCaptured then return false end
    for key, getter in pairs(stateGetters) do
        if NS.Safety.Call(button, getter) ~= state.glyphs[key] then return false end
    end
    return true
end

function WindowActionSkin.Track(button, owner, kind)
    local explicit = WindowActionSkin.GetExplicitKind(button)
    if explicit then return WindowActionSkin.ApplyExplicit(button, owner, explicit) end
    kind = kind or NS.Checkmarks.GetWindowAction(button)
    return WindowActionSkin.Apply(button, owner, kind)
end

-- Owned caption cells can mirror the native button's mouse state without
-- assigning any scripts or textures to that native button.
local captionVisuals = setmetatable({}, { __mode = "k" })
local visualRevision = 0
function WindowActionSkin.ClearCaption(button)
    local visual = captionVisuals[button]
    if not visual then return end
    visual.glyph:Hide()
    if visual.surface then NS.Surface.SetVisible(button, false) end
    visual.surface, visual.surfaceRevision, visual.active = nil, nil, nil
end

function WindowActionSkin.PaintCaption(button, kind, visualState)
    if not forever then return false end
    if NS.IsCombatLocked() then return captionVisuals[button] and captionVisuals[button].active == true end
    if not NS.Safety.CanCreateRegions(button) then return false end
    local settings, visual = WindowActionSkin.ResolveSettings(kind), captionVisuals[button]
    if settings.style == "native" then
        WindowActionSkin.ClearCaption(button)
        return false
    end
    if not visual then
        visual = { glyph = button:CreateTexture(nil, "OVERLAY", nil, 6) }
        captionVisuals[button] = visual
    end
    local atlas, cell = Shared.GlyphAsset(kind, settings, true)
    local size, x, y = Shared.GlyphLayout(button, kind, settings)
    local glyph = visual.glyph
    glyph:ClearAllPoints()
    glyph:SetPoint("CENTER", button, "CENTER", x, y)
    local opacity = visualState == "normal" and settings.opacity
        or visualState == "disabled" and math.min(settings.opacity, .55) or 1
    Shared.ConfigureGlyph(glyph, atlas, cell, size, Shared.ColorRole(kind, visualState), opacity)
    if visual.surfaceRevision ~= visualRevision then
        visual.surfaceRevision = visualRevision
        if settings.style == "soft" or settings.style == "outline" then
            local spec = Shared.SurfaceSpec(settings, visual)
            spec.ownedArt, spec.interactive = true, false
            visual.surface = NS.Surface.Attach(button, spec)
        elseif visual.surface then
            NS.Surface.SetVisible(button, false)
            visual.surface = nil
        end
    end
    visual.active = true
    return true
end

function WindowActionSkin.SetOption(key, value)
    if NS.IsCombatLocked() then return false, "combat" end
    local settings = Settings()
    if key == "style" then
        if not IsListed(NS.WindowActionStyles, value) then return false, "invalid value" end
    elseif key == "closeStyle" then
        if not IsListed(NS.WindowCloseStyles, value) then return false, "invalid value" end
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
    visualRevision = visualRevision + 1
    WindowActionSkin.RefreshAll()
    NS.Registry.NotifyListeners("windowAction", key)
    return true
end

function WindowActionSkin.ResetRecommended()
    if NS.IsCombatLocked() then return false, "combat" end
    local defaults = NS.Defaults.icons.windowActions
    local settings = Settings()
    for key, value in pairs(defaults) do settings[key] = value end
    visualRevision = visualRevision + 1
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
    return { applied = count, style = Settings().style, closeStyle = Settings().closeStyle }
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
    if domain == "profile" or domain == "theme" or domain == "geometry" then
        visualRevision = visualRevision + 1
    end
    if domain == "color" and GLYPH_COLORS[key]
        or domain == "theme" and key ~= "gradient"
        or domain == "profile" then
        NS.Registry.QueueJob(WindowActionSkin.RefreshAll)
    end
end

NS.Registry.AddListener(WindowActionSkin, WindowActionSkin.OnThemeChanged)

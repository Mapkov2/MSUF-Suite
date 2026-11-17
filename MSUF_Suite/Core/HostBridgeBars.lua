local _, Suite = ...
local HostBridge = Suite.HostBridge

function HostBridge.SharedCastFillColors()
    local host = HostBridge.Namespace()
    local public = host and host.Public
    local resolve = public and public.ResolveCastbarColors or _G.MSUF_ResolveCastbarColors
    if type(resolve) == "function" then return resolve() end
end

local function CastbarValue(host, name)
    local exports = host.PublicGlobals
    local get = exports and exports[name] or _G[name]
    if type(get) == "function" then return get() end
end

local function ColorComponent(value, default)
    local number = tonumber(value)
    if Suite.Finite(number) then return math.max(0, math.min(1, number)) end
    return default
end

function HostBridge.SharedCastbarStyle()
    local host, db = HostBridge.Namespace(), HostBridge.CurrentFrameProfile()
    local g = type(db) == "table" and db.general
    if not host or type(g) ~= "table" then return end
    local bgR, bgG, bgB, bgA = CastbarValue(host, "MSUF_GetCastbarBackgroundColor")
    local textR, textG, textB = CastbarValue(host, "MSUF_GetCastbarTextColor")
    local interruptR, interruptG, interruptB = CastbarValue(host, "MSUF_ResolveInterruptFeedbackCastColor")
    local fillR, fillG, fillB, lockedR, lockedG, lockedB = HostBridge.SharedCastFillColors()
    return {
        fill = CastbarValue(host, "MSUF_GetCastbarTexture") or Suite.ResolveTexture(g.castbarTexture),
        background = CastbarValue(host, "MSUF_GetCastbarBackgroundTexture")
            or Suite.ResolveTexture(g.castbarBackgroundTexture),
        fillR = fillR, fillG = fillG, fillB = fillB, lockedR = lockedR, lockedG = lockedG, lockedB = lockedB,
        backgroundR = ColorComponent(bgR or g.castbarBgR, .10),
        backgroundG = ColorComponent(bgG or g.castbarBgG, .10),
        backgroundB = ColorComponent(bgB or g.castbarBgB, .10),
        backgroundA = ColorComponent(bgA or g.castbarBgA, .85),
        outlineSize = math.max(0, math.min(12, math.floor((tonumber(g.castbarOutlineThickness) or 1) + .5))),
        outlineR = ColorComponent(g.castbarBorderR, 0), outlineG = ColorComponent(g.castbarBorderG, 0),
        outlineB = ColorComponent(g.castbarBorderB, 0), outlineA = ColorComponent(g.castbarBorderA, 1),
        reverseFill = g.castbarFillDirection == "RTL",
        showSpark = g.castbarShowSpark == true, sparkOverflow = g.castbarSparkOverflow ~= false,
        glow = g.castbarShowGlow == true,
        artwork = g.castbarArtworkEnabled == true, artworkNamePanel = g.castbarArtworkNamePanel ~= false,
        textR = ColorComponent(textR or g.castbarFontR), textG = ColorComponent(textG or g.castbarFontG),
        textB = ColorComponent(textB or g.castbarFontB), textA = 1,
        shortenName = tonumber(g.castbarSpellNameShortening) == 1,
        nameMax = math.max(6, math.min(30, math.floor(tonumber(g.castbarSpellNameMaxLen) or 30))),
        nameReserve = math.max(0, math.min(30, tonumber(g.castbarSpellNameReservedSpace) or 8)),
        showPushback = g.castbarShowPushback == true,
        interruptR = ColorComponent(interruptR), interruptG = ColorComponent(interruptG),
        interruptB = ColorComponent(interruptB),
        interruptShake = g.castbarInterruptShake ~= false,
        shakeStrength = math.max(0, math.min(30, tonumber(g.castbarShakeStrength) or 8)),
        interruptDuration = math.max(0, math.min(5, tonumber(g.castbarInterruptFeedbackDuration) or .5)),
    }
end

local castbarWatcher
function HostBridge.ObserveSharedCastbarStyle(callback)
    if castbarWatcher then return end
    local host = HostBridge.Namespace()
    if not host then return end
    castbarWatcher = true
    local exports = host.PublicGlobals
    for _, key in ipairs({ "MSUF_Castbars_OnSettingsChanged", "MSUF_UpdateCastbarTextures_Immediate",
        "MSUF_UpdateCastbarVisuals", "MSUF_UpdateCastbarVisuals_Immediate", "MSUF_ApplyAllCastbarsAndSync" }) do
        if exports and type(exports[key]) == "function" then hooksecurefunc(exports, key, callback) end
        if type(_G[key]) == "function" then hooksecurefunc(key, callback) end
    end
    local config = host.Castbars and host.Castbars.Config
    if config and type(config.Refresh) == "function" then hooksecurefunc(config, "Refresh", callback) end
end

function HostBridge.SharedAggroBorderEnabled()
    local get = HostBridge.NameplateSettingsGetter()
    local settings = type(get) == "function" and get()
    local read = type(settings) == "table" and settings.version == 1 and settings.SharedAggroBorderEnabled
    if type(read) == "function" then return read() end
    local db = HostBridge.CurrentFrameProfile()
    local general = type(db) == "table" and db.general
    if type(general) ~= "table" then return end
    local mode = general.aggroOutlineMode
    if type(mode) == "boolean" then return mode end
    mode = tonumber(mode)
    if mode then return mode == 1 end
    return general.aggroIndicatorMode == "border" or general.enableAggroHighlight ~= false
end

local function RGBHex(r, g, b, fallback)
    if not (Suite.Finite(r) and Suite.Finite(g) and Suite.Finite(b)) then return fallback end
    local function Byte(value) return math.floor(math.max(0, math.min(1, value)) * 255 + .5) end
    return ("%02x%02x%02x"):format(Byte(r), Byte(g), Byte(b))
end

local function ReadBarFinish(out, uf, general, kind)
    local prefix = kind .. "Gradient"
    local gradient = uf.ResolveBarGradient(nil, general, kind == "power" and "enablePowerGradient" or "enableGradient")
    out[prefix .. "Enabled"], out[prefix .. "Strength"] = gradient.enabled, gradient.strength * 100
    out[prefix .. "Color"] = RGBHex(gradient.r, gradient.g, gradient.b, "000000")
    out[prefix .. "DirLeft"], out[prefix .. "DirRight"] = gradient.left, gradient.right
    out[prefix .. "DirUp"], out[prefix .. "DirDown"] = gradient.up, gradient.down
    if uf.ResolveBarGloss then
        local gloss = uf.ResolveBarGloss(nil, general, kind)
        out[kind .. "GlossEnabled"], out[kind .. "GlossStrength"] = gloss.enabled, gloss.strength * 100
    end
end

function HostBridge.SharedNameplateAbsorbs()
    local db = HostBridge.CurrentFrameProfile()
    local g = type(db) == "table" and db.general
    if type(g) ~= "table" then return end
    local mode = tonumber(g.absorbTextMode)
    local positive = g.enableAbsorbBar
    if positive == nil then positive = mode == nil or mode == 2 or mode == 3 end
    local fallback = Suite.ResolveTexture(g.barTexture or "Blizzard")
    return {
        r = ColorComponent(g.absorbBarColorR, 1), g = ColorComponent(g.absorbBarColorG, 1),
        b = ColorComponent(g.absorbBarColorB, 1),
        a = positive ~= false and ColorComponent(g.absorbBarOpacity or g.absorbBarColorA, .75) or 0,
        texture = Suite.ResolveTexture(g.absorbBarTexture, fallback),
    }, {
        r = ColorComponent(g.healAbsorbBarColorR, .7), g = ColorComponent(g.healAbsorbBarColorG, 0),
        b = ColorComponent(g.healAbsorbBarColorB, 0),
        a = g.healAbsorbEnabled ~= false and ColorComponent(g.healAbsorbBarOpacity or g.healAbsorbBarColorA, 1) or 0,
        texture = Suite.ResolveTexture(g.healAbsorbBarTexture, fallback),
    }
end

function HostBridge.SharedNameplateBars()
    local host, db = HostBridge.Namespace(), HostBridge.CurrentFrameProfile()
    local uf = host and host.UF
    local general = type(db) == "table" and db.general
    if not uf or not uf.ResolveBarGradient or type(general) ~= "table" then return end
    local bars = type(db.bars) == "table" and db.bars or {}
    local fill = general.barTexture or "Blizzard"
    local back = general.barBackgroundTexture or general.barBgTexture
    if not back or back == "" then back = fill end
    local out = {
        nativeHealthFillTexture = fill,
        nativeHealthBackgroundTexture = back,
        powerFillTexture = type(bars.powerBarTexture) == "string" and bars.powerBarTexture ~= "" and bars.powerBarTexture or fill,
        powerBackgroundTexture = type(bars.powerBarBgTexture) == "string" and bars.powerBarBgTexture ~= "" and bars.powerBarBgTexture or back,
    }
    local thickness = math.max(0, math.min(6, tonumber(bars.barOutlineThickness)
        or (general.useBarBorder == false and 0 or 1)))
    local outline = bars.showBarBorder ~= false and thickness > 0
    local outlineColor = RGBHex(general.barOutlineColorR or general.barBorderR,
        general.barOutlineColorG or general.barBorderG, general.barOutlineColorB or general.barBorderB, "000000")
    out.enemyOutlineMode, out.friendlyOutlineMode = outline and 3 or 4, outline and 3 or 4
    out.enemyBorderSize, out.friendlyBorderSize = math.max(1, thickness), math.max(1, thickness)
    out.enemyBorderColor, out.friendlyBorderColor = outlineColor, outlineColor
    out.hideHealthBarBorders = false
    out.highlightBorderSize = math.max(1, math.min(30, tonumber(general.highlightBorderThickness
        or bars.highlightBorderThickness) or thickness))
    out.highlightAggroColor = RGBHex(general.hlAggroColorR or general.aggroBorderColorR or general.aggroBorderR or 1,
        general.hlAggroColorG or general.aggroBorderColorG or general.aggroBorderG or .55,
        general.hlAggroColorB or general.aggroBorderColorB or general.aggroBorderB or 0, "ff8c00")
    ReadBarFinish(out, uf, general, "health")
    ReadBarFinish(out, uf, general, "power")
    return out
end

local barsWatchers
function HostBridge.ObserveSharedNameplateBars(callback)
    if barsWatchers then return end
    local host = HostBridge.Namespace()
    if not host then return end
    barsWatchers = true
    local function Changed(scope)
        if not scope or scope == "shared" or scope == "*" or scope == "all" or scope == "global" then callback() end
    end
    local public = host.PublicGlobals
    for _, key in ipairs({ "MSUF_UpdateAllBarTextures_Immediate", "MSUF_UpdateAllBarGradients",
        "MSUF_ApplyBarOutlineThickness_All", "MSUF_RefreshAllFrameColors" }) do
        if public and type(public[key]) == "function" then hooksecurefunc(public, key, Changed) end
        if type(_G[key]) == "function" then hooksecurefunc(key, Changed) end
    end
    local uf = host.UF
    if uf and type(uf.RefreshBorders) == "function" then hooksecurefunc(uf, "RefreshBorders", Changed) end
    if uf and type(uf.RefreshColors) == "function" then hooksecurefunc(uf, "RefreshColors", Changed) end
    local colors = host.Public and host.Public.Colors or host._colorsAPI
    if colors then
        for _, key in ipairs({ "SetAbsorbOverlayColor", "SetHealAbsorbOverlayColor" }) do
            if type(colors[key]) == "function" then hooksecurefunc(colors, key, callback) end
        end
    end
end

function HostBridge.LiveHealthStyle(owner, detached)
    local host = HostBridge.Namespace()
    local common = host and host.UFBarTextCommon
    if not common then return end
    local spec = owner.MSUFSpec
    local health = spec and spec.health
    local tint = health and health.mode == "gradient" and common.PreviewHealthGradientColor or nil
    if detached then
        local db = HostBridge.CurrentFrameProfile()
        local config = db and db.bars
        local mode = config and tostring(config.playerHPBarColorMode or "GLOBAL"):upper()
        if mode == "GRADIENT" then return common.PreviewHealthGradientColor end
        if mode == "CLASS" or mode == "DARK" then return end
        return tint, health
    end
    return tint, health, common.ApplyBarGradient, owner.hpGradients
end

local function VisitUnitBars(frame, _, _, kind, visit)
    if not Suite.Public(frame) or frame:IsForbidden() then return end
    if kind ~= "power" then visit(frame.Health or frame.hpBar, frame, "health") end
    if kind ~= "health" then visit(frame.Power or frame.powerBar, frame, "power") end
end

local function VisitResourceChildren(visit, owner, kind, depth, ...)
    for i = 1, select("#", ...) do
        local child = select(i, ...)
        if Suite.Public(child) and not child:IsForbidden() then
            local visible = child:IsVisible()
            if Suite.Public(visible) and visible then
                if child:IsObjectType("StatusBar") then
                    visit(child, owner, kind)
                elseif depth > 0 then
                    VisitResourceChildren(visit, owner, kind, depth - 1, child:GetChildren())
                end
            end
        end
    end
end

local function VisitResources(parent, visit, kind, depth)
    if parent then VisitResourceChildren(visit, parent, kind, depth, parent:GetChildren()) end
end

local function VisitCastBar(frame, visit)
    if frame then visit(frame.statusBar, frame, "cast") end
end

function HostBridge.IsBarPreviewActive()
    local host = HostBridge.Namespace()
    local public = host and host.PublicGlobals
    return _G.MSUF_UnitEditModeActive == true or _G.MSUF_UnitPreviewActive == true
        or (public and public.MSUF_UnitPreviewActive == true)
end

-- Read-only, user-initiated discovery. Only the registered gameplay frames
-- and the named MSUF resource/timer owners participate.
function HostBridge.VisitLiveBars(kind, visit)
    local host = HostBridge.Namespace()
    if kind == "all" or kind == "health" or kind == "power" then
        local uf, gf = host and host.UF, host and host.GF
        if uf then uf.ForEachFrame(VisitUnitBars, nil, kind, visit) end
        if gf then gf.ForEachFrame(VisitUnitBars, false, kind, visit) end
        if kind ~= "power" then VisitResources(_G.MSUF_ClassPowerPlayerHealthBar, visit, "playerHealth", 0) end
        if kind ~= "health" then VisitResources(_G.MSUF_AltManaContainer, visit, "mana", 0) end
    end
    if kind == "all" or kind == "class" then
        VisitResources(_G.MSUF_ClassPowerContainer, visit, "class", 3)
    end
    if kind == "all" or kind == "cast" then
        local public = host and host.PublicGlobals
        local boss = _G.MSUF_BossCastbars or (public and public.MSUF_BossCastbars)
        local arena = _G.MSUF_ArenaCastbars or (public and public.MSUF_ArenaCastbars)
        VisitCastBar(_G.MSUF_PlayerCastBar, visit)
        VisitCastBar(_G.MSUF_TargetCastBar, visit)
        VisitCastBar(_G.MSUF_FocusCastBar, visit)
        VisitCastBar(_G.MSUF_DetachedGCDBar, visit)
        if boss then for _, frame in ipairs(boss) do VisitCastBar(frame, visit) end end
        if arena then for _, frame in ipairs(arena) do VisitCastBar(frame, visit) end end
    end
    if kind == "all" or kind == "swing" then
        local main, off, ranged = _G.MSUF_SwingTimer_main, _G.MSUF_SwingTimer_off, _G.MSUF_SwingTimer_ranged
        if main then visit(main.Bar, main, "swing") end
        if off then
            visit(off.Bar, off, "swing")
            visit(off.Lane, off, "swing")
        end
        if ranged then visit(ranged.Bar, ranged, "swing") end
    end
end

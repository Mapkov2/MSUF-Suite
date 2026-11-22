local _, private = ...
local NS = private.NS
local SAME_GEOMETRY = private.Mode.SAME_GEOMETRY
local Key = private.Key
local G = {}
private.Geometry = G

-- Every anchor the Suite writes on a plate snaps to physical pixels
-- (PixelUtil, Blizzard_SharedXMLBase on Retail and Forever).
function G.Point(region, point, owner, relative, x, y)
    PixelUtil.SetPoint(region, point, owner, relative, x, y)
end

-- Whether the native level badge (PlayerLevelDiffFrame) holds its space on
-- this plate; nil while that is unknown. On Retail that is its shown state.
-- Forever reserves the space whenever Camelot's
-- NameplateLevelFrameMixin:ShouldDisplay (upstream/forever
-- Blizzard_NamePlates/Camelot) allows the badge, also while it is hidden for
-- a moment. The same rule is evaluated here from the public unit predicates,
-- so no Blizzard method runs in addon code and a restricted answer reads as
-- unknown.
function G.LevelBadgeShown(uf, unit)
    local badge = uf.PlayerLevelDiffFrame
    if not badge then return false end
    if NS.Safety.IsForbidden(badge) then return nil end
    if not NS.Client.isForever then
        local shown = badge:IsShown()
        if NS.Public(shown) then return shown end
        return nil
    end
    if not unit then return false end
    local object = UnitIsGameObject(unit)
    if not NS.Public(object) then return nil end
    if object then return false end
    local friend, player = UnitIsFriend("player", unit), UnitIsPlayer(unit)
    if not NS.Public(friend) or not NS.Public(player) then return nil end
    if friend and player then
        return not C_CVar.GetCVarBool("nameplateShowOnlyNameForFriendlyPlayerUnits")
    end
    return true
end

-- Never measure restricted frames. These bases are public setup values from
-- Blizzard_NamePlateUnitFrame:UpdateAnchors on upstream/live and forever.
function G.LevelReserve(uf, setup)
    if not NS.Client.isForever then return 0 end
    local shown = G.LevelBadgeShown(uf, uf.unit)
    if shown == nil then return nil end
    if not shown then return 0 end
    if NS.Finite(setup.playerLevelDiffWidth) then return setup.playerLevelDiffWidth + 5 end
end

-- The native name points from Blizzard_NamePlateUnitFrame:UpdateAnchors.
-- They can be restored even when FrameMeasurement is blocked for the label.
local function NativeNamePoints(uf, setup, badgeShown)
    local container = uf.HealthBarsContainer
    local health = container and container.healthBar
    local healthText = health and health.Text
    if not healthText or NS.Safety.IsForbidden(healthText) then return end
    local style, spacing = setup.unitNameAnchorStyle, setup.healthBarToNameAboveSpacing
    if uf.showOnlyName then
        if style == 1 then return { { "LEFT", container, "LEFT", 4, 0 }, { "RIGHT", container, "RIGHT", -4, 0 } } end
        return { { "BOTTOMLEFT", container, "TOPLEFT", 4, 2 }, { "BOTTOMRIGHT", container, "TOPRIGHT", -4, 2 } }
    end
    if style == 1 then return { { "LEFT", container, "LEFT", 4, 0 }, { "RIGHT", healthText, "LEFT", -2, 0 } } end
    if style == 3 then return { { "BOTTOM", container, "TOP", 0, spacing } } end
    if style ~= 2 then return end
    if not NS.Client.isForever then
        return { { "BOTTOMLEFT", container, "TOPLEFT", 4, spacing }, { "BOTTOMRIGHT", healthText, "BOTTOMLEFT", -2, 0 } }
    end
    local inside = setup.healthTextInsideBarWhenNameAboveHealthBar
    if not NS.Public(inside) or type(inside) ~= "boolean" or badgeShown == nil then return end
    local right = badgeShown and { "RIGHT", uf.PlayerLevelDiffFrame, "RIGHT", 0, 0 }
        or inside and { "RIGHT", container, "RIGHT", 0, 0 } or { "RIGHT", healthText, "LEFT", -2, 0 }
    return { { "BOTTOMLEFT", container, "TOPLEFT", 0, spacing }, right }
end

function G.CenterName(uf, setup, healthHeight, offsetY, badgeShown)
    local label, cast = uf.name, uf.CastBarsContainer
    local spacing, gap = setup.castBarToHealthBarSpacing, setup.healthBarToNameAboveSpacing
    if not cast or NS.Safety.IsForbidden(cast) or not NS.Finite(healthHeight)
        or not NS.Finite(spacing) or not NS.Finite(gap) then return end
    local access, justify = cast:CanBeAccessedInContext(), label:GetJustifyH()
    if not NS.Public(access) or access ~= true or not NS.Public(justify) or type(justify) ~= "string" then return end
    local points = NativeNamePoints(uf, setup, badgeShown)
    if not points then return end
    local y = spacing + healthHeight + (uf.showOnlyName and 2 or gap) + offsetY
    -- The native cast container is centered on the plate. The health
    -- container can be narrower on the right to accommodate the level badge.
    label:ClearAllPoints()
    label:SetPoint("BOTTOMLEFT", cast, "TOPLEFT", 4, y)
    label:SetPoint("BOTTOMRIGHT", cast, "TOPRIGHT", -4, y)
    label:SetJustifyH("CENTER")
    return { native = true, points = points, justify = justify }
end

-- The plate width constants carry different names on Retail
-- (NAMEPLATE_WIDTH, CLASSIC_NAMEPLATE_WIDTH) and on Forever (Camelot's
-- NAME_PLATE_WIDTH, CLASSIC_NAME_PLATE_WIDTH).
local function NativeWidth(classic)
    local constants = NamePlateConstants
    if classic then return constants.CLASSIC_NAMEPLATE_WIDTH or constants.CLASSIC_NAME_PLATE_WIDTH end
    return constants.NAMEPLATE_WIDTH or constants.NAME_PLATE_WIDTH
end

-- Native cast and health share the horizontal insets. The health bar also
-- reserves the level badge and can have its own width delta.
function G.CastWidthDelta(uf, setup, config, prefix, healthDelta)
    local p = prefix .. "Cast"
    local mode = config[p .. "WidthMode"] or 1
    if mode == 1 then return config[p .. "WidthDelta"] or 0 end
    local style, scale = NS.NameplateStyle, setup.horizontalScale
    if not NS.Finite(scale) or not NS.Finite(setup.insetWidth) or not NS.Finite(setup.verticalScale)
        or not NS.Public(setup.useClassicHealthBar) then return end
    local classic = setup.useClassicHealthBar == true
    local total = style.BarDimensions(config.barGeometry, config.nativeStyle, scale, setup.verticalScale)
    local reserve = total and 0 or G.LevelReserve(uf, setup)
    local nativeWidth = NativeWidth(classic)
    if not reserve or not NS.Finite(nativeWidth) then return end
    local width = total or nativeWidth * scale
    local base = width - 2 * setup.insetWidth - (setup.useClassicCastBar and 24.25 * scale or 0)
    local health = width - 2 * setup.insetWidth - (classic and 24.25 * scale or 0) - reserve + healthDelta
    return style.CastWidth(base, health, mode, config[p .. "ManualWidth"] or 160, 0) - base
end

function G.RestoreIconZoom(state)
    local zoom = state.iconZoom
    if not zoom then return true end
    local icon = zoom.icon
    if NS.Safety.IsForbidden(icon) then return false end
    local accessible = icon:CanBeAccessedInContext()
    if not NS.Public(accessible) or not accessible then return false end
    icon:SetTexCoord(unpack(zoom.coords))
    state.iconZoom = nil
    return true
end

local castIconBorders = setmetatable({}, { __mode = "k" })
local function SyncCastIconBorder(cast)
    local border = castIconBorders[cast]
    if not border or NS.Safety.IsForbidden(cast) or NS.Safety.IsForbidden(border.icon) then return end
    if not border.enabled then return end
    local accessible = border.icon:CanBeAccessedInContext()
    if not NS.Public(accessible) or not accessible then
        border.host:Hide()
        return
    end
    local shown = border.icon:IsShown()
    border.host:SetShown(NS.Public(shown) and shown == true)
end

function G.HideCastIconBorder(state)
    local border = state.castIconBorder
    if border then
        border.enabled = false
        border.host:Hide()
    end
    state.castIconStyle = nil
end

local function GetCastIconBorder(cast, icon)
    local border = castIconBorders[cast]
    if not border then
        local host = CreateFrame("Frame", nil, cast)
        host:SetAllPoints(icon)
        border = NS.NameplateStyle.CreateBorder(host)
        border.host, border.icon = host, icon
        castIconBorders[cast] = border
        hooksecurefunc(cast, "UpdateIconShown", SyncCastIconBorder)
    end
    return border
end

function G.CastIconZoom(state, cast, percent)
    if not percent then return G.RestoreIconZoom(state) end
    if not cast or NS.Safety.IsForbidden(cast) then return false end
    local icon = cast.Icon
    if not icon or NS.Safety.IsForbidden(icon) then return false end
    local accessible = icon:CanBeAccessedInContext()
    if not NS.Public(accessible) or not accessible then return false end
    local zoom = state.iconZoom
    if not zoom then
        local coords = { icon:GetTexCoord() }
        if #coords ~= 8 then return false end
        for _, value in ipairs(coords) do if not NS.Finite(value) then return false end end
        zoom = { icon = icon, coords = coords }
        state.iconZoom = zoom
    end
    if zoom.percent == percent then return true end
    local c, scale = zoom.coords, 100 / percent
    local x, y = (c[1] + c[3] + c[5] + c[7]) / 4, (c[2] + c[4] + c[6] + c[8]) / 4
    icon:SetTexCoord(x + (c[1] - x) * scale, y + (c[2] - y) * scale, x + (c[3] - x) * scale, y + (c[4] - y) * scale,
        x + (c[5] - x) * scale, y + (c[6] - y) * scale, x + (c[7] - x) * scale, y + (c[8] - y) * scale)
    zoom.percent = percent
    return true
end

function G.CastIconStyle(state, uf, plan)
    local cast = uf.CastBarsContainer and uf.CastBarsContainer.castBar
    if not G.CastIconZoom(state, cast, plan.iconZoom) then return false end
    if plan.iconBorder then
        if not cast or NS.Safety.IsForbidden(cast) then return false end
        local icon = cast.Icon
        if not icon or NS.Safety.IsForbidden(icon) then return false end
        local accessible = icon:CanBeAccessedInContext()
        if not NS.Public(accessible) or not accessible then return false end
        local border = GetCastIconBorder(cast, icon)
        state.castIconBorder = border
        NS.NameplateStyle.PaintBorder(border, icon, plan.iconBorder, plan.iconBorderColor)
        border.enabled = true
        SyncCastIconBorder(cast)
    elseif state.castIconBorder then
        G.HideCastIconBorder(state)
    end
    state.castIconStyle = plan.castIconStyle
    return true
end

local SETUP_NUMBERS = { "insetWidth", "castBarToHealthBarSpacing", "healthBarHeight",
    "castBarHeight", "castIconWidth", "castIconHeight", "horizontalScale", "verticalScale" }
local function Ready(uf, setup)
    local container, health = uf.CastBarsContainer, uf.HealthBarsContainer
    if not container or not health or NS.Safety.IsForbidden(container) or NS.Safety.IsForbidden(health) then return end
    local cast = container.castBar
    if not cast or NS.Safety.IsForbidden(cast) or not cast.Icon or NS.Safety.IsForbidden(cast.Icon) then return end
    for _, key in ipairs(SETUP_NUMBERS) do
        if not NS.Finite(setup[key]) then return end
    end
    return container, health, cast
end

local function CastSize(container, cast, setup, height, iconWidth, iconHeight, old, force)
    local inside = setup.spellNameInsideCastBar
    local previousHeight = old and old.castHeight or setup.castBarHeight
    local previousIconHeight = old and old.iconHeight or setup.castIconHeight
    if force or height + (inside and 0 or iconHeight) ~= previousHeight + (inside and 0 or previousIconHeight) then
        container:SetHeight(height + (inside and 0 or iconHeight))
    end
    if force or height ~= previousHeight then cast:SetHeight(height) end
    if force or iconWidth ~= (old and old.iconWidth or setup.castIconWidth) or iconHeight ~= previousIconHeight then
        cast.Icon:SetSize(iconWidth, iconHeight)
    end
end

local function CastBorderSize(cast, setup, width, height)
    if not setup.useClassicCastBar then return true end
    local border = cast.Border
    if not border or NS.Safety.IsForbidden(border) or not NS.Finite(setup.castBarBorderWidth)
        or not NS.Finite(setup.castBarBorderHeight) then return false end
    border:SetSize(setup.castBarBorderWidth + width, setup.castBarBorderHeight + height)
    return true
end

function G.Restore(state, uf, setup)
    local old = state.geometry
    if not old then return true end
    local container, health, cast = Ready(uf, setup)
    if not container then return false end
    local reserve = old.inset and G.LevelReserve(uf, setup)
    if old.inset and not reserve then return false end
    if old.borderWidth and not CastBorderSize(cast, setup, 0, 0) then return false end
    if old.inset then
        G.Point(container, "BOTTOMLEFT", uf, "BOTTOMLEFT", setup.insetWidth, 0)
        G.Point(container, "BOTTOMRIGHT", uf, "BOTTOMRIGHT", -setup.insetWidth, 0)
        G.Point(health, "BOTTOMRIGHT", container, "TOPRIGHT", -reserve, setup.castBarToHealthBarSpacing)
        health:SetHeight(setup.healthBarHeight)
    end
    CastSize(container, cast, setup, setup.castBarHeight, setup.castIconWidth, setup.castIconHeight, old)
    state.geometry = nil
    return true
end

function G.Apply(state, uf, setup, config, force, prefix, width)
    local keys, old = Key[prefix], state.geometry
    local height, icon = config[keys.CastHeight] or 0, config[keys.CastIconSize] or 0
    width = width or config[keys.CastWidthDelta] or 0
    local uniform = config.barGeometry == SAME_GEOMETRY
    local classicBorder = setup.useClassicCastBar and (width ~= 0 or height ~= 0)
    local customCast = height ~= 0 or icon ~= 0 or classicBorder
    if not uniform and (not customCast or old and old.inset ~= nil) then
        if not G.Restore(state, uf, setup) then return end
        if not customCast then return setup.healthBarHeight end
        old = nil
    end
    local container, health, cast = Ready(uf, setup)
    if not container then return end
    local inset, healthHeight = nil, setup.healthBarHeight
    local castHeight, iconWidth, iconHeight = setup.castBarHeight, setup.castIconWidth, setup.castIconHeight
    if uniform then
        local totalWidth
        totalWidth, healthHeight, castHeight, iconHeight = NS.NameplateStyle.BarDimensions(
            config.barGeometry, config.nativeStyle, setup.horizontalScale, setup.verticalScale)
        local nativeWidth = NativeWidth(setup.useClassicHealthBar == true)
        if not NS.Finite(nativeWidth) then return end
        inset = setup.insetWidth + (nativeWidth * setup.horizontalScale - totalWidth) / 2
        iconWidth = iconHeight
    end
    castHeight, iconWidth, iconHeight = NS.NameplateStyle.CastDimensions(height, icon, castHeight, iconWidth, iconHeight)
    local borderWidth = classicBorder and width or nil
    if force or not old or old.inset ~= inset or old.healthHeight ~= healthHeight or old.castHeight ~= castHeight
        or old.iconWidth ~= iconWidth or old.iconHeight ~= iconHeight or old.borderWidth ~= borderWidth then
        if (borderWidth or old and old.borderWidth)
            and (force or not old or old.borderWidth ~= borderWidth or old.castHeight ~= castHeight) then
            local borderHeight = borderWidth and castHeight - setup.castBarHeight or 0
            if not CastBorderSize(cast, setup, borderWidth or 0, borderHeight) then return end
        end
        if inset then
            G.Point(container, "BOTTOMLEFT", uf, "BOTTOMLEFT", inset, 0)
            G.Point(container, "BOTTOMRIGHT", uf, "BOTTOMRIGHT", -inset, 0)
            -- The level badge remains a separate element and cannot shrink the bar.
            G.Point(health, "BOTTOMRIGHT", container, "TOPRIGHT", 0, setup.castBarToHealthBarSpacing)
            if force or not old or old.inset == nil or old.healthHeight ~= healthHeight then health:SetHeight(healthHeight) end
        end
        CastSize(container, cast, setup, castHeight, iconWidth, iconHeight, old, force)
        old = old or {}
        old.inset, old.healthHeight, old.castHeight = inset, healthHeight, castHeight
        old.iconWidth, old.iconHeight, old.borderWidth = iconWidth, iconHeight, borderWidth
        state.geometry = old
    end
    return healthHeight
end

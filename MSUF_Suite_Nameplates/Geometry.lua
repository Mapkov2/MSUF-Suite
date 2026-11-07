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

-- The plate width constants carry different names on Retail
-- (NAMEPLATE_WIDTH, CLASSIC_NAMEPLATE_WIDTH) and on Forever (Camelot's
-- NAME_PLATE_WIDTH, CLASSIC_NAME_PLATE_WIDTH).
local function NativeWidth(classic)
    local constants = NamePlateConstants
    if classic then return constants.CLASSIC_NAMEPLATE_WIDTH or constants.CLASSIC_NAME_PLATE_WIDTH end
    return constants.NAMEPLATE_WIDTH or constants.NAME_PLATE_WIDTH
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

local function CastSize(container, cast, inside, height, iconWidth, iconHeight)
    container:SetHeight(height + (inside and 0 or iconHeight))
    cast:SetHeight(height)
    cast.Icon:SetSize(iconWidth, iconHeight)
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
    CastSize(container, cast, setup.spellNameInsideCastBar, setup.castBarHeight, setup.castIconWidth, setup.castIconHeight)
    state.geometry = nil
    return true
end

function G.Apply(state, uf, setup, config, force, prefix)
    local keys, old = Key[prefix], state.geometry
    local height, icon, width = config[keys.CastHeight] or 0, config[keys.CastIconSize] or 0, config[keys.CastWidthDelta] or 0
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
        if borderWidth or old and old.borderWidth then
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
        CastSize(container, cast, setup.spellNameInsideCastBar, castHeight, iconWidth, iconHeight)
        old = old or {}
        old.inset, old.healthHeight, old.castHeight = inset, healthHeight, castHeight
        old.iconWidth, old.iconHeight, old.borderWidth = iconWidth, iconHeight, borderWidth
        state.geometry = old
    end
    return healthHeight
end

local _, private = ...
local NS = private.NS
local SAME_GEOMETRY = private.Mode.SAME_GEOMETRY
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

function G.Restore(state, uf, setup)
    if not state.geometry then return true end
    local container, health, cast = Ready(uf, setup)
    local reserve = G.LevelReserve(uf, setup)
    if not container or not reserve then return false end
    G.Point(container, "BOTTOMLEFT", uf, "BOTTOMLEFT", setup.insetWidth, 0)
    G.Point(container, "BOTTOMRIGHT", uf, "BOTTOMRIGHT", -setup.insetWidth, 0)
    G.Point(health, "BOTTOMRIGHT", container, "TOPRIGHT", -reserve, setup.castBarToHealthBarSpacing)
    health:SetHeight(setup.healthBarHeight)
    container:SetHeight(setup.castBarHeight + (setup.spellNameInsideCastBar and 0 or setup.castIconHeight))
    cast:SetHeight(setup.castBarHeight)
    cast.Icon:SetSize(setup.castIconWidth, setup.castIconHeight)
    state.geometry = nil
    return true
end

function G.Apply(state, uf, setup, config, force)
    if config.barGeometry ~= SAME_GEOMETRY then
        return G.Restore(state, uf, setup) and setup.healthBarHeight or nil
    end
    local container, health, cast = Ready(uf, setup)
    if not container then return end
    local totalWidth, healthHeight, castHeight, iconHeight = NS.NameplateStyle.BarDimensions(
        config.barGeometry, config.nativeStyle, setup.horizontalScale, setup.verticalScale)
    local nativeWidth = NativeWidth(setup.useClassicHealthBar == true)
    if not NS.Finite(nativeWidth) then return end
    local inset = setup.insetWidth + (nativeWidth * setup.horizontalScale - totalWidth) / 2
    local old = state.geometry
    if force or not old or old[1] ~= inset or old[2] ~= healthHeight or old[3] ~= castHeight or old[4] ~= iconHeight then
        G.Point(container, "BOTTOMLEFT", uf, "BOTTOMLEFT", inset, 0)
        G.Point(container, "BOTTOMRIGHT", uf, "BOTTOMRIGHT", -inset, 0)
        -- The level badge remains a separate element and cannot shrink the bar.
        G.Point(health, "BOTTOMRIGHT", container, "TOPRIGHT", 0, setup.castBarToHealthBarSpacing)
        health:SetHeight(healthHeight)
        container:SetHeight(castHeight + (setup.spellNameInsideCastBar and 0 or iconHeight))
        cast:SetHeight(castHeight)
        cast.Icon:SetSize(iconHeight, iconHeight)
        old = old or {}
        old[1], old[2], old[3], old[4] = inset, healthHeight, castHeight, iconHeight
        state.geometry = old
    end
    return healthHeight
end

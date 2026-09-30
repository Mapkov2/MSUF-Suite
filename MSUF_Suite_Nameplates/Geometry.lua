local _, private = ...
local NS = private.NS
local G = {}
private.Geometry = G

local function Point(region, point, owner, relative, x, y)
    if PixelUtil and PixelUtil.SetPoint then PixelUtil.SetPoint(region, point, owner, relative, x, y)
    else region:SetPoint(point, owner, relative, x, y) end
end

-- Never measure restricted frames. These bases are public setup values from
-- Blizzard_NamePlateUnitFrame:UpdateAnchors on upstream/live and forever.
function G.LevelReserve(uf, setup)
    if not NS.Client.isForever then return 0 end
    local level = uf.PlayerLevelDiffFrame
    if not level or NS.Safety.IsForbidden(level) then return end
    local shown
    if type(level.ShouldDisplay) == "function" then
        local ok, value = pcall(level.ShouldDisplay, level, uf.unit)
        if not ok then return end
        shown = value
    else shown = level:IsShown() end
    if not NS.Public(shown) then return end
    if not shown then return 0 end
    if NS.Finite(setup.playerLevelDiffWidth) then return setup.playerLevelDiffWidth + 5 end
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
    Point(container, "BOTTOMLEFT", uf, "BOTTOMLEFT", setup.insetWidth, 0)
    Point(container, "BOTTOMRIGHT", uf, "BOTTOMRIGHT", -setup.insetWidth, 0)
    Point(health, "BOTTOMRIGHT", container, "TOPRIGHT", -reserve, setup.castBarToHealthBarSpacing)
    health:SetHeight(setup.healthBarHeight)
    container:SetHeight(setup.castBarHeight + (setup.spellNameInsideCastBar and 0 or setup.castIconHeight))
    cast:SetHeight(setup.castBarHeight)
    cast.Icon:SetSize(setup.castIconWidth, setup.castIconHeight)
    state.geometry = nil
    return true
end

function G.Apply(state, uf, setup, config, force)
    if config.barGeometry ~= 2 then
        return G.Restore(state, uf, setup) and setup.healthBarHeight or nil
    end
    local container, health, cast = Ready(uf, setup)
    if not container then return end
    local totalWidth, healthHeight, castHeight, iconHeight = NS.NameplateStyle.BarDimensions(
        config.barGeometry, config.nativeStyle, setup.horizontalScale, setup.verticalScale)
    local constants = _G.NamePlateConstants or {}
    local classic = setup.useClassicHealthBar == true
    local nativeWidth = classic and (constants.CLASSIC_NAME_PLATE_WIDTH or constants.CLASSIC_NAMEPLATE_WIDTH or 152)
        or constants.NAME_PLATE_WIDTH or constants.NAMEPLATE_WIDTH or (NS.Client.isForever and 190 or 230)
    if not NS.Finite(nativeWidth) then return end
    local inset = setup.insetWidth + (nativeWidth * setup.horizontalScale - totalWidth) / 2
    local old = state.geometry
    if force or not old or old[1] ~= inset or old[2] ~= healthHeight or old[3] ~= castHeight or old[4] ~= iconHeight then
        Point(container, "BOTTOMLEFT", uf, "BOTTOMLEFT", inset, 0)
        Point(container, "BOTTOMRIGHT", uf, "BOTTOMRIGHT", -inset, 0)
        -- The level badge remains a separate element and cannot shrink the bar.
        Point(health, "BOTTOMRIGHT", container, "TOPRIGHT", 0, setup.castBarToHealthBarSpacing)
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

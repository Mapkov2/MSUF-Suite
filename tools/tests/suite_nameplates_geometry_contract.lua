local root = assert(arg[1])
local combat, style, calls = false, 0, 0
local NS = {
    Client = { isMainline = true, isForever = false },
    Public = function(v) return v ~= "secret" end,
    Finite = function(v) return type(v) == "number" and v == v end,
    IsCombatLocked = function() return combat end,
    Safety = { IsForbidden = function(r) return r.forbidden == true end },
}
C_CVar = { GetCVar = function() return tostring(style) end, GetCVarBool = function() return false end }
-- Blizzard_SharedXMLBase PixelUtil; the pixel snap itself is the engine's.
PixelUtil = { SetPoint = function(region, ...) region:SetPoint(...) end }
-- The plate is a hostile NPC: Forever's level badge rule shows the badge.
UnitIsGameObject = function(unit) assert(unit == "nameplate1"); return false end
UnitIsFriend = function(_, unit) assert(unit == "nameplate1"); return false end
UnitIsPlayer = function(unit) assert(unit == "nameplate1"); return false end
local private = { NS = NS }
assert(loadfile(root .. "/MSUF_Suite/Core/SuiteCatalog.lua"))("MSUF_Suite", NS)
assert(loadfile(root .. "/MSUF_Suite/Core/NameplateStyle.lua"))("MSUF_Suite", NS)
assert(loadfile(root .. "/MSUF_Suite_Nameplates/Modes.lua"))("MSUF_Suite_Nameplates", private)
assert(loadfile(root .. "/MSUF_Suite_Nameplates/Geometry.lua"))("MSUF_Suite_Nameplates", private)
assert(loadfile(root .. "/MSUF_Suite_Nameplates/Layout.lua"))("MSUF_Suite_Nameplates", private)
local function Frame()
    local f = { points = {} }
    function f:SetPoint(point, owner, relative, x, y)
        calls = calls + 1
        self.points[point] = { owner, relative, x, y }
    end
    function f:SetHeight(h) calls = calls + 1; self.height = h end
    function f:SetSize(w, h) calls = calls + 1; self.width, self.height = w, h end
    function f:SetPointsOffset(x, y) calls = calls + 1; self.x, self.y = x, y end
    function f:IsShown() return self.shown end
    function f:GetPoint() error("restricted anchor read") end
    function f:GetWidth() error("restricted dimension read") end
    return f
end
hooksecurefunc = function(uf, method, callback) uf.hook = callback end
local module = { active = true, levelLabels = {}, castTimes = {} }
private.Layout.Bind(module)
local setup
local function Native(uf)
    local cast, health = uf.CastBarsContainer, uf.HealthBarsContainer
    cast:SetPoint("BOTTOMLEFT", uf, "BOTTOMLEFT", setup.insetWidth, 0)
    cast:SetPoint("BOTTOMRIGHT", uf, "BOTTOMRIGHT", -setup.insetWidth, 0)
    health:SetPoint("BOTTOMLEFT", cast, "TOPLEFT", 0, setup.castBarToHealthBarSpacing)
    health:SetPoint("BOTTOMRIGHT", cast, "TOPRIGHT", NS.Client.isForever and -33 or 0, setup.castBarToHealthBarSpacing)
    cast:SetHeight(setup.castBarHeight + (setup.spellNameInsideCastBar and 0 or setup.castIconHeight))
    cast.castBar:SetHeight(setup.castBarHeight)
    cast.castBar.Icon:SetSize(setup.castIconWidth, setup.castIconHeight)
    health:SetHeight(setup.healthBarHeight)
    for _, key in ipairs({ "CrowdControlListFrame", "LossOfControlFrame" }) do
        uf.AurasFrame[key]:SetPoint("LEFT", health, "RIGHT", NS.Client.isForever and 38 or 5, 0)
    end
end
for _, forever in ipairs({ false, true }) do
    NS.Client.isForever = forever
    -- The width constants are named NAMEPLATE_WIDTH on Retail and
    -- NAME_PLATE_WIDTH in Forever's Camelot constants.
    NamePlateConstants = forever and { NAME_PLATE_WIDTH = 190, CLASSIC_NAME_PLATE_WIDTH = 152 }
        or { NAMEPLATE_WIDTH = 230, CLASSIC_NAMEPLATE_WIDTH = 152 }
    local nativeWidth = forever and 190 or 230
    for _, scale in ipairs({ .8, 1, 1.25, 1.6 }) do
        for _, selected in ipairs({ 0, 1, 2, 3, 4, 5 }) do
            style = selected
            local largeHealth = style == 0 or style == 2 or style == 3
            local largeCast = style == 2 or style == 4
            setup = { horizontalScale = scale, verticalScale = scale,
                insetWidth = 12 * scale, castBarToHealthBarSpacing = 2 * scale,
                healthBarHeight = (largeHealth and 20 or forever and 13 or 10) * scale,
                castBarHeight = (largeCast and 16 or forever and 6 or 10) * scale,
                castIconHeight = (forever and 10 or 12) * scale,
                castIconWidth = (forever and 10 or 12) * scale,
                playerLevelDiffWidth = 28, useClassicCastBar = false, useClassicHealthBar = false,
                spellNameInsideCastBar = largeCast, unitNameAnchorStyle = 1 }
            NamePlateSetupOptions = setup
            local uf = Frame()
            uf.unit, uf.showOnlyName, uf.isFriend, uf.UpdateAnchors = "nameplate1", false, false, function() end
            uf.HealthBarsContainer, uf.CastBarsContainer = Frame(), Frame()
            uf.HealthBarsContainer.healthBar = Frame()
            uf.CastBarsContainer.castBar = Frame()
            uf.CastBarsContainer.castBar.Icon = Frame()
            uf.PlayerLevelDiffFrame = Frame(); uf.PlayerLevelDiffFrame.shown = true
            uf.AurasFrame = { CrowdControlListFrame = Frame(), LossOfControlFrame = Frame() }
            Native(uf)
            local config = { look = 4, barGeometry = 2, nativeStyle = style + 2, enemy = true,
                enemyHealthWidthDelta = 41, enemyHealthHeightDelta = 7 }
            module.config = config
            private.Layout.Configure(config)
            private.Layout.Apply(uf, "enemy", config)
            local cast, health = uf.CastBarsContainer, uf.HealthBarsContainer
            local function Near(a, b) assert(math.abs(a - b) < .00001, tostring(a) .. " ~= " .. tostring(b)) end
            local function Check()
                local width = nativeWidth * scale
                    - cast.points.BOTTOMLEFT[3] + cast.points.BOTTOMRIGHT[3]
                Near(width, 206 * scale)
                Near(width - health.points.BOTTOMLEFT[3] + health.points.BOTTOMRIGHT[3], 206 * scale + 41)
                Near(health.height, (largeHealth and 20 or 10) * scale + 7)
                Near(cast.castBar.height, (largeCast and 16 or 10) * scale)
                Near(cast.castBar.Icon.height, 12 * scale)
                assert(uf.AurasFrame.CrowdControlListFrame.points.LEFT[3] == 5,
                    "invisible native badge still displaces portable control aura")
            end
            Check()
            local writes = calls
            private.Layout.Apply(uf, "enemy", config)
            assert(calls == writes, "unchanged plate repeated geometry writes")
            Native(uf); uf.hook(uf); Check()
            -- Dragging changes the preset label, never the saved size basis.
            config.look = 3
            private.Layout.Configure(config); private.Layout.Apply(uf, "enemy", config); Check()
            combat = true; private.Layout.Restore(uf)
            assert(module.needsRefresh and health.height ~= setup.healthBarHeight)
            combat = false; private.Layout.Restore(uf)
            Near(health.height, setup.healthBarHeight)
            Near(cast.castBar.height, setup.castBarHeight)
            Near(cast.points.BOTTOMLEFT[3], setup.insetWidth)
            assert(health.points.BOTTOMRIGHT[3] == (forever and -33 or 0))
            -- Reapplying and switching to native sizing restores every base
            -- while retaining a user's health width/height adjustments.
            private.Layout.Apply(uf, "enemy", config)
            config.barGeometry = 1
            private.Layout.Configure(config); private.Layout.Apply(uf, "enemy", config)
            Near(health.height, setup.healthBarHeight + 7)
            Near(cast.castBar.height, setup.castBarHeight)
            private.Layout.Restore(uf)
        end
    end
end
print("Mapko dimensions: Retail/Forever, six styles, four scales, native rebuild, Custom, combat and restoration passed")

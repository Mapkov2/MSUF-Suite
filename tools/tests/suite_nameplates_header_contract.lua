local root = assert(arg[1])
local combat, object, persistOffsets = false, false, false
local NS = { Client = { isMainline = true }, Public = function(v) return v ~= "secret" end,
    Finite = function(v) return type(v) == "number" and v == v end,
    IsCombatLocked = function() return combat end,
    Safety = { IsForbidden = function(r) return r.forbidden == true end } }
PixelUtil = { SetPoint = function(region, ...) region:SetPoint(...) end }
C_CVar = { GetCVar = function() return "5" end, GetCVarBool = function() return false end }
UnitIsGameObject = function() return object end
UnitIsFriend, UnitIsPlayer = function() return false end, function() return false end
local private = { NS = NS }
for _, file in ipairs({ "SuiteCatalog", "NameplateStyle" }) do
    assert(loadfile(root .. "/MSUF_Suite/Core/" .. file .. ".lua"))("MSUF_Suite", NS)
end
for _, file in ipairs({ "Modes", "Geometry", "Layout" }) do
    assert(loadfile(root .. "/MSUF_Suite_Nameplates/" .. file .. ".lua"))("MSUF_Suite_Nameplates", private)
end
local function Frame()
    local f = { points = {}, justify = "LEFT" }
    function f:SetPoint(point, owner, relative, x, y) self.points[point] = { owner, relative, x, y } end
    function f:ClearAllPoints()
        self.points = {}
        if not persistOffsets then self.x, self.y = 0, 0 end
    end
    function f:SetPointsOffset(x, y) self.x, self.y = x, y end
    function f:SetJustifyH(value) self.justify = value end
    function f:SetHeight(value) self.height = value end
    function f:SetSize(w, h) self.width, self.height = w, h end
    function f:IsShown() return true end
    function f:GetPoint() error("restricted native anchor read") end
    function f:GetWidth() error("restricted native dimension read") end
    function f:GetStringWidth() error("restricted native text read") end
    return f
end
hooksecurefunc = function(uf, _, callback) uf.hook = callback end
local module = { active = true, levelLabels = {}, castTimes = {}, pendingPlates = {} }
private.Layout.Bind(module)
for _, persist in ipairs({ false, true }) do
persistOffsets = persist
for _, forever in ipairs({ false, true }) do
    NS.Client.isForever = forever
    for _, inside in ipairs({ false, true }) do
        for _, badge in ipairs({ false, true }) do
            object = not badge
            local setup = { useClassicCastBar = true, useClassicHealthBar = false,
                spellNameInsideCastBar = true, unitNameAnchorStyle = 2,
                healthBarHeight = 10, healthBarToNameAboveSpacing = 2, castBarToHealthBarSpacing = 2,
                castBarHeight = 10, castIconWidth = 12, castIconHeight = 12, insetWidth = 12,
                horizontalScale = 1, verticalScale = 1, playerLevelDiffWidth = 28,
                healthTextInsideBarWhenNameAboveHealthBar = inside,
                nameJustificationWhenAboveHealthBar = "CENTER" }
            NamePlateSetupOptions, NamePlateConstants = setup, { NAMEPLATE_WIDTH = 230, NAME_PLATE_WIDTH = 190 }
            local uf = Frame()
            uf.unit, uf.showOnlyName, uf.isFriend = "nameplate1", false, false
            uf.name, uf.PlayerLevelDiffFrame = Frame(), Frame()
            uf.HealthBarsContainer, uf.CastBarsContainer = Frame(), Frame()
            local health = Frame()
            uf.HealthBarsContainer.healthBar = health
            health.Text, health.LeftText, health.RightText = Frame(), Frame(), Frame()
            -- Native NamePlateHealthBar.OnLoad calls SetBarText with the
            -- XML sides reversed. Percent-only displays TextString, whereas
            -- BOTH uses the two hidden side regions (upstream/ptr, Forever).
            local function SetBarText(self, text, left, right)
                self.TextString, self.LeftText, self.RightText = text, left, right
            end
            SetBarText(health, health.Text, health.RightText, health.LeftText)
            health.LeftText:SetPoint("BOTTOMRIGHT", health, "TOPRIGHT", -4, 2)
            health.RightText:SetPoint("BOTTOMRIGHT", health.LeftText, "BOTTOMLEFT", -2, 0)
            health.Text:SetPoint("BOTTOMRIGHT", health.RightText, "BOTTOMLEFT", 2, 0)
            health.Text.visible, health.LeftText.visible, health.RightText.visible = true, false, false
            uf.CastBarsContainer.castBar = Frame(); uf.CastBarsContainer.castBar.Icon = Frame()
            local value = health.TextString
            local nativeSides = health.RightText.points
            local config = { look = 3, barGeometry = 1, enemy = true, enemyMirrorHeader = true, enemyTextMode = 2,
                enemyNameOffsetX = 10, enemyNameOffsetY = 7, enemyHealthTextOffsetX = 3, enemyHealthTextOffsetY = 2 }
            module.config = config
            local function Apply() private.Layout.Configure(config); private.Layout.Apply(uf, "enemy", config) end
            Apply()
            assert(uf.name.justify == "RIGHT" and value.points.BOTTOMLEFT[1] == health,
                "header did not mirror native name and percent")
            assert(value.visible and not health.LeftText.visible and not health.RightText.visible
                and health.RightText.points == nativeSides, "mirror moved a hidden native side instead of the visible percentage")
            assert(uf.name.points.BOTTOMLEFT[1] == value and uf.name.points.BOTTOMRIGHT[1] == uf.HealthBarsContainer,
                "native name lacks a bounded span beside the percent")
            local placed = uf.name.points
            combat = true; private.Layout.Restore(uf)
            assert(uf.name.points == placed and module.pendingPlates[uf], "combat moved the header")
            combat = false
            uf.name.forbidden = true; private.Layout.Restore(uf)
            assert(uf.name.points == placed, "forbidden header was changed")
            uf.name.forbidden = false
            config.enemyMirrorHeader = false; Apply()
            assert(uf.name.justify == (forever and "CENTER" or "LEFT"), "native justification was not restored")
            local restored = value.points[forever and inside and "RIGHT" or "BOTTOMRIGHT"]
            assert(restored and restored[1] == health.RightText
                and restored[2] == (forever and inside and "LEFT" or "BOTTOMLEFT")
                and restored[3] == 2 and restored[4] == 0, "native percent chain was not restored")
            assert(uf.name.x == 10 and uf.name.y == 7 and health.LeftText.x == 3 and health.LeftText.y == 2,
                "mirror toggle lost cached element offsets")
            private.Layout.Restore(uf)
            assert(uf.name.x == 0 and value.x == 0, "disable retained element offsets")
            config.enemyMirrorHeader = true; Apply()
            -- Native UpdateAnchors rebuilt a different header before the hook.
            uf.name:ClearAllPoints(); value:ClearAllPoints()
            uf.name:SetPoint("LEFT", uf.HealthBarsContainer, "LEFT", 4, 0); uf.name:SetJustifyH("LEFT")
            value:SetPoint("RIGHT", health, "RIGHT", -4, 0)
            setup.unitNameAnchorStyle = 1
            uf.hook(uf)
            assert(uf.name.justify == "LEFT" and uf.name.points.LEFT and not uf.name.points.BOTTOMRIGHT,
                "native style change was overwritten by a stale mirrored header")
            setup.unitNameAnchorStyle = 2; config.enemyTextMode = 4; Apply()
            assert(uf.name.justify == "LEFT", "combined value and percent mode was mirrored")
            config.enemyTextMode = 2; uf.showOnlyName = "secret"; Apply()
            assert(uf.name.justify == "LEFT", "secret showOnlyName was compared")
            uf.showOnlyName = false
            if forever then
                setup.healthTextInsideBarWhenNameAboveHealthBar = "secret"; Apply()
                assert(uf.name.justify == "LEFT", "secret native setup was compared")
                setup.healthTextInsideBarWhenNameAboveHealthBar = inside
            end
            private.Layout.Restore(uf)
        end
    end
end
end
print("Native mirrored header: bounded names, Retail/Forever restore, offsets, native resets, combat, forbidden and secrets passed")

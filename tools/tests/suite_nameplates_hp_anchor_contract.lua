local root = assert(arg[1])
local combat, writes, checks = false, 0, 0
local function Public(value) return value ~= "secret" end
local function Noop() end
local NS = {
    Client = { isMainline = true },
    Public = Public,
    Finite = function(value) return type(value) == "number" and value == value end,
    IsCombatLocked = function() return combat end,
    InCombat = function() return combat end,
    Safety = { IsForbidden = function(region) return region.forbidden == true end },
    HostBridge = { NameFormatter = Noop },
    NameplatePortableText = { Stored = Noop, Resolve = Noop },
    AnchorPoints = {},
    IsSecret = function(value) return not Public(value) end,
}
local private = { NS = NS, Suite = NS, Extensions = { OnAnchors = Noop } }
PixelUtil = { SetPoint = function(region, ...) region:SetPoint(...) end }
UnitIsGameObject, UnitIsFriend = Noop, Noop
UnitIsPlayer = function() return false end

for _, name in ipairs({ "NameplateStyle", "NameplateText", "NameplateAuraDisplay", "NameplateExtensions" }) do
    assert(loadfile(root .. "/MSUF_Suite/Core/" .. name .. ".lua"))("MSUF_Suite", NS)
end
for _, name in ipairs({ "Modes", "Geometry", "Layout" }) do
    assert(loadfile(root .. "/MSUF_Suite_Nameplates/" .. name .. ".lua"))("MSUF_Suite_Nameplates", private)
end

local function Region()
    local region = { points = {}, protected = false, accessible = true }
    function region:IsProtected() checks = checks + 1; return self.protected end
    function region:CanBeAccessedInContext() return self.accessible end
    function region:GetEffectiveScale() return self.scale or 1 end
    function region:SetPoint(point, owner, relative, x, y)
        assert(not combat or self.protected == false, "combat changed a protected point")
        self.points[point] = { owner, relative, x, y }
        writes = writes + 1
    end
    function region:SetPointsOffset(x, y)
        assert(not combat or self.protected == false, "combat changed a protected offset")
        self.x, self.y = x, y
        writes = writes + 1
    end
    function region:IsShown() return false end
    function region:GetPoint() error("restricted anchor read") end
    function region:GetRect() error("restricted geometry read") end
    return region
end

local function Plate()
    local uf, container, health = Region(), Region(), Region()
    uf.unit, uf.isFriend, uf.showOnlyName = "nameplate1", false, false
    uf.name, uf.HealthBarsContainer, container.healthBar = Region(), container, health
    uf.SoftTargetFrame = Region()
    if NS.Client.isForever then uf.PlayerLevelDiffFrame = Region() end
    health.LeftText, health.RightText, health.Text = Region(), Region(), Region()

    function uf:UpdateAnchors()
        -- The native call lays out the three labels as a chain and discards
        -- its old offsets. Keep that reset outside the addon write counter.
        local above = not NS.Client.isForever
        health.LeftText.x, health.LeftText.y = -4, above and 2 or 0
        self.name.points = above and { BOTTOMRIGHT = { health.Text, "BOTTOMLEFT", -2, 0 } } or {}
        if self.onAnchors then self.onAnchors(self) end
    end
    uf:UpdateAnchors()
    return uf, health
end

hooksecurefunc = function(uf, method, callback)
    assert(method == "UpdateAnchors" and not uf.onAnchors, "duplicate layout hook")
    uf.onAnchors = callback
end

local Layout = private.Layout
for _, forever in ipairs({ false, true }) do
    NS.Client.isForever = forever
    NamePlateSetupOptions = { unitNameAnchorStyle = 2, healthBarHeight = 28,
        useClassicCastBar = false, spellNameInsideCastBar = true }
    if forever then
        NamePlateSetupOptions.healthTextInsideBarWhenNameAboveHealthBar = true
        NamePlateSetupOptions.nameJustificationWhenAboveHealthBar = "CENTER"
    end
    local config = { look = 3, barGeometry = 1, enemy = true, enemyTextMode = 4,
        enemyHealthTextOffsetX = -6, enemyHealthTextOffsetY = -14, enemySoftTargetOffsetY = 5 }
    local module = { active = true, config = config, activeUnits = {}, pendingPlates = {}, levelLabels = {}, castTimes = {} }
    Layout.Bind(module)
    Layout.Configure(config)
    local function Apply(uf)
        module.activeUnits[uf.unit] = uf
        Layout.Apply(uf, "enemy", config)
    end
    local uf, health = Plate()
    combat = true
    Apply(uf)
    assert(health.LeftText.x == -6 and health.LeftText.y == -14,
        "a writable nameplate acquired in combat left HP text at the native anchor")
    assert(module.pendingPlates[uf] and not uf.SoftTargetFrame.y, "unrelated layout did not defer")
    if forever then
        assert(not next(uf.name.points), "changed the Forever name's independent anchor")
    else
        local anchor = uf.name.points.BOTTOMRIGHT
        assert(anchor[1] == health.Text and anchor[2] == "BOTTOMLEFT" and anchor[3] == 4 and anchor[4] == 14,
            "did not compensate the native name link")
    end
    local appliedWrites, appliedChecks = writes, checks
    for _ = 1, 100 do Apply(uf) end
    assert(writes == appliedWrites and checks == appliedChecks, "unchanged combat paints read or rewrote geometry")
    uf:UpdateAnchors()
    assert(health.LeftText.y == -14, "native rebuild lost the combat HP offset")
    module.activeUnits[uf.unit] = nil
    Layout.Restore(uf, true)
    uf:UpdateAnchors()
    assert(health.LeftText.x == -4, "retired frame was laid out")
    uf.unit = "nameplate2"
    Apply(uf)
    assert(health.LeftText.y == -14, "pooled frame was not relocated on its next lease")
    combat = false
    Apply(uf)
    assert(health.LeftText.y == -14 and uf.SoftTargetFrame.y == 5, "normal replay did not finish the layout")

    combat = true
    for i = 1, forever and 4 or 6 do
        local blocked, bar = Plate()
        local parts = { blocked, blocked.HealthBarsContainer, bar, bar.LeftText, blocked.name, bar.Text }
        for _, condition in ipairs({ "protected", "secret", "inaccessible", "forbidden" }) do
            local part = parts[i]
            part.protected = condition == "secret" and "secret" or condition == "protected"
            part.accessible = condition ~= "inaccessible"
            part.forbidden = condition == "forbidden"
            local before = writes
            Apply(blocked)
            assert(writes == before and bar.LeftText.x == -4 and module.pendingPlates[blocked],
                "did not defer " .. condition .. " layout part " .. i)
        end
    end
    if not forever then
        local restricted, bar = Plate()
        restricted.name.scale = "secret"
        Apply(restricted)
        assert(bar.LeftText.x == -4 and module.pendingPlates[restricted],
            "combat moved the text before confirming the linked name's scale")
    end
    for _, namesOnly in ipairs({ true, "secret" }) do
        local excluded, bar = Plate()
        excluded.showOnlyName = namesOnly
        Apply(excluded)
        assert(bar.LeftText.x == -4, "combat moved a name-only or restricted plate")
    end
    config.enemyTextMode, config.enemyMirrorHeader = 2, true
    Layout.Configure(config)
    local mirrored, bar = Plate()
    Apply(mirrored)
    assert(bar.LeftText.x == -4, "combat moved the ordinary anchor for a mirrored percent header")
    config.enemyTextMode, config.enemyMirrorHeader = 4, false
    config.enemyHealthTextOffsetX, config.enemyHealthTextOffsetY = 0, 0
    Layout.Configure(config)
    local unchanged = Plate()
    local before = checks
    Apply(unchanged)
    assert(checks == before, "a plate without HP offsets checked combat protection")
    combat = false

    local neutral, neutralHealth = Plate()
    local name = neutral.name
    neutral.isPlayer = false
    neutral.CastBarsContainer = Region()
    function name:GetWidth() error("restricted name width read") end
    function name:ClearAllPoints() self.points = {} end
    function name:GetJustifyH() return self.justify end
    function name:SetJustifyH(justify) self.justify = justify end
    UnitReaction = function() return 4 end
    UnitAffectingCombat = function() return false end
    NamePlateSetupOptions.castBarToHealthBarSpacing = 3
    NamePlateSetupOptions.castBarHeight = 12
    NamePlateSetupOptions.healthBarToNameAboveSpacing = 2
    function neutral:UpdateAnchors()
        name.justify = forever and "CENTER" or "LEFT"
        name.points = {
            BOTTOMLEFT = { self.HealthBarsContainer, "TOPLEFT", forever and 0 or 4, 2 },
        }
        if forever then name.points.RIGHT = { self.PlayerLevelDiffFrame, "RIGHT", 0, 0 }
        else name.points.BOTTOMRIGHT = { neutralHealth.Text, "BOTTOMLEFT", -2, 0 } end
        if self.onAnchors then self.onAnchors(self) end
    end
    neutral:UpdateAnchors()
    config.neutralPlateNameOnly, config.neutralCenterName = true, true
    config.enemyNameOffsetX, config.enemyNameOffsetY = -32, 5
    Layout.Configure(config)
    combat = true
    name.protected = true
    Apply(neutral)
    assert(name.points.BOTTOMLEFT[1] == neutral.HealthBarsContainer and module.pendingPlates[neutral],
        "centering changed a protected name during combat")
    name.protected = false
    Apply(neutral)
    assert(name.points.BOTTOMLEFT[1] == neutral and name.points.BOTTOMRIGHT[1] == neutral,
        "a writable plate acquired in combat missed the unit center")
    local centeredWrites, centeredChecks = writes, checks
    for _ = 1, 100 do Apply(neutral) end
    assert(writes == centeredWrites and checks == centeredChecks, "a centered name rewrote geometry on unchanged paints")
    neutral:UpdateAnchors()
    assert(name.points.BOTTOMLEFT[1] == neutral, "combat rebuild lost the unit center")
    combat = false
    Apply(neutral)
    local left, right = name.points.BOTTOMLEFT, name.points.BOTTOMRIGHT
    assert(left[1] == neutral and right[1] == neutral
        and left[3] == 4 and right[3] == -4 and left[4] == 50 and right[4] == 50 and name.justify == "CENTER"
        and name.x ~= -32, "name-only label was not centered in the native plate's horizontal lane")
    neutral:UpdateAnchors()
    assert(name.points.BOTTOMLEFT[1] == neutral, "native anchor rebuild lost centering")

    config.neutralPlateNameOnly = false
    config.enemyHealthHeightDelta = 6
    function neutral.HealthBarsContainer:SetHeight(h) self.height = h end
    Layout.Configure(config)
    Apply(neutral)
    assert(name.points.BOTTOMLEFT[1] == neutral and name.points.BOTTOMRIGHT[1] == neutral and name.points.BOTTOMLEFT[4] == 56,
        "health bars ignored the center setting")
    combat = true
    neutral:UpdateAnchors()
    assert(name.points.BOTTOMLEFT[4] == 50, "a native combat rebuild reused the previous custom health height")

    local cast = Region()
    cast.Icon, cast.Text = Region(), Region()
    neutral.CastBarsContainer.castBar = cast
    config.enemyCastTextOffsetY = 13
    Layout.Configure(config)
    cast.Text.protected = true
    neutral:UpdateAnchors()
    assert(name.points.BOTTOMLEFT[4] == 50, "protected cast used custom health sizing")
    cast.Text.protected = false
    Apply(neutral)
    assert(neutral.HealthBarsContainer.height == 34 and cast.Text.y == 13,
        "the writable cast did not recover together with the configured health height")
    assert(name.points.BOTTOMLEFT[4] == 56, "the centered name did not follow the recovered health height")
    neutral:UpdateAnchors()
    assert(name.points.BOTTOMLEFT[4] == 56, "combat rebuild centered the name against the native health height")
    config.enemyCastTextOffsetY = nil
    combat = false
    config.neutralCenterName = false
    Layout.Configure(config)
    Apply(neutral)
    local restored = forever and name.points.RIGHT or name.points.BOTTOMRIGHT
    assert(name.points.BOTTOMLEFT[1] == neutral.HealthBarsContainer and restored[1] == (forever and neutral.PlayerLevelDiffFrame or neutralHealth.Text)
        and name.justify == (forever and "CENTER" or "LEFT") and name.x == -32,
        "disabling centering did not restore both native anchors and the manual offset")
    config.neutralPlateNameOnly = true
    private.FriendlyNames = { IsNameOnly = function(f) return f == neutral end }
    Layout.Configure(config)
    Apply(neutral)
    local only = assert(name.points.BOTTOMLEFT, "lost original name alignment")
    assert(only[1] == neutral.HealthBarsContainer and only[3] == -32 and only[4] == 7
        and name.points.BOTTOMRIGHT[1] == neutral.HealthBarsContainer and name.justify == (forever and "CENTER" or "LEFT"),
        "a name-only NPC's text width still depended on the hidden HP field")
    neutral:UpdateAnchors()
    assert(name.points.BOTTOMRIGHT[1] == neutral.HealthBarsContainer,
        "target rebuild restored the collapsed HP lane")
    NS.AnchorPoints[5], config.enemyNameRelativeAnchor = "TOPRIGHT", 6
    Layout.Configure(config)
    Apply(neutral)
    assert(name.points.TOPLEFT[1] == neutralHealth and name.points.TOPRIGHT[1] == neutralHealth and name.justify == "RIGHT",
        "a name-only plate lost the chosen manual alignment")
    NS.AnchorPoints[5] = nil
    private.FriendlyNames = nil
end
print("Nameplate HP anchors: Retail and Forever combat acquire, rebuild, reuse, deferral and repeat costs passed")

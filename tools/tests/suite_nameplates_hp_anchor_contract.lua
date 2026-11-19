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
}
local private = { NS = NS, Suite = NS, Extensions = { OnAnchors = Noop } }
PixelUtil = { SetPoint = function(region, ...) region:SetPoint(...) end }
UnitIsGameObject, UnitIsFriend, UnitIsPlayer = Noop, Noop, Noop

for _, name in ipairs({ "NameplateStyle", "NameplateText", "NameplateAuraDisplay" }) do
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
end
print("Nameplate HP anchors: Retail and Forever combat acquire, rebuild, reuse, deferral and repeat costs passed")

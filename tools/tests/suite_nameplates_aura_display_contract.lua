-- Nameplate auras, laid out like MSUF's unit frame Auras: Buffs, Debuffs,
-- Custom 1-3 and Dots on target for enemy and for friendly plates. Buffs and
-- Debuffs stay Blizzard's lists until they are made Visible; then the Suite
-- draws them and hides Blizzard's list of that kind only. Covers the cold
-- model and its catalog rules, the migration of the former tracked DoT
-- slots, the native aura container runtime and the options workspace with
-- its preview.
local root = assert(arg[1], "repository root required")
local up, out = root, root

-- Model, catalog and migration
do
    local function load(path, ...)
        local f = assert(io.open(path, "rb")) local s = f:read("*a") f:close()
        return assert(loadstring(s:gsub("\r\n", "\n"), "@" .. path:match("[^/]+$")))(...)
    end
    local function NewNS(forever)
        local NS = { Client = { isForever = forever }, L = {} }
        NS.Public = function() return true end
        NS.Text = function(s) return s end
        NS.Finite = function(v) return v == v end
        NS.NameplateStyle = { AuraCVar = {}, AuraBits = {}, NativeBit = function() return true end, NativeToggle = function() return false end,
            CreateBorder = function() return {} end, PaintBorder = function() end }
        UnitClass = function() return "Mage", "MAGE" end
        load(up .. "/MSUF_Suite/Core/SuiteCatalog.lua", "MSUF_Suite", NS)
        NS.NameplateAuraColors = { Decode = function() return { [62] = { { id = 589, ids = { 589, 34914 } }, { id = 172, ids = { 172 }, enabled = false } } } end,
            Spec = function() return 62 end, Selected = function(rows) local o = {} for _, r in ipairs(rows or {}) do if r.enabled ~= false then o[#o + 1] = r end end return o end }
        NS.CatalogBuild.ForAddon("MSUF_Suite_Nameplates").Module("nameplates", { title = "Nameplates", look = { key = "look", visualKeys = {}, presets = { {}, {} } } })
        local B = NS.CatalogBuild
        B.Add("nameplates", B.Choice("look", "Look", 1, { "a", "b", "c", "d" }))
        B.Add("nameplates", B.Bool("enemy", "Enemy", true))
        B.Add("nameplates", B.Bool("friendly", "Friendly", true))
        B.Add("nameplates", B.String("auraColorsData", "x", "", 4096))
        load(out .. "/MSUF_Suite/Core/NameplateAuraDisplay.lua", "MSUF_Suite", NS)
        load(out .. "/MSUF_Suite/Core/Catalog/NameplateAuras.lua", "MSUF_Suite", NS)
        return NS
    end
    local NS = NewNS(false)
    local M, spec = NS.NameplateAuraDisplay, NS.SuiteCatalog.nameplates
    local function C(plan, scope, key)
        for _, c in ipairs(plan.scopes[scope]) do if c.key == key then return c end end
    end
    local count = 0 for _ in pairs(spec.rules) do count = count + 1 end
    assert(count > 350, "container rules are missing")
    -- every tool key exists, every rule gated
    for _, scope in ipairs(M.Scopes) do for _, c in ipairs(M.Containers) do
        for _, tool in ipairs(M.Tools[c.kind]) do
            for _, key in ipairs(M.ToolKeys(scope, c, tool)) do assert(spec.rules[key], key) end
        end
        assert(spec.rules[M.ListKey(scope, c, "Retail")].client == "retail" and spec.rules[M.ListKey(scope, c, "Forever")].hidden)
    end end
    for _, rule in ipairs(spec.controls) do
        if rule.key:find("^aura") and rule.key ~= "auraDisplayEnabled" and rule.key ~= "auraColorsData" then assert(rule.enableKey, rule.key .. " has no gate") end
    end
    assert(not spec.look.visualKeys.auraEnemyDotsVisible and spec.look.visualKeys.auraFont)
    -- defaults: nothing used
    local plan = M.Plan({})
    assert(not plan.used.enemy and not plan.used.friendly, "defaults must build no container")
    -- enemy dots from the health-colour DoTs, fixed slots
    local config = { auraDisplayEnabled = true, auraEnemyDotsVisible = true }
    plan = M.Plan(config)
    local dots = C(plan, "enemy", "dots")
    assert(dots.key == "dots" and dots.enabled and dots.fixed and #dots.rows == 1 and dots.rows[1].id == 589)
    assert(dots.rows[1].filter == "HARMFUL|PLAYER|INCLUDE_NAME_PLATE_ONLY" and dots.rows[1].candidate.includeSpellIDs[34914])
    assert(dots.point == "BOTTOM" and dots.relative == "TOP" and dots.y == 46 and dots.missing == true)
    assert(plan.used.enemy and not plan.used.friendly)
    -- custom flow container, client list
    config.auraFriendlyCustom1Visible, config.auraFriendlyCustom1SpellsRetail = true, "774, 8936;33763 x 774"
    config.auraFriendlyCustom1SpellsForever = "1126"
    config.auraFriendlyCustom1HidePermanent = true
    local before = C(plan, "enemy", "dots").sig
    plan = M.Plan(config)
    local custom = C(plan, "friendly", "custom1")
    assert(custom.enabled and not custom.fixed and custom.filter == "HELPFUL|INCLUDE_NAME_PLATE_ONLY")
    assert(custom.candidate.includeSpellIDs[774] and custom.candidate.includeSpellIDs[33763] and not custom.candidate.includeSpellIDs[1126])
    assert(custom.candidate.maxDuration == 2147483647 and custom.groupCount == 8 and custom.anyCount == 0)
    assert(C(plan, "enemy", "dots").sig == before, "an edit to one container changed another container's signature")
    -- geometry and slot offsets
    config.auraEnemyDotsSource, config.auraEnemyDotsIDsRetail = 2, "1,2,3,4,5"
    config.auraEnemyDotsPerRow, config.auraEnemyDotsGrowth, config.auraEnemyDotsHeightPercent = 2, 4, 50
    plan = M.Plan(config)
    dots = C(plan, "enemy", "dots")
    assert(#dots.rows == 5 and dots.width == 24 and dots.height == 12 and dots.gridWidth == 50 and dots.gridHeight == 40, dots.gridWidth .. "x" .. dots.gridHeight)
    local x, y = M.SlotOffset(dots, 4)
    assert(dots.flowPoint == "TOPRIGHT" and x == -26 and y == -14, x .. "," .. y)
    -- a lane (Buffs, Debuffs) is off by default; Visible, it takes Blizzard's filter, plate kinds and position
    assert(not plan.lanes.enemy and not C(plan, "enemy", "debuff").enabled)
    config.auraEnemyDebuffVisible = true
    plan = M.Plan(config)
    local lane = C(plan, "enemy", "debuff")
    assert(lane.enabled and lane.filter == "HARMFUL|INCLUDE_NAME_PLATE_ONLY|!CROWD_CONTROL|PLAYER" and lane.frame == "DebuffListFrame")
    assert(lane.kinds.enemyNpc and lane.kinds.enemyPlayer and plan.lanes.enemy and not plan.lanes.friendly)
    assert(lane.point == "BOTTOMLEFT" and lane.relative == "TOPLEFT" and lane.x == 0 and lane.y == 6 and lane.groupCount == 8 and not lane.fixed)
    config.enemyNpcAuraMode, config.enemyNpcDebuffs, config.enemyAurasOffsetX = 2, false, 9
    config.auraEnemyDebuffBlockRetail, config.auraEnemyDebuffFilter, config.auraEnemyDebuffOnlyMine = "17", 4, false
    lane = C(M.Plan(config), "enemy", "debuff")
    assert(not lane.kinds.enemyNpc and lane.kinds.enemyPlayer and lane.candidate.excludeSpellIDs[17] and lane.candidate.isStealable
        and lane.x == 9 and lane.filter == "HARMFUL|INCLUDE_NAME_PLATE_ONLY|!CROWD_CONTROL")
    config.auraFriendlyBuffVisible = true
    local buffs = C(M.Plan(config), "friendly", "buff")
    assert(buffs.filter == "HELPFUL|INCLUDE_NAME_PLATE_ONLY" and buffs.point == "RIGHT" and buffs.x == -6 and buffs.flowPoint == "BOTTOMRIGHT"
        and buffs.kinds.friendlyPlayer and buffs.kinds.friendlyNpc == nil)
    -- the tools of a lane are MSUF's: Layout, Ordering, Filters, Blacklist, Style
    assert(table.concat(M.Tools.lane, " ") == "layout ordering filters blacklist style")
    assert(M.ToolKeys(M.Scope("enemy"), M.Container("buff"), "layout", true)[1] == "auraEnemyBuffVisible")
    assert(#M.ToolKeys(M.Scope("enemy"), M.Container("buff"), "style") == #M.ToolKeys(M.Scope("enemy"), M.Container("buff"), "style", true)
        + #M.AppearanceKeys)
    -- text inheritance
    config.auraEnemyDotsTimePoint, config.auraEnemyDotsStackSize = 2, 20
    plan = M.Plan(config)
    dots = C(plan, "enemy", "dots")
    assert(dots.text.Time.point == "TOPLEFT" and dots.text.Time.size == 11 and dots.text.Stack.size == 20 and dots.text.Stack.point == "BOTTOMRIGHT" and dots.text.Stack.x == -1)
    -- the other client reads its own list; Sunder joins as an every-player slot
    local F = NewNS(true)
    local FM = F.NameplateAuraDisplay
    config.auraSunder = true
    local fplan = FM.Plan(config)
    assert(C(fplan, "friendly", "custom1").candidate.includeSpellIDs[1126] and not C(fplan, "friendly", "custom1").candidate.includeSpellIDs[774])
    local fdots = C(fplan, "enemy", "dots")
    assert(#fdots.rows == 1 and fdots.rows[1].any and fdots.rows[1].filter == "HARMFUL|INCLUDE_NAME_PLATE_ONLY", "forever dots")
    config.auraEnemyDotsDisplay, config.auraEnemyDotsIDsForever = 2, "11"
    fdots = C(FM.Plan(config), "enemy", "dots")
    assert(fdots.groupCount == 8 and fdots.anyCount == 1 and fdots.anyCandidate.includeSpellIDs[7386] and fdots.candidate.includeSpellIDs[11])
    -- migration
    local NSm = { Client = { isForever = false }, SuiteCatalog = NS.SuiteCatalog }
    load(out .. "/MSUF_Suite/Core/SuiteMigrations.lua", "MSUF_Suite", NSm)
    local plates = { auraTrackedEnabled = true, auraTrackedSource = 2, auraTrackedIDs = "589,34914", auraTrackedSize = 30, auraTrackedY = 70,
        auraTrackedX = 4, aurabuffSize = 36, auracontrolAllow = "1", auraDisplayEnabled = true, auraFont = "x" }
    NSm.SuiteMigrationSteps.NameplateAuraContainers({ nameplates = plates })
    assert(plates.auraEnemyDotsVisible == true and plates.auraEnemyDotsIDsRetail == "589,34914" and plates.auraEnemyDotsSize == 30
        and plates.auraEnemyDotsOffsetY == 55 and plates.auraEnemyDotsOffsetX == 4 and plates.auraEnemyDotsSource == 2)
    assert(plates.auraTrackedIDs == nil and plates.aurabuffSize == nil and plates.auracontrolAllow == nil and plates.auraFont == "x")
    for key, value in pairs(plates) do
        local rule = spec.rules[key]
        assert(rule and type(rule.default) == type(value), "migrated key " .. key .. " has no matching rule")
    end
end

-- Runtime
do
    local function load(path, ...)
        local f = assert(io.open(path, "rb")) local s = f:read("*a") f:close()
        return assert(loadstring(s:gsub("\r\n", "\n"), "@" .. path:match("[^/]+$")))(...)
    end
    local log, frames, combat, blocked, secret, failLayout = {}, {}, false, false, false, false
    local methods, dispelCalls = {}, {}
    -- the clock (GetTime), the frame that runs a group's ramp (the last OnUpdate owner), whether the clock holds
    -- for a frame of several plates, and the aura count a group of each key has (default: one aura)
    local now, holdFrame, updateFrame, presentDefault = 100, false, nil, {}
    -- Blizzard seals an aura button, and with it everything on it, as soon as
    -- initializeFrame returns (DenyTaintedAccessWhenAurasAreSecret,
    -- Blizzard_AuraContainerFrameProviders.lua CreateFrame). While auras are
    -- secret every call of ours on a sealed object raises.
    local function Refused(frame)
        if not (combat or secret) then return false end
        while frame do
            if rawget(frame, "restricted") then return true end
            frame = rawget(frame, "parent")
        end
        return false
    end
    local function Frame(kind, parent, template)
        local frame = setmetatable({ kind = kind, parent = parent, template = template, shown = true, level = 1, scripts = {}, calls = {} },
            { __index = function(self, name)
                if name ~= "CanBeAccessedInContext" and Refused(self) then
                    error("calling '" .. name .. "' on bad self (sealed aura button)", 2)
                end
                if methods[name] then return methods[name] end
                return function(this, ...) this.calls[name] = (this.calls[name] or 0) + 1 this[name .. "Args"] = { ... } end
            end })
        frames[#frames + 1] = frame
        return frame
    end
    function methods:GetFrameLevel() return self.level end
    -- Anchors are kept in order per frame (a ClearAllPoints starts over), for the ring and the pandemic edges.
    function methods:ClearAllPoints() self.calls.ClearAllPoints = (self.calls.ClearAllPoints or 0) + 1 self.points = {} end
    function methods:SetPoint(...)
        self.calls.SetPoint = (self.calls.SetPoint or 0) + 1
        self.SetPointArgs = { ... }
        local points = rawget(self, "points") or {}
        points[#points + 1] = self.SetPointArgs
        self.points = points
    end
    function methods:ClearDispelTypeTextures() dispelCalls[#dispelCalls + 1] = { button = self } end
    function methods:AddDispelTypeTexture(texture, options) dispelCalls[#dispelCalls + 1] = { button = self, texture = texture, options = options } end
    function methods:SetFrameLevel(v) self.level = v end
    function methods:IsProtected() return false end
    function methods:CanBeAccessedInContext() return not rawget(self, "sealed") and not Refused(self) end
    local function AuraButton(container, initializeFrame)
        local button = Frame("AuraButton", container)
        initializeFrame(button)
        button.restricted = true
    end
    function methods:IsShown() return self.shown end
    function methods:SetShown(v) self.shown = v local cb = self.scripts[v and "OnShow" or "OnHide"] if cb then cb(self) end end
    function methods:Show() self:SetShown(true) end
    function methods:Hide() self:SetShown(false) end
    function methods:HookScript(e, cb) self.scripts[e] = cb end
    function methods:SetScript(e, cb) self.scripts[e] = cb if e == "OnUpdate" then updateFrame = self end end
    function methods:CreateTexture(_, layer) local texture = Frame("Texture", self) texture.drawLayer = layer return texture end
    function methods:CreateFontString() return Frame("FontString", self) end
    function methods:SetEnabled(v) self.enabled = v end
    function methods:SetUnit(u) self.unit = u end
    function methods:AddAuraSlot(key, filter, options)
        self.slots = rawget(self, "slots") or {}
        self.slots[key] = { filter = filter, candidate = options.candidateFilters }
        log[#log + 1] = "slot:" .. key
        AuraButton(self, options.initializeFrame)
    end
    function methods:SetAuraSlotCandidateFilters(key, c) self.slots[key].candidate = c log[#log + 1] = "slotc:" .. key end
    function methods:SetAuraSlotFilterString(key, f) self.slots[key].filter = f end
    -- Blizzard makes a group's buttons on demand: min(auras, limit). SetAuraGroupMaxFrameCount only stores the limit;
    -- the stub makes the buttons it allows at once (Blizzard makes them on its next refresh, through initializeFrame).
    local function Fill(frame, key)
        local group = frame.groups[key]
        local want = math.min(presentDefault[key] or 1, group.max)
        while group.made < want do
            group.made = group.made + 1
            AuraButton(frame, group.init)
        end
    end
    function methods:AddAuraGroup(key, filter, options)
        self.groups = rawget(self, "groups") or {}
        self.groups[key] = { filter = filter, candidate = options.candidateFilters, max = options.maxFrameCount, init = options.initializeFrame, made = 0 }
        log[#log + 1] = "group:" .. key
        Fill(self, key)
    end
    function methods:SetAuraGroupCandidateFilters(key, c) self.groups[key].candidate = c end
    function methods:SetAuraGroupFilterString(key, f) self.groups[key].filter = f end
    function methods:SetAuraGroupMaxFrameCount(key, n) self.groups[key].max = n Fill(self, key) end
    function methods:SetAuraGroupLayout(key, l)
        if failLayout then failLayout = false error("layout refused") end
        self.groups[key].layout = l
    end
    CreateFrame = function(kind, _, parent, template) return Frame(kind, parent, template) end
    GetTime = function() return now end
    AnchorUtil = { FlowDirection = { Left = "L", Right = "R", Up = "U", Down = "D" } }
    AuraContainerSortMethod = setmetatable({}, { __index = function(_, k) return k end })
    AuraContainerSortDirection = { Normal = 1, Reverse = 2 }
    -- Blizzard's colour objects (ColorMixin): r, g, b, a and the methods copied into each object. The real
    -- ColorMixin carries about 25 methods; this stub copies 24 and the GetRGB that Plain calls.
    local SOURCE = { Magic = { .2, .6, 1 }, Curse = { .6, 0, 1 }, Disease = { .6, .4, 0 }, Poison = { 0, .6, 0 }, Bleed = { .8, .1, .1 } }
    local MIXIN = { "GetRGBA", "GetRGBAsBytes", "SetRGB", "SetRGBA", "SetRGBAsBytes", "IsEqualTo", "WrapTextInColorCode",
        "GenerateHexColor", "GenerateHexColorMarkup", "GetRed", "GetGreen", "GetBlue", "GetAlpha", "SetAlpha", "Clone", "Mix", "Lerp",
        "SetRGBFromHex", "IsTransparent", "Init", "Dump", "Reset", "IsValid", "ToString" }
    local function BlizzardColor(r, g, b, a)
        local color = { r = r, g = g, b = b, a = a or 1 }
        for _, name in ipairs(MIXIN) do color[name] = function() end end
        function color:GetRGB() return self.r, self.g, self.b end
        return color
    end
    AuraUtil = { GetAuraBorderColor = function(k) local c = SOURCE[k] return BlizzardColor(c[1], c[2], c[3]) end }
    CreateColor = function(r, g, b, a) return BlizzardColor(r, g, b, a) end
    Enum = { CustomAuraButtonDispelTypeTextureStyle = { CustomAsset = 1 } }
    C_Spell = { GetSpellTexture = function(id) return id end }
    C_Secrets = { ShouldAurasBeSecret = function() return combat or secret end }
    C_StringUtil = { CreateNumericRuleFormatter = function() return { SetBreakpoints = function() end } end }
    UnitClass = function() return "Mage", "MAGE" end
    local playerUnit = false
    UnitIsPlayer = function() return playerUnit end
    hooksecurefunc = function(object, name, hook)
        local original = object[name]
        object[name] = function(...) original(...) hook(...) end
    end
    local NS = { Client = { isForever = false, AuraBuildBlocked = function() return blocked end, AfterAuraBuild = function() log[#log + 1] = "afterbuild" end,
        RealAurasOnly = function() return true end }, Safety = { IsForbidden = function() return false end } }
    NS.Public = function() return true end
    NS.Text = function(s) return s end
    NS.RGB = function() return 1, 1, 1 end
    NS.InCombat = function() return combat end
    NS.NameplateStyle = { AuraCVar = {}, AuraBits = {}, NativeBit = function() return true end, NativeToggle = function() return false end,
        CreateBorder = function() return {} end, PaintBorder = function() end }
    load(up .. "/MSUF_Suite/Core/SuiteCatalog.lua", "MSUF_Suite", NS)
    NS.NameplateAuraColors = { Decode = function() return {} end, Spec = function() return 1 end, Selected = function() return {} end }
    NS.CatalogBuild.ForAddon("MSUF_Suite_Nameplates").Module("nameplates", { title = "x", look = { key = "look", visualKeys = {}, presets = {} } })
    local B = NS.CatalogBuild
    B.Add("nameplates", B.Choice("look", "Look", 1, { "a", "b", "c", "d" }))
    B.Add("nameplates", B.Bool("enemy", "Enemy", true))
    B.Add("nameplates", B.Bool("friendly", "Friendly", true))
    B.Add("nameplates", B.String("auraColorsData", "x", "", 4096))
    load(out .. "/MSUF_Suite/Core/NameplateAuraDisplay.lua", "MSUF_Suite", NS)
    load(out .. "/MSUF_Suite/Core/Catalog/NameplateAuras.lua", "MSUF_Suite", NS)
    local S = { SetFont = function() end, ResolveFont = function() return nil end, GlobalFontPath = function() return "font" end }
    local private = { NS = NS, Suite = S, Mode = { LOOK_BLIZZARD = 2 } }
    load(out .. "/MSUF_Suite_Nameplates/AuraDisplay.lua", "MSUF_Suite_Nameplates", private)
    local D = private.AuraDisplay
    -- every Apply is a frame of its own, so each one has its own budget (the holdFrame switch keeps a frame)
    local apply = D.Apply
    D.Apply = function(...) if not holdFrame then now = now + 1 end return apply(...) end
    local repaints = 0
    local function Plate()
        local uf = Frame("Frame")
        uf.HealthBarsContainer = { healthBar = Frame("StatusBar", uf) }
        uf.AurasFrame = Frame("Frame", uf)
        uf.AurasFrame.BuffListFrame, uf.AurasFrame.DebuffListFrame = Frame("Frame", uf.AurasFrame), Frame("Frame", uf.AurasFrame)
        return uf
    end
    local active = {}
    local cvarEvent
    local module = { context = { Event = function(_, _, callback) cvarEvent = callback end, RemoveEvent = function() cvarEvent = nil end } }
    D.Bind(module, function() repaints = repaints + 1 for uf, a in pairs(active) do D.Apply(uf, a[1], a[2]) end end)
    local function Containers() local n = 0 for _, f in ipairs(frames) do if f.kind == "AuraContainer" then n = n + 1 end end return n end

    -- off: nothing is built
    local uf = Plate()
    D.Configure({ auraDisplayEnabled = false })
    assert(D.Apply(uf, "nameplate1", true) == false and Containers() == 0)
    -- on without an enabled container: still nothing
    local config = { auraDisplayEnabled = true }
    D.Configure(config)
    assert(D.Apply(uf, "nameplate1", true) == false and Containers() == 0, "a plate without containers got frames")
    -- enemy dots, fixed slots
    config.auraEnemyDotsVisible, config.auraEnemyDotsSource, config.auraEnemyDotsIDsRetail = true, 2, "589,34914"
    D.Configure(config)
    active[uf] = { "nameplate1", true }
    local r = D.Apply(uf, "nameplate1", true)
    assert(r == true and Containers() == 1)
    local dots
    for _, f in ipairs(frames) do if f.kind == "AuraContainer" then dots = f end end
    assert(dots.enabled and dots.unit == "nameplate1" and dots.slots.slot1.filter == "HARMFUL|PLAYER|INCLUDE_NAME_PLATE_ONLY"
        and dots.slots.slot2.candidate.includeSpellIDs[34914])
    assert(dots.SetPointArgs[1] == "BOTTOM" and dots.SetPointArgs[3] == "TOP" and dots.SetPointArgs[5] == 46)
    -- the same unit again costs nothing
    local before = #frames
    local calls = dots.calls.SetPoint
    assert(D.Apply(uf, "nameplate1", true) and #frames == before and dots.calls.SetPoint == calls)
    -- friendly plate with no friendly container: hidden, no new frames
    assert(D.Apply(uf, "nameplate1", false) == false and dots.enabled == false and Containers() == 1)
    assert(D.Apply(uf, "nameplate2", true) and dots.unit == "nameplate2" and dots.enabled)
    -- an edit to another container leaves this one alone
    config.auraEnemyCustom1Visible, config.auraEnemyCustom1SpellsRetail = true, "118,339"
    D.Configure(config)
    calls = dots.calls.SetPoint
    assert(D.Apply(uf, "nameplate2", true) and Containers() == 2 and dots.calls.SetPoint == calls, "unchanged container was laid out again")
    local custom
    for _, f in ipairs(frames) do if f.kind == "AuraContainer" and f ~= dots then custom = f end end
    assert(custom.groups.auras.filter == "HARMFUL|INCLUDE_NAME_PLATE_ONLY" and custom.groups.auras.candidate.includeSpellIDs[339]
        -- the limit is the buttons the group has (one aura here) plus the ramp, not the want of 8 (2026-11-11)
        and custom.groups.auras.max == 3 and custom.groups.auras.layout.layoutIndex == nil and not custom.groups.any)
    -- combat: an edit waits, the old plan keeps showing, then applies
    combat = true
    config.auraEnemyDotsSize = 40
    D.Configure(config)
    assert(D.Apply(uf, "nameplate2", true) == true and dots.SetSizeArgs[1] ~= 40 * 2 + 2, "combat edit applied")
    local size = dots.SetSizeArgs[1]
    combat = false
    D.Resume()
    assert(repaints == 1 and dots.SetSizeArgs[1] == 82 and size == 50, tostring(dots.SetSizeArgs[1]) .. "/" .. tostring(size))
    -- fewer tracked auras: the extra slot is emptied, not removed
    config.auraEnemyDotsIDsRetail = "589"
    D.Configure(config)
    assert(D.Apply(uf, "nameplate2", true) and next(dots.slots.slot2.candidate.includeSpellIDs) == nil)
    -- fixed -> flow
    config.auraEnemyDotsDisplay = 2
    D.Configure(config)
    assert(D.Apply(uf, "nameplate2", true) and dots.groups.auras.candidate.includeSpellIDs[589] and next(dots.slots.slot1.candidate.includeSpellIDs) == nil)
    -- Blizzard hides its aura frame: ours follows
    local wrapper
    for _, f in ipairs(frames) do if f.template == "DisableUntrustedLayoutScriptsTemplate" then wrapper = f end end
    uf.AurasFrame:Hide()
    assert(wrapper.shown == false)
    uf.AurasFrame:Show()
    assert(wrapper.shown == true)
    -- Forever gamepad panel blocks builds: a new plate waits
    blocked = true
    local uf2 = Plate()
    assert(D.Apply(uf2, "nameplate3", true) == false and log[#log] == "afterbuild")
    blocked = false
    assert(D.Apply(uf2, "nameplate3", true) == true)
    -- auras secret outside combat (keystone run, encounter, PvP): a new plate
    -- builds its containers at once. Each new button is styled once, inside
    -- initializeFrame; the build never returns to a button Blizzard sealed
    -- (2026-11-10: SetSize on bad self, AuraDisplay.lua StylePart, 3x).
    secret = true
    local uf3, first = Plate(), #frames + 1
    assert(D.Apply(uf3, "nameplate4", true) == true, "a first build under secret auras did not complete")
    secret = false
    local built = 0
    for index = first, #frames do
        local frame = frames[index]
        if frame.kind == "AuraButton" then
            built = built + 1
            assert(frame.calls.SetSize == 1, "a new aura button was styled " .. frame.calls.SetSize .. " times")
        elseif frame.kind == "AuraContainer" then
            assert(frame.enabled and frame.unit == "nameplate4", "a container built under secret auras does not show")
        end
    end
    assert(built == 2, built .. " aura buttons")
    -- a build that raised half way leaves a container with buttons and no
    -- signature. Its retry is an edit of sealed buttons: it waits while auras
    -- are secret and completes once they can be read.
    secret, failLayout = true, true
    local uf4 = Plate()
    assert(not pcall(D.Apply, uf4, "nameplate6", true), "the interrupted build did not raise")
    assert(D.Apply(uf4, "nameplate6", true) == false, "a half-built container was restyled under secret auras")
    secret, active[uf4] = false, { "nameplate6", true }
    D.Resume()
    active[uf4] = nil
    assert(D.Apply(uf4, "nameplate6", true) == true, "the interrupted build never completed")
    -- Dispel colours. Blizzard copies and processes the options on every AddDispelTypeTexture call, four a button.
    -- 2026-11-11, Lua 5.1, recursive key count of the options passed to AddDispelTypeTexture (both highlights on,
    -- this stub's colour objects: 29 keys each): before 229 (base AuraDisplay.lua) -> after 47 (colorRGB, r g b only).
    local function Names(map)
        local names = {}
        for key in pairs(map) do names[#names + 1] = key end
        table.sort(names)
        return table.concat(names, "|")
    end
    local function Keys(value)
        local n = 0
        for _, child in pairs(value) do n = n + 1 if type(child) == "table" then n = n + Keys(child) end end
        return n
    end
    -- Under(frame, button): the frame is the button or was made under it. Initialize makes the button's frames and
    -- textures; 2026-11-11, Lua 5.1, per aura button, before (base: four dispel edges on a host frame) -> after
    -- (one texture on the button): frames 6 -> 5 (the dispel host is gone), textures 9 -> 6 (four edges -> one),
    -- AddDispelTypeTexture calls 4 -> 1.
    local function Under(frame, button)
        while frame do
            if frame == button then return true end
            frame = rawget(frame, "parent")
        end
        return false
    end
    local function Made(first, button, kind)
        local n = 0
        for index = first, #frames do
            local frame = frames[index]
            if frame ~= button and frame.kind == kind and Under(frame, button) then n = n + 1 end
        end
        return n
    end
    local function Calls(button)
        local n = 0
        for _, call in ipairs(dispelCalls) do if call.button == button and call.texture then n = n + 1 end end
        return n
    end
    local function Options(button)
        for _, call in ipairs(dispelCalls) do if call.button == button and call.texture then return call.options end end
    end
    local function Anchor(entry, point, relative, relativePoint, x, y)
        return entry[1] == point and entry[2] == relative and entry[3] == relativePoint and entry[4] == x and entry[5] == y
    end
    local function Dispel(enrage, on)
        -- the custom 1 container of the earlier section is still on: every enemy container takes the switch
        config.auraDispelHighlight, config.auraEnrageHighlight, config.auraEnemyDotsDispel = true, enrage, on
        config.auraEnemyCustom1Dispel = on
        config.auraHighlightSize = 2
        D.Configure(config)
        local first, plate = #frames + 1, Plate()
        assert(D.Apply(plate, "nameplate7", true) == true, "the plate did not build")
        local buttons = {}
        for index = first, #frames do if frames[index].kind == "AuraButton" then buttons[#buttons + 1] = frames[index] end end
        assert(#buttons > 0, "no aura button was built")
        return plate, buttons, first
    end
    local plate, buttons, first = Dispel(true, true)
    local button = buttons[1]
    local frameCount, textureCount = Made(first, button, "Frame") + Made(first, button, "Cooldown"), Made(first, button, "Texture")
    print(("aura dispel per button: %d frames, %d textures, %d AddDispelTypeTexture calls"):format(frameCount, textureCount, Calls(button)))
    local dispel = Options(button)
    local count = Keys(dispel)
    print("aura dispel options: " .. count .. " keys")
    local map = dispel.customDispelColorMap
    assert(Names(map) == "|Bleed|Curse|Disease|Enrage|Magic|Poison", Names(map))
    local function CheckColor(color, want, label)
        local n = 0
        for key in pairs(color) do n = n + 1 assert(key == "r" or key == "g" or key == "b", label .. " keeps " .. tostring(key)) end
        assert(n == 3 and color.r == want[1] and color.g == want[2] and color.b == want[3], label .. " is not the source colour")
    end
    for key, want in pairs(SOURCE) do CheckColor(map[key], want, key) end
    CheckColor(map[""], { 1, .55, .1 }, "enrage token")
    CheckColor(map.Enrage, { 1, .55, .1 }, "Enrage")
    assert(map[""] ~= map.Enrage, "the two enrage entries share one table")
    assert(count <= 47, "dispel options grew to " .. count .. " keys")
    assert(frameCount == 5 and textureCount == 6, "frames " .. frameCount .. ", textures " .. textureCount)
    local want = { { "TOPLEFT", "TOPRIGHT" }, { "BOTTOMLEFT", "BOTTOMRIGHT" }, { "TOPLEFT", "BOTTOMLEFT" }, { "TOPRIGHT", "BOTTOMRIGHT" } }
    for _, b in ipairs(buttons) do
        -- one texture behind the icon, reaching the highlight's width beyond the button on every side
        assert(Calls(b) == 1, "a button got " .. Calls(b) .. " AddDispelTypeTexture calls")
        assert(Options(b) == dispel, "a button has its own options table")
        local texture
        for _, call in ipairs(dispelCalls) do if call.button == b and call.texture then texture = call.texture end end
        assert(texture.parent == b and texture.drawLayer == "BACKGROUND", "the dispel texture is not a background of its button")
        assert(b.SetIconArgs[1].drawLayer == "ARTWORK" and b.SetIconArgs[1] ~= texture, "the icon does not draw above the highlight")
        local points = rawget(texture, "points")
        assert(points and #points == 2 and Anchor(points[1], "TOPLEFT", b, "TOPLEFT", -2, 2)
            and Anchor(points[2], "BOTTOMRIGHT", b, "BOTTOMRIGHT", 2, -2), "the ring is not 2 pixels beyond the button")
        -- the pandemic highlight: its four edges keep Border's anchors and width
        local pandemic, style
        for index = first, #frames do
            local frame = frames[index]
            if frame.kind == "Frame" and rawget(frame, "parent") == b and frame.level == 4 then pandemic = frame end
        end
        assert(pandemic, "no pandemic frame")
        for index = first, #frames do
            local frame = frames[index]
            if frame.kind == "Frame" and rawget(frame, "parent") == pandemic and frame.level == 4 then style = frame end
        end
        assert(style, "no pandemic style frame")
        local edges = {}
        for index = first, #frames do
            local frame = frames[index]
            if frame.kind == "Texture" and rawget(frame, "parent") == style then edges[#edges + 1] = frame end
        end
        assert(#edges == 4, #edges .. " pandemic edges")
        for i, edge in ipairs(edges) do
            local edgePoints = rawget(edge, "points")
            assert(edgePoints and #edgePoints == 2 and Anchor(edgePoints[1], want[i][1], style, want[i][1])
                and Anchor(edgePoints[2], want[i][2], style, want[i][2]), "pandemic edge " .. i .. " anchors")
            local side = i <= 2 and "height" or "width"
            assert((i <= 2 and edge.SetHeightArgs or edge.SetWidthArgs)[1] == 2, "pandemic edge " .. i .. " " .. side)
        end
    end
    -- the highlight follows the thickness, and a restyled button is rebound once: its clear, then one bind
    local mark = #dispelCalls
    config.auraHighlightSize = 4
    D.Configure(config)
    assert(D.Apply(plate, "nameplate7", true) == true)
    for _, b in ipairs(buttons) do
        local sequence = {}
        for index = mark + 1, #dispelCalls do
            if dispelCalls[index].button == b then sequence[#sequence + 1] = dispelCalls[index].texture and "add" or "clear" end
        end
        assert(table.concat(sequence, ",") == "clear,add", "a restyled button was rebound as " .. table.concat(sequence, ","))
        local texture
        for _, call in ipairs(dispelCalls) do if call.button == b and call.texture then texture = call.texture end end
        local points = rawget(texture, "points")
        assert(points and #points == 2 and Anchor(points[1], "TOPLEFT", b, "TOPLEFT", -4, 4)
            and Anchor(points[2], "BOTTOMRIGHT", b, "BOTTOMRIGHT", 4, -4), "the ring did not follow the thickness")
    end
    -- off: no texture is bound; the enrage entries leave the map when enrages are off
    local _, offButtons = Dispel(true, false)
    for _, b in ipairs(offButtons) do assert(Calls(b) == 0, "a button with the dispel highlight off got " .. Calls(b) .. " calls") end
    local _, enrageOff = Dispel(false, true)
    assert(Names(Options(enrageOff[1]).customDispelColorMap) == "Bleed|Curse|Disease|Magic|Poison", "enrage off still colours enrages")
    config.auraDispelHighlight, config.auraEnrageHighlight, config.auraHighlightSize = nil, nil, nil
    config.auraEnemyDotsDispel, config.auraEnemyCustom1Dispel = nil, nil
    D.Configure(config)
    -- a Visible lane draws Debuffs and hides Blizzard's list of that kind only
    local buffList, debuffList = uf.AurasFrame.BuffListFrame, uf.AurasFrame.DebuffListFrame
    config.auraEnemyDebuffVisible = true
    module.config = config
    D.Configure(config)
    assert(D.Apply(uf, "nameplate2", true) and debuffList.shown == false and buffList.shown == true)
    local lane
    for _, f in ipairs(frames) do
        if f.kind == "AuraContainer" and rawget(f, "groups") and f.groups.auras.filter:find("!CROWD_CONTROL", 1, true) then lane = f end
    end
    assert(lane and lane.enabled and lane.unit == "nameplate2" and lane.groups.auras.filter == "HARMFUL|INCLUDE_NAME_PLATE_ONLY|!CROWD_CONTROL|PLAYER")
    -- Blizzard asks to show its list while the lane owns it: it stays hidden
    debuffList:Show()
    assert(debuffList.shown == false, "Blizzard's list came back under a Visible lane")
    -- a plate kind Blizzard's switches exclude keeps neither; the player plate of that side gets the lane
    config.enemyNpcAuraMode, config.enemyNpcDebuffs = 2, false
    D.Configure(config)
    assert(D.Apply(uf, "nameplate2", true) and lane.enabled == false and debuffList.shown == true)
    playerUnit = true
    assert(D.Apply(uf, "nameplate5", true) and lane.enabled == true and lane.unit == "nameplate5" and debuffList.shown == false)
    -- Blizzard's own aura switch changes (Keep Blizzard setting): the plan follows the CVar
    assert(cvarEvent, "the runtime does not follow Blizzard's aura CVars")
    local before = repaints
    cvarEvent(module, "CVAR_UPDATE", "nameplateResourceOnTarget")
    assert(repaints == before)
    -- the plate turns friendly: the enemy lane lets go of Blizzard's list
    assert(D.Apply(uf, "nameplate5", false) == false and debuffList.shown == true and lane.enabled == false)
    assert(D.Apply(uf, "nameplate5", true) and debuffList.shown == false)
    -- in combat a protected list cannot be handed back at once: it returns after combat
    combat = true
    debuffList.IsProtected = function() return true end
    D.Configure({ auraDisplayEnabled = false })
    assert(lane.enabled == false and debuffList.shown == false, "a protected list changed in combat")
    combat = false
    D.Resume()
    assert(debuffList.shown == true, "Blizzard's list was not handed back after combat")
    -- release
    assert(dots.enabled == false and custom.enabled == false and D.Apply(uf, "nameplate2", true) == false and cvarEvent == nil)
    -- Ramp. Blizzard makes a group's buttons on demand, min(auras, limit), each at about half a millisecond
    -- (2026-11-11 combat trace). Budget, lua 5.1, 2026-11-11: a plate that gets a unit with ten auras makes
    -- buttons in that frame: before 10 (base: the group's limit is its want) -> after 3 (RAMP), and frames
    -- until complete: before 1 -> after 4 (3, 3, 3, 1).
    local function Total(list)
        local n = 0
        for _, container in ipairs(list) do
            for _, frame in ipairs(frames) do
                if frame.kind == "AuraButton" and rawget(frame, "parent") == container then n = n + 1 end
            end
        end
        return n
    end
    local function Containers(first)
        local list = {}
        for index = first, #frames do if frames[index].kind == "AuraContainer" then list[#list + 1] = frames[index] end end
        return list
    end
    -- one frame: the clock moves on and the ramp runs; the result is the buttons each frame made
    local function Frames(list, count)
        local made = {}
        for i = 1, count do
            local before = Total(list)
            now = now + 1
            if updateFrame and updateFrame.scripts.OnUpdate then updateFrame.scripts.OnUpdate(updateFrame) end
            made[i] = Total(list) - before
        end
        return made
    end
    local ramp = { auraDisplayEnabled = true, auraEnemyCustom1Visible = true, auraEnemyCustom1SpellsRetail = "118,339",
        auraEnemyCustom1Max = 10 }
    config, module.config = ramp, ramp
    D.Configure(ramp)
    -- groups of the earlier sections that the budget left without a button are still waiting: let them finish
    for _ = 1, 20 do
        if not (updateFrame and updateFrame.scripts.OnUpdate) then break end
        Frames({}, 1)
    end
    -- (a) one plate, ten auras: three buttons in its frame, then three a frame, then the rest
    presentDefault.auras = 10
    local a = Plate()
    local firstA = #frames + 1
    assert(D.Apply(a, "nameplate8", true) == true)
    local boxA = Containers(firstA)
    local appliedA = Total(boxA)
    local ticksA = Frames(boxA, 3)
    local count, untilTen = appliedA, 1
    for _, made in ipairs(ticksA) do
        if count < 10 then count, untilTen = count + made, untilTen + 1 end
    end
    print(("aura ramp: %d buttons in the frame of a plate with ten auras, %d frames until ten"):format(appliedA, untilTen))
    assert(appliedA == 3, "the frame of a unit made " .. appliedA .. " buttons")
    assert(table.concat(ticksA, ",") == "3,3,1" and Total(boxA) == 10, table.concat(ticksA, ","))
    assert(boxA[1].groups.auras.max == 10 and updateFrame.scripts.OnUpdate == nil, "the ramp still runs with nothing waiting")
    -- (b) one plate, two auras: two buttons at once, a limit of three, and no ramp started
    presentDefault.auras = 2
    local b = Plate()
    local firstB = #frames + 1
    assert(D.Apply(b, "nameplate9", true) == true)
    local boxB = Containers(firstB)
    assert(Total(boxB) == 2 and boxB[1].groups.auras.max == 3, "two auras made " .. Total(boxB) .. " buttons")
    assert(updateFrame.scripts.OnUpdate == nil, "a ramp runs with nothing waiting")
    -- (c) the plate's unit changes to one with ten auras: the spare allowance makes one button, then three a frame
    presentDefault.auras = 10
    local spare = Total(boxB)
    for _, container in ipairs(boxB) do Fill(container, "auras") end
    local atOnce = Total(boxB) - spare
    assert(D.Apply(b, "nameplate10", true) == true)
    local ticksC = Frames(boxB, 3)
    assert(atOnce == 1 and table.concat(ticksC, ",") == "3,3,1" and Total(boxB) == 10, atOnce .. " at once, " .. table.concat(ticksC, ","))
    -- a group with fewer auras than its want stops at the buttons it has plus the ramp, and nothing ticks after that
    presentDefault.auras = 4
    local h = Plate()
    local firstH = #frames + 1
    assert(D.Apply(h, "nameplate60", true) == true)
    local boxH = Containers(firstH)
    local hTicks = Frames(boxH, 2)
    assert(table.concat(hTicks, ",") == "1,0" and Total(boxH) == 4 and boxH[1].groups.auras.max == 6, "four auras: " .. table.concat(hTicks, ","))
    assert(updateFrame.scripts.OnUpdate == nil, "a ramp runs for a group that is not full")
    -- (d) five plates with ten auras in one frame: three buttons in that frame over all plates, three a frame after
    now = now + 1
    holdFrame = true
    presentDefault.auras = 10
    local firstD = #frames + 1
    for index = 1, 5 do assert(D.Apply(Plate(), "nameplate" .. (20 + index), true) == true) end
    holdFrame = false
    local boxD = Containers(firstD)
    assert(#boxD == 5, #boxD .. " containers")
    local sizes = { Total(boxD) }
    for _ = 1, 20 do
        if Total(boxD) >= 50 then break end
        sizes[#sizes + 1] = Frames(boxD, 1)[1]
    end
    -- 2026-11-11, measured: the frame budget is FRAME_GRANT (6) allowances; the first frame grants two plates three
    -- each, then six a frame until the remainder
    assert(table.concat(sizes, ",") == "6,6,6,6,6,6,6,3,3,2", "five plates made " .. table.concat(sizes, ","))
    for _, size in ipairs(sizes) do assert(size <= 6, "a frame made " .. size .. " buttons") end
    for _, container in ipairs(boxD) do assert(container.groups.auras.max == 10, "a limit of " .. container.groups.auras.max) end
    assert(updateFrame.scripts.OnUpdate == nil)
    -- (e) a want of two never allows more than two; a settings change raises it to twelve, and the group goes on
    ramp.auraEnemyCustom1Max = 2
    D.Configure(ramp)
    presentDefault.auras = 10
    local e = Plate()
    local firstE = #frames + 1
    assert(D.Apply(e, "nameplate30", true) == true)
    local boxE = Containers(firstE)
    local capped = Frames(boxE, 2)
    assert(Total(boxE) == 2 and boxE[1].groups.auras.max == 2 and capped[1] == 0 and capped[2] == 0, "a want of two allowed more")
    ramp.auraEnemyCustom1Max = 12
    D.Configure(ramp)
    presentDefault.auras = 12
    local beforeRaise = Total(boxE)
    assert(D.Apply(e, "nameplate30", true) == true)
    local raisedAtOnce = Total(boxE) - beforeRaise
    local raised = Frames(boxE, 3)
    assert(raisedAtOnce == 3 and table.concat(raised, ",") == "3,3,1" and Total(boxE) == 12, raisedAtOnce .. " then " .. table.concat(raised, ","))
    -- (f) the any group (Sunder: WoW Forever only) ramps by the same rule and shares the budget; it is granted first
    NS.Client.isForever = true
    local forever = { auraDisplayEnabled = true, auraEnemyDotsVisible = true, auraEnemyDotsDisplay = 2, auraEnemyDotsMax = 10,
        auraEnemyDotsOnlyMine = true, auraSunder = true, auraEnemyDotsSource = 2, auraEnemyDotsIDsRetail = "589" }
    config, module.config = forever, forever
    D.Configure(forever)
    presentDefault.auras, presentDefault.any = 10, 1
    local f = Plate()
    local firstF = #frames + 1
    assert(D.Apply(f, "nameplate40", true) == true)
    local boxF = Containers(firstF)
    local dots = boxF[1]
    assert(#boxF == 1 and dots.groups.any and dots.groups.auras, "the dots container has no any group")
    local rows = { { dots.groups.auras.made, dots.groups.any.made } }
    for _ = 1, 5 do
        Frames(boxF, 1)
        rows[#rows + 1] = { dots.groups.auras.made, dots.groups.any.made }
    end
    local text = {}
    for index, row in ipairs(rows) do text[index] = row[1] .. "/" .. row[2] end
    -- 2026-11-11, measured (auras/any per frame): the frame of the Apply takes both groups' allowances (3 + 1 of 6),
    -- then the auras group takes three a frame
    assert(table.concat(text, ",") == "3/1,6/1,9/1,10/1,10/1,10/1", table.concat(text, ","))
    for index = 2, #rows do
        local made = (rows[index][1] - rows[index - 1][1]) + (rows[index][2] - rows[index - 1][2])
        assert(made <= 6, "a frame made " .. made .. " buttons")
    end
    assert(rows[#rows][1] == 10 and rows[#rows][2] == 1 and dots.groups.auras.max == 10 and dots.groups.any.max == 1, "the any group ramp stopped")
    NS.Client.isForever = false
    presentDefault.auras, presentDefault.any = nil, nil
    -- (g) the module stops with a ramp waiting: nothing ticks; a restart resumes the ramp; applying a plate works
    D.Configure(ramp)
    presentDefault.auras = 10
    local g = Plate()
    local firstG = #frames + 1
    assert(D.Apply(g, "nameplate50", true) == true)
    local boxG = Containers(firstG)
    local atStop = Total(boxG)
    D.Configure({ auraDisplayEnabled = false })
    assert(updateFrame.scripts.OnUpdate == nil, "a ramp still ticks after the module stopped")
    local idle = Frames(boxG, 2)
    assert(idle[1] == 0 and idle[2] == 0 and Total(boxG) == atStop, "a stopped module made buttons")
    D.Configure(ramp)
    assert(updateFrame.scripts.OnUpdate ~= nil, "the ramp did not resume after a restart")
    assert(D.Apply(g, "nameplate51", true) == true)
    local resumed = Frames(boxG, 3)
    assert(table.concat(resumed, ",") == "3,3,1" and Total(boxG) == 10, "the restarted ramp made " .. table.concat(resumed, ","))
    D.Configure({ auraDisplayEnabled = false })
    presentDefault.auras = nil
    -- (i) the ramp allocates nothing in a frame that makes no button (2026-11-11). Five plates ramp once as a
    -- warm-up; then five more ramp with the collector stopped. In each frame that ends with a group still waiting, a
    -- second tick at the same clock is measured when it makes no button: the stub makes the buttons, so a tick that
    -- makes one is not measured. A group that waited for the budget finds it spent, so its second tick grants nothing.
    presentDefault.auras = 10
    ramp.auraEnemyCustom1Max = 10
    D.Configure(ramp)
    local function FiveRamp(prefix)
        now = now + 1
        holdFrame = true
        local first = #frames + 1
        for index = 1, 5 do assert(D.Apply(Plate(), prefix .. index, true) == true) end
        holdFrame = false
        return Containers(first)
    end
    local function Settle(list)
        for _ = 1, 40 do
            if not (updateFrame and updateFrame.scripts.OnUpdate) then return end
            Frames(list, 1)
        end
        error("the ramp did not finish")
    end
    Settle(FiveRamp("warm"))
    local list = FiveRamp("measured")
    local measured, worst = 0, 0
    collectgarbage("collect")
    collectgarbage("stop")
    for _ = 1, 40 do
        if not (updateFrame and updateFrame.scripts.OnUpdate) then break end
        Frames(list, 1)
        if updateFrame.scripts.OnUpdate then
            local before, kib = Total(list), collectgarbage("count")
            updateFrame.scripts.OnUpdate(updateFrame)
            local delta = collectgarbage("count") - kib
            if Total(list) == before then
                measured = measured + 1
                if delta > worst then worst = delta end
            end
        end
    end
    collectgarbage("restart")
    print(("aura ramp: %d waiting frames measured, worst %.4f KB"):format(measured, worst))
    assert(measured > 0, "no waiting frame was measured")
    assert(worst < 0.001, "a frame that makes no button allocated " .. worst .. " KB")
    for _, container in ipairs(list) do assert(container.groups.auras.max == 10, "a limit of " .. container.groups.auras.max) end
    D.Configure({ auraDisplayEnabled = false })
end

-- Options workspace and preview
do
    local function load(path, ...)
        local f = assert(io.open(path, "rb")) local s = f:read("*a") f:close()
        return assert(loadstring(s:gsub("\r\n", "\n"), "@" .. path:match("[^/]+$")))(...)
    end
    local methods = {}
    local function Frame(kind, parent)
        return setmetatable({ kind = kind, parent = parent, shown = true, level = 1, calls = {} },
            { __index = function(self, name)
                if methods[name] then return methods[name] end
                return function(this, ...) this.calls[name] = (this.calls[name] or 0) + 1 this[name .. "Args"] = { ... } end
            end })
    end
    function methods:GetFrameLevel() return 1 end
    function methods:GetStringHeight() return 14 end
    function methods:SetShown(v) self.shown = v end
    function methods:Show() self.shown = true end
    function methods:Hide() self.shown = false end
    function methods:CreateTexture() return Frame("Texture", self) end
    function methods:CreateFontString() return Frame("FontString", self) end
    CreateFrame = function(kind, _, parent) return Frame(kind, parent) end
    C_Spell = { GetSpellIDForSpellIdentifier = function() return nil end, GetSpellName = function(id) return "Spell" .. id end,
        GetSpellTexture = function(id) return id end }
    UnitClass = function() return "Mage", "MAGE" end
    local NS = { Client = { isForever = false } }
    NS.Public = function() return true end
    NS.Text = function(s) return s end
    load(up .. "/MSUF_Suite/Core/SuiteCatalog.lua", "MSUF_Suite", NS)
    NS.NameplateAuraColors = { Decode = function() return {} end, Spec = function() return 1 end, Selected = function() return {} end,
        Suggestions = function() return { { id = 589 }, { id = 172 } } end }
    local spec = NS.CatalogBuild.ForAddon("MSUF_Suite_Nameplates").Module("nameplates", { title = "x", look = { key = "look", visualKeys = {}, presets = {} } })
    local B = NS.CatalogBuild
    B.Add("nameplates", B.Choice("look", "Look", 1, { "a", "b", "c", "d" }))
    B.Add("nameplates", B.Bool("enemy", "Enemy", true))
    B.Add("nameplates", B.Bool("friendly", "Friendly", true))
    B.Add("nameplates", B.String("auraColorsData", "x", "", 4096))
    -- Blizzard's aura settings, as Catalog/Nameplates.lua declares them.
    for _, group in ipairs({ "enemyNpc", "enemyPlayer", "friendlyPlayer" }) do
        B.Add("nameplates", B.Choice(group .. "AuraMode", group .. " auras", 1, { "Keep Blizzard setting", "Customize" }), "auras")
        for _, field in ipairs({ "Buffs", "Debuffs", "Control" }) do B.Add("nameplates", B.Bool(group .. field, group .. field, true), "auras") end
    end
    B.Add("nameplates", B.Choice("friendlyNpcDebuffs", "Friendly NPC debuffs", 1, { "Keep Blizzard setting", "Show", "Hide" }), "auras")
    B.Add("nameplates", B.Choice("auraScaleMode", "Blizzard aura icon size", 1, { "Keep Blizzard setting", "Customize" }), "auras")
    B.Add("nameplates", B.Number("auraScalePercent", "Aura icon size (%)", 100, 70, 140, 10), "auras")
    B.Add("nameplates", B.Choice("personalAuras", "Blizzard personal auras", 1, { "Keep Blizzard setting", "Show all", "Blizzard filter" }), "native")
    B.Add("nameplates", B.Bool("auraClickthrough", "Let clicks pass through nameplate auras", false), "native")
    load(out .. "/MSUF_Suite/Core/NameplateAuraDisplay.lua", "MSUF_Suite", NS)
    load(out .. "/MSUF_Suite/Core/Catalog/NameplateAuras.lua", "MSUF_Suite", NS)
    spec.controlAvailable = function(rule) return not rule.client or rule.client == "retail" end
    NS.NameplateStyle = { AuraCVar = {}, AuraBits = {}, NativeBit = function() return true end, NativeToggle = function() return false end,
        CreateBorder = function() return {} end, PaintBorder = function() end }
    NS.ResolveFont = function() end
    NS.GlobalFontPath = function() return "font" end

    local function NewP(bars)
        local config, refreshers, grids, P = { auraDisplayEnabled = true }, {}, {}, nil
        P = { Suite = NS, Tr = function(s) return s end, catalog = NS.SuiteCatalog, refreshes = 0, finished = {}, grids = grids, config = config }
        P.Meta = function(_, _, key) return { settingKey = key } end
        P.Text = function(parent, text) local f = Frame("FontString", parent) f.text = text return f end
        P.Button = function(_, _, label, _, _, _, onClick) local b = Frame("Button") b.click = onClick P.button = b return b end
        P.AttachRuleColors = function(_, _, _, rules) P.colors = #rules end
        P.SetTranslatedText = function(f, text) f.text = text end
        P.Refresh = function() P.refreshes = P.refreshes + 1 for _, fn in ipairs(refreshers) do fn() end end
        P.Combat = function() return false end
        P.Get = function(_, key) local v = config[key] if v == nil then return spec.rules[key].default end return v end
        P.Set = function(_, key, value) assert(spec.rules[key], key) config[key] = value return true end
        P.SetMany = function(_, values) for k, v in pairs(values) do assert(spec.rules[k], k) config[k] = v end return true end
        P.M = { cache = {}, TrackRefresh = function(_, fn) refreshers[#refreshers + 1] = fn end,
            BindTextInputAt = function(_, parent, _, _, _, _, _, set) local i = Frame("EditBox", parent) i.set = set return i end }
        P.W = { SettingsRows = function(_, parent, s)
            local grid = { controls = {}, bottomY = s.y - 60, rows = s.rows }
            for _, row in ipairs(s.rows) do grid.controls[row.id] = Frame("Control", parent) end
            grids[#grids + 1] = grid
            return grid
        end }
        if bars then
            P.bars = {}
            P.W.ScopeOverrideBar = function(_, section, opts)
                local bar = Frame("Bar", section)
                bar.label, bar.buttons, bar.opts = Frame("FontString"), { Frame("Button"), Frame("Button") }, opts
                bar.GetLayoutMetrics = function() return { bottomY = opts.centerY - 14 } end
                P.bars[#P.bars + 1] = bar
                return bar
            end
        end
        P.gridKeys = {}
        P.Description = function(parent, text) local f = Frame("FontString", parent) f.text = text return f end
        P.NameplateAuraPositionKeys = function(side, elements)
            local keys = {}
            for _, element in ipairs(elements) do keys[#keys + 1] = side .. element .. "OffsetX" keys[#keys + 1] = side .. element .. "OffsetY" end
            return keys
        end
        P.RuleGrid = function(_, panel, _, _, rules, y, _, _, _, columns)
            local labels = {}
            for index, rule in ipairs(rules) do
                labels[index] = rule.label
                assert(spec.rules[rule.key] and rule.key and rule.default ~= nil)
                assert(not P.gridKeys[rule.key], rule.key .. " has two controls")
                P.gridKeys[rule.key] = true
            end
            panel.grids = rawget(panel, "grids") or {}
            panel.grids[#panel.grids + 1] = { labels = labels, columns = columns }
            return y - 30 * #rules, {}
        end
        P.HM = { GetSectionWidth = function() return 700 end, GetSectionEntry = function() return {} end,
            GetSectionEnsureVisible = function() return function() P.revealed = (P.revealed or 0) + 1 end end }
        P.LazySection = function(_, id, _, _, s)
            local body = Frame("Section") body.id = id
            s.shell(body)
            s.finish(body, s.content(body))
            return body
        end
        P.AttachSectionReset = function(_, body, _, reset) body.reset = reset end
        P.SectionRules = function(_, section) local o = {} for _, r in ipairs(spec.controls) do if r.section == section and spec.controlAvailable(r) then o[#o + 1] = r end end return o end
        P.ResetRules = function(_, rules, _, extra)
            P.resetCount, P.resetExtra = #rules, extra
            for _, r in ipairs(rules) do config[r.key] = nil end
            return true
        end
        P.FinishBody = function(_, _, y) P.finished[#P.finished + 1] = y end
        P.EnsureSectionContent = function() end
        P.StylePreviewFont = function() end
        P.RGB = function() return 1, 1, 1 end
        P.S = { Config = function() return config end }
        load(out .. "/MSUF_Suite_Options/Pages/NameplatesAdvancedAuras.lua", "MSUF_Suite_Options", P)
        return P, config
    end

    local function BarKind(bar)
        local values = bar.opts.values
        if #values == 5 then return "lane" end
        return values[5].value == "whitelist" and "custom" or "dots"
    end
    local function SetTool(P, kind, tool)
        if not P.bars then return P.grids[1].rows[3].set(tool) end
        for i = 3, 5 do if BarKind(P.bars[i]) == kind then P.bars[i].opts.setValue(tool) end end
    end
    for _, bars in ipairs({ true, false }) do
        local P, config = NewP(bars)
        local UI = P.NameplatesAdvancedAuras
        local sections = {}
        UI.Append(sections, { auras = { summary = "Which Blizzard auras each kind of plate shows." } })
        assert(#sections == 1 and sections[1].key == "auraWorkspace" and sections[1].build == UI.Build and #sections[1].colors == 3)
        local placed = {}
        for _, key in ipairs(sections[1].keys) do assert(spec.rules[key], key) placed[key] = true end
        assert(placed.auraFriendlyDotsVisible and placed.auraEnemyCustom3StackPoint and placed.auraSunder and not placed.auraEnemyDotsIDsRetail)
        -- Blizzard's own aura settings, the master switch and the shared look all live in the workspace
        for _, key in ipairs({ "enemyNpcAuraMode", "enemyPlayerControl", "friendlyPlayerBuffs", "friendlyNpcDebuffs", "auraScalePercent",
            "personalAuras", "auraClickthrough", "auraDisplayEnabled", "auraFont", "auraHighlightSize", "auraEnemyBuffVisible",
            "auraFriendlyDebuffFilter" }) do assert(placed[key], key .. " has no place in the workspace") end
        local body = sections[1].build({}, { width = 720 }, sections[1])
        assert(#P.finished == 1 and P.finished[1] < -100, "workspace reported no height")
        -- the page opens on Buffs > Layout: master switch, the lane's layout, then Blizzard's settings for it
        assert(P.gridKeys.auraDisplayEnabled and P.gridKeys.auraEnemyBuffVisible and P.gridKeys.auraEnemyBuffPerRow
            and P.gridKeys.enemyNpcAuraMode and P.gridKeys.enemyPlayerBuffs and P.gridKeys.auraScalePercent and not P.gridKeys.enemyNpcDebuffs)
        assert(P.colors == 3, "the shared aura colors lost their menu")
        if bars then
            assert(#P.bars == 5 and P.bars[2].opts.label == "Container:" and #P.bars[2].opts.values == 6
                and P.bars[2].opts.values[1].value == "buff" and P.bars[2].opts.values[6].value == "dots")
            -- only the tool bar of the selected container kind shows
            for i = 3, 5 do assert(P.bars[i].shown == (BarKind(P.bars[i]) == "lane"), "Edit bar does not follow the container kind") end
            assert(P.bars[3].opts.label == "Edit:")
            P.bars[2].opts.setValue("dots")
            assert(P.refreshes == 1 and #P.finished == 2)
            for i = 3, 5 do
                local dots = BarKind(P.bars[i]) == "dots"
                assert(P.bars[i].shown == dots and P.bars[i].buttons[1].shown == dots, "Edit bar does not follow the container kind")
            end
        else
            assert(#P.grids == 1 and #P.grids[1].rows == 3 and #P.grids[1].rows[2].values() == 6 and #P.grids[1].rows[3].values() == 5)
            P.grids[1].rows[2].set("dots")
            assert(#P.grids[1].rows[3].values() == 6 and P.grids[1].rows[3].values()[5].value == "dots")
        end
        -- every Blizzard tab of both plates: each setting keeps exactly one control (P.RuleGrid asserts it)
        for _, key in ipairs({ "enemyPlayerDebuffs", "friendlyPlayerBuffs", "friendlyNpcDebuffs", "enemyNpcBuffs" }) do sections[1].prepare(key) end
        assert(P.gridKeys.friendlyPlayerAuraMode and P.gridKeys.enemyNpcControl and P.gridKeys.friendlyPlayerControl)
        -- a lane resets its own settings, its Blizzard switches and the dragged positions, not the shared mode
        sections[1].prepare("enemyPlayerDebuffs")
        config.enemyNpcAuraMode, config.enemyNpcDebuffs, config.auraEnemyDebuffSize, config.auraEnemyBuffSize = 2, false, 40, 41
        body.reset()
        assert(config.enemyNpcDebuffs == nil and config.auraEnemyDebuffSize == nil and config.enemyNpcAuraMode == 2 and config.auraEnemyBuffSize == 41)
        assert(#P.resetExtra == 4 and P.resetExtra[1] == "enemyAurasOffsetX" and P.resetExtra[4] == "enemyControlAuraOffsetY")
        -- every Style view shows the shared look below its own; it has one control each
        sections[1].prepare("auraFont")
        assert(P.gridKeys.auraFont and P.gridKeys.auraEnemyBuffZoom)
        sections[1].prepare("auraFriendlyCustom2Zoom")
        sections[1].prepare("auraEnemyDebuffSort")
        -- Global Aura Appearance opens the Style tool of the shown container
        P.button.click()
        assert(P.gridKeys.auraEnemyDebuffZoom, "Global Aura Appearance did not open Style")
        -- the Blacklist of a lane edits this client's list
        sections[1].prepare("auraFriendlyBuffVisible")
        SetTool(P, "lane", "blacklist")
        assert(P.grids[#P.grids].rows[1].label == "Add blocked aura")
        P.grids[#P.grids].rows[1].set(589)
        assert(config.auraFriendlyBuffBlockRetail == "589")
        -- search / preview jump selects plates, container and tool
        sections[1].prepare("auraFriendlyCustom2Gap")
        assert(P.revealed and P.refreshes >= 2)
        sections[1].prepare("auraEnemyDotsVisible")
        sections[1].prepare("auraEnemyDotsIDsRetail")   -- hidden list: no jump, no error
        -- the whitelist tool edits this client's list only
        config.auraEnemyCustom1SpellsForever = "999"
        sections[1].prepare("auraEnemyCustom1Sort")
        SetTool(P, "custom", "whitelist")
        local listGrid = P.grids[#P.grids]
        assert(listGrid.rows[1].label == "Add allowed aura" and #listGrid.rows[1].values() == 2)
        listGrid.rows[1].set(589)
        listGrid.rows[1].set(172)
        listGrid.rows[1].set(589)
        assert(config.auraEnemyCustom1SpellsRetail == "589,172" and config.auraEnemyCustom1SpellsForever == "999")
        listGrid.rows[2].set(589)
        assert(config.auraEnemyCustom1SpellsRetail == "172")
        -- a custom DoT selects the custom list as source
        sections[1].prepare("auraEnemyDotsSource")
        SetTool(P, "dots", "dots")
        P.grids[#P.grids].rows[1].set(34914)
        assert(config.auraEnemyDotsIDsRetail == "34914" and config.auraEnemyDotsSource == 2)
        -- reset: the shown container on this client only
        body.reset()
        assert(config.auraEnemyDotsIDsRetail == nil and config.auraEnemyCustom1SpellsForever == "999" and config.auraEnemyCustom1SpellsRetail == "172")
        -- preview: only enabled containers show, handles bind once per container
        config.enemy, config.auraEnemyDotsVisible, config.auraEnemyDotsIDsRetail, config.auraEnemyDotsSource = true, true, "1,2,3", 2
        local sample = { prefix = "enemy", cell = Frame("Frame"), bar = Frame("Frame"), buffs = Frame("Frame"), auras = Frame("Frame") }
        local bound = {}
        local editor = { LayerOn = function() return true end, Bind = function(_, frame, id, _, kx, ky) bound[id] = { frame, kx, ky } end }
        UI.Render(editor, sample, {})
        UI.Render(editor, sample, {})
        assert(bound["enemy.Tracked"][2] == "auraEnemyDotsOffsetX" and bound["enemy.CustomTwo"][3] == "auraEnemyCustom2OffsetY")
        assert(bound["enemy.Tracked"][1].shown == true and bound["enemy.CustomTwo"][1].shown == false)
        assert(#sample.auraPreviewState.containers.dots.icons == 3)
        assert(NS.NameplateAuraDisplay.Element("enemy.Tracked") and not NS.NameplateAuraDisplay.Element("enemy.Health"))
        -- a Visible lane paints over the preview's Blizzard sample and keeps Blizzard's handle; off, the sample returns
        assert(not bound["enemy.Buffs"] and not rawget(sample.buffs, "SetPointArgs"))
        config.auraEnemyBuffVisible = true
        UI.Render(editor, sample, {})
        assert(sample.buffs.SetPointArgs[1] == "RIGHT" and sample.buffs.SetPointArgs[4] == -6 and sample.buffs.SetSizeArgs[2] == 41)
        local lanes = sample.auraPreviewState.lanes
        assert(lanes.buff.painted and #lanes.buff.icons == 3 and not lanes.debuff)
        config.auraEnemyBuffVisible = false
        UI.Render(editor, sample, {})
        assert(lanes.buff.painted == false and lanes.buff.overlay.shown == false)
    end
    -- short labels reach the grid, the catalog keeps the full ones
    local P = NewP(true)
    local UI = P.NameplatesAdvancedAuras
    local sections = {}
    UI.Append(sections, {})
    sections[1].build({}, { width = 720 }, sections[1])
    sections[1].prepare("auraEnemyCustom1Size")
    assert(spec.rules.auraEnemyCustom1Size.label == "Enemy: Custom 1 icon size")
end
print("nameplate aura display contract: ok")

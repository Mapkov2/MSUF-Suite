-- Nameplate auras, laid out like MSUF's unit frame Auras: Buffs, Debuffs,
-- Control effects, Custom 1-3 and Dots on target. Buffs and Debuffs use
-- the built-in lists. Covers the cold
-- model and its catalog rules, the migration of the former tracked DoT
-- slots, the native aura container runtime and the options workspace with
-- its preview.
local root = assert(arg[1], "repository root required")
local up, out = root, root
wipe = function(t) for k in pairs(t) do t[k] = nil end return t end
canaccesstable = function(t) return t.accessible ~= false end

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
    assert(count > 255, "container rules are missing")
    -- every tool key exists, every rule gated
    for _, scope in ipairs(M.Scopes) do for _, c in ipairs(M.Containers) do
        for _, tool in ipairs(M.Tools[c.kind]) do
            for _, key in ipairs(M.ToolKeys(scope, c, tool)) do assert(spec.rules[key], key) end
        end
        assert(spec.rules[M.ListKey(scope, c, "Retail")].client == "retail" and spec.rules[M.ListKey(scope, c, "Forever")].hidden)
    end end
    assert(not spec.rules.auraEnemyDebuffUseLayout and not spec.rules.auraEnemyDebuffBlockRetail)
    assert(not spec.rules.auraEnemyDebuffScale.enableKey and spec.rules.auraEnemyCustom1Size.enableKey == "auraDisplayEnabled")
    assert(not spec.look.visualKeys.auraEnemyDotsVisible and spec.look.visualKeys.auraFont)
    local plan = M.Plan({})
    assert(not plan.used.enemy and not plan.used.friendly)
    local personal = { auraDisplayEnabled = true, auraEnemyCustom1Visible = true,
        auraEnemyCustom1OnlyMine = true, auraEnemyCustom1MaxDuration = 30, auraEnemyCustom1HideDuplicates = true }
    local filtered = M.Plan(personal)
    local flow = C(filtered, "enemy", "custom1")
    assert(flow.enabled and filtered.always.enemy and flow.groupCount == 8,
        "an enabled Custom Debuff flow row with an empty list did not show active debuffs")
    assert(flow.candidate.includeSpellIDs == nil and flow.candidate.maxDuration == 30
        and flow.filter == "HARMFUL|PLAYER|INCLUDE_NAME_PLATE_ONLY", "empty list bypassed the selected aura filters")
    assert(not filtered.exclusions.enemy, "a row without spell IDs claimed duplicates")
    personal.auraEnemyCustom1Display = 1
    assert(not C(M.Plan(personal), "enemy", "custom1").enabled, "fixed slots must have configured spells")
    personal.auraEnemyCustom1Display, personal.auraEnemyCustom1SpellsRetail = 2, "garbage"
    assert(not C(M.Plan(personal), "enemy", "custom1").enabled, "a malformed nonempty list must not track every spell")
    local inherited = M.Plan({ auraClickthrough = true, auraEnemyCustom1Clickthrough = 3 })
    assert(not C(inherited, "enemy", "custom1").clickthrough and C(inherited, "enemy", "custom2").clickthrough
        and C(inherited, "friendly", "custom1").clickthrough, "tracked rows did not inherit the saved click-through setting independently")
    local explicit = M.Plan({ auraClickthrough = false, auraFriendlyDotsClickthrough = 2 })
    assert(C(explicit, "friendly", "dots").clickthrough and not C(explicit, "enemy", "dots").clickthrough,
        "tracked row did not enable click-through independently")
    local config = { enemyNpcAuraMode = 2, enemyNpcBuffs = false, enemyNpcControl = true, auraEnemyBuffUseLayout = true }
    assert(not M.Active(config) and not C(M.Plan(config), "enemy", "buff"))
    assert(not M.NativeShown(config, "enemyNpc", "Buffs") and M.NativeShown(config, "enemyNpc", "Control"))
    assert(M.NativeSetting("friendlyNpc", "Debuffs") == "friendlyNpcDebuffs" and not M.NativeSetting("friendlyNpc", "Buffs"))
    -- enemy dots from the health-colour DoTs, fixed slots
    local config = { auraDisplayEnabled = true, auraEnemyDotsVisible = true }
    plan = M.Plan(config)
    local dots = C(plan, "enemy", "dots")
    assert(dots.key == "dots" and dots.enabled and dots.fixed and #dots.rows == 1 and dots.rows[1].id == 589)
    assert(dots.rows[1].filter == "HARMFUL|PLAYER|INCLUDE_NAME_PLATE_ONLY" and dots.rows[1].candidate.includeSpellIDs[34914])
    assert(dots.point == "BOTTOM" and dots.relative == "TOP" and dots.y == 46 and dots.missing == true)
    assert(plan.used.enemy and not plan.used.friendly)
    config.auraEnemyDotsHideDuplicates = true
    plan = M.Plan(config)
    assert(not plan.always.enemy and plan.exclusions.enemy.debuff[589] and plan.exclusions.enemy.debuff[34914],
        "target-only tracking must not allocate containers on other plates")
    assert(not plan.exclusions.enemy.debuff[172], "a disabled DoT was excluded")
    config.auraEnemyCustom1Visible, config.auraEnemyCustom1SpellsRetail = true, "589,118"
    config.auraEnemyCustom2Visible, config.auraEnemyCustom2SpellsRetail = true, "139"
    config.auraEnemyCustom2Type, config.auraEnemyCustom2HideDuplicates = 1, true
    local excluded = M.Plan(config).exclusions.enemy
    assert(not excluded.custom1 and not excluded.dots,
        "target-only DoT tracking must not exclude other tracked rows on every plate")
    assert(excluded.buff[139] and not excluded.buff[589] and not excluded.debuff[139],
        "buff and debuff exclusions were mixed")
    config.auraEnemyCustom1Visible, config.auraEnemyCustom2Visible = nil, nil
    config.auraEnemyDotsHideDuplicates = nil
    plan = M.Plan(config)
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
    assert(not C(plan, "enemy", "buff") and not C(plan, "enemy", "debuff"))
    assert(table.concat(M.Tools.native, " ") == "layout style")
    assert(M.ToolKeys(M.Scope("enemy"), M.Container("buff"), "layout", true)[1] == "auraEnemyBuffScale")
    -- text inheritance
    config.auraEnemyDotsTimePoint, config.auraEnemyDotsStackSize = 2, 20
    plan = M.Plan(config)
    dots = C(plan, "enemy", "dots")
    assert(dots.text.Time.point == "TOPLEFT" and dots.text.Time.size == 11 and dots.text.Stack.size == 20 and dots.text.Stack.point == "BOTTOMRIGHT" and dots.text.Stack.x == -1)
    -- the other client reads its own list; Sunder joins as an every-player slot
    local F = NewNS(true)
    F.HostBridge = { ForeverAuraAliases = function(id) if id == 11 then return { 11, 12 } end end }
    local FM = F.NameplateAuraDisplay
    config.auraSunder = true
    local fplan = FM.Plan(config)
    assert(C(fplan, "friendly", "custom1").candidate.includeSpellIDs[1126] and not C(fplan, "friendly", "custom1").candidate.includeSpellIDs[774])
    local fdots = C(fplan, "enemy", "dots")
    assert(#fdots.rows == 1 and fdots.rows[1].any and fdots.rows[1].filter == "HARMFUL|INCLUDE_NAME_PLATE_ONLY", "forever dots")
    config.auraEnemyDotsDisplay, config.auraEnemyDotsIDsForever = 2, "11"
    config.auraFriendlyCustom1SpellsForever = "11,12"
    local buff = C(FM.Plan(config), "friendly", "custom1")
    assert(buff.candidate.includeSpellIDs[12] and #buff.rows == 1, "a ranked buff did not resolve to a single tracked row")
    fdots = C(FM.Plan(config), "enemy", "dots")
    assert(fdots.groupCount == 8 and fdots.anyCount == 1 and fdots.anyCandidate.includeSpellIDs[7386]
        and fdots.candidate.includeSpellIDs[11] and fdots.candidate.includeSpellIDs[12], "Forever rank was not tracked")
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
    local publicCombat = false
    local methods, dispelCalls = {}, {}
    local now, holdFrame, presentDefault = 100, false, {}
    local rampQueued, rampCallback
    local buildWaits = {}
    -- Blizzard seals an aura button, and with it everything on it, as soon as
    -- initializeFrame returns (DenyTaintedAccessWhenAurasAreSecret,
    -- Blizzard_AuraContainerFrameProviders.lua CreateFrame). While auras are
    -- secret every call of ours on a sealed object raises.
    local function Refused(frame)
        if not (combat and not publicCombat or secret) then return false end
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
    function methods:GetScale() return 1 end
    function methods:GetAlpha() return rawget(self, "alpha") or 1 end
    function methods:SetAlpha(value) self.alpha, self.SetAlphaArgs = value, { value } end
    function methods:IsAnchoringRestricted() return false end
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
    function methods:IsProtected() return rawget(self, "protected") == true end
    function methods:CanBeAccessedInContext() return not rawget(self, "sealed") and not Refused(self) end
    local function AuraButton(container, initializeFrame)
        local button = Frame("AuraButton", container)
        initializeFrame(button)
        button.restricted = true
        return button
    end
    function methods:IsShown() return self.shown end
    function methods:IsVisible()
        local parent = rawget(self, "parent")
        return self.shown and (not parent or parent:IsVisible())
    end
    function methods:SetShown(v) self.shown = v local cb = self.scripts[v and "OnShow" or "OnHide"] if cb then cb(self) end end
    function methods:Show() self:SetShown(true) end
    function methods:Hide() self:SetShown(false) end
    function methods:HookScript(e, cb) self.scripts[e] = cb end
    function methods:GetParent() return self.parent end
    function methods:IsMouseClickEnabled() return rawget(self, "click") ~= false end
    function methods:IsMouseMotionEnabled() return rawget(self, "motion") ~= false end
    function methods:SetMouseClickEnabled(value) self.click = value end
    function methods:SetMouseMotionEnabled(value) self.motion = value end
    function methods:SetScript(event, callback)
        assert(event ~= "OnUpdate" or not callback, "aura allocation attached a frame update script")
        self.scripts[event] = callback
    end
    function methods:RegisterEvent(e) self.events = rawget(self, "events") or {} self.events[e] = true end
    function methods:UnregisterAllEvents() self.events = {} end
    function methods:CreateTexture(_, layer) local texture = Frame("Texture", self) texture.drawLayer = layer return texture end
    function methods:CreateMaskTexture() return Frame("MaskTexture", self) end
    function methods:CreateFontString() return Frame("FontString", self) end
    function methods:SetEnabled(v) self.enabled = v end
    function methods:SetUnit(u) self.unit = u end
    function methods:AddAuraSlot(key, filter, options)
        self.slots = rawget(self, "slots") or {}
        self.slots[key] = { filter = filter, candidate = options.candidateFilters }
        log[#log + 1] = "slot:" .. key
        self.slots[key].button = AuraButton(self, options.initializeFrame)
    end
    function methods:GetAuraSlotFrame(key) return self.slots[key].button end
    function methods:SetAuraSlotCandidateFilters(key, c) self.slots[key].candidate = c log[#log + 1] = "slotc:" .. key end
    function methods:SetAuraSlotFilterString(key, f) self.slots[key].filter = f end
    -- Blizzard makes a group's buttons on demand: min(auras, limit). SetAuraGroupMaxFrameCount only stores the limit;
    -- the stub makes the buttons it allows at once (Blizzard makes them on its next refresh, through initializeFrame).
    local function Fill(frame, key)
        local group = frame.groups[key]
        local want = math.min(presentDefault[key] or 1, group.max)
        while group.made < want do
            group.made = group.made + 1
            group.buttons[group.made] = AuraButton(frame, group.init)
        end
    end
    function methods:AddAuraGroup(key, filter, options)
        self.groups = rawget(self, "groups") or {}
        self.groups[key] = { filter = filter, candidate = options.candidateFilters, max = options.maxFrameCount, init = options.initializeFrame, made = 0,
            buttons = {} }
        log[#log + 1] = "group:" .. key
        Fill(self, key)
    end
    function methods:SetAuraGroupCandidateFilters(key, c) self.groups[key].candidate = c end
    function methods:GetAuraGroupFrameCount(key) return self.groups[key].made end
    function methods:GetAuraGroupFrame(key, index) return self.groups[key].buttons[index] end
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
    AuraUtil.AuraFilters = { CrowdControl = "CROWD_CONTROL", Important = "IMPORTANT" }
    CreateColor = function(r, g, b, a) return BlizzardColor(r, g, b, a) end
    Enum = { CustomAuraButtonDispelTypeTextureStyle = { CustomAsset = 1 },
        StatusBarTimerDirection = { ElapsedTime = 1, RemainingTime = 2 }, NumericRuleFormatRounding = { Up = 1, Down = 2 } }
    C_Spell = { GetSpellTexture = function(id) return id end }
    C_Secrets = { ShouldAurasBeSecret = function() return combat and not publicCombat or secret end }
    C_StringUtil = { CreateNumericRuleFormatter = function()
        return { SetBreakpoints = function(formatter, breakpoints) formatter.breakpoints = breakpoints end }
    end }
    UnitClass = function() return "Mage", "MAGE" end
    local targetUnit
    UnitIsUnit = function(unit) return targetUnit == nil or targetUnit == unit end
    hooksecurefunc = function(object, name, hook)
        local original = object[name]
        object[name] = function(...) original(...) hook(...) end
    end
    local iconLook, painted, watching = {}, {}, nil
    local NS = { HostBridge = {
        ForeverAuraAliases = function() end,
        IconSkinLook = function(choice, shape, _, allowVariant)
            assert(choice == nil and shape == "RECTANGLE" and allowVariant)
            return iconLook
        end,
        WatchIconSkins = function(id, on) assert(id == "nameplates") watching = on end,
        PaintIconSkin = function(button, look, width, height, icon, clip)
            assert(not Refused(button) and not Refused(icon) and button.kind == "AuraButton" and clip)
            assert(width == 24 and height == 24)
            painted[button] = look
            return look ~= nil
        end,
    }, Client = { isForever = false, AuraBuildBlocked = function() return blocked end,
        AfterAuraBuild = function(owner, callback) log[#log + 1] = "afterbuild"; buildWaits[owner] = callback end,
        CancelAuraBuild = function(owner) buildWaits[owner] = nil end,
        RealAurasOnly = function() return true end }, Safety = { IsForbidden = function() return false end } }
    NS.Public = function() return true end
    NS.Finite = function(value) return type(value) == "number" end
    NS.Text = function(s) return s end
    NS.RGB = function() return 1, 1, 1 end
    NS.InCombat = function() return combat end
    NS.IsCombatLocked = NS.InCombat
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
    S.Public, S.Finite = NS.Public, NS.Finite
    NamePlateConstants = { AURA_ITEM_HEIGHT = 25 }
    load(out .. "/MSUF_Suite_Nameplates/Auras.lua", "MSUF_Suite_Nameplates", private)
    load(out .. "/MSUF_Suite_Nameplates/AuraFilter.lua", "MSUF_Suite_Nameplates", private)
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
        uf.AurasFrame.CrowdControlListFrame = Frame("Frame", uf.AurasFrame)
        function uf.AurasFrame:RefreshList() end
        function uf.AurasFrame:RefreshAuras()
            self:RefreshList(self.DebuffListFrame)
            self:RefreshList(self.BuffListFrame)
            self:RefreshList(self.CrowdControlListFrame)
        end
        uf.isPlayer = false
        uf.AurasFrame.isActive = true
        uf.AurasFrame.auraItemScale = 1
        uf.AurasFrame.DebuffListFrame.stride = 8
        uf.AurasFrame.BuffListFrame.stride = 10
        return uf
    end
    local active = {}
    local cvarEvent
    local module = { active = true,
        context = { Event = function(_, _, callback) cvarEvent = callback end, RemoveEvent = function() cvarEvent = nil end } }
    function module.context:Coalesce(delay, callback)
        assert(delay == 0 and not rampCallback, "the ramp must reuse one job")
        rampCallback = callback
        return { Request = function() rampQueued = true end, Cancel = function() rampQueued = false end }
    end
    local function RunRamp()
        if not rampQueued then return end
        rampQueued = false
        rampCallback(module)
    end
    module.auraHooks, module.auraButtons, module.config = {}, {}, {}
    private.Auras.Bind(module)
    D.Bind(module, function() repaints = repaints + 1 for uf, a in pairs(active) do D.Apply(uf, a[1], a[2]) end end)
    local function Containers() local n = 0 for _, f in ipairs(frames) do if f.kind == "AuraContainer" then n = n + 1 end end return n end

    do
        local cfg = { auraDisplayEnabled = true, auraEnemyDotsVisible = true, auraEnemyDotsSource = 2,
            auraEnemyDotsIDsRetail = "589,34914", auraEnemyDotsHideDuplicates = true }
        local target, other = Plate(), Plate()
        local buttons, different = {}, {}
        for _, uf in ipairs({ target, other }) do
            local auras = uf.AurasFrame
            local lane = auras.DebuffListFrame
            lane.requireSourceIsLocalPlayer = true
            local duplicate, unrelated = Frame("NativeAuraButton", lane), Frame("NativeAuraButton", lane)
            duplicate.spellID, unrelated.spellID = 589, 1234
            buttons[uf], different[uf] = duplicate, unrelated
            auras.auraItemFramePool = {
                GetNextActive = function(_, current)
                    if current == nil then return duplicate end
                    if current == duplicate then return unrelated end
                end,
            }
        end
        target.unit, target.isFriend, other.unit, other.isFriend = "nameplate30", false, "nameplate31", false
        local nativeRefresh = target.AurasFrame.RefreshAuras
        targetUnit = "nameplate30"
        D.Configure(cfg)
        assert(D.Apply(target, "nameplate30", true) and not D.Apply(other, "nameplate31", true))
        assert(target.AurasFrame.RefreshAuras == nativeRefresh, "dedup wrapped Blizzard's UNIT_AURA entry point")
        local function Find(plate)
            for _, frame in ipairs(frames) do
                if frame.kind == "AuraContainer" and frame.parent.parent == plate and rawget(frame, "slots") then return frame end
            end
        end
        local dots, native, duplicate = assert(Find(target)), target.AurasFrame.DebuffListFrame, buttons[target]
        local slot = dots.slots.slot1.button
        local afterAura
        C_Timer = { After = function(_, callback) afterAura = callback end }
        local function DrainAuraRefresh()
            if afterAura then
                local callback = afterAura
                afterAura = nil
                callback()
            end
        end
        local function Refresh()
            target.AurasFrame:RefreshAuras()
            DrainAuraRefresh()
        end
        local function AuraEvent(event)
            for _, frame in ipairs(frames) do
                if rawget(frame, "events") and frame.events[event] then frame.scripts.OnEvent(frame, event) end
            end
        end
        assert(dots.enabled and not Find(other), "target-only DoT display leaked")
        assert(duplicate:GetAlpha() == 0 and not duplicate:IsMouseClickEnabled()
            and different[target]:GetAlpha() == 1 and buttons[other]:GetAlpha() == 1 and native:GetAlpha() == 1,
            "only a confirmed duplicate on the target may be hidden")
        target.AurasFrame:RefreshAuras()
        slot:Hide()
        local callback = assert(afterAura)
        afterAura = nil
        callback()
        assert(duplicate:GetAlpha() == 1 and duplicate:IsMouseClickEnabled(), "empty replacement hid the native icon")
        slot:Show()
        duplicate.parent = target.AurasFrame.BuffListFrame
        Refresh()
        assert(duplicate:GetAlpha() == 1 and duplicate:IsMouseMotionEnabled(), "recycled buff kept stale aura state")
        duplicate.parent = native
        combat = true
        Refresh()
        assert(duplicate:GetAlpha() == 1 and different[target]:GetAlpha() == 1, "restricted replacement hid native icons")
        combat = false
        Refresh()
        assert(duplicate:GetAlpha() == 0)
        AuraEvent("PLAYER_REGEN_DISABLED")
        assert(duplicate:GetAlpha() == 1, "combat entry left an old native icon hidden")
        combat, publicCombat = true, true
        duplicate.protected = true
        DrainAuraRefresh()
        assert(duplicate:GetAlpha() == 1, "dedup touched a protected native icon during combat")
        duplicate.protected = nil
        Refresh()
        assert(duplicate:GetAlpha() == 0, "public combat incorrectly skipped confirmed duplicates")
        secret = true
        AuraEvent("AURA_DATA_PROVIDER_SWITCH")
        DrainAuraRefresh()
        assert(duplicate:GetAlpha() == 1 and duplicate:IsMouseClickEnabled(), "restricted data left a recycled icon hidden")
        combat, publicCombat, secret = false, false, false
        AuraEvent("PLAYER_REGEN_ENABLED")
        DrainAuraRefresh()
        assert(duplicate:GetAlpha() == 0, "ending combat did not recover dedup without another aura update")
        cfg.auraEnemyDotsDisplay = 2
        local auras = { { spellId = 589 } }
        local auraFilter = "HARMFUL|PLAYER|INCLUDE_NAME_PLATE_ONLY"
        C_UnitAuras = { GetUnitAuras = function(unit, filter)
            assert(unit == "nameplate30" or unit == "nameplate31")
            assert(filter == auraFilter)
            return auras
        end }
        D.Configure(cfg)
        assert(D.Apply(target, "nameplate30", true))
        local group = dots.groups.auras
        assert(group.made == 1 and duplicate:GetAlpha() == 0, "the packed DoT never took over its native icon")
        combat, publicCombat = true, true
        Refresh()
        assert(duplicate:GetAlpha() == 0, "public combat did not deduplicate the packed DoT")
        combat, publicCombat = false, false
        auras[2] = { spellId = 34914 }
        Refresh()
        assert(duplicate:GetAlpha() == 1, "a packed group at capacity hid a potentially unrendered aura")
        auras[2] = nil
        auras[1].accessible = false
        Refresh()
        assert(duplicate:GetAlpha() == 1, "unreadable aura data hid the original")
        auras[1].accessible = nil
        group.buttons[1]:Hide()
        Refresh()
        assert(duplicate:GetAlpha() == 1, "an empty packed group hid a native icon")
        group.buttons[1]:Show()
        Refresh()
        assert(duplicate:GetAlpha() == 0)
        targetUnit = "nameplate31"
        D.TargetChanged(other)
        assert(not dots.enabled and duplicate:GetAlpha() == 1 and buttons[other]:GetAlpha() == 0,
            "target switch did not restore the old lane and deduplicate the new one")
        cfg.auraEnemyDotsType, cfg.auraEnemyDotsOnlyMine = 1, false
        auraFilter = "HELPFUL|INCLUDE_NAME_PLATE_ONLY"
        buttons[other].parent = other.AurasFrame.BuffListFrame
        D.Configure(cfg)
        assert(D.Apply(other, "nameplate31", true) and buttons[other]:GetAlpha() == 0,
            "the same packed filter must deduplicate Buffs")
        cfg.auraEnemyDotsHideDuplicates = false
        D.Configure(cfg)
        D.Apply(other, "nameplate31", true)
        assert(buttons[other]:GetAlpha() == 1 and buttons[other]:IsMouseClickEnabled(), "disabling dedup failed to restore Blizzard")
        D.Release()
        targetUnit = nil
        for index = #frames, 1, -1 do frames[index] = nil end
        for index = #log, 1, -1 do log[index] = nil end
    end

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
    config.auraEnemyCustom1SpellsRetail, config.auraEnemyCustom1OnlyMine = "", true
    D.Configure(config)
    assert(D.Apply(uf, "nameplate2", true) and custom.enabled
        and custom.groups.auras.filter == "HARMFUL|PLAYER|INCLUDE_NAME_PLATE_ONLY"
        and custom.groups.auras.candidate.includeSpellIDs == nil, "clearing the whitelist did not activate native debuff filtering")
    config.auraEnemyCustom1SpellsRetail, config.auraEnemyCustom1OnlyMine = "118,339", nil
    D.Configure(config)
    assert(D.Apply(uf, "nameplate2", true) and custom.groups.auras.candidate.includeSpellIDs[339],
        "restoring the whitelist did not narrow the native group")
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
    -- A restyle rebinds a button only when its binding changes. Blizzard keeps the bound texture and its copied
    -- options until ClearDispelTypeTextures. 2026-11-16, Lua 5.1, protected dispel calls per bound button for a
    -- restyle that leaves the binding alone: before 2 (clear, add) -> after 0.
    do
    local function Restyle(wanted, label)
        local mark = #dispelCalls
        D.Configure(config)
        assert(D.Apply(plate, "nameplate7", true) == true)
        local last
        for _, b in ipairs(buttons) do
            local sequence = {}
            for index = mark + 1, #dispelCalls do
                local call = dispelCalls[index]
                if call.button == b then
                    sequence[#sequence + 1] = call.texture and "add" or "clear"
                    last = call.options or last
                end
            end
            assert(table.concat(sequence, ",") == wanted, label .. ": a button was rebound as '" .. table.concat(sequence, ",") .. "'")
        end
        return last
    end
    -- the highlight follows the thickness without a rebind
    config.auraHighlightSize = 4
    Restyle("", "thickness")
    for _, b in ipairs(buttons) do
        assert(b.calls.SetSize == 2, "the unrelated restyle did not reach the button")
        local texture
        for _, call in ipairs(dispelCalls) do if call.button == b and call.texture then texture = call.texture end end
        local points = rawget(texture, "points")
        assert(points and #points == 2 and Anchor(points[1], "TOPLEFT", b, "TOPLEFT", -4, 4)
            and Anchor(points[2], "BOTTOMRIGHT", b, "BOTTOMRIGHT", 4, -4), "the ring did not follow the thickness")
    end
    -- a real change of the maps: one clear, one bind, with the new maps
    config.auraEnrageHighlight = false
    local rebound = Restyle("clear,add", "enrage off")
    assert(rebound ~= dispel and Names(rebound.customDispelColorMap) == "Bleed|Curse|Disease|Magic|Poison", "enrage off kept the old maps")
    config.auraHighlightSize = 3
    Restyle("", "thickness after a rebind")
    -- a changed palette is a real change too
    local magic = SOURCE.Magic
    SOURCE.Magic = { .1, .2, .3 }
    config.auraHighlightSize = 4
    local recolored = Restyle("clear,add", "palette")
    assert(recolored ~= rebound and recolored.customDispelColorMap.Magic.r == .1, "a changed palette was not bound")
    SOURCE.Magic = magic
    config.auraHighlightSize = 3
    assert(Restyle("clear,add", "palette back").customDispelColorMap.Magic.r == magic[1])
    -- off: cleared once; still off: nothing; on again: bound once, nothing to clear
    config.auraEnemyDotsDispel, config.auraEnemyCustom1Dispel = false, false
    Restyle("clear", "container highlight off")
    config.auraHighlightSize = 4
    Restyle("", "restyle while off")
    config.auraEnemyDotsDispel, config.auraEnemyCustom1Dispel = true, true
    Restyle("add", "container highlight on")
    config.auraEnrageHighlight = true
    assert(Names(Restyle("clear,add", "enrage on").customDispelColorMap) == "|Bleed|Curse|Disease|Enrage|Magic|Poison")
    -- the display off and on again: the released plan's options are not trusted, the next restyle binds again
    D.Configure({})
    config.auraHighlightSize = 3
    Restyle("clear,add", "display off and on")
    end
    -- off: no texture is bound; the enrage entries leave the map when enrages are off
    local _, offButtons = Dispel(true, false)
    for _, b in ipairs(offButtons) do assert(Calls(b) == 0, "a button with the dispel highlight off got " .. Calls(b) .. " calls") end
    local _, enrageOff = Dispel(false, true)
    assert(Names(Options(enrageOff[1]).customDispelColorMap) == "Bleed|Curse|Disease|Magic|Poison", "enrage off still colours enrages")
    config.auraDispelHighlight, config.auraEnrageHighlight, config.auraHighlightSize = nil, nil, nil
    config.auraEnemyDotsDispel, config.auraEnemyCustom1Dispel = nil, nil
    D.Configure(config)
    local buffList, debuffList = uf.AurasFrame.BuffListFrame, uf.AurasFrame.DebuffListFrame
    assert(buffList.shown and debuffList.shown and not cvarEvent)
    assert(not next(painted) and watching == nil, "an existing profile opted into icon skins")
    local plateSkin = Plate()
    local native = plateSkin.AurasFrame.BuffListFrame
    local direct = { auraDisplayEnabled = true, auraEnemyCustom1Visible = true,
        auraEnemyCustom1SpellsRetail = "589", auraEnemyCustom1IconSkin = true,
        auraEnemyCustom1DurationBar = true, auraEnemyCustom1DurationBarDirection = 2,
        auraEnemyCustom1DurationBarDisplay = 2, auraEnemyCustom1Padding = 6, auraEnemyCustom1TimeDecimals = 4 }
    D.Configure(direct)
    assert(D.Apply(plateSkin, "nameplate11", true) and native.shown)
    local firstSkin = iconLook
    local styled = next(painted)
    assert(styled and painted[styled] == firstSkin and watching == true)
    assert(styled.SetDurationBarArgs[1].kind == "StatusBar"
        and styled.SetDurationBarArgs[2].direction == Enum.StatusBarTimerDirection.ElapsedTime)
    assert(styled.SetIconArgs[1].SetAlphaArgs[1] == 0 and styled.SetDurationCooldownArgs[1].SetAlphaArgs[1] == 0,
        "bar-only mode kept the aura icon or swipe visible")
    local timer = styled.SetDurationTextArgs[2].textFormatter
    assert(timer.breakpoints[1].format == "%.1f" and timer.breakpoints[2].threshold == 4,
        "timer decimals were not passed to Blizzard's native formatter")
    assert(styled.parent.SetFlowLayoutPaddingArgs[1] == 6 and styled.parent.SetFlowLayoutPaddingArgs[4] == 6,
        "packed aura containers did not get their interior padding")
    iconLook = {}
    combat = true
    D.Configure(direct)
    assert(D.Apply(plateSkin, "nameplate11", true) and painted[styled] == firstSkin,
        "a sealed icon was restyled in combat")
    combat = false
    assert(D.Apply(plateSkin, "nameplate11", true) and painted[styled] == iconLook)
    direct.auraEnemyCustom1IconSkin = false
    D.Configure(direct)
    assert(D.Apply(plateSkin, "nameplate11", true) and not next(painted) and watching == false)
    D.Configure({})

    local dotsOnly = { auraDisplayEnabled = true, auraEnemyDotsVisible = true, auraEnemyDotsSource = 2, auraEnemyDotsIDsRetail = "589" }
    D.Configure(dotsOnly)
    local first, second = Plate(), Plate()
    first.unit, first.isFriend = "nameplate12", false
    second.unit, second.isFriend = "nameplate13", false
    targetUnit = first.unit
    local start = Containers()
    assert(D.Apply(first, first.unit, true) and Containers() == start + 1)
    assert(not D.Apply(second, second.unit, true) and Containers() == start + 1)
    local displayed
    for _, frame in ipairs(frames) do if frame.kind == "AuraContainer" then displayed = frame end end
    assert(displayed.enabled)
    targetUnit = second.unit
    D.TargetChanged(second)
    assert(not displayed.enabled and Containers() == start + 2)
    assert(first.AurasFrame.BuffListFrame.shown and second.AurasFrame.DebuffListFrame.shown)
    targetUnit = nil
    D.Configure({})
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
            if rampQueued then RunRamp() end
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
        if not (rampQueued) then break end
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
    assert(boxA[1].groups.auras.max == 10 and not rampQueued, "the ramp still runs with nothing waiting")
    -- (b) one plate, two auras: two buttons at once, a limit of three, and no ramp started
    presentDefault.auras = 2
    local b = Plate()
    local firstB = #frames + 1
    assert(D.Apply(b, "nameplate9", true) == true)
    local boxB = Containers(firstB)
    assert(Total(boxB) == 2 and boxB[1].groups.auras.max == 3, "two auras made " .. Total(boxB) .. " buttons")
    assert(not rampQueued, "a ramp runs with nothing waiting")
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
    assert(not rampQueued, "a ramp runs for a group that is not full")
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
    assert(not rampQueued)
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
    assert(not rampQueued, "a ramp still ticks after the module stopped")
    local idle = Frames(boxG, 2)
    assert(idle[1] == 0 and idle[2] == 0 and Total(boxG) == atStop, "a stopped module made buttons")
    D.Configure(ramp)
    assert(not rampQueued, "the ramp woke before a plate was attached")
    assert(D.Apply(g, "nameplate51", true) == true)
    assert(rampQueued, "attaching a plate did not resume its ramp")
    local resumed = Frames(boxG, 3)
    assert(table.concat(resumed, ",") == "3,3,1" and Total(boxG) == 10, "the restarted ramp made " .. table.concat(resumed, ","))
    -- Releasing a single unit can leave its old request in the shared queue.
    now = now + 1
    local removed, firstRemoved = Plate(), #frames + 1
    assert(D.Apply(removed, "nameplate52", true) and rampQueued)
    local released = Containers(firstRemoved)
    local before = Total(released)
    D.Restore(removed)
    Frames(released, 1)
    assert(Total(released) == before and not rampQueued, "a pooled plate continued to allocate aura buttons")

    -- A gamepad panel can appear after the initial grant and before the deferred job.
    now = now + 1
    local held, firstHeld = Plate(), #frames + 1
    assert(D.Apply(held, "nameplate53", true) and rampQueued)
    local heldBoxes = Containers(firstHeld)
    local starting = Total(heldBoxes)
    blocked = true
    local samples = Frames(heldBoxes, 8)
    assert(Total(heldBoxes) == starting and not rampQueued and samples[8] == 0, "blocked allocation kept waking")
    local group
    for key, wake in pairs(buildWaits) do
        if key ~= D then group = key; buildWaits[key] = nil; blocked = false; wake(key); break end
    end
    assert(group and rampQueued, "closing the gamepad panel did not wake the waiting group")
    Frames(heldBoxes, 3)
    assert(Total(heldBoxes) == 10 and not rampQueued, "resumed grants did not finish")
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
            if not (rampQueued) then return end
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
        if not (rampQueued) then break end
        Frames(list, 1)
        if rampQueued then
            local before, kib = Total(list), collectgarbage("count")
            RunRamp()
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
    do
        local reads, loaded, original = {}, nil, C_Spell.GetSpellTexture
        C_Spell.GetSpellTexture = function(id)
            reads[id] = (reads[id] or 0) + 1
            if id ~= 34914 then return id end
            return loaded
        end
        local config = { auraDisplayEnabled = true, auraEnemyDotsVisible = true, auraEnemyDotsSource = 2,
            auraEnemyDotsIDsRetail = "589,34914" }
        D.Configure(config)
        local first = #frames + 1
        targetUnit = nil
        assert(D.Apply(Plate(), "nameplate1", true))
        assert(D.Apply(Plate(), "nameplate2", true))
        assert(reads[589] == 1 and reads[34914] == 3, "shared spell art was fetched again or a missing texture was not retried")
        local function Seen(texture)
            local found = 0
            for i = first, #frames do
                local frame = frames[i]
                local args = rawget(frame, "SetTextureArgs")
                if frame.drawLayer == "BACKGROUND" and args and args[1] == texture then found = found + 1 end
            end
            return found
        end
        loaded = 34914
        D.SpellDataLoaded(nil, "SPELL_DATA_LOAD_RESULT", 34914, true)
        assert(Seen(34914) == 2 and reads[34914] == 4, "late spell art never reached both previously bound plates")
        loaded = nil
        D.Configure(config, true)
        assert(Seen(34914) == 2, "an unreadable override removed the last public art of the same spell")
        loaded = 54321
        D.SpellDataLoaded(nil, "SPELL_DATA_LOAD_RESULT", 34914, true)
        assert(Seen(54321) == 2 and reads[34914] == 6, "retained art prevented the override from loading")
        C_Spell.GetSpellTexture = original
        D.Configure({ auraDisplayEnabled = false })
    end
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
    function methods:IsShown() return self.shown end
    function methods:SetShown(v) self.shown = v end
    function methods:Show() self.shown = true end
    function methods:Hide() self.shown = false end
    function methods:CreateTexture() return Frame("Texture", self) end
    function methods:SetTexture(texture) self.texture = texture end
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
    B.Add("nameplates", B.Number("auraDebuffPadding", "Debuff padding", -1, -1, 50), "auras")
    B.Add("nameplates", B.Choice("personalAuras", "Blizzard personal auras", 1, { "Keep Blizzard setting", "Show all", "Blizzard filter" }), "native")
    for _, key in ipairs({ "auraColorsEnabled", "auraColorsNoneEnabled", "auraColorsIndividual" }) do
        B.Add("nameplates", B.Bool(key, key, false), "auraColors")
    end
    for _, key in ipairs({ "auraColorsAll", "auraColorsNone" }) do
        B.Add("nameplates", B.Color(key, key, "ffffff"), "auraColors")
    end
    B.Add("nameplates", B.Bool("auraClickthrough", "Let clicks pass through nameplate auras", false), "native")
    load(out .. "/MSUF_Suite/Core/NameplateAuraDisplay.lua", "MSUF_Suite", NS)
    load(out .. "/MSUF_Suite/Core/Catalog/NameplateAuras.lua", "MSUF_Suite", NS)
    spec.controlAvailable = function(rule) return not rule.client or rule.client == "retail" end
    NS.NameplateStyle = { AuraCVar = {}, AuraBits = {}, NativeBit = function() return true end, NativeToggle = function() return false end,
        CreateBorder = function() return {} end, PaintBorder = function() end }
    NS.ResolveFont = function() end
    NS.GlobalFontPath = function() return "font" end

    local function NewP(bars)
        local config, refreshers, grids, P = { auraDisplayEnabled = true, enabled = true }, {}, {}, nil
        P = { Suite = NS, Tr = function(s) return s end, catalog = NS.SuiteCatalog, refreshes = 0, finished = {}, grids = grids, config = config }
        P.Meta = function(_, _, key) return { settingKey = key } end
        P.T = { colors = {}, Panel = function(parent) return Frame("Panel", parent) end }
        P.Text = function(parent, text) local f = Frame("FontString", parent) f.text = text return f end
        P.Button = function(_, _, label, _, _, _, onClick)
            local button = Frame("Button")
            button.click = onClick
            P.button = button
            if label == "Global Aura Appearance" then P.appearanceButton = button end
            return button
        end
        P.AttachRuleColors = function(_, _, _, rules) P.colors = #rules end
        P.SetTranslatedText = function(f, text) f.text = text end
        P.Refresh = function() P.refreshes = P.refreshes + 1 for _, fn in ipairs(refreshers) do fn() end end
        P.Combat = function() return false end
        P.Get = function(_, key) local v = config[key] if v == nil then return spec.rules[key].default end return v end
        P.Set = function(_, key, value) assert(spec.rules[key], key) config[key] = value return true end
        P.SetMany = function(_, values) for k, v in pairs(values) do assert(spec.rules[k], k) config[k] = v end return true end
        P.M = { cache = {}, TrackRefresh = function(_, fn) refreshers[#refreshers + 1] = fn end,
            BindTextInputAt = function(_, parent, _, _, _, _, _, set)
                local i = Frame("EditBox", parent)
                i.set, P.input = set, i
                return i
            end,
            BindSwitchAt = function(_, parent, _, _, _, _, _, _, row)
                assert(not P.gridKeys[row.settingKey], row.settingKey .. " has two controls")
                P.gridKeys[row.settingKey] = true
                return Frame("Switch", parent)
            end }
        P.RuleRow = function(_, _, rule) return { settingKey = rule.key, label = rule.label } end
        P.GateControls = function() end
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
            SetSearchTargetPrepare = function() end,
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
        P.NameplatesEditorLayers = { AuraGroup = function(_, side) return side .. "Npc" end }
        load(out .. "/MSUF_Suite_Options/Pages/NameplatesSectionsLayout.lua", "MSUF_Suite_Options", P)
        load(out .. "/MSUF_Suite_Options/Pages/NameplatesAdvancedAuras.lua", "MSUF_Suite_Options", P)
        return P, config
    end

    local function BarKind(bar)
        local values = bar.opts.values
        return #values == 2 and "native" or "tracked"
    end
    local function SetTool(P, kind, tool)
        if not P.bars then return P.grids[1].rows[2].set(tool) end
        for i = 2, 3 do if BarKind(P.bars[i]) == (kind == "native" and "native" or "tracked") then P.bars[i].opts.setValue(tool) end end
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
        assert(not placed.enemyNpcAuraMode and not placed.auraEnemyBuffVisible and not placed.auraClickthrough)
        for _, key in ipairs({ "enemyNpcBuffs", "enemyPlayerControl", "friendlyPlayerBuffs", "friendlyNpcDebuffs", "auraScalePercent",
            "personalAuras", "auraEnemyBuffClickthrough", "auraFriendlyDebuffClickthrough", "auraEnemyControlClickthrough",
            "auraFriendlyCustom1Clickthrough", "auraEnemyDotsClickthrough", "auraDisplayEnabled", "auraFont", "auraHighlightSize", "auraEnemyBuffScale",
            "auraFriendlyDebuffAlpha" }) do assert(placed[key], key .. " has no place in the workspace") end
        local body = sections[1].build({}, { width = 720 }, sections[1])
        assert(#P.finished == 1 and P.finished[1] < -100, "workspace reported no height")
        -- Buffs opens with direct switches, followed by layout.
        assert(P.gridKeys.enemyNpcBuffs and P.gridKeys.enemyPlayerBuffs and P.gridKeys.auraEnemyBuffScale and not P.gridKeys.auraEnemyBuffUseLayout
            and not P.gridKeys.auraDisplayEnabled and not P.gridKeys.auraEnemyBuffVisible
            and not P.gridKeys.enemyNpcAuraMode and not P.gridKeys.enemyNpcDebuffs and not P.gridKeys.enemyNpcControl)
        assert(P.colors == 3, "the shared aura colors lost their menu")
        if bars then
            assert(#P.bars == 3 and P.bars[1].opts.label == "Container:" and #P.bars[1].opts.values == 7
                and P.bars[1].opts.values[1].value == "buff" and P.bars[1].opts.values[3].value == "control"
                and P.bars[1].opts.values[7].value == "dots")
            -- only the tool bar of the selected container kind shows
            for i = 2, 3 do assert(P.bars[i].shown == (BarKind(P.bars[i]) == "native"), "Edit bar does not follow the container kind") end
            assert(P.bars[2].opts.label == "Edit:")
            P.bars[1].opts.setValue("dots")
            assert(P.refreshes == 1 and #P.finished == 2)
            assert(P.bars[1].opts.getValue() == "dots")
        else
            assert(#P.grids == 1 and #P.grids[1].rows == 2 and #P.grids[1].rows[1].values() == 7 and #P.grids[1].rows[2].values() == 2)
            P.grids[1].rows[1].set("dots")
            assert(#P.grids[1].rows[2].values() == 6 and P.grids[1].rows[2].values()[5].value == "whitelist")
        end
        -- Switching between shared plate types does not duplicate exact controls.
        UI.SelectSide("enemy", "neutral")
        UI.SelectSide("enemy", "enemy")
        for _, key in ipairs({ "enemyPlayerDebuffs", "friendlyPlayerBuffs", "friendlyNpcDebuffs", "enemyNpcBuffs",
            "enemyNpcControl", "friendlyPlayerControl" }) do sections[1].prepare(key) end
        assert(P.gridKeys.friendlyNpcDebuffs and P.gridKeys.enemyNpcControl and P.gridKeys.friendlyPlayerControl
            and not P.gridKeys.friendlyPlayerAuraMode)
        -- Resetting the layout leaves the direct visibility settings alone.
        sections[1].prepare("enemyPlayerDebuffs")
        config.enemyNpcAuraMode, config.enemyNpcDebuffs, config.auraEnemyDebuffScale, config.auraEnemyBuffScale = 2, false, 40, 41
        body.reset()
        assert(config.enemyNpcDebuffs == false and config.auraEnemyDebuffScale == nil and config.enemyNpcAuraMode == 2 and config.auraEnemyBuffScale == 41)
        assert(#P.resetExtra == 2 and P.resetExtra[1] == "enemyAurasOffsetX")
        sections[1].prepare("auraFont")
        assert(P.gridKeys.auraFont)
        sections[1].prepare("auraFriendlyCustom2Zoom")
        assert(not P.gridKeys.auraFriendlyCustom2StackX and P.gridKeys.auraFriendlyCustom2SwipeDirection)
        sections[1].prepare("auraEnemyBuffAlpha")
        assert(P.gridKeys.auraEnemyBuffAlpha and P.gridKeys.auraEnemyBuffClickthrough and not P.gridKeys.auraEnemyBuffZoom)
        sections[1].prepare("auraFriendlyDebuffClickthrough")
        sections[1].prepare("auraEnemyControlClickthrough")
        sections[1].prepare("auraFriendlyCustom1Clickthrough")
        assert(P.gridKeys.auraFriendlyDebuffClickthrough and P.gridKeys.auraEnemyControlClickthrough
            and P.gridKeys.auraFriendlyCustom1Clickthrough and not P.gridKeys.auraClickthrough)
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
        P.input.SetOnValueCommittedArgs[1]("589")
        listGrid.rows[1].set(172)
        listGrid.rows[1].set(589)
        assert(config.auraEnemyCustom1SpellsRetail == "589,172" and config.auraEnemyCustom1SpellsForever == "999")
        listGrid.rows[4].set(589)
        assert(config.auraEnemyCustom1SpellsRetail == "172,589")
        listGrid.rows[3].set(589)
        assert(config.auraEnemyCustom1SpellsRetail == "589,172")
        listGrid.rows[2].set(589)
        assert(config.auraEnemyCustom1SpellsRetail == "172")
        -- a custom DoT selects the custom list as source
        sections[1].prepare("auraEnemyDotsSource")
        SetTool(P, "dots", "whitelist")
        P.grids[#P.grids].rows[1].set(34914)
        assert(config.auraEnemyDotsIDsRetail == "34914" and config.auraEnemyDotsSource == 2)
        -- reset: the shown container on this client only
        body.reset()
        assert(config.auraEnemyDotsIDsRetail == nil and config.auraEnemyCustom1SpellsForever == "999" and config.auraEnemyCustom1SpellsRetail == "172")
        -- preview: only enabled containers show, handles bind once per container
        config.enemy, config.auraEnemyDotsVisible, config.auraEnemyDotsIDsRetail, config.auraEnemyDotsSource = true, true, "589,2944", 2
        config.auraEnemyDotsDisplay, config.auraEnemyDotsHideDuplicates = 2, true
        local sample = { prefix = "enemy", state = { target = true }, cell = Frame("Frame"), bar = Frame("Frame"), buffs = Frame("Frame"), auras = Frame("Frame") }
        local bound = {}
        local editor = { LayerOn = function() return true end, Bind = function(_, frame, id, _, kx, ky) bound[id] = { frame, kx, ky } end }
        UI.Render(editor, sample, {})
        UI.Render(editor, sample, {})
        assert(bound["enemy.Tracked"][2] == "auraEnemyDotsOffsetX" and bound["enemy.CustomTwo"][3] == "auraEnemyCustom2OffsetY")
        assert(bound["enemy.Tracked"][1].shown == true and bound["enemy.CustomTwo"][1].shown == false)
        local state = sample.auraPreviewState
        assert(#state.containers.dots.icons == 2 and state.exclusions.debuff[589] and state.exclusions.debuff[2944]
            and not state.exclusions.debuff[34914], "packed preview used generic auras instead of the tracked list")
        assert(state.containers.dots.icons[1].icon.texture == 589 and state.containers.dots.icons[2].icon.texture == 2944)
        config.auraEnemyDotsType = 1
        UI.Render(editor, sample, {})
        assert(state.exclusions.buff[589] and not state.exclusions.debuff[589], "buff preview filtered the debuff lane")
        assert(NS.NameplateAuraDisplay.Element("enemy.Tracked") and not NS.NameplateAuraDisplay.Element("enemy.Health"))
        assert(not bound["enemy.Buffs"] and not rawget(sample.buffs, "SetPointArgs"))
        sample.state.target = false
        UI.Render(editor, sample, {})
        assert(not bound["enemy.Tracked"][1].shown and not sample.auraPreviewState.exclusions.debuff[589])
        config.auraEnemyCustom1Visible, config.auraEnemyCustom1SpellsRetail = true, ""
        UI.Render(editor, sample, {})
        local custom = sample.auraPreviewState.containers.custom1
        assert(custom.frame.shown and custom.icons[1].frame.shown, "empty Custom Debuff flow did not preview a sample")
        config.auraEnemyCustom2Visible, config.auraEnemyCustom2SpellsRetail = true, "172"
        config.auraEnemyCustom2HideDuplicates = true
        UI.Render(editor, sample, {})
        assert(custom.icons[1].frame.shown, "a whitelist excluded the synthetic sample of an empty flow row")
        config.auraEnemyCustom1Display = 1
        UI.Render(editor, sample, {})
        assert(not custom.frame.shown, "empty fixed slots should stay hidden")

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

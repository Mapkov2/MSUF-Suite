-- Per-event budgets of the coalesced QoL and Modules paths: ThreatMeter,
-- CombatStatsHUD, GroupBloodlust and the observed Mythic+ pull. Each module
-- runs on the shipped Runtime.lua context (and its timers) against the
-- client's frame clock (Support.Clock). Events reach the routing frame the
-- way the client delivers them. Only instructions of shipped Suite code are
-- counted: stubs stand in for C functions, which cost no Lua instructions.
-- Kilobytes are measured in a second pass without the hook, GC stopped.
--   steady: one relevant event while the coalesced repaint is already due;
--   burst:  ten relevant events from idle, then the frames until the one
--           repaint ran.
local root = assert(arg[1], "repository root required")
local Support = dofile(root .. "/tools/tests/suite_test_support.lua")

-- Instructions and KB measured 2026-10-02 on the hand-rolled timers (base
-- c8f0304). A budget may grow by at most 2 %; the steady path allocates
-- nothing.
local BASELINE = {
    threatMeter = { steady = 58, burst = 1314, burstKB = .198 },
    combatStatsHUD = { steady = 19, burst = 606, burstKB = .250 },
    groupBloodlust = { steady = 25, burst = 572, burstKB = .156 },
    observedPull = { steady = 28, burst = 532, burstKB = .156 },
}

------------------------------------------------------------------ client stubs
local frames = {}
local Noop = function() end
local WidgetMethods = {}
-- Widget methods (capitalized) answer with no effect; data fields stay nil.
local WidgetMeta = { __index = function(_, key)
    return WidgetMethods[key] or (key:find("^%u") and Noop or nil)
end }
local function Widget(kind, parent)
    local widget = setmetatable({ kind = kind, parent = parent, shown = true, events = {}, scripts = {} }, WidgetMeta)
    frames[#frames + 1] = widget
    return widget
end
function WidgetMethods:SetScript(name, fn) self.scripts[name] = fn end
function WidgetMethods:GetScript(name) return self.scripts[name] end
function WidgetMethods:RegisterEvent(event) self.events[event] = true end
function WidgetMethods:RegisterUnitEvent(event, ...) self.events[event] = { ... } end
function WidgetMethods:UnregisterEvent(event) self.events[event] = nil end
function WidgetMethods:UnregisterAllEvents() self.events = {} end
function WidgetMethods:Show() self.shown = true end
function WidgetMethods:Hide() self.shown = false end
function WidgetMethods:SetShown(shown) self.shown = shown and true or false end
function WidgetMethods:IsShown() return self.shown end
function WidgetMethods:IsVisible() return self.shown end
function WidgetMethods:SetText(text) self.text = text end
function WidgetMethods:GetText() return self.text end
function WidgetMethods:CreateTexture() return Widget("Texture", self) end
function WidgetMethods:CreateFontString() return Widget("FontString", self) end
function WidgetMethods:IsProtected() return false end
function WidgetMethods:IsForbidden() return false end
function WidgetMethods:GetParent() return self.parent end
function WidgetMethods:GetNumPoints() return 0 end
function WidgetMethods:SetFont() return true end
CreateFrame = function(kind, _, parent) return Widget(kind, parent) end
UIParent = Widget("Frame")
GameFontHighlightSmall = { GetFont = function() return "Fonts\\FRIZQT__.TTF", 12, "" end }
wipe = function(t) for key in pairs(t) do t[key] = nil end return t end
InCombatLockdown = function() return false end

-- The routing frame of `event` (and its unit filter) gets it, as the client
-- delivers an event to every frame registered for it.
local function Fire(event, ...)
    local unit = ...
    for _, frame in ipairs(frames) do
        local filter = frame.events[event]
        local handler = frame.scripts.OnEvent
        if filter and handler then
            local wanted = filter == true
            if not wanted then
                for _, token in ipairs(filter) do wanted = wanted or token == unit end
            end
            if wanted then handler(frame, event, ...) end
        end
    end
end

------------------------------------------------------------------ the shipped runtime
-- securecallfunction is a C function: the stand-in calls straight through,
-- so neither its instructions nor a results table enter the budget.
local reported = {}
local S = { instances = {}, catalog = {}, states = {} }
local NS = {
    Suite = S, Dispatch = function(callback, ...) return callback(...) end,
    Finish = function(callback, ...) return true, callback(...) end,
    Public = function(value) return value ~= "secret" end,
    Number = function(value) return type(value) == "number" end,
    Finite = function(value) return type(value) == "number" and value == value and value ~= math.huge end,
    PublicText = function(value) return type(value) == "string" and value ~= "" and value or nil end,
    Text = function(text) return text end,
    IsCombatLocked = function() return false end,
    Client = { SupportsEvent = function() return true end, isForever = false },
    Skin = { Release = Noop, Acquire = Noop },
    Safety = { IsForbidden = function() return false end },
    AnchorPoints = { "TOPLEFT", "TOP", "TOPRIGHT", "LEFT", "CENTER", "RIGHT", "BOTTOMLEFT", "BOTTOM", "BOTTOMRIGHT" },
    MSUFMedia = { font = "font", barTexture = "bar" },
    RGB = function() return 1, 1, 1 end,
    GlobalFontPath = function() return "font" end,
    QoLVisualStyles = { [1] = { background = "0a1220", border = "41627a", accent = "57c7df",
        text = "f4f7fb", muted = "aab5c2" } },
}
NS.ReadText = function(fn, ...) return NS.PublicText(fn(...)) end
NS.InCombat = function(event)
    return event == "PLAYER_REGEN_DISABLED" or (event ~= "PLAYER_REGEN_ENABLED" and InCombatLockdown())
end
_G.MSUFSuite = NS
-- Surfaces reads the "Font rendering" values (NS.FontRendering) from the core catalog.
do
    local core = { Suite = {} }
    assert(loadfile(root .. "/MSUF_Suite/Core/SuiteCatalog.lua"))("MSUF_Suite", core)
    NS.FontRendering = core.FontRendering
end
local clock = Support.Clock()
-- Coalescing means one C_Timer wait per burst and none for a steady event.
local waits = 0
local NativeAfter = C_Timer.After
C_Timer.After = function(seconds, callback)
    waits = waits + 1
    return NativeAfter(seconds, callback)
end
local private = { NS = NS, Suite = S }
for _, file in ipairs(Support.TocFiles(root, "MSUF_Suite_Modules")) do
    if file == "Surfaces.lua" or file == "Runtime.lua" or file == "Timers.lua" then
        assert(loadfile(root .. "/MSUF_Suite_Modules/" .. file))("MSUF_Suite_Modules", private)
    end
end
S.RegisterOwnedMover = Noop
S.Text = NS.Text
S.Print = Noop
local qol = { NS = NS, Suite = S }
assert(loadfile(root .. "/MSUF_Suite_QualityOfLife/Bootstrap.lua"))("MSUF_Suite_QualityOfLife", qol)

local function Start(id, file, addon, config)
    S.catalog[id] = { rules = {} }
    S.states[id] = { active = true }
    assert(loadfile(root .. "/" .. (addon or "MSUF_Suite_QualityOfLife") .. "/" .. file))(addon or "test", qol)
    local module = assert(S.instances[id], id .. " did not install")
    module.config, module.active = config, true
    module.context = S.NewContext(id)
    if module.Enable then module:Enable() end
    return module
end

-- As the controller stops a module: Disable, then the context's Release.
local function Stop(module)
    module.active = false
    module:Disable()
    module.context:Release()
end

------------------------------------------------------------------ measuring
local function ProductCode(source)
    return source:find("/MSUF_Suite[%w_]*/") and not source:find("/tools/", 1, true)
end

local function Instructions(fn)
    collectgarbage("collect")
    collectgarbage("stop")
    local count = 0
    debug.sethook(function()
        local info = debug.getinfo(2, "S")
        if info and ProductCode(info.source:gsub("\\", "/")) then count = count + 1 end
    end, "", 1)
    fn()
    debug.sethook()
    collectgarbage("restart")
    return count
end

-- A full collect shrinks the Lua stack of a thread that uses little of it;
-- the first deep call afterwards grows it again. Growing it once before the
-- window keeps that one-time cost out of the per-burst kilobytes.
local function Deep(depth, a, b, c, d, e, f, g, h)
    if depth > 0 then return Deep(depth - 1, a, b, c, d, e, f, g, h) + 0 end
    return 0
end

local function Kilobytes(fn)
    collectgarbage("collect")
    collectgarbage("stop")
    Deep(120)
    local before = collectgarbage("count")
    fn()
    local used = collectgarbage("count") - before
    collectgarbage("restart")
    return used
end

local measured, failures = {}, {}
local function Budget(name, kind, scenario, prepare)
    if prepare then prepare() end
    local count = Instructions(scenario)
    if prepare then prepare() end
    local before = waits
    local kilobytes = Kilobytes(scenario)
    local expected = kind == "burst" and 1 or 0
    if waits - before ~= expected then
        failures[#failures + 1] = string.format("%s %s: %d C_Timer waits, expected %d", name, kind,
            waits - before, expected)
    end
    -- The second Kilobytes pass leaves out one-time growth (a first key, a tick).
    if prepare then prepare() end
    kilobytes = math.min(kilobytes, Kilobytes(scenario))
    measured[#measured + 1] = string.format("%s %s %d instr %.3f KB", name, kind, count, kilobytes)
    local limit = BASELINE[name][kind]
    if count > math.floor(limit * 1.02) then
        failures[#failures + 1] = string.format("%s %s: %d instructions, baseline %d (+2 %% = %d)",
            name, kind, count, limit, math.floor(limit * 1.02))
    end
    local kbLimit = (BASELINE[name][kind .. "KB"] or 0) * 1.02 + .0005
    if kilobytes > kbLimit then
        failures[#failures + 1] = string.format("%s %s: %.3f KB, limit %.3f", name, kind, kilobytes, kbLimit)
    end
end

-- A QoL module's catalog defaults: the QoL catalog files need the shared
-- QualityOfLife.lua helpers loaded first, as in the TOC.
local catalogNS = { Client = { isForever = false }, Text = function(text) return text end }
assert(loadfile(root .. "/MSUF_Suite/Core/SuiteCatalog.lua"))("MSUF_Suite", catalogNS)
assert(loadfile(root .. "/MSUF_Suite/Core/Catalog/QualityOfLife.lua"))("MSUF_Suite", catalogNS)
local catalogLoaded = {}
local function Defaults(id, file)
    if not catalogLoaded[file] then
        assert(loadfile(root .. "/MSUF_Suite/Core/Catalog/" .. file .. ".lua"))("MSUF_Suite", catalogNS)
        catalogLoaded[file] = true
    end
    local config = {}
    for key, rule in pairs(catalogNS.SuiteCatalog[id].rules) do config[key] = rule.default end
    return config
end

local function Settle()
    clock.Advance(1)
end

------------------------------------------------------------------ ThreatMeter
do
    local threats = { player = { false, 1, 90, 99, 9000 }, party1 = { true, 3, 100, 100, 10000 } }
    UnitExists = function(unit) return unit == "player" or unit == "party1" or unit == "target"
        or unit == "targettarget" end
    UnitCanAssist = function() return false end
    UnitCanAttack = function(_, unit) return unit == "target" or unit == "targettarget" end
    UnitDetailedThreatSituation = function(unit) return unpack(threats[unit] or {}) end
    UnitName = function(unit) return unit end
    UnitClass = function() return "Warrior", "WARRIOR" end
    UnitIsUnit = function(a, b) return a == b end
    IsInRaid = function() return false end
    GetNumGroupMembers = function() return 2 end
    RAID_CLASS_COLORS = { WARRIOR = { r = .7, g = .5, b = .3 } }
    SOUNDKIT = { RAID_WARNING = 1 }
    PlaySound = Noop
    local config = Defaults("threatMeter", "QualityOfLifeDetails")
    config.enabled = true
    local m = Start("threatMeter", "ThreatMeter.lua", nil, config)
    Settle()
    local function Event() Fire("UNIT_THREAT_LIST_UPDATE", "target") end
    Budget("threatMeter", "steady", Event, function() Settle(); Event() end)
    Budget("threatMeter", "burst", function()
        for _ = 1, 10 do Event() end
        Settle()
    end, Settle)
    assert(m.active and #reported == 0, "threat meter raised: " .. tostring(reported[1]))
    Stop(m)
end

------------------------------------------------------------------ CombatStatsHUD
do
    GetCritChance, GetRangedCritChance = function() return 21 end, function() return 20 end
    GetSpellCritChance = function() return 22 end
    GetHaste, GetMasteryEffect = function() return 15 end, function() return 30 end
    CR_VERSATILITY_DAMAGE_DONE, CR_HASTE_MELEE, CR_MASTERY = 29, 18, 26
    GetCombatRatingBonus, GetVersatilityBonus = function() return 5 end, function() return 1 end
    GetCombatRating = function() return 700 end
    GetLifesteal, GetAvoidance, GetSpeed = function() return 1 end, function() return 2 end, function() return 3 end
    GetFramerate = function() return 120 end
    local config = Defaults("combatStatsHUD", "QualityOfLifeHUD")
    config.enabled, config.combatOnly = true, false
    local m = Start("combatStatsHUD", "CombatStatsHUD.lua", nil, config)
    Settle()
    local function Event() Fire("UNIT_AURA", "player") end
    Budget("combatStatsHUD", "steady", Event, function() Settle(); Event() end)
    Budget("combatStatsHUD", "burst", function()
        for _ = 1, 10 do Event() end
        Settle()
    end, Settle)
    assert(m.active and #reported == 0, "combat stats raised: " .. tostring(reported[1]))
    Stop(m)
end

------------------------------------------------------------------ GroupBloodlust
do
    C_Spell = { GetSpellTexture = function() return 1 end }
    C_Secrets = { ShouldSpellAuraBeSecret = function() return false end }
    C_UnitAuras = { GetPlayerAuraBySpellID = function() return nil end }
    IsInGroup = function() return true end
    local config = Defaults("groupBloodlust", "QualityOfLifeGroup")
    config.enabled = true
    local m = Start("groupBloodlust", "GroupBloodlust.lua", nil, config)
    Settle()
    local info = { isFullUpdate = false, addedAuras = { { spellId = 57724 } } }
    local function Event() Fire("UNIT_AURA", "player", info) end
    Budget("groupBloodlust", "steady", Event, function() Settle(); Event() end)
    Budget("groupBloodlust", "burst", function()
        for _ = 1, 10 do Event() end
        Settle()
    end, Settle)
    assert(m.active and #reported == 0, "bloodlust raised: " .. tostring(reported[1]))
    Stop(m)
end

------------------------------------------------------------------ observed Mythic+ pull
do
    local units = { target = "Creature-1", nameplate1 = "Creature-2", nameplate2 = "Creature-3" }
    UnitExists = function(unit) return units[unit] ~= nil end
    UnitIsDeadOrGhost = function() return false end
    UnitCanAttack = function() return true end
    UnitAffectingCombat = function() return true end
    UnitGUID = function(unit) return units[unit] end
    C_ScenarioInfo = { GetUnitCriteriaProgressValues = function() return 4, 1.5 end }
    S.catalog.objectives = { rules = {} }
    S.states.objectives = { active = true }
    local owner = { active = true, mplusActive = true, config = { showObservedPull = true },
        mplus = { observedPull = Widget("FontString"), forcesPercent = 40 } }
    S.instances.objectives = owner
    owner.context = S.NewContext("objectives")
    assert(loadfile(root .. "/MSUF_Suite_Modules/MythicPlusPull.lua"))("MSUF_Suite_Modules", private)
    local pull = assert(S.MythicPlusPull)
    pull.Sync(owner)
    Settle()
    local function Event() Fire("NAME_PLATE_UNIT_ADDED", "nameplate2") end
    Budget("observedPull", "steady", Event, function() Settle(); Event() end)
    Budget("observedPull", "burst", function()
        for _ = 1, 10 do Event() end
        Settle()
    end, Settle)
    assert(owner.observedPull.active and #reported == 0, "observed pull raised: " .. tostring(reported[1]))
end

assert(#failures == 0, table.concat(failures, "\n") .. "\nmeasured: " .. table.concat(measured, "; "))
print("suite_qol_event_budget_contract: OK (" .. table.concat(measured, "; ") .. ")")

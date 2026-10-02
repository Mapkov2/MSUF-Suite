-- Raid hot paths measured the way the 2026-10-02 raid trace saw them:
-- GroupDeathAlert (every raid member's UNIT_HEALTH/UNIT_FLAGS), GroupBloodlust
-- (the player's UNIT_AURA in combat) and the raid HUD's boss health.
-- Each module runs on the shipped Runtime.lua context and its timers; events
-- reach the routing frames the way the client delivers them (unit filters
-- included). The secret readers are the shipped ones from Platform.lua, so
-- their Lua cost counts as product code and their issecretvalue calls count
-- as native calls.
-- Three numbers per scenario:
--   instructions  VM instructions of shipped Suite code (stubs are C);
--   KB            allocation in a second pass, GC stopped;
--   natives       calls into client API stand-ins (issecretvalue included).
-- The VM budgets cannot see native cost (the wave-3 over-absorb glow passed
-- every VM budget and cost a third of the core CPU in the raid); the native
-- count is the guard for that.
local root = assert(arg[1], "repository root required")
local Support = dofile(root .. "/tools/tests/suite_test_support.lua")

-- Measured 2026-10-02 (wave 4, base a7aee25 -> this change). A budget may
-- grow by at most 2 %. Native calls are budgeted per client API, exactly: an
-- API the table leaves out must not be called at all.
--   groupDeathAlert steady (a living member's UNIT_HEALTH): base 76 instr,
--     0 KB, 5 natives (3 issecretvalue, UnitExists, UnitIsDeadOrGhost)
--     -> 39 instr, 0 KB, 3 natives (UnitExists only on a state change).
--   groupBloodlust, the player sated, a buff with a secret spell ID per
--     event (raid combat: 1,126 UNIT_AURA, 520 lockout reads in 120 s):
--     secretSteady (one event) base 137 instr, .156 KB, 6 issecretvalue
--       -> 93 instr, 0 KB, 6 issecretvalue (no lockout read requested);
--     secretBurst (ten events, then the frames until a read could run) base
--       790 instr, .313 KB, 25 issecretvalue + 7 ShouldSpellAuraBeSecret + 3
--       GetPlayerAuraBySpellID (the client allocates each found aura, about
--       1.9 KB in the trace) -> 930 instr, 0 KB, 60 issecretvalue. The trade:
--       +140 VM instructions per ten events for no lockout read at all; at
--       the trace's 2.2 events per read that is 205 instead of about 800.
local BASELINE = {
    groupDeathAlert = { steady = 39, steadyNatives = { issecretvalue = 2, UnitIsDeadOrGhost = 1 } },
    groupBloodlust = { secretSteady = 93, secretSteadyNatives = { issecretvalue = 6 },
        secretBurst = 930, secretBurstNatives = { issecretvalue = 60 } },
}

------------------------------------------------------------------ native counting
local natives = { total = 0, byName = {} }
local function Native(name, fn)
    return function(...)
        natives.total = natives.total + 1
        natives.byName[name] = (natives.byName[name] or 0) + 1
        return fn(...)
    end
end

-- Secrets raise on any Lua use; only the counted issecretvalue sees them.
local SecretMT = {}
local function Raise(what) return function() error("secret value used in Lua: " .. what, 2) end end
for _, key in ipairs({ "__eq", "__lt", "__le", "__add", "__sub", "__mul", "__div", "__mod", "__unm", "__concat",
    "__len", "__call" }) do SecretMT[key] = Raise(key) end
SecretMT.__index, SecretMT.__newindex, SecretMT.__tostring = Raise("index"), Raise("assignment"), Raise("tostring")
-- getmetatable interns "__metatable" again after a full collect, which the
-- KB pass would charge to the product code: secrets are looked up instead.
local secrets = setmetatable({}, { __mode = "k" })
local function Secret()
    local value = setmetatable({}, SecretMT)
    secrets[value] = true
    return value
end
issecretvalue = Native("issecretvalue", function(value)
    return value ~= nil and rawget(secrets, value) == true
end)

------------------------------------------------------------------ client stubs
local frames = {}
local Noop = function() end
local WidgetMethods = {}
local WidgetMeta = { __index = function(_, key)
    return WidgetMethods[key] or (key:find("^%u") and Noop or nil)
end }
local function Widget(kind, parent)
    local widget = setmetatable({ kind = kind, parent = parent, shown = true, events = {}, scripts = {},
        messages = {} }, WidgetMeta)
    frames[#frames + 1] = widget
    return widget
end
function WidgetMethods:SetScript(name, fn) self.scripts[name] = fn end
function WidgetMethods:GetScript(name) return self.scripts[name] end
function WidgetMethods:RegisterEvent(event) self.events[event] = true end
function WidgetMethods:RegisterUnitEvent(event, ...)
    assert(select("#", ...) <= 4, "RegisterUnitEvent takes at most four unit tokens")
    self.events[event] = { ... }
end
function WidgetMethods:UnregisterEvent(event) self.events[event] = nil end
function WidgetMethods:UnregisterAllEvents() self.events = {} end
function WidgetMethods:Show() self.shown = true end
function WidgetMethods:Hide() self.shown = false end
function WidgetMethods:SetShown(shown) self.shown = shown and true or false end
function WidgetMethods:IsShown() return self.shown end
function WidgetMethods:IsVisible() return self.shown end
function WidgetMethods:SetText(text) self.text = text end
function WidgetMethods:GetText() return self.text end
function WidgetMethods:SetFormattedText(format, ...) self.text, self.format, self.formatArgs = nil, format, { ... } end
function WidgetMethods:AddMessage(text) self.messages[#self.messages + 1] = text end
function WidgetMethods:Clear() self.messages = {} end
function WidgetMethods:CreateTexture() return Widget("Texture", self) end
function WidgetMethods:CreateFontString() return Widget("FontString", self) end
function WidgetMethods:IsProtected() return false end
function WidgetMethods:IsForbidden() return false end
function WidgetMethods:GetParent() return self.parent end
function WidgetMethods:GetNumPoints() return 0 end
function WidgetMethods:SetFont() return true end
CreateFrame = function(kind, _, parent) return Widget(kind, parent) end
UIParent = Widget("Frame")
RaidWarningFrame = Widget("Frame")
GameFontNormalHuge = {}
GameFontHighlightSmall = { GetFont = function() return "Fonts\\FRIZQT__.TTF", 12, "" end }
ChatTypeInfo = { RAID_WARNING = { r = 1, g = .28, b = 0 } }
SOUNDKIT = { RAID_WARNING = 1 }
PlaySound = Noop
wipe = function(t) for key in pairs(t) do t[key] = nil end return t end
local combat = false
InCombatLockdown = function() return combat end
UnitAffectingCombat = function() return combat end

-- Every routing frame registered for `event` (and its unit filter) gets it.
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

------------------------------------------------------------------ shipped readers and runtime
-- The secret readers of Platform.lua, loaded from the shipped file with the
-- counted issecretvalue.
local function PlatformReaders()
    local file = assert(io.open(root .. "/MSUF_Suite/Core/Platform.lua", "rb"))
    local source = file:read("*a"):gsub("\r\n", "\n")
    file:close()
    local block = assert(source:match("\n(local IsSecret = .-\nSuite%.PublicText, Suite%.ReadText = PublicText, ReadText)\n"),
        "the secret readers are missing from Platform.lua")
    -- Keep the shipped chunk name, so the hook counts these instructions.
    local chunk = assert(loadstring("local Suite = ...\n" .. block .. "\nreturn Suite",
        "@" .. root .. "/MSUF_Suite/Core/Platform.lua"))
    return chunk({})
end

local reported = {}
local S = { instances = {}, catalog = {}, states = {} }
local readers = PlatformReaders()
local NS = {
    Suite = S, Dispatch = function(callback, ...) return callback(...) end,
    Finish = function(callback, ...) return true, callback(...) end,
    IsSecret = readers.IsSecret, Public = readers.Public, Number = readers.Number, Finite = readers.Finite,
    PublicText = readers.PublicText, ReadText = readers.ReadText,
    Text = function(text) return text end,
    IsCombatLocked = function() return combat end,
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
NS.InCombat = Support.InCombat(root, function() return combat end, function() return combat end)
_G.MSUFSuite = NS
do
    local core = { Suite = {} }
    assert(loadfile(root .. "/MSUF_Suite/Core/SuiteCatalog.lua"))("MSUF_Suite", core)
    NS.FontRendering = core.FontRendering
end
local clock = Support.Clock()
local private = { NS = NS, Suite = S }
for _, file in ipairs(Support.TocFiles(root, "MSUF_Suite_Modules")) do
    if file == "Surfaces.lua" or file == "Runtime.lua" or file == "Timers.lua" then
        assert(loadfile(root .. "/MSUF_Suite_Modules/" .. file))("MSUF_Suite_Modules", private)
    end
end
S.RegisterOwnedMover = Noop
S.Text = NS.Text
local printed = {}
S.Print = function(text) printed[#printed + 1] = text end
local qol = { NS = NS, Suite = S }
assert(loadfile(root .. "/MSUF_Suite_QualityOfLife/Bootstrap.lua"))("MSUF_Suite_QualityOfLife", qol)

local function Start(id, file, config)
    S.catalog[id] = { rules = {} }
    S.states[id] = { active = true }
    assert(loadfile(root .. "/MSUF_Suite_QualityOfLife/" .. file))("MSUF_Suite_QualityOfLife", qol)
    local module = assert(S.instances[id], id .. " did not install")
    module.config, module.active = config, true
    module.context = S.NewContext(id)
    if module.Enable then module:Enable() end
    return module
end

local function Stop(module)
    module.active = false
    module:Disable()
    module.context:Release()
end

-- A QoL module's catalog defaults (QualityOfLife.lua helpers first, as in the TOC).
local catalogNS = { Client = { isForever = false }, Text = function(text) return text end }
assert(loadfile(root .. "/MSUF_Suite/Core/SuiteCatalog.lua"))("MSUF_Suite", catalogNS)
assert(loadfile(root .. "/MSUF_Suite/Core/Catalog/QualityOfLife.lua"))("MSUF_Suite", catalogNS)
local function Defaults(id, file)
    assert(loadfile(root .. "/MSUF_Suite/Core/Catalog/" .. file .. ".lua"))("MSUF_Suite", catalogNS)
    local config = {}
    for key, rule in pairs(catalogNS.SuiteCatalog[id].rules) do config[key] = rule.default end
    return config
end

local function Settle() clock.Advance(1) end

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

local function Natives(fn)
    local before = natives.total
    local byName = {}
    for name, count in pairs(natives.byName) do byName[name] = count end
    fn()
    local detail, deltas = {}, {}
    for name, count in pairs(natives.byName) do
        local delta = count - (byName[name] or 0)
        if delta > 0 then
            detail[#detail + 1] = name .. "=" .. delta
            deltas[name] = delta
        end
    end
    table.sort(detail)
    return natives.total - before, table.concat(detail, " "), deltas
end

local measured, failures = {}, {}
local function Budget(name, kind, scenario, prepare)
    if prepare then prepare() end
    local count = Instructions(scenario)
    if prepare then prepare() end
    local kilobytes = Kilobytes(scenario)
    if prepare then prepare() end
    kilobytes = math.min(kilobytes, Kilobytes(scenario))
    if prepare then prepare() end
    local calls, detail, deltas = Natives(scenario)
    measured[#measured + 1] = string.format("%s %s %d instr %.3f KB %d natives (%s)", name, kind, count,
        kilobytes, calls, detail)
    print(measured[#measured])
    local base = BASELINE[name]
    local limit = base[kind]
    if count > math.floor(limit * 1.02) then
        failures[#failures + 1] = string.format("%s %s: %d instructions, baseline %d (+2 %% = %d)",
            name, kind, count, limit, math.floor(limit * 1.02))
    end
    local kbLimit = (base[kind .. "KB"] or 0) * 1.02 + .0005
    if kilobytes > kbLimit then
        failures[#failures + 1] = string.format("%s %s: %.3f KB, limit %.3f", name, kind, kilobytes, kbLimit)
    end
    local nativeLimits = base[kind .. "Natives"]
    for api, delta in pairs(deltas) do
        if delta > (nativeLimits[api] or 0) then
            failures[#failures + 1] = string.format("%s %s: %d %s calls, budget %d (all: %s)", name, kind, delta,
                api, nativeLimits[api] or 0, detail)
        end
    end
end

------------------------------------------------------------------ GroupDeathAlert
do
    local members, names = {}, {}
    local raidSize = 20
    IsInGroup = Native("IsInGroup", function() return true end)
    IsInRaid = Native("IsInRaid", function() return true end)
    UnitIsUnit = Native("UnitIsUnit", function(a, b) return a == b or (a == "raid1" and b == "player") end)
    UnitExists = Native("UnitExists", function(unit) return members[unit] ~= nil end)
    UnitIsDeadOrGhost = Native("UnitIsDeadOrGhost", function(unit)
        local state = members[unit]
        if state == nil then return false end
        return state
    end)
    UnitName = Native("UnitName", function(unit) return names[unit] end)
    for i = 1, raidSize do
        members["raid" .. i], names["raid" .. i] = false, "Member" .. i
    end
    members.player, names.player = false, "Player"
    local m = Start("groupDeathAlert", "GroupDeathAlert.lua",
        { includePlayer = false, screen = true, chat = true, sound = false })
    combat = true
    Fire("PLAYER_REGEN_DISABLED")
    -- raid1 is the player: watched only through "player" (not included here).
    local function Health(unit) Fire("UNIT_HEALTH", unit) end
    printed = {}
    -- Steady: a living member's health tick.
    Budget("groupDeathAlert", "steady", function() Health("raid7") end)
    assert(#printed == 0, "a living member's health tick announced a death")
    -- A death is announced once; UNIT_FLAGS for the same death stays quiet.
    members.raid7 = true
    Health("raid7")
    Fire("UNIT_FLAGS", "raid7")
    assert(#printed == 1 and printed[1] == "Member7 died", "a death was not announced exactly once")
    -- A ghost stays dead (UnitIsDeadOrGhost), so the release is quiet.
    Health("raid7")
    assert(#printed == 1, "a released ghost was announced again")
    -- A resurrection arms the next death.
    members.raid7 = false
    Health("raid7")
    members.raid7 = true
    Health("raid7")
    assert(#printed == 2 and printed[2] == "Member7 died", "a death after a resurrection was missed")
    -- A token whose unit is gone reads alive; that must not replace the
    -- stored death, or the unit coming back dead would be announced again.
    members.raid7 = nil
    Health("raid7")
    members.raid7 = true
    Health("raid7")
    assert(#printed == 2, "a vanished dead unit was announced again when its token came back")
    -- A gone token that was alive never turns into a death on its own.
    members.raid8 = nil
    Health("raid8")
    assert(#printed == 2, "a vanished living unit was announced")
    -- A secret answer is ignored, never compared.
    UnitIsDeadOrGhost = Native("UnitIsDeadOrGhost", function() return Secret() end)
    Health("raid9")
    assert(#printed == 2, "a secret dead state was announced")
    -- The player's own token: a raid member token that is the player is not
    -- watched twice.
    Health("raid1")
    assert(#printed == 2 and #reported == 0, "group death alert raised: " .. tostring(reported[1]))
    combat = false
    Fire("PLAYER_REGEN_ENABLED")
    Stop(m)
end

------------------------------------------------------------------ GroupBloodlust
do
    local restricted, sated = false, true
    Enum = Enum or {}
    Enum.AddOnRestrictionState = { Inactive = 0, Activating = 1, Active = 2 }
    C_Spell = { GetSpellTexture = function() return 1 end }
    C_Secrets = { ShouldSpellAuraBeSecret = Native("ShouldSpellAuraBeSecret", function() return restricted end) }
    C_UnitAuras = { GetPlayerAuraBySpellID = Native("GetPlayerAuraBySpellID", function(id)
        if restricted or not sated or id ~= 80354 then return nil end
        return { auraInstanceID = 41, spellId = 80354, duration = 600, expirationTime = clock.now + 500 }
    end) }
    IsInGroup = Native("IsInGroup", function() return true end)
    local config = Defaults("groupBloodlust", "QualityOfLifeGroup")
    config.enabled = true
    local m = Start("groupBloodlust", "GroupBloodlust.lua", config)
    Settle()
    assert(m.status.text == "Locked" and m.auraInstanceID == 41, "the sated player was not shown locked")
    -- Raid combat: buffs land with secret spell IDs while the lockout stays readable.
    -- One payload, built once: the KB pass measures the module, not the test.
    local buff = { isFullUpdate = false, addedAuras = { { spellId = Secret(), auraInstanceID = 7 } } }
    local function SecretBuff() Fire("UNIT_AURA", "player", buff) end
    Budget("groupBloodlust", "secretSteady", SecretBuff, Settle)
    Budget("groupBloodlust", "secretBurst", function()
        for _ = 1, 10 do SecretBuff() end
        Settle()
    end, Settle)
    assert(m.status.text == "Locked", "secret buffs changed the lockout")
    -- The lockout itself still counts: its removal and a new lockout repaint.
    sated = false
    Fire("UNIT_AURA", "player", { isFullUpdate = false, removedAuraInstanceIDs = { 41 } })
    Settle()
    assert(m.status.text == "Ready" and not m.auraInstanceID, "the lockout removal was missed")
    sated = true
    Fire("UNIT_AURA", "player", { isFullUpdate = false, addedAuras = { { spellId = 80354, auraInstanceID = 41 } } })
    Settle()
    assert(m.status.text == "Locked", "a new lockout was missed")
    -- A restriction that turns the lockout secret: read after its dispatch;
    -- the known lockout keeps counting and aura events stop.
    restricted = true
    Fire("ADDON_RESTRICTION_STATE_CHANGED", 1, 1)
    assert(m.context.callbacks.UNIT_AURA, "an activating restriction read during its own dispatch")
    Settle()
    assert(m.status.text == "Locked" and not m.context.callbacks.UNIT_AURA,
        "a restricted lockout was read or replaced")
    -- Missing data never reads as Ready: an unknown state after the countdown.
    clock.Advance(600)
    Fire("GROUP_ROSTER_UPDATE")
    assert(m.status.text == "Unknown", "an unreadable lockout state was shown as Ready")
    restricted, sated = false, false
    Fire("ADDON_RESTRICTION_STATE_CHANGED", 1, 0)
    assert(m.status.text == "Ready" and m.context.callbacks.UNIT_AURA, "the lifted restriction was not read")
    assert(#reported == 0, "group bloodlust raised: " .. tostring(reported[1]))
    Stop(m)
end

------------------------------------------------------------------ Nameplates text
-- Pooled plates: a region is restored when its plate goes and restyled when
-- the next unit takes it (Capture 496 B and Apply 350 B a call in the raid
-- trace, three tables per plate cycle). The cycle now reuses the region's
-- record and must still restore exactly what the client drew.
do
    local textNS = { NameplateStyle = {}, Safety = { IsForbidden = function() return false end } }
    local textS = { Finite = NS.Finite, Public = NS.Public,
        SetFont = function(region, path, size, flags) region:SetFont(path, size, flags) end }
    local textPrivate = { NS = textNS, Suite = textS }
    assert(loadfile(root .. "/MSUF_Suite_Nameplates/Text.lua"))("MSUF_Suite_Nameplates", textPrivate)
    local Text = textPrivate.Text
    local region = { font = { "native", 12, "" }, shadow = { 0, 0, 0, .6 }, offset = { 1, -1 } }
    function region:GetFont() return self.font[1], self.font[2], self.font[3] end
    function region:SetFont(path, size, flags) self.font = { path, size, flags } end
    function region:GetShadowColor() return unpack(self.shadow) end
    function region:SetShadowColor(r, g, b, a) self.shadow = { r, g, b, a } end
    function region:GetShadowOffset() return unpack(self.offset) end
    function region:SetShadowOffset(x, y) self.offset = { x, y } end
    local style = { enabled = true, font = "suite", flags = "OUTLINE", shadow = true }
    local function Cycle()
        Text.Apply(region, style, 14)
        Text.Restore(region)
    end
    Cycle()
    -- The KB pass of a hundred cycles: the region's own setters are test
    -- tables, so only reads (no stub tables) are counted here.
    region.SetFont = function(self, path, size, flags) local font = self.font; font[1], font[2], font[3] = path, size, flags end
    region.SetShadowColor = function(self, r, g, b, a) local c = self.shadow; c[1], c[2], c[3], c[4] = r, g, b, a end
    region.SetShadowOffset = function(self, x, y) local o = self.offset; o[1], o[2] = x, y end
    local used = Kilobytes(function() for _ = 1, 100 do Cycle() end end)
    print(string.format("nameplates text: 100 plate cycles %.3f KB", used))
    if used > .05 then failures[#failures + 1] = string.format("100 nameplate text cycles allocated %.3f KB", used) end
    assert(region.font[1] == "native" and region.font[2] == 12 and region.font[3] == ""
        and region.shadow[4] == .6 and region.offset[1] == 1 and region.offset[2] == -1,
        "a restored plate text lost its native font or shadow")
    -- The next plate brings its own native look: it is captured, never the
    -- previous plate's.
    region.font[1], region.font[2], region.shadow[4], region.offset[2] = "other", 10, .3, -2
    Text.Apply(region, style, 14)
    assert(region.font[1] == "suite" and region.font[2] == 14 and region.shadow[4] == 1,
        "the restyle of a reused region was not applied")
    Text.Restore(region)
    assert(region.font[1] == "other" and region.font[2] == 10 and region.shadow[4] == .3 and region.offset[2] == -2,
        "a reused region restored the previous plate's native look")
    region.font[1] = "later"
    Text.Restore(region)
    assert(region.font[1] == "later", "a second restore wrote the font again")
end

------------------------------------------------------------------ named event options
-- Context:Event's options are named ({ inCombat = true }); the positional
-- true is legacy. These hot-path files pass the named option.
for _, file in ipairs({ "MSUF_Suite_DamageMeter/Controller.lua", "MSUF_Suite_ActionBars/Events.lua",
    "MSUF_Suite_CooldownManager/Events.lua", "MSUF_Suite_QualityOfLife/GroupBloodlust.lua",
    "MSUF_Suite_QualityOfLife/GroupDeathAlert.lua", "MSUF_Suite_QualityOfLife/ActionTracker.lua",
    "MSUF_Suite_Modules/Raid.lua" }) do
    local handle = assert(io.open(root .. "/" .. file, "rb"))
    local source = handle:read("*a")
    handle:close()
    for call in source:gmatch(":Event(%b())") do
        local third = call:match("^%([^,]+,[^,]+,%s*([%w_]+)")
        assert(third ~= "true" and third ~= "ALLOW_COMBAT", file .. " passes a positional combat flag: " .. call)
    end
end

if #failures > 0 then error(table.concat(failures, "\n")) end
print("Suite hot event native budgets passed")

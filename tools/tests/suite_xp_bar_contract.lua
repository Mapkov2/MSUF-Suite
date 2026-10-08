local root = assert(arg[1], "repository root required")
local now, level, xp, maximum, rested = 100000, 10, 100, 1000, 300
local timers = {}
local nativeSyncCalls = 0

local function Widget()
    local w = { shown = true }
    function w:SetFrameStrata() end
    function w:EnableMouse() end
    function w:SetScript(key, callback) self[key] = callback end
    function w:CreateTexture() return Widget() end
    function w:CreateFontString() return Widget() end
    function w:SetPoint(...) self.point = { ... }; self.anchors = (self.anchors or 0) + 1 end
    function w:ClearAllPoints() end
    function w:SetColorTexture(...) self.color = { ... } end
    function w:SetVertexColor(...) self.vertex = { ... }; self.vertexWrites = (self.vertexWrites or 0) + 1 end
    function w:SetTexture(value) self.texture = value end
    function w:SetAllPoints() end
    function w:SetScale(value) self.scale = value end
    function w:GetEffectiveScale() return 1 end
    function w:SetSize(width, height) self.width, self.height = width, height end
    function w:SetShown(value) self.shown = value end
    function w:IsShown() return self.shown end
    function w:Show() self.shown = true end
    function w:Hide() self.shown = false end
    function w:SetText(value) self.text = value end
    function w:SetWidth(value) self.width = value end
    function w:SetHeight(value) self.height = value end
    function w:SetJustifyH() end
    function w:SetTextColor(...) self.textColor = { ... } end
    function w:SetFont(path, size, flags) self.font = { path, size, flags }; return true end
    return w
end

UIParent = Widget()
CreateFrame = function() return Widget() end
GetServerTime = function() return now end
UnitLevel = function() return level end
UnitXP = function() return xp end
UnitXPMax = function() return maximum end
GetXPExhaustion = function() return rested end
UnitGUID = function() return "Player-test" end
BreakUpLargeNumbers = tostring
-- The client's seconds formatter; the stand-in marks its output.
local formatted = {}
Enum = Enum or {}
Enum.SecondsFormatterInterval = Enum.SecondsFormatterInterval or { Seconds = 1 }
Enum.SecondsFormatterAbbreviation = Enum.SecondsFormatterAbbreviation or { OneLetter = 2 }
C_StringUtil = { CreateSecondsFormatter = function()
    local formatter = {}
    function formatter:SetDesiredUnitCount(count) self.units = count end
    function formatter:SetMinInterval(interval) self.minimum = interval end
    function formatter:SetDefaultAbbreviation(mode) self.abbreviation = mode end
    function formatter:Format(seconds)
        assert(self.units == 2 and self.abbreviation == 2, "durations need two one-letter units")
        formatted[#formatted + 1] = seconds
        return "<" .. seconds .. "s>"
    end
    return formatter
end }
-- Blizzard_GameTooltip builds GameTooltip at startup on both clients.
local tooltip = { lines = {}, draws = 0 }
GameTooltip = tooltip
function tooltip:SetOwner(owner) self.owner, self.draws = owner, self.draws + 1 end
function tooltip:IsOwned(owner) return self.shown and self.owner == owner end
function tooltip:ClearLines() self.lines = {} end
function tooltip:AddLine(text) self.lines[#self.lines + 1] = text end
function tooltip:AddDoubleLine(left, right) self.lines[#self.lines + 1] = left .. " | " .. right end
function tooltip:Show() self.shown = true end
function tooltip:Hide() self.shown = false end
-- Blizzard_SharedXML defines GameRulesUtil on both clients.
local uncappedRules = { IsPlayerAtEffectiveMaxLevel = function() return false end }
GameRulesUtil = uncappedRules
C_Timer = { After = function(seconds, callback)
    assert(seconds == 60, "the rate refresh waits a minute")
    timers[#timers + 1] = { callback = callback }
end }

-- MSUF's media comes from the suite's shared table (NS.MSUFMedia); the real
-- paths are covered by suite_platform_contract.
local MEDIA = { font = "Interface\\AddOns\\Test\\Media\\MSUF.ttf", barTexture = "Interface\\AddOns\\Test\\Media\\MSUF.tga" }
local savedRoot = {}
local translate
local function Load(kind)
    local callbacks, movers = {}, {}
    local suite = { editMode = false, loginKind = kind, RootDB = savedRoot, MSUFMedia = MEDIA,
        InCombat = function() return false end,
        IsCombatLocked = function() return false end,
        Dispatch = function(callback, ...) return callback(...) end,
        AnchorPoints = { "TOPLEFT", "TOP", "TOPRIGHT", "LEFT", "CENTER", "RIGHT", "BOTTOMLEFT", "BOTTOM", "BOTTOMRIGHT" } }
    suite.Suite = { instances = {}, editMode = false }
    local runtime = suite.Suite
    runtime.ApplyOwnedLayer = function() return false end
    runtime.ApplyOwnedChildLayer = function() return false end
    runtime.GlobalFontPath = function() return MEDIA.font end
    runtime.Public = function(value) return value ~= "secret" end
    -- Readable-number helpers as defined by MSUF_Suite_Modules/Runtime.lua.
    runtime.Number = function(value) return runtime.Public(value) and type(value) == "number" and value == value end
    runtime.Finite = function(value) return runtime.Number(value) and value > -math.huge and value < math.huge end
    runtime.Text = function(value) return translate and translate(value) or value end
    runtime.CreateFrame = CreateFrame
    runtime.CreateTexture = function(parent, ...) return parent:CreateTexture(...) end
    runtime.CreateFontString = function(parent, ...) return parent:CreateFontString(...) end
    runtime.ResolveTexture = function(_, fallback) return fallback end
    runtime.RGB = function(hex)
        return tonumber(hex:sub(1, 2), 16) / 255, tonumber(hex:sub(3, 4), 16) / 255, tonumber(hex:sub(5, 6), 16) / 255
    end
    runtime.Install = function(id, module)
        assert(id == "xpBar")
        runtime.instances[id] = module
    end
    runtime.RegisterOwnedMover = function(id, elementID, spec)
        assert(id == "xpBar" and elementID == "experience" and spec.xKey == "x")
        movers[elementID] = spec
        return true
    end
    runtime.Config = function() return runtime.instances.xpBar.config end
    runtime.Set = function(_, key, value) runtime.instances.xpBar.config[key] = value; return true end
    runtime.SetFont = function(fontString, path, size, flags) return fontString:SetFont(path, size, flags) end
    -- The shared anchor list comes from the core catalog builders.
    assert(loadfile(root .. "/MSUF_Suite/Core/SuiteCatalog.lua"))("MSUF_Suite", suite)
    MSUFSuite = suite
    local private = {}
    for _, file in ipairs({ "Bootstrap", "NativeExperienceBar", "ExperienceBar" }) do
        assert(loadfile(root .. "/MSUF_Suite_QualityOfLife/" .. file .. ".lua"))("MSUF_Suite_QualityOfLife", private)
    end
    local module = runtime.instances.xpBar
    local sync = private.NativeExperienceBar.Sync
    private.NativeExperienceBar.Sync = function(...)
        nativeSyncCalls = nativeSyncCalls + 1
        return sync(...)
    end
    module.active = true
    module.config = { enabled = true, look = 1, width = 400, height = 18, scale = 100,
        showSegments = true, showRested = true, showSession = true, showRate = true, showETA = true,
        hideAtMax = true, point = 8, x = 0, y = 148 }
    module.context = dofile(root .. "/tools/tests/suite_test_support.lua").ModuleTimers(root, runtime, suite)(
        "xpBar", module, { Event = function(_, name, callback, allowCombat)
        assert(allowCombat and not callbacks[name])
        callbacks[name] = callback
    end })
    module:Enable()
    module:RegisterMovers() -- the controller registers movers after Enable
    return module, runtime, callbacks, movers, suite
end

-- Sentences reach the language pack whole: with every English string wrapped, the level
-- line and each detail are one translated sentence around their numbers.
translate = function(value) return "<" .. value .. ">" end
local worded = Load("login")
translate = nil
assert(worded.levelText.text == "<Lv 10  100 / 1.0k>", "the XP level line was joined after translation")
assert(worded.details.text:find("<Session +0>", 1, true) and worded.details.text:find("<XP/h -->", 1, true)
    and worded.details.text:find("<To level -->", 1, true), "an XP detail was joined after translation")

local module, runtime, events, movers, suite = Load("login")
assert(module.session.gained == 0 and module.host:IsShown())
assert(module.restedMarker:IsShown() and module.restedMarker.point[4] == 160
    and module.restedMarker.height == 22,
    "rested marker must sit at current XP plus rested XP")
assert(module.fill.texture == MEDIA.barTexture
    and module.rested.texture == module.fill.texture, "both XP fills must use MSUF bar art from NS.MSUFMedia")
assert(module.levelText.font[1] == MEDIA.font
    and module.details.font[1] == module.levelText.font[1], "XP texts must use the MSUF font from NS.MSUFMedia")
assert(math.abs(module.edges[1].color[1] - 0x57 / 255) < 0.001
    and math.abs(module.panel.color[3] - 0x20 / 255) < 0.001, "Midnight colors")
module.config.look = 2
module:Refresh()
assert(math.abs(module.edges[1].color[1] - 0xb9 / 255) < 0.001
    and math.abs(module.panel.color[1] - 0x15 / 255) < 0.001, "Midnight Dark colors")
module.config.look = 3
module:Refresh()
assert(math.abs(module.edges[1].color[1] - 0xd8 / 255) < 0.001
    and math.abs(module.panel.color[1] - 0x14 / 255) < 0.001, "MSUF Forever colors")
assert(module.fill.texture == MEDIA.barTexture and module.levelText.text:find("100 / 1.0k", 1, true),
    "switching styles must keep the MSUF texture and XP values")
assert(module.restedMarker.color[3] > module.restedMarker.color[1],
    "Forever style must keep a distinct rested marker")
suite.ChatLookPresets = { [6] = { panelColor = "101010", borderColor = "402818",
    accentColor = "ff7d0a", tabActiveColor = "f5f5f5", tabInactiveColor = "bfc4c9" } }
suite.SuiteLooks.classRevision = 1
module.config.look = 6
module:Refresh()
assert(module.appliedLook == 6 and module.fill.vertex[1] == 1
    and math.abs(module.fill.vertex[2] - 0x7d / 255) < 0.001,
    "Class Style must use the shared player-class accent")
local writes = module.fill.vertexWrites
module:Refresh()
assert(module.fill.vertexWrites == writes, "unchanged Class Style repaints the XP fill")
suite.ChatLookPresets[6].accentColor = "ffffff"
suite.SuiteLooks.classRevision = 2
module:Refresh()
assert(module.fill.vertex[1] == 1 and module.fill.vertex[2] == 1 and module.fill.vertex[3] == 1
    and module.panel.color[1] < 0.1 and module.background.color[1] < 0.1,
    "same-index class palette refresh must update the fill and keep Priest surfaces dark")
assert(module.rested.vertex[1] < module.fill.vertex[1] and module.fill.texture == MEDIA.barTexture,
    "Class Style must preserve distinct rested XP and the authored bar texture")
-- The Custom style paints the bar's own colors and repaints only on a change.
module.config.customFill, module.config.customRested = "6fc3a0", "6c8fd6"
module.config.customPanel, module.config.customBorder = "111820", "aab8c4"
module.config.look = 4
module:Refresh()
assert(module.appliedLook == 4 and math.abs(module.fill.vertex[1] - 0x6f / 255) < 0.001
    and math.abs(module.panel.color[1] - 0x11 / 255) < 0.001
    and math.abs(module.edges[2].color[1] - 0xaa / 255) < 0.001
    and math.abs(module.rested.vertex[3] - 0xd6 / 255) < 0.001, "the Custom style ignored its colors")
writes = module.fill.vertexWrites
module:Refresh()
assert(module.fill.vertexWrites == writes, "an unchanged Custom style repainted the bar")
module.config.customFill = "ff0000"
module:Refresh()
assert(module.fill.vertex[1] == 1 and module.fill.vertex[2] == 0, "a new custom bar color was not painted")
module.config.look = 1
module:Refresh()
module.config.showRested = false
module:Refresh()
assert(not module.restedMarker:IsShown() and not module.rested:IsShown(),
    "hiding rested XP must hide its endpoint too")
module.config.showRested = true
rested = 1200
events.UPDATE_EXHAUSTION(module, "UPDATE_EXHAUSTION")
assert(not module.restedMarker:IsShown(), "rested endpoint at the bar edge should stay hidden")
rested = 300
events.UPDATE_EXHAUSTION(module, "UPDATE_EXHAUSTION")
assert(module.restedMarker:IsShown(), "rested endpoint did not return after exhaustion changed")
assert(#module.segments == 19 and module.segments[1]:IsShown())
assert(module.segments[1].point[4] == 20 and module.segments[19].point[4] == 380,
    "divisions must mark each 5 percent of the bar")
module.config.showSegments = false
module:Refresh()
for _, divider in ipairs(module.segments) do assert(not divider:IsShown()) end
module.config.width, module.config.showSegments = 220, true
module:Refresh()
assert(module.segments[1]:IsShown() and module.segments[1].point[4] == 11,
    "divisions did not follow the configured width")
assert(movers.experience and events.PLAYER_XP_UPDATE and events.PLAYER_LEVEL_UP)
assert(movers.experience.quickPosition and not movers.experience.extraControls
    and table.concat(movers.experience.sizeKeys, ",") == "width,height,scale",
    "XP Edit Mode popup is missing exact position or size controls")
-- MSUF Edit Mode's size controls write these keys through S.Set.
runtime.Set(nil, "scale", 125)
module:Refresh()
assert(module.host.scale == 1.25, "XP popup scale did not reach runtime")
runtime.Set(nil, "scale", 100)
module:Refresh()
assert(module.levelText.text:find("100 / 1.0k", 1, true))

xp = 250
local syncCalls = nativeSyncCalls
local dividerAnchors, savedRecord = module.segments[1].anchors, savedRoot.suiteXP["Player-test"]
events.PLAYER_XP_UPDATE(module, "PLAYER_XP_UPDATE", "player")
assert(nativeSyncCalls == syncCalls, "an XP update walked Blizzard containers")
assert(module.session.gained == 150 and savedRoot.suiteXP["Player-test"].gained == 150)
assert(module.segments[1].anchors == dividerAnchors and savedRoot.suiteXP["Player-test"] == savedRecord,
    "an XP event re-anchored the dividers or replaced the saved session record")
assert(module.details.text:find("Session +150", 1, true))
-- Hovering the bar lists the progress and this session; a rested change
-- while it is open redraws it, leaving hides it.
module.host.OnEnter(module.host)
assert(tooltip.shown and tooltip.owner == module.host and tooltip.lines[1] == "Experience"
    and tooltip.lines[2] == "Level | 10" and tooltip.lines[3] == "Current XP | 250 / 1000"
    and tooltip.lines[5] == "Rested XP | 300" and tooltip.lines[8] == "Session XP | +150",
    "the XP tooltip did not list progress and session")
local draws = tooltip.draws
rested = 400
events.UPDATE_EXHAUSTION(module, "UPDATE_EXHAUSTION")
assert(tooltip.draws == draws + 1 and tooltip.lines[5] == "Rested XP | 400",
    "an open XP tooltip did not follow the new values")
module.host.OnLeave(module.host)
rested = 300
events.UPDATE_EXHAUSTION(module, "UPDATE_EXHAUSTION")
assert(not tooltip.shown and tooltip.draws == draws + 1, "a hidden XP tooltip was redrawn")
assert(#timers == 1, "one rate refresh timer")
xp = 900
events.PLAYER_XP_UPDATE(module, "PLAYER_XP_UPDATE", "target")
assert(module.session.gained == 150, "other unit ignored")
events.PLAYER_XP_UPDATE(module, "PLAYER_XP_UPDATE", "player")
assert(module.session.gained == 800)

-- An XP rollover before the level event must not destroy the old baseline.
xp = 80
events.PLAYER_XP_UPDATE(module, "PLAYER_XP_UPDATE", "player")
assert(module.session.gained == 800 and module.session.lastXP == 900)
level, maximum = 11, 1200
events.PLAYER_LEVEL_UP(module, "PLAYER_LEVEL_UP")
assert(module.session.gained == 980 and module.session.levelUps == 1)
now = now + 3600
timers[1].callback()
assert(module.details.text:find("XP/h 980", 1, true))
assert(module.details.text:find("To level <", 1, true) and #formatted > 0,
    "time to level did not use the client's seconds formatter")

-- The effective maximum level can change without a level change (party sync,
-- Timewalking, a new cap): world entry and Refresh read it again.
local capped = false
GameRulesUtil = { IsPlayerAtEffectiveMaxLevel = function() return capped end }
module:Refresh()
assert(module.host:IsShown(), "an uncapped character hid the XP bar")
capped = true
module:Refresh()
assert(not module.host:IsShown(), "Refresh kept a stale maximum-level state")
capped = false
module:Refresh()
assert(module.host:IsShown(), "Refresh kept a stale maximum-level state")
capped = true
events.PLAYER_ENTERING_WORLD(module, "PLAYER_ENTERING_WORLD")
assert(not module.host:IsShown(), "entering the world kept a stale maximum-level state")
capped = false
module:Refresh()
GameRulesUtil = uncappedRules

module:Disable()
local reloaded, reloadedRuntime = Load("reload")
assert(reloaded.session.gained == 980 and reloaded.session.levelUps == 1)
assert(reloaded.session.started == 100000, "/reload preserves session start")
assert(reloadedRuntime.ResetXPSession())
assert(reloaded.session.gained == 0 and savedRoot.suiteXP["Player-test"].gained == 0)

reloaded:Disable()
local nextLogin, nextRuntime = Load("login")
assert(nextLogin.session.gained == 0 and nextLogin.session.started == now)
maximum = 0
nextLogin:Refresh()
assert(not nextLogin.host:IsShown(), "maximum level hides the bar")
assert(not nextLogin.restedMarker:IsShown(), "maximum level left a rested marker visible")
nextRuntime.editMode = true
nextLogin:Refresh()
assert(nextLogin.host:IsShown(), "Edit Mode still previews the bar")
-- Suite-created regions go through the shared S.CreateTexture/S.CreateFontString.
local sourceFile = assert(io.open(root .. "/MSUF_Suite_QualityOfLife/ExperienceBar.lua", "rb"))
local source = sourceFile:read("*a")
sourceFile:close()
assert(not source:find(":CreateTexture%(") and not source:find(":CreateFontString%("),
    "the XP bar creates regions without S.CreateTexture/S.CreateFontString")
-- Retail and WoW Forever always have the APIs the XP bar calls.
for _, name in ipairs({ "ExperienceBar" }) do
    local file = assert(io.open(root .. "/MSUF_Suite_QualityOfLife/" .. name .. ".lua", "rb"))
    local source = file:read("*a")
    file:close()
    local guarded = source:match("type%(([^)]*)%)%s*[~=]=%s*\"function\"") or source:match("(C_%w+) and C_%w+%.")
        or source:match("(GameTooltip) and") or source:match("not (GameTooltip) then")
    assert(not guarded, name .. ".lua guards " .. tostring(guarded) .. " as if a client lacked it")
end
print("suite_xp_bar_contract: OK")

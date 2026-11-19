local root = assert(arg[1], "repository root required")
local now, level, xp, maximum, rested = 100000, 10, 100, 1000, 300
local timers = {}
local nativeSyncCalls = 0

local function Widget(parent)
    local w = { shown = true, parent = parent }
    function w:SetFrameStrata(value) self.strata = value end
    function w:EnableMouse(value) self.mouse = value end
    function w:SetAlpha(value) self.alpha = value end
    function w:SetScript(key, callback) self[key] = callback end
    function w:GetScript(key) return self[key] end
    -- A hook runs after the frame's own script, as the client's HookScript.
    function w:HookScript(key, callback)
        local original = self[key]
        self[key] = function(...)
            if original then original(...) end
            callback(...)
        end
    end
    function w:CreateTexture() return Widget() end
    function w:CreateFontString() return Widget() end
    function w:SetPoint(...) self.point = { ... }; self.anchors = (self.anchors or 0) + 1 end
    function w:ClearAllPoints() end
    function w:SetColorTexture(...) self.color = { ... }; self.colorWrites = (self.colorWrites or 0) + 1 end
    function w:SetVertexColor(...) self.vertex = { ... }; self.vertexWrites = (self.vertexWrites or 0) + 1 end
    function w:SetTexture(value) self.texture = value; self.textureWrites = (self.textureWrites or 0) + 1 end
    function w:SetAllPoints() end
    function w:SetScale(value) self.scale = value end
    function w:GetScale() return self.scale or 1 end
    function w:GetStringWidth() return #(self.text or "") * (self.font and self.font[2] or 11) * .55 end
    function w:GetStringHeight() return self.font and self.font[2] or 11 end
    function w:GetEffectiveScale() return (self.scale or 1) * (self.parent and self.parent:GetEffectiveScale() or 1) end
    function w:GetRight() return self.right or 500 end
    function w:SetSize(width, height) self.width, self.height = width, height end
    function w:SetShown(value) self.shown = value end
    function w:IsShown() return self.shown end
    function w:IsVisible()
        local widget = self
        while widget do
            if not widget.shown then return false end
            widget = widget.parent
        end
        return true
    end
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

-- Frames that run OnShow/OnHide as the client does: synchronously, for the
-- frame and every descendant whose effective visibility changes. Opt-in
-- (eventFrames), so the VM budgets below keep measuring the plain widgets.
local function Collect(widget, list)
    list[#list + 1] = widget
    list[#list + 1] = widget:IsVisible()
    for _, child in ipairs(widget.children or {}) do Collect(child, list) end
end
local function SetVisible(widget, value)
    value = value and true or false
    if widget.shown == value then return end
    local list = {}
    Collect(widget, list)
    widget.shown = value
    for index = 1, #list, 2 do
        local changed, visible = list[index], list[index]:IsVisible()
        if visible ~= list[index + 1] then
            local script = visible and changed.OnShow or changed.OnHide
            if script then script(changed) end
        end
    end
end
local eventFrames = false
local function EventFrame(parent)
    local frame = Widget(parent)
    if parent then
        parent.children = parent.children or {}
        parent.children[#parent.children + 1] = frame
    end
    frame.SetShown = SetVisible
    function frame:Show() SetVisible(self, true) end
    function frame:Hide() SetVisible(self, false) end
    return frame
end

UIParent = Widget()
CreateFrame = function(_, _, parent)
    if eventFrames then return EventFrame(parent) end
    return Widget(parent)
end
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
    -- The session-readiness retry is the only timer in the base XP bar.
    assert(seconds == .2, "unexpected XP bar timer")
    timers[#timers + 1] = { callback = callback, seconds = seconds }
end }

-- MSUF's media comes from the suite's shared table (NS.MSUFMedia); the real
-- paths are covered by suite_platform_contract.
local MEDIA = { font = "Interface\\AddOns\\Test\\Media\\MSUF.ttf", barTexture = "Interface\\AddOns\\Test\\Media\\MSUF.tga" }
local savedRoot = {}
local translate
local function Load(kind, forever)
    local callbacks, movers = {}, {}
    local suite = { editMode = false, loginKind = kind, RootDB = savedRoot, MSUFMedia = MEDIA,
        InCombat = function() return false end,
        IsCombatLocked = function() return false end,
        Dispatch = function(callback, ...) return callback(...) end,
        Client = { isForever = forever == true },
        AnchorPoints = { "TOPLEFT", "TOP", "TOPRIGHT", "LEFT", "CENTER", "RIGHT", "BOTTOMLEFT", "BOTTOM", "BOTTOMRIGHT" } }
    suite.Suite = { instances = {}, editMode = false }
    local runtime = suite.Suite
    runtime.ApplyOwnedLayer = function() return false end
    runtime.ApplyOwnedChildLayer = function() return false end
    runtime.GlobalFontPath = function() return MEDIA.font end
    runtime.Public = function(value)
        return (not issecretvalue or not issecretvalue(value)) and value ~= "secret"
    end
    -- Readable-number helpers as defined by MSUF_Suite_Modules/Runtime.lua.
    runtime.Number = function(value) return runtime.Public(value) and type(value) == "number" and value == value end
    runtime.Finite = function(value) return runtime.Number(value) and value > -math.huge and value < math.huge end
    runtime.Text = function(value) return translate and translate(value) or value end
    runtime.Print = function(message) runtime.lastReminder = message end
    runtime.CreateFrame = CreateFrame
    runtime.CreateTexture = function(parent, ...) return parent:CreateTexture(...) end
    runtime.CreateFontString = function(parent, ...) return parent:CreateFontString(...) end
    runtime.ResolveTexture = function(_, fallback) return fallback end
    runtime.ResolveFont = function() return nil end
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
    assert(loadfile(root .. "/MSUF_Suite/Core/ExperienceBarLayout.lua"))("MSUF_Suite", suite)
    MSUFSuite = suite
    local private = {}
    for _, file in ipairs({ "Bootstrap", "NativeExperienceBar", "ExperienceTrack", "ExperienceBarText", "ExperienceOptimizer",
        "ExperienceBar", "ExperienceBarSlot" }) do
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
        callbacks[name] = dofile(root .. "/tools/tests/suite_test_support.lua").EventCallback(callback)
    end, RemoveEvent = function(_, name) callbacks[name] = nil end })
    module:Enable()
    module:RegisterMovers() -- the controller registers movers after Enable
    return module, runtime, callbacks, movers, suite
end

-- Sentences reach the language pack whole: with every English string wrapped, the level
-- line and each detail are one translated sentence around their numbers.
translate = function(value) return "<" .. value .. ">" end
local worded = Load("login")
translate = nil
assert(worded.levelText.text == "<Lv 10>" and worded.xpText.text == "<100 / 1.0k>", "XP texts bypassed whole format keys")
assert(worded.sessionText.text == "<Session +0>" and worded.rateText.text == "<XP/h -->"
    and worded.etaText.text == "<To level -->", "an XP detail was joined after translation")

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
assert(module.fill.texture == MEDIA.barTexture and module.xpText.text:find("100 / 1.0k", 1, true),
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
    and module.panel.color[1] < 0.1 and module.background.vertex[1] < 0.1,
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
assert(module.xpText.text:find("100 / 1.0k", 1, true))

xp = 250
local syncCalls = nativeSyncCalls
local dividerAnchors, savedRecord = module.segments[1].anchors, savedRoot.suiteXP["Player-test"]
local dividerPaints = module.segments[1].colorWrites
local textGeometry = {}
for id, state in pairs(module.xpTexts) do textGeometry[id] = { state.region.anchors, state.region.font } end
local fillTextureWrites, backgroundTextureWrites = module.fill.textureWrites, module.background.textureWrites
-- The first gain now draws its rate and ETA immediately (1001 instructions,
-- 5 text writes). The unchanged event needs 688 instructions and no writes.
-- Preserve the geometry invariants and guard both offline budgets.
local vmCount, textWrites = 0, 0
for _, key in ipairs({ "levelText", "xpText", "percentText", "sessionText", "rateText", "etaText", "details" }) do
    local region = module[key]
    local native = region.SetText
    region.SetText = function(self, value) textWrites = textWrites + 1; return native(self, value) end
end
debug.sethook(function() vmCount = vmCount + 1 end, "", 1)
events.PLAYER_XP_UPDATE(module, "PLAYER_XP_UPDATE", "player")
debug.sethook()
assert(vmCount <= 1021 and textWrites == 5, "first XP event exceeded the rate and ETA paint budget")
vmCount, textWrites = 0, 0
debug.sethook(function() vmCount = vmCount + 1 end, "", 1)
events.PLAYER_XP_UPDATE(module, "PLAYER_XP_UPDATE", "player")
debug.sethook()
assert(vmCount <= 702 and textWrites == 0, "unchanged XP event exceeded text VM/native budget")
assert(nativeSyncCalls == syncCalls, "an XP update walked Blizzard containers")
assert(module.session.gained == 150 and savedRoot.suiteXP["Player-test"].gained == 150)
assert(module.segments[1].anchors == dividerAnchors and savedRoot.suiteXP["Player-test"] == savedRecord,
    "an XP event re-anchored the dividers or replaced the saved session record")
assert(module.segments[1].colorWrites == dividerPaints, "an XP event repainted static dividers")
for id, state in pairs(module.xpTexts) do
    assert(state.region.anchors == textGeometry[id][1] and state.region.font == textGeometry[id][2],
        "XP event moved or restyled " .. id)
end
assert(module.fill.textureWrites == fillTextureWrites and module.background.textureWrites == backgroundTextureWrites,
    "XP event reset a SharedMedia texture")
assert(module.sessionText.text:find("Session +150", 1, true))
assert(now - module.session.started < 60 and module.rateText.text ~= "XP/h --"
    and module.etaText.text ~= "To level --", "the first XP gain left the ETA unavailable")
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
assert(#timers == 0, "earning XP or showing a tooltip scheduled a rate refresh")
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
local idleRate, idleETA = module.rateText.text, module.etaText.text
now = now + 3600
assert(module.rateText.text == idleRate and module.etaText.text == idleETA and #timers == 0,
    "the XP rate or ETA changed while idle")
module.host.OnEnter(module.host)
assert(module.rateText.text:find("XP/h 980", 1, true))
assert(module.etaText.text:find("To level <", 1, true) and #formatted > 0,
    "hover did not refresh time to level using the client's seconds formatter")
assert(tooltip.lines[#tooltip.lines - 1] == "Time to level | <4114s>", "bar and tooltip used different ETA samples")
module.host.OnLeave(module.host)

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
-- Menu samples reuse all three live layouts without reading XP or touching the
-- active host, session, native visibility owner or refresh timer.
-- The same native regions accept independent media and text overrides.
now, level, xp, maximum, rested = 100000, 42, 38000, 100000, 19000
local customized, mediaRuntime = Load("login")
local mediaPaths = { Foreground = "Media/Foreground", Background = "Media/Background", Other = "Media/Other" }
mediaRuntime.ResolveTexture = function(key, fallback) return mediaPaths[key] or fallback end
mediaRuntime.ResolveFont = function(key) return key == "XP font" and "Media/XP.ttf" or nil end
local c = customized.config
c.barTexture, c.backgroundTexture, c.look = "Foreground", "Background", 3
c.levelTextFont, c.levelTextSize, c.levelTextOutline = "XP font", 22, 4
c.levelTextAnchor, c.levelTextX, c.levelTextY, c.percentTextFormat = 2, 23, -17, 4
customized:Refresh()
assert(customized.fill.texture == "Media/Foreground" and customized.rested.texture == "Media/Foreground"
    and customized.background.texture == "Media/Background", "independent LSM textures were not applied")
assert(customized.background.vertex and not customized.background.color, "palette paint replaced the chosen background texture")
assert(customized.levelText.font[1] == "Media/XP.ttf" and customized.levelText.font[2] == 22
    and customized.levelText.font[3] == "THICKOUTLINE", "per-text font or outline was ignored")
assert(customized.levelText.point[1] == "TOPLEFT" and customized.levelText.point[4] == 23
    and customized.levelText.point[5] == -17 and customized.percentText.text == "38.00%", "text anchor/offset/format was ignored")
c.barTexture, c.look = "Other", 1
customized:Refresh()
assert(customized.fill.texture == "Media/Other" and customized.background.texture == "Media/Background", "foreground/look edit reset background")
c.barTexture, c.backgroundTexture, c.levelTextFont = "missing", "missing", "missing"
customized:Refresh()
assert(customized.fill.texture == MEDIA.barTexture and customized.background.texture == "Interface\\Buttons\\WHITE8X8"
    and customized.levelText.font[1] == MEDIA.font, "unavailable media did not inherit safe defaults")
c.levelTextFormat, c.levelTextNumbers = 4, 3
customized:Refresh()
assert(customized.levelText.text == "Lv 42  38000 / 100000" and not customized.xpText:IsShown(), "combined legacy/full-number format failed")
c.levelTextFormat, c.xpTextFormat = 3, 4
customized:Refresh()
assert(customized.levelText.text == "42" and customized.xpText.text == "62k" and customized.xpText:IsShown(), "independent value/remaining formats failed")
-- Different progress must not disguise a selected layout. At low XP the first
-- filled gap is behind the label; all the empty cells still need visible lines.
local parityParent = Widget()
parityParent:SetScale(1.2)
nextLogin.config.width, nextLogin.config.height, nextLogin.config.scale = 450, 12, 143
nextLogin.config.customFill, nextLogin.config.customRested = "6fc3a0", "6c8fd6"
nextLogin.config.customPanel, nextLogin.config.customBorder = "111820", "aab8c4"
local function SameColor(left, right)
    for index = 1, 4 do assert(left[index] == right[index], "preview/runtime palette diverged") end
end
for look = 1, 6 do
    nextLogin.config.look = look
    for style = 1, 3 do
        nextLogin.config.displayStyle = style
        nextLogin:Refresh()
        nextRuntime.DrawExperienceBarPreview(parityParent, nextLogin.config, { xp = 38, rested = 19 },
            { scale = 1.43 / 1.2, width = 1000, height = 200 })
        local preview = parityParent.suiteXPPreview
        assert(math.abs(preview.host:GetEffectiveScale() - nextLogin.host:GetEffectiveScale()) < .0001,
            "preview/runtime effective scale diverged")
        SameColor(preview.fill.vertex, nextLogin.fill.vertex)
        SameColor(preview.background.vertex, nextLogin.background.vertex)
        assert(preview.fill.texture == nextLogin.fill.texture and preview.panel:IsShown() == nextLogin.panel:IsShown())
        assert(preview.percentText.font[2] == nextLogin.percentText.font[2])
        for index, divider in ipairs(nextLogin.segments) do
            local sampleDivider = preview.segments[index]
            SameColor(sampleDivider.color, divider.color)
            assert(math.abs(sampleDivider.width - divider.width) < .0001
                and math.abs(sampleDivider.point[4] - divider.point[4]) < .0001,
                "preview/runtime segment pixel geometry diverged")
            if style == 3 then
                local gap, track = divider.color, nextLogin.background.vertex
                assert(gap[1] ~= track[1] or gap[2] ~= track[2] or gap[3] ~= track[3],
                    "segmented layout disappears over the empty XP track")
            end
        end
    end
end
-- Exercise the real core boundary while the optional XP addon is absent.
do
    local originalRoot, originalGUID, originalNamespace = savedRoot, UnitGUID, MSUFSuite
    savedRoot = {}
    local function World(kind, owner)
        local create, after, frames = CreateFrame, C_Timer.After, {}
        CreateFrame = function()
            local frame = Widget()
            function frame:RegisterEvent() end
            function frame:UnregisterAllEvents() end
            frames[#frames + 1] = frame
            return frame
        end
        C_Timer.After = function(delay) assert(delay == 0) end
        owner = owner or { RootDB = savedRoot, Suite = { started = false }, Finite = runtime.Finite,
            Dispatch = function(fn, ...) return fn(...) end }
        owner.Finite = runtime.Finite
        owner.Client = owner.Client or { isForever = false }
        owner.Skin, owner.CaptureSessionGold = { SettleChatColors = function() end }, function() end
        assert(loadfile(root .. "/MSUF_Suite/Core/Startup.lua"))("MSUF_Suite", owner)
        frames[2].OnEvent(frames[2], "PLAYER_ENTERING_WORLD", kind == "login", kind == "reload")
        CreateFrame, C_Timer.After = create, after
        return owner.loginKind
    end
    level, xp, maximum = 20, 100, 1000
    local old, oldRuntime, oldEvents = Load("login")
    now, xp = now + 100, 175
    oldEvents.PLAYER_XP_UPDATE(old, "PLAYER_XP_UPDATE", "player")
    local oldStart = old.session.started
    old:Disable()
    -- Updating the addon during a session must still adopt a legacy unstamped save.
    World("reload")
    local legacy = Load("reload")
    assert(legacy.session.started == oldStart and legacy.session.gained == 75, "legacy reload lost session")
    legacy:Disable()
    local other = { started = 1, gained = 99 }
    savedRoot.suiteXP["Other-character"] = other
    UnitGUID = function() return nil end
    World("login")
    UnitGUID = originalGUID
    assert(savedRoot.suiteXP["Other-character"] == other, "login removed another character's record")
    now = now + 200
    World("reload")
    local fresh, freshRuntime, freshEvents = Load("reload")
    assert(fresh.session.started == now and fresh.session.gained == 0,
        "disabled login followed by reload revived the previous session")
    xp = xp + 25
    freshEvents.PLAYER_XP_UPDATE(fresh, "PLAYER_XP_UPDATE", "player")
    local freshStart, freshRecord = fresh.session.started, savedRoot.suiteXP["Player-test"]
    now = now + 300
    fresh:Disable()
    World("reload")
    UnitGUID = function() return nil end
    local waiting = Load("reload")
    assert(waiting.session == nil and savedRoot.suiteXP["Player-test"] == freshRecord,
        "unreadable GUID overwrote the valid saved session")
    UnitGUID = originalGUID
    assert(timers[#timers].seconds == .2, "missing GUID did not schedule readiness retry")
    timers[#timers].callback()
    assert(waiting.session.started == freshStart and waiting.session.gained == 25, "GUID readiness lost reload session")
    waiting:Disable()
    local pending, _, pendingEvents, _, pendingSuite = Load(nil)
    pendingEvents.PLAYER_ENTERING_WORLD(pending, "PLAYER_ENTERING_WORLD")
    assert(pending.session == nil and savedRoot.suiteXP["Player-test"] == freshRecord,
        "module world entry initialized before core classified login")
    World("login", pendingSuite)
    timers[#timers].callback()
    assert(pending.session.started == now and pending.session.gained == 0, "deferred login did not reset session")
    local started = pending.session.started
    now = now + 80
    pendingEvents.PLAYER_ENTERING_WORLD(pending, "PLAYER_ENTERING_WORLD")
    assert(pending.session.started == started, "zone entry reset the current session")
    pending:Disable()
    local record = savedRoot.suiteXP["Player-test"]
    UnitGUID = function() return nil end
    local before = #timers
    local bounded, _, boundedEvents = Load("reload")
    local cursor = before + 1
    while timers[cursor] do
        assert(cursor <= before + 5, "login readiness retries were not bounded")
        assert(timers[cursor].seconds == .2)
        timers[cursor].callback()
        cursor = cursor + 1
    end
    assert(#timers == before + 5 and bounded.session == nil and savedRoot.suiteXP["Player-test"] == record,
        "pending GUID corrupted saved data or kept polling")
    UnitGUID = originalGUID
    boundedEvents.PLAYER_XP_UPDATE(bounded, "PLAYER_XP_UPDATE", "player")
    assert(bounded.session.started == started, "natural XP event did not recover after retry budget")
    bounded:Disable()
    UnitGUID = function() return nil end
    local stopped = Load("reload")
    local cancelled = timers[#timers].callback
    stopped:Disable()
    UnitGUID = originalGUID
    cancelled()
    assert(stopped.session == nil and savedRoot.suiteXP["Player-test"] == record,
        "disabled module ran a stale session-readiness callback")
    savedRoot, MSUFSuite = originalRoot, originalNamespace
end

do
    local requests = 0
    GetTime = function() return now end
    RequestTimePlayed = function() requests = requests + 1 end
    level, xp, maximum = 21, 11108, 25200
    local played, playedRuntime, playedEvents = Load("login")
    local waits = #timers
    assert(not playedEvents.TIME_PLAYED_MSG and requests == 0, "disabled level time requested /played")
    played.config.showLevelTime = true
    played:Refresh()
    assert(requests == 1 and playedEvents.TIME_PLAYED_MSG, "level time did not request /played with its listener registered")
    assert(played.levelTimeText.text == "This level --", "level time invented a value before the reply")
    played:Refresh()
    assert(requests == 1, "refresh sent another pending request")
    playedEvents.TIME_PLAYED_MSG(played, "TIME_PLAYED_MSG", 145613, "secret")
    assert(played.levelTimeText.text == "This level --", "level time used unreadable time played")
    playedEvents.TIME_PLAYED_MSG(played, "TIME_PLAYED_MSG", 145613, 3465)
    assert(played.levelTimeText.text == "This level <3465s>", "level time used the wrong /played field")
    played.host.OnEnter(played.host)
    assert(tooltip.lines[#tooltip.lines] == "Time played this level | <3465s>", "tooltip did not show played time separately")
    -- The shown time is a sample: no wait is scheduled for it, and it moves
    -- on with the next event of the bar, row and open tooltip together.
    now = now + 1
    assert(#timers == waits and played.levelTimeText.text == "This level <3465s>"
        and tooltip.lines[#tooltip.lines] == "Time played this level | <3465s>",
        "played time scheduled a wait or moved without an event")
    playedEvents.PLAYER_XP_UPDATE(played, "PLAYER_XP_UPDATE", "player")
    assert(#timers == waits and played.levelTimeText.text == "This level <3466s>"
        and tooltip.lines[#tooltip.lines] == "Time played this level | <3466s>",
        "played time did not advance with the next XP event")
    played.host.OnLeave(played.host)
    level, xp, maximum = 22, 42, 27400
    playedEvents.PLAYER_LEVEL_UP(played, "PLAYER_LEVEL_UP", 22)
    assert(played.levelTimeText.text == "This level <0s>", "played time did not reset on level-up")
    playedEvents.TIME_PLAYED_MSG(played, "TIME_PLAYED_MSG", 145614, 3466)
    assert(played.levelTimeText.text == "This level <0s>", "old level reply overwrote the new level")
    played.config.levelTimeTextFormat = 3
    played:Refresh()
    assert(played.levelTimeText.text == "<0s>", "value-only setting ignored")
    local previewParent = Widget(UIParent)
    playedRuntime.DrawExperienceBarPreview(previewParent, played.config, { xp = 44, rested = 0 })
    assert(previewParent.suiteXPPreview.levelTimeText.text == "<3465s>" and requests == 1,
        "level time preview did not use its sample or queried the server")
    played.config.hideAtMax = false
    GameRulesUtil = { IsPlayerAtEffectiveMaxLevel = function() return true end }
    played:Refresh()
    assert(played.host:IsShown() and not played.levelTimeText:IsShown() and not playedEvents.TIME_PLAYED_MSG,
        "capped XP bar retained a stale level clock")
    GameRulesUtil = uncappedRules
    played:Refresh()
    assert(played.levelTimeText:IsShown() and requests == 1, "uncapped XP bar did not resume the known level clock")
    assert(played.host.height == played.config.height + 33, "the level time row extended beyond the framed bar")
    playedEvents.PLAYER_LEVEL_UP(played, "PLAYER_LEVEL_UP", 23)
    playedEvents.TIME_PLAYED_MSG(played, "TIME_PLAYED_MSG", 145615, 0)
    level = 23
    playedEvents.PLAYER_XP_UPDATE(played, "PLAYER_XP_UPDATE", "player")
    assert(played.levelTimeText.text == "<0s>" and requests == 1,
        "a reply before UnitLevel updated replaced the level-up clock")
    level = 24
    playedEvents.PLAYER_XP_UPDATE(played, "PLAYER_XP_UPDATE", "player")
    playedEvents.TIME_PLAYED_MSG(played, "TIME_PLAYED_MSG", 145616, 3467)
    playedEvents.PLAYER_LEVEL_UP(played, "PLAYER_LEVEL_UP", 24)
    assert(played.levelTimeText.text == "<0s>", "a cached reply suppressed the real level-up reset")
    played.config.showLevelTime = false
    played:Refresh()
    assert(not playedEvents.TIME_PLAYED_MSG and not played.levelTimeText:IsShown(),
        "turning off level time retained its listener or text")
    assert(not playedEvents.ZONE_CHANGED_NEW_AREA, "level time kept a sampling event after it was turned off")
    played:Disable()
end

-- The level time is a sample: it wakes nothing. Left alone the bar schedules
-- no wait and reads no clock, however long; the row moves on with the bar's
-- own events (experience, /played reply, zone change), when the bar is
-- shown and when the pointer enters it. A hidden
-- host keeps the baseline and the listener and is sampled when shown. The
-- shared tooltip is asked for its owner only while the pointer is on the bar.
do
    local requests, reads = 0, 0
    GetTime = function()
        reads = reads + 1
        return now
    end
    RequestTimePlayed = function() requests = requests + 1 end
    GameRulesUtil = uncappedRules
    level, xp, maximum = 30, 500, 40000
    eventFrames = true
    local idle, _, idleEvents = Load("login")
    eventFrames = false
    local host, row = idle.host, idle.levelTimeText
    local base, baseline
    local function Elapsed() return "<" .. baseline + now - base .. "s>" end
    local function Shown() return "This level " .. Elapsed() end
    local ownerChecks, isOwned = 0, tooltip.IsOwned
    tooltip.IsOwned = function(self, owner)
        ownerChecks = ownerChecks + 1
        return isOwned(self, owner)
    end
    tooltip:Hide()
    -- Every write of the row, to tell a repaint from an unchanged text.
    local writes, setText = {}, row.SetText
    row.SetText = function(self, value)
        writes[#writes + 1] = value
        return setText(self, value)
    end
    -- Time passing with no event and no input: nothing scheduled, read or written.
    local function Idle(seconds, message)
        local waits, clockReads, rowWrites, draws, text = #timers, reads, #writes, tooltip.draws, row.text
        ownerChecks = 0
        now = now + seconds
        assert(#timers == waits and reads == clockReads and #writes == rowWrites and tooltip.draws == draws
            and row.text == text and ownerChecks == 0, message)
    end
    -- One event or input: the row shows the current elapsed time from one clock read.
    local function Sampled(message)
        assert(row.text == Shown() and reads == 1, message)
    end

    local waits = #timers
    idle.config.showLevelTime = true
    idle:Refresh()
    assert(requests == 1 and idleEvents.TIME_PLAYED_MSG and #timers == waits and row.text == "This level --",
        "a level time without a baseline scheduled a wait or invented a value")
    assert(idleEvents.ZONE_CHANGED_NEW_AREA and not idleEvents.UNIT_AURA and not host.OnUpdate,
        "the level time has the wrong sampling events")
    base, baseline = now, 120
    idleEvents.TIME_PLAYED_MSG(idle, "TIME_PLAYED_MSG", 500000, 120)
    assert(row.text == Shown() and #timers == waits, "the /played reply was not shown at once or scheduled a wait")
    idle:Refresh()
    assert(#timers == waits and requests == 1, "a repaint scheduled a wait or asked /played again")

    -- Idle, visible: ten minutes pass and the bar does nothing at all.
    Idle(600, "an idle visible level time woke: a wait, a clock read, a repaint or a tooltip check")

    -- A zone change samples once without touching the unhovered tooltip.
    reads, ownerChecks, waits = 0, 0, #timers
    idleEvents.ZONE_CHANGED_NEW_AREA(idle, "ZONE_CHANGED_NEW_AREA")
    Sampled("a zone change did not show the current level time from one read")
    assert(ownerChecks == 0 and #timers == waits, "the zone change accessed the tooltip or scheduled a wait")
    Idle(45, "the level time kept running after a zone change")
    reads = 0
    idleEvents.PLAYER_XP_UPDATE(idle, "PLAYER_XP_UPDATE", "player")
    Sampled("an XP event did not show the current level time from one read")
    Idle(30, "the level time kept running after an XP event")

    -- First hover: one read repaints the row and fills the whole tooltip.
    local draws = tooltip.draws
    reads = 0
    host.OnEnter(host)
    local contents = table.concat(tooltip.lines, "\n")
    Sampled("the first hover did not repaint the row from one read")
    assert(tooltip.owner == host and tooltip.draws == draws + 1
        and tooltip.lines[#tooltip.lines] == "Time played this level | " .. Elapsed()
        and contents:find("Session XP | +0", 1, true) and contents:find("XP per hour | --", 1, true)
        and contents:find("Time to level | --", 1, true), "the hovered XP tooltip lost a line or showed an old time")
    -- Resting on the bar wakes nothing either: the tooltip keeps what it showed.
    local held = tooltip.lines[#tooltip.lines]
    Idle(90, "a hovered level time woke")
    assert(tooltip.lines[#tooltip.lines] == held, "the open tooltip changed without an event")
    -- Hovered: an event redraws the whole tooltip once, with the row's sample.
    draws, reads, ownerChecks = tooltip.draws, 0, 0
    idleEvents.ZONE_CHANGED_NEW_AREA(idle, "ZONE_CHANGED_NEW_AREA")
    contents = table.concat(tooltip.lines, "\n")
    Sampled("a hovered event did not sample once")
    assert(ownerChecks == 1 and tooltip.draws == draws + 1
        and tooltip.lines[#tooltip.lines] == "Time played this level | " .. Elapsed()
        and contents:find("Session XP | +0", 1, true) and contents:find("XP per hour | --", 1, true)
        and contents:find("Time to level | --", 1, true),
        "a hovered event did not redraw the whole tooltip once")

    -- Another owner took the shared tooltip under the pointer: it is left alone.
    local other = Widget()
    tooltip:SetOwner(other)
    tooltip:ClearLines()
    tooltip:AddLine("Other")
    tooltip:Show()
    draws = tooltip.draws
    now = now + 1
    idleEvents.ZONE_CHANGED_NEW_AREA(idle, "ZONE_CHANGED_NEW_AREA")
    assert(tooltip.owner == other and tooltip.draws == draws and #tooltip.lines == 1 and tooltip.lines[1] == "Other"
        and row.text == Shown(), "an event redrew or took a tooltip another frame owns")
    host.OnLeave(host)
    assert(tooltip.shown and tooltip.owner == other, "leaving the bar hid another frame's tooltip")
    tooltip:Hide()

    -- UIParent hidden: zone changes leave the hidden bar alone.
    local listener = idleEvents.TIME_PLAYED_MSG
    SetVisible(UIParent, false)
    assert(host:IsShown() and not host:IsVisible(), "the fixture did not hide the host through its parent")
    local frozen, rowWrites = row.text, #writes
    reads, ownerChecks, waits = 0, 0, #timers
    now = now + 1
    idleEvents.ZONE_CHANGED_NEW_AREA(idle, "ZONE_CHANGED_NEW_AREA")
    assert(row.text == frozen and #writes == rowWrites and reads == 0 and ownerChecks == 0 and #timers == waits,
        "a hidden level time was sampled by a zone change")
    assert(idleEvents.TIME_PLAYED_MSG == listener and idle.playedActive == 30 and requests == 1,
        "hiding dropped the level time's baseline or listener")
    Idle(300, "a hidden level time woke")
    now = now + 30
    reads = 0
    SetVisible(UIParent, true)
    Sampled("showing did not repaint the elapsed time at once from one read")
    assert(requests == 1, "showing asked /played again")
    Idle(60, "a shown level time started a wait")

    -- The host itself hidden under the pointer: its tooltip goes, hover ends.
    host.OnEnter(host)
    assert(tooltip.shown and tooltip.owner == host)
    host:Hide()
    assert(not tooltip.shown, "a hidden bar kept its tooltip")
    Idle(4, "a level time hidden under the pointer woke")
    reads = 0
    host:Show()
    Sampled("showing the host did not sample the level time")
    now = now + 1
    reads, ownerChecks = 0, 0
    idleEvents.ZONE_CHANGED_NEW_AREA(idle, "ZONE_CHANGED_NEW_AREA")
    Sampled("an event after the show did not sample")
    assert(ownerChecks == 0 and not tooltip.shown, "hover state survived the hide: an event asked for the tooltip owner")

    -- After gaining XP, both ETA and level time stay quiet until an event.
    xp = 600
    reads, waits = 0, #timers
    idleEvents.PLAYER_XP_UPDATE(idle, "PLAYER_XP_UPDATE", "player")
    Sampled("an XP gain did not sample the level time")
    assert(idle.rateText.text ~= "XP/h --" and idle.etaText.text ~= "To level --" and #timers == waits,
        "an XP gain left either estimate empty or started a wait")
    local idleRate, idleETA = idle.rateText.text, idle.etaText.text
    Idle(600, "XP gain started background work")
    assert(idle.rateText.text == idleRate and idle.etaText.text == idleETA,
        "the estimate changed without a trigger")
    reads = 0
    host.OnEnter(host)
    Sampled("the first hover after XP did not show the current level time")
    assert(idle.rateText.text ~= idleRate and idle.etaText.text ~= idleETA and #timers == waits,
        "hover did not refresh both estimates without a timer")
    assert(tooltip.lines[#tooltip.lines - 2] == "Time to level | " .. idle.etaText.text:sub(10),
        "bar and tooltip ETA diverged after an idle span")
    host.OnLeave(host)

    -- An ended level time (capped) gives up its events and ignores the host's show.
    idle.config.hideAtMax = true
    GameRulesUtil = { IsPlayerAtEffectiveMaxLevel = function() return true end }
    idle:Refresh()
    assert(not host:IsShown() and not idle.playedActive and not idleEvents.TIME_PLAYED_MSG
        and not idleEvents.ZONE_CHANGED_NEW_AREA, "a capped XP bar kept its level time or a sampling event")
    rowWrites, reads, waits = #writes, 0, #timers
    now = now + 1
    host:Show()
    host:Hide()
    assert(#writes == rowWrites and reads == 0 and #timers == waits, "an ended level time painted or read on show")
    -- Back below the cap: the host is shown before the level time starts again.
    now = now + 5
    GameRulesUtil = uncappedRules
    idle:Refresh()
    assert(host:IsShown() and row:IsShown() and row.text == Shown() and requests == 1
        and idleEvents.TIME_PLAYED_MSG and idleEvents.ZONE_CHANGED_NEW_AREA,
        "the level time did not resume from its baseline with its events")
    for index = rowWrites + 1, #writes do
        assert(writes[index] ~= "This level --", "showing the host painted a level time before it started")
    end

    -- A level-up while hidden: the new level's time is ready when shown.
    SetVisible(UIParent, false)
    level, xp, maximum = 31, 10, 42000
    idleEvents.PLAYER_LEVEL_UP(idle, "PLAYER_LEVEL_UP", 31)
    base, baseline = now, 0
    assert(idle.playedActive == 31 and requests == 1, "a hidden level-up lost its level or asked /played again")
    now = now + 7
    reads = 0
    SetVisible(UIParent, true)
    Sampled("the new level's time was not shown at once")
    idleEvents.TIME_PLAYED_MSG(idle, "TIME_PLAYED_MSG", 500200, 500)
    assert(row.text == Shown(), "an old level's reply replaced the level-up clock")

    -- Disabled: every event of the level time is gone and a later show samples nothing.
    idle:Disable()
    rowWrites, reads = #writes, 0
    host:Show()
    host:Hide()
    assert(#writes == rowWrites and reads == 0 and not host:IsShown() and not idleEvents.TIME_PLAYED_MSG
        and not idleEvents.ZONE_CHANGED_NEW_AREA, "a disabled XP bar kept or restarted its level time")
    row.SetText = setText
    tooltip.IsOwned = isOwned
    GetTime = function() return now end
end

local config = {}
for key, value in pairs(nextLogin.config) do config[key] = value end
local parent, sample = Widget(), { xp = 62, rested = 25 }
local timerCount, nativeCount = #timers, nativeSyncCalls
UnitXP, UnitXPMax, GetXPExhaustion = function() error("preview read live XP") end,
    function() error("preview read live XP cap") end, function() error("preview read rested XP") end
for style = 1, 3 do
    config.displayStyle = style
    local host, width, height = nextRuntime.DrawExperienceBarPreview(parent, config, sample)
    local view = parent.suiteXPPreview
    assert(host ~= nextLogin.host and width == config.width and height == config.height + 23)
    assert(host.strata == nil and nextLogin.host.strata == "MEDIUM", "menu sample must inherit menu strata")
    assert(view.fill.width == config.width * .62 and view.rested.width == config.width * .25)
    assert(view.panel:IsShown() == (style == 1) and view.detailRule:IsShown() == (style == 1))
    assert(view.levelText:IsShown() == (style ~= 2)
        and view.percentText.point[1] == (style == 2 and "CENTER" or "RIGHT")
        and view.percentText.font[2] == (style == 2 and 20 or 11), "minimal XP header does not match the centered reference")
    assert(view.segments[1].width == (style == 3 and 2 or 1), "segmented layout lost its gaps")
    assert(not host.OnEnter and not host.OnUpdate, "menu sample took live tooltip/tick ownership")
end
config.displayStyle = 1
nextRuntime.DrawExperienceBarPreview(parent, config, sample)
assert(parent.suiteXPPreview.levelText:IsShown() and parent.suiteXPPreview.percentText.font[2] == 11,
    "leaving Minimal XP did not restore the ordinary labels")
config.showSession, config.showRate, config.showETA = false, false, false
nextRuntime.DrawExperienceBarPreview(parent, config, sample)
assert(not parent.suiteXPPreview.sessionText:IsShown() and not parent.suiteXPPreview.rateText:IsShown()
    and not parent.suiteXPPreview.etaText:IsShown(), "sample ignored hidden XP details")
config.displayStyle, config.showLevelTime, config.track = 2, false, 1
local compactHost, _, compactHeight = nextRuntime.DrawExperienceBarPreview(parent, config, sample)
assert(compactHeight == config.height and compactHost.height == config.height,
    "a minimal XP strip with no extra text still reserves space below itself")
config.displayStyle = 1
config.showSession, config.showRate, config.showETA = true, true, false
nextRuntime.DrawExperienceBarPreview(parent, config, sample)
assert(parent.suiteXPPreview.sessionText.text == "Session +12k"
    and parent.suiteXPPreview.rateText.text == "XP/h 24k"
    and not parent.suiteXPPreview.etaText:IsShown(), "sample ignored XP detail choices")
sample.xp, sample.rested = 100, 100
nextRuntime.DrawExperienceBarPreview(parent, config, sample)
assert(not parent.suiteXPPreview.rested:IsShown() and not parent.suiteXPPreview.restedMarker:IsShown())
assert(#timers == timerCount and nativeSyncCalls == nativeCount, "preview scheduled work or hid Blizzard XP")
parent:SetScale(2)
nextRuntime.DrawExperienceBarPreview(parent, config, sample, { scale = .5, width = 200, height = 90 })
local view = parent.suiteXPPreview
assert(math.abs(view.edges[1].height * view.host:GetEffectiveScale() - 1) < .001,
    "first fitted paint used stale scale for pixel-sized edges")

for _,style in ipairs({1,2,3})do
 config.displayStyle=style
 config.borderSize=0
 config.showSegments=false
 nextRuntime.DrawExperienceBarPreview(parent, config, sample)
 assert(parent.suiteXPPreview.edges[1].height==0,'zero outline was not honored')
 for _,divider in ipairs(parent.suiteXPPreview.segments)do
  local x=divider.point[4]
  assert(x==x and x<math.huge and x>-math.huge,'invalid segment position')
 end
end
print('all XP display styles, zero outline, finite segment geometry: OK')

-- Another surface can stand in for the bar while it shows (the flight route timer's Timer bar, FlightTimer.lua;
-- ExperienceBarSlot.lua): the bar keeps its place, layout and events, draws nothing and takes no mouse until it is
-- handed back, and the stand-in learns when the bar shows or hides, so a hidden or disabled bar is handed back.
do
    -- The preview cases above made live XP reads raise.
    UnitXP, UnitXPMax, GetXPExhaustion = function() return xp end, function() return maximum end,
        function() return rested end
    eventFrames = true
    local view, xpRuntime = Load("login")
    eventFrames = false
    local changes = 0
    -- The stand-in places itself again; without a slot it hands the bar back (FlightTimer.lua, Place).
    xpRuntime.ExperienceSlotChanged = function()
        changes = changes + 1
        if not xpRuntime.ExperienceBarSlot() then xpRuntime.CoverExperienceBar(false) end
    end
    assert(xpRuntime.ExperienceBarSlot() == view.host, "a shown experience bar offers no slot")
    view.hovered = true
    tooltip.owner, tooltip.shown = view.host, true
    xpRuntime.CoverExperienceBar(true)
    assert(view.host.alpha == 0 and view.host.mouse == false and not tooltip.shown and not view.hovered,
        "a covered experience bar still draws, takes the mouse or keeps its tooltip")
    assert(view.host:IsShown() and xpRuntime.ExperienceBarSlot() == view.host and changes == 0,
        "covering hid the experience bar, so what is anchored to it would move")
    view:Refresh()
    assert(view.host.alpha == 0 and view.host:IsShown(), "a layout uncovered the experience bar")
    view.host:Hide()
    assert(changes == 1 and view.host.alpha == 1 and view.host.mouse == true and xpRuntime.ExperienceBarSlot() == nil,
        "a hidden experience bar was not handed back or still offers its slot")
    view.host:Show()
    assert(changes == 2 and xpRuntime.ExperienceBarSlot() == view.host, "a shown experience bar did not offer its slot")
    xpRuntime.CoverExperienceBar(true)
    view.active = false
    view:Disable()
    assert(changes == 3 and view.host.alpha == 1 and view.host.mouse == true and xpRuntime.ExperienceBarSlot() == nil,
        "disabling kept the experience bar covered or its slot offered")
end
print('experience bar slot for a stand-in: OK')


-- Exercise the opt-in through the installed bar with the production timer implementation.
do
    local sibling = root:gsub("[/\\][^/\\]+[/\\]?$", "") .. "/MidnightSimpleUnitFrames-7.0"
    local secrets = assert(loadfile(sibling .. "/tools/tests/classpower_secrets.lua"))()
    secrets.Install()
    secrets.GUARD_NAMES.falsy.Public = true
    local secret = secrets.New
    local optimizerPath = root .. "/MSUF_Suite_QualityOfLife/ExperienceOptimizer.lua"
    local stopWatching = secrets.Watch(optimizerPath, { strict = true })
    level, xp, maximum, rested = 21, 100, 1000, 10
    now = 200000
    GetTime = function() return now end
    UnitXP, UnitXPMax, GetXPExhaustion = function() return xp end, function() return maximum end,
        function() return rested end
    local afk, restricted, auraReads, itemReads, questReads = false, false, 0, 0, 0
    UnitIsAFK = function() return afk end
    UnitIsDeadOrGhost = function() return false end
    GetInventoryItemID = function() return nil end
    IsInInstance = function() return false, "none" end
    canaccesstable = function(t) return not issecretvalue(t) end
    wipe = function(t) for key in pairs(t) do t[key] = nil end end
    C_Secrets = { ShouldSpellAuraBeSecret = function() return restricted end }
    local aura = { spellId = 429959, applications = 3, expirationTime = now + 100 }
    C_UnitAuras = { GetPlayerAuraBySpellID = function(id)
        auraReads = auraReads + 1
        if id == 429959 then return aura end
    end }
    local cooldown = 0
    C_Item = {
        GetItemCount = function(id)
            itemReads = itemReads + 1
            return (id == 211527 or id == 12218) and 1 or 0
        end,
        GetItemCooldown = function() return cooldown, 0, true end,
    }
    local questReady, loaded = true, false
    local quests = {
        { isHeader = true, questID = 0 },
        { questID = 42, title = "The first quest" },
        { questID = 42, title = "Duplicate" },
        { questID = 43, title = "Pending reward" },
        { questID = 44, title = "Unfinished quest" },
        { questID = 45, title = secret("string") },
        { questID = secret("number") },
    }
    C_QuestLog = {
        GetNumQuestLogEntries = function() return #quests end,
        GetInfo = function(index) return quests[index] end,
        IsComplete = function(id) return questReady and id ~= 44 end,
    }
    HaveQuestRewardData = function(id) return id ~= 43 or loaded end
    GetQuestLogRewardXP = function(id)
        questReads = questReads + 1
        if id == 45 then return secret("number") end
        return id == 42 and 250 or 1000
    end
    local queued = {}
    C_Timer.After = function(delay, callback) queued[#queued + 1] = { at = now + delay, callback = callback } end
    local function Advance(seconds)
        local target = now + seconds
        while true do
            local earliest
            for index, timer in ipairs(queued) do
                if timer.at <= target and (not earliest or timer.at < queued[earliest].at) then earliest = index end
            end
            if not earliest then break end
            local timer = table.remove(queued, earliest)
            now = timer.at
            timer.callback()
        end
        now = target
    end
    local bar, engine, liveEvents = Load("login", true)
    assert(not bar.optimizer and not liveEvents.UNIT_AURA and #queued == 0, "default schedules optimizer work")
    bar.config.foreverOptimizer = true
    bar:Refresh()
    assert(liveEvents.UNIT_AURA and liveEvents.QUEST_LOG_UPDATE and liveEvents.PLAYER_FLAGS_CHANGED)
    Advance(1)
    assert(bar.questXPStrip:IsShown() and bar.questXPStrip.width == 100 and questReads == 2,
        "known quest rewards did not paint, or a hidden/duplicate/unfinished reward was read")
    bar.host.OnEnter(bar.host)
    local contents = table.concat(tooltip.lines, "\n")
    assert(contents:find("The first quest | 250", 1, true) and contents:find("3 / 3 stacks", 1, true)
        and contents:find("Some quest rewards are unavailable.", 1, true), "tooltip omitted optimizer details")
    assert(not engine.lastReminder, "optimizer warned during login grace")
    local savedItemReads = itemReads
    aura.spellId = secret("number")
    liveEvents.UNIT_AURA(bar, "UNIT_AURA", secret("string"))
    Advance(1)
    assert(itemReads == savedItemReads and not bar.optimizer.bonuses[2].aurasReadable
        and bar.optimizer.bonuses[1].aurasReadable, "a secret aura ID affected another bonus or caused a bag scan")
    aura.spellId = 429959
    loaded = true
    liveEvents.QUEST_DATA_LOAD_RESULT(bar, "QUEST_DATA_LOAD_RESULT", 43, true)
    Advance(1)
    assert(bar.optimizer.questXP == 1250 and bar.questXPStrip.width == 360 and bar.session.gained == 0,
        "quest rewards did not retry, extend to the cap, or stay out of earned XP")
    Advance(39)
    assert(engine.lastReminder == "XP bonus expiring soon: Cozy Sleeping Bag.", "expiration warning missed its deadline")
    local previousAuraReads = auraReads
    restricted, cooldown = secret("boolean"), secret("number")
    liveEvents.PLAYER_REGEN_DISABLED(bar, "PLAYER_REGEN_DISABLED")
    liveEvents.BAG_UPDATE_COOLDOWN(bar, "BAG_UPDATE_COOLDOWN")
    Advance(1)
    assert(auraReads == previousAuraReads and not bar.optimizer.bonuses[2].aurasReadable
        and table.concat(tooltip.lines, "\n"):find("Cozy Sleeping Bag | Owned", 1, true),
        "the tooltip queried a restricted aura or lost verified ownership")
    assert(bar.optimizer.bonuses[2].cooldownUnknown, "restricted cooldown appeared ready")
    liveEvents.ADDON_RESTRICTION_STATE_CHANGED(bar, "ADDON_RESTRICTION_STATE_CHANGED")
    restricted, cooldown = false, 0
    Advance(20)
    assert(bar.optimizer.bonuses[2].aurasReadable and not bar.optimizer.bonuses[2].cooldownUnknown
        and table.concat(tooltip.lines, "\n"):find("3 / 3 stacks", 1, true),
        "the aura or cooldown failed to recover after the restriction changed")
    xp = 200
    liveEvents.PLAYER_XP_UPDATE(bar, "PLAYER_XP_UPDATE", "player")
    assert(bar.optimizer.gained == 100 and bar.session.gained == 100 and not bar.rateText.text:find("--", 1, true))
    afk = secret("boolean")
    liveEvents.PLAYER_FLAGS_CHANGED(bar, "PLAYER_FLAGS_CHANGED", "player")
    afk = true
    Advance(1)
    local activeRate = bar.rateText.text
    assert(bar.optimizer.afk == true, "AFK state failed to recover after chat lockdown")
    xp = 350
    liveEvents.PLAYER_XP_UPDATE(bar, "PLAYER_XP_UPDATE", "player")
    Advance(80)
    assert(bar.optimizer.gained == 100 and bar.session.gained == 250 and bar.rateText.text == activeRate,
        "AFK time or gain leaked into the active rate")
    afk = false
    liveEvents.PLAYER_FLAGS_CHANGED(bar, "PLAYER_FLAGS_CHANGED", "player")
    questReady = false
    liveEvents.QUEST_TURNED_IN(bar, "QUEST_TURNED_IN", 42, 250)
    Advance(1)
    assert(not bar.questXPStrip:IsShown(), "a turned-in quest left its XP strip behind")
    local parent = Widget()
    local reads = auraReads + itemReads + questReads
    engine.DrawExperienceBarPreview(parent, bar.config, { xp = 50, rested = 15 })
    assert(parent.suiteXPPreview.questXPStrip:IsShown() and auraReads + itemReads + questReads == reads)
    liveEvents.UNIT_AURA(bar, "UNIT_AURA", "player")
    bar.config.foreverOptimizer = false
    bar:Refresh()
    Advance(360)
    assert(not bar.optimizer and not liveEvents.UNIT_AURA and not liveEvents.QUEST_LOG_UPDATE
        and not liveEvents.ADDON_RESTRICTION_STATE_CHANGED
        and not liveEvents.PLAYER_FLAGS_CHANGED and auraReads + itemReads + questReads == reads,
        "toggle off left optimizer work running")
    engine.DrawExperienceBarPreview(parent, bar.config, { xp = 50, rested = 15 })
    assert(not parent.suiteXPPreview.questXPStrip:IsShown(), "toggle off left a stale preview strip")
    bar.config.foreverOptimizer = true
    bar:Refresh()
    level, afk = secret("number"), secret("boolean")
    liveEvents.PLAYER_FLAGS_CHANGED(bar, "PLAYER_FLAGS_CHANGED", "player")
    Advance(1)
    assert(not bar.optimizer and not liveEvents.UNIT_AURA, "AFK retry survived unavailable XP")
    level, afk = 21, false
    bar:Refresh()
    GameRulesUtil = { IsPlayerAtEffectiveMaxLevel = function() return true end }
    bar:Refresh()
    assert(not bar.optimizer and not liveEvents.UNIT_AURA, "max level did not stop the optimizer")
    GameRulesUtil = uncappedRules
    bar:Refresh()
    bar:Disable()
    assert(not bar.optimizer and not liveEvents.UNIT_AURA, "disabling the bar did not stop the optimizer")

    local resumed, _, resumedEvents = Load("reload", true)
    assert(resumed.session.gained > 0, "reload fixture lost its earned session XP")
    resumed.config.foreverOptimizer = true
    resumed:Refresh()
    assert(resumed.optimizer.gained == 0 and resumed.etaText.text ~= "To level --",
        "a fresh optimizer hid the ETA despite a recovered session rate")
    resumed.host.OnEnter(resumed.host)
    assert(table.concat(tooltip.lines, "\n"):find("XP per hour | ", 1, true)
        and not table.concat(tooltip.lines, "\n"):find("Active XP per hour", 1, true),
        "the session fallback was labelled active XP per hour")
    xp = xp + 25
    resumedEvents.PLAYER_XP_UPDATE(resumed, "PLAYER_XP_UPDATE", "player")
    assert(resumed.optimizer.gained == 25 and resumed.etaText.text ~= "To level --"
        and table.concat(tooltip.lines, "\n"):find("Active XP per hour | 1500", 1, true),
        "the first fresh active XP did not replace the fallback estimate")
    resumed:Disable()
    Advance(1)

    local retail, _, retailEvents = Load("login")
    retail.config.foreverOptimizer = true
    retail:Refresh()
    assert(not retail.optimizer and not retailEvents.UNIT_AURA, "Retail started a Forever optimizer profile")
    -- Route button beside the bar: one control that starts the turn-in route and stops it.
    local routed, asked, enabled, hinted
    local live, liveEngine = Load("login", true)
    local route = { owner = {} }
    route.RouteQuests = function(ids, count)
        routed = { ids[1], ids[2], count }
        route.quests = {}
        route.questsChanged()
        return true, count
    end
    route.StopQuests = function()
        route.quests = nil
        route.questsChanged()
        return true
    end
    route.PrintStop = function() hinted = (hinted or 0) + 1 end
    liveEngine.Navigation = route
    liveEngine.Confirm = function(key, spec) asked = { key, spec.text, spec.callback } end
    liveEngine.Set = function(id, key, value) enabled = { id, key, value } route.owner = {} return true end
    live.config.foreverOptimizer = true
    UIParent.right, questReady = 2000, true
    live:Refresh()
    Advance(1)
    local button = live.routeButton
    assert(button and button:IsShown() and button.label.text == "Turn-in route (2)" and button.point[1] == "LEFT"
        and button.point[3] == "RIGHT" and button.height == 18 and button.width > 16, "ready quests showed no route button beside the bar")
    button.OnEnter(button)
    assert(tooltip.owner == button and table.concat(tooltip.lines, "\n"):find("nearest first", 1, true), "the button explains nothing")
    button.OnMouseUp(button, "RightButton")
    assert(not routed, "a right-click started a route")
    button.OnMouseUp(button, "LeftButton")
    assert(routed and routed[1] == 42 and routed[2] == 43 and routed[3] == 2
        and liveEngine.lastReminder == "Turn-in route planned. Stops: 2" and hinted == 1,
        "the button did not route the listed quests or say how to stop")
    assert(button.label.text == "Stop route" and table.concat(tooltip.lines, "\n"):find("clears its map pin", 1, true),
        "a running route kept the start button or its stale tooltip")
    button.OnLeave(button)
    button.OnMouseUp(button, "LeftButton")
    assert(not route.quests and button.label.text == "Turn-in route (2)" and liveEngine.lastReminder == "Turn-in route stopped.",
        "the button did not stop the route")
    -- Navigation switched off: one question, then on and started.
    route.owner, routed = nil, nil
    button.OnMouseUp(button, "LeftButton")
    assert(not routed and asked and asked[1] == "suite-turnin-route" and asked[2]:find("turned off", 1, true), "no offer to turn Navigation on")
    asked[3]()
    assert(enabled[1] == "navigation" and enabled[2] == "enabled" and enabled[3] == true and routed, "the offer did not enable and start")
    route.StopQuests()
    -- No room beside the bar: the button moves inside its right end.
    UIParent.right = 500
    live:Refresh()
    assert(button.point[1] == "RIGHT" and button.point[3] == "RIGHT", "a bar at the screen edge pushed the button off-screen")
    -- Nothing ready and no route: no button; a running route keeps its stop button.
    questReady = false
    live.optimizer.questJob:Request()
    Advance(1)
    assert(not button:IsShown(), "the button stayed without a ready quest")
    route.quests = {}
    route.questsChanged()
    assert(button:IsShown() and button.label.text == "Stop route", "a running route lost its stop button")
    live:Disable()
    assert(not button:IsShown() and route.questsChanged == nil, "disabling the bar left the button or its route hook")
    UIParent.right = nil
    -- The level time can coexist with Forever's optimizer on the same context.
    local shared, _, sharedEvents = Load("login", true)
    shared.config.showLevelTime = true
    shared:Refresh()
    local sample = sharedEvents.ZONE_CHANGED_NEW_AREA
    assert(sample and not sharedEvents.PLAYER_REGEN_DISABLED and not sharedEvents.PLAYER_REGEN_ENABLED,
        "level time took ownership of the optimizer's events")
    shared.config.foreverOptimizer = true
    shared:Refresh()
    assert(shared.optimizer and sharedEvents.PLAYER_REGEN_DISABLED and sharedEvents.PLAYER_REGEN_ENABLED
        and sharedEvents.ZONE_CHANGED_NEW_AREA == sample, "optimizer or level time lost its events")
    shared.config.foreverOptimizer = false
    shared:Refresh()
    assert(not shared.optimizer and not sharedEvents.PLAYER_REGEN_DISABLED
        and not sharedEvents.PLAYER_REGEN_ENABLED and sharedEvents.ZONE_CHANGED_NEW_AREA == sample,
        "stopping the optimizer removed level time events or kept combat listeners")
    shared:Disable()
    assert(not sharedEvents.ZONE_CHANGED_NEW_AREA and not sharedEvents.TIME_PLAYED_MSG,
        "disabling the bar left a level time event")
    local violations = stopWatching()
    assert(#violations == 0, table.concat(violations, "\n"))
end

print("suite_xp_bar_contract: OK")

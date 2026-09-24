local root = assert(arg[1], "repository root required")
local now, level, xp, maximum, rested = 100000, 10, 100, 1000, 300
local timers = {}

local function Widget()
    local w = { shown = true }
    function w:SetFrameStrata() end
    function w:EnableMouse() end
    function w:SetScript(key, callback) self[key] = callback end
    function w:CreateTexture() return Widget() end
    function w:CreateFontString() return Widget() end
    function w:SetPoint(...) self.point = { ... } end
    function w:ClearAllPoints() end
    function w:SetColorTexture(...) self.color = { ... } end
    function w:SetVertexColor(...) self.vertex = { ... } end
    function w:SetTexture(value) self.texture = value end
    function w:SetAllPoints() end
    function w:SetScale() end
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
C_Timer = { NewTimer = function(_, callback)
    local timer = { callback = callback }
    function timer:Cancel() self.canceled = true end
    timers[#timers + 1] = timer
    return timer
end }

local savedRoot = {}
local function Load(kind)
    local callbacks, movers = {}, {}
    local suite = { editMode = false, loginKind = kind, RootDB = savedRoot }
    suite.Suite = { instances = {}, editMode = false }
    local runtime = suite.Suite
    runtime.Public = function(value) return value ~= "secret" end
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
    assert(loadfile(root .. "/MSUF_Suite_QualityOfLife/ExperienceBar.lua"))(
        "MSUF_Suite_QualityOfLife", { NS = suite, Suite = runtime })
    local module = runtime.instances.xpBar
    module.active = true
    module.config = { enabled = true, look = 1, width = 400, height = 18, scale = 100,
        showSegments = true, showRested = true, showSession = true, showRate = true, showETA = true,
        hideAtMax = true, point = 8, x = 0, y = 148 }
    module.context = { Event = function(_, name, callback, allowCombat)
        assert(allowCombat and not callbacks[name])
        callbacks[name] = callback
    end }
    module:Enable()
    return module, runtime, callbacks, movers
end

local module, runtime, events, movers = Load("login")
assert(module.session.gained == 0 and module.host:IsShown())
assert(module.restedMarker:IsShown() and module.restedMarker.point[4] == 160
    and module.restedMarker.height == 22,
    "rested marker must sit at current XP plus rested XP")
assert(module.fill.texture:find("MSUF_Lucent_v2.tga", 1, true)
    and module.rested.texture == module.fill.texture, "both XP fills must use MSUF bar art")
assert(module.levelText.font[1]:find("Expressway SemiBold.ttf", 1, true)
    and module.details.font[1] == module.levelText.font[1], "XP texts must use the MSUF font")
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
assert(module.fill.texture:find("MSUF_Lucent_v2.tga", 1, true) and module.levelText.text:find("100 / 1.0k", 1, true),
    "switching styles must keep the MSUF texture and XP values")
assert(module.restedMarker.color[3] > module.restedMarker.color[1],
    "Forever style must keep a distinct rested marker")
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
assert(module.levelText.text:find("100 / 1.0k", 1, true))

xp = 250
events.PLAYER_XP_UPDATE(module, "PLAYER_XP_UPDATE", "player")
assert(module.session.gained == 150 and savedRoot.suiteXP["Player-test"].gained == 150)
assert(module.details.text:find("Session +150", 1, true))
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
assert(module.details.text:find("To level", 1, true))

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
print("suite_xp_bar_contract: OK")

-- Keystone controls: native actions, lifecycle, restrictions and owned skin.
local root = assert(arg[1], "repository root required")
local runtimePath = arg[2] or root .. "/MSUF_Suite_QualityOfLife/KeystoneReadyCheck.lua"
local Support = dofile(root .. "/tools/tests/suite_test_support.lua")
local checks = 0
local function Check(value, message)
    assert(value, message)
    checks = checks + 1
end

MSUF_NS, SlashCmdList = {}, {}
WOW_PROJECT_ID, WOW_PROJECT_MAINLINE = 1, 1
InCombatLockdown = function() return false end
local suite = Support.Load(root, "MSUF_Suite", {}, "Core/Suite.lua")
local spec = suite.SuiteCatalog.keystoneReadyCheck
Check(spec and spec.optIn and spec.defaultEnabled == false, "keystone controls must be opt-in")
Check(suite.Defaults.suite.modules.keystoneReadyCheck.enabled == false, "fresh profiles must keep keystone controls off")
Check(spec.rules.countdownSeconds.default == 10 and spec.rules.shortCountdownSeconds.default == 5,
    "normal and short countdown defaults")
Check(spec.rules.countdownSeconds.min == 1 and spec.rules.countdownSeconds.max == 60, "bounded countdown")
local page = { Tr = function(value) return value end, Suite = { Client = { isForever = false } } }
assert(loadfile(root .. "/MSUF_Suite_Options/Pages/QualityOfLifeHelp.lua"))("options", page)
local help = page.QoLHelpText("keystone_preparation")
Check(help and help:find("right%-click") and help:find("Blizzard's Start button", 1, true), "help describes both clicks and manual start")

local methods = {}
function methods:SetSize(w, h) self.width, self.height = w, h end
function methods:SetPoint(...) self.point = { ... } end
function methods:SetScript(event, fn) self.scripts[event] = fn end
function methods:HookScript(event, fn)
    self.hooks[event] = self.hooks[event] or {}
    table.insert(self.hooks[event], fn)
end
function methods:IsShown() return self.shown and (not self.parent or self.parent:IsShown()) end
function methods:Show() self.shown = true end
function methods:Hide() self.shown = false end
function methods:SetEnabled(value) self.enabled = value end
function methods:SetText(value) self.text = value end
function methods:RegisterForClicks(...) self.clicks = { ... } end
function methods:GetFontString() return self.label end
function methods:SetAllPoints(frame) self.allPoints = frame end
function methods:SetColorTexture(...) self.color = { ... } end
local function Frame(parent)
    return setmetatable({ parent = parent, shown = true, scripts = {}, hooks = {}, label = {} }, { __index = methods })
end

local function Setup(forever, absent)
    local state = { now = 100, group = true, leader = true, assistant = false, countdowns = {}, ready = 0,
        events = {}, skins = {}, frames = {}, messages = {}, restricted = false, combat = false, success = true }
    local secret = setmetatable({}, { __tostring = function() error("secret formatted") end })
    state.secret = secret
    local function Public(value) return not rawequal(value, secret) end
    local function Finite(value)
        return Public(value) and type(value) == "number" and value == value and math.abs(value) < math.huge
    end
    state.native = Frame()
    setmetatable(state.native, { __index = methods, __newindex = function() error("write to native frame") end })
    ChallengesKeystoneFrame = state.native
    if absent then ChallengesKeystoneFrame = nil end
    IsInGroup = function() return state.group end
    UnitIsGroupLeader = function() return state.leader end
    UnitIsGroupAssistant = function() return state.assistant end
    GetTime = function() return state.now end
    GetReadyCheckTimeLeft = function() return state.readyRemaining or 0 end
    C_ChallengeMode = { StartChallengeMode = function() error("keystone must be started manually") end }
    C_PartyInfo = {
        DoCountdown = function(seconds)
            state.countdowns[#state.countdowns + 1] = seconds
            state:Emit(seconds == 0 and "CANCEL_PLAYER_COUNTDOWN" or "START_PLAYER_COUNTDOWN")
            return state.success
        end,
        DoReadyCheck = function() state.ready = state.ready + 1 end,
    }
    local skin = {
        SkinFrame = function(_, frame) state.skins[frame] = "frame" end,
        SkinButton = function(_, frame) state.skins[frame] = "button" end,
    }
    local S = {
        Public = Public, Finite = Finite, Text = function(text) return text end,
        GlobalFontPath = function() return "SuiteFont" end, SetStyledFont = function() end,
        Print = function(text) state.messages[#state.messages + 1] = text end,
        CreateFrame = function(_, _, parent)
            local frame = Frame(parent)
            state.frames[#state.frames + 1] = frame
            return frame
        end,
        CreateTexture = function(parent) return Frame(parent) end,
        QoLRestrictedCall = function(fn, ...)
            if state.refused then return false end
            fn(...)
            return true
        end,
        Install = function(id, module) state.id, state.module = id, module end,
    }
    local NS = {
        Client = { isForever = forever },
        InCombat = function(event) return event == "PLAYER_REGEN_DISABLED" or state.combat end,
        GroupActionsRestricted = function() return state.restricted end,
        RestrictedNotice = function() return "restricted" end,
    }
    assert(loadfile(runtimePath))("qol", { NS = NS, Suite = S })
    if forever then return state end
    local module = assert(state.module)
    module.config = { countdownSeconds = 10, shortCountdownSeconds = 5 }
    module.active = true
    module.context = {
        Event = function(_, event, fn) state.events[event] = fn end,
        RemoveEvent = function(_, event) state.events[event] = nil end,
        Skin = function() return skin end,
    }
    function state:Emit(event)
        if event == "READY_CHECK" then self.readyRemaining = 30 end
        if event == "READY_CHECK_FINISHED" then self.readyRemaining = 0 end
        if self.events[event] then self.events[event](module, event) end
    end
    function state:Visible(show)
        self.native.shown = show
        for _, fn in ipairs(self.native.hooks[show and "OnShow" or "OnHide"] or {}) do fn() end
    end
    function state:Click(which, button) module[which].scripts.OnClick(module[which], button or "LeftButton") end
    function state:Tick(seconds)
        self.now = self.now + seconds
        local tick = module.panel.scripts.OnUpdate
        if tick then tick(module.panel, seconds) end
    end
    module:Enable()
    return state
end

local state = Setup(false)
local module = state.module
Check(state.id == "keystoneReadyCheck" and module.panel.parent == state.native, "owned controls follow native window")
Check(module.panel.point[1] == "TOP" and module.panel.point[3] == "BOTTOM", "controls stay clear of native Start button")
Check(state.skins[module.panel] == "frame" and state.skins[module.ready] == "button"
    and state.skins[module.pull] == "button", "all controls use Suite skin")
Check(module.panel.scripts.OnUpdate == nil, "no idle polling")
state:Click("ready")
Check(state.ready == 1, "ready click uses native ready check")
state:Emit("READY_CHECK")
state:Click("ready")
Check(state.ready == 1 and not module.ready.enabled, "active ready check is not sent twice")
state:Emit("READY_CHECK_FINISHED")
Check(module.ready.enabled and module.ready.text == "Ready check", "ready check completion restores button")
state:Click("pull")
Check(state.countdowns[1] == 10 and module.panel.scripts.OnUpdate, "normal click starts native countdown")
state:Tick(2.1)
Check(module.pull.text == "Cancel countdown (8)", "countdown uses elapsed time, not number of ticks")
state:Click("pull")
Check(state.countdowns[2] == 0 and not module.panel.scripts.OnUpdate, "second click cancels and stops updates")
state:Click("pull", "RightButton")
Check(state.countdowns[3] == 5, "right click uses short countdown")
state:Tick(6)
Check(not module.endsAt and not module.panel.scripts.OnUpdate, "finished countdown releases update script")
Check(module.pull.text == "Countdown (10 s)", "completion restores configured label")
state:Click("pull")
state:Emit("START_PLAYER_COUNTDOWN")
local calls = #state.countdowns
Check(not module.endsAt and not module.panel.scripts.OnUpdate, "another countdown supersedes our local timer")
state:Visible(false)
Check(#state.countdowns == calls, "closing must not cancel someone else's countdown")
state:Visible(true)
state:Click("pull")
state:Emit("CANCEL_PLAYER_COUNTDOWN")
Check(not module.endsAt, "external cancellation clears local timer")
state:Click("pull")
state:Visible(false)
Check(state.countdowns[#state.countdowns] == 0 and not module.panel:IsShown(), "closing cancels own countdown")
Check(next(state.events) == nil and not module.panel.scripts.OnUpdate, "hidden window has no events or timers")
state:Visible(true)
state:Click("pull")
calls = #state.countdowns
state:Emit("PLAYER_REGEN_DISABLED")
Check(#state.countdowns == calls and not module.endsAt and not module.pull.enabled, "combat edge does not send cancellation")
state:Emit("PLAYER_REGEN_ENABLED")
Check(module.pull.enabled, "combat end restores controls")
state.restricted = true
state:Click("pull")
state:Click("ready")
Check(#state.countdowns == calls and state.ready == 1, "restrictions are checked again on click")
state.restricted = false
state.leader, state.assistant = false, true
state:Emit("PARTY_LEADER_CHANGED")
Check(module.pull.enabled, "group assistant may use controls")
state:Click("pull")
state.leader, state.assistant = false, false
calls = #state.countdowns
state:Emit("GROUP_ROSTER_UPDATE")
Check(not module.endsAt and not module.pull.enabled and #state.countdowns == calls, "losing permission stops local countdown safely")
state:Click("ready")
Check(state.ready == 1, "non-leader cannot bypass disabled button")
state.group = state.secret
state:Emit("GROUP_ROSTER_UPDATE")
Check(not module.pull.enabled, "secret group state is not interpreted as permission")
state.group, state.leader = true, true
state.success = false
state:Click("pull")
Check(not module.endsAt and not module.panel.scripts.OnUpdate, "failed native countdown does not display a running timer")
state.success, state.refused = true, true
state:Click("pull")
Check(not module.endsAt, "blocked action does not display a timer")
state.refused = false
module.config.countdownSeconds = state.secret
calls = #state.countdowns
state:Click("pull")
Check(#state.countdowns == calls, "secret duration cannot reach arithmetic or native action")
module.config.countdownSeconds = 10
state:Click("pull")
state:Emit("CHALLENGE_MODE_START")
Check(not module.panel:IsShown() and next(state.events) == nil, "key start releases controls")
state:Visible(false)
state:Visible(true)
state:Click("pull")
module.active = false
module:Disable()
Check(not module.panel:IsShown() and next(state.events) == nil and not module.panel.scripts.OnUpdate, "disable releases all work")
state:Visible(true)
Check(not module.panel:IsShown(), "retained native hook stays inert when disabled")
module.active = true
module:Enable()
Check(#state.native.hooks.OnShow == 1 and #state.native.hooks.OnHide == 1, "re-enable does not duplicate hooks")
Check(module.panel:IsShown(), "re-enable while open restores controls")
module:Refresh()
Check(module.panel:IsShown(), "profile refresh keeps visible controls")
state:Visible(false)
state.readyRemaining = 20
state:Visible(true)
Check(not module.ready.enabled, "opening during an existing ready check keeps its button disabled")
state:Visible(false)
state.combat = true
state:Visible(true)
Check(not module.panel:IsShown() and state.events.PLAYER_REGEN_ENABLED, "combat open waits without creating work")
state.combat = false
state:Emit("PLAYER_REGEN_ENABLED")
Check(module.panel:IsShown(), "combat end attaches controls to the still-open native window")
local lazy = Setup(false, true)
Check(not lazy.module.panel and lazy.events.ADDON_LOADED, "missing load-on-demand window is deferred")
ChallengesKeystoneFrame = lazy.native
lazy:Emit("ADDON_LOADED")
Check(lazy.module.panel and not lazy.events.ADDON_LOADED, "load-on-demand window is attached once")
local forever = Setup(true)
Check(not forever.module and #forever.frames == 0, "Forever does not install Retail keystone controls")
print("keystone ready check: " .. checks .. " checks passed")

local root = assert(arg[1], "repository root required")
local clock, combat, inRaid = 100, false, false
local timers, movers = {}, {}
local function Widget(parent)
    local w = { parent = parent, shown = true }
    function w:CreateTexture() return Widget(self) end
    function w:CreateFontString() return Widget(self) end
    function w:SetPoint(...) self.point = { ... } end
    function w:ClearAllPoints() end
    function w:SetAllPoints() end
    function w:SetSize(width, height) self.width, self.height = width, height end
    function w:SetWidth(width) self.width = width end
    function w:SetHeight(height) self.height = height end
    function w:SetScale(scale) self.scale = scale end
    function w:SetFrameStrata() end
    function w:EnableMouse() end
    function w:RegisterForClicks() end
    function w:SetScript(script, callback) self[script] = callback end
    function w:SetColorTexture(...) self.color = { ... } end
    function w:SetText(text) self.text = text end
    function w:SetTextColor(...) self.textColor = { ... } end
    function w:SetJustifyH() end
    function w:SetWordWrap() end
    function w:SetFont() end
    function w:Show() self.shown = true end
    function w:Hide() self.shown = false end
    function w:IsVisible() return self.shown and (not self.parent or self.parent:IsVisible()) end
    return w
end
UIParent = Widget()
CreateFrame = function(_, _, parent) return Widget(parent) end
GetTime = function() return clock end
IsInInstance = function() return inRaid, inRaid and "raid" or "none" end
GetDifficultyInfo = function(id) return id == 16 and "Mythic" or "Normal" end
C_Timer = { After = function(_, callback) timers[#timers + 1] = callback end }
local info = { mapChallengeModeID = 42, level = 15, time = 1422000,
    onTime = true, keystoneUpgradeLevels = 2,
    oldOverallDungeonScore = 1000, newOverallDungeonScore = 1018 }
C_ChallengeMode = {
    GetChallengeCompletionInfo = function() return info end,
    GetMapUIInfo = function() return "Test Dungeon", nil, 1800 end,
    GetDeathCount = function() return 2, 10 end,
}
local NS = { AnchorPoints = { [5] = "CENTER" }, Client = { isForever = false },
    IsCombatLocked = function() return combat end }
local S = { instances = {}, editMode = false }
NS.Suite = S
local secret = {}
S.Public = function(value) return value ~= secret end
S.Finite = function(value) return S.Public(value) and type(value) == "number"
    and value == value and value > -math.huge and value < math.huge end
S.PublicText = function(value) return S.Public(value) and type(value) == "string"
    and value ~= "" and value or nil end
S.Text = function(value) return value end
S.CreateFrame = CreateFrame
S.CreateTexture = function(parent) return parent:CreateTexture() end
S.CreateFontString = function(parent) return parent:CreateFontString() end
S.SetStyledFont = function(widget, _, size) widget.size = size end
S.ResolveFont = function() return nil end
S.GlobalFontPath = function() return "test.ttf" end
S.RGB = function() return .2, .3, .4 end
S.RegisterOwnedMover = function(id, element, spec) movers[id] = { element = element, spec = spec } end
S.Install = function(id, module) S.instances[id] = module end
local state = {}
S.ModuleState = function() return state end
S.Config = function() return S.instances.runSummary.config end
S.Set = function(_, key, value) S.Config()[key] = value; return true end
local private = { NS = NS, Suite = S }
assert(loadfile(root .. "/MSUF_Suite_Modules/RunSummary.lua"))("MSUF_Suite_Modules", private)
local summary = S.instances.runSummary
summary.active = true
summary.config = { showMythicPlus = true, showRaid = true, showDuration = true,
    showTimer = true, showDeaths = true, showPenalty = true, showUpgrades = true,
    showScore = true, showRecord = true, showBest = true, showGroupSize = true,
    showKills = true, autoHide = 0, colorStyle = 1,
    backgroundOpacity = 90, width = 390, scale = 100, point = 5, x = 0, y = 80 }
local context = { events = {} }
function context:Event(event, callback) self.events[event] = callback end
function context:RemoveEvent(event) self.events[event] = nil end
function context:Skin() return nil end
summary.context = context
summary:Enable()
assert(movers.runSummary.element == "summary" and not summary.host:IsVisible())
assert(movers.runSummary.spec.quickPosition and movers.runSummary.spec.getFrame() == summary.host)
assert(movers.runSummary.spec.extraControls[1].set(420)
    and summary.config.width == 420, "Edit Mode width must update the card setting")
summary.config.width = 390
summary:Preview("raid")
assert(summary.host:IsVisible() and summary.title.text == "RAID BOSS DEFEATED" and state.last == nil)
summary:Close()
local function Event(event, ...)
    assert(context.events[event], "missing event " .. event)
    context.events[event](summary, event, ...)
end
Event("CHALLENGE_MODE_START")
Event("CHALLENGE_MODE_COMPLETED")
assert(summary.host:IsVisible() and state.last.kind == "mythic")
assert(summary.subtitle.text == "Test Dungeon  +15" and summary.rows[1].value.text == "23:42")
assert(summary.rows[2].value.text:find("In time", 1, true))
assert(summary.rows[6].value.text == "+18")
local serial = summary.serial
info.newOverallDungeonScore = 1020
Event("CHALLENGE_MODE_COMPLETED_REWARDS")
assert(summary.serial == serial and summary.rows[6].value.text == "+20",
    "reward update should refresh the same result, not open a second card")
summary:Close()
summary.config.showDeaths = false
summary.config.showPenalty = false
summary:ShowLast()
assert(summary.host:IsVisible() and summary.rows[3].label.text == "Keystone",
    "metric switches should change the saved result presentation")
summary:Close()
combat = true
Event("CHALLENGE_MODE_START")
Event("CHALLENGE_MODE_COMPLETED")
assert(summary.pending and not summary.host:IsVisible(), "completion in combat must defer the card")
Event("PLAYER_REGEN_DISABLED")
assert(summary.pending, "combat restart must retain the pending result")
combat = false
Event("PLAYER_REGEN_ENABLED")
assert(summary.host:IsVisible() and not summary.pending)
summary:Close()
info.newOverallDungeonScore = secret
Event("CHALLENGE_MODE_START")
Event("CHALLENGE_MODE_COMPLETED")
assert(summary.host:IsVisible() and state.last.scoreDelta == nil,
    "restricted rating must be omitted without leaking or arithmetic")
summary:Close()
info.newOverallDungeonScore = 1020
inRaid = true
clock = 200
Event("ENCOUNTER_START", 9001, "Test Boss", 16, 20)
clock = 220
Event("ENCOUNTER_END", 9001, "Test Boss", 16, 20, 0)
assert(not summary.host:IsVisible() and not state.raidRecords,
    "a wipe must not create a kill result")
clock = 230
Event("ENCOUNTER_START", 9001, "Test Boss", 16, 20)
clock = 350
Event("ENCOUNTER_END", 9001, "Test Boss", 16, 20, 1)
assert(summary.host:IsVisible() and state.last.kind == "raid")
assert(state.raidRecords["9001:16"].best == 120 and summary.rows[2].value.text:find("New best", 1, true))
assert(summary.rows[3].value.text == "20" and summary.rows[4].value.text == "1")
summary.config.showKills = false
summary:Refresh()
assert(not summary.rows[4].label.shown, "raid kill count switch must remove its row")
summary.config.showKills = true
serial = summary.serial
Event("ENCOUNTER_END", 9001, "Test Boss", 16, 20, 1)
assert(summary.serial == serial and state.raidRecords["9001:16"].kills == 1,
    "duplicate encounter end must count once")
summary.config.autoHide = 5
clock = 400
Event("ENCOUNTER_START", 9001, "Test Boss", 16, 20)
clock = 550
Event("ENCOUNTER_END", 9001, "Test Boss", 16, 20, 1)
assert(#timers == 1 and state.raidRecords["9001:16"].best == 120)
timers[1]()
assert(not summary.host:IsVisible(), "auto-hide must close the card")
summary.config.showRaid = false
summary:Refresh()
assert(not context.events.ENCOUNTER_END)
summary:Disable()
-- Classic 6.5 / Forever loads the same Suite module through its Mainline TOC.
-- It has raid encounters but the Suite must never subscribe to Mythic+ there.
NS.Client.isForever = true
summary.config.showRaid, summary.config.showMythicPlus = true, nil
summary.context = { events = {} }
summary.context.Event = context.Event
summary.context.RemoveEvent = context.RemoveEvent
summary.context.Skin = context.Skin
summary:Enable()
assert(summary.context.events.ENCOUNTER_END and not summary.context.events.CHALLENGE_MODE_COMPLETED)
summary:Close()
clock = 600
summary.context.events.ENCOUNTER_START(summary, "ENCOUNTER_START", 9002, "Forever Boss", 16, 20)
clock = 660
summary.context.events.ENCOUNTER_END(summary, "ENCOUNTER_END", 9002, "Forever Boss", 16, 20, 1)
assert(summary.host:IsVisible() and state.last.kind == "raid" and state.last.time == 60)
summary:Disable()
print("Run summary completion, reward update, combat delay, raid kill, wipe, records and settings: OK")

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
GetServerTime = function() return 100000 + clock end
SlashCmdList = {}
UnitGUID = function() return nil end
IsInInstance = function() return inRaid, inRaid and "raid" or "none" end
GetDifficultyInfo = function(id) return id == 16 and "Mythic" or "Normal" end
-- Blizzard's localized abbreviation (C API on Retail and Forever).
AbbreviateLargeNumbers = function(value) return "abbr:" .. value end
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
    IsCombatLocked = function() return combat end, Dispatch = function(callback, ...) return callback(...) end }
local S = { instances = {}, editMode = false }
NS.Suite = S
local secret = {}
NS.Public = function(value) return value ~= secret end
NS.Finite = function(value) return NS.Public(value) and type(value) == "number"
    and value == value and value > -math.huge and value < math.huge end
NS.Number = NS.Finite
NS.RGB = function() return .2, .3, .4 end
NS.ResolveFont = function() return nil end
NS.GlobalFontPath = function() return "test.ttf" end
S.Public, S.Finite = NS.Public, NS.Finite
S.PublicText = function(value) return S.Public(value) and type(value) == "string"
    and value ~= "" and value or nil end
S.Text = function(value) return value end
-- The shared module helpers (S.ClockText, S.PublicField) come from the real file.
MSUFSuite = NS
assert(loadfile(root .. "/MSUF_Suite_Modules/Surfaces.lua"))("MSUF_Suite_Modules", {})
S.CreateFrame = CreateFrame
S.CreateTexture = function(parent) return parent:CreateTexture() end
S.CreateFontString = function(parent) return parent:CreateFontString() end
S.SetStyledFont = function(widget, _, size) widget.size = size end
S.RegisterOwnedMover = function(id, element, spec) movers[id] = { element = element, spec = spec } end
S.Install = function(id, module) S.instances[id] = module end
-- Records belong to the character (MSUF_Suite/Core/CharacterData.lua).
local state = {}
S.CharacterData = function(owner) assert(owner == "runSummary"); return state end
S.Config = function() return S.instances.runSummary.config end
S.Set = function(_, key, value) S.Config()[key] = value; return true end
local private = { NS = NS, Suite = S }
for _, file in ipairs({ "RunSummaryParty", "RunSummary" }) do
    assert(loadfile(root .. "/MSUF_Suite_Modules/" .. file .. ".lua"))("MSUF_Suite_Modules", private)
end
local summary = S.instances.runSummary
summary.active = true
summary.config = { showMythicPlus = true, showRaid = true, showDuration = true,
    showTimer = true, showDeaths = true, showPenalty = true, showUpgrades = true,
    showScore = true, showRecord = true, showBest = true, showGroupSize = true,
    showKills = true, autoHide = 0, colorStyle = 1,
    backgroundOpacity = 90, width = 390, scale = 100, point = 5, x = 0, y = 80 }
local TimerContext = dofile(root .. "/tools/tests/suite_test_support.lua").ModuleTimers(root, S, NS)
local context = TimerContext("runSummary", summary, { events = {} })
function context:Event(event, callback) self.events[event] = callback end
function context:RemoveEvent(event) self.events[event] = nil end
function context:Skin() return nil end
summary.context = context
summary:Enable()
-- Counts the cards shown: a refresh repaints, it does not show a second card.
local cards, showHost = 0, summary.host.Show
summary.host.Show = function(self, ...)
    cards = cards + 1
    return showHost(self, ...)
end
assert(movers.runSummary.element == "summary" and not summary.host:IsVisible())
assert(movers.runSummary.spec.quickPosition and movers.runSummary.spec.getFrame() == summary.host)
assert(movers.runSummary.spec.extraControls[1].set(420)
    and summary.config.width == 420, "Edit Mode width must update the card setting")
-- The run history has one command of its own; /ov belongs to another addon.
assert(SLASH_MSUFSUITERUNS1 == "/msufruns" and SLASH_MSUFSUITERUNS2 == nil and SlashCmdList.MSUFSUITERUNS,
    "the run history command took a second alias")
summary.config.width = 390
summary:Preview("raid")
assert(summary.host:IsVisible() and summary.title.text == "RAID BOSS DEFEATED" and state.lastKind == nil)
summary:Close()
summary.config.partyDetails = 4
summary:Preview("mythic")
assert(summary.current.players and #summary.current.players == 5, "preview lacks the player table")
assert(summary.playerRows[1].name.text == "Player 1" and summary.playerHeaders.score.shown
    and summary.playerHeaders.loot.shown and summary.playerRows[1].damage.text:find("abbr:", 1, true),
    "preview must render the party table through the real painter")
assert(state.lastKind == nil and state.history == nil, "preview wrote sample rows to run history")
-- The party table grows by detail level.
summary.config.partyDetails = 2
summary:Refresh()
assert(summary.playerHeaders.score.shown and summary.playerHeaders.build.shown
    and not summary.playerHeaders.damage.shown and not summary.playerHeaders.loot.shown,
    "characters and scores showed combat figures or loot")
summary.config.partyDetails = 3
summary:Refresh()
assert(summary.playerHeaders.damage.shown and summary.playerHeaders.deaths.shown and not summary.playerHeaders.loot.shown,
    "combat figures level showed loot or lacked figures")
summary.config.partyDetails = 1
summary:Refresh()
assert(not summary.playerRows[1].name.shown, "disabling the party table left sample rows visible")
summary.config.partyDetails = 4
summary:Preview("raid")
assert(not summary.playerRows[1].name.shown, "raid preview retained Mythic+ sample rows")
summary:Close()
local function Event(event, ...)
    assert(context.events[event], "missing event " .. event)
    context.events[event](summary, event, ...)
end
Event("CHALLENGE_MODE_START")
Event("CHALLENGE_MODE_COMPLETED")
assert(summary.host:IsVisible() and state.lastKind == "mythic" and state.history[1].mapID == 42)
assert(summary.subtitle.text == "Test Dungeon  +15" and summary.rows[1].value.text == "23:42")
assert(summary.rows[2].value.text:find("In time", 1, true))
assert(summary.rows[5].value.text == "+2 upgrades" and summary.rows[6].value.text == "+18")
local serial = cards
info.newOverallDungeonScore = 1020
Event("CHALLENGE_MODE_COMPLETED_REWARDS")
assert(cards == serial and summary.rows[6].value.text == "+20",
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
assert(summary.host:IsVisible() and state.history[1].scoreDelta == nil,
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
assert(summary.host:IsVisible() and state.lastKind == "raid" and state.lastRaid.kind == "raid")
assert(state.raidRecords["9001:16"].best == 120 and summary.rows[2].value.text:find("New best", 1, true))
assert(summary.rows[3].value.text == "20" and summary.rows[4].value.text == "1")
summary.config.showKills = false
summary:Refresh()
assert(not summary.rows[4].label.shown, "raid kill count switch must remove its row")
summary.config.showKills = true
serial = cards
Event("ENCOUNTER_END", 9001, "Test Boss", 16, 20, 1)
assert(cards == serial and state.raidRecords["9001:16"].kills == 1,
    "duplicate encounter end must count once")
summary.config.autoHide = 5
clock = 400
Event("ENCOUNTER_START", 9001, "Test Boss", 16, 20)
clock = 550
Event("ENCOUNTER_END", 9001, "Test Boss", 16, 20, 1)
assert(#timers == 1 and state.raidRecords["9001:16"].best == 120)
clock = 555
timers[1]()
timers = {}
assert(not summary.host:IsVisible(), "auto-hide must close the card")
summary.config.showRaid = false
summary:Refresh()
assert(not context.events.ENCOUNTER_END)
summary:Disable()
-- Bounded, deduplicated history; navigation/deletion and loot deferral.
summary.config.keepRuns, summary.config.cardTiming = 2, 2
summary.config.autoHide = 0
summary.active = true
summary:Enable()
UnitGUID = function(unit) return unit == "player" and "Player-1" or nil end
UnitFullName = function() return "Player" end
-- C_SpecializationInfo only; the global functions are deprecation shims.
C_SpecializationInfo = { GetInspectSpecialization = function() return 62 end,
    GetSpecialization = function() return 1 end, GetSpecializationInfo = function() return 62 end }
GetSpecializationInfoByID = function() return 62, "Arcane" end
C_PaperDollInfo = { GetInspectItemLevel = function() return 220 end }
GetAverageItemLevel = function() return 220, 219 end
local score = 1100
C_PlayerInfo = { GetPlayerMythicPlusRatingSummary = function() return { currentSeasonScore = score } end }
local damage, meterReadable = 1000, true
-- The native overall meter reads nothing in combat or while a value is secret.
S.ReadDamageMeterTotals = function()
    if not meterReadable then return nil end
    return { damage = { ["Player-1"] = damage }, damageTaken = { ["Player-1"] = damage / 2 },
        interrupts = { ["Player-1"] = damage / 100 }, deaths = { ["Player-1"] = 0 } }
end
info.members = { { memberGUID = "Player-1", name = "Player" } }
Event("CHALLENGE_MODE_START")
damage, score = 3000, 1120
Event("CHALLENGE_MODE_COMPLETED")
assert(summary.lootPending and not summary.host:IsVisible())
assert(#state.history == 2 and state.history[1].players[1].damage == 2000
    and state.history[1].players[1].scoreDelta == 20 and state.history[1].players[1].ilvl == 219
    and state.history[1].players[1].spec == "Arcane")
local savedID = state.history[1].historyID
Event("CHALLENGE_MODE_COMPLETED_REWARDS")
assert(#state.history == 2 and state.history[1].historyID == savedID, "reward event duplicated history")
Event("LOOT_CLOSED")
assert(summary.host:IsVisible() and summary.playerRows[1].name.text == "Player"
    and summary.playerRows[1].interrupts.text == "20" and summary.playerRows[1].score.text == "1120 (+20)"
    and summary.playerRows[1].damage.text == "abbr:2000  (abbr:1/s)", "party figures were not formatted")
local function Loot(message, guid, line)
    Event("CHAT_MSG_LOOT", message, "Player", nil, nil, nil, nil, nil, nil, nil, nil, line, guid)
end
local link = "|cff00ff00|Hitem:123:0:0|h[Test loot]|h|r"
Loot(link, "Other-player", 1)
Loot(link, secret, 2)
Loot(secret, "Player-1", 3)
assert(not state.history[1].players[1].loot)
Loot(link, "Player-1", 4)
Loot(link, "Player-1", 4)
assert(#state.history[1].players[1].loot == 1 and summary.playerRows[1].loot.text == link
    and state.history[1].players[1].lootItems == nil, "loot was stored twice or not shown")
Event("CHALLENGE_MODE_COMPLETED_REWARDS")
assert(#state.history[1].players[1].loot == 1, "reward refresh lost attributed loot")
Event("PLAYER_ENTERING_WORLD")
Loot(link, "Player-1", 5)
assert(#state.history[1].players[1].loot == 1, "world transition kept loot ownership")
summary:Browse(-1)
assert(summary.current.historyID ~= savedID, "previous run did not navigate history")
summary:Browse(1)
assert(summary.current.historyID == savedID)
-- Deleting a run takes a second click on the armed button.
local delete = summary.historyButtons[3]
delete.OnClick(delete)
local firstWindow = timers[#timers]
assert(#state.history == 2 and delete.label.text == "Click again to delete", "one click deleted a run")
delete.OnClick(delete)
assert(#state.history == 1 and state.history[1].historyID ~= savedID and delete.label.text == "Delete run")
-- A new arm keeps its whole window: the end of an earlier, used one must
-- not disarm it.
delete.OnClick(delete)
clock = clock + 4
firstWindow()
assert(#state.history == 1 and delete.label.text == "Click again to delete",
    "the window of an earlier arm disarmed a newer one")
timers[#timers]()
assert(delete.label.text == "Delete run" and not delete.armed, "the delete arm did not end after its window")
summary:Close()
Event("CHALLENGE_MODE_START")
Event("DAMAGE_METER_RESET")
damage = 4000
Event("CHALLENGE_MODE_COMPLETED")
assert(state.history[1].players[1].damage == nil, "meter reset produced fabricated full-run totals")
assert(summary.lootPending and not summary.host:IsVisible())
local retainedRun = state.history[1].historyID
summary.pending = { kind = "mythic" }
Event("PLAYER_ENTERING_WORLD")
assert(not summary.lootPending and not summary.pending and not summary.host:IsVisible(),
    "world entry without dungeon loot must discard automatic openings, not display the result")
Event("LOOT_CLOSED"); Event("PLAYER_REGEN_ENABLED")
assert(not summary.host:IsVisible(), "unrelated loot or combat end after zoning must not open the old dungeon")
assert(state.history[1].historyID == retainedRun and state.lastKind == "mythic", "world entry must preserve manual history")
summary:ShowHistory()
assert(summary.host:IsVisible(), "the stored result must remain manually accessible after zoning")
summary:Close()
-- P2-4: a completion read that fails (combat, secrets) is retried by the
-- reward event and once combat ends, instead of losing the figures.
damage = 1000
Event("CHALLENGE_MODE_START")
damage, meterReadable = 3000, false
Event("CHALLENGE_MODE_COMPLETED")
assert(state.history[1].players[1].damage == nil, "an unreadable meter produced figures")
meterReadable = true
Event("CHALLENGE_MODE_COMPLETED_REWARDS")
assert(state.history[1].players[1].damage == 2000, "the reward event did not read the meter again")
damage = 1000
Event("CHALLENGE_MODE_START")
damage, meterReadable, combat = 3000, false, true
Event("CHALLENGE_MODE_COMPLETED")
Event("CHALLENGE_MODE_COMPLETED_REWARDS")
assert(state.history[1].players[1].damage == nil)
meterReadable, combat = true, false
Event("PLAYER_REGEN_ENABLED")
assert(state.history[1].players[1].damage == 2000, "combat end did not read the meter again")
summary:ClearHistory()
assert(#state.history == 0 and not state.lastKind and not summary.host:IsVisible())
-- A character keeps up to 100 runs (Runs kept per character: 1 to 100).
do
    local catalogNS = { Client = { isForever = false }, Text = function(text) return text end, Defaults = {} }
    assert(loadfile(root .. "/MSUF_Suite/Core/SuiteCatalog.lua"))("MSUF_Suite", catalogNS)
    assert(loadfile(root .. "/MSUF_Suite/Core/Catalog/HUD.lua"))("MSUF_Suite", catalogNS)
    local rule = catalogNS.SuiteCatalog.runSummary.rules.keepRuns
    assert(rule.min == 1 and rule.max == 100 and rule.step == 1, "the run history no longer offers 1 to 100 runs")
    for _, keep in ipairs({ 100, 1 }) do
        state.history = {}
        for i = 1, 120 do state.history[i] = { kind = "mythic", historyID = 121 - i, recordedAt = 121 - i } end
        state.lastKind, summary.config.keepRuns = "mythic", keep
        summary:ShowLast()
        assert(#state.history == keep and state.history[1].historyID == 120, "the history did not keep " .. keep .. " runs")
        summary:Close()
    end
    summary:ClearHistory()
    summary.config.keepRuns = 2
end
summary.config.cardTiming = 1
summary:Disable()
UnitGUID = function() return nil end
-- Classic 6.5 / Forever loads the same Suite module through its Mainline TOC.
-- It has raid encounters but the Suite must never subscribe to Mythic+ there.
NS.Client.isForever = true
summary.config.showRaid, summary.config.showMythicPlus = true, nil
summary.context = TimerContext("runSummary", summary, { events = {} })
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
assert(summary.host:IsVisible() and state.lastKind == "raid" and state.lastRaid.time == 60)
summary:Disable()
print("Run summary completion, reward update, combat delay, raid kill, wipe, records and settings: OK")

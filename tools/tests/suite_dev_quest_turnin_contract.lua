local root = assert(arg[1], "Suite root required")
local source = os.getenv("SUITE_DEV_QUEST_TURNIN_SOURCE") or root .. "/MSUF_Suite/Core/DevQuestTurnIn.lua"
local devModeSource = os.getenv("SUITE_DEV_MODE_SOURCE") or root .. "/MSUF_Suite/Core/DevMode.lua"
local checks = 0
local function Check(condition, message)
    checks = checks + 1
    assert(condition, message)
end

local function Unexpected() error("quest diagnostic wrote native state") end
local function Identity(value) return value end
local secret = newproxy(true)
getmetatable(secret).__tostring = function() error("restricted quest data was formatted") end
issecretvalue = function(value) return rawequal(value, secret) end
local function Public(value) return not issecretvalue(value) end
local function Finite(value)
    return Public(value) and type(value) == "number" and value == value and math.abs(value) < math.huge
end

local now, timers, frames, lines = 100, {}, {}, {}
GetTime = function() return now end
GetTimePreciseSec = GetTime
GetBuildInfo = function() return "1.60.1", "70959", "Nov 18 2026", 16001 end
date, time = os.date, os.time
local function Schedule(delay, callback)
    local job = { due = now + delay, callback = callback }
    function job:Cancel() self.cancelled = true end
    timers[#timers + 1] = job
    return job
end
C_Timer = { After = Schedule, NewTimer = Schedule }
local function Advance(seconds)
    local target = now + seconds
    for _ = 1, 100 do
        local index, due
        for i, job in ipairs(timers) do
            if job.due <= target and (not due or job.due < due) then index, due = i, job.due end
        end
        if not index then now = target return end
        now = due
        local job = table.remove(timers, index)
        if not job.cancelled then job.callback() end
    end
    error("quest diagnostic scheduled unbounded work")
end

CreateFrame = function(kind)
    assert(kind == "Frame", "diagnostic creates its own event frame")
    local frame = { events = {}, scripts = {} }
    function frame:RegisterEvent(event) self.events[event] = true end
    function frame:UnregisterEvent(event) self.events[event] = nil end
    function frame:UnregisterAllEvents() self.events = {} end
    function frame:IsEventRegistered(event) return self.events[event] == true end
    function frame:SetScript(script, callback) self.scripts[script] = callback end
    frames[#frames + 1] = frame
    return frame
end
local function Event(event)
    for _, frame in ipairs(frames) do
        if frame.events[event] then frame.scripts.OnEvent(frame, event) end
    end
end

local api, reads = {}, 0
local function Getter(key)
    return function() reads = reads + 1 return api[key] end
end
GetQuestID = Getter("quest")
GetRewardText = Getter("text")
GetNumQuestChoices = Getter("choices")
GetNumQuestRewards = Getter("rewards")
GetRewardXP = Getter("xp")
GetRewardMoney = Getter("money")
GetCVar = function() return "0" end
C_CVar = { GetCVar = GetCVar, SetCVar = Unexpected }
C_AddOns = {
    IsAddOnLoaded = function() return true end,
    GetAddOnMetadata = function() return "probe-test" end,
}
SlashCmdList = {}
EventRegistry = { RegisterCallback = function(_, event)
    assert(event == "ChatFrame.OnEditBoxFocusGained", "Dev Mode registered an unexpected callback")
end }
CompleteQuest, GetQuestReward, CloseQuest = Unexpected, Unexpected, Unexpected
QuestInfo_Display, QuestInfo_ShowRewards, hooksecurefunc = Unexpected, Unexpected, Unexpected
SendChatMessage = Unexpected

local function Visible(state)
    return state.shown and (not state.parent or state.parent.object:IsVisible())
end
local function Alpha(state)
    if not Public(state.alpha) then return state.alpha end
    local parentAlpha = state.parent and state.parent.object:GetEffectiveAlpha() or 1
    if not Public(parentAlpha) then return parentAlpha end
    return state.alpha * parentAlpha
end
local function Widget(name, parent)
    local state = { name = name, parent = parent, alpha = 1, shown = true, textAlpha = 1, height = 30 }
    local methods = {
        GetName = function() return state.name end,
        GetParent = function() return state.parent and state.parent.object end,
        IsForbidden = function() return state.forbidden == true end,
        IsShown = function() return state.shown end,
        IsVisible = function() return Visible(state) end,
        IsEnabled = function() return true end,
        GetAlpha = function() return state.alpha end,
        GetEffectiveAlpha = function() return Alpha(state) end,
        GetText = function() return state.text end,
        GetTextColor = function() return 1, 1, 1, state.textAlpha end,
        GetHeight = function() return state.height end,
        GetVerticalScrollRange = function() return 0 end,
        GetVerticalScroll = function() return 0 end,
        GetNumPoints = function() return 1 end,
        GetPoint = function() return "TOPLEFT", state.parent and state.parent.object, "TOPLEFT", 0, 0 end,
    }
    state.object = setmetatable({}, {
        __index = function(_, key)
            if methods[key] then return methods[key] end
            if key:match("^Set") or key == "Show" or key == "Hide" or key == "HookScript" then return Unexpected end
            return state[key]
        end,
        __newindex = Unexpected,
    })
    return state.object, state
end
local questFrame, panel, child, detail, title, rewardText, rewards, first, second
QuestFrame, questFrame = Widget("QuestFrame")
QuestFrameRewardPanel, panel = Widget("QuestFrameRewardPanel", questFrame)
QuestRewardScrollChildFrame, child = Widget("QuestRewardScrollChildFrame", panel)
QuestDetailScrollChildFrame, detail = Widget("QuestDetailScrollChildFrame", questFrame)
QuestInfoTitleHeader, title = Widget("QuestInfoTitleHeader", child)
QuestInfoRewardText, rewardText = Widget("QuestInfoRewardText", child)
QuestInfoRewardsFrame, rewards = Widget("QuestInfoRewardsFrame", child)
local firstButton, secondButton
firstButton, first = Widget("FirstChoice", rewards)
secondButton, second = Widget("SecondChoice", rewards)
rewards.RewardButtons = { firstButton, secondButton }
first.type, second.type = "choice", "choice"
QuestFrameCompleteQuestButton = Widget("QuestFrameCompleteQuestButton", panel)
QuestRewardScrollFrame = Widget("QuestRewardScrollFrame", panel)
WorldMapFrame = Widget("WorldMapFrame")
local questInfo = { rewardsFrame = QuestInfoRewardsFrame }
QuestInfoFrame = setmetatable({}, { __index = questInfo, __newindex = Unexpected })
UIFrameIsFading = function() return child.alpha < 1 end
local privateStory = "PRIVATE_CHARACTER_TEXT_MUST_NOT_LEAVE_WOW"
local function Setup(quest, ready)
    api = { quest = quest, text = ready and privateStory or "", choices = ready and 2 or 0,
        rewards = ready and 1 or 0, money = ready and 6500 or 0, xp = ready and 12463 or 0 }
    panel.shown, detail.shown = true, false
    child.alpha, rewardText.alpha, rewards.alpha = 1, 1, 1
    rewardText.text, rewards.shown = api.text, ready
    rewards.parent = ready and child or detail
    first.shown, second.shown = ready, ready
    title.text = "PRIVATE_QUEST_TITLE_MUST_NOT_LEAVE_WOW"
    questInfo.questLog, questInfo.mapView = false, false
    questInfo.chooseItems, questInfo.itemChoice = true, 0
end

local function Load(forever, saved)
    local suite = {
        Client = { isForever = forever },
        RootDB = saved or {},
        CreateFrame = CreateFrame,
        IsSecret = issecretvalue,
        Public = Public,
        Finite = Finite,
        PublicText = function(value) return Public(value) and type(value) == "string" and value ~= "" and value or nil end,
        Dispatch = function(callback, ...) return callback(...) end,
        IsCombatLocked = function() return false end,
        InCombat = function() return false end,
        Print = function(message) lines[#lines + 1] = message end,
        Text = Identity,
    }
    assert(loadfile(source))("MSUF_Suite", suite)
    assert(loadfile(devModeSource))("MSUF_Suite", suite)
    local slash = assert(SlashCmdList.MSUFSUITEDEVMODE)
    return suite, function(subcommand) slash("quest " .. subcommand) end
end
local function SavedCopy(value)
    local kind = type(value)
    if kind == "table" then
        local copy = {}
        for key, field in pairs(value) do copy[SavedCopy(key)] = SavedCopy(field) end
        return copy
    end
    Check(kind == "nil" or kind == "string" or kind == "number" or kind == "boolean", "SavedVariables hold a native object")
    if kind == "string" then
        Check(not value:find("PRIVATE_", 1, true), "quest or character text escaped the snapshot")
    end
    return value
end

local retail, retailCommand = Load(false)
retailCommand("on")
Check(not retail.DevQuestTurnIn and #frames == 0, "Retail started the Forever quest diagnostic")
Check(lines[#lines] == "This diagnostic setting is unavailable on this client.", "Retail quest slash did not explain unavailability")
local suite, command = Load(true)
Event("QUEST_COMPLETE")
Check(reads == 0 and not suite.RootDB.devQuestTurnIn, "probe observed a quest before opt-in")
command("on")
Check(reads == 0 and not suite.RootDB.devQuestTurnIn, "arming without a quest captured or saved native data")
local events = assert(frames[#frames], "quest diagnostic has no owned event frame").events
for _, event in ipairs({ "QUEST_COMPLETE", "QUEST_ITEM_UPDATE", "QUEST_FINISHED", "PLAYER_LOGOUT" }) do
    Check(events[event], "opt-in did not register " .. event)
end

Setup(10, true)
child.alpha = 0
Event("QUEST_COMPLETE")
Advance(0)
child.alpha = 1
Advance(0.7)
local reports = assert(suite.RootDB.devQuestTurnIn)
Check(reports.latest.quest == 10 and not reports.suspect, "normal native reward fade was classified as a failure")

Setup(11, true)
child.alpha = 0
Event("QUEST_COMPLETE")
Advance(0.7)
Check(reports.latest.quest == 11 and reports.suspect and reports.suspect.reason == "fade-unsettled",
    "whole reward canvas alpha was ignored or confused with hidden content")

Setup(2846, false)
Event("QUEST_COMPLETE")
Advance(0.7)
local suspect = assert(reports.suspect, "title-only reward page was not preserved")
Check(suspect.quest == 2846 and suspect.reason == "data-pending" and #suspect.rows >= 3,
    "initial and settled samples were not captured")
local initial = suspect.rows[1]
local firstIssue = suspect.firstIssue
Check(initial:find("complete@", 1, true) and initial:find("api=0/0/0/0/0", 1, true),
    "first incomplete payload was not recorded")
Check(firstIssue:find("settled@", 1, true) and firstIssue:find("issue=data-pending", 1, true),
    "first classification did not establish that the ordinary fade had elapsed")
local initialRows = #suspect.rows
api.text, api.choices, api.rewards, api.money, api.xp = privateStory, 2, 1, 6500, 12463
rewards.shown, first.shown, second.shown = true, true, true
questInfo.chooseItems = false
Event("QUEST_ITEM_UPDATE")
Advance(0)
Check(reports.suspect == suspect and #suspect.rows > initialRows, "late reward data did not enrich the saved failure")
local firstItem = assert(suspect.firstItem, "failed to mark the first post-item snapshot")
Check(firstItem:find("item-next@", 1, true) and firstItem:find("issue=blank", 1, true),
    "the first post-item snapshot did not capture the issue after the native refresh")
for _ = 1, 12 do
    Event("QUEST_ITEM_UPDATE")
    Advance(0.01)
end
Check(#suspect.rows <= 8, "repeated item updates grew the report beyond its bound")
local snapshot = table.concat(suspect.rows, "\n")
Check(suspect.rows[1] == initial and snapshot:find("api=1/2/1/12463/6500", 1, true),
    "bounded history discarded either the cold first event or the later ready payload")
Check(snapshot:find(firstIssue, 1, true) and snapshot:find(firstItem, 1, true),
    "report lost the first diagnosis or the first post-item snapshot")
Check(snapshot:find("text=0/1/reward", 1, true) and snapshot:find("rewards=detail/1/0", 1, true)
        and snapshot:find("choice=2/0/0/0", 1, true),
    "report did not distinguish visible page, blank story, stale reward parent and inert choices")
Check(not snapshot:find("PRIVATE_", 1, true), "report stored real quest content")

Event("QUEST_FINISHED")
Setup(44, true)
Event("QUEST_COMPLETE")
Advance(0.7)
Check(reports.latest.quest == 44 and reports.suspect == suspect, "healthy turn-in replaced the saved failure")

Setup(51, false)
Event("QUEST_COMPLETE")
Event("QUEST_FINISHED")
Setup(52, true)
Event("QUEST_COMPLETE")
Advance(0.7)
Check(reports.latest.quest == 52 and reports.suspect == suspect, "old quest's deferred samples contaminated the next attempt")

Setup(61, false)
Event("QUEST_COMPLETE")
local latest = reports.latest
command("off")
local reading = reads
Advance(1)
Event("QUEST_ITEM_UPDATE")
Check(reads == reading and reports.latest == latest and reports.suspect == suspect,
    "disabled probe continued reading or saving quest data")
Check(not next(frames[#frames].events), "disabled probe kept native event subscriptions")

local saved = SavedCopy(suite.RootDB)
local reload, reloadCommand = Load(true, saved)
lines = {}
reloadCommand("report")
Check(reads == reading and #lines > 0, "report after reload resampled native state or showed nothing")
local output = table.concat(lines, "\n")
Check(output:find("2846", 1, true) and not output:find("PRIVATE_", 1, true), "report did not show the previous safe capture")
lines = {}
reloadCommand("latest")
local latestOutput = table.concat(lines, "\n")
Check(reads == reading and latestOutput:find("/61/", 1, true) and not latestOutput:find("2846", 1, true),
    "the latest report lost the unsettled attempt or selected the older pinned failure")
local dialog, copied = {}, nil
reload.QoLCopyDialog = function() return dialog end
reload.QoLShowCopy = function(panel, content)
    Check(panel == dialog, "report used an unrelated copy panel")
    copied = content
end
reloadCommand("")
Check(reads == reading and copied and copied:find("2846", 1, true)
        and copied:find("issue=blank", 1, true) and not copied:find("PRIVATE_", 1, true),
    "copy dialog did not receive the full sanitized saved failure")

Setup(88, false)
api.text, api.choices, rewardText.text, rewards.alpha = secret, secret, secret, secret
reloadCommand("capture")
local manual = assert(reload.RootDB.devQuestTurnIn.suspect, "manual capture did not persist")
Check(manual.quest == 88, "manual capture failed on a restricted native data field")
Check(manual.rows[#manual.rows]:find("api=?/?/0/0/0", 1, true), "restricted quest data was reported as absent")
SavedCopy(reload.RootDB)
panel.shown = false
reloadCommand("capture")
Check(reload.RootDB.devQuestTurnIn.suspect == manual, "capture on a closed dialogue overwrote the report")

local quick, quickCommand = Load(true)
quickCommand("on")
Setup(405, false)
Event("QUEST_COMPLETE")
Event("PLAYER_LOGOUT")
local quickStore = assert(quick.RootDB.devQuestTurnIn)
local logout = assert(quickStore.latest, "immediate reload did not preserve the candidate")
Check(not quickStore.suspect and not logout.settled and logout.quest == 405 and logout.rows[#logout.rows]:find("logout@", 1, true),
    "pre-reload event lost provisional evidence or classified it during the native fade")
Setup(406, true)
questInfo.chooseItems = false
Event("QUEST_COMPLETE")
Advance(0.7)
local locked = assert(quick.RootDB.devQuestTurnIn.suspect)
Check(locked.quest == 406 and locked.reason == "choices", "visible choices with disabled selection were not diagnosed")

Setup(407, true)
rewardText.alpha, rewards.alpha = 0, 0
Event("QUEST_COMPLETE")
Advance(0.7)
local transparent = assert(quick.RootDB.devQuestTurnIn.suspect)
Check(transparent.quest == 407 and transparent.reason == "blank", "attached but transparent quest widgets were ignored")
local transparentRow = transparent.rows[#transparent.rows]
Check(transparentRow:find("text=1/1/reward/1/1/0/0", 1, true)
        and transparentRow:find("rewards=reward/1/1/0/0", 1, true),
    "report did not distinguish transparent populated rewards from missing payload and stale parent")

Setup(408, true)
questInfo.chooseItems = secret
Event("QUEST_COMPLETE")
Advance(0.7)
Check(quickStore.suspect == transparent and quickStore.latest.rows[#quickStore.latest.rows]:find("choice=2/2/?/0", 1, true),
    "unreadable selection mode was treated as disabled")
print("suite quest turn-in diagnostics: " .. checks .. " checks passed")

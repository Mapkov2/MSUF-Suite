local _, Suite = ...
if not Suite.Client.isForever then return end

local Diagnostic = {}
Suite.DevQuestTurnIn = Diagnostic

local SCHEMA = 1
local MAX_ROWS = 8
local MAX_REWARD_BUTTONS = 40
-- Forever fades the entire reward scroll child for 0.5 seconds.
local SETTLE_DELAY = 0.65
local CLEAR_ALPHA = 0.05
local SETTLED_ALPHA = 0.98
local armed, listener, current, copyDialog

local function Readable(object)
    if not Suite.Public(object) or type(object) ~= "table" then return false end
    local forbidden = object.IsForbidden
    if not Suite.Public(forbidden) then return false end
    if type(forbidden) ~= "function" then return true end
    local blocked = forbidden(object)
    return Suite.Public(blocked) and blocked == false
end

local function Field(object, key)
    if not Readable(object) then return end
    local value = object[key]
    if Suite.Public(value) then return value end
end

local function Read(object, key)
    local method = Field(object, key)
    if type(method) ~= "function" then return end
    local value = method(object)
    if Suite.Public(value) then return value end
end

local function Number(value)
    if Suite.Finite(value) then return value end
end

local function TextPresent(value)
    if not Suite.Public(value) then return end
    if value == nil then return false end
    if type(value) == "string" then return value ~= "" end
end

local function RenderedTextPresent(object)
    local method = Field(object, "GetText")
    if type(method) == "function" then return TextPresent(method(object)) end
end

local function Flag(value)
    if Suite.Public(value) and type(value) == "boolean" then return value end
end

local function NativeFlag(object, key)
    if not Readable(object) then return end
    local value = object[key]
    if Suite.Public(value) then return value == true end
end

local function ParentKind(object)
    local parent = Read(object, "GetParent")
    if parent == nil then return "?" end
    if parent == QuestRewardScrollChildFrame then return "reward" end
    if parent == QuestDetailScrollChildFrame then return "detail" end
    if parent == QuestProgressScrollChildFrame then return "progress" end
    return "other"
end

local function Widget(object)
    return {
        parent = ParentKind(object),
        shown = Flag(Read(object, "IsShown")),
        visible = Flag(Read(object, "IsVisible")),
        alpha = Number(Read(object, "GetAlpha")),
        effective = Number(Read(object, "GetEffectiveAlpha")),
        height = Number(Read(object, "GetHeight")),
    }
end

local function TextAlpha(object)
    local method = Field(object, "GetTextColor")
    if type(method) ~= "function" then return end
    local _, _, _, alpha = method(object)
    return Number(alpha)
end

local function ChoiceButtons(rewards)
    local buttons = Field(rewards, "RewardButtons")
    if type(buttons) ~= "table" then return end
    local shown, visible = 0, 0
    for index = 1, math.min(#buttons, MAX_REWARD_BUTTONS) do
        local button = buttons[index]
        if Field(button, "type") == "choice" then
            if Read(button, "IsShown") == true then shown = shown + 1 end
            local alpha = Number(Read(button, "GetEffectiveAlpha"))
            if Read(button, "IsVisible") == true and (not alpha or alpha > CLEAR_ALPHA) then visible = visible + 1 end
        end
    end
    return shown, visible
end

local function RewardPanelVisible()
    return Read(QuestFrameRewardPanel, "IsVisible") == true
end

local function Snapshot()
    local shown, visible = ChoiceButtons(QuestInfoRewardsFrame)
    local nativeRewards = Field(QuestInfoFrame, "rewardsFrame")
    return {
        page = RewardPanelVisible(),
        title = Flag(Read(QuestInfoTitleHeader, "IsVisible")),
        button = Flag(Read(QuestFrameCompleteQuestButton, "IsVisible")),
        storyAPI = TextPresent(GetRewardText()),
        storyUI = RenderedTextPresent(QuestInfoRewardText),
        choices = Number(GetNumQuestChoices()),
        fixed = Number(GetNumQuestRewards()),
        xp = Number(GetRewardXP()),
        money = Number(GetRewardMoney()),
        story = Widget(QuestInfoRewardText),
        textAlpha = TextAlpha(QuestInfoRewardText),
        rewards = Widget(QuestInfoRewardsFrame),
        scroll = Number(Read(QuestRewardScrollFrame, "GetVerticalScroll")),
        range = Number(Read(QuestRewardScrollFrame, "GetVerticalScrollRange")),
        childAlpha = Number(Read(QuestRewardScrollChildFrame, "GetEffectiveAlpha")),
        shownChoices = shown,
        visibleChoices = visible,
        chooseItems = NativeFlag(QuestInfoFrame, "chooseItems"),
        itemChoice = Number(Field(QuestInfoFrame, "itemChoice")),
        questLog = NativeFlag(QuestInfoFrame, "questLog"),
        nativeRewards = nativeRewards and (nativeRewards == QuestInfoRewardsFrame and "npc"
            or nativeRewards == MapQuestInfoRewardsFrame and "map") or nil,
        map = Flag(Read(WorldMapFrame, "IsVisible")),
    }
end

local function Encoded(value)
    if value == true then return "1" end
    if value == false then return "0" end
    if type(value) == "number" then
        return value == math.floor(value) and ("%.0f"):format(value) or ("%.2f"):format(value)
    end
    return type(value) == "string" and value or "?"
end

local function Columns(...)
    local values = {}
    for index = 1, select("#", ...) do values[index] = Encoded((select(index, ...))) end
    return table.concat(values, "/")
end

local function WidgetColumns(widget)
    return Columns(widget.parent, widget.shown, widget.visible, widget.alpha, widget.effective, widget.height)
end

local function FormatRow(phase, elapsed, snapshot)
    return phase .. "@" .. elapsed .. "ms"
        .. " page=" .. Columns(snapshot.page, snapshot.title, snapshot.button, snapshot.childAlpha, snapshot.scroll, snapshot.range)
        .. " api=" .. Columns(snapshot.storyAPI, snapshot.choices, snapshot.fixed, snapshot.xp, snapshot.money)
        .. " text=" .. Columns(snapshot.storyUI, snapshot.textAlpha) .. "/" .. WidgetColumns(snapshot.story)
        .. " rewards=" .. WidgetColumns(snapshot.rewards)
        .. " choice=" .. Columns(snapshot.shownChoices, snapshot.visibleChoices, snapshot.chooseItems, snapshot.itemChoice)
        .. " context=" .. Columns(snapshot.nativeRewards, snapshot.questLog, snapshot.map)
end

local function Concealed(widget)
    return widget.visible == false or widget.parent ~= "?" and widget.parent ~= "reward"
        or widget.effective and widget.effective <= CLEAR_ALPHA or widget.alpha and widget.alpha <= CLEAR_ALPHA
end

local function Issue(snapshot)
    if not snapshot.page or snapshot.button ~= true or not snapshot.childAlpha then return end
    if snapshot.childAlpha < SETTLED_ALPHA then return "fade-unsettled" end
    if snapshot.title ~= true then return end
    local hiddenText = snapshot.storyUI == false or Concealed(snapshot.story)
        or snapshot.textAlpha and snapshot.textAlpha <= CLEAR_ALPHA
    if hiddenText and (snapshot.rewards.shown == false or Concealed(snapshot.rewards)) then
        local hasData = snapshot.storyAPI == true or (snapshot.choices or 0) > 0 or (snapshot.fixed or 0) > 0
            or (snapshot.xp or 0) > 0 or (snapshot.money or 0) > 0
        return hasData and "blank" or "data-pending"
    end
    if snapshot.choices and snapshot.choices > 1 then
        if snapshot.visibleChoices and snapshot.visibleChoices < snapshot.choices or snapshot.chooseItems == false then
            return "choices"
        end
    end
end

local function Store()
    local store = Suite.RootDB.devQuestTurnIn
    if type(store) ~= "table" or store.schema ~= SCHEMA then
        store = { schema = SCHEMA }
        Suite.RootDB.devQuestTurnIn = store
    end
    return store
end

local function QuestID()
    local id = Number(GetQuestID())
    if id and id > 0 then return id end
end

local function NumericID(value)
    if Suite.Finite(value) then return tostring(value) end
    local text = Suite.PublicText(value)
    if text then return text:match("^%d+$") end
end

local function NewAttempt()
    local _, build = GetBuildInfo()
    local version = Suite.PublicText(C_AddOns.GetAddOnMetadata("MSUF_Suite", "Version"))
    local report = { quest = QuestID(), build = NumericID(build), rows = {},
        suite = version and version:match("^[%w%.%-]+$") or nil,
        skin = Flag(C_AddOns.IsAddOnLoaded("MSUF_Suite_Skin")) }
    -- Keep the provisional attempt even if the player reloads before the fade completes.
    Store().latest = report
    return { started = GetTime(), report = report }
end

local function Capture(attempt, phase, classify, manual)
    local snapshot = Snapshot()
    local report = attempt.report
    local rows = report.rows
    local reason = classify and Issue(snapshot)
    local row = FormatRow(phase, math.floor((GetTime() - attempt.started) * 1000), snapshot)
    if reason then row = row .. " issue=" .. reason end
    -- Keep the opening, first detected failure and first post-item snapshot.
    if #rows == MAX_ROWS then
        local oldest = 2
        while oldest < #rows and (rows[oldest] == report.firstIssue or rows[oldest] == report.firstItem) do
            oldest = oldest + 1
        end
        table.remove(rows, oldest)
    end
    rows[#rows + 1] = row
    if phase == "settled" then report.settled = true end
    if phase == "item-next" and not report.firstItem then report.firstItem = row end
    if (reason or manual) and not report.reason then
        report.reason = reason or "manual"
        report.firstIssue = row
        Store().suspect = report
    end
end

local function Matches(attempt)
    return current == attempt and attempt.report.quest ~= nil and RewardPanelVisible() and QuestID() == attempt.report.quest
end

local function SampleAfterEvent(attempt, phase)
    local queued = attempt.queued
    attempt.queued = phase
    if queued then return end
    C_Timer.After(0, function()
        local sample = attempt.queued
        attempt.queued = nil
        if Matches(attempt) then Suite.Dispatch(Capture, attempt, sample, attempt.report.settled) end
    end)
end

local function Observe(_, event)
    if event == "QUEST_FINISHED" then current = nil return end
    if event == "QUEST_COMPLETE" then
        local attempt = NewAttempt()
        current = attempt
        -- Event listeners have no guaranteed ordering. Only later samples can classify a failure.
        Capture(attempt, "complete")
        SampleAfterEvent(attempt, "next")
        C_Timer.After(SETTLE_DELAY, function()
            if Matches(attempt) then Suite.Dispatch(Capture, attempt, "settled", true) end
        end)
        return
    end
    local attempt = current
    if not attempt or not Matches(attempt) then return end
    if event == "QUEST_ITEM_UPDATE" then
        if not attempt.queued then Capture(attempt, "item") end
        SampleAfterEvent(attempt, "item-next")
    elseif event == "PLAYER_LOGOUT" then
        Capture(attempt, "logout", attempt.report.settled)
    end
end

local function Arm(enabled)
    if enabled == armed then return end
    armed = enabled
    if enabled then
        if not listener then
            listener = CreateFrame("Frame")
            listener:SetScript("OnEvent", Observe)
        end
        listener:RegisterEvent("QUEST_COMPLETE")
        listener:RegisterEvent("QUEST_ITEM_UPDATE")
        listener:RegisterEvent("QUEST_FINISHED")
        listener:RegisterEvent("PLAYER_LOGOUT")
    else
        if listener then listener:UnregisterAllEvents() end
        current = nil
    end
end

local function Report(latest)
    local store = Suite.RootDB.devQuestTurnIn
    local report = type(store) == "table" and store.schema == SCHEMA and (not latest and store.suspect or store.latest)
    if type(report) ~= "table" or type(report.rows) ~= "table" then
        Suite.Print("QuestDiag report=none")
        return
    end
    local header = "QuestDiag/" .. SCHEMA .. " stored build/suite/quest/skin/reason/settled="
        .. Columns(report.build, report.suite, report.quest, report.skin, report.reason, report.settled == true)
    if not Suite.InCombat() and Suite.QoLCopyDialog and Suite.QoLShowCopy then
        copyDialog = copyDialog or Suite.QoLCopyDialog("Copy", "Ctrl+C", 560)
        Suite.QoLShowCopy(copyDialog, header .. " | " .. table.concat(report.rows, " | "))
    else
        Suite.Print(header)
        for _, row in ipairs(report.rows) do Suite.Print(row) end
    end
end

function Diagnostic.Command(command)
    if not Suite.RootDB then
        Suite.Print("QuestDiag storage=unavailable")
        return
    end
    if command == "on" or command == "off" then
        Arm(command == "on")
        Suite.Print("QuestDiag " .. command)
    elseif command == "capture" then
        if not RewardPanelVisible() then
            Suite.Print("QuestDiag rewardPage=closed")
            return
        end
        local attempt = current and Matches(current) and current or NewAttempt()
        Capture(attempt, "manual", attempt.report.settled, true)
        Suite.Print("QuestDiag saved")
    elseif command == "" or command == "report" or command == "latest" then
        Report(command == "latest")
    else
        Suite.Print("/msufdev quest on | off | capture | report | latest")
    end
end

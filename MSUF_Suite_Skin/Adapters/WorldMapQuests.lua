local _, NS = ...

-- Compact presentation stays on Blizzard's pooled quest buttons. Owned
-- labels add columns and Forever masks the objective rows in this view.
-- Native search, header collapse, tracking, links, menus and tooltips remain.
local Quests = {}
NS.WorldMapQuests = Quests
local Safety, Kit = NS.Safety, NS.AdapterKit
local rows, contexts = Kit.WeakSet(), Kit.WeakSet()
local lists, headers, titleSizes = Kit.WeakSet(), Kit.WeakSet(), Kit.WeakSet()
local originalObjectives, yieldedObjectives, refreshing, combatRefreshQueued
local pendingValues, pendingHead, pendingTail = {}, 1, 0
local CVAR = "showQuestObjectivesInLog"
local REPLAY = "world-map-quest-layout"
local events = CreateFrame("Frame")

function Quests.GetLayout()
    local settings = NS.DB and NS.DB.questLog
    return settings and settings.layout == "compact" and "compact" or "blizzard"
end

local function Compact()
    return NS.DB and NS.DB.enabled ~= false and Quests.GetLayout() == "compact" and next(contexts) ~= nil
end

-- Keep the normal protection checks, including the combat edge before
-- InCombatLockdown turns true. Plain quest rows can still paint and reflow.
local function CanPaint(target, list, implicit)
    if implicit == nil then implicit = not NS.IsCombatLocked() and not NS.SuiteCore().startingBeforeLockdown end
    local allowed = Safety.CanDecorate(target, implicit)
    if not allowed and list and NS.IsCombatLocked() then list.refused = true end
    return allowed
end

local function HasCombatView()
    if Compact() then return true end
    for state in pairs(contexts) do
        local list = state.questFolds
        if list and (next(list.folded) or next(list.hiddenButtons)) then return true end
    end
    return false
end

local function ReplayList(list)
    if list.replayPending then return end
    list.replayPending = true
    NS.CombatGate.RunOrDefer(list, list.replay)
end

local function DeferList(list)
    list.stale = true
    if NS.IsCombatLocked() then Quests.QueueCombatRefresh()
    else NS.Registry.QueueJob(list.reapply) end
end

local function WriteObjectives(value)
    value = tostring(value)
    if GetCVar(CVAR) == value then return end
    pendingTail = pendingTail + 1
    pendingValues[pendingTail] = value
    SetCVar(CVAR, value)
end

local function OwnCVarEvent(value)
    if pendingValues[pendingHead] ~= value or pendingHead > pendingTail then return false end
    pendingValues[pendingHead] = nil
    pendingHead = pendingHead + 1
    if pendingHead > pendingTail then pendingHead, pendingTail = 1, 0 end
    return true
end

local function RestoreObjectives()
    if NS.Client.isForever then return end
    local original = originalObjectives
    originalObjectives = nil
    yieldedObjectives = nil
    if original ~= nil and GetCVar(CVAR) == "0" then WriteObjectives(original) end
end

local function SyncObjectives()
    -- Forever's CVAR_UPDATE refreshes the native quest pane and may recreate
    -- protected map pins from inside the addon's SetCVar call.
    if NS.Client.isForever or NS.IsCombatLocked() or NS.SuiteCore().startingBeforeLockdown then return end
    if not Compact() then
        RestoreObjectives()
        return
    end
    if originalObjectives ~= nil or yieldedObjectives then return end
    originalObjectives = GetCVar(CVAR)
    if originalObjectives ~= nil and originalObjectives ~= "0" then WriteObjectives("0") end
end

local function Plain(value)
    if Safety.Public(value) then return value end
end

-- Quest consumers can expand the native log to read progress. Remember the
-- player's disclosure choice in this view and filter Blizzard's active rows
-- before its layout. The quest data stays available to those consumers.
local PLUS, MINUS = "common-button-list-plus", "common-button-list-minus"
local FOLD_ROW_LIMIT = 256

local function HeaderKey(info)
    local key = Plain(Safety.Field(info, "headerSortKey"))
    if type(key) == "string" or type(key) == "number" then return key end
end

local function HeaderInfo(index)
    if type(index) ~= "number" or index < 1 then return end
    local info = Plain(C_QuestLog.GetInfo(index))
    if Plain(Safety.Field(info, "isHeader")) == true then return info end
end

local function SearchActive(list)
    local text = Safety.Read(Safety.Field(list.scroll, "SearchBox"), "GetText")
    return type(text) == "string" and text ~= ""
end

local function MaskRow(row, list, hide)
    if not CanPaint(row, list, list.implicit) then return end
    local shown = Safety.Read(row, "IsShown")
    if hide and shown == true then
        row:Hide()
        list.hidden[row] = true
        list.changed = true
    elseif not hide and list.hidden[row] then
        list.hidden[row] = nil
        if shown == false then
            row:Show()
            list.changed = true
            return true
        end
    end
end

local function SetCompactTitleHeight(row, list, compact)
    local record = list.titleHeights[row]
    if not (compact or record) or not CanPaint(row, list, list.implicit) then return end
    local current = Safety.Read(row, "GetHeight")
    if type(current) ~= "number" then return end
    if not compact then
        list.titleHeights[row] = nil
        if current == record.applied then
            row:SetHeight(record.native)
            list.changed = true
        end
        return
    end
    local textHeight = Safety.Read(Safety.Field(row, "Text"), "GetHeight")
    if type(textHeight) ~= "number" or textHeight <= 0 then return end
    -- QuestLogQuests_AddQuestButton includes objectives in the title's height.
    -- Its objective-free baseline adds 8 for text, 4 for spacing and 6 for the POI.
    local height = textHeight + 18
    if current ~= height then
        if not record or current ~= record.applied then
            record = titleSizes[row]
            if not record then
                record = {}
                titleSizes[row] = record
            end
            record.native = current
            list.titleHeights[row] = record
        end
        record.applied = height
        row:SetHeight(height)
        list.changed = true
    elseif record and current ~= record.applied then
        list.titleHeights[row] = nil
    end
end

local function MaskTitle(row, list, compact)
    local folded
    if list.masking or list.hidden[row] then
        local info = Plain(Safety.Field(row, "info"))
        local key = HeaderKey(Plain(Safety.Field(info, "header")))
        folded = list.masking and key ~= nil and list.folded[key] == true
        if MaskRow(row, list, folded) and list.owner then Quests.PaintRow(row, list.owner) end
    end
    -- An active title can also be hidden by another quest-log filter. Its
    -- sibling buttons would then sit at the top of the list, outside layout.
    if folded or list.spoken and Safety.Read(row, "IsShown") == false then
        local info = Plain(Safety.Field(row, "info"))
        local questID = Plain(Safety.Field(info, "questID"))
        if type(questID) == "number" then list.hiddenQuests[questID] = true end
    end
    SetCompactTitleHeight(row, list, compact)
end

local function MaskObjective(row, list, compact)
    local questID = not compact and Plain(Safety.Field(row, "questID"))
    MaskRow(row, list, compact or type(questID) == "number" and list.hiddenQuests[questID] == true)
end

-- POIs and Spoken controls are siblings of the quest title. Leave Show/Hide
-- to their owners (POI visibility scripts also change supertracking).
local function HoldButton(button, list, implicit)
    if not button or not CanPaint(button, list, implicit) then return end
    local record = list.hiddenButtons[button]
    if not record then
        local alpha = Safety.Read(button, "GetAlpha")
        local clicks = Safety.Read(button, "IsMouseClickEnabled")
        local motion = Safety.Read(button, "IsMouseMotionEnabled")
        if type(alpha) ~= "number" or type(clicks) ~= "boolean" or type(motion) ~= "boolean" then return end
        record = { alpha = alpha, clicks = clicks, motion = motion }
        list.hiddenButtons[button] = record
        button:SetAlpha(0)
        button:SetMouseClickEnabled(false)
        button:SetMouseMotionEnabled(false)
    end
    return record
end

local function MaskButton(button, list)
    local record = HoldButton(button, list, list.implicit)
    if record then record.masked = true end
end

local function MaskPin(pin, list)
    local questID = Safety.Read(pin, "GetQuestID")
    if type(questID) == "number" and list.hiddenQuests[questID] then MaskButton(pin, list) end
end

local function ReleaseButton(button, record, list, implicit)
    if not CanPaint(button, list, implicit) then return end
    button:SetAlpha(record.alpha)
    button:SetMouseClickEnabled(record.clicks)
    button:SetMouseMotionEnabled(record.motion)
    list.hiddenButtons[button] = nil
end

local function RestoreUnmaskedButtons(list)
    for button, record in pairs(list.hiddenButtons) do
        if record.masked then
            record.masked = nil
        else
            ReleaseButton(button, record, list, list.implicit)
        end
    end
end

-- Spoken 3.10 also positions fresh Play/Contribute buttons on independent
-- overlay refreshes. The hook runs after positioning and before Spoken's Show.
local spokenOverlay
local function OnSpokenTitle(_, row, button)
    local list = lists[QuestScrollFrame]
    if not list or not list.owner or not Safety.Public(row) or not Safety.Public(button) or not button
        or Safety.Read(row, "GetParent") ~= list.contents then return end
    local shown = Safety.Read(row, "IsShown")
    if shown == false then HoldButton(button, list)
    elseif shown == true and list.hiddenButtons[button] then
        ReleaseButton(button, list.hiddenButtons[button], list)
    end
    if list.refused then ReplayList(list) end
end

local function AttachSpoken()
    local voice = rawget(_G, "VoiceOver")
    if Plain(Safety.Field(voice, "AddonFolder")) ~= "Spoken_Quests" then return end
    local overlay = Plain(Safety.Field(voice, "QuestOverlayUI"))
    if overlay and overlay ~= spokenOverlay and Kit.HookFunction(overlay, "UpdateQuestTitle", Safety.Isolated(OnSpokenTitle)) then
        spokenOverlay = overlay
        events:UnregisterEvent("ADDON_LOADED")
    end
end

local function MaskSpokenButtons(list)
    local play = Plain(Safety.Field(spokenOverlay, "questPlayButtons"))
    local contribute = Plain(Safety.Field(spokenOverlay, "questContributeButtons"))
    for id in pairs(list.hiddenQuests) do
        MaskButton(Plain(Safety.Field(play, id)), list)
        MaskButton(Plain(Safety.Field(contribute, id)), list)
    end
end

local function ChangeDisclosureAtlas(texture, override)
    local from, to = MINUS, PLUS
    if not override then from, to = PLUS, MINUS end
    if Safety.Read(texture, "GetAtlas") == from then Safety.Invoke(texture, "SetAtlas", to, true) end
end

local function PaintDisclosure(header, record, folded)
    local button = Safety.Field(header, "CollapseButton")
    local nativeOpen = Plain(Safety.Field(button, "collapsed")) == false
    local override = folded and nativeOpen
    if (override or record.disclosure) and nativeOpen and CanPaint(button, record.list, record.list.implicit) then
        ChangeDisclosureAtlas(Safety.Field(button, "Icon"), override)
        ChangeDisclosureAtlas(Safety.Read(button, "GetHighlightTexture"), override)
    end
    record.disclosure = override
end

local function BeforeHeaderClick(header, button)
    local record = headers[header]
    if not record then return end
    record.clickKey, record.reopenIndex = nil, nil
    local list = record.list
    if button ~= "LeftButton" or not list.owner or not CanPaint(header) or SearchActive(list) then return end
    local index = Plain(Safety.Field(header, "questLogIndex"))
    local info = HeaderInfo(index)
    local key = HeaderKey(info)
    local collapsed = Plain(Safety.Field(info, "isCollapsed"))
    if key == nil or type(collapsed) ~= "boolean" then return end
    record.clickKey = key
    if list.folded[key] then
        list.folded[key] = nil
        -- Blizzard sees an open header if a consumer already expanded it.
        -- Finish this explicit reopen after its native click has run.
        if not collapsed then record.reopenIndex = index end
    elseif not collapsed then
        list.folded[key] = true
    end
end

local function AfterHeaderClick(header)
    local record = headers[header]
    if not record or record.clickKey == nil then return end
    local key, index, list = record.clickKey, record.reopenIndex, record.list
    record.clickKey, record.reopenIndex = nil, nil
    if not list.owner or not CanPaint(header) then return end
    local info = HeaderInfo(index)
    if HeaderKey(info) == key and Plain(Safety.Field(info, "isCollapsed")) == true then
        ExpandQuestHeader(index)
    end
    list.relayout()
end

local function TrackHeader(header, list, questInfo)
    local record = headers[header]
    if not record and list.owner and CanPaint(header)
        and Safety.Read(header, "HasScript", "PreClick") == true
        and Safety.Read(header, "HasScript", "PostClick") == true then
        record = { list = list }
        headers[header] = record
        header:HookScript("PreClick", Safety.Isolated(BeforeHeaderClick))
        header:HookScript("PostClick", Safety.Isolated(AfterHeaderClick))
    end
    if not record then return end
    local folded = false
    if list.masking then
        local index = Plain(Safety.Field(header, "questLogIndex"))
        local info = Plain(Safety.Field(questInfo, index)) or HeaderInfo(index)
        local key = HeaderKey(info)
        folded = key ~= nil and list.folded[key] == true
    end
    PaintDisclosure(header, record, folded)
end

local function ApplyFolds(list, questInfo)
    list.masking = list.owner ~= nil and next(list.folded) ~= nil and not SearchActive(list)
    list.spoken = list.owner ~= nil and spokenOverlay ~= nil and list.scroll == QuestScrollFrame
    local compact = list.owner ~= nil and Compact() and (NS.Client.isForever or GetCVar(CVAR) ~= "0")
    local masked = list.masking or next(list.hidden) ~= nil
    list.changed, list.refused = false, false
    list.implicit = not NS.IsCombatLocked() and not NS.SuiteCore().startingBeforeLockdown
    Kit.ForEachActive(Safety.Field(list.scroll, "headerFramePool"), FOLD_ROW_LIMIT, TrackHeader, list, questInfo)
    if masked or compact or list.spoken or next(list.titleHeights) then
        wipe(list.hiddenQuests)
        Kit.ForEachActive(Safety.Field(list.scroll, "titleFramePool"), FOLD_ROW_LIMIT, MaskTitle, list, compact)
        if next(list.hiddenQuests) then
            Kit.ForEachActive(Safety.Field(list.contents, "buttonPool"), FOLD_ROW_LIMIT, MaskPin, list)
            if list.spoken then MaskSpokenButtons(list) end
        end
    end
    if compact or masked then
        local objectives = Safety.Field(list.scroll, "objectiveFramePool")
        Kit.ForEachActive(objectives, Safety.Read(objectives, "GetNumActive") or FOLD_ROW_LIMIT, MaskObjective, list, compact)
    end
    RestoreUnmaskedButtons(list)
    if list.refused then ReplayList(list) end
    return list.changed
end

local function BeforeQuestLayout(scroll, displayState)
    local list = lists[scroll]
    if not list or not list.owner then return end
    -- Blizzard has reset its pools and is about to lay out shown rows.
    wipe(list.hidden)
    wipe(list.titleHeights)
    list.stale = true
    if Safety.Read(scroll, "IsVisible") ~= true then return end
    if NS.Client.isForever and not list.owner.questMapReady then
        -- The native map open can rebuild the quest log before its protected
        -- reading emote. Reapply our view after that stack, using the live rows.
        DeferList(list)
    else
        -- A completed map opening may be rebuilt repeatedly by quest scans.
        -- Filter the native layout inputs now; Blizzard owns the Layout below.
        ApplyFolds(list, Plain(Safety.Field(Plain(displayState), "questInfoContainer")))
        list.stale = false
    end
end

local function RevealMapQuest(scroll, questID)
    local list = lists[scroll]
    if not list or not list.owner or not next(list.folded) or not Safety.Public(questID) then return end
    local index = Plain(C_QuestLog.GetHeaderIndexForQuest(questID))
    local key = HeaderKey(HeaderInfo(index))
    if key ~= nil then list.folded[key] = nil end
end

-- Fold changes affect the row positions, so reuse the child sizes from the
-- native rebuild. The layout view skips child Layout calls and their MarkClean.
local function ResizeQuestList(contents, layout)
    local children = contents:GetLayoutChildren()
    local width, height, expandable = layout:LayoutChildren(children)
    local frameWidth, frameHeight = contents:CalculateFrameSize(width, height)
    if expandable then
        width, height = layout:LayoutChildren(children, frameWidth)
        frameWidth, frameHeight = contents:CalculateFrameSize(width, height)
    end
    contents:SetSize(frameWidth, frameHeight)
end

local function AttachFolds(scroll, state)
    local contents = Safety.Field(scroll, "Contents")
    if not Safety.HasMethod(scroll, "UpdateBackground") or not Safety.HasMethod(contents, "GetLayoutChildren")
        or not Safety.HasMethod(contents, "LayoutChildren") or not Safety.HasMethod(contents, "CalculateFrameSize") then
        return
    end
    local list = lists[scroll]
    if not list then
        local layout = setmetatable({ skipChildLayout = true }, { __index = contents })
        list = {
            scroll = scroll, contents = contents, folded = {}, hidden = Kit.WeakSet(),
            hiddenQuests = {}, hiddenButtons = Kit.WeakSet(), titleHeights = Kit.WeakSet(),
        }
        list.relayout = function()
            list.refused = false
            if CanPaint(contents, list) then
                if ApplyFolds(list) then ResizeQuestList(contents, layout) end
                list.stale = false
            elseif list.refused then ReplayList(list) end
        end
        list.reapply = function()
            if list.owner then list.relayout() end
        end
        list.replay = function()
            list.replayPending = false
            list.reapply()
        end
        lists[scroll] = list
        Kit.HookFunction(scroll, "UpdateBackground", Safety.Isolated(BeforeQuestLayout))
        Kit.HookFunction(scroll, "ExpandHeaderForQuest", Safety.Isolated(RevealMapQuest))
    end
    state.questFolds, list.owner = list, state
    if NS.IsCombatLocked() or NS.Client.isForever and not state.questMapReady then
        DeferList(list)
    else list.relayout() end
end

local function ReleaseFolds(state)
    local list = state.questFolds
    if not list or list.owner ~= state then return end
    list.owner, state.questFolds = nil, nil
    wipe(list.folded)
    list.relayout()
    wipe(list.hidden)
end

-- WorldMapBountyBoard.lua uses these five scalar returns on both clients.
-- Avoid allocating an objectives table for every quest-log refresh.
local function Progress(questID, index)
    if Plain(C_QuestLog.IsComplete(questID)) == true then return NS.L["Ready"] end
    local count = Plain(GetNumQuestLeaderBoards(index))
    if type(count) ~= "number" then return "" end
    local current, required, completed = 0, 0, 0
    for objective = 1, math.min(count, 40) do
        local _, _, finished, fulfilled, total = GetQuestObjectiveInfo(questID, objective, false)
        fulfilled, total, finished = Plain(fulfilled), Plain(total), Plain(finished)
        if type(fulfilled) == "number" and type(total) == "number" and total > 0 then
            current, required = current + fulfilled, required + total
        end
        if finished == true then completed = completed + 1 end
    end
    if required > 0 then return string.format("%d/%d", current, required) end
    if count > 0 then return string.format("%d/%d", completed, count) end
    return ""
end

local function Label(row)
    local label = row:CreateFontString(nil, "OVERLAY")
    label:SetWordWrap(false)
    return label
end

local function UpdateFont(record)
    local object = Safety.Read(record.original, "GetFontObject")
    if object then
        if record.fontObject ~= object then
            record.level:SetFontObject(object)
            record.title:SetFontObject(object)
            record.progress:SetFontObject(object)
            record.fontObject = object
        end
        return
    end
    local face, size, flags = Kit.ReadValues(Safety.Field(record.original, "GetFont"), record.original)
    if face and (record.face ~= face or record.size ~= size or record.flags ~= flags) then
        record.level:SetFont(face, size, flags)
        record.title:SetFont(face, size, flags)
        record.progress:SetFont(face, size, flags)
        record.face, record.size, record.flags = face, size, flags
    end
end

local function DecoratedTitle(original, info)
    local text = Safety.Read(original, "GetText")
    if type(text) ~= "string" or text == "" then return Plain(info.title) end
    local overrides = Safety.Field(_G, "QuestUtilsOverrides")
    local prefix = Kit.ReadValues(Safety.Field(overrides, "GetQuestTitlePrefix"), info)
    if type(prefix) == "string" and prefix ~= "" then
        local first, last = text:find(prefix, 1, true)
        if first then text = text:sub(1, first - 1) .. text:sub(last + 1) end
    end
    return text
end

local function CreateColumns(row, original)
    local record = { original = original }
    record.level, record.title, record.progress = Label(row), Label(row), Label(row)
    record.level:SetPoint("TOPLEFT", original, "TOPLEFT")
    record.level:SetWidth(26)
    record.level:SetJustifyH("LEFT")
    record.title:SetPoint("TOPLEFT", original, "TOPLEFT", 29, 0)
    record.title:SetPoint("TOPRIGHT", original, "TOPRIGHT", -64, 0)
    record.title:SetJustifyH("LEFT")
    record.progress:SetPoint("TOPRIGHT", original, "TOPRIGHT")
    record.progress:SetWidth(60)
    record.progress:SetJustifyH("RIGHT")
    rows[row] = record
    return record
end

local function ShowColumns(record, shown)
    if record.visible == shown then return end
    record.level:SetShown(shown)
    record.title:SetShown(shown)
    record.progress:SetShown(shown)
    record.visible = shown
end

local function RestoreRow(record)
    ShowColumns(record, false)
    if record.nativeHidden then
        record.nativeHidden = nil
        if Safety.Read(record.original, "IsShown") == false then record.original:Show() end
    end
end

local function CopyTitleColor(record)
    local r, g, b = Safety.ReadColor(record.original, "GetTextColor")
    if r then record.title:SetTextColor(r, g, b, 1) end
end

local function RefreshTitle(row)
    local record = rows[row]
    if record and record.visible and CanPaint(row) then CopyTitleColor(record) end
end

local function HideNativeTitle(record)
    -- Native hover and skin recolors write text alpha. Keep visibility separate
    -- from color so a repaint cannot reveal a second title or dim our copy.
    if Safety.Read(record.original, "IsShown") == true then
        record.original:Hide()
        record.nativeHidden = true
    end
end

function Quests.PaintRow(row, state, implicit)
    local record = rows[row]
    if not Compact() or not state.active then
        if record and CanPaint(row, nil, implicit) then RestoreRow(record) end
        return
    end
    if not CanPaint(row, nil, implicit) then return end
    if Safety.Read(row, "IsVisible") ~= true then
        if record then ShowColumns(record, false) end
        return
    end
    local info = Plain(Safety.Field(row, "info"))
    local questID = type(info) == "table" and Plain(info.questID)
    local index = Plain(Safety.Field(row, "questLogIndex"))
    if type(questID) ~= "number" or type(index) ~= "number" then
        if record then RestoreRow(record) end
        return
    end
    local original = Safety.Field(row, "Text")
    if not original then return end
    local title = DecoratedTitle(original, info)
    if type(title) ~= "string" then
        if record then RestoreRow(record) end
        return
    end
    if not record then
        record = CreateColumns(row, original)
        row:HookScript("OnEnter", RefreshTitle)
        row:HookScript("OnLeave", RefreshTitle)
    end
    record.state = state
    UpdateFont(record)
    local level = Plain(info.difficultyLevel)
    if type(level) ~= "number" then level = Plain(info.level) end
    level = type(level) == "number" and level > 0 and level or ""
    local progress = Progress(questID, index)
    if record.levelValue ~= level then
        record.level:SetText(level)
        record.levelValue = level
    end
    if record.titleValue ~= title then
        record.title:SetText(title)
        record.titleValue = title
    end
    if record.progressValue ~= progress then
        record.progress:SetText(progress)
        record.progressValue = progress
    end
    CopyTitleColor(record)
    record.level:SetTextColor(NS.Theme.GetColor("text"))
    record.progress:SetTextColor(NS.Theme.GetColor("text"))
    HideNativeTitle(record)
    ShowColumns(record, true)
end

local function RefreshRows()
    for row, record in pairs(rows) do Quests.PaintRow(row, record.state) end
end

local function RefreshNow()
    if not NS.Client.isForever then SyncObjectives() end
    local compact, combat = Compact(), NS.IsCombatLocked()
    local implicit = not combat and not NS.SuiteCore().startingBeforeLockdown
    for state, scroll in pairs(contexts) do
        local list = state.questFolds
        if list and (list.stale or not combat) then list.reapply() end
        if compact then
            Kit.ForEachActive(Safety.Field(scroll, "titleFramePool"), FOLD_ROW_LIMIT, Quests.PaintRow, state, implicit)
        end
    end
    if not compact then RefreshRows() end
end

function Quests.Refresh()
    if refreshing then return end
    if NS.IsCombatLocked() and not HasCombatView() then
        NS.CombatGate.RunOrDefer(REPLAY, Quests.Refresh)
        return
    end
    refreshing = true
    Safety.Dispatch(RefreshNow)
    refreshing = false
end

local function HasVisibleList()
    for _, scroll in pairs(contexts) do
        if Safety.Read(scroll, "IsVisible") == true then return true end
    end
    return false
end

local function RefreshCombatLayout()
    combatRefreshQueued = false
    if HasCombatView() and HasVisibleList() then Quests.Refresh() end
end

-- Registry jobs wait for combat to end. This separate, coalesced pass touches
-- only the quest view's unprotected rows after Blizzard's native rebuild.
function Quests.QueueCombatRefresh()
    if combatRefreshQueued or not HasCombatView() or not HasVisibleList() then return end
    combatRefreshQueued = true
    C_Timer.After(0, RefreshCombatLayout)
end

function Quests.Activate(state, frame)
    if not next(contexts) then
        if not spokenOverlay then events:RegisterEvent("ADDON_LOADED") end
        events:RegisterEvent("PLAYER_REGEN_DISABLED")
        events:RegisterEvent("PLAYER_REGEN_ENABLED")
    end
    AttachSpoken()
    local scroll = Kit.Path(frame, "QuestLog", "QuestsFrame", "ScrollFrame")
    contexts[state] = scroll or false
    SyncObjectives()
    if CanPaint(scroll) then AttachFolds(scroll, state) end
end

function Quests.Release(state)
    ReleaseFolds(state)
    contexts[state] = nil
    for row, record in pairs(rows) do
        if record.state == state and CanPaint(row) then RestoreRow(record) end
    end
    if not next(contexts) then
        events:UnregisterEvent("ADDON_LOADED")
        events:UnregisterEvent("PLAYER_REGEN_DISABLED")
        events:UnregisterEvent("PLAYER_REGEN_ENABLED")
        RestoreObjectives()
    end
end

function Quests.SetLayout(value)
    if value ~= "blizzard" and value ~= "compact" then return false, "invalid-layout" end
    if not NS.DB or NS.IsCombatLocked() or NS.SuiteCore().startingBeforeLockdown then return false, "combat" end
    NS.DB.questLog = NS.DB.questLog or {}
    if NS.DB.questLog.layout == value then return false end
    NS.DB.questLog.layout = value
    Quests.Refresh()
    NS.Registry.NotifyListeners("quests", "layout")
    return true
end

local function IsLayoutSelected(value)
    return Quests.GetLayout() == value
end

local function SelectLayout(value)
    if not next(contexts) or NS.IsCombatLocked() or NS.SuiteCore().startingBeforeLockdown or IsLayoutSelected(value) then return end
    NS.SuiteCore().HostBridge.WithMenuHistory(NS.L["Quest list layout"], "suite:skin.questLog.layout", function()
        return Quests.SetLayout(value)
    end)
end

local function AddLayoutMenu(_, description)
    if not next(contexts) then return end
    description:CreateDivider()
    description:CreateTitle(NS.L["Quest list layout"])
    local enabled = not NS.IsCombatLocked() and not NS.SuiteCore().startingBeforeLockdown
    description:CreateRadio(NS.L["Blizzard"], IsLayoutSelected, SelectLayout, "blizzard"):SetEnabled(enabled)
    description:CreateRadio(NS.L["Compact"], IsLayoutSelected, SelectLayout, "compact"):SetEnabled(enabled)
end

-- Both clients tag the native quest log gear menu with this identifier.
Kit.ReadValues(Safety.Field(Menu, "ModifyMenu"), "MENU_QUEST_MAP_FRAME_SETTINGS", AddLayoutMenu)

local function OnSettings(_, domain)
    if domain == "profile" then Quests.Refresh() end
    if domain == "color" or domain == "theme" then RefreshRows() end
end
NS.Registry.AddListener(Quests, OnSettings)

local function RestoreCombatTitles()
    -- Only protected rows need native-title ownership before lockdown.
    -- Ordinary pooled rows keep their Compact columns and continue updating.
    for row, record in pairs(rows) do
        if Safety.GetProtection(row) and (record.visible or record.nativeHidden) and Safety.CanDecorate(row, true) then
            RestoreRow(record)
        end
    end
end

if not NS.Client.isForever then
    events:RegisterEvent("PLAYER_LOGOUT")
    events:RegisterEvent("CVAR_UPDATE")
end
events:SetScript("OnEvent", function(_, event, name, value)
    if event == "ADDON_LOADED" then
        if name == "Spoken_Quests" then
            AttachSpoken()
            local list = lists[QuestScrollFrame]
            if list and list.owner and (not NS.Client.isForever or list.owner.questMapReady) then DeferList(list) end
        end
    elseif event == "PLAYER_LOGOUT" then
        RestoreObjectives()
    elseif event == "PLAYER_REGEN_DISABLED" then
        RestoreCombatTitles()
    elseif event == "PLAYER_REGEN_ENABLED" then
        if not Compact() then return end
        for _, scroll in pairs(contexts) do
            if Safety.Read(scroll, "IsVisible") == true then return Quests.Refresh() end
        end
    elseif name and name:lower() == "showquestobjectivesinlog" then
        if not OwnCVarEvent(value) and originalObjectives ~= nil then
            -- A later native settings edit wins, including off/on/off.
            originalObjectives = nil
            yieldedObjectives = true
        end
    end
end)

local _, NS = ...

-- Compact presentation stays on Blizzard's pooled quest buttons. The native
-- objective CVar supplies their compact layout; owned labels add columns.
-- Native search, header collapse, tracking, links, menus and tooltips remain.
local Quests = {}
NS.WorldMapQuests = Quests
local Safety, Kit = NS.Safety, NS.AdapterKit
local rows, contexts = Kit.WeakSet(), Kit.WeakSet()
local lists, headers = Kit.WeakSet(), Kit.WeakSet()
local originalObjectives, yieldedObjectives, refreshing
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
    local original = originalObjectives
    originalObjectives = nil
    yieldedObjectives = nil
    if original ~= nil and GetCVar(CVAR) == "0" then WriteObjectives(original) end
end

local function SyncObjectives()
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
    if not Safety.CanDecorate(row, true) then return end
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

local function MaskTitle(row, list)
    local info = Plain(Safety.Field(row, "info"))
    local key = HeaderKey(Plain(Safety.Field(info, "header")))
    local hide = list.masking and key ~= nil and list.folded[key] == true
    local questID = Plain(Safety.Field(info, "questID"))
    if hide and type(questID) == "number" then list.hiddenQuests[questID] = true end
    if MaskRow(row, list, hide) and list.owner then Quests.PaintRow(row, list.owner) end
end

local function MaskObjective(row, list)
    local questID = Plain(Safety.Field(row, "questID"))
    MaskRow(row, list, type(questID) == "number" and list.hiddenQuests[questID] == true)
end

-- Native POI visibility scripts change the shared supertracking callbacks.
-- Keep the button shown and suppress only its artwork and mouse input.
local function MaskPin(pin, list)
    local questID = Safety.Read(pin, "GetQuestID")
    if type(questID) ~= "number" or not list.hiddenQuests[questID] or not Safety.CanDecorate(pin, true) then return end
    local record = list.hiddenPins[pin]
    if not record then
        local alpha = Safety.Read(pin, "GetAlpha")
        local clicks = Safety.Read(pin, "IsMouseClickEnabled")
        local motion = Safety.Read(pin, "IsMouseMotionEnabled")
        if type(alpha) ~= "number" or type(clicks) ~= "boolean" or type(motion) ~= "boolean" then return end
        record = { alpha = alpha, clicks = clicks, motion = motion }
        list.hiddenPins[pin] = record
        pin:SetAlpha(0)
        pin:SetMouseClickEnabled(false)
        pin:SetMouseMotionEnabled(false)
    end
    record.masked = true
end

local function RestoreUnmaskedPins(list)
    for pin, record in pairs(list.hiddenPins) do
        if record.masked then
            record.masked = nil
        elseif Safety.CanDecorate(pin, true) then
            pin:SetAlpha(record.alpha)
            pin:SetMouseClickEnabled(record.clicks)
            pin:SetMouseMotionEnabled(record.motion)
            list.hiddenPins[pin] = nil
        end
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
    if (override or record.disclosure) and nativeOpen and Safety.CanDecorate(button, true) then
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
    if button ~= "LeftButton" or not list.owner or NS.IsCombatLocked() or SearchActive(list) then return end
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
    if not list.owner or NS.IsCombatLocked() then return end
    local info = HeaderInfo(index)
    if HeaderKey(info) == key and Plain(Safety.Field(info, "isCollapsed")) == true then
        ExpandQuestHeader(index)
    end
    list.relayout()
end

local function TrackHeader(header, list, questInfo)
    local record = headers[header]
    if not record and list.owner and Safety.CanDecorate(header, true)
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
    list.changed = false
    Kit.ForEachActive(Safety.Field(list.scroll, "headerFramePool"), FOLD_ROW_LIMIT, TrackHeader, list, questInfo)
    if list.masking or next(list.hidden) then
        wipe(list.hiddenQuests)
        Kit.ForEachActive(Safety.Field(list.scroll, "titleFramePool"), FOLD_ROW_LIMIT, MaskTitle, list)
        local objectives = Safety.Field(list.scroll, "objectiveFramePool")
        Kit.ForEachActive(objectives, Safety.Read(objectives, "GetNumActive") or FOLD_ROW_LIMIT, MaskObjective, list)
        Kit.ForEachActive(Safety.Field(list.contents, "buttonPool"), FOLD_ROW_LIMIT, MaskPin, list)
    end
    RestoreUnmaskedPins(list)
    return list.changed
end

local function BeforeQuestLayout(scroll, displayState)
    local list = lists[scroll]
    if not list or not list.owner then return end
    -- Blizzard has reset its pools and is about to lay out shown rows.
    wipe(list.hidden)
    if NS.IsCombatLocked() then
        if next(list.folded) or next(list.hiddenPins) then
            NS.CombatGate.RunOrDefer(list, list.relayout)
        end
        return
    end
    ApplyFolds(list, Plain(Safety.Field(Plain(displayState), "questInfoContainer")))
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
            hiddenQuests = {}, hiddenPins = Kit.WeakSet(),
        }
        list.relayout = function()
            if not NS.IsCombatLocked() and Safety.CanDecorate(contents, true) and ApplyFolds(list) then
                ResizeQuestList(contents, layout)
            end
        end
        lists[scroll] = list
        Kit.HookFunction(scroll, "UpdateBackground", Safety.Isolated(BeforeQuestLayout))
        Kit.HookFunction(scroll, "ExpandHeaderForQuest", Safety.Isolated(RevealMapQuest))
    end
    state.questFolds, list.owner = list, state
    list.relayout()
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
    if record and record.visible and Safety.CanDecorate(row, true) then CopyTitleColor(record) end
end

local function HideNativeTitle(record)
    -- Native hover and skin recolors write text alpha. Keep visibility separate
    -- from color so a repaint cannot reveal a second title or dim our copy.
    if Safety.Read(record.original, "IsShown") == true then
        record.original:Hide()
        record.nativeHidden = true
    end
end

function Quests.PaintRow(row, state)
    if NS.IsCombatLocked() or NS.SuiteCore().startingBeforeLockdown then return end
    local record = rows[row]
    if not Compact() or not state.active then
        if record and Safety.CanDecorate(row, true) then RestoreRow(record) end
        return
    end
    if not Safety.CanDecorate(row, true) then return end
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
    record.level:SetText(type(level) == "number" and level > 0 and level or "")
    record.title:SetText(title)
    record.progress:SetText(Progress(questID, index))
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
    -- Blizzard rebuilds its own POI pool on quest-log updates. Forever also
    -- rebuilds on this CVar change. Keep native visibility scripts in that path.
    SyncObjectives()
    if not Compact() then return RefreshRows() end
    for state, scroll in pairs(contexts) do
        Kit.ForEachActive(Safety.Field(scroll, "titleFramePool"), FOLD_ROW_LIMIT, Quests.PaintRow, state)
    end
end

function Quests.Refresh()
    if refreshing then return end
    if NS.IsCombatLocked() then
        NS.CombatGate.RunOrDefer(REPLAY, Quests.Refresh)
        return
    end
    refreshing = true
    Safety.Dispatch(RefreshNow)
    refreshing = false
end

function Quests.Activate(state, frame)
    if not next(contexts) then
        events:RegisterEvent("PLAYER_REGEN_DISABLED")
        events:RegisterEvent("PLAYER_REGEN_ENABLED")
    end
    local scroll = Kit.Path(frame, "QuestLog", "QuestsFrame", "ScrollFrame")
    contexts[state] = scroll or false
    SyncObjectives()
    if Safety.CanDecorate(frame, true) then AttachFolds(scroll, state) end
end

function Quests.Release(state)
    ReleaseFolds(state)
    contexts[state] = nil
    for row, record in pairs(rows) do
        if record.state == state and Safety.CanDecorate(row, true) then RestoreRow(record) end
    end
    if not next(contexts) then
        events:UnregisterEvent("PLAYER_REGEN_DISABLED")
        events:UnregisterEvent("PLAYER_REGEN_ENABLED")
        RestoreObjectives()
    end
end

function Quests.SetLayout(value)
    if value ~= "blizzard" and value ~= "compact" then return false, "invalid-layout" end
    if not NS.DB or NS.IsCombatLocked() then return false, "combat" end
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
    if not next(contexts) or NS.IsCombatLocked() or IsLayoutSelected(value) then return end
    NS.SuiteCore().HostBridge.WithMenuHistory(NS.L["Quest list layout"], "suite:skin.questLog.layout", function()
        return Quests.SetLayout(value)
    end)
end

local function AddLayoutMenu(_, description)
    if not next(contexts) then return end
    description:CreateDivider()
    description:CreateTitle(NS.L["Quest list layout"])
    local enabled = not NS.IsCombatLocked()
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
    -- Blizzard can recycle hidden rows without showing their Text regions.
    -- Release Compact's visibility ownership before lockdown takes effect.
    for row, record in pairs(rows) do
        if (record.visible or record.nativeHidden) and Safety.CanDecorate(row, true) then
            RestoreRow(record)
        end
    end
end

events:RegisterEvent("PLAYER_LOGOUT")
events:RegisterEvent("CVAR_UPDATE")
events:SetScript("OnEvent", function(_, event, name, value)
    if event == "PLAYER_LOGOUT" then
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

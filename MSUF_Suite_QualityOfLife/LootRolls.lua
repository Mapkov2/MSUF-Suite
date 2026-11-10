local _, P = ...
local NS, S = P.NS, P.Suite
local Data, View = P.LootRollData, P.LootRollView
local ID = "lootRolls"
local IN_COMBAT = { inCombat = true }
local MAX_TRACKED, RESULT_WAIT = 48, 8
local BUTTON_KEYS = { "NeedButton", "GreedButton", "TransmogButton", "DisenchantButton", "PassButton" }
local M = {}
local Flush, RetryItems, WatchItems

local function PublicTable(value)
    return S.Public(value) and type(value) == "table"
end

local ACTION_NAMES = { [0] = "Pass", "Need", "Greed", "Disenchant", "Transmog" }

local function ResultText(entry, short, detailed)
    local name = entry.statusName or S.Text("Unknown")
    local action = entry.statusChoice and ACTION_NAMES[entry.statusChoice]
    if action and S.Finite(entry.statusRoll) then
        return S.Text(detailed):format(name, S.Text(action), entry.statusRoll)
    end
    return S.Text(short):format(name)
end

local function SetStatus(entry)
    if entry.status == "winner" then
        entry.statusText = ResultText(entry, "Winner: %s", "Winner: %s (%s %d)")
    elseif entry.status == "leader" then
        entry.statusText = ResultText(entry, "Current leader: %s", "Current leader: %s (%s %d)")
    elseif entry.status == "allPassed" then
        entry.statusText = S.Text("Everyone passed")
    elseif entry.choice or entry.cancelled then
        entry.statusText = S.Text("Waiting for result")
    else
        entry.statusText = nil
    end
end

local function Schedule(self)
    if self.active then self.context:After(0, Flush) end
end

local function RestoreNative(self, record)
    if not record.muted then return end
    self.context:Unmute(record.frame)
    for _, control in ipairs(record.controls) do
        self.context:RestoreProperty(control, "EnableMouse")
    end
    record.muted = nil
end

local function PlainFrame(frame)
    if not frame or NS.Safety.IsForbidden(frame) then return false end
    local protected = frame:IsProtected()
    return S.Public(protected) and protected == false
end

local function NativeControls(frame)
    local result = { frame }
    local owner = frame.LootButtonContainer or frame
    if frame.IconFrame then result[#result + 1] = frame.IconFrame end
    for _, key in ipairs(BUTTON_KEYS) do
        if owner[key] then result[#result + 1] = owner[key] end
    end
    return result
end

local function SetNative(self, record, hidden)
    if not hidden then return RestoreNative(self, record) end
    for _, control in ipairs(record.controls) do
        if not PlainFrame(control) then return RestoreNative(self, record) end
    end
    -- Preserve native Show/Hide and roll cleanup. The shared shown mute host
    -- suppresses rendering; explicit child input ownership prevents ghost clicks.
    if not self.context:Mute(record.frame) then return end
    for _, control in ipairs(record.controls) do
        self.context:UnprotectedProperty(control, "IsMouseEnabled", "EnableMouse", false)
    end
    record.muted = true
end

local function NativeShown()
    Schedule(M)
end

local function AttachNative(self)
    local count = 0
    for index = 1, 4 do
        local frame = _G["GroupLootFrame" .. index]
        if PlainFrame(frame) then
            count = count + 1
            if not self.native[frame] then
                self.native[frame] = { frame = frame, controls = NativeControls(frame) }
                frame:HookScript("OnShow", NativeShown)
                frame:HookScript("OnHide", NativeShown)
            end
        end
    end
    if count == 4 then self.context:RemoveEvent("ADDON_LOADED") end
end

local function AddRoll(self, rollID, duration, now)
    if not S.Finite(rollID) or rollID <= 0 then return end
    if self.rolls[rollID] then return end
    local entry = Data.ReadRoll(rollID, duration, now)
    if not entry then
        self.pending[rollID] = S.Finite(duration) and duration or 0
        return
    end
    if #self.order >= MAX_TRACKED then return end
    self.pending[rollID] = nil
    self.rolls[rollID] = entry
    self.order[#self.order + 1] = entry
end

local function SeedRolls(self)
    local ids = GetActiveLootRollIDs()
    if not PublicTable(ids) then return end
    local now = GetTime()
    for index = 1, math.min(#ids, MAX_TRACKED) do AddRoll(self, ids[index], nil, now) end
end

local function IgnoreHistory(self, token)
    if self.ignoredHistory[token] then return end
    self.ignoredHistory[token] = true
    self.ignoredOrder[#self.ignoredOrder + 1] = token
    if #self.ignoredOrder > 1024 then
        self.ignoredHistory[table.remove(self.ignoredOrder, 1)] = nil
    end
end

local function StoreDrop(self, encounterID, key)
    local entry = Data.ReadDrop(encounterID, key)
    if not entry then return end
    local token = tostring(entry.encounterID) .. ":" .. tostring(entry.lootKey)
    if self.ignoredHistory[token] then return end
    if self.seedingHistory and entry.finished then
        IgnoreHistory(self, token)
        return
    end
    local old = self.histories[token]
    entry.token = token
    entry.removeAt = old and old.removeAt
    if entry.finished and not entry.removeAt then entry.removeAt = GetTime() + self.config.resultSeconds end
    if not old then
        if #self.historyOrder >= MAX_TRACKED then
            local first = table.remove(self.historyOrder, 1)
            self.histories[first] = nil
        end
        self.historyOrder[#self.historyOrder + 1] = token
    end
    self.histories[token] = entry
    SetStatus(entry)
end

local function RefreshEncounter(self, encounterID)
    Data.EncounterKeys(encounterID, self.keys)
    for _, key in ipairs(self.keys) do StoreDrop(self, encounterID, key) end
end

local function SeedHistory(self)
    self.seedingHistory = true
    Data.EncounterIDs(self.encounters)
    for _, id in ipairs(self.encounters) do RefreshEncounter(self, id) end
    self.seedingHistory = nil
end

local function HistoryFor(self, link)
    local match, count, complete = nil, 0, 0
    for _, token in ipairs(self.historyOrder) do
        local history = self.histories[token]
        if history and history.link == link then
            match, count = history, count + 1
            if history.finished then complete = complete + 1 end
        end
    end
    return match, count, complete
end

local function RollCount(self, link)
    local count = 0
    for _, entry in ipairs(self.order) do
        if entry.link == link then count = count + 1 end
    end
    return count
end

local function BindHistory(self, now)
    for _, token in ipairs(self.historyOrder) do
        local entry = self.histories[token]
        if entry then entry.attached = nil end
    end
    for _, entry in ipairs(self.order) do
        local history, count, complete = HistoryFor(self, entry.link)
        local rolls = RollCount(self, entry.link)
        entry.counts, entry.rollNames = nil, nil
        entry.finished, entry.status, entry.statusName, entry.statusRoll = nil, nil, nil, nil
        if entry.link and (count > 1 or rolls > 1) then self.ambiguousLinks[entry.link] = true end
        if history and count == 1 and rolls == 1 and not self.ambiguousLinks[entry.link] then
            history.attached = true
            entry.counts, entry.rollNames = history.counts, history.rollNames
            entry.finished, entry.status = history.finished, history.status
            entry.statusName, entry.statusRoll, entry.statusChoice = history.statusName, history.statusRoll, history.statusChoice
            if history.selfChoice ~= nil then entry.choice = history.selfChoice end
            entry.removeAt = history.removeAt
        elseif entry.cancelled and count >= rolls and complete == count and count > 0 then
            -- Equal hyperlinks carry no native rollID. Show each history key
            -- independently instead of assigning somebody else's winner.
            entry.removeAt = now
        end
        SetStatus(entry)
        if not entry.removeAt and entry.endsAt then entry.removeAt = entry.endsAt + RESULT_WAIT end
    end
end

local function Purge(self, now)
    local changed = false
    for index = #self.order, 1, -1 do
        local entry = self.order[index]
        if entry.removeAt and entry.removeAt <= now then
            self.rolls[entry.rollID] = nil
            table.remove(self.order, index)
            changed = true
        end
    end
    for index = #self.historyOrder, 1, -1 do
        local token = self.historyOrder[index]
        local entry = self.histories[token]
        if entry and entry.removeAt and entry.removeAt <= now then
            if entry.finished then IgnoreHistory(self, token) end
            self.histories[token] = nil
            table.remove(self.historyOrder, index)
            changed = true
        end
    end
    for link in pairs(self.ambiguousLinks) do
        local _, count = HistoryFor(self, link)
        if count == 0 and RollCount(self, link) == 0 then self.ambiguousLinks[link] = nil end
    end
    return changed
end

local function NextExpiry(self)
    local deadline
    for _, entry in ipairs(self.order) do
        if entry.removeAt and (not deadline or entry.removeAt < deadline) then deadline = entry.removeAt end
    end
    for _, token in ipairs(self.historyOrder) do
        local entry = self.histories[token]
        if entry and entry.removeAt and (not deadline or entry.removeAt < deadline) then deadline = entry.removeAt end
    end
    self.nextExpiry = deadline
end

local function Append(self, entry)
    if #self.visibleEntries < self.config.maxRows then
        self.visibleEntries[#self.visibleEntries + 1] = entry
    end
end

local function SelectRows(self)
    for index = #self.visibleEntries, 1, -1 do self.visibleEntries[index] = nil end
    -- Unanswered choices always precede waiting/results. Overflow keeps its
    -- native window, so limiting the custom stack cannot hide a decision.
    for _, entry in ipairs(self.order) do
        if not entry.choice and not entry.cancelled and not entry.finished then Append(self, entry) end
    end
    for _, entry in ipairs(self.order) do
        if not entry.finished and (entry.choice or entry.cancelled) then Append(self, entry) end
    end
    if not self.config.showResults then return end
    for _, entry in ipairs(self.order) do
        if entry.finished then Append(self, entry) end
    end
    for _, token in ipairs(self.historyOrder) do
        local entry = self.histories[token]
        if entry and entry.finished and not entry.attached then Append(self, entry) end
    end
end

local function NativeVisible(self, rollID)
    for _, entry in ipairs(self.visibleEntries) do
        if entry.rollID == rollID and not entry.choice and not entry.cancelled and not entry.finished then return true end
    end
    return false
end

local function Samples()
    return {
        { name = S.Text("Example equipment"), icon = "Interface\\Icons\\INV_Sword_04",
            quality = 4, itemLevel = 120, count = 1, bindOnPickUp = true,
            canNeed = true, canGreed = true, counts = { [1] = 2, [2] = 3, [0] = 1 },
            remaining = 42 },
        { name = S.Text("Example equipment"), icon = "Interface\\Icons\\INV_Misc_QuestionMark",
            quality = 3, count = 1, canNeed = true, canGreed = true, choice = 1,
            statusText = S.Text("Waiting for result") },
        { name = S.Text("Example equipment"), icon = "Interface\\Icons\\INV_Shield_04",
            quality = 4, count = 1, finished = true,
            statusText = S.Text("Winner: %s"):format(S.Text("Example player")) },
    }
end

local function Tick(_, elapsed)
    if not M.active then return end
    M.tickElapsed = (M.tickElapsed or 0) + elapsed
    if M.tickElapsed < .1 then return end
    M.tickElapsed = 0
    local now = GetTime()
    if M.nextExpiry and now >= M.nextExpiry then
        Flush(M)
    else
        View.Tick(M, now)
    end
end

Flush = function(self)
    if not self.active then return end
    AttachNative(self)
    local now = GetTime()
    Purge(self, now)
    BindHistory(self, now)
    if Purge(self, now) then BindHistory(self, now) end
    self.visibleEntries = self.liveEntries
    SelectRows(self)
    NextExpiry(self)
    WatchItems(self)
    local pad = S.GamepadUI()
    if S.editMode and #self.visibleEntries == 0 and not pad then
        self.sampleEntries = self.sampleEntries or Samples()
        self.visibleEntries = self.sampleEntries
        self.showingSamples = true
    elseif self.showingSamples then
        self.showingSamples = nil
    end
    View.Paint(self)
    View.Tick(self, now)
    self.host:SetShown(not pad and #self.visibleEntries > 0)
    for frame, record in pairs(self.native) do
        local rollID = frame.rollID
        local hidden = not pad and not S.editMode and S.Finite(rollID) and NativeVisible(self, rollID)
        SetNative(self, record, hidden)
    end
    self.host:SetScript("OnUpdate", not pad and (#self.order > 0 or self.nextExpiry ~= nil) and Tick or nil)
end

WatchItems = function(self)
    local needed = next(self.pending) ~= nil
    for _, entry in ipairs(self.order) do
        if self.config.showItemLevel and not entry.itemLevel then needed = true end
    end
    for _, token in ipairs(self.historyOrder) do
        local entry = self.histories[token]
        if entry and (not entry.icon or not entry.name or entry.name == entry.link) then needed = true end
    end
    if needed then self.context:Event("GET_ITEM_INFO_RECEIVED", RetryItems, IN_COMBAT)
    else
        self.context:RemoveEvent("GET_ITEM_INFO_RECEIVED")
        self.context:Cancel(RetryItems)
    end
end

RetryItems = function(self)
    if not self.active then return end
    local now = GetTime()
    for rollID, duration in pairs(self.pending) do AddRoll(self, rollID, duration, now) end
    for _, entry in ipairs(self.order) do
        local current = Data.ReadRoll(entry.rollID, nil, now)
        if current then
            entry.name, entry.icon, entry.itemLevel = current.name, current.icon, current.itemLevel
            entry.link, entry.quality = current.link, current.quality
        end
    end
    for _, token in ipairs(self.historyOrder) do
        local entry = self.histories[token]
        if entry and (not entry.icon or not entry.name or entry.name == entry.link) then
            StoreDrop(self, entry.encounterID, entry.lootKey)
        end
    end
    WatchItems(self)
    Schedule(self)
end

local function StartRoll(self, _, rollID, duration)
    AddRoll(self, rollID, duration, GetTime())
    if next(self.pending) then self.context:After(.2, RetryItems) end
    WatchItems(self)
    Schedule(self)
end

local function CancelRoll(self, _, rollID)
    if not S.Finite(rollID) then return end
    self.pending[rollID] = nil
    local entry = self.rolls[rollID]
    if entry then
        entry.cancelled = true
        entry.choice = entry.requestedChoice or entry.choice
        entry.removeAt = math.max(GetTime(), entry.endsAt or 0) + RESULT_WAIT
    end
    Schedule(self)
end

local function CancelAll(self)
    for _, entry in ipairs(self.order) do entry.removeAt = 0 end
    for key in pairs(self.pending) do self.pending[key] = nil end
    Schedule(self)
end

local function HistoryDrop(self, _, encounterID, key)
    StoreDrop(self, encounterID, key)
    Schedule(self)
end

local function HistoryEncounter(self, _, encounterID)
    RefreshEncounter(self, encounterID)
    Schedule(self)
end

local function ClearHistory(self)
    self.histories, self.historyOrder, self.ignoredHistory, self.ignoredOrder = {}, {}, {}, {}
    self.ambiguousLinks = {}
    Schedule(self)
end

local function InterfaceChanged(self)
    SeedRolls(self)
    Schedule(self)
end

function M:Choose(entry, rollType)
    if not self.active or S.editMode or S.GamepadUI() or not entry or not S.Finite(entry.rollID) then return end
    if self.rolls[entry.rollID] ~= entry or entry.choice or entry.cancelled or entry.finished then return end
    local live = Data.ReadRoll(entry.rollID, nil, GetTime())
    if not live or not S.Finite(rollType) then return end
    local allowed = rollType == 0 or rollType == 1 and live.canNeed or rollType == 2 and live.canGreed
        or rollType == 3 and live.canDisenchant or rollType == 4 and live.canTransmog
    if not allowed then return end
    entry.requestedChoice = rollType
    -- The native confirm popup remains in charge. Only CANCEL_LOOT_ROLL
    -- commits the visible choice, so cancelling that popup keeps buttons usable.
    RollOnLoot(entry.rollID, rollType)
end

function M:Enable()
    self.rolls, self.order, self.pending = {}, {}, {}
    self.histories, self.historyOrder = {}, {}
    self.visibleEntries, self.keys, self.encounters = {}, {}, {}
    self.liveEntries, self.ignoredHistory, self.ignoredOrder = self.visibleEntries, {}, {}
    self.ambiguousLinks = {}
    self.native = self.native or {}
    View.Create(self)
    self.context:Event("START_LOOT_ROLL", StartRoll, IN_COMBAT)
    self.context:Event("CANCEL_LOOT_ROLL", CancelRoll, IN_COMBAT)
    self.context:Event("CANCEL_ALL_LOOT_ROLLS", CancelAll, IN_COMBAT)
    self.context:Event("LOOT_HISTORY_UPDATE_DROP", HistoryDrop, IN_COMBAT)
    self.context:Event("LOOT_HISTORY_UPDATE_ENCOUNTER", HistoryEncounter, IN_COMBAT)
    self.context:Event("LOOT_HISTORY_CLEAR_HISTORY", ClearHistory, IN_COMBAT)
    self.context:Event("INPUT_DEVICE_INTERFACE_TRANSITION", InterfaceChanged, IN_COMBAT)
    self.context:Event("ADDON_LOADED", NativeShown, IN_COMBAT)
    AttachNative(self)
    SeedRolls(self)
    SeedHistory(self)
    WatchItems(self)
    Flush(self)
end

function M:Refresh()
    if self.showingSamples then self.visibleEntries = {} end
    Flush(self)
end

function M:Disable()
    for _, record in pairs(self.native or {}) do RestoreNative(self, record) end
    if self.host then
        self.host:SetScript("OnUpdate", nil)
        self.host:Hide()
    end
    self.nextExpiry, self.showingSamples = nil, nil
end

function M:RegisterMovers()
    S.RegisterOwnedMover(ID, "lootrolls", {
        label = "Loot roll window", order = 629,
        getFrame = function() return self.host end,
        xKey = "x", yKey = "y", pointKey = "point",
        point = function() return NS.AnchorPoints[self.config.point] or "CENTER" end,
        quickPosition = true, historyKeys = { "width", "rowHeight", "scale" },
        sizeKeys = { "width", "rowHeight", "scale" },
    })
end

function S.DrawLootRollPreview(parent, config, _, viewport)
    local view = parent.suiteLootRollPreview
    if not view then
        view = { previewParent = parent, visibleEntries = Samples() }
        parent.suiteLootRollPreview = view
    end
    view.config, view.previewViewport = config, viewport
    View.Paint(view)
    View.Tick(view, GetTime())
    return view.host
end

S.Install(ID, M)

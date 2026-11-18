local _, P = ...
local NS, S = P.NS, P.Suite

local ID = "worldQuestTab"
local M = { filter = "all" }
local Rewards, Tools = P.WorldQuestRewards, S.ToolListWindow
local Field, Finite, Text = S.PublicField, S.Finite, S.PublicText
local TABS = {
    { key = "all", label = "All" }, { key = "gold", label = "Gold" },
    { key = "reputation", label = "Reputation" }, { key = "currency", label = "Currency" },
    { key = "gear", label = "Gear" },
}
local QUEST_EVENTS = { "QUEST_POI_UPDATE", "QUEST_LOG_UPDATE", "QUEST_DATA_LOAD_RESULT", "QUEST_TURNED_IN" }

local function Available()
    return M.active and not NS.InCombat()
end

local function MapShown(map)
    if not map or NS.Safety.IsForbidden(map) then return false end
    local shown = map:IsVisible()
    return S.Public(shown) and shown == true
end

local function CurrentMapID(map)
    local id = map:GetMapID()
    return Finite(id) and id > 0 and id or nil
end

local function Readable(value)
    return S.Public(value) and type(value) == "table" and canaccesstable(value)
end

local function Earlier(a, b)
    if a.expires ~= b.expires then return (a.expires or math.huge) < (b.expires or math.huge) end
    if a.name ~= b.name then return a.name < b.name end
    return a.key < b.key
end

local function ReadRow(id, before, now)
    local isWorld = C_QuestLog.IsWorldQuest(id)
    if not S.Public(isWorld) or isWorld ~= true then return end
    local title, factionID = C_TaskQuest.GetQuestInfoByQuestID(id)
    local name = Text(title) or Text(C_QuestLog.GetTitleForQuestID(id))
    if not name then return end
    local remaining = C_TaskQuest.GetQuestTimeLeftSeconds(id)
    if Finite(remaining) and remaining <= 0 then return end
    local row = before or { key = id }
    row.name, row.factionID = name, Finite(factionID) and factionID or nil
    row.expires = Finite(remaining) and now + remaining or nil
    return row
end

local function Collect(self, mapID)
    local rows, byID = {}, {}
    local previous = mapID == self.mapID and self.byID or nil
    if not previous then self.requested = {} end
    self.mapID, self.rows, self.byID = mapID, rows, byID
    self.zone = nil
    if not mapID then return end
    local zone = C_Map.GetMapInfo(mapID)
    self.zone = Readable(zone) and Text(Field(zone, "name")) or nil
    local quests = C_TaskQuest.GetQuestsOnMap(mapID)
    if not Readable(quests) then return end
    local now = GetTime()
    for i = 1, #quests do
        local entry = quests[i]
        local id = Readable(entry) and Field(entry, "questID")
        if Finite(id) and id > 0 and byID[id] == nil then
            local row = ReadRow(id, previous and previous[id], now)
            byID[id] = row or false
            if row then rows[#rows + 1] = row end
        end
    end
    table.sort(rows, Earlier)
end

local function ReadRewards(self)
    self.waiting = false
    local requested = false
    for i = 1, #self.rows do
        local row = self.rows[i]
        if not row.classes then
            row.classes, row.rewardText, row.rewardSearch = Rewards.Read(row.key, row.factionID)
            if not row.classes then
                self.waiting = true
                if not self.requested[row.key] then
                    self.requested[row.key] = true
                    requested = true
                    C_TaskQuest.RequestPreloadRewardData(row.key)
                end
            end
        end
    end
    if requested then self.rewardCheckAt = GetTime() + 1
    elseif not self.waiting then self.rewardCheckAt = nil end
end

local function Flush()
    M.updateTimer = nil
    if not Available() or not Tools.IsOpen(M) then return end
    if not MapShown(M.map) then Tools.Close(M) return end
    local mapID = CurrentMapID(M.map)
    local scan = M.mapDirty or mapID ~= M.mapID
    if scan then Collect(M, mapID) end
    M.mapDirty = false
    if scan or M.waiting then ReadRewards(M) end
    Tools.Refresh(M)
end

-- One cancellable dispatch after the native map/quest event has returned.
local function Queue(self, mapDirty)
    if not Available() or not Tools.IsOpen(self) then return end
    if mapDirty then self.mapDirty = true end
    if not self.updateTimer then self.updateTimer = C_Timer.NewTimer(0, Flush) end
end

local function QuestEvent(self, event, id, success)
    if not Available() or not self.byID then return end
    if event == "QUEST_POI_UPDATE" then
        Queue(self, true)
    elseif event == "QUEST_LOG_UPDATE" then
        if self.waiting then Queue(self) end
    elseif Finite(id) and self.byID[id] ~= nil then
        local row = self.byID[id]
        if event == "QUEST_TURNED_IN" then Queue(self, true)
        elseif S.Public(success) and success == true and (not row or not row.classes) then Queue(self, not row) end
    end
end

-- Retail 297d7aaa: native WorldQuestDataProvider emits WorldQuestsUpdate on
-- browser-map changes. Subscribe only while our list is open. In particular
-- do not hook SetMapID, which can run before the native map OnShow is ready.
local function MapUpdated(self, count)
    if not Available() or self.mapDirty or not Tools.IsOpen(self) then return end
    local visibleCount = Finite(count) and count or nil
    local countChanged = visibleCount and self.nativeCount and visibleCount ~= self.nativeCount
    self.nativeCount = visibleCount
    if countChanged or CurrentMapID(self.map) ~= self.mapID then
        Queue(self, true)
        return
    end
    if not self.clockAt and not self.rewardCheckAt then return end
    local now = GetTime()
    if self.rewardCheckAt and now >= self.rewardCheckAt then
        self.rewardCheckAt = nil
        Queue(self)
    elseif self.clockAt and now >= self.clockAt then Queue(self) end
end

local function Closed(self)
    for i = 1, #QUEST_EVENTS do self.context:RemoveEvent(QUEST_EVENTS[i]) end
    if self.updateTimer then self.updateTimer:Cancel() self.updateTimer = nil end
    if self.watchedMap then
        self.watchedMap:UnregisterCallback("WorldQuestsUpdate", self)
        self.watchedMap = nil
    end
    self.rows, self.byID, self.requested, self.mapID, self.zone = nil, nil, nil, nil, nil
    self.waiting, self.mapDirty = false, false
    self.nativeCount, self.clockAt, self.rewardCheckAt = nil, nil, nil
end

local function RowDetail(row, time)
    local reward = row.rewardText
    if not reward then reward = S.Text("Quest rewards are loading.") end
    if reward == "" then reward = S.Text("Reward information unavailable") end
    row.label = time and S.Text("%s · %s remaining"):format(row.name, S.ClockText(time, true)) or row.name
    row.detail, row.search = reward, row.name .. " " .. (row.rewardSearch or "")
end

local function Rows(self)
    local rows, now, nextExpiry = {}, GetTime(), math.huge
    for i = 1, #self.rows do
        local row = self.rows[i]
        local time = row.expires and row.expires - now
        if (not time or time > 0) and (self.filter == "all" or row.classes and row.classes[self.filter]) then
            RowDetail(row, time)
            rows[#rows + 1] = row
            if time then nextExpiry = math.min(nextExpiry, row.expires) end
        end
    end
    self.clockAt = nextExpiry < math.huge and math.min(now + 30, nextExpiry) or nil
    self.visibleCount = #rows
    return rows
end

local function Status(self)
    local text = self.visibleCount == 0 and S.Text("No world quests match the selected map and filters.") or self.zone or ""
    if self.waiting then return text .. (text == "" and "" or " · ") .. S.Text("Quest rewards are loading.") end
    return text
end

local function Refresh(self)
    if not Available() or not MapShown(self.map) then return end
    self.mapID = nil
    Queue(self, true)
end

local function Track(self, row, window)
    if not row or not Available() or self.mapDirty or CurrentMapID(self.map) ~= self.mapID then return end
    local id = row.key
    local active = C_TaskQuest.IsActive(id)
    if not S.Public(active) or active ~= true or row.expires and row.expires <= GetTime() then
        window:SetStatus(S.Text("World quest finished or unavailable."))
        return
    end
    local watch = C_QuestLog.GetQuestWatchType(id)
    if not S.Public(watch) then return end
    -- Same automatic watch and super-track path as a Blizzard world quest pin.
    if watch ~= Enum.QuestWatchType.Manual then
        if not S.Dispatch(NS.Finish, QuestUtil.TrackWorldQuest, id, Enum.QuestWatchType.Automatic) then return end
    end
    S.Dispatch(NS.Finish, C_SuperTrack.SetSuperTrackedQuestID, id)
end

local SPEC = {
    title = "World quests", searchHint = "Search quests and rewards", rows = Rows, status = Status,
    help = "Filter by reward or select a quest to track it on the map. Shortest remaining time comes first.",
    empty = "Select a world quest to see its rewards.",
    valid = function(self) return MapShown(self.map) end, onHide = Closed, activate = Track, gamepad = true,
    tabs = TABS, currentTab = function(self) return self.filter end,
    selectTab = function(self, filter) self.filter = filter end,
    actions = {
        { label = "Track quest", enabled = function(_, row) return row ~= nil end, run = Track },
        { label = "Refresh", run = Refresh },
    },
}

function M:Open()
    if not Available() then return end
    local map = WorldMapFrame
    if not MapShown(map) and not S.ShowPanel("worldMap") then return end
    map = WorldMapFrame
    if not MapShown(map) then return end
    if Tools.IsOpen(self) then Tools.Close(self) return end
    self.map = map
    Collect(self, CurrentMapID(map))
    local window = Tools.Open(self, SPEC)
    if not window then Closed(self) return end
    for i = 1, #QUEST_EVENTS do self.context:Event(QUEST_EVENTS[i], QuestEvent) end
    self.watchedMap = map
    map:RegisterCallback("WorldQuestsUpdate", MapUpdated, self)
    ReadRewards(self)
    Tools.Refresh(self)
end

local function ShowButton(self)
    if not Available() then return end
    local map = WorldMapFrame
    if not MapShown(map) then return end
    local canvas, border = map.ScrollContainer, map.BorderFrame
    if not canvas or not border or NS.Safety.IsForbidden(canvas) or NS.Safety.IsForbidden(border) then return end
    local button = self.button
    if not button then
        button = S.CreateFrame("Button", nil, UIParent, "UIPanelButtonTemplate")
        button:SetSize(124, 21)
        button:SetFrameStrata("HIGH")
        button:SetText(S.Text("World quests"))
        button:SetScript("OnClick", function() M:Open() end)
        self.button = button
    end
    button:ClearAllPoints()
    -- Leave the header's window controls and drag strip, the floor chooser
    -- (canvas left) and Blizzard tracking controls (canvas right) clickable.
    button:SetPoint("TOP", canvas, "TOP", 0, -5)
    button:SetFrameLevel(border:GetFrameLevel() + 2)
    button:Show()
end

local function Hide(self)
    if self.button then self.button:Hide() end
    Tools.Close(self)
end

local Resume
local function Suspend(self)
    Hide(self)
    self.context:RemoveCallback("WorldMapOnShow")
    self.context:RemoveCallback("WorldMapOnHide")
    self.context:RemoveEvent("PLAYER_REGEN_DISABLED")
    self.context:Event("PLAYER_REGEN_ENABLED", Resume)
end

Resume = function(self)
    if NS.InCombat() then return end
    self.context:RemoveEvent("PLAYER_REGEN_ENABLED")
    self.context:Event("PLAYER_REGEN_DISABLED", Suspend)
    self.context:Callback("WorldMapOnShow", ShowButton)
    self.context:Callback("WorldMapOnHide", Hide)
    ShowButton(self)
end

function M:Enable()
    if NS.InCombat() then Suspend(self) else Resume(self) end
end

function M:Refresh()
    if Tools.IsOpen(self) then Tools.Close(self) end
end

function M:Disable()
    Hide(self)
end

S.Install(ID, M)

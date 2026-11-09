local _, P = ...
local NS, S = P.NS, P.Suite
local Data, Radar, Arrow = P.GatheringRouteData, P.GatheringRadar, P.GatheringArrow
local ID, COMMAND = "gatheringRoutes", "MSUFSUITEGATHER"
local IN_COMBAT = { inCombat = true }
local TABS = { { key = 0, label = "All" } }
for kind, spec in ipairs(Data.types) do TABS[kind + 1] = { key = kind, label = spec.label } end

local M = { points = {}, ranked = {}, visited = {}, tracking = {}, castNames = {}, tab = 0, tabs = {}, kinds = {} }

local function OpenWorld(self)
    return not self.leaving and S.InstanceKind() == "world"
end

function M:CanOpen()
    return self.active == true and not NS.InCombat() and OpenWorld(self)
end

local function ClearGoal(self)
    local goal = self.goal
    if goal and goal.automatic and not goal.arrived then self.visited[goal.key] = nil end
    self.goal = nil
    self.radarX, self.radarY = nil, nil
end

local function UseMap(self, map)
    self.map, self.loadedMap = map, nil
    self.rows, self.nextRow = nil, nil
    if map and map ~= self.routeMap then
        self.routeMap, self.lastKey = map, nil
        wipe(self.visited)
        ClearGoal(self)
    end
    self.width, self.height = nil, nil
    self.radarX, self.radarY = nil, nil
    if not map then
        wipe(self.points)
        return
    end
    local width, height = C_Map.GetMapWorldSize(map)
    if S.Finite(width) and S.Finite(height) and width > 0 and height > 0 then
        self.width, self.height = width, height
    end
end

local function Sample(self)
    local raw = C_Map.GetBestMapForUnit("player")
    if not Data.MapID(raw) then
        self.rawMap = nil
        if self.map then UseMap(self) end
        return
    end
    if raw ~= self.rawMap then
        self.rawMap, self.zone = raw, Data.Zone(raw)
    end
    local map = self.zone
    local x, y = Data.PlayerXY(map)
    if x == nil and map ~= raw then
        map = raw
        x, y = Data.PlayerXY(raw)
    end
    if map ~= self.map then UseMap(self, map) end
    return x, y
end

local function EnsureNodes(self)
    local map = self.map
    if map == self.loadedMap then return end
    self.loadedMap = map
    self.rows, self.nextRow = nil, nil
    self.radarX, self.radarY = nil, nil
    self.autoPending = true
    Data.Load(self.points, map, self.kinds)
end

local function SetGoal(self, node, automatic)
    local key = self.map .. ":" .. node.key
    ClearGoal(self)
    self.goal = { map = self.map, key = node.key, kind = node.kind, x = node.x, y = node.y, automatic = automatic }
    self.lastKey, self.visited[node.key], self.rows = key, true, nil
    self.radarX, self.radarY = nil, nil
end

local function Eligible(self, node)
    return self.kinds[node.kind] and (self.tab == 0 or self.tab == node.kind)
end

local function Distance(self, node, x, y)
    local dx, dy = (x - node.x) * self.width, (y - node.y) * self.height
    return dx * dx + dy * dy
end

local function ChooseAutomatic(self, x, y)
    if not self.autoPending or x == nil or not self.width then return end
    self.autoPending = nil
    if self.goal and not self.goal.arrived then return end
    local nearest, best
    for _, node in ipairs(self.points) do
        if not self.visited[node.key] and Eligible(self, node) then
            local distance = Distance(self, node, x, y)
            if distance > Data.arrivalDistanceSquared and (not best or distance < best
                or distance == best and node.key < nearest.key) then
                nearest, best = node, distance
            end
        end
    end
    if nearest then SetGoal(self, nearest, true) end
end

local function Hide(self)
    Radar.Hide(self)
    Arrow.Hide(self)
end

local function Paint(self, x, y)
    if not self.autoPaused or self.config.radar then EnsureNodes(self) end
    if not self.autoPaused then
        ChooseAutomatic(self, x, y)
        local goal = self.goal
        local navigating = goal and not goal.arrived
        Arrow.Paint(self, x, y)
        if navigating and goal.arrived then
            self.autoPending = true
            ChooseAutomatic(self, x, y)
            if self.goal ~= goal then Arrow.Paint(self, x, y) end
        end
    else
        Arrow.Hide(self)
    end
    if self.config.radar then Radar.Paint(self, x, y) else Radar.Hide(self) end
end

local function Navigating(self)
    return (self.goal and not self.goal.arrived and (not self.map or self.goal.map == self.map))
end

local function TickInterval(self)
    if Navigating(self) then return .12 end
    if self.width and #self.points > 0 and (self.config.radar or not self.autoPaused and self.autoPending) then return .25 end
end

local LeaveWorld, SyncWorld, Tick
local function SyncTicker(self)
    local interval = TickInterval(self)
    if interval == self.interval then return end
    self.interval = interval
    if interval then self.context:Ticker(interval, Tick) else self.context:Cancel(Tick) end
end

Tick = function(self)
    if not OpenWorld(self) then return LeaveWorld(self) end
    Paint(self, Sample(self))
    SyncTicker(self)
end

local function SyncView(self)
    if not OpenWorld(self) then return LeaveWorld(self) end
    if not self.autoPaused or self.config.radar then
        Paint(self, Sample(self))
    else
        Hide(self)
    end
    SyncTicker(self)
    S.ToolListWindow.Refresh(self)
end

local function TrackingText(kind, active)
    local label = S.Text(Data.types[kind].label)
    if active == nil then return S.Text("%s tracking: unavailable"):format(label) end
    if active then return S.Text("%s tracking: active"):format(label) end
    return S.Text("%s tracking: off"):format(label)
end

local function FormatTracking(self)
    local parts = {}
    for kind in ipairs(Data.types) do
        if self.kinds[kind] and (self.tab == 0 or self.tab == kind) then
            parts[#parts + 1] = TrackingText(kind, self.tracking[kind])
        end
    end
    self.trackingLine = table.concat(parts, "  ·  ")
end

function M:TrackingStatus()
    return self.trackingLine or ""
end

local function TrackingChanged(self)
    if not self:CanOpen() then return end
    Data.ReadTracking(self.tracking)
    FormatTracking(self)
    S.ToolListWindow.Refresh(self)
end

local function TrackingCVarChanged(self, _, name)
    if S.Public(name) and name == "minimapTrackedInfov4" then TrackingChanged(self) end
end

-- Localized spell names cover cast ranks and the current and older Retail
-- Mining variants. A match with the successful cast GUID confirms the spot.
local MINING_SPELLS = { 2575, 195122, 423341, 471013 }
local function LearnNames(self)
    wipe(self.castNames)
    if self.kinds[1] then
        local herb = S.ReadText(C_Spell.GetSpellName, 2366)
        if herb then self.castNames[herb] = 1 end
    end
    if self.kinds[2] then
        for i = 1, NS.Client.isForever and 1 or #MINING_SPELLS do
            local name = S.ReadText(C_Spell.GetSpellName, MINING_SPELLS[i])
            if name then self.castNames[name] = 2 end
        end
    end
end

local function CastSent(self, _, _, target, guid, spell)
    self.castGUID, self.castKind, self.castTarget = nil, nil, nil
    if not OpenWorld(self) or not S.Finite(spell) or not S.PublicText(guid) then return end
    target = S.PublicText(target)
    if not target then return end
    local name = S.ReadText(C_Spell.GetSpellName, spell)
    local kind = name and self.castNames[name]
    if kind then self.castGUID, self.castKind, self.castTarget = guid, kind, target end
end

local function CastSucceeded(self, _, _, guid)
    if not self.castGUID or not S.Public(guid) or guid ~= self.castGUID then return end
    local kind, target = self.castKind, self.castTarget
    self.castGUID, self.castKind, self.castTarget = nil, nil, nil
    if not OpenWorld(self) then return end
    local x, y = Sample(self)
    if x == nil then return end
    local _, changed = Data.Save(self.map, kind, x, y, target)
    if not changed then return end
    self.loadedMap = nil
    SyncView(self)
end

local function RecordEvents(self)
    if self.config.record and (self.kinds[1] or self.kinds[2]) then
        LearnNames(self)
        self.context:Event("UNIT_SPELLCAST_SENT", CastSent, IN_COMBAT, "player")
        self.context:Event("UNIT_SPELLCAST_SUCCEEDED", CastSucceeded, IN_COMBAT, "player")
    else
        self.castGUID, self.castKind, self.castTarget = nil, nil, nil
        self.context:RemoveEvent("UNIT_SPELLCAST_SENT")
        self.context:RemoveEvent("UNIT_SPELLCAST_SUCCEEDED")
    end
end

local function AddonLoaded(self, _, name)
    if S.Public(name) and name == "GatherMate2" then
        self.loadedMap = nil
        SyncView(self)
    end
end

local function ZoneChanged(self)
    if not OpenWorld(self) then return LeaveWorld(self) end
    self.context:After(0, SyncWorld)
end

local WORLD_EVENTS = {
    { "ADDON_LOADED", AddonLoaded, IN_COMBAT },
    { "ZONE_CHANGED", ZoneChanged, IN_COMBAT },
    { "MINIMAP_UPDATE_TRACKING", TrackingChanged },
    { "SPELLS_CHANGED", TrackingChanged },
    { "CVAR_UPDATE", TrackingCVarChanged },
}

LeaveWorld = function(self)
    self.context:Cancel(Tick)
    self.context:Cancel(SyncWorld)
    ClearGoal(self)
    if self.world then
        for _, row in ipairs(WORLD_EVENTS) do self.context:RemoveEvent(row[1]) end
        self.context:RemoveEvent("UNIT_SPELLCAST_SENT")
        self.context:RemoveEvent("UNIT_SPELLCAST_SUCCEEDED")
    end
    self.world, self.interval, self.routeMap, self.lastKey = nil, nil, nil, nil
    self.rawMap, self.castGUID, self.castKind, self.castTarget = nil, nil, nil, nil
    UseMap(self)
    wipe(self.ranked)
    wipe(self.visited)
    Hide(self)
    S.ToolListWindow.Close(self)
end

SyncWorld = function(self)
    if not OpenWorld(self) then return LeaveWorld(self) end
    if not self.world then
        self.world = true
        for _, row in ipairs(WORLD_EVENTS) do self.context:Event(row[1], row[2], row[3]) end
        RecordEvents(self)
        TrackingChanged(self)
    end
    SyncView(self)
end

local function Entered(self)
    self.leaving = nil
    SyncWorld(self)
end

local function Leaving(self)
    self.leaving = true
    LeaveWorld(self)
end

local function Nearer(a, b)
    return a.distance == b.distance and a.key < b.key or a.distance < b.distance
end

local function Rows(self)
    if not self:CanOpen() then return end
    local x, y = Sample(self)
    if x == nil or not self.width then
        self.rows, self.nextRow = nil, nil
        return
    end
    EnsureNodes(self)
    if self.rows and self.rowsX == x and self.rowsY == y then return self.rows end
    self.nextRow = nil
    local ranked, rows = self.ranked, {}
    wipe(ranked)
    for _, node in ipairs(self.points) do
        if Eligible(self, node) then
            node.distance = Distance(self, node, x, y)
            ranked[#ranked + 1] = node
        end
    end
    table.sort(ranked, Nearer)
    local firstUnselected
    for i = 1, math.min(#ranked, 100) do
        local node = ranked[i]
        local kind = S.Text(Data.types[node.kind].label)
        local meters = math.floor(math.sqrt(node.distance) * Data.yardsToMeters + .5)
        local label = ("%s · %d m"):format(node.name or kind, meters)
        local detail = ("%s · %.1f, %.1f"):format(kind, node.x * 100, node.y * 100)
        local row = { key = self.map .. ":" .. node.key, map = self.map, node = node,
            label = label, detail = detail, search = label .. " " .. detail }
        rows[i] = row
        if row.key ~= self.lastKey then
            firstUnselected = firstUnselected or row
            if not self.nextRow and not self.visited[node.key] then self.nextRow = row end
        end
    end
    self.nextRow = self.nextRow or firstUnselected
    self.rows, self.rowsX, self.rowsY = rows, x, y
    return rows
end

local function Selected(_, row) return row ~= nil end
local function HasNext(self) return self.nextRow ~= nil end
local function CanSave(self) return self.tab ~= 0 end

local function Guide(self, row, window)
    if not self:CanOpen() or row.map ~= self.map or not self.kinds[row.node.kind] then return end
    self.autoPaused, self.autoPending = nil, nil
    SetGoal(self, row.node)
    window:Hide()
    SyncView(self)
end

local function GuideNext(self, _, window)
    local row = self.nextRow
    if not row then return end
    if self.visited[row.node.key] then wipe(self.visited) end
    Guide(self, row, window)
end

local function SetWaypoint(self, row, window)
    if not self:CanOpen() or row.map ~= self.map then return end
    local allowed = C_Map.CanSetUserWaypointOnMap(row.map)
    if not S.Public(allowed) or allowed ~= true then
        window:SetStatus(S.Text("This map does not support waypoints."))
        return
    end
    local node = row.node
    local placed = C_Map.SetUserWaypoint(UiMapPoint.CreateFromCoordinates(row.map, node.x, node.y))
    if not S.Public(placed) or placed ~= true then window:SetStatus(S.Text("The waypoint could not be activated.")) end
end

local function Save(self, window, map, x, y)
    if not self:CanOpen() or not self.kinds[self.tab] then return end
    if not Data.MapID(map) or not Data.ValidXY(x, y) then
        window:SetStatus(S.Text("Your position is not available on this map."))
    elseif Data.Save(map, self.tab, x, y) then
        self.loadedMap = nil
        SyncView(self)
        window:SetStatus(S.Text("Gathering spot saved."))
    else
        window:SetStatus(S.Text("The gathering spot could not be saved."))
    end
end

local function SaveHere(self, _, window)
    if not self:CanOpen() then return end
    local x, y = Sample(self)
    Save(self, window, self.map, x, y)
end

local function SavePin(self, _, window)
    if not self:CanOpen() then return end
    local pin = C_Map.GetUserWaypoint()
    if not S.Public(pin) or type(pin) ~= "table" or not canaccesstable(pin) or not Data.MapID(pin.uiMapID)
        or not S.Public(pin.position) or not pin.position then
        window:SetStatus(S.Text("Place a waypoint on Blizzard's map first."))
        return
    end
    Save(self, window, pin.uiMapID, pin.position:GetXY())
end

local function IsOwn(_, row) return row and row.node.source ~= nil end
local function Remove(self, row)
    local profile = NS.DB
    S.Confirm("suite-gathering-remove", { text = S.Text("Remove this saved gathering spot?"), callback = function()
        if profile ~= NS.DB or not self:CanOpen() then return end
        Data.Remove(row.map, row.node.source)
        if self.goal and self.goal.map == row.map and self.goal.key == row.node.key then ClearGoal(self) end
        self.loadedMap = nil
        SyncView(self)
    end })
end

local function CurrentTab(self) return self.tab end
local function SelectTab(self, key)
    self.tab = key
    self.rows = nil
    self.radarX, self.radarY = nil, nil
    if self.goal and self.goal.automatic and key ~= 0 and self.goal.kind ~= key then ClearGoal(self) end
    self.autoPending = true
    FormatTracking(self)
    SyncView(self)
end

local WINDOW = {
    title = "Known gathering spots",
    help = "Choose a nearby spot to set a waypoint. Save a position under a profession tab or use GatherMate2 data.",
    empty = "Known gathering spots appear here as you record or save them.",
    valid = M.CanOpen, tabs = M.tabs, rows = Rows, status = M.TrackingStatus, currentTab = CurrentTab, selectTab = SelectTab,
    actions = {
        { label = "Guide to this spot", enabled = Selected, run = Guide },
        { label = "Next gathering spot", enabled = HasNext, run = GuideNext },
        { label = "Set waypoint", enabled = Selected, run = SetWaypoint },
        { label = "Save my position", enabled = CanSave, run = SaveHere },
        { label = "Save map pin", enabled = CanSave, run = SavePin },
        { label = "Remove spot", enabled = IsOwn, run = Remove },
    },
}

function M:Open()
    if not self:CanOpen() then return end
    self.loadedMap = nil
    TrackingChanged(self)
    SyncView(self)
    return S.ToolListWindow.Open(self, WINDOW)
end

local function Slash(message)
    if not M.active or not OpenWorld(M) then return end
    if message:match("^%s*[Hh][Uu][Dd]%s*$") then
        if M:CanOpen() then S.Set(ID, "radar", not M.config.radar) end
    elseif message:match("^%s*[Ss][Tt][Oo][Pp]%s*$") then
        M.autoPaused = true
        ClearGoal(M)
        SyncView(M)
    else
        M:Open()
    end
end

function M:Enable()
    S.RegisterSlash(COMMAND, Slash, "/msufgather")
    self.context:Event("PLAYER_ENTERING_WORLD", Entered, IN_COMBAT)
    self.context:Event("PLAYER_LEAVING_WORLD", Leaving, IN_COMBAT)
    self.context:Event("ZONE_CHANGED_NEW_AREA", ZoneChanged, IN_COMBAT)
    self:Refresh()
end

function M:Refresh()
    if self.profile ~= NS.DB then
        self.profile, self.tab, self.lastKey, self.autoPaused = NS.DB, 0, nil, nil
        ClearGoal(self)
        S.ToolListWindow.Close(self)
        wipe(self.visited)
    end
    wipe(self.tabs)
    self.tabs[1] = TABS[1]
    for kind in ipairs(Data.types) do
        local enabled = Data.Enabled(self.config, kind)
        self.kinds[kind] = enabled
        if enabled then self.tabs[#self.tabs + 1] = TABS[kind + 1] end
    end
    if self.tab ~= 0 and not self.kinds[self.tab] then self.tab = 0 end
    if self.goal and not self.kinds[self.goal.kind] then ClearGoal(self) end
    self.loadedMap, self.radarX, self.radarY = nil, nil, nil
    if self.world and OpenWorld(self) then
        RecordEvents(self)
        TrackingChanged(self)
    end
    SyncWorld(self)
end

function M:Disable()
    S.UnregisterSlash(COMMAND, Slash)
    LeaveWorld(self)
    self.leaving, self.profile, self.autoPaused = nil, nil, nil
end

S.Install(ID, M)

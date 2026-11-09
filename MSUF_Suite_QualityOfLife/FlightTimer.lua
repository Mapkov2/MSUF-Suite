local _, P = ...
local NS, S = P.NS, P.Suite
local IN_COMBAT = { inCombat = true }
local ID, M = "flightTimer", { routes = {}, nodes = {} }
-- A chosen destination belongs to the next takeoff only this long; a choice
-- the flight master refused never starts a flight.
local REQUEST_WINDOW = 5
local function Text(value) return S.Public(value) and type(value) == "string" and value ~= "" end
local function PublicTable(value)
    return S.Public(value) and type(value) == "table" and canaccesstable(value)
end

local function ReadNodeIDs(self, system)
    if not self.flightTimes then return end
    -- FlightMapFrame uses GetTaxiMapID. The legacy TaxiFrame has no UiMap,
    -- so query the map of the flight master the player is talking to.
    local mapID = S.Public(system) and system ~= Enum.UIMapSystem.Taxi and GetTaxiMapID()
    if not S.Finite(mapID) or mapID <= 0 then mapID = C_Map.GetBestMapForUnit("player") end
    if not S.Finite(mapID) or mapID <= 0 then return end
    local entries = C_TaxiMap.GetAllTaxiNodes(mapID)
    if not PublicTable(entries) then return end
    for _, entry in ipairs(entries) do
        if PublicTable(entry) then
            local slot, nodeID, name, state = entry.slotIndex, entry.nodeID, entry.name, entry.state
            local transition = entry.isMapLayerTransition
            if S.Finite(slot) and slot > 0 and S.Finite(nodeID) and nodeID > 0 and Text(name)
                and S.Public(transition) and not transition then
                local node = self.nodes[slot]
                if not node then
                    node = { name = name }
                    self.nodes[slot] = node
                end
                node.id = nodeID
                if S.Public(state) and state == Enum.FlightPathState.Current then self.startNode = node end
            end
        end
    end
end

local function PairTime(times, from, to)
    local row = times[from]
    return row and row[to]
end

local function BuildRoute(self, index, node, segments)
    local start, times = self.startNode, self.flightTimes
    local names = { start and start.name or S.Text("Unknown") }
    local previous = times and start and start.id
    local total = previous and 0
    for part = 1, segments do
        -- Both native taxi maps use exact segment slots; positions can overlap.
        local slot = TaxiGetNodeSlot(index, part, false)
        local stop = S.Finite(slot) and self.nodes[slot]
        if stop and stop.name ~= names[#names] then names[#names + 1] = stop.name end
        if total then
            local nextID = stop and stop.id
            local seconds = PairTime(times, previous, nextID)
            total = seconds and total + seconds
            previous = nextID
        end
    end
    if node.name ~= names[#names] then names[#names + 1] = node.name end
    -- Prefer the selected legs when all are known. The endpoint measurement
    -- can still give an estimate when the table is missing an intermediate leg.
    local estimate = total and total > 0 and previous == node.id and total
        or times and start and PairTime(times, start.id, node.id)
    return { names = names, key = table.concat(names, " > "), destination = node.name, estimate = estimate }
end

local function ReadRoutes(self, system)
    wipe(self.nodes)
    wipe(self.routes)
    self.startNode = nil
    if NS.Client.isForever and not self.flightTimes then
        local faction = UnitFactionGroup("player")
        local loadTimes = Text(faction) and P.ForeverFlightTimes[faction]
        self.flightTimes = loadTimes and loadTimes()
    end
    local count = NumTaxiNodes()
    count = S.Finite(count) and math.min(256, count) or 0
    for i = 1, count do
        local name, kind = TaxiNodeName(i), TaxiNodeGetType(i)
        if Text(name) and S.Public(kind) then
            local node = { name = name }
            self.nodes[i] = node
            if kind == "CURRENT" then self.startNode = node end
        end
    end
    ReadNodeIDs(self, system)
    for index, node in pairs(self.nodes) do
        local routes = GetNumRoutes(index)
        if S.Finite(routes) and routes >= 0 and routes <= 32 then
            self.routes[index] = BuildRoute(self, index, node, routes)
        end
    end
end

local function Estimate(self, route)
    local learned = self.timings and self.timings[route.key]
    if S.Finite(learned) and learned > 0 then return learned end
    return route.estimate
end

-- The route line under a node's tooltip (setting routePreview).
local function AddRoute(self, index)
    local route = self.active and self.config.routePreview and self.routes[index]
    if route and not NS.Safety.IsForbidden(GameTooltip) then
        local estimate = Estimate(self, route)
        local line = route.key
        if estimate then
            line = string.format("%s (%d:%02d)", line, math.floor(estimate / 60), math.floor(estimate % 60))
        end
        GameTooltip:AddLine(line, 1, .85, .4, true)
        GameTooltip:Show()
    end
end

-- A FlightMapFrame node (Blizzard_FlightMap, FM_FlightPathDataProvider.lua
-- OnMouseEnter) fills the shared tooltip and then shows it, so the tooltip's
-- OnShow is where the line joins it: its owner is the pin, its slotIndex the
-- number TakeTaxiNode takes. Only a reachable node leads anywhere.
local FLIGHT_PIN = "FlightMap_FlightPointPinTemplate"
local function FlightPinShown(self, tooltip)
    if not self.mapOpen or not self.active or not self.config.routePreview then return end
    local owner = tooltip:GetOwner()
    if not owner or NS.Safety.IsForbidden(owner) or owner.pinTemplate ~= FLIGHT_PIN or owner.isMapLayerTransition then
        return
    end
    local data = owner.taxiNodeData
    if type(data) == "table" and data.state == Enum.FlightPathState.Reachable and S.Finite(data.slotIndex) then
        AddRoute(self, data.slotIndex)
    end
end

local LABELS = { "title", "route", "time", "status", "landText" }

local function Create(self)
    if self.host then return end
    local host = S.CreateFrame("Frame", nil, UIParent)
    host.background = S.CreateTexture(host, nil, "BACKGROUND")
    host.background:SetAllPoints()
    host.background:SetColorTexture(.035, .045, .06, .92)
    host.title = S.CreateFontString(host, nil, "OVERLAY")
    host.title:SetJustifyH("LEFT")
    host.title:SetWordWrap(true)
    host.title:SetMaxLines(2)
    host.route = S.CreateFontString(host, nil, "OVERLAY")
    host.route:SetJustifyH("LEFT")
    host.route:SetWordWrap(true)
    host.route:SetMaxLines(2)
    host.time = S.CreateFontString(host, nil, "OVERLAY")
    host.time:SetJustifyH("LEFT")
    host.time:SetWordWrap(false)
    host.status = S.CreateFontString(host, nil, "OVERLAY")
    host.status:SetJustifyH("LEFT")
    host.status:SetWordWrap(true)
    host.land = S.CreateFrame("Button", nil, host)
    local fill = S.CreateTexture(host.land, nil, "BACKGROUND")
    fill:SetAllPoints()
    fill:SetColorTexture(.16, .19, .23, .9)
    local highlight = S.CreateTexture(host.land, nil, "HIGHLIGHT")
    highlight:SetAllPoints()
    highlight:SetColorTexture(1, 1, 1, .08)
    host.landText = S.CreateFontString(host.land, nil, "OVERLAY")
    host.landText:SetPoint("LEFT", 6, 0)
    host.landText:SetPoint("RIGHT", -6, 0)
    host.landText:SetJustifyH("CENTER")
    host.landText:SetWordWrap(true)
    host.land:SetScript("OnClick", function()
        local taxi = UnitOnTaxi("player")
        if self.active and not self.earlyLanding and not S.editMode and S.Public(taxi) and taxi then
            TaxiRequestEarlyLanding()
        end
    end)
    self.duration = C_DurationUtil.CreateDuration()
    self.binding = C_DurationUtil.CreateDurationTextBinding()
    self.binding:SetFontString(host.time)
    self.binding:SetEnabled(false)
    -- The client's seconds formatter writes the units in the player's language.
    local formatter = C_StringUtil.CreateSecondsFormatter()
    formatter:SetDesiredUnitCount(2)
    formatter:SetMinInterval(Enum.SecondsFormatterInterval.Seconds)
    formatter:SetDefaultAbbreviation(Enum.SecondsFormatterAbbreviation.OneLetter)
    self.binding:SetFormatter(formatter)
    self.binding:SetExpiredText(S.Text("Arriving"))
    self.binding:SetUpdateInterval(1)
    self.host = host
end

-- Font/style choices are applied only on Enable and Refresh; taxi events
-- arrange the text only when the displayed route or flight state changes.
local function Layout(self)
    local c, host = self.config, self.host
    host:SetScale(c.scale / 100)
    host:ClearAllPoints()
    host:SetPoint("CENTER", UIParent, "CENTER", c.x, c.y)
    local _, class = UnitClass("player")
    local color = c.classColor and S.Public(class) and RAID_CLASS_COLORS[class]
    for i = 1, #LABELS do
        local label = host[LABELS[i]]
        local size = LABELS[i] == "time" and math.floor(c.fontSize * 1.5) or c.fontSize
        S.QoLStyleText(label, c, S.GlobalFontPath(), size)
        label:SetTextColor(color and color.r or 1, color and color.g or 1, color and color.b or 1)
    end
    host.landText:SetText(S.Text("Land at next stop"))
end

-- Only real intermediate stops get a second route line. Reserve measured text
-- heights before the timer/footer so large fonts and narrow widths cannot overlap.
local function Arrange(self)
    local c, host, route = self.config, self.host, self.current
    host.title:ClearAllPoints()
    host.title:SetPoint("TOPLEFT", 10, -8)
    host.title:SetWidth(c.width - 20)
    local y = 8 + host.title:GetStringHeight() + 6
    local stops = c.showStops and (route and #route.names > 2 or S.editMode and not route)
    host.route:SetShown(stops == true)
    if stops then
        host.route:ClearAllPoints()
        host.route:SetPoint("TOPLEFT", 10, -y)
        host.route:SetWidth(c.width - 20)
        y = y + host.route:GetStringHeight() + 6
    end
    host.time:ClearAllPoints()
    host.time:SetPoint("TOPLEFT", 10, -y)
    host.time:SetWidth(c.width - 20)
    y = y + math.ceil(c.fontSize * 1.5) + 4
    host.status:ClearAllPoints()
    host.status:SetPoint("TOPLEFT", 10, -y)
    host.status:SetWidth(c.width - 20)
    y = y + host.status:GetStringHeight() + 8
    host.land:ClearAllPoints()
    host.land:SetPoint("TOPLEFT", 10, -y)
    host.land:SetWidth(c.width - 20)
    local height = host.landText:GetStringHeight() + 10
    host.land:SetSize(c.width - 20, height)
    host:SetSize(c.width, y + height + 8)
end

local function Elapsed(self)
    if not self.active or not self.departed or not self.paintedVisible then return end
    local seconds = math.max(0, math.floor(GetTime() - self.departed))
    if seconds == self.elapsedSecond then return end
    self.elapsedSecond = seconds
    self.host.time:SetFormattedText("%d:%02d", math.floor(seconds / 60), seconds % 60)
end

local function StopElapsed(self)
    if self.elapsedTicker then
        self.elapsedTicker:Cancel()
        self.elapsedTicker = nil
    end
    self.elapsedSecond = nil
end

local function StopCountdown(self)
    if not self.countdownStart then return end
    self.countdownStart, self.countdownDuration = nil, nil
    self.binding:SetEnabled(false)
end

-- UNIT_FLAGS and the control events fire for much more than flights; the
-- display is drawn again only when what it shows changed (force: settings).
local function Update(self, taxi, force)
    if not self.active then return end
    local visible = not self.config.hideDisplay and (taxi or S.editMode)
    if not force and visible == self.paintedVisible and taxi == self.paintedTaxi
        and self.current == self.paintedRoute and self.departed == self.paintedDeparted then
        return
    end
    self.paintedVisible, self.paintedTaxi = visible, taxi
    self.paintedRoute, self.paintedDeparted = self.current, self.departed
    self.host:SetShown(visible)
    self.host.land:SetEnabled(taxi and not self.earlyLanding and not S.editMode)
    self.host.landText:SetAlpha(taxi and not self.earlyLanding and not S.editMode and 1 or .45)
    StopElapsed(self)
    if not visible then
        StopCountdown(self)
        return
    end
    local route = self.current
    local title = route and (route.names[1] .. " > " .. route.destination)
        or S.Text(S.editMode and "Flight route preview" or "Flight route unavailable")
    self.host.title:SetText(title)
    self.host.route:SetText(route and #route.names > 2 and table.concat(route.names, " > ", 2, #route.names - 1)
        or S.editMode and S.Text("Select a destination at the flight master.") or "")
    local estimate = route and Estimate(self, route)
    if estimate and self.departed and not self.earlyLanding then
        if self.countdownStart ~= self.departed or self.countdownDuration ~= estimate then
            self.duration:SetTimeFromEnd(self.departed + estimate, estimate)
            self.binding:SetDuration(self.duration)
            self.binding:SetEnabled(true)
            self.binding:UpdateFontString()
            self.countdownStart, self.countdownDuration = self.departed, estimate
        end
        self.host.status:SetText(S.Text("Remaining time"))
    else
        StopCountdown(self)
        self.host.status:SetText(S.Text(route and not self.earlyLanding and "Learning flight time" or "Elapsed time"))
        if taxi and self.departed then
            Elapsed(self)
            self.elapsedTicker = self.context:Ticker(1, Elapsed)
        else
            self.host.time:SetText("0:00")
            self.host.status:SetText(S.Text("Estimated time"))
        end
    end
    Arrange(self)
end
local function Forget(self)
    self.departed, self.current, self.earlyLanding, self.requested, self.onTaxi = nil, nil, nil, nil, nil
end

local function WatchFlags(self)
    self.context:Event("UNIT_FLAGS", self.TaxiState, nil, "player")
end

local function ExpireRequest(self)
    -- A matching control loss already started the trip. The taxi flag may lag.
    if self.departed then return end
    if self.requested then
        Forget(self)
        Update(self, false)
    end
    if not self.mapOpen then self.context:RemoveEvent("UNIT_FLAGS") end
end

local function MapOpened(self, _, system)
    self.mapOpen = true
    WatchFlags(self)
    ReadRoutes(self, system)
end

local function MapClosed(self)
    self.mapOpen = nil
    -- A taxi selection can close the map and change UNIT_FLAGS before the
    -- TakeTaxiNode post-hook runs. Keep observing until that call returns.
    if not self.onTaxi and not self.requested then self.context:After(0, ExpireRequest) end
end

local function Fresh(self, now)
    return self.requested ~= nil and now - self.requested <= REQUEST_WINDOW
end

-- Only a whole journey on a known route teaches its time.
local function Land(self, now)
    local elapsed = now - self.departed
    if self.current and self.onTaxi and not self.earlyLanding and elapsed > 3 then
        local times = self.timings
        if not times[self.current.key] then
            local count = 0
            for _ in pairs(times) do count = count + 1 end
            if count >= 200 then
                for key in pairs(times) do
                    times[key] = nil
                    break
                end
            end
        end
        times[self.current.key] = elapsed
    end
    Forget(self)
end

-- Control can be lost before the taxi flag appears. Sample the flag once per
-- event and read the clock only when starting or ending a flight.
function M:TaxiState(event)
    local taxi = UnitOnTaxi("player")
    if not S.Public(taxi) then
        if not event then Update(self, false, true) end
        return
    end
    if taxi then
        if self.onTaxi and event then return end
        if not self.departed then
            local now = GetTime()
            -- A flight seen without its takeoff (after a /reload) has no known route.
            if not Fresh(self, now) then self.current = nil end
            self.departed = now
        end
        if not self.onTaxi then
            self.onTaxi = true
            self.context:Cancel(ExpireRequest)
            WatchFlags(self)
        end
    elseif self.departed then
        -- Control lost after a choice ends only with the taxi flag or control again.
        if self.onTaxi or event == "PLAYER_CONTROL_GAINED" then
            Land(self, GetTime())
            self.context:Cancel(ExpireRequest)
            if not self.mapOpen then self.context:RemoveEvent("UNIT_FLAGS") end
        end
    elseif event == "PLAYER_CONTROL_LOST" and self.requested then
        local now = GetTime()
        if Fresh(self, now) then self.departed = now end
    end
    -- A direct call follows a configuration or button-state change.
    Update(self, taxi == true, not event)
end

local function Takeoff(self, index)
    local taxi = UnitOnTaxi("player")
    taxi = S.Public(taxi) and taxi == true
    local now = GetTime()
    -- A flag event inside TakeTaxiNode may have observed takeoff already.
    local observed = taxi and self.onTaxi and not self.current and self.departed
    Forget(self)
    self.current = S.Finite(index) and self.routes[index] or nil
    WatchFlags(self)
    if taxi then
        self.departed = observed and now - observed <= REQUEST_WINDOW and observed or now
        self.onTaxi = true
        self.context:Cancel(ExpireRequest)
    else
        self.requested = now
        self.context:After(REQUEST_WINDOW, ExpireRequest)
    end
    Update(self, taxi)
end

-- Learned times are runtime state of the active profile (S.ModuleState),
-- never exported or offered as settings.
local function Timings()
    local state = S.ModuleState(ID)
    if type(state.timings) ~= "table" then state.timings = {} end
    return state.timings
end

function M:Enable()
    self.timings = Timings()
    if not self.hooked then
        self.hooked = true
        hooksecurefunc("TakeTaxiNode", function(index)
            if self.active then Takeoff(self, index) end
        end)
        hooksecurefunc("TaxiRequestEarlyLanding", function()
            if self.active then
                self.earlyLanding = true
                self:TaxiState()
            end
        end)
        hooksecurefunc("TaxiNodeOnButtonEnter", function(button) AddRoute(self, button:GetID()) end)
        GameTooltip:HookScript("OnShow", function(tooltip) FlightPinShown(self, tooltip) end)
    end
    self.context:Event("TAXIMAP_OPENED", MapOpened, IN_COMBAT)
    self.context:Event("TAXIMAP_CLOSED", MapClosed, IN_COMBAT)
    self.context:Event("PLAYER_CONTROL_LOST", self.TaxiState, IN_COMBAT)
    self.context:Event("PLAYER_CONTROL_GAINED", self.TaxiState, IN_COMBAT)
    self.context:Event("PLAYER_ENTERING_WORLD", self.TaxiState, IN_COMBAT)
    Create(self)
    Layout(self)
    self:TaxiState()
end
-- The controller registers the movers after Enable and Refresh (S.RefreshEditMover).
function M:RegisterMovers()
    S.RegisterOwnedMover(ID, "flight", { label = "Flight route timer", order = 651, getFrame = function() return self.host end,
        xKey = "x", yKey = "y", sizeKeys = { "width" }, point = function() return "CENTER" end })
end
function M:Refresh()
    local timings = Timings()
    -- A profile switch mid-flight must not teach the new profile this trip.
    if self.timings ~= timings then Forget(self) end
    self.timings = timings
    Create(self)
    Layout(self)
    self:TaxiState()
end
function M:Disable()
    StopElapsed(self)
    Forget(self)
    self.mapOpen = nil
    self.context:Cancel(ExpireRequest)
    self.context:RemoveEvent("UNIT_FLAGS")
    wipe(self.routes)
    self.paintedVisible = nil
    if self.host then
        StopCountdown(self)
        self.host:Hide()
    end
end
S.Install(ID, M)

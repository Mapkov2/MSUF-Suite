local _, P = ...
local NS, S = P.NS, P.Suite
local MAX_ROUTE_LEGS = 32
local MAX_FLIGHT_AGE = 60 * 60

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
                if S.Public(state) then
                    node.reachable = state == Enum.FlightPathState.Reachable
                    if state == Enum.FlightPathState.Current then self.startNode = node end
                end
            end
        end
    end
end

local function PairTime(times, from, to)
    local row = from and times[from]
    return row and row[to]
end

local function BuildRoute(self, index, node, segments)
    local start, times = self.startNode, self.flightTimes
    local names = { start and start.name or S.Text("Unknown") }
    local legs = {}
    local previous = start and start.id
    local total = times and previous and 0
    for part = 1, segments do
        -- Both native taxi maps use exact segment slots; positions can overlap.
        local slot = TaxiGetNodeSlot(index, part, false)
        local stop = S.Finite(slot) and self.nodes[slot]
        local nextID = stop and stop.id
        local seconds = times and PairTime(times, previous, nextID)
        if stop and stop.name ~= names[#names] then
            names[#names + 1] = stop.name
            local isDestination, isLastLeg = stop == node, part == segments
            -- Only the uninterrupted prefix can identify a landing point.
            if start and part == #legs + 1 and isDestination == isLastLeg then
                legs[part] = stop
            end
        end
        total = total and seconds and total + seconds
        previous = nextID
    end
    if node.name ~= names[#names] then names[#names + 1] = node.name end
    -- Prefer the selected legs when all are known. The endpoint measurement
    -- can still give an estimate when the table is missing an intermediate leg.
    local estimate = total and total > 0 and previous == node.id and total
        or times and start and PairTime(times, start.id, node.id)
    return {
        names = names, key = table.concat(names, " > "), destination = node.name, estimate = estimate,
        legs = legs, segments = segments, startID = start and start.id,
    }
end

local function LoadFlightTimes(self)
    if NS.Client.isForever and not self.flightTimes then
        local faction = UnitFactionGroup("player")
        local loadTimes = Text(faction) and P.ForeverFlightTimes[faction]
        self.flightTimes = loadTimes and loadTimes()
    end
end

local function ReadRoutes(self, system)
    wipe(self.nodes)
    wipe(self.routes)
    self.startNode = nil
    LoadFlightTimes(self)
    local count = NumTaxiNodes()
    count = S.Finite(count) and math.min(256, count) or 0
    for i = 1, count do
        local name, kind = TaxiNodeName(i), TaxiNodeGetType(i)
        if Text(name) and S.Public(kind) then
            local node = { name = name, reachable = kind == "REACHABLE" }
            self.nodes[i] = node
            if kind == "CURRENT" then self.startNode = node end
        end
    end
    ReadNodeIDs(self, system)
    for index, node in pairs(self.nodes) do
        local routes = GetNumRoutes(index)
        if S.Finite(routes) and routes >= 0 and routes <= MAX_ROUTE_LEGS then
            self.routes[index] = BuildRoute(self, index, node, routes)
        end
    end
end

local function LearnedTime(self, key)
    local learned = self.timings and self.timings[key]
    if S.Finite(learned) and learned > 0 then return learned end
end

local function Estimate(self, route)
    return LearnedTime(self, route.key) or route.estimate
end

-- The native request exposes no updated destination or ETA. Use the first
-- stop whose estimated arrival is still ahead, with times measured from takeoff.
local function EarlyLandingRoute(self)
    local route = self.current
    if not route then return end
    if route.segments == 1 and route.legs[1] ~= nil then return route end
    local elapsed = GetTime() - self.departed
    local names, arrival, previousID = route.names, 0, route.startID
    LoadFlightTimes(self)
    local times = self.flightTimes
    for part, leg in ipairs(route.legs) do
        local stop = part + 1
        local final = part == route.segments
        local key = final and route.key or table.concat(names, " > ", 1, stop)
        local seconds = times and PairTime(times, previousID, leg.id)
        local legTime = seconds or LearnedTime(self, names[part] .. " > " .. names[stop])
        local estimate = LearnedTime(self, key) or (final and route.estimate) or (legTime and arrival + legTime)
        if not estimate or estimate <= arrival then return end
        if estimate > elapsed and (final or leg.reachable ~= false) then
            if not final and not leg.reachable then return end
            return { names = { unpack(names, 1, stop) }, key = key, destination = names[stop], estimate = estimate }
        end
        arrival, previousID = estimate, leg.id
    end
end

-- An in-progress trip is private runtime state of the active profile.
-- The UI reload keeps GetTime's clock, so saved starts work directly with
-- C_DurationUtil when the next UI instance confirms a matching taxi.
local function Save(self)
    if not self.onTaxi then
        -- A second reload can happen before the startup taxi flag arrives.
        if NS.loginKind == "reload" then self.state.flight = self.resume end
        return
    end
    local guid = UnitGUID("player")
    if not Text(guid) then return end
    self.state.flight = {
        guid = guid, departed = self.departed, savedAt = GetTime(),
        route = self.current, earlyLanding = self.earlyLanding, landingDeadline = self.landingDeadline,
    }
end

local function TakeSnapshot(state)
    local flight = state.flight
    state.flight = nil
    if NS.startingModules and NS.loginKind ~= "login" and PublicTable(flight) then return flight end
end

local function ValidRoute(route, earlyLanding)
    if not PublicTable(route) or not Text(route.key) or not Text(route.destination) then return false end
    local names, legs, segments = route.names, route.legs, route.segments
    if not PublicTable(names) or #names == 0 or #names > MAX_ROUTE_LEGS + 1 then return false end
    for i = 1, #names do
        if not Text(names[i]) then return false end
    end
    local estimate = route.estimate
    if not S.Public(estimate) or estimate and (not S.Finite(estimate) or estimate <= 0) then return false end
    if earlyLanding then return true end
    if not PublicTable(legs) or not S.Finite(segments) or segments < 0 or segments > MAX_ROUTE_LEGS
        or #legs > segments or #legs >= #names then return false end
    if not S.Public(route.startID) or route.startID and not S.Finite(route.startID) then return false end
    for i = 1, #legs do
        local leg = legs[i]
        if not PublicTable(leg) or not S.Public(leg.id) or leg.id and not S.Finite(leg.id)
            or not S.Public(leg.reachable) then return false end
    end
    return true
end

local function Restore(self, now)
    local flight = self.resume
    self.resume = nil
    if not flight or NS.loginKind ~= "reload" then return false end
    local guid = UnitGUID("player")
    if not Text(guid) or not Text(flight.guid) or guid ~= flight.guid then return false end
    local departed, savedAt = flight.departed, flight.savedAt
    if not S.Finite(departed) or not S.Finite(savedAt) or departed < 0 or departed > savedAt or savedAt > now
        or now - departed >= MAX_FLIGHT_AGE then return false end

    self.departed, self.resumed = departed, true
    self.earlyLanding = S.Public(flight.earlyLanding) and flight.earlyLanding == true
    local route = flight.route
    self.current = ValidRoute(route, self.earlyLanding) and route or nil
    local deadline = flight.landingDeadline
    if self.current and self.earlyLanding and S.Finite(deadline) then
        if deadline > now and deadline - departed < MAX_FLIGHT_AGE then
            self.landingDeadline = deadline
        else
            self.current = nil
        end
    end
    return true
end

P.FlightTimerData = {
    ReadRoutes = ReadRoutes, EarlyLandingRoute = EarlyLandingRoute, Estimate = Estimate,
    Save = Save, TakeSnapshot = TakeSnapshot, Restore = Restore,
}

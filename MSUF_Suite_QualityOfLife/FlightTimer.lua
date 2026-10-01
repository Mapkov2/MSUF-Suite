local _, P = ...
local NS, S = P.NS, P.Suite
local ID, M = "flightTimer", { routes = {}, nodes = {} }
-- A chosen destination belongs to the next takeoff only this long; a choice
-- the flight master refused never starts a flight.
local REQUEST_WINDOW = 5
local function Text(value) return S.Public(value) and type(value) == "string" and value ~= "" end
local function RouteKey(names) return table.concat(names, " > ") end
local function MapOpened(self)
    wipe(self.nodes); wipe(self.routes)
    self.startName = nil
    local count = NumTaxiNodes()
    if not S.Finite(count) then return end
    count = math.min(256, count)
    for i = 1, count do
        local name, kind = TaxiNodeName(i), TaxiNodeGetType(i)
        local x, y = TaxiNodePosition(i)
        if Text(name) and S.Public(kind) and S.Finite(x) and S.Finite(y) then
            self.nodes[i] = { name = name, x = x, y = y }
            if kind == "CURRENT" then self.startName = name end
        end
    end
    for index, node in pairs(self.nodes) do
        local names = { self.startName or S.Text("Unknown") }
        local routes = GetNumRoutes(index)
        if S.Finite(routes) and routes >= 0 and routes <= 32 then
            for part = 1, routes do
                local x, y = TaxiGetDestX(index, part), TaxiGetDestY(index, part)
                if S.Finite(x) and S.Finite(y) then
                    local best, distance
                    for _, candidate in pairs(self.nodes) do
                        local d = math.abs(candidate.x - x) + math.abs(candidate.y - y)
                        if not distance or d < distance then best, distance = candidate.name, d end
                    end
                    if best and distance < .0001 and best ~= names[#names] then names[#names + 1] = best end
                end
            end
            if node.name ~= names[#names] then names[#names + 1] = node.name end
            self.routes[index] = { names = names, key = RouteKey(names), destination = node.name }
        end
    end
end
local function Layout(self)
    local c = self.config
    if not self.host then
        local host = S.CreateFrame("Frame", nil, UIParent)
        host.background = S.CreateTexture(host, nil, "BACKGROUND")
        host.background:SetAllPoints(); host.background:SetColorTexture(.035, .045, .06, .92)
        host.title = S.CreateFontString(host, nil, "OVERLAY")
        host.title:SetPoint("TOPLEFT", 8, -7); host.title:SetPoint("TOPRIGHT", -8, -7)
        host.route = S.CreateFontString(host, nil, "OVERLAY")
        host.route:SetPoint("TOPLEFT", 8, -29); host.route:SetPoint("TOPRIGHT", -8, -29)
        host.route:SetJustifyH("LEFT")
        host.time = S.CreateFontString(host, nil, "OVERLAY")
        host.time:SetPoint("BOTTOMLEFT", 8, 8)
        host.land = S.CreateFrame("Button", nil, host, "UIPanelButtonTemplate")
        host.land:SetSize(132, 23); host.land:SetPoint("BOTTOMRIGHT", -8, 5)
        host.land:SetText(S.Text("Land at next stop"))
        host.land:SetScript("OnClick", function()
            local taxi = UnitOnTaxi("player")
            if self.active and S.Public(taxi) and taxi then TaxiRequestEarlyLanding() end
        end)
        self.duration = C_DurationUtil.CreateDuration()
        self.binding = C_DurationUtil.CreateDurationTextBinding()
        self.binding:SetFontString(host.time)
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
    local host = self.host
    host:SetSize(c.width, c.showStops and 132 or 76); host:SetScale(c.scale / 100)
    host:ClearAllPoints(); host:SetPoint("CENTER", UIParent, "CENTER", c.x, c.y)
    local _, class = UnitClass("player")
    local color = c.classColor and S.Public(class) and RAID_CLASS_COLORS[class]
    for _, label in ipairs({ host.title, host.route, host.time }) do
        S.SetStyledFont(label, S.GlobalFontPath(), c.fontSize, "OUTLINE", 1, true, 80, 1)
        label:SetTextColor(color and color.r or 1, color and color.g or 1, color and color.b or 1)
    end
    host.route:SetShown(c.showStops)
end
local function Update(self)
    if not self.active then return end
    Layout(self)
    local taxi = UnitOnTaxi("player")
    taxi = S.Public(taxi) and taxi == true
    local visible = not self.config.hideDisplay and (taxi or S.editMode)
    self.host:SetShown(visible)
    self.host.land:SetEnabled(taxi and not S.editMode)
    if not visible then self.binding:SetEnabled(false); return end
    local route = self.current
    self.host.title:SetText(route and (route.names[1] .. " → " .. route.destination) or S.Text(S.editMode and "Flight route preview" or "Flight route unavailable"))
    self.host.route:SetText(route and table.concat(route.names, " → ") or S.Text("Select a destination at the flight master."))
    local estimate = route and self.timings and self.timings[route.key]
    if S.Finite(estimate) and estimate > 0 and self.departed then
        self.duration:SetTimeFromEnd(self.departed + estimate, estimate)
        self.binding:SetDuration(self.duration); self.binding:SetEnabled(true)
    else
        self.binding:SetEnabled(false)
        self.host.time:SetText(S.Text(S.editMode and "Estimated time" or "Learning flight time"))
    end
end
local function Forget(self)
    self.departed, self.current, self.earlyLanding, self.requested, self.onTaxi = nil, nil, nil, nil, nil
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
            if count >= 200 then for key in pairs(times) do times[key] = nil; break end end
        end
        times[self.current.key] = elapsed
    end
    Forget(self)
end

-- Takeoff order: TakeTaxiNode returns before the flight starts, then
-- PLAYER_CONTROL_LOST arrives while UnitOnTaxi("player") is still false and
-- the taxi flag follows with UNIT_FLAGS. Control returns at landing.
local function State(self, event)
    local taxi = UnitOnTaxi("player")
    if not S.Public(taxi) then return end
    local now = GetTime()
    if taxi then
        if not self.departed then
            -- A flight seen without its takeoff (after a /reload) has no known route.
            if not Fresh(self, now) then self.current = nil end
            self.departed = now
        end
        self.onTaxi = true
    elseif self.departed then
        -- Control lost after a choice ends only with the taxi flag or control again.
        if self.onTaxi or event == "PLAYER_CONTROL_GAINED" then Land(self, now) end
    elseif event == "PLAYER_CONTROL_LOST" and Fresh(self, now) then
        self.departed = now
    end
    Update(self)
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
            if not self.active then return end
            Forget(self)
            self.current = S.Finite(index) and self.routes[index] or nil
            self.requested = GetTime()
            Update(self)
        end)
        hooksecurefunc("TaxiRequestEarlyLanding", function() if self.active then self.earlyLanding = true end end)
        hooksecurefunc("TaxiNodeOnButtonEnter", function(button)
            local route = self.active and self.config.routePreview and self.routes[button:GetID()]
            if route then GameTooltip:AddLine(table.concat(route.names, " → "), 1, .85, .4, true); GameTooltip:Show() end
        end)
    end
    self.context:Event("TAXIMAP_OPENED", MapOpened, true)
    self.context:Event("PLAYER_CONTROL_LOST", State, true)
    self.context:Event("PLAYER_CONTROL_GAINED", State, true)
    self.context:Event("UNIT_FLAGS", State, false, "player")
    self.context:Event("PLAYER_ENTERING_WORLD", State, true)
    Update(self)
    S.RegisterOwnedMover(ID, "flight", { label = "Flight route timer", order = 651, getFrame = function() return self.host end,
        xKey = "x", yKey = "y", sizeKeys = { "width" }, point = function() return "CENTER" end })
end
function M:Refresh()
    local timings = Timings()
    -- A profile switch mid-flight must not teach the new profile this trip.
    if self.timings ~= timings then Forget(self) end
    self.timings = timings
    Update(self)
end
function M:Disable()
    Forget(self)
    if self.host then self.binding:SetEnabled(false); self.host:Hide() end
end
S.Install(ID, M)

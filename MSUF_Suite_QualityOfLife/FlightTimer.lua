local _, P = ...
local NS, S = P.NS, P.Suite
local IN_COMBAT = { inCombat = true }
local ID, M = "flightTimer", { routes = {}, nodes = {} }
-- A chosen destination belongs to the next takeoff only this long; a choice
-- the flight master refused never starts a flight.
local REQUEST_WINDOW = 5
-- displayStyle (MSUF_Suite/Core/Catalog/QualityOfLifeDetails.lua): the card,
-- or one slim Timer bar.
local BAR = 2
-- The Timer bar's spacing: text and bar insets, the padding above and below,
-- the gap between the text and the bar, and the fill the Edit Mode preview
-- shows.
local TEXT_INSET, BAR_INSET, BAR_PAD, BAR_GAP, PREVIEW_FILL = 10, 4, 7, 5, .6
local SPARK = "Interface\\CastingBar\\UI-CastingBar-Spark"
-- The card's panel, as it always was.
local CARD_PANEL = { .035, .045, .06, .92 }
-- The Timer bar's skins (barLook, MSUF_Suite/Core/Catalog/QualityOfLifeDetails.lua;
-- each look's preset writes its fill color, barColor). 1 Modern: the slim
-- dark bar without a frame, white text. 2 MSUF Forever: the Forever skin's
-- graphite glass (MSUF_Suite_Skin foreverGlass: a light top sheen, ivory
-- title, gold accent) with the hairline frame and gold top trim the
-- experience bar's MSUF Forever look draws, so the bar matches it in its slot.
local BAR_LOOKS = {
    { panel = "0b0e12", panelAlpha = .82, track = "000000", trackAlpha = .55,
        text = "ffffff", time = "ffffff", spark = "d6efff" },
    { panel = "14181b", panelAlpha = .94, track = "20272a", trackAlpha = .98, sheen = .07,
        text = "f1e3c4", time = "d8b66a", spark = "ffe6a8", border = "9f8960", trim = "d8b66a" },
}
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
    host.background:SetColorTexture(CARD_PANEL[1], CARD_PANEL[2], CARD_PANEL[3], CARD_PANEL[4])
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
    self.formatter = formatter
    -- The countdown's formatter of the chosen layout (Layout).
    self.countdownFormatter = formatter
    self.binding:SetFormatter(formatter)
    self.binding:SetExpiredText(S.Text("Arriving"))
    self.binding:SetUpdateInterval(1)
    self.host = host
end

-- The Timer bar, made the first time it is chosen: a StatusBar the client
-- fills from the countdown's own duration (StatusBar:SetTimerDuration, Retail
-- and Forever), so no Lua runs while it fills; a dark track behind it and a
-- spark on the fill's edge, anchored to the fill texture so the client moves
-- it with the fill.
local function CreateBar(self)
    local host = self.host
    if host.bar then return end
    local bar = S.CreateFrame("StatusBar", nil, host)
    bar.track = S.CreateTexture(bar, nil, "BACKGROUND")
    bar.track:SetAllPoints()
    bar.track:SetColorTexture(0, 0, 0, .55)
    bar.spark = S.CreateTexture(bar, nil, "OVERLAY")
    bar.spark:SetTexture(SPARK)
    bar.spark:SetBlendMode("ADD")
    bar:SetMinMaxValues(0, 1)
    bar:SetValue(0)
    -- The MSUF Forever frame (FrameBar) and glass sheen; the card never shows them.
    host.edges = {}
    for i = 1, 4 do host.edges[i] = S.CreateTexture(host, nil, "BORDER") end
    host.sheen = S.CreateTexture(host, nil, "BACKGROUND", nil, 1)
    host.sheen:SetAllPoints()
    host.sheen:SetColorTexture(1, 1, 1, 1)
    host.bar = bar
    self.barDuration = C_DurationUtil.CreateDuration()
    -- A new bar has no fill yet: the next update paints it (PaintBar).
    self.barKey = false
end

-- The Timer bar shows the time left as a clock (1:42), with the breakpoint
-- the battle resurrection timer and the cooldown manager's countdowns use.
local function ClockFormatter(self)
    if self.clockFormatter then return self.clockFormatter end
    local down = Enum.NumericRuleFormatRounding.Down
    local formatter = C_StringUtil.CreateNumericRuleFormatter()
    formatter:SetBreakpoints({ { threshold = 0, format = "%d:%02d", rounding = down,
        components = { { div = 60, rounding = down }, { mod = 60, rounding = down } } } })
    self.clockFormatter = formatter
    return formatter
end

-- Texture, look, height and spark of the Timer bar. A running fill keeps
-- its timer; the spark shows while the fill moves or holds the preview. The
-- look's text colors give way to the class color (classColor).
local function StyleBar(self)
    local c, host, bar = self.config, self.host, self.host.bar
    local look = BAR_LOOKS[c.barLook] or BAR_LOOKS[2]
    self.barLookStyle = look
    local r, g, b = S.RGB(look.panel)
    host.background:SetColorTexture(r, g, b, look.panelAlpha)
    host.sheen:SetShown(look.sheen ~= nil)
    if look.sheen then host.sheen:SetGradient("VERTICAL", CreateColor(1, 1, 1, 0), CreateColor(1, 1, 1, look.sheen)) end
    r, g, b = S.RGB(look.track)
    bar.track:SetColorTexture(r, g, b, look.trackAlpha)
    bar.spark:SetVertexColor(S.RGB(look.spark))
    if not c.classColor then
        host.title:SetTextColor(S.RGB(look.text))
        host.time:SetTextColor(S.RGB(look.time))
    end
    local inherited = S.ResolveTexture("MSUF Lucent", NS.MSUFMedia.barTexture)
    bar:SetStatusBarTexture(S.ResolveTexture(c.barTexture, inherited))
    r, g, b = S.RGB(c.barColor)
    bar:SetStatusBarColor(r, g, b, 1)
    bar:SetHeight(c.barHeight)
    bar.spark:ClearAllPoints()
    bar.spark:SetPoint("CENTER", bar:GetStatusBarTexture(), "RIGHT", 0, 0)
    bar.spark:SetSize(math.max(8, c.barHeight * 2.5), math.max(10, c.barHeight * 3))
    bar.spark:SetShown(c.barSpark == true and self.barMoving == true)
end

-- The fill of the Timer bar: the countdown's span from takeoff to arrival
-- (finish, length), run by the client; otherwise a still value (the Edit Mode
-- sample, else empty), as the dungeon cast stack shows an untimed cast. It is
-- written again only when it changed.
local function PaintBar(self, finish, length, sample)
    local bar = self.barStyle and self.host.bar
    if not bar then return end
    local key = finish or sample or 0
    if self.barKey == key and self.barLength == length then return end
    self.barKey, self.barLength = key, length
    if finish then
        self.barDuration:SetTimeFromEnd(finish, length)
        bar:SetTimerDuration(self.barDuration, Enum.StatusBarInterpolation.Immediate,
            Enum.StatusBarTimerDirection.ElapsedTime)
    else
        bar:SetMinMaxValues(0, 1)
        bar:SetValue(sample or 0)
    end
    self.barMoving = (finish or sample) ~= nil
    bar.spark:SetShown(self.config.barSpark == true and self.barMoving)
end

-- Where the display stands. In the experience bar's place (slot: its host,
-- S.ExperienceBarSlot) it takes that bar's scale and is anchored to its
-- corners, so it follows the bar's position and size; the bar draws nothing
-- meanwhile (S.CoverExperienceBar) and is handed back with slot nil.
-- Otherwise it stands at its own position and scale. Both functions come
-- from ExperienceBarSlot.lua, which this addon loads before this file.
local function Place(self, slot)
    local c, host = self.config, self.host
    if (slot ~= nil) ~= (self.slot ~= nil) then S.CoverExperienceBar(slot ~= nil) end
    self.slot = slot
    host:ClearAllPoints()
    if slot then
        host:SetScale(slot:GetScale())
        host:SetPoint("TOPLEFT", slot, "TOPLEFT")
        host:SetPoint("BOTTOMRIGHT", slot, "BOTTOMRIGHT")
    else
        host:SetScale(c.scale / 100)
        host:SetPoint("CENTER", UIParent, "CENTER", c.x, c.y)
    end
end

-- The experience bar to stand in for: only the Timer bar takes its place,
-- only while flying (replaceXPBar) and never in Edit Mode, where the display
-- is placed on its own. Nil without a shown MSUF experience bar.
local function Slot(self, visible, taxi)
    if not (visible and taxi and self.barStyle and self.config.replaceXPBar) or S.editMode then return nil end
    return S.ExperienceBarSlot()
end

-- Font/style choices are applied only on Enable and Refresh; taxi events
-- arrange the text only when the displayed route or flight state changes.
local function Layout(self)
    local c, host = self.config, self.host
    local bar = c.displayStyle == BAR
    if bar then CreateBar(self) end
    self.barStyle = bar
    Place(self, self.slot)
    local _, class = UnitClass("player")
    local color = c.classColor and S.Public(class) and RAID_CLASS_COLORS[class]
    for i = 1, #LABELS do
        local label = host[LABELS[i]]
        local size = LABELS[i] == "time" and not bar and math.floor(c.fontSize * 1.5) or c.fontSize
        S.QoLStyleText(label, c, S.GlobalFontPath(), size)
        label:SetTextColor(color and color.r or 1, color and color.g or 1, color and color.b or 1)
    end
    -- The bar's one line: the destination, cut where the time begins.
    host.title:SetWordWrap(not bar)
    host.title:SetMaxLines(bar and 1 or 2)
    host.time:SetJustifyH(bar and "RIGHT" or "LEFT")
    host.landText:SetText(S.Text("Land at next stop"))
    if bar then
        host.bar:Show()
        StyleBar(self)
    elseif host.bar then
        -- The card's own panel again, without the Timer bar's frame.
        host.bar:Hide()
        host.background:SetColorTexture(CARD_PANEL[1], CARD_PANEL[2], CARD_PANEL[3], CARD_PANEL[4])
        host.sheen:Hide()
        S.PlaceEdges(host.edges, host, 0)
    end
    -- The countdown of the chosen layout; a running one keeps its duration.
    local formatter = bar and ClockFormatter(self) or self.formatter
    if self.countdownFormatter ~= formatter then
        self.countdownFormatter = formatter
        if not self.elapsedClock then
            self.binding:SetFormatter(formatter)
            if self.countdownStart then self.binding:UpdateFontString() end
        end
    end
end

-- The Timer bar: the destination at the left and the time at the right on
-- one line, the bar across the width below them. Heights come from the font
-- size, not from measured text; in the experience bar's slot (whose corners
-- size the display) the line and the bar are centered in its height.
-- The MSUF Forever frame: one screen pixel at the display's current scale
-- (its own, or the experience bar's in that bar's slot), the top edge in the
-- gold trim. Modern draws none.
local function FrameBar(self)
    local host, look = self.host, self.barLookStyle
    if not look.border then return S.PlaceEdges(host.edges, host, 0) end
    local scale = host:GetEffectiveScale()
    local pixel = S.Finite(scale) and scale > 0 and 1 / scale or 1
    local r, g, b = S.RGB(look.border)
    S.PlaceEdges(host.edges, host, pixel, r, g, b, .86)
    r, g, b = S.RGB(look.trim)
    host.edges[1]:SetColorTexture(r, g, b, .88)
end

local function ArrangeBar(self)
    local c, host = self.config, self.host
    FrameBar(self)
    host.route:Hide()
    host.status:Hide()
    host.land:Hide()
    local content = c.fontSize + BAR_GAP + c.barHeight
    local height = content + BAR_PAD * 2
    if self.slot then
        height = self.slot:GetHeight()
    else
        host:SetSize(c.width, height)
    end
    local top = math.max(1, math.floor((height - content) / 2))
    host.time:ClearAllPoints()
    host.time:SetWidth(0)
    host.time:SetPoint("TOPRIGHT", -TEXT_INSET, -top)
    host.title:ClearAllPoints()
    host.title:SetWidth(0)
    host.title:SetPoint("TOPLEFT", TEXT_INSET, -top)
    host.title:SetPoint("TOPRIGHT", host.time, "TOPLEFT", -6, 0)
    host.bar:ClearAllPoints()
    host.bar:SetPoint("TOPLEFT", BAR_INSET, -(top + c.fontSize + BAR_GAP))
    host.bar:SetPoint("TOPRIGHT", -BAR_INSET, -(top + c.fontSize + BAR_GAP))
end

-- Only real intermediate stops get a second route line. Reserve measured text
-- heights before the timer/footer so large fonts and narrow widths cannot overlap.
local function Arrange(self)
    if self.barStyle then return ArrangeBar(self) end
    local c, host, route = self.config, self.host, self.current
    host.status:Show()
    host.land:Show()
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
    if self.elapsedClock then
        self.elapsedClock = nil
        self.binding:SetEnabled(false)
        -- The countdown's own format again.
        self.binding:SetFormatter(self.countdownFormatter)
    end
    self.elapsedSecond = nil
end

-- The elapsed time of a flight without an estimate. Where the client can
-- write the clock (S.ElapsedClock) the binding that shows the countdown shows
-- the time since departure instead, and nothing runs per second; otherwise a
-- 1 s ticker paints it. (From an hour on the client's clock reads h:mm:ss
-- where the ticker's reads minutes; no flight lasts that long.)
local function StartElapsed(self)
    local format = S.ElapsedClock()
    if not format then
        Elapsed(self)
        self.elapsedTicker = self.context:Ticker(1, Elapsed)
        return
    end
    self.elapsedClock = true
    self.binding:SetTextFormat("{}", format)
    self.duration:SetTimeFromStart(self.departed, S.CLOCK_SPAN)
    self.binding:SetDuration(self.duration)
    self.binding:SetEnabled(true)
    self.binding:UpdateFontString()
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
    Place(self, Slot(self, visible, taxi))
    self.host:SetShown(visible)
    self.host.land:SetEnabled(taxi and not self.earlyLanding and not S.editMode)
    self.host.landText:SetAlpha(taxi and not self.earlyLanding and not S.editMode and 1 or .45)
    StopElapsed(self)
    if not visible then
        StopCountdown(self)
        PaintBar(self)
        return
    end
    local route = self.current
    -- The Timer bar names only the destination.
    local title = route and (self.barStyle and route.destination or route.names[1] .. " > " .. route.destination)
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
        PaintBar(self, self.departed + estimate, estimate)
        self.host.status:SetText(S.Text("Remaining time"))
    else
        StopCountdown(self)
        PaintBar(self, nil, nil, S.editMode and not taxi and PREVIEW_FILL or nil)
        self.host.status:SetText(S.Text(route and not self.earlyLanding and "Learning flight time" or "Elapsed time"))
        if taxi and self.departed then
            StartElapsed(self)
        else
            self.host.time:SetText("0:00")
            self.host.status:SetText(S.Text("Estimated time"))
        end
    end
    Arrange(self)
end

-- The experience bar showed or hid (ExperienceBarSlot.lua): a shown Timer
-- bar that may stand in for it places itself again, and hands back a bar that
-- hid (the level cap, switched off).
function S.ExperienceSlotChanged()
    local self = M
    if self.active and self.host and self.paintedVisible and self.barStyle and self.config.replaceXPBar then
        Update(self, self.paintedTaxi, true)
    end
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
        -- The experience bar comes back.
        Place(self, nil)
        self.host:Hide()
    end
end
S.Install(ID, M)

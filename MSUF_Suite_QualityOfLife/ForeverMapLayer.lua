local _, P = ...
local NS, S = P.NS, P.Suite
if not NS.Client.isForever then return end

local Layer = {}
P.ForeverMapLayer = Layer

local UNIT_EVENTS = {
    PLAYER_TARGET_CHANGED = "target",
    UPDATE_MOUSEOVER_UNIT = "mouseover",
    PLAYER_SOFT_INTERACT_CHANGED = "softinteract",
    NAME_PLATE_UNIT_ADDED = false,
}
local LOCATION_EVENTS = { "PLAYER_ENTERING_WORLD", "PLAYER_LEAVING_WORLD", "ZONE_CHANGED_NEW_AREA", "SHARD_TRANSFER" }
local IN_COMBAT = { inCombat = true }

local function ReadLayer(unit)
    if not S.PublicText(unit) then return end
    local guid = S.PublicText(UnitGUID(unit))
    if not guid then return end
    -- The zoneUID is the fifth GUID field. It is a local observation and
    -- can differ for clients on the same physical layer.
    local kind, id = guid:match("^(%a+)%-[^-]+%-[^-]+%-[^-]+%-([1-9]%d*)%-")
    if kind == "Creature" or kind == "Vehicle" then return id end
end

local function Paint(self, id)
    local previous = self.observedLayer
    if previous == id then return end
    self.observedLayer = id
    local text = self.layerLabel
    if id == nil then
        text:Hide()
    elseif id then
        text:SetFormattedText(S.Text("Observed layer ID: %s"), id)
    else
        text:SetText(S.Text("Observed layer ID: unknown"))
    end
    if id ~= nil and previous == nil then text:Show() end
end

local function Observe(self, event, unit)
    local id = ReadLayer(UNIT_EVENTS[event] or unit)
    if id then
        self.layerSample = nil
        Paint(self, id)
    end
end

local function SetOutdoor(self, outdoor)
    if self.layerOutdoor == outdoor then return end
    self.layerOutdoor = outdoor
    for event in pairs(UNIT_EVENTS) do
        if outdoor then
            self.context:Event(event, Observe, IN_COMBAT)
        else
            self.context:RemoveEvent(event)
        end
    end
end

local function InOpenWorld()
    local inside = IsInInstance()
    return S.Public(inside) and inside == false
end

local function SampleNearby()
    local id = ReadLayer("target") or ReadLayer("softinteract") or ReadLayer("mouseover")
    if id then return id end
    local plates = C_NamePlate.GetNamePlates()
    for i = 1, #plates do
        local plate = plates[i]
        if not NS.Safety.IsForbidden(plate) then
            id = ReadLayer(plate:GetUnit())
            if id then return id end
        end
    end
end

local function QueueSample(self)
    if self.layerSample then return end
    local function Resample()
        if self.layerSample ~= Resample then return end
        self.layerSample = nil
        Paint(self, SampleNearby() or false)
    end
    self.layerSample = Resample
    C_Timer.After(0, Resample)
end

local function LocationChanged(self, event)
    if event == "SHARD_TRANSFER" then
        self.layerSample = nil
        if self.layerOutdoor then Paint(self, false) end
        return
    end
    SetOutdoor(self, event ~= "PLAYER_LEAVING_WORLD" and InOpenWorld())
    if self.layerOutdoor then
        Paint(self, false)
        QueueSample(self)
    else
        self.layerSample = nil
        Paint(self, nil)
    end
end

local function AttachLabel(self)
    for _, overlay in ipairs(self.map.overlayFrames) do
        if overlay.PlayerCoords and overlay.CursorCoords then
            local level = overlay.PlayerCoords:GetFrameLevel()
            if not S.Finite(level) then return end
            -- Follow the native coordinate panel above the map canvas. A
            -- sibling keeps Suite's holder outside Blizzard's layout pass.
            local holder = S.CreateFrame("Frame", nil, self.map)
            holder:SetFrameLevel(level + 1)
            holder:SetAllPoints(overlay)
            local label = S.CreateFontString(holder, nil, "OVERLAY")
            S.SetFont(label, nil, 11, "OUTLINE")
            label:SetPoint("BOTTOMLEFT", holder, "TOPLEFT", 0, 2)
            label:Hide()
            self.layerLabel = label
            return label
        end
    end
end

function Layer.Stop(self)
    if not self.layerWatching then return end
    self.layerWatching, self.layerSample = nil, nil
    SetOutdoor(self, false)
    Paint(self, nil)
    for _, event in ipairs(LOCATION_EVENTS) do self.context:RemoveEvent(event) end
end

function Layer.Sync(self)
    if not self.config.layerID or not self.map:IsShown() then return Layer.Stop(self) end
    if self.layerWatching or not (self.layerLabel or AttachLabel(self)) then return end
    self.layerWatching = true
    for _, event in ipairs(LOCATION_EVENTS) do self.context:Event(event, LocationChanged, IN_COMBAT) end
    SetOutdoor(self, InOpenWorld())
    if self.layerOutdoor then Paint(self, SampleNearby() or false) end
end

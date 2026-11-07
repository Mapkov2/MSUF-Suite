local _, P = ...
local NS, S = P.NS, P.Suite
MSUFSuiteForeverMapPinMixin = {}
if not NS.Client.isForever then return end

-- This template belongs to the Suite. AcquirePin supplies the native map,
-- mouse/gamepad routing, scaling and pooling; no Blizzard pin is modified.
local Pin = MSUFSuiteForeverMapPinMixin
local Pins = { template = "MSUFSuiteForeverMapPinTemplate" }
P.ForeverMapPins = Pins
local ATLASES = { "FlightPath", "flightmasterferry", "vehicle-air-horde", "vehicle-air-alliance",
    [6] = "poi-traveldirections", [7] = "Dungeon", [8] = "Dungeon" }
local icons = {}
local prepared = false

function Pins.Prepare()
    if prepared then return end
    for key, value in pairs(MapCanvasPinMixin) do
        if Pin[key] == nil then Pin[key] = value end
    end
    prepared = true
end

-- These pins always pass right clicks through, as declared in the template.
-- Skip MapCanvas's protected passthrough writes when it acquires our pins.
function Pin:CheckMouseButtonPassthrough() end

function Pin:OnLoad()
    self.icon = S.CreateTexture(self, nil, "ARTWORK")
    self.icon:SetAllPoints()
    self.highlight = S.CreateTexture(self, nil, "BACKGROUND")
    self.highlight:SetPoint("TOPLEFT", -2, 2)
    self.highlight:SetPoint("BOTTOMRIGHT", 2, -2)
    self.highlight:SetColorTexture(.2, .8, 1, .7)
    self.highlight:Hide()
    self:ClearNudgeSettings()
    self:SetScalingLimits(1, .5, 1)
end

function Pin:SetHighlightLocked(locked)
    self.highlight:SetShown(locked == true)
end

function Pin:OnAcquired(owner, record, x, y, title, kind)
    self.owner, self.record, self.title, self.kind = owner, record, title, kind
    local atlas = icons[kind]
    if atlas == nil then
        atlas = C_Texture.GetAtlasInfo(ATLASES[kind]) and ATLASES[kind] or false
        icons[kind] = atlas
    end
    if atlas then self.icon:SetAtlas(atlas) else self.icon:SetTexture("Interface\\Icons\\INV_Misc_Map_01") end
    self:SetSize(owner.config.pinSize, owner.config.pinSize)
    self:UseFrameLevelType("PIN_FRAME_LEVEL_FLIGHT_POINT")
    self:SetPosition(x, y)
end

function Pin:OnMouseEnter()
    if not self.owner or not self.owner.active or NS.Safety.IsForbidden(GameTooltip) then return end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetText(self.title)
    if self.record.tooltipLines then
        for i = 1, #self.record.tooltipLines do GameTooltip:AddLine(self.record.tooltipLines[i], 1, 1, 1) end
    end
    GameTooltip:AddLine(S.Text("Click to place a map pin"), .7, .85, 1)
    GameTooltip:Show()
end

function Pin:OnMouseLeave()
    if not NS.Safety.IsForbidden(GameTooltip) and GameTooltip:IsOwned(self) then GameTooltip:Hide() end
end

function Pin:OnMouseClickAction(button)
    if button ~= "LeftButton" or not self.owner or not self.owner.active or NS.InCombat() then return end
    -- Native pad clicks visit every overlapping pin. Only the one whose
    -- tooltip the player sees may place a waypoint.
    if S.GamepadUI() and (NS.Safety.IsForbidden(GameTooltip)
        or not GameTooltip:IsShown() or not GameTooltip:IsOwned(self)) then return end
    local record = self.record
    local allowed = C_Map.CanSetUserWaypointOnMap(record[1])
    if not S.Public(allowed) or not allowed then return end
    local placed = C_Map.SetUserWaypoint(UiMapPoint.CreateFromCoordinates(record[1], record[2], record[3]))
    if S.Public(placed) and placed then C_SuperTrack.SetSuperTrackedUserWaypoint(true) end
end

function Pin:OnReleased()
    -- The native pool also resets newly created pins before MapCanvas calls OnLoad.
    if self.highlight then
        self:OnMouseLeave()
        self.highlight:Hide()
    end
    self.owner, self.record, self.title, self.kind = nil, nil, nil, nil
    MapCanvasPinMixin.OnReleased(self)
end

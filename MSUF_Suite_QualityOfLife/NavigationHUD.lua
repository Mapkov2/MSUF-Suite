local _, private = ...
local S, NS, Map = private.Suite, private.NS, private.NavigationHUDMap
local Compass, Heading = NS.Compass, S.CompassHeading
local Markers = private.NavigationHUDMarkers
local ID = "navigationHUD"
local M = {}

local ART_CHECK_TICKS = 20
local MAP_RECOVERY_DELAY, MAP_RECOVERY_ATTEMPTS = .2, 5
local floor = math.floor
local MAP_SHORTCUT, OVERLAY_COMMAND, ZONE_MAP_COMMAND = "SHIFT-M", "MSUFSUITE_TOGGLE_MAP_OVERLAY", "TOGGLEBATTLEFIELDMINIMAP"
local CUSTOM_SHORTCUT = 2
local SHORTCUT_EVENTS = { "UPDATE_BINDINGS", "ACTIVE_GAME_MODE_UPDATED", "PLAYER_ENTERING_WORLD" }
local EVENT_NAMES = {
    "PLAYER_ENTERING_WORLD", "ZONE_CHANGED_NEW_AREA", "ZONE_CHANGED", "ZONE_CHANGED_INDOORS", "NEW_WMO_CHUNK",
    "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED", "ADDON_RESTRICTION_STATE_CHANGED",
    "UI_SCALE_CHANGED", "DISPLAY_SIZE_CHANGED",
}

local RecoverMap

local function CancelMapRecovery(self)
    if not self.mapRecovery then return end
    self.mapRecovery = nil
    self.context:Cancel(RecoverMap)
end

local function PaintLive(self, mapReady, compassWanted, bearing)
    local wasMap, wasCompass = self.mapLive, self.compassLive
    if mapReady then
        if self.mapRecovery then CancelMapRecovery(self) end
        self.map:SetHeading(bearing and floor(bearing + .5) % 360)
        if not self.mapLive then self.map:Show(false) end
    elseif self.mapLive then
        self.map.frame:Hide()
        if self.mapRequested then
            -- A requested overlay can briefly lose its map or position. Retry
            -- at a lower rate while it is hidden, without keeping the map watcher.
            self.mapRecovery = MAP_RECOVERY_ATTEMPTS
            self.context:After(MAP_RECOVERY_DELAY, RecoverMap)
        end
    end
    self.mapLive = mapReady
    local compassReady = compassWanted and bearing ~= nil
    if compassReady then
        Compass.Paint(self.compass, bearing)
        if not self.compassLive then self.compass.frame:Show() end
    elseif self.compassLive then
        Compass.Reset(self.compass)
        self.compass.frame:Hide()
    end
    self.compassLive = compassReady
    self.markerBearing = (mapReady or compassReady) and bearing or nil
    return mapReady ~= wasMap or compassReady ~= wasCompass
end

local function ReadMap(self, readWaypoint)
    local ready, changed = self.map:SelectArt()
    if not ready then return false end
    if changed or readWaypoint then self.map:UpdateWaypoint(self.config.showMarkers and self.config.showWaypoint) end
    return self.map:Sample()
end

local function Sample(self, bearing)
    local ready = self.mapLive
    if ready then
        self.artTicks = self.artTicks + 1
        if self.artTicks >= ART_CHECK_TICKS then
            -- Phasing can change the art even when the map ID stays the same.
            self.artTicks, ready = 0, ReadMap(self, false)
        else
            ready = self.map:Sample()
        end
    end
    if PaintLive(self, ready, self.config.showCompass, bearing) then Markers.Sync(self) end
    if not self.mapLive and not self.compassLive then Heading.Watch(self) end
end

local function StopSurfaces(self)
    CancelMapRecovery(self)
    Heading.Watch(self)
    self.map.frame:Hide()
    if self.compass then
        Compass.Reset(self.compass)
        self.compass.frame:Hide()
    end
    self.mapLive, self.compassLive, self.previewing = false, false, false
    self.markerBearing = nil
end

local function Stop(self)
    StopSurfaces(self)
    Markers.Stop(self)
end

local function Eligible(self, event)
    if not (self.mapRequested or self.config.showCompass) then return false end
    if self.config.hideInCombat and NS.InCombat(event) then return false end
    local inInstance = IsInInstance()
    return S.Public(inInstance) and inInstance == false
end

RecoverMap = function(self)
    local remaining = self.mapRecovery
    if not remaining or not self.active or not self.mapRequested or not self.driver:IsVisible()
        or S.editMode or not Eligible(self) then
        self.mapRecovery = nil
        return
    end
    if ReadMap(self, true) then
        self.mapRecovery, self.artTicks = nil, 0
        PaintLive(self, true, self.config.showCompass, Heading.Read())
        Heading.Watch(self, Sample)
        Markers.Sync(self)
    elseif remaining > 1 then
        self.mapRecovery = remaining - 1
        self.context:After(MAP_RECOVERY_DELAY, RecoverMap)
    else
        self.mapRecovery = nil
    end
end

local function ShowEditPreview(self)
    CancelMapRecovery(self)
    Heading.Watch(self)
    Markers.Stop(self)
    self.mapLive, self.compassLive, self.previewing = false, false, true
    self.map:Show(true)
    if self.compass then
        Compass.Reset(self.compass)
        if self.config.showCompass then Compass.Paint(self.compass, 0) end
        self.compass.frame:SetShown(self.config.showCompass)
    end
end

local function RefreshVisibility(self, event)
    if not self.driver:IsVisible() then
        Stop(self)
        return
    end
    if S.editMode and not NS.InCombat(event) then
        ShowEditPreview(self)
        return
    end
    local eligible = Eligible(self, event)
    if self.previewing or (not eligible and (self.mapLive or self.compassLive or self.mapRecovery)) then StopSurfaces(self) end
    if not eligible then
        Markers.Sync(self, event)
        return
    end
    if not self.mapRequested then CancelMapRecovery(self) end
    self.artTicks = 0
    local mapReady, compassWanted = self.mapRequested and ReadMap(self, true) or false, self.config.showCompass
    PaintLive(self, mapReady, compassWanted, (mapReady or compassWanted) and Heading.Read() or nil)
    Heading.Watch(self, (self.mapLive or self.compassLive) and Sample or nil)
    Markers.Sync(self, event)
end

local function Layout(self)
    local scale, pixel = UIParent:GetEffectiveScale(), PixelUtil.GetPixelToUIUnitFactor()
    local pixelScale = S.Finite(scale) and scale > 0 and S.Finite(pixel) and pixel > 0 and scale / pixel or 1
    self.map:Layout(self.config, pixelScale)
    if self.config.showCompass then
        local compass, config = self.compass, self.config
        if not compass then
            compass = Compass.New(self.driver, false, S.CreateFrame, S.CreateTexture)
            compass.frame:SetClampedToScreen(true)
            self.compass = compass
        end
        compass.frame:SetPoint("TOP", UIParent, "TOP", config.compassX, config.compassY)
        Compass.Layout(compass, config.compassWidth, 1 / pixelScale, S.GlobalFontPath(), config.accentColor)
    end
end

local function OnContextChanged(self, event)
    if event == "ADDON_RESTRICTION_STATE_CHANGED" then
        Stop(self)
        self.context:After(0, RefreshVisibility)
        return
    end
    if event == "UI_SCALE_CHANGED" or event == "DISPLAY_SIZE_CHANGED" then Layout(self) end
    if event == "PLAYER_ENTERING_WORLD" or event == "ZONE_CHANGED_NEW_AREA" then
        Markers.Invalidate(self)
        if event == "PLAYER_ENTERING_WORLD" then Markers.ResetQuestOffers() end
    elseif event == "ZONE_CHANGED" or event == "ZONE_CHANGED_INDOORS" or event == "UI_SCALE_CHANGED"
        or event == "DISPLAY_SIZE_CHANGED" then
        Markers.Invalidate(self, "map")
    end
    RefreshVisibility(self, event)
    local zoneEntry = event == "PLAYER_ENTERING_WORLD" or event == "ZONE_CHANGED_NEW_AREA"
    if zoneEntry and not self.previewing and self.driver:IsVisible() and Eligible(self, event) then
        -- At world entry the art and position may arrive after the first event.
        if (self.mapRequested and not self.mapLive) or (self.config.showCompass and not self.compassLive) then
            self.context:After(.2, RefreshVisibility)
        end
    end
end

local function WaypointChanged(self)
    if self.mapLive then self.map:UpdateWaypoint(self.config.showWaypoint) end
    Markers.Invalidate(self, "map")
end

local function SyncListeners(self)
    local c = self.config
    local listen = self.mapRequested or c.showCompass
        or (c.showMarkers and (c.showGatheringMinimap or c.showNavigationMinimap or S.CompassMarkerViews ~= nil))
    if self.listening ~= listen then
        self.listening = listen
        for _, event in ipairs(EVENT_NAMES) do
            if listen then self.context:Event(event, OnContextChanged, true) else self.context:RemoveEvent(event) end
        end
    end
    local compassMarkers = (c.showMapMarkers or c.showQuestOffers or c.showMapServices or c.showHandyNotes or c.showQuestie)
        and (c.showCompass or S.CompassMarkerViews)
    if c.showMarkers and c.showWaypoint and (self.mapRequested or compassMarkers) then
        self.context:Event("USER_WAYPOINT_UPDATED", WaypointChanged, true)
    else
        self.context:RemoveEvent("USER_WAYPOINT_UPDATED")
    end
    if not listen then self.context:Cancel(RefreshVisibility) end
end

function M:RefreshMarkerViews()
    SyncListeners(self)
    Markers.ViewsChanged(self)
end

local function WantsDefaultShortcut(self)
    if self.config.shortcutMode == CUSTOM_SHORTCUT then return false end
    local inInstance = IsInInstance()
    if not S.Public(inInstance) or inInstance ~= false then return false end
    local saved = GetBindingAction(MAP_SHORTCUT, false)
    if not S.Public(saved) or (saved ~= ZONE_MAP_COMMAND and saved ~= "") then return false end
    local effective = GetBindingAction(MAP_SHORTCUT, true)
    return S.Public(effective) and (effective == saved or (self.defaultShortcut == true and effective == OVERLAY_COMMAND))
end

local function RefreshDefaultShortcut(self, event)
    local driver = self.driver
    if (self.active or self.defaultShortcut) and NS.InCombat(event) then
        driver:RegisterEvent("PLAYER_REGEN_ENABLED")
        return
    end
    driver:UnregisterEvent("PLAYER_REGEN_ENABLED")
    local wanted = self.active and WantsDefaultShortcut(self) or false
    if wanted == (self.defaultShortcut == true) then return end
    -- Binding changes may notify listeners while the native write is underway.
    self.defaultShortcut = wanted
    if wanted then
        SetOverrideBinding(driver, false, MAP_SHORTCUT, OVERLAY_COMMAND)
    else
        ClearOverrideBindings(driver)
    end
end

function M:Enable()
    self.mapRequested = false
    if not self.driver then
        local driver = S.CreateFrame("Frame", nil, UIParent)
        driver:Hide()
        driver:SetAllPoints(UIParent)
        driver:SetFrameStrata("LOW")
        driver:EnableMouse(false)
        local map = Map.New(driver)
        driver:SetScript("OnShow", function() RefreshVisibility(self) end)
        driver:SetScript("OnHide", function() Stop(self) end)
        driver:SetScript("OnEvent", function(_, event) RefreshDefaultShortcut(self, event) end)
        self.driver, self.map = driver, map
    end
    Layout(self)
    SyncListeners(self)
    Markers.Bind(self)
    self.driver:Show()
    for _, event in ipairs(SHORTCUT_EVENTS) do self.driver:RegisterEvent(event) end
    RefreshDefaultShortcut(self)
end

function M:Refresh()
    Layout(self)
    SyncListeners(self)
    Markers.Bind(self)
    RefreshVisibility(self)
    RefreshDefaultShortcut(self)
end

function M:HideEditPreview()
    if self.previewing then Stop(self) end
end

function M:Disable()
    Heading.Watch(self)
    Markers.Disable(self)
    if self.driver then
        for _, event in ipairs(SHORTCUT_EVENTS) do self.driver:UnregisterEvent(event) end
        RefreshDefaultShortcut(self)
        self.driver:Hide()
    end
    if self.map then self.map:Release() end
    self.mapRequested, self.listening = false, nil
end

function M:ToggleMap()
    if S.editMode then return false end
    -- A hidden overlay with no pending recovery can try opening again.
    self.mapRequested = not (self.mapRequested and (self.mapLive or self.mapRecovery))
    RefreshVisibility(self)
    if self.mapLive then
        PlaySound(SOUNDKIT.IG_QUEST_LOG_OPEN)
    elseif self.mapRequested then
        self.mapRequested = false
        S.Print(S.Text("The map overlay is unavailable here."))
    end
    SyncListeners(self)
    return self.mapLive
end

function M:RegisterMovers()
    S.RegisterOwnedMover(ID, "map", {
        label = "Map overlay", order = 652, getFrame = function() return self.map.frame end,
        xKey = "mapX", yKey = "mapY", point = "CENTER", sizeKeys = { "mapWidth" },
    })
    S.RegisterOwnedMover(ID, "compass", {
        label = "Compass", order = 653, getFrame = function() return self.compass and self.compass.frame end,
        xKey = "compassX", yKey = "compassY", point = "TOP", sizeKeys = { "compassWidth" },
        visible = function() return self.config.showCompass end,
    })
end

S.Install(ID, M)

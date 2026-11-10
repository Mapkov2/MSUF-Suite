local _, Private = ...
local NS, Suite, Navigation = Private.NS, Private.Suite, Private.Navigation
local Module = { geometry = true, model = {}, elapsed = 0, fastElapsed = 0 }
Module.addons = { Blizzard_QuestNavigation = true, Blizzard_WorldMap = true, TomTom = true,
    RXPGuides = true, APR = true, ["APR-Core"] = true, Mapzeroth = true, ["Mapzeroth-Rebuild"] = true,
    DugisGuideViewerZ = true, SilverDragon = true }
local ART = { "Icon", "Arrow", "DistanceText", "IconBorder" }
local SAMPLE_INTERVAL, ARROW_INTERVAL = .1, 1 / 30

local function RestoreArt(self)
    if not self.native or not self.ownsArt then return end
    local protected = self.native:IsProtected()
    if not Suite.Public(protected) or protected == true then self.restorePending = true return end
    for _, key in ipairs(ART) do
        local region = self.native[key]
        if region then self.context:RestoreProperty(region, "SetAlpha") end
    end
    self.ownsArt, self.restorePending = false, false
end

local function OwnArt(self)
    if self.ownsArt then self.restorePending = false return true end
    if NS.IsCombatLocked() or not self.native then return false end
    local protected = self.native:IsProtected()
    if not Suite.Public(protected) or protected then return false end
    self.ownsArt = true
    for _, key in ipairs(ART) do
        local region = self.native[key]
        if not region or NS.Safety.IsForbidden(region) then RestoreArt(self) return false end
        self.context:Property(region, "GetAlpha", "SetAlpha", 0)
        local alpha = region:GetAlpha()
        if not Suite.Finite(alpha) or alpha ~= 0 then RestoreArt(self) return false end
    end
    return true
end

local function Stop(self)
    if self.driver then self.driver:SetScript("OnUpdate", nil) end
    if self.view then self.view.root:Hide() end
    self.model.valid, self.model.mode = false, nil
    RestoreArt(self)
end

local function Proximity(self, distance)
    local near = distance <= self.config.soundDistance
    if self.model.near == near then return end
    if self.model.near ~= nil and (near and self.config.soundNear or not near and self.config.soundLeave) then
        local now = GetTime()
        if not self.lastSound or now - self.lastSound > 2 then
            Navigation.Play(self.config)
            self.lastSound = now
        end
    end
    self.model.near = near
end

local function ReadPosition(self)
    local valid = C_Navigation.HasValidScreenPosition()
    local distance, clamped, state = C_Navigation.GetDistance(), C_Navigation.WasClampedToScreen(), C_Navigation.GetTargetState()
    if not Suite.Public(valid) or valid ~= true or not Suite.Finite(distance) or distance <= 0
        or not Suite.Public(clamped) or not Suite.Public(state) then return false end
    local model, config = self.model, self.config
    model.valid, model.distance, model.clamped = true, distance, clamped == true
    model.occluded = state == Enum.NavigationState.Occluded
    -- A placed, measured destination decides. Forever reports Invalid for one
    -- while Blizzard's own in-game navigation option is off (live, 2026-11-10).
    if state == Enum.NavigationState.Disabled then return false end
    local speed = GetUnitSpeed("player")
    if not Suite.Finite(speed) then speed = 0 end
    Navigation.Readout(model, config, distance, speed)
    Proximity(self, distance)
    model.mode = Navigation.Mode(model, config)
    if not config.showInCombat and NS.InCombat() then model.mode = nil end
    return true
end

local function Position(self)
    local model, config, host = self.model, self.config, self.host
    if not model.clamped then
        if self.screenAnchored then self.anchor = nil self.screenAnchored = false end
        if self.anchor ~= self.projection then
            host:ClearAllPoints()
            host:SetPoint("CENTER", self.projection, "CENTER")
            self.anchor = self.projection
        end
        return true
    end
    local parent = host:GetParent()
    local x, y = self.projection:GetCenter()
    local centerX, centerY = parent:GetCenter()
    local sourceScale, scale = UIParent:GetEffectiveScale(), parent:GetEffectiveScale()
    local width, height = parent:GetSize()
    if not Suite.Finite(x) or not Suite.Finite(y) or not Suite.Finite(centerX) or not Suite.Finite(centerY)
        or not Suite.Finite(sourceScale) or not Suite.Finite(scale) or scale <= 0
        or not Suite.Finite(width) or not Suite.Finite(height) or width <= 0 or height <= 0 then return false end
    x, y = (x * sourceScale - centerX * scale) / scale, (y * sourceScale - centerY * scale) / scale
    local radiusX, radiusY = math.min(500, width * .38), math.min(230, height * .3)
    local divisor = math.sqrt(x * x / (radiusX * radiusX) + y * y / (radiusY * radiusY))
    if divisor == 0 then return false end
    model.angle = -math.atan2(x, y)
    x, y = x / divisor + config.navigatorX, y / divisor + config.navigatorY
    if config.dynamicOffset then y = y * .9 end
    if not self.screenAnchored or math.abs(x - (self.anchorX or 0)) >= .25 or math.abs(y - (self.anchorY or 0)) >= .25 then
        host:ClearAllPoints()
        host:SetPoint("CENTER", parent, "CENTER", x, y)
        self.anchorX, self.anchorY, self.screenAnchored = x, y, true
    end
    return true
end

local function Paint(self)
    if not self.supported or not ReadPosition(self) or not Position(self) then
        self.model.valid, self.model.mode = false, nil
        self.view.root:Hide()
        RestoreArt(self)
        return
    end
    if not OwnArt(self) then self.view.root:Hide() return end
    local model, config, root = self.model, self.config, self.view.root
    local hovered = config.fadeOnHover and root:IsMouseOver()
    model.hovered = Suite.Public(hovered) and hovered == true
    Navigation.Paint(self.view, model, config)
end

local function UpdateArrow(self)
    if not self.supported or not self.model.valid or self.model.mode ~= Navigation.DIRECTION then return end
    local angle = self.model.angle
    if Position(self) and angle ~= self.model.angle then
        Navigation.Paint(self.view, self.model, self.config)
    end
end

local function OnUpdate(frame, elapsed)
    local self = Module
    self.elapsed, self.fastElapsed = self.elapsed + elapsed, self.fastElapsed + elapsed
    if self.fastElapsed >= ARROW_INTERVAL then
        self.fastElapsed = 0
        UpdateArrow(self)
    end
    local interval = self.model.mode and SAMPLE_INTERVAL or .25
    if self.elapsed < interval then return end
    self.elapsed = 0
    Paint(self)
end

local function Native(self)
    local frame = C_Navigation.GetFrame()
    if not Suite.Public(frame) or not frame or NS.Safety.IsForbidden(frame) then return false end
    local native = _G.SuperTrackedFrame
    if not native or NS.Safety.IsForbidden(native) then return false end
    if self.native ~= native then RestoreArt(self) self.native = native end
    self.projection = frame
    return true
end

local function RefreshSource(self)
    if not self.active then return end
    if self.pendingPin then self.pendingPin = nil Navigation.ObservePin(self) end
    if self.restorePending and not NS.IsCombatLocked() then RestoreArt(self) end
    if Navigation.quests then Navigation.AdvanceQuests() end
    self.supported = Navigation.ReadSource(self.model, self.config)
    if not self.supported or not Native(self) then Stop(self) return end
    self.elapsed, self.fastElapsed = 0, 0
    self.driver:SetScript("OnUpdate", OnUpdate)
    Paint(self)
end

local function Arrived(self, _, isWaypoint)
    if Suite.Public(isWaypoint) and isWaypoint == false and (self.config.autoNext or Navigation.travel) then Navigation.QueueNext(self) end
    self.refresh:Request()
end

local function StateChanged(self, event)
    if event == "ZONE_CHANGED_NEW_AREA" or event == "ZONE_CHANGED" or event == "ZONE_CHANGED_INDOORS"
        or event == "PLAYER_ENTERING_WORLD" then Navigation.RefreshMap(self) end
    if event == "PLAYER_REGEN_DISABLED" or event == "PLAYER_REGEN_ENABLED" then Navigation.RefreshMapInput(self) end
    if event == "ADDON_LOADED" then Navigation.RefreshGuides(self) end
    if event == "USER_WAYPOINT_UPDATED" then self.pendingPin = true end
    self.refresh:Request()
end

function Module:Enable()
    if not self.view then
        self.host = Suite.CreateFrame("Frame", nil, UIParent)
        self.host:SetSize(1, 1)
        self.view = Navigation.NewView(self.host)
        self.view.root:SetPoint("CENTER", self.host, "CENTER")
        self.view.root:SetFrameStrata("BACKGROUND")
        self.driver = Suite.CreateFrame("Frame")
        self.view.root:SetScript("OnMouseUp", function(_, button)
            if button == "RightButton" and self.active and self.config.rightClickClear then Navigation.Clear() end
        end)
    end
    C_AddOns.LoadAddOn("Blizzard_QuestNavigation")
    self.refresh = self.context:Coalesce(0, RefreshSource)
    for _, event in ipairs({ "SUPER_TRACKING_CHANGED", "USER_WAYPOINT_UPDATED", "QUEST_LOG_UPDATE",
        "NAVIGATION_FRAME_CREATED", "NAVIGATION_FRAME_DESTROYED", "PLAYER_ENTERING_WORLD",
        "PLAYER_REGEN_ENABLED", "PLAYER_REGEN_DISABLED", "ZONE_CHANGED_NEW_AREA", "ZONE_CHANGED", "ZONE_CHANGED_INDOORS", "ADDON_LOADED",
        "PLAYER_STARTED_MOVING", "PLAYER_STOPPED_MOVING" }) do
        self.context:Event(event, StateChanged, true)
    end
    self.context:Event("NAVIGATION_DESTINATION_REACHED", Arrived, true)
    Navigation.owner = self
    Navigation.RegisterCommand()
    Navigation.EnableLinks()
    Navigation.EnableMap(self)
    Navigation.RefreshGuides(self)
    self:Refresh()
end

function Module:Refresh()
    if not self.view then return end
    self.model.rounded, self.anchor = nil, nil
    self.host:SetParent(self.config.showWithHiddenUI and WorldFrame or UIParent)
    self.screenAnchored = false
    self.driver:SetParent(self.config.showWithHiddenUI and WorldFrame or UIParent)
    Navigation.Style(self.view, self.config)
    Navigation.RefreshMap(self)
    Navigation.RefreshGuides(self)
    RefreshSource(self)
end

function Module:Disable()
    Stop(self)
    Navigation.DisableMap(self)
    Navigation.DisableGuides(self)
    Navigation.owner = nil
    Navigation.UnregisterCommand()
end

Suite.Install("navigation", Module)

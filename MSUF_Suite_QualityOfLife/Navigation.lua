local _, Private = ...
local NS, Suite, Navigation = Private.NS, Private.Suite, Private.Navigation
local Module = { geometry = true, model = {}, screen = { age = 0 }, moving = false, settled = false, quiet = 0,
    running = false, visible = false }
Module.addons = { Blizzard_QuestNavigation = true, Blizzard_WorldMap = true, TomTom = true,
    RXPGuides = true, APR = true, ["APR-Core"] = true, Mapzeroth = true, ["Mapzeroth-Rebuild"] = true,
    DugisGuideViewerZ = true, SilverDragon = true }
local ART = { "Icon", "Arrow", "DistanceText", "IconBorder" }
local SAMPLE_INTERVAL, HIDDEN_INTERVAL, ARROW_INTERVAL = .1, .25, 1 / 30
-- At the arrow's pace a tick is a sample once this long has passed since the
-- last one: just under SAMPLE_INTERVAL, so the third tick counts whatever the
-- clock (in milliseconds) rounds to.
local ARROW_SAMPLE = .095
local SCREEN_SAMPLES = 10
-- Just under a second: the tenth 0.1 s sample (the fourth of a hidden
-- marker) is the safeguard, whatever the summed waits round to.
local SETTLE_SECONDS = .95
local STATE_EVENTS = { "SUPER_TRACKING_CHANGED", "USER_WAYPOINT_UPDATED", "QUEST_LOG_UPDATE",
    "NAVIGATION_FRAME_CREATED", "NAVIGATION_FRAME_DESTROYED", "PLAYER_ENTERING_WORLD",
    "PLAYER_REGEN_ENABLED", "PLAYER_REGEN_DISABLED", "ZONE_CHANGED_NEW_AREA", "ZONE_CHANGED", "ZONE_CHANGED_INDOORS", "ADDON_LOADED",
    "PLAYER_STARTED_MOVING", "PLAYER_STOPPED_MOVING" }
-- The events that start or end a pause (Pause), and the ones that stay
-- registered through it: the two that can end it, and a map pin the player
-- places meanwhile, which fires once and is followed when the pause ends.
local GATE = { PLAYER_REGEN_DISABLED = true, PLAYER_REGEN_ENABLED = true, PLAYER_ENTERING_WORLD = true }
local STAYS = { PLAYER_REGEN_ENABLED = true, PLAYER_ENTERING_WORLD = true, USER_WAYPOINT_UPDATED = true }
local Tick

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

-- Whether the native art can be taken over, without touching it.
local function Ownable(self)
    if self.ownsArt then return true end
    if not self.native then return false end
    local protected = self.native:IsProtected()
    return Suite.Public(protected) and not protected
end

-- Blizzard's marker stays unprotected in the open world, so a destination
-- that appears in combat (a reload, a new guide step) is taken over too.
local function OwnArt(self)
    if self.ownsArt then self.restorePending = false return true end
    if not Ownable(self) then return false end
    self.ownsArt = true
    for _, key in ipairs(ART) do
        local region = self.native[key]
        if not region or NS.Safety.IsForbidden(region) then RestoreArt(self) return false end
        self.context:UnprotectedProperty(region, "GetAlpha", "SetAlpha", 0)
        local alpha = region:GetAlpha()
        if not Suite.Finite(alpha) or alpha ~= 0 then RestoreArt(self) return false end
    end
    return true
end

-- No sampling and no marker. The native art stays as it is: a marker that
-- was taken over stays hidden. Accepted trade for a pause: a destination the
-- Suite does not follow that becomes current meanwhile gets Blizzard's marker
-- back only when the pause ends.
local function Halt(self)
    self.running = false
    if self.interval then
        self.interval = nil
        self.context:Cancel(Tick)
    end
    if self.view then Navigation.Hide(self.view) end
    self.settled = false
    self.model.valid, self.model.mode = false, nil
end

local function Stop(self)
    Halt(self)
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
    model.speed = speed
    Navigation.Readout(model, config, distance, speed)
    Proximity(self, distance)
    model.mode = Navigation.Mode(model, config)
    if not config.showInCombat and NS.InCombat() then model.mode = nil end
    return true
end

-- The parent's centre, size and scales change with the UI scale, the window
-- size or the parent itself. Those are announced (UI_SCALE_CHANGED,
-- DISPLAY_SIZE_CHANGED, Module:Refresh), and the geometry is read then. Every
-- SCREEN_SAMPLES samples it is read again as a safeguard for a change nothing
-- announced. Accepted trade: an unannounced change is used after at most
-- SCREEN_SAMPLES samples that place the direction arrow (about a second at 10
-- frames per second or more, longer below). Samples that place nothing (the
-- marker on screen, hidden or stopped) do not count, and while unannounced
-- unreadable geometry lasts less than that it no longer hides the marker.
local function ReadScreen(self)
    local screen, host = self.screen, self.host
    local parent = host:GetParent()
    local centerX, centerY = parent:GetCenter()
    local sourceScale, scale = UIParent:GetEffectiveScale(), parent:GetEffectiveScale()
    local width, height = parent:GetSize()
    if not Suite.Finite(centerX) or not Suite.Finite(centerY) or not Suite.Finite(sourceScale) or not Suite.Finite(scale)
        or scale <= 0 or not Suite.Finite(width) or not Suite.Finite(height) or width <= 0 or height <= 0 then
        screen.valid = false
        return false
    end
    screen.parent, screen.centerX, screen.centerY = parent, centerX, centerY
    screen.sourceScale, screen.scale = sourceScale, scale
    screen.radiusX, screen.radiusY = math.min(500, width * .38), math.min(230, height * .3)
    screen.valid, screen.age = true, 0
    self.projectionX = nil
    return true
end

local function Position(self, sample)
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
    local screen = self.screen
    if sample then screen.age = screen.age + 1 end
    if (not screen.valid or screen.age >= SCREEN_SAMPLES) and not ReadScreen(self) then return false end
    local x, y = self.projection:GetCenter()
    if not Suite.Finite(x) or not Suite.Finite(y) then return false end
    -- Same projection centre, same parent geometry and still anchored: the
    -- angle and the anchor are already what this would compute. Config changes
    -- arrive through Module:Refresh, which drops the anchor.
    if self.screenAnchored and x == self.projectionX and y == self.projectionY then return true end
    local x0, y0 = x, y
    local sourceScale, scale, centerX, centerY = screen.sourceScale, screen.scale, screen.centerX, screen.centerY
    local radiusX, radiusY = screen.radiusX, screen.radiusY
    x, y = (x * sourceScale - centerX * scale) / scale, (y * sourceScale - centerY * scale) / scale
    local divisor = math.sqrt(x * x / (radiusX * radiusX) + y * y / (radiusY * radiusY))
    if divisor == 0 then return false end
    model.angle = -math.atan2(x, y)
    x, y = x / divisor + config.navigatorX, y / divisor + config.navigatorY
    if config.dynamicOffset then y = y * .9 end
    if not self.screenAnchored or math.abs(x - (self.anchorX or 0)) >= .25 or math.abs(y - (self.anchorY or 0)) >= .25 then
        host:ClearAllPoints()
        host:SetPoint("CENTER", screen.parent, "CENTER", x, y)
        self.anchorX, self.anchorY, self.screenAnchored = x, y, true
    end
    self.projectionX, self.projectionY = x0, y0
    return true
end

local function Lost(self)
    self.model.valid, self.model.mode = false, nil
    Navigation.Hide(self.view)
    RestoreArt(self)
end

-- A marker that cannot show is not placed. The native art is taken over only
-- once the marker is placed, so an unreadable position writes no native alpha.
-- A completed sample of a player who is not moving stays true until the
-- projection moves, the pointer changes the hover fade or an event arrives.
local function Settle(self)
    local x, y = self.projection:GetCenter()
    if not Suite.Finite(x) or not Suite.Finite(y) then return end
    self.sampleX, self.sampleY, self.settled, self.quiet = x, y, true, 0
end

local function Paint(self)
    self.settled = false
    if not self.supported or not ReadPosition(self) then Lost(self) return end
    if not Ownable(self) then Navigation.Hide(self.view) return end
    if not Position(self, true) then Lost(self) return end
    if not OwnArt(self) then Navigation.Hide(self.view) return end
    local model, config, root = self.model, self.config, self.view.root
    local hovered = config.fadeOnHover and root:IsMouseOver()
    model.hovered = Suite.Public(hovered) and hovered == true
    Navigation.Paint(self.view, model, config)
    if not self.moving and model.speed == 0 then Settle(self) end
end

-- Without the native art the marker stays hidden (Paint): a turning arrow
-- must not show it again between two samples.
local function UpdateArrow(self)
    if not self.supported or not self.model.valid or self.model.mode ~= Navigation.DIRECTION
        or not self.ownsArt then return end
    if Position(self) then Navigation.Turn(self.view, self.model.angle) end
end

-- Whether a due sample of a settled marker can be skipped: the projection is
-- where the last sample saw it and the pointer did not change the hover fade.
local function Still(self)
    local x, y = self.projection:GetCenter()
    if not Suite.Finite(x) or not Suite.Finite(y) or x ~= self.sampleX or y ~= self.sampleY then return false end
    if not self.config.fadeOnHover then return true end
    local hovered = self.view.root:IsMouseOver()
    return Suite.Public(hovered) and (hovered == true) == self.model.hovered
end

-- How often the marker needs attention follows from what it shows: the arrow
-- of an off-screen destination turns every ARROW_INTERVAL, a marker on screen
-- is sampled every SAMPLE_INTERVAL and a hidden one every HIDDEN_INTERVAL. One
-- client ticker at that pace takes the place of a frame script, so no code
-- runs in the frames between: at 120 frames per second the script ran 120
-- times a second to sample ten times. The ticker stops with the destination
-- and, like the frame script, while the driver frame is hidden.
-- Accepted trades: a change of pace makes one client ticker object (the frame
-- script made none; a destination that flickers across the screen edge makes
-- one per sample). And off screen a sample falls on a tick of the arrow's
-- ticker: where 1/30 s is not a whole number of frames the marker is sampled
-- and placed up to a sixth less often than by the frame script (at 100
-- frames per second 8.3 samples and 25 placements a second, not 10 and 30);
-- at 30 frames per second and below the cadence is the frame script's.
local function Pace(self)
    local mode = self.model.mode
    self.paced = mode
    local interval = self.running and self.visible
        and (mode == Navigation.DIRECTION and ARROW_INTERVAL or mode and SAMPLE_INTERVAL or HIDDEN_INTERVAL) or nil
    if interval == self.interval then return end
    self.interval = interval
    if not interval then self.context:Cancel(Tick) return end
    self.wait = mode and SAMPLE_INTERVAL or HIDDEN_INTERVAL
    if interval == ARROW_INTERVAL then self.sampledAt = GetTime() end
    self.context:Ticker(interval, Tick)
end

-- One tick. At the arrow's pace a tick turns the arrow until ARROW_SAMPLE has
-- passed since the last sample (two turns, then a sample, at 30 frames per
-- second or more); at the other paces every tick is a sample. A sample places
-- and paints the marker itself. A settled marker skips its samples while
-- nothing it reads can have changed, for at most SETTLE_SECONDS of sample
-- intervals; the sample after that also reads the parent geometry again.
-- Accepted trade: a change that neither moves the projection nor comes from
-- the player's own movement, the pointer or an event (the distance on a
-- transport that moves straight along the line of sight) shows after ten
-- sample ticks: a second, and up to a third more where a frame is not a
-- whole part of the interval (twice as long at 5 frames per second). The
-- ticks are counted, not timed, so a settled marker never reads the clock.
Tick = function(self)
    if self.interval == ARROW_INTERVAL then
        local now = GetTime()
        if now - self.sampledAt < ARROW_SAMPLE then UpdateArrow(self) return end
        self.sampledAt = now
    end
    if self.settled then
        local quiet = self.quiet + self.wait
        if quiet < SETTLE_SECONDS and Still(self) then
            self.quiet = quiet
            return
        end
        if quiet >= SETTLE_SECONDS then self.screen.age = SCREEN_SAMPLES end
    end
    Paint(self)
    if self.model.mode ~= self.paced then Pace(self) end
end

-- The driver frame was shown or hidden (with its parent: the interface, or
-- the world frame for "Show navigation when the interface is hidden").
local function Visible(self, visible)
    self.visible, self.settled = visible, false
    Pace(self)
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
    if not self.active or self.paused then return end
    if self.pendingPin then self.pendingPin = nil Navigation.ObservePin(self) end
    if self.restorePending and not NS.IsCombatLocked() then RestoreArt(self) end
    if Navigation.quests then Navigation.AdvanceQuests() end
    Navigation.RefreshTaxi(self)
    self.supported = Navigation.ReadSource(self.model, self.config)
    if not self.supported or not Native(self) then Stop(self) return end
    self.running = true
    Paint(self)
    Pace(self)
end

local function Arrived(self, _, isWaypoint)
    if Suite.Public(isWaypoint) and isWaypoint == false and (self.config.autoNext or Navigation.travel) then Navigation.QueueNext(self) end
    self.refresh:Request()
end

-- The UI scale or the window size changed: the next placement reads the
-- parent geometry again, and the next sample runs.
local function ScreenChanged(self)
    self.screen.valid, self.settled = false, false
end

local StateChanged

local function Listen(self)
    for _, event in ipairs(STATE_EVENTS) do self.context:Event(event, StateChanged, true) end
    self.context:Event("UI_SCALE_CHANGED", ScreenChanged, true)
    self.context:Event("DISPLAY_SIZE_CHANGED", ScreenChanged, true)
    self.context:Event("NAVIGATION_DESTINATION_REACHED", Arrived, true)
end

-- Combat inside an instance pauses navigation altogether (owner decision
-- 2026-11-11): the marker is hidden, nothing samples and no ticker runs.
-- The events of a fight are not heard: only the two that end the pause stay
-- registered, and with them what the player does on purpose and what fires
-- once at most (a map pin placed, a route stop reached, the flight map,
-- STAYS). So a fight runs no code of this module. The open world keeps
-- "Show navigation in combat".
local function InstanceCombat(event)
    return NS.InCombat(event) and IsInInstance() == true
end

local function Pause(self)
    self.paused = true
    for _, event in ipairs(STATE_EVENTS) do
        if not STAYS[event] then self.context:RemoveEvent(event) end
    end
    self.context:RemoveEvent("UI_SCALE_CHANGED")
    self.context:RemoveEvent("DISPLAY_SIZE_CHANGED")
    Navigation.PauseMap(self)
    Navigation.PauseGuides(self)
    Halt(self)
end

-- The movement events were not heard: the next sample reads the speed, and
-- the screen geometry is read again.
local function Resume(self)
    self.paused, self.moving = false, false
    self.screen.valid = false
    Listen(self)
    Navigation.ResumeMap(self)
    Navigation.RefreshGuides(self)
end

-- Whether a pause consumed the event.
local function Gate(self, event)
    local pause = InstanceCombat(event)
    if pause and not self.paused then Pause(self) end
    if not pause and self.paused then Resume(self) end
    return pause
end

StateChanged = function(self, event)
    if GATE[event] and Gate(self, event) then return end
    -- The player's own movement changes what the next sample reads, not the
    -- destination: the source is not read again (a map pin or a quest costs
    -- client tables on every read), the next tick samples. Only a destination
    -- whose data the client could not give in full (a name that arrives
    -- later, an unreadable source, native art still to hand back) is asked
    -- again, as every movement event did before.
    if event == "PLAYER_STARTED_MOVING" or event == "PLAYER_STOPPED_MOVING" then
        self.moving, self.settled = event == "PLAYER_STARTED_MOVING", false
        if not self.model.incomplete and not self.restorePending then return end
    end
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
        self.driver:SetScript("OnShow", function() Visible(self, true) end)
        self.driver:SetScript("OnHide", function() Visible(self, false) end)
        self.view.root:SetScript("OnMouseUp", function(_, button)
            if button == "RightButton" and self.active and self.config.rightClickClear then Navigation.Clear() end
        end)
    end
    C_AddOns.LoadAddOn("Blizzard_QuestNavigation")
    self.refresh = self.context:Coalesce(0, RefreshSource)
    self.paused = false
    Listen(self)
    Navigation.owner = self
    Navigation.RegisterCommand()
    Navigation.EnableLinks()
    Navigation.EnableMap(self)
    Navigation.EnableTaxi(self)
    -- Enabled in the middle of instanced combat (a reload): start paused.
    if InstanceCombat() then Pause(self) end
    Navigation.RefreshGuides(self)
    self:Refresh()
end

function Module:Refresh()
    if not self.view then return end
    self.model.rounded, self.anchor = nil, nil
    self.host:SetParent(self.config.showWithHiddenUI and WorldFrame or UIParent)
    self.screenAnchored, self.screen.valid, self.projectionX = false, false, nil
    self.driver:SetParent(self.config.showWithHiddenUI and WorldFrame or UIParent)
    self.visible = self.driver:IsVisible() == true
    Navigation.Style(self.view, self.config)
    Navigation.RefreshMap(self)
    Navigation.RefreshGuides(self)
    self.settled = false
    RefreshSource(self)
end

function Module:Disable()
    self.paused = false
    Stop(self)
    Navigation.DisableMap(self)
    Navigation.DisableTaxi(self)
    Navigation.DisableGuides(self)
    Navigation.owner = nil
    Navigation.UnregisterCommand()
end

Suite.Install("navigation", Module)

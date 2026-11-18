-- The real overlay and controller, driven through their module lifecycle,
-- with secret values and client transitions supplied by this fixture.
local root = assert(arg[1])
local secret = setmetatable({}, { __index = function() error("read a secret object") end })
local calls = { positions = 0, headings = 0, art = 0, writes = 0, textures = 0, sounds = 0 }
local animation = { groups = 0, writes = 0, reads = 0 }
local world = { map = 1, art = 1, position = { x = .5, y = .5 }, heading = 0, instance = false }
local zoneMap, overlay = "TOGGLEBATTLEFIELDMINIMAP", "MSUFSUITE_TOGGLE_MAP_OVERLAY"
world.shiftM = zoneMap
local failNextFontString
world.waypoint = { uiMapID = 1, position = { x = .51, y = .49 } }
local function Public(value) return value ~= secret end
local function Finite(value)
    return Public(value) and type(value) == "number" and value == value and math.abs(value) < math.huge
end

local Frame = {}
Frame.__index = Frame
local function NewFrame(parent)
    return setmetatable({ parent = parent, shown = true, scripts = {}, events = {} }, Frame)
end
function Frame:IsVisible() return self.shown and (not self.parent or self.parent:IsVisible()) end
function Frame:SetShown(shown)
    local previous = self.shown
    self.shown = shown
    calls.writes = calls.writes + 1
    local key = shown and "OnShow" or "OnHide"
    if previous ~= shown and self.scripts[key] then self.scripts[key]() end
end
function Frame:Show() self:SetShown(true) end
function Frame:Hide() self:SetShown(false) end
function Frame:SetScript(event, fn) self.scripts[event] = fn end
function Frame:RegisterEvent(event) self.events[event] = true end
function Frame:UnregisterEvent(event) self.events[event] = nil end
function Frame:GetFrameLevel() return self.level or 1 end
function Frame:SetFrameLevel(level) self.level = level end
function Frame:CreateMaskTexture() return NewFrame(self) end
function Frame:CreateFontString(_, _, template)
    if failNextFontString then
        failNextFontString = false
        error("injected map construction failure")
    end
    local label = NewFrame(self)
    label.font = template
    return label
end
function Frame:SetPoint(...) self.point = { ... }; calls.writes = calls.writes + 1 end
function Frame:SetSize(w, h) self.width, self.height = w, h end
function Frame:SetTexture(file) self.file = file; calls.textures = calls.textures + 1 end
function Frame:SetTexCoord(...) self.coords = { ... } end
function Frame:SetRotation(angle) self.angle = angle; calls.writes = calls.writes + 1 end
function Frame:CreateAnimationGroup()
    animation.groups = animation.groups + 1
    local group = { playing = false }
    function group:CreateAnimation(kind)
        assert(kind == "Translation" and not self.slide)
        local slide = {}
        function slide:SetDuration(seconds) self.duration = seconds end
        function slide:SetOffset(x, y)
            assert(y == 0)
            self.x = x
            animation.writes = animation.writes + 1
        end
        self.slide = slide
        return slide
    end
    function group:Play(reverse)
        self.playing, self.progress, self.reverse = true, reverse and 1 or 0, reverse
        animation.writes = animation.writes + 1
    end
    function group:IsPlaying()
        animation.reads = animation.reads + 1
        return self.playing
    end
    function group:GetProgress()
        animation.reads = animation.reads + 1
        return self.progress
    end
    function group:Stop()
        self.playing, self.progress = false, 0
        animation.writes = animation.writes + 1
    end
    function group:SetScript(event, callback)
        assert(event == "OnFinished")
        self.finished = callback
    end
    function group:Finish()
        assert(self.playing)
        self.playing, self.progress = false, 1
        self.finished(self)
    end
    return group
end
function Frame:EnableMouse(on) self.mouse = on end
function Frame:AddMaskTexture(mask) self.mask = mask end
function Frame:SetText(text)
    assert(self.font, "FontString:SetText(): Font not set")
    self.text = text
end
function Frame:GetFont() return self.font end
for _, method in ipairs({ "SetClipsChildren", "SetClampedToScreen", "SetAllPoints", "SetAtlas", "SetDesaturated", "SetFrameStrata",
    "SetColorTexture", "SetVertexColor", "SetTextColor", "SetHeight", "SetAlpha" }) do
    Frame[method] = function() end
end

UIParent = NewFrame()
function UIParent:GetEffectiveScale() return .91 end
PixelUtil = { GetPixelToUIUnitFactor = function() return .73 end }
SOUNDKIT = { IG_QUEST_LOG_OPEN = 123 }
function PlaySound(sound, channel)
    assert(sound == SOUNDKIT.IG_QUEST_LOG_OPEN and channel == nil, "expected the native map opening sound and channel")
    calls.sounds = calls.sounds + 1
end
function IsInInstance() return world.instance end
function GetBindingKey(command)
    assert(command == overlay)
    return world.overlayKey
end
function GetBindingAction(key, overrides)
    assert(key == "SHIFT-M")
    if overrides then
        if world.externalBinding then return world.externalBinding end
        if world.bindingOwner then return overlay end
    end
    return world.shiftM
end
function SetOverrideBinding(owner, priority, key, command)
    assert(not world.combat and not priority and key == "SHIFT-M" and command == overlay)
    assert(not world.bindingOwner, "duplicate binding write")
    -- A synchronous UPDATE_BINDINGS may arrive before the change is readable.
    if owner.events.UPDATE_BINDINGS then owner.scripts.OnEvent(owner, "UPDATE_BINDINGS") end
    world.bindingOwner = owner
end
function ClearOverrideBindings(owner)
    assert(not world.combat and world.bindingOwner == owner)
    world.bindingOwner = nil
end
function GetPlayerFacing() calls.headings = calls.headings + 1; return world.heading end
local function Tiles(map)
    local out = {}
    for index = 1, 25 do out[index] = map * 1000 + world.art * 100 + index end
    return out
end
C_Map = {
    GetBestMapForUnit = function() return world.map end,
    GetMapArtID = function(map) assert(map == world.map); return world.art end,
    GetMapArtLayers = function()
        calls.art = calls.art + 1
        if world.map == 2 then return { { layerWidth = 180, layerHeight = 120, tileWidth = 256, tileHeight = 192 } } end
        return { { layerWidth = 1050, layerHeight = 790, tileWidth = 256, tileHeight = 192 } }
    end,
    GetMapArtLayerTextures = Tiles,
    GetPlayerMapPosition = function(map)
        assert(Finite(map))
        calls.positions = calls.positions + 1
        if map == world.map then return world.position end
    end,
    GetUserWaypoint = function() return world.waypoint end,
}
local hud, movers, msg, ctx
local S = {
    CreateFrame = function(_, _, parent) return NewFrame(parent) end,
    CreateTexture = NewFrame,
    SetFont = function(label, font) label.font = font end,
    GlobalFontPath = function() return "font" end,
    Text = function(text) return text == "N E S W" and "N O S W" or text end,
    Public = Public, Finite = Finite, RGB = function() return .4, .8, .9 end,
    Print = function(text) msg = text end,
    Install = function(id, module) assert(id == "navigationHUD"); hud = module end,
    RegisterOwnedMover = function(_, element, mover) movers[element] = mover end,
    Dispatch = function(fn, ...) return fn(...) end,
}
local NS = { Suite = S, Text = S.Text, RGB = S.RGB,
    InCombat = function(event) return event == "PLAYER_REGEN_DISABLED" or world.combat == true end }
local private = { Suite = S, NS = NS }
assert(loadfile(root .. "/MSUF_Suite/Core/Compass.lua"))("Core", NS)
assert(loadfile(root .. "/MSUF_Suite_Modules/CompassHeading.lua"))("Modules", private)
assert(loadfile(root .. "/MSUF_Suite_QualityOfLife/NavigationHUDMap.lua"))("QoL", private)
assert(loadfile(root .. "/MSUF_Suite_QualityOfLife/NavigationHUD.lua"))("QoL", private)
local dataText = { Suite = S, NS = NS }
assert(loadfile(root .. "/MSUF_Suite_DataTexts/Compass.lua"))("DataTexts", dataText)
ctx = { events = {}, deferred = {} }
local compassTask = { Cancel = function() ctx.ticker = nil end }
function S.ScheduleDataTick(owner, interval, callback)
    assert(owner == "compassHeading" and interval == .05 and not ctx.ticker, "only one timed heading job is allowed")
    ctx.ticker = callback
    return compassTask
end
function ctx:Event(event, callback) self.events[event] = callback end
function ctx:RemoveEvent(event) self.events[event] = nil end
function ctx:After(_, callback) self.deferred[callback] = true end
function ctx:Cancel(callback)
    self.deferred[callback] = nil
end
local function Fire(event)
    assert(ctx.events[event], event)(hud, event)
end
local function BindingEvent(event)
    local driver = hud.driver
    assert(driver.events[event], event)
    driver.scripts.OnEvent(driver, event)
end
local function Tick()
    local callback = assert(ctx.ticker)
    ctx.ticker = nil
    callback()
end
local function Resume()
    local fn = assert(next(ctx.deferred), "missing deferred recovery")
    ctx.deferred[fn] = nil
    fn(hud)
end
local function Present(map, compass)
    assert(hud.map.frame:IsVisible() == map, "wrong overlay visibility")
    assert((hud.compass and hud.compass.frame:IsVisible() or false) == compass, "wrong compass visibility")
end
local function TileCount()
    local count = 0
    for _, slot in pairs(hud.map.tiles) do if slot.visible then count = count + 1 end end
    return count
end

hud.context, hud.active = ctx, true
hud.config = { mapWidth = 360, mapZoom = 2, mapOpacity = 55, mapX = 0, mapY = 24,
    compassWidth = 280, compassX = 0, compassY = -62, showCompass = false, showWaypoint = true, hideInCombat = true }
hud:Enable()
Present(false, false)
assert(not next(ctx.events) and not ctx.ticker and calls.positions == 0 and calls.headings == 0)
assert(animation.groups == 0, "a disabled compass created an animation")
assert(world.bindingOwner == hud.driver and GetBindingAction("SHIFT-M", true) == overlay)
assert(GetBindingAction("SHIFT-M", false) == zoneMap)
world.overlayKey = "ALT-M"
hud.config.shortcutMode = 2
hud:Refresh()
BindingEvent("UPDATE_BINDINGS")
assert(not world.bindingOwner and GetBindingAction("SHIFT-M", true) == zoneMap)
assert(GetBindingKey(overlay) == "ALT-M", "switching modes changed the saved shortcut")
hud.config.shortcutMode = 1
hud:Refresh()
assert(world.bindingOwner == hud.driver and GetBindingKey(overlay) == "ALT-M")
hud.config.shortcutMode, world.combat = 2, true
BindingEvent("UPDATE_BINDINGS")
assert(world.bindingOwner == hud.driver and hud.driver.events.PLAYER_REGEN_ENABLED)
world.combat = false
BindingEvent("PLAYER_REGEN_ENABLED")
assert(not world.bindingOwner and GetBindingAction("SHIFT-M", true) == zoneMap)
hud.config.shortcutMode = 1
hud:Refresh()
world.overlayKey, world.shiftM = nil, "CUSTOM_ACTION"
BindingEvent("UPDATE_BINDINGS")
assert(not world.bindingOwner and GetBindingAction("SHIFT-M", true) == "CUSTOM_ACTION")
world.shiftM, world.externalBinding = zoneMap, "THIRD_PARTY_ACTION"
BindingEvent("ACTIVE_GAME_MODE_UPDATED")
assert(not world.bindingOwner)
world.externalBinding = nil
BindingEvent("UPDATE_BINDINGS")
assert(world.bindingOwner == hud.driver)
movers = {}
hud:RegisterMovers()
assert(movers.map.getFrame() == hud.map.frame and not movers.compass.visible())
S.editMode = true
hud:Refresh()
Present(true, false)
assert(hud.map.backdrop.shown and not hud.map.plane.shown and not ctx.ticker and calls.positions == 0)
S.editMode = false
hud:HideEditPreview()
Present(false, false)
assert(calls.sounds == 0, "the edit preview must stay silent")
assert(hud:ToggleMap())
Present(true, false)
assert(calls.sounds == 1, "opening the overlay must play the map sound once")
assert(hud.map.frame.mouse == false and hud.map.plane.mouse == false)
assert(hud.map.pin.shown and TileCount() > 0 and TileCount() <= 9)
local writes, textures = calls.writes, calls.textures
Tick()
world.position = { x = .50001, y = .5 }
Tick()
assert(calls.writes == writes and calls.textures == textures, "motionless or subpixel tick repainted")
world.position.x = .505
Tick()
assert(calls.writes == writes + 1 and calls.textures == textures, "panning moved more than the shared plane")
local x = hud.map.offsetX * hud.map.pixelScale
assert(math.abs(x - math.floor(x + .5)) < 1e-6, "panning did not snap to the physical pixel grid")
world.waypoint = { uiMapID = 1, position = secret }
Fire("USER_WAYPOINT_UPDATED")
assert(not hud.map.pin.shown)
world.waypoint = { uiMapID = 2, position = { x = .505, y = .5 } }
Fire("USER_WAYPOINT_UPDATED")
assert(not hud.map.pin.shown, "cross-zone waypoint leaked into the map")
world.position = { x = 1, y = 1 }
Tick()
assert(TileCount() <= 9)
local edge = assert(hud.map.tiles[((5 - 1) % 3) * 3 + (5 - 1) % 3 + 1])
assert(edge.visible and edge.texture.coords[2] == 26 / 256 and edge.texture.coords[4] == 22 / 192)
world.art = 2
for _ = 1, 20 do Tick() end
assert(hud.map.art.artID == 2 and calls.art == 2, "same-map phasing did not replace the tiles")
world.heading = secret
Tick()
assert(hud.map.dot.shown and not hud.map.arrow.shown, "missing heading needs a live position dot")

hud.config.showCompass, world.heading = true, -math.pi / 2
hud:Refresh()
Present(true, true)
assert(math.abs(hud.map.arrow.angle + math.pi / 2) < 1e-6 and movers.compass.visible())
assert(hud.compass.cardinals[1].text == "O", "east is missing or was not localized")
local compass = hud.compass
assert(animation.groups == 1 and not compass.motion.playing)
local anchor = compass.rail.point[4]
local previousWrites = calls.writes
world.heading = -math.rad(89.53)
Tick()
assert(compass.motion.playing and compass.rail.point[4] == anchor and calls.writes == previousWrites,
    "starting a compass slide jumped to the destination before drawing the motion")
assert(not compass.motion.reverse and compass.slide.x > 0 and compass.slide.x < compass.step)
local motionWrites, motionReads = animation.writes, animation.reads
local shift = compass.slide.x
world.heading = -math.rad(88.5)
Tick()
world.heading = -math.rad(87)
Tick()
assert(compass.rail.point[4] == anchor and animation.writes == motionWrites and animation.reads == motionReads,
    "new samples touched an in-flight slide")
compass.motion:Finish()
assert(math.abs(compass.rail.point[4] - anchor - shift) < 1e-6 and compass.motion.playing,
    "the finished slide did not commit its anchor and continue to the latest sample")
compass.motion:Finish()
assert(not compass.motion.playing and compass.anchorPixels == compass.offsetPixels)
local jitter = -90 - (compass.anchorPixels + .6) / compass.pixelsPerDegree
world.heading = -math.rad(jitter)
motionWrites, previousWrites = animation.writes, calls.writes
Tick()
assert(animation.writes == motionWrites and calls.writes == previousWrites, "subpixel jitter restarted the slide")

world.heading = -math.rad(55)
Tick()
assert(not compass.motion.playing, "a large heading change must snap instead of sliding the tape out of view")
world.heading = -math.rad(57)
Tick()
assert(compass.cardinals[0].shown, "the destination hid a cardinal letter while it was still sliding to the edge")
compass.motion:Finish()
assert(compass.cardinals[0].shown, "cardinal letters must remain in the clipped tape")
local headings = calls.headings
motionWrites, motionReads = animation.writes, animation.reads
previousWrites = calls.writes
Tick()
assert(calls.headings == headings + 1, "the map and compass did not share a heading sample")
assert(calls.writes == previousWrites and animation.writes == motionWrites and animation.reads == motionReads,
    "the compass did native animation or geometry work for an unchanged heading")
world.heading = -math.rad(359.5)
Tick()
assert(not compass.motion.playing, "a large heading change must snap instead of sliding the tape out of view")
world.heading = -math.rad(.5)
Tick()
assert(compass.motion.playing and compass.slide.x < 0 and compass.slide.x > -2 * compass.step, "north wrap took the long route")
anchor, shift = compass.rail.point[4], compass.slide.x
compass.motion:Finish()
assert(math.abs(compass.rail.point[4] - anchor - shift - compass.periodPixels * compass.unitsPerPixel) < 1e-6,
    "north wrap committed an anchor with a different pixel phase")
world.heading = -math.rad(359.5)
Tick()
assert(compass.motion.playing and compass.slide.x > 0 and compass.slide.x < 2 * compass.step, "reverse north wrap took the long route")
Fire("PLAYER_REGEN_DISABLED")
Present(false, false)
assert(not ctx.ticker and hud.mapRequested and not compass.motion.playing, "regen event did not pause before lockdown")
previousWrites = calls.writes
compass.motion.finished(compass.motion)
assert(calls.writes == previousWrites and not compass.motion.playing, "a stale completion moved a hidden compass")
Fire("PLAYER_REGEN_ENABLED")
Present(true, true)
assert(not compass.motion.playing, "resuming must place the compass at the current heading immediately")
world.instance = true
local positionCalls = calls.positions
BindingEvent("PLAYER_ENTERING_WORLD")
Fire("PLAYER_ENTERING_WORLD")
Present(false, false)
assert(not ctx.ticker and not next(ctx.deferred) and calls.positions == positionCalls and not world.bindingOwner)
world.instance, world.position, world.heading = false, nil, nil
BindingEvent("PLAYER_ENTERING_WORLD")
assert(world.bindingOwner == hud.driver)
Fire("ZONE_CHANGED_NEW_AREA")
Present(false, false)
assert(not ctx.ticker)
world.map, world.position, world.heading = 2, { x = .7, y = .6 }, 0
Resume()
Present(true, true)
assert(TileCount() == 1 and hud.map.art.mapID == 2 and hud.map.pin.shown, "handoff to a single-tile map failed")
world.position, world.heading = secret, secret
Fire("ADDON_RESTRICTION_STATE_CHANGED")
Present(false, false)
assert(not ctx.ticker)
Resume()
Present(false, false)
assert(not ctx.ticker)
world.position, world.heading = { x = .7, y = .6 }, 0
Fire("ADDON_RESTRICTION_STATE_CHANGED")
Resume()
Present(true, true)

UIParent:Hide()
hud.driver.scripts.OnHide()
Present(false, false)
assert(not ctx.ticker)
UIParent:Show()
hud.driver.scripts.OnShow()
Present(true, true)
assert(not hud:ToggleMap())
Present(false, true)
assert(calls.sounds == 1, "visibility recovery and closing must stay silent")
positionCalls = calls.positions
Tick()
assert(calls.positions == positionCalls and not ctx.events.USER_WAYPOINT_UPDATED, "compass alone uses the map API")
hud.config.showCompass = false
hud:Refresh()
assert(not ctx.ticker and not next(ctx.events))

local function CompassSlot(width)
    local slot = NewFrame(UIParent)
    slot.label = slot:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    NS.Compass.LayoutSlot(slot, width, 28, 5, .8, "57c7df")
    return slot
end
local wide, narrow = CompassSlot(120), CompassSlot(45)
local BindCompass = dataText.DataTextCompass.Bind
world.heading = -math.rad(90)
BindCompass({ wide, narrow })
assert(wide.dataCompass.showing and wide.dataCompass.view.frame:IsVisible() and not wide.label.shown)
assert(narrow.label.text == "90\194\176" and not narrow.dataCompass.view, "a narrow place needs a degree readout")
assert(ctx.ticker, "DataTexts must be able to use the compass independently")
hud.config.showCompass = true
hud:Refresh()
headings, positionCalls = calls.headings, calls.positions
world.heading = -math.rad(95)
Tick()
assert(calls.headings == headings + 1 and calls.positions == positionCalls, "the two compasses did not share one heading read")
assert(wide.dataCompass.view.motion.playing and hud.compass.motion.playing and narrow.label.text == "95\194\176")
BindCompass()
assert(ctx.ticker and not wide.dataCompass.view.motion.playing, "retiring the place should only stop its own motion")
NS.Compass.ClearSlot(wide)
assert(wide.label.shown and not wide.dataCompass.view.frame:IsVisible(), "switching sources left the compass over the text")
hud.config.showCompass = false
hud:Refresh()
assert(not ctx.ticker, "the shared job must stop when the last display hides")

world.instance = true
assert(not hud:ToggleMap() and msg == "The map overlay is unavailable here.")
assert(not hud.mapRequested and not ctx.ticker)
assert(calls.sounds == 1, "an unavailable overlay must stay silent")
hud.active, world.combat = false, true
hud:Disable()
assert(hud.map.art == nil and TileCount() == 0)
assert(world.bindingOwner == hud.driver and hud.driver.events.PLAYER_REGEN_ENABLED)
assert(not hud.driver.events.UPDATE_BINDINGS and not hud.driver.events.PLAYER_ENTERING_WORLD)
world.combat = false
BindingEvent("PLAYER_REGEN_ENABLED")
assert(not world.bindingOwner and not next(hud.driver.events))
local config = hud.config
assert(loadfile(root .. "/MSUF_Suite_QualityOfLife/NavigationHUD.lua"))("QoL", private)
hud.context, hud.active, hud.config = ctx, true, config
failNextFontString = true
local enabled, failure = pcall(hud.Enable, hud)
assert(not enabled and failure:find("injected map construction failure", 1, true))
hud.active = false
hud:Disable()
assert(not hud.driver and not hud.map, "failed activation left a partial HUD behind")
assert(not ctx.ticker and not next(ctx.events))
hud.active, world.instance = true, false
hud:Enable()
assert(hud:ToggleMap(), "failed activation could not be retried")
Present(true, false)
assert(calls.sounds == 2, "a later opening must also play the map sound")
hud.active = false
hud:Disable()
assert(not world.bindingOwner)
print("PASS map overlay and compass lifecycle, bounded tiles, world recovery and Shift-M binding ownership")

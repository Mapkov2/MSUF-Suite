local root = assert(arg[1], "repository root required")
local cursor
local combat, instance, gcdActive = false, false, false
local gcdDuration, castDuration = { gcd = true }, nil
local cursorReads = 0
hooksecurefunc = function() error("the cursor highlight hooks no Blizzard function") end
local function Region()
    local r = { scripts = {}, shown = false }
    function r:SetPoint(...) self.point = { ... } end
    function r:SetAllPoints() end
    function r:ClearAllPoints() self.point = nil end
    function r:SetSize(w, h) self.width, self.height = w, h end
    function r:SetAlpha(a) self.alpha = a end
    function r:SetColorTexture(...) self.color = { ... } end
    function r:SetVertexColor() end
    function r:SetRotation() end
    function r:SetFrameStrata() end
    function r:EnableMouse() end
    function r:SetDrawBling() end
    function r:SetHideCountdownNumbers() end
    function r:SetSwipeColor() end
    function r:SetDrawEdge(on) self.edge = on end
    function r:SetCooldownFromDurationObject(duration, autoHide)
        assert(type(duration) == "table", "native cooldown requires a duration object")
        self.duration, self.autoHide = duration, autoHide
    end
    function r:SetCooldown(start, duration) self.sample = { start, duration } end
    function r:Clear() self.sample, self.duration = nil, nil end
    function r:SetScript(key, handler) self.scripts[key] = handler end
    function r:SetShown(on) self.shown = on == true end
    function r:Show() self.shown = true end
    function r:Hide() self.shown = false end
    function r:GetEffectiveScale() return 2 end
    return r
end
UIParent = Region()
GetTime = function() return 100 end
-- GetMouseFoci returns the regions under the pointer; WorldFrame is the 3D world.
WorldFrame = Region()
local underPointer = { WorldFrame }
GetMouseFoci = function() return underPointer end
GetCursorPosition = function() cursorReads = cursorReads + 1; return 100, 140 end
IsInInstance = function() return instance end
UnitCastingDuration = function() return castDuration end
UnitChannelDuration = function() return nil end
C_Spell = {
    GetSpellCooldownDuration = function(id) assert(id == 61304); return gcdDuration end,
    GetSpellCooldown = function() return { isActive = gcdActive } end,
}
local movers = {}
local s = {
    CreateFrame = Region, CreateTexture = Region,
    RGB = function() return 1, 1, 1 end,
    Public = function(v) return v ~= "secret" end,
    Finite = function(v) return type(v) == "number" and v == v end,
    Install = function(id, m) assert(id == "cursorEffects"); cursor = m end,
    RegisterOwnedMover = function(id, element, spec)
        assert(id == "cursorEffects" and element == "gcd", "the cursor has one Edit Mode element")
        movers.gcd = spec
    end,
}
local ns = { IsCombatLocked = function() return combat end, AnchorPoints = { [5] = "CENTER", [8] = "BOTTOM" } }
ns.InCombat = assert(loadfile(root .. "/tools/tests/suite_test_support.lua"))().InCombat(root,
    function() return combat end)
assert(loadfile(root .. "/MSUF_Suite_QualityOfLife/CursorEffects.lua"))("cursor", { NS = ns, Suite = s })
cursor.context = { events = {} }
function cursor.context:Event(event, callback) self.events[event] = callback end
function cursor.context:RemoveEvent(event) self.events[event] = nil end
cursor.active = true
cursor.config = {
    color = "ffffff", ringShape = 1, size = 36, opacity = 85, showTrail = false,
    showGCD = true, showCast = true, combatOnly = false, zone = 1,
    showDot = false, dotSize = 4, cameraHoldOnly = false, castSpark = false,
    gcdDetached = false, gcdSize = 40, gcdOpacity = 80, gcdPoint = 5, gcdX = 0, gcdY = -140,
    ringWhen = 1, gcdWhen = 1, castWhen = 1,
}
local function Shown()
    local count = 0
    for _, piece in ipairs(cursor.pieces) do if piece.shown then count = count + 1 end end
    return count
end
cursor:Enable()
assert(cursor.host.shown and cursor.host.scripts.OnUpdate, "ring did not follow")
assert(cursor.host.point[4] == 50 and cursor.host.point[5] == 70, "UI scale was not applied")
assert(Shown() == 20 and not cursor.gcd.shown, "inactive GCD must stay hidden despite a duration object")

gcdActive = true
cursor.context.events.UNIT_SPELLCAST_SUCCEEDED(cursor)
assert(cursor.gcd.shown and cursor.gcd.duration == gcdDuration and cursor.gcd.autoHide,
    "GCD did not use the native duration")
castDuration = { cast = true }
cursor.context.events.UNIT_SPELLCAST_START(cursor)
assert(cursor.cast.shown and not cursor.gcd.shown, "the cast did not take the place of the global cooldown")
castDuration = nil
cursor.context.events.UNIT_SPELLCAST_STOP(cursor)
assert(not cursor.cast.shown and cursor.gcd.shown, "the global cooldown did not return after the cast")
gcdActive = false
cursor.gcd.scripts.OnCooldownDone()
assert(not cursor.gcd.shown, "completed GCD stayed visible")

-- Shapes reuse the pooled pieces; switching leaves none stale.
cursor.config.ringShape = 2
cursor:Refresh()
assert(Shown() == 48, "thin ring did not use its pooled segments")
cursor.config.ringShape = 3
cursor:Refresh()
assert(Shown() == 20, "switching shapes left stale segments visible")
-- No ring and no progress: nothing follows the pointer.
cursor.config.ringShape, cursor.config.showTrail = 4, false
cursor:Refresh()
local before = cursorReads
assert(Shown() == 0 and not cursor.host.shown and not cursor.host.scripts.OnUpdate,
    "an empty highlight kept sampling the pointer")
assert(cursorReads == before)
gcdActive = true
cursor.context.events.UNIT_SPELLCAST_SUCCEEDED(cursor)
assert(cursor.host.shown and cursor.gcd.shown and cursor.host.scripts.OnUpdate,
    "a ring-less progress fill did not follow the pointer")
gcdActive = false
cursor.gcd.scripts.OnCooldownDone()
assert(not cursor.host.shown and not cursor.host.scripts.OnUpdate, "an ended fill kept the pointer callback")
cursor.config.ringShape = 1

-- Location rule for the whole highlight.
cursor.config.zone = 2
cursor:Refresh()
assert(not cursor.host.shown and not cursor.host.scripts.OnUpdate, "instances-only highlight showed outside instances")
instance = true
cursor.context.events.ZONE_CHANGED_NEW_AREA(cursor, "ZONE_CHANGED_NEW_AREA")
assert(cursor.host.shown, "entering an instance did not show the highlight")
cursor.config.zone = 3
cursor:Refresh()
assert(not cursor.host.shown, "outside-only highlight showed inside an instance")
instance, cursor.config.zone = false, 1

-- Combat only: PLAYER_REGEN_DISABLED arrives before the lockdown starts.
cursor.config.combatOnly, cursor.config.showTrail = true, true
cursor:Refresh()
assert(not cursor.host.shown and not cursor.trailHost.shown and not cursor.host.scripts.OnUpdate,
    "combat-only highlight showed outside combat")
cursor.context.events.PLAYER_REGEN_DISABLED(cursor, "PLAYER_REGEN_DISABLED")
assert(cursor.host.shown and cursor.trailShown and cursor.host.scripts.OnUpdate,
    "combat-only highlight did not appear on combat entry")
combat = true
castDuration = { cast = true }
cursor.context.events.UNIT_SPELLCAST_START(cursor)
assert(cursor.cast.shown, "combat-only highlight dropped a cast in combat")
combat, castDuration = false, nil
cursor.context.events.PLAYER_REGEN_ENABLED(cursor, "PLAYER_REGEN_ENABLED")
assert(not cursor.host.shown and not cursor.host.scripts.OnUpdate, "combat-only highlight stayed after combat")
cursor.config.combatOnly, cursor.config.showTrail = false, false
cursor:Refresh()

-- The centre dot, also without a ring.
cursor.config.showDot, cursor.config.dotSize = true, 6
cursor:Refresh()
assert(cursor.dot.shown and cursor.dot.width == 6 and Shown() == 20, "the dot did not show with the ring")
cursor.config.ringShape = 4
cursor:Refresh()
assert(cursor.dot.shown and Shown() == 0 and cursor.host.scripts.OnUpdate, "a dot alone did not follow the pointer")
cursor.config.ringShape, cursor.config.showDot = 1, false
cursor:Refresh()
assert(not cursor.dot.shown, "a switched-off dot stayed")

-- A bright edge on the cast fill.
cursor.config.castSpark = true
cursor:Refresh()
assert(cursor.cast.edge == true, "the cast fill drew no edge")
cursor.config.castSpark = false
cursor:Refresh()
assert(cursor.cast.edge == false, "a switched-off edge stayed")

-- Only while the camera turns: a mouse button held down on the 3D world.
cursor.config.cameraHoldOnly, cursor.config.showDot = true, true
cursor:Refresh()
assert(cursor.context.events.GLOBAL_MOUSE_DOWN and not cursor.host.shown and not cursor.dot.shown,
    "the camera mode showed the pointer without a camera turn")
local Mouse = function(event, button) cursor.context.events[event](cursor, event, button) end
Mouse("GLOBAL_MOUSE_DOWN", "RightButton")
assert(cursor.host.shown and Shown() == 20 and cursor.dot.shown, "turning the camera did not show the ring")
Mouse("GLOBAL_MOUSE_DOWN", "LeftButton")
Mouse("GLOBAL_MOUSE_UP", "RightButton")
assert(cursor.host.shown, "the other held button stopped counting")
Mouse("GLOBAL_MOUSE_UP", "LeftButton")
assert(not cursor.host.shown and not cursor.host.scripts.OnUpdate, "releasing the camera kept the ring")
underPointer = { Region() }
Mouse("GLOBAL_MOUSE_DOWN", "LeftButton")
assert(not cursor.host.shown, "a click on a frame counted as a camera turn")
Mouse("GLOBAL_MOUSE_UP", "LeftButton")
underPointer = { WorldFrame }
Mouse("GLOBAL_MOUSE_DOWN", "MiddleButton")
assert(not cursor.host.shown, "another mouse button counted as a camera turn")
cursor.config.cameraHoldOnly, cursor.config.showDot = false, false
cursor:Refresh()
assert(not cursor.context.events.GLOBAL_MOUSE_DOWN and cursor.host.shown, "the camera mode kept its listeners")

-- The global cooldown on its own circle, placed in MSUF Edit Mode.
assert(movers.gcd and movers.gcd.getFrame() == cursor.gcdHost and movers.gcd.pointKey == "gcdPoint"
    and movers.gcd.sizeKeys[1] == "gcdSize" and not movers.gcd.visible(), "the circle's Edit Mode element is wrong")
cursor.config.gcdDetached, cursor.config.gcdPoint, cursor.config.gcdY = true, 8, -90
cursor:Refresh()
assert(movers.gcd.visible() and cursor.gcdHost.point[1] == "BOTTOM" and cursor.gcdHost.point[5] == -90
    and cursor.gcdHost.width == 40 and cursor.gcdHost.alpha == .8, "the circle ignored its placement")
gcdActive = true
cursor.context.events.UNIT_SPELLCAST_SUCCEEDED(cursor)
assert(cursor.gcdFree.shown and cursor.gcdHost.shown and cursor.gcdFree.duration == gcdDuration
    and not cursor.gcd.shown, "the detached circle did not take the global cooldown")
castDuration = { cast = true }
cursor.context.events.UNIT_SPELLCAST_START(cursor)
assert(cursor.cast.shown and cursor.gcdFree.shown, "a cast hid the detached circle")
castDuration = nil
cursor.context.events.UNIT_SPELLCAST_STOP(cursor)
gcdActive = false
cursor.gcdFree.scripts.OnCooldownDone()
assert(not cursor.gcdFree.shown and not cursor.gcdHost.shown, "an ended global cooldown kept the circle")
s.editMode = true
cursor:Refresh()
assert(cursor.gcdHost.shown and cursor.gcdFree.shown and cursor.gcdFree.sample, "Edit Mode showed no circle to place")
cursor:HideEditPreview()
s.editMode = false
cursor:Refresh()
assert(not cursor.gcdHost.shown and not cursor.gcdFree.sample, "the Edit Mode circle stayed")
cursor.config.gcdDetached = false
cursor:Refresh()

-- Each part keeps its own combat rule.
cursor.config.ringWhen, cursor.config.castWhen = 2, 3
cursor:Refresh()
assert(cursor.context.events.PLAYER_REGEN_DISABLED and Shown() == 0, "a combat-only ring showed outside combat")
gcdActive = true
cursor.context.events.UNIT_SPELLCAST_SUCCEEDED(cursor)
assert(cursor.gcd.shown and cursor.host.shown, "the always-shown global cooldown waited for the ring")
cursor.context.events.PLAYER_REGEN_DISABLED(cursor, "PLAYER_REGEN_DISABLED")
combat = true
assert(Shown() == 20, "the combat-only ring did not appear on combat entry")
castDuration = { cast = true }
cursor.context.events.UNIT_SPELLCAST_START(cursor)
assert(not cursor.cast.shown, "an out-of-combat cast fill showed in combat")
combat, castDuration, gcdActive = false, nil, false
cursor.context.events.PLAYER_REGEN_ENABLED(cursor, "PLAYER_REGEN_ENABLED")
assert(Shown() == 0, "the combat-only ring stayed after combat")
cursor.config.ringWhen, cursor.config.castWhen = 1, 1
cursor:Refresh()
assert(not cursor.context.events.PLAYER_REGEN_DISABLED, "per-part rules kept the combat listener")

cursor.config.gcdDetached, cursor.config.showDot = true, true
cursor:Refresh()
cursor:Disable()
assert(not cursor.dot.shown and not cursor.gcdHost.shown, "disable kept the dot or the circle")
assert(not cursor.host.shown and not cursor.host.scripts.OnUpdate and not cursor.gcd.shown
    and not cursor.trailHost.shown, "disable left an effect or cursor callback alive")
print("PASS cursor highlight shapes, dot, camera mode, own GCD circle, edge, per-part and combat rules")

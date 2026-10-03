-- Exercise the real Suite context, synchronous combat text, secret sinks,
-- native animation lifetime, fixed pool, Edit Mode and state restoration.
local root = assert(arg[1], "repository root required")
local created, fontCount, reads, writes = 0, 0, 0, 0
local duringEvent, vehicle, validEvent, locked = false, false, true, false
local activeUnit, cvar = "target", "1"
local secret = setmetatable({}, {
    __tostring = function() error("secret stringified in Lua") end,
    __concat = function() error("secret concatenated") end,
    __add = function() error("secret arithmetic") end,
    __lt = function() error("secret compared") end,
    __le = function() error("secret compared") end,
})
local healSecret = setmetatable({}, getmetatable(secret))
local firstPayload, secondPayload = secret, healSecret
local Widget
Widget = function()
    local w = { scripts = {}, events = {}, shown = false }
    function w:SetScript(event, fn)
        assert(event ~= "OnUpdate", "combat text must not install OnUpdate")
        self.scripts[event] = fn
    end
    function w:RegisterEvent(event)
        assert(event ~= "COMBAT_LOG_EVENT_UNFILTERED")
        self.events[event] = true
    end
    function w:RegisterUnitEvent(event, unit) assert(unit == "player"); self.events[event] = true end
    function w:UnregisterEvent(event) self.events[event] = nil end
    function w:UnregisterAllEvents() for event in pairs(self.events) do self.events[event] = nil end end
    function w:SetSize(width, height) self.width, self.height = width, height end
    function w:ClearAllPoints() end
    function w:SetPoint(point, parent, relative, x, y) self.point, self.x, self.y = point, x, y end
    function w:SetFrameStrata() end
    function w:EnableMouse(value) assert(value == false) end
    function w:SetAllPoints() end
    function w:SetJustifyH() end
    function w:SetJustifyV() end
    function w:SetWordWrap() end
    function w:SetFontHeight(size) self.fontSize = size end
    function w:SetTextColor(r, g, b) self.r, self.g, self.b = r, g, b end
    -- A C sink may receive a secret without any Lua coercion.
    function w:SetFormattedText(format, value) self.format, self.value = format, value end
    function w:SetAlpha(value) self.alpha = value end
    function w:IsShown() return self.shown end
    function w:SetShown(value) self.shown = value end
    function w:IsForbidden() return false end
    function w:IsProtected() return false end
    function w:Show() self.shown = true end
    function w:Hide() self.shown = false end
    function w:CreateAnimationGroup()
        local animation = Widget()
        function animation:SetLooping(value) assert(value == "NONE") end
        function animation:Stop() self.playing = false end
        function animation:Play() self.playing = true end
        function animation:CreateAnimation(kind)
            assert(kind == "Translation" or kind == "Alpha")
            local part = {}
            function part:SetOrder(order) assert(order == 1) end
            function part:SetOffset(x, y) self.x, self.y = x, y end
            function part:SetDuration(duration) self.duration = duration end
            function part:SetStartDelay(delay) self.delay = delay end
            function part:SetFromAlpha(value) self.from = value end
            function part:SetToAlpha(value) self.to = value end
            return part
        end
        return animation
    end
    return w
end
UIParent = Widget()
CombatText = Widget()
CombatText:Show()
UnitName = function() return "Tester" end
GetRealmName = function() return "Realm" end
UnitHasVehicleUI = function(unit) assert(unit == "player"); return vehicle end
C_CombatText = {
    GetActiveUnit = function() return activeUnit end,
    SetActiveUnit = function(unit) activeUnit = unit end,
    GetCurrentEventInfo = function()
        assert(duringEvent, "synchronous payload was read after its event")
        reads = reads + 1
        return firstPayload, secondPayload
    end,
}
C_CVar = {
    GetCVar = function(key) assert(key == "enableFloatingCombatText"); return cvar end,
    SetCVar = function(key, value)
        assert(key == "enableFloatingCombatText")
        cvar, writes = value, writes + 1
    end,
}
local function Dispatch(callback, ...) return callback(...) end
local NS = {
    Public = function(value) return not rawequal(value, secret) and not rawequal(value, healSecret) end,
    Client = { SupportsEvent = function() return validEvent end },
    IsCombatLocked = function() return locked end,
    Safety = { IsForbidden = function() return false end },
    Skin = { Release = function() end }, RootDB = {}, Dispatch = Dispatch,
}
local mover
local S = { instances = {}, Dispatch = Dispatch, editMode = false }
S.RegisterOwnedMover = function(id, element, options)
    assert(id == "selfCombatText" and element == "text")
    mover = options
end
NS.Suite = S
_G.MSUFSuite = NS
assert(loadfile(root .. "/MSUF_Suite/Core/SuiteCatalog.lua"))("MSUF_Suite", NS)
assert(loadfile(root .. "/MSUF_Suite/Core/Catalog/QualityOfLifeCombatText.lua"))("MSUF_Suite", NS)
S.catalog = NS.SuiteCatalog
local spec = assert(S.catalog.selfCombatText)
assert(spec.defaultEnabled == false and spec.optIn and spec.rules.enabled.default == false)
assert(spec.available() == true and spec.cvars.enableFloatingCombatText)
local get = C_CombatText.GetCurrentEventInfo
C_CombatText.GetCurrentEventInfo = nil
assert(spec.available() == false, "absent APIs must disable the feature")
C_CombatText.GetCurrentEventInfo = get
validEvent = false
assert(spec.available() == false)
validEvent = true
S.CreateFrame = function() created = created + 1; return Widget() end
S.CreateFontString = function() fontCount = fontCount + 1; return Widget() end
S.SetFont = function(text, _, size) text.fontSize = size end
S.RGB = function(hex) return tonumber(hex:sub(1, 2), 16)/255, tonumber(hex:sub(3, 4), 16)/255, tonumber(hex:sub(5, 6), 16)/255 end
S.Queue = function() error("combat text must not defer its payload") end
local private = {}
assert(loadfile(root .. "/MSUF_Suite_Modules/Runtime.lua"))("MSUF_Suite_Modules", private)
assert(loadfile(root .. "/MSUF_Suite_QualityOfLife/SelfCombatText.lua"))("MSUF_Suite_QualityOfLife", private)
local M = assert(S.instances.selfCombatText)
assert(created == 0 and fontCount == 0 and reads == 0 and writes == 0, "disabled module did work")
M.config = {}
for key, rule in pairs(spec.rules) do M.config[key] = rule.default end
M.context, M.active = S.NewContext("selfCombatText"), true
M:Enable()
M:RegisterMovers()
assert(mover.getFrame() == M.host and mover.xKey == "x" and mover.yKey == "y")
local function Event(event, ...)
    local frame = M.context.frame
    assert(frame.events[event], event .. " is not registered")
    duringEvent = event == "COMBAT_TEXT_UPDATE"
    frame.scripts.OnEvent(frame, event, ...)
    duringEvent = false
end
assert(created == 22 and fontCount == 20 and #M.slots == 20)
assert(cvar == "0" and activeUnit == "player" and not CombatText.shown)
assert(not M.context.frame.events.ADDON_LOADED, "loaded native UI left an addon listener")
local frames, fonts = created, fontCount
locked = true
Event("COMBAT_TEXT_UPDATE", "DAMAGE")
local text = M.slots[1].text
assert(rawequal(text.value, secret) and text.format == "-%s" and M.slots[1].animation.playing)
Event("COMBAT_TEXT_UPDATE", "HEAL_CRIT")
text = M.slots[2].text
assert(rawequal(text.value, healSecret) and text.format == "+%s" and text.fontSize == M.critSize)
assert(M.slots[2].fade.delay + M.slots[2].fade.duration == M.config.duration)
Event("COMBAT_TEXT_UPDATE", "SPELL_BLOCK")
assert(rawequal(M.slots[3].text.value, secret) and M.slots[3].text.format == "-%s")
-- Shared/CombatText.lua uses the second payload (arg3) to distinguish
-- partial damage from a full block/resist notice. The first field can
-- still contain an amount on a full notice.
local position = M.cursor
firstPayload, secondPayload = 37, nil
for _, kind in ipairs({ "BLOCK", "SPELL_BLOCK", "RESIST", "SPELL_RESIST" }) do
    Event("COMBAT_TEXT_UPDATE", kind)
    assert(M.cursor == position, "full " .. kind .. " made a damage number")
end
firstPayload, secondPayload = secret, healSecret
Event("COMBAT_TEXT_UPDATE", "RESIST")
assert(rawequal(M.slots[M.cursor].text.value, secret) and M.slots[M.cursor].text.format == "-%s",
    "partial mitigation did not send its secret damage directly to the native sink")
-- Absorb amounts can be private; the display never filters any amount for
-- zero. A non-nil partial marker preserves that native text behavior.
firstPayload = 0
Event("COMBAT_TEXT_UPDATE", "ABSORB")
assert(M.slots[M.cursor].text.value == 0, "absorb amount was filtered in Lua")
firstPayload = secret
local before = reads
M.config.showHealing = false
Event("COMBAT_TEXT_UPDATE", "PERIODIC_HEAL")
Event("COMBAT_TEXT_UPDATE", "SPELL_AURA_START")
assert(reads == before, "unselected or unrelated events read the payload")
M.config.showHealing = true
M.config.maxMessages = 3
for i = 1, 100 do Event("COMBAT_TEXT_UPDATE", "SPELL_DAMAGE_CRIT") end
assert(created == frames and fontCount == fonts and M.cursor <= 3, "burst grew the pool")
local slot = M.slots[M.cursor]
slot.animation.scripts.OnFinished(slot.animation)
assert(not slot.frame.shown, "finished animation left text visible")
vehicle = true
Event("UNIT_ENTERED_VEHICLE", "player")
assert(activeUnit == "vehicle")
vehicle = false
Event("UNIT_EXITING_VEHICLE", "player")
assert(activeUnit == "player")
locked = false
S.editMode = true
M:Refresh()
before = reads
Event("COMBAT_TEXT_UPDATE", "DAMAGE")
assert(reads == before and M.preview and M.slots[1].frame.shown and not M.slots[1].animation.playing)
M:HideEditPreview()
assert(not M.preview and not M.slots[1].frame.shown)
S.editMode = false
M.config.direction = 2
M:Refresh()
assert(M.slots[1].move.y == -M.config.distance)
-- The direct registered callback isolates allocations from this test's mocks.
local callback = M.context.callbacks.COMBAT_TEXT_UPDATE
duringEvent = true
collectgarbage("collect")
collectgarbage("stop")
local memory = collectgarbage("count")
for i = 1, 10000 do callback(M, "COMBAT_TEXT_UPDATE", "DAMAGE") end
local allocated = collectgarbage("count") - memory
collectgarbage("restart")
duringEvent = false
assert(allocated < 1, "combat-text burst allocated " .. allocated .. " KB")
M.active = false
M:Disable()
M.context:Release()
assert(cvar == "1" and activeUnit == "target" and not next(M.context.frame.events) and CombatText.shown)
before = reads
duringEvent = true
callback(M, "COMBAT_TEXT_UPDATE", "DAMAGE")
duringEvent = false
assert(reads == before, "disabled callback did work")
assert(not M.host.shown and not M.slots[1].animation.playing)
-- Reactivation reuses the pool; another addon/user's later changes survive.
M.active = true
M:Enable()
assert(created == frames and fontCount == fonts)
cvar, activeUnit = "1", "focus"
before = writes
M.active = false
M:Disable()
M.context:Release()
assert(cvar == "1" and activeUnit == "focus" and writes == before)
CombatText = nil
M.active = true
M:Enable()
assert(M.context.frame.events.ADDON_LOADED, "missing native UI was not watched")
Event("ADDON_LOADED", "Unrelated")
assert(M.context.frame.events.ADDON_LOADED)
CombatText = Widget()
CombatText:Show()
Event("ADDON_LOADED", "Blizzard_CombatText")
assert(not CombatText.shown and not M.context.frame.events.ADDON_LOADED)
M.active = false
M:Disable()
M.context:Release()
assert(CombatText.shown and not next(M.context.frame.events))
print("suite self combat text: secret-safe synchronous events, fixed allocation-free pool, native lifetime and restore passed")

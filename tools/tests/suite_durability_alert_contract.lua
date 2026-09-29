local root = assert(arg[1], "repository root required")
local timers, registered, reads = {}, {}, 0
local lowest, combat = .65, false

local function Widget(fontString)
    local w = { shown = true, fontString = fontString }
    function w:CreateTexture() return Widget() end
    function w:CreateFontString() return Widget(true) end
    function w:SetSize(width, height) self.width, self.height = width, height end
    function w:SetScale(value) self.scale = value end
    function w:SetFrameStrata() end
    function w:EnableMouse(value) self.mouse = value end
    function w:SetAllPoints() end
    function w:SetColorTexture() end
    function w:SetPoint(...) self.point = { ... } end
    function w:ClearAllPoints() end
    function w:SetJustifyH() end
    function w:SetWordWrap() end
    function w:SetTextColor() end
    function w:SetFont() self.font = true end
    function w:SetText(value)
        assert(not self.fontString or self.font, "warning text has no font")
        self.text = value
    end
    function w:Show() self.shown = true end
    function w:Hide() self.shown = false end
    return w
end

UIParent = Widget()
C_Timer = { After = function(delay, callback)
    assert(delay == .06, "durability refresh must settle after the shared cache")
    timers[#timers + 1] = callback
end }
local function Drain()
    local pending = timers
    timers = {}
    for _, callback in ipairs(pending) do callback() end
end

local NS = {
    AnchorPoints = { "TOPLEFT", "TOP", "TOPRIGHT", "LEFT", "CENTER", "RIGHT", "BOTTOMLEFT", "BOTTOM", "BOTTOMRIGHT" },
    MSUFMedia = { font = "MSUF.ttf" },
    IsCombatLocked = function() return combat end,
}
local S = { editMode = false }
NS.Suite = S
S.Text = function(text) return text end
S.Finite = function(value) return type(value) == "number" and value == value end
S.CreateFrame = function() return Widget() end
S.CreateTexture = function(parent) return parent:CreateTexture() end
S.CreateFontString = function(parent) return parent:CreateFontString() end
S.SetFont = function(fontString) fontString:SetFont() end
S.PlaceEdges = function() end
S.ReadInfoSource = function(key)
    assert(key == "durability")
    reads = reads + 1
    return lowest
end
S.RegisterOwnedMover = function(id, element, spec)
    assert(id == "durabilityAlert" and element == "warning")
    registered.spec = spec
    return true
end
S.Config = function(id) assert(id == "durabilityAlert"); return registered.module.config end
S.Set = function(id, key, value)
    S.Config(id)[key] = value
    registered.module:Refresh()
    return true
end
S.Install = function(id, module)
    assert(id == "durabilityAlert")
    registered.module = module
end

assert(loadfile(root .. "/tools/tests/suite_test_support.lua"))().QoLStyleFixture(root, S)
assert(loadfile(root .. "/MSUF_Suite_QualityOfLife/DurabilityAlert.lua"))(
    "MSUF_Suite_QualityOfLife", { NS = NS, Suite = S })
local M = assert(registered.module)
M.active = true
M.config = { threshold = 40, width = 250, height = 62, scale = 100,
    point = 5, x = 10, y = 180 }
local events = {}
M.context = { Event = function(_, event, callback, allowCombat)
    assert(allowCombat == true)
    events[event] = callback
end }

M:Enable()
assert(not M.host.shown and M.host.mouse == false, "healthy gear showed or captured input")
Drain()
assert(registered.spec and registered.spec.getFrame() == M.host
    and registered.spec.pointKey == "point" and registered.spec.xKey == "x"
    and registered.spec.yKey == "y" and registered.spec.quickPosition
    and #registered.spec.extraControls == 3,
    "MSUF Edit Mode mover or size controls were not registered")
assert(M.host.width == 250 and M.host.height == 62 and M.host.scale == 1,
    "warning default geometry was not applied")
registered.spec.extraControls[1].set(300)
registered.spec.extraControls[2].set(75)
registered.spec.extraControls[3].set(125)
assert(M.host.width == 300 and M.host.height == 75 and M.host.scale == 1.25,
    "warning popup size did not reach runtime")
assert(M.host.point[1] == "CENTER" and M.host.point[4] == 10 and M.host.point[5] == 180,
    "profile position was not applied")
assert(events.UPDATE_INVENTORY_DURABILITY and events.UPDATE_INVENTORY_ALERTS
    and events.PLAYER_EQUIPMENT_CHANGED and events.PLAYER_REGEN_ENABLED,
    "durability and combat events are incomplete")

lowest = .25
events.UPDATE_INVENTORY_DURABILITY(M, "UPDATE_INVENTORY_DURABILITY")
events.UPDATE_INVENTORY_ALERTS(M, "UPDATE_INVENTORY_ALERTS")
assert(#timers == 1 and not M.host.shown, "same-frame inventory events were not coalesced")
Drain()
assert(M.host.shown and M.value.text == "25%", "low durability warning did not appear")

combat = true
events.PLAYER_REGEN_DISABLED(M, "PLAYER_REGEN_DISABLED")
assert(not M.host.shown, "warning remained visible in combat")
events.UPDATE_INVENTORY_DURABILITY(M, "UPDATE_INVENTORY_DURABILITY")
assert(#timers == 0, "combat durability event scheduled work")
combat = false
events.PLAYER_REGEN_ENABLED(M, "PLAYER_REGEN_ENABLED")
Drain()
assert(M.host.shown, "warning did not return after combat")

lowest = .40
events.PLAYER_EQUIPMENT_CHANGED(M, "PLAYER_EQUIPMENT_CHANGED")
Drain()
assert(not M.host.shown, "warning showed at the threshold")
lowest = nil
events.UPDATE_INVENTORY_DURABILITY(M, "UPDATE_INVENTORY_DURABILITY")
Drain()
assert(not M.host.shown, "unreadable durability showed a warning")

S.editMode = true
M.config.point, M.config.x, M.config.y = 2, -18, -90
M:Refresh()
assert(M.host.shown and M.value.text == "Preview 25%"
    and M.host.point[1] == "TOP" and M.host.point[4] == -18,
    "MSUF Edit Mode preview or profile movement failed")
combat = true
M:Refresh()
assert(not M.host.shown, "Edit Mode preview appeared in combat")
combat = false
S.editMode = false
M:Refresh()
assert(not M.host.shown, "Edit Mode preview remained visible")

lowest = .20
events.UPDATE_INVENTORY_DURABILITY(M, "UPDATE_INVENTORY_DURABILITY")
local before = reads
M:Disable()
M.active = false
Drain()
assert(not M.host.shown and reads == before, "disabled module ran deferred work")

print("Low durability warning: threshold, combat, preview, mover and teardown passed")

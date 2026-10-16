-- The HUD preview's lifecycle on the real options page fixture: the AFK example listens to
-- character events only while shown, hiding drops them, and a burst of events repaints.
local root = assert(arg[1], "repository root required")
local originalLoad, P = loadfile
loadfile = function(path)
    local chunk = assert(originalLoad(path))
    if path:match("/Menu/PreviewInteraction%.lua$") then
        return function(addon, namespace) P = namespace; return chunk(addon, namespace) end
    end
    return chunk
end
assert(originalLoad(root .. "/tools/tests/suite_options_menu_contract.lua"))()
loadfile = originalLoad
assert(P and P.HUDPreview, "HUD preview owner is absent")

local timers, previous = {}, C_Timer
C_Timer = { After = function(_, fn) timers[#timers + 1] = fn end,
    NewTimer = function() return { Cancel = function() end } end }
local function Flush()
    local queue = timers
    timers = {}
    for _, fn in ipairs(queue) do fn() end
end
local ctx = { key = "suite_hud", refreshers = {}, widgets = {}, _msufSuiteHUDWorkspace = { groups = {} } }
local parent = CreateFrame("Frame", nil, UIParent)
local ui = P.HUDPreview.Build(ctx, parent, 400)
local host = ui.host
host.events = {}
function host:RegisterEvent(event) self.events[event] = true end
function host:UnregisterAllEvents() self.events = {} end
local paints = 0
local setSize = ui.canvas.SetSize
function ui.canvas:SetSize(...) paints = paints + 1; return setSize(self, ...) end

-- Only the AFK example reads character events.
ui.Select(ui, "objectives")
assert(next(host.events) == nil, "a preview that reads no character data listened to events")
ui.Select(ui, "afkScreen")
assert(host.events.PLAYER_EQUIPMENT_CHANGED and host.events.UNIT_MODEL_CHANGED and host.events.ZONE_CHANGED_NEW_AREA,
    "the AFK example is not listening while visible")
ui.Select(ui, "announcements")
assert(next(host.events) == nil, "leaving the AFK example kept its events")

-- An event of another unit's model is ignored; the player's repaints, once however many arrive.
ui.Select(ui, "afkScreen")
Flush()
paints = 0
host.scripts.OnEvent(host, "UNIT_MODEL_CHANGED", "party1")
Flush()
assert(paints == 0, "another unit's model repainted the HUD preview")
for _ = 1, 3 do host.scripts.OnEvent(host, "UNIT_MODEL_CHANGED", "player") end
Flush()
assert(paints >= 1 and paints <= 3, "the player's model change did not repaint the HUD preview")

-- Hiding drops the events and stops a playing example; showing selects again.
ui.playing = true
host.scripts.OnHide(host)
assert(next(host.events) == nil and not ui.playing, "hiding left subscriptions or a playing preview")
host.scripts.OnShow(host)
assert(host.events.UNIT_MODEL_CHANGED, "showing the preview again did not listen again")
C_Timer = previous
print("HUD preview lifecycle: events only while shown, ignored foreign units, repaint and hide checks passed")

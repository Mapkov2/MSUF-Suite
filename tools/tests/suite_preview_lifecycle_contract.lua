-- The HUD and ActionBars previews' lifecycle on the real options page fixture: the AFK example
-- listens to character events only while shown, hiding drops them, a burst of events repaints, and
-- a shown action bar preview listens before it paints.
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

-- ActionBars: every event is registered before the paint that a show makes, so none slips between
-- them; hiding drops them all, and an event that is still queued then paints nothing.
do
    local actionCtx = { key = "suite_actionbars", refreshers = {}, widgets = {} }
    P.ActionBarPreview.Build(actionCtx, parent, -20, 520, 200, function() return 1 end)
    local bars = actionCtx._msufSuiteActionBarPreview
    local barHost, log = bars.host, {}
    barHost.events = {}
    function barHost:RegisterEvent(event) self.events[event] = true; log[#log + 1] = "register" end
    function barHost:UnregisterAllEvents() self.events = {}; log[#log + 1] = "unregister" end
    local paint = bars.Paint
    bars.Paint = function(...) log[#log + 1] = "paint"; return paint(...) end
    barHost.scripts.OnHide(barHost)
    log = {}
    barHost.scripts.OnShow(barHost)
    local lastRegister, firstPaint
    for index, entry in ipairs(log) do
        if entry == "register" then lastRegister = index end
        if entry == "paint" and not firstPaint then firstPaint = index end
    end
    assert(lastRegister and firstPaint and lastRegister < firstPaint, "the action bar preview painted before it listened: "
        .. table.concat(log, " "))
    assert(barHost.events.ACTIONBAR_SLOT_CHANGED and barHost.events.UNIT_PET, "showing did not listen to the action bar events")
    log = {}
    barHost.scripts.OnEvent(barHost, "SPELL_UPDATE_ICON")
    barHost.scripts.OnHide(barHost)
    assert(next(barHost.events) == nil, "hiding kept the action bar events")
    Flush()
    for _, entry in ipairs(log) do assert(entry ~= "paint", "a hidden action bar preview painted") end
end
C_Timer = previous
print("preview lifecycle: HUD events only while shown, ignored foreign units, repaint, hide, and the action bar order passed")

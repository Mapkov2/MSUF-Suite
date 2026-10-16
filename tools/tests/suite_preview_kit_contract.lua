-- The preview kit (MSUF_Suite/Core/PreviewKit.lua): host lifecycle, pools, the
-- coalesced repaint, the one ticker, and the handle controller's selection,
-- drag, cancel, nudge and commit. A small frame model stands in for the client.
local root = assert(arg[1], "Suite root required")

local timers = { after = {}, tickers = 0, created = 0 }
C_Timer = {
    After = function(delay, callback)
        assert(delay == 0, "the repaint request waits one frame, not a delay")
        timers.after[#timers.after + 1] = callback
    end,
    NewTicker = function(interval, callback)
        local ticker = { interval = interval, callback = callback }
        function ticker:Cancel() if not self.cancelled then self.cancelled = true; timers.tickers = timers.tickers - 1 end end
        timers.tickers, timers.created = timers.tickers + 1, timers.created + 1
        return ticker
    end,
}
local function Flush()
    local queue = timers.after
    timers.after = {}
    for _, callback in ipairs(queue) do callback() end
end

local cursorX, cursorY, keys, keyboardFocus = 0, 0, {}, nil
GetCursorPosition = function() return cursorX, cursorY end
IsShiftKeyDown = function() return keys.shift == true end
IsControlKeyDown = function() return keys.ctrl == true end
IsAltKeyDown = function() return keys.alt == true end
GetCurrentKeyBoardFocus = function() return keyboardFocus end

local calls = { show = 0, hide = 0 }
local function Frame(parent)
    local f = { parent = parent, scripts = {}, points = {}, shown = true, scale = 1, drag = nil }
    function f:SetScript(name, fn) self.scripts[name] = fn end
    function f:GetScript(name) return self.scripts[name] end
    function f:HookScript(name, fn)
        local previous = self.scripts[name]
        self.scripts[name] = function(...) if previous then previous(...) end; fn(...) end
    end
    function f:Show()
        calls.show = calls.show + 1
        if not self.shown then
            self.shown = true
            if self.scripts.OnShow then self.scripts.OnShow(self) end
        end
    end
    function f:Hide()
        calls.hide = calls.hide + 1
        if self.shown then
            self.shown = false
            if self.scripts.OnHide then self.scripts.OnHide(self) end
        end
    end
    function f:IsShown() return self.shown end
    function f:IsVisible() return self.shown and (not self.parent or self.parent:IsVisible()) end
    function f:SetPoint(...) self.points[#self.points + 1] = { ... } end
    function f:ClearAllPoints() self.points = {} end
    function f:GetNumPoints() return #self.points end
    function f:GetPoint(i) return unpack(self.points[i]) end
    function f:EnableMouse(on) self.mouse = on end
    function f:EnableKeyboard(on) self.keyboard = on end
    function f:SetPropagateKeyboardInput(on) self.propagate = on end
    function f:RegisterForClicks(...) self.clicks = { ... } end
    function f:RegisterForDrag(...) self.dragButtons = { ... } end
    function f:SetMovable(on) self.movable = on end
    function f:StartMoving() self.moving = true; self.points = { { "CENTER", nil, "CENTER", 999, 999 } } end
    function f:StopMovingOrSizing() self.moving = false end
    function f:GetEffectiveScale() return self.scale end
    function f:IsObjectType(kind) return kind == self.kind end
    return f
end
CreateFrame = function(_, _, parent) return Frame(parent) end
unpack = unpack or table.unpack

local combat = false
local NS = {
    IsSecret = function(value) return type(value) == "table" and value.secret == true end,
    Number = function(value) return type(value) == "number" and value == value end,
    InCombat = function() return combat end,
}
assert(loadfile(root .. "/MSUF_Suite/Core/PreviewKit.lua"))("MSUF_Suite", NS)
local Kit = assert(NS.PreviewKit, "the kit is not published on the Suite namespace")

------------------------------------------------------------------ host
local paints, builds, activations = {}, 0, 0
local host = Kit.NewHost(Frame(), {
    build = function() builds = builds + 1 end,
    activate = function() activations = activations + 1 end,
    paint = function(_, reason) paints[#paints + 1] = reason end,
    animate = function() paints[#paints + 1] = "tick" end,
    interval = 0.5,
})
assert(host.frame and host.owned and not host.frame:IsShown(), "a host owns a hidden frame until it opens")
host:Request("closed")
host:SetAnimate(true)
assert(#timers.after == 0 and timers.tickers == 0, "a closed host holds a timer or queued work")
host:Activate()
host:Activate()
assert(builds == 1 and activations == 2 and host.frame:IsShown(),
    "activation builds once, runs its hook on every call and shows the frame")
host:Request("a")
host:Request("b")
host:Request("c")
assert(#timers.after == 1 and #paints == 0, "requests paint on the next frame, not at once")
Flush()
assert(#paints == 1 and paints[1] == "c", "requests of one frame paint once, with the last reason")
assert(host:Paint("now") and paints[#paints] == "now" and not host.queued, "a direct paint answers and clears the request")
assert(host:SetAnimate(true) and timers.tickers == 1 and host:SetAnimate(true) and timers.tickers == 1,
    "animation runs on one ticker, however often it is switched on")
host:Request("late")
host:Deactivate()
assert(timers.tickers == 0 and not host.frame:IsShown() and not host.active, "closing stops the ticker and hides the frame")
Flush()
assert(paints[#paints] ~= "late", "a request outlived the closing of its host")
assert(not host:SetAnimate(true) and timers.tickers == 0, "a closed host started a ticker")
host:Activate()
assert(builds == 1 and activations == 3, "reopening reuses what was built")
host:Deactivate()

-- A frame the page's layout owns is never shown or hidden by its host.
local adopted = Frame()
adopted:Hide()
local own = Kit.NewHost(nil, { frame = adopted, paint = function() end }):Activate()
assert(own.active and not own.owned and not adopted:IsShown(), "an adopted frame is not forced open")
own:Deactivate()
assert(not own.active and not adopted:IsShown(), "closing an adopted frame shows nothing")

------------------------------------------------------------------ pools
local made = {}
local pooled = Kit.NewHost(nil, { pools = { hit = function(_, index)
    local hit = Frame()
    hit.shown = false
    made[#made + 1] = index
    return hit
end } })
local first, second = pooled:Acquire("hit"), pooled:Acquire("hit")
assert(first ~= second and #made == 2 and first:IsShown() and second:IsShown(), "sequential acquire")
assert(pooled:Acquire("hit", 1) == first and #made == 2, "an index returns the same object")
calls.show, calls.hide = 0, 0
pooled:Acquire("hit", 1)
pooled:Acquire("hit", 2)
pooled:ReleaseAll("hit", 3)
assert(calls.show == 0 and calls.hide == 0, "a warm repaint made widget calls")
pooled:ReleaseAll("hit", 2)
assert(first:IsShown() and not second:IsShown() and pooled:List("hit")[2] == second,
    "release hides from the given place on")
pooled:ReleaseAll("hit")
assert(not first:IsShown(), "release without a place hides all")
assert(pooled:Acquire("hit") == first, "a released pool hands out its first object again")

------------------------------------------------------------------ handles
local writes, store, painted, hooks = {}, { x = 10, y = -4 }, 0, {}
local body, placed = Frame(), nil
-- The page's paint puts its region where the stored value says, as every preview does.
local main = Kit.NewHost(nil, { frame = body, paint = function()
    painted = painted + 1
    if placed then placed.points = { { "CENTER", body, "CENTER", store.x, store.y } } end
end })
main:Activate()
local handles
local function Controller(extra, own)
    local opts = { escape = function() handles:Release() end, steps = { shift = 5, ctrl = 10 },
        mark = function(region, selected) hooks[#hooks + 1] = { "mark", region, selected } end,
        tip = function(region, entering) hooks[#hooks + 1] = { "tip", region, entering } end,
        select = function(region) hooks[#hooks + 1] = { "select", region } end,
        click = function(region, button, moved) hooks[#hooks + 1] = { "click", region, button, moved } end,
        moved = function(region) hooks[#hooks + 1] = { "moved", region } end,
        drag = function(region, phase, moved) hooks[#hooks + 1] = { "drag", region, phase, moved } end }
    for key, value in pairs(extra or {}) do opts[key] = value end
    if own then opts.owner = Frame(body) end
    return Kit.Handles(own and Kit.NewHost(nil, { frame = body }):Activate() or main, opts)
end
handles = Controller()
assert(body.keyboard and body.propagate == true and body.scripts.OnKeyDown, "the owner listens for keys")
local function Read() return store.x, store.y end
local function Write(x, y)
    writes[#writes + 1] = { x, y }
    store.x, store.y = x, y
    return true
end
local region = Frame(body)
region.kind = "Button"
region.points = { { "CENTER", body, "CENTER", 10, -4 } }
placed = region
assert(handles:Add("bar", region, Read, Write) == region, "Add returns the region")
assert(region.mouse and region.movable and region.scripts.OnMouseDown and region.scripts.OnKeyDown
    and region.scripts.OnDragStart and region.dragButtons[1] == "LeftButton", "region wiring")
local other = Frame(body)
handles:Add("name", other, function() return 0, 0 end, nil)
assert(not other.movable and other.scripts.OnClick, "a region without write only selects and clicks")

-- Hover reaches the page's hook.
local tipped = Controller({ tip = function(r, entering) hooks[#hooks + 1] = { "tip", r, entering } end }, true)
tipped:Add("hover", Frame(body), Read, Write)
local hover = tipped.list[1]
hover.scripts.OnEnter(hover)
hover.scripts.OnLeave(hover)
assert(hooks[#hooks][1] == "tip" and hooks[#hooks][3] == false and hooks[#hooks - 1][3] == true, "tooltip hook")
tipped:Clear()
assert(hover.scripts.OnEnter == nil and #tipped.list == 0, "Clear drops the wiring")

-- Select: keyboard to a shown, movable region; mirror on the owner.
handles:Select("bar")
assert(body._selectedHandle == region and region.keyboard == true and handles.selected == region, "selection")
handles:Select("name")
assert(region.keyboard == false and body._selectedHandle == other and other.keyboard == false,
    "a region that cannot move takes no keyboard")
handles:Select("bar")

-- Nudge: Shift 5 and Ctrl 10 here, the plain step otherwise; the kit's own default is Shift 10.
local function Press(frame, key) return frame.scripts.OnKeyDown(frame, key) end
store.x, store.y = 10, -4
writes = {}
assert(Press(region, "RIGHT") and store.x == 11 and region.propagate == false, "plain arrow")
keys.shift = true
assert(Press(region, "UP") and store.y == 1, "Shift steps by the page's multiplier")
keys.shift, keys.ctrl = false, true
assert(Press(region, "LEFT") and store.x == 1, "Ctrl steps by the page's multiplier")
keys.ctrl = false
assert(Kit.Handles(Kit.NewHost(nil, {}), { owner = Frame() }):Step() == 1, "no modifier is one unit")
keys.shift = true
assert(Kit.Handles(Kit.NewHost(nil, {}), { owner = Frame() }):Step() == 10, "the kit's Shift step is 10")
keys.shift = false
local before = #writes
keyboardFocus = { kind = "EditBox", IsObjectType = function(self, kind) return kind == "EditBox" end }
assert(not Press(region, "RIGHT") and #writes == before and region.propagate == true, "typing keeps the arrows")
keyboardFocus = nil
combat = true
assert(not Press(region, "RIGHT") and #writes == before, "combat refuses a nudge")
combat = false
local seen = {}
local deduped = Controller({ dedupe = function(_, dx, dy) seen[#seen + 1] = dx .. ":" .. dy; return true end }, true)
deduped:Add("d", Frame(body), Read, Write)
deduped:Select("d")
assert(Press(deduped.list[1], "RIGHT") and #writes == before and seen[1] == "1:0", "a repeated key press is consumed once")
deduped:Clear()
assert(handles:Nudge(0, 0) and handles:Nudge(2, 3) and store.x == 3 and store.y == 4, "Nudge applies an offset as given")
store.x = { secret = true }
before = #writes
local ran, applied = pcall(handles.Nudge, handles, 1, 1)
assert(ran and not applied and #writes == before, "a secret value is never computed with")
store.x, store.y = 10, -4

-- Drag (the region moves by itself): commit through write, anchors kept on refusal.
local function Drag(dx, dy, target)
    target = target or region
    cursorX, cursorY = 100, 100
    target.scripts.OnMouseDown(target, "LeftButton")
    cursorX, cursorY = 100 + dx, 100 + dy
    target.scripts.OnMouseUp(target, "LeftButton")
end
region.points = { { "CENTER", body, "CENTER", 10, -4 } }
painted, writes = 0, {}
Drag(8, -6)
assert(#writes == 1 and writes[1][1] == 18 and writes[1][2] == -10, "release writes the stored value moved by the drag")
assert(not region.moving and not handles.drag and painted >= 1, "release ends the move and repaints")
local reported = 0
for _, entry in ipairs(hooks) do if entry[1] == "moved" then reported = reported + 1 end end
assert(reported == 1, "a drag that wrote reports it once through the moved hook")
region.scale = 2
store.x, store.y = 10, -4
Drag(8, -6)
assert(writes[2][1] == 14 and writes[2][2] == -7, "the drag divides by the region's scale")
region.scale = 1
store.x, store.y = 10, -4
region.points = { { "CENTER", body, "CENTER", 10, -4 } }
Drag(1, 1)
assert(#writes == 2, "a press that barely moves writes nothing")
assert(region.points[1][4] == 10 and region.points[1][5] == -4, "and the repaint puts the region back on its anchors")
assert(hooks[#hooks][1] == "drag" and hooks[#hooks][3] == "stop" and hooks[#hooks][4] == false, "drag hook")
Write = function(x, y) writes[#writes + 1] = { x, y }; return false end
handles.entries.bar.write = Write
region.points = { { "CENTER", body, "CENTER", 10, -4 } }
Drag(20, 20)
assert(region.points[1][4] == 10 and region.points[1][5] == -4, "a refused write is repainted from the stored value")
Write = function(x, y) writes[#writes + 1] = { x, y }; store.x, store.y = x, y; return true end
handles.entries.bar.write = Write
combat = true
region.points = { { "CENTER", body, "CENTER", 10, -4 } }
cursorX, cursorY = 100, 100
region.scripts.OnMouseDown(region, "LeftButton")
assert(not handles.drag, "combat refuses a drag")
combat = false
-- Combat that starts during a drag refuses the write.
before = #writes
cursorX, cursorY = 100, 100
region.scripts.OnMouseDown(region, "LeftButton")
cursorX = 140
combat = true
region.scripts.OnMouseUp(region, "LeftButton")
combat = false
assert(#writes == before and not handles.drag, "combat during a drag refuses the commit")
-- Cancel restores from the stored value and never writes.
before = #writes
region.points = { { "CENTER", body, "CENTER", 10, -4 } }
region.scripts.OnMouseDown(region, "LeftButton")
assert(handles.drag and region.moving, "press starts the move")
assert(not main:Paint("blocked") and handles.drag, "a native drag holds the paint")
handles:Cancel()
assert(not handles.drag and not region.moving and #writes == before, "Cancel writes nothing")
assert(region.points[1][4] == 10 and region.points[1][5] == -4, "Cancel repaints the region from the stored value")
-- Escape, hiding and closing end a drag and the selection.
handles:Select("bar")
region.scripts.OnMouseDown(region, "LeftButton")
assert(Press(region, "ESCAPE") and not handles.drag and body._selectedHandle == nil and region.propagate == false,
    "Escape ends the drag and the selection")
handles:Select("bar")
region.scripts.OnMouseDown(region, "LeftButton")
region:Hide()
assert(not handles.drag and handles.selected == nil, "hiding a region ends its drag and selection")
region:Show()
handles:Select("bar")
main:Deactivate()
assert(handles:Selected() == nil and not main.active, "closing the host drops the selection")
main:Activate()
-- A click carries whether the press moved.
hooks = {}
region.scripts.OnClick(region, "RightButton")
assert(hooks[#hooks][1] == "click" and hooks[#hooks][3] == "RightButton" and hooks[#hooks][4] == false, "click hook")

-- keep: the selection outlives its region hiding; keydown replaces the key handler; the
-- owner's field is the truth, so a page that clears it clears the selection.
do
    local keys = {}
    local kept = Controller({ keep = true, keydown = function(_, key) keys[#keys + 1] = key; return true end }, true)
    local one = Frame(kept.owner)
    kept:Add("one", one, Read, Write)
    kept:Select("one")
    one:Hide()
    assert(kept:Selected() == one, "a kept selection must outlive its region hiding")
    one:Show()
    one.scripts.OnKeyDown(one, "RIGHT")
    kept.owner.scripts.OnKeyDown(kept.owner, "Q")
    assert(#keys == 2 and keys[1] == "RIGHT" and keys[2] == "Q", "keydown must replace the key handler")
    kept.owner._selectedHandle = nil
    assert(kept:Selected() == nil and not kept:Nudge(1, 1), "clearing the owner's field clears the selection")
end

-- A followed drawing: one script only while the button is held.
local followRegion, shifted = Frame(body), { 0, 0 }
local followed2 = Controller({ escape = false }, true)
local canMove = false
followed2:Add("bar", followRegion, Read, Write, { select = false, clicks = { "LeftButtonUp" },
    follow = function(_, dx, dy) shifted = { dx, dy } end, can = function() return canMove end,
    scale = function() return 1 end })
assert(not followRegion.movable and followRegion.clicks[1] == "LeftButtonUp" and #followRegion.clicks == 1, "follow wiring")
cursorX, cursorY = 50, 50
followRegion.scripts.OnMouseDown(followRegion, "LeftButton")
assert(followRegion.scripts.OnUpdate == nil, "an attached bar starts no follow")
cursorX = 80
followRegion.scripts.OnMouseUp(followRegion, "LeftButton")
assert(hooks[#hooks][1] == "drag" and hooks[#hooks][3] == "stop" and hooks[#hooks][4] == true,
    "a refused drag still reports that it moved")
canMove, writes = true, {}
cursorX = 50
followRegion.scripts.OnMouseDown(followRegion, "LeftButton")
assert(followRegion.scripts.OnUpdate, "the follow runs while the button is held")
cursorX, cursorY = 62, 47
followRegion.scripts.OnUpdate(followRegion)
assert(shifted[1] == 12 and shifted[2] == -3, "the drawing follows the cursor")
followRegion.scripts.OnMouseUp(followRegion, "LeftButton")
assert(followRegion.scripts.OnUpdate == nil and #writes == 1 and writes[1][1] == 22 and writes[1][2] == -7,
    "release ends the follow and writes")
cursorX = 50
followRegion.scripts.OnMouseDown(followRegion, "LeftButton")
cursorX = 60
followRegion.scripts.OnUpdate(followRegion)
combat = true
followRegion.scripts.OnUpdate(followRegion)
assert(followRegion.scripts.OnUpdate == nil and shifted[1] == 0 and not followed2.drag, "combat cancels a followed drag and recenters")
combat = false

-- The host closing ends everything the handles hold.
main:Deactivate()
assert(timers.tickers == 0, "no timer outlives the host")
print("preview kit: lifecycle, pools, coalesced repaint, ticker, selection, drag, cancel, nudge and commit checks passed")

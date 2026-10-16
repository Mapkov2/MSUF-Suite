local _, NS = ...
-- The Suite's own preview kit: one lifecycle and one handle controller for
-- the options previews, so each preview keeps only its painting. It names no
-- MSUF host function; what a page needs from its host (secure arrow
-- bindings, the duplicate-nudge filter) comes in through opts, so the kit
-- runs on every supported MSUF build.
--   Kit.NewHost(parent, opts)   lifecycle, pools, one coalesced repaint
--   Kit.Handles(host, opts)     select, drag, nudge, commit, tooltip hook
-- Static samples only: no unit or aura query, no secure frame, no event
-- registered here. A closed host holds no timer and does no work.
local Kit = {}
NS.PreviewKit = Kit
local IsSecret, Number = NS.IsSecret, NS.Number
local EMPTY, DELTAS = {}, { LEFT = { -1, 0 }, RIGHT = { 1, 0 }, UP = { 0, 1 }, DOWN = { 0, -1 } }
local CLICKS = { "LeftButtonUp", "RightButtonUp" }
local SCRIPTS = { "OnMouseDown", "OnMouseUp", "OnDragStart", "OnDragStop", "OnClick", "OnHide", "OnEnter", "OnLeave",
    "OnKeyDown" }

local function Readable(value) return not IsSecret(value) and Number(value) end

------------------------------------------------------------------ host
local Host = {}
Host.__index = Host

-- opts: frame (a frame the page's layout already owns; else one is made),
-- build(host) once, activate/deactivate(host), paint(host, reason),
-- pools = { kind = create(host, index) }, animate(host) with interval for
-- SetAnimate.
function Kit.NewHost(parent, opts)
    opts = opts or EMPTY
    local host = setmetatable({ opts = opts, frame = opts.frame, pools = {} }, Host)
    host.flush = function()
        if host.queued then host:Paint(host.reason) end
    end
    if not host.frame and parent then
        host.frame, host.owned = CreateFrame("Frame", nil, parent), true
        host.frame:Hide()
    end
    return host
end

-- Opens the host. What was built stays built; the activate hook runs on every
-- call (it is the page's "now shown" work, so it must be safe to repeat).
function Host:Activate()
    self.active = true
    if not self.built then
        self.built = true
        if self.opts.build then self.opts.build(self) end
    end
    if self.owned then self.frame:Show() end
    if self.opts.activate then self.opts.activate(self) end
    return self
end

-- Closes the host and leaves nothing held. The hook is cleanup, so it runs
-- on every call, also for a host that never opened.
function Host:Deactivate()
    self.active, self.queued = false, false
    self:SetAnimate(false)
    if self.handles then self.handles:Release() end
    if self.opts.deactivate then self.opts.deactivate(self) end
    if self.owned then self.frame:Hide() end
    return self
end

-- Paints now. A native drag defers the paint to the end of the gesture.
function Host:Paint(reason)
    local handles = self.handles
    self.reason = reason or self.reason or true
    if handles and handles.drag and handles.drag.native then return false end
    reason, self.reason, self.queued = self.reason, nil, false
    if self.opts.paint then self.opts.paint(self, reason) end
    return true
end

-- A change signal: any number of requests in a frame paint once, next frame.
function Host:Request(reason)
    if not self.active then return end
    self.reason = reason or self.reason or true
    if self.queued then return end
    self.queued = true
    C_Timer.After(0, self.flush)
end

-- The one ticker; it lives only while the host is open and animating.
function Host:SetAnimate(on)
    on = on == true and self.active == true and self.opts.animate ~= nil
    if on == (self.ticker ~= nil) then return on end
    if on then
        self.ticker = C_Timer.NewTicker(self.opts.interval or 0.1, function() self.opts.animate(self) end)
    else
        self.ticker:Cancel()
        self.ticker = nil
    end
    return on
end

------------------------------------------------------------------ pools
-- Acquire(kind) takes the next object of a pool, Acquire(kind, index) the one
-- at a place the page keeps between paints. Objects are made on first use by
-- opts.pools[kind](host, index); shown and hidden state is remembered, so a
-- warm repaint makes no widget call.
function Host:Acquire(kind, index)
    self:List(kind)
    local pool = self.pools[kind]
    index = index or pool.used + 1
    local object = pool.list[index]
    if not object then
        object = self.opts.pools[kind](self, index)
        pool.list[index] = object
    end
    if index > pool.used then pool.used = index end
    if not pool.on[index] then
        pool.on[index] = true
        object:Show()
    end
    return object
end

-- Hides every object of the pool from `first` on (all by default).
function Host:ReleaseAll(kind, first)
    local pool = self.pools[kind]
    if not pool then return end
    first = first or 1
    for index = first, #pool.list do
        if pool.on[index] then
            pool.on[index] = false
            pool.list[index]:Hide()
        end
    end
    if pool.used >= first then pool.used = first - 1 end
end

-- The pool's objects in place order (the table a page may keep and read).
function Host:List(kind)
    local pool = self.pools[kind]
    if not pool then
        pool = { list = {}, on = {}, used = 0 }
        self.pools[kind] = pool
    end
    return pool.list
end

------------------------------------------------------------------ handles
local Handles = {}
Handles.__index = Handles

-- opts (all optional):
--   owner      keyboard owner and holder of the selection (default host.frame)
--   field      the owner's selection field (default "_selectedHandle")
--   keys       false: no arrow keys; keydown(frame, key) replaces the key handler
--   keep       a selected region that hides stays selected (the page clears it)
--   steps      { shift = 10, ctrl = n, alt = n } arrow step multipliers
--   threshold  distance a press must travel to be a drag (default 3)
--   escape()   Escape is consumed and calls this (the page's release)
--   combat()   refusal test (default: the Suite's combat flag)
--   dedupe(owner, dx, dy)   true when this key press was already applied
--   mark(region, selected)  selection look; tip(region, entering)  hover
--   focus(owner, region, active)  the page's keyboard capture
--   selecting(region, previous)  right after the selection changed, before the
--   keyboard moves; select(region, previous) after it; click(region, button,
--   moved); tab(shift); moved(region) after a drag wrote.
--   drag(region, phase, moved): press (before the drag exists: select here),
--   start (a followed drag passed the threshold; a native one began), stop
--   (before the write), done (after the write and moved), cancel.
--   write(x, y, dragged) gets dragged = true for the commit of a drag.
function Kit.Handles(host, opts)
    opts = opts or EMPTY
    local owner = opts.owner or host.frame
    local controller = setmetatable({ host = host, opts = opts, owner = owner, list = {}, entries = {},
        field = opts.field or "_selectedHandle", threshold = opts.threshold or 3 }, Handles)
    host.handles = controller
    if owner and opts.keys ~= false then
        owner:EnableKeyboard(true)
        owner:SetPropagateKeyboardInput(true)
        owner:SetScript("OnKeyDown", function(frame, key) return controller:Key(frame, key) end)
    end
    return controller
end

function Handles:Blocked()
    if self.opts.combat then return self.opts.combat() end
    return NS.InCombat()
end

function Handles:Typing()
    local focus = GetCurrentKeyBoardFocus()
    return focus ~= nil and focus:IsObjectType("EditBox")
end

-- The arrow multiplier of the held modifier (1 without one).
function Handles:Step()
    local steps = self.opts.steps or EMPTY
    if IsControlKeyDown() then return steps.ctrl or 1 end
    if IsShiftKeyDown() then return steps.shift or 10 end
    if steps.alt and IsAltKeyDown() then return steps.alt end
    return 1
end

local function Movable(entry)
    return entry.write ~= nil and (not entry.can or entry.can(entry.region) ~= false)
end

-- The selected region. The owner's field is the truth where there is an owner:
-- the host's selection bar and the page read it, and a page may clear it.
function Handles:Selected()
    local owner = self.owner
    if owner then return owner[self.field] or nil end
    return self.selected
end

-- Selects a region by key or region; nil clears. Keyboard goes to a shown,
-- movable selection out of combat.
function Handles:Select(target)
    local entry = target and self.entries[target] or nil
    local region, opts, owner, previous = entry and entry.region, self.opts, self.owner, self:Selected()
    if previous and previous ~= region then previous:EnableKeyboard(false) end
    self.selected = region
    if owner then owner[self.field] = region end
    if opts.selecting then opts.selecting(region, previous) end
    local active = entry ~= nil and Movable(entry) and region:IsShown() and not self:Blocked()
        and (not owner or owner:IsShown()) or false
    if region then region:EnableKeyboard(active) end
    if opts.focus then opts.focus(owner, region, active) end
    if opts.mark then
        for _, each in ipairs(self.list) do opts.mark(each, each == region) end
    end
    if opts.select then opts.select(region, previous) end
end

-- Writes the selected region's value moved by (dx, dy).
function Handles:Nudge(dx, dy)
    local entry = self.entries[self:Selected()]
    if not entry or not Movable(entry) or not entry.region:IsShown() or self:Blocked() then return false end
    local x, y = entry.read()
    if not (Readable(x) and Readable(y)) then return false end
    return self:Commit(entry, x + dx, y + dy)
end

-- Every write goes here: refused in combat, repainted either way. A drag's
-- commit says so to the page's write (dragged), which may refuse a stale one.
function Handles:Commit(entry, x, y, dragged)
    local ok = not self:Blocked() and entry.write(x, y, dragged) ~= false
    self.host:Paint("commit")
    return ok
end

-- An arrow press (unit offsets) steps by the modifier held. True when the
-- press was applied; the page's duplicate filter may also consume it.
function Handles:Arrow(dx, dy)
    local entry, owner = self.entries[self:Selected()], self.owner
    if not entry or not Movable(entry) or not entry.region:IsShown() or (owner and not owner:IsShown()) then return false end
    if self:Blocked() or self:Typing() then return false end
    local step = self:Step()
    dx, dy = dx * step, dy * step
    if self.opts.dedupe and self.opts.dedupe(owner, dx, dy) then return true end
    return self:Nudge(dx, dy)
end

-- The keys of a focused region or owner. Escape and Tab only where the page
-- asks for them; every other key goes on to the game.
function Handles:Key(frame, key)
    local opts, delta = self.opts, DELTAS[key]
    if opts.keydown then return opts.keydown(frame, key) end
    local consumed = false
    if key == "ESCAPE" and opts.escape then
        opts.escape()
        consumed = true
    elseif key == "TAB" and opts.tab then
        consumed = opts.tab(IsShiftKeyDown()) and true or false
    elseif delta then
        consumed = self:Arrow(delta[1], delta[2])
    end
    frame:SetPropagateKeyboardInput(not consumed)
    return consumed
end

------------------------------------------------------------------ drag
local function Cursor(entry)
    local x, y = GetCursorPosition()
    local scale = entry.scale and entry.scale() or entry.region:GetEffectiveScale()
    if not (Readable(x) and Readable(y) and Readable(scale)) then return nil end
    return x, y, scale > 0 and scale or 1
end

local function Stop(drag)
    local region = drag.entry.region
    region:SetScript("OnUpdate", nil)
    if drag.native then region:StopMovingOrSizing() end
end

-- Back to where the stored value puts the region: a followed drawing is
-- recentered at once; a region that moved by itself is placed again by the
-- repaint every ended drag asks for.
local function Restore(drag)
    local entry = drag.entry
    if entry.follow and not drag.blocked then entry.follow(entry.region, 0, 0) end
end

local function Follow(entry)
    local controller, drag = entry.controller, entry.controller.drag
    if not drag or drag.entry ~= entry then return end
    if controller:Blocked() then
        controller:Cancel()
        return
    end
    local x, y, scale = Cursor(entry)
    if not x then return end
    local dx, dy = (x - drag.x) / scale, (y - drag.y) / scale
    if not drag.moving then
        if math.abs(dx) + math.abs(dy) < controller.threshold then return end
        drag.moving = true
        if controller.opts.drag then controller.opts.drag(entry.region, "start") end
    end
    entry.follow(entry.region, dx, dy)
end

local function Down(entry, button)
    local controller, region = entry.controller, entry.region
    if (button and button ~= "LeftButton") or controller.drag or controller:Blocked() then return end
    entry.moved = false
    if entry.select then controller:Select(region) end
    if not entry.write then return end
    local blocked = not Movable(entry)
    if not blocked and controller.opts.drag then controller.opts.drag(region, "press") end
    local x, y, scale = Cursor(entry)
    local ox, oy = entry.read()
    if not x or not (Readable(ox) and Readable(oy)) then return end
    local drag = { entry = entry, x = x, y = y, scale = scale, ox = ox, oy = oy, native = not entry.follow,
        blocked = blocked }
    controller.drag = drag
    if drag.blocked then return end
    if entry.follow then
        region:SetScript("OnUpdate", function() Follow(entry) end)
        return
    end
    region:StartMoving()
    if controller.opts.drag then controller.opts.drag(region, "start") end
end

local function Up(entry, button)
    local controller = entry.controller
    local drag = controller.drag
    if (button and button ~= "LeftButton") or not drag or drag.entry ~= entry then return end
    controller.drag = nil
    Stop(drag)
    local x, y, scale = Cursor(entry)
    local dx, dy = x and (x - drag.x) / scale or 0, y and (y - drag.y) / scale or 0
    local moved = drag.moving or math.abs(dx) + math.abs(dy) >= controller.threshold
    entry.moved = moved
    if controller.opts.drag then controller.opts.drag(entry.region, "stop", moved) end
    local ok = moved and not drag.blocked and controller:Commit(entry, drag.ox + dx, drag.oy + dy, true)
    if not ok then Restore(drag) end
    if ok and controller.opts.moved then controller.opts.moved(entry.region) end
    if not ok then controller.host:Paint("drag") end
    if controller.opts.drag then controller.opts.drag(entry.region, "done", moved) end
end

-- Ends a drag in progress without writing: the region goes back to `read`.
function Handles:Cancel()
    local drag = self.drag
    if not drag then return end
    self.drag = nil
    Stop(drag)
    Restore(drag)
    if self.opts.drag then self.opts.drag(drag.entry.region, "cancel") end
    self.host:Paint("cancel")
end

-- Drops a drag and the selection (combat, closing the preview).
function Handles:Release()
    self:Cancel()
    if self:Selected() then self:Select(nil) end
end

------------------------------------------------------------------ regions
local function Click(entry, button)
    local controller = entry.controller
    if entry.select then controller:Select(entry.region) end
    if controller.opts.click then controller.opts.click(entry.region, button, entry.moved) end
    entry.moved = false
end

local function Hide(entry)
    local controller = entry.controller
    if controller.drag and controller.drag.entry == entry then controller:Cancel() end
    if controller:Selected() == entry.region and not controller.opts.keep then controller:Select(nil) end
end

-- Adds a region. read() returns its stored x, y; write(x, y) stores them and
-- returns false when refused (no write: select and click only). info:
-- select = false (never selected), can(region) = false (not movable now),
-- follow(region, dx, dy) (draws the drag instead of moving the region),
-- scale() (pixels per unit of the drag), clicks (mouse buttons).
function Handles:Add(key, region, read, write, info)
    info = info or EMPTY
    local opts = self.opts
    local entry = { key = key, region = region, read = read, write = write, controller = self,
        select = info.select ~= false, can = info.can, follow = info.follow, scale = info.scale }
    self.entries[region], self.entries[key] = entry, entry
    self.list[#self.list + 1] = region
    region:EnableMouse(true)
    region:RegisterForClicks(unpack(info.clicks or CLICKS))
    if write then
        region:SetMovable(not entry.follow)
        region:RegisterForDrag("LeftButton")
        region:SetScript("OnDragStart", function(_, button) Down(entry, button) end)
        region:SetScript("OnDragStop", function(_, button) Up(entry, button) end)
        if opts.keys ~= false then
            region:EnableKeyboard(false)
            region:SetScript("OnKeyDown", function(frame, pressed) return self:Key(frame, pressed) end)
        end
    end
    region:SetScript("OnMouseDown", function(_, button) Down(entry, button) end)
    region:SetScript("OnMouseUp", function(_, button) Up(entry, button) end)
    region:SetScript("OnClick", function(_, button) Click(entry, button) end)
    region:SetScript("OnHide", function() Hide(entry) end)
    if opts.tip then
        region:SetScript("OnEnter", function() opts.tip(region, true) end)
        region:SetScript("OnLeave", function() opts.tip(region, false) end)
    end
    return region
end

function Handles:Clear()
    self:Release()
    for _, region in ipairs(self.list) do
        for _, script in ipairs(SCRIPTS) do region:SetScript(script, nil) end
    end
    self.list, self.entries = {}, {}
end

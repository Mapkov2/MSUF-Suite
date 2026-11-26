-- Isolate two measured operations from ShowCaption, using the real frame fixture.
-- Counts are Lua heap and native reads/writes, independent of machine timing.
local root = assert(arg[1], "Suite root required")
local file = assert(io.open(root .. "/tools/tests/suite_window_controls_contract.lua", "rb"))
local source = file:read("*a")
file:close()
local stop = assert(source:find('assert(loadfile(arg[2] or root .. "/MSUF_Suite_Skin/Rendering/WindowControls.lua"))', 1, true))
local ns, Frame, secrets, openingWatcher = assert(loadstring(source:sub(1, stop - 1)
    .. "return NS, Frame, secretValues, watcher"))()
local chrome = ns.WindowControlChrome
local function Up(fn, name)
    for index = 1, 100 do
        local key, value = debug.getupvalue(fn, index)
        if key == name then return value end
        if not key then break end
    end
    error("missing caption operation " .. name)
end
local fade = Up(chrome.ShowCaption, "FadeNative")
local sockets = Up(Up(chrome.ShowCaption, "PlaceCloseCell"), "FadeSockets")
local release = Up(chrome.HideCaption, "RestoreNative")
local reads, hiddenReads, alphaReads, fills = 0, 0, 0, 0
local function Region(alpha)
    local region = { alpha = alpha }
    function region:GetAlpha() alphaReads = alphaReads + 1; return self.alpha end
    function region:SetAlpha(value) self.alpha = value end
    return region
end
local target, art, min, max = Region(1), Region(.65), Region(1), Region(1)
local minArt, maxArt = Region(.6), Region(.4)
target.MinimizeButton, target.MaximizeButton = min, max
function target:GetRegions() return art end
function min:GetRegions() return minArt end
function max:GetRegions() return maxArt end
local yielded = {}
ns.WindowActionSkin.Yield = function(region, value) yielded[region] = value end
local frame, children = Frame(nil, UIParent), {}
local state = { frame = frame }
function frame:GetRight() return 100 end
function frame:GetTop() return 800 end
function frame:GetChildren() return unpack(children) end
for _ = 1, 36 do
    local child = Frame(nil, frame)
    function child:GetRight() reads = reads + 1; return 100 end
    function child:GetTop() reads = reads + 1; return 800 end
    children[#children + 1] = child
end
local hidden, visible = Frame(nil, frame), Frame(nil, frame)
hidden.NineSlice, visible.NineSlice = { TopRightCorner = Region(.4) }, { TopRightCorner = Region(.5) }
hidden.shown = false
function hidden:GetRight() hiddenReads = hiddenReads + 1; return 100 end
function hidden:GetTop() hiddenReads = hiddenReads + 1; return 800 end
function visible:GetRight() return 100 end
function visible:GetTop() return 800 end
children[#children + 1] = hidden
children[#children + 1] = visible
local button = Frame(nil, frame)
local glyph = chrome.Control(button, "close", 1)
local color = glyph.fill.SetColorTexture
function glyph.fill:SetColorTexture(...) fills = fills + 1; color(self, ...) end
local forbiddenReads = 0
local function CountForbidden() forbiddenReads = forbiddenReads + 1; return false end
for _, part in ipairs({ target, min, max, art, minArt, maxArt }) do part.IsForbidden = CountForbidden end
fade(state, target)
forbiddenReads = 0
for i = 1, 100 do fade(state, target) end
print(("100 fade passes: %d native access checks"):format(forbiddenReads))
assert(forbiddenReads <= 1900, "native art rechecked the same object before any intervening write")
sockets(state)
chrome.PaintActionCell(button)
reads, hiddenReads, alphaReads, fills = 0, 0, 0, 0
collectgarbage("collect")
collectgarbage("stop")
local before = collectgarbage("count")
for _ = 1, 100 do fade(state, target); sockets(state) end
local bytes = math.floor((collectgarbage("count") - before) * 1024 + .5)
collectgarbage("restart")
for _ = 1, 100 do chrome.PaintActionCell(button) end
print(("100 warmed caption passes: %d bytes, %d geometry reads without socket or while hidden, %d fill writes"):format(
    bytes, reads + hiddenReads, fills))
release(state, target)
fade(state, target)
collectgarbage("collect")
collectgarbage("stop")
local cycleBefore = collectgarbage("count")
for _ = 1, 100 do
    release(state, target)
    fade(state, target)
end
local cycleBytes = math.floor((collectgarbage("count") - cycleBefore) * 1024 + .5)
collectgarbage("restart")
print(("100 warmed native fade/release cycles: %d bytes"):format(cycleBytes))
assert(reads + hiddenReads == 0, "queried coordinates for a child without visible socket art")
assert(bytes < 128, "native and socket discovery allocate on repeated layout")
assert(cycleBytes < 128, "reopening reallocated the native art records")
assert(fills == 0, "unchanged caption fill was rewritten")
button.scripts.OnEnter(button); button.scripts.OnMouseDown(button); button.scripts.OnMouseUp(button)
assert(fills == 3, "hover, down and up stopped changing caption fill")
ns.Theme.GetColor = function(role) if role == "danger" then return .2, .1, .3, 1 end; return 1, 1, 1, 1 end
chrome.PaintActionCell(button)
assert(fills == 4 and glyph.fill.color[1] == .2, "recolor missed the updated theme")
local hiddenColor = {}
secrets[hiddenColor] = true
local getColor = ns.Theme.GetColor
ns.Theme.GetColor = function(role)
    if role == "danger" then return hiddenColor, .1, .3, 1 end
    return getColor(role)
end
chrome.PaintActionCell(button)
chrome.PaintActionCell(button)
ns.Theme.GetColor = getColor
chrome.PaintActionCell(button)
assert(fills == 7 and glyph.fill.color[1] == .2, "secret or subsequent public fill was cached")
local privatePart, denied = {}, false
secrets[privatePart] = true
function min:IsForbidden() return denied end
denied = true
fade(state, target)
denied = false
fade(state, target)
local regions = target.GetRegions
function target:GetRegions() return privatePart end
fade(state, target)
target.GetRegions = nil
fade(state, target)
target.GetRegions = regions
fade(state, target)
release(state, target)
assert(min.alpha == 1 and minArt.alpha == .6 and art.alpha == .65,
    "temporary protection or a blind region slot discarded the original alpha")
fade(state, target)
local oldMin, oldArt = min, art
min, art = Region(.7), Region(.2)
target.MinimizeButton = min
fade(state, target)
assert(oldMin.alpha == 1 and oldArt.alpha == .65 and yielded[oldMin] == false,
    "replaced regions and size-toggle button did not leave the former fade owner")
assert(min.alpha == 0 and art.alpha == 0 and yielded[min] == true, "replacement button and art were not claimed")
oldArt:SetAlpha(.9)
assert(oldArt.alpha == .9, "a pooled former part is still suppressed")
local originalCorner = visible.NineSlice.TopRightCorner
visible.NineSlice.TopRightCorner = privatePart
sockets(state)
assert(originalCorner.alpha == 0, "secret replacement field uncovered the last owned socket")
visible.NineSlice.TopRightCorner = Region(.3)
sockets(state)
assert(originalCorner.alpha == .5 and visible.NineSlice.TopRightCorner.alpha == 0, "replaced socket retained the fade")
release(state, target)
assert(min.alpha == .7 and art.alpha == .2 and yielded[min] == false, "current parts failed to restore")
fade(state, target)
art.alpha = .98 -- Renderer changed it without passing through the Lua setter.
release(state, target)
assert(art.alpha == .98, "releasing the skin clobbered foreign native alpha")
print("WindowControlChrome scoped work, theme, replacement and restoration passed")

-- Run the real caption entry point repeatedly on one stationary open window.
local function TestStableCaption()
    local host = Frame("CharacterFrame", UIParent)
    function host:GetRight() return self.left + self.width end
    local native = Frame(nil, host, "Button")
    host.left, host.top, host.width = 100, 800, 600
    native.left, native.top, native.width, native.height = 676, 800, 24, 24
    local fixed = Frame(nil, host)
    local classifications = 0
    function fixed:GetObjectType() classifications = classifications + 1; return "Frame" end
    function host:GetChildren() return fixed, native end
    local owner = { frame = host, close = native, name = "CharacterFrame" }
    local refreshes = 0
    chrome.SetFocusRefresh(function(rootFrame)
        assert(rootFrame == host)
        refreshes = refreshes + 1
    end)
    chrome.ShowCaption(owner, 8)
    local cell = assert(owner.closeCell, "missing close cell")
    local size, level, point = cell.SetSize, cell.SetFrameLevel, cell.SetPoint
    local writes = 0
    function cell:GetPoint() return unpack(self.point or {}) end
    function cell:SetSize(...) writes = writes + 1; return size(self, ...) end
    function cell:SetFrameLevel(...) writes = writes + 1; return level(self, ...) end
    function cell:SetPoint(...) writes = writes + 1; return point(self, ...) end
    refreshes, classifications = 0, 0
    for _ = 1, 100 do chrome.ShowCaption(owner, 8) end
    print(("100 stable window captions: %d native cell writes, %d focus notifications, %d static type queries"):format(
        writes, refreshes, classifications))
    assert(writes == 0 and classifications == 0, "unchanged captions rewrote geometry or reclassified a static child")

    assert(refreshes > 0, "native layout did not invalidate focus for undiscovered children")
    cell:SetPoint("CENTER", host, "CENTER", 0, 0)
    cell:SetFrameLevel(1)
    cell:SetSize(2, 2)
    chrome.ShowCaption(owner, 8)
    assert(cell.point[1] == "TOPRIGHT" and cell:GetFrameLevel() == 8 and cell:GetWidth() >= 14,
        "changed owned geometry was not repaired")
    local restriction = {}
    secrets[restriction] = true
    function cell:IsAnchoringRestricted() return restriction end
    local getPoint = cell.GetPoint
    function cell:GetPoint() error("read a restricted anchor") end
    chrome.ShowCaption(owner, 8)
    cell.IsAnchoringRestricted, cell.GetPoint = nil, getPoint
    local newCorner = Region(.8)
    host.NineSlice = { TopRightCorner = newCorner }
    chrome.ShowCaption(owner, 8)
    assert(newCorner.alpha == 0 and refreshes > 0, "newly faded corner did not notify focus")
    local afterCorner = refreshes
    host.NineSlice.TopRightCorner = Region(.5)
    chrome.ShowCaption(owner, 8)
    assert(newCorner.alpha == .8 and refreshes > afterCorner, "replaced native corner did not restore and notify")
    local afterSwap = refreshes
    chrome.HideCaption(owner)
    assert(refreshes > afterSwap and not cell:IsShown(), "hiding caption did not notify")
    chrome.ShowCaption(owner, 8)
    assert(cell:IsShown(), "reopened caption stayed hidden")
end
TestStableCaption()


-- Native alpha can change without calling SetAlpha. Poll each distinct
-- native caption root once, including the close button when not in the set.
do
    local nativeShown = ns.WindowControlNativeArt.Shown or Up(Up(chrome.Settle, "Watch"), "NativeShown")
    local close, toggle = Region(0), Region(0)
    local owner = { close = close, nativeRoots = { [close] = true, [toggle] = true } }
    alphaReads = 0
    for _ = 1, 100 do assert(not nativeShown(owner)) end
    assert(alphaReads == 200, ("100 checks of two hidden roots used %d native alpha reads"):format(alphaReads))
    toggle.alpha = 1
    assert(nativeShown(owner), "native alpha bypass on the size toggle was missed")
    toggle.alpha, close.alpha, owner.nativeRoots[close] = 0, 1, nil
    assert(nativeShown(owner), "close removed from the native set no longer recovers")
end

-- A settled generic window has one cancellable deadline. Exercise the real
-- watched root alongside it and simulate a native reset without a Lua setter.
do
    local originalTimer, originalCombat, originalQueue = C_Timer.NewTimer, ns.IsCombatLocked, ns.Registry.QueueJob
    local timers, combatCalls, locked = {}, 0, false
    ns.IsCombatLocked = function() combatCalls = combatCalls + 1; return locked end
    ns.Registry.QueueJob = function() end
    C_Timer.NewTimer = function(delay, callback)
        assert(delay == 3)
        local timer = { run = callback }
        function timer:Cancel() self.cancelled = true end
        timers[#timers + 1] = timer
        return timer
    end
    local function MakeWindow(name)
        local host = Frame(name, UIParent)
        local state = { frame = host, name = name, close = Region(0), closeCell = Frame(nil, host), repairs = 0 }
        function state.settle()
            assert(not locked and host:IsVisible(), "hidden or combat layout")
            state.repairs = state.repairs + 1
            state.close.alpha = 0
        end
        return state
    end
    local generic, second, special = MakeWindow("PlayerSpellsFrame"), MakeWindow("ProfessionsFrame"), MakeWindow("LFGParentFrame")
    local function Arm(state) chrome.Settle(state, 8, function() return true end) end
    local function Tick()
        local step = openingWatcher.scripts.OnUpdate
        if step and openingWatcher.shown then step(openingWatcher, .01) end
    end
    Arm(generic)
    alphaReads, combatCalls = 0, 0
    for _ = 1, 180 do Tick() end
    print(("180 unchanged ordinary opening frames: %d native alpha reads, %d combat probes"):format(alphaReads, combatCalls))
    assert(alphaReads == 0 and combatCalls == 0 and not openingWatcher.scripts.OnUpdate, "ordinary window polled during opening")
    Arm(generic)
    assert(#timers == 2 and timers[1].cancelled, "repeated layout retained its former final timer")
    timers[1].run()
    assert(generic.repairs == 0, "superseded deadline ran")
    timers[2].run()
    assert(generic.repairs == 1 and not openingWatcher.events.PLAYER_REGEN_DISABLED, "final layout failed to disarm")
    Arm(generic); Arm(second); Arm(special)
    alphaReads, combatCalls = 0, 0
    for _ = 1, 180 do Tick() end
    print(("180 unchanged workaround frames alongside two ordinary windows: %d native alpha reads, %d combat probes")
        :format(alphaReads, combatCalls))
    assert(alphaReads == 180 and combatCalls == 0 and special.repairs == 0, "stable workarounds probed combat or other windows")
    special.close.alpha = 1
    Tick()
    assert(special.repairs == 1 and special.close.alpha == 0 and combatCalls == 1, "native write bypass was missed")
    generic.frame:Hide()
    assert(timers[3].cancelled, "hidden generic window retained its deadline")
    timers[3].run()
    locked, special.close.alpha = true, 1
    Tick()
    assert(special.repairs == 1 and special.close.alpha == 1, "repair wrote during the combat edge")
    assert(not openingWatcher.scripts.OnUpdate and openingWatcher.events.PLAYER_REGEN_DISABLED,
        "last workaround left a driver or lost the ordinary window's combat subscription")
    openingWatcher.scripts.OnEvent(openingWatcher, "PLAYER_REGEN_DISABLED")
    assert(timers[4].cancelled and not openingWatcher.events.PLAYER_REGEN_DISABLED, "combat retained opening work")
    locked = false
    timers[4].run()
    assert(second.repairs == 0, "cancelled work replayed on leaving combat")
    for _, name in ipairs({ "GuildFrame", "CommunitiesFrame", "SettingsPanel", "AddonList", "WorldMapFrame" }) do
        local state = MakeWindow(name)
        Arm(state)
        assert(openingWatcher.scripts.OnUpdate, "unobserved native reset for " .. name)
        state.frame:Hide()
        assert(not openingWatcher.scripts.OnUpdate and not openingWatcher.events.PLAYER_REGEN_DISABLED, "closed workaround retained work")
    end
    local late = MakeWindow("AnotherPanel")
    late.settle = nil
    function late.close:IsShown() return true end
    local paint = chrome.ShowCaption
    chrome.ShowCaption = function(state) state.close.alpha = 0 end
    Arm(late)
    local final = timers[#timers]
    assert(not openingWatcher.scripts.OnUpdate)
    late.close.alpha = 1
    late.settle() -- native X returned between OnShow and the next-frame settle
    assert(late.reported and openingWatcher.scripts.OnUpdate and late.close.alpha == 0, "newly observed native reset did not arm fallback")
    late.close.alpha = 1
    Tick()
    assert(late.close.alpha == 0, "dynamically discovered owner lost its next reset")
    final.run()
    assert(not openingWatcher.scripts.OnUpdate, "promoted owner outlived its original deadline")
    Arm(late)
    assert(openingWatcher.scripts.OnUpdate and timers[#timers] == final, "reopening forgot a proven native reset")
    late.frame:Hide()
    assert(not openingWatcher.scripts.OnUpdate)
    chrome.ShowCaption = paint
    C_Timer.NewTimer, ns.IsCombatLocked, ns.Registry.QueueJob = originalTimer, originalCombat, originalQueue
end

-- A locally shown caption inherits its window's visibility. The native size
-- toggle and its visible child each emit OnShow during the same opening.
do
    local host = Frame("CommunitiesFrame", UIParent)
    local toggle = Frame(nil, host)
    local max, min = Frame(nil, toggle), Frame(nil, toggle)
    toggle.MaximizeButton, toggle.MinimizeButton = max, min
    min.shown = false
    local state = { frame = host, name = "CommunitiesFrame", closeCell = Frame(nil, host), captionLevel = 8 }
    local oldShow = chrome.ShowCaption
    local paints, width = 0, nil
    chrome.ShowCaption = function(s)
        paints, width = paints + 1, s.frame:GetWidth()
    end
    chrome.FollowSizeToggle(state, toggle)
    local function Fire(widget, script)
        for _, callback in ipairs(widget.hooks[script] or {}) do callback(widget) end
    end
    local queue = {}
    local queueJob, cancelJob = ns.Registry.QueueJob, ns.Registry.CancelJob
    ns.Registry.QueueJob = function(job) queue[job] = true end
    ns.Registry.CancelJob = function(job) queue[job] = nil end
    for i = 1, 10 do
        host.shown = false
        Fire(toggle, "OnHide")
        Fire(max, "OnHide")
        assert(paints == i - 1, "an inherited toggle hide laid out a closed window")
        host.shown, host.width = true, 500 + i
        Fire(toggle, "OnShow")
        -- The final native layout changes before its child becomes visible.
        host.width = 650 + i
        Fire(max, "OnShow")
        assert(paints == i and width == host.width and not next(queue), "duplicate/missed parent-first toggle layout")
    end
    max.shown, min.shown = false, true
    Fire(max, "OnHide")
    Fire(min, "OnShow")
    assert(paints == 11, "explicit native size change did not paint synchronously")
    host.shown = false
    Fire(min, "OnHide")
    Fire(toggle, "OnHide")
    host.shown = true
    Fire(min, "OnShow")
    host.width = 800
    Fire(toggle, "OnShow")
    assert(width == 800 and not next(queue), "child-first propagation missed the final parent layout")
    host.shown = false
    Fire(min, "OnHide")
    Fire(toggle, "OnHide")
    min.parent, host.shown = UIParent, true
    Fire(toggle, "OnShow")
    assert(width == host.width and not next(queue), "a reparented child suppressed its old toggle")
    min.parent = toggle
    host.shown = false
    Fire(min, "OnHide")
    Fire(toggle, "OnHide")
    host.shown = true
    Fire(toggle, "OnShow")
    local pending = next(queue)
    assert(pending, "missing fallback when the child event is interrupted")
    min.shown = false
    queue[pending] = nil
    local before = paints
    pending()
    assert(paints == before + 1, "interrupted native propagation left a stale caption")
    min.shown, host.shown = true, false
    Fire(min, "OnHide")
    Fire(toggle, "OnHide")
    host.shown = true
    Fire(toggle, "OnShow")
    assert(next(queue), "missing late callback guard")
    host.shown = false
    Fire(toggle, "OnHide")
    assert(not next(queue), "closed-window toggle retained a fallback job")
    host.shown = true
    local realParent = min.GetParent
    local restricted = {}
    secrets[restricted] = true
    function min:GetParent() return restricted end
    before = paints
    Fire(toggle, "OnShow")
    assert(paints == before + 1 and not next(queue), "unreadable child parent suppressed native layout")
    min.GetParent = realParent
    ns.Registry.QueueJob, ns.Registry.CancelJob = queueJob, cancelJob
    chrome.ShowCaption = oldShow
end

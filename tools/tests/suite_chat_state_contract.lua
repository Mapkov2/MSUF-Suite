-- Suite.ChatState (MSUF_Suite/Core/ChatState.lua): Blizzard's chat state
-- reported without running inside Blizzard's chat code, and no Suite code at
-- all while chat is idle.
--   * No hooksecurefunc, no HookScript but OnKeyDown on the permanent boxes;
--     box reports come from Blizzard's EventRegistry triggers and skip a
--     temporary whisper box.
--   * The follower runs only after a mouse button, a chat event, a focused
--     box or Edit Mode, and stops once nothing is pending.
--   * Window reports arrive on the next frame, once per burst; whisper
--     windows and closed windows are found by the open-window check.
--   * Selection, layout (after Blizzard's pending dock relayout), drag end
--     and size changes are reported; hover reads run on a ticker only while
--     a watcher asks for hover.
local root = assert(arg[1], "Suite root required")
local checks = 0
local function Check(value, message)
    assert(value, message)
    checks = checks + 1
end

local now = 0
GetTime = function() return now end
local nextFrame, tickers = {}, {}
C_Timer = {
    After = function(_, callback) nextFrame[#nextFrame + 1] = callback end,
    NewTicker = function(seconds, callback)
        local ticker = { seconds = seconds, callback = callback }
        function ticker:Cancel() self.cancelled = true end
        tickers[#tickers + 1] = ticker
        return ticker
    end,
}
local function RunNextFrame()
    local queued = nextFrame
    nextFrame = {}
    for _, callback in ipairs(queued) do callback() end
end
hooksecurefunc = function(name) error("ChatState hooked " .. tostring(name)) end
local reported = {}
local finiteReads = 0
hasanysecretvalues = function(...)
    for i = 1, select("#", ...) do if select(i, ...) == "secret" then return true end end
    return false
end
local Suite = {
    Public = function(value) return value ~= "secret" end,
    Finite = function(value)
        finiteReads = finiteReads + 1
        return type(value) == "number" and value == value and math.abs(value) < math.huge
    end,
    Safety = { IsForbidden = function() return false end },
    Client = { SupportsEvent = function(event) return event ~= "ACTIVE_COMBAT_CONFIG_CHANGED" end },
    Dispatch = function(callback, ...)
        local ok, problem = pcall(callback, ...)
        if not ok then reported[#reported + 1] = problem end
    end,
}

local frames = {}
CreateFrame = function()
    local frame = { shown = true, events = {} }
    function frame:Show() self.shown = true end
    function frame:Hide() self.shown = false end
    function frame:IsShown() return self.shown end
    function frame:SetScript(script, callback) self[script] = callback end
    function frame:RegisterEvent(event) self.events[event] = true end
    frames[#frames + 1] = frame
    return frame
end
local registry = { callbacks = {} }
function registry:RegisterCallback(event, callback, owner)
    self.callbacks[event] = function(...) return callback(owner, ...) end
end
EventRegistry = registry
Constants = { ChatFrameConstants = { MaxChatWindows = 10 } }
local buttonDown = false
IsMouseButtonDown = function(button) return button == "LeftButton" and buttonDown end

local function ChatFrame(index, temporary)
    local frame = { shown = true, width = 400, height = 200, isTemporary = temporary, hooks = {} }
    function frame:IsShown() return self.shown end
    function frame:GetWidth() return self.width end
    function frame:GetHeight() return self.height end
    function frame:GetSize() return self.width, self.height end
    function frame:GetNumPoints() return 0 end
    function frame:HookScript() error("ChatState hooked a chat frame script") end
    local box = { name = "ChatFrame" .. index .. "EditBox", hooks = {} }
    function box:GetName() return self.name end
    function box:GetNumPoints() return 0 end
    function box:HookScript(script, callback)
        Check(script == "OnKeyDown", "ChatState hooked the input line's " .. script)
        Check(not self.hooks[script], "a box took its key hook twice")
        self.hooks[script] = callback
    end
    frame.editBox = box
    _G["ChatFrame" .. index], _G["ChatFrame" .. index .. "EditBox"] = frame, box
    return frame
end
local first, second = ChatFrame(1), ChatFrame(2)
UIParent = {}
local function Geometry(region, parent)
    region.nativeX, region.nativeY = 12, 52
    function region:GetNumPoints() return 1 end
    function region:GetPoint() return "BOTTOMLEFT", parent, "BOTTOMLEFT", self.nativeX, self.nativeY end
    function region:GetEffectiveScale() return 1 end
    region.GetWidth = region.GetWidth or function() return 400 end
    region.GetHeight = region.GetHeight or function() return 32 end
    region.GetSize = region.GetSize or function(self) return self:GetWidth(), self:GetHeight() end
end
Geometry(first, UIParent)
Geometry(first.editBox, first)
CHAT_FRAMES = { "ChatFrame1", "ChatFrame2" }
GENERAL_CHAT_DOCK = { selected = first, DOCKED_CHAT_FRAMES = { first, second } }
SELECTED_CHAT_FRAME = first

assert(loadfile(root .. "/MSUF_Suite/Core/ChatState.lua"))("MSUF_Suite", Suite)
local State = Suite.ChatState
Check(#frames == 0, "ChatState created frames before anyone watched")

local seen = {}
local function Record(kind)
    return function(owner, ...)
        Check(owner == seen, "a handler did not get its owner first")
        seen[#seen + 1] = { kind, ... }
    end
end
local function Count(kind)
    local count = 0
    for _, entry in ipairs(seen) do if entry[1] == kind then count = count + 1 end end
    return count
end
local function Last(kind)
    for index = #seen, 1, -1 do if seen[index][1] == kind then return seen[index] end end
end
local handlers = {}
for _, kind in ipairs({ "windows", "selection", "layout", "moved", "resized", "box", "key" }) do
    handlers[kind] = Record(kind)
end
State.Watch(seen, handlers)
local follower, events = frames[1], frames[2]
local function Tick(seconds)
    now = now + (seconds or 0.016)
    if follower.shown then follower.OnUpdate(follower, seconds or 0.016) end
end

-------------------------------------------------------------- no hooks
Check(first.editBox.hooks.OnKeyDown and second.editBox.hooks.OnKeyDown, "a permanent box missed its key hook")
Check(registry.callbacks["ChatFrame.OnEditBoxFocusGained"] and registry.callbacks["ChatFrame.OnEditBoxHide"]
    and registry.callbacks["EditMode.Exit"], "Blizzard's EventRegistry triggers are not followed")
Check(events.events.GLOBAL_MOUSE_DOWN and events.events.UPDATE_CHAT_WINDOWS and events.events.CHAT_MSG_WHISPER,
    "the arming events are not registered")
Check(#tickers == 0, "hover reads ran without a hover watcher")

-------------------------------------------------------------- idle
-- The first reports set the baseline; then the follower stops.
for _ = 1, 40 do Tick() end
Check(not follower.shown, "the follower kept running while chat was idle")
local before = #seen
for _ = 1, 100 do Tick() end
Check(#seen == before, "idle chat reported")

-------------------------------------------------------------- selection
events.OnEvent(events, "GLOBAL_MOUSE_DOWN")
Check(follower.shown, "a mouse button did not arm the follower")
GENERAL_CHAT_DOCK.selected, SELECTED_CHAT_FRAME = second, second
Tick()
Check(Count("selection") >= 1 and Last("selection") and Last("layout"),
    "a tab selection was not reported with its layout")
local layouts = Count("layout")
-- Blizzard's relayout after a resize of the primary window is pending
-- while the dock holds leftTab (FCFDock_OnPrimarySizeChanged).
GENERAL_CHAT_DOCK.leftTab = first
Tick(1)
Check(follower.shown and Count("layout") == layouts, "a pending dock relayout was reported early")
GENERAL_CHAT_DOCK.leftTab = nil
Tick()
Check(Count("layout") == layouts + 1, "a finished dock relayout was not reported")
for _ = 1, 40 do Tick() end
Check(not follower.shown, "the follower did not stop after the relayout")

-------------------------------------------------------------- drag and size
-- A held resize grip: the size is read each frame and reported at once.
events.OnEvent(events, "GLOBAL_MOUSE_DOWN")
buttonDown = true
first.width = 420
Tick()
Check(Last("resized") and Last("resized")[2] == first, "a live resize was not reported while the button was held")
local lastPublicWidth, resizeCount = first.width, Count("resized")
first.width = "secret"
Tick()
first.width = lastPublicWidth
Tick()
Check(Count("resized") == resizeCount, "a restricted resize replaced the previous public dimensions")
buttonDown = false
events.OnEvent(events, "GLOBAL_MOUSE_DOWN")
MOVING_CHATFRAME = second
second.width = 450
for _ = 1, 60 do Tick() end
Check(follower.shown, "the follower stopped during a drag")
Check(Last("resized") and Last("resized")[2] == second, "a resized window was not reported")
MOVING_CHATFRAME = nil
Tick()
Check(Last("moved") and Last("moved")[2] == second, "a released drag was not reported")
for _ = 1, 40 do Tick() end
Check(not follower.shown, "the follower kept running after the drag")

-------------------------------------------------------------- windows
local windows = Count("windows")
events.OnEvent(events, "UPDATE_CHAT_WINDOWS")
events.OnEvent(events, "UPDATE_FLOATING_CHAT_WINDOWS")
Check(Count("windows") == windows, "a window report ran inside Blizzard's own event handling")
RunNextFrame()
Check(Count("windows") == windows + 1, "a burst of window events was not reported once on the next frame")
-- A whisper opens a temporary window inside Blizzard's handler.
local whisper = ChatFrame(11, true)
whisper.inUse = true
CHAT_FRAMES[3] = "ChatFrame11"
events.OnEvent(events, "CHAT_MSG_WHISPER")
Tick()
RunNextFrame()
Check(Count("windows") == windows + 2, "a new whisper window was not reported")
-- A window closed from its tab menu: a click, then the open-window check.
events.OnEvent(events, "GLOBAL_MOUSE_UP")
whisper.inUse, whisper.shown = false, false
Tick(0.6)
RunNextFrame()
Check(Count("windows") == windows + 3, "a closed window was not reported")
for _ = 1, 40 do Tick() end

-------------------------------------------------------------- boxes and keys
registry.callbacks["ChatFrame.OnEditBoxFocusGained"](first.editBox)
Check(Last("box") and Last("box")[2] == "focus" and Last("box")[3] == first.editBox and follower.shown,
    "a focused permanent box was not reported")
local boxes = Count("box")
registry.callbacks["ChatFrame.OnEditBoxFocusGained"](whisper.editBox)
Check(Count("box") == boxes, "a temporary whisper box was reported")
local beyond = ChatFrame(12)
registry.callbacks["ChatFrame.OnEditBoxShow"](beyond.editBox)
Check(Count("box") == boxes, "a box beyond the permanent windows was reported")
Check(not whisper.editBox.hooks.OnKeyDown, "a temporary whisper box took a key hook")
local unnamed = { GetName = function() return nil end }
registry.callbacks["ChatFrame.OnEditBoxFocusGained"](unnamed)
Check(Count("box") == boxes and not State.IsPermanentBox(unnamed), "an unnamed box was reported")
first.editBox.hooks.OnKeyDown(first.editBox, "ENTER")
Check(Last("key") and Last("key")[2] == first.editBox and Last("key")[3] == "ENTER", "a key was not reported")
for _ = 1, 40 do Tick() end

-------------------------------------------------------------- edit mode
registry.callbacks["EditMode.Enter"]()
for _ = 1, 120 do Tick() end
Check(follower.shown, "the follower stopped while Edit Mode was open")
registry.callbacks["EditMode.Exit"]()
RunNextFrame()
for _ = 1, 40 do Tick() end
Check(not follower.shown, "the follower kept running after Edit Mode")

-------------------------------------------------------------- native geometry
handlers.geometry = Record("geometry")
State.Watch(seen, handlers)
Tick()
finiteReads = 0
Tick(.11)
Check(finiteReads == 5, "steady chat geometry revalidated dimensions already equal to its finite snapshot")
for _ = 1, 50 do Tick() end
-- Only the first native frame needs geometry methods for these focused reads.
second.GetNumPoints = function() return 0 end
Check(not events.events.ACTIVE_COMBAT_CONFIG_CHANGED, "unsupported geometry event was registered")
for _, event in ipairs({ "PLAYER_LEVEL_UP", "PLAYER_LEVEL_CHANGED", "PLAYER_ENTERING_WORLD",
    "LOADING_SCREEN_DISABLED", "EDIT_MODE_LAYOUTS_UPDATED", "PLAYER_SPECIALIZATION_CHANGED" }) do
    Check(events.events[event], event .. " cannot wake geometry observation")
    local count = Count("geometry")
    events.OnEvent(events, event, "player")
    Tick(.2)
    first.nativeX = first.nativeX + 1
    Tick(.2)
    Check(Count("geometry") > count and Last("geometry")[2] == first,
        event .. " missed a late pure anchor change")
    for _ = 1, 150 do Tick() end
    Check(not follower.shown, event .. " left permanent geometry polling")
end
local count = Count("geometry")
events.OnEvent(events, "PLAYER_SPECIALIZATION_CHANGED", "party1")
Check(not follower.shown, "another unit's specialization armed chat")
registry.callbacks["ChatFrame.OnEditBoxShow"](first.editBox)
first.editBox.nativeY = first.editBox.nativeY + 7
Tick(.2)
Check(Count("geometry") > count and Last("geometry")[2] == first, "input-only native anchor reset was missed")
count = Count("geometry")
first.editBox.nativeX = "secret"
Tick(.2)
Check(Count("geometry") == count, "restricted input coordinates were compared or reported")
first.editBox.nativeX = 12
for _ = 1, 150 do Tick() end
Check(not follower.shown, "input geometry left permanent polling")
local conflictOwner = {}
State.Watch(conflictOwner, { geometry = function() State.GeometryRepaired() end })
events.OnEvent(events, "PLAYER_LEVEL_UP")
for _ = 1, 200 do
    first.nativeX = first.nativeX + 1
    Tick()
end
Check(not follower.shown, "repairs extended one native event into permanent polling")
State.Unwatch(conflictOwner)

-------------------------------------------------------------- hover
local hovers = {}
local hoverOwner = {}
State.Watch(hoverOwner, { hover = function(owner, frame, on)
    Check(owner == hoverOwner, "the hover owner was not passed first")
    hovers[#hovers + 1] = { frame, on }
end, windows = function() error("one watcher's failure") end })
Check(#tickers == 1 and tickers[1].seconds == 0.1, "a hover watcher did not start the ten-per-second reads")
first.hasBeenFaded = true
tickers[1].callback()
Check(#hovers == 1 and hovers[1][1] == first and hovers[1][2] == true and State.IsHovered(first),
    "Blizzard's fade-in was not reported")
tickers[1].callback()
Check(#hovers == 1, "an unchanged hover was reported again")
first.hasBeenFaded = nil
tickers[1].callback()
Check(#hovers == 2 and hovers[2][2] == false, "Blizzard's fade-out was not reported")
-- One watcher's failing handler does not stop the others.
windows = Count("windows")
events.OnEvent(events, "UPDATE_CHAT_COLOR")
RunNextFrame()
Check(Count("windows") == windows + 1 and #reported == 1, "a failing watcher stopped another's report")
State.Unwatch(hoverOwner)
Check(tickers[1].cancelled, "the hover reads outlived their watcher")
State.Watch(seen, handlers)
Check(#tickers == 1, "re-watching without hover started the reads")
State.Unwatch(seen)
Check(not follower.shown, "the follower ran without watchers")
events.OnEvent(events, "GLOBAL_MOUSE_DOWN")
Check(not follower.shown, "the follower ran without watchers after a click")
print("Suite ChatState: " .. checks .. " checks passed")

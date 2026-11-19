local _, Suite = ...
-- Blizzard chat state, watched without running inside Blizzard's chat code.
-- A Suite closure that runs inside one of Blizzard's chat executions -- a
-- hooksecurefunc post-hook on an FCF_* function, a HookScript on a chat frame
-- or edit box that Blizzard's code dispatches (Show, SetFocus, SetText), or a
-- Blizzard chat function called from Suite code -- leaves the rest of that
-- execution tainted. FCF_Tab_OnClick then writes LAST_ACTIVE_CHAT_EDIT_BOX,
-- ChatFrameUtil.ActivateChat the box's chatType attribute and the whisper
-- tail SetLastTellTarget under that taint: later sends become addon calls of
-- C_ChatInfo.SendChatMessage, which chat lockdown refuses, and the box meets
-- secret text it may no longer index (ChatFrameEditBox.lua ParseText).
-- Consumers watch here instead, on live and forever alike:
--   box(owner, kind, editBox)  kind show/hide/focus/release. Blizzard's own
--     ChatFrame.OnEditBox* EventRegistry triggers; CallbackRegistry runs each
--     callback through securecallfunction, so the taint ends with it. Only
--     the boxes of the permanent windows are reported: a temporary whisper
--     box holds a secret tell target.
--   key(owner, editBox, key)   OnKeyDown of a permanent box: physical input
--     only, dispatched by the client, never from inside Blizzard's code.
--   windows(owner)             the next frame after UPDATE_CHAT_WINDOWS,
--     UPDATE_FLOATING_CHAT_WINDOWS, UPDATE_CHAT_COLOR, Edit Mode exit, a scale
--     change, or once the set of open windows changed (temporary whisper
--     windows, a window closed from its tab menu).
--   selection(owner)           SELECTED_CHAT_FRAME or the dock's selection.
--   layout(owner)              Blizzard finished laying out the dock tabs.
--   moved(owner, frame)        a dragged chat window was let go.
--   resized(owner, frame)      a chat window's size changed.
--   geometry(owner, frame)     a window or permanent input changed its anchor,
--     dimensions or scale during a bounded native-layout observation.
--   hover(owner, frame, on)    Blizzard faded a window's chrome in or out
--     (its own hasBeenFaded flag, set by FCF_FadeIn/OutChatFrame).
-- Idle chat costs nothing. The follower, an owned OnUpdate that only reads
-- Blizzard's fields, runs only after something can have changed them: a
-- mouse button anywhere (GLOBAL_MOUSE_DOWN/UP: tab clicks, drags, resizes,
-- menus), a chat event, a focused input line, Edit Mode. It stops once
-- nothing is pending. Hover has no event: only while a watcher asks for it
-- (handlers.hover) a ticker reads the windows' hasBeenFaded flags ten times
-- a second. Every callback runs isolated (Dispatch).
local ChatState = { owners = {} }
Suite.ChatState = ChatState
local owners = ChatState.owners
local Dispatch = Suite.Dispatch
local ARM_SECONDS, WINDOW_CHECK, HOVER_PROBE, MAX_FRAMES = 0.5, 0.5, 0.1, 64
local GEOMETRY_SECONDS, GEOMETRY_CHECK = 2, 0.1
local BOX_EVENTS = {
    ["ChatFrame.OnEditBoxShow"] = "show", ["ChatFrame.OnEditBoxHide"] = "hide",
    ["ChatFrame.OnEditBoxFocusGained"] = "focus", ["ChatFrame.OnEditBoxFocusLost"] = "release",
}
local WINDOW_EVENTS = {
    UPDATE_CHAT_WINDOWS = true, UPDATE_FLOATING_CHAT_WINDOWS = true, UPDATE_CHAT_COLOR = true,
    UI_SCALE_CHANGED = true, DISPLAY_SIZE_CHANGED = true,
}
local ARM_EVENTS = {
    GLOBAL_MOUSE_DOWN = true, GLOBAL_MOUSE_UP = true, CHAT_MSG_WHISPER = true, CHAT_MSG_WHISPER_INFORM = true,
    CHAT_MSG_BN_WHISPER = true, CHAT_MSG_BN_WHISPER_INFORM = true,
}
local GEOMETRY_EVENTS = {
    EDIT_MODE_LAYOUTS_UPDATED = true, PLAYER_SPECIALIZATION_CHANGED = true,
    PLAYER_ENTERING_WORLD = true, LOADING_SCREEN_DISABLED = true,
    PLAYER_LEVEL_UP = true, PLAYER_LEVEL_CHANGED = true,
    ACTIVE_TALENT_GROUP_CHANGED = true, ACTIVE_COMBAT_CONFIG_CHANGED = true,
    INPUT_DEVICE_INTERFACE_TRANSITION = true,
}
local permanent = setmetatable({}, { __mode = "k" })
local keyed = setmetatable({}, { __mode = "k" })
local hovered = setmetatable({}, { __mode = "k" })
local sizes = setmetatable({}, { __mode = "k" })
local geometry = setmetatable({}, { __mode = "k" })
local geometryWanted, geometryDue, sinceGeometry = false, false, 0
local follower, events, probe, windowsDue, layoutDue, checkDue, editMode
local lastSelected, lastChat, lastDocked, lastFrames, lastMoving, lastWindows = false, false, -1, -1, nil, nil
local armedUntil, sinceCheck = 0, 0

local signals = { "box", "key", "windows", "selection", "layout", "moved", "resized", "geometry", "settled", "hover" }
local subscribers = {}

local function CompileSubscribers()
    local nextSubscribers = {}
    for _, kind in ipairs(signals) do nextSubscribers[kind] = {} end
    for owner, handlers in pairs(owners) do
        for _, kind in ipairs(signals) do
            if handlers[kind] then
                local list = nextSubscribers[kind]
                list[#list + 1] = { owner = owner, handlers = handlers }
            end
        end
    end
    subscribers = nextSubscribers
end

local function Notify(kind, ...)
    local list = subscribers[kind]
    if not list then return end
    for i = 1, #list do
        local item = list[i]
        if owners[item.owner] == item.handlers then
            local handler = item.handlers[kind]
            if handler then Dispatch(handler, item.owner, ...) end
        end
    end
end

local function MaxWindows()
    local constants = Constants and Constants.ChatFrameConstants
    return constants and constants.MaxChatWindows or 10
end

-- ChatFrame1EditBox .. ChatFrame10EditBox of a permanent window.
function ChatState.IsPermanentBox(box)
    local known = permanent[box]
    if known ~= nil then return known end
    local name = box and box.GetName and box:GetName()
    local index = type(name) == "string" and tonumber(name:match("^ChatFrame(%d+)EditBox$")) or nil
    local parent = index and _G["ChatFrame" .. index]
    local result = index ~= nil and index <= MaxWindows() and parent ~= nil and parent.isTemporary ~= true
    permanent[box] = result
    return result
end

function ChatState.IsHovered(frame)
    return hovered[frame] == true
end

function ChatState.IsMoving()
    return not not _G.MOVING_CHATFRAME
end

local function Arm(seconds)
    if not (follower and next(owners)) then return end
    armedUntil = math.max(armedUntil, GetTime() + (seconds or ARM_SECONDS))
    geometryDue = true
    follower:Show()
end

-- A repair can finish after the follower's final read. Observe its result so
-- subscribed previews receive the settled geometry as well.
function ChatState.RequestGeometry() Arm() end

local function Flush()
    windowsDue = false
    if next(owners) then Notify("windows") end
end

local function QueueWindows()
    if windowsDue then return end
    windowsDue = true
    C_Timer.After(0, Flush)
end

-- A cheap signature of the open windows: count, shown, docked and in use.
local observedWindows = setmetatable({}, { __mode = "v" })
local observedCount = 0
local function WindowSignature()
    local frames, signature = _G.CHAT_FRAMES, 0
    local count = type(frames) == "table" and math.min(#frames, MAX_FRAMES) or 0
    local topologyChanged = count ~= observedCount
    for index = 1, count do
        local frame = _G[frames[index]]
        if frame ~= observedWindows[index] then
            observedWindows[index], topologyChanged = frame, true
        end
        if frame then
            local state = (frame:IsShown() and 1 or 0) + (frame.isDocked and 2 or 0) + (frame.inUse and 4 or 0)
            signature = (signature * 8 + state) % 2147483629
        end
    end
    for index = count + 1, observedCount do observedWindows[index] = nil end
    observedCount = count
    return signature * 64 + math.min(count, 63), topologyChanged
end

local function CheckWindows()
    checkDue, sinceCheck = false, 0
    local signature, topologyChanged = WindowSignature()
    if signature ~= lastWindows or topologyChanged then
        if lastWindows ~= nil then QueueWindows() end
        lastWindows = signature
    end
end

-- Sizes are read while the follower runs: every frame while a button is held
-- (a resize grip, Edit Mode), else with the open-window check and when the
-- follower stops. A change since the last read reports once.
local function CheckSizes(observed)
    local frames = observed and observedWindows or _G.CHAT_FRAMES
    if type(frames) ~= "table" then return end
    local count = observed and observedCount or math.min(#frames, MAX_FRAMES)
    for index = 1, count do
        local frame = frames[index]
        if not observed then frame = _G[frame] end
        if frame then
            local width, height, record = frame:GetWidth(), frame:GetHeight(), sizes[frame]
            if not record then
                sizes[frame] = { width = width, height = height }
            elseif width ~= record.width or height ~= record.height then
                record.width, record.height = width, height
                Notify("resized", frame)
            end
        end
    end
end

local function RegionChanged(region)
    if not region or Suite.Safety.IsForbidden(region) then return false end
    local count = region:GetNumPoints()
    if not Suite.Finite(count) or count < 1 then return false end
    local point, relative, edge, x, y = region:GetPoint(1)
    local width, height, scale = region:GetWidth(), region:GetHeight(), region:GetEffectiveScale()
    if not (Suite.Public(point) and Suite.Public(relative) and Suite.Public(edge)
        and Suite.Finite(x) and Suite.Finite(y) and Suite.Finite(width)
        and Suite.Finite(height) and Suite.Finite(scale)) then return false end
    local record = geometry[region]
    if not record then
        record = {}
        geometry[region] = record
    end
    if record.count == count and record.point == point and record.relative == relative and record.edge == edge
        and record.x == x and record.y == y and record.width == width and record.height == height and record.scale == scale then
        return false
    end
    record.count, record.point, record.relative, record.edge = count, point, relative, edge
    record.x, record.y, record.width, record.height, record.scale = x, y, width, height, scale
    return true
end

local function CheckGeometry(silent)
    if not geometryWanted then return end
    local frames = _G.CHAT_FRAMES
    if type(frames) ~= "table" then return end
    for index = 1, math.min(#frames, MAX_FRAMES) do
        local frame = _G[frames[index]]
        if frame and not Suite.Safety.IsForbidden(frame) then
            local changed = RegionChanged(frame)
            local box = frame.editBox
            if box and ChatState.IsPermanentBox(box) then changed = RegionChanged(box) or changed end
            if changed and not silent then Notify("geometry", frame) end
        end
    end
end

-- Store our applied state before another native reset can repeat the same
-- coordinates. Inform previews without rearming or triggering a repair loop.
function ChatState.GeometryRepaired()
    CheckGeometry(true)
    Notify("settled")
end

local function FollowDock(dock)
    local selected, chat = dock and dock.selected or false, _G.SELECTED_CHAT_FRAME or false
    if selected ~= lastSelected or chat ~= lastChat then
        lastSelected, lastChat, layoutDue = selected, chat, true
        Notify("selection")
    end
    local docked = dock and dock.DOCKED_CHAT_FRAMES
    local count, frames = docked and #docked or 0, _G.CHAT_FRAMES and #_G.CHAT_FRAMES or 0
    if count ~= lastDocked or frames ~= lastFrames then
        lastDocked, lastFrames, layoutDue, checkDue = count, frames, true, true
    end
    if dock and dock.leftTab ~= nil then
        layoutDue = true
    elseif layoutDue then
        layoutDue = false
        Notify("layout")
    end
end

local function Follow(self, elapsed)
    local dock = _G.GENERAL_CHAT_DOCK
    FollowDock(dock)
    local moving = _G.MOVING_CHATFRAME
    if moving ~= lastMoving then
        if lastMoving and not moving then Notify("moved", lastMoving) end
        lastMoving = moving
    end
    sinceCheck = sinceCheck + (elapsed or 0)
    local stopping = not (layoutDue or moving or editMode) and GetTime() > armedUntil
    if checkDue or sinceCheck >= WINDOW_CHECK then
        CheckWindows()
        CheckSizes(true)
    elseif stopping or IsMouseButtonDown("LeftButton") then
        CheckSizes()
    end
    sinceGeometry = sinceGeometry + (elapsed or 0)
    if geometryDue or stopping or sinceGeometry >= GEOMETRY_CHECK then
        geometryDue, sinceGeometry = false, 0
        CheckGeometry()
    end
    if stopping then self:Hide() end
end

-- Ten reads a second of Blizzard's own hover flags, only while asked for.
local function ProbeHover()
    local frames = _G.CHAT_FRAMES
    if type(frames) ~= "table" then return end
    for index = 1, math.min(#frames, MAX_FRAMES) do
        local frame = _G[frames[index]]
        local on = frame and frame.hasBeenFaded == true
        if frame and on ~= (hovered[frame] == true) then
            hovered[frame] = on or nil
            Notify("hover", frame, on)
        end
    end
end

local function SyncProbe()
    CompileSubscribers()
    local wanted = #subscribers.hover > 0
    geometryWanted = #subscribers.geometry > 0
    if wanted and not probe then
        probe = C_Timer.NewTicker(HOVER_PROBE, ProbeHover)
    elseif not wanted and probe then
        probe:Cancel()
        probe = nil
    end
end

local function OnEvent(_, event, unit)
    if event == "PLAYER_SPECIALIZATION_CHANGED" and (not Suite.Public(unit) or unit ~= "player") then return end
    if WINDOW_EVENTS[event] then
        checkDue = true
        QueueWindows()
    elseif event ~= "GLOBAL_MOUSE_DOWN" and event ~= "GLOBAL_MOUSE_UP" then
        checkDue = true
    end
    Arm(GEOMETRY_EVENTS[event] and GEOMETRY_SECONDS or ARM_SECONDS)
end

local function BoxEvent(event, box)
    local kind = BOX_EVENTS[event]
    if not (kind and next(owners) and ChatState.IsPermanentBox(box)) then return end
    Arm()
    Notify("box", kind, box)
end

local function KeyDown(box, key)
    if next(owners) then Notify("key", box, key) end
end

-- One OnKeyDown hook per permanent box, installed once; it cannot be removed.
local function HookKeys()
    for index = 1, MaxWindows() do
        local box = _G["ChatFrame" .. index .. "EditBox"]
        if box and not keyed[box] and ChatState.IsPermanentBox(box) and box.HookScript then
            box:HookScript("OnKeyDown", KeyDown)
            keyed[box] = true
        end
    end
end

local function EditModeEntered()
    editMode = true
    Arm()
end

local function EditModeExited()
    editMode = nil
    checkDue = true
    QueueWindows()
    Arm()
end

local function Create()
    follower = CreateFrame("Frame")
    follower:Hide()
    follower:SetScript("OnUpdate", Follow)
    events = CreateFrame("Frame")
    for event in pairs(WINDOW_EVENTS) do events:RegisterEvent(event) end
    for event in pairs(ARM_EVENTS) do events:RegisterEvent(event) end
    for event in pairs(GEOMETRY_EVENTS) do
        if Suite.Client.SupportsEvent(event) then events:RegisterEvent(event) end
    end
    events:SetScript("OnEvent", OnEvent)
    local registry = _G.EventRegistry
    if registry and registry.RegisterCallback then
        for event in pairs(BOX_EVENTS) do
            registry:RegisterCallback(event, function(_, box) BoxEvent(event, box) end, ChatState)
        end
        registry:RegisterCallback("EditMode.Enter", EditModeEntered, ChatState)
        registry:RegisterCallback("EditMode.Exit", EditModeExited, ChatState)
    end
    HookKeys()
end

-- handlers: a table of the callbacks above; owner is passed first to each.
-- Watching again with another table replaces the owner's handlers.
function ChatState.Watch(owner, handlers)
    owners[owner] = handlers
    if not follower then Create() end
    SyncProbe()
    Arm()
end

function ChatState.Unwatch(owner)
    owners[owner] = nil
    SyncProbe()
    if follower and not next(owners) then follower:Hide() end
end

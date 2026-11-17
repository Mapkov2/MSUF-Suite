-- Real ChatState -> Controller -> shared live/preview geometry. No direct
-- call to the repair function substitutes for native event delivery.
local root, flavor, host = assert(arg[1]), arg[2] or "Mainline", assert(arg[3])
local mode = arg[4]
local saved = arg
arg = { root, flavor, host, "native" }
local preview = dofile(root .. "/tools/tests/suite_chat_preview_contract.lua")
arg = { root, flavor, host, "geometry" }
local F = dofile(root .. "/tools/tests/suite_chat_contract.lua")
arg = saved
local C, NS, S, M = F.Chat, F.NS, F.Suite, F.module
local c, frame = M.config, ChatFrame1
local checks = 0
local function Check(ok, message) checks = checks + 1 assert(ok, message) end
function UIParent:GetLeft() return 0 end
function UIParent:GetBottom() return 0 end
function frame:GetLeft() return select(4, self:GetPoint(1)) or 0 end
function frame:GetBottom() return select(5, self:GetPoint(1)) or 0 end
function frame:GetTop() return self:GetBottom() + self:GetHeight() end
function frame:GetRight() return self:GetLeft() + self:GetWidth() end
function frame:IsResizable() return self.resizable ~= false end
function frame:SetResizable(value) self.resizable = value end
c.lockWindowPosition, c.windowX, c.windowY = true, 32, 95
c.lockWindowSize, c.windowWidth, c.windowHeight = true, 496, 148
c.inputWidth, c.inputHeight, c.inputX, c.inputY, c.inputTop = 0, 0, -1, 223, false
c.headerToolbar, c.toolbarLocked = false, true
frame:SetSize(420, 180)
frame.editBox:SetHeight(32)
M:Enable()
F.flush()
Check(frame:GetWidth() == 496 and frame.editBox:GetWidth() == 504,
    "input followed the pre-lock width and needs a second refresh/reload: "
        .. frame:GetWidth() .. "/" .. frame.editBox:GetWidth() .. "; " .. tostring(F.reports[1]))

local function PreviewParity()
    local parts = preview.ui.parts
    parts.sample:SetSize(c.windowWidth, c.windowHeight)
    parts.nativeInputHeight = 32
    preview.Suite.Suite.ChatPaintMenuPreview(parts, c)
    Check(parts.input:GetWidth() == frame.editBox:GetWidth(), "runtime/preview input widths differ")
    Check(parts.input:GetHeight() == frame.editBox:GetHeight(), "runtime/preview input heights differ")
    local p, _, edge, x, y = frame.editBox:GetPoint(1)
    local pp, _, pe, px, py = parts.input:GetPoint(1)
    Check(p == pp and edge == pe and x == px and y == py, "runtime/preview input origins differ")
end
PreviewParity()

local now, timers, created = 0, {}, {}
GetTime = function() return now end
IsMouseButtonDown = function() return false end
C_Timer = {
    After = function(_, callback) timers[#timers + 1] = callback end,
    NewTicker = function() return { Cancel = function() end } end,
}
local rawCreate = CreateFrame
CreateFrame = function(...)
    local object = rawCreate(...)
    object.nativeEvents = {}
    function object:RegisterEvent(event) self.nativeEvents[event] = true end
    function object:GetScript(script) return self.scripts and self.scripts[script] end
    created[#created + 1] = object
    return object
end
local registry = { callbacks = {} }
function registry:RegisterCallback(event, callback, owner)
    self.callbacks[event] = function(...) return callback(owner, ...) end
end
EventRegistry = registry
for i = 1, 10 do
    local native = _G["ChatFrame" .. i]
    if native and native.editBox then
        native.editBox.HookScript = function(_, script) Check(script == "OnKeyDown", "native geometry hook was added") end
    end
end
Check(type(preview.Suite.Public) == "function" and type(preview.Suite.Finite) == "function"
    and type(preview.Suite.Client.SupportsEvent) == "function", "productive Core geometry exports are absent")
NS.Public, NS.Finite, NS.Client = preview.Suite.Public, preview.Suite.Finite, preview.Suite.Client
local handlers = F.state.owners[M]
assert(loadfile(root .. "/MSUF_Suite/Core/ChatState.lua"))("MSUF_Suite", NS)
NS.ChatState.Watch(M, handlers)
local follower, events = created[1], created[2]
local function Step()
    now = now + .016
    local pending = timers
    timers = {}
    for _, callback in ipairs(pending) do callback() end
    if follower:IsShown() then follower:GetScript("OnUpdate")(follower, .016) end
end
local function Settle() for _ = 1, 150 do Step() end end
local function Fire(event, ...)
    Check(events.nativeEvents[event], event .. " was not registered")
    events:GetScript("OnEvent")(events, event, ...)
end
local function AtSaved()
    local p, relative, edge, x, y = frame:GetPoint(1)
    return frame:GetNumPoints() == 1 and p == "BOTTOMLEFT" and relative == UIParent and edge == "BOTTOMLEFT"
        and x == c.windowX and y == c.windowY
end
local function NativeReset()
    frame:ClearAllPoints()
    frame:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 300, -200)
    frame:SetSize(640, 220)
end
Settle()
if mode ~= "toolbar" then
for _, event in ipairs({ "PLAYER_LEVEL_UP", "PLAYER_LEVEL_CHANGED", "PLAYER_ENTERING_WORLD",
    "LOADING_SCREEN_DISABLED", "EDIT_MODE_LAYOUTS_UPDATED", "PLAYER_SPECIALIZATION_CHANGED" }) do
    Fire(event, "player")
    for _ = 1, 20 do Step() end
    NativeReset() -- later than the event's first deferred drain
    Settle()
    Check(AtSaved(), event .. " left the locked window displaced")
    Check(frame:GetWidth() == 496 and frame:GetHeight() == 148, event .. " lost the size lock")
    PreviewParity()
    Check(not follower:IsShown(), event .. " left permanent polling")
end

-- A size-only reset must recover even when the input uses an explicit width.
c.inputWidth = 380
M.messageWindows = { Request = function() end }
M:Refresh()
Settle()
Fire("EDIT_MODE_LAYOUTS_UPDATED")
frame:SetSize(640, 220)
Settle()
Check(AtSaved() and frame:GetWidth() == 496 and frame:GetHeight() == 148,
    "size-only reset with fixed input width escaped the size lock")
PreviewParity()
c.inputWidth = 0
M:Refresh()
Settle()

-- Native dragging owns its transient anchors until the mouse is released.
local secondary = F.Frame("PendingSecondaryChat")
secondary.editBox = F.Frame("PendingSecondaryInput")
local secondaryVisual = { frame = secondary }
M.visuals[secondary] = secondaryVisual
C.ApplyInputLayout(M, secondaryVisual, secondary, secondary.editBox)
secondary.editBox:SetWidth(secondary.editBox:GetWidth() + 50)
handlers.geometry(M, secondary)
Fire("PLAYER_LEVEL_UP")
MOVING_CHATFRAME = frame
NativeReset()
Fire("UPDATE_CHAT_WINDOWS")
for _ = 1, 40 do Step() end
Check(not AtSaved() and frame:GetWidth() == 640 and M.nativeDragRefreshPending,
    "native refresh fought the native chat drag")
MOVING_CHATFRAME = nil
Settle()
Check(AtSaved() and frame:GetWidth() == 496, "native drag release did not recover the locks")
Check(secondary.editBox:GetWidth() == secondary:GetWidth() + 2*c.padding,
    "native drag release dropped a pending secondary input repair")
Check(not M.nativeDragRefreshPending, "native drag refresh stayed pending after release")
M.visuals[secondary] = nil
PreviewParity()

-- Opening the input can rebuild only its native anchor and width.
frame.editBox:ClearAllPoints()
frame.editBox:SetPoint("TOPLEFT", frame, "BOTTOMLEFT", -5, -2)
frame.editBox:SetWidth(333)
registry.callbacks["ChatFrame.OnEditBoxShow"](frame.editBox)
Settle()
PreviewParity()

-- Width, height and placement changes must match the preview immediately.
c.windowWidth, c.windowHeight, c.inputHeight, c.inputTop = 572, 205, 38, true
M.messageWindows = { Request = function() end }
M:Refresh()
PreviewParity()
Settle()
PreviewParity()
c.inputHeight = 0
M:Refresh()
Check(frame.editBox:GetHeight() == 32, "native input height did not return without reload")
PreviewParity()

local queued = 0
S.Queue = function(id) Check(id == "chat", "wrong combat recovery owner") queued = queued + 1 end
F.combat(true)
Fire("PLAYER_LEVEL_UP")
NativeReset()
Settle()
Check(not AtSaved() and queued > 0, "combat detection moved the window or failed to queue recovery")
F.combat(false)
M:Refresh() -- the existing Core combat queue replays the module refresh
Settle()
Check(AtSaved() and frame:GetWidth() == 572 and frame:GetHeight() == 205, "combat replay lost locked geometry")
PreviewParity()
end

-- Refresh during an existing toolbar gesture must finish with the locks.
c.headerToolbar, c.toolbarLocked = true, false
M:Refresh()
Settle()
local proxy = F.Frame("GeometryToolbarProxy")
proxy:SetSize(frame:GetWidth(), frame:GetHeight())
function proxy:UnregisterEvent() end
M.toolbarProxy, M.toolbarGesture = proxy, { context = M.context, config = c }
M.context:Anchor(frame, "BOTTOMLEFT", proxy, "BOTTOMLEFT", 0, 0)
M:Refresh()
Check(not M.toolbarGesture and AtSaved(), "toolbar cancellation undid final window placement")
PreviewParity()

-- Native discovery (for example a new whisper window) waits for a live drag.
M.toolbarGesture = { context = M.context, config = c }
M.context:Anchor(frame, "BOTTOMLEFT", proxy, "BOTTOMLEFT", 0, 0)
local gesture = M.toolbarGesture
F.context.callbacks.UPDATE_CHAT_WINDOWS(M, "UPDATE_CHAT_WINDOWS")
Check(M.toolbarGesture == gesture and M.toolbarRefreshPending, "native discovery interrupted an active drag")
C.StopToolbarGesture(false)
Settle()
Check(not M.toolbarRefreshPending and AtSaved(), "deferred native refresh was not applied after the gesture")
PreviewParity()

-- Committing a native-interrupted drag must store the intended geometry and
-- consume the deferred refresh rather than restoring the old position.
S.CommitEditPosition = function(id, values)
    Check(id == "chat", "wrong toolbar commit owner")
    for key, value in pairs(values) do c[key] = value end
    M:Refresh()
    return true
end
M.toolbarGesture = { context = M.context, config = c }
M.context:Anchor(frame, "BOTTOMLEFT", proxy, "BOTTOMLEFT", 0, 0)
F.context.callbacks.UPDATE_CHAT_WINDOWS(M, "UPDATE_CHAT_WINDOWS")
C.StopToolbarGesture(true)
Settle()
Check(not M.toolbarRefreshPending and not M.toolbarRefreshContext and AtSaved(), "committed drag lost its deferred refresh")
PreviewParity()
Check(#F.reports == 0, "a geometry callback raised an isolated error")
print("Chat geometry event recovery and immediate input preview parity: " .. checks .. " checks (" .. flavor .. ")")

local _, P = ...
local NS, S = P.NS, P.Suite
local C = P.Chat
-- Lifecycle, the chat window walk and Suite.ChatState's reports. Chat window
-- reports restyle every window; a tab selection only recolors the old and new
-- tab labels and moves the sidebar. Nothing here runs inside Blizzard's chat
-- code: no FCF_* post-hook, no script hook on a chat frame or edit box.
local M = C.M
local MAX_FRAMES = 64
local HOST_CHAT = "external:msuf.blizzard:chat"
local FRIEND_EVENTS = {
    "FRIENDLIST_UPDATE", "BN_FRIEND_LIST_SIZE_CHANGED", "BN_FRIEND_ACCOUNT_ONLINE",
    "BN_FRIEND_ACCOUNT_OFFLINE", "BN_CONNECTED", "BN_DISCONNECTED",
}
-- The addons that own the chat windows themselves: the module's conflicts in
-- Core/Catalog/Chat.lua. One that loads late takes the module out of service.
local CHAT_ADDONS = {
    DaylightUI_Chat = true, EllesmereUIChat = true, ElvUI = true, Glass = true, Glassy = true,
    ["Prat-3.0"] = true, Chattynator = true, Chatter = true,
}
local ApplyWindow, ReleaseWindow, ColorTab, TabSelected = C.ApplyWindow, C.ReleaseWindow, C.ColorTab, C.TabSelected
local PlaceSidebar, ReleaseNativeControls, UpdateFriendsCount = C.PlaceSidebar, C.ReleaseNativeControls, C.UpdateFriendsCount
local HideCopyDialog, DockSelection = C.HideCopyDialog, C.DockSelection
local Dispatch = S.Dispatch

-- Built-in chat frames plus Blizzard's list of temporary windows, each once.
-- A window that fails to style (another addon may have replaced its parts)
-- is reported and the remaining windows are still styled.
local visited = {}
local function Visit(frame, count, callback, arg)
    if not frame or visited[frame] or count >= MAX_FRAMES then return count end
    visited[frame] = true
    Dispatch(callback, arg, frame)
    return count + 1
end

-- NUM_CHAT_WINDOWS is only a deprecation alias of this constant.
local function ForEachChatFrame(callback, arg)
    for frame in pairs(visited) do visited[frame] = nil end
    local count = 0
    local builtIn = math.min(Constants.ChatFrameConstants.MaxChatWindows, MAX_FRAMES)
    for i = 1, builtIn do count = Visit(_G["ChatFrame" .. i], count, callback, arg) end
    for _, name in pairs(_G.CHAT_FRAMES) do
        if count >= MAX_FRAMES then break end
        count = Visit(_G[name], count, callback, arg)
    end
end

-- Window events can fire inside Blizzard's pop-out/whisper setup, before the
-- native copy loop finishes. Reconcile message hooks after that stack unwinds.
local function RefreshMessageWindows(self)
    if C.LayoutLocked() then
        S.Queue("chat")
        return
    end
    ForEachChatFrame(C.ApplyMessages, self)
end

local function ApplyNativeWindow(self, frame) ApplyWindow(self, frame, true) end

local function ApplyAll(self, nativeRefresh)
    if C.LayoutLocked() then
        S.Queue("chat")
        return
    end
    if nativeRefresh and NS.ChatState.IsMoving() then
        self.nativeDragRefreshPending = true
        return
    end
    -- Native window discovery must not interrupt a player's drag. Settings
    -- refreshes cancel before applying the final geometry, never afterward.
    if self.toolbarGesture then
        if nativeRefresh then
            self.toolbarRefreshPending = true
            return
        end
        C.StopToolbarGesture(false, true)
    end
    self.toolbarRefreshPending, self.toolbarRefreshContext, self.nativeDragRefreshPending = nil, nil, nil
    if nativeRefresh then C.NoteNativeWindowPosition() end
    C.ApplyClockSettings()
    ForEachChatFrame(nativeRefresh and S.editMode and ApplyNativeWindow or ApplyWindow, self)
    if self.config.headerToolbar or self.toolbar then C.ApplyToolbar() end
    C.DockGeometry()
    C.UpdateWindowMoverBounds(self)
    if C.UpdateFloatingMoverBounds(self) and not nativeRefresh then S.RefreshOwnedMovers("chat") end
    self.selectedChat = _G.SELECTED_CHAT_FRAME
    self.selectedDock = DockSelection()
    C.RefreshClocks()
    self.messageWindows:Request()
    NS.ChatState.RequestGeometry()
end

local function NativeWindowsUpdated(self)
    ApplyAll(self, true)
    if S.editMode and not NS.InCombat() then S.RefreshOwnedMovers("chat") end
end

local function RecolorTab(self, frame, chat, dock)
    local visual = frame and self.visuals[frame]
    if visual and visual.tabLabel then ColorTab(self, visual, TabSelected(frame, chat, dock)) end
end

local function RefreshSelection(self)
    -- Dock selection changes do not change panel geometry or colors. Touch
    -- only the old and new tab labels instead of restyling every chat window.
    local chat, dock = _G.SELECTED_CHAT_FRAME, DockSelection()
    if chat == self.selectedChat and dock == self.selectedDock then return end
    local oldChat, oldDock = self.selectedChat, self.selectedDock
    self.selectedChat, self.selectedDock = chat, dock
    if dock then
        C.ChatActivity(dock)
        if self.visuals[dock] then C.UpdateMinimalChrome(self.visuals[dock]) end
    end
    RecolorTab(self, oldChat, chat, dock)
    if oldDock ~= oldChat then RecolorTab(self, oldDock, chat, dock) end
    if chat ~= oldChat and chat ~= oldDock then RecolorTab(self, chat, chat, dock) end
    if dock ~= chat and dock ~= oldChat and dock ~= oldDock then RecolorTab(self, dock, chat, dock) end
    if self.config.headerToolbar then
        C.UpdateToolbarHover()
        if self.visuals[oldDock] then C.ApplyInactivity(self, self.visuals[oldDock]) end
        if self.visuals[dock] then C.ApplyInactivity(self, self.visuals[dock]) end
    end
    local primary = self.visuals[_G.ChatFrame1]
    if self.config.sidebarPanel and self.config.panelAlpha > 0
        and primary and primary.sidebarFrame and dock then
        PlaceSidebar(self, primary.sidebarFrame, dock)
        -- The sidebar fades with the window it sits on (Fade.lua); the
        -- selection counts as activity for both windows.
        if self.visuals[oldDock] then C.ApplyInactivity(self, self.visuals[oldDock]) end
        if self.visuals[dock] then C.ApplyInactivity(self, self.visuals[dock]) end
    end
end

-- Other chat addons change the module's availability; Blizzard's quick join,
-- chat and combat log addons add parts the windows restyle around.
local function AddonLoaded(_, _, name)
    if CHAT_ADDONS[name] then S.Apply("chat") end
    if name == "Blizzard_QuickJoin" or name == "Blizzard_ChatFrame" or name == "Blizzard_CombatLog" then
        ApplyAll(M, true)
    end
end

-- A temporary whisper window opens inside the whisper event's handling; the
-- report that follows arrives on the next frame (Suite.ChatState), so its
-- message hook catches up on the lines Blizzard already gave it.
local function ApplyOpenWhisper(self, frame)
    if S.Public(frame.isTemporary) and frame.isTemporary then C.ApplyMessages(self, frame, true) end
end

-- Every styled tab after a Blizzard layout pass, which recolored them
-- (FCFTab_UpdateColors). Their alpha needs nothing: the held tab regions
-- ignore the tab frame's alpha that FCFTab_UpdateAlpha and the fades write.
local function RestyleTabs(self)
    local chat, dock = SELECTED_CHAT_FRAME, DockSelection()
    for frame, visual in pairs(self.visuals) do
        if visual.tabLabel then ColorTab(self, visual, TabSelected(frame, chat, dock)) end
        C.ResizeInput(frame)
    end
end

local function WindowsReported(self)
    C.ScanFloatingClosures()
    if not self.active then return end
    ApplyAll(self, true)
    if not C.LayoutLocked() then ForEachChatFrame(ApplyOpenWhisper, self) end
    C.CheckWindowPosition()
end

local function SelectionReported(self)
    if self.active then RefreshSelection(self) end
end

local function LayoutReported(self)
    if not self.active then return end
    C.DockGeometry()
    RestyleTabs(self)
    C.CheckWindowPosition()
end

local function MovedReported(self, frame)
    C.FloatingDragStopped(frame)
    if self.active then
        if self.nativeDragRefreshPending then ApplyAll(self, true) end
        C.CheckWindowGeometry()
    end
end

local function ResizedReported(self, frame)
    if self.active then
        C.ResizeInput(frame)
        C.CheckWindowGeometry(frame)
    end
end

local function GeometryReported(self, frame)
    if self.active then C.CheckWindowGeometry(frame) end
end

local function HoverReported(self, frame, hovered)
    if not self.active then return end
    if hovered then C.HoverStarted(frame) else C.HoverEnded(frame) end
end

local function BoxReported(self, kind, box)
    if not self.active then return end
    C.FadeInput(kind, box)
    C.InputAnimationEvent(kind, box)
    C.HistoryBox(kind, box)
end

local function KeyReported(self, box, key)
    if self.active then C.HistoryKey(box, key) end
end

local CHAT_WATCH = {
    windows = WindowsReported, selection = SelectionReported, layout = LayoutReported, moved = MovedReported,
    resized = ResizedReported, geometry = GeometryReported, box = BoxReported, key = KeyReported,
}
-- Hover is asked for only while a feature reacts to it (C.HoverWanted): the
-- core then reads Blizzard's hover flags on a ticker; otherwise idle chat
-- runs no Suite code at all.
local HOVER_WATCH = setmetatable({ hover = HoverReported }, { __index = CHAT_WATCH })
local function Watch(self)
    NS.ChatState.Watch(self, C.HoverWanted() and HOVER_WATCH or CHAT_WATCH)
end

function M:Enable()
    self.geometry = true
    self.messageWindows = self.context:Coalesce(0, RefreshMessageWindows)
    self.context:Event("UPDATE_CHAT_WINDOWS", NativeWindowsUpdated)
    self.context:Event("UPDATE_FLOATING_CHAT_WINDOWS", NativeWindowsUpdated)
    for _, event in ipairs(FRIEND_EVENTS) do C.ListenInCombat(self.context, event, UpdateFriendsCount) end
    self.context:Event("ADDON_LOADED", AddonLoaded)
    C.ScanFloatingClosures()
    self:Refresh()
end

function M:Refresh()
    C.MessagesRefresh(self)
    C.SpamFilterRefresh(self)
    C.BubblesRefresh(self)
    ApplyAll(self)
    Watch(self)
end

function M:Disable()
    NS.ChatState.Unwatch(self)
    self.toolbarRefreshPending, self.toolbarRefreshContext, self.nativeDragRefreshPending = nil, nil, nil
    S.SuppressHostElement("chat", HOST_CHAT, false)
    self.hostChatClaim = nil
    if self.moverFrame then self.moverFrame:Hide() end
    C.HideFloatingMovers(self)
    if self.whisperArrows then self.whisperArrows:Hide() end
    if self.toolbar or self.toolbarDockOwned then C.ReleaseToolbar() end
    C.StopInputAnimations()
    C.DisableClock()
    self.messageWindows:Cancel()
    C.MessagesDisable()
    C.SpamFilterDisable()
    -- Faded alpha goes back before the context restores the tabs it owns.
    C.FadeDisable()
    C.BubblesDisable()
    C.HistoryDisable()
    for _, visual in pairs(self.visuals) do ReleaseWindow(self, visual) end
    ReleaseNativeControls(self)
    HideCopyDialog(self.copyDialog)
end

local function ReadWindowDimension(getter)
    local frame = ChatFrame1
    if not frame or NS.Safety.IsForbidden(frame) then return end
    local value = frame[getter](frame)
    if S.Finite(value) and value > 0 then return math.floor(value) end
end

local function WindowSizeControl(key, label, getter, otherKey, otherGetter)
    local rule = S.catalog.chat.rules[key]
    return {
        id = key, label = label, kind = "number", min = rule.min, max = rule.max, step = rule.step,
        get = function() return ReadWindowDimension(getter) end,
        set = function(value)
            local current = ReadWindowDimension(getter)
            local other = ReadWindowDimension(otherGetter)
            if not (current and other) then return false end
            value = math.floor(value)
            if value == current then return true end
            -- Adopt the current size on the untouched axis when taking ownership.
            return S.SetMany("chat", { [key] = value, [otherKey] = other, lockWindowSize = true })
        end,
    }
end

local windowSizeControls

-- The active Suite chat always has one MSUF mover. Until its first move,
-- Blizzard keeps the position; a drag adopts the Suite anchor and Undo keeps
-- the previous ownership flag alongside the original native layout.
function M:RegisterMovers()
    if not windowSizeControls then
        windowSizeControls = {
            WindowSizeControl("windowWidth", S.Text("Width"), "GetWidth", "windowHeight", "GetHeight"),
            WindowSizeControl("windowHeight", S.Text("Height"), "GetHeight", "windowWidth", "GetWidth"),
        }
    end
    local registered = S.RegisterOwnedMover("chat", "window", {
        label = "Chat window", order = 870,
        getFrame = C.GetWindowMoverFrame, screenPosition = true, precisePosition = true,
        xKey = "windowX", yKey = "windowY", point = "BOTTOMLEFT", capture = C.CaptureWindowPosition,
        -- Numeric edits retain the other visible axis after a native layout change.
        moveValues = { lockWindowPosition = true },
        extraControls = windowSizeControls,
        historyKeys = { "lockWindowPosition", "lockWindowSize", "windowWidth", "windowHeight" },
        resetKeys = { "lockWindowPosition" }, place = C.PlaceWindowPosition,
    })
    for index = 2, C.MaxFloatingWindows() do
        local id = C.FloatingMoverID(index)
        if not S.HasOwnedMover("chat", id) then S.RegisterOwnedMover("chat", id, C.FloatingMoverSpec(index)) end
    end
    local claimed = registered == true
    S.SuppressHostElement("chat", HOST_CHAT, claimed)
    if (self.hostChatClaim == true) ~= claimed then
        self.hostChatClaim = claimed
        S.RefreshOwnedMovers("chat")
    end
end

S.Install("chat", M)

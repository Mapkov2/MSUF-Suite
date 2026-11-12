local _, P = ...
local NS, S = P.NS, P.Suite
local C = P.Chat
-- Lifecycle, the chat window walk and the cold Blizzard hooks. Chat window
-- events restyle every window; a tab selection only recolors the old and new
-- tab labels and moves the sidebar.
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
local KeepTabVisible = C.KeepTabVisible
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

local function ApplyNativeWindow(self, frame) ApplyWindow(self, frame, true) end

local function ApplyAll(self, nativeRefresh)
    if C.LayoutLocked() then
        S.Queue("chat")
        return
    end
    C.ApplyClockSettings()
    ForEachChatFrame(nativeRefresh and S.editMode and ApplyNativeWindow or ApplyWindow, self)
    if self.config.headerToolbar or self.toolbar then C.ApplyToolbar() end
    C.DockGeometry()
    C.UpdateWindowMoverBounds(self)
    if C.UpdateFloatingMoverBounds(self) and not nativeRefresh then S.RefreshOwnedMovers("chat") end
    self.selectedChat = _G.SELECTED_CHAT_FRAME
    self.selectedDock = DockSelection()
    C.RefreshClocks()
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

-- Temporary whisper frames are created after the usual chat-window update
-- events. Hook only these cold window paths, never the message path.
local function TemporaryWindowOpened()
    if M.active then ApplyAll(M, true) end
end

local function DockSelectionChanged()
    if M.active then RefreshSelection(M) end
end

local function TabAlphaUpdated(frame)
    if M.active and frame then KeepTabVisible(M, frame) end
end

local function TabFadedIn(frame) C.HoldTabAlpha(frame, true) end
local function TabFadedOut(frame) C.HoldTabAlpha(frame, false) end

local function TabColorsUpdated(tab, selected)
    local visual = M.active and tab and M.tabs[tab]
    if visual then ColorTab(M, visual, selected) end
end

local function NewWindowOpened()
    if not M.active then return end
    if NS.InCombat() then
        S.Queue("chat")
        return
    end
    local frame = DockSelection()
    if frame then ApplyWindow(M, frame, S.editMode) end
    RefreshSelection(M)
    C.RefreshClocks()
end

-- The FCF_* targets exist at login on both clients (Blizzard_ChatFrameBase);
-- a post-hook cannot be removed, so each one is installed once.
local function Hook(self, flag, name, hook)
    if self[flag] then return end
    hooksecurefunc(name, hook)
    self[flag] = true
end

function M:Enable()
    self.geometry = true
    self.context:Event("UPDATE_CHAT_WINDOWS", NativeWindowsUpdated)
    self.context:Event("UPDATE_FLOATING_CHAT_WINDOWS", NativeWindowsUpdated)
    for _, event in ipairs(FRIEND_EVENTS) do C.ListenInCombat(self.context, event, UpdateFriendsCount) end
    self.context:Event("ADDON_LOADED", AddonLoaded)
    Hook(self, "hookedTemporary", "FCF_OpenTemporaryWindow", TemporaryWindowOpened)
    Hook(self, "hookedSelect", "FCFDock_SelectWindow", DockSelectionChanged)
    Hook(self, "hookedNewWindow", "FCF_OpenNewWindow", NewWindowOpened)
    C.WatchFloatingClosures()
    Hook(self, "hookedFloatingDrag", "FCF_StopDragging", C.FloatingDragStopped)
    Hook(self, "hookedTabAlpha", "FCFTab_UpdateAlpha", TabAlphaUpdated)
    Hook(self, "hookedTabFadeIn", "FCF_FadeInChatFrame", TabFadedIn)
    Hook(self, "hookedTabFadeOut", "FCF_FadeOutChatFrame", TabFadedOut)
    Hook(self, "hookedTabColors", "FCFTab_UpdateColors", TabColorsUpdated)
    Hook(self, "hookedDockGeometry", "FCFDock_UpdateTabs", C.DockGeometry)
    self:Refresh()
end

function M:Refresh()
    C.MessagesRefresh(self)
    C.SpamFilterRefresh(self)
    C.BubblesRefresh(self)
    ApplyAll(self)
end

function M:Disable()
    S.SuppressHostElement("chat", HOST_CHAT, false)
    self.hostChatClaim = nil
    if self.moverFrame then self.moverFrame:Hide() end
    C.HideFloatingMovers(self)
    if self.whisperArrows then self.whisperArrows:Hide() end
    if self.toolbar or self.toolbarDockOwned then C.ReleaseToolbar() end
    C.StopInputAnimations()
    C.DisableClock()
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

local _, P = ...
local NS, S = P.NS, P.Suite
local C = P.Chat
-- Lifecycle, the chat window walk and the cold Blizzard hooks. Chat window
-- events restyle every window; a tab selection only recolors the old and new
-- tab labels and moves the sidebar.
local M = C.M
local MAX_FRAMES = 64
local FRIEND_EVENTS = {
    "FRIENDLIST_UPDATE", "BN_FRIEND_LIST_SIZE_CHANGED", "BN_FRIEND_ACCOUNT_ONLINE",
    "BN_FRIEND_ACCOUNT_OFFLINE", "BN_CONNECTED", "BN_DISCONNECTED",
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

local function ApplyAll(self)
    if NS.IsCombatLocked() then
        S.Queue("chat")
        return
    end
    ForEachChatFrame(ApplyWindow, self)
    C.DockGeometry()
    self.selectedChat = _G.SELECTED_CHAT_FRAME
    self.selectedDock = DockSelection()
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
    RecolorTab(self, oldChat, chat, dock)
    if oldDock ~= oldChat then RecolorTab(self, oldDock, chat, dock) end
    if chat ~= oldChat and chat ~= oldDock then RecolorTab(self, chat, chat, dock) end
    if dock ~= chat and dock ~= oldChat and dock ~= oldDock then RecolorTab(self, dock, chat, dock) end
    local primary = self.visuals[_G.ChatFrame1]
    if self.config.sidebarPanel and self.config.panelAlpha > 0
        and primary and primary.sidebarFrame and dock then
        PlaceSidebar(self, primary.sidebarFrame, dock)
    end
end

-- Other chat addons change the module's availability; Blizzard's quick join,
-- chat and combat log addons add parts the windows restyle around.
local function AddonLoaded(_, _, name)
    if name == "EllesmereUIChat" or name == "ElvUI" then S.Apply("chat") end
    if name == "Blizzard_QuickJoin" or name == "Blizzard_ChatFrame" or name == "Blizzard_CombatLog" then
        ApplyAll(M)
    end
end

-- Temporary whisper frames are created after the usual chat-window update
-- events. Hook only these cold window paths, never the message path.
local function TemporaryWindowOpened()
    if M.active then ApplyAll(M) end
end

local function DockSelectionChanged()
    if M.active then RefreshSelection(M) end
end

local function TabAlphaUpdated(frame)
    if M.active and frame then KeepTabVisible(M, frame) end
end

local function TabColorsUpdated(tab, selected)
    local visual = M.active and tab and M.tabs[tab]
    if visual then ColorTab(M, visual, selected) end
end

local function NewWindowOpened()
    if not M.active then return end
    if NS.IsCombatLocked() then
        S.Queue("chat")
        return
    end
    local frame = DockSelection()
    if frame then ApplyWindow(M, frame) end
    RefreshSelection(M)
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
    self.context:Event("UPDATE_CHAT_WINDOWS", ApplyAll)
    self.context:Event("UPDATE_FLOATING_CHAT_WINDOWS", ApplyAll)
    for _, event in ipairs(FRIEND_EVENTS) do C.ListenInCombat(self.context, event, UpdateFriendsCount) end
    self.context:Event("ADDON_LOADED", AddonLoaded)
    Hook(self, "hookedTemporary", "FCF_OpenTemporaryWindow", TemporaryWindowOpened)
    Hook(self, "hookedSelect", "FCFDock_SelectWindow", DockSelectionChanged)
    Hook(self, "hookedNewWindow", "FCF_OpenNewWindow", NewWindowOpened)
    Hook(self, "hookedTabAlpha", "FCFTab_UpdateAlpha", TabAlphaUpdated)
    Hook(self, "hookedTabColors", "FCFTab_UpdateColors", TabColorsUpdated)
    Hook(self, "hookedDockGeometry", "FCFDock_UpdateTabs", C.DockGeometry)
    C.MessagesRefresh(self)
    C.BubblesRefresh(self)
    ApplyAll(self)
end

function M:Refresh()
    C.MessagesRefresh(self)
    C.BubblesRefresh(self)
    ApplyAll(self)
end

function M:Disable()
    C.MessagesDisable()
    -- Faded alpha goes back before the context restores the tabs it owns.
    C.FadeDisable()
    C.BubblesDisable(self)
    for _, visual in pairs(self.visuals) do ReleaseWindow(self, visual) end
    ReleaseNativeControls(self)
    HideCopyDialog(self.copyDialog)
end

S.Install("chat", M)

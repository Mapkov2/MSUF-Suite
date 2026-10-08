local _, P = ...
local NS, S = P.NS, P.Suite

-- Manually cover chat windows that receive guild or officer messages and,
-- when chosen, the guild chat of the Guild & Communities window. A mixed
-- window is covered in full; the native messages and channel settings remain
-- intact underneath. No chat text is read or retained.
local M = { covered = false, overlays = setmetatable({}, { __mode = "k" }) }
local COMMAND = "MSUFSUITEGUILDPRIVACY"
local MAX_CHAT_FRAMES = 64
-- revealClick choice -> the key a left-click on a cover needs (false: none).
local REVEAL_KEYS = { false, IsControlKeyDown, IsShiftKeyDown, IsAltKeyDown }
local WINDOW_HINTS = {
    "Whole window hidden. Click to reveal.",
    "Whole window hidden. Ctrl + left-click to reveal.",
    "Whole window hidden. Shift + left-click to reveal.",
    "Whole window hidden. Alt + left-click to reveal.",
}
local CLUB_HINTS = {
    "Click to reveal.",
    "Ctrl + left-click to reveal.",
    "Shift + left-click to reveal.",
    "Alt + left-click to reveal.",
}

local function Affected(frame)
    return frame and not NS.Safety.IsForbidden(frame)
        and (frame:ContainsMessageGroup("GUILD") or frame:ContainsMessageGroup("OFFICER"))
end

local function Reveal(_, button)
    if not M.active or button ~= "LeftButton" then return end
    local key = REVEAL_KEYS[M.config.revealClick]
    local held = not key or key()
    if S.Public(held) and held == true then
        M.covered = false
        M:Sync()
    end
end

local function CreateCover(parent, window)
    local overlay = S.CreateFrame("Button", nil, parent)
    local background = S.CreateTexture(overlay, nil, "BACKGROUND")
    background:SetAllPoints()
    background:SetColorTexture(.04, .05, .06, .99)
    local accent = S.CreateTexture(overlay, nil, "ARTWORK")
    accent:SetPoint("TOPLEFT")
    accent:SetPoint("BOTTOMLEFT")
    accent:SetWidth(2)
    accent:SetColorTexture(.8, .68, .42, 1)
    local title = S.QoLLabel(overlay, "Guild chat covered", 13)
    title:SetPoint("CENTER", 0, 10)
    overlay.hint = S.QoLLabel(overlay, "", 11)
    overlay.hint:SetPoint("TOP", title, "BOTTOM", 0, -5)
    overlay.window = window
    overlay:SetScript("OnClick", Reveal)
    overlay:Hide()
    return overlay
end

local function CreateOverlay(frame)
    local overlay = CreateCover(frame, true)
    overlay:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
    overlay:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
    overlay:SetFrameStrata("HIGH")
    overlay:SetFrameLevel(frame:GetFrameLevel() + 6)
    return overlay
end

-- The hint names the click the reveal choice asks for.
local function ShowCover(overlay, shown)
    if shown then
        local choice = M.config.revealClick
        local text = overlay.window and WINDOW_HINTS[choice] or CLUB_HINTS[choice]
        overlay.hint:SetText(S.Text(text))
    end
    overlay:SetShown(shown)
end

------------------------------------------------------------ communities
-- Blizzard_Communities loads on demand. CommunitiesFrame.Chat is the chat
-- pane of the chat and minimized display modes and shows the selected club
-- (CommunitiesFrame.xml/.lua). The cover is a child of that pane, so it
-- leaves with it, and shows only while the guild is the selected club;
-- other communities stay visible. It keeps the window's strata, so other
-- windows still draw above it.
local function GuildClubShown(self)
    local frame = self.watching
    local guild = frame and frame:IsGuildSelected()
    return S.Public(guild) and guild == true
end

local function ClubCover(self)
    local chat = self.watching.Chat
    if not chat or NS.Safety.IsForbidden(chat) then return nil end
    local cover = CreateCover(chat, false)
    cover:SetPoint("TOPLEFT", chat, "TOPLEFT", -6, 6)
    cover:SetPoint("BOTTOMRIGHT", chat, "BOTTOMRIGHT", 6, -4)
    cover:SetFrameLevel(chat:GetFrameLevel() + 10)
    self.clubCover = cover
    return cover
end

local function SyncClub(self)
    local shown = self.covered and self.config.communities == true and GuildClubShown(self)
    local cover = self.clubCover
    if shown and not cover then
        if NS.IsCombatLocked() then return S.Queue("guildChatPrivacy") end
        cover = ClubCover(self)
    end
    if cover then ShowCover(cover, shown == true) end
end

-- CommunitiesFrameMixin's own callback for every club change; the registry
-- calls it through securecallfunction with this module as the owner.
local function ClubSelected(self)
    if self.active then SyncClub(self) end
end

local function WatchClubs(self, frame)
    if self.watching or NS.Safety.IsForbidden(frame) then return end
    self.context:RemoveEvent("ADDON_LOADED")
    frame:RegisterCallback(CommunitiesFrameMixin.Event.ClubSelected, ClubSelected, self)
    self.watching = frame
    -- Built hidden ahead of time, so covering in combat needs no new frame.
    if not self.clubCover and not NS.IsCombatLocked() then ClubCover(self) end
end

local function Unwatch(self)
    self.context:RemoveEvent("ADDON_LOADED")
    if self.watching then
        self.watching:UnregisterCallback(CommunitiesFrameMixin.Event.ClubSelected, self)
        self.watching = nil
    end
end

local Watch
local function CommunitiesLoaded(self, _, addon)
    if addon == "Blizzard_Communities" then
        Watch(self)
        SyncClub(self)
    end
end

function Watch(self)
    if self.config.communities ~= true then return Unwatch(self) end
    local frame = CommunitiesFrame
    if frame then
        WatchClubs(self, frame)
    else
        self.context:Event("ADDON_LOADED", CommunitiesLoaded)
    end
end

------------------------------------------------------------ chat windows
local function CreateControl(frame)
    local button = S.CreateFrame("Button", nil, frame)
    button:SetSize(127, 19)
    button:SetPoint("BOTTOMRIGHT", frame, "TOPRIGHT", 0, 27)
    button:SetFrameStrata("HIGH")
    button:SetFrameLevel(frame:GetFrameLevel() + 8)
    local background = S.CreateTexture(button, nil, "BACKGROUND")
    background:SetAllPoints()
    background:SetColorTexture(.1, .12, .14, .95)
    local label = S.QoLLabel(button, "Guild privacy: OFF", 11)
    label:SetPoint("CENTER")
    button.label = label
    button:SetScript("OnClick", function()
        if M.active then
            M.covered = not M.covered
            M:Sync()
        end
    end)
    return button
end

function M:Sync()
    if NS.IsCombatLocked() then
        if self.control then
            self.control.label:SetText(S.Text(self.covered and "Guild privacy: ON" or "Guild privacy: OFF"))
        end
        for _, overlay in pairs(self.overlays) do ShowCover(overlay, self.covered) end
        SyncClub(self)
        S.Queue("guildChatPrivacy")
        return
    end
    self.control = self.control or CreateControl(ChatFrame1)
    self.control.label:SetText(S.Text(self.covered and "Guild privacy: ON" or "Guild privacy: OFF"))
    self.control:Show()
    local seen = self.seen or {}
    self.seen = seen
    for frame in pairs(seen) do seen[frame] = nil end
    local count = 0
    for _, name in pairs(CHAT_FRAMES) do
        if count >= MAX_CHAT_FRAMES then break end
        count = count + 1
        local frame = type(name) == "string" and _G[name]
        if Affected(frame) then
            seen[frame] = true
            local overlay = self.overlays[frame]
            if not overlay then
                overlay = CreateOverlay(frame)
                self.overlays[frame] = overlay
            end
            if overlay then ShowCover(overlay, self.covered) end
        end
    end
    for frame, overlay in pairs(self.overlays) do
        if not seen[frame] then overlay:Hide() end
    end
    SyncClub(self)
end

local function Toggle()
    if not M.active then return end
    M.covered = not M.covered
    M:Sync()
end

local function ChatChanged(module) module:Sync() end
local function NewWindow()
    if M.active then M:Sync() end
end

function M:Enable()
    S.RegisterSlash(COMMAND, Toggle, "/msufguildprivacy")
    self.context:Event("UPDATE_CHAT_WINDOWS", ChatChanged)
    self.context:Event("UPDATE_FLOATING_CHAT_WINDOWS", ChatChanged)
    -- Blizzard calls both window openers by name (FloatingChatFrame.lua,
    -- ChatFrameUtil.lua, UnitPopupSharedButtonMixins.lua).
    if not self.hooked then
        hooksecurefunc("FCF_OpenNewWindow", NewWindow)
        hooksecurefunc("FCF_OpenTemporaryWindow", NewWindow)
        self.hooked = true
    end
    Watch(self)
    self:Sync()
end

function M:Refresh()
    Watch(self)
    self:Sync()
end

function M:Disable()
    S.UnregisterSlash(COMMAND, Toggle)
    Unwatch(self)
    self.covered = false
    for _, overlay in pairs(self.overlays) do overlay:Hide() end
    if self.clubCover then self.clubCover:Hide() end
    if self.control then self.control:Hide() end
end

S.Install("guildChatPrivacy", M)

local _, P = ...
local NS, S = P.NS, P.Suite

-- Manually cover chat windows that receive guild or officer messages. A mixed
-- window is covered in full; the native messages and channel settings remain
-- intact underneath. No chat text is read or retained.
local M = { covered = false, overlays = setmetatable({}, { __mode = "k" }) }
local COMMAND = "MSUFSUITEGUILDPRIVACY"
local MAX_CHAT_FRAMES = 64

local function Label(parent, text, size)
    local label = S.CreateFontString(parent, nil, "ARTWORK")
    S.SetFont(label, nil, size, "")
    label:SetText(S.Text(text))
    return label
end

local function Affected(frame)
    return frame and not NS.Safety.IsForbidden(frame)
        and (frame:ContainsMessageGroup("GUILD") or frame:ContainsMessageGroup("OFFICER"))
end

local function CreateOverlay(frame)
    local overlay = S.CreateFrame("Button", nil, frame)
    overlay:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
    overlay:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
    overlay:SetFrameStrata("HIGH")
    overlay:SetFrameLevel(frame:GetFrameLevel() + 6)
    local background = S.CreateTexture(overlay, nil, "BACKGROUND")
    background:SetAllPoints()
    background:SetColorTexture(.04, .05, .06, .99)
    local accent = S.CreateTexture(overlay, nil, "ARTWORK")
    accent:SetPoint("TOPLEFT")
    accent:SetPoint("BOTTOMLEFT")
    accent:SetWidth(2)
    accent:SetColorTexture(.8, .68, .42, 1)
    local title = Label(overlay, "Guild chat covered", 13)
    title:SetPoint("CENTER", 0, 10)
    local hint = Label(overlay, "Whole window hidden. Click to reveal.", 11)
    hint:SetPoint("TOP", title, "BOTTOM", 0, -5)
    overlay:SetScript("OnClick", function()
        if M.active then
            M.covered = false
            M:Sync()
        end
    end)
    overlay:Hide()
    return overlay
end

local function CreateControl(frame)
    local button = S.CreateFrame("Button", nil, frame)
    button:SetSize(127, 19)
    button:SetPoint("BOTTOMRIGHT", frame, "TOPRIGHT", 0, 27)
    button:SetFrameStrata("HIGH")
    button:SetFrameLevel(frame:GetFrameLevel() + 8)
    local background = S.CreateTexture(button, nil, "BACKGROUND")
    background:SetAllPoints()
    background:SetColorTexture(.1, .12, .14, .95)
    local label = Label(button, "Guild privacy: OFF", 11)
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
        for _, overlay in pairs(self.overlays) do overlay:SetShown(self.covered) end
        S.Queue("guildChatPrivacy")
        return
    end
    if not _G.ChatFrame1 or type(_G.CHAT_FRAMES) ~= "table" then return end
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
            if self.covered and not overlay then
                overlay = CreateOverlay(frame)
                self.overlays[frame] = overlay
            end
            if overlay then overlay:SetShown(self.covered) end
        end
    end
    for frame, overlay in pairs(self.overlays) do
        if not seen[frame] then overlay:Hide() end
    end
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
    _G["SLASH_" .. COMMAND .. "1"] = "/msufguildprivacy"
    SlashCmdList[COMMAND] = Toggle
    self.context:Event("UPDATE_CHAT_WINDOWS", ChatChanged)
    self.context:Event("UPDATE_FLOATING_CHAT_WINDOWS", ChatChanged)
    if not self.hooked then
        if type(_G.FCF_OpenNewWindow) == "function"
            and type(_G.FCF_OpenTemporaryWindow) == "function" then
            hooksecurefunc("FCF_OpenNewWindow", NewWindow)
            hooksecurefunc("FCF_OpenTemporaryWindow", NewWindow)
            self.hooked = true
        end
    end
    self:Sync()
end

function M:Refresh() self:Sync() end

function M:Disable()
    _G["SLASH_" .. COMMAND .. "1"] = nil
    SlashCmdList[COMMAND] = nil
    self.covered = false
    for _, overlay in pairs(self.overlays) do overlay:Hide() end
    if self.control then self.control:Hide() end
end

S.Install("guildChatPrivacy", M)

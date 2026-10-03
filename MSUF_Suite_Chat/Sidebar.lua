local _, P = ...
local S = P.Suite
local C = P.Chat
-- The sidebar left of the primary chat window: suite glyph buttons that click
-- Blizzard's own chat buttons, which stay in place at alpha 0 without mouse.
local M = C.M
local GLYPHS = "Interface\\AddOns\\MSUF_Suite_Chat\\Media\\MSUFChatGlyphs.png"
local SIDEBAR_BUTTONS = {
    { native = "QuickJoinToastButton", title = S.Text("Friends"), glyph = 0 },
    { native = "ChatFrameChannelButton", title = S.Text("Channels and voice"), glyph = 1 },
    { native = "TextToSpeechButton", title = S.Text("Text to speech"), glyph = 2 },
    { native = "ChatFrameMenuButton", title = S.Text("Chat menu"), glyph = 3, menu = true },
    { title = S.Text("Newest messages"), glyph = 4, scroll = true },
}
local NATIVE_BUTTONS = {
    "QuickJoinToastButton", "ChatFrameChannelButton", "TextToSpeechButton",
    "ChatFrameMenuButton", "ChatFrameToggleVoiceDeafenButton", "ChatFrameToggleVoiceMuteButton",
}
local Fill, Tint, ShowTooltip, HideTooltip = C.Fill, C.Tint, C.ShowTooltip, C.HideTooltip
local OwnBorderedParts = C.OwnBorderedParts
local HeaderTop, DockSelection = C.HeaderTop, C.DockSelection
local RGB = S.RGB

local function SidebarClassColor(c)
    if not c.sidebarClassColor then return end
    local _, token = UnitClass("player")
    return C.ClassHex(token)
end

local function RefreshSidebarButton(self, entry)
    local c = self.config
    local hovered = entry.button.hovered
    local color = self.sidebarClassColor or (hovered and c.accentColor or c.tabActiveColor)
    local r, g, b = RGB(color)
    entry.glyph:SetVertexColor(r, g, b, hovered and 1 or 0.94)
    Tint(entry.highlight, self.sidebarClassColor or c.accentColor, hovered and 20 or 0)
end

-- Friend events also fire in combat; the count label is plain suite text.
local function UpdateFriendsCount(self)
    local visual = self.visuals[_G.ChatFrame1]
    local label = visual and visual.friendCount
    if not label then return end
    local _, bn = BNGetNumFriends()
    local wow = C_FriendList.GetNumOnlineFriends()
    if not S.Number(bn) or not S.Number(wow) then return end
    local total = bn + wow
    local value = total > 99 and "99+" or tostring(total)
    if label.lastValue ~= value then
        label:SetText(value)
        label.lastValue = value
    end
end
C.UpdateFriendsCount = UpdateFriendsCount

-- Blizzard's buttons stay shown (their own logic keeps running); only their
-- alpha, mouse and the button frame's chrome are owned while the sidebar shows.
local function SyncNativeControls(self, hidden)
    local context = self.context
    for i = 1, #NATIVE_BUTTONS do context:HideControl(_G[NATIVE_BUTTONS[i]], hidden) end
    OwnBorderedParts(context, _G.ChatFrame1.buttonFrame, hidden)
end

local function OwnNativeControls(self)
    SyncNativeControls(self, true)
end

-- Hands the native buttons and the button frame's chrome back.
local function ReleaseNativeControls(self)
    SyncNativeControls(self, false)
end
C.ReleaseNativeControls = ReleaseNativeControls

-- Sidebar buttons share these scripts; button.entry holds their definition.
local function SidebarEnter(button)
    button.hovered = true
    RefreshSidebarButton(M, button.entry)
    ShowTooltip(button, button.entry.definition.title)
end

local function SidebarLeave(button)
    button.hovered = nil
    RefreshSidebarButton(M, button.entry)
    HideTooltip(button)
end

-- Load-on-demand parts (Blizzard_QuickJoin) may not have built theirs yet.
local function Native(definition)
    return definition.native and _G[definition.native]
end

local function SidebarClick(button, mouseButton)
    local definition = button.entry.definition
    if definition.scroll then
        local selected = _G.SELECTED_DOCK_FRAME or _G.SELECTED_CHAT_FRAME or _G.ChatFrame1
        selected:ScrollToBottom()
        return
    end
    if definition.menu then return end
    local native = Native(definition)
    if native then native:Click(mouseButton or "LeftButton") end
end

-- Blizzard's chat menu button is a DropdownButton: its menu opens and closes
-- on the press (DropdownButtonMixin:OnMouseDown_Intrinsic), and its OnClick
-- (ChatFrameMenuButtonMixin) only hides a help tip, so Click() never opens
-- it. The sidebar icon presses it the way Blizzard's DropdownButtonProxyMixin
-- does (Blizzard_Menu/DropdownButton.lua, live and forever): a left press
-- without Shift (Shift drags the icon) toggles the menu, and the icon keeps
-- Blizzard's menu manager from closing the open menu on that press. Blizzard
-- closes the menu once its owner hides (another docked tab hides ChatFrame1
-- and the button with it), so the menu only opens while the button shows.
local function SidebarMenuPress(button, mouseButton)
    if mouseButton ~= "LeftButton" or IsShiftKeyDown() then return end
    local native = Native(button.entry.definition)
    if not native then return end
    local open = not native:IsMenuOpen()
    if open and not native:IsVisible() then return end
    native:SetMenuOpen(open)
end

local function MenuHandlesGlobalMouse(_, mouseButton, event)
    return event == "GLOBAL_MOUSE_DOWN" and mouseButton == "LeftButton"
end

-- Shift-drag moves one icon; its offset from the sidebar center is saved.
local function SidebarDragStart(button)
    if not M.active or not IsShiftKeyDown() or P.NS.IsCombatLocked() then return end
    button.dragging = true
    button:StartMoving()
end

local function SidebarDragStop(button)
    if not button.dragging then return end
    button:StopMovingOrSizing()
    button.dragging = nil
    local x, y = button:GetCenter()
    local sidebarX, sidebarY = button:GetParent():GetCenter()
    if S.Finite(x) and S.Finite(y) and S.Finite(sidebarX) and S.Finite(sidebarY) then
        local prefix = "sidebarButton" .. button.sidebarIndex
        S.SetMany("chat", {
            [prefix .. "X"] = x - sidebarX, [prefix .. "Y"] = y - sidebarY, [prefix .. "Moved"] = true,
        })
    end
end

local function CreateSidebarButton(sidebar, definition)
    local button = S.CreateFrame("Button", nil, sidebar)
    button:SetSize(24, 24)
    button:RegisterForClicks("AnyUp")
    local highlight = Fill(button, "BACKGROUND")
    highlight:SetAllPoints(button)
    local glyph = S.CreateTexture(button, nil, "ARTWORK")
    glyph:SetTexture(GLYPHS)
    glyph:SetTexCoord(definition.glyph / 8, (definition.glyph + 1) / 8, 0, 1)
    glyph:SetPoint("CENTER", button, "CENTER", 0, definition.glyph == 0 and 2 or 0)
    glyph:SetSize(definition.glyph == 0 and 24 or 25, definition.glyph == 0 and 24 or 25)
    local entry = { button = button, glyph = glyph, highlight = highlight, definition = definition }
    button.entry = entry
    button:SetScript("OnEnter", SidebarEnter)
    button:SetScript("OnLeave", SidebarLeave)
    button:SetScript("OnClick", SidebarClick)
    if definition.menu then
        button:SetScript("OnMouseDown", SidebarMenuPress)
        button.HandlesGlobalMouseEvent = MenuHandlesGlobalMouse
    end
    button:SetMovable(true)
    button:RegisterForDrag("LeftButton")
    button:SetScript("OnDragStart", SidebarDragStart)
    button:SetScript("OnDragStop", SidebarDragStop)
    return entry
end

local function CreateSidebar(self, visual)
    local sidebar = S.CreateFrame("Frame", nil, UIParent)
    sidebar:EnableMouse(false)
    visual.sidebarFrame = sidebar
    visual.buttons = {}
    for i, definition in ipairs(SIDEBAR_BUTTONS) do
        local entry = CreateSidebarButton(sidebar, definition)
        visual.buttons[i] = entry
        entry.button.sidebarIndex = i
        if i == 1 then
            local count = S.CreateFontString(entry.button, nil, "OVERLAY", "GameFontHighlightSmall")
            count:SetPoint("BOTTOM", entry.button, "BOTTOM", 0, -2)
            count:SetText("0")
            local r, g, b = RGB(self.config.tabActiveColor)
            count:SetTextColor(r, g, b, 1)
            visual.friendCount = count
        end
    end
    return sidebar
end

-- Follows the selected docked window (RefreshSelection calls this on tab changes).
function C.PlaceSidebar(self, sidebar, frame)
    local c = self.config
    local top = math.max(24, HeaderTop(c, frame))
    sidebar:ClearAllPoints()
    if c.sidebarSide == 2 then
        sidebar:SetPoint("TOPLEFT", frame, "TOPRIGHT", c.padding, top)
        sidebar:SetPoint("BOTTOMLEFT", frame, "BOTTOMRIGHT", c.padding, -c.padding)
    else
        sidebar:SetPoint("TOPRIGHT", frame, "TOPLEFT", -c.padding, top)
        sidebar:SetPoint("BOTTOMRIGHT", frame, "BOTTOMLEFT", -c.padding, -c.padding)
    end
    sidebar:SetWidth(c.sidebarWidth)
end
local PlaceSidebar = C.PlaceSidebar

local function LayoutButtons(self, sidebar, visual)
    local c = self.config
    for i, entry in ipairs(visual.buttons) do
        local button, prefix = entry.button, "sidebarButton" .. i
        button:ClearAllPoints()
        if c[prefix .. "Moved"] then
            button:SetPoint("CENTER", sidebar, "CENTER", c[prefix .. "X"] or 0, c[prefix .. "Y"] or 0)
        elseif entry.definition.scroll and c.scrollButtonPlace == 2 then
            button:SetPoint("BOTTOMRIGHT", DockSelection() or _G.ChatFrame1, "BOTTOMRIGHT", -4, 4)
        elseif entry.definition.scroll then
            button:SetPoint("BOTTOM", sidebar, "BOTTOM", 0, 4)
        else
            button:SetPoint("TOP", sidebar, "TOP", 0, -5 - (i - 1) * (24 + (c.sidebarGap or 2)))
        end
        button:SetShown(entry.definition.scroll or Native(entry.definition) ~= nil)
        RefreshSidebarButton(self, entry)
    end
end

function C.ApplySidebar(self, visual, frame)
    local c = self.config
    if not (c.sidebarPanel and c.panelAlpha > 0) then
        if visual.sidebar then visual.sidebar:Hide() end
        if visual.sidebarFrame then visual.sidebarFrame:Hide() end
        ReleaseNativeControls(self)
        return
    end
    self.sidebarClassColor = SidebarClassColor(c)
    local sidebar = visual.sidebarFrame or CreateSidebar(self, visual)
    if visual.friendCount then
        local r, g, b = RGB(self.sidebarClassColor or c.tabActiveColor)
        visual.friendCount:SetTextColor(r, g, b, 1)
    end
    if not visual.sidebar then
        -- The primary Blizzard chat frame is hidden while another docked tab
        -- is selected. Keep the background with the UIParent sidebar buttons.
        visual.sidebar = Fill(sidebar, "BACKGROUND")
        visual.sidebar:SetAllPoints(sidebar)
    end
    Tint(visual.sidebar, c.sidebarColor or c.panelColor, c.sidebarAlpha or math.min(100, c.panelAlpha + 8))
    visual.sidebar:Show()
    PlaceSidebar(self, sidebar, DockSelection() or frame)
    sidebar:SetFrameStrata("MEDIUM")
    sidebar:SetFrameLevel(frame:GetFrameLevel() + 3)
    LayoutButtons(self, sidebar, visual)
    sidebar:Show()
    OwnNativeControls(self)
    UpdateFriendsCount(self)
end

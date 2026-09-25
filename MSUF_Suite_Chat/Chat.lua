local _, private = ...
local NS, S = private.NS, private.Suite
local WHITE = "Interface\\Buttons\\WHITE8X8"
local GLYPHS = "Interface\\AddOns\\MSUF_Suite_Chat\\Media\\MSUFChatGlyphs.png"
local MAX_FRAMES = 64
local SIDEBAR_BUTTONS = {
    { native = "QuickJoinToastButton", title = S.Text("Friends"), glyph = 0 },
    { native = "ChatFrameChannelButton", title = S.Text("Channels and voice"), glyph = 1 },
    { native = "TextToSpeechButton", title = S.Text("Text to speech"), glyph = 2 },
    { native = "ChatFrameMenuButton", title = S.Text("Chat menu"), glyph = 3 },
    { title = S.Text("Newest messages"), glyph = 4, scroll = true },
}
local NATIVE_BUTTONS = {
    "QuickJoinToastButton", "ChatFrameChannelButton", "TextToSpeechButton",
    "ChatFrameMenuButton", "ChatFrameToggleVoiceDeafenButton", "ChatFrameToggleVoiceMuteButton",
}
-- Blizzard's chat frame chrome; ChatFrame1's button frame uses the same parts.
local CHAT_CHROME = {
    "Background", "TopLeftTexture", "BottomLeftTexture", "TopRightTexture",
    "BottomRightTexture", "LeftTexture", "RightTexture", "TopTexture", "BottomTexture",
}
local TAB_CHROME = {
    "Left", "Middle", "Right", "ActiveLeft", "ActiveMiddle", "ActiveRight",
    "HighlightLeft", "HighlightMiddle", "HighlightRight",
}
local INPUT_CHROME = { "Left", "Mid", "Right", "FocusLeft", "FocusMid", "FocusRight" }
-- fontOutline 1 keeps Blizzard's own outline.
local OUTLINES = { false, "OUTLINE", "THICKOUTLINE", "" }
local TEXT = {
    copy = S.Text("Copy"),
    copyTooltip = S.Text("Copy a recent chat message"),
    copyTitle = S.Text("Copy chat message (drag to move)"),
    copyHint = S.Text("Choose a line, then press Ctrl+C"),
    copyEmpty = S.Text("No recent messages to copy"),
}
local RGB = S.RGB

local M = {
    visuals = setmetatable({}, { __mode = "k" }), hookedTemporary = false, hookedNewWindow = false, hookedSelect = false,
}

local function Fill(owner, layer)
    local texture = owner:CreateTexture(nil, layer)
    texture:SetTexture(WHITE)
    return texture
end

local function Tint(texture, hex, alpha)
    local r, g, b = RGB(hex)
    if type(texture.SetColorTexture) == "function" then
        texture:SetColorTexture(r, g, b, alpha / 100)
    else
        texture:SetVertexColor(r, g, b, alpha / 100)
    end
end

local function Anchor(texture, owner, left, bottom, right, top)
    texture:ClearAllPoints()
    texture:SetPoint("TOPLEFT", owner, "TOPLEFT", left, top)
    texture:SetPoint("BOTTOMRIGHT", owner, "BOTTOMRIGHT", right, bottom)
end

local function ShowTooltip(owner, text)
    if not _G.GameTooltip then return end
    _G.GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
    _G.GameTooltip:SetText(text)
    _G.GameTooltip:Show()
end

local function HideTooltip()
    if _G.GameTooltip then _G.GameTooltip:Hide() end
end

local function CombatLogBar(frame)
    if frame ~= _G.ChatFrame2 then return nil end
    return frame.CombatLogQuickButtonFrame or _G.CombatLogQuickButtonFrame_Custom
end

local function HeaderTop(config, frame)
    if not config.tabPanel then return config.padding end
    local top = 24
    local quickBar = CombatLogBar(frame)
    if quickBar and type(quickBar.GetHeight) == "function" then
        local height = quickBar:GetHeight()
        if type(height) == "number" and height > 0 then top = top + height + 3 end
    end
    return top
end

local function CreateVisual(frame)
    local visual = { frame = frame }
    visual.panel = Fill(frame, "BACKGROUND")
    visual.header = Fill(frame, "BORDER")
    visual.headerRule = Fill(frame, "ARTWORK")
    visual.edges = {}
    for i = 1, 4 do visual.edges[i] = Fill(frame, "BORDER") end
    M.visuals[frame] = visual
    return visual
end

local function ApplyEdge(edge, owner, side, size, pad, top, hex, alpha)
    if size <= 0 or alpha <= 0 then
        edge:Hide()
        return
    end
    edge:ClearAllPoints()
    if side == 1 then
        edge:SetPoint("TOPLEFT", owner, "TOPLEFT", -pad, top)
        edge:SetPoint("TOPRIGHT", owner, "TOPRIGHT", pad, top)
        edge:SetHeight(size)
    elseif side == 2 then
        edge:SetPoint("BOTTOMLEFT", owner, "BOTTOMLEFT", -pad, -pad)
        edge:SetPoint("BOTTOMRIGHT", owner, "BOTTOMRIGHT", pad, -pad)
        edge:SetHeight(size)
    elseif side == 3 then
        edge:SetPoint("TOPLEFT", owner, "TOPLEFT", -pad, top)
        edge:SetPoint("BOTTOMLEFT", owner, "BOTTOMLEFT", -pad, -pad)
        edge:SetWidth(size)
    else
        edge:SetPoint("TOPRIGHT", owner, "TOPRIGHT", pad, top)
        edge:SetPoint("BOTTOMRIGHT", owner, "BOTTOMRIGHT", pad, -pad)
        edge:SetWidth(size)
    end
    Tint(edge, hex, alpha)
    edge:Show()
end

local function RefreshSidebarButton(self, entry)
    local c = self.config
    local hovered = entry.button.hovered
    local r, g, b = RGB(hovered and c.accentColor or c.tabActiveColor)
    entry.glyph:SetVertexColor(r, g, b, hovered and 1 or 0.94)
    Tint(entry.highlight, c.accentColor, hovered and 20 or 0)
end

local function UpdateFriendsCount(self)
    local visual = self.visuals[_G.ChatFrame1]
    local label = visual and visual.friendCount
    if not label then return end
    local bn = type(_G.BNGetNumFriends) == "function" and select(2, _G.BNGetNumFriends()) or 0
    local wow = _G.C_FriendList and type(_G.C_FriendList.GetNumOnlineFriends) == "function"
        and _G.C_FriendList.GetNumOnlineFriends() or 0
    if not S.Public(bn) or not S.Public(wow) or type(bn) ~= "number" or type(wow) ~= "number" then return end
    local total = bn + wow
    local value = total > 99 and "99+" or tostring(total)
    if label.lastValue ~= value then
        label:SetText(value)
        label.lastValue = value
    end
end

local function SyncNativeControls(self, hidden)
    if not self.context or type(self.context.HideControl) ~= "function" then return end
    for i = 1, #NATIVE_BUTTONS do
        local button = _G[NATIVE_BUTTONS[i]]
        if button then self.context:HideControl(button, hidden) end
    end
    for i = 1, #CHAT_CHROME do
        local texture = _G["ChatFrame1ButtonFrame" .. CHAT_CHROME[i]]
        if texture then
            if hidden then
                self.context:Property(texture, "IsShown", "SetShown", false)
            else
                self.context:RestoreProperty(texture, "SetShown")
            end
        end
    end
end

-- Owns (alpha 0) or restores each named region of a native frame.
local function OwnAlpha(context, owner, parts, globalPrefix, own)
    for i = 1, #parts do
        local suffix = parts[i]
        local texture = owner[suffix] or _G[globalPrefix .. suffix]
        if texture then
            if own then
                context:Alpha(texture, 0)
            else
                context:RestoreProperty(texture, "SetAlpha")
            end
        end
    end
end

local function TabLabel(tab)
    return tab.Text or (type(tab.GetFontString) == "function" and tab:GetFontString())
end

local function SetNativeChrome(self, frame, tab, input, enabled)
    local context = self.context
    local name = frame.GetName and frame:GetName()
    if type(name) ~= "string" then return end
    for i = 1, #CHAT_CHROME do
        local suffix = CHAT_CHROME[i]
        local texture = frame[suffix] or _G[name .. suffix]
        if texture then
            if enabled then
                context:Property(texture, "IsShown", "SetShown", false)
            else
                context:RestoreProperty(texture, "SetShown")
            end
        end
    end
    if tab then
        local ownTabs = enabled and self.config.tabPanel
        OwnAlpha(context, tab, TAB_CHROME, name .. "Tab", ownTabs)
        local label = TabLabel(tab)
        if label then
            if ownTabs then
                context:Alpha(label, 0)
            else
                context:RestoreProperty(label, "SetAlpha")
            end
        end
    end
    if input then OwnAlpha(context, input, INPUT_CHROME, name .. "EditBox", enabled and self.config.inputPanel) end
    local quickBar = CombatLogBar(frame)
    local quickTexture = quickBar and (quickBar.Texture or _G.CombatLogQuickButtonFrame_CustomTexture)
    if quickTexture then
        if enabled and self.config.tabPanel then
            context:Alpha(quickTexture, 0)
        else
            context:RestoreProperty(quickTexture, "SetAlpha")
        end
    end
end

local function ColorTab(self, visual, selected)
    local c = self.config
    local r, g, b = RGB(selected and c.tabActiveColor or c.tabInactiveColor)
    visual.tabLabel:SetTextColor(r, g, b, selected and 1 or 0.78)
    visual.tabLine:SetShown(c.tabAccent and c.accentAlpha > 0 and selected)
end

local function DockSelection()
    local dock = _G.GENERAL_CHAT_DOCK
    return dock and dock.selected or _G.SELECTED_DOCK_FRAME
end

local function TabSelected(frame, chat, dock)
    if frame.isDocked == true then return frame == dock end
    if frame.isDocked == false then return true end
    return frame == chat or frame == dock
end

-- The overlay is a child of the tab: it hides with the tab (FCF_Close hides
-- tabs directly) and follows Blizzard's tab alpha fading.
local function CreateTabOverlay(visual, tab, nativeLabel)
    local overlay = S.CreateFrame("Frame", nil, tab)
    overlay:EnableMouse(false)
    visual.tabOverlay = overlay
    local label = overlay:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    label:SetPoint("CENTER", nativeLabel, "CENTER", 0, 0)
    label:SetJustifyH("CENTER")
    visual.tabLabel = label
    visual.tabLine = Fill(overlay, "ARTWORK")
end

local function ApplyTabOverlay(self, visual, tab, selected)
    local c = self.config
    if not (c.tabPanel and c.panelAlpha > 0) then
        if visual.tabOverlay then visual.tabOverlay:Hide() end
        return
    end
    local nativeLabel = TabLabel(tab)
    if not nativeLabel then return end
    if not visual.tabOverlay then CreateTabOverlay(visual, tab, nativeLabel) end
    local overlay = visual.tabOverlay
    overlay:SetAllPoints(tab)
    overlay:SetFrameStrata("MEDIUM")
    if type(tab.GetFrameLevel) == "function" then overlay:SetFrameLevel(tab:GetFrameLevel() + 1) end
    local label = visual.tabLabel
    local text = type(nativeLabel.GetText) == "function" and nativeLabel:GetText() or nil
    if text and S.Public(text) then label:SetText(text) end
    if type(nativeLabel.GetFont) == "function" then
        local path, size, flags = nativeLabel:GetFont()
        if type(path) == "string" and type(size) == "number" then label:SetFont(path, size, flags) end
    end
    if type(tab.GetWidth) == "function" then label:SetWidth(math.max(20, tab:GetWidth() - 4)) end
    local line = visual.tabLine
    line:ClearAllPoints()
    line:SetPoint("BOTTOMLEFT", overlay, "BOTTOMLEFT", 5, 1)
    line:SetPoint("BOTTOMRIGHT", overlay, "BOTTOMRIGHT", -5, 1)
    line:SetHeight(2)
    Tint(line, c.accentColor, c.accentAlpha)
    ColorTab(self, visual, selected)
    overlay:Show()
end

-- Sidebar buttons share these scripts; button.entry holds their definition.
local function SidebarEnter(button)
    button.hovered = true
    RefreshSidebarButton(M, button.entry)
    ShowTooltip(button, button.entry.definition.title)
end

local function SidebarLeave(button)
    button.hovered = nil
    RefreshSidebarButton(M, button.entry)
    HideTooltip()
end

local function SidebarClick(button, mouseButton)
    local definition = button.entry.definition
    if definition.scroll then
        local selected = _G.SELECTED_DOCK_FRAME or _G.SELECTED_CHAT_FRAME or _G.ChatFrame1
        if selected and type(selected.ScrollToBottom) == "function" then selected:ScrollToBottom() end
        return
    end
    local native = _G[definition.native]
    if native and type(native.Click) == "function" then native:Click(mouseButton or "LeftButton") end
end

local function CreateSidebarButton(sidebar, definition)
    local button = S.CreateFrame("Button", nil, sidebar)
    button:SetSize(24, 24)
    button:RegisterForClicks("AnyUp")
    local highlight = Fill(button, "BACKGROUND")
    highlight:SetAllPoints(button)
    local glyph = button:CreateTexture(nil, "ARTWORK")
    glyph:SetTexture(GLYPHS)
    glyph:SetTexCoord(definition.glyph / 8, (definition.glyph + 1) / 8, 0, 1)
    glyph:SetPoint("CENTER", button, "CENTER", 0, definition.glyph == 0 and 2 or 0)
    glyph:SetSize(definition.glyph == 0 and 24 or 25, definition.glyph == 0 and 24 or 25)
    local entry = { button = button, glyph = glyph, highlight = highlight, definition = definition }
    button.entry = entry
    button:SetScript("OnEnter", SidebarEnter)
    button:SetScript("OnLeave", SidebarLeave)
    button:SetScript("OnClick", SidebarClick)
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
        if i == 1 then
            local count = entry.button:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            count:SetPoint("BOTTOM", entry.button, "BOTTOM", 0, -2)
            count:SetText("0")
            local r, g, b = RGB(self.config.tabActiveColor)
            count:SetTextColor(r, g, b, 1)
            visual.friendCount = count
        end
    end
    return sidebar
end

local function PlaceSidebar(self, sidebar, frame)
    local c = self.config
    local top = math.max(24, HeaderTop(c, frame))
    sidebar:ClearAllPoints()
    sidebar:SetPoint("TOPRIGHT", frame, "TOPLEFT", -c.padding, top)
    sidebar:SetPoint("BOTTOMRIGHT", frame, "BOTTOMLEFT", -c.padding, -c.padding)
    sidebar:SetWidth(c.sidebarWidth)
end

local function ApplySidebar(self, visual, frame)
    local c = self.config
    if not (c.sidebarPanel and c.panelAlpha > 0) then
        if visual.sidebar then visual.sidebar:Hide() end
        if visual.sidebarFrame then visual.sidebarFrame:Hide() end
        SyncNativeControls(self, false)
        return
    end
    local sidebar = visual.sidebarFrame or CreateSidebar(self, visual)
    if not visual.sidebar then
        -- The primary Blizzard chat frame is hidden while another docked tab
        -- is selected. Keep the background with the UIParent sidebar buttons.
        visual.sidebar = Fill(sidebar, "BACKGROUND")
        visual.sidebar:SetAllPoints(sidebar)
    end
    Tint(visual.sidebar, c.panelColor, math.min(100, c.panelAlpha + 8))
    visual.sidebar:Show()
    PlaceSidebar(self, sidebar, DockSelection() or frame)
    if type(sidebar.SetFrameStrata) == "function" then sidebar:SetFrameStrata("MEDIUM") end
    if type(sidebar.SetFrameLevel) == "function" and type(frame.GetFrameLevel) == "function" then
        sidebar:SetFrameLevel(frame:GetFrameLevel() + 3)
    end
    for i, entry in ipairs(visual.buttons) do
        local button = entry.button
        button:ClearAllPoints()
        if entry.definition.scroll then
            button:SetPoint("BOTTOM", sidebar, "BOTTOM", 0, 4)
        else
            button:SetPoint("TOP", sidebar, "TOP", 0, -5 - (i - 1) * 26)
        end
        local native = entry.definition.native and _G[entry.definition.native]
        button:SetShown(entry.definition.scroll or native ~= nil)
        RefreshSidebarButton(self, entry)
    end
    sidebar:Show()
    SyncNativeControls(self, true)
    UpdateFriendsCount(self)
end

local function PlainMessage(text)
    -- GetMessageInfo returns Blizzard's rendered line, including a timestamp
    -- if its native setting is enabled. Present readable text in the copy box.
    local plain = text:gsub("|H.-|h(.-)|h", "%1")
        :gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
        :gsub("|T.-|t", ""):gsub("|A.-|a", "")
    return plain
end

local function HideCopyDialog(panel)
    if not panel then return end
    panel:Hide()
    if panel.edit then
        if type(panel.edit.ClearFocus) == "function" then panel.edit:ClearFocus() end
        panel.edit:SetText("")
    end
    for _, row in ipairs(panel.rows or {}) do
        row.message = nil
        row.label:SetText("")
        row:Hide()
    end
end

-- A dedicated title drag area leaves message rows and the copy edit box
-- free for clicks, selection and Ctrl+C.
local function CreateCopyHeader(panel)
    local dragHandle = S.CreateFrame("Button", nil, panel)
    dragHandle:SetPoint("TOPLEFT", panel, "TOPLEFT", 0, 0)
    dragHandle:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -34, 0)
    dragHandle:SetHeight(56)
    dragHandle:RegisterForDrag("LeftButton")
    dragHandle:SetScript("OnDragStart", function() panel:StartMoving() end)
    dragHandle:SetScript("OnDragStop", function() panel:StopMovingOrSizing() end)
    panel.dragHandle = dragHandle
    local title = dragHandle:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    title:SetPoint("TOPLEFT", dragHandle, "TOPLEFT", 15, -13)
    title:SetText(TEXT.copyTitle)
    local hint = dragHandle:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    hint:SetPoint("TOPLEFT", dragHandle, "TOPLEFT", 15, -36)
    hint:SetText(TEXT.copyHint)
    panel.hint = hint
    local close = S.CreateFrame("Button", nil, panel)
    close:SetSize(24, 22)
    close:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -8, -8)
    local closeLabel = close:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    closeLabel:SetPoint("CENTER", close, "CENTER")
    closeLabel:SetText("X")
    close:SetScript("OnClick", function() HideCopyDialog(panel) end)
end

local function CopyRowClick(row)
    if not row.message then return end
    local edit = row.panel.edit
    edit:SetText(row.message)
    edit:SetFocus()
    edit:HighlightText()
end

local function CreateCopyRows(panel)
    panel.rows = {}
    for i = 1, 10 do
        local row = S.CreateFrame("Button", nil, panel)
        row.panel = panel
        row:SetSize(410, 23)
        row:SetPoint("TOPLEFT", panel, "TOPLEFT", 15, -61 - (i - 1) * 25)
        local shade = Fill(row, "BACKGROUND")
        shade:SetAllPoints(row)
        Tint(shade, i % 2 == 0 and "252a2d" or "1d2225", 100)
        local label = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
        label:SetPoint("LEFT", row, "LEFT", 7, 0)
        label:SetWidth(394)
        label:SetJustifyH("LEFT")
        if type(label.SetMaxLines) == "function" then label:SetMaxLines(1) end
        row.label = label
        row:SetScript("OnClick", CopyRowClick)
        panel.rows[i] = row
    end
end

local function CreateCopyDialog()
    local panel = S.CreateFrame("Frame", nil, UIParent)
    panel:SetSize(440, 345)
    panel:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    panel:SetFrameStrata("DIALOG")
    panel:EnableMouse(true)
    panel:SetMovable(true)
    if type(panel.SetClampedToScreen) == "function" then panel:SetClampedToScreen(true) end
    local background = Fill(panel, "BACKGROUND")
    background:SetAllPoints(panel)
    Tint(background, "151719", 97)
    CreateCopyHeader(panel)
    local edit = S.CreateFrame("EditBox", nil, panel, "InputBoxTemplate")
    edit:SetSize(400, 25)
    edit:SetPoint("BOTTOM", panel, "BOTTOM", 0, 12)
    edit:SetAutoFocus(false)
    edit:SetScript("OnEscapePressed", function() HideCopyDialog(panel) end)
    panel.edit = edit
    CreateCopyRows(panel)
    panel:Hide()
    return panel
end

local function ShowCopyDialog(self, frame)
    if not self.config.copyMessages or not frame
        or NS.Safety.IsForbidden(frame) or type(frame.GetNumMessages) ~= "function"
        or type(frame.GetMessageInfo) ~= "function" then
        return
    end
    local count = frame:GetNumMessages()
    if not S.Public(count) or type(count) ~= "number" then return end
    local panel = self.copyDialog or CreateCopyDialog()
    self.copyDialog = panel
    local shown = 0
    for index = count, math.max(1, count - 99), -1 do
        if shown == #panel.rows then break end
        local message = frame:GetMessageInfo(index)
        if S.Public(message) and type(message) == "string" and message ~= "" then
            shown = shown + 1
            local row = panel.rows[shown]
            row.message = PlainMessage(message)
            row.label:SetText(row.message)
            row:Show()
        end
    end
    for i = shown + 1, #panel.rows do
        panel.rows[i].message = nil
        panel.rows[i]:Hide()
    end
    panel.hint:SetText(shown > 0 and TEXT.copyHint or TEXT.copyEmpty)
    panel.edit:SetText("")
    panel:Show()
end

local function CopyButtonClick(button) ShowCopyDialog(M, button.chatFrame) end
local function CopyButtonEnter(button) ShowTooltip(button, TEXT.copyTooltip) end

local function ApplyCopyButton(self, visual, frame, top)
    if not self.config.copyMessages then
        if visual.copyButton then visual.copyButton:Hide() end
        HideCopyDialog(self.copyDialog)
        return
    end
    if not visual.copyButton then
        local button = S.CreateFrame("Button", nil, frame)
        button.chatFrame = frame
        button:SetSize(46, 19)
        button:SetFrameStrata("MEDIUM")
        local fill = Fill(button, "BACKGROUND")
        fill:SetAllPoints(button)
        button.fill = fill
        local label = button:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
        label:SetPoint("CENTER", button, "CENTER")
        label:SetText(TEXT.copy)
        button:SetScript("OnClick", CopyButtonClick)
        button:SetScript("OnEnter", CopyButtonEnter)
        button:SetScript("OnLeave", HideTooltip)
        visual.copyButton = button
    end
    local button = visual.copyButton
    button:ClearAllPoints()
    button:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -4, math.max(21, top) - 3)
    if type(frame.GetFrameLevel) == "function" then button:SetFrameLevel(frame:GetFrameLevel() + 4) end
    Tint(button.fill, self.config.panelColor, 95)
    button:Show()
end

local function ApplyPanel(self, visual, frame, top)
    local c = self.config
    Anchor(visual.panel, frame, -c.padding, -c.padding, c.padding, top)
    Tint(visual.panel, c.panelColor, c.panelAlpha)
    visual.panel:SetShown(c.panelAlpha > 0)
    visual.header:ClearAllPoints()
    visual.header:SetPoint("TOPLEFT", frame, "TOPLEFT", -c.padding, top)
    visual.header:SetPoint("TOPRIGHT", frame, "TOPRIGHT", c.padding, top)
    visual.header:SetHeight(top)
    Tint(visual.header, c.panelColor, math.min(100, c.panelAlpha + 12))
    visual.header:SetShown(c.tabPanel and c.panelAlpha > 0)
    visual.headerRule:ClearAllPoints()
    visual.headerRule:SetPoint("TOPLEFT", frame, "TOPLEFT", -c.padding, 0)
    visual.headerRule:SetPoint("TOPRIGHT", frame, "TOPRIGHT", c.padding, 0)
    visual.headerRule:SetHeight(1)
    Tint(visual.headerRule, c.borderColor, math.min(55, c.borderAlpha))
    visual.headerRule:SetShown(c.tabPanel and c.panelAlpha > 0)
    for side = 1, 4 do
        ApplyEdge(visual.edges[side], frame, side, c.borderSize, c.padding, top, c.borderColor, c.borderAlpha)
    end
end

local function ApplyInput(self, visual, frame, input)
    local c = self.config
    if not (input and type(input.CreateTexture) == "function") then
        if visual.input then
            visual.input:Hide()
            if visual.inputEdges then for i = 1, 4 do visual.inputEdges[i]:Hide() end end
        end
        return
    end
    if not visual.input then visual.input = Fill(input, "BACKGROUND") end
    -- Blizzard's edit box deliberately overhangs the chat frame on both
    -- sides. Keep its native hit area and text, but align our visible bar
    -- with the chat panel. Both anchors follow frame moves and resizes.
    local inputHeight = type(input.GetHeight) == "function" and input:GetHeight() or 32
    if type(inputHeight) ~= "number" or inputHeight <= 0 then inputHeight = 32 end
    visual.input:ClearAllPoints()
    visual.input:SetPoint("TOPLEFT", frame, "BOTTOMLEFT", -c.padding, 0)
    visual.input:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", c.padding, -(inputHeight + 4))
    Tint(visual.input, c.inputColor, c.inputAlpha)
    visual.input:SetShown(c.inputPanel and c.inputAlpha > 0)
    if not visual.inputEdges then
        visual.inputEdges = {}
        for i = 1, 4 do visual.inputEdges[i] = Fill(input, "BORDER") end
    end
    for i = 1, 4 do
        local edge = visual.inputEdges[i]
        ApplyEdge(edge, visual.input, i, math.max(1, c.borderSize), 0, 0, c.borderColor, math.min(60, c.borderAlpha))
        edge:SetShown(c.inputPanel and c.inputAlpha > 0 and c.borderSize > 0)
    end
end

local function ApplyFont(self, frame)
    local c, context = self.config, self.context
    if type(frame.GetFont) == "function" and type(frame.SetFont) == "function" then
        local chosenFont = type(c.font) == "string" and c.font ~= "" and S.ResolveFont(c.font) or nil
        local custom = chosenFont or c.fontSize > 0 or (c.fontOutline or 1) ~= 1 or (c.fontRendering or 1) ~= 1
        if custom then
            local path, size, flags = frame:GetFont()
            local owned = context.tuples and context.tuples[frame]
            local original = owned and owned.SetFont and owned.SetFont.before
            if original then path, size, flags = original[1], original[2], original[3] end
            if S.Public(path) and S.Public(size) and S.Public(flags)
                and type(path) == "string" and type(size) == "number" then
                local outline = OUTLINES[c.fontOutline or 1]
                context:Tuple(frame, "GetFont", "SetFont", chosenFont or path,
                    c.fontSize > 0 and c.fontSize or size, S.FontFlags(outline or flags, c.fontRendering or 1))
            end
        else
            context:RestoreTuple(frame, "SetFont")
        end
    end
    local shadow = (c.fontRendering or 1) == 3 and 3 or (c.fontShadow or 1)
    if shadow == 1 then
        context:RestoreTuple(frame, "SetShadowColor")
        context:RestoreTuple(frame, "SetShadowOffset")
    elseif shadow == 2 then
        context:Tuple(frame, "GetShadowColor", "SetShadowColor", 0, 0, 0, (c.fontShadowOpacity or 100) / 100)
        local distance = c.fontShadowDistance or 1
        context:Tuple(frame, "GetShadowOffset", "SetShadowOffset", distance, -distance)
    else
        context:Tuple(frame, "GetShadowColor", "SetShadowColor", 0, 0, 0, 0)
        context:Tuple(frame, "GetShadowOffset", "SetShadowOffset", 0, 0)
    end
end

local function ApplyWindow(self, frame)
    if not frame or NS.Safety.IsForbidden(frame) or type(frame.CreateTexture) ~= "function" then return end
    local c = self.config
    local visual = M.visuals[frame] or CreateVisual(frame)
    local top = HeaderTop(c, frame)
    ApplyPanel(self, visual, frame, top)
    local name = frame.GetName and frame:GetName()
    local tab = type(name) == "string" and _G[name .. "Tab"] or nil
    local input = frame.editBox or (type(name) == "string" and _G[name .. "EditBox"])
    SetNativeChrome(self, frame, tab, input, c.panelAlpha > 0)
    if tab and type(tab.CreateTexture) == "function" then
        ApplyTabOverlay(self, visual, tab, TabSelected(frame, _G.SELECTED_CHAT_FRAME, DockSelection()))
    elseif visual.tabOverlay then
        visual.tabOverlay:Hide()
    end
    if frame == _G.ChatFrame1 then ApplySidebar(self, visual, frame) end
    ApplyCopyButton(self, visual, frame, top)
    ApplyInput(self, visual, frame, input)
    ApplyFont(self, frame)
end

-- Built-in chat frames plus Blizzard's list of temporary windows, each once.
local visited = {}
local function Visit(frame, count, callback, arg)
    if not frame or visited[frame] or count >= MAX_FRAMES then return count end
    visited[frame] = true
    callback(arg, frame)
    return count + 1
end

local function ForEachChatFrame(callback, arg)
    for frame in pairs(visited) do visited[frame] = nil end
    local count = 0
    local countBuiltIn = tonumber(_G.NUM_CHAT_WINDOWS) or 10
    for i = 1, math.min(countBuiltIn, MAX_FRAMES) do count = Visit(_G["ChatFrame" .. i], count, callback, arg) end
    local names = _G.CHAT_FRAMES
    if type(names) == "table" then
        for _, name in pairs(names) do
            if count >= MAX_FRAMES then break end
            if type(name) == "string" then count = Visit(_G[name], count, callback, arg) end
        end
    end
end

local function ApplyAll(self)
    if NS.IsCombatLocked() then
        S.Queue("chat")
        return
    end
    ForEachChatFrame(ApplyWindow, self)
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

-- hooksecurefunc raises when the target is missing, so each one is checked.
local function Hook(self, flag, name, hook)
    if self[flag] or type(hooksecurefunc) ~= "function" or type(_G[name]) ~= "function" then return end
    hooksecurefunc(name, hook)
    self[flag] = true
end

local FRIEND_EVENTS = {
    "FRIENDLIST_UPDATE", "BN_FRIEND_LIST_SIZE_CHANGED", "BN_FRIEND_ACCOUNT_ONLINE",
    "BN_FRIEND_ACCOUNT_OFFLINE", "BN_CONNECTED", "BN_DISCONNECTED",
}

function M:Enable()
    self.geometry = true
    self.context:Event("UPDATE_CHAT_WINDOWS", ApplyAll)
    self.context:Event("UPDATE_FLOATING_CHAT_WINDOWS", ApplyAll)
    for _, event in ipairs(FRIEND_EVENTS) do self.context:Event(event, UpdateFriendsCount, true) end
    self.context:Event("ADDON_LOADED", AddonLoaded)
    Hook(self, "hookedTemporary", "FCF_OpenTemporaryWindow", TemporaryWindowOpened)
    Hook(self, "hookedSelect", "FCFDock_SelectWindow", DockSelectionChanged)
    Hook(self, "hookedNewWindow", "FCF_OpenNewWindow", NewWindowOpened)
    ApplyAll(self)
end

function M:Refresh()
    ApplyAll(self)
end

local function HideVisual(visual)
    visual.panel:Hide()
    visual.header:Hide()
    visual.headerRule:Hide()
    for i = 1, 4 do visual.edges[i]:Hide() end
    if visual.tabLine then visual.tabLine:Hide() end
    if visual.tabOverlay then visual.tabOverlay:Hide() end
    if visual.sidebar then visual.sidebar:Hide() end
    if visual.sidebarFrame then visual.sidebarFrame:Hide() end
    if visual.copyButton then visual.copyButton:Hide() end
    if visual.input then visual.input:Hide() end
    if visual.inputEdges then for i = 1, 4 do visual.inputEdges[i]:Hide() end end
end

function M:Disable()
    for _, visual in pairs(self.visuals) do
        HideVisual(visual)
        local frame = visual.frame
        local name = frame and frame.GetName and frame:GetName()
        local tab = name and _G[name .. "Tab"]
        local input = frame and (frame.editBox or (name and _G[name .. "EditBox"]))
        if frame then SetNativeChrome(self, frame, tab, input, false) end
    end
    SyncNativeControls(self, false)
    HideCopyDialog(self.copyDialog)
end

S.Install("chat", M)

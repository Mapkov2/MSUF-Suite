local _, P = ...
local NS, S = P.NS, P.Suite
local C = P.Chat
local M = C.M
local SIZE, WIDTH = 20, 100
local ARROW_WIDTH, ARROW_HEIGHT, ARROW_GAP = 36, 18, 2
local TOOLS = {
    { title = S.Text("New tab"), action = "new" },
    { title = S.Text("Chat input"), action = "input" },
    { title = S.Text("Copy chat"), action = "copy" },
    { title = S.Text("Lock chat movement and resizing"), action = "lock" },
    { title = S.Text("Chat settings"), action = "settings" },
}
local STROKES = {
    { {0, 0, 10, 1}, {0, 0, 1, 10} },
    { {0, 4, 11, 1}, {-5, 0, 1, 7}, {5, 0, 1, 7}, {1, -3, 8, 1}, {-3, -4, 1, 3} },
    { {-2, 3, 8, 1}, {-5, -1, 1, 8}, {-2, -5, 8, 1}, {2, -1, 1, 8},
      {1, 6, 8, 1}, {5, 2, 1, 8} },
    { {0, -2, 10, 7}, {-3, 4, 1, 6}, {0, 7, 7, 1}, {3, 4, 1, 6} },
    { {0, 4, 12, 1}, {0, 0, 12, 1}, {0, -4, 12, 1},
      {-3, 4, 2, 5}, {3, 0, 2, 5}, {-1, -4, 2, 5} },
}

local function Icon(button, index)
    button.strokes = {}
    for part, geometry in ipairs(STROKES[index]) do
        local stroke = C.Fill(button, "ARTWORK")
        stroke:SetPoint("CENTER", button, "CENTER", geometry[1], geometry[2])
        stroke:SetSize(geometry[3], geometry[4])
        button.strokes[part] = stroke
    end
end

local function Selected()
    local frame = C.DockSelection() or ChatFrame1
    if frame and not NS.Safety.IsForbidden(frame) then return frame end
end

-- Narrow headers extend above Blizzard's native hover rectangle. Keep their
-- owned controls awake from enter/leave events, including a tab change.
function C.UpdateToolbarHover()
    local previous = M.toolbarHoverVisual
    local frame = (M.toolbarHoverCount or 0) > 0 and Selected()
    local visual = frame and M.visuals[frame]
    if previous == visual then return end
    if previous then
        previous.toolbarHovered = nil
        if M.active then C.ChatActivity(previous.frame) end
    end
    M.toolbarHoverVisual = visual
    if visual then
        visual.toolbarHovered = true
        C.ChatActivity(visual.frame)
    end
    if visual or previous then C.UpdateMinimalChrome(visual or previous) end
end

function C.ToolbarHover(button, hovered)
    if button.chatToolHovered == hovered then return end
    button.chatToolHovered = hovered
    M.toolbarHoverCount = math.max(0, (M.toolbarHoverCount or 0) + (hovered and 1 or -1))
    C.UpdateToolbarHover()
end

local function Click(button)
    if not M.active then return end
    local frame = Selected()
    if not frame then return end
    local action = button.action
    if action == "copy" then
        C.OpenCopyDialog(M, frame)
        return
    end
    if action == "input" then
        if frame.editBox:HasFocus() then
            ChatFrameUtil.DeactivateChat(frame.editBox)
        else
            ChatFrameUtil.OpenChat(nil, frame)
        end
        return
    end
    if NS.InCombat() then
        S.Print(NS.RestrictedNotice())
        return
    end
    if action == "new" then
        S.ChatCreateTab()
    elseif action == "lock" then
        S.Set("chat", "toolbarLocked", not M.config.toolbarLocked)
    elseif action == "settings" then
        S.Open("chat")
    end
end

local function Enter(button)
    C.ToolbarHover(button, true)
    C.Tint(button.fill, button.config.accentColor, 25)
    C.ShowTooltip(button, button.title)
end

local function Leave(button)
    C.ToolbarHover(button, false)
    C.Tint(button.fill, button.config.panelColor, 0)
    C.HideTooltip(button)
end

-- Shared by the live header and its menu preview; samples have no actions.
function C.PaintToolbar(owner, config, live)
    if not owner.buttons then
        owner.buttons = {}
        for index, tool in ipairs(TOOLS) do
            local button = S.CreateFrame("Button", nil, owner)
            button:SetSize(SIZE, SIZE)
            button:SetPoint("LEFT", owner, "LEFT", (index - 1) * SIZE, 0)
            button.fill = C.Fill(button, "BACKGROUND")
            button.fill:SetAllPoints(button)
            Icon(button, index)
            button.action, button.title = tool.action, tool.title
            if live then
                button:SetScript("OnClick", Click)
                button:SetScript("OnEnter", Enter)
                button:SetScript("OnLeave", Leave)
            else
                button:EnableMouse(false)
            end
            owner.buttons[index] = button
        end
    end
    owner:SetSize(WIDTH, SIZE)
    for index, button in ipairs(owner.buttons) do
        button.config = config
        local iconColor = index == 1 and "4fc27c" or config.tabActiveColor
        for _, stroke in ipairs(button.strokes) do C.Tint(stroke, iconColor, 100) end
        if index == 4 then button.strokes[4]:SetShown(config.toolbarLocked == true) end
        C.Tint(button.fill, config.panelColor, 0)
    end
end

function C.ApplyToolbar()
    local c = M.config
    if not c.headerToolbar then
        if M.toolbar and M.toolbar:IsShown() then C.ReleaseToolbar() end
        return
    end
    local toolbar = M.toolbar
    if not toolbar then
        -- The dock stays visible when another tab hides ChatFrame1.
        toolbar = S.CreateFrame("Frame", nil, GENERAL_CHAT_DOCK)
        M.toolbar = toolbar
    end
    C.PaintToolbar(toolbar, c, true)
    toolbar:ClearAllPoints()
    toolbar:SetPoint("TOPRIGHT", ChatFrame1, "TOPRIGHT", c.padding + (c.tabX or 0),
        math.max(22, C.HeaderTop(c, ChatFrame1)) + (c.tabY or 0))
    toolbar:SetFrameLevel(GENERAL_CHAT_DOCK:GetFrameLevel() + 8)
    toolbar:Show()
    C.ApplyToolbarGeometry()
    local visual = M.visuals[C.DockSelection() or ChatFrame1]
    if visual then
        C.ApplyInactivity(M, visual)
        C.UpdateMinimalChrome(visual)
    end
end

-- Reserve room before Blizzard computes tab overflow; no native title is read.
function C.ToolbarWrap(config, frame)
    local width = frame:GetWidth()
    return S.Finite(width) and width < 180 + WIDTH + 8 + (config.headerClock and 80 or 0)
end

local function IsWhisper(frame)
    local kind = frame.chatType
    return frame.isTemporary and S.Public(kind) and (kind == "WHISPER" or kind == "BN_WHISPER")
end

local function HasDockedWhisper(dock)
    if not (dock.DOCKED_CHAT_FRAMES and dock.scrollFrame and dock.overflowButton) then return false end
    for _, frame in ipairs(dock.DOCKED_CHAT_FRAMES) do
        if not NS.Safety.IsForbidden(frame) and not frame.isStaticDocked and IsWhisper(frame) then
            local tab = _G[frame:GetName() .. "Tab"]
            if tab and not NS.Safety.IsForbidden(tab) and tab:IsShown() then return true end
        end
    end
    return false
end

local function BeforeControl(limit, left, bottom, top, control, scale)
    if not control or not control:IsShown() then return limit end
    local x, right, low, high = control:GetLeft(), control:GetRight(), control:GetBottom(), control:GetTop()
    if S.Finite(x) and S.Finite(right) and S.Finite(low) and S.Finite(high)
        and x * scale < limit and right * scale > left and high * scale > bottom and low * scale < top then
        return x * scale - ARROW_GAP
    end
    return limit
end

local function NativeDockMinimum(dock, left)
    local scrollLeft, overflowWidth = dock.scrollFrame:GetLeft(), dock.overflowButton:GetWidth()
    if not S.Finite(scrollLeft) or not S.Finite(overflowWidth) then return end
    local minimum = math.max(0, scrollLeft - left) + overflowWidth + 6
    if dock.RightTabHint and S.GamepadUI() then
        local hintWidth = dock.RightTabHint:GetWidth()
        if not S.Finite(hintWidth) then return end
        -- Forever reserves three pixels to the left of the gamepad hint.
        minimum = minimum + hintWidth + 3
    end
    return minimum
end

local function WhisperDockWidth(dock, inset, previousX, previousY)
    local left, bottom, top = dock:GetLeft(), dock:GetBottom(), dock:GetTop()
    local right, chatTop = ChatFrame1:GetRight(), ChatFrame1:GetTop()
    local dockScale, chatScale = dock:GetEffectiveScale(), ChatFrame1:GetEffectiveScale()
    if not (S.Finite(left) and S.Finite(bottom) and S.Finite(top) and S.Finite(right) and S.Finite(chatTop)
        and S.Finite(dockScale) and dockScale > 0 and S.Finite(chatScale) and chatScale > 0) then return end
    local minimum = NativeDockMinimum(dock, left)
    if not minimum then return end
    local c, scale = M.config, chatScale / dockScale
    local x, y = c.tabX or 0, c.tabY or 0
    left = left + x - previousX
    bottom, top = bottom + y - previousY, top + y - previousY
    local limit = (right + math.min(0, (c.padding or 0) + x) - inset) * scale
    local rowBottom, rowHeight = (chatTop + y) * scale, (c.tabHeight or 24) * scale
    local frame = Selected() or ChatFrame1
    local visual = M.visuals[frame]
    if visual then
        local visualScale = frame:GetEffectiveScale()
        if not S.Finite(visualScale) or visualScale <= 0 then return end
        local low, high = math.min(bottom, rowBottom), math.max(top, rowBottom + rowHeight)
        limit = BeforeControl(limit, left, low, high, visual.copyButton, visualScale / dockScale)
        limit = BeforeControl(limit, left, low, high, visual.headerClock, visualScale / dockScale)
    end
    local width = limit - left
    if width < minimum then return end
    local slot = ARROW_WIDTH + ARROW_GAP
    -- Reserving the slot while a whisper is docked keeps overflow independent
    -- of whether the arrows happen to be shown.
    if width >= minimum + slot and rowHeight >= ARROW_HEIGHT then
        return width - slot, rowBottom + rowHeight / 2 - (bottom + top) / 2
    end
    return width
end

local function ReleaseDockWidth(dock)
    if not M.toolbarDockOwned then return end
    M.toolbarLayingOut = true
    M.context:RestoreProperty(dock, "SetWidth")
    M.context:RestorePoints(dock)
    M.toolbarDockAnchor, M.toolbarDockOwned, M.whisperArrowY = nil, nil, nil
    M.toolbarDockX, M.toolbarDockY = nil, nil
    FCFDock_UpdateTabs(dock, true)
    M.toolbarLayingOut = nil
end

local function RememberDockAnchor(point, relative, edge, x, y, xOffset, yOffset)
    local before = M.toolbarDockAnchor or {}
    before[1], before[2], before[3], before[4], before[5] = point, relative, edge, x, y
    M.toolbarDockAnchor, M.toolbarDockX, M.toolbarDockY = before, xOffset, yOffset
end

local function LayoutNativeDock(dock, xOffset, yOffset)
    ReleaseDockWidth(dock)
    C.OffsetNative(M, dock, xOffset, yOffset)
    M.whisperArrowY = nil
    if xOffset == 0 and yOffset == 0 then
        M.toolbarDockAnchor = nil
    else
        local point, relative, edge, x, y = dock:GetPoint(1)
        if S.Public(point) and S.Public(relative) and S.Public(edge) and S.Finite(x) and S.Finite(y) then
            RememberDockAnchor(point, relative, edge, x, y, xOffset, yOffset)
        else
            M.toolbarDockAnchor = nil
        end
    end
end

function C.LayoutToolbarDock()
    if M.toolbarLayingOut or not M.active or C.LayoutLocked() then return end
    local dock, c = GENERAL_CHAT_DOCK, M.config
    local xOffset, yOffset = c.tabX or 0, c.tabY or 0
    local toolbar = c.headerToolbar and not C.ToolbarWrap(c, ChatFrame1)
    local whisper = HasDockedWhisper(dock)
    if not toolbar and not whisper then
        LayoutNativeDock(dock, xOffset, yOffset)
        return
    end
    local point, relative, edge, x, y = dock:GetPoint(1)
    local before = M.toolbarDockAnchor
    local sameAnchor = before and dock:GetNumPoints() == 1 and S.Public(point) and S.Public(relative) and S.Public(edge)
        and S.Finite(x) and S.Finite(y) and point == before[1] and relative == before[2]
        and edge == before[3] and x == before[4] and y == before[5]
    local inset = toolbar and WIDTH + 8 + (c.headerClock and 80 or 0) or 0
    local width, arrowY
    if whisper then
        width, arrowY = WhisperDockWidth(dock, inset, sameAnchor and M.toolbarDockX or 0, sameAnchor and M.toolbarDockY or 0)
    end
    M.whisperArrowY = arrowY
    if not width and not toolbar then
        LayoutNativeDock(dock, xOffset, yOffset)
        return
    end
    width = width or ChatFrame1:GetWidth() - inset
    if not S.Finite(width) then return end
    if M.toolbarDockOwned and sameAnchor and M.toolbarDockX == xOffset and M.toolbarDockY == yOffset
        and dock:GetWidth() == width then return end
    M.toolbarLayingOut = true
    M.context:RestorePoints(dock)
    point, relative, edge, x, y = dock:GetPoint(1)
    if S.Public(point) and S.Public(relative) and S.Public(edge) and S.Finite(x) and S.Finite(y) then
        x, y = x + xOffset, y + yOffset
        M.context:Anchor(dock, point, relative, edge, x, y)
        M.context:Property(dock, "GetWidth", "SetWidth", width)
        RememberDockAnchor(point, relative, edge, x, y, xOffset, yOffset)
        M.toolbarDockOwned = true
        FCFDock_UpdateTabs(dock, true)
    else
        M.whisperArrowY = nil
    end
    M.toolbarLayingOut = nil
end

function C.ReleaseToolbar()
    C.StopToolbarGesture(false)
    M.toolbarHoverCount = 0
    C.UpdateToolbarHover()
    if M.toolbar then
        for _, button in ipairs(M.toolbar.buttons) do button.chatToolHovered = nil end
    end
    if M.toolbarDrag then M.toolbarDrag.chatToolHovered = nil end
    if M.toolbarResize then M.toolbarResize.chatToolHovered = nil end
    if M.toolbar then M.toolbar:Hide() end
    if M.toolbarDrag then M.toolbarDrag:Hide() end
    if M.toolbarResize then M.toolbarResize:Hide() end
    ReleaseDockWidth(GENERAL_CHAT_DOCK)
end

local function SelectWhisper(button)
    if not M.active or NS.InCombat() then return end
    local alpha = button:GetEffectiveAlpha()
    if not S.Finite(alpha) or alpha <= 0 then return end
    local selected = C.DockSelection()
    local first, last, selectedTab, neighbor
    for _, frame in ipairs(GENERAL_CHAT_DOCK.DOCKED_CHAT_FRAMES) do
        local tab = not NS.Safety.IsForbidden(frame) and IsWhisper(frame) and _G[frame:GetName() .. "Tab"]
        if tab and not NS.Safety.IsForbidden(tab) and tab:IsShown() then
            if selected == frame then
                selectedTab = tab
                if button.previous then neighbor = last end
            elseif not button.previous and selectedTab and last == selectedTab then
                neighbor = tab
            end
            first, last = first or tab, tab
        end
    end
    local tab = neighbor or (button.previous and last or first)
    if tab and tab ~= selectedTab then FCF_Tab_OnClick(tab, "LeftButton") end
end

local function WakeWhisperArrows()
    if M.active then C.ChatActivity(C.DockSelection() or ChatFrame1) end
end

local function WhisperArrows(frame)
    local arrows = S.CreateFrame("Frame", nil, frame)
    arrows:SetSize(ARROW_WIDTH, ARROW_HEIGHT)
    arrows:SetFrameStrata("MEDIUM")
    arrows:SetClampedToScreen(true)
    arrows.buttons = {}
    for index, glyph in ipairs({ "<", ">" }) do
        local button = S.CreateFrame("Button", nil, arrows)
        button:SetSize(ARROW_WIDTH / 2, ARROW_HEIGHT)
        button:SetPoint("LEFT", arrows, "LEFT", (index - 1) * ARROW_WIDTH / 2, 0)
        local fill = C.Fill(button, "BACKGROUND")
        fill:SetAllPoints(button)
        local label = S.CreateFontString(button, nil, "ARTWORK", "GameFontHighlightSmall")
        label:SetPoint("CENTER", button, "CENTER")
        label:SetText(glyph)
        button.fill, button.previous = fill, index == 1
        button:SetScript("OnClick", SelectWhisper)
        button:SetScript("OnEnter", WakeWhisperArrows)
        arrows.buttons[index] = button
    end
    return arrows
end

-- Compare the whole row with the remaining viewport, independent of
-- Blizzard's horizontal scroll position.
local function WhisperOverflow(dock)
    if dock.overflowButton:IsShown() then return true end
    local first, last
    for _, frame in ipairs(dock.DOCKED_CHAT_FRAMES) do
        if not NS.Safety.IsForbidden(frame) and not frame.isStaticDocked then
            local tab = _G[frame:GetName() .. "Tab"]
            if tab and not NS.Safety.IsForbidden(tab) and tab:IsShown() then first, last = first or tab, tab end
        end
    end
    if not first then return false end
    local left, right = dock.scrollFrame:GetLeft(), dock.scrollFrame:GetRight()
    local firstLeft, lastRight = first:GetLeft(), last:GetRight()
    if not (S.Finite(left) and S.Finite(right) and S.Finite(firstLeft) and S.Finite(lastRight)) then return false end
    return lastRight - firstLeft > right - left + 0.5
end

local function WhisperArrowFits(dock)
    -- Suite tab padding and gaps are applied after Blizzard's layout. Recheck
    -- the static span so those tabs cannot paint into the reserved arrow slot.
    local left, width = dock:GetLeft(), dock:GetWidth()
    if not (S.Finite(left) and S.Finite(width)) then return false end
    local minimum = NativeDockMinimum(dock, left)
    return minimum ~= nil and width >= minimum
end

function C.UpdateWhisperArrows(dock)
    local frame = C.DockSelection() or ChatFrame1
    local arrows = M.whisperArrows
    if NS.Safety.IsForbidden(frame) or M.whisperArrowY == nil or not WhisperArrowFits(dock) or not WhisperOverflow(dock) then
        if arrows and arrows:IsShown() then arrows:Hide() end
        return
    end
    local c = M.config
    if not arrows then
        arrows = WhisperArrows(frame)
        M.whisperArrows = arrows
    elseif arrows:GetParent() ~= frame then
        -- Follow the selected chat window's visibility and inactivity alpha.
        arrows:SetParent(frame)
    end
    local dockScale, frameScale = dock:GetEffectiveScale(), frame:GetEffectiveScale()
    if S.Finite(dockScale) and dockScale > 0 and S.Finite(frameScale) and frameScale > 0 then
        local scale = dockScale / frameScale
        if arrows.dockScale ~= scale then
            arrows:SetScale(scale)
            arrows.dockScale = scale
        end
    end
    if arrows.anchor ~= dock or arrows.y ~= M.whisperArrowY then
        arrows:ClearAllPoints()
        arrows:SetPoint("LEFT", dock, "RIGHT", ARROW_GAP, M.whisperArrowY)
        arrows.anchor, arrows.y = dock, M.whisperArrowY
    end
    if arrows.color ~= c.panelColor or arrows.minimal ~= c.minimalChrome then
        for _, button in ipairs(arrows.buttons) do C.Tint(button.fill, c.panelColor, c.minimalChrome and 0 or 95) end
        arrows.color, arrows.minimal = c.panelColor, c.minimalChrome
    end
    if not arrows:IsShown() then arrows:Show() end
end

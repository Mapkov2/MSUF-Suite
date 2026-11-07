local _, P = ...
local NS, S = P.NS, P.Suite
local C = P.Chat
local M = C.M
local SIZE, WIDTH = 20, 100
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
        C.ReleaseToolbar()
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

function C.LayoutToolbarDock()
    if M.toolbarLayingOut or not M.active or not M.config.headerToolbar or NS.InCombat() then return end
    local dock, c = GENERAL_CHAT_DOCK, M.config
    if C.ToolbarWrap(c, ChatFrame1) then
        if M.toolbarDockOwned then
            M.toolbarLayingOut = true
            M.context:RestoreProperty(dock, "SetWidth")
            M.context:RestorePoints(dock)
            M.toolbarDockOwned = nil
            FCFDock_UpdateTabs(dock, true)
            M.toolbarLayingOut = nil
        end
        C.OffsetNative(M, dock, c.tabX or 0, c.tabY or 0)
        return
    end
    local width = ChatFrame1:GetWidth() - WIDTH - 8 - (c.headerClock and 80 or 0)
    if not S.Finite(width) then return end
    local point, relative, edge, x, y = dock:GetPoint(1)
    local before = M.toolbarDockAnchor
    if before and M.toolbarDockX == (c.tabX or 0) and M.toolbarDockY == (c.tabY or 0)
        and dock:GetNumPoints() == 1 and point == before[1] and relative == before[2]
        and edge == before[3] and x == before[4] and y == before[5] and dock:GetWidth() == width then return end
    M.toolbarLayingOut = true
    M.context:RestorePoints(dock)
    point, relative, edge, x, y = dock:GetPoint(1)
    if S.Public(point) and S.Public(relative) and S.Public(edge) and S.Finite(x) and S.Finite(y) then
        x, y = x + (c.tabX or 0), y + (c.tabY or 0)
        M.context:Anchor(dock, point, relative, edge, x, y)
        M.context:Property(dock, "GetWidth", "SetWidth", width)
        M.toolbarDockAnchor = { point, relative, edge, x, y }
        M.toolbarDockX, M.toolbarDockY = c.tabX or 0, c.tabY or 0
        M.toolbarDockOwned = true
        FCFDock_UpdateTabs(dock, true)
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
    if M.toolbarDockOwned then
        M.toolbarDockOwned = nil
        M.context:RestoreProperty(GENERAL_CHAT_DOCK, "SetWidth")
        M.context:RestorePoints(GENERAL_CHAT_DOCK)
        FCFDock_UpdateTabs(GENERAL_CHAT_DOCK, true)
    end
end

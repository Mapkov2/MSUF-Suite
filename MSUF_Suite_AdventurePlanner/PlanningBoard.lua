local _, P = ...
local NS, S, Plan = P.NS, P.Suite, P.PlanningTools
-- Menu2's window anatomy: a shell with a title band, the navigation rail on
-- the left and the host on the right. The host carries the status bar (page
-- title, hint, search), the body and the footer actions.
local Board = { PAGE_ROWS = 10, ROW_HEIGHT = 50, WIDTH = 1180, HEIGHT = 720, RAIL_WIDTH = 200, HOST_X = 220,
    HOST_WIDTH = 944, HOST_HEIGHT = 660, BODY_X = 12, BODY_TOP = -68, BODY_WIDTH = 920, BODY_HEIGHT = 520 }
Plan.Board = Board

function Board.Label(parent, text, size, token)
    local label = S.CreateFontString(parent, nil, "OVERLAY")
    Board.TrackFont(label, size or 12, token or "text")
    label:SetText(S.Text(text or ""))
    label:SetJustifyH("LEFT")
    label:SetJustifyV("TOP")
    return label
end

function Board.Panel(parent, x, y, width, height, material)
    local panel = S.CreateFrame("Frame", nil, parent, "BackdropTemplate")
    panel:SetPoint("TOPLEFT", x, y)
    panel:SetSize(width, height)
    Board.Material(panel, material or "card", "panel2")
    return panel
end

function Board.Button(parent, text, width, height, callback)
    local bridge = NS.HostBridge
    local button = bridge.MenuButton(parent, width, height or 30)
    local native = button ~= nil
    button = button or S.CreateFrame("Button", nil, parent)
    button:SetSize(width, height or 30)
    button.plannerNativeButton = native
    if native then
        button.text = Board.TrackFont(bridge.MenuButtonLabel(button), 12, false)
    else
        button.fill = Board.Fill(button, "pillBase")
        button.text = Board.Label(button, "", 12)
        button:SetScript("OnEnter", function(self) Board.Tint(self.fill, "pillHover") end)
        button:SetScript("OnLeave", function(self) Board.Tint(self.fill, "pillBase") end)
    end
    button.text:ClearAllPoints()
    button.text:SetPoint("LEFT", 8, 0)
    button.text:SetPoint("RIGHT", -8, 0)
    button.text:SetHeight((height or 30) - 4)
    button.text:SetJustifyV("MIDDLE")
    button.text:SetWordWrap(true)
    button.text:SetText(S.Text(text))
    button:SetScript("OnClick", callback)
    return button
end

function Board.Valid(window)
    return window.owner and window.profile == NS.DB and Plan.CanEdit()
        and (not window.spec.valid or window.spec.valid(window.owner))
end

function Board.Selected(window)
    if not Board.Valid(window) then return nil end
    for _, row in ipairs(window.items) do if row.key == window.selected then return row end end
end

function Board.RunAction(button)
    local window = button.window
    if not Board.Valid(window) then return end
    window:Refresh()
    local action, row = window.spec.actions[button.index], window:Selected()
    if action and (not action.enabled or action.enabled(window.owner, row)) then action.run(window.owner, row, window) end
end

function Board.RowClicked(button, mouse)
    local window = button.window
    if not Board.Valid(window) then return end
    local row = window.filtered[window.offset + button.index]
    if not row or row.disabled then return end
    if window.selected ~= row.key then
        window.detailScroll:Reset()
        if window.spec.onSelect then window.spec.onSelect(window.owner, row) end
    end
    window.selected = row.key
    if mouse == "RightButton" and window.spec.menu then window.spec.menu(window.owner, row, button) end
    window:Refresh()
end

function Board.TabClicked(button)
    Board.FinishAccordion(button.window, true)
    local window = button.window
    if not Board.Valid(window) then return end
    local entry = window.spec.tabs[button.index]
    if not entry then return end
    local changed = entry.key ~= window.spec.currentTab(window.owner)
    window.offset, window.selected = 0, nil
    window.listScroll:Reset()
    window.detailScroll:Reset()
    window.spec.selectTab(window.owner, entry.key)
    window.search:SetText("")
    window:Refresh()
    if changed then Board.PlayPage(window) end
end

function Board.Refresh(owner)
    local window = Board.window
    if window and window.owner == owner and window:IsShown() then window:Refresh() end
end

-- Programmatic close (combat, disable, profile change) hides at once.
function Board.Close(owner)
    local window = Board.window
    if window and window.restoreBar and window.restoreBar.owner == owner then Board.ClearRestore(window) end
    if window and window.owner == owner then window:Hide() end
end

-- A close the user asked for plays MSUF's popup exit first.
function Board.Dismiss(owner)
    local window = Board.window
    if not window or window.owner ~= owner or not window:IsShown() then return end
    if NS.InCombat() then return window:Hide() end
    Board.PlayClose(window)
end

local _, P = ...
local E, S, T, W, Tr = {}, P.S, P.T, P.W, P.Tr
P.ChatPreviewWindows = E

local function OpenDetached(card)
    if P.Combat() or not S.ChatOpenDetachedMover(card.index) then return end
    P.M.frame:Hide()
end

local DELETE_TABS = { title = Tr("Delete Chat Tabs"), action = Tr("Delete selected tabs"),
    key = "chat-delete-tabs", question = Tr("Delete these chat tabs?") }

local function OpenDeleteMenu(ui, button)
    if ui.inCombat or P.Combat() then return end
    local rows = {}
    if S.ChatDeletableTabs(rows) == 0 then return end
    for _, item in ipairs(rows) do item.text = item.title .. "  #" .. item.index end
    P.OpenDeletePicker(button, rows, DELETE_TABS, function(picks)
        S.ChatDeleteTabs(picks)
        ui.runtimeRefresh()
    end)
end

local function Rename(ui, row)
    if ui.inCombat or P.Combat() or not ui.header:IsVisible() or not ui.ctx.wrapper:IsVisible() then return false end
    local dialog = P.AskText("chat-rename-tab", Tr("Rename Chat Tab"), function(name)
        if S.ChatRenameTab(row, name) then
            ui.runtimeRefresh()
        elseif P.M.ShowStatusFeedback then
            P.M.ShowStatusFeedback(Tr("Action failed"), "danger", 1.5)
        end
    end, 31)
    if not dialog then return false end
    local edit = dialog:GetEditBox()
    edit:SetText(row.title)
    edit:HighlightText()
    return true
end

local function FindTab(id, generation)
    local rows = {}
    S.ChatDeletableTabs(rows)
    for _, row in ipairs(rows) do
        if row.index == id and row.generation == generation then return row end
    end
end

function E.RenamePreviewTab(ui, tab)
    if not tab.previewTabID or ui.inCombat or P.Combat() then return false end
    local row = FindTab(tab.previewTabID, tab.previewTabGeneration)
    return row and Rename(ui, row) or false
end

local function OpenRenameMenu(ui, button)
    if ui.inCombat or P.Combat() then return end
    local rows = {}
    if S.ChatDeletableTabs(rows) == 0 then return end
    P.AnchoredContextMenu(button, function(_, root)
        root:CreateTitle(Tr("Rename Chat Tab"))
        for _, row in ipairs(rows) do
            root:CreateButton(row.title .. "  #" .. row.index, function()
                if ui.inCombat or P.Combat() then return end
                local current = FindTab(row.index, row.generation)
                if current then Rename(ui, current) end
            end)
        end
    end)
end

local function PaintCard(rail)
    local row = rail.selected
    if not row then return end
    local card = rail.card
    card.index = row.index
    card:SetText(row.text)
    local width = rail.cardWidth or 100
    card:SetHeight(math.max(24, math.min(46, width * row.height / row.width)))
end

function E.Build(ui)
    local panel = CreateFrame("Frame", nil, ui.header)
    local rail = { panel = panel, rows = {}, choices = {} }
    ui.windowRail = rail
    rail.create = T.RoleButton(panel, Tr("Create New Chat Tab"), "success", 236, 26)
    rail.create:SetPoint("TOPLEFT")
    rail.create:SetScript("OnClick", function()
        if ui.inCombat or P.Combat() then return end
        if S.ChatCreateTab then
            S.ChatCreateTab(function()
                if ui.header:IsVisible() then P.M.frame:Hide() end
            end)
        end
    end)
    P.HM.SkipHistoryCheckpoint(rail.create)
    rail.rename = T.Button(panel, Tr("Rename Chat Tab"), 236, 26)
    rail.rename:SetScript("OnClick", function(button) OpenRenameMenu(ui, button) end)
    P.HM.SkipHistoryCheckpoint(rail.rename)
    rail.delete = T.RoleButton(panel, Tr("Delete Chat Tabs"), "destructive", 236, 26)
    rail.delete:SetScript("OnClick", function(button) OpenDeleteMenu(ui, button) end)
    P.HM.SkipHistoryCheckpoint(rail.delete)
    rail.detached = CreateFrame("Frame", nil, panel)
    rail.detached:Hide()
    rail.picker = P.M.BindDropdownAt(ui.ctx, rail.detached, Tr("Detached chat windows"), 0, 0,
        function() return rail.choices end, 172, function() return rail.selected and rail.selected.index end,
        function(index)
            for _, row in ipairs(rail.choices) do
                if row.index == index then rail.selected = row break end
            end
            PaintCard(rail)
        end, P.Meta("suite_chat", "chat", "preview.floating", "ephemeral"))
    rail.card = T.Button(rail.detached, "", 100, 24)
    rail.card:SetScript("OnClick", OpenDetached)
    P.HM.SkipHistoryCheckpoint(rail.card)
end

function E.Refresh(ui)
    local rail = ui.windowRail
    rail.create:SetEnabled(not ui.inCombat and S.ChatCanCreateTab and S.ChatCanCreateTab() or false)
    local editable = not ui.inCombat and S.ChatDeletableTabs and S.ChatDeletableTabs() > 0 or false
    rail.rename:SetEnabled(editable)
    rail.delete:SetEnabled(editable)
    local previous = rail.selected and rail.selected.value
    local count = S.ChatDetachedWindows and S.ChatDetachedWindows(rail.rows) or 0
    local selected
    for i = 1, count do
        local row = rail.rows[i]
        row.value, row.text = row.index, row.title .. "  #" .. row.index
        rail.choices[i] = row
        if row.index == previous then selected = row end
    end
    for i = #rail.choices, count + 1, -1 do rail.choices[i] = nil end
    rail.selected = selected or rail.choices[1]
    rail.detached:SetShown(rail.selected ~= nil)
    if not rail.selected then return end
    rail.picker:SetValue(rail.selected.index)
    rail.card:SetEnabled(not ui.inCombat and S.Status("chat") == "Active")
    PaintCard(rail)
end

function E.Layout(ui, offset)
    local rail, width = ui.windowRail, ui.width
    rail.panel:ClearAllPoints()
    rail.panel:SetPoint("TOPLEFT", ui.viewport, "BOTTOMLEFT", 0, -8 - offset)
    if rail.width ~= width then
        rail.width = width
        local wide = width >= 900
        local inline = width >= 552
        local buttonWidth = inline and ((wide and 552 or width) - 12) / 3 or math.min(236, width)
        rail.create:SetWidth(buttonWidth)
        rail.rename:ClearAllPoints()
        rail.rename:SetPoint("TOPLEFT", rail.panel, "TOPLEFT", inline and buttonWidth + 6 or 0, inline and 0 or -30)
        rail.rename:SetWidth(buttonWidth)
        rail.delete:ClearAllPoints()
        rail.delete:SetPoint("TOPLEFT", rail.panel, "TOPLEFT", inline and 2 * (buttonWidth + 6) or 0, inline and 0 or -60)
        rail.delete:SetWidth(buttonWidth)
        rail.actionHeight = inline and 26 or 86
        local x, y = wide and 560 or 0, wide and 0 or -(rail.actionHeight + 6)
        local available = width - x
        local pickerWidth = math.min(172, math.floor(available * .57))
        rail.cardWidth = available - pickerWidth - 8
        rail.detached:ClearAllPoints()
        rail.detached:SetPoint("TOPLEFT", rail.panel, "TOPLEFT", x, y)
        rail.detached:SetSize(available, 50)
        W.MoveWidget(rail.picker, rail.detached, 0, 0, pickerWidth)
        rail.card:SetPoint("TOPRIGHT", rail.detached, "TOPRIGHT", 0, -6)
        rail.card:SetWidth(rail.cardWidth)
        rail.detachedHeight = math.max(rail.actionHeight, 50 - y)
        PaintCard(rail)
    end
    local height = rail.selected and rail.detachedHeight or rail.actionHeight
    rail.panel:SetSize(width, height)
    return height + 8
end

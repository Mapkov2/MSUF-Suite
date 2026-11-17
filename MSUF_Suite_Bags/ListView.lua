local _, P = ...
local S = P.Suite
local Columns, Grid = P.BagListColumns, P.GridView
-- The list presentation of the bag view (InventoryRendering.lua), the bank
-- view (BankInventory.lua) and the offline view (OfflineInventory.lua). One
-- line per row, CELL tall like a grid line, so paging and the window size
-- stay those of the grid. A live row keeps Blizzard's own item button at its
-- left edge (its owner places it): this file only draws Suite text beside
-- it and never touches a Blizzard frame. Offline rows draw their own icon
-- and react to the mouse with a tooltip alone.
-- The first visible line is the band: the column titles (click one to sort)
-- and, offline, which snapshot is shown. It does not scroll.
local List = {}
P.BagList = List
local CELL, ROW_HEIGHT = 40, 36
local LEFT_COLUMNS = { name = true, binding = true, type = true }
local SORT_STATE = { bags = "listSort", bank = "bankListSort" }
local SORT_ARROW = "Interface\\Buttons\\UI-SortArrow"

function List.New()
    return { entries = {}, entryPool = {}, rows = {}, headers = {}, fit = {}, fitScratch = {}, count = 0 }
end

------------------------------------------------------------------ sort state
-- The column and direction of a list, kept in the profile's module state
-- (state.listSort, state.bankListSort): a header click is no setting.
function List.SortSpec(scope)
    local field = SORT_STATE[scope] or SORT_STATE.bags
    local state = S.ModuleState("bags")
    local spec = state and state[field]
    if type(spec) ~= "table" or not Columns.Valid(spec.key) then
        spec = { key = "name", desc = false }
        if state then state[field] = spec end
    end
    if spec.desc ~= true then spec.desc = false end
    return spec
end

-- A click on a column title: the same column flips its direction, another
-- one starts in its natural direction. Returns whether the order changed.
function List.SetSort(scope, key)
    if not Columns.Valid(key) then return false end
    local spec = List.SortSpec(scope)
    if spec.key == key then
        spec.desc = not spec.desc
    else
        spec.key, spec.desc = key, Columns.byKey[key].desc == true
    end
    return true
end

------------------------------------------------------------------ layout
local function Entry(list, index)
    local entry = list.entryPool[index]
    if not entry then
        entry = {}
        list.entryPool[index] = entry
    end
    list.entries[index] = entry
    return entry
end

-- The lines of a built model: a header per shown group, then its rows in the
-- list's order. An unchanged model (InventoryModel.lua revision) and order
-- keeps the lines it has: paging and repainting sort nothing again.
function List.Layout(list, model, spec, config)
    local track = config.listShowTrack == true
    if list.model == model and list.revision == model.revision and list.sortKey == spec.key
        and list.sortDesc == spec.desc and list.track == track then
        return list.entries, list.count
    end
    list.model, list.revision, list.sortKey, list.sortDesc, list.track = model, model.revision, spec.key, spec.desc, track
    local comparator = Columns.Comparator(spec.key, spec.desc)
    local count = 0
    for g = 1, #model.groups do
        local group = model.groups[g]
        local rows = group.displayRows
        if group.visible and (#rows > 0 or group.collapsed) then
            count = count + 1
            local header = Entry(list, count)
            header.group, header.row = group, nil
            for i = 1, #rows do Columns.Prepare(rows[i].item, config) end
            table.sort(rows, comparator)
            for i = 1, #rows do
                count = count + 1
                local entry = Entry(list, count)
                entry.group, entry.row = group, rows[i]
            end
        end
    end
    for i = count + 1, #list.entries do list.entries[i] = nil end
    list.count = count
    return list.entries, count
end

-- Forgets the cached lines (the next Layout sorts again).
function List.Invalidate(list)
    list.model, list.revision = nil, nil
end

-- The first entry shown and how far a list may scroll for rows lines of
-- content below the band.
function List.Clamp(count, scroll, rows)
    local maximum = math.max(0, count - rows)
    return math.max(0, math.min(scroll or 0, maximum)), maximum
end

------------------------------------------------------------------ widgets
local function Detach(list)
    for i = 1, #list.rows do list.rows[i]:Hide() end
    for i = 1, #list.headers do list.headers[i]:Hide() end
    if list.status then list.status:Hide() end
    if list.back then list.back:Hide() end
    list.rows, list.headers, list.status, list.back = {}, {}, nil, nil
end

-- Widgets live on parent (the bag chrome or the organised bank frame).
function List.Attach(list, parent)
    if list.parent == parent then return end
    if list.parent then Detach(list) end
    list.parent = parent
end

local function ColumnMenu(button, list)
    if NS.InCombat() or not button.key then return end
    local previous, following
    for i = 1, #list.fit do
        if list.fit[i].column.key == button.key then
            local left, right = list.fit[i - 1], list.fit[i + 1]
            previous, following = left and left.column.key, right and right.column.key
            break
        end
    end
    local key = button.key
    P.BagFilterMenu.Show(button, function(_, menu)
        if previous then
            menu:CreateButton(S.Text("Move column left"), function()
                if not NS.InCombat() then Columns.Move(S.Config("bags"), key, previous) end
            end)
        end
        if following then
            menu:CreateButton(S.Text("Move column right"), function()
                if not NS.InCombat() then Columns.Move(S.Config("bags"), key, following) end
            end)
        end
        menu:CreateButton(S.Text("Reset column order"), function()
            if not NS.InCombat() then S.Set("bags", "listColumnOrder", "") end
        end)
    end)
end

local function HeaderClicked(button, mouse)
    local list = button.list
    if mouse == "RightButton" then
        ColumnMenu(button, list)
    elseif list.onSort and button.key then
        list.onSort(button.key)
    end
end

local function HeaderEnter(button)
    local column = Columns.byKey[button.key]
    if not column then return end
    GameTooltip:SetOwner(button, "ANCHOR_TOP")
    GameTooltip:SetText(S.Text(column.label))
    GameTooltip:AddLine(S.Text("Click to sort by this column. Click again to reverse the order."), .8, .8, .8, true)
    GameTooltip:AddLine(S.Text("Right-click to move this column."), .8, .8, .8, true)
    GameTooltip:Show()
end

local function Header(list, index)
    local button = list.headers[index]
    if button then return button end
    button = P.ChildFrame("Button", list.parent)
    button:SetHeight(18)
    button:SetFrameLevel(list.parent:GetFrameLevel() + 2)
    button.text = Grid.Font(button, 11)
    button.text:SetPoint("TOPLEFT", 0, 0)
    button.text:SetPoint("BOTTOMRIGHT", -12, 0)
    button.text:SetWordWrap(false)
    button.arrow = S.CreateTexture(button, nil, "ARTWORK")
    button.arrow:SetSize(9, 8)
    button.arrow:SetPoint("RIGHT", 0, 0)
    button.arrow:SetTexture(SORT_ARROW)
    button.rule = S.CreateTexture(button, nil, "BORDER")
    button.rule:SetPoint("BOTTOMLEFT")
    button.rule:SetPoint("BOTTOMRIGHT")
    button.rule:SetHeight(1)
    button.list = list
    button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    button:SetScript("OnClick", HeaderClicked)
    button:SetScript("OnEnter", HeaderEnter)
    button:SetScript("OnLeave", GameTooltip_Hide)
    list.headers[index] = button
    return button
end

local function PaintHeader(button, entry, x, y, spec, accent)
    local column = entry.column
    if button.x ~= x or button.y ~= y or button.width ~= entry.width then
        button:ClearAllPoints()
        button:SetPoint("TOPLEFT", button.list.parent, "TOPLEFT", x, y)
        button:SetWidth(entry.width)
        button.x, button.y, button.width = x, y, entry.width
    end
    local sorted = spec.key == column.key
    local label = S.Text(entry.width < 64 and column.short or column.label)
    if button.key ~= column.key or button.label ~= label then
        button.text:SetJustifyH(LEFT_COLUMNS[column.key] and "LEFT" or "RIGHT")
        button.text:SetText(label)
        button.key, button.label = column.key, label
    end
    button.arrow:SetShown(sorted)
    if sorted then
        if spec.desc then button.arrow:SetTexCoord(0, .5625, 0, 1) else button.arrow:SetTexCoord(0, .5625, 1, 0) end
    end
    local r, g, b = S.RGB(accent)
    button.rule:SetColorTexture(r, g, b, sorted and .8 or .2)
    button:Show()
end

local function StatusWidgets(list)
    if list.status then return end
    list.status = Grid.Font(list.parent, 11)
    list.status:SetWordWrap(false)
    list.status:SetTextColor(.85, .85, .7)
    list.back = Grid.Button(list.parent, "Back to live items", 132, function()
        if list.onBack then list.onBack() end
    end, 18)
    list.back:SetFrameLevel(list.parent:GetFrameLevel() + 2)
end

local function PaintStatus(list, x, y, width, status)
    if not status then
        if list.status then
            list.status:Hide()
            list.back:Hide()
        end
        return
    end
    StatusWidgets(list)
    list.back:ClearAllPoints()
    list.back:SetPoint("TOPRIGHT", list.parent, "TOPLEFT", x + width, y)
    list.back:Show()
    list.status:ClearAllPoints()
    list.status:SetPoint("TOPLEFT", list.parent, "TOPLEFT", x, y - 2)
    list.status:SetWidth(math.max(40, width - 140))
    list.status:SetText(status)
    list.status:Show()
end

-- The band above the rows at (x, y) of the parent: the status line of the
-- offline view (nil: none) and the column titles.
function List.Band(list, x, y, width, config, spec, status)
    local key = Columns.FitKey(config, width)
    if list.fitKey ~= key then
        Columns.Fit(config, width, list.fit, list.fitScratch)
        list.fitKey = key
    end
    local headerY = y - (status and 21 or 11)
    for i = 1, #list.fit do
        local entry = list.fit[i]
        PaintHeader(Header(list, i), entry, x + entry.x, headerY, spec, config.accentColor)
    end
    for i = #list.fit + 1, #list.headers do list.headers[i]:Hide() end
    PaintStatus(list, x, y, width, status)
end

------------------------------------------------------------------ rows
local function RowEnter(row)
    if not row.offlineID then return end
    GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
    GameTooltip:SetItemByID(row.offlineID)
    if row.offlineNote then GameTooltip:AddLine(row.offlineNote, .8, .8, .8, true) end
    GameTooltip:Show()
end

local function Row(list, index)
    local row = list.rows[index]
    if row then return row end
    row = P.ChildFrame("Frame", list.parent)
    row:SetHeight(ROW_HEIGHT)
    row:SetFrameLevel(list.parent:GetFrameLevel() + 1)
    row:EnableMouse(false)
    row.mouse = false
    row.shade = S.CreateTexture(row, nil, "BACKGROUND")
    row.shade:SetAllPoints(row)
    row.shade:SetColorTexture(1, 1, 1, index % 2 == 0 and .035 or .015)
    row.icon = S.CreateTexture(row, nil, "ARTWORK")
    row.icon:SetSize(32, 32)
    row.icon:SetPoint("LEFT", 3, 0)
    row.icon:Hide()
    row.cells = {}
    row:SetScript("OnEnter", RowEnter)
    row:SetScript("OnLeave", GameTooltip_Hide)
    list.rows[index] = row
    return row
end

local function Cell(row, index)
    local cell = row.cells[index]
    if not cell then
        cell = Grid.Font(row, 12)
        cell:SetWordWrap(false)
        row.cells[index] = cell
    end
    return cell
end

local function QualityColor(cell, quality)
    local r, g, b = 1, 1, 1
    if S.Finite(quality) then
        r, g, b = C_Item.GetItemQualityColor(quality)
        if not S.Finite(r) or not S.Finite(g) or not S.Finite(b) then r, g, b = 1, 1, 1 end
    end
    cell:SetTextColor(r, g, b)
end

local function PaintCells(list, row, data)
    local fit = list.fit
    local relayout = row.fitKey ~= list.fitKey
    for i = 1, #fit do
        local entry, cell = fit[i], Cell(row, i)
        if relayout then
            cell:ClearAllPoints()
            cell:SetPoint("LEFT", row, "LEFT", entry.x, 0)
            cell:SetWidth(entry.width)
            cell:SetJustifyH(LEFT_COLUMNS[entry.column.key] and "LEFT" or "RIGHT")
        end
        cell:SetText(Columns.Text(entry.column.key, data))
        if entry.column.key == "name" then QualityColor(cell, data.item.quality) else cell:SetTextColor(.9, .9, .9) end
        cell:Show()
    end
    for i = #fit + 1, #row.cells do row.cells[i]:Hide() end
    row.fitKey = list.fitKey
end

local function Changed(row, data, item, list)
    return row.item ~= item or row.count ~= data.count or row.version ~= item.version or row.loaded ~= item.loaded
        or row.fitKey ~= list.fitKey or row.level ~= item.listLevel or row.track ~= item.listTrack
        or row.binding ~= item.binding or row.fontEpoch ~= list.fontEpoch
end

local function Remember(row, data, item)
    row.item, row.count, row.version, row.loaded = item, data.count, item.version, item.loaded
    row.level, row.track, row.binding = item.listLevel, item.listTrack, item.binding
end

local function PaintIcon(row, item, note)
    local offline = item.offline == true
    if row.mouse ~= offline then
        row:EnableMouse(offline)
        row.mouse = offline
    end
    row.offlineID = offline and item.itemID or nil
    row.offlineNote = offline and note or nil
    if offline and item.icon then
        if row.iconFile ~= item.icon then
            row.icon:SetTexture(item.icon)
            row.icon:SetDesaturated(false)
            row.iconFile = item.icon
        end
        row.icon:Show()
    else
        row.icon:Hide()
    end
end

-- Line slot of the list (1 first below the band) shows data (a model row) at
-- (x, y) of the parent. A row whose item, count and columns did not change
-- sets no text. note: the tooltip line of an offline row.
function List.PaintRow(list, slot, x, y, width, data, note)
    local row = Row(list, slot)
    if row.x ~= x or row.y ~= y or row.width ~= width then
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", list.parent, "TOPLEFT", x, y + 1)
        row:SetWidth(width)
        row.x, row.y, row.width = x, y, width
    end
    local item = data.item
    if Changed(row, data, item, list) then
        PaintCells(list, row, data)
        Remember(row, data, item)
        row.fontEpoch = list.fontEpoch
    end
    PaintIcon(row, item, note)
    row:Show()
    return row
end

-- Hides the rows from slot on (the rest of the page).
function List.HideRows(list, from)
    for i = from, #list.rows do
        local row = list.rows[i]
        if row:IsShown() then
            if GameTooltip:IsOwned(row) then GameTooltip:Hide() end
            row:Hide()
        end
    end
end

-- Hides every list widget: the grid is shown, or the window closed.
function List.Hide(list)
    List.HideRows(list, 1)
    for i = 1, #list.headers do list.headers[i]:Hide() end
    if list.status then
        list.status:Hide()
        list.back:Hide()
    end
end

-- A changed font repaints every row's text at the next pass.
function List.FontChanged(list, path)
    if list.fontPath == path then return end
    list.fontPath = path
    list.fontEpoch = (list.fontEpoch or 0) + 1
end

List.CELL = CELL

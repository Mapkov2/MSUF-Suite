local _, P = ...
-- One readable snapshot per selected fight. The live meter keeps its own
-- routes, windows and paint schedule.
local D, S, NS = P.DamageMeter, P.Suite, P.NS
local M, T = D.M, D.TYPE
local WIDTH, HEIGHT, PAGE, CELL = 700, 394, 10, 69
local COLUMNS = {
    { T.DamageDone, "Damage", "totalAmount" }, { T.Dps, "DPS", "amountPerSecond" },
    { T.HealingDone, "Healing", "totalAmount" }, { T.Hps, "HPS", "amountPerSecond" },
    { T.Interrupts, "Interrupts", "totalAmount" }, { T.Dispels, "Dispels", "totalAmount" },
    { T.Deaths, "Deaths", "totalAmount" },
}
local panel

local function Readable(value)
    return S.Public(value) and type(value) == "table" and canaccesstable and canaccesstable(value)
end

local function CollectColumn(id, column, rows, byGUID)
    local mode = COLUMNS[column]
    if mode[1] == nil then return end
    local session = C_DamageMeter.GetCombatSessionFromID(id, mode[1])
    local list = Readable(session) and session.combatSources
    if not Readable(list) then return end
    local count = #list
    if not S.Finite(count) then return end
    for index = 1, math.min(count, 80) do
        local source = list[index]
        if Readable(source) then
            local guid, name = S.PublicText(source.sourceGUID), S.PublicText(source.name)
            local number = source[mode[3]]
            if guid and guid:sub(1, 7) == "Player-" and name and S.Finite(number) and number >= 0 then
                local row = byGUID[guid]
                if not row then
                    row = { guid = guid, name = name }
                    byGUID[guid], rows[#rows + 1] = row, row
                end
                if row[column] == nil then row[column] = number end
            end
        end
    end
end

function D.ReadFightSummary(id)
    if M.inCombat or NS.IsCombatLocked() or not (C_DamageMeter and C_DamageMeter.GetCombatSessionFromID) or not S.Finite(id) then return end
    local rows, byGUID = {}, {}
    for column = 1, #COLUMNS do CollectColumn(id, column, rows, byGUID) end
    return rows
end

local function Sort()
    local column, ascending = panel.sortColumn, panel.ascending
    table.sort(panel.items, function(a, b)
        local x, y = a[column], b[column]
        if x == nil and y ~= nil then return false end
        if y == nil and x ~= nil then return true end
        if x ~= y then
            if ascending then return x < y end
            return x > y
        end
        if a.name ~= b.name then return a.name < b.name end
        return a.guid < b.guid
    end)
end

local function Paint()
    local offset = (panel.page - 1) * PAGE
    local total = #panel.items
    for index, row in ipairs(panel.rows) do
        local item = panel.items[offset + index]
        row:SetShown(item ~= nil)
        if item then
            row.name:SetText(D.Short(item.name))
            for column, cell in ipairs(row.cells) do
                local value = item[column]
                cell:SetText(value ~= nil and D.Abbreviate(value) or "—")
            end
        end
    end
    for column, header in ipairs(panel.columns) do
        local suffix = panel.sortColumn == column and (panel.ascending and " ▲" or " ▼") or ""
        header:SetText(header.caption .. suffix)
    end
    panel.empty:SetShown(total == 0)
    panel.prev:SetEnabled(panel.page > 1)
    panel.more:SetEnabled(offset + PAGE < total)
end

local function Select(segment)
    if not segment or M.inCombat or NS.IsCombatLocked() then return end
    panel.segment:SetText(segment.label)
    panel.items, panel.page = D.ReadFightSummary(segment.id) or {}, 1
    Sort()
    Paint()
end

local function Button(parent, width, title, click)
    local button = NS.HostBridge.MenuButton(parent, width, 24) or S.CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    button:SetSize(width, 24)
    button:SetText(title)
    button:SetScript("OnClick", click)
    return button
end

local function CreateRows(window)
    for index = 1, PAGE do
        local row = S.CreateFrame("Frame", nil, window)
        row:SetPoint("TOPLEFT", 14, -103 - (index - 1) * 24)
        row:SetPoint("TOPRIGHT", -14, -103 - (index - 1) * 24)
        row:SetHeight(22)
        if index % 2 == 0 then
            local bg = row:CreateTexture(nil, "BACKGROUND")
            bg:SetAllPoints(row)
            bg:SetColorTexture(.4, .6, .7, .10)
        end
        local name = S.QoLLabel(row, "", 12)
        name:SetPoint("LEFT", 7, 0)
        name:SetWidth(WIDTH - 28 - #COLUMNS * CELL - 15)
        name:SetMaxLines(1)
        name:SetJustifyH("LEFT")
        row.name, row.cells = name, {}
        for column = 1, #COLUMNS do
            local cell = S.QoLLabel(row, "", 12)
            cell:SetPoint("RIGHT", row, "RIGHT", -10 - (#COLUMNS - column) * CELL, 0)
            cell:SetJustifyH("RIGHT")
            row.cells[column] = cell
        end
        window.rows[index] = row
    end
end

local function OpenSegments(button)
    S.ContextMenu(button, function(_, menu)
        menu:SetScrollMode(280)
        for _, segment in ipairs(panel.segments) do menu:CreateButton(segment.label, Select, segment) end
    end)
end

local function CreatePanel()
    local window = S.QoLWindow(WIDTH, HEIGHT, "Fight summary", 16, true)
    window.rows, window.columns = {}, {}
    window.close:SetScript("OnClick", function() D.CloseFightSummary() end)
    window.segment = Button(window, 216, S.Text("Choose a fight"), OpenSegments)
    window.segment:SetPoint("TOPLEFT", 14, -46)
    for column, def in ipairs(COLUMNS) do
        local key = column
        local caption = S.Text(def[2])
        local header = Button(window, CELL - 2, caption, function()
            panel.ascending = panel.sortColumn == key and not panel.ascending or false
            panel.sortColumn, panel.page = key, 1
            Sort()
            Paint()
        end)
        header.caption = caption
        header:SetPoint("TOPRIGHT", -14 - (#COLUMNS - column) * CELL, -76)
        window.columns[column] = header
    end
    CreateRows(window)
    window.empty = S.QoLLabel(window, S.Text("No public player totals for this fight."), 13)
    window.empty:SetPoint("CENTER", 0, 14)
    window.more = Button(window, 82, S.Text("Next"), function() panel.page = panel.page + 1 Paint() end)
    window.more:SetPoint("BOTTOMRIGHT", -14, 12)
    window.prev = Button(window, 82, S.Text("Previous"), function() panel.page = panel.page - 1 Paint() end)
    window.prev:SetPoint("RIGHT", window.more, "LEFT", -6, 0)
    return window
end

function D.CloseFightSummary()
    if not panel or not panel:IsShown() then return end
    S.CloseOwnedContextMenu(panel.segment)
    panel:Hide()
    panel.items, panel.segments = {}, {}
end

function D.OpenFightSummary(win)
    if not M.active or M.inCombat or NS.IsCombatLocked() then return end
    panel = panel or CreatePanel()
    local width = UIParent:GetWidth()
    if S.Finite(width) and width > 20 then panel:SetScale(math.min(1, (width - 20) / WIDTH)) end
    panel.segments = D.CompareSegments() or {}
    panel.items, panel.page, panel.sortColumn, panel.ascending = {}, 1, 2, false
    local selected = panel.segments[1]
    local id = win and win.sessionID
    for _, segment in ipairs(panel.segments) do
        if S.Finite(id) and segment.id == id then
            selected = segment
            break
        end
    end
    panel.segment:SetEnabled(selected ~= nil)
    if selected then
        Select(selected)
    else
        panel.segment:SetText(S.Text("Choose a fight"))
        Paint()
    end
    panel:Show()
end

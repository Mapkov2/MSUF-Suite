local _, P = ...
local NS, S, Model = P.NS, P.Suite, P.InventoryModel
local Editor = { selected = 1, rows = {} }
P.InventoryEditor = Editor
local Refresh

local function ClearSession()
    Editor.profile, Editor.open = nil, nil
    NS.Registry.RemoveListener(Editor)
end

local function ProfileChanged(_, domain)
    if domain == "profile" then Editor.Hide() end
end

local function Label(parent, text, x, y)
    local label = S.CreateFontString(parent, nil, "OVERLAY")
    S.SetFont(label, S.GlobalFontPath(), 12, "OUTLINE")
    label:SetPoint("TOPLEFT", x, y)
    label:SetText(S.Text(text))
    return label
end

local function Input(parent, x, y, width)
    local edit = S.CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
    edit:SetSize(width, 24)
    edit:SetPoint("TOPLEFT", x, y)
    edit:SetAutoFocus(false)
    edit:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    return edit
end

local function Action(parent, text, x, y, width, callback)
    local button = S.CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    button:SetSize(width, 24)
    button:SetPoint("TOPLEFT", x, y)
    button:SetText(S.Text(text))
    button:SetScript("OnClick", callback)
    return button
end

local function Store()
    if not Editor.open or NS.IsCombatLocked() or Editor.profile ~= NS.DB then
        Editor.Hide()
        return false
    end
    if Editor.editPins then
        local state = S.ModuleState("bags")
        if not state then return false end
        state.pinned = Editor.categories[1] and Editor.categories[1].items or {}
        P.InventoryView.Request()
        return true
    end
    local encoded = Model.EncodeCategories(Editor.categories)
    return encoded and S.Set("bags", "customCategories", encoded)
end

local function Select(button)
    Editor.selected = button.index
    Refresh()
end

local function ItemText(items)
    local ids = {}
    for id, enabled in pairs(items) do if enabled then ids[#ids + 1] = id end end
    table.sort(ids)
    return table.concat(ids, ", ")
end

Refresh = function()
    Editor.status:SetText("")
    if Editor.editPins then
        local state = S.ModuleState("bags")
        local items = {}
        for id, enabled in pairs(state.pinned or {}) do items[id] = enabled end
        Editor.categories = { { name = S.Text("Pinned items"), enabled = true, items = items } }
        Editor.selected = 1
    else
        Editor.categories = Model.DecodeCategories(S.Config("bags").customCategories)
    end
    Editor.selected = math.min(Editor.selected, #Editor.categories)
    for i = 1, #Editor.rows do Editor.rows[i]:Hide() end
    for i = 1, #Editor.categories do
        local row = Editor.rows[i]
        if not row then
            row = Action(Editor.child, "", 0, -(i - 1) * 27, 332, Select)
            Editor.rows[i] = row
        end
        row.index = i
        row:SetText((i == Editor.selected and "> " or "") .. Editor.categories[i].name)
        row:Show()
    end
    Editor.child:SetHeight(math.max(27, #Editor.categories * 27))
    local category = Editor.categories[Editor.selected]
    Editor.name:SetText(category and category.name or "")
    Editor.items:SetText(category and ItemText(category.items) or "")
    Editor.enabled:SetChecked(not category or category.enabled)
    Editor.save:SetEnabled(category ~= nil)
    Editor.remove:SetEnabled(category ~= nil)
    Editor.up:SetEnabled(Editor.selected > 1)
    Editor.down:SetEnabled(category ~= nil and Editor.selected < #Editor.categories)
    Editor.add:SetEnabled(not Editor.editPins)
    Editor.name:SetEnabled(not Editor.editPins)
    Editor.enabled:SetEnabled(not Editor.editPins)
end

local function NewCategory()
    if NS.IsCombatLocked() or Editor.editPins or #Editor.categories >= 24 then return end
    Editor.categories[#Editor.categories + 1] = { name = S.Text("New category"), enabled = true, items = {} }
    Editor.selected = #Editor.categories
    if Store() then
        Refresh()
        Editor.name:SetFocus()
        Editor.name:HighlightText()
    end
end

local function SaveCategory()
    local category = Editor.categories[Editor.selected]
    if not category or NS.IsCombatLocked() then return end
    local name = Editor.name:GetText():gsub("[\r\n]", " ")
    if not name:find("%S") then
        Editor.status:SetText(S.Text("Enter a category name."))
        return
    end
    local input, count = Editor.items:GetText(), 0
    local invalid = input:find("[^%d, ]")
    for value in input:gmatch("%d+") do
        count = count + 1
        if tonumber(value) <= 0 or tonumber(value) >= 2147483647 or count > 500 then invalid = true end
    end
    if invalid then
        Editor.status:SetText(S.Text("Use up to 500 positive item IDs, separated by commas."))
        return
    end
    local parsed = Model.DecodeCategories("1|x|" .. input)
    if #parsed ~= 1 then return end
    category.name, category.items, category.enabled = name, parsed[1].items, Editor.enabled:GetChecked() == true
    if Store() then Refresh() else Editor.status:SetText(S.Text("Category data is full. Remove unused item IDs first.")) end
end

local function RemoveCategory()
    if NS.IsCombatLocked() or not Editor.categories[Editor.selected] then return end
    table.remove(Editor.categories, Editor.selected)
    if Store() then Refresh() end
end

local function MoveCategory(button)
    local from, to = Editor.selected, Editor.selected + button.delta
    if NS.IsCombatLocked() or not Editor.categories[to] then return end
    Editor.categories[from], Editor.categories[to] = Editor.categories[to], Editor.categories[from]
    Editor.selected = to
    if Store() then Refresh() end
end

local function Create()
    local frame = P.GridView.Window("MSUFSuiteBagCategories", 410, 485, "Bag categories")
    Editor.frame = frame
    frame:HookScript("OnHide", ClearSession)
    Label(frame, "Name", 18, -40)
    Editor.name = Input(frame, 24, -61, 357)
    Editor.name:SetMaxLetters(64)
    Label(frame, "Item IDs (or drop items onto the sidebar)", 18, -93)
    Editor.items = Input(frame, 24, -115, 357)
    Editor.items:SetMaxLetters(5500)
    Editor.enabled = S.CreateFrame("CheckButton", nil, frame, "UICheckButtonTemplate")
    Editor.enabled:SetPoint("TOPLEFT", 15, -147)
    Label(frame, "Show this category", 48, -153)
    Editor.save = Action(frame, "Save", 18, -185, 80, SaveCategory)
    Editor.add = Action(frame, "New", 104, -185, 80, NewCategory)
    Editor.remove = Action(frame, "Delete", 190, -185, 80, RemoveCategory)
    Editor.up = Action(frame, "Up", 278, -185, 50, MoveCategory)
    Editor.up.delta = -1
    Editor.down = Action(frame, "Down", 333, -185, 59, MoveCategory)
    Editor.down.delta = 1
    local scroll = S.CreateFrame("ScrollFrame", nil, frame, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 20, -226)
    scroll:SetPoint("BOTTOMRIGHT", -40, 42)
    Editor.child = S.CreateFrame("Frame", nil, scroll)
    Editor.child:SetSize(340, 27)
    scroll:SetScrollChild(Editor.child)
    Label(frame, "Deleting a category never deletes its items.", 18, -452)
    Editor.status = Label(frame, "", 18, -470)
    Editor.status:SetWidth(375)
    Editor.status:SetTextColor(1, 0.55, 0.2)
end

function Editor.Show(pinned)
    if NS.IsCombatLocked() then return end
    Editor.editPins = pinned == true
    if not Editor.frame then Create() end
    Editor.profile, Editor.open = NS.DB, true
    NS.Registry.AddListener(Editor, ProfileChanged)
    Refresh()
    Editor.frame:Show()
end

function Editor.ShowPinned()
    Editor.Show(true)
end

function Editor.Hide()
    ClearSession()
    if Editor.frame then Editor.frame:Hide() end
end

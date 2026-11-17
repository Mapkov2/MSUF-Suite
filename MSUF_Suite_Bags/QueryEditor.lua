local _, P = ...
local NS, S = P.NS, P.Suite
local Tree = P.QueryTree
-- The visual search builder: AND/OR groups of filters, nested up to four
-- levels (QueryTree.lua), written into the smart search text the bag and
-- bank search boxes, saved searches and category rules already use. Opened
-- from the Filters menu (SmartSearch.lua) for the box that menu belongs to.
-- Apply puts the text in that box; nothing else changes until then. The
-- builder closes in combat and when the profile changes.
local Editor = { rows = {}, entries = {} }
P.QueryEditor = Editor
local ROW, INDENT, WIDTH = 30, 18, 556
local Refresh, Preview

local OPS = { ["="] = "equals", [">"] = "above", ["<"] = "below", [">="] = "at least", ["<="] = "at most",
    range = "between", name = "named" }
local FLAGS = { equipment = "Equipment", bound = "Bound", boe = "Bind on Equip", wue = "Warbound until equipped",
    warbound = "Warbound", junk = "Junk", quest = "Quest item", set = "In an equipment set", locked = "Locked" }
local MODES = { ["and"] = "All of these (AND)", ["or"] = "Any of these (OR)" }

function Editor.Close()
    if Editor.frame then Editor.frame:Hide() end
end

local function ClearSession()
    Editor.open, Editor.profile, Editor.target = nil, nil, nil
    NS.Registry.RemoveListener(Editor)
end

local function ProfileChanged(_, domain)
    if domain == "profile" then Editor.Close() end
end

-- Every action first checks that the builder may still act.
local function Usable()
    if Editor.open and not NS.InCombat() and Editor.profile == NS.DB then return true end
    Editor.Close()
    return false
end

local function Status(text, good)
    Editor.status:SetText(text and S.Text(text) or "")
    if good then Editor.status:SetTextColor(.5, .9, .5) else Editor.status:SetTextColor(1, .55, .2) end
end

------------------------------------------------------------------ menus
local function Menu(owner, build)
    if not Usable() then return end
    P.BagFilterMenu.Show(owner, function(_, menu) build(menu) end)
end

-- Changes a filter's field in place: its parent keeps the same table.
local function SetField(term, field)
    local fresh = Tree.Term(field, nil, nil, term.negate)
    local before = Tree.byField[term.field]
    if before and Tree.byField[field].kind == before.kind and before.kind ~= "flag" then
        fresh.value = term.value
        if before.kind == "number" then fresh.op = term.op end
    end
    term.field, term.op, term.value = fresh.field, fresh.op, fresh.value
end

-- A menu choice that sets one key of a filter, then repaints.
local function Setter(term, key, value)
    return function()
        if not Usable() then return end
        term[key] = value
        Refresh()
    end
end

local function FieldClicked(button)
    local term = button.row.node
    Menu(button, function(menu)
        menu:CreateTitle(S.Text("Filter by"))
        for i = 1, #Tree.FIELDS do
            local field = Tree.FIELDS[i]
            menu:CreateButton(S.Text(field.label), function()
                if not Usable() then return end
                SetField(term, field.key)
                Refresh()
            end)
        end
    end)
end

local function OpClicked(button)
    local term = button.row.node
    local spec = Tree.byField[term.field]
    Menu(button, function(menu)
        menu:CreateTitle(S.Text("Compare"))
        for i = 1, #Tree.NUMBER_OPS do
            local op = Tree.NUMBER_OPS[i]
            menu:CreateButton(S.Text(OPS[op]), Setter(term, "op", op))
        end
        if spec and spec.named then menu:CreateButton(S.Text(OPS.name), Setter(term, "op", "name")) end
    end)
end

local function FlagClicked(button)
    local term = button.row.node
    Menu(button, function(menu)
        menu:CreateTitle(S.Text("Is"))
        for i = 1, #Tree.FLAGS do
            local flag = Tree.FLAGS[i]
            if not (Tree.RETAIL_FLAGS[flag] and NS.Client.isForever) then
                menu:CreateButton(S.Text(FLAGS[flag]), Setter(term, "value", flag))
            end
        end
    end)
end

------------------------------------------------------------------ tree actions
local function TooLarge()
    Status("Use at most 40 filters and groups, nested four levels deep.")
end

local function AddChild(button, child)
    if not Usable() then return end
    local entry = button.row.entry
    if not Tree.Add(Editor.root, entry.node, child, entry.depth) then return TooLarge() end
    Refresh()
end

local function AddTerm(button)
    AddChild(button, Tree.Term("text"))
end

-- A new group starts with one filter and the other mode than its parent.
local function AddGroup(button)
    local entry = button.row.entry
    local group = Tree.Group(entry.node.mode == "and" and "or" or "and")
    group.children[1] = Tree.Term("text")
    AddChild(button, group)
end

local function RemoveClicked(button)
    if not Usable() then return end
    local entry = button.row.entry
    if entry.parent then Tree.Remove(entry.parent, entry.node) end
    Refresh()
end

local function ModeClicked(button)
    if not Usable() then return end
    local group = button.row.node
    group.mode = group.mode == "and" and "or" or "and"
    Refresh()
end

local function NotClicked(check)
    if not Usable() then return end
    check.row.node.negate = check:GetChecked() == true
    Preview()
end

local function ValueChanged(edit, user)
    local term = edit.row and edit.row.node
    if not user or not term or term.kind ~= "term" then return end
    term.value = edit:GetText()
    Preview()
end

------------------------------------------------------------------ rows
local GROUP_WIDGETS, TERM_WIDGETS = { "mode", "addTerm", "addGroup" }, { "negate", "field", "op", "value", "flag" }

local function Widget(row, kind, label, width, action, x)
    local button = P.BagWidgets.Button(row, label, width, action, 24)
    button:ClearAllPoints()
    if kind == "right" then
        button:SetPoint("TOPRIGHT", row, "TOPRIGHT", 0, -3)
    else
        button:SetPoint("TOPLEFT", row, "TOPLEFT", x, -3)
    end
    button.row = row
    return button
end

local function CreateRow(index)
    local row = P.ChildFrame("Frame", Editor.child)
    row:SetHeight(ROW)
    row:SetFrameLevel(Editor.child:GetFrameLevel() + 1)
    row.negate = P.BagWidgets.Check(row, 0, -3, "Not")
    row.negate.row = row
    row.negate:HookScript("OnClick", NotClicked)
    row.field = Widget(row, "left", "", 132, FieldClicked, 58)
    row.op = Widget(row, "left", "", 86, OpClicked, 194)
    row.value = P.BagWidgets.Input(row, 284, -3, 166)
    row.value.row = row
    row.value:SetScript("OnTextChanged", ValueChanged)
    row.flag = Widget(row, "left", "", 166, FlagClicked, 284)
    row.mode = Widget(row, "left", "", 160, ModeClicked, 0)
    row.addTerm = Widget(row, "left", "Add filter", 92, AddTerm, 166)
    row.addGroup = Widget(row, "left", "Add group", 92, AddGroup, 262)
    row.remove = Widget(row, "right", "Remove", 70, RemoveClicked)
    Editor.rows[index] = row
    return row
end

local function ShowAll(row, keys, shown)
    for i = 1, #keys do row[keys[i]]:SetShown(shown) end
end

local function PaintGroup(row, entry)
    local group = entry.node
    row.mode:SetText(S.Text(MODES[group.mode]))
    row.addGroup:SetEnabled(entry.depth < Tree.MAX_DEPTH)
    ShowAll(row, GROUP_WIDGETS, true)
    ShowAll(row, TERM_WIDGETS, false)
end

local function PaintValue(row, term, spec)
    local kind = spec and spec.kind or "text"
    row.op:SetShown(kind == "number")
    if kind == "number" then row.op:SetText(S.Text(OPS[term.op] or OPS["="])) end
    row.flag:SetShown(kind == "flag")
    row.value:SetShown(kind ~= "flag")
    if kind == "flag" then
        row.flag:SetText(S.Text(FLAGS[term.value] or FLAGS.equipment))
    elseif row.value:GetText() ~= (term.value or "") then
        row.value:SetText(term.value or "")
    end
    row.value:SetMaxLetters(kind == "number" and 24 or 64)
end

local function PaintTerm(row, entry)
    local term = entry.node
    local spec = Tree.byField[term.field]
    row.negate:SetChecked(term.negate == true)
    row.field:SetText(spec and S.Text(spec.label) or S.Text("Typed filter"))
    PaintValue(row, term, spec)
    row.negate:Show()
    row.field:Show()
    ShowAll(row, GROUP_WIDGETS, false)
end

local function PaintRow(index, entry)
    local row = Editor.rows[index] or CreateRow(index)
    row.entry, row.node = entry, entry.node
    local indent = (entry.depth - 1) * INDENT
    row:ClearAllPoints()
    row:SetPoint("TOPLEFT", Editor.child, "TOPLEFT", indent, -(index - 1) * ROW)
    row:SetWidth(WIDTH - indent)
    if entry.node.kind == "group" then PaintGroup(row, entry) else PaintTerm(row, entry) end
    row.remove:SetShown(entry.parent ~= nil)
    row:Show()
end

------------------------------------------------------------------ preview and actions
local function Categories()
    return #P.InventoryModel.DecodeCategories(S.Config("bags").customCategories)
end

Preview = function()
    local text, why = Tree.Text(Editor.root)
    if text and not Editor.text:HasFocus() then Editor.text:SetText(text) end
    Editor.current = text
    if why then Status(why) elseif Editor.status.ok ~= true then Status(nil) end
    Editor.status.ok = nil
    local rules = NS.InventoryRules
    local terms = text and text ~= "" and rules.HasTerms(rules.Compile(text))
    Editor.apply:SetEnabled(text ~= nil and Editor.target ~= nil)
    Editor.save:SetEnabled(terms == true)
    Editor.category:SetEnabled(terms == true and Categories() < 24)
end

Refresh = function()
    Tree.Flatten(Editor.root, Editor.entries)
    for i = 1, #Editor.entries do PaintRow(i, Editor.entries[i]) end
    for i = #Editor.entries + 1, #Editor.rows do Editor.rows[i]:Hide() end
    Editor.child:SetHeight(math.max(ROW, #Editor.entries * ROW))
    P.BagWidgets.UpdateScroll(Editor.scroll)
    Preview()
end

local function Done(text)
    Status(text, true)
    Editor.status.ok = true
end

local function Apply()
    if not Usable() or not Editor.current or not Editor.target then return end
    if NS.IsCombatLocked() then return end
    Editor.target:SetText(Editor.current)
    Done("The search box now holds this search.")
end

local SAVE_REASONS = { saved = "This search is saved already.", full = "Twelve searches are saved. Remove one first.",
    invalid = "Check the search filters." }

local function Save()
    if not Usable() or not Editor.current then return end
    local state = S.ModuleState("bags")
    if not state then return end
    local ok, why = P.SavedSearches.Add(P.SavedSearches.List(state), Editor.current)
    if ok then Done("Search saved.") else Status(SAVE_REASONS[why] or SAVE_REASONS.invalid) end
end

local function MakeCategory()
    if not Usable() or not Editor.current then return end
    P.InventoryEditor.FromSearch(Editor.current)
end

local function Import()
    if not Usable() then return end
    Editor.root = Tree.Parse(Editor.text:GetText())
    Editor.text:ClearFocus()
    Refresh()
end

local function Clear()
    if not Usable() then return end
    Editor.root = Tree.Group("and")
    Editor.text:SetText("")
    Refresh()
end

------------------------------------------------------------------ the window
local function Label(text, x, y)
    local label = S.CreateFontString(Editor.frame, nil, "OVERLAY")
    S.SetFont(label, S.GlobalFontPath(), 12, "OUTLINE")
    label:SetPoint("BOTTOMLEFT", x, y)
    label:SetText(S.Text(text))
    return label
end

local function Action(text, x, width, callback)
    local button = P.BagWidgets.Button(Editor.frame, text, width, callback, 24)
    button:ClearAllPoints()
    button:SetPoint("BOTTOMLEFT", x, 16)
    return button
end

local function Create()
    local frame = P.BagWidgets.Window("MSUFSuiteBagSearchBuilder", 600, 540, S.Text("Search builder"))
    Editor.frame = frame
    frame:HookScript("OnHide", ClearSession)
    frame:RegisterEvent("PLAYER_REGEN_DISABLED")
    frame:SetScript("OnEvent", Editor.Close)
    Editor.scroll, Editor.child = P.BagWidgets.Scroll(frame, WIDTH)
    Editor.scroll:SetPoint("TOPLEFT", 16, -44)
    Editor.scroll:SetPoint("BOTTOMRIGHT", -28, 164)
    Label("Search text (press Enter to turn typed text into filters)", 18, 132)
    Editor.text = P.BagWidgets.Input(frame, 0, 0, 562)
    Editor.text:ClearAllPoints()
    Editor.text:SetPoint("BOTTOMLEFT", 20, 102)
    Editor.text:SetMaxBytes(Tree.MAX_LENGTH)
    Editor.text:SetScript("OnEnterPressed", Import)
    Editor.status = Label("", 18, 78)
    Editor.status:SetWidth(562)
    Editor.status:SetWordWrap(true)
    Editor.apply = Action("Apply search", 18, 112, Apply)
    Editor.save = Action("Save search", 136, 104, Save)
    Editor.category = Action("Create category", 246, 124, MakeCategory)
    Editor.import = Action("Read text", 376, 96, Import)
    Editor.clear = Action("Clear", 478, 86, Clear)
end

-- Opens the builder for target, a search box (or a category's rule box): its
-- text becomes the tree to edit.
function Editor.Open(target)
    if NS.InCombat() then return end
    if not Editor.frame then Create() end
    Editor.target, Editor.profile, Editor.open = target, NS.DB, true
    NS.Registry.AddListener(Editor, ProfileChanged)
    local text = target and target:GetText() or ""
    Editor.root = Tree.Parse(text)
    Editor.text:SetText(text)
    Status(nil)
    Refresh()
    Editor.frame:Show()
end

local _, P = ...
local NS, S = P.NS, P.Suite
local Search = {}
P.InventorySearch = Search
local Saved = P.SavedSearches
local PRESETS = {
    { "All items", "" }, { "Equipment", "is:equipment" }, { "Junk", "quality=0" },
    { "Rare equipment", "is:equipment quality=3" }, { "Epic equipment", "is:equipment quality=4" },
    { "Unbound items", "!is:bound" }, { "Quest items", "is:quest" },
    { "Bind on Equip", "is:boe" }, { "Warbound items", "is:warbound | is:wue" },
}

-- A saved search is the player's own text; the menu would read a "|" in it as
-- an escape code.
local function Shown(text)
    return (text:gsub("|", "||"))
end

local function Apply(edit, text)
    if not NS.IsCombatLocked() then edit:SetText(text) end
end

-- Saved searches: apply one, save what the box holds now, or remove one.
local function AddSaved(menu, edit)
    local state = S.ModuleState("bags")
    if not state then return end
    local list = Saved.List(state)
    menu:CreateDivider()
    if #list > 0 then
        menu:CreateTitle(S.Text("Saved searches"))
        for i = 1, #list do
            local text = list[i]
            menu:CreateButton(Shown(text), function() Apply(edit, text) end)
        end
    end
    local save = menu:CreateButton(S.Text("Save this search"), function() Saved.Add(list, edit:GetText()) end)
    save:SetEnabled((Saved.CanAdd(list, edit:GetText())))
    if #list > 0 then
        local remove = menu:CreateButton(S.Text("Remove a saved search"))
        for i = 1, #list do remove:CreateButton(Shown(list[i]), function() Saved.Remove(list, i) end) end
    end
end

function Search.Menu(button, edit)
    S.ContextMenu(button, function(_, menu)
        menu:CreateTitle(S.Text("Smart search presets"))
        for i = 1, #PRESETS do
            local preset = PRESETS[i]
            menu:CreateButton(S.Text(preset[1]), function() Apply(edit, preset[2]) end)
        end
        AddSaved(menu, edit)
    end)
end

-- Where the bag view puts the box and its Filters button.
local function PlaceInBag(edit, button)
    edit:SetPoint("TOPLEFT", 18, -91)
    edit:SetPoint("TOPRIGHT", -104, -91)
    button:SetPoint("TOPRIGHT", -12, -91)
end

-- The smart search box of a view: its text lands in view.smartQuery and
-- request() asks for a new pass. parent and place default to the bag view's
-- chrome and position; the bank view passes its own.
function Search.Create(view, request, parent, place)
    parent = parent or view.chrome
    local edit = P.ChildFrame("EditBox", parent, "InputBoxInstructionsTemplate")
    edit:SetHeight(23)
    edit:SetAutoFocus(false)
    edit:SetMaxBytes(512)
    edit.Instructions:SetText(S.Text("Smart search: name, quality>=3, !is:bound"))
    -- What is typed in combat is kept for the view, which builds on it when
    -- combat ends (both views repaint on PLAYER_REGEN_ENABLED).
    edit:SetScript("OnTextChanged", function(self)
        local query = self:GetText()
        local compiled = NS.InventoryRules.Compile(query)
        self:SetTextColor(compiled and 1 or 1, compiled and 1 or .4, compiled and 1 or .3)
        view.smartQuery, view.scroll = query, 0
        if not NS.IsCombatLocked() then request() end
    end)
    edit:SetScript("OnEscapePressed", function(self) self:SetText("") self:ClearFocus() end)
    local button = P.GridView.Button(parent, "Filters", 80, function(self) Search.Menu(self, edit) end)
    place = place or PlaceInBag
    place(edit, button)
    view.smartSearch = edit
end

function Search.RuleControls(editor, label, input, action)
    label(editor.frame, "Automatic rule (optional)", 18, -176)
    editor.rule = input(editor.frame, 24, -197, 263)
    editor.rule:SetMaxBytes(512)
    action(editor.frame, "Filters", 300, -197, 90, function(self) Search.Menu(self, editor.rule) end)
end

local _, P = ...
-- Cooldown manager page, per-spell popover: what the player types into its
-- boxes (spell and icon file ID inputs, and the number a value click opens).
-- Enter and leaving the box store valid input once; Escape restores the
-- stored value. Invalid input keeps its text and shows why, except a number,
-- which goes back to its stored value. The popover stores what is left when
-- it closes, scope or entry change.
local Page = P.CDMPage
if not Page then return end
local floor, max, min = math.floor, math.max, math.min

local function StoredText(edit)
    local value = Page.SpellField(Page.popover.key, edit.row.field.key)
    if value == nil then return "" end
    local name = edit.inputKind == "spell" and C_Spell.GetSpellName(value)
    return name or tostring(value)
end
-- A repaint shows the stored value, never over typed text.
function Page.PaintPopoverInput(edit, text)
    if edit.dirty or edit:HasFocus() then return end
    edit.savedText = text
    edit:SetText(text)
end
-- valid, value: the value to store (nil clears) or why the text is invalid.
local function InputValue(edit, text)
    local field, kind = edit.row.field, edit.inputKind
    if kind == "number" then
        local value = tonumber(text)
        if not value or value ~= value then return false, "Invalid value." end
        value = max(0, min(field.max, floor(value / field.step + 0.5) * field.step))
        -- 0 turns an "Off" field off: cleared, or stored by a specialization.
        if field.off and value == 0 and not Page.spellSpecScope then return true, nil end
        return true, value
    end
    if text == "" then return true, nil end
    -- A bar name: plain text, no escape sequences.
    if kind == "text" then
        if text:find("[|%c]") then return false, "A name cannot contain the | character." end
        return true, text:sub(1, 40)
    end
    if kind == "spell" then
        local id = C_Spell.GetSpellIDForSpellIdentifier(text)
        if Page.Public(id) and type(id) == "number" and id > 0 and id < 2147483648 then return true, id end
        return false, "Enter a valid talent or spell name or ID."
    end
    local id = tonumber((text:gsub("%s", "")))
    if id and id >= 1 and id < 2147483648 and id == floor(id) then return true, id end
    return false, "Enter a texture file ID."
end
-- A number's box closes again and shows its value button.
local function Close(edit)
    if edit.inputKind ~= "number" then return end
    edit:Hide()
    edit.row.value:Show()
end
-- committing: this box is being written or reset; its focus loss is no edit.
local function Restore(edit)
    edit.dirty, edit.committing = nil, true
    edit.savedText = StoredText(edit)
    edit:SetText(edit.savedText)
    edit:ClearFocus()
    edit.committing = nil
    Close(edit)
end
-- enter: Enter keeps an invalid number open for correction. Returns false
-- while invalid text stays in the box.
local function Commit(edit, enter)
    if edit.committing then return end
    local text = (edit:GetText() or ""):match("^%s*(.-)%s*$")
    if not edit.dirty and text == edit.savedText then
        Close(edit)
        return true
    end
    local valid, value = InputValue(edit, text)
    if not valid then
        Page.Fail(value)
        if edit.inputKind == "number" and not enter then
            Restore(edit)
            return true
        end
        edit.dirty = true
        return false
    end
    -- A settings write repaints synchronously; mark this transaction first.
    edit.committing, edit.dirty, edit.savedText = true, nil, text
    local ok, reason = Page.SetSpellField(Page.popover.key, edit.row.field.key, value)
    edit.committing = nil
    if not ok then
        edit.dirty = true
        Page.Fail(reason)
        return false
    end
    Close(edit)
    return true
end
local function Enter(edit)
    if Commit(edit, true) then edit:ClearFocus() end
end
local function Changed(edit, userInput)
    if userInput then edit.dirty = true end
end
function Page.InitPopoverInput(edit, kind)
    edit.inputKind = kind
    edit:SetScript("OnEnterPressed", Enter)
    edit:SetScript("OnEditFocusLost", Commit)
    edit:SetScript("OnEscapePressed", Restore)
    edit:SetScript("OnTextChanged", Changed)
end
-- Stores what was typed into the open popover; discard (another entry
-- opens) then empties every box. A closed popover stored its valid input
-- when it closed; what is left there is invalid and reported already.
-- Returns false while invalid text stays.
function Page.FlushPopoverInputs(discard)
    local pop = Page.popover
    if not pop then return true end
    local valid, store = true, not discard or pop:IsShown()
    for _, row in pairs(pop.rows) do
        local edit = row.edit
        if edit then
            if store and row:IsShown() and edit:IsShown() and (edit.dirty or edit:GetText() ~= edit.savedText)
                and Commit(edit) == false then
                valid = false
            end
            edit.committing = true
            edit:ClearFocus()
            edit.committing = nil
            Close(edit)
            if discard then
                edit.dirty, edit.savedText = nil, ""
                edit:SetText("")
            end
        end
    end
    return valid
end
-- A click on a number's value opens its box in place (one per row, made on
-- the first click), holding the value shown.
function Page.BeginPopoverNumber(self)
    local row = self.row
    local edit = row.edit
    if not edit then
        edit = Page.NewPopoverEdit(row, "number", 36)
        edit:SetPoint("LEFT", self, "LEFT", 0, 0)
    end
    local value = Page.SpellField(Page.popover.key, row.field.key)
    edit.dirty, edit.savedText = nil, tostring(value == nil and row.shownNumber or value)
    edit:SetText(edit.savedText)
    self:Hide()
    edit:Show()
    edit:SetFocus()
    edit:HighlightText()
end

local _, P = ...
-- Cooldown manager page, pooled editor: the per-spell popover. Its sound rows
-- open the sound picker of CooldownManagerSounds.lua.
local Page = P.CDMPage
if not Page then return end
local W, T, Tr = P.W, P.T, P.Tr
local CDM = P.Suite.CDM
local FAMILY = CDM.FAMILY
local ID = Page.ID
local SLOTS, KEYS = CDM.SLOTS, CDM.KEYS
local CROP_MIN, CROP_MAX = Page.CROP_MIN, Page.CROP_MAX
local floor, max, min, format = math.floor, math.max, math.min, string.format
local Public, SetIcon, SetRaw = Page.Public, Page.SetIcon, Page.SetRaw
local Accent, TextColor = Page.Accent, Page.TextColor
local Button, Label, ButtonText = Page.Button, Page.Label, Page.ButtonText
local ShowTip, HideTip, Light = Page.ShowTip, Page.HideTip, Page.Light

------------------------------------------------------------------ per-spell popover
-- Options of one entry, limited to its family and to what the runtime reads
-- for it. A missing value means "follow the bar": customised rows get the
-- accent label and a reset button, which sits in its own column right of
-- every control. Glow style and color style every glow of the entry (spell
-- alert, ready, buff while active and stack glows). Stack rows (0 = off)
-- serve buffs and cooldowns that show their buff; "Color stacks from" also
-- holds the stack color (its swatch opens a color list, reset clears both).
-- Every row explains itself on its label (help), without allocating.
local POP_W, POP_MAX = 380, 520
-- Label column and the x where every row's control starts.
local LABEL_W, POP_X = 150, 154
Page.POP_X = POP_X
local FIELDS = Page.FIELDS
local SWATCHES, COLOR_MENU
local SWATCH, SWATCH_STEP, STACK_SWATCH = 13, 14, 18
local STACK_COLOR = CDM.SPELL_DEFAULTS.stackColor
local pop

-- aura: the entry is a buff, or a cooldown that shows the buff it tracks.
-- bars: the bar draws bars (buff bars, cooldowns shown as timer bars).
local function Applies(field, family, kind, aura, barKind, bars)
    if field.timer and barKind ~= CDM.KIND.AURA_BAR then return false end
    if field.blizzardOnly and kind ~= "b" then return false end
    if field.bars and not bars then return false end
    if field.itemOnly and kind ~= "i" and kind ~= "e" then return false end
    if field.stack then return family == FAMILY.AURA or aura == true end
    if family == FAMILY.AURA then return field.aura == true end
    if not field.cd then return false end
    return not (field.spellOnly and (kind == "i" or kind == "e"))
end
Page.FieldApplies = Applies
local function BarSetting(suffix)
    local key = KEYS[pop.slot] and KEYS[pop.slot][suffix]
    if key then return P.Get(ID, key) end
end
local function BarValue(field)
    if field.key == "threshold" then return P.Get(ID, "thresholdSeconds") end
    if field.key == "showGCD" then return P.Get(ID, "showGCD") end
    -- Countdown and charges say what the runtime shows (K.BarTime and
    -- K.BarStacks in MSUF_Suite_CooldownManager/Const.lua): timer bars also
    -- follow "Show time", cooldown icons also "Show charges".
    if field.key == "timeText" then
        return BarSetting("cdText") ~= false and (Page.Kind(pop.slot) ~= CDM.KIND.AURA_BAR
            and not BarSetting("cooldownDuration") or BarSetting("barTime") ~= false)
    end
    if field.key == "stackText" then
        return BarSetting("stackText") ~= false and not (pop.family ~= FAMILY.AURA and BarSetting("charges") == false)
    end
    return field.bar and BarSetting(field.bar)
end

-- "Own options: ..." for tooltips, built once per entry and stored string.
local customLines, customText = {}, nil
local customSpec
function Page.CustomLine(key)
    Page.CompleteFields()
    local text = P.Get(ID, "spellsData")
    local spec = Page.Spec()
    if customText ~= text or customSpec ~= spec then
        for entry in pairs(customLines) do customLines[entry] = nil end
        customText = text
        customSpec = spec
    end
    local line = customLines[key]
    if line == nil then
        local fields = Page.SpellFields(key, true)
        line = false
        if fields then
            local names = {}
            for i = 1, #FIELDS do
                local field = FIELDS[i]
                if fields[field.key] ~= nil or (field.color and fields[field.color] ~= nil) then names[#names + 1] = Tr(field.label) end
            end
            if #names > 0 then line = Tr("Own options") .. ": " .. table.concat(names, ", ") end
        end
        customLines[key] = line
    end
    return line or nil
end
-- A cooldown shows its buff, and so its stacks, only while "Show active
-- buff duration" applies to it; its stack rows are dimmed otherwise.
local function StacksShown(fields)
    if pop.family == FAMILY.AURA or fields and fields.itemAura then return true end
    local value = fields and fields.showAura
    if value == nil then
        local key = KEYS[pop.slot] and KEYS[pop.slot].showAura
        value = key and P.Get(ID, key)
    end
    return value == true
end
local function SetField(field, value)
    local ok, reason = Page.SetSpellField(pop.key, field.key, value)
    if not ok then Page.Fail(reason) end
end
local function ResetClick(self)
    local field = self.row.field
    -- A reset also drops text typed into the row and not stored.
    if self.row.edit then self.row.edit.dirty = nil end
    if not field.clears then
        SetField(field, nil)
        return
    end
    local ok, reason = Page.ClearSpellFields(pop.key, field.clears)
    if not ok then Page.Fail(reason) end
end
-- Shared choices: three states follow, force on or force off (the active
-- one clicked again follows); a switch is On or nothing. A specialization
-- stores On or Off as clicked, so Off never inherits a shared On.
local function BoolClick(self)
    local field = self.row.field
    if Page.spellSpecScope then
        SetField(field, self.value)
        return
    end
    if field.switch then
        SetField(field, self.value == true or nil)
        return
    end
    if Page.SpellField(pop.key, field.key) == self.value then SetField(field, nil) else SetField(field, self.value) end
end
-- self.field: an inline choice (the stack comparison) inside another row.
-- The first choice clears a shared choice; a specialization stores it
-- (field.zero), so it does not inherit the shared one.
local function ChoiceClick(self)
    local field = self.field or self.row.field
    local current = Page.SpellField(pop.key, field.key) or 0
    if current == field.zero then current = 0 end
    local function Pick(value)
        value = tonumber(value) or 0
        if value == 0 then value = Page.spellSpecScope and field.zero or nil end
        SetField(field, value)
    end
    if W.OpenDropdown then
        Page.dropdownOpen = true
        W.OpenDropdown(self, field.menu, current, Pick)
        return
    end
    -- Without Menu2's list, step through the choices.
    local menu, index = field.menu, 1
    for i = 1, #menu do if menu[i].value == current then index = i end end
    Pick(menu[index % #menu + 1].value)
end
-- Fields with "off" start at 0; stepped back to it they clear, or, in a
-- specialization, store 0 (off over a shared count).
local function StepClick(self)
    local field = self.row.field
    local current = Page.SpellField(pop.key, field.key)
    if current == nil then current = field.off and 0 or tonumber(BarValue(field)) or 0 end
    local multiplier = IsControlKeyDown() and 10 or IsShiftKeyDown() and 5 or 1
    local value = max(0, min(field.max, current + self.delta * field.step * multiplier))
    value = floor(value / field.step + 0.5) * field.step
    SetField(field, not (field.off and value == 0 and not Page.spellSpecScope) and value or nil)
end
-- The chosen color clicked again follows the bar: cleared, or, in a
-- specialization, stored as "" (the bar's color over a shared color).
local function SwatchClick(self)
    local field = self.row.field
    local current = Page.SpellField(pop.key, field.key)
    if not (current and current:lower() == self.hex) then
        SetField(field, self.hex)
    else
        SetField(field, Page.spellSpecScope and "" or nil)
    end
end
-- Default ("") clears a shared stack color; a specialization stores it.
local function ColorClick(self)
    local name = self.row.field.color
    local current = Page.SpellField(pop.key, name) or ""
    local function Pick(value)
        local ok, reason = Page.SetSpellField(pop.key, name, (value ~= "" or Page.spellSpecScope) and value or nil)
        if not ok then Page.Fail(reason) end
    end
    if W.OpenDropdown then
        Page.dropdownOpen = true
        W.OpenDropdown(self, COLOR_MENU, current, Pick)
        return
    end
    -- Without Menu2's list, step through the colors.
    local index = 1
    for i = 1, #COLOR_MENU do if COLOR_MENU[i].value == current then index = i end end
    Pick(COLOR_MENU[index % #COLOR_MENU + 1].value)
end
local function ColorEnter(self)
    ShowTip(self, Tr("Stack color"), Tr("Stacks show in this color from the number on the left."))
end
-- None clears a shared sound; a specialization stores it ("", silent).
local function SoundClick(self)
    local field = self.row.field
    Page.OpenSoundPicker(self, Page.SpellField(pop.key, field.key) or "", function(value)
        SetField(field, (value ~= "" or Page.spellSpecScope) and value or nil)
    end)
end
local function PlayClick(self) Page.PlaySound(Page.SpellField(pop.key, self.row.field.key)) end
local function NewSwatch(row, size, onClick)
    local swatch = CreateFrame("Button", nil, row)
    swatch:SetSize(size, size)
    swatch.edge = swatch:CreateTexture(nil, "BACKGROUND")
    swatch.edge:SetAllPoints(swatch)
    swatch.fill = swatch:CreateTexture(nil, "ARTWORK")
    swatch.fill:SetPoint("TOPLEFT", swatch, "TOPLEFT", 2, -2)
    swatch.fill:SetPoint("BOTTOMRIGHT", swatch, "BOTTOMRIGHT", -2, 2)
    swatch.row = row
    swatch:SetScript("OnClick", onClick)
    return swatch
end
-- The comparison in front of its threshold reads "Glow at stacks >= 3"; its
-- tooltip says the rule in words.
local OP_W = 40
local function OpMenuItem(field, value)
    local menu = field.menu
    for i = 1, #menu do if menu[i].value == (value or 0) then return menu[i] end end
    return menu[1]
end
local function StackRule(row)
    local fields = Page.SpellFields(pop.key)
    local count = fields and fields[row.field.key]
    if not count or count == 0 then return Tr("The stack glow is off.") end
    return format(Tr(OpMenuItem(row.op.field, fields[row.field.op]).rule), count)
end
local function OpEnter(self)
    ShowTip(self, Tr(self.field.label), Tr(self.field.help), StackRule(self.row))
end
local function NumberControls(row, field, x)
    if field.op then
        row.op = Button(row, "", OP_W, 20, ChoiceClick)
        row.op.row, row.op.field = row, field.opField
        Page.Chevron(row.op)
        row.op:SetPoint("LEFT", row, "LEFT", x, 0)
        row.op:HookScript("OnEnter", OpEnter)
        row.op:HookScript("OnLeave", HideTip)
        x = x + OP_W + 4
    end
    row.minus = Button(row, "-", 22, 20, StepClick)
    row.minus.row, row.minus.delta = row, -1
    row.minus:SetPoint("LEFT", row, "LEFT", x, 0)
    -- A click on the value types it (CooldownManagerPopoverInputs.lua).
    row.value = Button(row, "", 36, 20, Page.BeginPopoverNumber)
    row.value.row = row
    row.value:SetPoint("LEFT", row.minus, "RIGHT", 2, 0)
    row.plus = Button(row, "+", 22, 20, StepClick)
    row.plus.row, row.plus.delta = row, 1
    row.plus:SetPoint("LEFT", row.value, "RIGHT", 2, 0)
    if field.color then
        row.swatch = NewSwatch(row, STACK_SWATCH, ColorClick)
        row.swatch:SetPoint("LEFT", row.plus, "RIGHT", 8, 0)
        row.swatch:SetScript("OnEnter", ColorEnter)
        row.swatch:SetScript("OnLeave", HideTip)
    elseif not field.off then
        -- "Bar" (or the field's fallback) marks a value that follows the bar.
        row.hint = Label(row, "GameFontDisableSmall", "", "muted")
        row.hint:SetPoint("LEFT", row.plus, "RIGHT", 6, 0)
        row.hint:SetWidth(60)
    end
end

-- The label explains its row; a dimmed stack row also says why.
local STACK_DIM = "Needs \"Show active buff duration\": this icon shows the buff and its stacks only then."
local function LabelEnter(self)
    local row = self.row
    ShowTip(self, row.label:GetText(), Tr(row.field.help), row.op and StackRule(row) or nil, row.dimmed and Tr(STACK_DIM) or nil)
end
-- The glow color swatches. A stored color that is none of them (imported)
-- shows as a ninth, selected swatch that names it; like any chosen swatch,
-- clicked it follows the bar. No picker: one color route.
local function CustomColorEnter(self)
    ShowTip(self, format(Tr("Glow color: #%s"), self.hex))
end
local function ColorControls(row, x)
    row.swatches = {}
    for i = 1, #SWATCHES + 1 do
        local swatch = NewSwatch(row, SWATCH, SwatchClick)
        swatch:SetPoint("LEFT", row, "LEFT", x + (i - 1) * SWATCH_STEP, 0)
        if SWATCHES[i] then
            local r, g, b = P.RGB(SWATCHES[i])
            swatch.fill:SetColorTexture(r, g, b, 1)
            swatch.hex = SWATCHES[i]
        else
            swatch:SetScript("OnEnter", CustomColorEnter)
            swatch:SetScript("OnLeave", HideTip)
            swatch:Hide()
        end
        row.swatches[i] = swatch
    end
end
-- value "": a specialization follows the bar, so no swatch is selected.
local function PaintColors(row, value)
    local hex, found = value and value ~= "" and value:lower() or nil, false
    local ar, ag, ab = Accent()
    for i = 1, #SWATCHES do
        local swatch = row.swatches[i]
        if swatch.hex == hex then
            found = true
            swatch.edge:SetColorTexture(ar, ag, ab, 1)
        else
            swatch.edge:SetColorTexture(0, 0, 0, 0.8)
        end
    end
    local custom = row.swatches[#SWATCHES + 1]
    custom:SetShown(hex ~= nil and not found)
    if hex and not found then
        custom.hex = hex
        local r, g, b = P.RGB(hex)
        custom.fill:SetColorTexture(r, g, b, 1)
        custom.edge:SetColorTexture(ar, ag, ab, 1)
    end
end
-- A text box of a row: kind "spell", "icon" or "number" (the box a value
-- click opens). CooldownManagerPopoverInputs.lua stores what is typed.
function Page.NewPopoverEdit(row, kind, width)
    local edit = CreateFrame("EditBox", nil, row, "InputBoxTemplate")
    edit:SetSize(width, 20)
    edit:SetAutoFocus(false)
    edit:SetNumeric(kind == "icon")
    edit:SetMaxLetters(kind == "spell" and 100 or kind == "text" and 40 or 10)
    if T.SkinEditBox then T.SkinEditBox(edit) end
    edit.row = row
    Page.InitPopoverInput(edit, kind)
    row.edit = edit
    return edit
end
local function InputControls(row, kind, x)
    local edit = Page.NewPopoverEdit(row, kind, kind == "text" and 150 or 80)
    edit:SetPoint("LEFT", row, "LEFT", x + 4, 0)
    if kind == "text" then return end
    row.preview = row:CreateTexture(nil, "ARTWORK")
    row.preview:SetSize(20, 20)
    row.preview:SetPoint("LEFT", edit, "RIGHT", 8, 0)
    row.preview:SetTexCoord(CROP_MIN, CROP_MAX, CROP_MIN, CROP_MAX)
end
local function Row(field)
    local row = pop.rows[field.key]
    if row then return row end
    row = CreateFrame("Frame", nil, pop.content)
    row:SetSize(POP_W - 40, 24)
    row.field = field
    row.label = Label(row, "GameFontHighlightSmall", "")
    row.label:SetPoint("LEFT", row, "LEFT", 0, 0)
    row.label:SetWidth(LABEL_W)
    row.label:SetWordWrap(true)
    row.label:SetMaxLines(2)
    row.tip = CreateFrame("Frame", nil, row)
    row.tip:SetPoint("LEFT", row, "LEFT", 0, 0)
    row.tip:SetSize(LABEL_W, 20)
    row.tip:EnableMouse(true)
    row.tip.row = row
    row.tip:SetScript("OnEnter", LabelEnter)
    row.tip:SetScript("OnLeave", HideTip)
    row.reset = Button(row, "Reset", 44, 20, ResetClick)
    row.reset.row = row
    row.reset:SetPoint("RIGHT", row, "RIGHT", 0, 0)
    local x, kind = POP_X, field.kind
    if kind == "bool" then
        row.on = Button(row, "On", 38, 20, BoolClick)
        row.on.row, row.on.value = row, true
        row.on:SetPoint("LEFT", row, "LEFT", x, 0)
        row.off = Button(row, "Off", 38, 20, BoolClick)
        row.off.row, row.off.value = row, false
        row.off:SetPoint("LEFT", row.on, "RIGHT", 4, 0)
        row.hint = Label(row, "GameFontDisableSmall", "", "muted")
        row.hint:SetPoint("LEFT", row.off, "RIGHT", 6, 0)
        row.hint:SetWidth(60)
    elseif kind == "choice" or kind == "sound" then
        row.choice = Button(row, "", kind == "sound" and 68 or 108, 20, kind == "sound" and SoundClick or ChoiceClick)
        row.choice.row = row
        Page.Chevron(row.choice)
        row.choice:SetPoint("LEFT", row, "LEFT", x, 0)
        if kind == "sound" then
            row.play = Button(row, "Play", 38, 20, PlayClick)
            row.play.row = row
            row.play:SetPoint("LEFT", row.choice, "RIGHT", 2, 0)
        end
    elseif kind == "number" then
        NumberControls(row, field, x)
    elseif kind == "color" then
        ColorControls(row, x)
    elseif kind == "icon" or kind == "spell" or kind == "text" then
        InputControls(row, kind, x)
    end
    pop.rows[field.key] = row
    return row
end

-- companion: the stack color ("" is a specialization's explicit default).
local function PaintNumber(row, field, value, companion)
    if companion == "" then companion = nil end
    local shown = value
    if shown == nil then shown = field.off and 0 or tonumber(BarValue(field)) or 0 end
    row.shownNumber = shown
    ButtonText(row.value, field.off and shown == 0 and Tr("Off") or tostring(shown))
    row.value:SetAlpha(value ~= nil and 1 or 0.6)
    if row.hint then SetRaw(row.hint, value ~= nil and "" or Tr(field.fallback or "Bar")) end
    local swatch = row.swatch
    if swatch then
        local r, g, b = P.RGB(companion or STACK_COLOR)
        swatch.fill:SetColorTexture(r, g, b, 1)
        if companion then r, g, b = Accent() else r, g, b = 0, 0, 0 end
        swatch.edge:SetColorTexture(r, g, b, companion and 1 or 0.8)
        swatch:SetAlpha(shown > 0 and 1 or 0.5)
    end
end
local function PaintRow(row, fields)
    local field = row.field
    local value = fields and fields[field.key]
    local companion = field.color and fields and fields[field.color] or nil
    local own = Page.OwnSpellFields(pop.key)
    local partner = field.color or field.op
    local custom = own and (own[field.key] ~= nil or (partner and own[partner] ~= nil)) or false
    SetRaw(row.label, Tr(pop.family == FAMILY.AURA and field.auraLabel or field.label))
    local r, g, b
    if custom then r, g, b = Accent() else r, g, b = TextColor() end
    row.label:SetTextColor(r, g, b)
    row.reset:SetShown(custom)
    -- Stack rows of a cooldown whose buff is not shown stay editable, dimmed.
    row.dimmed = field.stack == true and not StacksShown(fields)
    row:SetAlpha(row.dimmed and 0.45 or 1)
    local kind = field.kind
    if kind == "bool" then
        if field.switch then
            row.on:SetActive(value == true)
            row.off:SetActive(value ~= true)
            row.hint:SetText("")
        else
            row.on:SetActive(value == true)
            row.off:SetActive(value == false)
            local bar = BarValue(field)
            SetRaw(row.hint, custom and "" or (Tr("Bar") .. ": " .. Tr(bar == true and "On" or "Off")))
        end
    elseif kind == "choice" then
        -- A specialization's stored first choice reads as the first choice.
        local menu, choice = field.menu, value
        if choice == field.zero then choice = nil end
        -- A row that follows the bar names the bar's current choice.
        local shown = choice
        if shown == nil and field.fromBar then shown = field.fromBar[BarValue(field)] end
        local text = menu[1].text
        for i = 1, #menu do if menu[i].value == (shown or 0) then text = menu[i].text end end
        if choice == nil and shown ~= nil then
            ButtonText(row.choice, Tr("Bar") .. ": " .. Tr(text))
        elseif choice == nil and field.key == "auraUnit" and (pop.unit == "player" or pop.unit == "target") then
            -- What Automatic picked, when the runtime says so.
            ButtonText(row.choice, Tr(pop.unit == "target" and "Automatic: target" or "Automatic: you"))
        else
            ButtonText(row.choice, Tr(text))
        end
    elseif kind == "number" then
        PaintNumber(row, field, value, companion)
        if row.op then ButtonText(row.op, OpMenuItem(row.op.field, fields and fields[field.op]).mark) end
    elseif kind == "color" then
        PaintColors(row, value)
    elseif kind == "sound" then
        ButtonText(row.choice, value and Page.SoundLabel(value) or Tr("None"))
        row.play:SetEnabled(value ~= nil and value ~= "")
    elseif kind == "text" then
        Page.PaintPopoverInput(row.edit, value or "")
    elseif kind == "icon" or kind == "spell" then
        local name = value and kind == "spell" and C_Spell.GetSpellName(value)
        Page.PaintPopoverInput(row.edit, value and (name or tostring(value)) or "")
        if value then row.preview:SetTexture(kind == "spell" and C_Spell.GetSpellTexture(value) or value) else SetIcon(row.preview, pop.texture) end
    end
    if Page.spellSpecScope and not custom and value ~= nil and row.hint then SetRaw(row.hint, Tr("Shared")) end
end

local function RemoveClick()
    local key, slot, name = pop.key, pop.slot, Public(pop.entryName) and pop.entryName or nil
    pop:Hide()
    Page.RemoveWithUndo(slot, key, name)
end
local function MoveClick(self)
    local values, n = pop.moveValues, 0
    for i = 1, #SLOTS do
        local slot = SLOTS[i].key
        if slot ~= pop.slot and Page.IsOn(slot) then
            n = n + 1
            local item = values[n] or {}
            values[n] = item
            item.value, item.text, item.translate = slot, Page.BarName(slot), false
            item.disabled = Page.Family(slot) ~= pop.family
            item.tooltip = item.disabled and Tr(Page.FamilyError(pop.family)) or nil
        end
    end
    for i = n + 1, #values do values[i] = nil end
    if n == 0 then
        Page.Fail("Turn on another bar first.")
        return
    end
    if not W.OpenDropdown then return end
    Page.dropdownOpen = true
    W.OpenDropdown(self, values, nil, function(slot)
        local key, family = pop.key, pop.family
        local name = Public(pop.entryName) and pop.entryName or key
        pop:Hide()
        local ok, reason = Page.MoveEntry(key, slot, nil, family)
        if ok then Page.Note(format(Tr("Moved %s to %s."), name, Page.BarName(slot))) else Page.Fail(reason) end
    end)
end
local function ResetSpellClick()
    for _, row in pairs(pop.rows) do
        if row.edit then row.edit.dirty = nil end
    end
    local ok, reason = Page.ResetSpell(pop.key)
    if not ok then Page.Fail(reason) end
end
local function CopyClick()
    local ok, result = Page.CopyToSpecs(pop.slot, pop.key)
    if not ok then
        Page.Fail(result)
        return
    end
    Page.Note(result == 0 and Tr("Every specialization already has it.")
        or format(Tr("Copied to %d specializations."), result))
end

-- Typed input is stored in the scope it was typed in; invalid input stays.
local function ScopeClick()
    if not Page.FlushPopoverInputs() then return end
    Page.spellSpecScope = not Page.spellSpecScope
    Page.PaintPopover()
end

local function EnsurePopover()
    if pop then return pop end
    Page.PreparePopoverFields()
    SWATCHES, COLOR_MENU = Page.POPOVER_SWATCHES, Page.COLOR_MENU
    pop = Page.NewPopup(POP_W, 300)
    Page.popover = pop
    pop.rows, pop.moveValues, pop.headers = {}, {}, {}
    pop.icon = pop:CreateTexture(nil, "ARTWORK")
    pop.icon:SetSize(34, 34)
    pop.icon:SetPoint("TOPLEFT", pop, "TOPLEFT", 12, -12)
    pop.icon:SetTexCoord(CROP_MIN, CROP_MAX, CROP_MIN, CROP_MAX)
    pop.title = Label(pop, "GameFontNormal", "")
    pop.title:SetPoint("TOPLEFT", pop.icon, "TOPRIGHT", 8, -2)
    pop.title:SetWidth(POP_W - 90)
    pop.sub = Label(pop, "GameFontDisableSmall", "", "muted")
    pop.sub:SetPoint("TOPLEFT", pop.title, "BOTTOMLEFT", 0, -4)
    pop.sub:SetWidth(POP_W - 90)
    pop.close = Button(pop, "x", 22, 20, function() pop:Hide() end)
    pop.close:SetPoint("TOPRIGHT", pop, "TOPRIGHT", -8, -8)
    -- Header actions fit their captions (longer in other languages) and
    -- wrap onto a second line when they do not fit side by side.
    pop.actions = {
        Button(pop, "Remove from bar", 100, 22, RemoveClick), Button(pop, "Move to bar", 100, 22, MoveClick),
        Button(pop, "Reset this spell", 102, 22, ResetSpellClick), Button(pop, "Copy to all specs", 140, 22, CopyClick),
    }
    pop.scopeButton = Button(pop, "Edit this specialization", 160, 22, ScopeClick)
    pop.remove, pop.move, pop.reset, pop.copy = pop.actions[1], pop.actions[2], pop.actions[3], pop.actions[4]
    for i = 1, #pop.actions do
        local width = T.MeasureButtonWidth and T.MeasureButtonWidth(pop.actions[i], 60, POP_W - 24)
        if type(width) == "number" and width > 0 then pop.actions[i]:SetWidth(width) end
    end
    pop.scope = Label(pop, "GameFontDisableSmall", "These choices apply to this spell on every bar and specialization.",
        "muted")
    pop.scope:SetWidth(POP_W - 24)
    pop.scope:SetWordWrap(true)
    pop.scroll, pop.content = Page.ScrollArea(pop, POP_W - 40)
    pop.OnClosed = function(self)
        Page.FlushPopoverInputs()
        Light(self.anchor, false)
    end
    return pop
end
-- Places the header actions (Copy only for the player's own entries) and
-- returns where the rows start, below the scope text however many lines it
-- wraps to; moves nothing when neither changed.
local function PlaceActions(copy)
    local scopeHeight = max(14, pop.scope:GetStringHeight() or 14)
    if pop.placedCopy == copy and pop.placedScope == scopeHeight then return pop.top end
    pop.placedCopy, pop.placedScope = copy, scopeHeight
    pop.copy:SetShown(copy)
    local x, line = 12, 0
    for i = 1, copy and 4 or 3 do
        local button = pop.actions[i]
        local width = tonumber((button:GetWidth())) or 100
        if x > 12 and x + width > POP_W - 12 then x, line = 12, line + 1 end
        button:ClearAllPoints()
        button:SetPoint("TOPLEFT", pop, "TOPLEFT", x, -54 - line * 26)
        x = x + width + 4
    end
    local y = 54 + (line + 1) * 26
    pop.scope:ClearAllPoints()
    pop.scope:SetPoint("TOPLEFT", pop, "TOPLEFT", 12, -y)
    pop.scope:SetHeight(scopeHeight)
    pop.scopeButton:ClearAllPoints()
    pop.scopeButton:SetPoint("TOPLEFT", pop.scope, "BOTTOMLEFT", 0, -5)
    pop.top = y + scopeHeight + 34
    pop.scroll:ClearAllPoints()
    pop.scroll:SetPoint("TOPLEFT", pop, "TOPLEFT", 12, -pop.top)
    pop.scroll:SetPoint("BOTTOMRIGHT", pop, "BOTTOMRIGHT", -26, 10)
    return pop.top
end

-- Section headers: the section's name in the accent color and a thin rule,
-- one pooled frame per section, shown above the first row it holds.
local SECTION_H = 20
local function Header(section, y)
    local header = pop.headers[section]
    if not header then
        header = CreateFrame("Frame", nil, pop.content)
        header:SetSize(POP_W - 40, SECTION_H)
        header.label = Label(header, "GameFontNormalSmall", "")
        header.label:SetPoint("LEFT", header, "LEFT", 0, 0)
        SetRaw(header.label, Tr(section.label))
        header.line = header:CreateTexture(nil, "ARTWORK")
        header.line:SetHeight(1)
        header.line:SetPoint("LEFT", header.label, "RIGHT", 8, 0)
        header.line:SetPoint("RIGHT", header, "RIGHT", 0, 0)
        pop.headers[section] = header
    end
    local r, g, b = Accent()
    header.label:SetTextColor(r, g, b)
    header.line:SetColorTexture(r, g, b, 0.25)
    header:ClearAllPoints()
    header:SetPoint("TOPLEFT", pop.content, "TOPLEFT", 0, -y)
    header:Show()
end
-- A label may wrap to two lines; its row grows to fit and keeps the
-- controls centered on it. Single-line rows keep their 26 px step.
local function RowHeight(row)
    local height = max(24, min(40, row.label:GetStringHeight() or 14) + 4)
    row:SetHeight(height)
    row.tip:SetHeight(height)
    return height + 2
end
function Page.PaintPopover()
    if not pop then return end
    local fields = Page.SpellFields(pop.key)
    local kind = CDM.EntryKind(pop.key)
    SetIcon(pop.icon, pop.texture)
    SetRaw(pop.title, Public(pop.entryName) and pop.entryName or pop.key)
    SetRaw(pop.sub, Page.BarName(pop.slot) .. "  -  " .. Page.Identity(pop.key))
    pop.reset:SetEnabled(Page.OwnSpellFields(pop.key) ~= nil)
    SetRaw(pop.scope, Tr(Page.spellSpecScope and "Editing this specialization. Reset a choice to inherit the shared value."
        or "These choices apply to this spell on every bar and specialization."))
    pop.scopeButton:SetText(Page.spellSpecScope and "Edit shared choices" or "Edit this specialization")
    pop.scopeButton:SetEnabled(Page.Spec() ~= nil)
    local top = PlaceActions(kind ~= "b")
    local barKind = Page.Kind(pop.slot)
    local bars = barKind == CDM.KIND.AURA_BAR or barKind == CDM.KIND.COOLDOWN and BarSetting("cooldownDuration") == true
    local y, section = 0, nil
    for _, header in pairs(pop.headers) do header:Hide() end
    for i = 1, #FIELDS do
        local field = FIELDS[i]
        local row = pop.rows[field.key]
        if not field.inline and Applies(field, pop.family, kind, pop.hasAura, barKind, bars) then
            if section ~= field.section then
                section = field.section
                Header(section, y)
                y = y + SECTION_H
            end
            row = Row(field)
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", pop.content, "TOPLEFT", 0, -y)
            PaintRow(row, fields)
            row:Show()
            y = y + RowHeight(row)
        elseif row then
            row:Hide()
        end
    end
    pop.content:SetHeight(max(1, y))
    pop:SetHeight(min(POP_MAX, top + y + 12))
    -- Sound mute note; a searched option scrolls into view and flashes.
    Page.PaintSpellOptionFeedback(pop)
end

-- Opens the entry of a spell tile, anchored under the tile or under anchor
-- (its icon in the preview). The same spell clicked there again closes it.
function Page.TogglePopover(tile, anchor)
    anchor = anchor or tile
    if pop and pop:IsShown() and pop.key == tile.key and pop.slot == Page.selected and pop.anchor == anchor then
        pop:Hide()
        return false
    end
    if P.Combat() or not tile.key then return false end
    EnsurePopover()
    -- Typed input belongs to its entry: stored first, emptied for another one.
    Page.FlushPopoverInputs(pop.key ~= tile.key)
    Page.ClosePopups(pop)
    if pop:IsShown() and pop.anchor ~= anchor then Light(pop.anchor, false) end
    pop.key, pop.slot, pop.family, pop.hasAura = tile.key, Page.selected, tile.family, tile.aura == true
    pop.entryName, pop.texture, pop.unit = tile.name, tile.texture, tile.unit
    Page.PlacePopup(pop, anchor)
    pop.scroll:SetVerticalScroll(0)
    Page.PaintPopover()
    pop:Show()
    P.Suite.Skin.RegisterMenu(pop, "cdmMenuMotion")
    P.Suite.Skin.AnimateContent(pop.content, pop.key, "cdmMenuMotion")
    Light(anchor, true)
    return true
end
-- The preview moves the open popover to the icon that now holds its entry.
function Page.MovePopover(anchor)
    if not (pop and pop:IsShown()) or pop.anchor == anchor then return end
    Light(pop.anchor, false)
    Page.PlacePopup(pop, anchor)
    Light(anchor, true)
end

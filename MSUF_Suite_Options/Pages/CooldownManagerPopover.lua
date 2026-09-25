local _, P = ...
-- Cooldown manager page, pooled editors: the sound picker and the per-spell
-- popover.
local Page = P.CDMPage
if not Page then return end
local W, T, Tr = P.W, P.T, P.Tr
local CDM = P.Suite.CDM
local ID = Page.ID
local SLOTS, KEYS = CDM.SLOTS, CDM.KEYS
local EMPTY = {}
local CROP_MIN, CROP_MAX = Page.CROP_MIN, Page.CROP_MAX
local floor, max, min, format = math.floor, math.max, math.min, string.format
local Public, SetIcon, SetRaw, Media = Page.Public, Page.SetIcon, Page.SetRaw, Page.Media
local Accent, TextColor, MutedColor = Page.Accent, Page.TextColor, Page.MutedColor
local Button, Label, ButtonText = Page.Button, Page.Label, Page.ButtonText
local ShowTip, HideTip, ClearFocus, Light = Page.ShowTip, Page.HideTip, Page.ClearFocusScript, Page.Light

------------------------------------------------------------------ sound picker
-- "None", the current value when no list below has it, Blizzard's Cooldown
-- Manager sounds by category, then the LibSharedMedia sounds. Items and rows
-- are pooled; a header shows while one of its rows matches the filter, and a
-- category name finds all of its sounds.
local SOUND_W, SOUND_H = 280, 400
local sounds

local function SoundRowClick(self)
    local item = self.item
    if not item or item.header or P.Combat() then return end
    local pick = sounds.onPick
    sounds:Hide()
    if pick then pick(item.value) end
end
local function SoundPlayClick(self)
    local item = self.row and self.row.item
    if item and not item.header then Page.PlaySound(item.value) end
end
local function SoundRowEnter(self) if self.item and not self.item.header then self.hover:Show() end end
local function SoundRowLeave(self) self.hover:Hide() end
local function SoundRow(index)
    local row = sounds.rows[index]
    if row then return row end
    row = CreateFrame("Button", nil, sounds.content)
    row:SetSize(SOUND_W - 40, 22)
    row:RegisterForClicks("LeftButtonUp")
    row.hover = row:CreateTexture(nil, "BACKGROUND")
    row.hover:SetAllPoints(row)
    row.hover:SetColorTexture(1, 1, 1, 0.06)
    row.hover:Hide()
    row.text = Label(row, "GameFontHighlightSmall", "")
    row.text:SetPoint("LEFT", row, "LEFT", 4, 0)
    row.text:SetWidth(SOUND_W - 100)
    row.play = Button(row, "Play", 44, 18, SoundPlayClick)
    row.play.row = row
    row.play:SetPoint("RIGHT", row, "RIGHT", -2, 0)
    row:SetScript("OnClick", SoundRowClick)
    row:SetScript("OnEnter", SoundRowEnter)
    row:SetScript("OnLeave", SoundRowLeave)
    sounds.rows[index] = row
    return row
end
local function PaintSoundRow(row, item)
    row.item = item
    SetRaw(row.text, item.text)
    local r, g, b
    if item.header == 2 then
        r, g, b = MutedColor()
    elseif item.header or item.value == sounds.current then
        r, g, b = Accent()
    else
        r, g, b = TextColor()
    end
    row.text:SetTextColor(r, g, b)
    row.play:SetShown(not item.header and item.value ~= "")
    row.hover:Hide()
end
function Page.FilterSounds()
    local query = Page.Query(sounds.search)
    local items = sounds.items
    -- Headers come before their rows: they are cleared before a row marks them.
    for i = 1, sounds.count do
        local item = items[i]
        if item.header then
            item.match = false
        else
            item.match = query == "" or item.search:find(query, 1, true) ~= nil
            if item.match then
                if item.section then item.section.match = true end
                if item.group then item.group.match = true end
            end
        end
    end
    local shown = 0
    for i = 1, sounds.count do
        local item = items[i]
        if item.match then
            shown = shown + 1
            local row = SoundRow(shown)
            PaintSoundRow(row, item)
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", sounds.content, "TOPLEFT", 0, -(shown - 1) * 22)
            row:Show()
        end
    end
    for i = shown + 1, #sounds.rows do
        sounds.rows[i].item = nil
        sounds.rows[i]:Hide()
    end
    sounds.content:SetHeight(max(1, shown * 22))
end
-- header: 1 section, 2 category. Rows are found by their category name too.
local function SoundItem(n, value, text, header, section, group)
    local item = sounds.items[n]
    if not item then
        item = {}
        sounds.items[n] = item
    end
    item.value, item.text, item.header, item.section, item.group = value, text, header, section, group
    local search = type(text) == "string" and text:lower() or ""
    item.search = group and (search .. " " .. group.search) or search
    return item
end
local function KitListed(value, kits)
    local kit = kits and value:match("^kit:(%d+)$")
    return kit ~= nil and kits.names[tonumber(kit)] ~= nil
end
-- Blizzard's Cooldown Manager sounds, one header per category.
local function AddKitSounds(n, kits)
    local groups = kits and kits.groups or EMPTY
    if #groups == 0 then return n end
    n = n + 1
    local section = SoundItem(n, nil, Tr("Blizzard Cooldown Manager"), 1)
    for i = 1, #groups do
        local group = groups[i]
        n = n + 1
        local header = SoundItem(n, nil, group.title, 2, section)
        for j = 1, #group do
            n = n + 1
            SoundItem(n, group[j].value, group[j].text, nil, section, header)
        end
    end
    return n
end
local function AddMediaSounds(n)
    local lsm = Media()
    local names = lsm and lsm.List and lsm:List("sound") or EMPTY
    local section
    for i = 1, #names do
        local name = names[i]
        if type(name) == "string" and name ~= "" and #name <= 116 then
            if not section then
                n = n + 1
                section = SoundItem(n, nil, Tr("Shared media"), 1)
            end
            n = n + 1
            SoundItem(n, "lsm:" .. name, name, nil, section)
        end
    end
    return n
end
local function EnsureSounds()
    if sounds then return sounds end
    sounds = Page.NewPopup(SOUND_W, SOUND_H)
    Page.soundPicker = sounds
    sounds.items, sounds.rows, sounds.count = {}, {}, 0
    sounds.title = Label(sounds, "GameFontNormal", Tr("Choose a sound"))
    sounds.title:SetPoint("TOPLEFT", sounds, "TOPLEFT", 12, -12)
    sounds.close = Button(sounds, "x", 22, 20, function() sounds:Hide() end)
    sounds.close:SetPoint("TOPRIGHT", sounds, "TOPRIGHT", -8, -8)
    sounds.search = Page.SearchBox(sounds, SOUND_W - 28, Tr("Filter sounds"), Page.FilterSounds)
    sounds.search:SetPoint("TOPLEFT", sounds, "TOPLEFT", 14, -36)
    sounds.scroll, sounds.content = Page.ScrollArea(sounds, SOUND_W - 40)
    sounds.scroll:SetPoint("TOPLEFT", sounds, "TOPLEFT", 12, -66)
    sounds.scroll:SetPoint("BOTTOMRIGHT", sounds, "BOTTOMRIGHT", -26, 12)
    sounds.OnClosed = function(self)
        self.search:ClearFocus()
        self.onPick = nil
    end
    return sounds
end
function Page.OpenSoundPicker(anchor, current, onPick)
    if P.Combat() then return false end
    if sounds and sounds:IsShown() and sounds.anchor == anchor then
        sounds:Hide()
        return false
    end
    EnsureSounds()
    current = type(current) == "string" and current or ""
    local kits = Page.BlizzardSounds()
    local n = 1
    SoundItem(n, "", Tr("None"))
    if current ~= "" and not current:find("^lsm:") and not KitListed(current, kits) then
        n = n + 1
        SoundItem(n, current, Page.SoundLabel(current))
    end
    n = AddMediaSounds(AddKitSounds(n, kits))
    sounds.count, sounds.current, sounds.onPick = n, current, onPick
    Page.ClosePopups(Page.popover)
    Page.PlacePopup(sounds, anchor)
    if Page.popover and sounds.SetFrameLevel then sounds:SetFrameLevel((Page.popover:GetFrameLevel() or 0) + 20) end
    sounds.search:SetText("")
    if sounds.scroll.SetVerticalScroll then sounds.scroll:SetVerticalScroll(0) end
    Page.FilterSounds()
    sounds:Show()
    return true
end

------------------------------------------------------------------ per-spell popover
-- Options of one entry, limited to its family and to what the runtime reads
-- for it. A missing value means "follow the bar": customised rows get the
-- accent label and a reset button, which sits in its own column right of
-- every control. Glow style and color style every glow of the entry (spell
-- alert, ready, buff while active and stack glows). Stack rows (0 = off)
-- serve buffs and cooldowns that show their buff; "Color stacks from" also
-- holds the stack color (its swatch opens a color list, reset clears both).
-- Every row explains itself on its label (help), without allocating.
local POP_W, POP_MAX = 360, 520
-- Label column and the x where every row's control starts.
local LABEL_W, POP_X = 150, 154
Page.POP_X = POP_X
local SWATCHES = { "ffd200", "ffffff", "ff4d4d", "4dff73", "4db8ff", "c78cff", "4dffff", "ff9933" }
local SWATCH_NAMES = { "Gold", "White", "Red", "Green", "Blue", "Purple", "Cyan", "Orange" }
local SWATCH, SWATCH_STEP, STACK_SWATCH = 13, 14, 18
-- The stack color of an entry that has none.
local STACK_COLOR = CDM.SPELL_DEFAULTS and CDM.SPELL_DEFAULTS.stackColor or "ff5a3c"
local SHOW_HIDE = { { 0, "Bar setting" }, { 2, "Show" }, { 3, "Hide" } }
local FROM_BOOL = { [true] = 2, [false] = 3 }
-- bar: the bar setting a missing value follows. fromBar: that setting's
-- value as a choice of the row. fallback: the hint when no bar setting
-- stands behind the row. switch: On or nothing (no bar setting to follow).
-- blizzardOnly: Blizzard's entries only (custom auras name their unit).
local ALL_FIELDS = {
    { key = "procGlow", label = "Spell alert glow", kind = "bool", cd = true, spellOnly = true, bar = "procGlow",
      help = "Glow while the game highlights this spell (spell alert)." },
    { key = "readyGlow", label = "Glow when ready", kind = "bool", cd = true, bar = "readyGlow",
      help = "Glow while the spell is ready. \"Ready glows only in combat\" in Frame Basics limits it to combat." },
    { key = "auraGlow", label = "Glow while active", kind = "bool", aura = true, bar = "auraGlow",
      help = "Glow while the buff is active." },
    { key = "glowStyle", label = "Glow style", kind = "choice", cd = true, aura = true,
      values = { { 0, "Bar setting" }, { 1, "Blizzard alert" }, { 2, "Marching ants" }, { 3, "Pulse" }, { 4, "Border" } },
      help = "Style of every glow of this spell: spell alert, ready, active buff and stack glows." },
    { key = "glowColor", label = "Glow color", kind = "color", cd = true, aura = true,
      help = "Tints every glow of this spell. Click the chosen color again to follow the bar." },
    { key = "desat", label = "Desaturate on cooldown", kind = "choice", cd = true,
      values = { { 0, "Bar setting" }, { 2, "Never" }, { 3, "Always" } },
      help = "Grey out the icon while the spell is on cooldown." },
    { key = "hideReady", label = "Hide when ready", kind = "bool", cd = true, bar = "hideReady",
      help = "Show the icon only while the spell is on cooldown." },
    { key = "readyAlpha", label = "Opacity when ready", kind = "number", cd = true, bar = "readyAlpha", step = 1, max = 100,
      help = "Icon opacity while the spell is ready. Shift steps by 5, Ctrl by 10." },
    { key = "cdAlpha", label = "Opacity on cooldown", kind = "number", cd = true, bar = "cdAlpha", step = 1, max = 100,
      help = "Icon opacity while the spell is on cooldown. Shift steps by 5, Ctrl by 10." },
    { key = "showAura", label = "Show active buff duration", kind = "bool", cd = true, spellOnly = true, bar = "showAura",
      help = "While the buff of this spell lasts, the icon shows its duration and stacks instead of the cooldown." },
    { key = "showMissing", label = "Show dimmed when missing", kind = "bool", aura = true, bar = "showMissing",
      help = "Keep the icon in its place, dimmed, while the buff is missing." },
    { key = "auraUnit", label = "Track on", kind = "choice", stack = true, blizzardOnly = true,
      values = { { 0, "Automatic" }, { 2, "Me" }, { 3, "Target" }, { 4, "Both" } },
      help = "Where the buff or debuff is looked for. Automatic: harmful spells on your target, all others on you." },
    { key = "stackGlow", label = "Glow at stacks", kind = "number", stack = true, off = true, step = 1, max = 99,
      help = "Glow while the buff has at least this many stacks." },
    { key = "stackColorAt", label = "Color stacks from", kind = "number", stack = true, off = true, step = 1, max = 99,
      color = "stackColor", help = "From this many stacks the number shows in the color on the right." },
    { key = "swipe", label = "Swipe", kind = "choice", cd = true, aura = true,
      values = { { 0, "Normal" }, { 2, "Reversed" }, { 3, "Hidden" } },
      help = "The dark sweep over the icon while it counts down." },
    { key = "timeText", label = "Countdown", auraLabel = "Seconds", kind = "choice", cd = true, aura = true,
      bar = "cdText", fromBar = FROM_BOOL, values = SHOW_HIDE,
      help = "Show or hide the countdown numbers of this spell. Bar setting follows the bar's Text section." },
    { key = "stackText", label = "Charges", auraLabel = "Stacks", kind = "choice", cd = true, aura = true,
      bar = "stackText", fromBar = FROM_BOOL, values = SHOW_HIDE,
      help = "Show or hide the charges, stacks or item count of this spell." },
    { key = "textTop", label = "Text on top", kind = "choice", cd = true, aura = true, bar = "textTop",
      fromBar = { 2, 3 }, values = { { 0, "Bar setting" }, { 2, "Stacks" }, { 3, "Countdown" } },
      help = "Which number is drawn on top when both show." },
    { key = "threshold", label = "Warn below (seconds)", kind = "number", cd = true, aura = true, step = 1, max = 10,
      fallback = "All bars",
      help = "The countdown turns to the warning color below this many seconds. All bars: the Text section's setting." },
    { key = "sound", label = "Sound when ready", auraLabel = "Sound when gained", kind = "sound", cd = true, aura = true,
      help = "Plays when the spell becomes ready (a buff: when you gain it)." },
    { key = "lossSound", label = "Sound when lost", kind = "sound", aura = true, help = "Plays when the buff ends." },
    { key = "tts", label = "Say the name when ready", kind = "bool", cd = true, switch = true,
      help = "Your computer says the spell's name when it becomes ready." },
    -- A buff shows the game's icon while active; its own icon only while missing.
    { key = "icon", label = "Icon file ID (Enter)", auraLabel = "Icon when missing (Enter)", kind = "icon", cd = true,
      aura = true, help = "Type a texture file ID and press Enter to show another icon. Empty follows the game." },
}
-- Rows exist for the fields the catalog stores.
local FIELDS = {}
for _, field in ipairs(ALL_FIELDS) do
    if CDM.SPELL_FIELDS[field.key] then FIELDS[#FIELDS + 1] = field end
end
Page.FIELDS = FIELDS
local function SwatchItem(value, text, hex)
    local r, g, b = P.RGB(hex)
    return { value = value, text = text, swatchColor = { r, g, b, 1 } }
end
-- Stack colors: "" is the default color (the field is cleared).
local COLOR_MENU = { SwatchItem("", "Default", STACK_COLOR) }
for i, hex in ipairs(SWATCHES) do COLOR_MENU[i + 1] = SwatchItem(hex, SWATCH_NAMES[i], hex) end
Page.COLOR_MENU = COLOR_MENU
for _, field in ipairs(FIELDS) do
    if field.values then
        field.menu = {}
        for i, pair in ipairs(field.values) do field.menu[i] = { value = pair[1], text = pair[2] } end
    end
    if field.color then field.clears = { field.key, field.color } end
end
local pop

-- aura: the entry is a buff, or a cooldown that shows the buff it tracks.
local function Applies(field, family, kind, aura)
    if field.blizzardOnly and kind ~= "b" then return false end
    if field.stack then return family == 2 or aura == true end
    if family == 2 then return field.aura == true end
    if not field.cd then return false end
    return not (field.spellOnly and (kind == "i" or kind == "e"))
end
Page.FieldApplies = Applies
local function BarValue(field)
    if field.key == "threshold" then return P.Get(ID, "thresholdSeconds") end
    local key = field.bar and KEYS[pop.slot] and KEYS[pop.slot][field.bar]
    if key then return P.Get(ID, key) end
end

-- "Own options: ..." for tooltips, built once per entry and stored string.
local customLines, customText = {}, nil
function Page.CustomLine(key)
    local text = P.Get(ID, "spellsData")
    if customText ~= text then
        for entry in pairs(customLines) do customLines[entry] = nil end
        customText = text
    end
    local line = customLines[key]
    if line == nil then
        local fields = Page.SpellOverrides().e[key]
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
    if pop.family == 2 then return true end
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
    if not field.clears then
        SetField(field, nil)
        return
    end
    local ok, reason = Page.ClearSpellFields(pop.key, field.clears)
    if not ok then Page.Fail(reason) end
end
-- Three states follow, force on or force off; a switch is On or nothing.
local function BoolClick(self)
    local field = self.row.field
    if field.switch then
        SetField(field, self.value == true or nil)
        return
    end
    if Page.SpellField(pop.key, field.key) == self.value then SetField(field, nil) else SetField(field, self.value) end
end
local function ChoiceClick(self)
    local field = self.row.field
    local current = Page.SpellField(pop.key, field.key) or 0
    local function Pick(value)
        value = tonumber(value) or 0
        SetField(field, value ~= 0 and value or nil)
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
-- Fields with "off" start at 0 and clear themselves when stepped back to it.
local function StepClick(self)
    local field = self.row.field
    local current = Page.SpellField(pop.key, field.key)
    if current == nil then current = field.off and 0 or tonumber(BarValue(field)) or 0 end
    local multiplier = IsControlKeyDown and IsControlKeyDown() and 10
        or IsShiftKeyDown and IsShiftKeyDown() and 5 or 1
    local value = max(0, min(field.max, current + self.delta * field.step * multiplier))
    value = floor(value / field.step + 0.5) * field.step
    SetField(field, not (field.off and value == 0) and value or nil)
end
local function SwatchClick(self)
    local field = self.row.field
    if Page.SpellField(pop.key, field.key) == self.hex then SetField(field, nil) else SetField(field, self.hex) end
end
local function ColorClick(self)
    local name = self.row.field.color
    local current = Page.SpellField(pop.key, name) or ""
    local function Pick(value)
        local ok, reason = Page.SetSpellField(pop.key, name, value ~= "" and value or nil)
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
local function SoundClick(self)
    local field = self.row.field
    Page.OpenSoundPicker(self, Page.SpellField(pop.key, field.key) or "", function(value)
        SetField(field, value ~= "" and value or nil)
    end)
end
local function PlayClick(self) Page.PlaySound(Page.SpellField(pop.key, self.row.field.key)) end
local function IconCommit(self)
    local text = (self:GetText() or ""):gsub("%s", "")
    local id = tonumber(text)
    self:ClearFocus()
    if text == "" then
        SetField(self.row.field, nil)
    elseif id and id >= 1 and id < 2147483648 and id == floor(id) then
        SetField(self.row.field, id)
    else
        Page.Fail("Enter a texture file ID.")
        Page.PaintPopover()
    end
end

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
local function NumberControls(row, field, x)
    row.minus = Button(row, "-", 22, 20, StepClick)
    row.minus.row, row.minus.delta = row, -1
    row.minus:SetPoint("LEFT", row, "LEFT", x, 0)
    row.value = Label(row, "GameFontHighlightSmall", "")
    row.value:SetWidth(36)
    row.value:SetJustifyH("CENTER")
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
    ShowTip(self, row.label:GetText(), Tr(row.field.help), row.dimmed and Tr(STACK_DIM) or nil)
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
        row.choice:SetPoint("LEFT", row, "LEFT", x, 0)
        if kind == "sound" then
            row.play = Button(row, "Play", 38, 20, PlayClick)
            row.play.row = row
            row.play:SetPoint("LEFT", row.choice, "RIGHT", 2, 0)
        end
    elseif kind == "number" then
        NumberControls(row, field, x)
    elseif kind == "color" then
        row.swatches = {}
        for i, hex in ipairs(SWATCHES) do
            local swatch = NewSwatch(row, SWATCH, SwatchClick)
            swatch:SetPoint("LEFT", row, "LEFT", x + (i - 1) * SWATCH_STEP, 0)
            local r, g, b = P.RGB(hex)
            swatch.fill:SetColorTexture(r, g, b, 1)
            swatch.hex = hex
            row.swatches[i] = swatch
        end
    elseif kind == "icon" then
        local edit = CreateFrame("EditBox", nil, row, "InputBoxTemplate")
        edit:SetSize(80, 20)
        edit:SetAutoFocus(false)
        edit:SetNumeric(true)
        edit:SetMaxLetters(10)
        if T.SkinEditBox then T.SkinEditBox(edit) end
        edit.row = row
        edit:SetPoint("LEFT", row, "LEFT", x + 4, 0)
        edit:SetScript("OnEnterPressed", IconCommit)
        edit:SetScript("OnEscapePressed", ClearFocus)
        row.edit = edit
        row.preview = row:CreateTexture(nil, "ARTWORK")
        row.preview:SetSize(20, 20)
        row.preview:SetPoint("LEFT", edit, "RIGHT", 8, 0)
        row.preview:SetTexCoord(CROP_MIN, CROP_MAX, CROP_MIN, CROP_MAX)
    end
    pop.rows[field.key] = row
    return row
end

local function PaintNumber(row, field, value, companion)
    local shown = value
    if shown == nil then shown = field.off and 0 or tonumber(BarValue(field)) or 0 end
    SetRaw(row.value, field.off and shown == 0 and Tr("Off") or tostring(shown))
    row.value:SetAlpha(value ~= nil and 1 or 0.6)
    if row.hint then row.hint:SetText(value ~= nil and "" or Tr(field.fallback or "Bar")) end
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
    local custom = value ~= nil or companion ~= nil
    row.label:SetText(Tr(pop.family == 2 and field.auraLabel or field.label))
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
        local menu, shown = field.menu, value
        -- A row that follows the bar names the bar's current choice.
        if shown == nil and field.fromBar then shown = field.fromBar[BarValue(field)] end
        local text = menu[1].text
        for i = 1, #menu do if menu[i].value == (shown or 0) then text = menu[i].text end end
        if value == nil and shown ~= nil then
            ButtonText(row.choice, Tr("Bar") .. ": " .. Tr(text))
        elseif value == nil and field.key == "auraUnit" and (pop.unit == "player" or pop.unit == "target") then
            -- What Automatic picked, when the runtime says so.
            ButtonText(row.choice, Tr(pop.unit == "target" and "Automatic: target" or "Automatic: you"))
        else
            row.choice:SetText(Tr(text))
        end
    elseif kind == "number" then
        PaintNumber(row, field, value, companion)
    elseif kind == "color" then
        local ar, ag, ab = Accent()
        for i = 1, #row.swatches do
            local swatch = row.swatches[i]
            if swatch.hex == value then
                swatch.edge:SetColorTexture(ar, ag, ab, 1)
            else
                swatch.edge:SetColorTexture(0, 0, 0, 0.8)
            end
        end
    elseif kind == "sound" then
        ButtonText(row.choice, custom and Page.SoundLabel(value) or Tr("None"))
        row.play:SetEnabled(custom)
    elseif kind == "icon" then
        if not (row.edit.HasFocus and row.edit:HasFocus()) then row.edit:SetText(custom and tostring(value) or "") end
        if value then row.preview:SetTexture(value) else SetIcon(row.preview, pop.texture) end
    end
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

local function EnsurePopover()
    if pop then return pop end
    pop = Page.NewPopup(POP_W, 300)
    Page.popover = pop
    pop.rows, pop.moveValues = {}, {}
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
    pop.remove, pop.move, pop.reset, pop.copy = pop.actions[1], pop.actions[2], pop.actions[3], pop.actions[4]
    for i = 1, #pop.actions do
        local width = T.MeasureButtonWidth and T.MeasureButtonWidth(pop.actions[i], 60, POP_W - 24)
        if type(width) == "number" and width > 0 then pop.actions[i]:SetWidth(width) end
    end
    pop.scope = Label(pop, "GameFontDisableSmall", Tr("These choices apply to this spell on every bar and specialization."),
        "muted")
    pop.scope:SetWidth(POP_W - 24)
    pop.scroll, pop.content = Page.ScrollArea(pop, POP_W - 40)
    pop.OnClosed = function(self)
        for _, row in pairs(self.rows) do if row.edit then row.edit:ClearFocus() end end
        Light(self.anchor, false)
    end
    return pop
end
-- Places the header actions (Copy only for the player's own entries) and
-- returns where the rows start; moves nothing when the set did not change.
local function PlaceActions(copy)
    if pop.placedCopy == copy then return pop.top end
    pop.placedCopy = copy
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
    pop.top = y + 20
    pop.scroll:ClearAllPoints()
    pop.scroll:SetPoint("TOPLEFT", pop, "TOPLEFT", 12, -pop.top)
    pop.scroll:SetPoint("BOTTOMRIGHT", pop, "BOTTOMRIGHT", -26, 10)
    return pop.top
end

function Page.PaintPopover()
    if not pop then return end
    local fields = Page.SpellOverrides().e[pop.key]
    local kind = CDM.EntryKind(pop.key)
    SetIcon(pop.icon, pop.texture)
    SetRaw(pop.title, Public(pop.entryName) and pop.entryName or pop.key)
    SetRaw(pop.sub, Page.BarName(pop.slot) .. "  -  " .. Page.Identity(pop.key))
    pop.reset:SetEnabled(fields ~= nil)
    local top = PlaceActions(kind ~= "b")
    local y = 0
    for i = 1, #FIELDS do
        local field = FIELDS[i]
        local row = pop.rows[field.key]
        if Applies(field, pop.family, kind, pop.hasAura) then
            row = Row(field)
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", pop.content, "TOPLEFT", 0, -y)
            PaintRow(row, fields)
            row:Show()
            y = y + 26
        elseif row then
            row:Hide()
        end
    end
    pop.content:SetHeight(max(1, y))
    pop:SetHeight(min(POP_MAX, top + y + 12))
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
    Page.ClosePopups(pop)
    if pop:IsShown() and pop.anchor ~= anchor then Light(pop.anchor, false) end
    pop.key, pop.slot, pop.family, pop.hasAura = tile.key, Page.selected, tile.family, tile.aura == true
    pop.entryName, pop.texture, pop.unit = tile.name, tile.texture, tile.unit
    Page.PlacePopup(pop, anchor)
    if pop.scroll.SetVerticalScroll then pop.scroll:SetVerticalScroll(0) end
    Page.PaintPopover()
    pop:Show()
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

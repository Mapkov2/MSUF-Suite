-- Package 1: exercise actual pooled controls, codec and settings refreshes.
-- Reuse the existing Menu2 world up to its first popover assertion.
local root = assert(arg[1]):gsub("\\", "/")
local file = assert(io.open(root .. "/tools/tests/suite_cooldown_manager_options_contract.lua", "rb"))
local source = file:read("*a"):gsub("\r\n", "\n")
file:close()
local stop = assert(source:find("------------------------------------------------------------------ per-spell popover", 1, true))
source = source:sub(1, stop - 1) .. [[
return { Page = Page, P = P, CDM = CDM, Config = Config, Fire = Fire, Widget = Widget,
    Grid = grid, Frames = frames, Tooltip = tooltip, Runtime = runtime, Writes = function() return historyWrites end,
    Dropdown = function() return lastDropdown end, Methods = methods, Strict = strict, L = L }
]]
local world = assert(loadstring(source, "@popover-world"))()
-- Font strings wrap like the client's: only when allowed, at most MaxLines
-- lines, about 4 px per character of their width; one line is 14 px.
world.Methods.SetWordWrap = function(self, wrap) self.wordWrap = wrap == true end
world.Methods.SetMaxLines = function(self, lines) self.maxLines = lines end
world.Methods.GetStringHeight = function(self)
    local lines = 1
    if self.wordWrap and (self.width or 0) > 0 then
        lines = math.max(1, math.ceil(#(self.text or "") * 4 / self.width))
        if (self.maxLines or 0) > 0 then lines = math.min(lines, self.maxLines) end
    end
    return lines * 14
end
local Page, CDM, Fire = world.Page, world.CDM, world.Fire
local config, mode = world.Config(), arg[2]
local key = "b1"
local anchor = assert(world.Grid:Tile(key))
local tile = { key = key, family = CDM.FAMILY.COOLDOWN, aura = true, name = "Fireball", texture = 1001 }
local function Open(slot, family, aura)
    if Page.popover and Page.popover:IsShown() then Page.popover:Hide() end
    Page.selected, tile.family, tile.aura = slot or "ess", family or CDM.FAMILY.COOLDOWN, aura ~= false
    assert(Page.TogglePopover(tile, anchor))
    return Page.popover
end
local function Fresh()
    if Page.popover then Page.popover:Hide() end
    Page.spellSpecScope = false
    config.spellsData = ""
    return Open()
end
-- Model the client's synchronous focus events.
local function Focusable(edit)
    edit.ClearFocus = function(self)
        local focused = self.focus
        self.focus = false
        if focused then Fire(self, "OnEditFocusLost") end
    end
    edit.SetFocus = function(self) self.focus = true end
    return edit
end
local function Type(edit, text)
    Focusable(edit):SetFocus()
    edit:SetText(text)
    Fire(edit, "OnTextChanged", true)
end
-- The runtime's text and glow rules (MSUF_Suite_CooldownManager/Const.lua).
local function Runtime()
    local runtime = {}
    local chunk = assert(loadfile(root .. "/MSUF_Suite_CooldownManager/Const.lua"))
    setfenv(chunk, setmetatable({ Constants = { SpellCooldownConsts = { GLOBAL_RECOVERY_CATEGORY = 133 } } }, { __index = _G }))
    chunk("CDM", { CDM = runtime, NS = { CDM = CDM }, Suite = world.P.Suite })
    return runtime.Const
end
local function Pick(row, value)
    Fire(row.choice, "OnClick")
    world.Dropdown().onSelect(value)
end
local function SpecField(field, shared)
    local pop = Fresh()
    assert(Page.SetSpellField(key, field, shared))
    Fire(pop.scopeButton, "OnClick")
    assert(Page.spellSpecScope)
    return pop, pop.rows[field]
end
local tests = {}
function tests.F01_bool()
    local pop, row = SpecField("tts", true)
    Fire(row.off, "OnClick")
    assert(Page.SpellField(key, "tts") == false, "F01: TTS Off inherited shared On")
    assert(CDM.EffectiveSpells(CDM.Codec.DecodeSpells(config.spellsData), Page.Spec())[key].tts == false)
    Fire(row.off, "OnClick")
    assert(Page.SpellField(key, "tts") == false, "an explicit spec choice must remain explicit")
    Fire(row.reset, "OnClick")
    assert(Page.SpellField(key, "tts") == true, "Reset must inherit shared On")
end
-- What the runtime reads for each choice's first entry (the menu's 0).
local FIRST = { swipe = CDM.SWIPE.NORMAL, desat = CDM.CHOICE.BAR, timeText = CDM.CHOICE.BAR,
    stackText = CDM.CHOICE.BAR, textTop = CDM.CHOICE.BAR, auraUnit = 1, actionGlowUnit = 1,
    actionGlowMode = CDM.ACTION_GLOW.PRESENT, stackGlowOp = CDM.STACK_OP.AT_LEAST, glowStyle = 0 }
function tests.F01_choice()
    local pop, row = SpecField("swipe", 2)
    Pick(row, 0)
    assert(Page.SpellField(key, "swipe") == CDM.SWIPE.NORMAL and row.choice.text == "Normal" and row.reset.shown,
        "F01: Normal inherited Reversed")
    Fire(row.reset, "OnClick")
    assert(Page.SpellField(key, "swipe") == 2)
    local K = Runtime()
    for _, field in ipairs(Page.FIELDS) do
        if field.kind == "choice" then
            assert(FIRST[field.key], "F01: say what the runtime reads for the first choice of " .. field.key)
            pop, row = SpecField(field.key, field.menu[#field.menu].value)
            local button = field.inline and pop.rows.stackGlow.op or row.choice
            local shared = config.spellsData
            config.spellsData = ""
            Page.PaintPopover()
            local inherited = button.text
            config.spellsData = shared
            Page.PaintPopover()
            Fire(button, "OnClick")
            world.Dropdown().onSelect(0)
            local effective = CDM.EffectiveSpells(CDM.Codec.DecodeSpells(config.spellsData), Page.Spec())[key]
            assert(Page.SpellField(key, field.key) == FIRST[field.key] and effective[field.key] == FIRST[field.key],
                "F01: the first choice inherited the shared choice: " .. field.key)
            assert(button.text == inherited, "F01: a stored first choice reads differently: " .. field.key)
        end
    end
    -- Glow style 0 is the bar's style, not Blizzard alert (style 1).
    assert(K.GlowSpec({ glowStyle = 0 }, 3) == 3 and K.GlowSpec({ glowStyle = 1 }, 3) == 1 and K.GlowSpec({}, 3) == 3,
        "F01: the runtime must read a specialization's glow style 0 as the bar's style")
    pop = Fresh()
    assert(Page.SetSpellField(key, "glowStyle", 1))
    Fire(pop.rows.glowStyle.choice, "OnClick")
    assert(world.Dropdown().current == 1 and pop.rows.glowStyle.choice.text == "Blizzard alert",
        "F01: a shared Blizzard alert must not read as the bar setting")
end
function tests.F01_step()
    local pop, row = SpecField("stackGlow", 5)
    for _ = 1, 5 do Fire(row.minus, "OnClick") end
    assert(Page.SpellField(key, "stackGlow") == 0 and row.value.text == "Off", "F01: Off inherited shared threshold: " .. tostring(Page.SpellField(key, "stackGlow")) .. "/" .. tostring(row.value.text))
    Fire(row.reset, "OnClick")
    assert(Page.SpellField(key, "stackGlow") == 5)
end
function tests.F01_sound()
    local pop, row = SpecField("sound", "kit:316406")
    local original, selected = Page.OpenSoundPicker
    Page.OpenSoundPicker = function(_, _, pick) selected = pick end
    Fire(row.choice, "OnClick")
    selected("")
    Page.OpenSoundPicker = original
    assert(Page.SpellField(key, "sound") == "" and row.choice.text == "None" and not row.play.enabled,
        "F01: None inherited shared sound")
    Fire(row.reset, "OnClick")
    assert(Page.SpellField(key, "sound") == "kit:316406")
end
-- A specialization follows the bar's glow color and the default stack color
-- over shared colors ("", which the runtime reads as no own color).
local function Effective()
    return CDM.EffectiveSpells(CDM.Codec.DecodeSpells(config.spellsData), Page.Spec())[key]
end
local function Selected(row)
    for i = 1, #row.swatches do
        if row.swatches[i]:IsShown() and row.swatches[i].edge.color[1] == 0.2 then return i end
    end
end
function tests.F01_color()
    local K = Runtime()
    local pop, row = SpecField("glowColor", "ff4d4d")
    assert(Selected(row) == 3)
    Fire(row.swatches[3], "OnClick")
    assert(Page.SpellField(key, "glowColor") == "" and Effective().glowColor == "" and row.reset.shown
        and Selected(row) == nil, "F01: following the bar inherited the shared glow color")
    local style, r, g, b = K.GlowSpec(Effective(), 2, true, 0.1, 0.2, 0.3)
    assert(style == 2 and r == 0.1 and g == 0.2 and b == 0.3, "F01: the runtime must tint with the bar's glow color")
    assert(K.GlowSpec(Effective(), 2) == 2 and select("#", K.GlowSpec(Effective(), 2)) == 1, "F01: no tint: the art's gold")
    Fire(row.swatches[5], "OnClick")
    assert(Page.SpellField(key, "glowColor") == "4db8ff" and Selected(row) == 5)
    Fire(row.reset, "OnClick")
    assert(Page.SpellField(key, "glowColor") == "ff4d4d" and Selected(row) == 3, "F01: Reset must inherit the shared glow color")
    Page.spellSpecScope = false
    Page.PaintPopover()
    Fire(row.swatches[3], "OnClick")
    assert(Page.SpellField(key, "glowColor") == nil and Selected(row) == nil, "a shared color clicked again follows the bar")
    -- The stack color: Default in a specialization over a shared color.
    pop = Fresh()
    row = pop.rows.stackColorAt
    assert(Page.SetSpellField(key, "stackColorAt", 3) and Page.SetSpellField(key, "stackColor", "4dff73"))
    Fire(pop.scopeButton, "OnClick")
    Fire(row.swatch, "OnClick")
    assert(world.Dropdown().current == "4dff73")
    world.Dropdown().onSelect("")
    local dr, dg, db = world.P.RGB(CDM.SPELL_DEFAULTS.stackColor)
    local fill = row.swatch.fill.color
    assert(Page.SpellField(key, "stackColor") == "" and Effective().stackColor == "" and row.reset.shown
        and fill[1] == dr and fill[2] == dg and fill[3] == db, "F01: Default inherited the shared stack color")
    Fire(row.swatch, "OnClick")
    assert(world.Dropdown().current == "", "F01: an explicit default must show as Default")
    Fire(row.reset, "OnClick")
    assert(Page.SpellField(key, "stackColor") == "4dff73" and Page.SpellField(key, "stackColorAt") == 3,
        "F01: Reset must inherit the shared stack color")
end
function tests.F03()
    local pop = Fresh()
    local K = Runtime()
    for _, switches in ipairs({ { true, false }, { false, true }, { false, false }, { true, true } }) do
        config.ess_stackText, config.ess_charges = switches[1], switches[2]
        Page.PaintPopover()
        local shown = K.BarStacks({ stackText = switches[1], charges = switches[2] }, true)
        assert(pop.rows.stackText.choice.text == (shown and "Bar: Show" or "Bar: Hide"), "F03: combined charges hint")
    end
    for _, slot in ipairs({ "bar", "c1" }) do
        config.c1_kind, config.c1_cooldownDuration = CDM.KIND.COOLDOWN, true
        Open(slot, slot == "bar" and CDM.FAMILY.AURA or CDM.FAMILY.COOLDOWN)
        for _, switches in ipairs({ { true, false }, { false, true }, { false, false }, { true, true } }) do
            config[CDM.KEYS[slot].cdText], config[CDM.KEYS[slot].barTime] = switches[1], switches[2]
            Page.PaintPopover()
            local shown = K.BarTime({ kind = Page.Kind(slot), cooldownDuration = slot == "c1",
                cdText = switches[1], barTime = switches[2] })
            assert(pop.rows.timeText.choice.text == (shown and "Bar: Show" or "Bar: Hide"), "F03: combined countdown hint")
        end
    end
end
function tests.U04()
    local pop = Fresh()
    local keys = { "actionGlowSpell", "actionGlowRequireSpell", "requireSpell1", "excludeSpell1",
        "requireSpell2", "excludeSpell2", "requireSpell3", "excludeSpell3", "icon" }
    local writes = world.Writes()
    for _, field in ipairs(keys) do
        local edit = pop.rows[field].edit
        Type(edit, field == "icon" and "12345" or "Fireball")
        edit:ClearFocus()
        local expected = field == "icon" and 12345 or 133
        assert(Page.SpellField(key, field) == expected, "U04: blur lost " .. field)
        Type(edit, field == "icon" and "54321" or "Frost Nova")
        Fire(edit, "OnEscapePressed")
        assert(Page.SpellField(key, field) == expected and not edit.dirty, "U04: Escape committed " .. field)
        Type(edit, field == "icon" and "0" or "bogus spell")
        edit:ClearFocus()
        Page.PaintPopover()
        assert(edit:GetText() == (field == "icon" and "0" or "bogus spell") and Page.noteError,
            "U04: invalid input disappeared: " .. field)
        Fire(edit, "OnEscapePressed")
    end
    assert(world.Writes() == writes + #keys, "blur or Escape committed twice")
    local edit = pop.rows.actionGlowSpell.edit
    Type(edit, "Frost Nova")
    pop:Hide()
    assert(Page.SpellField(key, "actionGlowSpell") == 122 and world.Writes() == writes + #keys + 1,
        "U04: closing lost input or committed twice")
    Open("bar", CDM.FAMILY.AURA)
    edit = pop.rows.timerSpell.edit
    Type(edit, "Fireball")
    Fire(edit, "OnEnterPressed")
    assert(Page.SpellField(key, "timerSpell") == 133 and world.Writes() == writes + #keys + 2,
        "U04: Enter followed by blur committed twice")
    Type(edit, "bogus spell")
    pop:Hide()
    Open("bar", CDM.FAMILY.AURA)
    assert(edit:GetText() == "bogus spell" and edit.dirty, "U04: reopening must retain invalid input for correction")
    Fire(edit, "OnEscapePressed")
    assert(edit:GetText() == "Fireball", "U04: Escape must restore the stored name")
    Type(edit, "Frost Nova")
    Fire(pop.scopeButton, "OnClick")
    assert(Page.spellSpecScope and Page.SpellOverrides().e[key].timerSpell == 122,
        "U04: scope switch must commit under the old scope")
end
-- Typed text belongs to its entry, and a reset drops it.
function tests.U04_entries()
    local pop = Fresh()
    local row = pop.rows.actionGlowSpell
    Type(row.edit, "bogus spell")
    row.edit:ClearFocus()
    pop:Hide()
    assert(Page.TogglePopover({ key = "b2", family = CDM.FAMILY.COOLDOWN, aura = true }, anchor) and pop:IsShown()
        and pop.key == "b2", "U04: invalid input of a closed popover blocked another entry")
    assert(row.edit:GetText() == "" and not row.edit.dirty, "U04: typed text moved to another entry")
    Type(row.edit, "Frost Nova")
    assert(Page.TogglePopover({ key = key, family = CDM.FAMILY.COOLDOWN, aura = true }, anchor) and pop.key == key)
    assert(Page.SpellField("b2", "actionGlowSpell") == 122 and Page.SpellField(key, "actionGlowSpell") == nil
        and row.edit:GetText() == "", "U04: switching entries must store typed input on its own entry")
    assert(Page.SetSpellField(key, "actionGlowSpell", 133))
    Type(row.edit, "bogus spell")
    row.edit:ClearFocus()
    Fire(row.reset, "OnClick")
    assert(Page.SpellField(key, "actionGlowSpell") == nil and row.edit:GetText() == "" and not row.edit.dirty,
        "U04: Reset must drop typed text")
end
function tests.U10()
    local pop = Fresh()
    for _, field in ipairs({ "readyAlpha", "cdAlpha", "threshold", "stackGlow", "stackColorAt" }) do
        local row = pop.rows[field]
        Fire(row.value, "OnClick")
        local edit = assert(row.edit, "U10: number has no inline edit: " .. field)
        Type(edit, "9999")
        Fire(edit, "OnEnterPressed")
        assert(Page.SpellField(key, field) == row.field.max, "U10: clamp failed")
        Fire(row.value, "OnClick")
        Type(edit, "2.7")
        edit:ClearFocus()
        assert(Page.SpellField(key, field) == 3, "U10: step rounding failed")
        Fire(row.value, "OnClick")
        Type(edit, "9")
        Fire(edit, "OnEscapePressed")
        assert(Page.SpellField(key, field) == 3 and not edit:IsShown() and row.value:IsShown(), "U10: cancel failed")
    end
    Fire(pop.rows.stackGlow.value, "OnClick")
    Type(pop.rows.stackGlow.edit, "0")
    pop.rows.stackGlow.edit:ClearFocus()
    assert(Page.SpellField(key, "stackGlow") == nil, "U10: 0 must disable shared off fields")
    Open("bar", CDM.FAMILY.AURA)
    local row = pop.rows.timerDuration
    Fire(row.value, "OnClick")
    Type(row.edit, "601")
    row.edit:ClearFocus()
    assert(Page.SpellField(key, "timerDuration") == 600)
    Open()
    assert(Page.SetSpellField(key, "stackGlow", 5))
    Fire(pop.scopeButton, "OnClick")
    row = pop.rows.stackGlow
    Fire(row.value, "OnClick")
    Type(row.edit, "0")
    row.edit:ClearFocus()
    assert(Page.SpellField(key, "stackGlow") == 0, "U10: typed spec Off must override shared threshold")
    Fire(row.reset, "OnClick")
    assert(Page.SpellField(key, "stackGlow") == 5)
    local other = assert(world.Grid:Tile("b2"))
    assert(Page.TogglePopover({ key = "b2", family = CDM.FAMILY.COOLDOWN, aura = true }, other))
    pop:Hide()
    assert(Page.SpellField("b2", "stackGlow") == nil, "U10: a hidden number editor wrote into the next entry")
    -- Leaving the box unchanged closes it; invalid text goes back on leaving
    -- and stays open for correction on Enter.
    pop = Fresh()
    row = pop.rows.readyAlpha
    Fire(row.value, "OnClick")
    Focusable(row.edit):SetFocus()
    row.edit:ClearFocus()
    assert(not row.edit:IsShown() and row.value:IsShown(), "U10: an unchanged number box stayed open")
    Fire(row.value, "OnClick")
    Type(row.edit, "abc")
    Fire(row.edit, "OnEnterPressed")
    assert(row.edit:IsShown() and row.edit:GetText() == "abc" and Page.noteError, "U10: Enter dropped invalid text")
    row.edit:ClearFocus()
    assert(not row.edit:IsShown() and row.value:IsShown() and Page.SpellField(key, "readyAlpha") == nil
        and not row.edit.dirty, "U10: invalid text left in a number box must go back to the stored value")
end
-- Longer translations (here: German-length stand-ins) wrap instead of
-- running past the 150 px label column and the scope line.
local LABEL = "Ready glow requires enough resources"
local SCOPE = "These choices apply to this spell on every bar and specialization."
function tests.U11()
    local pop = Fresh()
    local row, below = pop.rows.readyResources, pop.rows.fullChargeGlow
    local before, top = below.points[1][5], pop.top
    assert(row:GetHeight() == 24, "U11: a one-line label keeps its row")
    world.L[LABEL] = "Leuchten bei Bereitschaft erfordert genug Ressourcen"
    Page.PaintPopover()
    assert(row:GetHeight() == 32 and below.points[1][5] == before - 8, "U11: wrapped label did not grow its row")
    assert(row.tip:GetHeight() == 32 and row.label.points[1][1] == "LEFT", "U11: row must stay centered")
    world.L[LABEL] = "Leuchten bei Bereitschaft erfordert genug Ressourcen, sonst bleibt das Symbol ohne Leuchten stehen"
    Page.PaintPopover()
    assert(row:GetHeight() == 32, "U11: a label wraps to two lines at most")
    world.L[SCOPE] = "Diese Auswahl gilt fuer diesen Zauber auf jeder Leiste und in jeder Spezialisierung deines Charakters."
    Page.PaintPopover()
    assert(pop.scope:GetHeight() == 28 and pop.top == top + 14, "U11: scope must wrap and move the rows below it")
    world.L[LABEL], world.L[SCOPE] = nil, nil
    Page.PaintPopover()
    assert(row:GetHeight() == 24 and pop.top == top and below.points[1][5] == before, "U11: rows return to one line")
end
function tests.U17()
    local pop = Fresh()
    assert(Page.SetSpellField(key, "glowColor", "12AbEf"))
    local swatch = pop.rows.glowColor.swatches[9]
    assert(swatch and swatch:IsShown() and swatch.hex == "12abef" and swatch.edge.color[1] == 0.2,
        "U17: imported color has no selected ninth swatch")
    Fire(swatch, "OnEnter")
    assert(world.Tooltip.text:find("#12abef", 1, true), "U17: custom color tooltip must name hex")
    -- Like any chosen swatch, clicked it follows the bar: cleared, or stored
    -- as "" by a specialization over the shared color.
    local frames = #world.Frames
    Fire(swatch, "OnClick")
    assert(Page.SpellField(key, "glowColor") == nil and not swatch:IsShown() and #world.Frames == frames,
        "U17: the imported swatch clicked must follow the bar")
    assert(Page.SetSpellField(key, "glowColor", "12AbEf"))
    Fire(pop.scopeButton, "OnClick")
    Fire(swatch, "OnClick")
    assert(Page.SpellOverrides().e[key].glowColor == "12AbEf" and Page.SpellField(key, "glowColor") == ""
        and not swatch:IsShown(), "U17: a specialization must follow the bar over the imported color")
    Fire(pop.scopeButton, "OnClick")
    assert(Page.SetSpellField(key, "glowColor", "FF4D4D"))
    assert(not swatch:IsShown() and pop.rows.glowColor.swatches[3].edge.color[1] == 0.2)
    Fire(pop.rows.glowColor.swatches[3], "OnClick")
    assert(not swatch:IsShown() and Page.SpellField(key, "glowColor") == nil, "U17: chosen imported swatch must reset")
end
-- The popover's files load in their TOC order, from nothing of each
-- other, into a working popover.
local SPLIT_EXPORTS = { "FIELDS", "PreparePopoverFields", "PaintPopoverInput", "InitPopoverInput",
    "FlushPopoverInputs", "BeginPopoverNumber", "NewPopoverEdit", "PaintPopover", "TogglePopover", "popover" }
function tests.SPLIT()
    local handle = assert(io.open(root .. "/MSUF_Suite_Options/MSUF_Suite_Options_Mainline.toc", "rb"))
    local toc = handle:read("*a")
    handle:close()
    local files = {}
    for file in toc:gmatch("(Pages\\CooldownManagerPopover%w*%.lua)") do files[#files + 1] = file:gsub("\\", "/") end
    assert(#files == 3, "SPLIT: the TOC must list the popover and its two helper files")
    if Page.popover then Page.popover:Hide() end
    for _, name in ipairs(SPLIT_EXPORTS) do Page[name] = nil end
    for _, file in ipairs(files) do
        local chunk = assert(loadfile(root .. "/MSUF_Suite_Options/" .. file))
        setfenv(chunk, world.Strict)
        chunk("MSUF_Suite_Options", world.P)
    end
    local pop = Fresh()
    assert(pop and pop:IsShown() and #Page.FIELDS > 40 and pop.rows.glowColor and pop.rows.actionGlowSpell.edit,
        "SPLIT: the popover's files did not load into a working popover")
    Type(pop.rows.actionGlowSpell.edit, "Fireball")
    pop.rows.actionGlowSpell.edit:ClearFocus()
    Fire(pop.rows.readyAlpha.value, "OnClick")
    assert(Page.SpellField(key, "actionGlowSpell") == 133 and pop.rows.readyAlpha.edit:IsShown(),
        "SPLIT: inputs and number boxes must work after the split")
    pop:Hide()
end
function tests.SECTIONS()
    local pop = Fresh()
    local expected = { "Glow", "Appearance", "Buff and stacks", "Action bars", "Text", "Custom timer", "Sounds", "Conditions" }
    assert(Page.POPOVER_SECTIONS and #Page.POPOVER_SECTIONS == #expected, "SECTIONS: missing section model")
    for i, section in ipairs(Page.POPOVER_SECTIONS) do
        assert(section.label == expected[i])
        local visible, last = false, nil
        for _, field in ipairs(Page.FIELDS) do
            local row = pop.rows[field.key]
            if field.section == section and row and row:IsShown() then
                visible = true
                local y = row.points[1][5]
                if last then assert(y == last - 26, "SECTIONS: broken row adjacency") end
                last = y
            end
        end
        local header = pop.headers[section]
        assert((header and header:IsShown() or false) == visible, "SECTIONS: empty header")
    end
    for _, field in ipairs(Page.FIELDS) do
        assert(field.section and (" " .. field.section.keys .. " "):find(" " .. field.key .. " ", 1, true),
            "SECTIONS: no section names " .. field.key)
    end
    local frames = #world.Frames
    Page.PaintPopover()
    assert(#world.Frames == frames, "SECTIONS: headers must be pooled")
    Open("bar", CDM.FAMILY.AURA)
    assert(pop.headers[Page.POPOVER_SECTIONS[6]]:IsShown(), "SECTIONS: timer section missing")
    Open("ess", CDM.FAMILY.COOLDOWN, false)
    assert(not pop.headers[Page.POPOVER_SECTIONS[6]]:IsShown(), "SECTIONS: empty timer header persists")
end
local order = { "SPLIT", "SECTIONS", "F01_bool", "F01_choice", "F01_step", "F01_sound", "F01_color", "F03", "U04", "U04_entries",
    "U10", "U11", "U17" }
for _, name in ipairs(order) do
    if not mode or mode == name then tests[name](); print("PASS popover " .. name) end
end

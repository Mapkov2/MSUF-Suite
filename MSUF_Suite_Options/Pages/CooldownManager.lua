local _, P = ...
-- Cooldown manager page: one home for every bar. The docked preview shows the
-- selected bar and edits its spells. Frame Basics holds the module switch,
-- what applies to every bar, and the bar being edited with its name, type
-- and actions. The sections below edit that bar through custom bar 1's
-- rules, which Page.KeyFn maps from c1_<setting> to <selected bar>_<setting>.
local Page = P.CDMPage
if not Page then return end
local Suite, S, M, W, T, Tr = P.Suite, P.S, P.M, P.W, P.T, P.Tr
local ID, PAGE = Page.ID, Page.PAGE
local CDM = Suite.CDM
local RULES, SLOTS, KEYS = P.catalog[ID].rules, CDM.SLOTS, CDM.KEYS
local max, min, ceil, floor, format = math.max, math.min, math.ceil, math.floor, string.format
local MODULE_SECTION = PAGE .. "_" .. ID .. "_module"

local HELP = {
    general = "These apply to every bar.",
    bars = "The preview and every section below edit this bar.",
    basics = "The settings you change most. Attach the bar to another bar or to your player frame to keep them together; the gap is the space between them.",
    spells = "Every spell of this bar, unlearned ones included. The preview edits them too: click a spell for its own options, drag to reorder or onto a bar above, middle-click removes it (with undo). Removed spells stay listed under Add spells, where a click brings one back. Lists are kept per specialization.",
    layout = "How the icons line up and grow. A free bar's position counts from the screen center; an attached bar's is an offset from its attach point.",
    look = "Icon crop, border, swipe and frame layer of this bar.",
    text = "Which numbers show, which one is drawn on top, and their size and place. Single spells can differ: click them in the preview. The font settings below apply to every bar; Slug has no shadow.",
    effects = "How cooldown icons react. Single spells can differ: click them in the preview.",
    buffs = "Buff icons and timer bars: missing buffs, fixed places and highlights.",
    barstyle = "Size and look of timer bars. Used when the bar type is Timer bar.",
    visibility = "When this bar shows, and how far it fades out of combat. Tooltips show a spell when you hover its icon. This page and MSUF Edit Mode always show every bar.",
}
-- Per-bar settings by topic; every custom bar 1 rule appears exactly once.
-- Basics holds the most used ones (attachment complete) and stays open; the
-- rest start closed. The bar's name and type sit in Frame Basics.
local SECTIONS = {
    { id = "basics", title = "Basics", open = true, suffixes = { "on", "size", "perRow", "anchor", "side", "gap", "align",
        "alpha" } },
    { id = "layout", title = "Layout", suffixes = { "height", "spacing", "maxIcons", "vertical", "grow", "x", "y" } },
    { id = "look", title = "Look", suffixes = { "zoom", "border", "borderColor", "borderClass", "swipeAlpha", "edge",
        "strata" } },
    { id = "text", title = "Text", module = "text", suffixes = { "cdText", "cdSize", "stackText", "stackSize", "textTop",
        "stackPos", "keybind", "keybindSize", "keybindPos" } },
    { id = "effects", title = "Cooldown effects", suffixes = { "desat", "cdAlpha", "readyAlpha", "hideReady", "procGlow",
        "readyGlow", "glowStyle", "glowTint", "glowColor", "usable", "range", "rangeColor", "showAura", "charges",
        "assist", "bling" } },
    { id = "buffs", title = "Buffs", suffixes = { "showMissing", "keepSlots", "auraGlow", "pandemic" } },
    { id = "barstyle", title = "Timer bar style", suffixes = { "barWidth", "barHeight", "barTexture", "barColor",
        "barClass", "barBgAlpha", "barIcon", "barIconSide", "barName", "barTime", "barFill" } },
    { id = "visibility", title = "Visibility", suffixes = { "vis", "oocAlpha", "hideMounted", "hideVehicle", "tooltips" } },
}
local CARD_SUFFIXES = { "name", "kind" }
Page.SECTIONS, Page.CARD_SUFFIXES = SECTIONS, CARD_SUFFIXES
-- Only settings the catalog has. One it adds that no section names joins
-- Cooldown effects, so every rule keeps exactly one control.
do
    local listed, effects = {}, nil
    for _, suffix in ipairs(CARD_SUFFIXES) do listed[suffix] = true end
    for _, spec in ipairs(SECTIONS) do
        local kept = {}
        for _, suffix in ipairs(spec.suffixes) do
            if KEYS.c1[suffix] and not listed[suffix] then kept[#kept + 1], listed[suffix] = suffix, true end
        end
        spec.suffixes = kept
        if spec.id == "effects" then effects = spec end
    end
    for _, rule in ipairs(P.SectionRules(ID, "c1")) do
        if rule.suffix and not listed[rule.suffix] then
            effects.suffixes[#effects.suffixes + 1], listed[rule.suffix] = rule.suffix, true
        end
    end
end
-- Frame Basics: Blizzard's bars and sounds share a row, then the switches.
local GENERAL_ORDER = { "blizzard", "raidEssentials", "soundChannel", "showGCD", "muteSounds", "readyGlowCombat" }

------------------------------------------------------------------ selected-bar rows
-- Choice lists that follow the selected bar are edited in place: SettingsRows
-- resolves a row's list once, the dropdown reads the same table on open.
local growValues = { { value = 1, text = "Down" }, { value = 2, text = "Up" } }
local anchorValues = {}
-- Why an attach target is greyed; built on hover only.
local function AnchorTip(item)
    if item.own then return Tr("A bar cannot attach to itself.") end
    if item.loopOf then
        return format(Tr("%s follows this bar. Attaching this bar to it would make a loop."), Page.BarName(item.loopOf))
    end
end
for i, label in ipairs(CDM.ANCHOR_LABELS) do
    anchorValues[i] = { value = i, text = label }
    if i >= 2 and i <= #SLOTS + 1 then anchorValues[i].tooltip = AnchorTip end
end
local kindValues = {}
for i, name in ipairs(Page.KIND_NAMES) do kindValues[i] = { value = i, text = name } end
-- Blizzard's cooldown bars: each choice explains itself, and the current one
-- also says what the runtime does right now.
local BLIZZARD_TIPS = {
    "Blizzard's Cooldown Manager stops completely. While your MSUF frames follow its bars, MSUF keeps it running invisibly.",
    "Blizzard's bars keep running, invisible, so frames that other addons attach to them stay in place.",
}
local function BlizzardTip(item)
    local tip = Tr(BLIZZARD_TIPS[item.value] or "")
    local status = P.Get(ID, "blizzard") == item.value and S.CooldownManagerStatus and S.CooldownManagerStatus()
    if type(status) == "string" and status ~= "" then tip = tip .. "\n\n" .. Tr("Right now:") .. " " .. status end
    return tip
end
local blizzardValues = {}
for i, choice in ipairs(RULES.blizzard and RULES.blizzard.choices or {}) do
    blizzardValues[i] = { value = i, text = choice, tooltip = BlizzardTip }
end

local function PaintChoices()
    local vertical = Page.Relevant(Page.selected, "vertical") and P.Get(ID, Page.Key("vertical")) == true
    growValues[1].text = vertical and "Right" or "Down"
    growValues[2].text = vertical and "Left" or "Up"
    -- Bar targets carry the bars' own names; MSUF frame targets keep theirs.
    -- A bar that already follows this one would close a loop.
    for i = 2, #SLOTS + 1 do
        local slot = SLOTS[i - 1].key
        local item = anchorValues[i]
        local own = slot == Page.selected
        local loop = not own and Page.Follows(slot, Page.selected)
        item.text, item.translate = Page.BarName(slot), false
        item.disabled, item.own, item.loopOf = own or loop, own or nil, loop and slot or nil
    end
end

-- Grow direction and orientation go through the runtime so the bar keeps its
-- place on screen (it returns the matching position change).
local function ConvertSet(suffix, value)
    local key = Page.Key(suffix)
    if not key or P.Combat() then return end
    local convert = suffix == "grow" and S.CooldownManagerConvertGrow or S.CooldownManagerConvertVertical
    local values = convert and convert(Page.selected, value)
    if type(values) == "table" and next(values) ~= nil then
        if values[key] == nil then values[key] = value end
        if P.SetMany(ID, values) then return end
    end
    P.Set(ID, key, value)
end

-- Attach changes go through the runtime too: the bar stays where it is
-- (free) or starts flush on its new anchor (zero offset).
local function AnchorSet(value)
    local key = Page.Key("anchor")
    if not key or P.Combat() then return end
    local values = S.CooldownManagerConvertAnchor and S.CooldownManagerConvertAnchor(Page.selected, value)
    if type(values) == "table" and next(values) ~= nil and P.SetMany(ID, values) then return end
    P.Set(ID, key, value)
end

local function RuleGrid(ctx, body, rules, y, width, sectionId)
    local rows, bound, strings = {}, {}, {}
    for _, rule in ipairs(rules) do
        local row = not rule.color and P.RuleRow(PAGE, ID, rule, Page.KeyFn, sectionId)
        if row then
            if rule.key == KEYS.c1.grow then
                row.values = growValues
                row.set = function(value) ConvertSet("grow", tonumber(value) or rule.default) end
            elseif rule.key == KEYS.c1.vertical then
                row.set = function(value) ConvertSet("vertical", value == true) end
            elseif rule.key == KEYS.c1.anchor then
                row.values = anchorValues
                row.set = function(value) AnchorSet(tonumber(value) or rule.default) end
            elseif rule.key == "blizzard" and #blizzardValues > 0 then
                row.values = blizzardValues
            end
            rows[#rows + 1], bound[#bound + 1] = row, rule
        elseif not rule.color and type(rule.default) == "string" then
            strings[#strings + 1] = rule
        end
    end
    local entries = {}
    if #rows > 0 then
        local grid = W.SettingsRows(ctx, body, { x = 16, y = y, width = width, columns = 2, rows = rows })
        for _, rule in ipairs(bound) do entries[#entries + 1] = { rule = rule, widget = grid.controls[rule.key] } end
        y = grid.bottomY
    end
    for _, rule in ipairs(strings) do
        -- Commit on blur writes to the bar the input was focused on.
        local input
        input = M.BindTextInputAt(ctx, body, Tr(rule.label), 16, y, width,
            function() return P.Get(ID, Page.InputKey(input, rule.key)) end,
            function(value) P.Set(ID, Page.InputKey(input, rule.key), value or "") end, true,
            P.Meta(PAGE, ID, rule.key, "setting", sectionId))
        Page.TrackInput(input)
        if input.SetMaxLetters and rule.maxLength then input:SetMaxLetters(rule.maxLength) end
        entries[#entries + 1] = { rule = rule, widget = input }
        y = y - 58
    end
    P.GateControls(ctx, ID, entries, Page.KeyFn)
    return y, entries
end

local function Help(body, text, y, width)
    local label = P.Text(body, text, 16, y, width)
    return y - max(14, ceil(label:GetStringHeight() or 14)) - 8
end
local function Divider(body, y)
    if W.DividerAt then W.DividerAt(body, y + 4, 16, 16) end
end
-- Section headers name the bar they edit. A section the bar does not use
-- keeps its plain title and a muted badge instead. Writes only on change.
local NO_BADGES = {}
local function Header(body, title, unused, kind)
    local entry = body._msuf2CollapsibleEntry
    if not (entry and entry.label) then return end
    local name = Page.BarName(Page.selected)
    if body._cdmName == name and body._cdmUnused == unused and body._cdmKind == kind then return end
    body._cdmName, body._cdmUnused, body._cdmKind = name, unused, kind
    Page.SetRaw(entry.label, unused and Tr(title) or (Tr(title) .. ": " .. name))
    if W.SetCollapsibleBadges then
        W.SetCollapsibleBadges(body, unused and { { text = format(Tr("Not used by %s"), kind), kind = "muted",
            showWhenClosed = true } } or NO_BADGES)
    end
end

-- Why controls of a section are greyed: 1 unavailable, 2 module off, 3 all
-- used, 4 none used by this bar type, 5 as 4 but the module part below
-- works, 6 some unused.
local function SectionState(spec)
    local ok, why = S.Availability(ID)
    if not ok then return 1, why end
    if not P.Get(ID, "enabled") then return 2 end
    local unused = 0
    for i = 1, #spec.suffixes do
        if not Page.Relevant(Page.selected, spec.suffixes[i]) then unused = unused + 1 end
    end
    if unused == 0 then return 3 end
    if unused == #spec.suffixes then return spec.module and 5 or 4 end
    return 6
end
local function StateText(state, why, kind)
    if state == 1 then return Tr(why or "Unavailable on this client") end
    if state == 2 then return Tr("Turn the cooldown manager on in Frame Basics to edit these.") end
    if state == 4 then return format(Tr("Not used by the %s type. Pick another bar to edit these."), kind) end
    if state == 5 then
        return format(Tr("This bar's own options are not used by the %s type; the settings below apply to every bar."), kind)
    end
    if state == 6 then return Tr("Greyed options are not used by this bar type.") end
    return ""
end
-- A color edits nothing while its bar does not use it or its own switch
-- (Tint glows, Class-colored border, ...) says otherwise.
local function ColorEnabled(rule) return P.RuleEnabled(ID, rule, Page.KeyFn) end

local function BuildSection(ctx, b, ui, spec)
    local sectionId = "suite_cooldownManager_" .. spec.id
    local body = b:CollapsibleSection(sectionId, Tr(spec.title), 120, spec.open == true)
    local width = max(240, (body._msuf2Width or b.width or 720) - 32)
    local y = Help(body, HELP[spec.id], -18, width)
    local unused = P.Text(body, "", 16, y, width, T.colors.dim or T.colors.muted)
    y = y - 20
    -- The attach list (Basics) and grow list (Layout) are repainted before the
    -- dropdowns that show them read their captions (refreshers run in order).
    if spec.id == "basics" then M.TrackRefresh(ctx, function() if not P.Combat() then PaintChoices() end end) end
    local rules = {}
    for i, suffix in ipairs(spec.suffixes) do rules[i] = RULES[KEYS.c1[suffix]] end
    y = RuleGrid(ctx, body, rules, y, width, sectionId)
    if spec.module then
        P.Text(body, "These apply to every bar:", 16, y - 6, width, T.colors.text)
        local shared = P.SectionRules(ID, spec.module)
        y = RuleGrid(ctx, body, shared, y - 28, width, sectionId)
        for _, rule in ipairs(shared) do rules[#rules + 1] = rule end
    end
    P.AttachRuleColors(body, spec.title, ID, rules, Page.KeyFn, ColorEnabled)
    P.AttachSectionReset(ctx, body, spec.title, function()
        return P.ResetRules(ID, rules, Page.KeyFn)
    end)
    if spec.id == "layout" then
        local half = floor((width - 12) / 2)
        -- Navigation needs no snapshot; the reset records its own history entry.
        P.Button(ctx, body, "Move this bar on screen", 16, y - 4, half, function() P.MoveOnScreen(ID, Page.selected) end,
            function() return S.Availability(ID) and P.Get(ID, "enabled") and Page.IsOn(Page.selected) and Page.Movable(Page.selected) end,
            P.Meta(PAGE, ID, "editor.move", "action", sectionId))._msuf2SkipHistoryCheckpoint = true
        P.Button(ctx, body, "Reset this bar's settings", 28 + half, y - 4, half, function() Page.ResetBar(Page.selected) end,
            function() return S.Availability(ID) and true or false end,
            P.Meta(PAGE, ID, "editor.reset", "action", sectionId))._msuf2SkipHistoryCheckpoint = true
        y = y - 40
    end
    ui.sections[spec.id] = body
    M.TrackRefresh(ctx, function()
        if P.Combat() then return end
        local state, why = SectionState(spec)
        local kind = Page.KindName(Page.Kind(Page.selected))
        if body._cdmState ~= state or body._cdmStateKind ~= kind then
            body._cdmState, body._cdmStateKind = state, kind
            Page.SetRaw(unused, StateText(state, why, kind))
        end
        Header(body, spec.title, state == 4, kind)
    end)
    P.FinishBody(b, body, y)
    return body
end

------------------------------------------------------------------ bar choice
local SIDES = { "below", "above", "left of", "right of" }
function Page.Summary(slot)
    local keys = KEYS[slot]
    local text = Page.KindName(Page.Kind(slot))
    local anchor = P.Get(ID, keys.anchor)
    local parent = anchor > 1 and SLOTS[anchor - 1]
    local target = parent and Page.BarName(parent.key) or CDM.FRAME_ANCHORS[anchor] and Tr(CDM.ANCHOR_LABELS[anchor])
    if target then
        text = text .. "  -  " .. format(Tr("attached %s %s"), Tr(SIDES[P.Get(ID, keys.side)] or SIDES[1]), target)
        if parent and Page.InLoop(slot) then
            -- Old settings may hold a loop: the runtime places such bars freely.
            text = text .. " (" .. Tr("the attachments form a loop, so it is placed freely") .. ")"
        elseif parent and not Page.IsOn(parent.key) then
            -- A bar attached to a bar that is off follows the next shown bar
            -- up the chain, or takes the place of the bar that is off.
            local shown, standIn = Page.Chain(slot)
            text = text .. " (" .. Tr("off") .. ")"
            if shown then
                text = text .. ", " .. format(Tr("follows %s"), Page.BarName(shown))
            elseif standIn then
                text = text .. ", " .. format(Tr("takes the place of %s"), Page.BarName(standIn))
            end
        end
    else
        text = text .. "  -  " .. Tr("placed freely")
    end
    if not Page.IsOn(slot) then text = text .. "  -  " .. Tr("off") end
    return text
end

-- Frame Basics, after the module actions: what applies to every bar.
local function BuildGeneral(ctx, card)
    local width = max(240, (card._msuf2Width or 720) - 32)
    local y = min(tonumber(card._msuf2CursorY) or -80, -40)
    Divider(card, y)
    y = Help(card, HELP.general, y - 8, width)
    local rules, seen = {}, {}
    for _, key in ipairs(GENERAL_ORDER) do
        local rule = RULES[key]
        if rule and rule.section == "general" then rules[#rules + 1], seen[key] = rule, true end
    end
    for _, rule in ipairs(P.SectionRules(ID, "general")) do
        if not seen[rule.key] then rules[#rules + 1] = rule end
    end
    card._msuf2CursorY = RuleGrid(ctx, card, rules, y, width, MODULE_SECTION)
end

-- The bar's name (custom bars) and type, next to the bar choice.
local function BuildIdentity(ctx, ui, body, y, half)
    local nameRule, kindRule = RULES[KEYS.c1.name], RULES[KEYS.c1.kind]
    local entries = {}
    if nameRule then
        local input
        input = M.BindTextInputAt(ctx, body, Tr(nameRule.label), 16, y, half,
            function() return P.Get(ID, Page.InputKey(input, nameRule.key)) end,
            function(value) P.Set(ID, Page.InputKey(input, nameRule.key), value or "") end, true,
            P.Meta(PAGE, ID, nameRule.key, "setting", MODULE_SECTION))
        Page.TrackInput(input)
        if input.SetMaxLetters and nameRule.maxLength then input:SetMaxLetters(nameRule.maxLength) end
        entries[#entries + 1] = { rule = nameRule, widget = input }
        ui.nameInput = input
    end
    local row = kindRule and P.RuleRow(PAGE, ID, kindRule, Page.KeyFn, MODULE_SECTION)
    if row then
        row.values = kindValues
        local grid = W.SettingsRows(ctx, body, { x = 28 + half, y = y, width = half, columns = 1, rows = { row } })
        entries[#entries + 1] = { rule = kindRule, widget = grid.controls[kindRule.key] }
    end
    P.GateControls(ctx, ID, entries, Page.KeyFn)
    return y - 58
end

-- The bar choice closes the Frame Basics card: the bar being edited, + Add
-- bar and the bar's actions, its name and type, and its summary.
local function BuildBars(ctx, b, ui, body)
    local width = max(240, (body._msuf2Width or b.width or 720) - 32)
    local half = floor((width - 12) / 2)
    local y = min(tonumber(body._msuf2CursorY) or -80, -40)
    Divider(body, y)
    y = Help(body, HELP.bars, y - 8, width)
    local values = {}
    local function Values()
        for i, info in ipairs(SLOTS) do
            local item = values[i] or {}
            values[i] = item
            local name = Page.BarName(info.key)
            if not Page.IsOn(info.key) then name = name .. " " .. Tr("(off)") end
            item.value, item.text, item.translate = info.key, name, false
        end
        return values
    end
    local picker = M.BindDropdownAt(ctx, body, Tr("Bar to edit"), 16, y, Values, half,
        function() return Page.selected end, function(value) Page.Select(value) end,
        P.Meta(PAGE, ID, "editor.selected", "ephemeral", MODULE_SECTION))
    local buttonWidth = floor((half - 8) / 2)
    local add = Page.Button(body, "+ Add bar", buttonWidth, 24, function(self) Page.OpenAddBar(self) end)
    add:SetPoint("TOPLEFT", body, "TOPLEFT", 28 + half, y - 24)
    local actions = Page.Button(body, "Bar actions", buttonWidth, 24, function(self) Page.OpenBarMenu(self, Page.selected) end)
    actions:SetPoint("TOPLEFT", body, "TOPLEFT", 36 + half + buttonWidth, y - 24)
    actions:HookScript("OnEnter", function(self)
        Page.ShowTip(self, Tr("Bar actions"), Tr("Show or hide, rename, reset or delete this bar, or copy the settings of another bar. Right-click a bar above the preview for the same list."))
    end)
    actions:HookScript("OnLeave", Page.HideTip)
    if M.RegisterControlMetadata then
        M.RegisterControlMetadata(add, P.Meta(PAGE, ID, "editor.add", "action", MODULE_SECTION), "+ Add bar", "button")
        M.RegisterControlMetadata(actions, P.Meta(PAGE, ID, "editor.actions", "action", MODULE_SECTION), "Bar actions", "button")
    end
    y = BuildIdentity(ctx, ui, body, y - 58, half)
    local summary = P.Text(body, "", 16, y, width, T.colors.text)
    y = y - 24
    M.TrackRefresh(ctx, function()
        if P.Combat() then return end
        if picker and picker.SetValue then picker:SetValue(Page.selected) end
        local available = S.Availability(ID) and true or false
        add:SetEnabled(Page.FreeCustom() ~= nil and available)
        actions:SetEnabled(available)
        Page.SetRaw(summary, Page.Summary(Page.selected))
    end)
    ui.sections.bars = body
    P.FinishBody(b, body, y)
end

------------------------------------------------------------------ spells
-- The preview is the spell editor; this closed list keeps every entry
-- (unlearned and rule-hidden ones too) and the list-wide actions, each with
-- an Undo line.
local CLEAR_TIPS = {
    ["Reset to Blizzard's list"] = "Drops this bar's own order and the spells and items you added to it, for this specialization. Spells you removed stay hidden: Show removed spells brings them back. You can undo it.",
    ["Restore raid essentials"] = "Returns this specialization to its short raid essentials list. Your other bars and specializations stay as they are. You can undo it.",
    ["Restore spec defaults"] = "Restores this bar's default spells and buffs for your specialization. Other bars and specializations stay as they are. You can undo it.",
    ["Restore default spells"] = "Goes back to your class's defensive cooldowns, for this specialization. You can undo it.",
    ["Remove all spells"] = "Empties this bar for this specialization. You can undo it.",
}
local function ClearEnter(self)
    local label = Page.ClearLabel(Page.selected)
    Page.ShowTip(self, Tr(label), Tr(CLEAR_TIPS[label]))
end
local function RestoreEnter(self)
    Page.ShowTip(self, Tr("Show removed spells"),
        Tr("Brings back the spells you removed from the built-in bars, on every bar, for this specialization. You can undo it."))
end
local function CopyEnter(self)
    Page.ShowTip(self, Tr("Copy to other specializations"),
        Tr("Copies the spells and items you added to this bar to the same bar in your other specializations. Blizzard's entries follow each specialization's own list. You can undo it."))
end
local function ImportEnter(self)
    Page.ShowTip(self, Tr("Import Blizzard CDM"),
        Tr("Copies the active Blizzard spell selection, bar assignment and order into this specialization's five built-in Suite bars. Your defensive and custom bars, other specializations, and Blizzard settings stay as they are. You can undo it."))
end
local function SpellButton(body, text, width, onClick, onEnter)
    local button = Page.Button(body, text, width, 24, onClick)
    button:HookScript("OnEnter", onEnter)
    button:HookScript("OnLeave", Page.HideTip)
    return button
end
local function BuildSpells(ctx, b, ui)
    local sectionId = "suite_cooldownManager_spells"
    local body = b:CollapsibleSection(sectionId, Tr("Spell list"), 120, false)
    local width = max(240, (body._msuf2Width or b.width or 720) - 32)
    local y = Help(body, HELP.spells, -18, width)
    local spec = P.Text(body, "", 16, y, width, T.colors.text)
    y = y - 22
    local grid = Page.CreateTileGrid(ctx, body, 16, y, width)
    grid.ui, ui.grid = ui, grid
    local note = T.Font(body, "GameFontHighlightSmall", "", T.colors.text)
    note:SetPoint("TOPLEFT", grid.host, "BOTTOMLEFT", 0, -12)
    note:SetWidth(width - 100)
    note:SetJustifyH("LEFT")
    local undo = Page.Button(body, "Undo", 80, 20, Page.RunUndo)
    undo:SetPoint("TOPLEFT", grid.host, "BOTTOMLEFT", width - 84, -8)
    undo:Hide()
    local half = floor((width - 8) / 2)
    local addSpells = Page.Button(body, "Add spells", half, 24, function() Page.TogglePicker(grid.plus) end)
    addSpells:SetPoint("TOPLEFT", grid.host, "BOTTOMLEFT", 0, -36)
    local restore = SpellButton(body, "Show removed spells", half, function() Page.RestoreWithUndo() end, RestoreEnter)
    restore:SetPoint("LEFT", addSpells, "RIGHT", 8, 0)
    local clear = SpellButton(body, "Reset to Blizzard's list", half, function() Page.ClearWithUndo(Page.selected) end,
        ClearEnter)
    clear:SetPoint("TOPLEFT", addSpells, "BOTTOMLEFT", 0, -6)
    local copy = SpellButton(body, "Copy to other specializations", half,
        function() Page.CopyListWithUndo(Page.selected) end, CopyEnter)
    copy:SetPoint("LEFT", clear, "RIGHT", 8, 0)
    local import = SpellButton(body, "Import Blizzard CDM", width,
        Page.ImportBlizzardWithUndo, ImportEnter)
    import:SetPoint("TOPLEFT", clear, "BOTTOMLEFT", 0, -6)
    if M.RegisterControlMetadata then
        M.RegisterControlMetadata(addSpells, P.Meta(PAGE, ID, "spells.add", "action", sectionId), "Add spells", "button")
        M.RegisterControlMetadata(restore, P.Meta(PAGE, ID, "spells.restore", "action", sectionId), "Show removed spells", "button")
        M.RegisterControlMetadata(clear, P.Meta(PAGE, ID, "spells.clear", "action", sectionId), "Reset to Blizzard's list", "button")
        M.RegisterControlMetadata(copy, P.Meta(PAGE, ID, "spells.copy", "action", sectionId), "Copy to other specializations", "button")
        M.RegisterControlMetadata(import, P.Meta(PAGE, ID, "spells.importBlizzard", "action", sectionId), "Import Blizzard CDM", "button")
    end
    ui.spellButtons = { add = addSpells, restore = restore, clear = clear, copy = copy, import = import }
    -- The note shows here and under the preview.
    ui.PaintNote = function()
        Page.SetRaw(note, Page.note or "")
        if Page.noteError then note:SetTextColor(1, 0.4, 0.35) else note:SetTextColor(Page.TextColor()) end
        undo:SetShown(Page.undo ~= nil)
        if ui.PaintPreviewNote then ui.PaintPreviewNote() end
    end
    local top = y
    local function Layout(height)
        if height == ui.gridHeight then return end
        ui.gridHeight = height
        P.FinishBody(b, body, top - height - 130)
    end
    M.TrackRefresh(ctx, function()
        if P.Combat() then return end
        local _, specName = Page.Spec()
        Page.SetRaw(spec, Page.BarName(Page.selected) .. "  -  " .. (specName or Tr("No specialization")))
        Layout(grid:Refresh())
        ui.PaintNote()
        local blocked = Page.EditorBlocked() ~= nil
        addSpells:SetEnabled(not blocked)
        -- Removals are kept per specialization, for every bar at once.
        local hidden = blocked and 0 or Page.HiddenCount()
        Page.ButtonText(restore, hidden > 0 and format(Tr("Show removed spells, all bars (%d)"), hidden)
            or Tr("Show removed spells"))
        restore:SetEnabled(hidden > 0)
        local label = Page.ClearLabel(Page.selected)
        if body._cdmClear ~= label then
            body._cdmClear = label
            clear:SetText(Tr(label))
        end
        clear:SetEnabled(not blocked and Page.HasList(Page.selected))
        copy:SetEnabled(not blocked and Page.HasOwnEntries(Page.selected))
        import:SetEnabled(not blocked and type(S.CooldownManagerBlizzardSnapshot) == "function")
        Header(body, "Spell list", false, "")
    end)
    ui.sections.spells = body
    P.AttachSectionReset(ctx, body, "Spell list", function()
        return Page.ClearWithUndo and Page.ClearWithUndo(Page.selected) or false
    end)
    Layout(grid:Refresh())
end

------------------------------------------------------------------ page
local function Build(ctx)
    local b = W.PageBuilder(ctx)
    local ui = { sections = {} }
    -- A layout built while another one is on screen (Menu2 builds one per
    -- window size, and may build hidden) takes over only when it is shown.
    if not (Page.ui and Page.ui.live) then Page.ui = ui end
    -- FixedPreviewSection releases the first builder slot from scroll flow.
    Page.BuildPreview(ctx, b, ui)
    local card = P.ModuleCard(ctx, b, PAGE, ID, {
        -- Edit Mode opens on a bar it can move: the selected one, or the first.
        { "Move bars on screen", function() P.MoveOnScreen(ID, Page.MoveTarget()) end,
            function() return S.Availability(ID) and P.Get(ID, "enabled") and Page.MoveTarget() ~= nil end, key = "move" },
        { "Open Blizzard's Cooldown Settings", Page.OpenBlizzardSettings, Page.CanOpenBlizzardSettings, key = "blizzard" },
    })
    -- These actions navigate, or record their own history entry (reset), so
    -- a click never takes Menu2's full settings snapshot.
    if card and card.GetChildren then
        local children = { card:GetChildren() }
        for i = 1, #children do children[i]._msuf2SkipHistoryCheckpoint = true end
    end
    if card then
        BuildGeneral(ctx, card)
        BuildBars(ctx, b, ui, card)
        P.AttachSectionReset(ctx, card, "Frame Basics", function()
            local rules = P.SectionRules(ID, "general")
            rules[#rules + 1] = RULES[KEYS.c1.name]
            rules[#rules + 1] = RULES[KEYS.c1.kind]
            return P.ResetRules(ID, rules, Page.KeyFn, { "enabled" })
        end)
    end
    -- Basics first, then the closed spell list, then the other topics.
    for _, spec in ipairs(SECTIONS) do
        BuildSection(ctx, b, ui, spec)
        if spec.id == "basics" then BuildSpells(ctx, b, ui) end
    end
end

P.RegisterPage({ key = PAGE, label = "Cooldown manager", title = "Cooldown manager", build = Build, icon = { 1, 1 },
    aliases = { "cdm", "cooldowns", "cooldown manager", "buffs", "buff bars", "timer bars", "ccm" } })

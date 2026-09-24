local _, P = ...
-- Cooldown manager page: one home for every bar. The docked preview shows the
-- selected bar; the sections below edit it through custom bar 1's rules, which
-- Page.KeyFn maps from c1_<setting> to <selected bar>_<setting>.
local Page = P.CDMPage
if not Page then return end
local Suite, S, M, W, T, Tr = P.Suite, P.S, P.M, P.W, P.T, P.Tr
local ID, PAGE = Page.ID, Page.PAGE
local CDM = Suite.CDM
local RULES, SLOTS, KEYS = P.catalog[ID].rules, CDM.SLOTS, CDM.KEYS
local max, ceil, format = math.max, math.ceil, string.format

local HELP = {
    bars = "Every section below edits the bar chosen here. Built-in bars follow Blizzard's Cooldown Manager; Defensives start with your class's defensive cooldowns, Potions and racials add your racial; custom bars show only what you add.",
    spells = "Click a spell for its own options. Drag to reorder, or drop it on a bar in the preview to move it. Middle-click removes it (with undo); removed spells stay listed under Add spells, where a click brings one back. Lists are kept per specialization.",
    layout = "Where this bar sits and how its icons line up. Attach it to another bar to keep them together, or leave it free and move it on screen.",
    look = "Icon crop, border and opacity of this bar.",
    text = "Countdown, charges and keybind text of this bar.",
    effects = "How cooldown icons react. Single spells can differ: click them under Spells on this bar.",
    buffs = "Buff icons and buff bars: missing buffs, fixed places and highlights.",
    barstyle = "Size and look of timer bars. Used when the bar type is Buff bars.",
    visibility = "When this bar shows. This page and MSUF Edit Mode always show every bar.",
    general = "Settings for the whole cooldown manager. Blizzard's cooldown bars: \"Turn off\" is the fastest. \"Keep running invisibly\" keeps frames that are attached to Blizzard's bars in place, for example from other addons. The status line at the top says when MSUF needs it and it is used automatically.",
}
-- Per-bar settings by topic; every custom bar 1 rule appears exactly once.
local SECTIONS = {
    { id = "layout", title = "Layout", open = true, suffixes = { "on", "name", "kind", "anchor", "side", "gap", "size",
        "height", "spacing", "perRow", "maxIcons", "vertical", "align", "grow", "x", "y" } },
    { id = "look", title = "Look", suffixes = { "zoom", "border", "borderColor", "borderClass", "swipeAlpha", "edge",
        "strata", "alpha", "oocAlpha" } },
    { id = "text", title = "Text", module = "text", suffixes = { "cdText", "cdSize", "stackSize", "stackPos", "keybind",
        "keybindSize", "keybindPos" } },
    { id = "effects", title = "Cooldown effects", suffixes = { "desat", "cdAlpha", "readyAlpha", "hideReady", "procGlow",
        "readyGlow", "glowStyle", "glowTint", "glowColor", "usable", "range", "rangeColor", "showAura", "charges",
        "assist", "bling" } },
    { id = "buffs", title = "Buffs", suffixes = { "showMissing", "keepSlots", "auraGlow", "pandemic" } },
    { id = "barstyle", title = "Buff bars", suffixes = { "barWidth", "barHeight", "barTexture", "barColor", "barClass",
        "barBgAlpha", "barIcon", "barIconSide", "barName", "barTime", "barFill" } },
    { id = "visibility", title = "Visibility", suffixes = { "vis", "hideMounted", "hideVehicle", "tooltips" } },
}
Page.SECTIONS = SECTIONS
-- Kept by "Reset this bar": identity, bar type and captured position.
local RESET_KEEP = { on = true, name = true, kind = true, x = true, y = true }

------------------------------------------------------------------ selected-bar rows
-- Choice lists that follow the selected bar are edited in place: SettingsRows
-- resolves a row's list once, the dropdown reads the same table on open.
local growValues = { { value = 1, text = "Down" }, { value = 2, text = "Up" } }
local anchorValues = {}
for i, label in ipairs(CDM.ANCHOR_LABELS) do anchorValues[i] = { value = i, text = label } end
local function PaintChoices()
    local vertical = Page.Relevant(Page.selected, "vertical") and P.Get(ID, Page.Key("vertical")) == true
    growValues[1].text = vertical and "Right" or "Down"
    growValues[2].text = vertical and "Left" or "Up"
    -- Bar targets carry the bars' own names; MSUF frame targets keep theirs.
    for i = 2, #SLOTS + 1 do
        local slot = SLOTS[i - 1].key
        anchorValues[i].text, anchorValues[i].translate = Page.BarName(slot), false
        anchorValues[i].disabled = slot == Page.selected
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
        local row = P.RuleRow(PAGE, ID, rule, Page.KeyFn, sectionId)
        if row then
            if rule.key == KEYS.c1.grow then
                row.values = growValues
                row.set = function(value) ConvertSet("grow", tonumber(value) or rule.default) end
            elseif rule.key == KEYS.c1.vertical then
                row.set = function(value) ConvertSet("vertical", value == true) end
            elseif rule.key == KEYS.c1.anchor then
                row.values = anchorValues
                row.set = function(value) AnchorSet(tonumber(value) or rule.default) end
            end
            rows[#rows + 1], bound[#bound + 1] = row, rule
        elseif type(rule.default) == "string" then
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
local function Header(body, title)
    local entry = body._msuf2CollapsibleEntry
    if entry and entry.label then Page.SetRaw(entry.label, Tr(title) .. ": " .. Page.BarName(Page.selected)) end
end

local function ResetBar()
    if P.Combat() then return end
    local values = {}
    for suffix, key in pairs(KEYS[Page.selected]) do
        if not RESET_KEEP[suffix] then values[key] = RULES[key].default end
    end
    -- x/y follow the attachment: an attached bar goes back flush on its
    -- anchor, a bar that becomes free keeps its place on screen.
    local k = KEYS[Page.selected]
    local anchor = RULES[k.anchor].default
    if anchor ~= 1 or P.Get(ID, k.anchor) ~= 1 then
        local moved = S.CooldownManagerConvertAnchor and S.CooldownManagerConvertAnchor(Page.selected, anchor)
        if type(moved) == "table" then for key, value in pairs(moved) do values[key] = value end end
    end
    P.SetMany(ID, values)
end

local function BuildSection(ctx, b, ui, spec)
    local sectionId = "suite_cooldownManager_" .. spec.id
    local body = b:CollapsibleSection(sectionId, Tr(spec.title), 120, spec.open == true)
    local width = max(240, (body._msuf2Width or b.width or 720) - 32)
    local y = Help(body, HELP[spec.id], -18, width)
    local unused = P.Text(body, "", 16, y, width, T.colors.dim or T.colors.muted)
    y = y - 20
    -- The attach and grow lists are repainted before the dropdowns that
    -- show them read their captions (refreshers run in order).
    if spec.id == "layout" then M.TrackRefresh(ctx, function() if not P.Combat() then PaintChoices() end end) end
    local rules = {}
    for i, suffix in ipairs(spec.suffixes) do rules[i] = RULES[KEYS.c1[suffix]] end
    y = RuleGrid(ctx, body, rules, y, width, sectionId)
    if spec.module then
        P.Text(body, "These apply to every bar:", 16, y - 6, width, T.colors.text)
        y = RuleGrid(ctx, body, P.SectionRules(ID, spec.module), y - 28, width, sectionId)
    end
    if spec.id == "layout" then
        local half = math.floor((width - 12) / 2)
        -- Navigation needs no snapshot; the reset records its own history entry.
        P.Button(ctx, body, "Move this bar on screen", 16, y - 4, half, function() P.MoveOnScreen(ID, Page.selected) end,
            function() return S.Availability(ID) and P.Get(ID, "enabled") and Page.IsOn(Page.selected) and Page.Movable(Page.selected) end,
            P.Meta(PAGE, ID, "editor.move", "action", sectionId))._msuf2SkipHistoryCheckpoint = true
        P.Button(ctx, body, "Reset this bar's settings", 28 + half, y - 4, half, ResetBar,
            function() return S.Availability(ID) and true or false end,
            P.Meta(PAGE, ID, "editor.reset", "action", sectionId))._msuf2SkipHistoryCheckpoint = true
        y = y - 40
    end
    ui.sections[spec.id] = body
    M.TrackRefresh(ctx, function()
        if P.Combat() then return end
        local count = 0
        for i = 1, #spec.suffixes do
            if not Page.Relevant(Page.selected, spec.suffixes[i]) then count = count + 1 end
        end
        local kind = Page.KindName(Page.Kind(Page.selected))
        if count == 0 then Page.SetRaw(unused, "")
        elseif count == #spec.suffixes then Page.SetRaw(unused, format(Tr("Not used by the %s type. Pick another bar to edit these."), kind))
        else Page.SetRaw(unused, Tr("Greyed options are not used by this bar type.")) end
        Header(body, spec.title)
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
        -- A bar attached to a bar that is off follows the next shown bar up
        -- the chain, or takes the place of the bar that is off.
        if parent and not Page.IsOn(parent.key) then
            local shown, standIn = Page.Chain(slot)
            text = text .. " (" .. Tr("off") .. ")"
            if shown then text = text .. ", " .. format(Tr("follows %s"), Page.BarName(shown))
            elseif standIn then text = text .. ", " .. format(Tr("takes the place of %s"), Page.BarName(standIn)) end
        end
    else
        text = text .. "  -  " .. Tr("placed freely")
    end
    if not Page.IsOn(slot) then text = text .. "  -  " .. Tr("off") end
    return text
end

local function BuildBars(ctx, b, ui)
    local sectionId = "suite_cooldownManager_bars"
    local body = b:CollapsibleSection(sectionId, Tr("Choose a bar"), 120, true)
    local width = max(240, (body._msuf2Width or b.width or 720) - 32)
    local half = math.floor((width - 12) / 2)
    local y = Help(body, HELP.bars, -18, width)
    local values = {}
    local function Values()
        for i, info in ipairs(SLOTS) do
            local item = values[i] or {}
            values[i] = item
            local name = Page.BarName(info.key)
            if info.custom and not Page.IsOn(info.key) then name = name .. " " .. Tr("(off)") end
            item.value, item.text, item.translate = info.key, name, false
        end
        return values
    end
    local picker = M.BindDropdownAt(ctx, body, Tr("Bar to edit"), 16, y, Values, half,
        function() return Page.selected end, function(value) Page.Select(value) end,
        P.Meta(PAGE, ID, "editor.selected", "ephemeral", sectionId))
    local add = Page.Button(body, "+ Add bar", 150, 24, function(self) Page.OpenAddBar(self) end)
    add:SetPoint("TOPLEFT", body, "TOPLEFT", 28 + half, y - 24)
    if M.RegisterControlMetadata then
        M.RegisterControlMetadata(add, P.Meta(PAGE, ID, "editor.add", "action", sectionId), "+ Add bar", "button")
    end
    local summary = P.Text(body, "", 16, y - 58, width, T.colors.text)
    y = y - 82
    M.TrackRefresh(ctx, function()
        if P.Combat() then return end
        if picker and picker.SetValue then picker:SetValue(Page.selected) end
        add:SetEnabled(Page.FreeCustom() ~= nil and S.Availability(ID) and true or false)
        Page.SetRaw(summary, Page.Summary(Page.selected))
    end)
    ui.sections.bars = body
    P.FinishBody(b, body, y)
end

------------------------------------------------------------------ spells
local function BuildSpells(ctx, b, ui)
    local sectionId = "suite_cooldownManager_spells"
    local body = b:CollapsibleSection(sectionId, Tr("Spells on this bar"), 120, true)
    local width = max(240, (body._msuf2Width or b.width or 720) - 32)
    local y = Help(body, HELP.spells, -18, width)
    local spec = P.Text(body, "", 16, y, width, T.colors.text)
    y = y - 22
    local grid = Page.CreateTileGrid(ctx, body, 16, y, width)
    ui.grid = grid
    local note = T.Font(body, "GameFontHighlightSmall", "", T.colors.text)
    note:SetPoint("TOPLEFT", grid.host, "BOTTOMLEFT", 0, -12)
    note:SetWidth(width - 100)
    note:SetJustifyH("LEFT")
    local undo = Page.Button(body, "Undo", 80, 20, Page.RunUndo)
    undo:SetPoint("TOPLEFT", grid.host, "BOTTOMLEFT", width - 84, -8)
    undo:Hide()
    local third = math.floor((width - 16) / 3)
    local addSpells = Page.Button(body, "Add spells", third, 24, function() Page.TogglePicker(grid.plus) end)
    addSpells:SetPoint("TOPLEFT", grid.host, "BOTTOMLEFT", 0, -36)
    local restore = Page.Button(body, "Show removed spells", third, 24, function()
        local ok, reason = Page.RestoreHidden()
        if not ok then Page.Fail(reason) end
    end)
    restore:SetPoint("LEFT", addSpells, "RIGHT", 8, 0)
    local clear = Page.Button(body, "Use Blizzard's order", third, 24, function()
        local ok, reason = Page.ClearList(Page.selected)
        if not ok then Page.Fail(reason) end
    end)
    clear:SetPoint("LEFT", restore, "RIGHT", 8, 0)
    if M.RegisterControlMetadata then
        M.RegisterControlMetadata(addSpells, P.Meta(PAGE, ID, "spells.add", "action", sectionId), "Add spells", "button")
        M.RegisterControlMetadata(restore, P.Meta(PAGE, ID, "spells.restore", "action", sectionId), "Show removed spells", "button")
        M.RegisterControlMetadata(clear, P.Meta(PAGE, ID, "spells.clear", "action", sectionId), "Use Blizzard's order", "button")
    end
    ui.PaintNote = function()
        Page.SetRaw(note, Page.note or "")
        if Page.noteError then note:SetTextColor(1, 0.4, 0.35) else note:SetTextColor(Page.Color("text", 0.92, 0.94, 0.98)) end
        undo:SetShown(Page.undo ~= nil)
    end
    local top = y
    local function Layout(height)
        if height == ui.gridHeight then return end
        ui.gridHeight = height
        P.FinishBody(b, body, top - height - 70)
    end
    M.TrackRefresh(ctx, function()
        if P.Combat() then return end
        local _, specName = Page.Spec()
        Page.SetRaw(spec, Page.BarName(Page.selected) .. "  -  " .. (specName or Tr("No specialization")))
        Layout(grid:Refresh())
        ui.PaintNote()
        local blocked = Page.EditorBlocked() ~= nil
        local custom = Page.SlotInfo(Page.selected).custom
        addSpells:SetEnabled(not blocked)
        -- Removals are kept per specialization, for every bar at once.
        local hidden = blocked and 0 or Page.HiddenCount()
        Page.ButtonText(restore, hidden > 0 and format(Tr("Show removed spells, all bars (%d)"), hidden)
            or Tr("Show removed spells"))
        restore:SetEnabled(hidden > 0)
        local preset = Page.SlotInfo(Page.selected).preset == "defensives"
        clear:SetText(Tr(custom and "Remove all spells" or preset and "Restore default spells" or "Use Blizzard's order"))
        clear:SetEnabled(not blocked and Page.HasList(Page.selected))
    end)
    ui.sections.spells = body
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
        { "Reset module", function()
            P.WithHistory("Reset cooldown manager", "suite:cooldownManager.reset", function() return S.Reset(ID) end)
        end, function() return S.Availability(ID) end, key = "reset" },
    })
    -- These actions navigate, or record their own history entry (reset), so
    -- a click never takes Menu2's full settings snapshot.
    if card and card.GetChildren then
        local children = { card:GetChildren() }
        for i = 1, #children do children[i]._msuf2SkipHistoryCheckpoint = true end
    end
    BuildBars(ctx, b, ui)
    BuildSpells(ctx, b, ui)
    for _, spec in ipairs(SECTIONS) do BuildSection(ctx, b, ui, spec) end
    ui.sections.general = P.RuleSection(ctx, b, PAGE, ID, "suite_cooldownManager_general", Tr("General"),
        P.SectionRules(ID, "general"), { help = HELP.general, open = false })
end

P.RegisterPage({ key = PAGE, label = "Cooldown manager", title = "Cooldown manager", build = Build, icon = { 1, 1 },
    aliases = { "cdm", "cooldowns", "cooldown manager", "buffs", "buff bars", "ccm" } })

local _, P = ...
local Page, W, M, Tr = P.DataTextPage, P.W, P.M, P.Tr
local PAGE, ID = "suite_dataTexts", "dataTexts"
local VISIBILITY_HELP = P.Help("Hide this bar when any selected condition is true.",
    "Health refers to your character. At full health the bar is hidden and cannot receive clicks. Edit Mode shows it for placement.")
local Editor = {}
P.DataTextEditor = Editor

local function Rules(bar, predicate)
    local result, prefix = {}, "bar" .. bar
    for _, rule in ipairs(P.Suite.DataTextBarControls(P.S.Config(ID), bar)) do
        if rule.key:match("^bar%d+") == prefix and predicate(rule, rule.key:sub(#prefix + 1)) then
            result[#result + 1] = rule
        end
    end
    return result
end

local function SelectSource(ctx, body, bar, slot, section, y, width, reveal)
    local key = "bar" .. bar .. "Slot" .. slot
    local meta = P.Meta(PAGE, ID, key, "setting", section)
    local button
    button = P.Button(ctx, body, "Choose data", 16, y, width, function()
        P.DataTextsSourcePicker.Open(button, bar, slot, function() P.Refresh() end)
    end, nil, meta)
    Page.Prepare({ { widget = button, meta = meta, label = Tr("Place %d"):format(slot) } }, section, reveal)
    M.TrackRefresh(ctx, function()
        P.SetButtonText(button, Tr("Change data"))
    end)
    return y - 42
end

local function Slot(ctx, builder, bar, slot, reveal)
    local prefix = "bar" .. bar .. "Slot" .. slot
    local section = PAGE .. "_bar" .. bar .. "_slot" .. slot
    local body = builder:CollapsibleSection(section, Tr("Selected data"), 120, true)
    local width = (body._msuf2Width or builder.width) - 32
    local y = SelectSource(ctx, body, bar, slot, section, -18, width - 142, reveal)
    Page.Button(ctx, body, "Remove data", width - 120, -18, 136, function()
        P.SetMany(ID, P.Suite.DataTextRemoveSlotValues(P.S.Config(ID), bar, slot))
    end, prefix .. ".remove", section, reveal, function() return P.Get(ID, prefix) ~= 1 end)
    local details
    y, details = P.DataTextsSourcePicker.BuildDetails(ctx, body, bar, slot, section, y, width)
    Page.Prepare(details, section, reveal)
    P.FinishBody(builder, body, y)
    if body._msuf2CollapsibleEntry then body._msuf2CollapsibleEntry._msuf2EnsureVisible = reveal end
    return body
end

local function SlotDetails(ctx, builder, bar, slot, reveal, select)
    local prefix = "bar" .. bar .. "Slot" .. slot
    local section = PAGE .. "_bar" .. bar .. "_slot" .. slot .. "_details"
    local rules = Rules(bar, function(rule)
        return rule.key:match("^bar%d+Slot%d+") == prefix and rule.key ~= prefix
    end)
    Page.Rules(ctx, builder, section, Tr("Data settings"), rules, reveal, {
        open = true, extra = function(body, y, width)
            local function Move(offset)
                if P.SetMany(ID, P.Suite.DataTextMoveSlotValues(P.S.Config(ID), bar, slot, slot + offset)) then
                    select("details", slot + offset)
                end
            end
            Page.Button(ctx, body, "Move earlier", 16, y, (width - 6) / 2, function() Move(-1) end,
                prefix .. ".previous", section, reveal, function() return slot > 1 end)
            Page.Button(ctx, body, "Move later", 22 + (width - 6) / 2, y, (width - 6) / 2, function() Move(1) end,
                prefix .. ".next", section, reveal, function() return slot < P.Suite.DataTextSlotLimit end)
            return y - 40
        end,
    })
end

local LAYOUT = { Width = true, Height = true, Vertical = true, FullScreen = true, Dock = true, Layout = true }
local ESSENTIAL_STYLE = { Look = true, FontSize = true, ShowLabels = true, BackgroundEnabled = true }

local function Appearance(ctx, builder, bar, reveal)
    local section, prefix = PAGE .. "_bar" .. bar .. "_appearance", "bar" .. bar
    local body = builder:CollapsibleSection(section, Tr("Appearance"), 120, true)
    local width = (body._msuf2Width or builder.width) - 32
    local primary = Rules(bar, function(_, suffix) return LAYOUT[suffix] end)
    local y, entries = P.RuleGrid(ctx, body, PAGE, ID, primary, -18, width, nil, section)
    Page.Prepare(entries, section, reveal)
    local ownRule = P.catalog[ID].rules[prefix .. "StyleOverride"]
    local own = P.RuleRow(PAGE, ID, ownRule, nil, section)
    own.set = function(value)
        local values = { [ownRule.key] = value == true }
        if value and not P.Get(ID, ownRule.key) then
            for _, key in ipairs(P.Suite.DataTextStyleKeys) do values[P.Suite.DataTextBarStyleKey(bar, key)] = P.Get(ID, key) end
        end
        P.SetMany(ID, values)
    end
    local hint = P.Text(body, "Use the shared style or customize this bar. Switching on copies the current shared settings.",
        16, y - 8, width)
    y = y - 16 - math.max(16, hint:GetStringHeight())
    local row = W.SettingsRows(ctx, body, { x = 16, y = y, width = width, rows = { own }, columns = 1 })
    local ownEntries = { { rule = ownRule, widget = row.controls[ownRule.key] } }
    P.GateControls(ctx, ID, ownEntries)
    Page.Prepare(ownEntries, section, reveal)
    local style = Rules(bar, function(_, suffix) return ESSENTIAL_STYLE[suffix] end)
    y, entries = P.RuleGrid(ctx, body, PAGE, ID, style, row.bottomY - 8, width, nil, section)
    Page.Prepare(entries, section, reveal)
    local extra = Rules(bar, function(rule, suffix)
        return not rule.hidden and not LAYOUT[suffix] and not ESSENTIAL_STYLE[suffix] and suffix ~= "Name"
            and suffix ~= "Visibility" and not suffix:match("^Slot") and not suffix:match("^LoadCond")
    end)
    P.AttachRuleColors(body, Tr("Bar styling"), ID, extra)
    y, entries = P.RuleGrid(ctx, body, PAGE, ID, extra, y - 8, width, nil, section)
    Page.Prepare(entries, section, reveal)
    P.FinishBody(builder, body, y)
    if body._msuf2CollapsibleEntry then body._msuf2CollapsibleEntry._msuf2EnsureVisible = reveal end
end

local function BarActions(ctx, body, bar, section, reveal, y, width)
    local prefix, half = "bar" .. bar, (width - 8) / 2
    Page.Button(ctx, body, "Apply preset to this bar", 16, y, half,
        function() ctx.dataTextWorkspace.presets(bar) end, prefix .. ".manage", section, reveal)
    Page.Button(ctx, body, "Duplicate bar", 24 + half, y, half, function()
        local target = P.Suite.DataTextNextBarID(P.S.Config(ID))
        if target then Page.ChangeBars(P.Suite.DataTextDuplicateBarValues(P.S.Config(ID), bar, target), target) end
    end, prefix .. ".duplicate", section, reveal, function()
        return P.Suite.DataTextNextBarID(P.S.Config(ID)) ~= nil
    end)
    P.Button(ctx, body, "Remove bar", 16, y - 38, half, function()
        Page.ChangeBars(P.Suite.DataTextBarRemovalValues(P.S.Config(ID), bar))
    end, function() return true end)
    Page.Button(ctx, body, "All bars", 24 + half, y - 38, half,
        function() ctx.dataTextWorkspace.choose("shared") end, prefix .. ".shared", section, reveal)
    return y - 78
end

local function BarSectionActions(ctx, body, bar, section, select)
    local prefix = "bar" .. bar
    local more = P.AttachSectionReset(ctx, body, Tr("Bar %d"):format(bar),
        function() return P.ResetPrefix(ID, prefix) end)
    local popup = more._msuf2EnsureSectionPopup()
    P.Button(ctx, popup, "Remove bar", 14, -76, 250, function()
        popup:Hide()
        Page.ChangeBars(P.Suite.DataTextBarRemovalValues(P.S.Config(ID), bar))
    end, function() return true end)
    -- Search focuses the page-owned menu button and reveals its floating action.
    Page.Prepare({ { widget = more, label = "Remove bar",
        meta = P.Meta(PAGE, ID, prefix .. ".remove", "action", section) } }, section, function()
            select()
            more._msuf2OpenSectionPopup()
        end)
    popup:SetHeight(114)
end

local function Header(ctx, builder, bar, select)
    local section, prefix = PAGE .. "_bar" .. bar, "bar" .. bar
    local body = builder:CollapsibleSection(section, Page.BarName(bar), 120, true)
    local width = (body._msuf2Width or builder.width) - 32
    local toggle = W.SectionSwitch(body, Tr("Show bar"), Tr("Show bar"))
    M.BindBoolWidget(ctx, toggle, function() return P.Get(ID, prefix .. "Enabled") end,
        function(value) P.Set(ID, prefix .. "Enabled", value == true) end,
        P.Meta(PAGE, ID, prefix .. "Enabled", "setting", section))
    Page.Prepare({ { widget = toggle, rule = P.catalog[ID].rules[prefix .. "Enabled"] } }, section, select)
    M.TrackRefresh(ctx, function() W.SetControlEnabled(toggle, not P.Combat()) end)
    local y, entries = P.RuleGrid(ctx, body, PAGE, ID, Rules(bar, function(_, suffix) return suffix == "Name" end),
        -18, width, nil, section)
    Page.Prepare(entries, section, select)
    local function Add(anchor)
        for slot = 1, P.Suite.DataTextSlotLimit do
            if P.Get(ID, prefix .. "Slot" .. slot) == 1 then
                P.DataTextsSourcePicker.Open(anchor, bar, slot, function() select("content", slot) end)
                return
            end
        end
    end
    local preview = P.DataTextsPreview.Build(ctx, body, bar, { x = 16, y = y, width = width, height = 160,
        selectedSlot = function() return Page.selections[bar].slot end,
        onSelect = function(slot) select("content", slot) end, onAdd = Add })
    Page.Prepare({ { widget = preview.add, label = "Add data",
        meta = P.Meta(PAGE, ID, prefix .. ".addPlace", "action", section) } }, section, select)
    y = preview.bottomY - 8
    Page.Button(ctx, body, "Move in Edit Mode", 16, y, width, function() P.OpenEditMode(ID, prefix) end,
        prefix .. ".move", section, select, function()
            return P.EditModeReady() and P.S.Status(ID) == "Active" and P.Get(ID, prefix .. "Enabled")
        end)
    BarSectionActions(ctx, body, bar, section, select)
    P.FinishBody(builder, body, BarActions(ctx, body, bar, section, select, y - 40, width))
    M.TrackRefresh(ctx, function()
        local entry = body._msuf2CollapsibleEntry
        if entry and entry.label then P.SetTranslatedText(entry.label, Page.BarName(bar)) end
    end)
    if body._msuf2CollapsibleEntry then body._msuf2CollapsibleEntry._msuf2EnsureVisible = select end
    return preview
end

local function SlotChoices(bar, selected)
    local values = {}
    for slot = 1, P.Suite.DataTextSlotLimit do
        local source = P.Get(ID, "bar" .. bar .. "Slot" .. slot)
        if source ~= 1 or slot == selected then
            values[#values + 1] = { value = slot,
                text = Tr("Place %d"):format(slot) .. " · " .. Tr(P.Suite.DataTextSources[source] or "None") }
        end
    end
    return values
end

function Editor.Build(ctx, builder, bar, view, select)
    local state = Page.selections[bar] or { mode = "content", slot = 1 }
    Page.selections[bar] = state
    local preview = Header(ctx, builder, bar, select)
    local body = builder:Section(Tr("Settings"), 160)
    if body.title then body.title:Hide() end
    for _, entry in ipairs(builder.layoutEntries) do
        if entry.frame == body then entry.gap = 8 end
    end
    local width = body._msuf2Width or builder.width
    local slotPicker, deck
    local sections = {}
    deck = Page.Deck(ctx, body, width, -78, function(height) P.FinishBody(builder, body, -78 - height, 0) end, true)
    local function Choose(mode, slot)
        state.mode, state.slot = mode or state.mode, slot or state.slot
        if slotPicker then slotPicker:SetValue(state.slot) end
        local selectedSlot = state.slot
        local inspector = deck:Select("slot" .. selectedSlot, function(item, child, childBuilder)
            local function Reveal() select("details", selectedSlot) end
            item.content = Slot(child, childBuilder, bar, selectedSlot, function() select("content", selectedSlot) end)
            item.details = Page.LazySection(child, childBuilder, PAGE .. "_bar" .. bar .. "_slot" .. selectedSlot .. "_details",
                Tr("Data settings"), Reveal, function(proxy) SlotDetails(child, proxy, bar, selectedSlot, Reveal, select) end)
        end)
        local target = mode == "content" and inspector.content or mode == "details" and inspector.details.body
            or sections[mode] and sections[mode].body
        if target then Page.OpenSection(target) end
        preview:SetSelectedSlot(state.slot)
    end
    slotPicker = M.BindDropdownAt(ctx, body, "Selected data", 16, -12,
        function() return SlotChoices(bar, state.slot) end, width - 32,
        function() return state.slot end, function(slot) Choose("content", slot) end,
        P.Meta(PAGE, ID, "bar" .. bar .. ".view.slot", "ephemeral", PAGE .. "_bar" .. bar))
    Choose()
    sections.appearance = Page.LazySection(ctx, builder, PAGE .. "_bar" .. bar .. "_appearance", Tr("Appearance"),
        function() select("appearance") end, function(proxy) Appearance(ctx, proxy, bar, function() select("appearance") end) end)
    sections.visibility = Page.LazySection(ctx, builder, PAGE .. "_bar" .. bar .. "_visibility", Tr("Visibility"),
        function() select("visibility") end, function(proxy)
            Page.Rules(ctx, proxy, PAGE .. "_bar" .. bar .. "_visibility", Tr("Visibility"),
                Rules(bar, function(_, suffix) return suffix == "Visibility" or suffix:match("^LoadCond") end),
                function() select("visibility") end, { help = VISIBILITY_HELP })
        end)
    view.select, view.preview, view.deck, view.slotPicker = Choose, preview, deck, slotPicker
    view.sections = sections
end

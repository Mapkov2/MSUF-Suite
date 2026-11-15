local _, P = ...
local Layout = {}
P.NameplatesSectionsLayout = Layout

local PAGE, ID = "suite_nameplates", "nameplates"
local Tr, W = P.Tr, P.W
local ENEMY = { enemy = true, neutral = true }
local FRIENDLY = { friendly = true, friendlyNpc = true }
local ALL = { enemy = true, neutral = true, friendly = true, friendlyNpc = true }
local X = P.Suite.NameplateExtensions

local function AttachSummary(ctx, body, read)
    if not read or not W.SetCollapsibleSummary then return end
    local previous
    local function Refresh()
        local text = read() or ""
        if text == previous then return end
        W.SetCollapsibleSummary(body, text)
        previous = text
    end
    Refresh()
    P.M.TrackRefresh(ctx, Refresh)
end

local function SetHeaderSwitch(spec, rule, row, on)
    if not P.RuleEnabled(ID, rule, nil, false, spec.enableModule) then return end
    if spec.enableModule and on and not P.Get(ID, "enabled") then
        local values = { enabled = true }
        for _, key in pairs(X.SkinKeys) do values[key] = key == rule.key end
        return P.SetMany(ID, values)
    end
    return row.set(on)
end

local function AttachSwitch(ctx, body, spec, sectionId)
    local rule = spec.switch and P.catalog[ID].rules[spec.switch]
    if not rule then return end
    local row = P.RuleRow(PAGE, ID, rule, nil, sectionId)
    local meta = row
    if spec.sharedSwitch then meta = P.Meta(PAGE, ID, spec.key .. ".visibility", "action", sectionId) end
    local function Checked()
        return P.Get(ID, "enabled") and row.get() == true
    end
    local button = P.BindSectionSwitch(ctx, body, { label = row.label, displayLabel = Tr(spec.switchLabel or "Enable"),
        get = Checked,
        set = function(value) return SetHeaderSwitch(spec, rule, row, value == true) end,
        meta = meta,
    })
    P.GateControls(ctx, ID, { { widget = button, rule = rule, checked = Checked } }, nil, spec.enableModule)
end

function Layout.Header(ctx, spec, sectionId)
    if not spec.switch and not spec.summary then return end
    return function(body)
        if spec.switch and W.SectionSwitch then AttachSwitch(ctx, body, spec, sectionId) end
        if spec.summary then body._msufSuiteSkipSummary = true end
        AttachSummary(ctx, body, spec.summary)
    end
end

function Layout.Dimensions(scope)
    local enemy = scope == "enemy" or scope == "neutral"
    local sample = { prefix = enemy and "enemy" or "friendly" }
    local state, metrics = { scope = scope, friendlyElite = scope == "friendlyNpc" }, {}
    return function()
        if not P.Get(ID, "enabled") or P.Get(ID, X.SkinKeys[scope]) == false then return Tr("Off") end
        local m = P.NameplatesPreview.Metrics(state, sample, metrics)
        if m.namesOnly then return Tr("Name only") end
        return Tr("%d × %d px"):format(math.floor(m.barWidth + 0.5), math.floor(m.nativeBarHeight + m.heightDelta + 0.5))
    end
end

function Layout.Choice(key)
    local rule = P.catalog[ID].rules[key]
    if not rule then return end
    local row
    return function()
        row = row or P.RuleRow(PAGE, ID, rule)
        return Tr(rule.choices[row.get()])
    end
end

local function ContextEnabled(kind)
    if kind == "neutralNpc" then return P.Get(ID, "neutralNpcContextOverride") end
    return P.Get(ID, "plateContextEnabled")
end

function Layout.Opacity(kinds, key)
    return function()
        local health = P.Get(ID, key .. "FadeHealth") or 100
        local low, high = 100, 0
        for kind in pairs(kinds) do
            local opacity = ContextEnabled(kind) and P.Get(ID, kind .. "Opacity") or 100
            opacity = math.floor(opacity * health / 100 + 0.5)
            low, high = math.min(low, opacity), math.max(high, opacity)
        end
        return low == high and Tr("%d%%"):format(low) or Tr("%d–%d%%"):format(low, high)
    end
end

function Layout.TextShortcuts(ctx, body, y, width, sectionId)
    local fonts = P.NameplateFonts
    if not fonts then return y end
    return fonts.AddLinks(ctx, body, y, width, sectionId)
end

local function At(scopes, rank)
    local result = {}
    for key in pairs(scopes) do result[key] = rank end
    return result
end

local function Add(sections, key, title, scopes, rank, spec)
    spec.key, spec.title, spec.scopes = key, title, At(scopes, rank)
    sections[#sections + 1] = spec
    return spec
end

local function Relocate(sections, key, title, scopes, rank)
    local spec = sections[key]
    spec.title, spec.scopes = title or spec.title, At(scopes, rank)
    return spec
end

local function Take(tab, first, last)
    local keys = {}
    for i = first, last or #tab.keys do keys[#keys + 1] = tab.keys[i] end
    return keys
end

local function Tab(id, label, keys, extra)
    return { id = id, label = label, keys = keys, extra = extra }
end

local function TextTab(id, label, prefix, appearance, position, format, colors)
    local visible = { prefix .. "Mouseover", prefix .. "FadeIn", prefix .. "FadeOut" }
    local keys = { prefix .. "Visible" }
    for _, group in ipairs({ appearance, position, format, visible, colors or {} }) do
        for _, key in ipairs(group) do keys[#keys + 1] = key end
    end
    local anchor = position[1]:match("Anchor$") and position[1] or nil
    return { id = id, label = label, keys = keys, toggle = prefix .. "Visible",
        appearance = appearance, anchor = anchor, format = format, visibility = visible, colors = colors }
end

local function Text(sections, side, scopes)
    local name = TextTab("name", "Name", side .. "Name", { side .. "NameSize" },
        { side .. "NameRelativeAnchor", side .. "NameOffsetX", side .. "NameOffsetY" }, {})
    local healthFormat = side == "enemy" and { "enemyTextMode", "enemyMirrorHeader" } or {}
    local health = TextTab("hp", "HP Text", side .. "HealthText", { side .. "HealthTextSize" },
        { side .. "HealthTextOffsetX", side .. "HealthTextOffsetY" }, healthFormat)
    local tabs = { name, health }
    if side == "enemy" then
        tabs[#tabs + 1] = TextTab("power", "Power Text", "enemyPowerText", { "enemyPowerTextSize" },
            { "enemyPowerTextAnchor", "enemyPowerTextOffsetX", "enemyPowerTextOffsetY" }, { "enemyPowerTextMode" }, { "enemyPowerTextColor" })
    end
    Add(sections, side .. "Text", "Text", scopes, 40, { tabs = tabs, positionSide = side,
        positionElements = { "Name", "HealthText" }, textCards = true,
        summary = side == "enemy" and Layout.Choice("enemyTextMode") or nil })
end

local function TextSample(ctx, card, side, tab, width, y)
    P.Text(card, "Preview", 16, y, width, nil, "section")
    local sample = P.Text(card, "", 16, y - 20, width)
    local model = P.Suite.NameplateText
    local state = { sampleNPC = side == "enemy" }
    local function Paint()
        if not card:IsVisible() then return end
        local config = P.S.Config(ID)
        if tab.id == "name" then
            sample:SetTextColor(1, 1, 1)
            model.PaintFont(sample, config, side, 12, P.Suite.GlobalFontPath(), P.StylePreviewFont)
            model.Paint(sample, state, model.Sample(side), model.Compile(config, side))
        elseif tab.id == "hp" then
            local mode = side == "enemy" and P.Get(ID, "enemyTextMode") or 2
            model.PaintFont(sample, config, side, 12, P.Suite.GlobalFontPath(), P.StylePreviewFont, true)
            sample:SetText(mode == 3 and "630k" or mode == 4 and "630k 63%" or "63%")
        else
            local power = P.Suite.NameplateStyle.EnemyPower
            local _, _, format = power.TextValue(P.Get(ID, "enemyPowerTextMode"))
            sample:SetFormattedText(format, 63, 100)
            P.StylePreviewFont(sample, P.Suite.GlobalFontPath(), P.Get(ID, "enemyPowerTextSize"), "OUTLINE")
            sample:SetTextColor(P.RGB(P.Get(ID, "enemyPowerTextColor")))
        end
    end
    card:HookScript("OnShow", Paint)
    Paint()
    P.M.TrackRefresh(ctx, Paint)
    return y - 51
end

function Layout.TextCards(ctx, panel, y, width, spec, tab, sectionId)
    local entries, byKey = {}, {}
    for _, rule in ipairs(tab.rules) do byKey[rule.key] = rule end
    local narrow = width < 590
    local left, right = narrow and width or math.floor(width * .56), narrow and width or math.floor(width * .44) - 14
    local function Card(title, keys, x, top, w, extra)
        local card = P.T.Panel(panel, nil, P.T.colors.panel2, P.T.colors.borderSoft)
        card:SetPoint("TOPLEFT", panel, "TOPLEFT", x, top)
        card:SetWidth(w)
        P.Text(card, title, 16, -14, w - 32)
        local rules = {}
        for _, key in ipairs(keys) do if byKey[key] then rules[#rules + 1] = byKey[key] end end
        local bottom, controls = -40, {}
        if #rules == 1 and rules[1].key == tab.toggle then
            local rule = rules[1]
            local row = P.RuleRow(PAGE, ID, rule, nil, sectionId)
            local widget = P.M.BindSwitchAt(ctx, card, row.label, 16, bottom, w - 32, row.get, row.set, row)
            controls[1], bottom = { rule = rule, widget = widget, checked = row.get }, bottom - 33
            P.GateControls(ctx, ID, controls)
        elseif #rules > 0 then
            bottom, controls = P.RuleGrid(ctx, card, PAGE, ID, rules, bottom, w - 32, nil, sectionId, 1)
        end
        for _, entry in ipairs(controls) do entries[#entries + 1] = entry end
        if extra then bottom = extra(card, bottom, w - 32) end
        card:SetHeight(12 - bottom)
        return top + bottom - 24
    end
    local leftEnd = Card(tab.label, { tab.toggle }, 16, y, left, function(card, top, w)
        if tab.colors then
            local rules = {}
            for _, key in ipairs(tab.colors) do if byKey[key] then rules[#rules + 1] = byKey[key] end end
            P.AttachRuleColors(card, tab.label, ID, rules)
        end
        if tab.id == "power" then
            local hint = P.Text(card, "Enable the Resource Bar to show power text.", 16, top, w)
            local function ShowHint() hint:SetShown(not P.Get(ID, "enemyPowerEnabled")) end
            ShowHint()
            P.M.TrackRefresh(ctx, ShowHint)
            top = top - 22
        end
        local bottom = TextSample(ctx, card, spec.positionSide, tab, w, top)
        if tab.id == "name" then
            return Layout.TextShortcuts(ctx, card, bottom, w, sectionId .. ".name")
        end
        return bottom
    end)
    if tab.anchor then leftEnd = Card("Position", { tab.anchor }, 16, leftEnd, left) end
    local x = narrow and 16 or left + 30
    local rightEnd = Card("Appearance", tab.appearance, x, narrow and leftEnd or y, right)
    if #tab.format > 0 then rightEnd = Card("Format", tab.format, x, rightEnd, right) end
    rightEnd = Card("Visibility", tab.visibility, x, rightEnd, right, function(card, top, w)
        local label = P.Text(card, "Preview stays visible. 0 seconds = instant.", 16, top, w)
        return top - math.max(16, math.ceil(label:GetStringHeight() or 16)) - 4
    end)
    return math.min(leftEnd, rightEnd), entries
end

local function CastCard(title, keys, colors)
    return { title = title, keys = keys, colors = colors }
end

local function CastTab(id, label, ...)
    local tab = Tab(id, label, {})
    tab.cards = { ... }
    for _, card in ipairs(tab.cards) do
        for _, keys in ipairs({ card.keys, card.rightKeys or {}, card.colors or {} }) do
            for _, key in ipairs(keys) do tab.keys[#tab.keys + 1] = key end
        end
    end
    return tab
end

local SHARED_CAST_SETTINGS = {
    enemyCastDisplay = true, enemyCastSpellName = true, enemyCastSpellIcon = true, enemyCastSpellTarget = true,
    enemyCastImportant = true, enemyCastTargetHighlight = true, interruptFeedbackEnabled = true, interruptFeedbackWho = true,
    interruptFeedbackDuration = true, interruptFeedbackFlash = true, interruptFeedbackColor = true,
}
local CAST_LABELS = {
    interruptFeedbackEnabled = "Show interrupt", interruptFeedbackWho = "Show interrupter name",
}

local function CastTabs(side)
    local p = side .. "Cast"
    local size = CastCard("Size", { p .. "WidthMode" })
    size.rightKeys = { p .. "ManualWidth", p .. "WidthDelta", p .. "Height" }
    size.span, size.group = true, true
    local interrupt = CastCard(nil, { "interruptFeedbackEnabled", "interruptFeedbackWho" }, { "interruptFeedbackColor" })
    interrupt.interrupt = true
    if side == "friendly" then interrupt.note = "Interrupt feedback settings apply to all nameplates." end
    local surface = CastCard("Provider & Surface", { "enemyCastDisplay" })
    surface.group, surface.links = true, true
    local general = CastTab("general", "General", interrupt, surface, size)
    local iconCard = CastCard(nil, { "enemyCastSpellIcon", p .. "IconRelativeAnchor", p .. "IconSize", p .. "IconZoom",
        p .. "IconBorder", p .. "IconBorderSize" }, { p .. "IconBorderColor" })
    iconCard.toggle = true
    local icon = CastTab("icon", "Icon", iconCard)
    local spellCard = CastCard(nil, { "enemyCastSpellName", p .. "TextEnabled", p .. "Size" })
    spellCard.toggle = true
    local target = CastCard("Cast Target Text", { "enemyCastSpellTarget" })
    target.group, target.toggle = true, true
    local spell = CastTab("spell", "Spell Text", spellCard, target)
    local timeCard = CastCard(nil, { p .. "TimeEnabled", p .. "TimeFormat", p .. "TimeSize" })
    timeCard.toggle = true
    local time = CastTab("time", "Time Text", timeCard)
    local behavior = CastCard("Spell Text Behavior", { side .. "NameDuringCast", side .. "NameCastAlpha" })
    local layer = CastCard("Whole Castbar Layer", { p .. "Foreground" })
    local feedback = CastCard("Interrupted casts", { "interruptFeedbackDuration", "interruptFeedbackFlash" })
    local details = CastCard("Castbar details", { "enemyCastImportant", "enemyCastTargetHighlight" })
    for _, card in ipairs({ behavior, layer, feedback, details }) do card.group = true end
    local advanced = CastTab("advanced", "Advanced", behavior, layer, feedback, details)
    return { general, icon, spell, time, advanced }
end

local function CastCardFrame(panel, spec, x, y, width)
    if W.ControlCard then
        return W.ControlCard(panel, spec.title, nil, x, y, width, 1, spec.group and "group" or nil)
    end
    local card = P.T.Panel(panel, nil, P.T.colors.panel2, P.T.colors.borderSoft)
    card:SetPoint("TOPLEFT", panel, "TOPLEFT", x, y)
    card:SetWidth(width)
    if spec.title then P.Text(card, spec.title, 16, -14, width - 32) end
    return card
end

local function RuleList(keys, rules)
    local result = {}
    for _, key in ipairs(keys or {}) do
        if rules[key] then result[#result + 1] = rules[key] end
    end
    return result
end

local function FormatCastRow(sectionId, row)
    local label = CAST_LABELS[row.id]
    if label then row.label = Tr(label) end
    if sectionId == PAGE .. "_friendlyCast" and SHARED_CAST_SETTINGS[row.id] then
        local meta = P.Meta(PAGE, ID, "friendlyCast.shared." .. row.id, "setting", sectionId)
        row.controlId, row.identityKey, row.controlPath = meta.controlId, meta.identityKey, meta.controlPath
        row.settingKey = nil
    end
    return row
end

local function CastGrid(ctx, card, sectionId, rules, y, width, entries)
    if #rules == 0 then return y end
    local built = P.RuleRows(PAGE, ID, rules, nil, sectionId)
    for _, row in ipairs(built.rows) do FormatCastRow(sectionId, row) end
    local bottom, controls = P.RuleGrid(ctx, card, PAGE, ID, rules, y, width, nil, sectionId, 1, built)
    for _, entry in ipairs(controls) do entries[#entries + 1] = entry end
    return bottom
end

local function CastFeatureSwitch(ctx, card, sectionId, rule, y, width, entries)
    local row = FormatCastRow(sectionId, P.RuleRow(PAGE, ID, rule, nil, sectionId))
    local widget = P.M.BindSwitchAt(ctx, card, row.label, 16, y, width, row.get, row.set, row)
    P.StyleMenuControl(widget)
    local entry = { rule = rule, widget = widget, checked = row.get }
    P.GateControls(ctx, ID, { entry })
    entries[#entries + 1] = entry
end

local function BuildCastCard(ctx, panel, sectionId, spec, rules, x, y, width, entries, links)
    local card = CastCardFrame(panel, spec, x, y, width)
    local innerWidth = width - 32
    local bottom = spec.title and -52 or -24
    local visible = RuleList(spec.keys, rules)
    if spec.toggle and visible[1] then
        CastFeatureSwitch(ctx, card, sectionId, table.remove(visible, 1), bottom, innerWidth, entries)
        bottom = bottom - 40
    elseif spec.interrupt then
        bottom = -72
    end
    if spec.links then
        local provider = P.Text(card, "Blizzard castbar", 16, bottom, innerWidth)
        bottom = bottom - math.max(18, math.ceil(provider:GetStringHeight() or 18)) - 8
    end
    local split = spec.rightKeys and width >= 590
    local leftWidth = split and math.floor((innerWidth - 24) / 2) or innerWidth
    local top = bottom
    bottom = CastGrid(ctx, card, sectionId, visible, top, leftWidth, entries)
    if spec.rightKeys then
        local parent = card
        if split then
            parent = CreateFrame("Frame", nil, card)
            parent:SetPoint("TOPLEFT", card, "TOPLEFT", leftWidth + 24, 0)
            parent:SetSize(leftWidth + 32, 1)
        end
        local right = CastGrid(ctx, parent, sectionId, RuleList(spec.rightKeys, rules), split and top or bottom, leftWidth, entries)
        bottom = math.min(bottom, right)
    end
    if spec.note then
        local note = P.Text(card, spec.note, 16, bottom, innerWidth)
        bottom = bottom - math.max(18, math.ceil(note:GetStringHeight() or 18)) - 8
    end
    local colors = RuleList(spec.colors, P.catalog[ID].rules)
    if #colors > 0 then P.AttachRuleColors(card, spec.title or (spec.interrupt and "Interrupted casts" or "Icon border"), ID, colors) end
    if spec.interrupt then
        P.Button(ctx, card, "Preview interrupted cast", 16, bottom - 4, math.min(200, innerWidth), function()
            P.EditNameplatesPreview("cast", "Cast", true)
        end, function() return P.Get(ID, "interruptFeedbackEnabled") end,
            P.Meta(PAGE, ID, "action.previewInterruptedCast", "ephemeral", sectionId))
        bottom = bottom - 38
    end
    if spec.links and links then bottom = links(card, bottom, innerWidth, sectionId) end
    local height = 12 - bottom
    card:SetHeight(height)
    return y - height - 12
end

local function BuildOpacityCard(ctx, panel, sectionId, spec, rules, x, y, width, entries)
    local card = P.T.Panel(panel, nil, P.T.colors.panel2, P.T.colors.borderSoft)
    card:SetPoint("TOPLEFT", panel, "TOPLEFT", x, y)
    card:SetWidth(width)
    P.Text(card, spec.title, 16, -14, width - 32)
    local bottom, controls = P.RuleGrid(ctx, card, PAGE, ID, RuleList(spec.keys, rules), -42, width - 32, nil, sectionId, 1)
    for _, entry in ipairs(controls) do entries[#entries + 1] = entry end
    local colors = RuleList(spec.colors, P.catalog[ID].rules)
    if #colors > 0 then P.AttachRuleColors(card, spec.title, ID, colors) end
    card:SetHeight(12 - bottom)
    return y + bottom - 24
end

function Layout.CastCards(ctx, panel, y, width, tab, sectionId, opacity, links)
    local entries, rules = {}, {}
    for _, rule in ipairs(tab.rules) do rules[rule.key] = rule end
    local legacySwitch = rules.enemyCastEnabled
    if legacySwitch then
        local controls
        y, controls = P.RuleGrid(ctx, panel, PAGE, ID, { legacySwitch }, y, width, nil, sectionId, 1)
        for _, entry in ipairs(controls) do entries[#entries + 1] = entry end
    end
    if opacity then
        local columns = width >= 930 and 3 or width >= 590 and 2 or 1
        local column = math.floor((width - (columns - 1) * 16) / columns)
        local bottom = y
        for index, card in ipairs(tab.cards) do
            local slot = (index - 1) % columns
            if slot == 0 then y = bottom end
            bottom = math.min(bottom, BuildOpacityCard(ctx, panel, sectionId, card, rules,
                16 + slot * (column + 16), y, column, entries))
        end
        return bottom, entries
    end
    local narrow = width < 590
    local gap = 28
    local column = narrow and width or math.min(430, math.floor((width - gap) / 2))
    local left, right = y, y
    for index, card in ipairs(tab.cards) do
        if card.span then
            left = BuildCastCard(ctx, panel, sectionId, card, rules, 16, math.min(left, right), width, entries, links)
            right = left
        elseif narrow or index % 2 == 1 then
            left = BuildCastCard(ctx, panel, sectionId, card, rules, 16, left, column, entries, links)
        else
            right = BuildCastCard(ctx, panel, sectionId, card, rules, 16 + column + gap, right, column, entries, links)
        end
    end
    return math.min(left, right), entries
end

local POWER_CARDS = {
    { title = "Visibility & Size", keys = { "enemyPowerEnabled", "enemyPowerHeight", "enemyPowerWidth", "enemyPowerSource",
        "enemyPowerEmbed", "enemyPowerDetached" } },
    { title = "Border & fill", keys = { "enemyPowerBorder", "enemyPowerBorderSize", "enemyPowerSmooth", "enemyPowerChunked",
        "enemyPowerByType", "enemyPowerBackgroundAlpha" }, colors = { "enemyPowerColor", "enemyPowerBackgroundColor",
        "enemyPowerBorderColor", "enemyPowerLossColor" } },
    { title = "Position", keys = { "enemyPowerDetachedWidth",
        "enemyPowerDetachedHeight", "enemyPowerDetachedLayer" } },
}

local function PowerCards(ctx, body, y, width, sectionId, rules)
    local byKey = {}
    for _, rule in ipairs(rules) do byKey[rule.key] = rule end
    local twoColumns = width >= 600
    local column = twoColumns and math.floor((width - 16) / 2) or width
    local function Card(spec, x, top, w)
        local card = P.T.Panel(body, nil, P.T.colors.panel2, P.T.colors.borderSoft)
        card:SetPoint("TOPLEFT", body, "TOPLEFT", x, top)
        card:SetWidth(w)
        P.Text(card, spec.title, 16, -14, w - 32)
        local shown = {}
        for _, key in ipairs(spec.keys) do if byKey[key] then shown[#shown + 1] = byKey[key] end end
        local bottom = P.RuleGrid(ctx, card, PAGE, ID, shown, -42, w - 32, nil, sectionId, 1)
        if spec.colors then
            local colors = {}
            for _, key in ipairs(spec.colors) do colors[#colors + 1] = byKey[key] end
            P.AttachRuleColors(card, "Power Bar Colors", ID, colors)
        end
        card:SetHeight(12 - bottom)
        return top + bottom - 24
    end
    local left = Card(POWER_CARDS[1], 16, y, column)
    local right = Card(POWER_CARDS[2], twoColumns and column + 32 or 16, twoColumns and y or left, column)
    return Card(POWER_CARDS[3], 16, math.min(left, right), width)
end

local function ResourceSection(power)
    power.switch, power.grid = "enemyPowerEnabled", PowerCards
    power.summary = function()
        if P.Get(ID, "enabled") and P.Get(ID, "enemyPowerEnabled") then
            local height = P.Get(ID, "enemyPowerDetached") and "enemyPowerDetachedHeight" or "enemyPowerHeight"
            return Tr("%d px"):format(P.Get(ID, height))
        end
    end
    power.keys, power.colors = {}, POWER_CARDS[2].colors
    for _, card in ipairs(POWER_CARDS) do
        for _, key in ipairs(card.keys) do power.keys[#power.keys + 1] = key end
    end
    for _, key in ipairs(power.colors) do power.keys[#power.keys + 1] = key end
end

local CAST_POSITIONS = { "Cast", "CastText", "CastTime", "CastIcon", "CastShield", "CastTarget" }

local function StyleColors(side)
    local colors, seen = {}, {}
    local function Add(key)
        if not seen[key] then colors[#colors + 1], seen[key] = key, true end
    end
    for _, suffix in ipairs({ "BorderColor", "BackdropColor", "OuterFrameColor", "GlowColor", "NameColor" }) do
        Add(side .. suffix)
    end
    for _, rule in ipairs(P.catalog[ID].controls) do
        if rule.color and not rule.hidden and rule.section ~= "plateExtraText" and not rule.key:match("^aura") then
            local owner = rule.key:match("^(enemy)") or rule.key:match("^(friendly)")
            if not owner or owner == side then Add(rule.key) end
        end
    end
    return colors
end

local function StyleAppearance(side, frame, health, combat, threat)
    local colors = StyleColors(side)
    local keys = health and Take(health.tabs[1], 1) or {}
    if health then
        for _, tab in ipairs({ health.tabs[2], threat }) do
            for _, key in ipairs(tab.keys) do keys[#keys + 1] = key end
        end
    end
    local tabs = { Tab("colors", "Colors", keys), Tab("frame", frame.label, { side .. "BackdropEnabled", side .. "BackdropAlpha" }) }
    tabs[1].colors, tabs[1].help, tabs[2].help = colors, health and "roleColors" or nil, frame.help
    local textures = P.NameplateBarTextures
    if not textures.Target("enemyOutlineMode") then
        local fallback = textures.OutlineKeys()
        for _, key in ipairs(fallback) do
            if key:match("^" .. side) or not key:match("^enemy") and not key:match("^friendly") then
                tabs[2].keys[#tabs[2].keys + 1] = key
            end
        end
    end
    if combat then tabs[#tabs + 1] = Tab("combat", combat.title, combat.keys) end
    return tabs
end

local function PlaceStyle(sections, scope, native, appearance, sharedAppearance)
    local style = Tab("style", "Style", native.keys)
    style.shared = scope ~= "enemy"
    style.extra = function(ctx, body, y, width)
        local hint = P.Text(body, "Nameplate style and size apply to all nameplate types.", 16, y - 8, width)
        return y - 18 - math.ceil(hint:GetStringHeight() or 14)
    end
    local tabs = { style }
    for _, source in ipairs(appearance) do
        local tab = Tab(source.id, source.label, source.keys)
        tab.colors, tab.help, tab.shared = source.colors, source.help, sharedAppearance
        tabs[#tabs + 1] = tab
    end
    Add(sections, scope .. "Style", "Style", { [scope] = true }, 20,
        { tabs = tabs, styleScope = scope, tabWidth = 175 })
end

local function StatusSections(sections, by, side, identity, target, options)
    local alternate = side == "enemy" and "neutral" or "friendlyNpc"
    for _, scope in ipairs({ side, alternate }) do
        local spec = { positionSide = side, plateScope = scope }
        local more = Tab("more", "More Options", {}, P.NameplatesStatus.More)
        P.NameplatesStatus.Configure(spec, side, identity, target, more, by.signals, options)
        Add(sections, scope .. "Markers", "Status icons", { [scope] = true }, 70, spec)
    end
end

local function PlaceEnemy(sections, by)
    local bar, frame, target = unpack(by.enemy.tabs)
    local dimensions = Take(bar, 1, 2)
    Add(sections, "enemyBasics", "Basics", { enemy = true }, 10, { open = true,
        switch = X.SkinKeys.enemy, enableModule = true, summary = Layout.Dimensions("enemy"),
        keys = dimensions })
    Add(sections, "neutralBasics", "Basics", { neutral = true }, 10, { open = true,
        switch = X.SkinKeys.neutral, enableModule = true, summary = Layout.Dimensions("neutral"),
        help = "neutralBasics", keys = { "neutralNpcSizeOverride",
            "neutralNpcHealthWidthDelta", "neutralNpcHealthHeightDelta" } })
    local appearance = StyleAppearance("enemy", frame, by.roleColors, by.combatExtensions, by.threatDetail)
    PlaceStyle(sections, "enemy", by.native, appearance, false)
    PlaceStyle(sections, "neutral", by.native, appearance, true)
    Text(sections, "enemy", ENEMY)
    local options = { "enemyThresholdEnabled", "enemyThresholdPercent", "enemyThresholdWidth", "enemyThresholdColor" }
    StatusSections(sections, by, "enemy", by.plateIdentity.tabs[1].keys, target.keys, options)
    ResourceSection(Relocate(by, "enemyPower", "Resource Bar", ENEMY, 50))
    local cast = Relocate(by, "castbar", "Castbar", ENEMY, 60)
    cast.switch, cast.castCards = "enemyCastEnabled", true
    cast.positions, cast.positionSide, cast.positionElements = nil, "enemy", CAST_POSITIONS
    cast.tabs = CastTabs("enemy")
end

local function PlaceFriendly(sections, by)
    local display, bar, frame = unpack(by.friendly.tabs)
    local dimensions = Take(bar, 1, 2)
    Add(sections, "friendlyBasics", "Basics", { friendly = true }, 10, { open = true,
        keys = { display.keys[1], display.keys[2], display.keys[3], dimensions[1], dimensions[2] },
        switch = X.SkinKeys.friendly, enableModule = true, help = "friendly",
        summary = Layout.Dimensions("friendly") })
    Add(sections, "friendlyNpcBasics", "Basics", { friendlyNpc = true }, 10, { open = true,
        help = "friendlyNpcBasics", switch = X.SkinKeys.friendlyNpc, enableModule = true,
        summary = Layout.Dimensions("friendlyNpc"),
        keys = { display.keys[4], "friendlyNpcSizeOverride", "friendlyNpcHealthWidthDelta", "friendlyNpcHealthHeightDelta" } })
    local appearance = StyleAppearance("friendly", frame)
    PlaceStyle(sections, "friendly", by.native, appearance, false)
    PlaceStyle(sections, "friendlyNpc", by.native, appearance, true)
    Text(sections, "friendly", FRIENDLY)
    Add(sections, "friendlyCast", "Castbar", FRIENDLY, 60, {
        switch = "enemyCastEnabled", sharedSwitch = true, castCards = true, tabs = CastTabs("friendly"), sharedSettings = SHARED_CAST_SETTINGS,
        positionSide = "friendly", positionElements = CAST_POSITIONS })
    StatusSections(sections, by, "friendly", by.plateIdentity.tabs[2].keys)
end

local function ContextTabs(kind, suffixes)
    local tabs = {}
    for _, entry in ipairs(P.Suite.NameplateExtensions.Kinds) do
        if kind[entry.key] then
            local keys = {}
            for _, suffix in ipairs(suffixes) do keys[#keys + 1] = entry.key .. suffix end
            tabs[#tabs + 1] = Tab(entry.key, entry.label, keys)
        end
    end
    return tabs
end

local function ExtendBasics(sections, basics, scope, gate, kinds, display, suffixes, by)
    local tabs = { Tab("general", "General", basics.keys) }
    basics.keys = nil
    if gate == "plateContextEnabled" then basics.sharedGate = gate end
    tabs[1].help = basics.help
    tabs[1].before, tabs[1].extra = Layout.Look, Layout.BarLinks
    tabs[1].keys[#tabs[1].keys + 1] = gate
    if display then tabs[#tabs + 1] = Tab("display", "Display", display) end
    local clicks, range = {}, {}
    for _, field in ipairs(X.InteractionFields) do
        local keys = field:sub(1, 5) == "Range" and range or clicks
        keys[#keys + 1] = scope .. field
    end
    if scope == "friendly" or scope == "friendlyNpc" then clicks[#clicks + 1] = scope .. "PlateClickThrough" end
    local clickTab = Tab("clicks", "Click area", clicks)
    clickTab.help = "plateClickArea"
    tabs[#tabs + 1] = clickTab
    local spell = Tab("spell", "Spell range", range)
    spell.help = "plateRange"
    local distance = Tab("distance", "Distance and stacking", by.distance.keys)
    distance.shared = scope ~= "enemy"
    Add(sections, scope .. "Range", "Range Check", { [scope] = true }, 85,
        { tabs = { spell, distance }, switch = scope .. "RangeEnabled", spellPicker = scope .. "RangeSpell" })
    for _, tab in ipairs(ContextTabs(kinds, suffixes)) do
        table.insert(tab.keys, 1, gate)
        tabs[#tabs + 1] = tab
    end
    basics.tabs = tabs
end

local function OpacityTabs(key, kinds, gate)
    local prefix = key .. "Fade"
    local side = (key == "enemy" or key == "neutral") and "enemy" or "friendly"
    local general = CastTab("general", "General",
        CastCard("Health Bar", { prefix .. "Health", prefix .. "HealthBackground" }),
        CastCard("Options", { prefix .. "KeepText", prefix .. "KeepPrediction" }))
    general.cards[1].colors = { side .. "BackdropColor", side .. "BorderColor" }
    if key == "enemy" or key == "neutral" then
        local card = CastCard("Resource Bar", { prefix .. "Power", prefix .. "PowerBackground" },
            { "enemyPowerColor", "enemyPowerBackgroundColor" })
        table.insert(general.cards, 2, card)
        for _, rule in ipairs(card.keys) do general.keys[#general.keys + 1] = rule end
    end
    local ooc = CastTab("ooc", "Out of Combat",
        CastCard("Out of Combat", { prefix .. "OutOfCombat", prefix .. "OutOfCombatAlpha" }))
    local whole = CastTab("plate", "Whole Plate", CastCard("Whole Plate", { gate }))
    for _, tab in ipairs(ContextTabs(kinds, { "Opacity" })) do
        whole.cards[#whole.cards + 1] = CastCard(tab.label, tab.keys)
        whole.keys[#whole.keys + 1] = tab.keys[1]
    end
    local function Preview(outOfCombat)
        return function(ctx, body, y, width, section)
            P.Button(ctx, body, "Show in preview", 16, y - 4, 165, function()
                P.PreviewNameplateOpacity(outOfCombat)
            end, nil, P.Meta(PAGE, ID, section .. ".opacityPreview." .. tostring(outOfCombat), "ephemeral", section))
            return y - 38
        end
    end
    general.extra, ooc.extra = Preview(false), Preview(true)
    return { general, ooc, whole }
end

local function AddOpacity(sections, key, kinds, gate)
    Add(sections, key .. "Opacity", "Opacity", { [key] = true }, 90,
        { tabs = OpacityTabs(key, kinds, gate), castCards = true, opacityCards = true,
            sharedGate = gate == "plateContextEnabled" and gate or nil, summary = Layout.Opacity(kinds, key) })
end

local function PlaceVisibility(sections, by)
    local model = P.Suite.NameplateExtensions
    local suffixes = { "CastVisibility", "Scale" }
    for _, location in ipairs(model.Contexts) do suffixes[#suffixes + 1] = location.key .. "Visible" end
    local kinds = { enemy = { enemyNpc = true, enemyPlayer = true }, neutral = { neutralNpc = true },
        friendly = { friendlyPlayer = true }, friendlyNpc = { friendlyNpc = true } }
    local displays = {
        enemy = { "plateEnemyMinions", "plateEnemyPets", "plateEnemyGuardians", "plateEnemyTotems",
            "plateEnemyMinus", "plateSimpleMinion", "plateSimpleMinus" },
        friendly = { "plateFriendlyMinions", "plateFriendlyPets", "plateFriendlyGuardians", "plateFriendlyTotems",
            "plateSimpleFriendlyPlayer" },
        friendlyNpc = { "plateSimpleFriendlyNpc" },
    }
    for _, key in ipairs({ "enemy", "neutral", "friendly", "friendlyNpc" }) do
        local gate = key == "neutral" and "neutralNpcContextOverride" or "plateContextEnabled"
        ExtendBasics(sections, by[key .. "Basics"], key, gate, kinds[key], displays[key], suffixes, by)
        AddOpacity(sections, key, kinds[key], gate)
    end
    Relocate(by, "enemyVisibility", nil, { enemy = true }, 80)
end

function Layout.Arrange(sections)
    local by = {}
    for _, spec in ipairs(sections) do by[spec.key] = spec end
    PlaceEnemy(sections, by)
    PlaceFriendly(sections, by)
    for _, spec in ipairs(sections) do by[spec.key] = spec end
    by.distance.keys = { "plateMaxDistanceMode", "plateMaxDistance", "plateOccludedMode", "plateOccludedPercent", "plateFadeDistance",
        "plateShrinkDistance", "plateSpacingMode", "plateOverlapV", "plateOverlapH", "plateMotionSpeed", "plateInsetMode",
        "plateTopInset", "plateBottomInset", "plateClampTarget", "plateStackEnemy", "plateStackFriendly", "plateShowAll", "plateOffscreen" }
    PlaceVisibility(sections, by)
    local auras = Relocate(by, "auraWorkspace", "Auras", ALL, 30)
    auras.open, auras.summary = false, P.NameplatesAdvancedAuras.Summary
    for i = #sections, 1, -1 do
        if not sections[i].scopes then table.remove(sections, i) end
    end
end

function Layout.Look(ctx, body, y, width, sectionId)
    local M = P.M
    local look = P.RuleRow(PAGE, ID, P.catalog[ID].rules.look, nil, sectionId)
    local scope = sectionId:sub(#PAGE + 2)
    if scope ~= "enemyBasics" then
        look.controlId = P.Meta(PAGE, ID, scope .. ".look", "ephemeral", sectionId).controlId
    end
    local grid = P.W.SettingsRows(ctx, body, { x = 16, y = y - 4, width = width, rows = { look }, columns = 2 })
    M.AddTooltip(grid.controls.look, Tr("Look"), Tr("The selected look applies to all nameplate types."), { hook = true })
    return grid.bottomY - 12
end

function Layout.BarLinks(ctx, body, y, width, sectionId)
    local bars = P.NameplateBarTextures
    y = bars.Link(ctx, body, y, width, sectionId)
    return bars.LinkOutline(ctx, body, y, width, sectionId)
end


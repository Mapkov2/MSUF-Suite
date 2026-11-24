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
    return Refresh
end

local function FriendlyScope(rule)
    if rule.key == X.SkinKeys.friendly then return "friendly" end
    if rule.key == X.SkinKeys.friendlyNpc then return "friendlyNpc" end
end

local function SetHeaderSwitch(spec, rule, row, on)
    if not P.RuleEnabled(ID, rule, nil, false, spec.enableModule) then return end
    local scope, values = FriendlyScope(rule)
    if spec.enableModule and on and not P.Get(ID, "enabled") then
        values = { enabled = true }
        for _, key in pairs(X.SkinKeys) do values[key] = key == rule.key end
    end
    if scope then return P.SetFriendlyNameplateVisibility(scope, on, values) end
    if values then return P.SetMany(ID, values) end
    return row.set(on)
end

-- Blizzard settings and key bindings can change visibility while the menu is
-- open. Only the visible header listens; repainting it never writes a profile.
local function WatchFriendlySwitch(button, read, summary)
    local events = CreateFrame("Frame", nil, button)
    local function Sync()
        button:SetChecked(read() == true)
        if summary then summary() end
    end
    local function Activate()
        events:RegisterEvent("CVAR_UPDATE")
        Sync()
    end
    events:SetScript("OnShow", Activate)
    events:SetScript("OnHide", events.UnregisterAllEvents)
    events:SetScript("OnEvent", function(_, _, name)
        if not P.Suite.Public(name) or type(name) ~= "string" then return end
        name = name:lower()
        if name == "nameplateshowfriendlyplayers" or name == "nameplateshowfriendlynpcs" or name == "unitnamenpc" then Sync() end
    end)
    if events:IsVisible() then Activate() end
end

local function AttachSwitch(ctx, body, spec, sectionId, summary)
    local rule = spec.switch and P.catalog[ID].rules[spec.switch]
    if not rule then return end
    local row = P.RuleRow(PAGE, ID, rule, nil, sectionId)
    local meta = row
    if spec.sharedSwitch then meta = P.Meta(PAGE, ID, spec.key .. ".visibility", "action", sectionId) end
    local scope = FriendlyScope(rule)
    local function Checked()
        if scope then return P.Suite.FriendlyNameplateShown(scope) end
        return P.Get(ID, "enabled") and row.get() == true
    end
    local button = P.BindSectionSwitch(ctx, body, { label = row.label, displayLabel = Tr(spec.switchLabel or "Enable"),
        get = Checked,
        set = function(value) return SetHeaderSwitch(spec, rule, row, value == true) end,
        meta = meta,
    })
    P.GateControls(ctx, ID, { { widget = button, rule = rule, checked = Checked } }, nil, spec.enableModule)
    if scope then WatchFriendlySwitch(button, Checked, summary) end
end

function Layout.Header(ctx, spec, sectionId)
    if not spec.switch and not spec.summary then return end
    return function(body)
        if spec.summary then body._msufSuiteSkipSummary = true end
        local summary = AttachSummary(ctx, body, spec.summary)
        if spec.switch and W.SectionSwitch then AttachSwitch(ctx, body, spec, sectionId, summary) end
    end
end

function Layout.Dimensions(scope)
    local enemy = scope == "enemy" or scope == "neutral"
    local sample = { prefix = enemy and "enemy" or "friendly" }
    local state, metrics = { scope = scope, friendlyElite = scope == "friendlyNpc" }, {}
    return function()
        if FRIENDLY[scope] and not P.Suite.FriendlyNameplateShown(scope) then return Tr("Off") end
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
    return X.ContextEnabled(P.S.Config(ID), kind)
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
        { side .. "NameRelativeAnchor", side .. "NameOffsetX", side .. "NameOffsetY" },
        side == "friendly" and { "playerGuildNames" } or {})
    P.NameplatesWorkspace.AddNameOptions(name.keys, scopes)
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
            model.Paint(sample, state, model.Sample(side), model.Compile(config, side, P.NameplatesWorkspace.Kind()))
        elseif tab.id == "hp" then
            local mode = side == "enemy" and P.Get(ID, "enemyTextMode") or 2
            model.PaintFont(sample, config, side, 12, P.Suite.GlobalFontPath(), P.StylePreviewFont, true)
            local shared = model.Shared(config)
            local color = shared and shared.textColor
            if color then sample:SetTextColor(color.r, color.g, color.b, color.a)
            else sample:SetTextColor(unpack(P.T.colors.text)) end
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
    local rightEnd = Card("Appearance", tab.appearance, x, narrow and leftEnd or y, right,
        tab.id == "name" and function(card, top, w)
            return P.NameplatesWorkspace.NameOptionRows(ctx, card, top, w, sectionId, byKey, entries)
        end or nil)
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
    interruptFeedbackDuration = true, interruptFeedbackFlash = true, interruptFeedbackColor = true, interruptFeedbackShared = true,
    castIconCombinedHeight = true, castSeamLine = true,
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
        p .. "IconBorder", p .. "IconBorderSize", "castIconCombinedHeight" }, { p .. "IconBorderColor" })
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
    local feedback = CastCard("Interrupted casts", { "interruptFeedbackShared", "interruptFeedbackDuration", "interruptFeedbackFlash" })
    local details = CastCard("Castbar details", { "enemyCastImportant", "enemyCastTargetHighlight", "castSeamLine" })
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
local ENEMY_EXTRA_COLORS = { "questNeutralColor", "questHostileColor", "castHealthInterruptible", "castHealthLocked" }
local function StyleColors(side)
    local colors, seen = {}, {}
    local function Add(key)
        if not seen[key] then colors[#colors + 1], seen[key] = key, true end
    end
    for _, suffix in ipairs({ "BorderColor", "BackdropColor", "OuterFrameColor", "GlowColor" }) do
        Add(side .. suffix)
    end
    for _, rule in ipairs(P.catalog[ID].controls) do
        if rule.color and not rule.hidden and rule.section ~= "plateExtraText" and rule.section ~= "plateExtras"
            and rule.section ~= "plateTextDisplay" and rule.section ~= "nameText"
            and not (rule.section or ""):match("StyleOutline$") and not (rule.section or ""):match("StyleTextures$")
            and not rule.key:match("^aura") then
            local owner = rule.section == "combatExtensions" and "enemy" or rule.key:match("^(enemy)") or rule.key:match("^(friendly)")
            if not owner or owner == side then Add(rule.key) end
        end
    end
    if side == "enemy" then
        for _, key in ipairs(ENEMY_EXTRA_COLORS) do Add(key) end
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
        for _, key in ipairs({ "questReactionColors", "castHealthColors", "threatNameColor", "threatFrameColor" }) do
            keys[#keys + 1] = key
        end
    end
    local tabs = { Tab("colors", "Colors", keys), Tab("frame", frame.label, { side .. "BackdropEnabled", side .. "BackdropAlpha" }) }
    tabs[1].colors, tabs[1].help, tabs[2].help = colors, health and "roleColors" or nil, frame.help
    if side == "enemy" and not P.NameplateBarTextures.Target("enemySlantedHealth") then
        tabs[2].keys[#tabs[2].keys + 1] = "enemySlantedHealth"
    end
    if combat then tabs[#tabs + 1] = Tab("combat", combat.title, combat.keys) end
    return tabs
end

local function AppearanceTab(scope, suffix, id, title)
    local keys, colors = {}, {}
    for _, rule in ipairs(P.catalog[ID].controls) do
        if rule.section == scope .. suffix and not rule.hidden then
            local list = rule.color and colors or keys
            list[#list + 1] = rule.key
        end
    end
    local tab = Tab(id, title, keys)
    tab.colors = colors
    return tab
end

local function PlaceStyle(sections, scope, appearance, sharedAppearance)
    local tabs, palette = {}
    for _, source in ipairs(appearance) do
        if source.id == "colors" and #source.keys == 0 then
            palette = source.colors
        else
            local tab = Tab(source.id, source.label, source.keys)
            tab.colors, tab.help, tab.shared = source.colors, source.help, sharedAppearance
            if tab.id == "frame" then
                if scope == "enemy" and P.NameplateBarTextures.Target("enemySlantedHealth") then
                    tab.extra = P.NameplateBarTextures.LinkShapes
                end
                tab.keys = Take(source, 1)
                for _, pattern in ipairs(P.Suite.NameplateExtensions.Patterns) do
                    local key = scope .. pattern.field
                    tab.keys[#tab.keys + 1], tab.keys[#tab.keys + 2] = key .. "Texture", key .. "Alpha"
                end
            end
            tabs[#tabs + 1] = tab
        end
    end
    local index = palette and 2 or 3
    table.insert(tabs, index, AppearanceTab(scope, "StyleOutline", "outline", "Frame Outline"))
    table.insert(tabs, index + 1, AppearanceTab(scope, "StyleTextures", "textures", "Textures & Gradient"))
    Add(sections, scope .. "Style", "Style", { [scope] = true }, 20,
        { tabs = tabs, colors = palette, sharedColors = sharedAppearance, styleScope = scope, tabWidth = 175 })
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
    PlaceStyle(sections, "enemy", appearance, false)
    PlaceStyle(sections, "neutral", appearance, true)
    Text(sections, "enemy", ENEMY)
    local options = { "enemyThresholdEnabled", "enemyThresholdPercent", "enemyThresholdWidth", "enemyThresholdColor" }
    StatusSections(sections, by, "enemy", by.plateIdentity.tabs[1].keys, target.keys, options)
    ResourceSection(Relocate(by, "enemyPower", "Resource Bar", ENEMY, 50))
    Add(sections, "classResources", "Class Resources", { enemy = true }, 55, { tabs = {
        Tab("plate", "Nameplates", { "targetClassResource", "targetClassResourceWidth", "targetClassResourceHeight", "targetClassResourceY" }),
        Tab("frame", "Target", { "targetUnitFrameResource", "targetUnitFrameResourceWidth", "targetUnitFrameResourceHeight",
            "targetUnitFrameResourceY" }),
    } })
    local cast = Relocate(by, "castbar", "Castbar", ENEMY, 60)
    cast.switch, cast.castCards = "enemyCastEnabled", true
    cast.positions, cast.positionSide, cast.positionElements = nil, "enemy", CAST_POSITIONS
    cast.tabs = CastTabs("enemy")
end

local function PlaceFriendly(sections, by)
    local display, bar, frame = unpack(by.friendly.tabs)
    local dimensions = Take(bar, 1, 2)
    Add(sections, "friendlyBasics", "Basics", { friendly = true }, 10, { open = true,
        keys = { display.keys[3], dimensions[1], dimensions[2] },
        switch = X.SkinKeys.friendly, enableModule = true, help = "friendly",
        summary = Layout.Dimensions("friendly") })
    Add(sections, "friendlyNpcBasics", "Basics", { friendlyNpc = true }, 10, { open = true,
        help = "friendlyNpcBasics", switch = X.SkinKeys.friendlyNpc, enableModule = true,
        summary = Layout.Dimensions("friendlyNpc"),
        keys = { "friendlyNpcSizeOverride",
            "friendlyNpcHealthWidthDelta", "friendlyNpcHealthHeightDelta" } })
    local appearance = StyleAppearance("friendly", frame)
    PlaceStyle(sections, "friendly", appearance, false)
    PlaceStyle(sections, "friendlyNpc", appearance, true)
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

local DISTANCE = { "plateMaxDistanceMode", "plateMaxDistance", "plateOccludedMode", "plateOccludedPercent",
    "plateFadeDistance", "plateShrinkDistance", "plateInsetMode", "plateTopInset", "plateBottomInset", "plateClampTarget" }
local VISIBILITY = { enemy = "What enemies to show", neutral = "What neutral NPCs to show",
    friendly = "What friendly players to show", friendlyNpc = "What friendly NPCs to show" }

local function ExtendBasics(sections, basics, scope, kinds, display, suffixes)
    local health = Tab("health", "Health Bar", basics.keys)
    basics.keys = nil
    health.help = basics.help
    local visibility = Tab("visibility", VISIBILITY[scope], display)
    local stackKey = (scope == "enemy" or scope == "neutral") and "plateStackEnemy" or "plateStackFriendly"
    local stacking = Tab("stacking", "Stacking", {
        stackKey, "plateSpacingMode", "plateOverlapV", "plateOverlapH", "plateMotionSpeed",
    })
    stacking.help = "stacking"
    local tabs = { visibility, health, stacking }
    local clicks, range = {}, { scope .. "RangeAuto" }
    for _, field in ipairs(X.InteractionFields) do
        local keys = field:sub(1, 5) == "Range" and range or clicks
        if field ~= "RangeEnabled" then keys[#keys + 1] = scope .. field end
    end
    if scope == "friendly" or scope == "friendlyNpc" then clicks[#clicks + 1] = scope .. "PlateClickThrough" end
    local clickTab = Tab("clicks", "Click area", clicks)
    clickTab.help = "plateClickArea"
    tabs[#tabs + 1] = clickTab
    local spell = Tab("spell", "Spell range", range)
    spell.help = "plateRange"
    local distance = Tab("distance", "Distance", DISTANCE)
    distance.help = "distance"
    Add(sections, scope .. "Range", "Range Check", { [scope] = true }, 85,
        { tabs = { spell, distance }, tabWidth = 140, switch = scope .. "RangeEnabled", spellPicker = scope .. "RangeSpell" })
    for _, tab in ipairs(ContextTabs(kinds, suffixes)) do
        tabs[#tabs + 1] = tab
    end
    basics.tabs = tabs
end

local function OpacityTabs(key, kinds)
    local prefix = key .. "Fade"
    local general = CastTab("general", "General",
        CastCard("Health Bar", { prefix .. "Health", prefix .. "HealthBackground" }),
        CastCard("Options", { prefix .. "KeepText", prefix .. "KeepPrediction" }))
    if key == "enemy" or key == "neutral" then
        local card = CastCard("Resource Bar", { prefix .. "Power", prefix .. "PowerBackground" })
        table.insert(general.cards, 2, card)
        for _, rule in ipairs(card.keys) do general.keys[#general.keys + 1] = rule end
    end
    local ooc = CastTab("ooc", "Out of Combat",
        CastCard("Out of Combat", { prefix .. "OutOfCombat", prefix .. "OutOfCombatAlpha" }))
    local whole = CastTab("plate", "Whole Plate")
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

local function AddOpacity(sections, key, kinds)
    Add(sections, key .. "Opacity", "Opacity", { [key] = true }, 90,
        { tabs = OpacityTabs(key, kinds), castCards = true, opacityCards = true, summary = Layout.Opacity(kinds, key) })
end

local function PlaceVisibility(sections, by)
    local model = P.Suite.NameplateExtensions
    local suffixes = { "CastVisibility", "Scale" }
    for _, location in ipairs(model.Contexts) do suffixes[#suffixes + 1] = location.key .. "Visible" end
    local kinds = { enemy = { enemyNpc = true, enemyPlayer = true }, neutral = { neutralNpc = true },
        friendly = { friendlyPlayer = true }, friendlyNpc = { friendlyNpc = true } }
    local displays = {
        enemy = { "enemyPlateNameOnly", "plateEnemyMinions", "plateEnemyPets", "plateEnemyGuardians", "plateEnemyTotems",
            "plateEnemyMinus", "plateSimpleMinion", "plateSimpleMinus", "plateShowAll", "plateOffscreen" },
        neutral = { "neutralPlateNameOnly" },
        friendly = { "friendlyNamesOnly", "plateFriendlyMinions", "plateFriendlyPets", "plateFriendlyGuardians", "plateFriendlyTotems",
            "plateSimpleFriendlyPlayer" },
        friendlyNpc = { "friendlyNPCs", "plateSimpleFriendlyNpc" },
    }
    Relocate(by, "enemyVisibility", nil, { enemy = true }, 15)
    for _, key in ipairs(X.OpacityScopes) do
        local basics, display = by[key .. "Basics"], displays[key]
        table.insert(display, 1, X.ContextKeys[key])
        ExtendBasics(sections, basics, key, kinds[key], display, suffixes)
        AddOpacity(sections, key, kinds[key])
    end
end

local function NativeStyle(by)
    local function Links(ctx, body, y, width, section)
        local bars = P.NameplateBarTextures
        y = bars.Link(ctx, body, y, width, section)
        y = bars.LinkOutline(ctx, body, y, width, section)
        y = bars.LinkCastTarget(ctx, body, y, width, section)
        return bars.LinkAbsorbs(ctx, body, y, width, section)
    end
    for _, scope in ipairs(X.OpacityScopes) do
        local style = by[scope .. "Style"]
        local tab = Tab("blizzard", "Blizzard & presets", by.native.keys, Links)
        tab.help = "native"
        style.tabs[#style.tabs + 1] = tab
    end
end

function Layout.Arrange(sections)
    local by = {}
    for _, spec in ipairs(sections) do by[spec.key] = spec end
    PlaceEnemy(sections, by)
    PlaceFriendly(sections, by)
    for _, spec in ipairs(sections) do by[spec.key] = spec end
    PlaceVisibility(sections, by)
    NativeStyle(by)
    local auras = Relocate(by, "auraWorkspace", "Auras", ALL, 30)
    auras.open, auras.summary = false, P.NameplatesAdvancedAuras.Summary
    for i = #sections, 1, -1 do
        if not sections[i].scopes then table.remove(sections, i) end
    end
end


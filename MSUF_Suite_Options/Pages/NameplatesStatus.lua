local _, P = ...
local PAGE, ID = "suite_nameplates", "nameplates"
local Tr, HM = P.Tr, P.HM
local Style, X = P.Suite.NameplateStyle, P.Suite.NameplateExtensions
local Status = {}
P.NameplatesStatus = Status

local function Item(key, element, label, toggle, ...)
    return { key = key, label = label, element = element, toggle = toggle, keys = { ... } }
end

function Status.Items(side, identity, target, scope)
    local items = {
        Item("raid", "RaidIcon", "Raid marker", side .. "RaidIcon", side .. "RaidIconSize",
            side .. "RaidRelativeAnchor", side .. "RaidIconOffsetX", side .. "RaidIconOffsetY"),
        Item("level", "Level", "Level text", side .. "LevelEnabled", side .. "LevelSize", side .. "LevelAnchor",
            side .. "LevelOffsetX", side .. "LevelOffsetY", side == "enemy" and "enemyLevelColor" or nil),
        Item("elite", "elite", "Boss and rare marker", side .. "EliteMarker", side .. "EliteMarkerSize",
            side .. "EliteMarkerAnchor", side .. "EliteOffsetX", side .. "EliteOffsetY"),
        Item("quest", "quest", "Quest marker", side .. "QuestMarker", side .. "QuestMarkerSize",
            side .. "QuestMarkerAnchor", side .. "QuestOffsetX", side .. "QuestOffsetY"),
    }
    for _, status in ipairs(Style.Status or {}) do
        local key = side .. status.key
        if P.catalog[ID].rules[key] then
            local item = Item(status.key, status.key, status.label, key, key .. "Size",
                key .. "Anchor", key .. "OffsetX", key .. "OffsetY", key .. "Layer", status.sample and key .. "Color" or nil)
            item.player = status.player
            items[#items + 1] = item
        end
    end
    local icons = Item("identity", "identity", "Player identity icons")
    icons.keys = identity
    icons.mode, icons.player = side .. "IdentityIcons", true
    items[#items + 1] = icons
    if target then
        local arrows = Item("target", "target", "Target arrows", "enemyTargetMarker")
        arrows.keys = { unpack(target, 2) }
        for _, key in ipairs({ "enemyTargetOffsetX", "enemyTargetOffsetY", "enemyTargetPrimaryOffsetX", "enemyTargetPrimaryOffsetY",
            "enemyTargetMirrorOffsetX", "enemyTargetMirrorOffsetY" }) do arrows.keys[#arrows.keys + 1] = key end
        items[#items + 1] = arrows
        items[#items + 1] = Item("focus", "focusMarker", "Focus diamond", "enemyFocusMarker",
            "enemyFocusMarkerSize", "enemyFocusMarkerX", "enemyFocusMarkerY", "enemyFocusMarkerColor")
    end
    for source = X.FirstTextSource, X.LastTextSource do
        local key = X.TextKey(scope, source)
        local definition = X.TextIndicators[source]
        local item = Item(key, definition.element, definition.label, key,
            key .. "Anchor", key .. "X", key .. "Y", key .. "Size", key .. "Unknown", key .. "Color")
        if definition.layer then item.keys[#item.keys + 1] = key .. "Layer" end
        item.textSource = source
        items[#items + 1] = item
    end
    return items
end

local function InScope(item)
    local scope = P.NameplatesWorkspace.Kind()
    return not item.player or scope ~= "neutral" and scope ~= "friendlyNpc"
end

local function AddSignals(items, side, signals, threshold)
    local aggro, soft = unpack(signals.tabs)
    if side == "enemy" then
        local aggroItem = Item("aggro", "Aggro", aggro.label, nil, unpack(aggro.keys))
        for _, key in ipairs(signals.colors) do aggroItem.keys[#aggroItem.keys + 1] = key end
        items[#items + 1] = aggroItem
    end
    local softTarget = Item("soft", "SoftTarget", soft.label, nil, unpack(soft.keys))
    softTarget.keys[#softTarget.keys + 1] = side .. "SoftTargetOffsetX"
    softTarget.keys[#softTarget.keys + 1] = side .. "SoftTargetOffsetY"
    items[#items + 1] = softTarget
    items[#items + 1] = Item("classification", "Classification", "Blizzard elite / rare icon", nil,
        "enemyRarityIcon", side .. "ClassificationOffsetX", side .. "ClassificationOffsetY")
    if threshold then
        items[#items + 1] = Item("threshold", "Threshold", "Threshold", threshold[1], unpack(threshold, 2))
    end
end

function Status.IsOffset(key)
    return key:match("Offset[XY]$") or key:match("IdentityIcon[XY]$") or key:match("FocusMarker[XY]$")
        or key:match("ExtraText%a+[XY]$") or key:match("^aura.*[XY]$")
end

function Status.Configure(spec, side, identity, target, tab, signals, threshold)
    spec.statusItems = Status.Items(side, identity, target, spec.plateScope)
    AddSignals(spec.statusItems, side, signals, threshold)
    spec.statusSettings, spec.statusOffsets = {}, {}
    local keys, byItem = {}, {}
    for _, item in ipairs(spec.statusItems) do
        byItem[item.key] = item
        if item.toggle then
            keys[#keys + 1] = item.toggle
            spec.statusSettings[item.toggle] = item.key
        end
        for _, key in ipairs(item.keys) do
            if Status.IsOffset(key) then
                item.positionable = true
                local element = key:find("TargetMirrorOffset", 1, true) and "targetRight"
                    or key:find("enemyTargetOffset", 1, true) and "targetPair" or item.element
                spec.statusOffsets[key] = { element = element, sample = item.element }
            else
                keys[#keys + 1] = key
            end
            spec.statusSettings[key] = item.key
        end
    end
    spec.currentStatus = function()
        local item = byItem[spec.statusSelection or "raid"]
        return InScope(item) and item or byItem.raid
    end
    spec.revealStatus = function(setting)
        local item = byItem[spec.statusSettings[setting]]
        if item and not InScope(item) then P.NameplatesWorkspace.Open(side) end
    end
    spec.tabs = { { id = "basic", label = "Basic", keys = keys }, tab }
    return spec
end

function Status.PreviewItems(menu, scope, select)
    for _, spec in ipairs(P.NameplateSections) do
        if spec.plateScope == scope and spec.statusItems then
            for _, item in ipairs(spec.statusItems) do
                if item.positionable and InScope(item) then
                    local element = item.element == "target" and "targetPair" or item.element
                    menu:CreateButton(Tr(item.label), function() select(element, item.element) end)
                    if item.element == "target" then
                        menu:CreateButton(Tr("Primary target arrow"), function() select("target", "target") end)
                        menu:CreateButton(Tr("Right target arrow"), function() select("targetRight", "target") end)
                    end
                end
            end
            return
        end
    end
end

local function Card(parent, title, x, y, width, height)
    if P.W.ControlCard then return P.W.ControlCard(parent, title, nil, x, y, width, height) end
    local card = P.T.Panel(parent, nil, P.T.colors.panel2, P.T.colors.borderSoft)
    card:SetPoint("TOPLEFT", x, y)
    card:SetWidth(width)
    if height then card:SetHeight(height) end
    P.Text(card, title, 16, -14, width - 32)
    return card
end

local function Enabled(item)
    if item.toggle then return P.Get(ID, item.toggle) == true end
    return not item.mode or P.Get(ID, item.mode) ~= 1
end

local function ResetItem(item)
    if not item then return end
    local rules = {}
    for _, key in ipairs(item.keys) do
        local rule = P.catalog[ID].rules[key]
        if rule and key ~= item.mode and not P.NameplateFonts.OwnsColor(rule) then rules[#rules + 1] = rule end
    end
    P.ResetRules(ID, rules)
end

local function BindEnabled(ctx, choice, item, sectionId, byKey)
    local rule = byKey[item.toggle or item.mode]
    if not rule then return end
    local row = P.RuleRow(PAGE, ID, rule, nil, sectionId)
    local control = P.W.SwitchAt(choice, Tr("Enabled"), choice:GetWidth() - 52, -24, 0, "HIDDEN")
    local switch, checked = nil, row.get
    if item.mode then
        local previousMode = item.defaultMode or 4
        checked = function() return Enabled(item) end
        switch = P.M.BindBoolWidget(ctx, control, checked, function(enabled)
            local mode = P.Get(ID, item.mode)
            if mode ~= 1 then previousMode = mode end
            P.Set(ID, item.mode, enabled and previousMode or 1)
        end)
    else
        switch = P.M.BindBoolWidget(ctx, control, row.get, row.set, row)
    end
    local entry = { rule = rule, widget = switch, checked = checked }
    P.GateControls(ctx, ID, { entry })
    return switch, entry
end

local function BuildItem(ctx, parent, choice, width, item, sectionId, byKey, selectItem)
    local panel = CreateFrame("Frame", nil, parent)
    panel:SetPoint("TOPLEFT", 0, 0)
    panel:SetWidth(width + 16)
    local card = Card(panel, item.textSource and "Text" or "Placement", 0, 0, width)
    local y, rules = -54, {}
    local switch, entry = BindEnabled(ctx, choice, item, sectionId, byKey)
    for _, key in ipairs(item.keys) do
        if key ~= item.mode and byKey[key] then rules[#rules + 1] = byKey[key] end
    end
    local modeEntry
    if item.mode and byKey[item.mode] then
        local _, entries = P.RuleGrid(ctx, choice, PAGE, ID, { byKey[item.mode] }, -98, choice:GetWidth() - 32, nil, sectionId, 1)
        modeEntry = entries[1]
    end
    local resetWidth = 150
    local placementWidth = width >= 550 and width - resetWidth - 52 or width - 32
    local entries
    y, entries = P.RuleGrid(ctx, card, PAGE, ID, rules, y, placementWidth, nil, sectionId, 1)
    local key
    for _, setting in ipairs(item.keys) do
        local rule = P.catalog[ID].rules[setting]
        if rule and P.NameplateFonts.OwnsColor(rule) then key = setting break end
    end
    local colors
    if key then
        colors = P.Button(ctx, card, "Text Colors", 0, 0, 144, function()
            P.NameplateFonts.OpenColors("msufsuite.nameplates." .. key)
        end)
    else
        colors = P.AttachRuleColors(panel, item.label, ID, rules)
    end
    if colors then
        colors:ClearAllPoints()
        colors:SetPoint("TOPRIGHT", card, "TOPRIGHT", -12, -12)
        if (key or item.textSource) and P.M.RegisterControlMetadata then
            local meta = P.Meta(PAGE, ID, item.key .. ".colors", "action", sectionId)
            P.M.RegisterControlMetadata(colors, meta, key and "Text Colors" or "Colors", "button")
        end
    end
    if entry then entries[#entries + 1] = entry end
    if modeEntry then entries[#entries + 1] = modeEntry end
    local function Prepare() selectItem(item.key) end
    for _, control in ipairs(entries) do
        if control.widget then
            HM.SetSearchTargetPrepare(control.widget, Prepare)
        end
    end
    local wide = width >= 550
    local reset = P.Button(ctx, card, "Reset selected", wide and width - resetWidth - 16 or 16, wide and -54 or y,
        resetWidth, function() ResetItem(item) end)
    HM.SkipHistoryCheckpoint(reset)
    y = wide and math.min(y, -84) or y - 34
    local height = math.max(242, 12 - y)
    card:SetHeight(height)
    panel:SetHeight(height + 6)
    return { panel = panel, switch = switch, mode = modeEntry and modeEntry.widget }
end

local function PreviewButton(card, label, x, y, width, action, sectionId, path)
    local button = P.T.Button(card, label, width, 22)
    button:SetPoint("TOPLEFT", x, y)
    button:SetScript("OnClick", action)
    HM.SkipHistoryCheckpoint(button)
    if P.M.RegisterControlMetadata then
        P.M.RegisterControlMetadata(button, P.Meta(PAGE, ID, "preview." .. path .. "." .. sectionId, "ephemeral", sectionId),
            label, "button")
    end
    return button
end

local function PreviewButtons(card, width, y, current, sectionId, side, tab)
    local currentWidth = math.min(142, math.floor((width - 40) * .56))
    local allWidth = math.min(112, width - 40 - currentWidth)
    local button = PreviewButton(card, "Preview current", 16, y, currentWidth, function()
        local item = current()
        if item then P.PreviewNameplateStatus(item.element) end
    end, sectionId, tab .. ".current")
    local all = PreviewButton(card, "Show all", 24 + currentWidth, y, allWidth, function()
        P.PreviewNameplateStatus(nil, true)
    end, sectionId, tab .. ".all")
    local function Refresh()
        local item = current()
        local editable = not P.Combat()
        button:SetEnabled(item ~= nil and editable)
        all:SetEnabled(editable)
        local enabled = item and Enabled(item) and P.Get(ID, "look") ~= 2 and P.Get(ID, side)
        if item and P.T.ApplyButtonRole then P.T.ApplyButtonRole(button, enabled and "success" or "danger") end
    end
    return Refresh
end

local function EliteExamples(card)
    local examples = {}
    for index, variant in ipairs({ "rare", "elite", "boss" }) do
        local badge = card:CreateTexture(nil, "ARTWORK")
        badge:SetPoint("TOPLEFT", card, "TOPLEFT", 17 + (index - 1) * 28, -159)
        Style.PaintMarker(badge, "elite", 22, nil, variant)
        examples[index] = badge
    end
    return examples
end

local function SamplePlate(card, width)
    local label = P.Text(card, "Icon preview", 16, -146, width - 32, P.T.colors.accent)
    local plate = CreateFrame("Frame", nil, card)
    plate:SetPoint("TOPLEFT", card, "TOPLEFT", 16, -158)
    plate:SetSize(width - 32, 24)
    local background = plate:CreateTexture(nil, "BACKGROUND")
    background:SetAllPoints(plate)
    background:SetColorTexture(.020, .026, .052, .70)
    local icon = plate:CreateTexture(nil, "ARTWORK")
    icon:SetSize(22, 22)
    local faction = plate:CreateTexture(nil, "ARTWORK")
    faction:SetPoint("RIGHT", plate, "RIGHT", -1, 0)
    faction:SetSize(22, 22)
    local factionAtlas = P.Suite.Client.isForever and "UI-HUD-UnitFrame-SmallCircle-Horde" or "UI-HUD-UnitFrame-Player-PVP-HordeIcon"
    local sample = P.T.Font(plate, "GameFontHighlightSmall", "", P.T.colors.text)
    sample:SetPoint("CENTER")
    return label, plate, icon, faction, sample, factionAtlas
end

local function IconSample(card, width, side)
    local label, plate, icon, faction, sample, factionAtlas = SamplePlate(card, width)
    local targetSample = CreateFrame("Frame", nil, card)
    targetSample:SetPoint("LEFT", plate, "RIGHT", 28, 0)
    targetSample:SetSize(28, 10)
    local targetVisual = {}
    local elite = EliteExamples(card)
    return function(item)
        local element = item.element
        local data = Style.StatusByKey[element]
        local caption = item.textSource and P.NameplatesPreviewDecor.ExtraTextSample(item.textSource)
            or data and data.sample or (element == "Level" and "90") or nil
        local texture = data and data.texture
        local atlas = data and data.atlas
        local identity = element == "identity" and P.Get(ID, side .. "IdentityIcons")
        if element == "RaidIcon" then texture = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_8"
        elseif element == "quest" then atlas = Style.Markers.quest.atlas
        elseif element == "Classification" then atlas = "nameplates-icon-elite-gold"
        elseif element == "SoftTarget" then icon:SetColorTexture(.40, .78, 1, 1)
        elseif element == "Aggro" then caption = Tr("Aggro")
        elseif element == "Threshold" then caption = Tr("Threshold")
        elseif identity then atlas = identity == 3 and factionAtlas or "classicon-warrior"
        elseif element == "focusMarker" then texture = "Interface\\AddOns\\MSUF_Suite\\Media\\Nameplates\\Focus.tga" end
        local showTarget = element == "target"
        targetSample:SetShown(showTarget)
        local alpha = Enabled(item) and 1 or .46
        for _, badge in ipairs(elite) do
            badge:SetShown(element == "elite")
            badge:SetAlpha(alpha)
        end
        if showTarget then
            local target = Style.TargetConfig(P.S.Config(ID))
            target.bossTargetSize = math.min(target.bossTargetSize, 22)
            target.primaryX, target.primaryY, target.mirrorX, target.mirrorY = -22, 0, 22, 0
            Style.PaintTarget(targetVisual, targetSample, true, target, targetSample)
            targetSample:SetAlpha(alpha)
        end
        if atlas then
            icon:SetAtlas(atlas)
        elseif texture then
            icon:SetTexture(texture)
            icon:SetTexCoord(0, 1, 0, 1)
        end
        icon:ClearAllPoints()
        if identity == 4 then
            icon:SetPoint("LEFT", plate, "LEFT", 1, 0)
            faction:SetAtlas(factionAtlas)
        else
            icon:SetPoint("CENTER")
        end
        faction:SetShown(identity == 4)
        icon:SetShown(atlas ~= nil or texture ~= nil or element == "SoftTarget")
        P.SetTranslatedText(sample, caption and Tr(caption) or "")
        sample:SetShown(caption ~= nil)
        local color = item.textSource and P.Get(ID, item.key .. "Color")
            or data and data.sample and P.Get(ID, side .. element .. "Color")
        sample:SetTextColor(P.RGB(color or "ffffff"))
        plate:SetWidth(caption and math.max(24, sample:GetStringWidth() + 8) or identity == 4 and 52 or 24)
        plate:SetShown(not showTarget and element ~= "elite")
        plate:SetAlpha(alpha)
        local role = element == "StatusLeader" or element == "StatusAssist"
        P.SetTranslatedText(label, Tr(caption and "Text preview" or role and "Role icon preview" or "Icon preview"))
    end
end

function Status.More(ctx, parent, y, width, sectionId, spec)
    if spec then
        local card = Card(parent, "Advanced Placement", 16, y, width, 232)
        local Current = spec.currentStatus
        local function LayerRule()
            local item = Current()
            local key = item.textSource and item.key or spec.positionSide .. item.element
            return P.catalog[ID].rules[key .. "Layer"]
        end
        local layerWidth = math.min(270, math.floor((width - 48) * .5))
        local layer = P.M.BindSliderAt(ctx, card, Tr("Layer"), 16, -58, 0, 30, 1, layerWidth, function()
            local rule = LayerRule()
            return rule and P.Get(ID, rule.key) or 0
        end, function(value)
            local rule = LayerRule()
            if rule and P.RuleEnabled(ID, rule) then P.Set(ID, rule.key, value) end
        end, { step = 1, roundStep = true })
        local reset = P.Button(ctx, card, "Reset selected", width - layerWidth - 16, -58, math.min(150, layerWidth),
            function() ResetItem(Current()) end, Current)
        HM.SkipHistoryCheckpoint(reset)
        P.M.TrackRefresh(ctx, function()
            local rule = LayerRule()
            layer:SetShown(rule ~= nil)
            layer:SetEnabled(rule and P.RuleEnabled(ID, rule) or false)
        end)
        P.M.TrackRefresh(ctx, PreviewButtons(card, width, -178, Current, sectionId, spec.positionSide, "more"))
        y = y - 244
    end
    local note = P.Text(parent, "Player status icons require a player nameplate. The AFK timer starts when the plate first sees the player go AFK.",
        16, y - 6, width)
    return y - math.max(16, math.ceil(note:GetStringHeight() or 16)) - 18
end

local function IndicatorChoices(spec)
    local items, all, npc = {}, {}, {}
    for _, item in ipairs(spec.statusItems) do
        items[item.key] = item
        local value = { value = item.key, text = Tr(item.label) }
        all[#all + 1] = value
        if not item.player then npc[#npc + 1] = value end
    end
    return items, function()
        local scope = P.NameplatesWorkspace.Kind()
        return (scope == "neutral" or scope == "friendlyNpc") and npc or all
    end
end

local function BasicCards(ctx, parent, width, spec, sectionId)
    local narrow = width < 492
    local left = narrow and width or math.min(316, math.max(236, math.floor((width - 28) * .46)))
    local right = narrow and width or math.min(336, width - left - 28)
    local choice = Card(parent, "Selected Indicator", 16, -12, left, narrow and 160 or 214)
    local preview = Card(parent, "Status Preview", narrow and 16 or 44 + left, narrow and -184 or -12, right, 214)
    local Current = spec.currentStatus
    local refreshButtons = PreviewButtons(preview, right, -54, Current, sectionId, spec.positionSide, "basic")
    local paintIcon = IconSample(preview, right, spec.positionSide)
    local function Refresh()
        refreshButtons()
        paintIcon(Current())
    end
    P.M.TrackRefresh(ctx, Refresh)
    local top = narrow and -410 or -238
    local content = CreateFrame("Frame", nil, parent)
    content:SetPoint("TOPLEFT", 16, top)
    content:SetSize(width, 1)
    return choice, content, left, top, Refresh
end

function Status.Basic(ctx, parent, width, spec, tab, sectionId, resize)
    local items, Values = IndicatorChoices(spec)
    local panels, byKey = {}, {}
    for _, rule in ipairs(tab.rules) do byKey[rule.key] = rule end
    local selected = spec.currentStatus().key
    local Current = spec.currentStatus
    local choice, content, left, top, Refresh = BasicCards(ctx, parent, width, spec, sectionId)
    local function Select(key)
        if not items[key] or not InScope(items[key]) or P.Combat() then return end
        local previous = panels[selected]
        if previous then
            previous.panel:Hide()
            if previous.switch then previous.switch:Hide() end
            if previous.mode then previous.mode:Hide() end
        end
        selected, spec.statusSelection = key, key
        if not panels[key] then
            panels[key] = BuildItem(ctx, content, choice, width, items[key], sectionId, byKey, function(value)
                if spec.select then spec.select("basic", value) end
            end)
        end
        local current = panels[key]
        current.panel:Show()
        if current.switch then current.switch:Show() end
        if current.mode then current.mode:Show() end
        Refresh()
        resize(-top + current.panel:GetHeight() + 12)
    end
    local values = Values()
    local control = P.M.BindDropdownAt(ctx, choice, Tr("Indicator"), 16, -54, values, left - 32,
        function() return selected end, function(key)
            Select(key)
            P.SelectNameplateStatusPreview(Current().element)
        end)
    P.StyleMenuControl(control)
    Select(selected)
    local function SyncScope()
        local nextValues = Values()
        if values ~= nextValues then
            values = nextValues
            if control.SetValues then control:SetValues(values) end
            if not InScope(items[selected]) then Select("raid") end
            control:SetValue(selected, true)
        end
    end
    return function(key)
        SyncScope()
        if key and key ~= selected then Select(key) end
        control:SetValue(selected, true)
    end
end

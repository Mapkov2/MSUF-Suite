local _, P = ...
local Page, M, Tr, HM, T = P.DataTextPage, P.M, P.Tr, P.HM, P.T
local ID, PAGE = "dataTexts", "suite_dataTexts"
local Presets = {}
P.DataTextPresetPage = Presets
local LOOKS = { 1, 2, 3, 5, 6 }
local CARD_PAD, CARD_GAP, PREVIEW_HEIGHT = 12, 18, 94

local function Values(preset, bar, look, target)
    local config = P.S.Config(ID)
    local values = target and P.Suite.DataTextPresetValues(preset, bar, config)
        or P.Suite.DataTextBarCreationValues(config, bar, preset)
    if preset ~= "antique" then
        values["bar" .. bar .. "StyleOverride"] = true
        for _, key in ipairs(P.Suite.DataTextStyleKeys) do
            local styleKey = P.Suite.DataTextBarStyleKey(bar, key)
            if values[styleKey] == nil then values[styleKey] = P.Get(ID, key) end
        end
        local lookKey = "bar" .. bar .. "Look"
        values[lookKey] = look or values[lookKey] or P.Get(ID, "look")
        if values[lookKey] == 4 then values[lookKey] = P.Suite.Client.isForever and 3 or 2 end
        values["bar" .. bar .. "CustomColors"] = false
    end
    return values
end

local function RefreshCards(cards, look, target)
    local bar = target or P.Suite.DataTextNextBarID(P.S.Config(ID)) or 1
    local current = P.S.Config(ID)
    for _, card in ipairs(cards) do
        local config = {}
        for key, value in pairs(current) do config[key] = value end
        for key, value in pairs(Values(card.preset.id, bar, look, target)) do config[key] = value end
        card.config, card.bar = config, bar
    end
end

local function Card(ctx, body, preset, width, section, target, getLook, choose)
    local frame = T.Panel(body, nil, T.colors.panel2, T.colors.borderSoft)
    local card = { frame = frame, preset = preset, bar = target or P.Suite.DataTextNextBarID(P.S.Config(ID)) or 1 }
    local inner = width - 2 * CARD_PAD
    card.title = P.Text(frame, preset.title, CARD_PAD, -CARD_PAD, inner, T.colors.text, "heading")
    local preview = P.DataTextsPreview.Build(ctx, frame, function() return card.bar end, {
        x = CARD_PAD, y = -36, width = inner, height = PREVIEW_HEIGHT, interactive = false, compact = true,
        config = function() return card.config end,
    })
    card.preview = preview
    local names = {}
    for _, key in ipairs(P.Suite.DataTextPresetSources(preset.id)) do
        names[#names + 1] = Tr(P.Suite.DataTextSources[P.Suite.DataTextSourceIndex[key]])
    end
    preview.host:EnableMouse(true)
    M.AddTooltip(preview.host, Tr(preset.title), table.concat(names, ", "))
    card.description = P.Text(frame, preset.description, CARD_PAD, -142, inner)
    local action = target and "Apply preset to this bar" or "Add bar"
    local key = (target and "bar" .. target .. "." or "") .. "preset." .. preset.id
    card.button = Page.Button(ctx, frame, action, CARD_PAD, -176, inner, function()
        local bar = target or P.Suite.DataTextNextBarID(P.S.Config(ID))
        if not bar then return end
        if target then
            if P.SetMany(ID, Values(preset.id, bar, getLook(), target)) then ctx.dataTextWorkspace.choose(bar, "content", 1) end
        else
            Page.selections[bar] = { mode = "content", slot = 1 }
            Page.ChangeBars(Values(preset.id, bar, getLook()), bar)
        end
    end, key, section, choose, function() return target ~= nil or P.Suite.DataTextNextBarID(P.S.Config(ID)) ~= nil end)
    card.button:ClearAllPoints()
    card.button:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", CARD_PAD, CARD_PAD)
    return card
end

local function CardHeight(card, width)
    local frame, preview = card.frame, card.preview.host
    local inner = width - 2 * CARD_PAD
    frame:SetWidth(width)
    card.title:SetWidth(inner)
    local previewY = -CARD_PAD - math.max(20, card.title:GetStringHeight()) - 8
    preview:ClearAllPoints()
    preview:SetPoint("TOPLEFT", frame, "TOPLEFT", CARD_PAD, previewY)
    preview:SetWidth(inner)
    local descriptionY = previewY - PREVIEW_HEIGHT - 8
    card.description:ClearAllPoints()
    card.description:SetPoint("TOPLEFT", frame, "TOPLEFT", CARD_PAD, descriptionY)
    card.description:SetWidth(inner)
    card.button:SetWidth(inner)
    return -descriptionY + math.max(18, card.description:GetStringHeight()) + 10 + card.button:GetHeight() + CARD_PAD
end

local function Columns(width) return width >= 570 and 2 or 1 end
local function CardWidth(width, columns) return (width - (columns - 1) * CARD_GAP) / columns end

local function LayoutCards(cards, body, y, width)
    local columns = Columns(width)
    local cardWidth, rowHeight = CardWidth(width, columns), 0
    for index, card in ipairs(cards) do
        local column = (index - 1) % columns
        card.frame:ClearAllPoints()
        card.frame:SetPoint("TOPLEFT", body, "TOPLEFT", 16 + column * (cardWidth + CARD_GAP), y)
        rowHeight = math.max(rowHeight, CardHeight(card, cardWidth))
        if column == columns - 1 or index == #cards then
            for item = index - column, index do cards[item].frame:SetHeight(rowHeight) end
            y, rowHeight = y - rowHeight - CARD_GAP, 0
        end
    end
    return y
end

function Presets.Build(ctx, builder, choose, target, getState, back)
    local section = target and PAGE .. "_bar" .. target .. "_presets" or PAGE .. "_presets"
    local title = target and "Apply preset to this bar" or "Add bar"
    local body = builder:CollapsibleSection(section, Tr(title), 120, true)
    local width = (HM.GetSectionWidth(body) or builder.width) - 32
    local cards, look = {}, nil
    local function GetLook() return not target and getState().look or look end
    local function SelectedLook()
        local current = GetLook() or P.Get(ID, "look")
        if current == 4 then return P.Suite.Client.isForever and 3 or 2 end
        return current
    end
    local y, hint = -18, nil
    if not target then
        local button = T.Button(body, "Back", 112, 26, { noSearch = true })
        button:SetPoint("TOPLEFT", body, "TOPLEFT", 16, y)
        button:SetScript("OnClick", function() if not P.Combat() then back() end end)
        HM.SkipHistoryCheckpoint(button)
        y = y - 36
        hint = P.Text(body, "Choose a starting point. Existing bars stay unchanged.", 16, y, width)
    end
    local function PickerY()
        if not hint then return y end
        hint:SetWidth(width)
        return y - math.max(16, hint:GetStringHeight()) - 14
    end
    local choices = {}
    for _, index in ipairs(LOOKS) do
        choices[#choices + 1] = { value = index, text = Tr(P.catalog[ID].rules.look.choices[index]) }
    end
    local picker = M.BindDropdownAt(ctx, body, "MSUF style", 16, PickerY(), choices, width, SelectedLook, function(value)
        if target then look = value else getState().look = value end
        RefreshCards(cards, value, target)
        for _, card in ipairs(cards) do card.preview:Refresh() end
    end, P.Meta(PAGE, ID, (target and "bar" .. target or "presets") .. ".look", "ephemeral", section))
    M.TrackRefresh(ctx, function() if body:IsVisible() then RefreshCards(cards, GetLook(), target) end end)
    local cardWidth = CardWidth(width, Columns(width))
    for _, preset in ipairs(P.Suite.DataTextPresets) do
        cards[#cards + 1] = Card(ctx, body, preset, cardWidth, section, target, GetLook, choose)
    end
    RefreshCards(cards, GetLook(), target)
    for _, card in ipairs(cards) do card.preview:Refresh() end
    P.FinishBody(builder, body, LayoutCards(cards, body, PickerY() - 64, width))
    body:HookScript("OnSizeChanged", function(_, bodyWidth)
        local usable = bodyWidth - 32
        if usable <= 2 * CARD_PAD or usable == width then return end
        width = usable
        local pickerY = PickerY()
        P.W.MoveWidget(picker, body, 16, pickerY, width)
        P.FinishBody(builder, body, LayoutCards(cards, body, pickerY - 64, width))
    end)
    return cards
end

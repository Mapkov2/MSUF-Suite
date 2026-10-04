local _, P = ...
local Page, M, Tr = P.DataTextPage, P.M, P.Tr
local ID, PAGE = "dataTexts", "suite_dataTexts"
local Presets = {}
P.DataTextPresetPage = Presets
local LOOKS = { 1, 2, 3, 5, 6 }

local function Values(preset, bar, look, target)
    local config = P.S.Config(ID)
    local values = target and P.Suite.DataTextPresetValues(preset, bar, config)
        or P.Suite.DataTextBarCreationValues(config, bar, preset)
    if preset ~= "antique" then
        values["bar" .. bar .. "StyleOverride"] = true
        for _, key in ipairs(P.Suite.DataTextStyleKeys) do values[P.Suite.DataTextBarStyleKey(bar, key)] = P.Get(ID, key) end
        values["bar" .. bar .. "Look"], values["bar" .. bar .. "CustomColors"] = look, false
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

local function Card(ctx, body, preset, x, y, width, section, target, getLook, choose)
    local card = { preset = preset, bar = target or P.Suite.DataTextNextBarID(P.S.Config(ID)) or 1 }
    P.Text(body, preset.title, x, y, width, P.T.colors.text)
    local preview = P.DataTextsPreview.Build(ctx, body, function() return card.bar end, {
        x = x, y = y - 25, width = width, height = 94, interactive = false, compact = true,
        config = function() return card.config end,
    })
    card.preview = preview
    local names = {}
    for _, key in ipairs(P.Suite.DataTextPresetSources(preset.id)) do
        names[#names + 1] = Tr(P.Suite.DataTextSources[P.Suite.DataTextSourceIndex[key]])
    end
    preview.host:EnableMouse(true)
    M.AddTooltip(preview.host, Tr(preset.title), table.concat(names, ", "))
    local description = P.Text(body, preset.description, x, y - 126, width)
    local buttonY = y - 126 - math.max(28, description:GetStringHeight()) - 12
    card.height = y - buttonY + 46
    local action = target and "Apply preset to this bar" or "Add bar"
    local key = (target and "bar" .. target .. "." or "") .. "preset." .. preset.id
    Page.Button(ctx, body, action, x, buttonY, width, function()
        local bar = target or P.Suite.DataTextNextBarID(P.S.Config(ID))
        if not bar then return end
        if target then
            if P.SetMany(ID, Values(preset.id, bar, getLook(), target)) then ctx.dataTextWorkspace.choose(bar, "content", 1) end
        else
            Page.selections[bar] = { mode = "content", slot = 1 }
            Page.ChangeBars(Values(preset.id, bar, getLook()), bar)
        end
    end, key, section, choose, function() return target ~= nil or P.Suite.DataTextNextBarID(P.S.Config(ID)) ~= nil end)
    return card
end

function Presets.Build(ctx, builder, choose, target)
    local section = target and PAGE .. "_bar" .. target .. "_presets" or PAGE .. "_presets"
    local title = target and "Apply preset to this bar" or "Add bar"
    local body = builder:CollapsibleSection(section, Tr(title), 120, true)
    local width = (body._msuf2Width or builder.width) - 32
    local look, cards = P.Get(ID, "look"), {}
    if look == 4 then look = P.Suite.Client.isForever and 3 or 2 end
    local y = -18
    if not target then
        local hint = P.Text(body, "Choose a starting point. Existing bars stay unchanged.", 16, y, width)
        y = y - math.max(16, hint:GetStringHeight()) - 14
    end
    local choices = {}
    for _, index in ipairs(LOOKS) do
        choices[#choices + 1] = { value = index, text = Tr(P.catalog[ID].rules.look.choices[index]) }
    end
    M.BindDropdownAt(ctx, body, "MSUF style", 16, y, choices, width, function() return look end, function(value)
        look = value
        RefreshCards(cards, look, target)
        for _, card in ipairs(cards) do card.preview:Refresh() end
    end, P.Meta(PAGE, ID, (target and "bar" .. target or "presets") .. ".look", "ephemeral", section))
    y = y - 64
    M.TrackRefresh(ctx, function() if body:IsVisible() then RefreshCards(cards, look, target) end end)
    local columns = width >= 570 and 2 or 1
    local cardWidth = (width - (columns - 1) * 20) / columns
    local rowHeight = 0
    for index, preset in ipairs(P.Suite.DataTextPresets) do
        local column = (index - 1) % columns
        local card = Card(ctx, body, preset, 16 + column * (cardWidth + 20), y,
            cardWidth, section, target, function() return look end, choose)
        cards[#cards + 1] = card
        rowHeight = math.max(rowHeight, card.height)
        if column == columns - 1 or index == #P.Suite.DataTextPresets then y, rowHeight = y - rowHeight, 0 end
    end
    RefreshCards(cards, look, target)
    for _, card in ipairs(cards) do card.preview:Refresh() end
    P.FinishBody(builder, body, y)
    return cards
end

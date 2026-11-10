local _, P = ...
local Suite, T, Tr, HM = P.Suite, P.T, P.Tr, P.HM
local Model = Suite.CharacterTabs
local WIDTH, HEIGHT = 350, 392
local LIST_TOP, LIST_BOTTOM, ROW_HEIGHT, STEP = 94, 52, 23, 28
local VISIBLE_SLOTS = math.ceil((HEIGHT - LIST_TOP - LIST_BOTTOM) / STEP) + 1
local LIST_WIDTH = WIDTH - 46
local Picker = {}
P.CharacterSourcePicker = Picker

local function DataName(data)
    if Suite.Public(data) and type(data) == "table" then return Suite.PublicText(data.name) end
end

function Picker.SourceText(source)
    if not source.target then return source.text end
    local data
    if source.kind == "faction" then
        data = C_Reputation.GetFactionDataByID(source.target)
    elseif source.kind == "currency" then
        data = C_CurrencyInfo.GetCurrencyInfo(source.target)
    end
    return DataName(data) or source.text
end

local function Group(groups, name)
    local group = { name = name }
    groups[#groups + 1] = group
    return group
end

local function Add(group, entry, english, category)
    entry.search = table.concat({ entry.name, english or "", group.name, category or "", entry.id or "" }, " "):lower()
    group[#group + 1] = entry
end

local function ReportSlots(tab, cardIndex, rowIndex)
    local used = {}
    for i, card in ipairs(tab.cards) do
        for j, row in ipairs(card.rows) do
            if i ~= cardIndex or j ~= rowIndex then
                local source = Model.Source(row.source)
                if source.report then used[source.report] = true end
            end
        end
    end
    return used
end

local function StaticChoices(groups, tab, frame, hasRoom)
    local usedReports = ReportSlots(tab, frame.cardIndex, frame.rowIndex)
    local room = Model.CardLimit - #tab.cards
    if not frame.cardIndex then
        local cards = Group(groups, Tr("Cards"))
        Add(cards, { name = Tr("Empty card"), id = "empty", enabled = room > 0, card = true }, "Empty card")
        for _, group in ipairs(Model.Groups) do
            local duplicate
            for _, id in ipairs(group.sources) do
                local source = Model.Source(id)
                if source.report and usedReports[source.report] then duplicate = true break end
            end
            Add(cards, { name = group.text, id = group.id, card = true, group = group.id,
                enabled = room > 0 and not duplicate, duplicate = duplicate }, group.label)
        end
    end
    local categories = {}
    for _, source in ipairs(Model.Sources) do
        local category = categories[source.category]
        if not category then
            category = Group(groups, Tr(source.category))
            categories[source.category] = category
        end
        local available, duplicate = Model.SourceAvailable(source.id), usedReports[source.report]
        Add(category, { name = source.text, id = source.id, enabled = hasRoom and available and not duplicate,
            unavailable = not available, duplicate = duplicate }, source.label)
    end
end

local function AddNative(group, seen, kind, id, name, category, enabled)
    if not Suite.Finite(id) then return end
    local source = Model.DynamicSourceID(kind, id)
    if not source or seen[source] then return end
    seen[source] = true
    Add(group, { name = name, id = source, enabled = enabled }, nil, category)
end

local function Flag(value)
    return Suite.Public(value) and value == true
end

local function AddFactionGroups(groups, start, room)
    for i = start, #groups do
        local group = groups[i]
        if #group > 1 then
            local members = {}
            for j, entry in ipairs(group) do members[j] = entry.id end
            local name = Tr("Add shown factions in %s"):format(group.name)
            local fits = #members <= room * Model.RowLimit
            local entry = { name = name, title = group.name, members = members,
                enabled = fits, noRoom = not fits, search = (name .. " " .. Tr("Reputation")):lower() }
            table.insert(group, 1, entry)
        end
    end
end

local function FactionChoices(groups, hasRoom, room)
    local count = C_Reputation.GetNumFactions()
    if not Suite.Finite(count) or count < 1 then return end
    local category, seen = Tr("Reputation"), {}
    local group = Group(groups, category)
    local firstHeader = #groups + 1
    for index = 1, count do
        local data = C_Reputation.GetFactionDataByIndex(index)
        local name = DataName(data)
        if name and Suite.Public(data.isHeader) then
            local header = Flag(data.isHeader)
            if header then group = Group(groups, name) end
            if not header or Flag(data.isHeaderWithRep) then
                AddNative(group, seen, "faction", data.factionID, name, category, hasRoom)
            end
        end
    end
    if room then AddFactionGroups(groups, firstHeader, room) end
end

local function CurrencyChoices(groups, hasRoom)
    local count = C_CurrencyInfo.GetCurrencyListSize()
    if not Suite.Finite(count) or count < 1 then return end
    local category, seen = Tr("Currencies"), {}
    local group = Group(groups, category)
    for index = 1, count do
        local data = C_CurrencyInfo.GetCurrencyListInfo(index)
        local name = DataName(data)
        if name and Suite.Public(data.isHeader) then
            if Flag(data.isHeader) then
                group = Group(groups, name)
            else
                AddNative(group, seen, "currency", data.currencyID, name, category, hasRoom)
            end
        end
    end
end

local function Catalog(frame, tab, hasRoom)
    local groups = {}
    StaticChoices(groups, tab, frame, hasRoom)
    FactionChoices(groups, hasRoom, not frame.cardIndex and Model.CardLimit - #tab.cards or nil)
    CurrencyChoices(groups, hasRoom)
    return groups
end

local function Position(region, body, y)
    if region.sourcePickerY == y then return end
    region.sourcePickerY = y
    region:ClearAllPoints()
    region:SetPoint("TOPLEFT", body, "TOPLEFT", 0, -y)
end

local function Button(parent, label, width, height, click)
    local button = T.Button(parent, label, width, height, { noSearch = true })
    HM.SkipHistoryCheckpoint(button)
    button:SetScript("OnClick", click)
    return button
end

local function Row(frame, index)
    local row = frame.rows[index]
    if not row then
        row = Button(frame.body, "", LIST_WIDTH, ROW_HEIGHT, function(button)
            frame.pick(frame, button.entry)
        end)
        frame.rows[index] = row
    end
    return row
end

local function Heading(frame, index)
    local heading = frame.headings[index]
    if not heading then
        heading = P.Text(frame.body, "", 0, 0, LIST_WIDTH, T.colors.muted)
        frame.headings[index] = heading
    end
    return heading
end

local function PaintChoice(frame, row, entry, y)
    local title = entry.name
    if entry.id and frame.currentSource == entry.id then title = Tr("Selected: %s"):format(title) end
    if entry.unavailable then title = Tr("%s - Not available on this client"):format(title)
    elseif entry.duplicate then title = Tr("%s - Already added"):format(title)
    elseif entry.noRoom then title = Tr("%s - Not enough room"):format(title) end
    if row.customText ~= title then
        row.customText = title
        P.SetButtonText(row, title)
    end
    if row.sourcePickerEnabled ~= entry.enabled then
        row.sourcePickerEnabled = entry.enabled
        row:SetEnabled(entry.enabled)
    end
    row.entry = entry
    Position(row, frame.body, y)
    row:Show()
end

local function Paint(frame, offset)
    local first = math.floor(offset / STEP) + 1
    if frame.paintedFirst == first then return end
    frame.paintedFirst = first
    local rows, headings = 0, 0
    for index = first, math.min(first + VISIBLE_SLOTS - 1, #frame.results) do
        local entry, y = frame.results[index], (index - 1) * STEP
        if entry.heading then
            headings = headings + 1
            local heading = Heading(frame, headings)
            P.SetTranslatedText(heading, entry.name)
            Position(heading, frame.body, y)
            heading:Show()
        else
            rows = rows + 1
            PaintChoice(frame, Row(frame, rows), entry, y)
        end
    end
    for i = rows + 1, #frame.rows do
        frame.rows[i].entry = nil
        frame.rows[i]:Hide()
    end
    for i = headings + 1, #frame.headings do frame.headings[i]:Hide() end
end

local function Filter(frame)
    if not frame.catalog then return end
    local query = frame.search:GetText():lower():match("^%s*(.-)%s*$")
    if frame.query == query then return end
    frame.query, frame.first, frame.paintedFirst = query, nil, nil
    local results = frame.results
    wipe(results)
    for _, group in ipairs(frame.catalog) do
        local started
        for _, entry in ipairs(group) do
            if query == "" or entry.search:find(query, 1, true) then
                if not started then
                    group.heading = group.heading or { name = group.name, heading = true }
                    results[#results + 1], started = group.heading, true
                end
                results[#results + 1] = entry
                if not frame.first and entry.enabled then frame.first = entry end
            end
        end
    end
    frame.empty:SetShown(#results == 0)
    frame.body:SetHeight(math.max(1, #results * STEP))
    frame.scroll:SetVerticalScroll(0)
    Paint(frame, 0)
end

local function New(pick)
    local frame = P.MenuPopupPanel(WIDTH, HEIGHT)
    frame.rows, frame.headings, frame.results, frame.pick = {}, {}, {}, pick
    P.Text(frame, "Choose a data source", 12, -10, WIDTH - 50)
    local close = Button(frame, "x", 24, 22, function() frame:Hide() end)
    close:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -8, -6)
    P.Text(frame, "Search data sources", 12, -37, WIDTH - 24, T.colors.muted)
    local input = CreateFrame("EditBox", nil, frame, "InputBoxTemplate")
    input:SetPoint("TOPLEFT", frame, "TOPLEFT", 14, -58)
    input:SetSize(WIDTH - 30, 25)
    input:SetAutoFocus(false)
    input:SetMaxLetters(80)
    input:SetScript("OnTextChanged", function() Filter(frame) end)
    input:SetScript("OnEnterPressed", function() pick(frame, frame.first) end)
    input:SetScript("OnEscapePressed", function() frame:Hide() end)
    frame.search = input
    local styleScroll = T.StyleScrollFrame
    local template = not styleScroll and "ScrollFrameTemplate" or nil
    local scroll = CreateFrame("ScrollFrame", nil, frame, template)
    scroll:SetPoint("TOPLEFT", frame, "TOPLEFT", 12, -LIST_TOP)
    scroll:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -30, LIST_BOTTOM)
    local body = CreateFrame("Frame", nil, scroll)
    body:SetSize(LIST_WIDTH, 1)
    scroll:SetScrollChild(body)
    if styleScroll then
        styleScroll(scroll, frame)
    else
        scroll.ScrollBar:SetHideIfUnscrollable(true)
    end
    frame.scroll, frame.body = scroll, body
    scroll:HookScript("OnVerticalScroll", function(_, offset)
        if frame.catalog then Paint(frame, offset) end
    end)
    frame.empty = P.Text(frame, "No matching data sources.", 12, -LIST_TOP, WIDTH - 24)
    P.Text(frame, "Expand groups in Reputation or Currencies to find more entries.", 12, -HEIGHT + 43, WIDTH - 24, T.colors.muted)
    frame:HookScript("OnHide", function()
        frame.anchor, frame.claim, frame.first, frame.query, frame.catalog, frame.paintedFirst = nil, nil, nil, nil, nil, nil
        wipe(frame.results)
        for _, row in ipairs(frame.rows) do row.entry = nil end
    end)
    frame:Hide()
    return frame
end

function Picker.Open(frame, tab, anchor, claim, cardIndex, rowIndex, hasRoom, pick)
    frame = frame or New(pick)
    if frame:IsShown() and frame.anchor == anchor then frame:Hide() return frame end
    frame:Hide()
    frame.anchor, frame.claim, frame.cardIndex, frame.rowIndex = anchor, claim, cardIndex, rowIndex
    frame.currentSource = rowIndex and tab.cards[cardIndex].rows[rowIndex].source or nil
    frame.catalog = Catalog(frame, tab, hasRoom)
    frame:ClearAllPoints()
    frame:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -5)
    frame.search:SetText("")
    Filter(frame)
    frame:Show()
    frame.search:SetFocus()
    return frame
end

local _, P = ...
local Suite, M, T, Tr, HM = P.Suite, P.M, P.T, P.Tr, P.HM
local Picker = {}
P.DataTextsSourcePicker = Picker
local ID, PAGE = "dataTexts", "suite_dataTexts"
local WIDTH, HEIGHT = 430, 468
local popup
local hookedAnchors = setmetatable({}, { __mode = "k" })
local GROUPS = {
    { "Everyday", { "clock", "date", "gold", "sessionGold", "bags", "durability", "location", "coordinates" } },
    { "Character", { "xp", "progress", "itemLevel", "specialization", "specLoot", "professions" } },
    { "Travel and menus", { "travel", "hearth", "portals", "microMenu" } },
    { "Currencies", { "currency", "crests" } },
    { "System", { "fps", "latency", "fpsLatency", "audio" } },
    { "Addons", { "broker" } },
}
local CATEGORIES = {}
for group, spec in ipairs(GROUPS) do
    for _, key in ipairs(spec[2]) do CATEGORIES[key] = group end
end

local function Available(key)
    return not Suite.DataTextSourceAvailable or Suite.DataTextSourceAvailable(key)
end

-- Static catalog only: filtering does not load addons or inspect game data.
function Picker.Choices(query)
    local entries = {}
    query = (query or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
    for index, raw in ipairs(Suite.DataTextSources) do
        local key = Suite.DataTextSourceKeys[index] or "none"
        local group = CATEGORIES[key] or #GROUPS + 1
        local category = GROUPS[group] and GROUPS[group][1] or "Other"
        local name = Tr(raw)
        local search = (name .. " " .. raw .. " " .. key .. " " .. Tr(category)):lower()
        if query == "" or search:find(query, 1, true) then
            entries[#entries + 1] = { index = index, key = key, name = name, group = group,
                category = Tr(category), available = Available(key) }
        end
    end
    table.sort(entries, function(a, b)
        if a.group ~= b.group then return a.group < b.group end
        return a.index < b.index
    end)
    return entries
end

local function Pick(entry)
    if not popup or P.Combat() or not Available(entry.key) then return end
    local bar, slot, changed = popup.bar, popup.slot, popup.onChanged
    if P.Set(ID, "bar" .. bar .. "Slot" .. slot, entry.index) then
        popup:Hide()
        if changed then changed(entry.index) end
    end
end

local function NewRow(parent)
    local button = T.Button(parent, "", WIDTH - 48, 29, { noSearch = true })
    button:SetScript("OnClick", function() if button.entry then Pick(button.entry) end end)
    return button
end

local function Filter()
    if not popup then return end
    local choices = Picker.Choices(popup.search:GetText())
    local selected = P.Get(ID, "bar" .. popup.bar .. "Slot" .. popup.slot)
    local y, category, headings = -2, nil, 0
    popup.firstChoice = nil
    for i, entry in ipairs(choices) do
        if category ~= entry.category then
            category, headings = entry.category, headings + 1
            local heading = popup.headings[headings] or P.Text(popup.content, "", 0, 0, WIDTH - 48)
            popup.headings[headings] = heading
            heading:ClearAllPoints()
            heading:SetPoint("TOPLEFT", popup.content, "TOPLEFT", 0, y)
            P.SetTranslatedText(heading, category)
            heading:Show()
            y = y - 23
        end
        local button = popup.rows[i] or NewRow(popup.content)
        popup.rows[i], button.entry = button, entry
        button:ClearAllPoints()
        button:SetPoint("TOPLEFT", popup.content, "TOPLEFT", 0, y)
        local label = entry.index == selected and Tr("Selected: %s"):format(entry.name) or entry.name
        if not entry.available then label = Tr("%s - Not available on this client"):format(label) end
        P.SetButtonText(button, label)
        button:SetEnabled(entry.available)
        button:Show()
        if not popup.firstChoice and entry.available then popup.firstChoice = entry end
        y = y - 34
    end
    for i = #choices + 1, #popup.rows do popup.rows[i]:Hide() end
    for i = headings + 1, #popup.headings do popup.headings[i]:Hide() end
    popup.empty:SetShown(#choices == 0)
    popup.content:SetHeight(math.max(1, -y))
    popup.scroll:SetVerticalScroll(0)
end

local function MouseOver(frame)
    return frame and frame:IsVisible() and frame:IsMouseOver()
end

local function Lifecycle(frame)
    frame:SetScript("OnEvent", function(_, event)
        if event == "PLAYER_REGEN_DISABLED" or not MouseOver(frame) and not MouseOver(frame.anchor) then frame:Hide() end
    end)
    frame:HookScript("OnShow", function()
        frame:RegisterEvent("PLAYER_REGEN_DISABLED")
        frame:RegisterEvent("GLOBAL_MOUSE_DOWN")
    end)
    frame:HookScript("OnHide", function()
        frame:UnregisterAllEvents()
        frame.search:ClearFocus()
        if frame:IsShown() then frame:Hide() end
    end)
end

local function SearchBox(frame)
    local input = CreateFrame("EditBox", nil, frame, "InputBoxTemplate")
    input:SetPoint("TOPLEFT", frame, "TOPLEFT", 16, -42)
    input:SetSize(WIDTH - 34, 25)
    input:SetAutoFocus(false)
    input:SetMaxLetters(80)
    if T.SkinEditBox then T.SkinEditBox(input) end
    input:SetScript("OnEscapePressed", function() frame:Hide() end)
    input:SetScript("OnEnterPressed", function() if frame.firstChoice then Pick(frame.firstChoice) end end)
    input:SetScript("OnTextChanged", function() Filter() end)
    local hint = P.Text(frame, "Search data sources", 16, -73, WIDTH - 34)
    hint:SetWordWrap(false)
    return input
end

-- A child of the menu window, like the other Suite popups: under its anchor
-- it would be clipped by the preview host and take the anchor's strata.
local function Ensure()
    if popup then return popup end
    local parent = M.frame or UIParent
    local frame = M.CreateMenuPopupPanel and M.CreateMenuPopupPanel(parent, {}) or CreateFrame("Frame", nil, parent)
    popup = frame
    frame:SetSize(WIDTH, HEIGHT)
    frame:SetFrameStrata("FULLSCREEN_DIALOG")
    frame:SetClampedToScreen(true)
    frame:EnableMouse(true)
    local background = frame:CreateTexture(nil, "BACKGROUND")
    background:SetAllPoints(frame)
    background:SetColorTexture(.025, .035, .045, .98)
    frame.rows, frame.headings = {}, {}
    frame.title = P.Text(frame, "Choose a data source", 14, -14, WIDTH - 52, T.colors.text)
    frame.close = T.Button(frame, "x", 24, 23, { noSearch = true })
    frame.close:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -8, -8)
    HM.SkipHistoryCheckpoint(frame.close)
    frame.close:SetScript("OnClick", function() frame:Hide() end)
    frame.search = SearchBox(frame)
    frame.scroll = CreateFrame("ScrollFrame", nil, frame)
    frame.scroll:SetPoint("TOPLEFT", frame, "TOPLEFT", 14, -100)
    frame.scroll:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -28, 16)
    frame.content = CreateFrame("Frame", nil, frame.scroll)
    frame.content:SetSize(WIDTH - 48, 1)
    frame.scroll:SetScrollChild(frame.content)
    frame.scroll:EnableMouseWheel(true)
    frame.scroll:SetScript("OnMouseWheel", function(self, delta)
        self:SetVerticalScroll(math.max(0, math.min(self:GetVerticalScrollRange(), self:GetVerticalScroll() - delta * 68)))
    end)
    if T.StyleScrollFrame then T.StyleScrollFrame(frame.scroll, frame) end
    frame.empty = P.Text(frame, "No matching data sources.", 14, -106, WIDTH - 48)
    frame:Hide()
    Lifecycle(frame)
    return frame
end

function Picker.Open(anchor, bar, slot, onChanged)
    if P.Combat() or not anchor or not bar or not slot then return false end
    local frame = Ensure()
    if frame:IsShown() and frame.anchor == anchor then
        frame:Hide()
        return false
    end
    frame:Hide()
    -- It still closes with the page its anchor belongs to.
    if not hookedAnchors[anchor] then
        hookedAnchors[anchor] = true
        anchor:HookScript("OnHide", function() if frame.anchor == anchor then frame:Hide() end end)
    end
    frame.anchor, frame.bar, frame.slot, frame.onChanged = anchor, bar, slot, onChanged
    frame:ClearAllPoints()
    frame:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -5)
    if M.ApplyPopupFramePriority then M.ApplyPopupFramePriority(frame) end
    frame.search:SetText("")
    Filter()
    frame:Show()
    frame.search:SetFocus()
    return true
end

local function PublicString(value)
    return not Suite.IsSecret(value) and type(value) == "string" and value ~= ""
end

local function BrokerMenu(anchor, block)
    local stub = Suite.Safety.Field(_G, "LibStub")
    local lib = stub and stub:GetLibrary("LibDataBroker-1.1", true)
    local names = {}
    if lib then
        for name in lib:DataObjectIterator() do
            if PublicString(name) then names[#names + 1] = name end
            if #names >= 256 then break end
        end
    end
    table.sort(names)
    MenuUtil.CreateContextMenu(anchor, function(_, menu)
        menu:SetScrollMode(340)
        menu:CreateTitle(Tr("Choose loaded broker"))
        if #names == 0 then menu:CreateTitle(Tr("No broker plugins are loaded. You can enter a name below.")) end
        for _, name in ipairs(names) do
            menu:CreateRadio(name, function() return P.Get(ID, block .. "Broker") == name end,
                function() P.Set(ID, block .. "Broker", name) end)
        end
    end)
end

local function CurrencyMenu(anchor, block)
    MenuUtil.CreateContextMenu(anchor, function(_, menu)
        menu:SetScrollMode(340)
        menu:CreateTitle(Tr("Choose discovered currency"))
        local found = false
        for index = 1, C_CurrencyInfo.GetCurrencyListSize() do
            local info = C_CurrencyInfo.GetCurrencyListInfo(index)
            if not Suite.IsSecret(info) and type(info) == "table" and PublicString(info.name) then
                if not Suite.IsSecret(info.isHeader) and info.isHeader then
                    local row = index
                    local expanded = not Suite.IsSecret(info.isHeaderExpanded) and info.isHeaderExpanded == true
                    menu:CreateButton(info.name .. (expanded and " -" or " +"), function()
                        C_CurrencyInfo.ExpandCurrencyList(row, not expanded)
                        CurrencyMenu(anchor, block)
                    end)
                else
                    local link = C_CurrencyInfo.GetCurrencyListLink(index)
                    local id = PublicString(link) and C_CurrencyInfo.GetCurrencyIDFromLink(link)
                    if Suite.Finite(id) and id > 0 then
                        found = true
                        menu:CreateRadio(info.name, function() return P.Get(ID, block .. "Currency") == id end,
                            function() P.Set(ID, block .. "Currency", id) end)
                    end
                end
            end
        end
        if not found then menu:CreateTitle(Tr("Expand a category or enter a currency ID below.")) end
    end)
end

function Picker.BuildDetails(ctx, parent, bar, slot, sectionId, y, width)
    local block = "bar" .. bar .. "Slot" .. slot
    local function Source()
        local choice = P.Get(ID, block)
        return choice and Suite.DataTextSourceKeys[choice]
    end
    local meta = P.Meta(PAGE, ID, block .. ".choose", "action", sectionId)
    local button
    button = P.Button(ctx, parent, "Choose discovered currency", 16, y, width, function()
        local source = Source()
        if source == "broker" then BrokerMenu(button, block)
        elseif source == "currency" then CurrencyMenu(button, block) end
    end, function() return not P.Combat() end, meta)
    M.TrackRefresh(ctx, function()
        local source = Source()
        button:SetShown(source == "broker" or source == "currency")
        P.SetButtonText(button, Tr(source == "broker" and "Choose loaded broker" or "Choose discovered currency"))
    end)
    return y - 38, { { meta = meta, label = "Choose data source", widget = button } }
end

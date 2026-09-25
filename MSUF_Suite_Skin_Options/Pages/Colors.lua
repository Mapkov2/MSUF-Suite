local _, Private = ...
local NS, O = Private.NS, Private.Options
local L = NS.L

local ROW_HEIGHT = 56

local GROUPS = {
    { key = "surfaces", label = L["Surfaces"], keys = { "background", "ink", "surface", "raised", "card", "popup", "input", "microBarFill", "microBarFillAlt", "microButtonFill", "microButtonFillAlt" } },
    { key = "text", label = L["Text"], keys = { "text", "title", "muted", "dim", "disabled", "blizzardYellow" } },
    { key = "accents", label = L["Accents"], keys = { "blue", "accent", "accentBright", "success", "warning", "danger", "accentAlt" } },
    { key = "borders", label = L["Borders"], keys = { "rim", "border", "borderSoft", "buttonBorder", "iconBorder", "microBarBorder", "microButtonBorder" } },
    { key = "controls", label = L["Controls"], keys = { "buttonFill", "buttonFillAlt", "hover", "pressed", "active", "checkmark", "microIcon", "microIconHover", "microIconPressed", "microIconDisabled" } },
    { key = "blizzard", label = L["Blizzard"], keys = { "blizzardArrow", "blizzardExpand", "blizzardExpandPressed", "blizzardExpandHover", "blizzardClose", "blizzardClosePressed", "blizzardCloseHover", "blizzardCloseDisabled" } },
}
local GROUP_BY_KEY = {}
for index = 1, #GROUPS do
    local group = GROUPS[index]
    GROUP_BY_KEY[group.key] = group
    group.members = {}
    for member = 1, #group.keys do group.members[group.keys[member]] = true end
end

local SIMPLE_KEYS = {
    background = true, surface = true, text = true, title = true, border = true,
    buttonFill = true, accent = true, hover = true, active = true,
    blizzardYellow = true, checkmark = true, microIcon = true,
}

local DESCRIPTIONS = {
    background = L["Main window backdrop"],
    ink = L["Navigation and deepest panels"],
    surface = L["Standard window panels"],
    raised = L["Raised sections and emphasis"],
    card = L["Cards and grouped settings"],
    popup = L["Menus and floating panels"],
    input = L["Search and text fields"],
    blue = L["Dark interactive accent"],
    accent = L["Primary brand and focus color"],
    accentBright = L["Bright focus edge"],
    text = L["Normal readable text"],
    title = L["Headings and important labels"],
    muted = L["Secondary explanations"],
    dim = L["Low-priority metadata"],
    disabled = L["Unavailable controls"],
    rim = L["Outer structural edge"],
    border = L["Strong outlines"],
    borderSoft = L["Subtle separators and panels"],
    buttonFill = L["Normal button surface"],
    buttonFillAlt = L["Second button shading color"],
    buttonBorder = L["Button outline"],
    iconBorder = L["Theme-colored icon outline"],
    hover = L["Mouse-over highlight"],
    pressed = L["Pressed interaction state"],
    active = L["Selected pages and list entries"],
    success = L["Success and enabled status"],
    warning = L["Warnings and attention"],
    danger = L["Errors and destructive actions"],
    accentAlt = L["Secondary accent"],
    blizzardYellow = L["Gold UI text and system chat"],
    blizzardArrow = L["Dropdown and previous/next arrows"],
    blizzardExpand = L["Plus/minus normal state"],
    blizzardExpandPressed = L["Plus/minus pressed state"],
    blizzardExpandHover = L["Plus/minus mouse-over state"],
    checkmark = L["Checkbox ticks and menu marks"],
    blizzardClose = L["Close X normal state"],
    blizzardClosePressed = L["Close X pressed state"],
    blizzardCloseHover = L["Close X mouse-over state"],
    blizzardCloseDisabled = L["Close X disabled state"],
    microBarFill = L["Micro Bar shared background"],
    microBarFillAlt = L["Micro Bar second shading color"],
    microBarBorder = L["Micro Bar shared outline"],
    microButtonFill = L["Individual Micro button background"],
    microButtonFillAlt = L["Individual Micro button second shading color"],
    microButtonBorder = L["Individual Micro button outline"],
    microIcon = L["Micro icon normal state"],
    microIconHover = L["Micro icon mouse-over state"],
    microIconPressed = L["Micro icon pressed state"],
    microIconDisabled = L["Micro icon disabled state"],
}

local function PaletteLabel(value)
    if value == "classColor" then
        return string.upper(NS.Theme.GetClassLookLabel())
    end
    return string.upper(NS.PaletteLabels[value] or tostring(value))
end

-- Lower-case text a search query is matched against, one per color row.
local function SearchText(key, label)
    return (key .. " " .. tostring(label) .. " " .. tostring(DESCRIPTIONS[key] or "")):lower()
end

local function BuildHeader(page, view)
    local preset = O.CreateDropdown(page, L["Color palette (colors only)"], NS.PaletteOrder, function()
        return NS.DB.theme.preset
    end, function(value)
        NS.Theme.ApplyPreset(value)
    end, 520, PaletteLabel, nil, { countLabel = L["palettes"], countSingular = L["palette"] })
    preset:SetPoint("TOPLEFT", 4, -70)

    local reset = O.CreateButton(page, NS.L.RESET_COLORS, 150, 28, function()
        local began = O.BeginUserChange(NS.L.RESET_COLORS)
        NS.Theme.ResetColors()
        if began then O.CommitUserChange(NS.L.RESET_COLORS) end
    end)
    reset:SetPoint("TOPRIGHT", -4, -77)

    local search = O.CreateSearchBox(page, L["Find a color or UI element..."], function(value)
        view.query = tostring(value or ""):lower():match("^%s*(.-)%s*$") or ""
        if view.Refresh then view.Refresh() end
    end, 570)
    search:SetPoint("TOPLEFT", 4, -116)

    view.count = O.CreateText(page, "", 10, "muted", "RIGHT")
    view.count:SetPoint("TOPRIGHT", -4, -123)
    view.count:SetWidth(164)
end

-- Expert mode browses colors by group; Guided mode shows the essentials.
local function BuildGroupBar(page, view)
    view.groupButtons = {}
    for index = 1, #GROUPS do
        local group = GROUPS[index]
        local button = O.CreateButton(page, group.label, 118, 26, function()
            O.ui.colorGroup = group.key
            view.Refresh()
        end, "navigation")
        button:SetPoint("TOPLEFT", 4 + (index - 1) * 124, -154)
        view.groupButtons[group.key] = button
    end

    local guided = O.CreatePanel(page, "status")
    guided:SetPoint("TOPLEFT", 4, -154)
    guided:SetPoint("TOPRIGHT", -4, -154)
    guided:SetHeight(30)
    local guidedText = O.CreateText(guided,
        L["ESSENTIAL COLORS  |  Search finds all %d colors. Switch to Expert for grouped browsing."]:format(#NS.ColorOrder),
        10, "accent")
    guidedText:SetPoint("LEFT", 12, 0)
    view.guided = guided
end

local function BuildRows(page, view)
    local scrollHost = CreateFrame("Frame", nil, page)
    scrollHost:SetPoint("TOPLEFT", 4, -192)
    scrollHost:SetPoint("BOTTOMRIGHT", -4, 4)
    local _, content = O.CreateScrollContainer(scrollHost, #NS.ColorOrder * ROW_HEIGHT + 12)
    view.content = content
    view.rows = {}
    for index = 1, #NS.ColorOrder do
        local entry = NS.ColorOrder[index]
        local key = entry[1]
        local label = NS.L[entry[2]]
        view.rows[index] = {
            key = key,
            frame = O.CreateColorRow(content, key, label, 750, DESCRIPTIONS[key]),
            search = SearchText(key, label),
        }
    end
end

local function RefreshRows(view)
    local mode = O.GetMode()
    local query = view.query
    local selected = GROUP_BY_KEY[O.ui.colorGroup] or GROUPS[1]
    local visible = 0
    for index = 1, #view.rows do
        local row = view.rows[index]
        local show
        if query ~= "" then
            show = row.search:find(query, 1, true) ~= nil
        elseif mode == "guided" then
            show = SIMPLE_KEYS[row.key] == true
        else
            show = selected.members[row.key] == true
        end
        local frame = row.frame
        frame:ClearAllPoints()
        frame:SetShown(show)
        if show then
            frame:SetPoint("TOPLEFT", 0, -2 - visible * ROW_HEIGHT)
            visible = visible + 1
        end
    end
    view.content:SetHeight(math.max(1, visible * ROW_HEIGHT + 8))
    view.count:SetText(L["%d of %d colors"]:format(visible, #NS.ColorOrder))
    view.guided:SetShown(mode == "guided" and query == "")
    for key, button in pairs(view.groupButtons) do
        button:SetShown(mode == "expert" and query == "")
        O.SetButtonActive(button, key == O.ui.colorGroup)
    end
end

O.RegisterPage("colors", NS.L.COLORS, function(page)
    O.CreateSectionTitle(page, L["Colors"],
        L["Midnight Blue, Midnight Dark and MSUF Forever are complete looks in Style. Color palettes here change colors only; use Expert mode for every UI state."])
    if not GROUP_BY_KEY[O.ui.colorGroup] then O.ui.colorGroup = "surfaces" end

    local view = { query = "" }
    BuildHeader(page, view)
    BuildGroupBar(page, view)
    BuildRows(page, view)
    view.Refresh = function() RefreshRows(view) end
    -- The page refresher also runs after every mode switch while the page is
    -- shown; a hidden page lays its rows out when it is opened.
    O.TrackRefresh(view.Refresh)
    view.Refresh()
end)

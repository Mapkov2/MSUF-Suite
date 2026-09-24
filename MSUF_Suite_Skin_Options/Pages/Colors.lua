local _, Private = ...
local NS, O = Private.NS, Private.Options

local groups = {
    { key = "surfaces", label = "Surfaces", keys = { "background", "ink", "surface", "raised", "card", "popup", "input", "microBarFill", "microBarFillAlt", "microButtonFill", "microButtonFillAlt" } },
    { key = "text", label = "Text", keys = { "text", "title", "muted", "dim", "disabled", "blizzardYellow" } },
    { key = "accents", label = "Accents", keys = { "blue", "accent", "accentBright", "success", "warning", "danger", "accentAlt" } },
    { key = "borders", label = "Borders", keys = { "rim", "border", "borderSoft", "buttonBorder", "iconBorder", "microBarBorder", "microButtonBorder" } },
    { key = "controls", label = "Controls", keys = { "buttonFill", "buttonFillAlt", "hover", "pressed", "active", "checkmark", "microIcon", "microIconHover", "microIconPressed", "microIconDisabled" } },
    { key = "blizzard", label = "Blizzard", keys = { "blizzardArrow", "blizzardExpand", "blizzardExpandPressed", "blizzardExpandHover", "blizzardClose", "blizzardClosePressed", "blizzardCloseHover", "blizzardCloseDisabled" } },
}

local simpleKeys = {
    background = true, surface = true, text = true, title = true, border = true,
    buttonFill = true, accent = true, hover = true, active = true,
    blizzardYellow = true, checkmark = true, microIcon = true,
}

local descriptions = {
    background = "Main window backdrop", ink = "Navigation and deepest panels", surface = "Standard window panels",
    raised = "Raised sections and emphasis", card = "Cards and grouped settings", popup = "Menus and floating panels",
    input = "Search and text fields", blue = "Dark interactive accent", accent = "Primary brand and focus color",
    accentBright = "Bright focus edge", text = "Normal readable text", title = "Headings and important labels",
    muted = "Secondary explanations", dim = "Low-priority metadata", disabled = "Unavailable controls",
    rim = "Outer structural edge", border = "Strong outlines", borderSoft = "Subtle separators and panels",
    buttonFill = "Normal button surface", buttonFillAlt = "Second button shading color", buttonBorder = "Button outline",
    iconBorder = "Theme-colored icon outline", hover = "Mouse-over highlight", pressed = "Pressed interaction state",
    active = "Selected pages and list entries", success = "Success and enabled status", warning = "Warnings and attention",
    danger = "Errors and destructive actions", accentAlt = "Secondary accent", blizzardYellow = "Gold UI text and system chat",
    blizzardArrow = "Dropdown and previous/next arrows", blizzardExpand = "Plus/minus normal state",
    blizzardExpandPressed = "Plus/minus pressed state", blizzardExpandHover = "Plus/minus mouse-over state",
    checkmark = "Checkbox ticks and menu marks", blizzardClose = "Close X normal state",
    blizzardClosePressed = "Close X pressed state", blizzardCloseHover = "Close X mouse-over state",
    blizzardCloseDisabled = "Close X disabled state",
    microBarFill = "Micro Bar shared background", microBarFillAlt = "Micro Bar second shading color",
    microBarBorder = "Micro Bar shared outline", microButtonFill = "Individual Micro button background",
    microButtonFillAlt = "Individual Micro button second shading color",
    microButtonBorder = "Individual Micro button outline", microIcon = "Micro icon normal state",
    microIconHover = "Micro icon mouse-over state", microIconPressed = "Micro icon pressed state",
    microIconDisabled = "Micro icon disabled state",
}

O.RegisterPage("colors", NS.L.COLORS, function(page)
    O.CreateSectionTitle(page, "Colors", "Midnight Blue, Midnight Dark and MSUF Forever are complete looks in Style. Color palettes here change colors only; use Expert mode for every UI state.")

    local preset = O.CreateDropdown(page, "Color palette (colors only)", NS.PaletteOrder, function()
        return NS.DB.theme.preset
    end, function(value)
        NS.Theme.ApplyPreset(value)
    end, 520, function(value)
        if value == "classColor" then
            return string.upper(NS.Theme.GetClassLookLabel())
        end
        return string.upper(NS.PaletteLabels[value] or tostring(value))
    end, nil, { countLabel = "palettes" })
    preset:SetPoint("TOPLEFT", 4, -70)

    local reset = O.CreateButton(page, NS.L.RESET_COLORS, 150, 28, function()
        local began = O.BeginUserChange(NS.L.RESET_COLORS)
        NS.Theme.ResetColors()
        if began then O.CommitUserChange(NS.L.RESET_COLORS) end
    end)
    reset:SetPoint("TOPRIGHT", -4, -77)

    local query = ""
    local RefreshRows
    local search = O.CreateSearchBox(page, "Find a color or UI element...", function(value)
        query = tostring(value or ""):lower():match("^%s*(.-)%s*$") or ""
        if RefreshRows then RefreshRows() end
    end, 570)
    search:SetPoint("TOPLEFT", 4, -116)

    local count = O.CreateText(page, "", 10, "muted", "RIGHT")
    count:SetPoint("TOPRIGHT", -4, -123)
    count:SetWidth(164)

    local groupButtons = {}
    for index = 1, #groups do
        local item = groups[index]
        local button = O.CreateButton(page, item.label, 118, 26, function()
            O.ui.colorGroup = item.key
            RefreshRows()
        end, "navigation")
        button:SetPoint("TOPLEFT", 4 + (index - 1) * 124, -154)
        groupButtons[item.key] = button
    end

    local guided = O.CreatePanel(page, "status")
    guided:SetPoint("TOPLEFT", 4, -154)
    guided:SetPoint("TOPRIGHT", -4, -154)
    guided:SetHeight(30)
    local guidedText = O.CreateText(guided,
        ("ESSENTIAL COLORS  |  Search finds all %d colors. Switch to Expert for grouped browsing."):format(#NS.ColorOrder),
        10, "accent")
    guidedText:SetPoint("LEFT", 12, 0)

    local scrollHost = CreateFrame("Frame", nil, page)
    scrollHost:SetPoint("TOPLEFT", 4, -192)
    scrollHost:SetPoint("BOTTOMRIGHT", -4, 4)
    local _, content = O.CreateScrollContainer(scrollHost, #NS.ColorOrder * 56 + 12)

    local rows = {}
    local entries = {}
    for index = 1, #NS.ColorOrder do
        local entry = NS.ColorOrder[index]
        entries[entry[1]] = entry
        rows[entry[1]] = O.CreateColorRow(content, entry[1], NS.L[entry[2]], 750, descriptions[entry[1]])
    end

    local validGroup = {}
    for index = 1, #groups do validGroup[groups[index].key] = groups[index] end
    if not validGroup[O.ui.colorGroup] then O.ui.colorGroup = "surfaces" end

    RefreshRows = function()
        local mode = O.GetMode()
        local selected = validGroup[O.ui.colorGroup] or groups[1]
        local selectedKeys = {}
        for index = 1, #selected.keys do selectedKeys[selected.keys[index]] = true end
        local visible = 0
        for index = 1, #NS.ColorOrder do
            local entry = NS.ColorOrder[index]
            local key, label = entry[1], tostring(NS.L[entry[2]] or entry[1])
            local matches = query ~= "" and (key:lower() .. " " .. label:lower() .. " " .. tostring(descriptions[key] or ""):lower()):find(query, 1, true) ~= nil
            local show = query ~= "" and matches
                or query == "" and ((mode == "guided" and simpleKeys[key]) or (mode == "expert" and selectedKeys[key]))
            local row = rows[key]
            row:ClearAllPoints()
            row:SetShown(show)
            if show then
                row:SetPoint("TOPLEFT", 0, -2 - visible * 56)
                visible = visible + 1
            end
        end
        content:SetHeight(math.max(1, visible * 56 + 8))
        count:SetText(("%d of %d colors"):format(visible, #NS.ColorOrder))
        guided:SetShown(mode == "guided" and query == "")
        for key, button in pairs(groupButtons) do
            button:SetShown(mode == "expert" and query == "")
            O.SetButtonActive(button, key == O.ui.colorGroup)
        end
    end

    O.TrackMode(RefreshRows)
    O.TrackRefresh(RefreshRows)
    RefreshRows()
end)

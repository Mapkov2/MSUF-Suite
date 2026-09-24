local _, Private = ...
local NS, O = Private.NS, Private.Options

local function Percent(value)
    return tostring(math.floor((tonumber(value) or 0) * 100 + 0.5)) .. "%"
end

local function LookLabel(value)
    if value == "classColor" then
        return string.upper(NS.Theme.GetClassLookLabel())
    end
    local look = NS.LookPresets[value]
    return look and string.upper(look.label) or string.upper(tostring(value))
end

local function DirectionLabel(value)
    return value == "HORIZONTAL" and "Horizontal" or "Vertical"
end

O.RegisterPage("looks", NS.L.LOOKS, function(page)
    O.CreateSectionTitle(page, "Style",
        "Choose Midnight Blue, Midnight Dark or MSUF Forever for Skinning and enabled Suite modules. Modules enabled later inherit it.")

    local controlsHost = CreateFrame("Frame", nil, page)
    controlsHost:SetPoint("TOPLEFT", 4, -70)
    controlsHost:SetPoint("BOTTOMLEFT", 4, 4)
    controlsHost:SetWidth(510)
    local controlsScroll, controlsList = O.CreateScrollContainer(controlsHost, 660, 484)
    page._mskinLooksScroll = controlsScroll
    page._mskinLooksContent = controlsList

    local look, lookButton = O.CreateDropdown(controlsList, "Style preset", NS.LookOrder, function()
        return NS.DB.theme.look
    end, function(value)
        NS.Theme.ApplyLook(value)
    end, 484, LookLabel, nil, { countLabel = "styles" })
    look:SetPoint("TOPLEFT", 0, -2)
    page._mskinLookSelector = lookButton

    local gradient = O.CreateToggle(controlsList, "Shaded surfaces", function()
        return NS.DB.theme.gradient
    end, function(value)
        NS.Theme.SetAppearance("gradient", value)
    end, 484)
    gradient:SetPoint("TOPLEFT", look, "BOTTOMLEFT", 0, -8)

    local direction = O.CreateCycle(controlsList, "Light direction", NS.GradientDirections, function()
        return NS.DB.theme.gradientDirection
    end, function(value)
        NS.Theme.SetAppearance("gradientDirection", value)
    end, 484, DirectionLabel)
    direction:SetPoint("TOPLEFT", gradient, "BOTTOMLEFT", 0, -8)

    local strength = O.CreateSlider(controlsList, "Shading strength", 0, 1, 0.05, function()
        return NS.DB.theme.gradientStrength
    end, function(value)
        NS.Theme.SetAppearance("gradientStrength", value)
    end, 484, Percent)
    strength:SetPoint("TOPLEFT", direction, "BOTTOMLEFT", 0, -8)

    local depth = O.CreateSlider(controlsList, "Surface depth", 0, 1, 0.05, function()
        return NS.DB.theme.materialDepth
    end, function(value)
        NS.Theme.SetAppearance("materialDepth", value)
    end, 484, Percent)
    depth:SetPoint("TOPLEFT", strength, "BOTTOMLEFT", 0, -8)

    local iconSettings = O.CreateButton(controlsList, "Customize icons and Micro Bar", 484, 32, function()
        O.ShowPage("icons")
    end, "navigation")
    iconSettings:SetPoint("TOPLEFT", depth, "BOTTOMLEFT", 0, -8)

    local shell = O.CreateSlider(controlsList, "Window opacity", 0.35, 1, 0.05, function()
        return NS.DB.theme.shellOpacity
    end, function(value)
        NS.Theme.SetAppearance("shellOpacity", value)
    end, 484, Percent)
    shell:SetPoint("TOPLEFT", iconSettings, "BOTTOMLEFT", 0, -8)

    local panels = O.CreateSlider(controlsList, "Content opacity", 0.35, 1, 0.05, function()
        return NS.DB.theme.panelOpacity
    end, function(value)
        NS.Theme.SetAppearance("panelOpacity", value)
    end, 484, Percent)
    panels:SetPoint("TOPLEFT", shell, "BOTTOMLEFT", 0, -8)

    local controls = O.CreateSlider(controlsList, "Controls opacity", 0.35, 1, 0.05, function()
        return NS.DB.theme.controlOpacity
    end, function(value)
        NS.Theme.SetAppearance("controlOpacity", value)
    end, 484, Percent)
    controls:SetPoint("TOPLEFT", panels, "BOTTOMLEFT", 0, -8)

    local borders = O.CreateSlider(controlsList, "Outline opacity", 0, 1, 0.05, function()
        return NS.DB.theme.borderOpacity
    end, function(value)
        NS.Theme.SetAppearance("borderOpacity", value)
    end, 484, Percent)
    borders:SetPoint("TOPLEFT", controls, "BOTTOMLEFT", 0, -8)

    local preview = O.CreatePanel(page, "navigation")
    preview:SetPoint("TOPLEFT", 534, -70)
    preview:SetPoint("BOTTOMRIGHT", -4, 4)

    local heading = O.CreateText(preview, "LIVE LOOK PREVIEW", 11, "muted")
    heading:SetPoint("TOPLEFT", 16, -16)

    local shellPreview = O.CreatePanel(preview, "shell")
    shellPreview:SetPoint("TOPLEFT", 16, -46)
    shellPreview:SetPoint("TOPRIGHT", -16, -46)
    shellPreview:SetHeight(224)

    local title = O.CreateText(shellPreview, "Window shell", 16, "title")
    title:SetPoint("TOPLEFT", 16, -16)
    local subtitle = O.CreateText(shellPreview, "Opacity and material blending remain independent.", 11, "muted")
    subtitle:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -7)
    subtitle:SetPoint("RIGHT", -16, 0)

    local panelPreview = O.CreatePanel(shellPreview, "panel")
    panelPreview:SetPoint("TOPLEFT", 14, -76)
    panelPreview:SetPoint("BOTTOMRIGHT", -14, 14)
    local card = O.CreatePanel(panelPreview, "card")
    card:SetPoint("TOPLEFT", 12, -12)
    card:SetPoint("TOPRIGHT", -12, -12)
    card:SetHeight(58)
    local cardText = O.CreateText(card, "Panel and card layer", 12, "text")
    cardText:SetPoint("LEFT", 12, 0)

    local primary = O.CreateButton(panelPreview, "Primary", 72, 28, nil, "buttonPrimary")
    primary:SetPoint("BOTTOMLEFT", 12, 12)
    local secondary = O.CreateButton(panelPreview, "Secondary", 80, 28)
    secondary:SetPoint("LEFT", primary, "RIGHT", 8, 0)

    local note = O.CreatePanel(preview, "status")
    note:SetPoint("TOPLEFT", shellPreview, "BOTTOMLEFT", 0, -12)
    note:SetPoint("TOPRIGHT", shellPreview, "BOTTOMRIGHT", 0, -12)
    note:SetHeight(94)
    local noteTitle = O.CreateText(note, "CURRENT LOOK", 11, "accent")
    noteTitle:SetPoint("TOPLEFT", 14, -14)
    local noteText = O.CreateText(note, "", 11, "text")
    noteText:SetPoint("TOPLEFT", noteTitle, "BOTTOMLEFT", 0, -8)
    noteText:SetPoint("RIGHT", -14, 0)
    noteText:SetJustifyV("TOP")
    page._mskinLookNoteTitle = noteTitle
    page._mskinLookNoteText = noteText

    local function RefreshLookNote()
        local selected = NS.LookPresets[NS.DB.theme.look] or NS.LookPresets.custom
        noteTitle:SetText("CURRENT LOOK / " .. string.upper(selected.label or "Custom"))
        noteText:SetText(selected.description
            or "Your current hand-tuned combination of palette, material and geometry.")
    end
    O.TrackRefresh(RefreshLookNote)
    RefreshLookNote()

    local rows = {
        { look, true }, { gradient, false }, { direction, false }, { strength, false }, { depth, false },
        { iconSettings, true }, { shell, true }, { panels, true }, { controls, true }, { borders, false },
    }
    local function RefreshMode()
        local guided = O.GetMode() == "guided"
        local previous
        local contentHeight = 4
        for index = 1, #rows do
            local row, essential = rows[index][1], rows[index][2]
            local show = not guided or essential
            row:ClearAllPoints()
            row:SetShown(show)
            if show then
                if previous then row:SetPoint("TOPLEFT", previous, "BOTTOMLEFT", 0, -8)
                else row:SetPoint("TOPLEFT", 0, -2) end
                contentHeight = contentHeight + row:GetHeight() + (previous and 8 or 0)
                previous = row
            end
        end
        controlsList:SetHeight(math.max(1, contentHeight + 4))
    end
    O.TrackMode(RefreshMode)
    RefreshMode()
end)

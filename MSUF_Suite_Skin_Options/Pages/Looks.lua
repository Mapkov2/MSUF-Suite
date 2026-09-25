local _, Private = ...
local NS, O = Private.NS, Private.Options
local L = NS.L

local WIDTH = 484

local function LookLabel(value)
    if value == "classColor" then
        return string.upper(NS.Theme.GetClassLookLabel())
    end
    local look = NS.LookPresets[value]
    return look and string.upper(look.label) or string.upper(tostring(value))
end

local DirectionLabel = O.Labeler({ HORIZONTAL = L["Horizontal"], VERTICAL = L["Vertical"] })

local function ThemeGetter(key)
    return function() return NS.DB.theme[key] end
end

local function ThemeSetter(key)
    return function(value) NS.Theme.SetAppearance(key, value) end
end

-- { label, theme key, minimum, essential in Guided mode }
local MATERIAL_SLIDERS = {
    { L["Shading strength"], "gradientStrength", 0, false },
    { L["Surface depth"], "materialDepth", 0, false },
}
local OPACITY_SLIDERS = {
    { L["Window opacity"], "shellOpacity", 0.35, true },
    { L["Content opacity"], "panelOpacity", 0.35, true },
    { L["Controls opacity"], "controlOpacity", 0.35, true },
    { L["Outline opacity"], "borderOpacity", 0, false },
}

local function AddSliders(list, rows, specs)
    for index = 1, #specs do
        local spec = specs[index]
        local slider = O.CreateSlider(list, spec[1], spec[3], 1, 0.05, ThemeGetter(spec[2]),
            ThemeSetter(spec[2]), WIDTH, O.Percent)
        rows[#rows + 1] = { slider, spec[4] }
    end
end

-- The left column: every look control, stacked for the current mode.
local function BuildControls(page)
    local controlsHost = CreateFrame("Frame", nil, page)
    controlsHost:SetPoint("TOPLEFT", 4, -70)
    controlsHost:SetPoint("BOTTOMLEFT", 4, 4)
    controlsHost:SetWidth(510)
    local controlsScroll, list = O.CreateScrollContainer(controlsHost, 660, WIDTH)
    page._mskinLooksScroll = controlsScroll
    page._mskinLooksContent = list

    local rows = {}
    local look, lookButton = O.CreateDropdown(list, L["Style preset"], NS.LookOrder,
        ThemeGetter("look"), function(value) NS.Theme.ApplyLook(value) end,
        WIDTH, LookLabel, nil, { countLabel = L["styles"], countSingular = L["style"] })
    page._mskinLookSelector = lookButton
    rows[#rows + 1] = { look, true }
    rows[#rows + 1] = { O.CreateToggle(list, L["Shaded surfaces"], ThemeGetter("gradient"),
        ThemeSetter("gradient"), WIDTH), false }
    rows[#rows + 1] = { O.CreateCycle(list, L["Light direction"], NS.GradientDirections,
        ThemeGetter("gradientDirection"), ThemeSetter("gradientDirection"), WIDTH, DirectionLabel), false }
    AddSliders(list, rows, MATERIAL_SLIDERS)
    rows[#rows + 1] = { O.CreateButton(list, L["Customize icons and Micro Bar"], WIDTH, 32, function()
        O.ShowPage("icons")
    end, "navigation"), true }
    AddSliders(list, rows, OPACITY_SLIDERS)

    local RefreshMode = O.StackRows(list, rows)
    O.TrackMode(RefreshMode)
    RefreshMode()
end

-- The right column: a live sample of the shell, panel, card and buttons.
local function BuildPreview(page)
    local preview = O.CreatePanel(page, "navigation")
    preview:SetPoint("TOPLEFT", 534, -70)
    preview:SetPoint("BOTTOMRIGHT", -4, 4)

    local heading = O.CreateText(preview, L["LIVE LOOK PREVIEW"], 11, "muted")
    heading:SetPoint("TOPLEFT", 16, -16)

    local shellPreview = O.CreatePanel(preview, "shell")
    shellPreview:SetPoint("TOPLEFT", 16, -46)
    shellPreview:SetPoint("TOPRIGHT", -16, -46)
    shellPreview:SetHeight(224)

    local title = O.CreateText(shellPreview, L["Window shell"], 16, "title")
    title:SetPoint("TOPLEFT", 16, -16)
    local subtitle = O.CreateText(shellPreview, L["Opacity and material blending remain independent."], 11, "muted")
    subtitle:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -7)
    subtitle:SetPoint("RIGHT", -16, 0)

    local panelPreview = O.CreatePanel(shellPreview, "panel")
    panelPreview:SetPoint("TOPLEFT", 14, -76)
    panelPreview:SetPoint("BOTTOMRIGHT", -14, 14)
    local card = O.CreatePanel(panelPreview, "card")
    card:SetPoint("TOPLEFT", 12, -12)
    card:SetPoint("TOPRIGHT", -12, -12)
    card:SetHeight(58)
    local cardText = O.CreateText(card, L["Panel and card layer"], 12, "text")
    cardText:SetPoint("LEFT", 12, 0)

    local primary = O.CreateButton(panelPreview, L["Primary"], 72, 28, nil, "buttonPrimary")
    primary:SetPoint("BOTTOMLEFT", 12, 12)
    local secondary = O.CreateButton(panelPreview, L["Secondary"], 80, 28)
    secondary:SetPoint("LEFT", primary, "RIGHT", 8, 0)
    return shellPreview
end

local function BuildLookNote(page, shellPreview)
    local note = O.CreatePanel(page, "status")
    note:SetPoint("TOPLEFT", shellPreview, "BOTTOMLEFT", 0, -12)
    note:SetPoint("TOPRIGHT", shellPreview, "BOTTOMRIGHT", 0, -12)
    note:SetHeight(94)
    local noteTitle = O.CreateText(note, L["CURRENT LOOK"], 11, "accent")
    noteTitle:SetPoint("TOPLEFT", 14, -14)
    local noteText = O.CreateText(note, "", 11, "text")
    noteText:SetPoint("TOPLEFT", noteTitle, "BOTTOMLEFT", 0, -8)
    noteText:SetPoint("RIGHT", -14, 0)
    noteText:SetJustifyV("TOP")
    page._mskinLookNoteTitle = noteTitle
    page._mskinLookNoteText = noteText

    local function RefreshLookNote()
        local selected = NS.LookPresets[NS.DB.theme.look] or NS.LookPresets.custom
        noteTitle:SetText(L["CURRENT LOOK / %s"]:format(string.upper(selected.label or L["Custom"])))
        noteText:SetText(selected.description
            or L["Your current hand-tuned combination of palette, material and geometry."])
    end
    O.TrackRefresh(RefreshLookNote)
    RefreshLookNote()
end

O.RegisterPage("looks", NS.L.LOOKS, function(page)
    O.CreateSectionTitle(page, L["Style"],
        L["Choose Midnight Blue, Midnight Dark or MSUF Forever for Skinning and enabled Suite modules. Modules enabled later inherit it."])
    BuildControls(page)
    BuildLookNote(page, BuildPreview(page))
end)

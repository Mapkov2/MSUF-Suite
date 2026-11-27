local _, Private = ...
local NS, O = Private.NS, Private.Options
local L = NS.L

local HoverLabel = O.Labeler({
    outline = L["Border only"],
    softFill = L["Soft fill"],
    solidFill = L["Solid fill"],
    off = L["Off"],
})

local FAMILY_SAMPLES = {
    { key = "round", label = L["Circular  n=2"] },
    { key = "continuous", label = L["Continuous  n=4"] },
    { key = "squircle", label = L["Squircle  n=6"] },
}

local function RadiusIndex()
    for index = 1, #NS.GeometryRadii do
        if NS.GeometryRadii[index] == NS.DB.geometry.radius then return index end
    end
    return 3
end

local function WindowRadiusIndex()
    for index = 1, #NS.WindowRadii do
        if NS.WindowRadii[index] == NS.DB.geometry.windowRadius then return index end
    end
    return 3
end

-- Rounded windows: one shape for every skinned window and menu.
local function AddWindowRounding(list, rows)
    local rounded = O.CreateToggle(list, L["Round all windows and menus"], function()
        return NS.DB.geometry.roundWindows == true
    end, function(value)
        NS.Theme.SetWindowRounding("roundWindows", value)
    end, 520)
    local radius = O.CreateSlider(list, L["Window corner radius"], 1, #NS.WindowRadii, 1, WindowRadiusIndex,
        function(value) NS.Theme.SetWindowRounding("windowRadius", NS.WindowRadii[value]) end,
        520, function(value) return O.Pixel(NS.WindowRadii[value]) end)
    O.TrackAndRefresh(function() O.SetWidgetEnabled(radius, NS.DB.geometry.roundWindows == true) end)
    rows[#rows + 1] = { rounded, true }
    rows[#rows + 1] = { radius, true }
end

local function BorderLabel(value)
    return value == 0 and L["Off"] or O.Pixel(value)
end

-- The left column scrolls: every row stays reachable at the window's height.
local function BuildControls(page)
    local _, list = O.CreateLeftColumn(page, 536, 900, 520)
    local rows = {}
    local function Add(widget) rows[#rows + 1] = { widget, true } end
    Add(O.CreateCycle(list, L["Window corner style"], NS.GeometryFamilies, function()
        return NS.DB.geometry.family
    end, function(value)
        NS.Theme.SetGeometry("family", value)
    end, 520, O.HumanizeShape))
    Add(O.CreateCycle(list, L["Button corner style"], NS.ControlShapes, function()
        return NS.DB.geometry.controlShape
    end, function(value)
        NS.Theme.SetGeometry("controlShape", value)
    end, 520, O.HumanizeShape))
    Add(O.CreateSlider(list, L["Corner radius"], 1, #NS.GeometryRadii, 1, RadiusIndex, function(value)
        NS.Theme.SetGeometry("radius", NS.GeometryRadii[value])
    end, 520, function(value) return O.Pixel(NS.GeometryRadii[value]) end))
    AddWindowRounding(list, rows)
    Add(O.CreateSlider(list, L["Outline thickness"], 0, 2, 1, function()
        return NS.DB.geometry.border
    end, function(value)
        NS.Theme.SetGeometry("border", value)
    end, 520, BorderLabel, { outlineSetting = "msufsuite.skin.geometry.border" }))
    Add(O.CreateSlider(list, L["Window outline"], 0, 10, 1, function()
        return NS.DB.theme.windowOutline
    end, function(value)
        NS.Theme.SetAppearance("windowOutline", value)
    end, 520, BorderLabel, { outlineSetting = "msufsuite.skin.theme.windowOutline" }))
    Add(O.CreateColorRow(list, "windowOutline", L["Outline color"], 520))
    Add(O.CreateToggle(list, L["Match tooltip border"], function()
        return NS.DB.theme.windowOutlineMatchTooltip == true
    end, function(value)
        NS.Theme.SetAppearance("windowOutlineMatchTooltip", value)
    end, 520, { outlineSetting = "msufsuite.skin.theme.windowOutlineMatchTooltip" }))
    Add(O.CreateCycle(list, L["Hover highlight"], NS.HoverStyles, function()
        return NS.DB.theme.hoverStyle
    end, function(value)
        NS.Theme.SetAppearance("hoverStyle", value)
    end, 520, HoverLabel))
    Add(O.CreateSlider(list, L["Hover intensity"], 0, 1, 0.05, function()
        return NS.DB.theme.hoverIntensity
    end, function(value)
        NS.Theme.SetAppearance("hoverIntensity", value)
    end, 520, O.Percent))
    Add(O.CreateToggle(list, L["Two-color material gradients"], function()
        return NS.DB.theme.gradient
    end, function(value)
        NS.Theme.SetGradient(value)
    end, 520))
    O.StackRows(list, rows)()
end

-- Three static sample cards, one per corner family.
local function BuildCurveComparison(page)
    local preview = O.CreatePanel(page, "navigation")
    preview:SetPoint("TOPLEFT", 544, -70)
    preview:SetPoint("BOTTOMRIGHT", -4, 4)

    local heading = O.CreateText(preview, L["CURVE COMPARISON"], 11, "muted")
    heading:SetPoint("TOPLEFT", 16, -16)
    local y = -48
    for index = 1, #FAMILY_SAMPLES do
        local item = FAMILY_SAMPLES[index]
        local sample = CreateFrame("Frame", nil, preview)
        sample:SetPoint("TOPLEFT", 16, y)
        sample:SetPoint("TOPRIGHT", -16, y)
        sample:SetHeight(112)
        NS.Surface.Attach(sample, { role = "card", shape = item.key })
        local label = O.CreateText(sample, item.label, 13, item.key == "continuous" and "accent" or "text")
        label:SetPoint("TOPLEFT", 14, -14)
        local noteText = item.key == "continuous"
            and L["Default: soft continuous transition into straight edges"]
            or L["Alternative geometry profile"]
        local note = O.CreateText(sample, noteText, 11, "muted")
        note:SetPoint("TOPLEFT", label, "BOTTOMLEFT", 0, -8)
        note:SetPoint("RIGHT", -14, 0)
        note:SetMaxLines(2)
        local button = O.CreateButton(sample, L["Preview"], 104, 28)
        button:SetPoint("BOTTOMRIGHT", -12, 12)
        y = y - 122
    end
end

O.RegisterPage("geometry", NS.L.GEOMETRY, function(page)
    O.CreateSectionTitle(page, L["Corners and interactions"],
        L["Fine-tune window shapes, button shapes, outlines and mouse-over feedback."])
    BuildControls(page)
    BuildCurveComparison(page)
end)

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

local function BorderLabel(value)
    return value == 0 and L["Off"] or O.Pixel(value)
end

local function BuildControls(page)
    local family = O.CreateCycle(page, L["Window corner style"], NS.GeometryFamilies, function()
        return NS.DB.geometry.family
    end, function(value)
        NS.Theme.SetGeometry("family", value)
    end, 520, O.HumanizeShape)
    family:SetPoint("TOPLEFT", 4, -70)

    local controls = O.CreateCycle(page, L["Button corner style"], NS.ControlShapes, function()
        return NS.DB.geometry.controlShape
    end, function(value)
        NS.Theme.SetGeometry("controlShape", value)
    end, 520, O.HumanizeShape)
    controls:SetPoint("TOPLEFT", family, "BOTTOMLEFT", 0, -8)

    local radius = O.CreateSlider(page, L["Corner radius"], 1, #NS.GeometryRadii, 1, RadiusIndex, function(value)
        NS.Theme.SetGeometry("radius", NS.GeometryRadii[value])
    end, 520, function(value) return O.Pixel(NS.GeometryRadii[value]) end)
    radius:SetPoint("TOPLEFT", controls, "BOTTOMLEFT", 0, -8)

    local border = O.CreateSlider(page, L["Outline thickness"], 0, 2, 1, function()
        return NS.DB.geometry.border
    end, function(value)
        NS.Theme.SetGeometry("border", value)
    end, 520, BorderLabel)
    border:SetPoint("TOPLEFT", radius, "BOTTOMLEFT", 0, -8)

    local hoverStyle = O.CreateCycle(page, L["Hover highlight"], NS.HoverStyles, function()
        return NS.DB.theme.hoverStyle
    end, function(value)
        NS.Theme.SetAppearance("hoverStyle", value)
    end, 520, HoverLabel)
    hoverStyle:SetPoint("TOPLEFT", border, "BOTTOMLEFT", 0, -8)

    local hoverIntensity = O.CreateSlider(page, L["Hover intensity"], 0, 1, 0.05, function()
        return NS.DB.theme.hoverIntensity
    end, function(value)
        NS.Theme.SetAppearance("hoverIntensity", value)
    end, 520, O.Percent)
    hoverIntensity:SetPoint("TOPLEFT", hoverStyle, "BOTTOMLEFT", 0, -8)

    local gradient = O.CreateToggle(page, L["Two-color material gradients"], function()
        return NS.DB.theme.gradient
    end, function(value)
        NS.Theme.SetGradient(value)
    end, 520)
    gradient:SetPoint("TOPLEFT", hoverIntensity, "BOTTOMLEFT", 0, -8)
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
        if note.SetMaxLines then note:SetMaxLines(2) end
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

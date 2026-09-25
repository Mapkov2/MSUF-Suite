local _, Private = ...
local NS, O = Private.NS, Private.Options
local L = NS.L

O.Layout = {
    width = 1060,
    height = 720,
    header = 56,
    rail = 208,
    padding = 16,
}

-- Colors each role was last painted with; see the text role refresher below.
local paintedColors = {}

function O.SetTextColor(fontString, colorKey)
    if not fontString then return end
    colorKey = colorKey or "text"
    O.textRoles[fontString] = colorKey
    local r, g, b, a = NS.Theme.GetColor(colorKey)
    if not paintedColors[colorKey] then paintedColors[colorKey] = { r, g, b, a } end
    fontString:SetTextColor(r, g, b, a)
end

function O.CreateText(parent, text, size, colorKey, justify)
    local fontString = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    local fontPath = fontString:GetFont()
    if fontPath and size then
        fontString:SetFont(fontPath, size, "")
    end
    fontString:SetText(text or "")
    fontString:SetJustifyH(justify or "LEFT")
    O.SetTextColor(fontString, colorKey or "text")
    return fontString
end

function O.CreatePanel(parent, role, inset)
    local frame = CreateFrame("Frame", nil, parent)
    NS.Surface.Attach(frame, {
        role = role or "panel",
        inset = inset or 0,
    })
    return frame
end

function O.FormatRGBA(color)
    local r = math.floor((color[1] or 0) * 255 + 0.5)
    local g = math.floor((color[2] or 0) * 255 + 0.5)
    local b = math.floor((color[3] or 0) * 255 + 0.5)
    local a = math.floor((color[4] or 1) * 100 + 0.5)
    return ("#%02X%02X%02X  %d%%"):format(r, g, b, a)
end

------------------------------------------------------------------ value labels
function O.Percent(value)
    return tostring(math.floor((tonumber(value) or 0) * 100 + 0.5)) .. "%"
end

function O.Pixel(value)
    value = math.floor((tonumber(value) or 0) + 0.5)
    return tostring(value) .. " px"
end

-- Formatter over a static label map; unknown values show as they are.
function O.Labeler(labels)
    return function(value)
        return labels[value] or tostring(value)
    end
end

O.HumanizeShape = O.Labeler({
    round = L["Circular"],
    continuous = L["Continuous n=4"],
    squircle = L["Squircle n=6"],
    pill = L["Pill"],
})

------------------------------------------------------------------ text roles
-- FontStrings are not Surface registry consumers. One weak role map lets
-- presets and token edits repaint every existing options label without hooks
-- or per-widget handlers. The map is repainted only when a role color
-- changed, so ordinary setting refreshes compare a few colors and stop.
local function RoleColorsChanged()
    local changed = false
    for colorKey, painted in pairs(paintedColors) do
        local r, g, b, a = NS.Theme.GetColor(colorKey)
        if painted[1] ~= r or painted[2] ~= g or painted[3] ~= b or painted[4] ~= a then
            painted[1], painted[2], painted[3], painted[4] = r, g, b, a
            changed = true
        end
    end
    return changed
end

O.TrackRefresh(function()
    if not RoleColorsChanged() then return end
    for fontString, colorKey in pairs(O.textRoles) do
        fontString:SetTextColor(NS.Theme.GetColor(colorKey))
    end
end)

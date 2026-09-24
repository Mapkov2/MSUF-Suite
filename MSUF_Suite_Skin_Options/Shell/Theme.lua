local _, Private = ...
local NS, O = Private.NS, Private.Options

O.Layout = {
    width = 1060,
    height = 720,
    header = 56,
    rail = 208,
    padding = 16,
}

function O.SetTextColor(fontString, colorKey)
    if not fontString then return end
    colorKey = colorKey or "text"
    O.textRoles[fontString] = colorKey
    fontString:SetTextColor(NS.Theme.GetColor(colorKey))
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

function O.HumanizeShape(shape)
    local labels = {
        round = "Circular",
        continuous = "Continuous n=4",
        squircle = "Squircle n=6",
        pill = "Pill",
    }
    return labels[shape] or tostring(shape)
end

-- FontStrings are not Surface registry consumers. Keep one weak role map so
-- presets and token edits repaint every existing options label without hooks
-- or per-widget event handlers.
O.TrackRefresh(function()
    for fontString, colorKey in pairs(O.textRoles) do
        if fontString and type(fontString.SetTextColor) == "function" then
            fontString:SetTextColor(NS.Theme.GetColor(colorKey))
        end
    end
end)

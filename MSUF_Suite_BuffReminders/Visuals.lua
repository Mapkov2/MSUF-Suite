local _, P = ...
local NS, S = P.NS, P.Suite
local R = P.BuffReminders
-- The secure runtime buttons and the menu's ordinary buttons share regions,
-- crop, typography and layout. Action attributes remain in the controller.
function R.CreateIcon(button)
    button.icon = S.CreateTexture(button, nil, "ARTWORK")
    button.icon:SetPoint("TOPLEFT", button, "TOPLEFT", 1, -1)
    button.icon:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -1, 1)
    button.icon:SetTexCoord(.08, .92, .08, .92)
    button.border = S.CreateTexture(button, nil, "BACKGROUND")
    button.border:SetAllPoints(button)
    button.border:SetColorTexture(1, .72, .34, 1)
    button.count = S.CreateFontString(button, nil, "OVERLAY", "GameFontHighlightSmall")
    button.count:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -2, 2)
end

function R.PaintEntry(button, entry)
    local action = (entry.kind == "spell" or entry.notice == "food") and "spell" or "item"
    button.icon:SetTexture(R.Texture(action, entry.id))
    button.icon:SetDesaturated(entry.restock)
    button.count:SetText("")
end

function R.StyleCount(button, config)
    local point = NS.AnchorPoints[config.countPosition or 9] or "BOTTOMRIGHT"
    button.count:ClearAllPoints()
    button.count:SetPoint(point, button, point, config.countX or -2, config.countY or 2)
    S.SetFont(button.count, S.ResolveFont(config.countFont), config.countSize or 12, "OUTLINE")
end

function R.IconGeometry(config, count)
    local size, spacing, columns = config.size, config.spacing, config.columns
    local displayColumns = math.min(columns, math.max(1, count))
    local rows = math.max(1, math.ceil(count / columns))
    return displayColumns * size + (displayColumns - 1) * spacing,
        rows * size + (rows - 1) * spacing
end

function R.PositionIcon(button, host, shown, config)
    local size, spacing, columns = config.size, config.spacing, config.columns
    button:ClearAllPoints()
    button:SetPoint("TOPLEFT", host, "TOPLEFT", (shown % columns) * (size + spacing),
        -math.floor(shown / columns) * (size + spacing))
end

function R.PreviewCount(entry)
    return entry.group and "2" or entry.kind ~= "spell" and not entry.notice and "5" or ""
end

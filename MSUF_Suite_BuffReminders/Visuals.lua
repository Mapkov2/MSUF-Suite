local _, P = ...
local NS, S = P.NS, P.Suite
local R = P.BuffReminders
local SQUARE = "RECTANGLE"
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

-- Look resolution belongs to settings/compile, never aura or bag evaluation.
function R.IconLook(config)
    local shape = NS.IconShapeIds[config.iconShape or 1] or SQUARE
    if not config.iconSkin or config.iconSkin == "CUSTOM" then return shape end
    return shape, NS.HostBridge.IconSkinLook(config.iconSkin, shape)
end

local function SquareColor(frame, r, g, b)
    for i = 1, 4 do frame.edges[i]:SetColorTexture(r, g, b, 1) end
end

local function SquareBorder(button)
    if button.reminderSquareBorder then return button.reminderSquareBorder end
    local frame = CreateFrame("Frame", nil, button)
    frame:SetAllPoints(button)
    frame:SetFrameLevel(button:GetFrameLevel() + 1)
    frame.edges, frame.SetColorTexture = {}, SquareColor
    for i, edge in ipairs({ "TOP", "BOTTOM", "LEFT", "RIGHT" }) do
        local texture = S.CreateTexture(frame, nil, "OVERLAY", nil, 7)
        frame.edges[i] = texture
        if i <= 2 then
            texture:SetPoint("TOPLEFT", frame, edge == "TOP" and "TOPLEFT" or "BOTTOMLEFT", 0, edge == "TOP" and 0 or 1)
            texture:SetPoint("TOPRIGHT", frame, edge == "TOP" and "TOPRIGHT" or "BOTTOMRIGHT", 0, edge == "TOP" and 0 or 1)
            texture:SetHeight(1)
        else
            texture:SetPoint("TOPLEFT", frame, edge == "LEFT" and "TOPLEFT" or "TOPRIGHT", edge == "LEFT" and 0 or -1, 0)
            texture:SetPoint("BOTTOMLEFT", frame, edge == "LEFT" and "BOTTOMLEFT" or "BOTTOMRIGHT", edge == "LEFT" and 0 or -1, 0)
            texture:SetWidth(1)
        end
    end
    frame:Hide()
    button.reminderSquareBorder = frame
    return frame
end

local function ShapeBorder(button, shape)
    local art = NS.HostBridge.IconShapeArt(shape)
    button.reminderBorderArt = art
    if art then
        button.border:SetDrawLayer("OVERLAY", 7)
        button.border:SetTexture(art)
    else
        button.border:SetDrawLayer("BACKGROUND", 0)
        button.border:SetColorTexture(1, .72, .34, 1)
    end
    button.alertColor = nil
end

-- Secure runtime and ordinary preview buttons use exactly this cold painter.
function R.StyleIcon(button, config, look, shape)
    local size = config.size
    if button.reminderStyleSize == size and button.reminderStyleLook == look
        and button.reminderStyleShape == shape then return end
    local previous = button.reminderStyleSize ~= nil
    local shaped = shape ~= SQUARE or button.reminderStyleShape and button.reminderStyleShape ~= SQUARE
    local skinChanged = look ~= nil or button.reminderSkinned
    if skinChanged then
        button.icon:ClearAllPoints()
        local inset = look and 0 or 1
        button.icon:SetPoint("TOPLEFT", button, "TOPLEFT", inset, -inset)
        button.icon:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -inset, inset)
    end
    local actual = shape
    if shaped or skinChanged then
        actual = NS.HostBridge.ApplyIconShape(button, shape, button.icon, nil, button.icon)
    end
    if shaped or previous and button.reminderBorderArt then ShapeBorder(button, actual) end
    if button.alertPulse then button.alertPulse:Stop() end
    button.alertPulse, button.alertPulsing, button.reminderBorderShown = nil, nil, nil
    if button.reminderSquareBorder then button.reminderSquareBorder:Hide() end
    button.reminderAlertBorder = look and actual == SQUARE and SquareBorder(button) or nil
    if skinChanged then
        button.reminderSkinned = NS.HostBridge.PaintIconSkin(button, look, size, size, button.icon)
        button.alertColor = nil
    end
    if skinChanged or shaped then button.border:SetShown(not button.reminderSkinned and not button.reminderAlertBorder) end
    button.reminderStyleSize, button.reminderStyleLook, button.reminderStyleShape = size, look, shape
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

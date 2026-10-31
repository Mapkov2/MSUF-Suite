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

-- The note texts (the ready check note, the notice lines) keep their Blizzard
-- font object, and so the client's and the skin's fonts, while their size
-- setting is 0, which is the look they always had. Another size draws the
-- object's own face at that size; label.sized remembers it, so a return to 0
-- restores the object.
function R.StyleNote(label, object, size)
    if size > 0 then
        local path, _, flags = object:GetFont()
        S.SetFont(label, path, size, flags)
        label.sized = true
    elseif label.sized then
        label.sized = nil
        label:SetFontObject(object)
    end
end

-- The "Screen anchor" choice (catalog: point). Center and Top keep the
-- numbers older profiles stored; the other seven anchors follow in the
-- Suite's order, as the catalog lists them. The host is placed by this point
-- of itself on the same point of the screen, so every anchor keeps that point
-- of the row's box where it is while the icons fill the box from its top
-- left.
local SCREEN_POINTS = { "CENTER", "TOP", "TOPLEFT", "TOPRIGHT", "LEFT", "RIGHT", "BOTTOMLEFT", "BOTTOM", "BOTTOMRIGHT" }

function R.ScreenPoint(config)
    return SCREEN_POINTS[config.point] or "CENTER"
end

-- The note texts hang on the row's host: the notice lines below it, the ready
-- check note above it. A bottom anchor leaves no room below the row, so every
-- note hangs above it; this is the one rule for both.
local BOTTOM_POINTS = { BOTTOM = true, BOTTOMLEFT = true, BOTTOMRIGHT = true }

-- Whether a note that belongs below the row (below) hangs there.
function R.NoteBelow(config, below)
    return below and not BOTTOM_POINTS[R.ScreenPoint(config)]
end

-- anchor is what the note hangs on: the host, or a note already on that side.
function R.PlaceNote(label, anchor, config, below, gap)
    label:ClearAllPoints()
    if R.NoteBelow(config, below) then
        label:SetPoint("TOP", anchor, "BOTTOM", 0, -gap)
    else
        label:SetPoint("BOTTOM", anchor, "TOP", 0, gap)
    end
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
    return entry.group and not entry.ally and "2" or entry.kind ~= "spell" and not entry.notice and "5" or ""
end

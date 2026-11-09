local _, NS = ...
local S, Header = NS.Suite, NS.CharacterHeader
S.CharacterHeader = Header

local Render = {}
Render.__index = Render

local MARGIN, FIELD_GAP = 14, 10
local max, min, floor = math.max, math.min, math.floor
local LEVEL_FORMAT = NS.Text("Level %d")
local DEFAULT_COLORS = {
    text = { .941, .922, .886 },
    muted = { .682, .714, .733 },
    accentBright = { .922, .784, .553 },
    active = { .227, .200, .157 },
}

local function Skin()
    return NS.Skin.Acquire("characterPanel")
end

function Header.ThemeColor(token, skin)
    if skin and skin:IsEnabled() then
        local r, g, b = skin:GetColor(token)
        if r then return r, g, b end
    end
    return unpack(DEFAULT_COLORS[token])
end

function Header.PickerColor(token)
    return Header.ThemeColor(token, Skin())
end

local function Place(region, x, y, width, height)
    if region.x ~= x or region.y ~= y then
        region.x, region.y = x, y
        region:ClearAllPoints()
        region:SetPoint("TOPLEFT", x, -y)
    end
    if region.width ~= width or region.height ~= height then
        region.width, region.height = width, height
        region:SetSize(width, height)
    end
end

local function ClampOffset(renderer, x, y, width, height, dx, dy)
    local right = max(0, renderer.width - renderer.rightReserve - width)
    return max(-x, min(right - x, dx)), max(y + height - Header.Height, min(y, dy))
end

local function PlaceField(renderer, button, x, y, width, height)
    button.baseX, button.baseY = x, y
    local dx, dy = ClampOffset(renderer, x, y, width, height, button.offsetX, button.offsetY)
    Place(button, x + dx, y - dy, width, height)
end

function Header.DragOffsets(renderer, id, x, y)
    local button = renderer.buttons[id]
    return ClampOffset(renderer, button.baseX, button.baseY, button.width, button.height, x, y)
end

local function Show(region, visible)
    if region.visible == visible then return end
    region.visible = visible
    region:SetShown(visible)
end

-- A preview-only hidden layer keeps its space so moving a neighbor still
-- uses the live anchor. Explicitly showing an optional sample adds it.
local function Present(button, hasValue)
    local participates = hasValue and (button.enabled or button.previewLayer == true)
    Show(button, participates and button.previewLayer ~= false)
    return participates
end

local function Color(text, r, g, b)
    if text.red ~= r or text.green ~= g or text.blue ~= b then
        text.red, text.green, text.blue = r, g, b
        text:SetTextColor(r, g, b)
    end
end

local function Font(text, path, size)
    if text.path == path and text.fontSize == size and text.fontRevision == S.FontRevision then return end
    text.path, text.fontSize, text.fontRevision = path, size, S.FontRevision
    S.SetFont(text, path, size)
    text.measured = nil
end

local function Text(text, value)
    if text.value == value then return end
    text.value, text.measured = value, nil
    text:SetText(value)
end

local function Measure(text)
    if not text.measured then text.measured = math.ceil(text:GetUnboundedStringWidth()) end
    return text.measured
end

local function NewText(button, align)
    local text = button:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    text:SetJustifyH(align or "LEFT")
    text:SetWordWrap(false)
    return text
end

local function NewField(renderer, field, click)
    local button = CreateFrame(click and "Button" or "Frame", nil, renderer.frame)
    renderer.buttons[field.id] = button
    if click then
        button:SetScript("OnClick", function() click(field.id, button) end)
        local hover = button:CreateTexture(nil, "HIGHLIGHT")
        hover:SetAllPoints()
        hover:SetColorTexture(1, 1, 1, .12)
    end
    if field.portrait then
        button.background = button:CreateTexture(nil, "BACKGROUND")
        button.background:SetAllPoints()
        button.image = button:CreateTexture(nil, "ARTWORK")
        button.image:SetPoint("TOPLEFT", 3, -3)
        button.image:SetPoint("BOTTOMRIGHT", -3, 3)
    else
        button.text = NewText(button)
        button.text:SetAllPoints()
    end
end

function Header.Create(parent, callbacks)
    local renderer = setmetatable({ frame = CreateFrame("Frame", nil, parent), buttons = {} }, Render)
    for i = 1, #Header.Fields do
        NewField(renderer, Header.Fields[i], callbacks and callbacks.field)
    end
    local item = renderer.buttons.itemLevel
    item.text:ClearAllPoints()
    item.text:SetPoint("LEFT")
    item.label = NewText(item, "RIGHT")
    item.label:SetPoint("RIGHT")
    return renderer
end

local function Style(renderer, field, config, skin, globalFont)
    local button, prefix = renderer.buttons[field.id], field.prefix
    button.size = config[prefix .. "Size"] or field.size
    button.offsetX, button.offsetY = config[prefix .. "X"] or 0, config[prefix .. "Y"] or 0
    button.previewLayer = renderer.previewLayers and renderer.previewLayers[field.id]
    local visible = config[prefix .. "Visible"]
    if visible == nil then visible = field.visible end
    button.enabled = visible == true
    if field.portrait then
        button.background:SetColorTexture(Header.ThemeColor("active", skin))
        return
    end

    local path = NS.ResolveFont(config[prefix .. "Font"]) or globalFont
    Font(button.text, path, button.size)
    local hex = tonumber(config[prefix .. "Color"] or "", 16)
    if hex then
        Color(button.text, math.floor(hex / 65536) / 255, math.floor(hex / 256) % 256 / 255, hex % 256 / 255)
    else
        Color(button.text, Header.ThemeColor(field.tone or "muted", skin))
    end
    if button.label then
        Font(button.label, path, 11)
        Color(button.label, Header.ThemeColor("muted", skin))
        Text(button.label, NS.Text("Item Level"))
    end
end

function Render:Settings(config, skin, width, rightReserve, previewLayers)
    if self.width ~= width then self.frame:SetSize(width, Header.Height) end
    self.width, self.rightReserve = width, rightReserve or 0
    self.previewLayers = previewLayers
    self.fields = Header.Order(config, "field")
    local fontPath = S.GlobalFontPath()
    for i = 1, #self.fields do Style(self, self.fields[i], config, skin, fontPath) end
end

local function DrawPortrait(renderer, button, unit, identity)
    if not Present(button, unit ~= nil) then return MARGIN end
    if button.unit ~= unit or button.identity ~= identity then
        button.unit, button.identity = unit, identity
        SetPortraitTexture(button.image, unit)
    end
    PlaceField(renderer, button, MARGIN, floor((Header.Height - button.size) / 2), button.size, button.size)
    return MARGIN + button.size + 11
end

local function DrawItemLevel(renderer, button, value, right, compact)
    if not Present(button, not compact and value ~= nil) then return right end
    Text(button.text, value)
    local textWidth = Measure(button.text)
    local labelWidth = Measure(button.label)
    local width = textWidth + labelWidth + 8
    if width ~= button.textWidth then
        button.textWidth = width
        button.text:SetWidth(textWidth)
        button.label:SetWidth(labelWidth)
    end
    local height = max(17, button.size + 5)
    PlaceField(renderer, button, right - width, floor((Header.Height - height) / 2), width, height)
    return right - width - 16
end

local function DrawMetadata(renderer, data, left, room, y, compact)
    local natural, count = 0, 0
    for i = 1, #renderer.fields do
        local field = renderer.fields[i]
        if field.lane == "meta" then
            local button, value = renderer.buttons[field.id], data[field.id]
            button.participates = Present(button, value ~= nil and (not compact or field.visible == true))
            if button.participates then
                if button.raw ~= value then
                    button.raw = value
                    Text(button.text, field.id == "level" and type(value) == "number" and LEVEL_FORMAT:format(value) or value)
                end
                natural, count = natural + Measure(button.text), count + 1
            end
        end
    end
    local ratio = min(1, max(0, room - FIELD_GAP * (count - 1)) / max(1, natural))
    for i = 1, #renderer.fields do
        local field = renderer.fields[i]
        if field.lane == "meta" then
            local button = renderer.buttons[field.id]
            if button.participates then
                local width = floor(Measure(button.text) * ratio)
                PlaceField(renderer, button, left, y, width, 21)
                left = left + width + FIELD_GAP
            end
        end
    end
end

function Render:Paint(data, compact)
    local buttons = self.buttons
    local left = DrawPortrait(self, buttons.portrait, data.portrait, data.identity)
    local right = DrawItemLevel(self, buttons.itemLevel, data.itemLevel, self.width - self.rightReserve - MARGIN, compact)
    local room = max(1, right - left)
    local name = buttons.name
    local named = Present(name, data.name ~= nil)
    if named then
        Text(name.text, data.name)
        PlaceField(self, name, left, 4, min(room, max(8, Measure(name.text))), 32)
    end
    DrawMetadata(self, data, left, room, named and 34 or 20, compact)
end

function Render:Render(config, data, skin, width, rightReserve, previewLayers)
    self:Settings(config, skin or Skin(), width, rightReserve, previewLayers)
    self:Paint(data)
end

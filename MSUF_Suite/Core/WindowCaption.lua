local _, NS = ...

-- Windows caption glyphs: minimize, maximize, restore and close, drawn as
-- solid bars on whole screen pixels. Nothing is rotated and no edge falls on
-- half a pixel, so every line stays one crisp pixel at any UI scale. The Skin
-- draws its caption cells over Blizzard's windows with it, and Suite windows
-- (character panel, bags) build their own cells from Caption.Dress.
-- Published on the core (MSUFSuite.WindowCaption: the Skin's SuiteCore()) and
-- on its Suite table (MSUFSuite.Suite.WindowCaption: Suite modules' NS.Suite).
local Caption = {}
NS.WindowCaption, NS.Suite.WindowCaption = Caption, Caption

local floor, max, min = math.floor, math.max, math.min
local DANGER = { .769, .169, .11, 1 }
local WHITE = { 1, 1, 1, 1 }

-- UI units per screen pixel at scale 1 (the client's PixelUtil).
function Caption.PixelFactor() return PixelUtil.GetPixelToUIUnitFactor() end

-- One screen pixel in the button's own units (one unit while either is unknown).
local function Pixel(button)
    local factor, scale = Caption.PixelFactor(), button:GetEffectiveScale()
    if type(factor) ~= "number" or type(scale) ~= "number" or factor <= 0 or scale <= 0 then return 1 end
    return factor / scale
end

-- An outline: top, right, bottom, left.
local function Box(rects, x, y, width, height, t)
    rects[#rects + 1] = { x, y, width, t }
    rects[#rects + 1] = { x + width - t, y + t, t, height - 2 * t }
    rects[#rects + 1] = { x, y + height - t, width, t }
    rects[#rects + 1] = { x, y + t, t, height - 2 * t }
end

-- Rectangles in pixels from the glyph's top left: x, y, width, height.
local function Shape(kind, n, t)
    local rects = {}
    if kind == "minimize" then
        rects[1] = { 0, floor(n / 2), n, t }
    elseif kind == "maximize" then
        Box(rects, 0, 0, n, n, t)
    elseif kind == "restore" then
        -- Windows' restore: a front square and the corner of one behind it.
        local offset = max(2, 2 * t)
        local size = n - offset
        Box(rects, 0, offset, size, size, t)
        rects[5] = { offset, 0, size, t }
        rects[6] = { n - t, 0, t, size }
        rects[7] = { offset, t, t, offset - t }
        rects[8] = { size, size - t, n - size, t }
    else
        for step = 0, n - t do
            rects[#rects + 1] = { step, step, t, t }
            rects[#rects + 1] = { n - t - step, step, t, t }
        end
    end
    return rects
end

-- Lays the glyph for kind out on button, reusing the textures in bars. Every
-- edge lands on a whole screen pixel: the glyph is offset by the button's own
-- distance to the pixel grid, and the engine's rounding stays off, because a
-- one-pixel bar it rounds the wrong way vanishes (a square loses a side).
function Caption.Layout(button, kind, bars)
    local pixel = Pixel(button)
    local width = floor((button:GetWidth() or 0) / pixel + .5)
    local height = floor((button:GetHeight() or 0) / pixel + .5)
    local n = max(5, floor(min(width, height) * .4 + .5))
    local t = max(1, floor(n / 12 + .5))
    local x0, y0, dx, dy = floor((width - n) / 2), floor((height - n) / 2), 0, 0
    local left, top = button:GetLeft(), button:GetTop()
    if left and top then
        dx = (floor(left / pixel + .5) - left / pixel) * pixel
        dy = (top / pixel - floor(top / pixel + .5)) * pixel
    end
    local rects = Shape(kind, n, t)
    for index, rect in ipairs(rects) do
        local bar = bars[index]
        if not bar then
            bar = button:CreateTexture(nil, "OVERLAY")
            bar:SetSnapToPixelGrid(false)
            bar:SetTexelSnappingBias(0)
            bars[index] = bar
        end
        bar:ClearAllPoints()
        bar:SetPoint("TOPLEFT", button, "TOPLEFT", dx + (x0 + rect[1]) * pixel, -(dy + (y0 + rect[2]) * pixel))
        bar:SetSize(rect[3] * pixel, rect[4] * pixel)
        bar:Show()
    end
    for index = #rects + 1, #bars do bars[index]:Hide() end
    return #rects
end

------------------------------------------------------------------ cells
-- A Suite window's caption cell: no box at rest, a soft fill under the
-- pointer, a red close cell with a white cross. colors(role) answers
-- "text" with the window's own text colour.

local function Paint(cell)
    local art = cell.caption
    local active = art.hover or art.down
    local close = art.kind == "close"
    local r, g, b, a = art.colors("text")
    if close and active then r, g, b, a = unpack(WHITE) end
    for _, bar in ipairs(art.bars) do bar:SetColorTexture(r, g, b, a or 1) end
    if close then
        art.fill:SetColorTexture(DANGER[1], DANGER[2], DANGER[3], active and (art.down and 1 or .9) or 0)
    else
        art.fill:SetColorTexture(1, 1, 1, active and (art.down and .17 or .1) or 0)
    end
    if art.base then art.base:SetColorTexture(art.colors("base")) end
end
Caption.Paint = Paint

function Caption.SetHover(cell, hover)
    cell.caption.hover = hover or nil
    if not hover then cell.caption.down = nil end
    Paint(cell)
end

local function Enter(cell) Caption.SetHover(cell, true) end
local function Leave(cell) Caption.SetHover(cell, false) end
local function Down(cell) cell.caption.down = true Paint(cell) end
local function Up(cell) cell.caption.down = nil Paint(cell) end

function Caption.SetKind(cell, kind)
    local art = cell.caption
    art.kind = kind
    Caption.Layout(cell, kind, art.bars)
    Paint(cell)
end

-- opaque: an unhovered fill in colors("base") that hides what lies beneath.
function Caption.Dress(cell, kind, colors, opaque)
    local art = { bars = {}, colors = colors }
    cell.caption = art
    if opaque then art.base = cell:CreateTexture(nil, "BACKGROUND", nil, -1) art.base:SetAllPoints(cell) end
    art.fill = cell:CreateTexture(nil, "BACKGROUND")
    art.fill:SetAllPoints(cell)
    cell:SetScript("OnEnter", Enter)
    cell:SetScript("OnLeave", Leave)
    cell:SetScript("OnMouseDown", Down)
    cell:SetScript("OnMouseUp", Up)
    cell:SetScript("OnHide", Leave)
    cell:SetScript("OnSizeChanged", function() Caption.SetKind(cell, art.kind) end)
    Caption.SetKind(cell, kind)
    return cell
end

return Caption

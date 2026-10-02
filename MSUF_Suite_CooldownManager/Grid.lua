local _, P = ...
local NS, S = P.NS, P.Suite
local C = P.CDM
-- Grid math of the bars: cell sizes and spacing in whole physical pixels,
-- the offsets of every place (lines of perRow in growth order, Center
-- alignment from the middle out, later rows with their own size), the
-- footprint and the growth-edge point. Pure: every function takes the UI
-- units per pixel (Layout.PixelScale), reads only the view and writes only
-- the caller's offsets table.
local Grid = {}
C.Grid = Grid
local floor, ceil, max, min = math.floor, math.ceil, math.max, math.min
local type = type
local KIND = C.Const.KIND
local COOLDOWN, AURA_BAR = KIND.COOLDOWN, KIND.AURA_BAR

local function Round(value) return floor(value + .5) end

-- Growth direction: 1 Down (vertical: Right), 2 Up (vertical: Left). Aura
-- bars without a grow rule (built-in "Buff bars") stack upward.
local function Grow(view)
    local grow = view.grow
    if grow == nil and view.kind == AURA_BAR then return 2 end
    return grow == 2 and 2 or 1
end

-- Cell size and spacing in whole pixels, stride, flow and alignment.
local function Cells(view, unit)
    if view.kind == AURA_BAR or view.kind == COOLDOWN and view.cooldownDuration then
        return max(1, Round((view.barWidth or 200) / unit)), max(1, Round((view.barHeight or 18) / unit)),
            Round((view.spacing or 2) / unit), 1, false, Grow(view), 1
    end
    local size = view.size or 36
    local per = floor(view.perRow or 1)
    if per < 1 then per = 1 end
    local align = view.align
    if align ~= 2 and align ~= 3 then align = 1 end
    return max(1, Round(size / unit)), max(1, Round(size * (view.height or 100) / 100 / unit)), Round((view.spacing or 0) / unit),
        per, view.vertical == true, Grow(view), align
end

-- Lays out group 1 (n1 cells) and then group 2 (n2 cells) starting on a new
-- line, lines of `per`, in growth order. Every line is aligned on its own.
-- Integer pixel math; the centering origin is floored once per line.
-- Writes out[2i-1], out[2i] and returns the content size in UI units. An
-- empty layout keeps the footprint of one cell.
local function Fill(w, h, sp, per, vertical, grow, align, n1, n2, out, unit)
    local lines1 = ceil(n1 / per)
    local lines = lines1 + ceil(n2 / per)
    if lines == 0 then return w * unit, h * unit end
    local along, across = w, h
    if vertical then along, across = h, w end
    local full = n1 > n2 and n1 or n2
    if full > per then full = per end
    local extent = full * along + (full - 1) * sp
    local depth = lines * across + (lines - 1) * sp
    local index = 0
    for group = 1, 2 do
        local n, base = n1, 0
        if group == 2 then n, base = n2, lines1 end
        for i = 0, n - 1 do
            local line = floor(i / per)
            local count = n - line * per
            if count > per then count = per end
            local free = extent - (count * along + (count - 1) * sp)
            local a = (align == 2 and 0 or align == 3 and free or floor(free / 2)) + (i - line * per) * (along + sp)
            local g = base + line
            if grow == 2 then g = lines - 1 - g end
            local b = g * (across + sp)
            index = index + 1
            if vertical then
                out[2 * index - 1], out[2 * index] = b * unit, -a * unit
            else
                out[2 * index - 1], out[2 * index] = a * unit, -b * unit
            end
        end
    end
    if vertical then return depth * unit, extent * unit end
    return extent * unit, depth * unit
end

-- Cooldown icons with Center keep the first visible icon on the bar's
-- midpoint. Later icons occupy right, left, right, left in plan order.
-- The symmetric footprint keeps that midpoint stable when the count changes.
-- Aura buttons use Blizzard's own compact flow instead (Fill above).
local function CenterOut(w, h, sp, per, vertical, grow, n, out, unit)
    if n == 0 then return w * unit, h * unit end
    local along, across = w, h
    if vertical then along, across = h, w end
    local count = n > per and per or n
    local radius = floor(count / 2)
    local stride = along + sp
    local extent = (2 * radius + 1) * along + 2 * radius * sp
    local lines = ceil(n / per)
    local depth = lines * across + (lines - 1) * sp
    local middle = radius * stride
    for i = 0, n - 1 do
        local line = floor(i / per)
        local ordinal = i - line * per
        local side = ordinal == 0 and 0 or (ordinal % 2 == 1 and (ordinal + 1) / 2 or -ordinal / 2)
        local a = middle + side * stride
        local g = grow == 2 and lines - 1 - line or line
        local b = g * (across + sp)
        if vertical then
            out[2 * i + 1], out[2 * i + 2] = b * unit, -a * unit
        else
            out[2 * i + 1], out[2 * i + 2] = a * unit, -b * unit
        end
    end
    if vertical then return depth * unit, extent * unit end
    return extent * unit, depth * unit
end

-- Cooldown bars whose later rows take their own icon count or size.
local function MixedRows(view)
    return view.kind == COOLDOWN and not view.cooldownDuration
        and ((view.laterPerRow or 0) > 0 or (view.laterSize or 0) > 0)
end
-- Size of the icon at place index (later rows may have their own).
local function Footprint(view, index, unit)
    local w, h, _, per = Cells(view, unit)
    if MixedRows(view) and index > per and (view.laterSize or 0) > 0 then
        w = max(1, Round(view.laterSize / unit))
        h = max(1, Round(view.laterSize * (view.height or 100) / 100 / unit))
    end
    return w * unit, h * unit
end
local function RowSpan(count, size, align, spacing)
    if count == 0 then return 0 end
    if align == 1 then count = 2 * floor(count / 2) + 1 end
    return count * size + (count - 1) * spacing
end
local function FillMixed(view, n, out, unit)
    local w, h, sp, per, vertical, grow, align = Cells(view, unit)
    local w2, h2 = Footprint(view, per + 1, unit)
    w2, h2 = Round(w2 / unit), Round(h2 / unit)
    local per2 = (view.laterPerRow or 0) > 0 and view.laterPerRow or per
    local first = min(n, per)
    local remaining = max(0, n - first)
    local rows = ceil(remaining / per2)
    local a, b, a2, b2 = w, h, w2, h2
    if vertical then a, b, a2, b2 = h, w, h2, w2 end
    local extent = max(RowSpan(first, a, align, sp), RowSpan(min(remaining, per2), a2, align, sp))
    local depth = b + rows * (b2 + sp)
    local index = 0
    for row = 0, rows do
        local count = row == 0 and first or min(per2, remaining - (row - 1) * per2)
        local along, across = row == 0 and a or a2, row == 0 and b or b2
        local cross = row == 0 and 0 or b + sp + (row - 1) * (b2 + sp)
        if grow == 2 then cross = depth - cross - across end
        local origin = align == 2 and 0 or align == 3 and extent - RowSpan(count, along, align, sp) or floor((extent - along) / 2)
        for ordinal = 0, count - 1 do
            local offset = ordinal
            if align == 1 then offset = ordinal == 0 and 0 or ordinal % 2 == 1 and (ordinal + 1) / 2 or -ordinal / 2 end
            local alongAt = origin + offset * (along + sp)
            index = index + 1
            out[2 * index - 1] = (vertical and cross or alongAt) * unit
            out[2 * index] = -(vertical and alongAt or cross) * unit
        end
    end
    if n == 0 then return w * unit, h * unit end
    if vertical then return depth * unit, extent * unit end
    return extent * unit, depth * unit
end

-- Offsets of the first `count` cells (capped by maxIcons) relative to the
-- bar's TOPLEFT. Returns width, height and the laid-out count.
local function Offsets(view, count, out, unit)
    local w, h, sp, per, vertical, grow, align = Cells(view, unit)
    local n = type(count) == "number" and count or 0
    local cap = view.maxIcons
    if type(cap) == "number" and cap > 0 and n > cap then n = cap end
    if n < 0 then n = 0 end
    local width, height
    if MixedRows(view) then
        width, height = FillMixed(view, n, out, unit)
    elseif view.kind == COOLDOWN and align == 1 then
        width, height = CenterOut(w, h, sp, per, vertical, grow, n, out, unit)
    else
        width, height = Fill(w, h, sp, per, vertical, grow, align, n, 0, out, unit)
    end
    return width, height, n
end

-- Cell width, height and spacing in UI units (pixel exact), stride, vertical,
-- grow and align: what the aura layer needs for its flow layout.
local function Metrics(view, unit)
    local w, h, sp, per, vertical, grow, align = Cells(view, unit)
    return w * unit, h * unit, sp * unit, per, vertical, grow, align
end

-- Growth-edge point of a bar; free bars anchor it to UIParent's center.
local function Point(view)
    if view.kind ~= AURA_BAR and view.vertical then return Grow(view) == 2 and "RIGHT" or "LEFT" end
    return Grow(view) == 2 and "BOTTOM" or "TOP"
end

Grid.Cells, Grid.Fill, Grid.MixedRows, Grid.Footprint = Cells, Fill, MixedRows, Footprint
Grid.Offsets, Grid.Metrics, Grid.Point = Offsets, Metrics, Point

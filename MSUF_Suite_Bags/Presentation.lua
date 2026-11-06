local _, P = ...
local NS = P.NS
local Presentation = { CELL = 40, RAIL = 112, PAD = 16 }
P.BagPresentation = Presentation
local max, min, floor, ceil = math.max, math.min, math.floor, math.ceil

function Presentation.IsPanel(c)
    return c.windowPresentation == NS.BagsPresentation.PANEL and c.inventoryView ~= NS.BagsView.BLIZZARD_GRID
end

-- A default reagent window remains a separate native root. Its width is
-- reserved before choosing columns; custom reagent placement stays independent.
function Presentation.CompanionWidth(c)
    if not Presentation.IsPanel(c) or c.reagentWindowMoved or not ContainerFrame6:IsShown()
        or not ContainerFrameCombinedBags:IsShown() then return 0 end
    return ContainerFrame6:GetWidth()
end

local function Top(panel, drawer)
    return panel and (drawer and 144 or 88) or (drawer and 176 or 122)
end

function Presentation.MoneyTop(frame)
    local top, bottom = frame.MoneyFrame:GetTop(), frame:GetBottom()
    if P.Suite.Finite(top) and P.Suite.Finite(bottom) and top > bottom then return top - bottom end
    return 24
end

local function MinimumRows(c, top, bottom)
    if not Presentation.IsPanel(c) then return 2 end
    local height = c.inventoryView == NS.BagsView.CATEGORIES and 390 or 290
    return max(2, ceil((height - top - bottom) / Presentation.CELL))
end

function Presentation.ResolveScale(c, viewportWidth, viewportHeight, money, drawer, companion, companionHeight)
    if not Presentation.IsPanel(c) then return c.windowScale end
    local top, bottom = Top(true, drawer), money + 50
    local height = MinimumRows(c, top, bottom) * Presentation.CELL + top + bottom
    local width = Presentation.RAIL + 6 * Presentation.CELL + 32
    if companion and companion > 0 then
        width = width + companion + 8
        height = max(height, companionHeight)
    end
    return min(c.windowScale, viewportWidth / (width + 24), viewportHeight / (height + 24))
end

function Presentation.Scale(c, companion)
    local drawer = P.EquippedBags.frame
    return Presentation.ResolveScale(c, UIParent:GetWidth(), UIParent:GetHeight(),
        Presentation.MoneyTop(ContainerFrameCombinedBags), drawer and drawer:IsShown(),
        companion, companion > 0 and ContainerFrame6:GetHeight() or 0)
end

-- Pure rectangles in frame units, shared by the renderer and menu sample.
-- The native root includes the whole rail, so its clamp and mover bounds do too.
function Presentation.Measure(out, c, width, available, money, lines, drawer)
    local panel = Presentation.IsPanel(c)
    local columns = c.inventoryColumns
    local rail = panel and Presentation.RAIL or 0
    local columnCapacity = panel and max(6, floor((width - 24 - rail - 32) / 40)) or 20
    if panel then columns = min(columns, columnCapacity) end
    out.columnCapacity = columnCapacity
    local sidebar = panel and rail + 16 or c.inventoryView == NS.BagsView.CATEGORIES and 178 or 12
    local top = Top(panel, drawer)
    local bottom = money + 50
    local height = max(top + bottom + 80, available - 12)
    local rows = max(2, floor((height - top - bottom) / 40))
    out.capacity = rows
    local minimum = min(rows, MinimumRows(c, top, bottom))
    local full = panel and c.panelFullHeight == true
    if not full then
        rows = max(minimum, min(rows, c.inventoryRows))
        if c.autoSizeWindow and lines then rows = max(minimum, min(rows, lines)) end
        height = rows * Presentation.CELL + top + bottom
    end
    out.minimum, out.fullHeight = minimum, full
    out.panel, out.rail, out.top, out.bottom = panel, rail, top, bottom
    out.columns, out.sidebar, out.rows = columns, sidebar, rows
    out.width = panel and rail + columns * 40 + 32 or max(620, sidebar + columns * 40 + 12)
    out.height = height
    out.compact = not panel and c.compactGroups
    return out
end

-- Corner sizing uses complete cells and the same rectangles as live/preview.
function Presentation.Resize(out, c, g, width, height)
    local columns = max(8, min(20, floor((width - (g.panel and g.rail + 32 or g.sidebar + 12)) / 40 + .5)))
    local rows = max(4, min(16, floor((height - g.top - g.bottom) / 40 + .5)))
    rows = max(rows, g.minimum)
    -- Persist the setting's limits; display only what the viewport can hold.
    local visibleColumns = min(columns, g.columnCapacity)
    local visibleRows = min(rows, g.capacity)
    out.columns, out.rows = columns, rows
    out.visibleColumns, out.visibleRows = visibleColumns, visibleRows
    out.width = g.panel and g.rail + visibleColumns * 40 + 32 or max(620, g.sidebar + visibleColumns * 40 + 12)
    out.height = visibleRows * 40 + g.top + g.bottom
    return out
end

-- Combat exposes every physical slot. Choose a bounded grid and scale in
-- one cold pass; configured wide rows must not put small bags off screen.
function Presentation.Combat(out, c, total, width, height, money, extra, wantedScale, companion, companionHeight)
    local bestScale, bestDistance = 0, math.huge
    local target = min(max(1, total), c.inventoryColumns)
    for columns = 1, min(max(1, total), max(20, c.inventoryColumns)) do
        local rows = max(1, ceil(total / columns))
        local w = max(c.showSessionGold and 420 or 300, columns * Presentation.CELL + 24)
        local h = rows * Presentation.CELL + 66 + money + 6 + extra
        local reserve = companion > 0 and companion + 8 or 0
        local scale = min(wantedScale, width / (w + reserve + 24), height / (max(h, companionHeight) + 24))
        local distance = math.abs(columns - target)
        if scale > bestScale or scale == bestScale and distance < bestDistance then
            bestScale, bestDistance = scale, distance
            out.columns, out.width, out.height = columns, w, h
        end
    end
    out.scale = bestScale
    return out
end

function Presentation.FitRows(out, c, lines)
    if not out.fullHeight and c.autoSizeWindow then
        out.rows = max(out.minimum, min(out.rows, lines))
        out.height = out.rows * 40 + out.top + out.bottom
    end
end

P.Suite.BagsPreviewGeometry = Presentation.Measure
P.Suite.BagsFitPreviewRows = Presentation.FitRows
P.Suite.BagsPreviewScale = Presentation.ResolveScale
P.Suite.BagsPreviewIsPanel = Presentation.IsPanel

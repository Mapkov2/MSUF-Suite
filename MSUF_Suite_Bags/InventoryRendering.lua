local _, P = ...
local S, M = P.Suite, P.BagsModule
local Grid, Model, FreeSlots = P.GridView, P.InventoryModel, P.FreeSlots
local VIEW, POOR = P.NS.BagsView, Enum.ItemQuality.Poor
local QUEST_CLASS, QUEST_BIND = Enum.ItemClass.Questitem, Enum.ItemBind.Quest
local floor, ceil, max, min = math.floor, math.ceil, math.max, math.min
local CELL, TOP, FOOTER, COMBAT_TOP = 40, 122, 50, 66
local InventoryView
local Presentation = P.BagPresentation
local Rendering = {}
P.InventoryRendering = Rendering

local function PlaceSlot(button, x, y, row)
    local slot = InventoryView.slotState[button]
    if not slot then
        slot = {}
        InventoryView.slotState[button] = slot
    end
    if InventoryView.positionsDirty or slot.x ~= x or slot.y ~= y then
        button:ClearAllPoints()
        button:SetPoint("TOPLEFT", InventoryView.frame, "TOPLEFT", x, y)
        slot.x, slot.y = x, y
    end
    slot.row, InventoryView.visibleButtons[button] = row, true
    if not button:IsShown() then button:Show() end
end

-- Blizzard's SetItemButtonCount hides counts of one and shows "*" above its
-- maximum; a merged total must be shown even where the shown stack holds one.
-- path: the bag font, read once per render (Grid.FontPath).
local function SetCount(button, count, path)
    local text = button.Count
    if not text then return end
    local saved = InventoryView.nativeCountFonts[text]
    if not saved then
        saved = { text:GetFont() }
        InventoryView.nativeCountFonts[text] = saved
    end
    local size = InventoryView.countSize
    if saved.path ~= path or saved.size ~= size then
        S.SetFont(text, path, size, "OUTLINE")
        saved.path, saved.size = path, size
    end
    if count > 1 then
        text:SetText(tostring(GetFormattedItemQuantity(count, button.maxDisplayCount)))
        text:Show()
    else
        text:Hide()
    end
end

local function InactiveQuest(item)
    return item.quest == false and (item.classID == QUEST_CLASS or item.bindType == QUEST_BIND)
end
Rendering.InactiveQuest = InactiveQuest

local function PaintSlot(item, x, y, row, count, font)
    local button = item.button
    PlaceSlot(button, x, y, row)
    SetCount(button, count, font)
    local config = M.config
    local gray = item.locked or config.desaturateJunk and item.quality == POOR
        or config.desaturateInactiveQuestItems and InactiveQuest(item)
    SetItemButtonDesaturated(button, gray or false)
    P.InventoryDetails.Paint(button, item, font)
end

local function PaintCell(cell, top, sidebar, columns, font)
    local row, group = cell.row, cell.group
    local y = -TOP - (cell.line - top) * CELL
    if row then
        PaintSlot(row.item, sidebar + cell.column * CELL, y, row, row.count, font)
    else
        InventoryView.labelCount = InventoryView.labelCount + 1
        local toggle = M.config.inventoryView == VIEW.CATEGORIES and P.InventoryControls.ToggleGroup or nil
        local label = Grid.PaintHeader(InventoryView.labels, InventoryView.labelCount, InventoryView.chrome, InventoryView.frame,
            sidebar + cell.column * CELL, y - 10, (cell.width or columns) * CELL - 5, group, toggle)
        local plate = P.BagAppearance.Section(label, InventoryView.frame)
        P.BagAppearance.PaintSection(plate, InventoryView.frame, sidebar + cell.column * CELL, y,
            (cell.width or columns) * CELL - 4, math.min(cell.height, InventoryView.visibleRows - cell.line + top) * CELL - 5, nil, label)
    end
end

------------------------------------------------------------------ geometry
-- Space from the window's bottom edge to the top of the screen, in the
-- window's own units. The window grows upward from Blizzard's anchor
-- (CONTAINER_OFFSET_Y above the screen bottom) or from its custom position.
local function Available()
    local frame = InventoryView.frame
    local bottom, top = frame:GetBottom(), UIParent:GetTop()
    local scale, parentScale = frame:GetEffectiveScale(), UIParent:GetEffectiveScale()
    if S.Finite(bottom) and S.Finite(top) and S.Finite(scale) and S.Finite(parentScale) and scale > 0 then
        return top * parentScale / scale - bottom, UIParent:GetWidth() * parentScale / scale, top * parentScale / scale
    end
    local height = UIParent:GetHeight() / frame:GetScale()
    return height - CONTAINER_OFFSET_Y / frame:GetScale(), UIParent:GetWidth() / frame:GetScale(), height
end

-- Height of Blizzard's money row above the window bottom, tracked currency
-- rows included.
local function MoneyTop()
    return Presentation.MoneyTop(InventoryView.frame)
end

-- Blizzard scaled its bags for its own window size: lay them out again for
-- the Suite size (Bags.lua reapplies the Suite scale and position after it).
local function SetWindowSize(width, height)
    local frame = InventoryView.frame
    if frame:GetWidth() == width and frame:GetHeight() == height then return end
    frame:SetSize(width, height)
    M:RefreshWindowLayout()
end

local function ClearVisible()
    for button in pairs(InventoryView.visibleButtons) do InventoryView.visibleButtons[button] = nil end
    Grid.HideHeaders(InventoryView.labels)
    InventoryView.labelCount = 0
end

local function HideUnplaced()
    for i = 1, #InventoryView.index.items do
        local button = InventoryView.index.items[i].button
        if not InventoryView.visibleButtons[button] and button:IsShown() then button:Hide() end
    end
    InventoryView.positionsDirty = false
end

local function PaintFree()
    local counts = InventoryView.freeSlots
    if M.config.showFreeSlots and counts.regular then
        FreeSlots.Paint(InventoryView.free, counts)
    else
        InventoryView.free:Hide()
    end
end

function Rendering.Suite(visualPass)
    InventoryView = P.InventoryView
    local c = P.BagResize.active and P.BagResize.config or M.config
    if M.combatScale then
        M.combatScale = nil
        M:RefreshWindowLayout()
    end
    local g, layout = InventoryView.geometry
    if not visualPass then
        local available, width, screenHeight = Available()
        if Presentation.IsPanel(c) then
            available = screenHeight - 12
            local companion = Presentation.CompanionWidth(c)
            if companion > 0 then width = width - companion - 8 end
        end
        Presentation.Measure(g, c, width, available, MoneyTop(), nil, P.EquippedBags.frame:IsShown())
        layout = Model.Layout(InventoryView.model, g.columns, g.compact)
        Presentation.FitRows(g, c, InventoryView.model.lineCount)
        if P.BagResize.active then g.width, g.height = P.BagResize.width, P.BagResize.height end
        P.BagWindowMotion.Target(g.width, g.height)
    end
    TOP = g.top
    local columns, visibleRows = P.BagWindowMotion.Viewport(g)
    local sidebar = g.sidebar
    local categories = c.inventoryView == VIEW.CATEGORIES
    if not layout or columns ~= g.columns then layout = Model.Layout(InventoryView.model, columns, g.compact) end
    InventoryView.visibleRows, InventoryView.maxScroll = visibleRows, max(0, InventoryView.model.lineCount - visibleRows)
    InventoryView.scroll = min(InventoryView.scroll, InventoryView.maxScroll)
    ClearVisible()
    local font = Grid.FontPath()
    InventoryView.countSize = M.config.itemCountSize + (M.readableValues and 2 or 0)
    for i = 1, #layout do
        local cell = layout[i]
        if cell.line >= InventoryView.scroll and cell.line < InventoryView.scroll + visibleRows then
            PaintCell(cell, InventoryView.scroll, sidebar, columns, font)
        end
    end
    HideUnplaced()
    InventoryView.layout = "suite"
    InventoryView.ShowChrome(true)
    InventoryView.sidebar:SetShown(categories)
    InventoryView.previous:SetEnabled(InventoryView.scroll > 0)
    InventoryView.next:SetEnabled(InventoryView.scroll < InventoryView.maxScroll)
    Grid.PositionText(InventoryView.position, InventoryView.scroll, visibleRows, InventoryView.model.lineCount)
    PaintFree()
    for view, button in pairs(InventoryView.tabs) do
        P.BagAppearance.Button(button, view == c.inventoryView)
    end
    P.InventoryControls.Layout(g)
    P.BagHover.Refresh()
end

-- Protected fallback: every slot in physical order without pages, groups, merged or hidden
-- stacks, and without the Suite controls; the currency and Gold history
-- line keeps a row below the slots. Laid out at PLAYER_REGEN_DISABLED, the
-- last moment before combat lockdown, so nothing is out of reach while the
-- layout cannot change.
function Rendering.Combat()
    P.BagHover.Clear()
    InventoryView = P.InventoryView
    local items = InventoryView.index.items
    local total = #items
    local line = P.BagFinance.HasLine() and P.BagFinance.LINE or 0
    InventoryView.combatLine = line > 0
    local companion = Presentation.CompanionWidth(M.config)
    local g = Presentation.Combat(InventoryView.combatGeometry, M.config, total,
        UIParent:GetWidth(), UIParent:GetHeight(), MoneyTop(), line, InventoryView.frame:GetScale(),
        companion, companion > 0 and ContainerFrame6:GetHeight() or 0)
    local columns = g.columns
    InventoryView.layout, M.combatScale = "combat", g.scale
    M:RefreshWindowLayout()
    ClearVisible()
    local font = Grid.FontPath()
    InventoryView.countSize = M.config.itemCountSize + (M.readableValues and 2 or 0)
    for i = 1, total do
        local item = items[i]
        PaintSlot(item, 12 + (i - 1) % columns * CELL, -COMBAT_TOP - floor((i - 1) / columns) * CELL, nil,
            item.count or 0, font)
    end
    HideUnplaced()
    InventoryView.layout = "combat"
    InventoryView.ShowChrome(false)
    P.BagFinance.Refresh()
    SetWindowSize(g.width, g.height)
end

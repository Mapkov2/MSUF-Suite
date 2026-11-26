local _, P = ...
local K, S, Tr = P.PreviewCanvas, P.S, P.Tr
local Interaction = P.PreviewInteraction
local VIEW, BANK_VIEW = P.Suite.BagsView, P.Suite.BagsBankView
local GOLD_PERIOD = P.Suite.BagsGoldPeriod
local EMPTY = {}
local BANK_WIDTH, BANK_HEIGHT = 738, 460
local BACKPACK_COLUMNS, BACKPACK_SLOTS = 10, 66
local BACKPACK_SLOT_SIZE, BACKPACK_SPACING = 37, 5
local BACKPACK_TOP, BACKPACK_BOTTOM = 72, 21
local BACKPACK_PITCH = BACKPACK_SLOT_SIZE + BACKPACK_SPACING
local BACKPACK_ROWS = math.ceil(BACKPACK_SLOTS / BACKPACK_COLUMNS)
local BACKPACK_WIDTH = BACKPACK_COLUMNS * BACKPACK_PITCH - BACKPACK_SPACING + 15
local BACKPACK_HEIGHT = BACKPACK_ROWS * BACKPACK_PITCH - BACKPACK_SPACING + BACKPACK_TOP + BACKPACK_BOTTOM

local function RefreshGuide(preview)
    if preview.hovered and not preview.hovered:IsVisible() then preview.hovered = nil end
    if preview.clicked and not preview.clicked:IsVisible() then preview.clicked = nil end
    local target = preview.hovered or preview.clicked
    local guide = preview.guide
    if target ~= preview.guideTarget then
        preview.guideTarget = target
        guide:ClearAllPoints()
        if target then guide:SetAllPoints(target) end
        guide:SetShown(target ~= nil)
    end
    if target then Interaction.Outline(guide, true, target == preview.clicked and 2 or 1) end
end

local function GuideTarget(preview, button)
    button:SetScript("OnEnter", function()
        preview.hovered = button
        RefreshGuide(preview)
    end)
    button:SetScript("OnLeave", function()
        if preview.hovered == button then preview.hovered = nil end
        RefreshGuide(preview)
    end)
    button:HookScript("OnClick", function()
        preview.clicked = button
        RefreshGuide(preview)
    end)
    return button
end

-- The runtime supplies representative items and its real category/packing
-- model. The menu never scans bags, banks or character inventories.
local function Texture(parent, layer, sublevel)
    return parent:CreateTexture(nil, layer or "BACKGROUND", nil, sublevel)
end
local function Chrome(window, width)
    local t = { shell = window, combined = true }
    t[1] = Texture(window, "BACKGROUND", -8)
    t[2] = Texture(window, "BACKGROUND", -7)
    t[3] = Texture(window, "BORDER", -7)
    t[4] = Texture(window, "ARTWORK", -7)
    t[5] = Texture(window, "BORDER", -6)
    for i = 6, 9 do t[i] = Texture(window, "ARTWORK", -6) end
    t[1]:SetPoint("TOPLEFT", -3, 3)
    t[1]:SetPoint("BOTTOMRIGHT", 3, -3)
    t[2]:SetAllPoints(window)
    t[3]:SetPoint("TOPLEFT")
    t[3]:SetPoint("TOPRIGHT")
    t[3]:SetHeight(62)
    t[4]:SetPoint("TOPLEFT", t[3], "BOTTOMLEFT")
    t[4]:SetPoint("TOPRIGHT", t[3], "BOTTOMRIGHT")
    t[4]:SetHeight(1)
    t[5]:SetPoint("BOTTOMLEFT")
    t[5]:SetPoint("BOTTOMRIGHT")
    t[5]:SetHeight(32)
    t[6]:SetPoint("TOPLEFT")
    t[6]:SetPoint("TOPRIGHT")
    t[6]:SetHeight(1)
    t[7]:SetPoint("BOTTOMLEFT")
    t[7]:SetPoint("BOTTOMRIGHT")
    t[7]:SetHeight(1)
    t[8]:SetPoint("TOPLEFT")
    t[8]:SetPoint("BOTTOMLEFT")
    t[8]:SetWidth(1)
    t[9]:SetPoint("TOPRIGHT")
    t[9]:SetPoint("BOTTOMRIGHT")
    t[9]:SetWidth(1)
    t.goldLabel = K.Text(window, "12,345 |cffffd700g|r", width - 144, -328, 132)
    t.goldLabel:SetJustifyH("RIGHT")
    return t
end

-- The bag window's Windows caption (MSUF_Suite_Bags/BagCaption.lua), drawn
-- only: minimize, maximize and close cells in the top right corner. Maximize
-- stands for the side panel's full screen height.
local CAPTION_TEXT, CAPTION_MUTED = { .94, .95, .98, 1 }, { .45, .48, .53, 1 }
local function Caption(content)
    local cells = {}
    for index, kind in ipairs({ "close", "maximize", "minimize" }) do
        local cell = CreateFrame("Frame", nil, content)
        cell:SetSize(30, 24)
        cell:SetPoint("TOPRIGHT", content, "TOPRIGHT", 1 - index * 30, -1)
        S.WindowCaption.Dress(cell, kind, function()
            local color = cell.previewMuted and CAPTION_MUTED or CAPTION_TEXT
            return color[1], color[2], color[3], color[4]
        end)
        cell:EnableMouse(false)
        cells[index] = cell
    end
    return cells
end

local function PaintCaption(preview, c, bank)
    local panel = not bank and S.BagsPreviewIsPanel(c)
    local maximize = preview.caption[2]
    maximize.previewMuted = not (panel or not bank and c.inventoryView == VIEW.BLIZZARD_GRID)
    S.WindowCaption.SetKind(maximize, panel and c.panelFullHeight and "restore" or "maximize")
    for _, cell in ipairs(preview.caption) do cell:SetShown(not bank) end
end

local function Slot(preview, ui, parent)
    local slot = K.Button(parent or preview.content, 0, 0, 36, 36, function() ui:Focus("suite_bags_itemLevels") end)
    GuideTarget(preview, slot)
    slot.border = Texture(slot)
    slot.border:SetAllPoints(slot)
    slot.icon = Texture(slot, "ARTWORK")
    slot.icon:SetPoint("TOPLEFT", 1, -1)
    slot.icon:SetPoint("BOTTOMRIGHT", -1, 1)
    slot.icon:SetTexCoord(.08, .92, .08, .92)
    slot.level = K.Text(slot, "", 2, -2, 32)
    slot.level:SetJustifyH("RIGHT")
    slot.count = K.Text(slot, "", 2, -22, 32)
    slot.count:SetJustifyH("RIGHT")
    slot.arrow = Texture(slot, "OVERLAY")
    slot.arrow:SetAtlas("bags-greenarrow", true)
    slot.arrow:SetPoint("TOPLEFT")
    return slot
end

local function BankLook(look, c)
    look.backgroundColor, look.backgroundOpacity = P.Suite.BagsBankColor(c), 100
    look.accentColor, look.font = c.accentColor, c.font
    return look
end

local function PaintItem(slot, item, c, bank, native)
    slot.icon:SetTexture(item.icon)
    local itemLevel = item.itemLevel
    slot.level:SetText(itemLevel and itemLevel > 0 and tostring(itemLevel) or "")
    slot.count:SetText(item.count > 1 and tostring(item.count) or "")
    slot.level:SetShown(bank and c.showBankItemLevel or not bank and c.showItemLevel)
    slot.arrow:SetShown(not native and c.showUpgradeMarker and item.upgrade == true)
    S.BagsStylePreviewLabel(slot.level, c)
    local r, g, b = C_Item.GetItemQualityColor(item.quality)
    slot.border:SetColorTexture(r, g, b, 1)
    if bank then
        if slot.slotEdges then
            for i = 1, #slot.slotEdges do slot.slotEdges[i]:Hide() end
        end
        slot.icon:ClearAllPoints()
        slot.icon:SetPoint("TOPLEFT", 1, -1)
        slot.icon:SetPoint("BOTTOMRIGHT", -1, 1)
    else
        S.BagsPaintPreviewSlot(slot, c, item)
    end
    slot.level:SetTextColor(c.qualityColor and r or 1, c.qualityColor and g or 1, c.qualityColor and b or 1)
    S.SetFont(slot.count, S.ResolveFont(c.font) or S.GlobalFontPath(), c.itemCountSize, "OUTLINE")
end

local function PaintEmpty(slot, c)
    S.BagsPaintPreviewSlot(slot, c, EMPTY)
    slot.level:Hide()
    slot.count:Hide()
    slot.arrow:Hide()
end

local function PaintBorderExamples(ui, preview, c, bank)
    local examples = preview.borderExamples
    if not examples then
        examples = CreateFrame("Frame", nil, ui.header)
        examples:SetSize(preview.width, 44)
        examples.item = Slot(preview, ui, examples)
        examples.empty = Slot(preview, ui, examples)
        examples.item:SetPoint("TOPLEFT", examples, "TOPLEFT", 0, 0)
        local half = math.floor(preview.width / 2)
        examples.empty:SetPoint("TOPLEFT", examples, "TOPLEFT", half, 0)
        for _, slot in ipairs({ examples.item, examples.empty }) do
            slot:SetScript("OnClick", function() ui:Focus("suite_bags_appearance") end)
        end
        K.Text(examples, "Equipment", 44, -10, half - 48)
        K.Text(examples, "Empty slots", half + 44, -10, half - 48)
        preview.borderExamples = examples
    end
    examples:SetShown(not bank)
    if bank then return end
    examples:ClearAllPoints()
    examples:SetPoint("TOPLEFT", preview.window, "BOTTOMLEFT", 0, -10)
    PaintItem(examples.item, preview.snapshot.items[1], c, false)
    PaintEmpty(examples.empty, c)
    preview.footer:ClearAllPoints()
    preview.footer:SetPoint("TOPLEFT", examples, "BOTTOMLEFT", -4, -4)
end

local function Header(preview, number, cell, x, y, width, c)
    local header = preview.groups[number]
    if not header then
        local plate = CreateFrame("Frame", nil, preview.content)
        plate:EnableMouse(false)
        plate.fill, plate.edge = Texture(plate), Texture(plate, "BORDER")
        plate.fill:SetAllPoints(plate)
        plate.edge:SetPoint("TOPLEFT")
        plate.edge:SetPoint("TOPRIGHT")
        plate.edge:SetHeight(1)
        header = { plate = plate, label = K.Text(preview.content, "", 0, 0, width) }
        preview.groups[number] = header
    end
    header.label:ClearAllPoints()
    header.label:SetPoint("TOPLEFT", preview.content, "TOPLEFT", x, y - 10)
    header.label:SetWidth(width)
    local group = cell.group
    local text = group.translate and Tr(group.label) or group.label
    if group.expansionName then text = string.format(Tr("%s - %s"), text, group.expansionName) end
    if S.BagsPreviewIsPanel(c) then text = string.format(Tr("%s (%d)"), text, #group.rows) end
    header.label:SetText(text)
    S.SetFont(header.label, S.ResolveFont(c.font) or S.GlobalFontPath(), 12, "OUTLINE")
    S.BagsPaintPreviewSection(header.plate, preview.content, x, y, width,
        math.min(cell.height, preview.rows - cell.line) * 40 - 5, c, header.label)
    header.label:Show()
end

local function Geometry(preview, c, bank, native)
    local g = preview.geometry
    g.nativeBackpack = not bank and c.inventoryView == VIEW.BLIZZARD_GRID
    if bank then
        g.panel, g.sidebar, g.top = false, c.bankView == BANK_VIEW.CATEGORIES and 170 or 12, 40
        g.height = BANK_HEIGHT
        g.rows = math.floor((g.height - 84) / 40)
    elseif g.nativeBackpack then
        g.panel, g.sidebarShown, g.rail = false, false, 0
        g.width, g.height, g.rows = BACKPACK_WIDTH, BACKPACK_HEIGHT, BACKPACK_ROWS
    else
        local width, height = UIParent:GetWidth(), UIParent:GetHeight()
        local scale = S.BagsPreviewScale(c, width, height, 24, false)
        S.BagsPreviewGeometry(g, c, width / scale, height / scale - 12, 24)
    end
    local layout = EMPTY
    if not native and not g.nativeBackpack then
        layout = S.BagsPreviewLayout(preview.snapshot, c, bank, not bank and g or nil)
        if not bank then S.BagsFitPreviewRows(g, c, preview.snapshot.model.lineCount) end
    end
    local columns = preview.snapshot.config.inventoryColumns
    local width = native and BANK_WIDTH or bank and preview.snapshot.width or g.width
    preview.rows = g.rows
    preview.content:SetSize(width, g.height)
    local outerWidth, outerHeight = width + (native and 36 or 0), g.height + (native and 28 or 0)
    local scale = math.min(preview.width / outerWidth, (g.panel and 350 or 304) / outerHeight)
    preview.content:SetScale(scale)
    preview.content:ClearAllPoints()
    local anchor = native and "TOPLEFT" or "TOPRIGHT"
    preview.content:SetPoint(anchor, preview.window, anchor)
    preview.window:SetHeight(math.ceil(outerHeight * scale))
    preview.footer:ClearAllPoints()
    preview.footer:SetPoint("TOPLEFT", preview.window, "BOTTOMLEFT", -4, -10)
    return layout, width, columns
end

local function PlaceTool(button, label, texture, atlas, panel, x, y, width)
    button:ClearAllPoints()
    button:SetPoint("TOPRIGHT", button:GetParent(), "TOPRIGHT", x, y)
    button:SetSize(width, panel and 24 or 22)
    P.SetTranslatedText(button.previewLabel, Tr(label))
    button.previewLabel:SetShown(not panel)
    button.previewLabel:SetWidth(width - 8)
    S.BagsPaintPreviewTool(button, label, texture, atlas, panel)
end

local function PlaceSessionGold(preview, c)
    local g = preview.geometry
    local show = (g.panel or g.nativeBackpack) and c.showSessionGold
    preview.session:SetShown(show)
    preview.sessionJump:SetShown(show)
    if not show then return end
    local label, period = preview.session, c.goldPeriod
    local session, today = Tr("Session %s"):format("+124 |cffffd700g|r"), Tr("Today %s"):format("+370 |cffffd700g|r")
    label:ClearAllPoints()
    label:SetPoint("BOTTOMLEFT", preview.content, "BOTTOMLEFT", 8, g.panel and 50 or 2)
    label:SetSize(g.panel and 96 or 260, g.panel and (period == GOLD_PERIOD.BOTH and 44 or 32) or 18)
    label:SetWordWrap(g.panel)
    label:SetText(period == GOLD_PERIOD.TODAY and today
        or period == GOLD_PERIOD.BOTH and session .. (g.panel and "\n" or "    ") .. today or session)
    S.SetFont(label, S.ResolveFont(c.font) or S.GlobalFontPath(), 11, "OUTLINE")
end

local function PlaceNativeBackpackControls(preview, width)
    local title, search = preview.title, preview.search
    title:SetWidth(width - 104)
    title:SetJustifyH("CENTER")
    search:ClearAllPoints()
    search:SetPoint("TOPLEFT", preview.content, "TOPLEFT", 62, -37)
    search:SetSize(330, 18)
    preview.searchLabel:SetWidth(314)
    P.SetTranslatedText(preview.searchLabel, Tr("Search"))
    PlaceTool(preview.cleanup, "Clean up bags", nil, "bags-button-autosort-up", true, -9, -34, 24)
end

local function PlaceControls(preview, c, bank, width, native)
    local g = preview.geometry
    local suite = not bank and c.inventoryView ~= VIEW.BLIZZARD_GRID
    local categories = bank and c.bankView == BANK_VIEW.CATEGORIES or not bank and g.sidebarShown
    preview.title:SetShown(not g.panel)
    preview.title:ClearAllPoints()
    preview.title:SetPoint("TOPLEFT", preview.content, "TOPLEFT", 12, native and -5 or -10)
    preview.title:SetWidth(native and width - 24 or 400)
    preview.title:SetJustifyH(native and "CENTER" or "LEFT")
    preview.categories:SetShown(categories)
    if categories then
        preview.categories:ClearAllPoints()
        preview.categories:SetPoint("TOPLEFT", preview.content, "TOPLEFT", g.panel and 8 or 12, g.panel and -224 or -g.top)
        preview.categories:SetSize(g.panel and 88 or 148, g.panel and g.height - 318 or (bank and 260 or g.height - g.top - g.bottom))
        preview.categoryLabel:SetWidth(g.panel and 80 or 140)
    end
    preview.search:ClearAllPoints()
    preview.search:SetShown(bank or not c.hideSearchBar)
    local searchLeft = bank and 240 or (g.panel and g.rail + 20 or 12)
    preview.search:SetPoint("TOPLEFT", preview.content, "TOPLEFT", searchLeft, bank and -7 or (g.panel and -58 or -91))
    preview.search:SetSize(width - searchLeft - 12, 23)
    preview.searchLabel:SetWidth(width - searchLeft - 28)
    P.SetTranslatedText(preview.searchLabel, Tr(native and "Search" or "Search items"))
    for i, button in ipairs(preview.viewButtons) do
        button:ClearAllPoints()
        button:SetPoint("TOPLEFT", preview.content, "TOPLEFT", g.panel and 8 or 12 + (i - 1) * 92,
            g.panel and -100 - (i - 1) * 34 or -62)
        button:SetSize(g.panel and 96 or 88, g.panel and 28 or 22)
        button:SetShown(suite and not g.hideTabs)
    end
    preview.equipped:SetShown(suite)
    -- The side panel's tools end 8 left of the caption (BagCaption.lua PANEL_TOOLS).
    PlaceTool(preview.equipped, "Equipped bags", "Interface\\Icons\\INV_Misc_Bag_08", nil,
        g.panel, g.panel and -99 or -12, g.panel and -16 or -62, g.panel and 24 or 116)
    PlaceTool(preview.cleanup, bank and "Manage bank tabs" or "Clean up bags", nil, "bags-button-autosort-up",
        g.panel, g.panel and -131 or (bank and -12 or -156), g.panel and -16 or -328, g.panel and 24 or (bank and 160 or 108))
    PlaceSessionGold(preview, c)
    if native then
        preview.search:ClearAllPoints()
        preview.search:SetPoint("TOPRIGHT", preview.content, "TOPRIGHT", -56, -33)
        preview.search:SetWidth(110)
        preview.searchLabel:SetWidth(94)
        PlaceTool(preview.cleanup, "Clean up bags", nil, "bags-button-autosort-up", true, -20, -33, 24)
    elseif g.nativeBackpack then
        PlaceNativeBackpackControls(preview, width)
    elseif not g.panel then
        preview.cleanup:ClearAllPoints()
        preview.cleanup:SetPoint("BOTTOMRIGHT", preview.content, "BOTTOMRIGHT", bank and -12 or -156, 10)
    end
    preview.free:ClearAllPoints()
    preview.free:SetPoint("BOTTOMLEFT", preview.content, "BOTTOMLEFT", g.panel and 8 or 12, g.panel and 12 or 20)
    preview.free:SetSize(g.panel and 96 or 220, g.panel and 32 or 0)
    preview.free:SetWordWrap(g.panel)
    preview.chrome.goldLabel:ClearAllPoints()
    preview.chrome.goldLabel:SetPoint("BOTTOMRIGHT", preview.content, "BOTTOMRIGHT",
        g.nativeBackpack and -26 or -12, g.nativeBackpack and 5 or 20)
    preview.chrome.goldLabel:SetShown(not bank)
    preview.goldJump:SetShown(not bank)
end

local function SampleBankButton(preview, frame, text, x, y, width, open)
    local button = GuideTarget(preview, K.Button(frame, x, y, width, 24, open))
    local fill = Texture(button)
    fill:SetAllPoints(button)
    fill:SetColorTexture(.18, .21, .24, .75)
    K.Text(button, text, 4, -4, width - 8):SetJustifyH("CENTER")
end

-- Mainline BankFrame.xml and BankPanelMixin:GenerateItemSlotsForSelectedTab.
-- Use sample items and the native seven rows, paired columns and side tabs.
local function CreateNativeBank(ui, preview)
    local frame = CreateFrame("Frame", nil, preview.content)
    frame:SetAllPoints(preview.content)
    local native = { frame = frame, slots = {} }
    local function Open() ui:Focus("suite_bags_bank") end
    K.Text(frame, "1", 219, -40, 300):SetJustifyH("CENTER")
    for column = 0, 13 do
        for row = 0, 6 do
            local x, y = 26 + column * 45 + math.floor(column / 2) * 11, -63 - row * 47
            local empty = Texture(frame)
            empty:SetAtlas("bags-item-slot64")
            empty:SetPoint("TOPLEFT", frame, "TOPLEFT", x, y)
            empty:SetSize(37, 37)
            local index = row * 14 + column + 1
            if preview.snapshot.items[index] then
                local slot = Slot(preview, ui, frame)
                slot:ClearAllPoints()
                slot:SetPoint("TOPLEFT", frame, "TOPLEFT", x, y)
                slot:SetSize(37, 37)
                native.slots[index] = slot
            end
        end
    end
    for index = 1, 6 do
        local tab = GuideTarget(preview, K.Button(frame, BANK_WIDTH + 2, -25 - (index - 1) * 49, 32, 32, Open))
        local icon = Texture(tab, "ARTWORK")
        icon:SetAllPoints(tab)
        icon:SetTexture(QUESTION_MARK_ICON or 134400)
        if index == 1 then
            local selected = Texture(tab, "OVERLAY")
            selected:SetAllPoints(tab)
            selected:SetTexture("Interface\\Buttons\\CheckButtonHilight")
            selected:SetBlendMode("ADD")
        end
    end
    SampleBankButton(preview, frame, BANK or Tr("Bank"), 22, 2 - BANK_HEIGHT, 100, Open)
    SampleBankButton(preview, frame, ACCOUNT_BANK_PANEL_TITLE or "Warband Bank", 126, 2 - BANK_HEIGHT, 100, Open)
    SampleBankButton(preview, frame, Tr("Bank tabs"), BANK_WIDTH - 164, 2 - BANK_HEIGHT, 142, Open)
    SampleBankButton(preview, frame, CHARACTER_BANK_DEPOSIT_BUTTON_LABEL or "Deposit All Reagents", 241, -396, 256, Open)
    K.Text(frame, "12,345 |cffffd700g|r", 534, -436, 180):SetJustifyH("RIGHT")
    return native
end

local function PaintNativeBank(ui, preview, c, native)
    if not native then
        if preview.nativeBank then preview.nativeBank.frame:Hide() end
        return
    end
    preview.nativeBank = preview.nativeBank or CreateNativeBank(ui, preview)
    preview.nativeBank.frame:Show()
    for index, slot in pairs(preview.nativeBank.slots) do PaintItem(slot, preview.snapshot.items[index], c, true, true) end
end

-- Blizzard's combined bag packs ten columns of 37px slots from the bottom
-- right, with 5px gaps. Populate the preview with example items only.
local function CreateNativeBackpack(ui, preview)
    local frame = CreateFrame("Frame", nil, preview.content)
    frame:SetAllPoints(preview.content)
    local slots = {}
    for index = 1, BACKPACK_SLOTS do
        local slot = Slot(preview, ui, frame)
        local column, row = (index - 1) % BACKPACK_COLUMNS, math.floor((index - 1) / BACKPACK_COLUMNS)
        slot:ClearAllPoints()
        slot:SetSize(BACKPACK_SLOT_SIZE, BACKPACK_SLOT_SIZE)
        slot:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -7 - column * BACKPACK_PITCH, BACKPACK_BOTTOM + row * BACKPACK_PITCH)
        slots[index] = slot
    end
    local scaleGrip = GuideTarget(preview, K.Button(frame, 0, 0, 20, 20, function() ui:Focus("suite_bags_window") end))
    scaleGrip:ClearAllPoints()
    scaleGrip:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -1, 1)
    scaleGrip.icon = Texture(scaleGrip, "ARTWORK")
    scaleGrip.icon:SetAllPoints(scaleGrip)
    scaleGrip.icon:SetTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
    return { frame = frame, slots = slots, scaleGrip = scaleGrip }
end

local function PaintNativeBackpack(ui, preview, c)
    local grid = preview.nativeBackpack
    if not preview.geometry.nativeBackpack then
        if grid then grid.frame:Hide() end
        return
    end
    grid = grid or CreateNativeBackpack(ui, preview)
    preview.nativeBackpack = grid
    grid.frame:Show()
    local items = preview.snapshot.items
    for index, slot in ipairs(grid.slots) do
        if index <= 3 or index >= 31 then
            PaintItem(slot, items[(index - 1) % 12 + 1], c, false)
        else
            PaintEmpty(slot, c)
        end
    end
end

local function PaintCells(ui, preview, c, bank, layout, columns)
    for _, slot in pairs(preview.slots) do slot:Hide() end
    for _, header in ipairs(preview.groups) do
        header.label:Hide()
        header.plate:Hide()
    end
    local g, headers = preview.geometry, 0
    for _, cell in ipairs(layout) do
        if cell.line < preview.rows then
            local x, y = g.sidebar + cell.column * 40, -g.top - cell.line * 40
            if cell.row then
                local item = cell.row.item
                local slot = preview.slots[item.itemID]
                if not slot then
                    slot = Slot(preview, ui)
                    preview.slots[item.itemID] = slot
                end
                slot:ClearAllPoints()
                slot:SetPoint("TOPLEFT", preview.content, "TOPLEFT", x, y)
                PaintItem(slot, item, c, bank)
                slot:Show()
            else
                headers = headers + 1
                Header(preview, headers, cell, x, y, (cell.width or columns) * 40 - 5, c)
            end
        end
    end
end

local function PaintLayout(ui, preview, c, bank, native)
    preview.snapshot = preview.snapshot or S.BagsNewPreview()
    local layout, width, columns = Geometry(preview, c, bank, native)
    PlaceControls(preview, c, bank, width, native)
    PaintCells(ui, preview, c, bank, layout, columns)
    PaintNativeBank(ui, preview, c, native)
    PaintNativeBackpack(ui, preview, c)
end

local function Paint(ui, preview)
    if not K.Runtime("MSUF_Suite_Bags", "BagsNewPreview") then
        P.SetTranslatedText(preview.footer, Tr("Preview is available outside combat."))
        return
    end
    local c = S.Config("bags")
    local changed = K.Changed(preview.settings, c, P.catalog.bags.rules)
    local width, height = UIParent:GetWidth(), UIParent:GetHeight()
    local border = S.BagsDefaultBorder and S.BagsDefaultBorder(c)
    if not changed and preview.tab == ui.selected and preview.defaultBorder == border
        and preview.viewportWidth == width and preview.viewportHeight == height then return end
    preview.defaultBorder = border
    preview.tab, preview.viewportWidth, preview.viewportHeight = ui.selected, width, height
    local bank = ui.selected == "bank"
    local native = bank and c.bankView == BANK_VIEW.TABS
    preview.chrome.combined = not bank
    S.BagsPaintPreviewWindow(preview.chrome, bank and BankLook(preview.bankLook, c) or c)
    PaintCaption(preview, c, bank)
    preview.chrome[3]:SetHeight(bank and (native and 22 or 40) or (preview.chrome.panel and 50 or 62))
    local title = bank and P.catalog.bags.rules.bankView.choices[c.bankView] or "Bags"
    if native then title = BANK or Tr("Bank")
    elseif not bank and c.inventoryView == VIEW.BLIZZARD_GRID then title = COMBINED_BAG_TITLE or Tr(title)
    else title = Tr(title) end
    P.SetTranslatedText(preview.title, title)
    PaintLayout(ui, preview, c, bank, native)
    PaintBorderExamples(ui, preview, c, bank)
    local showFree = not native and not preview.geometry.nativeBackpack and c.showFreeSlots
    preview.free:SetShown(showFree)
    preview.freeJump:SetShown(showFree)
    preview.free:SetText(string.format(bank and Tr("%d free") or Tr("%d free + %d reagent"), 22, 4))
    P.SetTranslatedText(preview.footer, Tr("Sample values. Click an element to open its settings."))
    P.MenuWorkspace.FitHeader(ui, math.max(406, 102 + preview.window:GetHeight())
        + (bank and 0 or 48) + math.ceil(preview.footer:GetStringHeight() or 14))
end

local function WatchViewport(ui)
    local events = CreateFrame("Frame", nil, ui.header)
    local function Activate()
        events:RegisterEvent("UI_SCALE_CHANGED")
        events:RegisterEvent("DISPLAY_SIZE_CHANGED")
        ui.refreshPreview()
    end
    events:SetScript("OnShow", Activate)
    events:SetScript("OnHide", events.UnregisterAllEvents)
    events:SetScript("OnEvent", function() ui.refreshPreview() end)
    if events:IsVisible() then Activate() end
end

function P.BuildBagsMenuPreview(ui)
    if not ui then return end
    local width = math.min(520, ui.width - 40)
    local window = K.Button(ui.header, 20, -76, width, 304, function() ui:Focus("suite_bags_appearance") end)
    local content = CreateFrame("Frame", nil, window)
    content:SetPoint("TOPLEFT")
    local preview = { window = window, content = content, width = width, settings = {}, slots = {}, groups = {}, bankLook = {}, geometry = {} }
    local guide = CreateFrame("Frame", nil, content)
    guide:SetFrameLevel(content:GetFrameLevel() + 7)
    guide:EnableMouse(false)
    guide:Hide()
    preview.guide = guide
    GuideTarget(preview, window)
    window:SetScript("OnHide", function()
        preview.hovered, preview.clicked = nil, nil
        RefreshGuide(preview)
    end)
    preview.chrome = Chrome(content, 620)
    preview.caption = Caption(content)
    preview.title = K.Text(content, "Bags", 12, -10, 400)
    local function FocusOrganisation()
        ui:Focus(ui.selected == "bank" and "suite_bags_bank" or "suite_bags_organisation")
    end
    preview.search = GuideTarget(preview, K.Button(content, 12, -91, 596, 23, function()
        ui:Focus(ui.selected == "bank" and "suite_bags_bank" or "suite_bags_window")
    end))
    local fill = Texture(preview.search)
    fill:SetAllPoints(preview.search)
    fill:SetColorTexture(0, 0, 0, .25)
    preview.searchLabel = K.Text(preview.search, "Search items", 8, -4, 570)
    preview.viewButtons = {}
    for i, title in ipairs({ "All items", "By bag", "Categories" }) do
        local button = GuideTarget(preview, K.Button(content, 12 + (i - 1) * 92, -62, 88, 22, FocusOrganisation))
        K.Text(button, title, 4, -4, 84)
        preview.viewButtons[i] = button
    end
    local equipped = K.Button(content, 492, -62, 116, 22, function() ui:Focus("suite_bags_window") end)
    equipped.previewLabel = K.Text(equipped, "Equipped bags", 4, -4, 112)
    preview.equipped = GuideTarget(preview, equipped)
    preview.categories = GuideTarget(preview, K.Button(content, 12, -122, 148, 180, function()
        ui:Focus(ui.selected == "bank" and "suite_bags_bank" or "suite_bags_categories")
    end))
    preview.categoryLabel = K.Text(preview.categories, Tr("Equipment") .. "\n\n" .. Tr("Consumables") .. "\n\n" .. Tr("Reagents"), 4, -6, 140)
    preview.session = K.Text(content, string.format(Tr("Session %s"), "+124 |cffffd700g|r"), 8, 0, 96)
    preview.session:ClearAllPoints()
    preview.session:SetPoint("BOTTOMLEFT", content, "BOTTOMLEFT", 8, 50)
    preview.session:SetHeight(32)
    preview.session:SetWordWrap(true)
    preview.session:Hide()
    local sessionJump = K.Jump(ui, preview.session, content, "suite_bags_finance")
    sessionJump:SetScript("OnClick", function()
        if not P.Suite.HostBridge.OpenExactMenuSetting(P.M, "suite_bags", "suite_bags_finance", "msufsuite.bags.goldPeriod") then
            ui:Focus("suite_bags_finance")
        end
    end)
    sessionJump:Hide()
    preview.sessionJump = GuideTarget(preview, sessionJump)
    preview.free = K.Text(content, "", 12, -328, 220)
    preview.freeJump = GuideTarget(preview, K.Jump(ui, preview.free, content, "suite_bags_organisation"))
    local cleanup = K.Button(content, 396, -328, 160, 22, FocusOrganisation)
    preview.cleanup = GuideTarget(preview, cleanup)
    preview.cleanupLabel = K.Text(cleanup, "Clean up bags", 4, -4, 156)
    cleanup.previewLabel = preview.cleanupLabel
    preview.goldJump = GuideTarget(preview, K.Jump(ui, preview.chrome.goldLabel, content, "suite_bags_finance"))
    K.Text(ui.header, "Preview", 16, -52, ui.width - 32)
    preview.footer = K.Text(ui.header, "", 16, -390, ui.width - 32)
    ui.bagsPreview = preview
    P.MenuWorkspace.FitHeader(ui, 406 + math.ceil(preview.footer:GetStringHeight() or 14))
    K.Watch(ui, function()
        Paint(ui, preview)
        RefreshGuide(preview)
    end)
    WatchViewport(ui)
end

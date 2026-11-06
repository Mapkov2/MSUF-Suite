local _, P = ...
local K, S, Tr = P.PreviewCanvas, P.S, P.Tr
local VIEW, BANK_VIEW = P.Suite.BagsView, P.Suite.BagsBankView
-- The runtime supplies representative items and its real category/packing
-- model. The menu never scans bags, banks or character inventories.
local function Texture(parent, layer)
    return parent:CreateTexture(nil, layer or "BACKGROUND")
end
local function Chrome(window, width)
    local t = { shell = window, combined = true }
    for i = 1, 9 do t[i] = Texture(window, i == 4 and "ARTWORK" or "BACKGROUND") end
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

local function Slot(parent, ui)
    local slot = K.Button(parent, 0, 0, 36, 36, function() ui:Focus("suite_bags_itemLevels") end)
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

local function PaintItem(slot, item, c, bank)
    slot.icon:SetTexture(item.icon)
    slot.level:SetText(item.itemLevel > 0 and tostring(item.itemLevel) or "")
    slot.count:SetText(item.count > 1 and tostring(item.count) or "")
    slot.level:SetShown(bank and c.showBankItemLevel or not bank and c.showItemLevel)
    slot.arrow:SetShown(c.showUpgradeMarker and item.upgrade == true)
    S.BagsStylePreviewLabel(slot.level, c)
    local r, g, b = C_Item.GetItemQualityColor(item.quality)
    slot.border:SetColorTexture(r, g, b, 1)
    slot.level:SetTextColor(c.qualityColor and r or 1, c.qualityColor and g or 1, c.qualityColor and b or 1)
    S.SetFont(slot.count, S.ResolveFont(c.font) or S.GlobalFontPath(), c.itemCountSize, "OUTLINE")
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

local function Geometry(preview, c, bank)
    local g = preview.geometry
    if bank then
        g.panel, g.sidebar, g.top, g.rows, g.height = false, c.bankView == BANK_VIEW.CATEGORIES and 170 or 12, 40, 7, 360
    else
        local width, height = UIParent:GetWidth(), UIParent:GetHeight()
        local scale = S.BagsPreviewScale(c, width, height, 24, false)
        S.BagsPreviewGeometry(g, c, width / scale, height / scale - 12, 24)
    end
    local layout = S.BagsPreviewLayout(preview.snapshot, c, bank, not bank and g or nil)
    if not bank then S.BagsFitPreviewRows(g, c, preview.snapshot.model.lineCount) end
    local columns = preview.snapshot.config.inventoryColumns
    local width = bank and preview.snapshot.width or g.width
    if not bank and c.inventoryView == VIEW.BLIZZARD_GRID then g.rows, g.height = 5, 360 end
    preview.rows = g.rows
    preview.content:SetSize(width, g.height)
    local scale = math.min(preview.width / width, (g.panel and 350 or 304) / g.height)
    preview.content:SetScale(scale)
    preview.content:ClearAllPoints()
    preview.content:SetPoint("TOPRIGHT", preview.window, "TOPRIGHT")
    preview.window:SetHeight(math.ceil(g.height * scale))
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

local function PlaceControls(preview, c, bank, width)
    local g = preview.geometry
    local suite = not bank and c.inventoryView ~= VIEW.BLIZZARD_GRID
    local categories = bank and c.bankView == BANK_VIEW.CATEGORIES or not bank and c.inventoryView == VIEW.CATEGORIES
    preview.title:SetShown(not g.panel)
    preview.categories:SetShown(categories)
    preview.categories:ClearAllPoints()
    preview.categories:SetPoint("TOPLEFT", preview.content, "TOPLEFT", g.panel and 8 or 12, g.panel and -224 or -g.top)
    preview.categories:SetSize(g.panel and 88 or 148, g.panel and g.height - 318 or (bank and 260 or g.height - g.top - g.bottom))
    preview.categoryLabel:SetWidth(g.panel and 80 or 140)
    preview.search:ClearAllPoints()
    preview.search:SetPoint("TOPLEFT", preview.content, "TOPLEFT", bank and 240 or (g.panel and 132 or 12), bank and -7 or (g.panel and -58 or -91))
    preview.search:SetWidth(width - (bank and 252 or (g.panel and 144 or 24)))
    preview.searchLabel:SetWidth(width - (bank and 268 or (g.panel and 160 or 40)))
    for i, button in ipairs(preview.viewButtons) do
        button:ClearAllPoints()
        button:SetPoint("TOPLEFT", preview.content, "TOPLEFT", g.panel and 8 or 12 + (i - 1) * 92,
            g.panel and -100 - (i - 1) * 34 or -62)
        button:SetSize(g.panel and 96 or 88, g.panel and 28 or 22)
        button:SetShown(suite)
    end
    preview.equipped:SetShown(suite)
    PlaceTool(preview.equipped, "Equipped bags", "Interface\\Icons\\INV_Misc_Bag_08", nil,
        g.panel, g.panel and -44 or -12, g.panel and -16 or -62, g.panel and 24 or 116)
    PlaceTool(preview.cleanup, bank and "Manage bank tabs" or "Clean up bags", nil, "bags-button-autosort-up",
        g.panel, g.panel and -76 or (bank and -12 or -156), g.panel and -16 or -328, g.panel and 24 or (bank and 160 or 108))
    preview.session:SetShown(g.panel and c.showSessionGold)
    S.SetFont(preview.session, S.ResolveFont(c.font) or S.GlobalFontPath(), 11, "OUTLINE")
    if not g.panel then
        preview.cleanup:ClearAllPoints()
        preview.cleanup:SetPoint("BOTTOMRIGHT", preview.content, "BOTTOMRIGHT", bank and -12 or -156, 10)
    end
    preview.free:ClearAllPoints()
    preview.free:SetPoint("BOTTOMLEFT", preview.content, "BOTTOMLEFT", g.panel and 8 or 12, g.panel and 12 or 20)
    preview.free:SetSize(g.panel and 96 or 220, g.panel and 32 or 0)
    preview.free:SetWordWrap(g.panel)
    preview.chrome.goldLabel:ClearAllPoints()
    preview.chrome.goldLabel:SetPoint("BOTTOMRIGHT", preview.content, "BOTTOMRIGHT", -12, 20)
    preview.chrome.goldLabel:SetShown(not bank)
    preview.goldJump:SetShown(not bank)
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
                    slot = Slot(preview.content, ui)
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

local function PaintLayout(ui, preview, c, bank)
    preview.snapshot = preview.snapshot or S.BagsNewPreview()
    local layout, width, columns = Geometry(preview, c, bank)
    PlaceControls(preview, c, bank, width)
    PaintCells(ui, preview, c, bank, layout, columns)
end

local function Paint(ui, preview)
    if not K.Runtime("MSUF_Suite_Bags", "BagsNewPreview") then
        P.SetTranslatedText(preview.footer, Tr("Preview is available outside combat."))
        return
    end
    local c = S.Config("bags")
    local changed = K.Changed(preview.settings, c, P.catalog.bags.rules)
    local width, height = UIParent:GetWidth(), UIParent:GetHeight()
    if not changed and preview.tab == ui.selected and preview.viewportWidth == width and preview.viewportHeight == height then return end
    preview.tab, preview.viewportWidth, preview.viewportHeight = ui.selected, width, height
    local bank = ui.selected == "bank"
    preview.chrome.combined = not bank
    S.BagsPaintPreviewWindow(preview.chrome, bank and BankLook(preview.bankLook, c) or c)
    P.SetTranslatedText(preview.title, bank and Tr(P.catalog.bags.rules.bankView.choices[c.bankView]) or Tr("Bags"))
    PaintLayout(ui, preview, c, bank)
    preview.free:SetShown(c.showFreeSlots)
    preview.free:SetText(string.format(bank and Tr("%d free") or Tr("%d free + %d reagent"), 22, 4))
    P.SetTranslatedText(preview.footer, Tr("Sample values. Click an element to open its settings."))
    P.MenuWorkspace.FitHeader(ui, math.max(406, 102 + preview.window:GetHeight()) + math.ceil(preview.footer:GetStringHeight() or 14))
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
    preview.chrome = Chrome(content, 620)
    preview.title = K.Text(content, "Bags", 12, -10, 400)
    local route = function() return ui.selected == "bank" and "suite_bags_bank" or "suite_bags_organisation" end
    preview.search = K.Button(content, 12, -91, 596, 23, function() ui:Focus(route()) end)
    local fill = Texture(preview.search)
    fill:SetAllPoints(preview.search)
    fill:SetColorTexture(0, 0, 0, .25)
    preview.searchLabel = K.Text(preview.search, "Search items", 8, -4, 570)
    preview.viewButtons = {}
    for i, title in ipairs({ "All items", "By bag", "Categories" }) do
        local button = K.Button(content, 12 + (i - 1) * 92, -62, 88, 22, function() ui:Focus(route()) end)
        K.Text(button, title, 4, -4, 84)
        preview.viewButtons[i] = button
    end
    local equipped = K.Button(content, 492, -62, 116, 22, function() ui:Focus("suite_bags_window") end)
    equipped.previewLabel = K.Text(equipped, "Equipped bags", 4, -4, 112)
    preview.equipped = equipped
    preview.categories = K.Button(content, 12, -122, 148, 180, function() ui:Focus(ui.selected == "bank" and "suite_bags_bank" or "suite_bags_categories") end)
    preview.categoryLabel = K.Text(preview.categories, Tr("Equipment") .. "\n\n" .. Tr("Consumables") .. "\n\n" .. Tr("Reagents"), 4, -6, 140)
    preview.session = K.Text(content, string.format(Tr("Session %s"), "+124 |cffffd700g|r"), 8, 0, 96)
    preview.session:ClearAllPoints()
    preview.session:SetPoint("BOTTOMLEFT", content, "BOTTOMLEFT", 8, 50)
    preview.session:SetHeight(32)
    preview.session:SetWordWrap(true)
    preview.free = K.Text(content, "", 12, -328, 220)
    K.Jump(ui, preview.free, content, "suite_bags_organisation")
    local cleanup = K.Button(content, 396, -328, 160, 22, function() ui:Focus(route()) end)
    preview.cleanup = cleanup
    preview.cleanupLabel = K.Text(cleanup, "Clean up bags", 4, -4, 156)
    cleanup.previewLabel = preview.cleanupLabel
    preview.goldJump = K.Jump(ui, preview.chrome.goldLabel, content, "suite_bags_finance")
    K.Text(ui.header, "Preview", 16, -52, ui.width - 32)
    preview.footer = K.Text(ui.header, "", 16, -390, ui.width - 32)
    ui.bagsPreview = preview
    P.MenuWorkspace.FitHeader(ui, 406 + math.ceil(preview.footer:GetStringHeight() or 14))
    K.Watch(ui, function() Paint(ui, preview) end)
    WatchViewport(ui)
end

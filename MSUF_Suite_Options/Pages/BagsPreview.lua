local _, P = ...
local K, S, Tr = P.PreviewCanvas, P.S, P.Tr
-- Representative inventory, not a scan of bags or inaccessible bank tabs.
local ITEMS = {
    { 135274, 4, "450", "" }, { 132529, 3, "437", "" }, { 132608, 4, "450", "" },
    { 134829, 2, "", "20" }, { 134830, 2, "", "5" }, { 134414, 1, "", "200" },
    { 133739, 2, "", "80" }, { 134414, 3, "", "12" }, { 132727, 4, "450", "" },
    { 132574, 3, "437", "" }, { 134328, 2, "", "8" }, { 134328, 1, "", "50" },
}
local function Texture(parent, layer)
    return parent:CreateTexture(nil, layer or "BACKGROUND")
end
local function Chrome(window, width)
    local t = {}
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
    t.goldLabel = K.Text(window, "12,345 |cffffd700g|r", width - 144, -213, 132)
    t.goldLabel:SetJustifyH("RIGHT")
    return t
end
local function Slot(window, index, ui)
    local item = ITEMS[index]
    local slot = K.Button(window, 0, 0, 36, 36, function() ui:Focus("suite_bags_itemLevels") end)
    slot.border = Texture(slot)
    slot.border:SetAllPoints(slot)
    slot.icon = Texture(slot, "ARTWORK")
    slot.icon:SetPoint("TOPLEFT", 1, -1)
    slot.icon:SetPoint("BOTTOMRIGHT", -1, 1)
    slot.icon:SetTexture(item[1])
    slot.icon:SetTexCoord(.08, .92, .08, .92)
    slot.level = K.Text(slot, item[3], 2, -2, 32)
    slot.level:SetJustifyH("RIGHT")
    slot.count = K.Text(slot, item[4], 2, -22, 32)
    slot.count:SetJustifyH("RIGHT")
    return slot
end
local function Paint(ui, preview)
    if not K.Runtime("MSUF_Suite_Bags", "BagsPaintPreviewWindow") then
        P.SetTranslatedText(preview.footer, Tr("Preview is available outside combat."))
        return
    end
    local c = S.Config("bags")
    local changed = K.Changed(preview.settings, c, P.catalog.bags.rules)
    if not changed and preview.tab == ui.selected then return end
    preview.tab = ui.selected
    local bank = ui.selected == "bank"
    local categories = bank and c.bankView == 4 or not bank and c.inventoryView == 3
    P.SetTranslatedText(preview.title, bank and Tr("Bank organisation") or Tr("Bags"))
    S.BagsPaintPreviewWindow(preview.chrome, c)
    preview.categories:SetShown(categories)
    local start = categories and 128 or 12
    local columns = math.max(1, math.min(6, math.floor((preview.width - start - 12) / 40)))
    for i, slot in ipairs(preview.slots) do
        slot:ClearAllPoints()
        slot:SetPoint("TOPLEFT", preview.window, "TOPLEFT", start + (i - 1) % columns * 40,
            -76 - math.floor((i - 1) / columns) * 40)
        slot:SetShown(i <= columns * 3)
        slot.level:SetShown(bank and c.showBankItemLevel or not bank and c.showItemLevel)
        S.BagsStylePreviewLabel(slot.level, c)
        local r, g, b = 1, 1, 1
        if c.qualityColor then r, g, b = C_Item.GetItemQualityColor(ITEMS[i][2]) end
        slot.level:SetTextColor(r, g, b)
        r, g, b = C_Item.GetItemQualityColor(ITEMS[i][2])
        slot.border:SetColorTexture(r, g, b, 1)
        P.StylePreviewFont(slot.count, c.font, c.itemCountSize or 12, "OUTLINE", c.fontRendering)
    end
    P.SetTranslatedText(preview.footer, Tr("Sample values. Click an element to open its settings."))
    P.MenuWorkspace.FitHeader(ui, 344 + math.ceil(preview.footer:GetStringHeight() or 14))
end

function P.BuildBagsMenuPreview(ui)
    if not ui then return end
    local width = math.min(520, ui.width - 40)
    local window = K.Button(ui.header, 20, -76, width, 242, function() ui:Focus("suite_bags_appearance") end)
    local preview = { window = window, width = width, settings = {}, slots = {} }
    preview.chrome = Chrome(window, width)
    preview.title = K.Text(window, "Bags", 12, -10, width - 48)
    K.Jump({ Focus = function()
        ui:Focus(ui.selected == "bank" and "suite_bags_bank" or "suite_bags_window")
    end }, preview.title, window, "suite_bags_window")
    local search = K.Button(window, 12, -35, width - 52, 22, function() ui:Focus(ui.selected == "bank" and "suite_bags_bank" or "suite_bags_organisation") end)
    preview.search = search
    local bg = Texture(search)
    bg:SetAllPoints(search)
    bg:SetColorTexture(0, 0, 0, .4)
    K.Text(search, "Search items", 6, -4, width - 64)
    local close = K.Button(window, width - 32, -8, 22, 22, function() ui:Focus(ui.selected == "bank" and "suite_bags_bank" or "suite_bags_window") end)
    K.Text(close, "×", 6, -2, 18)
    preview.categories = K.Button(window, 12, -76, 106, 118, function() ui:Focus(ui.selected == "bank" and "suite_bags_bank" or "suite_bags_categories") end)
    K.Text(preview.categories, Tr("Equipment") .. "\n\n" .. Tr("Consumables") .. "\n\n" .. Tr("Reagents"), 0, 0, 104)
    for i = 1, #ITEMS do preview.slots[i] = Slot(window, i, ui) end
    local finance = K.Text(window, "36 / 80", 12, -214, 110)
    K.Jump(ui, finance, window, "suite_bags_finance")
    K.Jump(ui, preview.chrome.goldLabel, window, "suite_bags_finance")
    K.Text(ui.header, "Preview", 16, -52, ui.width - 32)
    preview.footer = K.Text(ui.header, "", 16, -328, ui.width - 32)
    ui.bagsPreview = preview
    K.Watch(ui, function() Paint(ui, preview) end)
end

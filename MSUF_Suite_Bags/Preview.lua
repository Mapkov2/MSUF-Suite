local _, P = ...
local S, Model = P.Suite, P.InventoryModel
local SAMPLES = {
    { 135274, 4, 450, 1, 4, "INVTYPE_HEAD", true },
    { 132529, 3, 437, 1, 4, "INVTYPE_HEAD" },
    { 132608, 4, 450, 1, 4, "INVTYPE_CHEST", true },
    { 134829, 2, 0, 20, 0 }, { 134830, 2, 0, 5, 0 },
    { 134414, 1, 0, 200, 7 }, { 133739, 2, 0, 80, 7 }, { 134414, 3, 0, 12, 7 },
    { 132727, 4, 450, 1, 4, "INVTYPE_CHEST" },
    { 132574, 3, 437, 1, 4, "INVTYPE_CHEST" },
    { 134328, 2, 0, 8, 0 }, { 134328, 1, 0, 50, 0 },
}

function S.BagsNewPreview()
    local preview = { model = Model.New(), items = {}, config = {}, state = {} }
    for i = 1, #SAMPLES do
        local sample = SAMPLES[i]
        preview.items[i] = {
            icon = sample[1], quality = sample[2], itemLevel = sample[3], count = sample[4],
            classID = sample[5], equipLoc = sample[6], upgrade = sample[7], myArmorSlot = sample[6] ~= nil,
            itemID = i, key = i, slot = i, bag = i > 6 and 1 or 0,
            bagName = S.Text(i > 6 and "Bags" or "Backpack"),
            slotName = sample[6] and _G[sample[6]], name = tostring(i),
        }
    end
    return preview
end

function S.BagsPreviewLayout(preview, config, bank, geometry)
    local c = preview.config
    for key, value in pairs(config) do c[key] = value end
    if bank then
        Model.BankConfig(c, config)
        local view = P.BankInventory
        preview.width = view and view.frame and view.frame:GetWidth() or 700
        c.inventoryColumns = Model.BankColumns(preview.width, config.bankView == P.NS.BagsBankView.CATEGORIES)
    else
        preview.width = nil
        if geometry then c.inventoryColumns = geometry.columns end
        if P.BagPresentation.IsPanel(c) then c.compactGroups = false end
    end
    Model.Build(preview.model, preview.items, c, preview.state)
    return Model.Layout(preview.model, c.inventoryColumns, c.compactGroups)
end

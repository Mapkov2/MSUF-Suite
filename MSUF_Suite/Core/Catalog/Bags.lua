local _, NS = ...
local B = NS.CatalogBuild.ForAddon("MSUF_Suite_Bags")

-- The combined bag window and the item APIs exist on Retail and Forever. The
-- combinedBags setting may be missing from a client build; Blizzard's own
-- settings panel checks it the same way.
local function Available()
    local value = C_CVar.GetCVar("combinedBags")
    if not NS.Public(value) then
        return false, "The combined bag setting is protected on this client"
    end
    if type(value) ~= "string" then
        return false, "This client has no combined bag setting"
    end
    return true
end

B.Module("bags", {
    title = "Bags",
    description = "One combined bag with a clear Suite background and item levels on equipment. Keep Blizzard's own item grid, or choose a Suite view with pages, bag groups or categories. Using and sorting items stays Blizzard's.",
    core = true, page = "suite_bags", available = Available,
    conflicts = { "EllesmereUIBags", "ElvUI", "Bagnon", "BetterBags", "AdiBags", "ArkInventory", "Inventorian" },
    cvars = { combinedBags = true },
    summary = "look windowScale windowMoved reagentWindowMoved showItemLevel itemLevelSize backgroundOpacity",
})

-- The choice values of the view and sorting settings below (each is its
-- label's position there); the Bags runtime names its modes through these.
NS.BagsView = { ALL = 1, BY_BAG = 2, CATEGORIES = 3, BLIZZARD_GRID = 4 }
NS.BagsBankView = { TABS = 1, CHARACTER = 2, WARBANK = 3, CATEGORIES = 4 }
NS.BagsSortDirection = { BLIZZARD = 1, FROM_TOP = 2, FROM_BOTTOM = 3 }

-- Bags first kept Blizzard's own item grid under a Suite surface; the Suite
-- inventory views came later. A profile saved before them keeps Blizzard's
-- grid until its player picks a Suite view; new profiles start with All items.
function NS.MigrateBagsInventoryView(modules)
    local bags = modules.bags
    if type(bags) == "table" and next(bags) ~= nil and bags.inventoryView == nil then
        bags.inventoryView = NS.BagsView.BLIZZARD_GRID
    end
end

NS.BagsLookPresets = {
    [1] = { backgroundColor = "0a1522", backgroundOpacity = 96, accentColor = "5794d2" },
    [2] = { backgroundColor = "151719", backgroundOpacity = 96, accentColor = "b9ab86" },
    [3] = { backgroundColor = "14181b", backgroundOpacity = 98, accentColor = "9f8960" },
    [5] = { backgroundColor = "101010", backgroundOpacity = 96, accentColor = "e6ecf2" },
}
NS.BagsLookPresets[6] = B.ClassPreset(NS.BagsLookPresets[5], { accentColor = "accent" })
NS.BagsLookVisualKeys = { backgroundColor = true, backgroundOpacity = true, accentColor = true }
NS.SuiteCatalog.bags.look = {
    key = "look", presets = NS.BagsLookPresets, visualKeys = NS.BagsLookVisualKeys,
    custom = 4, global = true,
}
local initial = NS.BagsLookPresets[NS.Client.isForever and 3 or 2]
B.Section("bags", "look", "Choose a look", {
    B.Choice("look", "Style preset", NS.Client.isForever and 3 or 2,
        { "Midnight Blue", "Midnight Dark", "MSUF Forever", "Custom", "Clean Modern", "Class Style" }),
})
B.Section("bags", "appearance", "Window appearance", {
    B.Color("backgroundColor", "Background color", initial.backgroundColor),
    B.Number("backgroundOpacity", "Background opacity (percent)", initial.backgroundOpacity, 0, 100, 1),
    B.Color("accentColor", "Accent color", initial.accentColor),
})

B.Section("bags", "itemLevels", "Item levels", {
    B.Bool("showItemLevel", "Show item levels on equipment", true),
    B.Bool("showBankItemLevel", "Show item levels in the bank", true),
    B.Bool("showBindBadge", "Show BoE and Warbound badges on items"),
    B.Number("itemLevelSize", "Item level text size", 12, 8, 20),
    B.Bool("qualityColor", "Color item levels by quality", true),
    B.Font("font", "Item level font"),
    B.Choice("fontRendering", "Font rendering", NS.FontRendering.SLUG, { "Smooth", "Sharp / pixel", "Slug" }),
    B.Choice("fontOutline", "Text outline", 1, { "Outline", "Thick outline", "None" }),
    B.Bool("fontShadow", "Text shadow"),
    B.Number("fontShadowOpacity", "Shadow opacity (percent)", 100, 20, 100, 5),
    B.Choice("fontShadowDistance", "Shadow distance", 1, { "1 px", "2 px" }),
})
B.LinkFontShadow(NS.SuiteCatalog.bags.rules)

B.Section("bags", "window", "Combined bag window", {
    B.Bool("showSessionGold", "Show gold change since login", true),
    B.Number("windowScale", "Window size", 1, 0.65, 1.5, 0.05),
    B.Bool("windowMoved", "Use custom window position", false),
    B.Number("windowX", "Horizontal offset", 0, -4096, 4096),
    B.Number("windowY", "Vertical offset", 0, -4096, 4096),
})
B.Section("bags", "organisation", "Inventory organisation", {
    B.Choice("inventoryView", "Default inventory view", 1, { "All items", "By bag", "Categories", "Blizzard grid" }),
    B.Number("inventoryColumns", "Items per row", 12, 8, 20),
    B.Number("inventoryRows", "Visible rows", 10, 4, 16),
    B.Bool("autoSizeWindow", "Fit window to contents", true),
    B.Bool("compactGroups", "Place small groups side by side", true),
    B.Bool("hideEmptySlots", "Hide empty slots"),
    B.Bool("hideEmptyCategories", "Hide empty categories", true),
    B.Bool("mergeStacks", "Combine identical stacks visually"),
    B.Choice("sortDirection", "Native bag sorting direction", 1, { "Blizzard setting", "Fill from the top", "Fill from the bottom" }),
    B.Bool("stackSplitter", "Stack split presets and automatic splitting", true),
    B.Bool("desaturateJunk", "Desaturate junk items"),
    B.Bool("groupEquipmentSets", "Group equipment by set", true),
    B.Bool("groupEquipmentSlots", "Group equipment by slot", true),
    B.Bool("groupExpansions", "Group by expansion"),
    B.Bool("groupReagentTypes", "Group reagents by material type"),
    B.Bool("showEquipmentSetNames", "Show equipment set names"),
    B.Number("equipmentSetNameSize", "Equipment set name text size", 9, 7, 16),
    B.Bool("showUpgradeTrack", "Show upgrade track and rank"),
    B.Number("upgradeTextSize", "Upgrade rank text size", 9, 7, 16),
    B.Bool("showKeystoneDetails", "Show keystone level and dungeon", true),
    B.Number("keystoneLevelSize", "Keystone level text size", 16, 8, 24),
    B.Number("keystoneDungeonSize", "Dungeon abbreviation text size", 9, 7, 16),
    B.Number("itemCountSize", "Item count text size", 12, 8, 20),
    B.String("customCategories", "Custom category data", "", 16000),
})
B.Section("bags", "categories", "Built-in categories", {
    B.Bool("category_equipment", "Equipment category", true),
    B.Bool("category_consumables", "Consumables category", true),
    B.Bool("category_reagents", "Reagents category", true),
    B.Bool("category_recipes", "Recipes category", true),
    B.Bool("category_quest", "Quest items category", true),
    B.Bool("category_junk", "Junk category", true),
})
B.Section("bags", "finance", "Gold and currencies", {
    B.Bool("showGoldHistory", "Record gold history and character balances", true),
    B.String("currencyIDs", "Currency IDs (up to 8, separated by commas)", "", 120),
})
B.Section("bags", "collections", "Pinned and recent items", {
    B.Bool("showPinned", "Show pinned items", true),
    B.Bool("showRecent", "Show recent items", true),
    B.Bool("showPinnedHint", "Show pinned item hints", true),
    B.Bool("showRecentHint", "Show recent item hints", true),
    B.Number("recentHours", "Keep recent items for (hours)", 24, 1, 168),
})
B.Section("bags", "bank", "Bank organisation", {
    B.Choice("bankView", "Default bank view", 1, { "Bank tabs", "Combined bank", "Combined warbank", "Bank categories" }),
    B.Bool("bankGroupExpansions", "Group bank items by expansion"),
    B.Bool("bankGroupEquipmentSlots", "Group bank equipment by slot", true),
    B.Bool("bankGroupReagentTypes", "Group bank reagents by material type", true),
    B.Bool("bankHideEmptySlots", "Hide empty bank slots"),
    B.Bool("showBankTabs", "Show individual bank tabs in the sidebar", true),
})
B.Section("bags", "reagentWindow", "Reagent bag window", {
    B.Bool("reagentWindowMoved", "Use custom reagent bag position", false),
    B.Number("reagentWindowX", "Horizontal offset", 0, -4096, 4096),
    B.Number("reagentWindowY", "Vertical offset", 0, -4096, 4096),
})

local rules = NS.SuiteCatalog.bags.rules
for _, key in ipairs({ "bankView", "bankGroupExpansions", "bankGroupEquipmentSlots",
    "bankGroupReagentTypes", "bankHideEmptySlots", "showBankTabs" }) do
    rules[key].hidden = NS.Client.isForever
end
rules.showKeystoneDetails.hidden = NS.Client.isForever
rules.keystoneLevelSize.hidden = NS.Client.isForever
rules.keystoneDungeonSize.hidden = NS.Client.isForever
rules.equipmentSetNameSize.enableKey = "showEquipmentSetNames"
rules.upgradeTextSize.enableKey = "showUpgradeTrack"
rules.keystoneLevelSize.enableKey = "showKeystoneDetails"
rules.keystoneDungeonSize.enableKey = "showKeystoneDetails"
rules.customCategories.hidden = true
rules.recentHours.enableKey = "showRecent"
rules.showBindBadge.hidden = NS.Client.isForever
rules.showBankItemLevel.hidden = NS.Client.isForever
rules.itemLevelSize.enableKey = "showItemLevel"
rules.qualityColor.enableKey = "showItemLevel"
rules.font.enableKey = "showItemLevel"

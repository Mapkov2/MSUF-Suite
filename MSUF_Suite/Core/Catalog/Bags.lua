local _, NS = ...
local B = NS.CatalogBuild

local function Available()
    local frame = _G.ContainerFrameCombinedBags
    if not frame or type(frame.EnumerateValidItems) ~= "function"
        or type(frame.UpdateItems) ~= "function"
        or type(_G.hooksecurefunc) ~= "function"
        or type(_G.GetCVar) ~= "function"
        or type(_G.SetCVar) ~= "function"
        or not _G.C_Container or type(C_Container.GetContainerItemInfo) ~= "function"
        or not _G.C_Item or type(C_Item.GetDetailedItemLevelInfo) ~= "function"
        or type(C_Item.IsEquippableItem) ~= "function" then
        return false, "This client has no supported combined bag and item level API"
    end
    local value = GetCVar("combinedBags")
    if type(_G.issecretvalue) == "function" and issecretvalue(value) then
        return false, "The combined bag setting is protected on this client"
    end
    if type(value) ~= "string" then
        return false, "This client has no combined bag setting"
    end
    return true
end

B.Module("bags", {
    title = "Bags",
    description = "One combined bag with a clear Suite background and item levels shown directly on equipment. Blizzard keeps item use, sorting, search, and bank interactions.",
    core = true, page = "suite_bags", available = Available,
    conflicts = { "EllesmereUIBags", "ElvUI", "Bagnon", "BetterBags", "AdiBags", "ArkInventory", "Inventorian" },
})

NS.BagsLookPresets = {
    [1] = { backgroundColor = "0a1522", backgroundOpacity = 96, accentColor = "5794d2" },
    [2] = { backgroundColor = "151719", backgroundOpacity = 96, accentColor = "b9ab86" },
    [3] = { backgroundColor = "14181b", backgroundOpacity = 98, accentColor = "9f8960" },
}
NS.BagsLookVisualKeys = { backgroundColor = true, backgroundOpacity = true, accentColor = true }
local initial = NS.BagsLookPresets[NS.Client.isForever and 3 or 2]
B.Section("bags", "look", "Choose a look", {
    B.Choice("look", "Style preset", NS.Client.isForever and 3 or 2,
        { "Midnight Blue", "Midnight Dark", "MSUF Forever", "Custom" }),
})
B.Section("bags", "appearance", "Window appearance", {
    B.Color("backgroundColor", "Background color", initial.backgroundColor),
    B.Number("backgroundOpacity", "Background opacity (percent)", initial.backgroundOpacity, 0, 100, 1),
    B.Color("accentColor", "Accent color", initial.accentColor),
})

B.Section("bags", "itemLevels", "Item levels", {
    B.Bool("showItemLevel", "Show item levels on equipment", true),
    B.Number("itemLevelSize", "Item level text size", 12, 8, 20),
    B.Bool("qualityColor", "Color item levels by quality", true),
    B.Font("font", "Item level font"),
})

B.Section("bags", "window", "Combined bag window", {
    B.Bool("showSessionGold", "Show gold change since login", true),
    B.Number("windowScale", "Window size", 1, 0.65, 1.5, 0.05),
    B.Bool("windowMoved", "Use custom window position", false),
    B.Number("windowX", "Horizontal offset", 0, -4096, 4096),
    B.Number("windowY", "Vertical offset", 0, -4096, 4096),
})
B.Section("bags", "reagentWindow", "Reagent bag window", {
    B.Bool("reagentWindowMoved", "Use custom reagent bag position", false),
    B.Number("reagentWindowX", "Horizontal offset", 0, -4096, 4096),
    B.Number("reagentWindowY", "Vertical offset", 0, -4096, 4096),
})

local rules = NS.SuiteCatalog.bags.rules
rules.itemLevelSize.enableKey = "showItemLevel"
rules.qualityColor.enableKey = "showItemLevel"
rules.font.enableKey = "showItemLevel"

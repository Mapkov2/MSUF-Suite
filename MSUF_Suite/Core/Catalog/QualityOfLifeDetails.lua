local _, NS = ...
local B = NS.CatalogBuild.ForAddon("MSUF_Suite_QualityOfLife")
local Number, Bool, Choice = B.Number, B.Bool, B.Choice

B.Module("threatMeter", {
    title = "Threat meter (Forever)", description = "Your group's threat on the enemy you watch, read from Blizzard's own threat data, with an optional second window for your focus.",
    optIn = true, defaultEnabled = false, page = "suite_qualityOfLife",
    available = function() return NS.Client.isForever == true, "Threat meter is available in WoW Forever" end,
    editElement = "main",
})
B.Section("threatMeter", "threat_meter", "Threat meter", {
    Choice("windows", "Watched enemies", 1, { "Target", "Focus", "Target and focus" }),
    Bool("includePets", "List group pets"),
    Choice("numberMode", "Shown value", 1, { "Threat points", "Share of the tank's threat", "Share of your pull threshold" }),
    Bool("showThreshold", "Mark where you would pull aggro", true),
    Number("pullAlert", "Alert sound at this share of your pull threshold (percent, 0 = off)", 0, 0, 100, 5),
    Number("rows", "Rows shown", 6, 1, 20), Number("width", "Width", 260, 140, 600),
    Number("rowHeight", "Row height", 20, 10, 40), Number("fontSize", "Font size", 11, 8, 24),
    Number("scale", "Scale (percent)", 100, 50, 200, 5),
    Number("mainX", "Main window X", 350, -4000, 4000), Number("mainY", "Main window Y", -150, -3000, 3000),
    Number("focusX", "Focus window X", 350, -4000, 4000), Number("focusY", "Focus window Y", 100, -3000, 3000),
})
B.Module("flightTimer", {
    title = "Flight route timer (Forever)", description = "Learn flight-master route times, show the route and request landing at the next stop.",
    optIn = true, defaultEnabled = false, page = "suite_qualityOfLife",
    available = function() return NS.Client.isForever == true, "Flight route timer is available in WoW Forever" end,
    editElement = "flight",
})
B.Section("flightTimer", "flight_route", "Flight route timer", {
    Bool("hideDisplay", "Hide the flight timer"), Bool("showStops", "Show intermediate flight stops", true),
    Bool("routePreview", "Flight route preview in the taxi tooltip", true), Bool("classColor", "Use class color"),
    Number("width", "Width", 340, 180, 700), Number("fontSize", "Font size", 12, 8, 24),
    Number("scale", "Scale (percent)", 100, 50, 200, 5),
    Number("x", "Horizontal position", 0, -4000, 4000), Number("y", "Vertical position", 180, -3000, 3000),
})

local function RetailExtras()
    if not NS.Client.modernEquipment then return false, "This feature is available only in Retail" end
    return true
end
B.Module("characterExtras", {
    title = "Character sheet additions",
    description = "A summary with gem sockets, durability, PvP item level and Great Vault and expansion buttons, durability on the model, cropped slot icons and item levels on equipment choices.",
    optIn = true, defaultEnabled = false, page = "suite_qualityOfLife", available = RetailExtras,
})
B.Section("characterExtras", "character_extras", "Summary beside the character sheet", {
    Bool("summaryPanel", "Show the summary beside the character sheet", true),
    Bool("summarySockets", "List gear with gem sockets (click to socket)", true),
    Bool("summaryDurability", "Total durability of equipped gear", true),
    Bool("summaryPvP", "PvP item level"),
    Bool("shortcutVault", "Great Vault button", true),
    Bool("shortcutExpansion", "Expansion page button", true),
    Number("summaryFontSize", "Text size of the summary and item levels", 11, 8, 22),
})
B.Section("characterExtras", "character_model", "On the character sheet", {
    Bool("modelDurability", "Total durability on the character model"),
    Number("modelDurabilityX", "Durability text X offset", 0, -200, 200),
    Number("modelDurabilityY", "Durability text Y offset", -150, -250, 250),
    Number("slotIconCrop", "Crop gear slot icons on the character and Inspect sheets (percent)", 0, 0, 20),
})
B.Section("characterExtras", "character_flyouts", "Equipment choices", {
    Bool("choiceItemLevels", "Item levels on equipment choices", true),
    Bool("slotArrowsHidden", "Hide the arrows beside gear slots"),
})
do
    local rules = NS.SuiteCatalog.characterExtras.rules
    for _, key in ipairs({ "summarySockets", "summaryDurability", "summaryPvP", "shortcutVault", "shortcutExpansion" }) do
        rules[key].enableKey = "summaryPanel"
    end
    rules.modelDurabilityX.enableKey, rules.modelDurabilityY.enableKey = "modelDurability", "modelDurability"
end
B.Module("merchantList", {
    title = "Scrollable merchant offers",
    description = "The merchant's whole stock in one scrolling list with prices, quality colors and item levels.",
    optIn = true, defaultEnabled = false, page = "suite_qualityOfLife", available = RetailExtras,
})
B.Section("merchantList", "merchant_list", "Merchant list", {
    Number("rowHeight", "Offer row height", 44, 36, 72),
})
-- inspectHovered sends inspect requests for hovered players, so the module
-- counts as automation for profile imports.
B.Module("tooltipDetails", {
    title = "Tooltip details and anchor",
    description = "General tooltips, guild rank, target, item levels and item details. MSUF unit-frame tooltip anchors remain separate.",
    optIn = true, defaultEnabled = false, page = "suite_qualityOfLife", available = RetailExtras,
    editElement = "tooltip",
})
B.Section("tooltipDetails", "tooltip_details", "Tooltip details", {
    Choice("anchor", "General tooltip anchor", 1, { "Blizzard", "Cursor", "Fixed screen corner" }),
    Number("cursorX", "Cursor X offset", 16, -500, 500),
    Number("cursorY", "Cursor Y offset", 16, -500, 500),
    Choice("growth", "Fixed corner / growth direction", 1,
        { "Bottom right / up left", "Bottom left / up right", "Top right / down left", "Top left / down right" }),
    Number("fixedX", "Fixed X offset", -24, -4000, 4000),
    Number("fixedY", "Fixed Y offset", 24, -3000, 3000),
    Bool("titles", "Show unit titles", true),
    Bool("itemLevel", "Item level for you and the unit in the Inspect window", true),
    B.Automation(Bool("inspectHovered", "Request item levels of hovered players (sends inspect requests)")),
    Bool("ownedMount", "Collection marker on native mount tooltips", true),
    Bool("guildRank", "Guild rank", true),
    Bool("unitMount", "Currently ridden mount in unit tooltips (out of combat)", true),
    Bool("unitMountOwned", "Collection marker for the hovered mount", true),
    Bool("target", "Hovered unit target", true),
    Bool("selfTarget", "Highlight targets that are you", true),
    Bool("hideHealth", "Hide unit tooltip health bar"),
    Bool("maxStack", "Item maximum stack", true),
    Bool("iconID", "Item and spell icon file IDs"),
})
do
    local rules = NS.SuiteCatalog.tooltipDetails.rules
    -- MSUF Edit Mode places the fixed-corner tooltip; the offsets stay for its
    -- mover, profile import and undo.
    rules.fixedX.hidden, rules.fixedY.hidden = true, true
    rules.inspectHovered.enableKey = "itemLevel"
    rules.selfTarget.enableKey = "target"
    rules.cursorX.requiresChoice = { key = "anchor", values = { [2] = true } }
    rules.cursorY.requiresChoice = { key = "anchor", values = { [2] = true } }
    rules.growth.requiresChoice = { key = "anchor", values = { [3] = true } }
end
B.Module("popupAttention", {
    title = "Dialogs and loot toasts",
    description = "A Suite look, font, minimum height and position for Blizzard dialogs, marked resurrection offers, the item quality written on loot toasts and gold-framed money toasts.",
    optIn = true, defaultEnabled = false, page = "suite_qualityOfLife", available = RetailExtras,
    editElement = "popup",
})
B.Section("popupAttention", "popup_attention", "Dialogs", {
    Bool("skin", "Suite look for Blizzard dialogs"),
    Bool("dialogFont", "Suite font for dialog text"),
    Number("fontSize", "Dialog text size", 14, 8, 24),
    Number("minHeight", "Minimum dialog height (0 keeps Blizzard's height)", 0, 0, 360),
    Bool("move", "Custom dialog position"),
    Number("x", "Dialog X", 0, -4000, 4000),
    Number("y", "Dialog Y", 160, -3000, 3000),
})
B.Section("popupAttention", "popup_revive", "Resurrection offers", {
    Choice("reviveCue", "Mark resurrection offers", 2, { "No mark", "Colored frame", "Colored frame and sound" }),
    Bool("reviveButton", "Frame the accept button of resurrection offers", true),
})
B.Section("popupAttention", "popup_toasts", "Loot toasts", {
    Bool("lootQualityName", "Write the item quality on loot toasts", true),
    Bool("moneyToastFrame", "Gold frame on money toasts", true),
})
do
    local rules = NS.SuiteCatalog.popupAttention.rules
    -- MSUF Edit Mode moves the dialogs; x and y stay for its mover, profile
    -- import and undo.
    rules.x.hidden, rules.y.hidden = true, true
    rules.fontSize.enableKey = "dialogFont"
end

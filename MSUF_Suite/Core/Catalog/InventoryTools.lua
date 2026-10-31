local _, NS = ...
local B = NS.CatalogBuild.ForAddon("MSUF_Suite_QualityOfLife")
local function Retail()
    if not NS.Client.isForever then return true end
    return false, "Available only in Retail"
end
local PAGES = { inventoryArchive = "suite_bags", restockPlanner = "suite_bags", craftShopping = "suite_bags", bankTransfer = "suite_bags" }
local function Module(id, title, description, retail, settings)
    B.Module(id, { title = title, description = description, optIn = true, defaultEnabled = false,
        page = PAGES[id] or "suite_qualityOfLife", available = retail and Retail or nil })
    B.Section(id, id, title, settings or {})
end
Module("inventoryArchive", "Inventory archive",
    "Search the last recorded bags and banks of your characters. Each snapshot shows when it was recorded.", false, {
    B.Bool("tooltips", "Show recorded owner counts in item tooltips", true),
    B.Number("characters", "Maximum archived characters", 30, 5, 100, 5),
})
Module("restockPlanner", "Stock targets", "Set item quantities to keep in your bags and see missing amounts and recorded bank supplies.", false, {
    B.String("targets", "Stock target data", "", 12000),
})
Module("craftShopping", "Crafting shopping list",
    "Combine tracked recipe requirements for your chosen craft quantities. Choose material alternatives explicitly.", true, {
    B.String("quantities", "Craft quantity data", "", 12000), B.String("choices", "Reagent choice data", "", 12000),
})
Module("inventoryProtection", "Never sell items", "Protect selected items and equipment sets from all Suite sale actions.", false, {
    B.String("items", "Protected item data", "", 12000), B.Bool("sets", "Protect items in equipment sets", true),
})
NS.SuiteCatalog.inventoryProtection.rules.sets.help =
    "When equipment sets exist, all equippable items are protected. Exact set membership is unavailable to this helper."
Module("bankTransfer", "Bank transfer preview", "Review matching stacks and move one selected stack with each click while your bank is open.", true)
Module("mailTemplates", "Mail templates",
    "Prepare mail for your own recorded characters with saved subjects and item quantities. Sending stays manual.", true, {
    B.String("templates", "Mail template data", "", 24000),
})
for id, keys in pairs({ restockPlanner = { "targets" }, craftShopping = { "quantities", "choices" },
    inventoryProtection = { "items" }, mailTemplates = { "templates" } }) do
    for i = 1, #keys do NS.SuiteCatalog[id].rules[keys[i]].hidden = true end
end
-- Each template names the character it mails to, so the data stays on this
-- client: ProfileIO resets personal rules in an export and a shared import.
NS.SuiteCatalog.mailTemplates.rules.templates.personal = true

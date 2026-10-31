local _, P = ...
local NS = P.Suite
P.InventoryToolGroups = {
    { id = "inventoryArchive", title = "Inventory archive", switch = "enabled", sections = { "inventoryArchive" } },
    { id = "restockPlanner", title = "Stock targets", switch = "enabled", sections = { "restockPlanner" } },
    { id = "craftShopping", title = "Crafting shopping list", switch = "enabled", sections = { "craftShopping" } },
    { id = "inventoryProtection", title = "Never sell items", switch = "enabled", sections = { "inventoryProtection" } },
    { id = "bankTransfer", title = "Bank transfer preview", switch = "enabled", sections = { "bankTransfer" } },
    { id = "mailTemplates", title = "Mail templates", switch = "enabled", sections = { "mailTemplates" } },
}
function P.BuildInventoryToolActions(ctx, body, id, section, y, width)
    local found
    for i = 1, #P.InventoryToolGroups do if P.InventoryToolGroups[i].id == id then found = true break end end
    if not found then return y end
    P.Button(ctx, body, "Open inventory tool", 16, y, width, function()
        local runtime = NS.Suite.instances[id]
        if not P.Combat() and runtime and runtime.active then runtime:Open() end
    end, function()
        local runtime = NS.Suite.instances[id]
        return not P.Combat() and runtime and runtime.active
    end, P.Meta(P.catalog[id].page, id, "action.open", "action", section))
    return y - 38
end

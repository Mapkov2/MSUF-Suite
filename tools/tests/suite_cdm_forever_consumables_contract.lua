local root = assert(arg[1], "repository root required")
-- WoW Forever consumables on the Potions and racials bar (Presets.lua,
-- Catalog.lua, EntryFill.lua, Resolve.lua, Index.lua on the shared data
-- world). Forever has no single Healthstone or health potion item: every
-- rank is an item of its own, all on one shared cooldown. This contract
-- holds:
--   * Retail keeps its two one-item healthstones and has no item family;
--   * Forever offers one Healthstone and one health potion entry, each a
--     family whose first item is its key and whose list holds every rank
--     (the Lesser Healthstone and the improved ranks among them);
--   * the family entries stand on the Potions and racials bar, hide while
--     the bags hold none, follow both bag events and go by their category's
--     title, in the plan and in the refill compare (no rebuild in combat);
--   * a learned Blizzard record of the category takes the family's place,
--     so each consumable shows once; the potion record never hides.
-- The cooldown, count and icon of the held rank are Time.lua's and are held
-- by suite_cooldown_manager_render_contract.lua ("item families") and
-- suite_cooldown_manager_contract.lua (a category of many ranks).
local World = dofile(root .. "/tools/tests/cdm_data_world.lua")
local DATA = { "Presets.lua", "GuideProfiles.lua", "Catalog.lua", "CatalogSlices.lua", "EntryFill.lua", "Resolve.lua",
    "ResolveStages.lua", "Index.lua" }
local checks = 0
local function Check(value, message)
    checks = checks + 1
    assert(value, message)
end
local function Info(id, category, spell, spellCategory, known)
    return { cooldownID = id, spellID = spell, linkedSpellIDs = {}, selfAura = false, hasAura = false, charges = false,
        isKnown = known ~= false, isInvisible = false, flags = 0, category = category, spellCategoryID = spellCategory }
end
-- The world loads as Retail; Forever reads the client once per file, so the
-- data plane loads again with the flag set. One Essential record makes the
-- catalog ready at load.
local function Load(forever)
    local W = World(root)
    if forever then
        W.NS.Client.isForever = true
        W.infos[101], W.sets[0] = Info(101, 0, 5001), { 101 }
        for _, file in ipairs(DATA) do
            assert(loadfile(root .. "/MSUF_Suite_CooldownManager/" .. file))("MSUF_Suite_CooldownManager", W.P)
        end
    end
    return W
end
local function Keys(entries)
    local out = {}
    for i = 1, #entries do out[i] = entries[i].key end
    return table.concat(out, ",")
end
local function Has(list, value)
    for i = 1, #list do
        if list[i] == value then return true end
    end
    return false
end

------------------------------------------------------------------ Retail
do
    local W = Load(false)
    local Presets, CATEGORY = W.C.Presets, W.C.Const.SPELL_CATEGORY
    Check(#Presets.CONSUMABLES == 2 and Presets.CONSUMABLES[1].item == 5512 and Presets.CONSUMABLES[2].item == 224464,
        "Retail keeps the Healthstone and the Demonic Healthstone")
    Check(#Presets.CATEGORY_ITEMS[CATEGORY.HEALTHSTONE] == 1 and #Presets.CATEGORY_ITEMS[CATEGORY.DEMONIC_HEALTHSTONE] == 1,
        "Retail healthstones are one item each")
    Check(next(Presets.STOCK) == nil, "Retail has no item family")
    Check(W.C.Catalog.ItemName(5512) == "Item 5512", "a plain item goes by its own name")
end

------------------------------------------------------------------ Forever: the lists
local W = Load(true)
local C, NS = W.C, W.NS
local CDM = NS.CDM
local Presets, Catalog, Resolve, Index = C.Presets, C.Catalog, C.Resolve, C.Index
local CATEGORY = C.Const.SPELL_CATEGORY
local STONES, POTIONS = Presets.CATEGORY_ITEMS[CATEGORY.HEALTHSTONE], Presets.CATEGORY_ITEMS[CATEGORY.HEALTH_POTION]
do
    local consumables = Presets.CONSUMABLES
    Check(#consumables == 2 and consumables[1].item == 5512 and consumables[1].category == CATEGORY.HEALTHSTONE
        and consumables[2].item == 118 and consumables[2].category == CATEGORY.HEALTH_POTION,
        "Forever offers the Healthstone, then the health potion")
    local seen = {}
    for i = 1, #consumables do
        local consumable = consumables[i]
        local items = Presets.CATEGORY_ITEMS[consumable.category]
        Check(items[1] == consumable.item, "item " .. consumable.item .. " names its family")
        Check(#items > 1 and Presets.STOCK[consumable.item] == consumable.category, "item " .. consumable.item .. " is a family")
        for j = 1, #items do
            local id = items[j]
            Check(type(id) == "number" and id > 0 and id % 1 == 0 and not seen[id], "rank " .. tostring(id) .. " listed once")
            seen[id] = true
        end
    end
    -- Every conjured rank, and the two a rank of Improved Healthstone adds.
    for _, id in ipairs({ 5512, 5511, 5509, 5510, 9421, 19004, 19005, 19006, 19007, 19008, 19009, 19010, 19011, 19012, 19013 }) do
        Check(Has(STONES, id), "healthstone rank " .. id)
    end
    Check(#STONES == 15, "fifteen healthstone items")
    for _, id in ipairs({ 118, 858, 929, 1710, 3928, 13446 }) do Check(Has(POTIONS, id), "healing potion " .. id) end
    -- Weakest first: the strongest rank the bags hold is read from the end.
    Check(STONES[#STONES] == 19013 and POTIONS[1] == 118 and Has(POTIONS, 18253), "ranks run weakest first")
    local members = 0
    for _ in pairs(Presets.STOCK) do members = members + 1 end
    Check(members == 2, "only the family's first item is its key")
end

------------------------------------------------------------------ Forever: the bar
-- No Blizzard record of either category: the families stand in.
W.Views()
C.state.specID = 63
Check(Catalog.Ready() and Catalog.Rebuild() == true, "the catalog reads")
local plans = Resolve.Build()
local E = C.entries
do
    Check(plans.ext and Keys(plans.ext.entries) == "i5512,i118", "the families stand on Potions and racials: "
        .. (plans.ext and Keys(plans.ext.entries) or "no bar"))
    local stone, potion = E.i5512, E.i118
    Check(stone.src == "i" and stone.itemID == 5512 and stone.hideEmpty == true and stone.known == true, "the Healthstone family")
    Check(potion.src == "i" and potion.itemID == 118 and potion.hideEmpty == true and potion.known == true, "the health potion family")
    Check(stone.name == "Healthstone" and potion.name == "Health potion", "a family goes by its category's title: "
        .. tostring(stone.name) .. ", " .. tostring(potion.name))
    Check(stone.texture == 700000 + 5512 and potion.texture == 700000 + 118, "and by its first item's icon until a rank is held")
    Check(Catalog.ItemName(5511) == "Item 5511", "a rank on its own keeps its own name")
    Index.Rebuild()
    Check(Has(Index.items, stone) and Has(Index.bags, stone) and Has(Index.items, potion) and Has(Index.bags, potion),
        "families follow bag contents and bag cooldowns")
    -- The refill compare reads the same name: an unchanged spellbook in
    -- combat asks for no build.
    W.combat = true
    Check(Resolve.SpellsChanged() == true and Resolve.RefillChanged() == false, "a family asked for a build in combat")
    W.combat = false
    Resolve.SpellsChanged()
end
-- Blizzard's title where the client has one.
do
    COOLDOWN_VIEWER_TOOLTIP_POTION_HEALTHSTONE_TITLE = "Gesundheitsstein"
    Check(Catalog.ItemName(5512) == "Gesundheitsstein", "Blizzard's category title names the family")
    COOLDOWN_VIEWER_TOOLTIP_POTION_HEALTHSTONE_TITLE = nil
end
-- A rank listed on a custom bar is a plain item entry; the family stays.
do
    C.views.c1.on = true
    C.lists = CDM.CleanLists({ specs = { [63] = { c1 = { "i5511" } } } })
    plans = Resolve.Build()
    Check(Keys(plans.c1.entries) == "i5511" and E.i5511.hideEmpty == false and E.i5511.name == "Item 5511",
        "a listed rank is its own item")
    Check(Keys(plans.ext.entries) == "i5512,i118", "next to the family")
    C.views.c1.on = false
    C.lists = CDM.CleanLists(nil)
    plans = Resolve.Build()
end
-- A learned Blizzard record of a category owns that consumable: the record
-- takes the family's place and hides the same way; the other family stays.
do
    W.infos[801], W.sets[5] = Info(801, 5, 6262, CATEGORY.HEALTHSTONE), { 801 }
    Check(Catalog.Rebuild() == true, "the record arrives")
    plans = Resolve.Build()
    Check(Keys(plans.ext.entries) == "b801,i118" and E.i5512 == nil, "the record replaces the family: " .. Keys(plans.ext.entries))
    Check(E.b801.hideEmpty == true and E.b801.spellCategory == CATEGORY.HEALTHSTONE, "and hides with empty bags")
    W.infos[801].isKnown = false
    Check(Catalog.Rebuild() == true, "the record is unlearned")
    plans = Resolve.Build()
    Check(Keys(plans.ext.entries) == "i5512,i118" and E.b801 == nil, "an unlearned record yields to the family again")
    -- Blizzard's health potion record replaces the potion family too, and
    -- stays a potion category: the list may miss a potion, so it never hides.
    W.infos[802], W.sets[5] = Info(802, 5, 439, CATEGORY.HEALTH_POTION), { 801, 802 }
    Check(Catalog.Rebuild() == true, "the potion record arrives")
    plans = Resolve.Build()
    Check(Keys(plans.ext.entries) == "b802,i5512" and E.i118 == nil, "the potion record replaces its family: "
        .. Keys(plans.ext.entries))
    Check(E.b802.hideEmpty == false and E.b802.spellCategory == CATEGORY.HEALTH_POTION, "and never hides")
end

print(("CDM Forever consumables: %d checks passed"):format(checks))

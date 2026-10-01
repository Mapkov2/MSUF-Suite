local _, P = ...
local S, Tr = P.S, P.Tr
local PAGE, ID = "suite_buffReminders", "buffReminders"
-- The recommended consumables use Retail's items and equipment rules.
P.Requires.modernEquipment = function() return P.Suite.Client.modernEquipment == true end

local HELP = {
    demons = "Tick every demon you want out; demons your character has not learned yet can be ticked too. A summoned demon you left unticked gets a notice, as long as one of your ticked demons can be summoned. Another look of a demon counts as that demon once you have summoned it in that look.",
    tracking = P.Help("Choose buffs and consumables to track.", "The class buff is included only when your character knows it. Enter self-buff spell IDs separated by spaces or commas. For a consumable, enter item ID:aura ID; separate pairs with commas. Up to 12 total reminders are shown. Weapon enchant items use the main-hand or off-hand enchant state."),
    recommended = P.Help("Reminders for missing poisons and consumables.", "Mainline covers Rogue poisons, this season's flasks, augment runes and weapon oils, and the Well Fed food buff. Each category clicks the first matching item in your bags; an item you enter for it is tried first. Food is found in your bags by the game's eating spells: the food you enter comes first, then the newest one. With the gray reminder on, a category with nothing left stays visible without a click action. Assassination prefers Deadly Poison; Outlaw and Subtlety prefer Instant Poison. Dragon-Tempered Blades allows two poisons per category. Oils target equipped weapons; known Shaman or Paladin imbues suppress automatic oils."),
    visibility = P.Help("Show missing or expiring buffs outside combat.", "Reminders appear only outside combat. The advance setting also shows active buffs, food and weapon enchants when their remaining time reaches the chosen number of minutes; 0 shows only missing effects. A single scheduled wakeup handles the next threshold. Reminders hide in arenas and battlegrounds, where aura data can be restricted."),
    appearance = "Click a reminder to cast its spell or use its item. Aura checks run on relevant events; there is no repeating scan.",
    position = "Move the reminder row in MSUF Edit Mode or set its offsets here.",
    readycheck = "When a ready check starts outside combat and your mana as a healer is low, a short note shows how much you have; it turns red below half of your limit. Only your own mana is read.",
}
HELP.visibility = P.Help("Show missing or expiring buffs outside combat.", "Pick the places where reminders may show; arenas and battlegrounds never show them. Before a keystone starts, buffs can be asked to last the dungeon's timer or a number of minutes; once the key starts, the normal warning time applies again. One scheduled wakeup handles the next expiry.")

-- { catalog section, accordion title } in page order.
local SECTIONS = {
    { "tracking", "What to remind" },
    { "demons", "Warlock demon choice" },
    { "recommended", "Recommended consumables (Mainline)" },
    { "visibility", "When to show" },
    { "readycheck", "Ready check" },
    { "classVisibility", "Class and group reminders" },
    { "personalVisibility", "Personal spell reminders" },
    { "consumableVisibility", "Consumable and weapon reminders" },
    { "appearance", "Icons" },
    { "position", "Position" },
}

P.Gates[ID] = function(rule)
    if rule.key == "campfireBuff" then return P.Suite.Client.isForever == true end
    return true
end

-- The map the player stands on joins the map potion's list once.
local function AddPotionMap()
    local map = C_Map.GetBestMapForUnit("player")
    if not P.Suite.Public(map) or type(map) ~= "number" or map <= 0 then return end
    local value = P.Get(ID, "mapPotionMaps")
    for token in value:gmatch("%d+") do
        if tonumber(token) == map then return end
    end
    P.Set(ID, "mapPotionMaps", value == "" and tostring(map) or value .. "," .. map)
end

local function Build(ctx)
    local b = P.W.PageBuilder(ctx)
    P.ModuleCard(ctx, b, PAGE, ID, {
        { "Edit Mode", function() P.OpenEditMode(ID, "buffs") end,
            function() return P.EditModeReady() and S.Status(ID) == "Active" end, key = "edit" },
        { "Add this map to the potion maps", AddPotionMap, nil, key = "potionMap" },
    })
    for _, section in ipairs(SECTIONS) do
        if section[1] ~= "recommended" or P.Requires.modernEquipment() then
            P.RuleSection(ctx, b, PAGE, ID, PAGE .. "_" .. section[1], Tr(section[2]),
                P.SectionRules(ID, section[1]), { help = HELP[section[1]], open = section[1] == "tracking" })
        end
    end
end

P.RegisterPage({ key = PAGE, label = "Buff Reminders", title = "Buff Reminders", build = Build, icon = { 7, 1 },
    aliases = { "buffreminders", "buffs", "reminders", "consumables" } })

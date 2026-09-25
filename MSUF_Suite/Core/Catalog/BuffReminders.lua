local _, NS = ...
local B = NS.CatalogBuild
local Bool, Number, Choice, String, Color = B.Bool, B.Number, B.Choice, B.String, B.Color

local function Available()
    local auras = _G.C_UnitAuras
    if type(_G.RegisterStateDriver) ~= "function" or type(_G.UnregisterStateDriver) ~= "function" or not auras or
        (type(auras.GetPlayerAuraBySpellID) ~= "function" and type(auras.GetAuraDataByIndex) ~= "function") then
        return false, "This client lacks the aura or secure visibility API"
    end
    return true
end

B.Module("buffReminders", {
    title = "Buff reminders",
    description = "Clickable reminders for missing personal buffs, chosen aura spells, consumables and weapon enchants. Checks only while out of combat.",
    optIn = true, page = "suite_buffReminders", available = Available,
    conflicts = { "EllesmereUIAuraBuffReminders" },
})

local id = "buffReminders"
-- A global look recolors the icon border from its palette.
NS.SuiteCatalog[id].look = {
    extra = function(values, lookIndex)
        values.borderColor = NS.DataTextLooks[lookIndex].border
    end,
}
B.Section(id, "tracking", "What to remind", {
    Bool("classBuff", "Remind me of my known class raid buff", true),
    String("spellIDs", "Additional self-buff spell IDs", "", 240),
    String("items", "Consumables (item ID:aura ID)", "", 320),
    String("mainHandItem", "Main-hand enchant item ID", "", 10),
    String("offHandItem", "Off-hand enchant item ID", "", 10),
})
B.Section(id, "recommended", "Recommended consumables (Mainline)", {
    Bool("autoRoguePoisons", "Rogue poisons for my specialization", true),
    Bool("autoFlask", "Flask from my bags", true),
    Bool("autoFood", "Food from my bags", true),
    Bool("autoRune", "Augment rune from my bags", true),
    Bool("autoWeapon", "Weapon oils for equipped weapons", true),
}, { requires="buffRemindersMainline" })
B.Section(id, "visibility", "When to show", {
    Bool("instancesOnly", "Show only in dungeons and raids", false),
    Bool("hideMounted", "Hide while mounted", true),
    Number("remindBeforeMinutes", "Remind before expiration (minutes)", 5, 0, 60),
})
B.Section(id, "appearance", "Icons", {
    Number("size", "Icon size", 38, 22, 72),
    Number("spacing", "Icon spacing", 5, 0, 20),
    Number("columns", "Icons per row", 6, 1, 12),
    Color("borderColor", "Border color", NS.Client.isForever and "d8b66a" or "e8b855"),
})
B.Section(id, "position", "Position", {
    Choice("point", "Screen anchor", 2, { "Center", "Top" }),
    Number("x", "Horizontal offset", 0, -4000, 4000),
    Number("y", "Vertical offset", -145, -3000, 3000),
})

local rules = NS.SuiteCatalog[id].rules
rules.spellIDs.spells = true
rules.mainHandItem.items = true
rules.offHandItem.items = true

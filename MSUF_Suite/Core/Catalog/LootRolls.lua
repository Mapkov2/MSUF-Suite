local _, NS = ...
local B = NS.CatalogBuild.ForAddon("MSUF_Suite_QualityOfLife")
local Number, Bool, Choice = B.Number, B.Bool, B.Choice

B.Module("lootRolls", {
    title = "Loot roll window",
    description = "Compact manual loot rolls with player counts, a countdown and results. Gamepad mode keeps Blizzard's roll window.",
    optIn = true, defaultEnabled = false, page = "suite_qualityOfLife", editElement = "lootrolls",
    conflicts = { "XLoot_Group" },
})
B.Section("lootRolls", "loot_rolls", "Loot roll window", {
    Number("width", "Window width", 380, 300, 600, 5),
    Number("rowHeight", "Row height", 58, 48, 84),
    Number("rowGap", "Space between rows", 4, 0, 12),
    Number("maxRows", "Visible loot rolls", 6, 2, 12),
    Choice("growth", "Loot roll growth direction", 1, { "Down", "Up" }),
    Number("scale", "Scale (percent)", 100, 50, 150, 5),
    B.Font("font", "Font"),
    Number("fontSize", "Font size", 12, 9, 18),
    Bool("showItemLevel", "Show item level", true),
    Bool("showBind", "Show bind-on-pickup status", true),
    Bool("showCounts", "Show roll counts", true),
    Bool("showResults", "Keep loot roll results visible", true),
    Number("resultSeconds", "Loot result duration (seconds)", 8, 2, 30),
    Bool("urgentTimer", "Highlight expiring loot rolls"),
    Number("urgentSeconds", "Loot roll warning threshold (seconds)", 10, 3, 30),
    Choice("point", "Screen anchor", 5, NS.AnchorLabels),
    Number("x", "Horizontal position", 0, -4000, 4000),
    Number("y", "Vertical position", 160, -3000, 3000),
})
NS.AddQoLVisualStyle("lootRolls", "loot_rolls", "Loot roll window")
NS.AddQoLTextStyle("lootRolls", "loot_rolls", "Loot roll window")
-- Row elements the preview edits. <id>OffsetX/Y shift an element from its
-- default place in every row (the preview's X/Y bar; hidden from the grid).
-- <id>Size is its icon, text, bar or button size, 0 keeping the automatic one;
-- the preview shows it for the selected element (lootElement), not the grid.
NS.LootRollElements = {
    { id = "icon", label = "Icon", maxSize = 80 }, { id = "name", label = "Name", maxSize = 30 },
    { id = "details", label = "Details", maxSize = 30 }, { id = "result", label = "Result", maxSize = 30 },
    { id = "remaining", label = "Remaining time", maxSize = 30 },
    { id = "timer", label = "Timer bar", maxSize = 12 }, { id = "buttons", label = "Buttons", maxSize = 40 },
}
for _, element in ipairs(NS.LootRollElements) do
    local name = NS.Text(element.label)
    element.xKey, element.yKey, element.sizeKey = element.id .. "OffsetX", element.id .. "OffsetY", element.id .. "Size"
    B.Add("lootRolls", Number(element.xKey, NS.Text("%s: Horizontal offset"):format(name), 0, -200, 200), "loot_rolls", "Loot roll window")
    B.Add("lootRolls", Number(element.yKey, NS.Text("%s: Vertical offset"):format(name), 0, -200, 200), "loot_rolls", "Loot roll window")
    local size = Number(element.sizeKey, NS.Text("%s: Size (0 = automatic)"):format(name), 0, 0, element.maxSize)
    size.lootElement = element.id
    B.Add("lootRolls", size, "loot_rolls", "Loot roll window")
end
local rules = NS.SuiteCatalog.lootRolls.rules
rules.resultSeconds.enableKey = "showResults"
rules.urgentSeconds.enableKey = "urgentTimer"
for _, key in ipairs({ "point", "x", "y" }) do rules[key].hidden = true end
for _, element in ipairs(NS.LootRollElements) do rules[element.xKey].hidden, rules[element.yKey].hidden = true, true end

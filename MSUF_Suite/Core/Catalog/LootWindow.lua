local _, NS = ...
local B = NS.CatalogBuild.ForAddon("MSUF_Suite_QualityOfLife")
local Number, Bool, Choice = B.Number, B.Bool, B.Choice

-- A frameless loot list in place of Blizzard's loot window: one row per slot
-- with its icon, name, a quality or quest line and the stack or money amount.
-- Blizzard's window keeps running unseen (Escape, sounds, bind confirmations
-- and closing stay native). The feed lists what actually reached the bags.
local lootWindow = B.Module("lootWindow", {
    title = "Minimal loot window",
    description = "A frameless loot list with icons, names and quality in place of Blizzard's loot window, "
        .. "and a short feed of what you looted.",
    optIn = true, defaultEnabled = false, page = "suite_qualityOfLife", editElement = "lootfeed",
    conflicts = { "XLoot_Frame", "Butsu" },
})
B.Section("lootWindow", "loot_window", "Loot window", {
    Bool("window", "Replace Blizzard's loot window", true),
    Choice("position", "Loot window position", 1, { "Cursor", "Fixed position" }),
    Number("width", "Window width", 240, 160, 420, 5),
    Number("rowHeight", "Row height", 32, 20, 56),
    Number("rowGap", "Space between rows", 2, 0, 16),
    Number("maxRows", "Visible loot slots", 8, 3, 16),
    Choice("growth", "Growth direction", 1, { "Down", "Up" }),
    Number("fadeIn", "Fade in (seconds)", .15, 0, 2, .05),
    Number("fadeOut", "Fade out (seconds)", .20, 0, 2, .05),
    Number("scale", "Scale (percent)", 100, 50, 200, 5),
    B.Font("font", "Font"),
    Choice("point", "Screen anchor", 5, NS.AnchorLabels),
    Number("x", "Horizontal position", -260, -4000, 4000),
    Number("y", "Vertical position", 80, -3000, 3000),
})
NS.AddQoLVisualStyle("lootWindow", "loot_window", "Loot window")
NS.AddQoLTextStyle("lootWindow", "loot_window", "Loot window", 80)
B.Section("lootWindow", "loot_feed", "Loot feed", {
    Bool("feed", "Show what you looted", true),
    Number("feedRows", "Visible feed entries", 6, 1, 12),
    Number("feedSeconds", "Feed entry duration (seconds)", 6, 2, 30),
    Choice("feedGrowth", "Feed growth direction", 2, { "Down", "Up" }),
    Number("feedFadeIn", "Fade in (seconds)", .15, 0, 2, .05),
    Number("feedFadeOut", "Fade out (seconds)", .25, 0, 2, .05),
    Number("feedQuality", "Minimum item quality", 0, 0, 6),
    Bool("feedMoney", "Show money in the feed", true),
    Choice("feedPoint", "Screen anchor", 5, NS.AnchorLabels),
    Number("feedX", "Horizontal position", 300, -4000, 4000),
    Number("feedY", "Vertical position", -60, -3000, 3000),
})

-- The editable parts of every row. Preview drags move an element in all rows.
lootWindow.layers = {
    { "background", "Background", { Number("backgroundOpacity", "Background opacity (percent)", 70, 0, 100, 5) },
        shown = false, fixed = true },
    { "icon", "Icon", { Number("iconSize", "Icon size", 24, 12, 48), Bool("iconBorder", "Quality border", true) } },
    { "name", "Name", { Number("nameSize", "Font size", 12, 8, 24), Bool("nameQuality", "Color names by quality", true) } },
    { "subtitle", "Quality line", { Number("subtitleSize", "Font size", 10, 7, 20) } },
    { "count", "Amount", { Number("countSize", "Font size", 12, 8, 24) } },
}
NS.AddQoLLayers("lootWindow", "loot_window_", lootWindow.layers, 120, 40)

local rules = lootWindow.rules
-- Plain text with a soft shadow suits a list without a frame better than an outline.
rules.fontOutline.default = 1
for _, key in ipairs({ "point", "x", "y", "feedPoint", "feedX", "feedY" }) do rules[key].hidden = true end
for _, layer in ipairs(lootWindow.layers) do
    layer.rules[1].label = layer[2]
    if not layer.fixed then
        local key = layer[1]
        rules[key .. "X"].hidden, rules[key .. "Y"].hidden = true, true
    end
end
for _, key in ipairs({ "position", "width", "rowHeight", "rowGap", "maxRows", "growth", "fadeIn", "fadeOut" }) do
    rules[key].enableKey = "window"
end
for _, key in ipairs({ "feedRows", "feedSeconds", "feedGrowth", "feedQuality", "feedMoney", "feedFadeIn", "feedFadeOut" }) do
    rules[key].enableKey = "feed"
end

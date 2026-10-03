local _, NS = ...
local B = NS.CatalogBuild.ForAddon("MSUF_Suite_QualityOfLife")
local Number, Bool, Choice = B.Number, B.Bool, B.Choice

B.Module("selfCombatText", {
    title = "Own combat text",
    description = "Movable incoming damage and healing with native animations.",
    optIn = true, defaultEnabled = false, page = "suite_qualityOfLife",
    editElement = "text", cvars = { enableFloatingCombatText = true },
    available = function()
        local api = C_CombatText
        if type(api) ~= "table" or type(api.GetCurrentEventInfo) ~= "function"
            or type(api.GetActiveUnit) ~= "function" or type(api.SetActiveUnit) ~= "function"
            or type(UnitHasVehicleUI) ~= "function" or not NS.Client.SupportsEvent("COMBAT_TEXT_UPDATE") then
            return false, "Combat text is unavailable on this client"
        end
        return true
    end,
})
B.Section("selfCombatText", "self_combat_text", "Own combat text", {
    Bool("showDamage", "Show incoming damage", true),
    Bool("showHealing", "Show incoming healing", true),
    Number("fontSize", "Font size", 20, 10, 48),
    Number("critScale", "Critical text size (percent)", 130, 100, 200, 5),
    Number("duration", "Text duration (seconds)", 2, 1, 5, .1),
    Number("maxMessages", "Maximum visible messages", 12, 1, 20),
    Choice("direction", "Scroll direction", 1, { "Up", "Down" }),
    Number("distance", "Scroll distance", 96, 24, 240, 4),
    Number("width", "Display width", 320, 180, 600),
    B.Color("damageColor", "Incoming damage color", "ff7373"),
    B.Color("healColor", "Incoming healing color", "73e6a3"),
    Choice("point", "Screen anchor", 5, NS.AnchorLabels),
    Number("x", "Horizontal position", -220, -4000, 4000),
    Number("y", "Vertical position", -120, -3000, 3000),
})

local _, NS = ...
local B = NS.CatalogBuild.ForAddon("MSUF_Suite_QualityOfLife")
local Number, Bool, Choice = B.Number, B.Bool, B.Choice

B.Module("selfCombatText", {
    title = "Own combat text",
    description = "Movable incoming damage and healing with native animations.",
    optIn = true, defaultEnabled = false, page = "suite_qualityOfLife",
    editElement = "text", cvars = { enableFloatingCombatText = true },
    -- Each of these owns the same floating combat text and its CVar.
    conflicts = { "MikScrollingBattleText", "Parrot", "xCT+" },
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

local DAMAGE_CVAR = "floatingCombatTextCombatDamage_v2"
B.Module("floatingCombatText", {
    title = "Floating combat text",
    description = "Show damage above enemy nameplates.",
    defaultEnabled = NS.Client.isForever == true, page = "suite_qualityOfLife",
    cvars = { [DAMAGE_CVAR] = true },
    conflicts = { "ForeverCombatText", "BetterDamageText", "NameplateSCT" },
    available = function()
        if not NS.Client.isForever then return false, "Available only in WoW Forever" end
        if not NS.Client.SupportsEvent("UNIT_COMBAT") then
            return false, "Combat text is unavailable on this client"
        end
        return true
    end,
})
B.Section("floatingCombatText", "floating_combat_text", "Floating combat text", {
    B.Tooltip(Choice("hitSource", "Hits to display", 1, { "Your hits (estimated)", "All hits on enemies" }),
        "Estimates your hits on your target from swings and harmful casts. Simultaneous hits can be misidentified."),
    Bool("hideBlizzard", "Hide Blizzard damage numbers", true),
    B.Font("font", "Font"),
    Number("fontSize", "Font size", 28, 10, 48),
    Number("critScale", "Critical text size (percent)", 140, 100, 200, 5),
    Number("duration", "Text duration (seconds)", 0.9, 0.4, 2, 0.1),
    Number("offset", "Vertical offset", 5, 0, 60),
})

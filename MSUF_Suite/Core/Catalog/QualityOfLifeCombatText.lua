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
local Feed = { WorldTextScale = "WorldTextScale_v2" }
NS.FloatingCombatFeed = Feed

function Feed.Enemy()
    return NS.Client.SupportsEvent("UNIT_COMBAT")
end

function Feed.Gains()
    return NS.Client.SupportsEvent("COMBAT_TEXT_UPDATE")
end

function Feed.Experience()
    return NS.Client.SupportsEvent("PLAYER_XP_UPDATE")
end

function Feed.LevelUp()
    return NS.Client.SupportsEvent("PLAYER_LEVEL_UP")
end

B.Module("floatingCombatText", {
    title = "Floating combat text",
    description = "Scroll enemy hits and gains around your character or above enemy nameplates.",
    defaultEnabled = true, page = "suite_qualityOfLife",
    cvars = { [DAMAGE_CVAR] = true, [Feed.WorldTextScale] = true },
    conflicts = { "ForeverCombatText", "BetterDamageText", "NameplateSCT" },
    available = function()
        if not (Feed.Enemy() or Feed.Gains() or Feed.Experience()) then
            return false, "Combat text is unavailable on this client"
        end
        return true
    end,
})
local SIDES = { "Enemy nameplate", "Left", "Right" }
local SCREEN_SIDES = { "Left", "Right" }
local forever = NS.Client.isForever
B.Section("floatingCombatText", "floating_combat_text", "Appearance", {
    B.Font("font", "Font"),
    Number("fontSize", "Font size", 28, 10, 48),
    Number("critScale", "Critical text size (percent)", 140, 100, 200, 5),
    Number("duration", "Text duration (seconds)", 0.9, 0.4, 2, 0.1),
    Choice("scrollStyle", "Scroll style", 1, { "Up", "Down", "Outward" }),
    Number("travel", "Scroll distance", 42, 16, 96, 2),
    Number("sideOffset", "Distance from center", 124, 48, 360, 2),
    Number("screenY", "Vertical position", 0, -220, 220, 2),
})
B.Section("floatingCombatText", "floating_combat_text_hits", "Enemy hits", {
    B.Tooltip(Choice("hitSource", "Hits to display", forever and 1 or 3,
        { forever and "Your hits (estimated)" or "Your spell hits (estimated)",
            "All hits on enemies", "All hits on current target" }),
        "Estimated hits use your attack events. All hits can include other players' damage."),
    Bool("showHits", "Show enemy damage", true),
    Choice("hitSide", "Enemy damage placement", forever and 1 or 3, SIDES),
    B.Color("hitColor", "Enemy damage color", "ffd100"),
    Bool("showAvoidance", "Show enemy dodge, parry and misses", true),
    Choice("avoidSide", "Enemy avoidance placement", 2, SIDES),
    B.Color("avoidColor", "Enemy avoidance color", "fae0a0"),
    Bool("hideBlizzard", "Hide Blizzard damage numbers", forever),
    Number("offset", "Vertical offset", 5, 0, 60),
})
local xpGains = B.Tooltip(Bool("showXP", "XP gains (Suite)", false),
    "Show Suite XP in addition to Blizzard's XP text.")
local xpPlacement = Choice("xpSide", "XP placement", 1, { "Progression placement", "Left", "Right" })
xpGains.searchSection, xpPlacement.searchSection = "XP", "XP"
if forever then
    local worldText = B.Tooltip(Bool("hideBlizzardWorldText", "Hide Blizzard world text", false),
        "Hide Blizzard's floating damage, healing and XP in the world. Suite XP stays on while this is active.")
    B.Add("floatingCombatText", worldText, "floating_combat_text_gains", "Gains and notifications")
end
B.Section("floatingCombatText", "floating_combat_text_gains", "Gains and notifications", {
    xpGains,
    xpPlacement,
    Bool("showLevelUp", "Show level-up notifications", true),
    Bool("showReputation", "Show reputation changes", true),
    Bool("showHonor", "Show honor gains", false),
    Choice("gainSide", "Progression placement", 2, SCREEN_SIDES),
    B.Color("gainColor", "Progression color", "9be9b0"),
    Bool("showPower", "Show resource gains", false),
    Choice("powerSide", "Resource placement", 2, SCREEN_SIDES),
    B.Color("powerColor", "Resource gain color", "8ed8ff"),
    Bool("showCombatState", "Show combat entry and exit", false),
    Choice("combatSide", "Combat state placement", 1, SCREEN_SIDES),
    B.Color("combatColor", "Combat state color", "ffac77"),
})

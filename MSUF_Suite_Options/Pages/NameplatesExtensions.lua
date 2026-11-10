local _, P = ...
local UI = {}
P.NameplatesExtensions = UI
local X = P.Suite.NameplateExtensions

local function AddHelp(help)
    if not help then return end
    help.castFeedback = P.Help("Show timed feedback when Blizzard reports an interrupted cast.",
        "The duration controls the feedback display. The interrupt event provides the interrupter but no enemy school-lockout duration.")
    help.relativeCasts = P.Help("Place the native spell icon and raid marker relative to the name, health bar or castbar.",
        "Existing offsets still apply. Foreground raises the castbar above health art. Protected layout changes wait until combat ends.")
    help.combatExtensions = P.Help("Emphasize focused, casting and low-health enemies. Focus reminders apply to casters and lieutenants.",
        "Reminders appear while you have no hostile focus. The pulse uses your health threshold. Protected scale changes wait until combat ends.")
    help.plateClickArea = P.Help("Adjust the clickable area of native nameplates.",
        "Hit testing stays inside native plate bounds. Changes wait for Blizzard's hit-test permission. Forbidden friendly plates use Blizzard's rules.")
    help.plateRange = P.Help("Select a known spell by ID to check enemy range.",
        "Invalid checks use unknown opacity. Spell range and camera occlusion provide no per-unit spell line-of-sight result.")
    help.plateContext = P.Help("Choose opacity, scale and visibility separately for each unit type.",
        "Location rules cover world, dungeon, raid and PvP. Cast rules follow native events. Unknown unit or location data keeps the plate visible.")
    help.extraPlateText = P.Help("Add four labels using native unit, quest-tooltip, threat, resource and Mythic+ data.",
        "NPC titles use tooltip subtitles. Threat differences need public values for you and the tank. Missing data can show a question mark.")
    help.targetResources = P.Help("Attach Retail's native class mechanic bar to the enemy target's nameplate.",
        "Supported classes need an active native mechanic bar. WoW Forever excludes these bars. Protected parent changes wait until combat ends.")
    help.threatDetail = P.Help("Focus > safe tank threat > other tank > threat > tapped > quest > neutral > NPC type.",
        "Separate orange warnings use native threat level 2. Level 1 keeps the usual warning color. Tracked aura colors can cover the role tint.")
    help.plateIdentity = P.Help("Show class and faction icons beside player names when identity data is public.",
        "Blizzard's classification marker continues to show supported flag, cart and orb carriers. Restricted identities hide the extra icons.")
end

local function Gates()
    local previous = P.Gates.nameplates
    P.Gates.nameplates = function(rule, key)
        if key == "targetClassResources" then
            local available, reason = X.Capability("resources")
            if not available then return false, P.Tr(reason) end
        end
        if rule.section == "castExtensions" or rule.section == "combatExtensions" or rule.section == "plateInteraction"
            or rule.section == "plateContext" or rule.section == "threatDetail" or rule.section == "plateIdentity"
            or rule.section and rule.section:match("^extraText%d$") then
            if P.Get("nameplates", "look") == 2 then
                return false, P.Tr("Choose a nameplate look other than Blizzard under Look.")
            end
        end
        if previous then return previous(rule, key) end
        return true
    end
end

local function ContextSection()
    local spec = { key = "plateContext", area = "general", title = "Unit types and locations", tabs = {
        { id = "enabled", label = "General", help = "plateContext", keys = { "plateContextEnabled" } },
    } }
    for _, kind in ipairs(X.Kinds) do
        local keys = { kind.key .. "Opacity", kind.key .. "Scale", kind.key .. "CastVisibility" }
        for _, location in ipairs(X.Contexts) do keys[#keys + 1] = kind.key .. location.key .. "Visible" end
        spec.tabs[#spec.tabs + 1] = { id = kind.key, label = kind.label, keys = keys }
    end
    return spec
end

local function TextSection()
    local spec = { key = "extraPlateText", area = "general", title = "Extra nameplate text", tabs = {}, colors = {} }
    for i = 1, 4 do
        local key = "extraText" .. i
        spec.tabs[#spec.tabs + 1] = { id = key, label = P.Tr("Text %d"):format(i), help = "extraPlateText",
            keys = { key .. "Source", key .. "Side", key .. "Anchor", key .. "X", key .. "Y", key .. "Size", key .. "Unknown" } }
        spec.colors[#spec.colors + 1] = key .. "Color"
    end
    return spec
end

function UI.Append(sections, help)
    AddHelp(help)
    sections[#sections + 1] = { key = "castExtensions", area = "casts", title = "Cast feedback and relative anchors",
        colors = { "interruptFeedbackColor" }, tabs = {
            { id = "feedback", label = "Interrupted casts", help = "castFeedback", keys = {
                "interruptFeedbackEnabled", "interruptFeedbackDuration", "interruptFeedbackFlash", "interruptFeedbackWho" } },
            { id = "enemy", label = "Enemy", help = "relativeCasts", keys = {
                "enemyNameDuringCast", "enemyNameCastAlpha", "enemyCastForeground", "enemyCastIconRelativeAnchor", "enemyRaidRelativeAnchor" } },
            { id = "friendly", label = "Friendly", help = "relativeCasts", keys = {
                "friendlyNameDuringCast", "friendlyNameCastAlpha", "friendlyCastForeground", "friendlyCastIconRelativeAnchor",
                "friendlyRaidRelativeAnchor" } },
        } }
    sections[#sections + 1] = { key = "combatExtensions", area = "enemies", title = "Combat emphasis",
        colors = { "focusReminderColor", "executePulseColor" }, keys = {
            "focusScaleEnabled", "focusScalePercent", "castingScaleEnabled", "castingScalePercent", "focusReminderEnabled",
            "executePulseEnabled", "executePulsePercent", "executePulseAlpha" } }
    sections[#sections + 1] = { key = "targetResources", area = "general", title = "Target class resources", keys = { "targetClassResources" } }
    sections[#sections + 1] = { key = "threatDetail", area = "colors", title = "Threat warning detail",
        keys = { "enemyThreatTransitionEnabled" }, colors = { "enemyThreatTransitionColor" } }
    sections[#sections + 1] = { key = "plateIdentity", area = "enemies", title = "Player identity icons", tabs = {
        { id = "enemy", label = "Enemy", help = "plateIdentity", keys = {
            "enemyIdentityIcons", "enemyIdentityIconSize", "enemyIdentityIconX", "enemyIdentityIconY" } },
        { id = "friendly", label = "Friendly", help = "plateIdentity", keys = {
            "friendlyIdentityIcons", "friendlyIdentityIconSize", "friendlyIdentityIconX", "friendlyIdentityIconY" } },
    } }
    sections[#sections + 1] = { key = "plateInteraction", area = "general", title = "Click area and spell range", tabs = {
        { id = "clicks", label = "Click area", help = "plateClickArea", keys = {
            "plateClickboxEnabled", "plateClickboxWidth", "plateClickboxHeight", "friendlyPlateClickThrough" } },
        { id = "range", label = "Spell range", help = "plateRange", keys = {
            "plateRangeEnabled", "plateRangeSpell", "plateRangeAlpha", "plateRangeUnknownAlpha", "plateRangeText" } },
    } }
    sections[#sections + 1] = ContextSection()
    sections[#sections + 1] = TextSection()
end

Gates()

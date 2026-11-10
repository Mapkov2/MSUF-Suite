local _, NS = ...
-- Shared settings and presentation contracts. This file has no runtime
-- subscriptions, timers or frames. Unknown unit facts stay unknown.
local X = {}
NS.NameplateExtensions = X

X.Kinds = {
    { key = "enemyNpc", label = "Enemy NPC" },
    { key = "enemyPlayer", label = "Enemy player" },
    { key = "friendlyNpc", label = "Friendly NPC" },
    { key = "friendlyPlayer", label = "Friendly player" },
}
X.Contexts = {
    { key = "World", label = "Open world" },
    { key = "Dungeon", label = "Dungeon" },
    { key = "Raid", label = "Raid" },
    { key = "PvP", label = "Battleground or arena" },
}
X.TextSources = { "Off", "Unit target", "Quest objective progress", "Guild name", "NPC title",
    "Threat percentage", "Threat difference to current tank", "Current / maximum resource", "Absorb amount",
    "Mythic+ enemy forces" }
X.TextAnchors = { "Above name", "Below health bar", "Inside health bar", "Left of health bar", "Right of health bar" }
X.RaidAnchors = { "Blizzard anchor", "Left of name", "Right of name", "Above name", "Inside health bar" }
X.CastIconAnchors = { "Blizzard anchor", "Left of castbar", "Right of castbar", "Left of health bar", "Right of health bar" }
X.IdentityIcons = { "Off", "Class icon", "Faction icon", "Class and faction icons" }
X.RangeLabels = { "In range", "Out of range", "Range unknown" }

function X.RoleLabel(role)
    if not role then return nil end
    if role == "ThreatTransition" then return "Orange threat warning" end
    for _, entry in ipairs(NS.NameplateStyle.Roles) do
        if entry.key == role then return entry.label end
    end
end

local function Number(value, default, minimum, maximum)
    if not NS.Finite(value) then return default end
    return math.max(minimum, math.min(maximum, value))
end
X.Number = Number

function X.Kind(friend, player)
    if NS.IsSecret(friend) or NS.IsSecret(player) then return end
    if type(friend) ~= "boolean" or type(player) ~= "boolean" then return end
    if friend then return player and "friendlyPlayer" or "friendlyNpc" end
    return player and "enemyPlayer" or "enemyNpc"
end

function X.Context(instanceType)
    if NS.IsSecret(instanceType) then return end
    if instanceType == "none" then return "World" end
    if instanceType == "party" or instanceType == "scenario" then return "Dungeon" end
    if instanceType == "raid" then return "Raid" end
    if instanceType == "pvp" or instanceType == "arena" then return "PvP" end
end

function X.Range(value)
    if NS.IsSecret(value) then return 3 end
    if value == true then return 1 end
    if value == false then return 2 end
    return 3
end

local function Side(c, prefix)
    return {
        nameCast = Number(c[prefix .. "NameDuringCast"], 1, 1, 3),
        nameAlpha = Number(c[prefix .. "NameCastAlpha"], 35, 0, 100) / 100,
        raidAnchor = Number(c[prefix .. "RaidRelativeAnchor"], 1, 1, #X.RaidAnchors),
        iconAnchor = Number(c[prefix .. "CastIconRelativeAnchor"], 1, 1, #X.CastIconAnchors),
        foreground = c[prefix .. "CastForeground"] == true,
        identity = Number(c[prefix .. "IdentityIcons"], 1, 1, #X.IdentityIcons),
        identitySize = Number(c[prefix .. "IdentityIconSize"], 14, 8, 40),
        identityX = Number(c[prefix .. "IdentityIconX"], -3, -2048, 2048),
        identityY = Number(c[prefix .. "IdentityIconY"], 0, -2048, 2048),
    }
end

local function Slots(c, plan)
    for i = 1, 4 do
        local key = "extraText" .. i
        local source = Number(c[key .. "Source"], 1, 1, #X.TextSources)
        if source > 1 then
            plan.slots[#plan.slots + 1] = {
                index = i, source = source, side = Number(c[key .. "Side"], 1, 1, 3),
                anchor = Number(c[key .. "Anchor"], i == 1 and 1 or 2, 1, #X.TextAnchors),
                x = Number(c[key .. "X"], 0, -2048, 2048),
                y = Number(c[key .. "Y"], (i - 1) * -12, -2048, 2048),
                size = Number(c[key .. "Size"], 10, 6, 32), color = c[key .. "Color"] or "ffffff",
                unknown = c[key .. "Unknown"] == true,
            }
            plan.sources[source] = true
        end
    end
end

function X.Plan(c)
    local plan = {
        enemy = Side(c, "enemy"), friendly = Side(c, "friendly"), slots = {}, sources = {}, kinds = {},
        contextEnabled = c.plateContextEnabled == true, interrupt = c.interruptFeedbackEnabled == true,
        interruptDuration = Number(c.interruptFeedbackDuration, 1.2, .1, 5),
        interruptColor = c.interruptFeedbackColor or "ff5050", interruptFlash = c.interruptFeedbackFlash == true,
        interruptWho = c.interruptFeedbackWho ~= false, focusReminder = c.focusReminderEnabled == true,
        focusColor = c.focusReminderColor or "ffb833", execute = c.executePulseEnabled == true,
        executeAt = Number(c.executePulsePercent, 20, 1, 99) / 100, executeColor = c.executePulseColor or "ff3030",
        executeAlpha = Number(c.executePulseAlpha, 60, 0, 100) / 100,
        focusScale = c.focusScaleEnabled and Number(c.focusScalePercent, 110, 50, 200) / 100 or 1,
        castScale = c.castingScaleEnabled and Number(c.castingScalePercent, 110, 50, 200) / 100 or 1,
        clickbox = c.plateClickboxEnabled == true, clickWidth = Number(c.plateClickboxWidth, 140, 20, 500),
        clickHeight = Number(c.plateClickboxHeight, 40, 5, 200), clickThrough = c.friendlyPlateClickThrough == true,
        range = c.plateRangeEnabled == true, rangeSpell = Number(c.plateRangeSpell, 0, 0, 10000000),
        rangeAlpha = Number(c.plateRangeAlpha, 40, 0, 100) / 100,
        rangeUnknownAlpha = Number(c.plateRangeUnknownAlpha, 100, 0, 100) / 100,
        rangeText = c.plateRangeText == true, resources = c.targetClassResources == true,
    }
    for _, kind in ipairs(X.Kinds) do
        local entry = { alpha = 1, scale = 1, castVisibility = 1 }
        if plan.contextEnabled then
            entry.alpha = Number(c[kind.key .. "Opacity"], 100, 0, 100) / 100
            entry.scale = Number(c[kind.key .. "Scale"], 100, 50, 200) / 100
            entry.castVisibility = Number(c[kind.key .. "CastVisibility"], 1, 1, 3)
            for _, context in ipairs(X.Contexts) do entry[context.key] = c[kind.key .. context.key .. "Visible"] ~= false end
        end
        plan.kinds[kind.key] = entry
    end
    Slots(c, plan)
    plan.enabled = plan.contextEnabled or plan.interrupt or plan.focusReminder or plan.execute
        or plan.focusScale ~= 1 or plan.castScale ~= 1 or plan.clickbox or plan.clickThrough or plan.range
        or plan.resources or #plan.slots > 0
    for _, prefix in ipairs({ "enemy", "friendly" }) do
        local side = plan[prefix]
        plan.enabled = plan.enabled or side.nameCast > 1 or side.raidAnchor > 1 or side.iconAnchor > 1
            or side.foreground or side.identity > 1
    end
    return plan
end

function X.Visibility(plan, kind, context, casting)
    local entry = plan.kinds[kind]
    if not entry or not plan.contextEnabled then return true, 1, 1 end
    -- An unknown context/cast does not satisfy a hide rule.
    local visible = entry[context] ~= false
    if casting ~= nil and entry.castVisibility > 1 then
        visible = visible and (entry.castVisibility == 2 and casting or entry.castVisibility == 3 and not casting)
    end
    return visible, entry.alpha, entry.scale
end

-- No enemy school-lockout duration or per-unit spell line-of-sight query
-- exists in the current Retail/Forever Unit and Spell API contracts.
function X.Capability(key)
    if key == "lockout" then
        return false, "The interrupt event identifies the interrupter but provides no enemy school-lockout duration."
    elseif key == "lineOfSight" then
        return false, "Spell range and camera occlusion do not report spell line of sight for a unit."
    elseif key == "forces" then
        return true, "Enemy forces require an active Mythic+ run and native per-unit criteria values."
    elseif key == "resources" then
        if NS.Client.isForever then return false, "WoW Forever does not load Blizzard's class nameplate mechanic bars." end
        local driver = NamePlateDriverFrame
        if not NS.IsSecret(driver) and driver and driver.GetClassNameplateBar then
            local bar = driver:GetClassNameplateBar()
            if not NS.IsSecret(bar) and bar == nil then
                return false, "No active Blizzard class resource bar is available for this character."
            end
        end
        return true
    end
    return true
end

local _, NS = ...
-- Shared settings and presentation contracts. This file has no runtime
-- subscriptions, timers or frames. Unknown unit facts stay unknown.
local X = {}
NS.NameplateExtensions = X

X.Kinds = {
    { key = "enemyNpc", label = "Enemy NPC" },
    { key = "enemyPlayer", label = "Enemy player" },
    { key = "neutralNpc", label = "Neutral" },
    { key = "friendlyNpc", label = "Friendly NPC" },
    { key = "friendlyPlayer", label = "Friendly player" },
}
X.Contexts = {
    { key = "World", label = "Open world" },
    { key = "Dungeon", label = "Dungeon" },
    { key = "Raid", label = "Raid" },
    { key = "PvP", label = "Battleground or arena" },
}
X.EnemyConditions = {
    { key = "enemyHideInHousing", label = "Housing", client = "retail" },
    { key = "enemyHideInCombat", label = "In combat" },
    { key = "enemyHideInGroup", label = "In group" },
    { key = "enemyHideInInstance", label = "In instance" },
    { key = "enemyHideInVehicle", label = "In vehicle" },
    { key = "enemyHideMounted", label = "Mounted" },
    { key = "enemyHideNoTarget", label = "No target", replacedByHealth = true },
    { key = "enemyHideOutOfCombat", label = "Out of combat", replacedByHealth = true },
    { key = "enemyHideOutOfCombatNoTarget", label = "Out of combat and no target", replacedByHealth = true },
    { key = "enemyHideResting", label = "Resting" },
    { key = "enemyHideSolo", label = "Solo" },
    { key = "enemyHideStealthed", label = "Stealthed" },
    { key = "enemyShowWhenInjured", label = "Show only below 100% health" },
}

function X.EnemyConditionActive(config, rule)
    return config[rule.key] == true and (rule.client ~= "retail" or not NS.Client.isForever)
        and (not rule.replacedByHealth or config.enemyShowWhenInjured ~= true)
end

local function EnemyLoad(config)
    if config.enemy ~= true then return end
    local rules
    for _, rule in ipairs(X.EnemyConditions) do
        if X.EnemyConditionActive(config, rule) then
            rules = rules or {}
            rules[rule.key] = true
        end
    end
    return rules
end

function X.IsEnemy(kind)
    return kind == "enemyNpc" or kind == "enemyPlayer"
end

X.OpacityScopes = { "enemy", "neutral", "friendly", "friendlyNpc" }
X.SkinKeys = { enemy = "enemySkinEnabled", neutral = "neutralSkinEnabled",
    friendly = "friendlySkinEnabled", friendlyNpc = "friendlyNpcSkinEnabled" }

function X.SkinEnabled(config, scope)
    return config[X.SkinKeys[scope]] ~= false
end

X.InteractionFields = { "ClickboxEnabled", "ClickboxWidth", "ClickboxHeight", "RangeEnabled", "RangeSpell",
    "RangeAlpha", "RangeUnknownAlpha", "RangeText" }

function X.OpacityScope(kind)
    if X.IsEnemy(kind) then return "enemy" end
    if kind == "neutralNpc" then return "neutral" end
    if kind == "friendlyPlayer" then return "friendly" end
    if kind == "friendlyNpc" then return kind end
end

-- The indices match the data readers in ExtensionText.lua and the old source IDs.
X.TextIndicators = {
    [2] = { element = "ExtraTextTarget", label = "Unit target", anchor = 1, y = 0 },
    [3] = { element = "ExtraTextQuest", label = "Quest objective progress", anchor = 1, y = 12 },
    [4] = { element = "ExtraTextGuild", label = "Guild name", anchor = 1, y = 24 },
    [5] = { element = "ExtraTextTitle", label = "NPC title", anchor = 2, y = 0 },
    [6] = { element = "ExtraTextThreat", label = "Threat percentage", anchor = 5, y = 0, layer = 5 },
    [7] = { element = "ExtraTextTankThreat", label = "Threat difference to current tank", anchor = 5, y = -12 },
    [8] = { element = "ExtraTextResource", label = "Current / maximum resource", anchor = 2, y = -12 },
    [9] = { element = "ExtraTextAbsorb", label = "Absorb amount", anchor = 4, y = 0 },
    [10] = { element = "ExtraTextForces", label = "Mythic+ enemy forces", anchor = 4, y = -12 },
}
X.FirstTextSource, X.LastTextSource = 2, 10

function X.TextKey(scope, source)
    return scope .. X.TextIndicators[source].element
end

X.TextAnchors = { "Above name", "Below health bar", "Inside health bar", "Left of health bar", "Right of health bar" }
X.TextPoints = {
    { "BOTTOM", "name", "TOP", 0, 2 }, { "TOP", "health", "BOTTOM", 0, -2 },
    { "CENTER", "health", "CENTER", 0, 0 }, { "RIGHT", "health", "LEFT", -4, 0 },
    { "LEFT", "health", "RIGHT", 4, 0 },
}
-- The former Threat % indicator could be centered on any point of the bar.
X.TextHealthAnchorStart = #X.TextPoints
for i, point in ipairs(NS.AnchorPoints) do
    X.TextAnchors[#X.TextAnchors + 1] = NS.AnchorLabels[i]
    X.TextPoints[#X.TextPoints + 1] = { "CENTER", "health", point, 0, 0 }
end
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

function X.Kind(friend, player, reaction, fighting)
    if NS.IsSecret(friend) or NS.IsSecret(player) then return end
    if type(friend) ~= "boolean" or type(player) ~= "boolean" then return end
    if friend then return player and "friendlyPlayer" or "friendlyNpc" end
    if player then return "enemyPlayer" end
    if not NS.IsSecret(reaction) and reaction == 4 and not NS.IsSecret(fighting) and fighting == false then
        return "neutralNpc"
    end
    return "enemyNpc"
end

function X.PlateKind(frame, unit)
    local kind = X.Kind(frame.isFriend, frame.isPlayer)
    if kind ~= "enemyNpc" or not unit then return kind end
    return X.Kind(false, false, UnitReaction(unit, "player"), UnitAffectingCombat(unit))
end

function X.HealthDimensions(config, side, kind)
    if (kind == "neutralNpc" or kind == "friendlyNpc") and config[kind .. "SizeOverride"] then
        return config[kind .. "HealthWidthDelta"] or 0, config[kind .. "HealthHeightDelta"] or 0
    end
    return config[side .. "HealthWidthDelta"] or 0, config[side .. "HealthHeightDelta"] or 0
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

function X.ReadOpacity(c, scope)
    local key = scope .. "Fade"
    local health = Number(c[key .. "Health"], 100, 0, 100) / 100
    local background = Number(c[key .. "HealthBackground"], 100, 0, 100) / 100
    local power = Number(c[key .. "Power"], 100, 0, 100) / 100
    local powerBackground = Number(c[key .. "PowerBackground"], 100, 0, 100) / 100
    local ooc = c[key .. "OutOfCombat"] == true and Number(c[key .. "OutOfCombatAlpha"], 50, 0, 100) / 100 or 1
    if health == 1 and background == 1 and power == 1 and powerBackground == 1 and ooc == 1 then return end
    local text = c[key .. "KeepText"] == true
    return { health = health, background = background, power = power, powerBackground = powerBackground, ooc = ooc,
        text = text and 1 or health, powerText = text and 1 or power,
        prediction = c[key .. "KeepPrediction"] == true and 1 or health }
end

local function AddOpacity(plan, c)
    for _, scope in ipairs(X.OpacityScopes) do
        local side = (scope == "enemy" or scope == "neutral") and "enemy" or "friendly"
        local fade = c[side] and X.ReadOpacity(c, scope)
        if fade then
            plan.opacity = plan.opacity or {}
            plan.opacity[scope] = fade
            plan.opacityCombat = plan.opacityCombat or fade.ooc ~= 1
        end
    end
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

local function TextIndicators(c, plan, scope, entry)
    for source = X.FirstTextSource, X.LastTextSource do
        local key = X.TextKey(scope, source)
        if c[key] then
            local item = X.TextIndicators[source]
            entry.slots[#entry.slots + 1] = {
                source = source,
                anchor = Number(c[key .. "Anchor"], item.anchor, 1, #X.TextAnchors),
                x = Number(c[key .. "X"], 0, -2048, 2048),
                y = Number(c[key .. "Y"], item.y, -2048, 2048),
                size = Number(c[key .. "Size"], 10, 6, 48), color = c[key .. "Color"] or "ffffff",
                unknown = c[key .. "Unknown"] == true,
                layer = item.layer and Number(c[key .. "Layer"], item.layer, 0, 30),
            }
            entry.sources[source] = true
            plan.sources[source] = true
        end
    end
end

local function Interaction(c, plan)
    for _, scope in ipairs(X.OpacityScopes) do
        local friendly = scope == "friendly" or scope == "friendlyNpc"
        local click = c[scope .. "ClickboxEnabled"] ~= nil and scope or "plate"
        local range = c[scope .. "RangeEnabled"] ~= nil and scope or "plate"
        local through = c[scope .. "PlateClickThrough"]
        if through == nil and friendly then through = c.friendlyPlateClickThrough end
        local entry = {
            friendly = friendly, slots = {}, sources = {},
            clickbox = c[click .. "ClickboxEnabled"] == true, clickThrough = through == true,
            clickWidth = Number(c[click .. "ClickboxWidth"], 140, 20, 500),
            clickHeight = Number(c[click .. "ClickboxHeight"], 40, 5, 200),
            range = c[range .. "RangeEnabled"] == true and (range ~= "plate" or not friendly),
            rangeSpell = Number(c[range .. "RangeSpell"], 0, 0, 10000000),
            rangeAuto = c[range .. "RangeAuto"] == true,
            rangeAlpha = Number(c[range .. "RangeAlpha"], 40, 0, 100) / 100,
            rangeUnknownAlpha = Number(c[range .. "RangeUnknownAlpha"], 100, 0, 100) / 100,
            rangeText = c[range .. "RangeText"] == true,
        }
        if entry.rangeAuto and NS.HostBridge and NS.HostBridge.NameplateRangeSpell then
            entry.rangeSpell = NS.HostBridge.NameplateRangeSpell(friendly)
        end
        TextIndicators(c, plan, scope, entry)
        plan.interaction[scope] = entry
        plan.range = plan.range or entry.range
        plan.clickbox = plan.clickbox or entry.clickbox or entry.clickThrough
        local active = entry.range or entry.clickbox or entry.clickThrough or #entry.slots > 0
        plan.scoped = plan.scoped or active
        plan.hostileScoped = plan.hostileScoped or not friendly and active
    end
end

function X.Plan(c)
    local plan = {
        enemy = Side(c, "enemy"), friendly = Side(c, "friendly"), interaction = {}, sources = {}, kinds = {},
        contextEnabled = c.plateContextEnabled == true, enemyLoad = EnemyLoad(c),
        interrupt = c.interruptFeedbackEnabled == true,
        interruptShared = c.interruptFeedbackShared ~= false,
        interruptDuration = Number(c.interruptFeedbackDuration, 1.2, .1, 5),
        interruptColor = c.interruptFeedbackColor or "ff5050", interruptFlash = c.interruptFeedbackFlash == true,
        interruptWho = c.interruptFeedbackWho ~= false, focusReminder = c.focusReminderEnabled == true,
        focusColor = c.focusReminderColor or "ffb833", execute = c.executePulseEnabled == true,
        executeAt = Number(c.executePulsePercent, 20, 1, 99) / 100, executeColor = c.executePulseColor or "ff3030",
        executeAlpha = Number(c.executePulseAlpha, 60, 0, 100) / 100,
        focusScale = c.focusScaleEnabled and Number(c.focusScalePercent, 110, 50, 200) / 100 or 1,
        castScale = c.castingScaleEnabled and Number(c.castingScalePercent, 110, 50, 200) / 100 or 1,
    }
    for _, kind in ipairs(X.Kinds) do
        local entry = { alpha = 1, scale = 1, castVisibility = 1 }
        if kind.key == "neutralNpc" and not c.neutralNpcContextOverride then
            entry = plan.kinds.enemyNpc
        elseif plan.contextEnabled or kind.key == "neutralNpc" and c.neutralNpcContextOverride then
            entry.alpha = Number(c[kind.key .. "Opacity"], 100, 0, 100) / 100
            entry.scale = Number(c[kind.key .. "Scale"], 100, 50, 200) / 100
            entry.castVisibility = Number(c[kind.key .. "CastVisibility"], 1, 1, 3)
            for _, context in ipairs(X.Contexts) do entry[context.key] = c[kind.key .. context.key .. "Visible"] ~= false end
        end
        plan.kinds[kind.key] = entry
    end
    Interaction(c, plan)
    AddOpacity(plan, c)
    plan.neutralContext = c.neutralNpcContextOverride == true
    plan.contextEnabled = plan.contextEnabled or plan.neutralContext
    plan.enabled = plan.contextEnabled or plan.opacity ~= nil or plan.enemyLoad ~= nil or plan.interrupt or plan.focusReminder or plan.execute
        or plan.focusScale ~= 1 or plan.castScale ~= 1 or plan.scoped
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
    local visible = not entry.hidden and entry[context] ~= false
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
    end
    return true
end

local _, P = ...
local ID, Tr = "nameplates", P.Tr
local Layers = P.NameplatesEditorLayers
local X = P.Suite.NameplateExtensions
local Templates = {}
P.NameplatesLayoutTemplates = Templates

local SCOPES = {
    enemy = { label = "Enemy", side = "enemy", auras = { "enemyNpc", "enemyPlayer" } },
    neutral = { label = "Neutral", side = "enemy", dimensions = "neutralNpc" },
    friendly = { label = "Friendly", side = "friendly", auras = { "friendlyPlayer" } },
    friendlyNpc = { label = "Friendly NPC", side = "friendly", dimensions = "friendlyNpc" },
}

local classic = { label = "Classic", description = "Reset the layout elements to their MSUF defaults." }
local minimal = { label = "Minimal", description = "A slimmer plate with name and debuffs.",
    npcDescription = "A slimmer health bar.",
    height = -4, name = true, healthText = false, level = false, castTime = false, glow = false,
    power = false, debuffs = true, buffs = false, control = false }
local tank = { label = "Tank", description = "A taller health bar with a frame glow.",
    height = 4, glow = true }
local interrupter = { label = "Interrupter", description = "Larger castbar and spell icon when shown, with cast time enabled.",
    castTime = true, castHeight = 14, castIcon = 14, debuffs = false, buffs = false, control = true }
local pvp = { label = "PvP", description = "Buffs and level.",
    enemyDescription = "Buffs, level, and the enemy resource bar.", level = true, power = true, buffs = true }

local ALL_TEMPLATES = { classic, minimal, tank, interrupter, pvp }
local NPC_TEMPLATES = { classic, minimal }
local CUSTOM_AURAS, SHOW_AURAS = 2, 2

local function Setting(values, key, value)
    local spec = P.catalog[ID]
    local rule = spec.rules[key]
    if not rule or not spec.controlAvailable(rule) then return end
    if value == nil then value = rule.default end
    if P.Get(ID, key) ~= value then values[key] = value end
end

local function Dimensions(values, config, scope, template)
    if not scope.dimensions then
        Setting(values, scope.side .. "HealthHeightDelta", template.height)
        return
    end
    local kind = scope.dimensions
    if template == classic then
        Setting(values, kind .. "SizeOverride")
        Setting(values, kind .. "HealthWidthDelta")
        Setting(values, kind .. "HealthHeightDelta")
        return
    end
    local width, height = X.HealthDimensions(config, scope.side, kind)
    local desired = template.height or 0
    if height == desired then return end
    -- Turning on the existing size override must keep the inherited width.
    Setting(values, kind .. "SizeOverride", true)
    Setting(values, kind .. "HealthWidthDelta", width)
    Setting(values, kind .. "HealthHeightDelta", desired)
end

local function Auras(values, scope, template)
    for _, kind in ipairs(scope.auras) do
        Setting(values, kind .. "AuraMode", template ~= classic and CUSTOM_AURAS or nil)
        Setting(values, kind .. "Debuffs", template.debuffs)
        Setting(values, kind .. "Buffs", template.buffs)
        Setting(values, kind .. "Control", template.control)
    end
end

local function SideElements(values, ui, scope, template)
    local side = scope.side
    Setting(values, side .. "NameVisible", template.name)
    Setting(values, side .. "HealthTextVisible", template.healthText)
    Setting(values, side .. "LevelEnabled", template.level)
    Setting(values, side .. "CastTimeEnabled", template.castTime)
    Setting(values, side .. "CastHeight", template.castHeight)
    Setting(values, side .. "CastIconSize", template.castIcon)
    Setting(values, Layers.DecorSetting(ui, "glow"), template.glow)
    if side == "enemy" then Setting(values, "enemyPowerEnabled", template.power) end
    Auras(values, scope, template)
end

local function Values(ui, scopeKey, scope, template)
    local values = {}
    Dimensions(values, P.S.Config(ID), scope, template)
    if scope.auras then
        SideElements(values, ui, scope, template)
    elseif scopeKey == "friendlyNpc" then
        Setting(values, "friendlyNpcDebuffs", template.debuffs and SHOW_AURAS or nil)
    end
    return values
end

local function CanApply(ui, scopeKey)
    return not P.Combat() and ui.scope == scopeKey and not Layers.NPCWorldNames(ui)
        and P.Get(ID, "enabled") and P.Get(ID, "look") ~= 2 and P.Get(ID, X.SkinKeys[scopeKey])
        and P.Available(ID)
end

function Templates.Available(ui)
    return SCOPES[ui.scope] ~= nil and CanApply(ui, ui.scope) == true
end

local function Feedback(key, style, label)
    if not P.M.ShowStatusFeedback then return end
    local text = Tr(key)
    if label then text = text:format(label) end
    P.M.ShowStatusFeedback(text, style, 2)
end

local function Confirm(ui, scopeKey, scope, template)
    if not CanApply(ui, scopeKey) then return end
    local label = Tr(template.label)
    local prompt = Tr("Apply the %s layout to %s nameplates?"):format(label, Tr(scope.label))
    if scope.auras then prompt = prompt .. "\n\n" .. Tr("Some settings also affect plate types that inherit from this one.") end
    P.Confirm("nameplates.layoutTemplate", prompt, function()
        if not CanApply(ui, scopeKey) then return end
        local values = Values(ui, scopeKey, scope, template)
        if not next(values) then return Feedback("This layout is already applied.", "ok") end
        if P.SetMany(ID, values) then Feedback("Applied the %s layout.", "ok", label) end
    end)
end

function Templates.Open(ui, anchor)
    local scopeKey = ui.scope
    local scope = SCOPES[scopeKey]
    if not scope or not CanApply(ui, scopeKey) then return end
    return P.AnchoredContextMenu(anchor, function(_, menu)
        menu:CreateTitle(Tr("Layout templates"))
        for _, template in ipairs(scope.auras and ALL_TEMPLATES or NPC_TEMPLATES) do
            local item = template
            local row = menu:CreateButton(Tr(item.label), function() Confirm(ui, scopeKey, scope, item) end)
            local description = scopeKey == "enemy" and item.enemyDescription
                or scope.dimensions and item.npcDescription or item.description
            if row and row.SetTooltip then row:SetTooltip(function(tip) tip:SetText(Tr(description)) end) end
        end
    end)
end


local _, P = ...
-- The nameplate preview's elements: which group lists each one, the profile
-- switch that puts it on the plate (its presence) and how the preview shows
-- it. The element panel and the inspector read this model; the preview layer
-- rules stay in NameplatesEditorLayers.lua. Presence writes go through P.Set,
-- so the menu's history and undo cover them.
local ID = "nameplates"
local Elements = {}
P.NameplatesElements = Elements
local Layers = P.NameplatesEditorLayers

Elements.GROUPS = {
    { id = "health", title = "Health and text" },
    { id = "cast", title = "Castbar" },
    { id = "power", title = "Resource Bar" },
    { id = "auras", title = "Auras" },
    { id = "icons", title = "Icons and markers", layer = "status" },
    { id = "frame", title = "Frame and highlights" },
}
Elements.GROUP_TITLE = {}
for _, group in ipairs(Elements.GROUPS) do Elements.GROUP_TITLE[group.id] = group.title end

-- Presence kinds. key(ui) names the profile setting; off is its "not on the
-- plate" value (false for a switch); invert stores true for off; can(ui)
-- says whether the setting decides presence in the current setup.
local function Bool(key) return { key = function() return key end, off = false } end
local function Side(suffix) return { key = function(ui) return ui.sampleKind .. suffix end, off = false } end
local function Decor(key) return { key = function(ui) return Layers.DecorSetting(ui, key) end, off = false } end
local function Choice(key, off) return { key = function() return key end, off = off } end
local function CastDetail(key)
    return { key = function() return key end, off = false, can = function() return P.Get(ID, "enemyCastDisplay") == 2 end }
end
local function Threat(key)
    return { key = function() return key end, off = false, can = function() return P.Get(ID, "threatSignalMode") == 2 end }
end
local AURA_KINDS = { auras = "Debuffs", buffs = "Buffs", controlAura = "Control" }
local function Aura(layer)
    return { key = function(ui) return Layers.AuraSetting(ui, layer) end,
        off = function(ui) return Layers.AuraGroup(ui) == "friendlyNpc" and 3 or false end,
        on = function(ui) return Layers.AuraGroup(ui) == "friendlyNpc" and 2 or true end,
        can = function(ui)
            local group = Layers.AuraGroup(ui)
            return group == "friendlyNpc" or P.Get(ID, group .. "AuraMode") == 2
        end }
end
local TARGET_ARROWS = {
    key = function(ui) return ui.sampleKind == "friendly" and "enemyTargetHideFriendly" or "enemyTargetMarker" end,
    off = function(ui) return ui.sampleKind == "friendly" end,
    on = function(ui) return ui.sampleKind ~= "friendly" end,
    can = function(ui) return ui.sampleKind ~= "friendly" or P.Get(ID, "enemyTargetMarker") == true end,
}

-- handle: the preview element selected for the row; context: the Edit
-- context that brings it into the sample; status: the status sample that
-- shows it; highlight: the highlight sample; side: only on that side.
Elements.LIST = {
    { key = "health", group = "health", handle = "Health", context = "anchor", locked = true },
    { key = "name", group = "health", handle = "Name", context = "text", presence = Side("NameVisible") },
    { key = "healthText", group = "health", handle = "HealthText", context = "text", presence = Side("HealthTextVisible") },
    { key = "level", group = "health", status = "Level", presence = Side("LevelEnabled") },
    { key = "cast", group = "cast", handle = "Cast", context = "cast", presence = Choice("enemyCastEnabled", 3) },
    { key = "castText", group = "cast", handle = "CastText", context = "cast", presence = CastDetail("enemyCastSpellName") },
    { key = "castTime", group = "cast", handle = "CastTime", context = "cast", presence = Side("CastTimeEnabled") },
    { key = "castIcon", group = "cast", handle = "CastIcon", context = "cast", presence = CastDetail("enemyCastSpellIcon") },
    { key = "castTarget", group = "cast", handle = "CastTarget", context = "cast", presence = CastDetail("enemyCastSpellTarget") },
    { key = "castShield", group = "cast", handle = "CastShield", context = "cast" },
    { key = "enemyPower", group = "power", handle = "Power", context = "power", side = "enemy", presence = Bool("enemyPowerEnabled") },
    { key = "auras", group = "auras", handle = "Auras", context = "auras", presence = Aura("auras") },
    { key = "buffs", group = "auras", handle = "Buffs", context = "auras", presence = Aura("buffs"), notFriendlyNpc = true },
    { key = "controlAura", group = "auras", handle = "ControlAura", context = "auras", presence = Aura("controlAura"),
      notFriendlyNpc = true },
    { key = "raidIcon", group = "icons", status = "RaidIcon", presence = Side("RaidIcon") },
    { key = "classification", group = "icons", status = "Classification", presence = Choice("enemyRarityIcon", 3) },
    { key = "eliteMarker", group = "icons", status = "elite", presence = Side("EliteMarker") },
    { key = "questMarker", group = "icons", status = "quest", presence = Side("QuestMarker") },
    { key = "target", group = "icons", status = "target", presence = TARGET_ARROWS },
    { key = "focusMarker", group = "icons", status = "focusMarker", side = "enemy", presence = Bool("enemyFocusMarker") },
    { key = "threshold", group = "icons", status = "Threshold", side = "enemy", presence = Bool("enemyThresholdEnabled") },
    { key = "softTarget", group = "icons", status = "SoftTarget" },
    { key = "backdrop", group = "frame", presence = Side("BackdropEnabled") },
    { key = "border", group = "frame" },
    { key = "outerFrame", group = "frame", presence = Decor("outerFrame") },
    { key = "shadow", group = "frame", presence = Decor("shadow") },
    { key = "glow", group = "frame", presence = Decor("glow") },
    { key = "roleFill", group = "frame", side = "enemy", presence = Bool("enemyRoleColors") },
    { key = "highlightBorders", group = "frame" },
    { key = "targetBorder", group = "frame", highlight = "target", presence = Bool("highlightTarget") },
    { key = "focusBorder", group = "frame", highlight = "focus", presence = Bool("highlightFocus") },
    { key = "mouseoverBorder", group = "frame", highlight = "mouseover", presence = Bool("highlightMouseover") },
    { key = "aggroBorder", group = "frame", highlight = "aggro", side = "enemy" },
    { key = "threatFlash", group = "frame", side = "enemy", status = "Aggro", presence = Threat("threatFlash") },
    { key = "threatHighlight", group = "frame", side = "enemy", status = "Aggro", presence = Threat("threatHighlight") },
    { key = "targetScale", group = "frame" },
}
Elements.BY_KEY = {}
for _, def in ipairs(Elements.LIST) do Elements.BY_KEY[def.key] = def end

-- Preview handles (the part after "enemy." or "friendly.") and their element.
local HANDLE_ELEMENT = { Power = "enemyPower", PowerText = "enemyPower", elite = "eliteMarker", quest = "questMarker",
    target = "target", targetRight = "target", targetPair = "target" }
for _, def in ipairs(Elements.LIST) do
    if def.handle then HANDLE_ELEMENT[def.handle] = def.key end
    if def.status and not def.handle and not HANDLE_ELEMENT[def.status] then HANDLE_ELEMENT[def.status] = def.key end
end

function Elements.ForHandle(handle)
    local id = handle and handle._key
    local element = id and id:match("^%a+%.(%a+)$")
    return element and Elements.BY_KEY[HANDLE_ELEMENT[element]] or nil
end

function Elements.Current(ui)
    local handle = ui.body._selectedHandle
    if handle then return Elements.ForHandle(handle), handle end
    return ui.inspectedKey and Elements.BY_KEY[ui.inspectedKey], nil
end

function Elements.Label(def, handle)
    local layer = def and Layers.Def(def.key)
    return layer and layer.label or handle and handle._label or ""
end

function Elements.OpenSettings(ui)
    local def, handle = Elements.Current(ui)
    if handle then return ui:OpenHandleSettings(handle) end
    local layer = def and Layers.Def(def.key)
    if layer then Layers.Focus(ui, layer.section, def.key) end
end

-- Whether the row belongs to the sample shown (side and plate kind).
function Elements.Applies(ui, def)
    if def.side and def.side ~= ui.sampleKind then return false end
    if def.key == "aggroBorder" and ui.scope == "neutral" then return false end
    if def.notFriendlyNpc and ui.scope == "friendlyNpc" then return false end
    return not Layers.NPCWorldNames(ui) or def.key == "name"
end

local function Value(spec, field, ui)
    local value = spec[field]
    if type(value) == "function" then return value(ui) end
    return value
end

-- The presence setting and whether the element is on the plate. Nil key: the
-- element has no switch of its own here (it follows Blizzard or a sample).
function Elements.Presence(ui, def)
    local spec = def.presence
    if not spec or (spec.can and not spec.can(ui)) then return nil end
    local key = spec.key(ui)
    local rule = key and P.catalog[ID].rules[key]
    if not rule then return nil end
    return key, P.Get(ID, key) ~= Value(spec, "off", ui), rule
end

-- Why the switch cannot change now, or nil.
function Elements.Locked(ui, def)
    local key, _, rule = Elements.Presence(ui, def)
    if not key then return nil end
    if P.Combat() then return true end
    local enabled, reason = P.RuleEnabled(ID, rule, nil, true)
    if enabled then return nil end
    return reason or true
end

-- Choice settings remember their last "on" value for the session, so taking
-- an element off and back on keeps its mode.
local restore = setmetatable({}, { __mode = "k" })
function Elements.SetPresence(ui, def, on)
    local key, current, rule = Elements.Presence(ui, def)
    if not key or current == on or Elements.Locked(ui, def) then return false end
    local spec = def.presence
    local off = Value(spec, "off", ui)
    local value = off
    local config = P.S.Config(ID)
    local remembered = restore[config]
    if on then
        value = Value(spec, "on", ui)
        if value == nil then
            if off == false then value = true
            else value = remembered and remembered[key] or (rule.default ~= off and rule.default) or 2 end
        end
    end
    local before = not on and type(off) == "number" and P.Get(ID, key)
    if P.Set(ID, key, value) == false then return false end
    if before then
        remembered = remembered or {}
        remembered[key] = before
        restore[config] = remembered
    end
    return true
end

-- Brings the element into the sample and selects it where it has a handle.
function Elements.Show(ui, def)
    if P.Combat() then return end
    if def.highlight then return ui:SampleHighlight(def.highlight) end
    if def.status then return P.PreviewNameplateStatus(def.status) end
    if def.context then return ui:Edit(def.context, def.handle) end
end

function Elements.Inspect(ui, def, show)
    if P.Combat() then return end
    local _, on = Elements.Presence(ui, def)
    if show and on ~= false then
        Layers.SetShown(ui, def.key, true)
        local entry = def.handle or def.status
        local handle = entry and ui.kit.entries[ui.sampleKind .. "." .. entry]
        if handle and ui:CanMoveHandle(handle.region) then
            ui:Select(handle.region)
        elseif not Layers.Blocked(ui, def.key) then
            Elements.Show(ui, def)
        end
        ui:Paint()
    end
    if Elements.ForHandle(ui.body._selectedHandle) ~= def then
        ui:Select(nil)
        ui.inspectedKey = def.key
    end
    ui:RefreshSelection()
end

Elements.AURA_KINDS = AURA_KINDS

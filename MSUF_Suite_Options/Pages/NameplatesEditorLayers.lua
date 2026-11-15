local _, P = ...
local M, W, T, Tr, HM = P.M, P.W, P.T, P.Tr, P.HM
local Style, Auras = P.Suite.NameplateStyle, P.Suite.NameplateAuraDisplay
local ID, PAGE = "nameplates", "suite_nameplates"
local H = M.PreviewHelpers or {}
local Markers = P.NameplatesEditorMarkers
local NativeBit = Style.NativeBit

-- The nameplate preview's layers: which layer a sample shows, the live
-- settings behind it, the click and right-click actions of the layer rail and
-- the rail itself. NameplatesEditor.lua installs On, Available and Active as
-- the editor's LayerOn, LayerAvailable and LayerActive methods. Register and
-- OpenSetting link every preview control to search and to its setting.
local Layers = {}
P.NameplatesEditorLayers = Layers
local DECOR_LAYERS = {
    outerFrame = "OuterFrame", shadow = "ShadowEnabled", glow = "GlowEnabled",
    focusMarker = "enemyFocusMarker", threshold = "enemyThresholdEnabled",
    targetScale = "targetScaleEnabled",
}
local function DecorSetting(ui, key)
    local suffix = DECOR_LAYERS[key]
    return suffix and (suffix:match("^[A-Z]") and ui.sampleKind .. suffix or suffix)
end

local HIGHLIGHT_SAMPLES = {
    targetBorder = "target", focusBorder = "focus", aggroBorder = "aggro", mouseoverBorder = "mouseover",
}
local HIGHLIGHT_SETTINGS = {
    target = "highlightTarget", focus = "highlightFocus", aggro = "highlightAggro", mouseover = "highlightMouseover",
}

local LAYERS, LAYER_COLORS
local function PrepareLayers()
    if LAYERS then return LAYERS end
    LAYER_COLORS = {
        guides = { 0.42, 0.72, 1.00 }, health = { 0.25, 0.90, 0.42 },
        backdrop = { 0.80, 0.55, 0.25 }, border = { 0.85, 0.70, 0.25 }, roleFill = { 0.30, 0.78, 0.55 },
        highlightBorders = { 0.85, 0.70, 0.25 },
        targetBorder = { 1, 1, 1 }, focusBorder = { 1, 0.4, 1 },
        aggroBorder = { 1, 0.32, 0.32 }, mouseoverBorder = { 1, 1, 1 },
        name = { 0.30, 0.66, 1.00 }, level = { 0.30, 0.66, 1.00 }, healthText = { 0.25, 0.90, 0.42 },
        cast = { 0.20, 0.90, 0.85 }, castText = { 0.20, 0.90, 0.85 }, castTime = { 0.20, 0.90, 0.85 },
        auras = { 0.90, 0.20, 0.22 }, buffs = { 0.20, 0.90, 0.35 }, controlAura = { 0.90, 0.42, 1.00 },
        status = { 0.95, 0.72, 0.18 }, classification = { 0.95, 0.72, 0.18 }, raidIcon = { 0.95, 0.72, 0.18 }, power = { 0.95, 0.72, 0.18 },
        enemyPower = { 0.25, 0.64, 1.00 },
        castIcon = { 0.20, 0.90, 0.85 }, castShield = { 0.20, 0.90, 0.85 }, castTarget = { 0.20, 0.90, 0.85 },
        target = { 0.95, 0.72, 0.18 }, eliteMarker = { 0.95, 0.72, 0.18 }, questMarker = { 0.95, 0.72, 0.18 },
        threatFlash = { 0.90, 0.20, 0.22 }, threatHighlight = { 0.90, 0.20, 0.22 }, softTarget = { 0.25, 0.72, 1.00 },
    }
    for key in pairs(DECOR_LAYERS) do LAYER_COLORS[key] = LAYER_COLORS.border end
    LAYERS = {
        { "guides", "Guides", "enemy" }, { "health", "Blizzard health", "enemy" },
        { "backdrop", "Skin backdrop", "enemy" }, { "border", "Skin border", "enemy" },
        { "highlightBorders", "Highlight Borders", "signals" },
        { "aggroBorder", "Aggro border", "signals" }, { "targetBorder", "Target border", "signals" },
        { "focusBorder", "Focus border", "signals" }, { "mouseoverBorder", "Mouseover border", "signals" },
        { "roleFill", "Role fill", "roleColors" },
        { "outerFrame", "Outer frame", "enemy" }, { "shadow", "Shadow", "enemy" },
        { "glow", "Glow", "enemy" },
        { "threshold", "Threshold", "enemy" }, { "focusMarker", "Focus diamond", "enemy" },
        { "targetScale", "Target size", "native" },
        { "name", "Name", "elements" }, { "level", "Level", "elements" },
        { "healthText", "HP text", "elements" },
        { "cast", "Castbar", "castbar" }, { "enemyPower", "Enemy power bar", "enemyPower" },
        { "castText", "Spell name", "castbar" }, { "castTime", "Cast time", "castbar" },
        { "auras", "Debuffs", "auras" },
        { "buffs", "Buffs", "auras" }, { "controlAura", "Control effects", "auras" },
        { "status", "Status icons", "markers" }, { "classification", "Elite / rare", "elements" }, { "raidIcon", "Raid mark", "elements" },
        { "castIcon", "Spell icon", "castbar" }, { "castShield", "Blizzard shield", "castbar" },
        { "castTarget", "Cast target", "castbar" }, { "target", "Target arrows", "enemy" },
        { "eliteMarker", "MSUF elite", "enemy" }, { "questMarker", "MSUF quest", "enemy" },
        { "threatFlash", "Aggro flash", "signals" },
        { "threatHighlight", "Aggro highlight", "signals" },
        { "softTarget", "Soft target", "signals" },
    }
    return LAYERS
end
local LAYER_SETTING = {
    health = "enemyHealthWidthDelta", backdrop = "enemyBackdropEnabled", border = "enemyOutlineMode",
    highlightBorders = "highlightTarget",
    roleFill = "enemyRoleColors", target = "enemyTargetMarker",
    name = "enemyNameSize", level = "enemyLevelEnabled",
    healthText = "enemyTextMode",
    cast = "enemyCastEnabled", castText = "enemyCastSpellName", castTime = "enemyCastTimeEnabled",
    classification = "enemyRarityIcon", raidIcon = "enemyRaidIcon",
    castIcon = "enemyCastSpellIcon",
    castTarget = "enemyCastSpellTarget", enemyPower = "enemyPowerEnabled",
}
local FRIENDLY_CAST_SETTINGS = { cast = "friendlyCastHeight", castText = "friendlyCastTextEnabled",
    castTime = "friendlyCastTimeEnabled", castIcon = "friendlyCastIconSize" }
local function NativeToggle(key, cvar)
    local mode = P.Get(ID, "look") ~= 2 and P.Get(ID, key) or 1
    if mode ~= 1 then return mode == 2 end
    return Style.NativeToggle(cvar, false)
end

local function ThreatOn(key)
    if P.Get(ID, "look") ~= 2 and P.Get(ID, "threatSignalMode") == 2 then
        return P.Get(ID, key)
    end
    return NativeBit("nameplateThreatDisplay", key == "threatHighlight" and 1 or 2, false)
end

local function SoftOn(ui)
    local name = ui.sampleKind == "enemy" and (ui.softInteract and "Interact" or "Enemy") or "Friend"
    return NativeToggle("softTargetIconGate", "SoftTargetNameplateSize")
        and NativeToggle("softTarget" .. name, "SoftTargetIcon" .. name)
end

local function AuraGroup(ui, side)
    if (side or ui.sampleKind) == "enemy" then return ui.enemyPlayer and "enemyPlayer" or "enemyNpc" end
    if ui.friendlyElite then return "friendlyNpc" end
    return "friendlyPlayer"
end

local AURA_KIND = { auras = "Debuffs", buffs = "Buffs", controlAura = "Control" }
Layers.AuraElement = { Auras = "auras", Buffs = "buffs", ControlAura = "controlAura" }
local function AuraSetting(ui, key)
    return Auras.NativeSetting(AuraGroup(ui), AURA_KIND[key])
end

local function AuraOn(ui, key)
    return Auras.NativeShown(P.S.Config(ID), AuraGroup(ui), AURA_KIND[key])
end

local function ToggleAura(ui, key)
    local setting = AuraSetting(ui, key)
    local rule = setting and P.catalog[ID].rules[setting]
    if not rule or not P.RuleEnabled(ID, rule) then return end
    P.RuleRow(PAGE, ID, rule).set(not AuraOn(ui, key))
    ui.layers[key] = true
end
local function Register(widget, key, label)
    if M.RegisterControlMetadata then
        M.RegisterControlMetadata(widget, P.Meta(PAGE, ID, "preview." .. key, "action", "suite_nameplates_preview"), label, "button")
    end
end
local function OpenSetting(key)
    return P.OpenNameplateSetting(key)
end
Layers.AURA_KIND, Layers.AuraGroup, Layers.AuraSetting = AURA_KIND, AuraGroup, AuraSetting
Layers.Register, Layers.OpenSetting = Register, OpenSetting

local STATUS_LAYERS = {
    focusMarker = true, level = true, classification = true, raidIcon = true,
    target = true, eliteMarker = true, questMarker = true,
    softTarget = true, threatFlash = true, threatHighlight = true, threshold = true,
}
function Layers.On(ui, key)
    return ui.layers[key] ~= false and (not STATUS_LAYERS[key] or ui.layers.status ~= false)
end

function Layers.NPCWorldNames(ui)
    return ui.sampleKind == "friendly" and ui.friendlyElite and P.Get(ID, "friendlyNPCs") == 4
end

local function FriendlyNamesOnly(ui)
    if ui.sampleKind ~= "friendly" or ui.friendlyElite then return false end
    local mode = P.Get(ID, "friendlyNamesOnly")
    return mode == 2 or mode == 3 or mode == 1 and Style.NativeToggle("nameplateShowOnlyNameForFriendlyPlayerUnits", false)
end

function Layers.Available(ui, key)
    if Layers.NPCWorldNames(ui) then return false end
    if key == "status" then return true end
    local skinned = P.Get(ID, "look") ~= 2
    if HIGHLIGHT_SAMPLES[key] then
        local extensions = P.Suite.NameplateExtensions
        return skinned and not FriendlyNamesOnly(ui) and P.Get(ID, "enabled") ~= false and P.Get(ID, ui.sampleKind) ~= false
            and (not extensions or extensions.SkinEnabled(P.S.Config(ID), ui.scope or ui.sampleKind))
            and (key ~= "aggroBorder" or ui.sampleKind == "enemy" and ui.scope ~= "neutral")
    end
    if key == "threshold" or key == "focusMarker" then return skinned and ui.sampleKind == "enemy" end

    if DECOR_LAYERS[key] then return skinned end
    if key == "target" then return skinned end
    if key == "backdrop" or key == "border" or key == "highlightBorders" then return skinned end
    if key == "roleFill" then return skinned and ui.sampleKind == "enemy" end
    if key == "enemyPower" then return skinned and ui.sampleKind == "enemy" and P.Get(ID, "enemy") == true end
    if key == "level" then return true end
    if key == "threatFlash" or key == "threatHighlight" then return ui.sampleKind == "enemy" end
    if (key == "buffs" or key == "controlAura") and ui.sampleKind == "friendly"
        and ui.friendlyElite then return false end
    if AURA_KIND[key] and FriendlyNamesOnly(ui) then return false end
    if key == "classification" then return not skinned or P.Get(ID, "enemyRarityIcon") ~= 3 end
    if key == "raidIcon" then return not skinned or P.Get(ID, ui.sampleKind .. "RaidIcon") end
    if key == "cast" then return not skinned or P.Get(ID, "enemyCastEnabled") ~= 3 end
    if key == "castTime" then return skinned and P.Get(ID, ui.sampleKind .. "CastTimeEnabled") end
    if key == "eliteMarker" or key == "questMarker" then
        return skinned
    end
    if skinned and P.Get(ID, "enemyCastDisplay") == 2 then
        if key == "castText" then return P.Get(ID, "enemyCastSpellName") end
        if key == "castIcon" then return P.Get(ID, "enemyCastSpellIcon") end
        if key == "castTarget" then return P.Get(ID, "enemyCastSpellTarget") end
    end
    return true
end

function Layers.Active(ui, key)
    if not ui:LayerOn(key) or not ui:LayerAvailable(key) then return false end
    if HIGHLIGHT_SAMPLES[key] then
        return ui:LayerOn("highlightBorders") and ui:LayerOn("health") and ui.highlightSample == HIGHLIGHT_SAMPLES[key]
    end
    local setting = DecorSetting(ui, key)
    if setting then
        local value = P.Get(ID, setting)
        return value == true
    end
    if key == "backdrop" then
        return P.Get(ID, ui.sampleKind .. "BackdropEnabled")
            and P.Get(ID, ui.sampleKind .. "BackdropAlpha") > 0
    end
    if key == "border" then
        local c, side = ui.barSettings or P.S.Config(ID), ui.sampleKind
        return Style.OutlineSize(c[side .. "OutlineMode"], c[side .. "BorderEnabled"], c[side .. "BorderSize"],
            c.hideHealthBarBorders) > 0
    end
    if key == "highlightBorders" then
        local c = P.S.Config(ID)
        return ui.highlightSample ~= nil or c.highlightTarget or c.highlightFocus or c.highlightMouseover
            or ui.sampleKind == "enemy" and Style.AggroHighlightEnabled(c)
    end
    if key == "roleFill" then return P.Get(ID, "enemyRoleColors") end
    if key == "target" then return Markers.TargetActive(ui) end
    if AURA_KIND[key] then return AuraOn(ui, key) end
    if key == "threatFlash" or key == "threatHighlight" then
        return ui.aggroSample and ThreatOn(key)
    end
    if key == "softTarget" then
        return ui.softTargetSample and SoftOn(ui)
    end
    if key == "enemyPower" then return P.Get(ID, "enemyPowerEnabled") == true end
    if key == "level" then
        local classic = Style.ClassicNativePlate(P.Get(ID, "nativeStyle"))
        return P.NameplatesPreviewDecor.LevelMode(ui, ui.sampleKind, classic, FriendlyNamesOnly(ui)) ~= nil
    end
    if key == "raidIcon" then return ui.raidMarked == true or ui.statusSample == "RaidIcon" or ui.allStatusSamples == true end
    if key == "castShield" then return ui.uninterruptible == true end
    if key == "classification" then
        local role = ui.previewRole or P.Get(ID, "enemyPreviewRole")
        return not ui.raidMarked and (ui.sampleKind == "friendly" and ui.friendlyElite
            or ui.sampleKind == "enemy" and (role == 3 or role == 4))
    end
    if key == "eliteMarker" or key == "questMarker" then
        local kind = key == "eliteMarker" and "Elite" or "Quest"
        if not P.Get(ID, ui.sampleKind .. kind .. "Marker") then return false end
        if ui.sampleKind == "friendly" then return ui.friendlyElite == true end
        local role = ui.previewRole or P.Get(ID, "enemyPreviewRole")
        return key == "eliteMarker" and (role == 3 or role == 4) or key == "questMarker" and role == 5
    end
    return true
end

local function FocusLayer(ui, section, key)
    if P.Combat() then return end
    if Layers.NPCWorldNames(ui) then
        OpenSetting("friendlyNPCs")
        return
    end
    if key == "status" then
        P.OpenNameplateStatusSection(ui.sampleKind)
        return
    end
    if key == "castShield" then
        P.OpenNameplateCastDetail(ui.sampleKind, "advanced")
        return
    end
    if key == "castTarget" and ui.sampleKind == "friendly" then
        P.OpenNameplateCastDetail("friendly", "spell")
        return
    end
    if section == "enemy" and ui.sampleKind == "friendly" then section = "friendly" end
    if section == "elements" and ui.sampleKind == "friendly"
        and (key == "name" or key == "level" or key == "healthText") then section = "friendly" end
    local setting = HIGHLIGHT_SETTINGS[HIGHLIGHT_SAMPLES[key]] or DecorSetting(ui, key) or LAYER_SETTING[key]
    if ui.sampleKind == "friendly" and FRIENDLY_CAST_SETTINGS[key] then
        section, setting = "friendlyCast", FRIENDLY_CAST_SETTINGS[key]
    elseif key == "backdrop" or key == "border" then
        setting = ui.sampleKind .. (key == "backdrop" and "BackdropEnabled" or "OutlineMode")
    elseif key == "raidIcon" then
        setting = ui.sampleKind .. "RaidIcon"
    elseif key == "classification" then
        if P.OpenNameplateStatusItem(ui.sampleKind, "enemyRarityIcon") then return end
        setting = "enemyRarityIcon"
    elseif key == "health" then
        setting = P.NameplatesSize.HealthScope(ui, ui.sampleKind) .. "HealthWidthDelta"
    elseif ui.sampleKind == "friendly" and key == "target" then
        setting = "enemyTargetHideFriendly"
    elseif ui.sampleKind == "friendly" and (key == "name" or key == "healthText" or key == "level") then
        setting = key == "level" and "friendlyLevelEnabled"
            or key == "name" and "friendlyNameSize" or "friendlyNamesOnly"
    end
    if AURA_KIND[key] then
        setting = AuraSetting(ui, key)
        if not ui:LayerAvailable(key) and ui.sampleKind == "friendly" and not ui.friendlyElite then
            section, setting = "friendly", "friendlyNamesOnly"
        end
    elseif key == "softTarget" then
        local name = ui.sampleKind == "enemy" and (ui.softInteract and "Interact" or "Enemy") or "Friend"
        setting = "softTarget" .. name
    elseif key == "threatFlash" or key == "threatHighlight" then setting = key
    elseif key == "eliteMarker" or key == "questMarker" then
        setting = ui.sampleKind .. (key == "eliteMarker" and "Elite" or "Quest") .. "Marker"
    end
    if OpenSetting(setting) then return end
    if key == "castTarget" and P.OpenNameplateCastDetail(ui.sampleKind, "spell") then return end
    local target = section == "elements" and P.SelectNameplatesEnemyTab("elements")
        or ui.sections and ui.sections[section]
    if target and W.FocusCollapsibleSection then
        W.FocusCollapsibleSection(target, { persist = true, flash = true })
    end
end
Layers.Focus = FocusLayer

local function ToggleSkinLayer(ui, key)
    if P.Get(ID, "look") == 2 then
        OpenSetting("look")
        return
    end
    if key == "roleFill" then
        P.Set(ID, "enemyRoleColors", not P.Get(ID, "enemyRoleColors"))
    else
        local prefix = ui.sampleKind
        local enabledKey = prefix .. (key == "backdrop" and "BackdropEnabled" or "BorderEnabled")
        local enabled = P.Get(ID, enabledKey)
        local amountKey = prefix .. (key == "backdrop" and "BackdropAlpha" or "BorderSize")
        local amount = P.Get(ID, amountKey)
        if enabled and amount > 0 then P.Set(ID, enabledKey, false)
        else P.SetMany(ID, { [enabledKey] = true,
            [amountKey] = amount > 0 and amount or (key == "backdrop" and 50 or 1) }) end
    end
    ui.layers[key] = true
    ui:Paint()
end

local function ToggleLevel(ui, key)
    if P.Get(ID, "look") == 2 then
        FocusLayer(ui, "elements", key)
    else
        P.Set(ID, ui.sampleKind .. "LevelEnabled", not P.Get(ID, ui.sampleKind .. "LevelEnabled"))
        ui.layers.level = true
        ui:Paint()
    end
end

local function ToggleThreat(ui, key)
    local active = ThreatOn(key)
    if ui.aggroSample or not active then
        local other = key == "threatFlash" and "threatHighlight" or "threatFlash"
        P.SetMany(ID, { threatSignalMode = 2, [key] = not active,
            [other] = ThreatOn(other) })
    end
    ui.aggroSample, ui.layers[key] = true, true
end

local function ToggleSoftTarget(ui, key)
    local name = ui.sampleKind == "enemy" and (ui.softInteract and "Interact" or "Enemy") or "Friend"
    local setting = "softTarget" .. name
    if ui.softTargetSample or not SoftOn(ui) then
        local show = not SoftOn(ui)
        local values = { [setting] = show and 2 or 3 }
        if show then values.softTargetIconGate = 2 end
        P.SetMany(ID, values)
    end
    ui.softTargetSample, ui.layers[key] = true, true
end

-- The layers that change a live setting: auras, threat, soft target and power.
local function ToggleLive(ui, key)
    if P.Get(ID, "look") == 2 then
        OpenSetting("look")
        return
    end
    if AURA_KIND[key] then
        ToggleAura(ui, key)
    elseif key == "threatFlash" or key == "threatHighlight" then
        ToggleThreat(ui, key)
    elseif key == "softTarget" then
        ToggleSoftTarget(ui, key)
    else
        local setting = "enemyPowerEnabled"
        P.Set(ID, setting, not P.Get(ID, setting))
        ui.layers[key] = true
    end
    ui:Paint()
end

local function ToggleClassification(ui, key)
    if ui.sampleKind == "friendly" then
        if not ui.friendlyElite then
            ui.friendlyElite, ui.layers[key] = true, true
        else
            ui.layers[key] = not ui:LayerOn(key)
        end
        ui:Paint()
        return
    end
    local wasFriendly = ui.sampleKind ~= "enemy"
    ui.sampleKind = "enemy"
    local role = ui.previewRole or P.Get(ID, "enemyPreviewRole")
    if wasFriendly or role ~= 3 and role ~= 4 or ui.raidMarked then
        ui.previewRole, ui.previewRoleSource, ui.raidMarked = 4, P.Get(ID, "enemyPreviewRole"), false
        ui.layers[key] = true
    else
        ui.layers[key] = not ui:LayerOn(key)
    end
    ui:Paint()
end

-- Click routing and its hint share the same live-setting classification.
local LAYER_ACTION = {
    level = "level", target = "target", backdrop = "skin", roleFill = "skin",
    threatFlash = "live", threatHighlight = "live", softTarget = "live", power = "live", enemyPower = "live",
    eliteMarker = "marker", questMarker = "marker",
}
local function LayerAction(key)
    if DECOR_LAYERS[key] then return "decor" end
    if AURA_KIND[key] then return "live" end
    return LAYER_ACTION[key]
end

local function FocusUnavailableLayer(ui, key)
    for _, layer in ipairs(PrepareLayers()) do
        if layer[1] == key then return FocusLayer(ui, layer[3], key) end
    end
    return FocusLayer(ui, "elements", key)
end

local function ToggleLayer(ui, key)
    local sample = HIGHLIGHT_SAMPLES[key]
    if sample then
        if ui:LayerAvailable(key) then
            ui:SampleHighlight(sample, ui:LayerActive(key), true)
        else
            FocusLayer(ui, "signals", key)
        end
        return
    end
    if Layers.NPCWorldNames(ui) then
        OpenSetting("friendlyNPCs")
        return
    end
    if STATUS_LAYERS[key] and ui.layers.status == false then
        ui.layers.status = true
        ui:Paint()
        return
    end
    local action = LayerAction(key)
    if action == "decor" and not ui:LayerAvailable(key) then
        FocusLayer(ui, key == "targetScale" and "native" or "enemy", key)
        return
    end
    if action == "decor" then
        local setting = DecorSetting(ui, key)
        local on = ui:LayerActive(key)
        P.Set(ID, setting, not on)
        ui.layers[key] = true
        if key == "focusMarker" or key == "glow" then ui.focusSample = true end
        if key == "targetScale" then ui.targetSample = true end
        ui:Paint()
        return
    end
    if action == "level" then return ToggleLevel(ui, key) end
    if action == "target" then return Markers.ToggleTarget(ui, OpenSetting) end
    if not ui:LayerAvailable(key) then
        return FocusUnavailableLayer(ui, key)
    end
    if action == "skin" then
        ToggleSkinLayer(ui, key)
        return
    end
    if action == "live" then
        ToggleLive(ui, key)
        return
    end
    if key == "classification" then
        ToggleClassification(ui, key)
        return
    end
    if key == "raidIcon" then
        ui.raidMarked, ui.layers[key] = not ui.raidMarked, true
        ui.raidIndex = ui.raidMarked and 8 or 0
    elseif key == "castShield" then
        ui.uninterruptible, ui.layers[key] = not ui.uninterruptible, true
    elseif action == "marker" then
        Markers.ToggleMarker(ui, key)
    else
        ui.layers[key] = not ui:LayerOn(key)
        if key == "highlightBorders" and not ui.layers[key] then ui.highlightSample = nil end
    end
    ui:Paint()
    if key == "questMarker" and ui.sampleKind == "enemy" and ui:LayerActive(key) and ui.questMarkerHandle then
        ui:Select(ui.questMarkerHandle)
    end
end

-- The hint a layer button shows: live layers change a real setting, the others only the preview.
local function LayerHelp(key)
    return LayerAction(key) and "Click: change live setting; right-click: settings"
        or key == "guides" and "Click: show or hide preview guides"
        or "Click: show or hide preview; right-click: settings"
end

local CONTEXT_LAYERS = {
    anchor = { guides = true, health = true, name = true, cast = true, auras = true, buffs = true, status = true,
        targetBorder = true, focusBorder = true, aggroBorder = true, mouseoverBorder = true },
    auras = { buffs = true, auras = true, controlAura = true },
    text = { status = true, name = true, level = true, healthText = true, enemyPower = true },
    cast = { cast = true, castText = true, castTime = true, castIcon = true, castShield = true, castTarget = true },
    status = { status = true, level = true, classification = true, raidIcon = true, target = true, eliteMarker = true, questMarker = true,
        focusMarker = true, softTarget = true, threatFlash = true, threatHighlight = true },
    opacity = { health = true, backdrop = true, name = true, healthText = true, enemyPower = true },
    highlight = { health = true, border = true, highlightBorders = true,
        targetBorder = true, focusBorder = true, aggroBorder = true, mouseoverBorder = true },
    power = { enemyPower = true },
}

local GROUPS = {
    { "Plate", "guides health backdrop border roleFill outerFrame shadow glow targetScale" },
    { "Highlight Borders", "highlightBorders targetBorder focusBorder aggroBorder mouseoverBorder" },
    { "Text", "status name level healthText enemyPower" },
    { "Castbar", "cast castText castTime castIcon castShield castTarget" },
    { "Auras", "auras buffs controlAura" },
    { "Status icons", "status classification raidIcon target eliteMarker questMarker focusMarker threshold threatFlash threatHighlight softTarget" },
}
for _, group in ipairs(GROUPS) do
    local keys, members = {}, {}
    for key in group[2]:gmatch("%S+") do
        keys[#keys + 1] = key
        members[key] = true
    end
    group[2], group.members = keys, members
end

local function AddVisible(ui, button)
    local enemyAggro = button.layerKey ~= "aggroBorder" or ui.sampleKind == "enemy" and ui.scope ~= "neutral"
    button:SetShown(enemyAggro)
    if enemyAggro then ui.visibleLayerButtons[#ui.visibleLayerButtons + 1] = button end
end

local function VisibleButtons(ui)
    local visible = ui.visibleLayerButtons
    for i = #visible, 1, -1 do visible[i] = nil end
    if ui.layerGroup then
        for _, button in ipairs(ui.layerButtons) do
            if not ui.layerGroup.members[button.layerKey] then button:Hide() end
        end
        for _, key in ipairs(ui.layerGroup[2]) do AddVisible(ui, ui.layerByKey[key]) end
        return visible
    end
    local relevant = CONTEXT_LAYERS[ui.layerContext] or CONTEXT_LAYERS.anchor
    for _, button in ipairs(ui.layerButtons) do
        if relevant[button.layerKey] then AddVisible(ui, button)
        else button:Hide() end
    end
    return visible
end

local function ShowGroups(ui, button)
    if P.Combat() then return end
    local function Select(group)
        ui.layerGroup = group
        ui:Layout()
        ui:Paint()
    end
    P.AnchoredContextMenu(button, function(_, menu)
        if menu.CreateTitle then menu:CreateTitle(Tr("All layers")) end
        menu:CreateButton(Tr("Relevant layers"), function() Select(nil) end)
        for _, group in ipairs(GROUPS) do
            menu:CreateButton(Tr(group[1]), function() Select(group) end)
        end
    end)
end

local function BuildRailLayout(ui, rail, title)
    local toggle = T.Button(rail, "Relevant layers", 110, 22)
    if T.CenterButtonLabel then T.CenterButtonLabel(toggle) end
    local measure = T.Font(rail, "GameFontDisableSmall", "", T.colors.muted)
    measure:Hide()
    toggle:SetPoint("TOPRIGHT", rail, "TOPRIGHT", -8, -6)
    toggle:SetScript("OnClick", function() ShowGroups(ui, toggle) end)
    Register(toggle, "layers.all", "All layers")
    ui.layerGroupButton = toggle
    function ui:LayoutLayerRail()
        local width = rail:GetWidth()
        if not width or width <= 16 then return end
        local groupName = self.layerGroup and self.layerGroup[1] or "Relevant layers"
        local caption = Tr(groupName) .. " ▾"
        P.SetButtonText(toggle, caption)
        local toggleLabel = HM.GetControlLabel(toggle)
        local measureWidth = toggleLabel and toggleLabel.GetUnboundedStringWidth
        if not measureWidth then P.SetTranslatedText(measure, caption) end
        local textWidth = measureWidth and measureWidth(toggleLabel) or measure:GetStringWidth()
        toggle:SetWidth(math.min(width - 16, math.max(86, math.ceil(textWidth) + 28)))
        local titleWidth = title:GetStringWidth()
        local separate = titleWidth + toggle:GetWidth() + 22 > width
        toggle:ClearAllPoints()
        toggle:SetPoint("TOPRIGHT", rail, "TOPRIGHT", -8, separate and -26 or -6)
        local top = separate and 52 or 32
        local x = 8
        for _, button in ipairs(VisibleButtons(self)) do
            local label = button.fs or HM.GetControlLabel(button)
            local measureWidth = label and (label.GetUnboundedStringWidth or label.GetStringWidth)
            local naturalWidth = measureWidth and math.ceil(measureWidth(label)) + button.labelPadding or button.layerWidth
            local size = math.min(width - 16, naturalWidth)
            if x > 8 and x + size > width - 8 then x, top = 8, top + 26 end
            button:SetWidth(size)
            button:ClearAllPoints()
            button:SetPoint("TOPLEFT", rail, "TOPLEFT", x, -top)
            x = x + size + 5
        end
        rail:SetHeight(top + 28)
    end
end

local function AddSettingsLink(button, ui, section, key, label)
    local link = CreateFrame("Button", nil, button)
    link:SetSize(20, 20)
    link:SetPoint("RIGHT", button, "RIGHT", -1, 0)
    link:SetIgnoreParentAlpha(true)
    link:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    local glyph = link:CreateTexture(nil, "ARTWORK")
    glyph:SetTexture("Interface\\AddOns\\MidnightSimpleUnitFrames\\Media\\msuf_dropdown_chevron_down.tga")
    glyph:SetSize(9, 9)
    glyph:SetPoint("CENTER", link, "CENTER", 0, 0)
    glyph:SetRotation(math.pi / 2)
    glyph:SetAlpha(.72)
    local highlight = link:CreateTexture(nil, "HIGHLIGHT")
    highlight:SetAllPoints(link)
    highlight:SetColorTexture(1, 1, 1, .18)
    link:SetScript("OnClick", function() FocusLayer(ui, section, key) end)
    HM.SkipHistoryCheckpoint(link)
    if M.AddTooltip then M.AddTooltip(link, "Open settings", label, { hook = true }) end
    button.settingsLink = link
end

local function BuildButtons(ui, rail)
    local measure = T.Font(rail, "GameFontDisableSmall", "", T.colors.muted)
    measure:Hide()
    ui.layerButtons, ui.visibleLayerButtons, ui.layerByKey = {}, {}, {}
    for i, def in ipairs(PrepareLayers()) do
        local key, label, section = def[1], def[2], def[3]
        local button
        local adjustable = key ~= "guides"
        if H.CreateLayerButton then
            button = H.CreateLayerButton(rail, ui,
                { key = key, label = label, color = LAYER_COLORS[key] }, i, 95,
                { Tr = Tr, layout = "chip", height = 22, showOffText = false, quiet = true,
                    IsAvailable = function(owner, layer) return owner:LayerAvailable(layer) end,
                    IsOn = function(owner, layer) return owner:LayerActive(layer) end })
        else
            button = T.Button(rail, label, 95, 22)
        end
        P.SetTranslatedText(measure, Tr(label))
        button.labelPadding = adjustable and 52 or 30
        button.layerWidth = math.ceil(measure:GetStringWidth()) + button.labelPadding
        local text = button.fs or HM.GetControlLabel(button)
        if text then
            text:SetPoint("RIGHT", button, "RIGHT", adjustable and -25 or -6, 0)
            text:SetJustifyH("LEFT")
            text:SetWordWrap(false)
        end
        if adjustable then AddSettingsLink(button, ui, section, key, label) end
        button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        button.layerKey = key
        button:SetScript("OnClick", function(_, mouseButton)
            if mouseButton == "RightButton" then
                if adjustable then FocusLayer(ui, section, key) end
                return
            end
            ToggleLayer(ui, key)
        end)
        HM.SetCommandAction(button, { kind = "toggle", historyMode = "none",
            get = function() return ui:LayerActive(key) end,
            set = function(desired)
                desired = desired == true
                if ui:LayerActive(key) ~= desired then ToggleLayer(ui, key) end
                return ui:LayerActive(key) == desired
            end })
        if M.AddTooltip then M.AddTooltip(button, label, LayerHelp(key), { hook = true }) end
        Register(button, "layer." .. key, Tr("%s preview layer"):format(Tr(label)))
        ui.layerButtons[#ui.layerButtons + 1] = button
        ui.layerByKey[key] = button
    end
end

function Layers.Build(ui)
    local rail = CreateFrame("Frame", nil, ui.body, "BackdropTemplate")
    rail:SetPoint("BOTTOMLEFT", ui.body, "BOTTOMLEFT", 0, 4)
    rail:SetPoint("BOTTOMRIGHT", ui.body, "BOTTOMRIGHT", 0, 4)
    rail:SetHeight(80)
    local title = P.PreviewInteraction.LayerRailTitle and P.PreviewInteraction.LayerRailTitle(rail)
    if not title then
        local background = rail:CreateTexture(nil, "BACKGROUND")
        background:SetAllPoints(rail)
        background:SetColorTexture(.04, .06, .09, .96)
        local border = Style.CreateBorder(rail)
        Style.PaintBorder(border, rail, 1, "9e997f")
        title = T.Font(rail, "GameFontDisableSmall", "Preview Layers", T.colors.muted)
    end
    title:SetPoint("TOPLEFT", rail, "TOPLEFT", 8, -8)
    BuildButtons(ui, rail)
    BuildRailLayout(ui, rail, title)
    ui.layerRail = rail
end

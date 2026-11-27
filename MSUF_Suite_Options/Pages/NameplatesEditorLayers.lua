local _, P = ...
local M, W = P.M, P.W
local Style, Auras = P.Suite.NameplateStyle, P.Suite.NameplateAuraDisplay
local ID, PAGE = "nameplates", "suite_nameplates"
local Markers = P.NameplatesEditorMarkers
local NativeBit = Style.NativeBit

-- The nameplate preview's layers: which layer a sample shows, the live
-- settings behind it and the click and right-click actions on a layer
-- (NameplatesElementPanel.lua shows them as the element list).
-- NameplatesEditor.lua installs On, Available and Active as the editor's
-- LayerOn, LayerAvailable and LayerActive methods. Register and OpenSetting
-- link every preview control to search and to its setting.
local Layers = {}
P.NameplatesEditorLayers = Layers
local DECOR_LAYERS = {
    outerFrame = "OuterFrame", shadow = "ShadowEnabled", glow = "GlowEnabled",
    focusMarker = "enemyFocusMarker", threshold = "enemyThresholdEnabled",
    targetScale = "targetScaleEnabled",
}
function Layers.DecorSetting(ui, key)
    local suffix = DECOR_LAYERS[key]
    if not suffix or not suffix:match("^[A-Z]") then return suffix end
    local scope = ui.scope or ui.sampleKind
    if P.Get(ID, Style.AppearanceSwitch(scope, "outline")) then return scope .. "Style" .. suffix end
    return ui.sampleKind .. suffix
end
local DecorSetting = Layers.DecorSetting

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
        { "name", "Name", "elements" }, { "healthText", "HP text", "elements" },
        { "enemyPower", "Enemy power bar", "enemyPower" }, { "cast", "Castbar", "castbar" },
        { "auras", "Debuffs", "auras" }, { "buffs", "Buffs", "auras" }, { "controlAura", "Control effects", "auras" },
        { "status", "Status icons", "markers" },
        { "backdrop", "Skin backdrop", "enemy" }, { "border", "Skin border", "enemy" },
        { "highlightBorders", "Highlight Borders", "signals" },
        { "aggroBorder", "Aggro border", "signals" }, { "targetBorder", "Target border", "signals" },
        { "focusBorder", "Focus border", "signals" }, { "mouseoverBorder", "Mouseover border", "signals" },
        { "roleFill", "Role fill", "roleColors" },
        { "outerFrame", "Outer frame", "enemy" }, { "shadow", "Shadow", "enemy" },
        { "glow", "Glow", "enemy" },
        { "threshold", "Threshold", "enemy" }, { "focusMarker", "Focus diamond", "enemy" },
        { "targetScale", "Target size", "native" },
        { "level", "Level", "elements" },
        { "castText", "Spell name", "castbar" }, { "castTime", "Cast time", "castbar" },
        { "classification", "Elite / rare", "elements" }, { "raidIcon", "Raid mark", "elements" },
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
    if key == "guides" then return true end
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

local function OutlineSetting(ui)
    local scope = ui.scope or ui.sampleKind
    local toggle = Style.AppearanceSwitch(scope, "outline")
    return P.Get(ID, toggle) and scope .. "StyleOutlineMode" or toggle
end

local function OutlineSize(config, side)
    return Style.OutlineSize(config[side .. "OutlineMode"], config[side .. "BorderEnabled"],
        config[side .. "BorderSize"], config.hideHealthBarBorders)
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
        return OutlineSize(Style.ScopeBars(ui.barSettings or P.S.Config(ID), ui.scope), ui.sampleKind) > 0
    end
    if key == "highlightBorders" then
        local c = P.S.Config(ID)
        return ui.highlightSample ~= nil or c.highlightTarget or c.highlightFocus or c.highlightMouseover
            or ui.sampleKind == "enemy" and Style.AggroHighlightEnabled(c)
    end
    if key == "roleFill" then return P.Get(ID, "enemyRoleColors") end
    if key == "target" then
        return Markers.TargetActive(ui) and (ui.statusSample == "target" or ui.allStatusSamples
            or ui.highlightSample == "target" or ui.targetSample == true or ui.targetSample == nil and ui.sampleKind == "enemy")
    end
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
    if (key == "cast" or key == "castText" or key == "castTime" or key == "castIcon" or key == "castTarget" or key == "castShield")
        and (not ui:LayerOn("cast") or not ui.castSample and ui.castingSample == false) then return false end
    if key == "castShield" then return ui.uninterruptible == true or ui.castSample == "CastShield" end
    if key == "focusMarker" then
        return ui.statusSample == "focusMarker" or ui.allStatusSamples or ui.highlightSample == "focus" or ui.focusSample == true
    end
    local role = not ui.enemyPlayer and (ui.questSample and 5 or ui.previewRole or P.Get(ID, "enemyPreviewRole"))
    if key == "classification" then
        return ui.statusSample == "Classification" or ui.allStatusSamples or not ui.raidMarked and (ui.sampleKind == "friendly" and ui.friendlyElite
            or ui.sampleKind == "enemy" and (role == 3 or role == 4))
    end
    if key == "eliteMarker" or key == "questMarker" then
        local kind = key == "eliteMarker" and "Elite" or "Quest"
        if not P.Get(ID, ui.sampleKind .. kind .. "Marker") then return false end
        if ui.sampleKind == "friendly" then return ui.friendlyElite == true end
        if ui.statusSample == (key == "eliteMarker" and "elite" or "quest") or ui.allStatusSamples then return true end
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
        P.OpenNameplateStatusSection(ui.sampleKind, nil, ui.scope)
        return
    end
    if key == "castShield" then
        if ui:CanPickElement() then return ui:Edit("cast", "CastShield") end
        P.OpenNameplateCastDetail(ui.sampleKind, "general")
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
    elseif key == "border" then
        setting = OutlineSetting(ui)
    elseif key == "backdrop" then
        setting = ui.sampleKind .. "BackdropEnabled"
    elseif key == "raidIcon" then
        setting = ui.sampleKind .. "RaidIcon"
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
    if P.OpenNameplateStatusItem(ui.sampleKind, setting, ui.scope) or OpenSetting(setting) then return end
    if key == "castTarget" and P.OpenNameplateCastDetail(ui.sampleKind, "spell") then return end
    local target = section == "elements" and P.SelectNameplatesEnemyTab("elements")
        or ui.sections and ui.sections[section]
    if target and W.FocusCollapsibleSection then
        W.FocusCollapsibleSection(target, { persist = true, flash = true })
    end
end
Layers.Focus = FocusLayer

local CAST_LAYERS = { cast = true, castText = true, castTime = true, castIcon = true, castShield = true, castTarget = true }

local function DisabledFeature(ui, key, c)
    if AURA_KIND[key] and not AuraOn(ui, key) then return AuraSetting(ui, key) end
    if key == "enemyPower" then
        if not c.enemy then return "enemy" end
        if not c.enemyPowerEnabled then return "enemyPowerEnabled" end
    end
    if key == "target" and not Markers.TargetActive(ui) then
        return c.enemyTargetMarker and "enemyTargetHideFriendly" or "enemyTargetMarker"
    end
    if key == "softTarget" and not SoftOn(ui) then
        if not NativeToggle("softTargetIconGate", "SoftTargetNameplateSize") then return "softTargetIconGate" end
        local name = ui.sampleKind == "enemy" and (ui.softInteract and "Interact" or "Enemy") or "Friend"
        return "softTarget" .. name
    end
    if (key == "threatFlash" or key == "threatHighlight") and not ThreatOn(key) then
        return c.threatSignalMode == 2 and key or "threatSignalMode"
    end
end

local function DisabledHighlight(ui, key, config)
    local sample = HIGHLIGHT_SAMPLES[key]
    if sample == "aggro" then
        if not Style.AggroHighlightEnabled(config) then return "highlightAggro" end
    elseif sample then
        local setting = HIGHLIGHT_SETTINGS[sample]
        if not config[setting] then return setting end
    elseif key == "highlightBorders" and not (config.highlightTarget or config.highlightFocus or config.highlightMouseover
        or ui.sampleKind == "enemy" and Style.AggroHighlightEnabled(config)) then
        return "highlightTarget"
    end
end

local function BlockedLayer(ui, key)
    if key == "guides" then return end
    if Layers.NPCWorldNames(ui) then return "friendlyNPCs" end
    local c, side = P.S.Config(ID), ui.sampleKind
    if key == "name" and c.look ~= 2 and c[side] and c[side .. "NameVisible"] == false then return side .. "NameVisible" end
    if key == "healthText" and side == "enemy" and c.look ~= 2 and c.enemyTextMode == 5 then return "enemyTextMode" end
    if CAST_LAYERS[key] and c.look ~= 2 and c.enemyCastEnabled == 3 then return "enemyCastEnabled" end
    if not ui:LayerAvailable(key) then
        if c.look == 2 then return "look" end
        return true
    end
    local setting = DecorSetting(ui, key)
    if key == "level" and c.look ~= 2 then setting = side .. "LevelEnabled" end
    if key == "eliteMarker" then setting = side .. "EliteMarker" end
    if key == "questMarker" then setting = side .. "QuestMarker" end
    if setting and c[setting] == false then return setting end
    if key == "roleFill" and not c.enemyRoleColors then return "enemyRoleColors" end
    if key == "backdrop" then
        if not c[side .. "BackdropEnabled"] then return side .. "BackdropEnabled" end
        if c[side .. "BackdropAlpha"] == 0 then return side .. "BackdropAlpha" end
    end
    if key == "border" then
        local bars = Style.ScopeBars(ui.barSettings or c, ui.scope)
        if OutlineSize(bars, side) <= 0 then return OutlineSetting(ui) end
    end
    return DisabledHighlight(ui, key, c) or DisabledFeature(ui, key, c)
end

function Layers.SetShown(ui, key, show)
    ui.layers[key] = show
    if show and STATUS_LAYERS[key] then ui.layers.status = true end
end

local function ToggleLayer(ui, key)
    Layers.SetShown(ui, key, not ui:LayerOn(key))
    ui:Paint()
end

-- The panel's view of a layer: its label, color and settings section.
local DEFS
function Layers.Def(key)
    if not DEFS then
        DEFS = {}
        for _, def in ipairs(PrepareLayers()) do
            DEFS[def[1]] = { key = def[1], label = def[2], section = def[3], color = LAYER_COLORS[def[1]] }
        end
    end
    return DEFS[key]
end
Layers.Toggle, Layers.Blocked = ToggleLayer, BlockedLayer
Layers.STATUS_LAYERS = STATUS_LAYERS

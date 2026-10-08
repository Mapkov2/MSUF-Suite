local _, P = ...
local M, W, T, Tr, HM = P.M, P.W, P.T, P.Tr, P.HM
local Style = P.Suite.NameplateStyle
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
-- Match unit-preview colors and group related nameplate layers.
local LAYER_COLORS = {
    guides = { 0.42, 0.72, 1.00 }, health = { 0.25, 0.90, 0.42 },
    backdrop = { 0.80, 0.55, 0.25 }, border = { 0.85, 0.70, 0.25 }, roleFill = { 0.30, 0.78, 0.55 },
    name = { 0.30, 0.66, 1.00 }, level = { 0.30, 0.66, 1.00 }, healthText = { 0.25, 0.90, 0.42 },
    cast = { 0.20, 0.90, 0.85 }, castText = { 0.20, 0.90, 0.85 }, castTime = { 0.20, 0.90, 0.85 },
    auras = { 0.90, 0.20, 0.22 }, buffs = { 0.20, 0.90, 0.35 }, controlAura = { 0.90, 0.42, 1.00 },
    classification = { 0.95, 0.72, 0.18 }, raidIcon = { 0.95, 0.72, 0.18 }, power = { 0.95, 0.72, 0.18 },
    castIcon = { 0.20, 0.90, 0.85 }, castShield = { 0.20, 0.90, 0.85 }, castTarget = { 0.20, 0.90, 0.85 },
    target = { 0.95, 0.72, 0.18 }, eliteMarker = { 0.95, 0.72, 0.18 }, questMarker = { 0.95, 0.72, 0.18 },
    threatFlash = { 0.90, 0.20, 0.22 }, threatHighlight = { 0.90, 0.20, 0.22 }, softTarget = { 0.25, 0.72, 1.00 },
}
local LAYERS = {
    { "guides", "Guides", "enemy" }, { "health", "Blizzard health", "enemy" },
    { "backdrop", "Skin backdrop", "enemy" }, { "border", "Skin border", "enemy" },
    { "roleFill", "Role fill", "enemy" },
    { "name", "Name", "elements" }, { "level", "Level", "elements" },
    { "healthText", "HP text", "elements" },
    { "cast", "Castbar", "castbar" },
    { "castText", "Spell name", "elements" }, { "castTime", "Cast time", "castbar" },
    { "auras", "Debuffs", "auras" },
    { "buffs", "Buffs", "auras" }, { "controlAura", "Control", "auras" },
    { "classification", "Elite / rare", "elements" }, { "raidIcon", "Raid mark", "elements" },
    { "castIcon", "Spell icon", "elements" }, { "castShield", "Blizzard shield", "castbar" },
    { "castTarget", "Cast target", "elements" }, { "target", "Target arrows", "enemy" },
    { "eliteMarker", "MSUF elite", "enemy" }, { "questMarker", "MSUF quest", "enemy" },
    { "threatFlash", "Aggro flash", "signals" },
    { "threatHighlight", "Aggro highlight", "signals" },
    { "softTarget", "Soft target", "signals" },
    { "power", "Power skin", "personal" },
}
local LAYER_SETTING = {
    health = "enemyHealthWidthDelta", backdrop = "enemyBackdropEnabled", border = "enemyBorderEnabled",
    roleFill = "enemyRoleColors", target = "enemyTargetMarker",
    name = "enemyTextMode", level = P.Suite.Client.isForever and "levelAppearance" or "enemyLevelEnabled",
    healthText = "enemyTextMode",
    cast = "enemyCastEnabled", castText = "enemyCastSpellName", castTime = "enemyCastTimeEnabled",
    classification = "enemyRarityIcon", raidIcon = "enemyRaidIcon",
    castIcon = "enemyCastSpellIcon", castShield = "enemyCastEnabled",
    castTarget = "enemyCastSpellTarget",
}
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

local function AuraGroup(ui)
    if ui.sampleKind == "enemy" then return ui.enemyPlayer and "enemyPlayer" or "enemyNpc" end
    if ui.friendlyElite and not ui.personal then return nil end
    return "friendlyPlayer"
end

local AURA_KIND = { auras = "Debuffs", buffs = "Buffs", controlAura = "Control" }
Layers.AuraElement = { Auras = "auras", Buffs = "buffs", ControlAura = "controlAura" }
local function AuraOn(ui, key)
    local group = AuraGroup(ui)
    if not group then return key == "auras" and NativeToggle("friendlyNpcDebuffs", "nameplateShowDebuffsOnFriendly") end
    local kind = AURA_KIND[key]
    if P.Get(ID, "look") ~= 2 and P.Get(ID, group .. "AuraMode") == 2 then
        return P.Get(ID, group .. kind)
    end
    return NativeBit(Style.AuraCVar[group], Style.AuraBits[kind], true)
end

local function ToggleAura(ui, key)
    local group = AuraGroup(ui)
    if not group then
        if key ~= "auras" then return end
        P.Set(ID, "friendlyNpcDebuffs", AuraOn(ui, key) and 3 or 2)
    elseif P.Get(ID, group .. "AuraMode") == 2 then
        local setting = group .. AURA_KIND[key]
        P.Set(ID, setting, not P.Get(ID, setting))
    else
        local values = { [group .. "AuraMode"] = 2 }
        for kind, bit in pairs(Style.AuraBits) do
            values[group .. kind] = NativeBit(Style.AuraCVar[group], bit, true)
        end
        local setting = group .. AURA_KIND[key]
        values[setting] = not values[setting]
        P.SetMany(ID, values)
    end
    ui.layers[key] = true
end
local function Register(widget, key, label)
    if M.RegisterControlMetadata then
        M.RegisterControlMetadata(widget, P.Meta(PAGE, ID, "preview." .. key, "action", "suite_nameplates_preview"), label, "button")
    end
end
local function OpenSetting(key, label)
    if not key or type(M.OpenExactSettingControl) ~= "function" then return false end
    return M.OpenExactSettingControl("msufsuite.nameplates." .. key, Tr(label), PAGE) ~= false
end
Layers.AURA_KIND, Layers.AuraGroup = AURA_KIND, AuraGroup
Layers.Register, Layers.OpenSetting = Register, OpenSetting

function Layers.On(ui, key) return ui.layers[key] ~= false end

function Layers.Available(ui, key)
    local skinned = P.Get(ID, "look") ~= 2
    if key == "target" then return skinned end
    if key == "backdrop" or key == "border" then return skinned end
    if key == "roleFill" then return skinned and ui.sampleKind == "enemy" end
    if key == "power" then return ui.personal == true end
    if key == "level" then return true end
    if key == "threatFlash" or key == "threatHighlight" then return ui.sampleKind == "enemy" end
    if (key == "buffs" or key == "controlAura") and ui.sampleKind == "friendly"
        and ui.friendlyElite and not ui.personal then return false end
    if AURA_KIND[key] and ui.sampleKind == "friendly" and not ui.personal and not ui.friendlyElite then
        local display = P.Get(ID, "friendlyNamesOnly")
        if display == 2 or display == 3 or display == 1
            and Style.NativeToggle("nameplateShowOnlyNameForFriendlyPlayerUnits", false) then return false end
    end
    if key == "classification" then return not skinned or P.Get(ID, "enemyRarityIcon") ~= 3 end
    if key == "raidIcon" then return ui.sampleKind == "friendly" or not skinned or P.Get(ID, "enemyRaidIcon") end
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
    if key == "backdrop" then
        return P.Get(ID, ui.sampleKind .. "BackdropEnabled")
            and P.Get(ID, ui.sampleKind .. "BackdropAlpha") > 0
    end
    if key == "border" then
        return P.Get(ID, ui.sampleKind .. "BorderEnabled")
            and P.Get(ID, ui.sampleKind .. "BorderSize") > 0
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
    if key == "power" then return P.Get(ID, "look") ~= 2 and P.Get(ID, "personalPowerSkin") end
    if key == "level" then
        local classic = P.Suite.NameplateStyle.ClassicNativePlate(P.Get(ID, "nativeStyle"))
        if not P.Suite.Client.isForever then
            return classic or P.Get(ID, "look") ~= 2
                and P.Get(ID, ui.sampleKind .. "LevelEnabled")
        end
        local namesOnly = ui.sampleKind == "friendly" and not ui.personal
            and not ui.friendlyElite and (P.Get(ID, "friendlyNamesOnly") == 2
                or P.Get(ID, "friendlyNamesOnly") == 3
                or P.Get(ID, "friendlyNamesOnly") == 1 and P.Suite.NameplateStyle.NativeToggle(
                    "nameplateShowOnlyNameForFriendlyPlayerUnits", false))
        if namesOnly then return false end
        local badge = P.Get(ID, "look") == 2 or P.Get(ID, "levelAppearance") == 2
        if badge and not (P.Suite.Client.isForever or classic) then return false end
        return P.Get(ID, "look") == 2 or P.Get(ID, ui.sampleKind .. "LevelEnabled")
    end
    if key == "raidIcon" then return ui.raidMarked == true end
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
    if (section == "enemy" or key == "castTime") and ui.sampleKind == "friendly" then section = "friendly" end
    if section == "elements" and ui.sampleKind == "friendly"
        and (key == "name" or key == "level" or key == "healthText") then section = "friendly" end
    local target = section == "elements" and P.SelectNameplatesEnemyTab("elements")
        or ui.sections and ui.sections[section]
    if target and W.FocusCollapsibleSection then
        W.FocusCollapsibleSection(target, { persist = true, flash = true })
    end
    local setting = LAYER_SETTING[key]
    if key == "castTime" then
        setting = ui.sampleKind .. "CastTimeEnabled"
    elseif key == "backdrop" or key == "border" then
        setting = ui.sampleKind .. (key == "backdrop" and "BackdropEnabled" or "BorderEnabled")
    elseif ui.sampleKind == "friendly" and key == "health" then
        setting = "friendlyHealthWidthDelta"
    elseif ui.sampleKind == "friendly" and key == "target" then
        setting = "enemyTargetHideFriendly"
    elseif ui.sampleKind == "friendly" and (key == "name" or key == "healthText" or key == "level") then
        setting = key == "level" and (P.Suite.Client.isForever and "levelAppearance"
            or "friendlyLevelEnabled")
            or key == "name" and "friendlyTextEnabled" or "friendlyNamesOnly"
    end
    if AURA_KIND[key] then
        local group = AuraGroup(ui)
        setting = group and group .. AURA_KIND[key] or key == "auras" and "friendlyNpcDebuffs" or "friendlyNPCs"
        if not ui:LayerAvailable(key) and ui.sampleKind == "friendly" and not ui.personal and not ui.friendlyElite then
            section, setting = "friendly", "friendlyNamesOnly"
        end
    elseif key == "softTarget" then
        local name = ui.sampleKind == "enemy" and (ui.softInteract and "Interact" or "Enemy") or "Friend"
        setting = "softTarget" .. name
    elseif key == "threatFlash" or key == "threatHighlight" then setting = key
    elseif key == "eliteMarker" or key == "questMarker" then
        setting = ui.sampleKind .. (key == "eliteMarker" and "Elite" or "Quest") .. "Marker"
    elseif key == "power" then setting = "personalPowerSkin" end
    OpenSetting(setting, key)
end
Layers.Focus = FocusLayer

local function ToggleSkinLayer(ui, key)
    if P.Get(ID, "look") == 2 then
        OpenSetting("look", "Look")
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
    local classic = P.Suite.NameplateStyle.ClassicNativePlate(P.Get(ID, "nativeStyle"))
    if P.Get(ID, "look") == 2 or classic and not P.Suite.Client.isForever then
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

-- The layers that change a live setting: auras, threat, soft target and personal power.
local function ToggleLive(ui, key)
    if P.Get(ID, "look") == 2 then
        OpenSetting("look", "Look")
        return
    end
    if AURA_KIND[key] then
        ToggleAura(ui, key)
    elseif key == "threatFlash" or key == "threatHighlight" then
        ToggleThreat(ui, key)
    elseif key == "softTarget" then
        ToggleSoftTarget(ui, key)
    else
        P.Set(ID, "personalPowerSkin", not P.Get(ID, "personalPowerSkin"))
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

local function ToggleLayer(ui, key)
    if key == "level" then
        ToggleLevel(ui, key)
        return
    end
    if key == "target" then
        Markers.ToggleTarget(ui, OpenSetting)
        return
    end
    if not ui:LayerAvailable(key) then
        local section = "elements"
        for _, layer in ipairs(LAYERS) do
            if layer[1] == key then
                section = layer[3]
                break
            end
        end
        FocusLayer(ui, section, key)
        return
    end
    if key == "backdrop" or key == "border" or key == "roleFill" then
        ToggleSkinLayer(ui, key)
        return
    end
    if AURA_KIND[key] or key == "threatFlash" or key == "threatHighlight"
        or key == "softTarget" or key == "power" then
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
    elseif key == "eliteMarker" or key == "questMarker" then
        Markers.ToggleMarker(ui, key)
    else
        ui.layers[key] = not ui:LayerOn(key)
    end
    ui:Paint()
    if key == "questMarker" and ui.sampleKind == "enemy" and ui:LayerActive(key) and ui.questMarkerHandle then
        ui:Select(ui.questMarkerHandle)
    end
end

-- The hint a layer button shows: live layers change a real setting, the others only the preview.
local function LayerHelp(key)
    local live = AURA_KIND[key] or key == "target" or key == "threatFlash" or key == "threatHighlight"
        or key == "softTarget" or key == "power" or key == "eliteMarker" or key == "questMarker"
        or key == "backdrop" or key == "border" or key == "roleFill"
    return live and "Click: change live setting; right-click: settings"
        or key == "guides" and "Click: show or hide preview guides"
        or "Click: show or hide preview; right-click: settings"
end

function Layers.Build(ui)
    local rail = CreateFrame("Frame", nil, ui.body, "BackdropTemplate")
    -- Like UF/GF, dock the rail inside the bottom of the preview. Its wrapped
    -- height belongs to the layout; growing down from a fixed canvas lets the
    -- last rows escape into the settings ScrollFrame.
    rail:SetPoint("BOTTOMLEFT", ui.body, "BOTTOMLEFT", 0, 4)
    rail:SetPoint("BOTTOMRIGHT", ui.body, "BOTTOMRIGHT", 0, 4)
    rail:SetHeight(80)
    local background = rail:CreateTexture(nil, "BACKGROUND")
    background:SetAllPoints(rail)
    background:SetColorTexture(0.04, 0.06, 0.09, 0.96)
    local border = P.Suite.NameplateStyle.CreateBorder(rail)
    P.Suite.NameplateStyle.PaintBorder(border, rail, 1, "9e997f")
    local title = T.Font(rail, "GameFontDisableSmall", "LAYERS", T.colors.muted)
    title:SetPoint("TOPLEFT", rail, "TOPLEFT", 8, -8)
    ui.layerButtons = {}
    for i, def in ipairs(LAYERS) do
        local key, label, section = def[1], def[2], def[3]
        local button
        if H.CreateLayerButton then
            button = H.CreateLayerButton(rail, ui,
                { key = key, label = label, color = LAYER_COLORS[key] }, i, 95,
                { Tr = Tr, layout = "chip", height = 20, showOffText = false, quiet = true,
                    IsAvailable = function(owner, layer) return owner:LayerAvailable(layer) end,
                    IsOn = function(owner, layer) return owner:LayerActive(layer) end })
        else
            button = T.Button(rail, label, 95, 20)
            button:SetSize(95, 20)
        end
        button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        button.layerKey = key
        button:SetScript("OnClick", function(_, mouseButton)
            if mouseButton == "RightButton" then
                FocusLayer(ui, section, key)
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
        button:SetScript("OnEnter", function()
            P.SetTranslatedText(ui.hint, Tr(label) .. " · " .. Tr(LayerHelp(key)))
        end)
        button:SetScript("OnLeave", function() P.SetTranslatedText(ui.hint, Tr(ui.help)) end)
        Register(button, "layer." .. key, Tr("%s preview layer"):format(Tr(label)))
        ui.layerButtons[#ui.layerButtons + 1] = button
    end
    function ui:LayoutLayerRail()
        local width = self.body:GetWidth()
        if not width or width < 300 then width = self.layoutWidth end
        if H.FlowLayerChips then
            H.FlowLayerChips(rail, self.layerButtons, { width = width, padX = 64,
                padXRight = 8, padY = 6, gapX = 5, gapY = 4, rowHeight = 20 })
        else
            local perRow = math.max(1, math.floor((width - 64) / 100))
            for i, button in ipairs(self.layerButtons) do
                local row, col = math.floor((i - 1) / perRow), (i - 1) % perRow
                button:ClearAllPoints()
                button:SetPoint("TOPLEFT", rail, "TOPLEFT", 64 + col * 100, -6 - row * 24)
            end
            rail:SetHeight(12 + math.ceil(#self.layerButtons / perRow) * 20
                + math.max(0, math.ceil(#self.layerButtons / perRow) - 1) * 4)
        end
    end
    ui.layerRail = rail
end

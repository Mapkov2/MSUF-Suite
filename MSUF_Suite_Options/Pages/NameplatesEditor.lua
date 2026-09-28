local _, P = ...
local M, W, T, Tr = P.M, P.W, P.T, P.Tr
local Style = P.Suite.NameplateStyle
local ID, PAGE = "nameplates", "suite_nameplates"
local SB, H = M.PreviewSelectionBar, M.PreviewHelpers or {}
local Markers = P.NameplatesEditorMarkers
local NativeBit = Style.NativeBit
local Editor = {}
P.NameplatesEditor = Editor
local DELTA = { LEFT = { -1, 0 }, RIGHT = { 1, 0 }, UP = { 0, 1 }, DOWN = { 0, -1 } }
local RAID_MARK_NAMES = { [0] = "Off", [1] = "Star", [2] = "Circle", [3] = "Diamond",
    [4] = "Triangle", [5] = "Moon", [6] = "Blue square", [7] = "Cross", [8] = "Skull" }
local ENEMY_ELEMENT_SETTINGS = { Name = true, Level = true, HealthText = true, Classification = true,
    RaidIcon = true, Cast = true, CastText = true, CastTime = true,
    CastIcon = true, CastShield = true, CastTarget = true }
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
local ELEMENT_SETTING = {
    Name = "enemyTextMode", Level = "enemyLevelEnabled", HealthText = "enemyTextMode", Cast = "enemyCastEnabled",
    CastText = "enemyCastSpellName", CastTime = "enemyCastTimeEnabled", RaidIcon = "enemyRaidIcon",
    Classification = "enemyRarityIcon", CastIcon = "enemyCastSpellIcon",
    CastTarget = "enemyCastSpellTarget",
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
local function Clamp(v, lo, hi) return math.max(lo, math.min(hi, v)) end
local function Round(v) return math.floor(v + 0.5) end
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
local function Focus(ui, handle)
    local section = handle and ui.sections and ui.sections[handle.section]
    if handle and handle._npSettingsTab and P.SelectNameplatesEnemyTab then
        section = P.SelectNameplatesEnemyTab(handle._npSettingsTab) or section
    end
    if section and W.FocusCollapsibleSection then W.FocusCollapsibleSection(section, { persist = true, flash = true }) end
    if handle then
        local key = handle._npSettingKey
        local kind = handle._key and handle._key:match("%.([%a]+)$")
        if kind and AURA_KIND[kind] then
            local group = AuraGroup(ui)
            key = group and group .. AURA_KIND[kind] or "friendlyNpcDebuffs"
        elseif handle._key and handle._key:find("%.SoftTarget$", 1, false) then
            key = ui.sampleKind == "enemy" and (ui.softInteract and "softTargetInteract" or "softTargetEnemy")
                or "softTargetFriend"
        end
        OpenSetting(key, handle._label)
    end
end
local function Write(ui, handle, x, y)
    if P.Combat() then return false end
    local rules = P.catalog[ID].rules
    local xr, yr = rules[handle.keyX], rules[handle.keyY]
    if not xr or not yr then return false end
    local ok = P.SetMany(ID, { [handle.keyX] = Clamp(Round(x), xr.min, xr.max),
        [handle.keyY] = Clamp(Round(y), yr.min, yr.max) })
    ui:Paint()
    return ok ~= false
end
local function Read(handle) return P.Get(ID, handle.keyX), P.Get(ID, handle.keyY) end

function Editor:Select(handle)
    local previous = self.body._selectedHandle
    if previous and previous ~= handle then previous:EnableKeyboard(false) end
    self.body._selectedHandle = handle
    local active = handle and handle:IsShown() and not P.Combat() and self.body:IsShown() or false
    if handle then handle:EnableKeyboard(active) end
    if M.SetPreviewArrowBindings then M.SetPreviewArrowBindings(self.body, active, self.bindings) end
    if active and H.FocusKeyboardTarget then
        H.FocusKeyboardTarget(self.body, handle, false, { selectedField = "_selectedHandle" })
    elseif not active and H.ReleaseKeyboardCapture then H.ReleaseKeyboardCapture(self.body) end
    self:RefreshSelection()
end

function Editor:RefreshSelection()
    local selected = self.body._selectedHandle
    for _, handle in ipairs(self.handles) do
        handle.outline(handle == selected and 1 or 0, "4ebaff")
    end
    if SB then SB.Refresh(self.body) end
    if self.RefreshSizeSelection then self:RefreshSizeSelection() end
end

local function Nudge(ui, dx, dy)
    local handle = ui.body._selectedHandle
    if P.Combat() or not ui.body:IsShown() or not handle or not handle:IsShown() then return false end
    if H.IsTextInputFocused and H.IsTextInputFocused() then return false end
    local focus = GetCurrentKeyBoardFocus and GetCurrentKeyBoardFocus()
    if focus and focus:IsObjectType("EditBox") then return false end
    local step = H.NudgeStep and H.NudgeStep() or (IsControlKeyDown() and 10 or IsShiftKeyDown() and 5 or 1)
    if H.ShouldSkipDuplicateNudge and H.ShouldSkipDuplicateNudge(ui.body, dx * step, dy * step) then return true end
    local x, y = Read(handle)
    return Write(ui, handle, x + dx * step, y + dy * step)
end

local function Key(self, key)
    local ui = self.previewUI
    if key == "ESCAPE" then
        ui:CancelDrag()
        ui:Select(nil)
        self:SetPropagateKeyboardInput(false)
    elseif key == "TAB" and SB and SB.CycleHandle then
        self:SetPropagateKeyboardInput(not SB.CycleHandle(ui.body, IsShiftKeyDown()))
    else
        local d = DELTA[key]
        self:SetPropagateKeyboardInput(not (d and Nudge(ui, d[1], d[2])))
    end
end

function Editor:CancelDrag()
    local handle = self.dragging
    if handle then handle:StopMovingOrSizing(); handle._npDrag = nil; self.dragging = nil end
    if self.panning then self.stage:StopMovingOrSizing(); self.panning = nil end
    self:Paint()
end

local function Start(self, button)
    if button and button ~= "LeftButton" then return end
    local ui = self.previewUI
    if P.Combat() or self._npDrag then return end
    ui:Select(self)
    self._npDragged = false
    local x, y = GetCursorPosition()
    local ox, oy = Read(self)
    self._npDrag = { x = x, y = y, ox = ox, oy = oy, scale = self:GetEffectiveScale() }
    ui.dragging = self
    self:StartMoving()
end

local function Stop(self, button)
    if button and button ~= "LeftButton" then return end
    local ui, drag = self.previewUI, self._npDrag
    if not drag then return end
    self:StopMovingOrSizing()
    self._npDrag, ui.dragging = nil, nil
    local x, y = GetCursorPosition()
    local dx, dy = x - drag.x, y - drag.y
    local moved = math.abs(dx) + math.abs(dy) >= 3
    self._npDragged = moved
    if not P.Combat() and moved then
        Write(ui, self, drag.ox + dx / drag.scale, drag.oy + dy / drag.scale)
        if H.NotePreviewElementMoved then H.NotePreviewElementMoved() end
    else
        ui:Paint()
    end
end

function Editor:Bind(handle, id, label, keyX, keyY, section)
    handle.previewUI, handle._key, handle._label = self, id, label
    handle._color, handle.keyX, handle.keyY, handle.section = { 0.3, 0.74, 1 }, keyX, keyY, section
    local enemyElement = id:match("^enemy%.(.+)$")
    if enemyElement and ENEMY_ELEMENT_SETTINGS[enemyElement] then
        handle._npSettingsTab = "elements"
        handle._npSettingKey = ELEMENT_SETTING[enemyElement]
    elseif id == "enemy.Health" then
        handle._npSettingKey = "enemyHealthWidthDelta"
    elseif id == "friendly.Health" then
        handle._npSettingKey = "friendlyHealthWidthDelta"
    elseif id == "friendly.Classification" or id == "friendly.Cast" or id == "friendly.CastText"
        or id == "friendly.CastIcon" or id == "friendly.CastTarget" then
        local element = id:match("^friendly%.(.+)$")
        handle._npSettingsTab = "elements"
        handle._npSettingKey = ELEMENT_SETTING[element]
    elseif id == "friendly.Name" or id == "friendly.HealthText" or id == "friendly.Level" then
        handle._npSettingKey = id == "friendly.Level" and "friendlyLevelEnabled" or "friendlyNamesOnly"
    elseif id == "personal.Power" then
        handle._npSettingKey = "personalPowerSkin"
    elseif id == "enemy.target" or id == "friendly.target" then
        handle._npSettingKey = id == "enemy.target" and "enemyTargetMarker" or "enemyTargetHideFriendly"
    elseif id == "enemy.elite" or id == "enemy.quest"
        or id == "friendly.elite" or id == "friendly.quest" then
        handle._npSettingKey = id:match("^enemy") and (id:find("elite") and "enemyEliteMarker" or "enemyQuestMarker")
            or (id:find("elite") and "friendlyEliteMarker" or "friendlyQuestMarker")
    elseif id:match("%.SoftTarget$") then
        handle._npSettingKey = id:match("^enemy") and "softTargetEnemy" or "softTargetFriend"
    elseif AURA_KIND[id:match("%.([%a]+)$")] then
        handle._npSettingKey = "enemyNpcAuraMode"
    end
    local border = P.Suite.NameplateStyle.CreateBorder(handle)
    handle.outline = function(size, color) P.Suite.NameplateStyle.PaintBorder(border, handle, size, color) end
    handle:EnableMouse(true)
    handle:SetMovable(true)
    handle:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    handle:RegisterForDrag("LeftButton")
    handle:EnableMouseWheel(true)
    handle:SetScript("OnMouseWheel", function(_, delta)
        self.zoom = Clamp(self.zoom + delta * 0.1, 0.5, 2)
        self:Paint()
    end)
    handle:SetScript("OnMouseDown", Start)
    handle:SetScript("OnMouseUp", Stop)
    handle:SetScript("OnDragStart", Start)
    handle:SetScript("OnDragStop", Stop)
    handle:SetScript("OnClick", function(_, button)
        self:Select(handle)
        if button == "RightButton" or button == "LeftButton"
            and (handle._npSettingsTab or handle._npSettingKey) and not handle._npDragged then
            Focus(self, handle)
        end
    end)
    handle:SetScript("OnEnter", function()
        handle.outline(1, "4ebaff")
        self.hint:SetText(Tr(label) .. " · " .. Tr(handle._npSettingsTab
            and "Drag to move; click for Blizzard settings" or "Drag to move; right-click for settings"))
    end)
    handle:SetScript("OnLeave", function() self:RefreshSelection(); self.hint:SetText(Tr(self.help)) end)
    handle:SetScript("OnKeyDown", Key)
    handle:SetScript("OnHide", function()
        if handle._npDrag then handle:StopMovingOrSizing(); handle._npDrag = nil; self.dragging = nil end
        if self.body._selectedHandle == handle then self:Select(nil) end
    end)
    self.handles[#self.handles + 1] = handle
    Register(handle, id, label)
end

function Editor:Paint()
    if self.dragging or self.panning then return end
    self.stage:ClearAllPoints()
    self.stage:SetPoint("CENTER", self.canvas, "CENTER", self.panX, self.panY)
    self.stage:SetScale(self.zoom)
    for _, render in ipairs(self.renderers) do render() end
    if self.contextButton then
        self.contextButton:SetText(Tr(self.inDungeon and "Dungeon / raid" or "Outdoor"))
    end
    if self.zoomLabel then self.zoomLabel:SetText(string.format("%d%%", Round(self.zoom * 100))) end
    if self.LayoutLayerRail then self:LayoutLayerRail() end
    for _, button in ipairs(self.layerButtons or {}) do
        if button.Refresh then button:Refresh()
        else button:SetAlpha(self:LayerActive(button.layerKey) and 1 or 0.42) end
    end
    if self.sampleButton then
        self.sampleButton:SetText(Tr(self.personal and "Personal plate" or self.sampleKind == "enemy"
            and "Enemy plate" or "Friendly plate"))
    end
    if self.roleButton then self.roleButton:SetShown(self.sampleKind == "enemy" and not self.enemyPlayer) end
    if self.enemyTypeButton then self.enemyTypeButton:SetShown(self.sampleKind == "enemy") end
    if self.softTypeButton then self.softTypeButton:SetShown(self.sampleKind == "enemy") end
    if self.questButton then self.questButton:SetShown(self.sampleKind == "enemy") end
    if self.friendlyTypeButton then self.friendlyTypeButton:SetShown(self.sampleKind == "friendly" and not self.personal) end
    for _, choice in ipairs(self.raidChoices or {}) do
        choice.outline(self.raidMarked and self.raidIndex == choice.index and 1 or 0, "4ebaff")
    end
    for _, button in ipairs(self.friendlyButtons or {}) do
        button:SetShown(self.sampleKind == "friendly" and not self.personal)
    end
    local selected = self.body._selectedHandle
    if selected and not selected:IsShown() then self:Select(nil) end
    self:RefreshSelection()
end

function Editor:LayerOn(key) return self.layers[key] ~= false end

function Editor:LayerAvailable(key)
    local skinned = P.Get(ID, "look") ~= 2
    if key == "target" then return skinned end
    if key == "backdrop" or key == "border" then return skinned end
    if key == "roleFill" then return skinned and self.sampleKind == "enemy" end
    if key == "power" then return self.personal == true end
    if key == "level" then return true end
    if key == "threatFlash" or key == "threatHighlight" then return self.sampleKind == "enemy" end
    if (key == "buffs" or key == "controlAura") and self.sampleKind == "friendly"
        and self.friendlyElite and not self.personal then return false end
    if AURA_KIND[key] and self.sampleKind == "friendly" and not self.personal and not self.friendlyElite then
        local display = P.Get(ID, "friendlyNamesOnly")
        if display == 2 or display == 3 or display == 1
            and Style.NativeToggle("nameplateShowOnlyNameForFriendlyPlayerUnits", false) then return false end
    end
    if key == "classification" then return not skinned or P.Get(ID, "enemyRarityIcon") ~= 3 end
    if key == "raidIcon" then return self.sampleKind == "friendly" or not skinned or P.Get(ID, "enemyRaidIcon") end
    if key == "cast" then return not skinned or P.Get(ID, "enemyCastEnabled") ~= 3 end
    if key == "castTime" then return skinned and P.Get(ID, self.sampleKind .. "CastTimeEnabled") end
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

function Editor:LayerActive(key)
    if not self:LayerOn(key) or not self:LayerAvailable(key) then return false end
    if key == "backdrop" then
        return P.Get(ID, self.sampleKind .. "BackdropEnabled")
            and P.Get(ID, self.sampleKind .. "BackdropAlpha") > 0
    end
    if key == "border" then
        return P.Get(ID, self.sampleKind .. "BorderEnabled")
            and P.Get(ID, self.sampleKind .. "BorderSize") > 0
    end
    if key == "roleFill" then return P.Get(ID, "enemyRoleColors") end
    if key == "target" then return Markers.TargetActive(self) end
    if AURA_KIND[key] then return AuraOn(self, key) end
    if key == "threatFlash" or key == "threatHighlight" then
        return self.aggroSample and ThreatOn(key)
    end
    if key == "softTarget" then
        return self.softTargetSample and SoftOn(self)
    end
    if key == "power" then return P.Get(ID, "look") ~= 2 and P.Get(ID, "personalPowerSkin") end
    if key == "level" then
        local classic = P.Suite.NameplateStyle.ClassicNativePlate(P.Get(ID, "nativeStyle"))
        if not P.Suite.Client.isForever then
            return classic or P.Get(ID, "look") ~= 2
                and P.Get(ID, self.sampleKind .. "LevelEnabled")
        end
        local namesOnly = self.sampleKind == "friendly" and not self.personal
            and not self.friendlyElite and (P.Get(ID, "friendlyNamesOnly") == 2
                or P.Get(ID, "friendlyNamesOnly") == 3
                or P.Get(ID, "friendlyNamesOnly") == 1 and P.Suite.NameplateStyle.NativeToggle(
                    "nameplateShowOnlyNameForFriendlyPlayerUnits", false))
        if namesOnly then return false end
        local badge = P.Get(ID, "look") == 2 or P.Get(ID, "levelAppearance") == 2
        if badge and not (P.Suite.Client.isForever or classic) then return false end
        return P.Get(ID, "look") == 2 or P.Get(ID, self.sampleKind .. "LevelEnabled")
    end
    if key == "raidIcon" then return self.raidMarked == true end
    if key == "castShield" then return self.uninterruptible == true end
    if key == "classification" then
        local role = self.previewRole or P.Get(ID, "enemyPreviewRole")
        return not self.raidMarked and (self.sampleKind == "friendly" and self.friendlyElite
            or self.sampleKind == "enemy" and (role == 3 or role == 4))
    end
    if key == "eliteMarker" or key == "questMarker" then
        local kind = key == "eliteMarker" and "Elite" or "Quest"
        if not P.Get(ID, self.sampleKind .. kind .. "Marker") then return false end
        if self.sampleKind == "friendly" then return self.friendlyElite == true end
        local role = self.previewRole or P.Get(ID, "enemyPreviewRole")
        return key == "eliteMarker" and (role == 3 or role == 4) or key == "questMarker" and role == 5
    end
    return true
end

local function Button(ui, parent, key, label, width, x, action)
    local button = T.Button(parent, Tr(label), width, 20)
    button:SetPoint("LEFT", parent, "LEFT", x, 0)
    button:SetScript("OnClick", action)
    Register(button, key, label)
    return button
end

local function FocusLayer(ui, section, key)
    if section == "enemy" and ui.sampleKind == "friendly" then section = "friendly" end
    if section == "elements" and ui.sampleKind == "friendly"
        and (key == "name" or key == "level" or key == "healthText") then section = "friendly" end
    local target = section == "elements" and P.SelectNameplatesEnemyTab
        and P.SelectNameplatesEnemyTab("elements") or ui.sections and ui.sections[section]
    if target and W.FocusCollapsibleSection then
        W.FocusCollapsibleSection(target, { persist = true, flash = true })
    end
    local setting = LAYER_SETTING[key]
    if key == "backdrop" or key == "border" then
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

local function ToggleSkinLayer(ui, key)
    if P.Get(ID, "look") == 2 then OpenSetting("look", "Look"); return end
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

local function ToggleLayer(ui, key)
    if key == "level" then
        local classic = P.Suite.NameplateStyle.ClassicNativePlate(P.Get(ID, "nativeStyle"))
        if P.Get(ID, "look") == 2 or classic and not P.Suite.Client.isForever then
            FocusLayer(ui, "elements", key)
        else
            P.Set(ID, ui.sampleKind .. "LevelEnabled", not P.Get(ID, ui.sampleKind .. "LevelEnabled"))
            ui.layers.level = true
            ui:Paint()
        end
        return
    end
    if key == "target" then Markers.ToggleTarget(ui, OpenSetting); return end
    if not ui:LayerAvailable(key) then
        local section = "elements"
        for _, layer in ipairs(LAYERS) do if layer[1] == key then section = layer[3]; break end end
        FocusLayer(ui, section, key)
        return
    end
    if key == "backdrop" or key == "border" or key == "roleFill" then
        ToggleSkinLayer(ui, key)
        return
    end
    if AURA_KIND[key] or key == "threatFlash" or key == "threatHighlight"
        or key == "softTarget" or key == "power" then
        if P.Get(ID, "look") == 2 then OpenSetting("look", "Look"); return end
        if AURA_KIND[key] then ToggleAura(ui, key)
        elseif key == "threatFlash" or key == "threatHighlight" then
            local active = ThreatOn(key)
            if ui.aggroSample or not active then
                local other = key == "threatFlash" and "threatHighlight" or "threatFlash"
                P.SetMany(ID, { threatSignalMode = 2, [key] = not active,
                    [other] = ThreatOn(other) })
            end
            ui.aggroSample, ui.layers[key] = true, true
        elseif key == "softTarget" then
            local name = ui.sampleKind == "enemy" and (ui.softInteract and "Interact" or "Enemy") or "Friend"
            local setting = "softTarget" .. name
            if ui.softTargetSample or not SoftOn(ui) then
                local show = not SoftOn(ui)
                local values = { [setting] = show and 2 or 3 }
                if show then values.softTargetIconGate = 2 end
                P.SetMany(ID, values)
            end
            ui.softTargetSample, ui.layers[key] = true, true
        else
            P.Set(ID, "personalPowerSkin", not P.Get(ID, "personalPowerSkin"))
            ui.layers[key] = true
        end
        ui:Paint()
        return
    end
    if key == "classification" then
        if ui.sampleKind == "friendly" then
            if not ui.friendlyElite then ui.friendlyElite, ui.layers[key] = true, true
            else ui.layers[key] = not ui:LayerOn(key) end
            ui:Paint()
            return
        end
        local wasFriendly = ui.sampleKind ~= "enemy"
        ui.sampleKind = "enemy"
        local role = ui.previewRole or P.Get(ID, "enemyPreviewRole")
        if wasFriendly or role ~= 3 and role ~= 4 or ui.raidMarked then
            ui.previewRole, ui.previewRoleSource, ui.raidMarked = 4, P.Get(ID, "enemyPreviewRole"), false
            ui.layers[key] = true
        else ui.layers[key] = not ui:LayerOn(key) end
    elseif key == "raidIcon" then
        ui.raidMarked, ui.layers[key] = not ui.raidMarked, true
        ui.raidIndex = ui.raidMarked and 8 or 0
    elseif key == "castShield" then
        ui.uninterruptible, ui.layers[key] = not ui.uninterruptible, true
    elseif key == "eliteMarker" or key == "questMarker" then
        Markers.ToggleMarker(ui, key)
    else ui.layers[key] = not ui:LayerOn(key) end
    ui:Paint()
    if key == "questMarker" and ui.sampleKind == "enemy" and ui:LayerActive(key) and ui.questMarkerHandle then
        ui:Select(ui.questMarkerHandle)
    end
end

local function BuildLayers(ui)
    local rail = CreateFrame("Frame", nil, ui.body, "BackdropTemplate")
    local anchor = ui.selection or ui.tools
    rail:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -6)
    rail:SetPoint("TOPRIGHT", anchor, "BOTTOMRIGHT", 0, -6)
    rail:SetHeight(80)
    local background = rail:CreateTexture(nil, "BACKGROUND")
    background:SetAllPoints(rail)
    background:SetColorTexture(0.04, 0.06, 0.09, 0.96)
    local border = P.Suite.NameplateStyle.CreateBorder(rail)
    P.Suite.NameplateStyle.PaintBorder(border, rail, 1, "9e997f")
    local title = T.Font(rail, "GameFontDisableSmall", Tr("LAYERS"), T.colors.muted)
    title:SetPoint("TOPLEFT", rail, "TOPLEFT", 8, -8)
    ui.layerButtons = {}
    for i, def in ipairs(LAYERS) do
        local key, label, section = def[1], def[2], def[3]
        local button
        if H.CreateLayerButton then
            button = H.CreateLayerButton(rail, ui,
                { key = key, label = label, color = { 0.43, 0.76, 1 } }, i, 95,
                { Tr = Tr, layout = "chip", height = 20, showOffText = false, quiet = true,
                    IsAvailable = function(owner, layer) return owner:LayerAvailable(layer) end,
                    IsOn = function(owner, layer) return owner:LayerActive(layer) end })
        else button = T.Button(rail, Tr(label), 95, 20); button:SetSize(95, 20) end
        button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        button.layerKey = key
        button:SetScript("OnClick", function(_, mouseButton)
            if mouseButton == "RightButton" then FocusLayer(ui, section, key); return end
            ToggleLayer(ui, key)
        end)
        button._msuf2CommandAction = { kind = "toggle", historyMode = "none",
            get = function() return ui:LayerActive(key) end,
            set = function(desired)
                desired = desired == true
                if ui:LayerActive(key) ~= desired then ToggleLayer(ui, key) end
                return ui:LayerActive(key) == desired
            end }
        button:SetScript("OnEnter", function()
            local live = AURA_KIND[key] or key == "target" or key == "threatFlash" or key == "threatHighlight"
                or key == "softTarget" or key == "power" or key == "eliteMarker" or key == "questMarker"
                or key == "backdrop" or key == "border" or key == "roleFill"
            local help = live and "Click: change live setting; right-click: settings"
                or key == "guides" and "Click: show or hide preview guides"
                or "Click: show or hide preview; right-click: settings"
            ui.hint:SetText(Tr(label) .. " · " .. Tr(help))
        end)
        button:SetScript("OnLeave", function() ui.hint:SetText(Tr(ui.help)) end)
        Register(button, "layer." .. key, label .. " preview layer")
        ui.layerButtons[#ui.layerButtons + 1] = button
    end
    function ui:LayoutLayerRail()
        local width = rail:GetWidth()
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

local function BuildTools(ui)
    local body, canvas = ui.body, ui.canvas
    local tools = CreateFrame("Frame", nil, body)
    tools:SetPoint("TOPLEFT", canvas, "BOTTOMLEFT", 0, -4)
    tools:SetPoint("TOPRIGHT", canvas, "BOTTOMRIGHT", 0, -4)
    tools:SetHeight(22)
    Button(ui, tools, "fit", "Fit", 36, 0, function()
        ui.panX, ui.panY = 0, 0
        ui.zoom = Clamp((canvas:GetWidth() - 40) / 600, 0.5, 1)
        ui:Paint()
    end)
    Button(ui, tools, "actual", "1:1", 36, 40, function() ui.zoom = 1; ui:Paint() end)
    Button(ui, tools, "zoomOut", "-", 24, 80, function() ui.zoom = Clamp(ui.zoom - 0.1, 0.5, 2); ui:Paint() end)
    ui.zoomLabel = T.Font(tools, "GameFontDisableSmall", "100%", T.colors.text)
    ui.zoomLabel:SetPoint("LEFT", tools, "LEFT", 112, 0)
    Button(ui, tools, "zoomIn", "+", 24, 156, function() ui.zoom = Clamp(ui.zoom + 0.1, 0.5, 2); ui:Paint() end)
    ui.contextButton = Button(ui, tools, "context", "Outdoor", 128, 188,
        function() ui.inDungeon = not ui.inDungeon; ui:Paint() end)
    local samples = CreateFrame("Frame", nil, body)
    samples:SetPoint("TOPLEFT", canvas, "TOPLEFT", 8, -8)
    samples:SetSize(540, 20)
    ui.sampleButton = Button(ui, samples, "plateKind", "Enemy / Friendly / Personal", 124, 0, function()
        if ui.sampleKind == "enemy" then
            ui.sampleKind, ui.personal = "friendly", false
        elseif not ui.personal then
            ui.sampleKind, ui.personal = "friendly", true
        else
            ui.sampleKind, ui.personal = "enemy", false
        end
        ui:Select(nil)
        ui:Paint()
    end)
    ui.roleButton = Button(ui, samples, "role", "Enemy type", 88, 130, function()
        ui.previewRole = nil
        P.Set(ID, "enemyPreviewRole", P.Get(ID, "enemyPreviewRole") % #P.Suite.NameplateStyle.Roles + 1)
        ui:Paint()
    end)
    ui.enemyTypeButton = Button(ui, samples, "enemyType", "NPC / player", 112, 224, function()
        ui.enemyPlayer = not ui.enemyPlayer
        ui:Select(nil)
        ui:Paint()
    end)
    ui.softTypeButton = Button(ui, samples, "softType", "Soft: enemy / interact", 126, 342, function()
        ui.softInteract = not ui.softInteract
        ui:Select(nil)
        ui:Paint()
    end)
    ui.questButton = Button(ui, samples, "questSample", "Quest", 58, 472, function()
        if P.Get(ID, "look") == 2 then OpenSetting("look", "Look"); return end
        ui.enemyPlayer = false
        ui.previewRole, ui.previewRoleSource = 5, P.Get(ID, "enemyPreviewRole")
        ui.raidMarked, ui.layers.questMarker = false, true
        if not P.Get(ID, "enemyQuestMarker") then P.Set(ID, "enemyQuestMarker", true) end
        ui:Paint()
        if ui.questMarkerHandle and ui.questMarkerHandle:IsShown() then ui:Select(ui.questMarkerHandle) end
    end)
    ui.friendlyButtons = {}
    ui.friendlyButtons[1] = Button(ui, samples, "friendlyMode", "Friendly player display", 146, 130, function()
        OpenSetting("friendlyNamesOnly", "Friendly player display")
    end)
    ui.friendlyButtons[2] = Button(ui, samples, "friendlyGroup", "Group / outsider", 114, 282, function()
        ui.friendlyOutsider = not ui.friendlyOutsider
        ui:Paint()
    end)
    ui.friendlyTypeButton = Button(ui, samples, "friendlyType", "Player / elite NPC", 112, 402, function()
        ui.friendlyElite = not ui.friendlyElite
        ui:Select(nil)
        ui:Paint()
    end)
    if H.EnsurePreviewBackgroundButton then
        local background = H.EnsurePreviewBackgroundButton(body, samples)
        if background then background:ClearAllPoints(); background:SetPoint("RIGHT", canvas, "TOPRIGHT", -8, -18) end
    end
    ui.tools = tools
end

local function BuildRaidPalette(ui)
    local strip = CreateFrame("Frame", nil, ui.canvas)
    strip:SetPoint("TOPRIGHT", ui.canvas, "TOPRIGHT", -8, -39)
    strip:SetSize(165, 22)
    local title = T.Font(strip, "GameFontDisableSmall", Tr("RAID MARKS"), T.colors.muted)
    title:SetPoint("BOTTOMRIGHT", strip, "TOPRIGHT", 0, 1)
    ui.raidChoices = {}
    for index = 1, 8 do
        local button = CreateFrame("Button", nil, strip)
        button:SetSize(18, 18)
        button:SetPoint("LEFT", strip, "LEFT", (index - 1) * 21, 0)
        button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        button.index = index
        local icon = button:CreateTexture(nil, "ARTWORK")
        icon:SetAllPoints(button)
        icon:SetTexture("Interface\\TargetingFrame\\UI-RaidTargetingIcon_" .. index)
        local border = P.Suite.NameplateStyle.CreateBorder(button)
        button.outline = function(size, color)
            P.Suite.NameplateStyle.PaintBorder(border, button, size, color)
        end
        button:SetScript("OnClick", function(_, mouseButton)
            if mouseButton == "RightButton" or not ui:LayerAvailable("raidIcon") then
                FocusLayer(ui, "elements", "raidIcon")
                return
            end
            ui.raidMarked = not (ui.raidMarked and ui.raidIndex == index)
            ui.raidIndex = ui.raidMarked and index or 0
            ui.layers.raidIcon = true
            ui:Paint()
        end)
        button:SetScript("OnEnter", function()
            ui.hint:SetText(Tr("Raid mark: " .. RAID_MARK_NAMES[index]) .. " · "
                .. Tr("Click to preview; right-click for settings"))
        end)
        button:SetScript("OnLeave", function() ui.hint:SetText(Tr(ui.help)) end)
        Register(button, "raidMark." .. index, "Raid mark: " .. RAID_MARK_NAMES[index])
        ui.raidChoices[index] = button
    end
end

local function BuildSelection(ui)
    local body, tools = ui.body, ui.tools
    if SB then
        local bar = SB.Create(body, {
            Tr = Tr, Theme = function() return T end, HandleList = function() return ui.handles end,
            HandleLabel = function(handle) return handle._label end,
            IsPlaced = function(handle) return handle:IsShown() end,
            ReadOffsets = function(_, handle) return Read(handle) end,
            WriteOffsets = function(_, handle, x, y) return Write(ui, handle, x, y) end,
            SelectHandle = function(_, handle) ui:Select(handle); return true end,
            ResetOffsets = function(_, handle)
                local rules = P.catalog[ID].rules
                local values = {
                    [handle.keyX] = rules[handle.keyX].default,
                    [handle.keyY] = rules[handle.keyY].default,
                }
                P.NameplatesSize.ResetValues(handle, values, rules)
                local ok = P.SetMany(ID, values)
                ui:Paint()
                return ok ~= false
            end,
            NudgeDelta = function(_, dx, dy)
                local handle = body._selectedHandle
                if not handle then return false end
                local x, y = Read(handle)
                return Write(ui, handle, x + dx, y + dy)
            end,
            OpenSettings = function(_, handle) Focus(ui, handle) end,
        })
        bar:SetPoint("TOPLEFT", tools, "BOTTOMLEFT", 0, -5)
        bar:SetPoint("TOPRIGHT", tools, "BOTTOMRIGHT", 0, -5)
        P.NameplatesSize.Build(ui, bar, body)
        if SB.CreatePicker then
            local picker = SB.CreatePicker(body, tools)
            picker:SetPoint("RIGHT", tools, "RIGHT", 0, 0)
            picker:SetWidth(152)
        end
        ui.selection = bar
    end
end

local function BuildInput(ui)
    local body, canvas, stage = ui.body, ui.canvas, ui.stage
    ui.bindings = { ownerName = "MSUF_SuiteNameplatesPreview_NudgeOwner", activeName = "MSUF_SuiteNameplatesPreview_ActiveNudgeBox",
        buttonPrefix = "MSUF_SuiteNameplatesPreview_Nudge", onClick = function(_, dx, dy) return Nudge(ui, dx, dy) end }
    body:EnableKeyboard(true)
    body:SetPropagateKeyboardInput(true)
    body:SetScript("OnKeyDown", Key)
    canvas:SetScript("OnMouseWheel", function(_, delta) ui.zoom = Clamp(ui.zoom + delta * 0.1, 0.5, 2); ui:Paint() end)
    canvas:SetScript("OnMouseDown", function(_, button)
        if button ~= "LeftButton" or ui.panning then return end
        local x, y = GetCursorPosition()
        ui.panning = { x = x, y = y }
        stage:StartMoving()
    end)
    canvas:SetScript("OnMouseUp", function()
        local pan = ui.panning
        if not pan then return end
        stage:StopMovingOrSizing()
        ui.panning = nil
        local x, y = GetCursorPosition()
        local scale = canvas:GetEffectiveScale()
        ui.panX, ui.panY = ui.panX + (x - pan.x) / scale, ui.panY + (y - pan.y) / scale
        ui:Paint()
    end)
    body:SetScript("OnHide", function() ui:CancelDrag(); ui:Select(nil) end)
    body:RegisterEvent("PLAYER_REGEN_DISABLED")
    body:SetScript("OnEvent", function() ui:CancelDrag(); ui:Select(nil) end)
end

local function BuildExpander(ui, section, toolbar, record)
    local body, canvas, tools, ctx = ui.body, ui.canvas, ui.tools, ui.ctx
    if W.AttachFixedPreviewExpander then
        function body:ApplyCompactPreviewPresentation(compact)
            canvas:SetHeight(compact and 108 or 226)
            tools:SetShown(not compact)
            if SB then SB.SetShown(body, not compact) end
            if ui.layerRail then ui.layerRail:SetShown(not compact) end
            ui:Paint()
        end
        local expander = W.AttachFixedPreviewExpander(section, toolbar, body, { pageKey = ctx.key, wrapper = ctx.wrapper,
            compactHeight = 116, compactTop = -38, expandedHeight = 370, expandedTop = -38, expandedSectionHeight = 416 })
        if record then record.onActivate = function()
            if expander and M.ShouldExpandFixedPreview and M.ShouldExpandFixedPreview() then expander:Open("NAMEPLATES_PREVIEW") end
            ui:Paint()
        end end
    end
end

function Editor.Create(ctx, builder, sections)
    local section, toolbar, record = W.FixedPreviewSection(ctx, builder, { title = Tr("Nameplate preview"), height = 416, gap = 8 })
    if not section then return end
    local inInstance, instanceType = _G.IsInInstance()
    local inDungeon = P.Suite.Public(instanceType) and P.Suite.Public(inInstance)
        and inInstance == true and (instanceType == "party" or instanceType == "raid" or instanceType == "scenario")
    local ui = setmetatable({ ctx = ctx, sections = sections, handles = {}, renderers = {}, layers = {},
        sampleKind = "enemy", zoom = 1, panX = 0, panY = 0,
        softTargetSample = true, aggroSample = true,
        layoutWidth = math.max(640, (section._msuf2Width or builder.width or 720) - 28),
        inDungeon = inDungeon, help = "Select an element for X/Y and available size · Drag or arrow keys: move · Tab: select · Wheel: zoom" }, { __index = Editor })
    ui.previewRole, ui.previewRoleSource = nil, P.Get(ID, "enemyPreviewRole")
    P.ShowNameplatesElementsSample = function()
        ui.sampleKind = "enemy"
        ui.previewRole = nil
        ui.previewRoleSource = P.Get(ID, "enemyPreviewRole")
        ui:Paint()
    end
    local body = CreateFrame("Frame", nil, section)
    body:SetPoint("TOPLEFT", section, "TOPLEFT", 14, -38)
    body:SetPoint("TOPRIGHT", section, "TOPRIGHT", -14, -38)
    body:SetHeight(370)
    ui.body, body.previewUI, body._handleList = body, ui, ui.handles
    local canvas = CreateFrame("Frame", nil, body, "BackdropTemplate")
    canvas:SetPoint("TOPLEFT", body, "TOPLEFT", 0, 0)
    canvas:SetPoint("TOPRIGHT", body, "TOPRIGHT", 0, 0)
    canvas:SetHeight(226)
    canvas:SetClipsChildren(true)
    canvas:EnableMouse(true)
    canvas:EnableMouseWheel(true)
    ui.canvas = canvas
    if H.ApplyPreviewChrome then H.ApplyPreviewChrome(canvas, "canvas", T) end
    local stage = CreateFrame("Frame", nil, canvas)
    stage:SetSize(600, 180)
    stage:SetMovable(true)
    ui.stage = stage
    ui.hint = T.Font(toolbar, "GameFontDisableSmall", Tr(ui.help), T.colors.muted)
    ui.hint:SetPoint("LEFT", toolbar, "LEFT", 132, 0)
    ui.hint:SetPoint("RIGHT", toolbar, "RIGHT", -26, 0)
    ui.hint:SetJustifyH("LEFT")
    BuildTools(ui)
    BuildRaidPalette(ui)
    BuildSelection(ui)
    BuildLayers(ui)
    BuildInput(ui)
    BuildExpander(ui, section, toolbar, record)
    M.TrackRefresh(ctx, function() ui:Paint() end)
    return ui
end

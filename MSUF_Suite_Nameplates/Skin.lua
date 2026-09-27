local _, private = ...
local NS, S = private.NS, private.Suite
local Style = NS.NameplateStyle
local ResolveTexture = Style.ResolveTexture
local Border = Style.PaintBorder
local Layout, Roles, Text, Textures = private.Layout, private.Roles, private.Text, private.Textures
local M = {
    visuals = setmetatable({}, { __mode = "k" }),
    roles = setmetatable({}, { __mode = "k" }),
    focused = setmetatable({}, { __mode = "k" }),
    elites = setmetatable({}, { __mode = "k" }),
    quests = setmetatable({}, { __mode = "k" }),
    units = setmetatable({}, { __mode = "k" }),
    activeUnits = {},
    auraHooks = setmetatable({}, { __mode = "k" }),
    auraButtons = setmetatable({}, { __mode = "k" }),
    friendlyNames = setmetatable({}, { __mode = "k" }),
    raidIcons = setmetatable({}, { __mode = "k" }),
}

local function Safe(frame)
    return frame and not NS.Safety.IsForbidden(frame)
end

local function Color(texture, hex, alpha)
    local r, g, b = S.RGB(hex)
    texture:SetVertexColor(1, 1, 1, 1)
    texture:SetColorTexture(r, g, b, alpha or 1)
end

local RestoreFont = Text.Restore

local function RestorePlateFonts(uf, health, cast)
    RestoreFont(uf.name)
    RestoreFont(health.Text)
    RestoreFont(health.LeftText)
    RestoreFont(health.RightText)
    if cast then
        RestoreFont(cast.Text)
        RestoreFont(cast.CastTargetNameText)
    end
end

-- The color overlay follows Blizzard's filled StatusBar texture. No health,
-- cast progress or aura value is read or cached by this module.
local function Visual(bar, markerOwner)
    local visual = M.visuals[bar]
    if visual then return visual end
    visual = Style.CreateBorder(bar)
    visual.back = bar:CreateTexture(nil, "BACKGROUND", nil, 1)
    visual.back:SetAllPoints(bar)
    -- Keep Blizzard's ARTWORK sublayers 1/2 (absorb and glow) above the tint.
    visual.fill = bar:CreateTexture(nil, "ARTWORK", nil, 0)
    visual.fill:Hide()
    visual.elite = markerOwner:CreateTexture(nil, "OVERLAY", nil, 7)
    visual.elite:Hide()
    visual.quest = markerOwner:CreateTexture(nil, "OVERLAY", nil, 7)
    visual.quest:Hide()
    M.visuals[bar] = visual
    return visual
end

local function HideVisual(visual)
    if not visual then return end
    visual.back:Hide()
    visual.fill:Hide()
    Style.PaintTarget(visual, nil, false)
    visual.elite:Hide()
    visual.quest:Hide()
    for i = 1, 4 do visual.edges[i]:Hide() end
end

local function Prefix(uf)
    local value = uf.isFriend
    if not S.Public(value) or type(value) ~= "boolean" then return nil end
    return value and "friendly" or "enemy"
end

-- Unit metadata is refreshed on identity/threat/quest events, never health ticks.
local function SetRole(uf, unit)
    local health = uf.HealthBarsContainer and uf.HealthBarsContainer.healthBar
    if not Safe(health) then return end
    M.units[health] = unit
    M.elites[health], M.quests[health], M.roles[health] = nil, nil, nil
    M.focused[health] = nil
    local prefix = Prefix(uf)
    if M.config.look == 2 or not prefix or not M.config[prefix] then return end
    if not S.Public(unit) or type(unit) ~= "string" then return end
    if type(_G.UnitIsUnit) == "function" then
        local focus = _G.UnitIsUnit(unit, "focus")
        if S.Public(focus) and focus == true then M.focusUF = uf; M.focused[health] = true end
    end
    if not S.Public(uf.isPlayer) or uf.isPlayer ~= false then return end
    local color = prefix == "enemy" and M.config.enemyRoleColors and Roles.allowed
    local elite, quest = M.config[prefix .. "EliteMarker"], M.config[prefix .. "QuestMarker"]
    if not color and not elite and not quest then return end
    local classification = type(_G.UnitClassification) == "function" and _G.UnitClassification(unit)
    if not S.Public(classification) then classification = nil end
    if elite then M.elites[health] = Roles.Marker(unit, classification) end
    if quest or color and M.config.enemyQuestColors then M.quests[health] = Roles.Quest(unit) end
    if color and M.active then
        M.roles[health] = Roles.Get(unit, uf, classification, M.quests[health])
    end
end

local function PaintMarker(texture, health, kind, enabled, size, x, y, color, anchor, variant)
    if not enabled then texture:Hide(); return end
    Style.PaintMarker(texture, kind, size, color, variant)
    if texture._msufX ~= x or texture._msufY ~= y or texture._msufAnchor ~= anchor then
        Style.PlaceMarker(texture, health, kind, x, y, anchor)
        texture._msufX, texture._msufY, texture._msufAnchor = x, y, anchor
    end
    texture:Show()
end

local function PaintHealth(health, visual, prefix)
    local backColor = M.config[prefix .. "BackdropColor"]
    local backAlpha = (M.config[prefix .. "BackdropAlpha"] or 100) / 100
    if visual.backColor ~= backColor or visual.backAlpha ~= backAlpha then
        Color(visual.back, backColor, backAlpha)
        visual.backColor, visual.backAlpha = backColor, backAlpha
    end
    Border(visual, health, M.config[prefix .. "BorderSize"], M.config[prefix .. "BorderColor"])
    visual.back:Show()
    local role = prefix == "enemy" and M.config.enemyRoleColors and M.roles[health]
    if role and M.config["enemy" .. role .. "Enabled"] == false then role = nil end
    local fillTexture = health.GetStatusBarTexture and health:GetStatusBarTexture()
    if role and Safe(fillTexture) then
        if visual.fillTarget ~= fillTexture then
            visual.fill:ClearAllPoints()
            visual.fill:SetAllPoints(fillTexture)
            visual.fillTarget = fillTexture
        end
        local hex = M.config["enemy" .. role .. "Color"]
        local texture = M.focused[health] and M.focusHealthTexture or M.healthTexture
        if visual.fillColor ~= hex or visual.fillTexture ~= texture then
            if texture then
                visual.fill:SetTexture(texture)
                local r, g, b = S.RGB(hex)
                visual.fill:SetVertexColor(r, g, b)
            else Color(visual.fill, hex) end
            visual.fillColor, visual.fillTexture = hex, texture
        end
        visual.fill:Show()
    else
        visual.fill:Hide()
    end
    Textures.MaskOverlay(health, visual.fill, not not role)
    PaintMarker(visual.elite, health, "elite", M.config[prefix .. "EliteMarker"] and M.elites[health],
        M.config[prefix .. "EliteMarkerSize"] or 14, M.config[prefix .. "EliteOffsetX"] or -13,
        M.config[prefix .. "EliteOffsetY"] or 0, M.config.enemyMinibossColor, M.config[prefix .. "EliteMarkerAnchor"], M.elites[health])
    PaintMarker(visual.quest, health, "quest", M.config[prefix .. "QuestMarker"] and M.quests[health],
        M.config[prefix .. "QuestMarkerSize"] or 15, M.config[prefix .. "QuestOffsetX"] or 0,
        M.config[prefix .. "QuestOffsetY"] or 17, M.config.enemyQuestColor, M.config[prefix .. "QuestMarkerAnchor"])
end

local function PaintTarget(uf, health, visual, prefix)
    local unit = M.units[health]
    local target = unit and type(_G.UnitIsUnit) == "function" and _G.UnitIsUnit(unit, "target")
    local visible = M.config.enemyTargetMarker and (prefix == "enemy" or M.config.enemyTargetHideFriendly == false)
        and S.Public(target) and target == true
    if visible then M.targetUF = uf elseif M.targetUF == uf then M.targetUF = nil end
    Style.PaintTarget(visual, health, visible, M.targetConfig, uf)
end

local function RestoreFriendlyName(name)
    local alpha = name and M.friendlyNames[name]
    if alpha == nil then return end
    if Safe(name) then name:SetAlpha(alpha) end
    M.friendlyNames[name] = nil
end

local function FilterFriendlyName(uf, prefix)
    local name = uf.name
    if not Safe(name) then return end
    if not M.config.friendlyGroupOnly or not M.config.friendly or M.config.look == 2
        or prefix ~= "friendly" or not S.Public(uf.isPlayer) or uf.isPlayer ~= true then
        RestoreFriendlyName(name); return
    end
    local health = uf.HealthBarsContainer and uf.HealthBarsContainer.healthBar
    local unit = health and M.units[health]
    if not unit then RestoreFriendlyName(name); return end
    local party = type(_G.UnitInParty) == "function" and _G.UnitInParty(unit)
    local raid = type(_G.UnitInRaid) == "function" and _G.UnitInRaid(unit)
    if not S.Public(party) or not S.Public(raid) then RestoreFriendlyName(name); return end
    if party or raid then RestoreFriendlyName(name); return end
    if M.friendlyNames[name] == nil then
        local alpha = name:GetAlpha()
        if not NS.Finite(alpha) then return end
        M.friendlyNames[name] = alpha
        -- Alpha survives Blizzard's ordinary name Show()/Hide() refreshes.
        name:SetAlpha(0)
    end
end

local function PaintRaidIcon(uf, prefix)
    local frame = uf.RaidTargetFrame
    local icon = frame and frame.RaidTargetIcon
    if not Safe(icon) then return end
    local original = M.raidIcons[icon]
    local hide = M.active and M.config.look ~= 2 and M.config.enemy and prefix == "enemy"
        and M.config.enemyRaidIcon == false
    if not hide then
        if original ~= nil and pcall(icon.SetAlpha, icon, original) then M.raidIcons[icon] = nil end
    elseif original == nil then
        local alpha = icon:GetAlpha()
        if S.Finite(alpha) and pcall(icon.SetAlpha, icon, 0) then M.raidIcons[icon] = alpha end
    end
end

local function PaintFonts(uf, health, cast, prefix)
    Text.Apply(uf.name, Text.styles[prefix], M.config[prefix .. "NameSize"] or 0)
    if prefix == "enemy" then
        if cast then
            Text.Apply(cast.Text, Text.styles.enemyCast, M.config.enemyCastSize or 0)
            Text.Apply(cast.CastTargetNameText, Text.styles.enemyCast, M.config.enemyCastSize or 0)
        end
        Text.Apply(health.Text, Text.styles.enemy, M.config.enemyHealthTextSize or 0)
        Text.Apply(health.LeftText, Text.styles.enemy, M.config.enemyHealthTextSize or 0)
        Text.Apply(health.RightText, Text.styles.enemy, M.config.enemyHealthTextSize or 0)
    else
        RestoreFont(health.Text)
        RestoreFont(health.LeftText)
        RestoreFont(health.RightText)
        if cast then
            Text.Apply(cast.Text, Text.styles.friendlyCast, M.config.friendlyCastSize or 0)
            Text.Apply(cast.CastTargetNameText, Text.styles.friendlyCast, M.config.friendlyCastSize or 0)
        end
    end
end

local function Paint(uf)
    if not M.active or not Safe(uf) then return end
    local health = uf.HealthBarsContainer and uf.HealthBarsContainer.healthBar
    if not Safe(health) then return end
    local cast = uf.CastBarsContainer and uf.CastBarsContainer.castBar
    local prefix = Prefix(uf)
    FilterFriendlyName(uf, prefix)
    PaintRaidIcon(uf, prefix)
    Layout.Apply(uf, prefix, M.config)
    Textures.Apply(uf, health)
    if M.config.look == 2 or not prefix or not M.config[prefix] then
        if M.targetUF == uf then M.targetUF = nil end
        HideVisual(M.visuals[health])
        RestorePlateFonts(uf, health, cast)
        return
    end
    local visual = Visual(health, uf)
    PaintHealth(health, visual, prefix)
    PaintTarget(uf, health, visual, prefix)
    PaintFonts(uf, health, cast, prefix)
end

local function ApplyCVars(self)
    local style = self.config.nativeStyle
    if style == 1 then S.RestoreCVar("nameplates", "nameplateStyle")
    elseif style then self.context:CVar("nameplateStyle", tostring(style - 2)) end
    local size = self.config.nativeSize
    if size == 1 then S.RestoreCVar("nameplates", "nameplateSize")
    elseif size then self.context:CVar("nameplateSize", tostring(size - 1)) end

    -- Blizzard stores these two settings as a version byte plus six-bit data
    -- bytes, not as decimal masks. Preserve its version and unrelated flags.
    local function LowBits(key, mask, width)
        local api = _G.C_CVar
        local current = api and type(api.GetCVar) == "function" and api.GetCVar(key)
        if not S.Public(current) or type(current) ~= "string" or #current == 0 then return end
        local byte = current:byte(2) or 64
        if byte < 64 or byte > 127 then return end
        local span = 2 ^ (width or 2)
        local other = (byte - 64) - ((byte - 64) % span)
        local flags = other + mask
        local tail = current:sub(3)
        local value = current:sub(1, 1)
        if flags > 0 or #tail > 0 then value = value .. string.char(64 + flags) .. tail end
        self.context:CVar(key, value)
    end
    local textMode = self.config.enemy and self.config.enemyTextMode or 1
    local rarityMode = self.config.enemy and self.config.enemyRarityIcon or 1
    if self.config.look == 2 then textMode = 1 end
    if self.config.look == 2 then rarityMode = 1 end
    if textMode == 1 then
        S.RestoreCVar("nameplates", "nameplateForceShowUnitName")
        S.RestoreCVar("nameplates", "nameplateSimplifiedTypes")
    else
        self.context:CVar("nameplateForceShowUnitName", "1")
        LowBits("nameplateSimplifiedTypes", 0, 2)
    end
    if textMode == 1 and (rarityMode == 1 or self.infoTextApplied) then
        S.RestoreCVar("nameplates", "nameplateInfoDisplay")
    end
    if textMode ~= 1 or rarityMode ~= 1 then
        -- Blizzard's rarity icon is bit 3 of the same CVar as the two health
        -- text flags. Compose one write so either control preserves the other.
        local api = _G.C_CVar
        local current = api and type(api.GetCVar) == "function" and api.GetCVar("nameplateInfoDisplay")
        if S.Public(current) and type(current) == "string" and #current > 0 then
            local byte = current:byte(2) or 64
            if byte >= 64 and byte <= 127 then
                local flags = byte - 64
                local textBits = textMode == 1 and flags % 4 or textMode - 1
                local currentRarity = flags % 8 - flags % 4
                if rarityMode ~= 1 and self.rarityBefore == nil then self.rarityBefore = currentRarity end
                local rarityBit = rarityMode == 1 and (self.rarityBefore or currentRarity)
                    or (rarityMode == 2 and 4 or 0)
                LowBits("nameplateInfoDisplay", textBits + rarityBit, 3)
                if rarityMode == 1 then self.rarityBefore = nil end
            end
        end
    else
        self.rarityBefore = nil
    end
    self.infoTextApplied = textMode ~= 1

    local castEnabled = self.config.look == 2 and 1 or self.config.enemyCastEnabled
    if castEnabled == 1 then
        S.RestoreCVar("nameplates", "nameplateShowCastBars")
    else
        self.context:CVar("nameplateShowCastBars", castEnabled == 3 and "0" or "1")
    end

    if self.config.enemyCastDisplay == 1 or self.config.look == 2 then
        S.RestoreCVar("nameplates", "nameplateCastBarDisplay")
    else
        local c = self.config
        local mask = (c.enemyCastSpellName and 1 or 0)
            + (c.enemyCastSpellIcon and 2 or 0)
            + (c.enemyCastSpellTarget and 4 or 0)
            + (c.enemyCastImportant and 8 or 0)
            + (c.enemyCastTargetHighlight and 16 or 0)
        LowBits("nameplateCastBarDisplay", mask, 5)
    end

    local choices = {
        { "friendlyNamesOnly", "nameplateShowOnlyNameForFriendlyPlayerUnits" },
        { "classColors", "ShowClassColorInNameplate" },
        { "classColors", "nameplateShowClassColor" },
        { "friendlyNameClassColor", "nameplateUseClassColorForFriendlyPlayerUnitNames" },
        { "friendlyRealm", "nameplateShowFriendlyRealmName" },
        { "personalAuras", "nameplateShowAllPersonalAuras" },
        { "friendlyNPCs", "nameplateShowFriendlyNpcs" },
        { "playerGuildNames", "UnitNamePlayerGuild" },
        { "playerTitles", "UnitNamePlayerPVPTitle" },
    }
    for i = 1, #choices do
        local choice = choices[i]
        local mode = self.config[choice[1]] or 1
        if choice[1] == "friendlyNamesOnly" and self.config.friendlyGroupOnly
            and self.config.friendly and self.config.look ~= 2 then mode = 2 end
        if mode == 1 then S.RestoreCVar("nameplates", choice[2])
        else self.context:CVar(choice[2], mode == 2 and "1" or "0") end
    end
end

local function RestorePlate(uf)
    RestoreFriendlyName(uf.name)
    PaintRaidIcon(uf)
    Layout.Restore(uf)
    local health = uf.HealthBarsContainer and uf.HealthBarsContainer.healthBar
    if not Safe(health) then return end
    local cast = uf.CastBarsContainer and uf.CastBarsContainer.castBar
    Textures.Restore(health)
    M.roles[health] = nil
    M.focused[health] = nil
    M.elites[health], M.quests[health] = nil, nil
    M.units[health] = nil
    HideVisual(M.visuals[health])
    RestorePlateFonts(uf, health, cast)
end

local function RestoreAuraButtons()
    local failed = false
    for button, enabled in pairs(M.auraButtons) do
        if Safe(button) and type(button.SetMouseClickEnabled) == "function" then
            if pcall(button.SetMouseClickEnabled, button, enabled) then
                M.auraButtons[button] = nil
            else failed = true end
        else M.auraButtons[button] = nil end
    end
    if failed then
        if not M.auraRestoreFrame then
            M.auraRestoreFrame = CreateFrame("Frame")
            M.auraRestoreFrame:SetScript("OnEvent", function(frame)
                if NS.IsCombatLocked() then return end
                frame:UnregisterEvent("PLAYER_REGEN_ENABLED")
                RestoreAuraButtons()
            end)
        end
        M.auraRestoreFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
    end
end

local function SetAuraClickthrough(button)
    if not Safe(button) or type(button.SetMouseClickEnabled) ~= "function"
        or type(button.IsMouseClickEnabled) ~= "function" then return end
    local current = button:IsMouseClickEnabled()
    if not S.Public(current) or type(current) ~= "boolean" or current == false then return end
    if M.auraButtons[button] == nil then M.auraButtons[button] = current end
    if not pcall(button.SetMouseClickEnabled, button, false) then M.needsRefresh = true end
end

local function ApplyAuraPool(pool)
    if not M.active or not M.config.auraClickthrough or not pool
        or type(pool.EnumerateActive) ~= "function" then return end
    for button in pool:EnumerateActive() do SetAuraClickthrough(button) end
end

local function ApplyAuraClickthrough(uf)
    if not M.config.auraClickthrough then
        if next(M.auraButtons) then RestoreAuraButtons() end
        return
    end
    local auras = uf.AurasFrame
    if Safe(auras) then
        if not M.auraHooks[auras] then
            if NS.IsCombatLocked() then M.needsRefresh = true; return end
            if type(auras.RefreshAuras) == "function" then
                hooksecurefunc(auras, "RefreshAuras", function(frame)
                    ApplyAuraPool(frame.auraItemFramePool)
                end)
            end
            if type(auras.RefreshLossOfControl) == "function" then
                hooksecurefunc(auras, "RefreshLossOfControl", function(frame)
                    if M.active and M.config.auraClickthrough then
                        local item = frame.LossOfControlFrame and frame.LossOfControlFrame.AuraItemFrame
                        if item then SetAuraClickthrough(item) end
                    end
                end)
            end
            M.auraHooks[auras] = true
        end
        ApplyAuraPool(auras.auraItemFramePool)
        local item = auras.LossOfControlFrame and auras.LossOfControlFrame.AuraItemFrame
        if item then SetAuraClickthrough(item) end
    end
    local buff = uf.BuffFrame
    if Safe(buff) then
        if not M.auraHooks[buff] then
            if NS.IsCombatLocked() then M.needsRefresh = true; return end
            if type(buff.UpdateBuffs) == "function" then
                hooksecurefunc(buff, "UpdateBuffs", function(frame) ApplyAuraPool(frame.buffPool) end)
            end
            M.auraHooks[buff] = true
        end
        ApplyAuraPool(buff.buffPool)
    end
end

local function ApplyPlate(plate)
    if not Safe(plate) or not Safe(plate.UnitFrame) then return end
    local uf, unit = plate.UnitFrame, plate.unitToken
    if not M.active then RestorePlate(uf); return end
    if S.Public(unit) and type(unit) == "string" then
        M.activeUnits[unit] = uf
        SetRole(uf, unit)
    else
        local health = uf.HealthBarsContainer and uf.HealthBarsContainer.healthBar
        if Safe(health) then M.roles[health] = nil; M.units[health] = nil end
    end
    Paint(uf)
    ApplyAuraClickthrough(uf)
end

local function EachPlate(callback)
    local plates = _G.C_NamePlate and _G.C_NamePlate.GetNamePlates and _G.C_NamePlate.GetNamePlates()
    if type(plates) ~= "table" then return end
    for i = 1, #plates do callback(plates[i]) end
end

local function OnAdded(self, _, unit)
    if not S.Public(unit) or type(unit) ~= "string" then return end
    Roles.ClearQuest(unit)
    local plate = _G.C_NamePlate.GetNamePlateForUnit(unit)
    local uf = Safe(plate) and plate.UnitFrame
    if not Safe(uf) then return end
    self.activeUnits[unit] = uf
    SetRole(uf, unit)
    Paint(uf)
    ApplyAuraClickthrough(uf)
end

local function OnRemoved(self, _, unit)
    if not S.Public(unit) or type(unit) ~= "string" then return end
    local uf = self.activeUnits[unit]
    self.activeUnits[unit] = nil
    Roles.ClearQuest(unit)
    if self.targetUF == uf then self.targetUF = nil end
    if uf then RestorePlate(uf) end
end

local function RefreshActive(self, recategorize)
    for unit, uf in pairs(self.activeUnits) do
        if Safe(uf) then
            if recategorize then SetRole(uf, unit) end
            Paint(uf)
        end
    end
end

local function RefreshRole(uf)
    local health = uf.HealthBarsContainer and uf.HealthBarsContainer.healthBar
    local prefix = Prefix(uf)
    local visual = health and M.visuals[health]
    if not Safe(health) or not prefix or not visual or M.config.look == 2 or not M.config[prefix] then
        Paint(uf)
        return
    end
    PaintHealth(health, visual, prefix)
end

local function RefreshTarget(uf)
    if not Safe(uf) then return end
    local health = uf.HealthBarsContainer and uf.HealthBarsContainer.healthBar
    local prefix = Prefix(uf)
    local visual = health and M.visuals[health]
    if not Safe(health) or not prefix or not visual or M.config.look == 2 or not M.config[prefix] then
        Paint(uf)
        return
    end
    PaintTarget(uf, health, visual, prefix)
end

local function CancelQuestRefresh(module)
    local timer = module.questTimer
    module.questTimer = nil
    if timer and type(timer.Cancel) == "function" then timer:Cancel() end
end

local function OnQuestLogChanged(module)
    Roles.ClearQuest()
    if Roles.inInstance or not (module.config.enemyQuestColors or module.config.enemyQuestMarker
        or module.config.friendlyQuestMarker) then return end
    if not next(module.activeUnits) then return end
    if module.questTimer then return end
    local timerAPI = _G.C_Timer
    if not timerAPI or type(timerAPI.NewTimer) ~= "function" then
        RefreshActive(module, true)
        return
    end
    -- Quest logs can emit several updates together. One cancellable pass is
    -- enough; no persistent ticker or plate work runs while idle.
    module.questTimer = timerAPI.NewTimer(1, function()
        module.questTimer = nil
        if module.active and not Roles.inInstance then RefreshActive(module, true) end
    end)
end

local function OnTargetChanged(self)
    local previous = self.targetUF
    local plate = _G.C_NamePlate.GetNamePlateForUnit("target")
    local current = Safe(plate) and plate.UnitFrame
    if Safe(previous) then RefreshTarget(previous) end
    if Safe(current) and current ~= previous then RefreshTarget(current) end
end

local function OnUnitChanged(module, event, unit)
    if not S.Public(unit) or type(unit) ~= "string" then return end
    local uf = module.activeUnits[unit]
    if not Safe(uf) then return end
    SetRole(uf, unit)
    if event == "UNIT_FACTION" or event == "UNIT_FLAGS" then Paint(uf)
    else RefreshRole(uf) end
end

local function OnContextChanged(module)
    CancelQuestRefresh(module)
    Roles.RefreshContext()
    Roles.ClearQuest()
    RefreshActive(module, true)
end

local function OnFocusChanged(module)
    local previous = module.focusUF
    local plate = _G.C_NamePlate.GetNamePlateForUnit("focus")
    local current = Safe(plate) and plate.UnitFrame
    local function Refresh(uf)
        if not Safe(uf) then return end
        local health = uf.HealthBarsContainer and uf.HealthBarsContainer.healthBar
        local unit = health and module.units[health]
        if unit then SetRole(uf, unit); Paint(uf) end
    end
    Refresh(previous)
    if current ~= previous then Refresh(current) end
    module.focusUF = current
end

function M:Enable()
    local mixin = _G.NamePlateUnitFrameMixin
    if not self.fontHook and type(mixin) == "table" and type(mixin.ApplyFrameOptions) == "function" then
        self.fontHook = true
        -- Observe Blizzard's font reset. Never call frame setup ourselves.
        hooksecurefunc(mixin, "ApplyFrameOptions", function(uf)
            if not self.active then return end
            local health = uf.HealthBarsContainer and uf.HealthBarsContainer.healthBar
            if health and self.units[health] then
                local cast = uf.CastBarsContainer and uf.CastBarsContainer.castBar
                Text.Invalidate(uf.name)
                Text.Invalidate(health.Text)
                Text.Invalidate(health.LeftText)
                Text.Invalidate(health.RightText)
                if cast then
                    Text.Invalidate(cast.Text)
                    Text.Invalidate(cast.CastTargetNameText)
                end
                Paint(uf)
            end
        end)
    end
    self.context:Event("NAME_PLATE_UNIT_ADDED", OnAdded, true)
    self.context:Event("NAME_PLATE_UNIT_REMOVED", OnRemoved, true)
    self.context:Event("PLAYER_TARGET_CHANGED", OnTargetChanged, true)
    self.context:Event("PLAYER_FOCUS_CHANGED", OnFocusChanged, true)
    for _, event in ipairs({ "UNIT_THREAT_SITUATION_UPDATE", "UNIT_THREAT_LIST_UPDATE",
        "UNIT_FACTION", "UNIT_FLAGS", "UNIT_CLASSIFICATION_CHANGED", "UNIT_LEVEL", "UNIT_DISPLAYPOWER" }) do
        self.context:Event(event, OnUnitChanged, true)
    end
    self.context:Event("QUEST_LOG_UPDATE", OnQuestLogChanged, true)
    for _, event in ipairs({ "PLAYER_ENTERING_WORLD", "ZONE_CHANGED_NEW_AREA", "PLAYER_LEVEL_UP",
        "GROUP_ROSTER_UPDATE", "PLAYER_ROLES_ASSIGNED", "PLAYER_SPECIALIZATION_CHANGED", "ZONE_CHANGED" }) do
        self.context:Event(event, OnContextChanged, true)
    end
    self.context:Event("PLAYER_REGEN_ENABLED", function(module)
        local retryQuests = Roles.RetryQuests()
        if not module.needsRefresh then
            if retryQuests then CancelQuestRefresh(module); RefreshActive(module, true) end
            return
        end
        module.needsRefresh = false
        EachPlate(ApplyPlate)
    end, true)
    self:Refresh()
end

function M:Refresh()
    CancelQuestRefresh(self)
    Layout.Configure(self.config)
    Roles.Configure(self.config)
    Text.Configure(self.config)
    self.targetConfig = Style.TargetConfig(self.config)
    self.healthTexture = ResolveTexture(self.config.enemyHealthTexture)
    self.focusHealthTexture = ResolveTexture(self.config.enemyFocusHealthTexture)
    self.friendlyHealthTexture = ResolveTexture(self.config.friendlyHealthTexture)
    self.friendlyFocusHealthTexture = ResolveTexture(self.config.friendlyFocusHealthTexture)
    ApplyCVars(self)
    EachPlate(ApplyPlate)
end

function M:Disable()
    CancelQuestRefresh(self)
    self.active = false
    self.rarityBefore = nil
    self.infoTextApplied = nil
    Layout.RestoreAll()
    self.targetUF, self.focusUF = nil, nil
    Textures.RestoreAll()
    Roles.ClearQuest()
    for unit, uf in pairs(self.activeUnits) do
        RestorePlate(uf)
        self.activeUnits[unit] = nil
    end
    for _, visual in pairs(self.visuals) do
        HideVisual(visual)
    end
    RestoreAuraButtons()
end

Layout.Bind(M)
Text.Bind(M)
Textures.Bind(M)
S.Install("nameplates", M)

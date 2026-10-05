local _, P = ...
local M, Tr = P.M, P.Tr
local Style = P.Suite.NameplateStyle
local NativeBit = Style.NativeBit
local ID, PAGE = "nameplates", "suite_nameplates"
local WHITE = "Interface\\Buttons\\WHITE8X8"
-- Static samples shared with the GF preview. These never query live auras.
local AURA_SAMPLES = {
    debuffs = { "Interface\\Icons\\Spell_Shadow_CurseOfTounges",
        "Interface\\Icons\\Spell_Shadow_AbominationExplosion",
        "Interface\\Icons\\Spell_Frost_FrostNova" },
    buffs = { "Interface\\Icons\\Spell_Holy_WordFortitude",
        "Interface\\Icons\\Spell_Holy_Renew" },
    control = { "Interface\\Icons\\Spell_Frost_FrostNova" },
}
local SIZE_SCALE = { [2] = { 0.75, 0.8 }, [3] = { 1, 1 },
    [4] = { 1.25, 1.25 }, [5] = { 1.4, 1.4 }, [6] = { 1.6, 1.6 } }
local TARGET_KEYS = { "Style", "Layout", "Anchor", "Direction", "MarkerSize", "OffsetX", "OffsetY", "Color" }

local function NativeCastDetail(key, index, fallback)
    if P.Get(ID, "look") ~= 2 and P.Get(ID, "enemyCastDisplay") == 2 then
        return P.Get(ID, key)
    end
    return NativeBit("nameplateCastBarDisplay", index, fallback)
end

local function AuraShown(group, kind)
    if P.Get(ID, "look") ~= 2 and P.Get(ID, group .. "AuraMode") == 2 then
        return P.Get(ID, group .. kind)
    end
    return NativeBit(Style.AuraCVar[group], Style.AuraBits[kind], true)
end

local function NativeToggle(key, cvar)
    local mode = P.Get(ID, "look") ~= 2 and P.Get(ID, key) or 1
    if mode ~= 1 then return mode == 2 end
    return Style.NativeToggle(cvar, false)
end

local function AuraScale()
    if P.Get(ID, "look") ~= 2 and P.Get(ID, "auraScaleMode") == 2 then
        return P.Get(ID, "auraScalePercent") / 100
    end
    local value = C_CVar.GetCVar("nameplateAuraScale")
    return P.Suite.Public(value) and tonumber(value) or 1
end

-- The sample uses Blizzard's current public setup values. Its element offsets
-- then start from the same native anchors that Layout.lua displaces at runtime.
local function SetupNumber(key, fallback)
    local value = NamePlateSetupOptions[key]
    if P.Suite.Public(value) and type(value) == "number" and value == value then return value end
    return fallback
end

-- Blizzard_SharedXMLBase/CvarUtil.lua; the runtime reads the same padding.
local function DebuffPadding()
    local value = GetCVarNumberOrDefault(NamePlateConstants.DEBUFF_PADDING_CVAR)
    if P.Suite.Public(value) and type(value) == "number" and value == value then return value end
    return 0
end

local function Fill(owner, layer)
    local texture = owner:CreateTexture(nil, layer or "ARTWORK")
    texture:SetTexture(WHITE)
    return texture
end

local function Tint(texture, hex, alpha)
    local r, g, b = P.RGB(hex)
    texture:SetVertexColor(1, 1, 1, 1)
    texture:SetColorTexture(r, g, b, alpha or 1)
end

local function Text(owner, value, size, color)
    local label = owner:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    label:SetFont(_G.STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF", size or 12, "OUTLINE")
    label:SetText(Tr(value))
    if color then label:SetTextColor(unpack(color)) end
    return label
end

local function Border(owner)
    local visual = Style.CreateBorder(owner)
    return function(size, color) Style.PaintBorder(visual, owner, size, color) end
end

local function SampleRegion(parent, width, height)
    local frame = CreateFrame("Button", nil, parent)
    frame:SetSize(width, height)
    return frame
end

local function AuraGroup(parent, textures, reverse)
    local size, step = 22, 24
    local group = SampleRegion(parent, #textures * step - 2, size)
    for index, path in ipairs(textures) do
        local slot = reverse and #textures - index or index - 1
        local edge = Fill(group, "BACKGROUND")
        edge:SetSize(size, size)
        edge:SetPoint("LEFT", group, "LEFT", slot * step, 0)
        edge:SetColorTexture(0, 0, 0, 0.95)
        local icon = group:CreateTexture(nil, "ARTWORK")
        icon:SetTexture(path)
        icon:SetSize(size - 2, size - 2)
        icon:SetPoint("CENTER", edge, "CENTER")
        if index == 1 then
            local stack = Text(group, "2", 9, { 1, 1, 1 })
            stack:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", 1, -1)
        end
    end
    return group
end

local function PreviewFont(region, prefix, size, outline, nativeSize)
    local enabled = P.Get(ID, prefix .. "TextEnabled")
    local custom = P.Get(ID, prefix .. "CustomFont")
    local fontKey = prefix .. (prefix:sub(-4) == "Cast" and "Font" or "NameFont")
    local font = enabled and custom and Style.Font(P.Get(ID, fontKey)) or _G.STANDARD_TEXT_FONT
    P.StylePreviewFont(region, font, enabled and size > 0 and size or nativeSize,
        enabled and Style.FontFlags(outline) or "OUTLINE")
    local shadow = enabled and P.Get(ID, prefix .. "TextShadow")
    region:SetShadowColor(0, 0, 0, shadow and 1 or 0)
    region:SetShadowOffset(shadow and 1 or 0, shadow and -1 or 0)
end

-- Moves a sample element by its saved offset from a native-style base.
local function Place(s, frame, point, owner, relative, x, y, key)
    frame:ClearAllPoints()
    frame:SetPoint(point, owner, relative, x + P.Get(ID, s.prefix .. key .. "OffsetX"),
        y + P.Get(ID, s.prefix .. key .. "OffsetY"))
end

----------------------------------------------------------------- sample build
-- One sample plate (s) per side. Its regions are created once, in this order.
local function BuildBar(editor, s, cell)
    local prefix = s.prefix
    local bar = CreateFrame("Button", nil, cell)
    bar:SetSize(206, 20)
    bar:SetPoint("CENTER", cell, "CENTER", 0, -4)
    if M.RegisterControlMetadata then
        M.RegisterControlMetadata(bar,
            P.Meta(PAGE, ID, "preview." .. prefix, "action", "suite_nameplates_preview"),
            prefix == "enemy" and "Enemy nameplate preview" or "Friendly nameplate preview", "button")
    end
    s.bar = bar
    s.back = Fill(bar, "BACKGROUND")
    s.back:SetAllPoints(bar)
    s.progress = Fill(bar, "ARTWORK")
    s.progress:SetPoint("TOPLEFT", bar, "TOPLEFT", 0, 0)
    s.progress:SetPoint("BOTTOMLEFT", bar, "BOTTOMLEFT", 0, 0)
    s.progress:SetWidth(100)
    Tint(s.progress, prefix == "enemy" and "c64b52" or "52a873")
    s.selectedBar = bar:CreateTexture(nil, "OVERLAY")
    s.selectedBar:SetPoint("TOPLEFT", bar, "TOPLEFT", -3, 2)
    s.selectedBar:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", 0, 2)
    s.aggro = Fill(bar, "OVERLAY")
    s.aggro:SetPoint("BOTTOMLEFT", bar, "TOPLEFT", 0, 0)
    s.aggro:SetPoint("BOTTOMRIGHT", bar, "TOPRIGHT", 0, 0)
    s.aggro:SetHeight(2)
    Tint(s.aggro, "ffe93a")
    s.aggroFlash = Fill(bar, "OVERLAY")
    s.aggroFlash:SetAllPoints(bar)
    Tint(s.aggroFlash, "ffff00", 0.24)
    s.border = Border(bar)
    s.healthText = SampleRegion(cell, 78, 18)
    s.value = Text(s.healthText, "", 10, { 1, 1, 1 })
    s.value:SetAllPoints(s.healthText)
    s.value:SetWidth(78)
    s.value:SetJustifyH("RIGHT")
end

local function BuildNameAndLevel(s, cell)
    local prefix = s.prefix
    s.name = CreateFrame("Button", nil, cell)
    s.name:SetSize(118, 20)
    s.name:RegisterForClicks("LeftButtonUp", "RightButtonUp", "MiddleButtonUp")
    s.nameText = Text(s.name, prefix == "enemy" and "Mire Laborer" or "Friendly Player", 12, { 1, 1, 1 })
    s.nameText:SetPoint("LEFT", s.name, "LEFT", 0, 0)
    s.nameText:SetWidth(118)
    s.nameText:SetJustifyH("LEFT")
    s.nameText:SetMaxLines(1)
    s.nameText:SetWordWrap(false)
    s.level = SampleRegion(cell, 24, 16)
    s.levelBack = Fill(s.level, "BACKGROUND")
    s.levelBack:SetAllPoints(s.level)
    Tint(s.levelBack, "191714")
    s.levelSelected = s.level:CreateTexture(nil, "OVERLAY")
    s.levelSelected:SetAtlas("ui-hud-nameplates-levelindicator-rectangle-selected")
    s.levelSelected:SetPoint("TOPLEFT", s.level, "TOPLEFT", -3, 4)
    s.levelSelected:SetPoint("BOTTOMRIGHT", s.level, "BOTTOMRIGHT", 3, -4)
    s.levelBorder = Style.CreateBorder(s.level)
    s.levelText = Text(s.level, prefix == "enemy" and "73" or "80", 11, { 1, 1, 1 })
    s.levelText:SetAllPoints(s.level)
    s.levelText:SetJustifyH("RIGHT")
    s.arrowGroup = CreateFrame("Button", nil, cell)
    s.arrowGroup:SetSize(222, 30)
    s.arrowGroup:SetPoint("CENTER", s.bar, "CENTER", 0, 0)
    s.targetVisual = {}
end

local function Marker(editor, s, cell, kind, color, keyX, keyY)
    local handle = CreateFrame("Button", nil, cell)
    handle:SetSize(22, 22)
    local back = Fill(handle, "BACKGROUND")
    back:SetAllPoints(handle)
    Tint(back, color, 0.18)
    local icon = Fill(handle, "OVERLAY")
    icon:SetPoint("CENTER", handle, "CENTER", 0, 0)
    editor:Bind(handle, s.prefix .. "." .. kind,
        Tr(s.prefix == "enemy" and "Enemy %s marker" or "Friendly %s marker"):format(Tr(kind)), keyX, keyY, s.prefix)
    return handle, back, icon
end

local function BuildMarkers(editor, s, cell)
    local prefix = s.prefix
    local eliteMarker, eliteBack, eliteIcon = Marker(editor, s, cell, "elite", "9370db",
        prefix .. "EliteOffsetX", prefix .. "EliteOffsetY")
    local questMarker, questBack, questIcon = Marker(editor, s, cell, "quest", "ff7e00",
        prefix .. "QuestOffsetX", prefix .. "QuestOffsetY")
    if prefix == "enemy" then editor.questMarkerHandle = questMarker end
    s.markers = {
        { handle = eliteMarker, back = eliteBack, icon = eliteIcon, kind = "elite",
          enabled = prefix .. "EliteMarker", size = prefix .. "EliteMarkerSize", color = "enemyMinibossColor",
          x = prefix .. "EliteOffsetX", y = prefix .. "EliteOffsetY", roles = { [3] = true, [4] = true } },
        { handle = questMarker, back = questBack, icon = questIcon, kind = "quest",
          enabled = prefix .. "QuestMarker", size = prefix .. "QuestMarkerSize", color = "enemyQuestColor",
          x = prefix .. "QuestOffsetX", y = prefix .. "QuestOffsetY", roles = { [5] = true } },
    }
end

local function BuildCast(s, cell)
    local prefix = s.prefix
    s.cast = SampleRegion(cell, 206, 10)
    local castBack = Fill(s.cast, "BACKGROUND")
    castBack:SetAllPoints(s.cast)
    castBack:SetAtlas("ui-castingbar-background")
    -- A real StatusBar owns preview fill geometry, as it does on live plates.
    -- Keep the drag handle separate so editing never changes cast behavior.
    local castProgress = CreateFrame("StatusBar", nil, s.cast)
    castProgress:SetAllPoints(s.cast)
    castProgress:EnableMouse(false)
    castProgress:SetMinMaxValues(0, 100)
    castProgress:SetValue(65)
    castProgress:SetStatusBarTexture("ui-castingbar-filling-standard")
    castProgress:SetStatusBarColor(1, 1, 1, 1)
    s.cast._npProgress = castProgress
    s.castProgress = castProgress
    s.castName = SampleRegion(castProgress, 206, 14)
    s.castText = Text(s.castName, prefix == "enemy" and "Rite of Agony" or "Friendly Cast", 10, { 1, 1, 1 })
    s.castText:SetAllPoints(s.castName)
    s.castText:SetJustifyH("LEFT")
    s.castTime = SampleRegion(castProgress, 38, 14)
    s.castTimeText = Text(s.castTime, "2.3s", 10, { 1, 1, 1 })
    s.castTimeText:SetAllPoints(s.castTime)
    s.castTimeText:SetJustifyH("LEFT")
    s.castIcon = SampleRegion(cell, 14, 14)
    s.castIcon:SetPoint("RIGHT", s.cast, "LEFT", -2, 0)
    local castIconFill = Fill(s.castIcon, "ARTWORK")
    castIconFill:SetAllPoints(s.castIcon)
    Tint(castIconFill, "a8a1df")
end

local function BuildAurasAndPower(s, cell)
    s.auras = AuraGroup(cell, AURA_SAMPLES.debuffs)
    s.buffs = AuraGroup(cell, AURA_SAMPLES.buffs, true)
    s.control = AuraGroup(cell, AURA_SAMPLES.control)
    s.softTarget = SampleRegion(cell, 24, 24)
    local softIcon = Fill(s.softTarget, "ARTWORK")
    softIcon:SetSize(14, 14)
    softIcon:SetPoint("CENTER", s.softTarget, "CENTER")
    Tint(softIcon, "67c7ff")
    s.power = SampleRegion(cell, 86, 8)
    local powerBack = Fill(s.power, "BACKGROUND")
    powerBack:SetAllPoints(s.power)
    Tint(powerBack, "202535", .9)
    local powerFill = Fill(s.power, "ARTWORK")
    powerFill:SetPoint("TOPLEFT", s.power, "TOPLEFT")
    powerFill:SetPoint("BOTTOMLEFT", s.power, "BOTTOMLEFT")
    powerFill:SetWidth(56)
    Tint(powerFill, "397fe3")
    s.powerBorder = Border(s.power)
end

local function BuildRaidAndDetails(s, cell)
    s.raid = SampleRegion(cell, 22, 22)
    s.raidTexture = Fill(s.raid, "ARTWORK")
    s.raidTexture:SetAllPoints(s.raid)
    s.raidTexture:SetTexture("Interface\\TargetingFrame\\UI-RaidTargetingIcon_8")
    s.raid._npTexture = s.raidTexture
    s.classificationBase = SampleRegion(cell, 20, 20)
    s.classificationBase:EnableMouse(false)
    s.classification = SampleRegion(cell, 20, 20)
    s.nativeElite = Fill(s.classification, "OVERLAY")
    s.nativeElite:SetAllPoints(s.classification)
    s.nativeElite:SetAtlas("nameplates-icon-elite-gold")
    s.shield = SampleRegion(s.castProgress, 14, 14)
    local shieldIcon = Fill(s.shield, "OVERLAY")
    shieldIcon:SetAllPoints(s.shield)
    shieldIcon:SetAtlas("nameplates-InterruptShield")
    s.castTarget = SampleRegion(s.castProgress, 64, 14)
    s.castTargetText = Text(s.castTarget, "Mapko", 10, { 1, 1, 1 })
    s.castTargetText:SetAllPoints(s.castTarget)
end

local function BindElements(editor, s)
    local prefix = s.prefix
    local regions = { Health = s.bar, Name = s.name, Level = s.level, HealthText = s.healthText, Cast = s.cast,
        CastText = s.castName, CastTime = s.castTime,
        Auras = s.auras, Buffs = s.buffs, ControlAura = s.control, SoftTarget = s.softTarget,
        RaidIcon = s.raid, Classification = s.classification, CastIcon = s.castIcon, CastShield = s.shield,
        CastTarget = s.castTarget }
    -- Joined labels cannot be looked up, so the side is a translated format.
    local side = Tr(prefix == "enemy" and "Enemy %s" or "Friendly %s")
    for _, element in ipairs(Style.Elements) do
        editor:Bind(regions[element.key], prefix .. "." .. element.key, side:format(Tr(element.label)),
            prefix .. element.key .. "OffsetX", prefix .. element.key .. "OffsetY",
            prefix == "enemy" and element.section or (element.section == "auras" or element.section == "signals")
                and element.section or "friendly")
    end
    if prefix == "friendly" then
        editor:Bind(s.power, "personal.Power", "Personal power bar",
            "personalPowerOffsetX", "personalPowerOffsetY", "personal")
    end
    -- The left arrow is a small hit target; it must not cover name/health.
    s.arrowGroup:SetSize(20, 24)
    editor:Bind(s.arrowGroup, prefix .. ".target", side:format(Tr("target arrows")), "enemyTargetOffsetX",
        "enemyTargetOffsetY", "enemy")
end

----------------------------------------------------------------- sample render
-- Match the loaded Blizzard layout. Forever loads the Camelot constants and
-- level frame, which reserve space on the right. m is the sample's reused
-- metrics table.
local function Metrics(editor, s, m)
    local prefix = s.prefix
    local selectedStyle = P.Get(ID, "nativeStyle")
    m.style = Style.NativeStyleValue(selectedStyle)
    m.classic = Style.ClassicNativePlate(selectedStyle)
    m.forever = P.Suite.Client.isForever
    local sizeScale = SIZE_SCALE[P.Get(ID, "nativeSize")] or SIZE_SCALE[3]
    if m.classic and P.Get(ID, "nativeSize") == 2 then sizeScale = { 0.8, 0.8 } end
    m.horizontal = SetupNumber("horizontalScale", sizeScale[1])
    m.vertical = SetupNumber("verticalScale", sizeScale[2])
    m.classificationScale = SetupNumber("classificationScale", m.horizontal)
    local inset = SetupNumber("insetWidth", 12 * m.horizontal)
    m.friendlyNPC = prefix == "friendly" and editor.friendlyElite and not editor.personal
    local friendlyDisplay = P.Get(ID, "friendlyNamesOnly")
    m.groupOnly = prefix == "friendly" and not editor.personal and not m.friendlyNPC and friendlyDisplay == 3
    m.namesOnly = prefix == "friendly" and not editor.personal and not m.friendlyNPC
        and (friendlyDisplay == 2 or friendlyDisplay == 3 or friendlyDisplay == 1
            and Style.NativeToggle("nameplateShowOnlyNameForFriendlyPlayerUnits", false))
    m.nativeLevel = m.forever and not m.namesOnly
    m.boxedLevel = m.classic or P.Get(ID, "look") == 2
    if m.forever then m.boxedLevel = P.Get(ID, "look") == 2 or P.Get(ID, "levelAppearance") == 2 end
    m.nativeLevelWidth = m.nativeLevel and SetupNumber("playerLevelDiffWidth", 28 * m.classificationScale) or 0
    m.reserve = m.nativeLevel and m.nativeLevelWidth + 5 or 0
    local contentWidth = (m.classic and 152 or m.forever and 190 or 230) * m.horizontal - 2 * inset
    local geometry = P.Get(ID, "look") ~= 2 and P.Get(ID, prefix) and P.Get(ID, "barGeometry") or 1
    local totalWidth, uniformHealth, uniformCast = Style.BarDimensions(geometry, selectedStyle, m.horizontal, m.vertical)
    if totalWidth then contentWidth, m.reserve = totalWidth - 2 * inset, 0 end
    m.classicInset = m.classic and 24.25 * m.horizontal or 0
    m.widthDelta = P.Get(ID, prefix .. "HealthWidthDelta") or 0
    m.heightDelta = P.Get(ID, prefix .. "HealthHeightDelta") or 0
    m.barWidth = contentWidth - m.reserve - m.classicInset + m.widthDelta
    m.castWidth = contentWidth - m.classicInset
    m.healthX = -m.reserve / 2 - (m.classic and 8.625 * m.horizontal or 0) - m.widthDelta / 2
    m.castX = m.classic and 8.625 * m.horizontal or 0
    local style = m.style
    local healthHeight = m.classic and 10 or (style == 0 or style == 2 or style == 3) and 20 or m.forever and 13 or 10
    m.nativeBarHeight = uniformHealth or SetupNumber("healthBarHeight", healthHeight * m.vertical)
    local nativeCastHeight = (style == 2 or style == 4) and 16 or m.classic and 10 or m.forever and 6 or 10
    m.castHeight = uniformCast or SetupNumber("castBarHeight", nativeCastHeight * m.vertical)
    local fallbackAnchor = m.classic and 3 or (style == 0 or style == 2) and 1 or 2
    m.nameAnchor = SetupNumber("unitNameAnchorStyle", fallbackAnchor)
    m.nameSpacing = SetupNumber("healthBarToNameAboveSpacing", (m.classic and 4 or 2) * m.vertical)
    m.castSpacing = SetupNumber("castBarToHealthBarSpacing", (m.classic and 4 or 2) * m.vertical)
    return m
end

-- Bar and cast frame geometry, and the sample's enemy type for this render.
local function RenderFrames(editor, s, m)
    local prefix, bar, cell = s.prefix, s.bar, s.cell
    local barHeight = m.nativeBarHeight + m.heightDelta
    bar:SetSize(m.barWidth, barHeight)
    bar._npNativeWidth, bar._npNativeHeight = m.barWidth - m.widthDelta, m.nativeBarHeight
    bar:ClearAllPoints()
    bar:SetPoint("CENTER", cell, "CENTER", m.healthX + P.Get(ID, prefix .. "HealthOffsetX"),
        -4 + m.heightDelta / 2 + P.Get(ID, prefix .. "HealthOffsetY"))
    s.cast:SetSize(m.castWidth, m.castHeight)
    s.castName:SetWidth(m.castWidth)
    m.availableNameWidth = math.max(20, m.barWidth - math.min(88, m.barWidth * .45))
    cell:SetAlpha(P.Get(ID, prefix) and 1 or 0.4)
    s.selectedBar:SetAtlas(m.forever and "UI-HUD-CoolDownManager-Selected-yellow" or "UI-HUD-Nameplates-Selected")
    s.selectedBar:SetShown(s.state.target and not m.classic and editor:LayerOn("health"))
    local savedRole = prefix == "enemy" and P.Get(ID, "enemyPreviewRole") or nil
    if prefix == "enemy" and editor.previewRole and editor.previewRoleSource ~= savedRole then
        editor.previewRole = nil
    end
    m.role = prefix == "enemy" and not editor.enemyPlayer and (editor.previewRole or savedRole) or nil
    m.descriptor = m.role and Style.Roles[m.role]
end

local function RenderTitle(editor, s, m)
    local prefix, descriptor = s.prefix, m.descriptor
    if descriptor then
        s.title:SetText(Tr("ENEMY / TARGET") .. " · " .. Tr(descriptor.label)
            .. (editor.raidMarked and " · " .. Tr("Raid marked") or ""))
        s.nameText:SetText(Tr(descriptor.sample))
    elseif prefix == "enemy" then
        s.title:SetText(Tr("ENEMY PLAYER / TARGET"))
        s.nameText:SetText(Tr("Enemy Player"))
    end
    s.name:SetShown(editor:LayerOn("name") and not (m.groupOnly and editor.friendlyOutsider))
    if prefix == "friendly" then
        s.title:SetText(Tr(editor.personal and "PERSONAL / PLAYER" or m.friendlyNPC and "FRIENDLY / ELITE NPC"
            or editor.friendlyOutsider and "FRIENDLY / OUTSIDE GROUP" or "FRIENDLY / GROUP"))
        s.nameText:SetText(Tr(editor.personal and "Your Character" or m.friendlyNPC and "Friendly Elite" or "Friendly Player"))
    end
end

local function RenderVisibility(editor, s, m)
    local prefix, namesOnly, friendlyNPC = s.prefix, m.namesOnly, m.friendlyNPC
    s.bar:SetShown(not namesOnly and editor:LayerOn("health"))
    local castMode = P.Get(ID, "look") == 2 and 1 or P.Get(ID, "enemyCastEnabled")
    local nativeCast = C_CVar.GetCVar("nameplateShowCastBars")
    m.showCast = not namesOnly and s.state.cast and editor:LayerOn("cast") and castMode ~= 3
        and (castMode ~= 1 or not P.Suite.Public(nativeCast) or nativeCast ~= "0")
    s.cast:SetShown(m.showCast)
    local auraGroup = prefix == "enemy" and (editor.enemyPlayer and "enemyPlayer" or "enemyNpc") or "friendlyPlayer"
    local auraScale = AuraScale()
    s.auras:SetScale(auraScale)
    s.buffs:SetScale(auraScale)
    s.control:SetScale(auraScale)
    local npcDebuffs = NativeToggle("friendlyNpcDebuffs", "nameplateShowDebuffsOnFriendly")
    s.auras:SetShown(not namesOnly and editor:LayerOn("auras")
        and (friendlyNPC and npcDebuffs or not friendlyNPC and AuraShown(auraGroup, "Debuffs")))
    s.buffs:SetShown(not namesOnly and not friendlyNPC and editor:LayerOn("buffs") and AuraShown(auraGroup, "Buffs"))
    s.control:SetShown(not namesOnly and not friendlyNPC and editor:LayerOn("controlAura")
        and AuraShown(auraGroup, "Control"))
end

local function RenderName(s, m)
    local prefix, name, bar = s.prefix, s.name, s.bar
    local size = P.Get(ID, prefix .. "NameSize")
    name:SetHeight(P.Get(ID, prefix .. "TextEnabled") and size > 0 and size
        or SetupNumber("healthBarFontHeight", (m.classic and 10 or m.forever and 14 or 12) * m.vertical))
    name:ClearAllPoints()
    if m.namesOnly then
        if m.nameAnchor == 1 then Place(s, name, "CENTER", bar, "CENTER", 0, 0, "Name")
        else Place(s, name, "BOTTOM", bar, "TOP", 0, 2, "Name") end
        name:SetWidth(170)
    elseif m.nameAnchor == 3 then
        Place(s, name, "BOTTOM", bar, "TOP", m.classic and 8.625 * m.horizontal or 0, m.nameSpacing, "Name")
        name:SetWidth(m.barWidth - 8 + (m.classic and m.classicInset or 0))
    elseif m.nameAnchor == 2 then
        Place(s, name, "BOTTOMLEFT", bar, "TOPLEFT", 4, m.nameSpacing, "Name")
        name:SetWidth(m.nativeLevel and m.barWidth + m.reserve - 4 or m.availableNameWidth)
    else
        Place(s, name, "LEFT", bar, "LEFT", 4, 0, "Name")
        name:SetWidth(m.availableNameWidth)
    end
    s.nameText:SetWidth(m.namesOnly and 170 or m.nameAnchor == 3 and name:GetWidth() or m.availableNameWidth)
    s.nameText:SetJustifyH((m.namesOnly or m.nameAnchor == 3) and "CENTER" or "LEFT")
end

local function RenderLevel(editor, s, m)
    local prefix, level, levelText = s.prefix, s.level, s.levelText
    local boxed, native, classic = m.boxedLevel, m.nativeLevel, m.classic
    if boxed and native then
        Place(s, level, "LEFT", s.bar, "RIGHT", 5 + (classic and 20.75 * m.horizontal or 0), 0, "Level")
    elseif boxed and classic then
        -- Blizzard anchors the plaque to the container border, while the
        -- preview bar represents the inset health texture.
        Place(s, level, "CENTER", s.bar, "RIGHT", 10 * m.horizontal, 0, "Level")
    else
        Place(s, level, "RIGHT", s.bar, "LEFT", -4, 0, "Level")
    end
    local nativeHeight = (m.style == 0 or m.style == 2) and 23 or 16
    local customSize = P.Get(ID, prefix .. "LevelSize") or 0
    level:SetSize(boxed and native and m.nativeLevelWidth
            or boxed and classic and SetupNumber("levelIconWidth", 15 * m.horizontal)
            or math.max(24, (customSize > 0 and customSize or SetupNumber("levelFontHeight", 10 * m.vertical)) * 2),
        boxed and native and SetupNumber("playerLevelDiffHeight", nativeHeight * m.classificationScale)
            or boxed and classic and SetupNumber("levelIconHeight", 15 * m.vertical) or 16)
    if boxed and native then s.levelBack:SetAtlas("ui-hud-nameplates-levelindicator")
    else Tint(s.levelBack, "191714") end
    s.levelBack:SetShown(boxed and (native or classic))
    s.levelSelected:SetShown(boxed and native and s.state.target and editor:LayerOn("level"))
    Style.PaintBorder(s.levelBorder, level, boxed and not native and classic and 1 or 0, "d9b64b")
    levelText:SetJustifyH(boxed and (native or classic) and "CENTER" or "RIGHT")
    if boxed and (native or classic) then levelText:SetTextColor(1, 0.85, 0.35)
    else levelText:SetTextColor(1, 1, 1) end
    levelText:SetText(prefix == "enemy" and (m.role == 1 and "11" or "73") or "80")
    levelText:SetTextHeight(not boxed and customSize > 0 and customSize or SetupNumber("levelFontHeight", 10 * m.vertical))
    local enabled = P.Get(ID, "look") == 2 or not m.forever and classic or P.Get(ID, prefix .. "LevelEnabled")
    level:SetShown(editor:LayerOn("level") and not m.namesOnly and enabled and (not boxed or native or classic))
end

local function RoleColorShown(editor, m)
    local role, inDungeon = m.role, editor.inDungeon
    local scopeColor = inDungeon and P.Get(ID, "enemyColorsInDungeons") or not inDungeon and P.Get(ID, "enemyColorsOutside")
    local kindColor = role and (role ~= 5 or P.Get(ID, "enemyQuestColors"))
    return kindColor and scopeColor and editor:LayerOn("roleFill") and P.Get(ID, "look") ~= 2
        and P.Get(ID, "enemyRoleColors")
        and (role == 12 and P.Get(ID, "enemyTankMode") or role ~= 12 and P.Get(ID, "enemy" .. m.descriptor.key .. "Enabled"))
end

local function RenderHealth(editor, s, m)
    local prefix = s.prefix
    Place(s, s.healthText, "RIGHT", s.bar, "RIGHT", -4, 0, "HealthText")
    s.healthText:SetShown(not m.namesOnly and editor:LayerOn("healthText"))
    Tint(s.back, P.Get(ID, prefix .. "BackdropColor"), (P.Get(ID, prefix .. "BackdropAlpha") or 100) / 100)
    s.back:SetShown(P.Get(ID, "look") ~= 2 and editor:LayerOn("backdrop")
        and P.Get(ID, prefix .. "BackdropEnabled") and P.Get(ID, prefix .. "BackdropAlpha") > 0)
    if RoleColorShown(editor, m) then
        Tint(s.progress, P.Get(ID, "enemy" .. m.descriptor.key .. "Color"))
    else
        Tint(s.progress, prefix == "enemy" and "c64b52" or "52a873")
    end
    s.progress:SetWidth(m.barWidth * s.state.health / 100)
    local customThreat = P.Get(ID, "look") ~= 2 and P.Get(ID, "threatSignalMode") == 2
    local flashOn = customThreat and P.Get(ID, "threatFlash")
        or not customThreat and NativeBit("nameplateThreatDisplay", 2, false)
    local highlightOn = customThreat and P.Get(ID, "threatHighlight")
        or not customThreat and NativeBit("nameplateThreatDisplay", 1, false)
    Tint(s.aggro, P.Get(ID, "threatHighlightColorEnabled") and P.Get(ID, "threatHighlightColor") or "ffe93a")
    Tint(s.aggroFlash, P.Get(ID, "threatFlashColorEnabled") and P.Get(ID, "threatFlashColor") or "ffff00", 0.24)
    s.aggro:SetShown(prefix == "enemy" and editor.aggroSample and editor:LayerOn("threatHighlight") and highlightOn)
    s.aggroFlash:SetShown(prefix == "enemy" and editor.aggroSample and editor:LayerOn("threatFlash") and flashOn)
    local mode = prefix == "enemy" and (P.Get(ID, "look") == 2 and 1 or P.Get(ID, "enemyTextMode")) or 2
    local health = s.state.health
    local amount = string.format("%.1fM", 3.5 * health / 100)
    local showPercent = mode == 1 and NativeBit("nameplateInfoDisplay", 1, true) or mode == 2 or mode == 4
    local showValue = mode == 1 and NativeBit("nameplateInfoDisplay", 2, false) or mode == 3 or mode == 4
    s.value:SetText(showValue and (amount .. (showPercent and " " .. health .. "%" or ""))
        or (showPercent and health .. "%" or ""))
    s.value:SetShown(not m.namesOnly and editor:LayerOn("healthText") and (showPercent or showValue))
    s.border((P.Get(ID, "look") == 2 or not editor:LayerOn("border")
        or not P.Get(ID, prefix .. "BorderEnabled")) and 0 or P.Get(ID, prefix .. "BorderSize"),
        P.Get(ID, prefix .. "BorderColor"))
end

local function RenderTarget(s, m)
    local prefix, level = s.prefix, s.level
    local arrows = (prefix == "enemy" or not P.Get(ID, "enemyTargetHideFriendly")) and s.state.target
        and P.Get(ID, "enemyTargetMarker") and P.Get(ID, "look") ~= 2
    local targetConfig = s.targetConfig
    for _, key in ipairs(TARGET_KEYS) do
        targetConfig["enemyTarget" .. key] = P.Get(ID, "enemyTarget" .. key)
    end
    local rightGap = m.boxedLevel and level:IsShown() and (m.nativeLevel and m.nativeLevelWidth + 5
        or m.classic and SetupNumber("levelIconWidth", 15 * m.horizontal) + 4) or 0
    local leftGap = m.forever and not m.boxedLevel and level:IsShown() and level:GetWidth() + 4 or 0
    local marker = Style.PaintTarget(s.targetVisual, s.bar, arrows, Style.TargetConfig(targetConfig), s.cell,
        rightGap, leftGap)
    s.arrowGroup:SetShown(arrows and marker ~= nil)
    if marker then
        s.arrowGroup:ClearAllPoints()
        s.arrowGroup:SetPoint("CENTER", marker, "CENTER", 0, 0)
        s.arrowGroup:SetSize(targetConfig.enemyTargetMarkerSize, targetConfig.enemyTargetMarkerSize)
        s.arrowGroup:SetFrameLevel(marker:GetFrameLevel() + 1)
    end
end

local function RenderMarkers(editor, s, m)
    local prefix = s.prefix
    for i = 1, #s.markers do
        local marker = s.markers[i]
        local size = P.Get(ID, marker.size)
        marker.handle:SetSize(size, size)
        Style.PlaceMarker(marker.handle, s.bar, marker.kind, P.Get(ID, marker.x), P.Get(ID, marker.y),
            P.Get(ID, prefix .. (marker.kind == "elite" and "EliteMarkerAnchor" or "QuestMarkerAnchor")))
        Style.PaintMarker(marker.icon, marker.kind, size, P.Get(ID, marker.color), m.role == 4 and "boss" or "elite")
        marker.handle:SetShown(editor:LayerOn(marker.kind .. "Marker") and P.Get(ID, "look") ~= 2
            and P.Get(ID, marker.enabled) and (prefix == "friendly" and m.friendlyNPC or marker.roles[m.role] == true))
        marker.handle:EnableMouse(true)
        marker.back:Hide()
    end
end

local function RenderFonts(s, m)
    local prefix = s.prefix
    local nativeNameSize = SetupNumber("healthBarFontHeight", (m.classic and 10 or m.forever and 14 or 12) * m.vertical)
    local nativeCastSize = SetupNumber("castBarFontHeight", 10 * m.vertical)
    local castSize, castOutline = P.Get(ID, prefix .. "CastSize"), P.Get(ID, prefix .. "CastOutline")
    PreviewFont(s.nameText, prefix, P.Get(ID, prefix .. "NameSize"), P.Get(ID, prefix .. "TextOutline"), nativeNameSize)
    PreviewFont(s.castText, prefix .. "Cast", castSize, castOutline, nativeCastSize)
    PreviewFont(s.castTimeText, prefix .. "Cast", castSize, castOutline, nativeCastSize)
    PreviewFont(s.castTargetText, prefix .. "Cast", castSize, castOutline, nativeCastSize)
    if prefix == "enemy" then
        PreviewFont(s.value, prefix, P.Get(ID, "enemyHealthTextSize"), P.Get(ID, "enemyTextOutline"), nativeNameSize)
    end
end

local function RenderCastAndAuras(editor, s, m)
    local prefix, cast = s.prefix, s.cast
    s.castName:SetShown(m.showCast and editor:LayerOn("castText") and NativeCastDetail("enemyCastSpellName", 1, true))
    -- Blizzard anchors the castbar to the plate, not the movable health container.
    Place(s, cast, "TOP", s.cell, "CENTER", m.castX, -4 - m.nativeBarHeight / 2 - m.castSpacing, "Cast")
    Place(s, s.castName, "TOPLEFT", cast, "BOTTOMLEFT", 0, -1, "CastText")
    Place(s, s.castTime, "LEFT", cast, "RIGHT", 4, 0, "CastTime")
    s.castTime:SetShown(m.showCast and P.Get(ID, "look") ~= 2
        and P.Get(ID, prefix .. "CastTimeEnabled") and editor:LayerOn("castTime"))
    -- Blizzard's DebuffListFrame starts at HealthBarsContainer.LEFT, not
    -- at the middle of the visible bar. Its BOTTOM follows bar/name TOP;
    -- the Suite name offset is compensated independently at runtime.
    Place(s, s.auras, "BOTTOMLEFT", s.bar, "TOPLEFT", m.classic and -3.5 * m.horizontal or 0,
        DebuffPadding() + (m.nameAnchor == 1 and 0 or m.nameSpacing + s.name:GetHeight()), "Auras")
    Place(s, s.buffs, "RIGHT", s.classificationBase, "LEFT", -5, 0, "Buffs")
    Place(s, s.control, "LEFT", s.bar, "RIGHT", 5 + m.reserve + (m.classic and 20.75 * m.horizontal or 0), 0,
        "ControlAura")
    -- Blizzard anchors this to the nameplate root, independently of a
    -- dragged health container.
    Place(s, s.softTarget, "BOTTOM", s.cell, "CENTER", 0, 34, "SoftTarget")
    local softKind = prefix == "enemy" and (editor.softInteract and "Interact" or "Enemy") or "Friend"
    s.softTarget:SetShown(editor.softTargetSample and editor:LayerOn("softTarget")
        and NativeToggle("softTargetIconGate", "SoftTargetNameplateSize")
        and NativeToggle("softTarget" .. softKind, "SoftTargetIcon" .. softKind))
    if prefix == "friendly" then
        s.power:ClearAllPoints()
        s.power:SetPoint("TOP", s.bar, "BOTTOM", P.Get(ID, "personalPowerOffsetX"), -3 + P.Get(ID, "personalPowerOffsetY"))
        s.power:SetShown(editor.personal and editor:LayerOn("power"))
        s.powerBorder(editor.personal and P.Get(ID, "look") ~= 2 and P.Get(ID, "personalPowerSkin")
            and P.Get(ID, "personalPowerBorderSize") or 0, P.Get(ID, "personalPowerBorderColor"))
    end
end

local function RenderRaid(editor, s, m)
    local prefix, raid = s.prefix, s.raid
    if m.namesOnly then
        -- Runtime subtracts the name displacement from this native link.
        raid:ClearAllPoints()
        raid:SetPoint("BOTTOM", s.name, "TOP",
            P.Get(ID, prefix .. "RaidIconOffsetX") - P.Get(ID, prefix .. "NameOffsetX"),
            10 + P.Get(ID, prefix .. "RaidIconOffsetY") - P.Get(ID, prefix .. "NameOffsetY"))
    else Place(s, raid, "RIGHT", s.bar, "LEFT", m.classic and -3.5 * m.horizontal or 0, 0, "RaidIcon") end
    s.raidTexture:SetTexture("Interface\\TargetingFrame\\UI-RaidTargetingIcon_" .. (editor.raidIndex or 8))
    raid:SetShown(editor:LayerOn("raidIcon") and editor.raidMarked
        and (prefix ~= "enemy" or P.Get(ID, "look") == 2 or P.Get(ID, "enemyRaidIcon")))
    -- Hiding the icon with Suite alpha does not collapse Blizzard's frame.
    raid:SetWidth(editor.raidMarked and 22 or 0)
    s.classificationBase:ClearAllPoints()
    s.classificationBase:SetPoint("RIGHT", raid, "LEFT", 0, 0)
    Place(s, s.classification, "CENTER", s.classificationBase, "CENTER",
        -P.Get(ID, prefix .. "RaidIconOffsetX"), -P.Get(ID, prefix .. "RaidIconOffsetY"), "Classification")
    local role = m.role
    if role == 3 then s.nativeElite:SetAtlas("UI-HUD-UnitFrame-Target-PortraitOn-Boss-Rare-Star")
    else s.nativeElite:SetAtlas("nameplates-icon-elite-gold") end
    local rarityMode = P.Get(ID, "look") == 2 and 1 or P.Get(ID, "enemyRarityIcon")
    local showRarity = rarityMode == 2 or rarityMode == 1 and NativeBit("nameplateInfoDisplay", 3, true)
    local showClassification = not editor.raidMarked and editor:LayerOn("classification")
        and (prefix == "enemy" and (role == 3 or role == 4) or m.friendlyNPC) and showRarity
    s.classification:SetShown(showClassification)
    s.classificationBase:SetWidth(showClassification and 20 or 0) -- Blizzard ClassificationFrame collapsesLayout.
end

local function RenderCastDetails(editor, s, m)
    local cast = s.cast
    Place(s, s.castIcon, "LEFT", cast, "BOTTOMLEFT", 0, -7, "CastIcon")
    Place(s, s.shield, "LEFT", cast, "BOTTOMLEFT", 0, -7, "CastShield")
    s.shield:SetShown(editor.uninterruptible and m.showCast and editor:LayerOn("castShield"))
    local classicCast = P.Get(ID, "nativeStyle") == 7 or P.Get(ID, "nativeStyle") == 8
    s.castIcon:SetShown(m.showCast and editor:LayerOn("castIcon") and (not editor.uninterruptible or classicCast)
        and NativeCastDetail("enemyCastSpellIcon", 2, false))
    Place(s, s.castTarget, "TOPRIGHT", cast, "BOTTOMRIGHT", 0, -1, "CastTarget")
    s.castTarget:SetShown(m.showCast and editor:LayerOn("castTarget") and NativeCastDetail("enemyCastSpellTarget", 3, false))
end

local function Render(editor, s)
    s.cell:SetShown(editor.sampleKind == s.prefix)
    s.title:SetShown(editor:LayerOn("guides"))
    local m = Metrics(editor, s, s.metrics)
    RenderFrames(editor, s, m)
    RenderTitle(editor, s, m)
    RenderVisibility(editor, s, m)
    RenderName(s, m)
    RenderLevel(editor, s, m)
    RenderHealth(editor, s, m)
    RenderTarget(s, m)
    RenderMarkers(editor, s, m)
    RenderFonts(s, m)
    RenderCastAndAuras(editor, s, m)
    RenderRaid(editor, s, m)
    RenderCastDetails(editor, s, m)
end

local function Sample(editor, prefix, x)
    local s = { prefix = prefix, metrics = {}, targetConfig = {},
        state = { health = prefix == "enemy" and 53 or 100, target = prefix == "enemy", cast = true } }
    local cell = CreateFrame("Frame", nil, editor.stage)
    cell:SetSize(260, 124)
    cell:SetPoint("CENTER", editor.stage, "CENTER", x, 0)
    editor.sampleCells[prefix] = cell
    s.cell = cell
    s.title = Text(cell, prefix == "enemy" and Tr("ENEMY / TARGET") or Tr("FRIENDLY"), 10, { 0.7, 0.75, 0.8 })
    s.title:SetPoint("TOP", cell, "TOP", 0, 0)
    BuildBar(editor, s, cell)
    BuildNameAndLevel(s, cell)
    BuildMarkers(editor, s, cell)
    BuildCast(s, cell)
    BuildAurasAndPower(s, cell)
    BuildRaidAndDetails(s, cell)
    BindElements(editor, s)
    editor.renderers[#editor.renderers + 1] = function() Render(editor, s) end
end

function P.BuildNameplatesPreview(ctx, builder, sections)
    local editor = P.NameplatesEditor.Create(ctx, builder, sections)
    if not editor then return end
    editor.sampleCells = {}
    Sample(editor, "enemy", 0)
    Sample(editor, "friendly", 0)
    editor:Paint()
end

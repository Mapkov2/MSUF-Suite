local _, P = ...
local M, W, Tr = P.M, P.W, P.Tr
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
    local api = _G.C_CVar
    local value = api and type(api.GetCVar) == "function" and api.GetCVar("nameplateAuraScale")
    return P.Suite.Public(value) and tonumber(value) or 1
end

-- The sample uses Blizzard's current public setup values. Its element offsets
-- then start from the same native anchors that Layout.lua displaces at runtime.
local function SetupNumber(key, fallback)
    local setup = _G.NamePlateSetupOptions
    local value = setup and setup[key]
    if P.Suite.Public(value) and type(value) == "number" and value == value then return value end
    return fallback
end

local function DebuffPadding()
    local constants, registry = _G.NamePlateConstants, _G.CVarCallbackRegistry
    local key = constants and constants.DEBUFF_PADDING_CVAR
    if key and registry and type(registry.GetCVarNumberOrDefault) == "function" then
        local ok, value = pcall(registry.GetCVarNumberOrDefault, registry, key)
        if ok and P.Suite.Public(value) and type(value) == "number" and value == value then return value end
    end
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
    label:SetText(value)
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

local function Sample(editor, prefix, x)
    local canvas, previewContext = editor.stage, editor
    local state = { health = prefix == "enemy" and 53 or 100, target = prefix == "enemy", cast = true }
    local cell = CreateFrame("Frame", nil, canvas)
    cell:SetSize(260, 124)
    cell:SetPoint("CENTER", canvas, "CENTER", x, 0)
    editor.sampleCells[prefix] = cell
    local title = Text(cell, prefix == "enemy" and Tr("ENEMY / TARGET") or Tr("FRIENDLY"), 10, { 0.7, 0.75, 0.8 })
    title:SetPoint("TOP", cell, "TOP", 0, 0)

    local bar = CreateFrame("Button", nil, cell)
    bar:SetSize(206, 20)
    bar:SetPoint("CENTER", cell, "CENTER", 0, -4)
    bar._msufPreviewState = state
    if M.RegisterControlMetadata then
        M.RegisterControlMetadata(bar,
            P.Meta(PAGE, ID, "preview." .. prefix, "action", "suite_nameplates_preview"),
            Tr(prefix == "enemy" and "Enemy nameplate preview" or "Friendly nameplate preview"), "button")
    end
    local back = Fill(bar, "BACKGROUND")
    back:SetAllPoints(bar)
    local progress = Fill(bar, "ARTWORK")
    progress:SetPoint("TOPLEFT", bar, "TOPLEFT", 0, 0)
    progress:SetPoint("BOTTOMLEFT", bar, "BOTTOMLEFT", 0, 0)
    progress:SetWidth(100)
    Tint(progress, prefix == "enemy" and "c64b52" or "52a873")
    local selectedBar = bar:CreateTexture(nil, "OVERLAY")
    selectedBar:SetPoint("TOPLEFT", bar, "TOPLEFT", -3, 2)
    selectedBar:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", 0, 2)
    local aggro = Fill(bar, "OVERLAY")
    aggro:SetPoint("BOTTOMLEFT", bar, "TOPLEFT", 0, 0)
    aggro:SetPoint("BOTTOMRIGHT", bar, "TOPRIGHT", 0, 0)
    aggro:SetHeight(2)
    Tint(aggro, "ffe93a")
    local aggroFlash = Fill(bar, "OVERLAY")
    aggroFlash:SetAllPoints(bar)
    Tint(aggroFlash, "ffff00", 0.24)
    local border = Border(bar)
    local healthText = SampleRegion(cell, 78, 18)
    local value = Text(healthText, "", 10, { 1, 1, 1 })
    value:SetAllPoints(healthText)
    value:SetWidth(78)
    value:SetJustifyH("RIGHT")

    local name = CreateFrame("Button", nil, cell)
    name:SetSize(118, 20)
    name:RegisterForClicks("LeftButtonUp", "RightButtonUp", "MiddleButtonUp")
    local nameText = Text(name, prefix == "enemy" and "Mire Laborer" or "Friendly Player", 12, { 1, 1, 1 })
    nameText:SetPoint("LEFT", name, "LEFT", 0, 0)
    nameText:SetWidth(118)
    nameText:SetJustifyH("LEFT")
    if nameText.SetMaxLines then nameText:SetMaxLines(1) end
    if nameText.SetWordWrap then nameText:SetWordWrap(false) end
    local level = SampleRegion(cell, 24, 16)
    local levelBack = Fill(level, "BACKGROUND")
    levelBack:SetAllPoints(level)
    Tint(levelBack, "191714")
    local levelSelected = level:CreateTexture(nil, "OVERLAY")
    levelSelected:SetAtlas("ui-hud-nameplates-levelindicator-rectangle-selected")
    levelSelected:SetPoint("TOPLEFT", level, "TOPLEFT", -3, 4)
    levelSelected:SetPoint("BOTTOMRIGHT", level, "BOTTOMRIGHT", 3, -4)
    local levelBorder = Style.CreateBorder(level)
    local levelText = Text(level, prefix == "enemy" and "73" or "80", 11, { 1, 1, 1 })
    levelText:SetAllPoints(level)
    levelText:SetJustifyH("RIGHT")
    local arrowGroup = CreateFrame("Button", nil, cell)
    arrowGroup:SetSize(222, 30)
    arrowGroup:SetPoint("CENTER", bar, "CENTER", 0, 0)
    local targetVisual = {}
    local function Marker(kind, color, keyX, keyY)
        local handle = CreateFrame("Button", nil, cell)
        handle:SetSize(22, 22)
        local back = Fill(handle, "BACKGROUND")
        back:SetAllPoints(handle)
        Tint(back, color, 0.18)
        local icon = Fill(handle, "OVERLAY")
        icon:SetPoint("CENTER", handle, "CENTER", 0, 0)
        editor:Bind(handle, prefix .. "." .. kind,
            Tr(prefix == "enemy" and "Enemy %s marker" or "Friendly %s marker"):format(Tr(kind)), keyX, keyY, prefix)
        return handle, back, icon
    end
    local eliteMarker, eliteBack, eliteIcon = Marker("elite", "9370db",
        prefix .. "EliteOffsetX", prefix .. "EliteOffsetY")
    local questMarker, questBack, questIcon = Marker("quest", "ff7e00",
        prefix .. "QuestOffsetX", prefix .. "QuestOffsetY")
    if prefix == "enemy" then editor.questMarkerHandle = questMarker end
    local markers = {
        { handle = eliteMarker, back = eliteBack, icon = eliteIcon, kind = "elite",
          enabled = prefix .. "EliteMarker", size = prefix .. "EliteMarkerSize", color = "enemyMinibossColor",
          x = prefix .. "EliteOffsetX", y = prefix .. "EliteOffsetY", roles = { [3] = true, [4] = true } },
        { handle = questMarker, back = questBack, icon = questIcon, kind = "quest",
          enabled = prefix .. "QuestMarker", size = prefix .. "QuestMarkerSize", color = "enemyQuestColor",
          x = prefix .. "QuestOffsetX", y = prefix .. "QuestOffsetY", roles = { [5] = true } },
    }
    local cast = SampleRegion(cell, 206, 10)
    local castBack = Fill(cast, "BACKGROUND")
    castBack:SetAllPoints(cast)
    castBack:SetAtlas("ui-castingbar-background")
    -- A real StatusBar owns preview fill geometry, as it does on live plates.
    -- Keep the drag handle separate so editing never changes cast behavior.
    local castProgress = CreateFrame("StatusBar", nil, cast)
    castProgress:SetAllPoints(cast)
    castProgress:EnableMouse(false)
    castProgress:SetMinMaxValues(0, 100)
    castProgress:SetValue(65)
    castProgress:SetStatusBarTexture("ui-castingbar-filling-standard")
    castProgress:SetStatusBarColor(1, 1, 1, 1)
    cast._npProgress = castProgress
    local castName = SampleRegion(castProgress, 206, 14)
    local castText = Text(castName, prefix == "enemy" and "Rite of Agony" or "Friendly Cast", 10, { 1, 1, 1 })
    castText:SetAllPoints(castName)
    castText:SetJustifyH("LEFT")
    local castTime = SampleRegion(castProgress, 38, 14)
    local castTimeText = Text(castTime, "2.3s", 10, { 1, 1, 1 })
    castTimeText:SetAllPoints(castTime)
    castTimeText:SetJustifyH("LEFT")
    local castIcon = SampleRegion(cell, 14, 14)
    castIcon:SetPoint("RIGHT", cast, "LEFT", -2, 0)
    local castIconFill = Fill(castIcon, "ARTWORK")
    castIconFill:SetAllPoints(castIcon)
    Tint(castIconFill, "a8a1df")
    local auras = AuraGroup(cell, AURA_SAMPLES.debuffs)
    local buffs = AuraGroup(cell, AURA_SAMPLES.buffs, true)
    local control = AuraGroup(cell, AURA_SAMPLES.control)
    local softTarget = SampleRegion(cell, 24, 24)
    local softIcon = Fill(softTarget, "ARTWORK")
    softIcon:SetSize(14, 14)
    softIcon:SetPoint("CENTER", softTarget, "CENTER")
    Tint(softIcon, "67c7ff")
    local power = SampleRegion(cell, 86, 8)
    local powerBack = Fill(power, "BACKGROUND")
    powerBack:SetAllPoints(power)
    Tint(powerBack, "202535", .9)
    local powerFill = Fill(power, "ARTWORK")
    powerFill:SetPoint("TOPLEFT", power, "TOPLEFT")
    powerFill:SetPoint("BOTTOMLEFT", power, "BOTTOMLEFT")
    powerFill:SetWidth(56)
    Tint(powerFill, "397fe3")
    local powerBorder = Border(power)

    local raid = SampleRegion(cell, 22, 22)
    local raidTexture = Fill(raid, "ARTWORK")
    raidTexture:SetAllPoints(raid)
    raidTexture:SetTexture("Interface\\TargetingFrame\\UI-RaidTargetingIcon_8")
    raid._npTexture = raidTexture
    local classificationBase = SampleRegion(cell, 20, 20)
    classificationBase:EnableMouse(false)
    local classification = SampleRegion(cell, 20, 20)
    local nativeElite = Fill(classification, "OVERLAY")
    nativeElite:SetAllPoints(classification)
    nativeElite:SetAtlas("nameplates-icon-elite-gold")
    local shield = SampleRegion(castProgress, 14, 14)
    local shieldIcon = Fill(shield, "OVERLAY")
    shieldIcon:SetAllPoints(shield)
    shieldIcon:SetAtlas("nameplates-InterruptShield")
    local castTarget = SampleRegion(castProgress, 64, 14)
    local castTargetText = Text(castTarget, "Mapko", 10, { 1, 1, 1 })
    castTargetText:SetAllPoints(castTarget)
    local regions = { Health = bar, Name = name, Level = level, HealthText = healthText, Cast = cast,
        CastText = castName, CastTime = castTime,
        Auras = auras, Buffs = buffs, ControlAura = control, SoftTarget = softTarget,
        RaidIcon = raid, Classification = classification, CastIcon = castIcon, CastShield = shield, CastTarget = castTarget }
    -- Joined labels cannot be looked up, so the side is a translated format.
    local side = Tr(prefix == "enemy" and "Enemy %s" or "Friendly %s")
    for _, element in ipairs(Style.Elements) do
        editor:Bind(regions[element.key], prefix .. "." .. element.key, side:format(Tr(element.label)),
            prefix .. element.key .. "OffsetX", prefix .. element.key .. "OffsetY",
            prefix == "enemy" and element.section or (element.section == "auras" or element.section == "signals")
                and element.section or "friendly")
    end
    if prefix == "friendly" then
        editor:Bind(power, "personal.Power", "Personal power bar",
            "personalPowerOffsetX", "personalPowerOffsetY", "personal")
    end
    do
        -- The left arrow is a small hit target; it must not cover name/health.
        arrowGroup:SetSize(20, 24)
        editor:Bind(arrowGroup, prefix .. ".target", side:format(Tr("target arrows")), "enemyTargetOffsetX",
            "enemyTargetOffsetY", "enemy")
    end
    local function Place(frame, point, owner, relative, x, y, key)
        frame:ClearAllPoints()
        frame:SetPoint(point, owner, relative, x + P.Get(ID, prefix .. key .. "OffsetX"), y + P.Get(ID, prefix .. key .. "OffsetY"))
    end

    local function Render()
        cell:SetShown(editor.sampleKind == prefix)
        title:SetShown(editor:LayerOn("guides"))
        -- Match the loaded Blizzard layout. Forever loads the Camelot
        -- constants and level frame, which reserve space on the right.
        local selectedStyle = P.Get(ID, "nativeStyle")
        local style = Style.NativeStyleValue(selectedStyle)
        local classic = Style.ClassicNativePlate(selectedStyle)
        local forever = P.Suite.Client.isForever
        local sizeScale = SIZE_SCALE[P.Get(ID, "nativeSize")] or SIZE_SCALE[3]
        if classic and P.Get(ID, "nativeSize") == 2 then sizeScale = { 0.8, 0.8 } end
        local horizontal = SetupNumber("horizontalScale", sizeScale[1])
        local vertical = SetupNumber("verticalScale", sizeScale[2])
        local classificationScale = SetupNumber("classificationScale", horizontal)
        local inset = SetupNumber("insetWidth", 12 * horizontal)
        local friendlyNPC = prefix == "friendly" and editor.friendlyElite and not editor.personal
        local friendlyDisplay = P.Get(ID, "friendlyNamesOnly")
        local groupOnly = prefix == "friendly" and not editor.personal and not friendlyNPC
            and friendlyDisplay == 3
        local namesOnly = prefix == "friendly" and not editor.personal and not friendlyNPC
            and (friendlyDisplay == 2 or friendlyDisplay == 3 or friendlyDisplay == 1
                and Style.NativeToggle("nameplateShowOnlyNameForFriendlyPlayerUnits", false))
        local nativeLevel = forever and not namesOnly
        local boxedLevel = classic or P.Get(ID, "look") == 2
        if forever then
            boxedLevel = P.Get(ID, "look") == 2 or P.Get(ID, "levelAppearance") == 2
        end
        local nativeLevelWidth = nativeLevel and SetupNumber("playerLevelDiffWidth", 28 * classificationScale) or 0
        local reserve = nativeLevel and nativeLevelWidth + 5 or 0
        local contentWidth = (classic and 152 or forever and 190 or 230) * horizontal - 2 * inset
        local classicInset = classic and 24.25 * horizontal or 0
        local widthDelta = P.Get(ID, prefix .. "HealthWidthDelta") or 0
        local heightDelta = P.Get(ID, prefix .. "HealthHeightDelta") or 0
        local barWidth = contentWidth - reserve - classicInset + widthDelta
        local castWidth = contentWidth - classicInset
        local healthX = -reserve / 2 - (classic and 8.625 * horizontal or 0) - widthDelta / 2
        local castX = classic and 8.625 * horizontal or 0
        local healthHeight = classic and 10 or (style == 0 or style == 2 or style == 3)
            and 20 or forever and 13 or 10
        local nativeBarHeight = SetupNumber("healthBarHeight", healthHeight * vertical)
        local barHeight = nativeBarHeight + heightDelta
        local nativeCastHeight = (style == 2 or style == 4) and 16 or classic and 10
            or forever and 6 or 10
        local castHeight = SetupNumber("castBarHeight", nativeCastHeight * vertical)
        local fallbackAnchor = classic and 3 or (style == 0 or style == 2) and 1 or 2
        local nameAnchor = SetupNumber("unitNameAnchorStyle", fallbackAnchor)
        local nameSpacing = SetupNumber("healthBarToNameAboveSpacing", (classic and 4 or 2) * vertical)
        local castSpacing = SetupNumber("castBarToHealthBarSpacing", (classic and 4 or 2) * vertical)
        bar:SetSize(barWidth, barHeight)
        bar._npNativeWidth, bar._npNativeHeight = barWidth - widthDelta, nativeBarHeight
        bar:ClearAllPoints()
        bar:SetPoint("CENTER", cell, "CENTER", healthX + P.Get(ID, prefix .. "HealthOffsetX"),
            -4 + heightDelta / 2 + P.Get(ID, prefix .. "HealthOffsetY"))
        cast:SetSize(castWidth, castHeight)
        castName:SetWidth(castWidth)
        local availableNameWidth = math.max(20, barWidth - math.min(88, barWidth * .45))
        local show = P.Get(ID, prefix)
        cell:SetAlpha(show and 1 or 0.4)
        selectedBar:SetAtlas(forever and "UI-HUD-CoolDownManager-Selected-yellow"
            or "UI-HUD-Nameplates-Selected")
        selectedBar:SetShown(state.target and not classic and editor:LayerOn("health"))
        local savedRole = prefix == "enemy" and P.Get(ID, "enemyPreviewRole") or nil
        if prefix == "enemy" and editor.previewRole and editor.previewRoleSource ~= savedRole then
            editor.previewRole = nil
        end
        local role = prefix == "enemy" and not editor.enemyPlayer and (editor.previewRole or savedRole) or nil
        local descriptor = role and Style.Roles[role]
        if descriptor then
            title:SetText(Tr("ENEMY / TARGET") .. " · " .. Tr(descriptor.label)
                .. (editor.raidMarked and " · " .. Tr("Raid marked") or ""))
            nameText:SetText(descriptor.sample)
        elseif prefix == "enemy" then
            title:SetText(Tr("ENEMY PLAYER / TARGET"))
            nameText:SetText("Enemy Player")
        end
        name:SetShown(editor:LayerOn("name") and not (groupOnly and editor.friendlyOutsider))
        if prefix == "friendly" then
            title:SetText(Tr(editor.personal and "PERSONAL / PLAYER" or friendlyNPC and "FRIENDLY / ELITE NPC"
                or editor.friendlyOutsider and "FRIENDLY / OUTSIDE GROUP" or "FRIENDLY / GROUP"))
            nameText:SetText(editor.personal and "Your Character" or friendlyNPC and "Friendly Elite" or "Friendly Player")
        end
        bar:SetShown(not namesOnly and editor:LayerOn("health"))
        local castMode = P.Get(ID, "look") == 2 and 1 or P.Get(ID, "enemyCastEnabled")
        local nativeCast = _G.C_CVar and _G.C_CVar.GetCVar and _G.C_CVar.GetCVar("nameplateShowCastBars")
        local showCast = not namesOnly and state.cast and editor:LayerOn("cast") and castMode ~= 3
            and (castMode ~= 1 or not P.Suite.Public(nativeCast) or nativeCast ~= "0")
        cast:SetShown(showCast)
        local auraGroup = prefix == "enemy" and (editor.enemyPlayer and "enemyPlayer" or "enemyNpc")
            or "friendlyPlayer"
        local auraScale = AuraScale()
        auras:SetScale(auraScale)
        buffs:SetScale(auraScale)
        control:SetScale(auraScale)
        local npcDebuffs = NativeToggle("friendlyNpcDebuffs", "nameplateShowDebuffsOnFriendly")
        auras:SetShown(not namesOnly and editor:LayerOn("auras")
            and (friendlyNPC and npcDebuffs or not friendlyNPC and AuraShown(auraGroup, "Debuffs")))
        buffs:SetShown(not namesOnly and not friendlyNPC and editor:LayerOn("buffs")
            and AuraShown(auraGroup, "Buffs"))
        control:SetShown(not namesOnly and not friendlyNPC and editor:LayerOn("controlAura")
            and AuraShown(auraGroup, "Control"))
        name:SetHeight(P.Get(ID, prefix .. "TextEnabled") and P.Get(ID, prefix .. "NameSize") > 0
            and P.Get(ID, prefix .. "NameSize") or SetupNumber("healthBarFontHeight", (classic and 10 or forever and 14 or 12) * vertical))
        name:ClearAllPoints()
        if namesOnly then
            if nameAnchor == 1 then Place(name, "CENTER", bar, "CENTER", 0, 0, "Name")
            else Place(name, "BOTTOM", bar, "TOP", 0, 2, "Name") end
            name:SetWidth(170)
        elseif nameAnchor == 3 then
            Place(name, "BOTTOM", bar, "TOP", classic and 8.625 * horizontal or 0, nameSpacing, "Name")
            name:SetWidth(barWidth - 8 + (classic and classicInset or 0))
        elseif nameAnchor == 2 then
            Place(name, "BOTTOMLEFT", bar, "TOPLEFT", 4, nameSpacing, "Name")
            name:SetWidth(nativeLevel and barWidth + reserve - 4 or availableNameWidth)
        else
            Place(name, "LEFT", bar, "LEFT", 4, 0, "Name")
            name:SetWidth(availableNameWidth)
        end
        nameText:SetWidth(namesOnly and 170 or nameAnchor == 3 and name:GetWidth() or availableNameWidth)
        nameText:SetJustifyH((namesOnly or nameAnchor == 3) and "CENTER" or "LEFT")
        if boxedLevel and nativeLevel then
            Place(level, "LEFT", bar, "RIGHT", 5 + (classic and 20.75 * horizontal or 0), 0, "Level")
        elseif boxedLevel and classic then
            -- Blizzard anchors the plaque to the container border, while the
            -- preview bar represents the inset health texture.
            Place(level, "CENTER", bar, "RIGHT", 10 * horizontal, 0, "Level")
        else
            Place(level, "RIGHT", bar, "LEFT", -4, 0, "Level")
        end
        local nativeHeight = (style == 0 or style == 2) and 23 or 16
        local customLevelSize = P.Get(ID, prefix .. "LevelSize") or 0
        level:SetSize(boxedLevel and nativeLevel and nativeLevelWidth
                or boxedLevel and classic and SetupNumber("levelIconWidth", 15 * horizontal)
                or math.max(24, (customLevelSize > 0 and customLevelSize
                    or SetupNumber("levelFontHeight", 10 * vertical)) * 2),
            boxedLevel and nativeLevel and SetupNumber("playerLevelDiffHeight", nativeHeight * classificationScale)
                or boxedLevel and classic and SetupNumber("levelIconHeight", 15 * vertical) or 16)
        if boxedLevel and nativeLevel then levelBack:SetAtlas("ui-hud-nameplates-levelindicator")
        else Tint(levelBack, "191714") end
        levelBack:SetShown(boxedLevel and (nativeLevel or classic))
        levelSelected:SetShown(boxedLevel and nativeLevel and state.target and editor:LayerOn("level"))
        Style.PaintBorder(levelBorder, level, boxedLevel and not nativeLevel and classic and 1 or 0, "d9b64b")
        levelText:SetJustifyH(boxedLevel and (nativeLevel or classic) and "CENTER" or "RIGHT")
        if boxedLevel and (nativeLevel or classic) then levelText:SetTextColor(1, 0.85, 0.35)
        else levelText:SetTextColor(1, 1, 1) end
        levelText:SetText(prefix == "enemy" and (role == 1 and "11" or "73") or "80")
        local levelSize = P.Get(ID, prefix .. "LevelSize") or 0
        levelText:SetTextHeight(not boxedLevel and levelSize > 0 and levelSize
            or SetupNumber("levelFontHeight", 10 * vertical))
        local levelEnabled = P.Get(ID, "look") == 2 or not forever and classic
            or P.Get(ID, prefix .. "LevelEnabled")
        level:SetShown(editor:LayerOn("level") and not namesOnly and levelEnabled
            and (not boxedLevel or nativeLevel or classic))
        Place(healthText, "RIGHT", bar, "RIGHT", -4, 0, "HealthText")
        healthText:SetShown(not namesOnly and editor:LayerOn("healthText"))
        Tint(back, P.Get(ID, prefix .. "BackdropColor"),
            (P.Get(ID, prefix .. "BackdropAlpha") or 100) / 100)
        back:SetShown(P.Get(ID, "look") ~= 2 and editor:LayerOn("backdrop")
            and P.Get(ID, prefix .. "BackdropEnabled")
            and P.Get(ID, prefix .. "BackdropAlpha") > 0)
        local scopeColor = previewContext.inDungeon and P.Get(ID, "enemyColorsInDungeons")
            or not previewContext.inDungeon and P.Get(ID, "enemyColorsOutside")
        local kindColor = role and (role ~= 5 or P.Get(ID, "enemyQuestColors"))
        if kindColor and scopeColor and editor:LayerOn("roleFill")
            and P.Get(ID, "look") ~= 2 and P.Get(ID, "enemyRoleColors")
            and (role == 12 and P.Get(ID, "enemyTankMode") or role ~= 12 and P.Get(ID, "enemy" .. descriptor.key .. "Enabled")) then
            local color = P.Get(ID, "enemy" .. descriptor.key .. "Color")
            Tint(progress, color)
        else
            Tint(progress, prefix == "enemy" and "c64b52" or "52a873")
        end
        progress:SetWidth(barWidth * state.health / 100)
        local customThreat = P.Get(ID, "look") ~= 2 and P.Get(ID, "threatSignalMode") == 2
        local flashOn = customThreat and P.Get(ID, "threatFlash")
            or not customThreat and NativeBit("nameplateThreatDisplay", 2, false)
        local highlightOn = customThreat and P.Get(ID, "threatHighlight")
            or not customThreat and NativeBit("nameplateThreatDisplay", 1, false)
        Tint(aggro, P.Get(ID, "threatHighlightColorEnabled") and P.Get(ID, "threatHighlightColor") or "ffe93a")
        Tint(aggroFlash, P.Get(ID, "threatFlashColorEnabled") and P.Get(ID, "threatFlashColor") or "ffff00", 0.24)
        aggro:SetShown(prefix == "enemy" and editor.aggroSample
            and editor:LayerOn("threatHighlight") and highlightOn)
        aggroFlash:SetShown(prefix == "enemy" and editor.aggroSample
            and editor:LayerOn("threatFlash") and flashOn)
        local mode = prefix == "enemy" and (P.Get(ID, "look") == 2 and 1 or P.Get(ID, "enemyTextMode")) or 2
        local amount = string.format("%.1fM", 3.5 * state.health / 100)
        local showPercent = mode == 1 and NativeBit("nameplateInfoDisplay", 1, true) or mode == 2 or mode == 4
        local showValue = mode == 1 and NativeBit("nameplateInfoDisplay", 2, false) or mode == 3 or mode == 4
        value:SetText(showValue and (amount .. (showPercent and " " .. state.health .. "%" or ""))
            or (showPercent and state.health .. "%" or ""))
        value:SetShown(not namesOnly and editor:LayerOn("healthText") and (showPercent or showValue))
        local borderColor = P.Get(ID, prefix .. "BorderColor")
        border((P.Get(ID, "look") == 2 or not editor:LayerOn("border")
            or not P.Get(ID, prefix .. "BorderEnabled")) and 0
            or P.Get(ID, prefix .. "BorderSize"), borderColor)
        local arrows = (prefix == "enemy" or not P.Get(ID, "enemyTargetHideFriendly")) and state.target
            and P.Get(ID, "enemyTargetMarker")
            and P.Get(ID, "look") ~= 2
        local targetConfig = {}
        for _, key in ipairs({ "Style", "Layout", "Anchor", "Direction", "MarkerSize", "OffsetX", "OffsetY", "Color" }) do
            targetConfig["enemyTarget" .. key] = P.Get(ID, "enemyTarget" .. key)
        end
        local rightGap = boxedLevel and level:IsShown() and (nativeLevel and nativeLevelWidth + 5
            or classic and SetupNumber("levelIconWidth", 15 * horizontal) + 4) or 0
        local leftGap = forever and not boxedLevel and level:IsShown() and level:GetWidth() + 4 or 0
        local marker = Style.PaintTarget(targetVisual, bar, arrows, Style.TargetConfig(targetConfig), cell,
            rightGap, leftGap)
        arrowGroup:SetShown(arrows and marker ~= nil)
        if marker then
            arrowGroup:ClearAllPoints()
            arrowGroup:SetPoint("CENTER", marker, "CENTER", 0, 0)
            arrowGroup:SetSize(targetConfig.enemyTargetMarkerSize, targetConfig.enemyTargetMarkerSize)
            arrowGroup:SetFrameLevel(marker:GetFrameLevel() + 1)
        end
        do
            for i = 1, #markers do
                local m = markers[i]
                local markerSize = P.Get(ID, m.size)
                m.handle:SetSize(markerSize, markerSize)
                Style.PlaceMarker(m.handle, bar, m.kind, P.Get(ID, m.x), P.Get(ID, m.y),
                    P.Get(ID, prefix .. (m.kind == "elite" and "EliteMarkerAnchor" or "QuestMarkerAnchor")))
                Style.PaintMarker(m.icon, m.kind, markerSize, P.Get(ID, m.color), role == 4 and "boss" or "elite")
                m.handle:SetShown(editor:LayerOn(m.kind .. "Marker") and P.Get(ID, "look") ~= 2 and P.Get(ID, m.enabled)
                    and (prefix == "friendly" and friendlyNPC or m.roles[role] == true))
                m.handle:EnableMouse(true)
                m.back:Hide()
            end
        end
        local nativeNameSize = SetupNumber("healthBarFontHeight", (classic and 10 or forever and 14 or 12) * vertical)
        local nativeCastSize = SetupNumber("castBarFontHeight", 10 * vertical)
        PreviewFont(nameText, prefix, P.Get(ID, prefix .. "NameSize"), P.Get(ID, prefix .. "TextOutline"), nativeNameSize)
        PreviewFont(castText, prefix .. "Cast", P.Get(ID, prefix .. "CastSize"), P.Get(ID, prefix .. "CastOutline"), nativeCastSize)
        PreviewFont(castTimeText, prefix .. "Cast", P.Get(ID, prefix .. "CastSize"), P.Get(ID, prefix .. "CastOutline"), nativeCastSize)
        PreviewFont(castTargetText, prefix .. "Cast", P.Get(ID, prefix .. "CastSize"), P.Get(ID, prefix .. "CastOutline"), nativeCastSize)
        if prefix == "enemy" then
            PreviewFont(value, prefix, P.Get(ID, "enemyHealthTextSize"), P.Get(ID, "enemyTextOutline"), nativeNameSize)
        end
        castName:SetShown(showCast and editor:LayerOn("castText")
            and NativeCastDetail("enemyCastSpellName", 1, true))
        -- Blizzard anchors the castbar to the plate, not the movable health container.
        Place(cast, "TOP", cell, "CENTER", castX, -4 - nativeBarHeight / 2 - castSpacing, "Cast")
        Place(castName, "TOPLEFT", cast, "BOTTOMLEFT", 0, -1, "CastText")
        Place(castTime, "LEFT", cast, "RIGHT", 4, 0, "CastTime")
        castTime:SetShown(showCast and P.Get(ID, "look") ~= 2
            and P.Get(ID, prefix .. "CastTimeEnabled") and editor:LayerOn("castTime"))
        local auraY = DebuffPadding()
        -- Blizzard's DebuffListFrame starts at HealthBarsContainer.LEFT, not
        -- at the middle of the visible bar. Its BOTTOM follows bar/name TOP;
        -- the Suite name offset is compensated independently at runtime.
        Place(auras, "BOTTOMLEFT", bar, "TOPLEFT", classic and -3.5 * horizontal or 0,
            auraY + (nameAnchor == 1 and 0 or nameSpacing + name:GetHeight()), "Auras")
        Place(buffs, "RIGHT", classificationBase, "LEFT", -5, 0, "Buffs")
        Place(control, "LEFT", bar, "RIGHT", 5 + reserve
            + (classic and 20.75 * horizontal or 0), 0, "ControlAura")
        -- Blizzard anchors this to the nameplate root, independently of a
        -- dragged health container.
        Place(softTarget, "BOTTOM", cell, "CENTER", 0, 34, "SoftTarget")
        local softKind = prefix == "enemy" and (editor.softInteract and "Interact" or "Enemy") or "Friend"
        softTarget:SetShown(editor.softTargetSample and editor:LayerOn("softTarget")
            and NativeToggle("softTargetIconGate", "SoftTargetNameplateSize")
            and NativeToggle("softTarget" .. softKind, "SoftTargetIcon" .. softKind))
        if prefix == "friendly" then
            power:ClearAllPoints()
            power:SetPoint("TOP", bar, "BOTTOM", P.Get(ID, "personalPowerOffsetX"),
                -3 + P.Get(ID, "personalPowerOffsetY"))
            power:SetShown(editor.personal and editor:LayerOn("power"))
            powerBorder(editor.personal and P.Get(ID, "look") ~= 2 and P.Get(ID, "personalPowerSkin")
                and P.Get(ID, "personalPowerBorderSize") or 0,
                P.Get(ID, "personalPowerBorderColor"))
        end
        if namesOnly then
            -- Runtime subtracts the name displacement from this native link.
            raid:ClearAllPoints()
            raid:SetPoint("BOTTOM", name, "TOP",
                P.Get(ID, prefix .. "RaidIconOffsetX") - P.Get(ID, prefix .. "NameOffsetX"),
                10 + P.Get(ID, prefix .. "RaidIconOffsetY") - P.Get(ID, prefix .. "NameOffsetY"))
        else Place(raid, "RIGHT", bar, "LEFT", classic and -3.5 * horizontal or 0, 0, "RaidIcon") end
        raidTexture:SetTexture("Interface\\TargetingFrame\\UI-RaidTargetingIcon_" .. (editor.raidIndex or 8))
        local showRaid = editor:LayerOn("raidIcon") and editor.raidMarked
            and (prefix ~= "enemy" or P.Get(ID, "look") == 2 or P.Get(ID, "enemyRaidIcon"))
        raid:SetShown(showRaid)
        -- Hiding the icon with Suite alpha does not collapse Blizzard's frame.
        raid:SetWidth(editor.raidMarked and 22 or 0)
        classificationBase:ClearAllPoints()
        classificationBase:SetPoint("RIGHT", raid, "LEFT", 0, 0)
        Place(classification, "CENTER", classificationBase, "CENTER",
            -P.Get(ID, prefix .. "RaidIconOffsetX"), -P.Get(ID, prefix .. "RaidIconOffsetY"), "Classification")
        if role == 3 then nativeElite:SetAtlas("UI-HUD-UnitFrame-Target-PortraitOn-Boss-Rare-Star")
        else nativeElite:SetAtlas("nameplates-icon-elite-gold") end
        local rarityMode = P.Get(ID, "look") == 2 and 1 or P.Get(ID, "enemyRarityIcon")
        local showRarity = rarityMode == 2 or rarityMode == 1
            and NativeBit("nameplateInfoDisplay", 3, true)
        local showClassification = not editor.raidMarked and editor:LayerOn("classification")
            and (prefix == "enemy" and (role == 3 or role == 4) or friendlyNPC)
            and showRarity
        classification:SetShown(showClassification)
        classificationBase:SetWidth(showClassification and 20 or 0) -- Blizzard ClassificationFrame collapsesLayout.
        Place(castIcon, "LEFT", cast, "BOTTOMLEFT", 0, -7, "CastIcon")
        Place(shield, "LEFT", cast, "BOTTOMLEFT", 0, -7, "CastShield")
        shield:SetShown(editor.uninterruptible and showCast and editor:LayerOn("castShield"))
        local classicCast = P.Get(ID, "nativeStyle") == 7 or P.Get(ID, "nativeStyle") == 8
        castIcon:SetShown(showCast and editor:LayerOn("castIcon") and (not editor.uninterruptible or classicCast)
            and NativeCastDetail("enemyCastSpellIcon", 2, false))
        Place(castTarget, "TOPRIGHT", cast, "BOTTOMRIGHT", 0, -1, "CastTarget")
        castTarget:SetShown(showCast and editor:LayerOn("castTarget")
            and NativeCastDetail("enemyCastSpellTarget", 3, false))
    end
    editor.renderers[#editor.renderers + 1] = Render
end

function P.BuildNameplatesPreview(ctx, builder, sections)
    local editor = P.NameplatesEditor.Create(ctx, builder, sections)
    if not editor then return end
    editor.sampleCells = {}
    Sample(editor, "enemy", 0)
    Sample(editor, "friendly", 0)
    editor:Paint()
end

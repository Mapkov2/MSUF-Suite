local _, P = ...
local M, W, Tr = P.M, P.W, P.Tr
local Style = P.Suite.NameplateStyle
local ID, PAGE = "nameplates", "suite_nameplates"
local WHITE = "Interface\\Buttons\\WHITE8X8"
local SIZE_SCALE = { [2] = { 0.75, 0.8 }, [3] = { 1, 1 },
    [4] = { 1.25, 1.25 }, [5] = { 1.4, 1.4 }, [6] = { 1.6, 1.6 } }

local function NativeBit(cvar, index, fallback)
    local api = _G.C_CVar
    local value = api and type(api.GetCVar) == "function" and api.GetCVar(cvar)
    local flags = Style.CVarFlags(value)
    if flags == nil then return fallback end
    return math.floor(flags / 2 ^ (index - 1)) % 2 == 1
end

local function NativeCastDetail(key, index, fallback)
    if P.Get(ID, "look") ~= 2 and P.Get(ID, "enemyCastDisplay") == 2 then
        return P.Get(ID, key)
    end
    return NativeBit("nameplateCastBarDisplay", index, fallback)
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
            (prefix == "enemy" and "Enemy" or "Friendly") .. " nameplate preview", "button")
    end
    local back = Fill(bar, "BACKGROUND")
    back:SetAllPoints(bar)
    local progress = Fill(bar, "ARTWORK")
    progress:SetPoint("TOPLEFT", bar, "TOPLEFT", 0, 0)
    progress:SetPoint("BOTTOMLEFT", bar, "BOTTOMLEFT", 0, 0)
    progress:SetWidth(100)
    Tint(progress, prefix == "enemy" and "c64b52" or "52a873")
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
        editor:Bind(handle, prefix .. "." .. kind, (prefix == "enemy" and "Enemy " or "Friendly ") .. kind .. " marker", keyX, keyY, prefix)
        return handle, back, icon
    end
    local eliteMarker, eliteBack, eliteIcon = Marker("elite", "9370db",
        prefix .. "EliteOffsetX", prefix .. "EliteOffsetY")
    local questMarker, questBack, questIcon = Marker("quest", "ff7e00",
        prefix .. "QuestOffsetX", prefix .. "QuestOffsetY")
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
    local castIcon = SampleRegion(cell, 14, 14)
    castIcon:SetPoint("RIGHT", cast, "LEFT", -2, 0)
    local castIconFill = Fill(castIcon, "ARTWORK")
    castIconFill:SetAllPoints(castIcon)
    Tint(castIconFill, "a8a1df")
    local auras = SampleRegion(cell, 75, 18)
    for i = 1, 3 do
        local icon = Fill(auras, "ARTWORK")
        icon:SetSize(18, 18)
        icon:SetPoint("LEFT", auras, "LEFT", (i - 1) * 23, 0)
        Tint(icon, ({ "557dc5", "a666bb", "c88b4d" })[i])
    end

    local raid = SampleRegion(cell, 18, 18)
    local raidTexture = Fill(raid, "ARTWORK")
    raidTexture:SetAllPoints(raid)
    raidTexture:SetTexture("Interface\\TargetingFrame\\UI-RaidTargetingIcon_8")
    raid._npTexture = raidTexture
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
    local regions = { Health = bar, Name = name, HealthText = healthText, Cast = cast, CastText = castName, Auras = auras,
        RaidIcon = raid, Classification = classification, CastIcon = castIcon, CastShield = shield, CastTarget = castTarget }
    local side = prefix == "enemy" and "Enemy " or "Friendly "
    for _, element in ipairs(Style.Elements) do
        editor:Bind(regions[element.key], prefix .. "." .. element.key, side .. element.label,
            prefix .. element.key .. "OffsetX", prefix .. element.key .. "OffsetY",
            prefix == "enemy" and element.section or "friendly")
    end
    do
        -- The left arrow is a small hit target; it must not cover name/health.
        arrowGroup:SetSize(20, 24)
        editor:Bind(arrowGroup, prefix .. ".target", side .. "target arrows", "enemyTargetOffsetX", "enemyTargetOffsetY", "enemy")
    end
    local function Place(frame, point, owner, relative, x, y, key)
        frame:ClearAllPoints()
        frame:SetPoint(point, owner, relative, x + P.Get(ID, prefix .. key .. "OffsetX"), y + P.Get(ID, prefix .. key .. "OffsetY"))
    end

    local function Render()
        cell:SetShown(editor.sampleKind == prefix)
        title:SetShown(editor:LayerOn("guides"))
        -- Match Blizzard's content width (230 minus two 12px insets) and
        -- Modern bar heights. The old fixed preview hid the Small-size bug.
        local sizeScale = SIZE_SCALE[P.Get(ID, "nativeSize")] or SIZE_SCALE[3]
        local barWidth = 206 * sizeScale[1]
        local barHeight = 20 * sizeScale[2]
        local castHeight = 10 * sizeScale[2]
        bar:SetSize(barWidth, barHeight)
        bar:ClearAllPoints()
        bar:SetPoint("CENTER", cell, "CENTER", P.Get(ID, prefix .. "HealthOffsetX"),
            -4 + P.Get(ID, prefix .. "HealthOffsetY"))
        cast:SetSize(barWidth, castHeight)
        castName:SetWidth(barWidth)
        local availableNameWidth = math.max(20, barWidth - 88)
        local show = P.Get(ID, prefix)
        cell:SetAlpha(show and 1 or 0.4)
        local savedRole = prefix == "enemy" and P.Get(ID, "enemyPreviewRole") or nil
        if prefix == "enemy" and editor.previewRole and editor.previewRoleSource ~= savedRole then
            editor.previewRole = nil
        end
        local role = prefix == "enemy" and (editor.previewRole or savedRole) or nil
        local descriptor = role and Style.Roles[role]
        if descriptor then
            title:SetText(Tr("ENEMY / TARGET") .. " · " .. Tr(descriptor.label)
                .. (editor.raidMarked and " · " .. Tr("Raid marked") or ""))
            nameText:SetText(descriptor.sample)
        end
        local friendlyNPC = prefix == "friendly" and editor.friendlyElite
        local groupOnly = prefix == "friendly" and not friendlyNPC and P.Get(ID, "friendlyGroupOnly") and P.Get(ID, "look") ~= 2
        local namesOnly = prefix == "friendly" and not friendlyNPC and (P.Get(ID, "friendlyNamesOnly") == 2 or groupOnly)
        name:SetShown(editor:LayerOn("name") and not (groupOnly and editor.friendlyOutsider))
        if prefix == "friendly" then
            title:SetText(Tr(friendlyNPC and "FRIENDLY / ELITE NPC"
                or editor.friendlyOutsider and "FRIENDLY / OUTSIDE GROUP" or "FRIENDLY / GROUP"))
            nameText:SetText(friendlyNPC and "Friendly Elite" or "Friendly Player")
        end
        bar:SetShown(not namesOnly and editor:LayerOn("health"))
        local castMode = P.Get(ID, "look") == 2 and 1 or P.Get(ID, "enemyCastEnabled")
        local nativeCast = _G.C_CVar and _G.C_CVar.GetCVar and _G.C_CVar.GetCVar("nameplateShowCastBars")
        local showCast = not namesOnly and state.cast and editor:LayerOn("cast") and castMode ~= 3
            and (castMode ~= 1 or not P.Suite.Public(nativeCast) or nativeCast ~= "0")
        cast:SetShown(showCast)
        auras:SetShown(not namesOnly and editor:LayerOn("auras"))
        name:ClearAllPoints()
        if namesOnly then
            Place(name, "CENTER", cell, "CENTER", 0, -4, "Name")
            name:SetWidth(170)
        else
            Place(name, "LEFT", bar, "LEFT", 4, 0, "Name")
            name:SetWidth(availableNameWidth)
        end
        nameText:SetWidth(namesOnly and 170 or availableNameWidth)
        Place(healthText, "RIGHT", bar, "RIGHT", -4, 0, "HealthText")
        healthText:SetShown(not namesOnly and editor:LayerOn("healthText"))
        Tint(back, P.Get(ID, prefix .. "BackdropColor"),
            (P.Get(ID, prefix .. "BackdropAlpha") or 100) / 100)
        local scopeColor = previewContext.inDungeon and P.Get(ID, "enemyColorsInDungeons")
            or not previewContext.inDungeon and P.Get(ID, "enemyColorsOutside")
        local kindColor = role and (role ~= 5 or P.Get(ID, "enemyQuestColors"))
        if kindColor and scopeColor and P.Get(ID, "look") ~= 2 and P.Get(ID, "enemyRoleColors")
            and (role == 12 and P.Get(ID, "enemyTankMode") or role ~= 12 and P.Get(ID, "enemy" .. descriptor.key .. "Enabled")) then
            local color = P.Get(ID, "enemy" .. descriptor.key .. "Color")
            Tint(progress, color)
        else
            Tint(progress, prefix == "enemy" and "c64b52" or "52a873")
        end
        progress:SetWidth(barWidth * state.health / 100)
        local mode = prefix == "enemy" and (P.Get(ID, "look") == 2 and 1 or P.Get(ID, "enemyTextMode")) or 2
        local amount = string.format("%.1fM", 3.5 * state.health / 100)
        local showPercent = mode == 1 and NativeBit("nameplateInfoDisplay", 1, true) or mode == 2 or mode == 4
        local showValue = mode == 1 and NativeBit("nameplateInfoDisplay", 2, false) or mode == 3 or mode == 4
        value:SetText(showValue and (amount .. (showPercent and " " .. state.health .. "%" or ""))
            or (showPercent and state.health .. "%" or ""))
        value:SetShown(not namesOnly and editor:LayerOn("healthText") and (showPercent or showValue))
        local borderColor = P.Get(ID, prefix .. "BorderColor")
        border(P.Get(ID, "look") == 2 and 0 or P.Get(ID, prefix .. "BorderSize"), borderColor)
        local arrows = (prefix == "enemy" or not P.Get(ID, "enemyTargetHideFriendly")) and state.target
            and editor:LayerOn("target") and P.Get(ID, "enemyTargetMarker")
            and P.Get(ID, "look") ~= 2
        local targetConfig = {}
        for _, key in ipairs({ "Style", "Layout", "Anchor", "Direction", "MarkerSize", "OffsetX", "OffsetY", "Color" }) do
            targetConfig["enemyTarget" .. key] = P.Get(ID, "enemyTarget" .. key)
        end
        local marker = Style.PaintTarget(targetVisual, bar, arrows, Style.TargetConfig(targetConfig), cell)
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
                Style.PlaceMarker(m.handle, bar, m.kind, P.Get(ID, m.x), P.Get(ID, m.y),
                    P.Get(ID, prefix .. (m.kind == "elite" and "EliteMarkerAnchor" or "QuestMarkerAnchor")))
                Style.PaintMarker(m.icon, m.kind, P.Get(ID, m.size), P.Get(ID, m.color), role == 4 and "boss" or "elite")
                m.handle:SetShown(editor:LayerOn(m.kind .. "Marker") and P.Get(ID, "look") ~= 2 and P.Get(ID, m.enabled)
                    and (prefix == "friendly" and friendlyNPC or m.roles[role] == true))
                m.handle:EnableMouse(true)
                m.back:Hide()
            end
        end
        PreviewFont(nameText, prefix, P.Get(ID, prefix .. "NameSize"), P.Get(ID, prefix .. "TextOutline"), 12)
        PreviewFont(castText, prefix .. "Cast", P.Get(ID, prefix .. "CastSize"), P.Get(ID, prefix .. "CastOutline"), 11)
        PreviewFont(castTargetText, prefix .. "Cast", P.Get(ID, prefix .. "CastSize"), P.Get(ID, prefix .. "CastOutline"), 11)
        if prefix == "enemy" then
            PreviewFont(value, prefix, P.Get(ID, "enemyHealthTextSize"), P.Get(ID, "enemyTextOutline"), 11)
        end
        castName:SetShown(showCast and editor:LayerOn("castText")
            and NativeCastDetail("enemyCastSpellName", 1, true))
        -- Blizzard anchors the castbar to the plate, not the movable health container.
        Place(cast, "CENTER", cell, "CENTER", 0, -4 - barHeight / 2 - castHeight / 2 - 2, "Cast")
        Place(castName, "TOPLEFT", cast, "BOTTOMLEFT", 0, -1, "CastText")
        Place(auras, "BOTTOM", bar, "TOP", 0, 14, "Auras")
        if namesOnly then Place(raid, "BOTTOM", name, "TOP", 0, 8, "RaidIcon")
        else Place(raid, "RIGHT", bar, "LEFT", -25, 0, "RaidIcon") end
        raidTexture:SetTexture("Interface\\TargetingFrame\\UI-RaidTargetingIcon_" .. (editor.raidIndex or 8))
        raid:SetShown(editor:LayerOn("raidIcon") and editor.raidMarked and (prefix ~= "enemy" or P.Get(ID, "look") == 2
            or P.Get(ID, "enemyRaidIcon")))
        Place(classification, "RIGHT", bar, "LEFT", -3, 0, "Classification")
        if role == 3 then nativeElite:SetAtlas("UI-HUD-UnitFrame-Target-PortraitOn-Boss-Rare-Star")
        else nativeElite:SetAtlas("nameplates-icon-elite-gold") end
        local rarityMode = P.Get(ID, "look") == 2 and 1 or P.Get(ID, "enemyRarityIcon")
        local showRarity = rarityMode == 2 or rarityMode == 1
            and NativeBit("nameplateInfoDisplay", 3, true)
        classification:SetShown(not editor.raidMarked and editor:LayerOn("classification")
            and (prefix == "enemy" and (role == 3 or role == 4) or friendlyNPC)
            and showRarity)
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

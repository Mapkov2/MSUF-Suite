local _, NS = ...
-- Presentation shared by the native skin and its options preview. Loading
-- this file creates no frames, hooks, timers or event listeners.
local Style = {}

function Style.CastFillColors(cast, locked)
    local bridge = NS.HostBridge
    local resolve = bridge and bridge.SharedCastFillColors
    local r, g, b, nr, ng, nb
    if resolve then r, g, b, nr, ng, nb = resolve() end
    if cast and cast ~= "" then r, g, b = NS.RGB(cast) end
    if locked and locked ~= "" then nr, ng, nb = NS.RGB(locked) end
    return r or 1, g or .84, b or .2, nr or .62, ng or .62, nb or .62
end

function Style.SharedCastColor()
    local r, g, b = Style.CastFillColors()
    return r, g, b
end

function Style.SharedLockedCastColor()
    return select(4, Style.CastFillColors())
end

function Style.SharedCastbar(look)
    local bridge = NS.HostBridge
    local read = bridge and bridge.SharedCastbarStyle
    if read and look ~= 2 then return read() end
end

NS.NameplateStyle = Style
-- Nameplate indicators with data available for the plate's own unit token.
-- The menu and preview share the same labels, artwork and default placement.
Style.Status = {
    { key = "StatusLeader", label = "Leader icon", player = true, side = "friendly", texture = "Interface\\GroupFrame\\UI-Group-LeaderIcon", x = -30 },
    { key = "StatusAssist", label = "Assist icon", player = true, side = "friendly", texture = "Interface\\GroupFrame\\UI-Group-AssistantIcon", x = -14 },
    { key = "StatusRace", label = "Race text", player = true, sample = "Tauren", x = 16, y = 29 },
    { key = "StatusClass", label = "Class text", player = true, sample = "Warrior", x = 16, y = 14 },
    { key = "StatusGroup", label = "Raid group", player = true, side = "friendly", sample = "4", x = 48 },
    { key = "StatusDead", label = "Dead / Offline text", sample = "Dead", anchor = 5, y = 0 },
    { key = "StatusGhost", label = "Ghost text", player = true, sample = "Ghost", anchor = 5, y = -15 },
    { key = "StatusAFK", label = "AFK text", player = true, sample = "AFK", x = -30, y = 26 },
    { key = "StatusAFKTimer", label = "AFK timer", player = true, sample = "5:00", x = -30, y = 13 },
    { key = "StatusDND", label = "DND text", player = true, sample = "DND", x = -78, y = 13 },
    { key = "StatusCombat", label = "Combat icon", atlas = "UI-HUD-UnitFrame-Player-CombatIcon", x = -46 },
    { key = "StatusRez", label = "Incoming resurrection", player = true, texture = "Interface\\RaidFrame\\Raid-Icon-Rez", x = -62 },
    { key = "StatusPvP", label = "PvP flag", player = true, texture = "Interface\\TargetingFrame\\UI-PVP-Horde", x = 32 },
    { key = "StatusBossNumber", label = "Boss number", side = "enemy", sample = "1", anchor = 3, x = 0 },
}
Style.StatusByKey = {}
for _, item in ipairs(Style.Status) do Style.StatusByKey[item.key] = item end

function Style.StatusSupported(item, side)
    return (not item.side or item.side == side) and (not item.forever or NS.Client.isForever)
end

function Style.StatusAnchor(index) return NS.AnchorPoints[index] end

function Style.StatusPoint(config, prefix, item)
    local key = prefix .. item.key
    local point = NS.AnchorPoints[config[key .. "Anchor"] or item.anchor or 2] or "TOP"
    return point, config[key .. "OffsetX"] or item.x or 0, config[key .. "OffsetY"] or item.y or 9
end

-- Blizzard's array CVars store six bits per data byte after a version byte.
-- Keep one decoder for the runtime and preview; callers choose their flags.
function Style.CVarFlags(value)
    if not NS.Public(value) or type(value) ~= "string" or #value == 0 then return nil end
    local byte = value:byte(2) or 64
    if byte < 64 or byte > 127 then return nil end
    return byte - 64
end
function Style.NativeBit(cvar, index, fallback)
    local flags = Style.CVarFlags(C_CVar.GetCVar(cvar))
    if flags == nil then return fallback end
    return math.floor(flags / 2 ^ (index - 1)) % 2 == 1
end
function Style.NativeToggle(cvar, fallback)
    local value = C_CVar.GetCVar(cvar)
    if not NS.Public(value) or type(value) ~= "string" then return fallback end
    local number = tonumber(value)
    if number then return number > 0 end
    return value ~= "0"
end
-- Offset keys describe existing Blizzard regions, relative to their native
-- layout. The same descriptors drive the settings and preview handles.
Style.Elements = {
    { key = "Name", label = "Name", section = "enemy" },
    { key = "Level", label = "Level", section = "enemy" },
    { key = "HealthText", label = "Health text", section = "enemy" },
    { key = "Cast", label = "Castbar", section = "castbar" },
    { key = "CastText", label = "Spell name", section = "castbar" },
    { key = "CastTime", label = "Cast time", section = "castbar" },
    { key = "Auras", label = "Auras", section = "enemy" },
    { key = "RaidIcon", label = "Raid marker", section = "enemy" },
    { key = "Classification", label = "Blizzard elite / rare icon", section = "enemy" },
    { key = "CastIcon", label = "Blizzard spell icon", section = "castbar" },
    { key = "CastShield", label = "Blizzard interrupt shield", section = "castbar" },
    { key = "CastTarget", label = "Spell target", section = "castbar" },
    { key = "Health", label = "Health bar", section = "enemy" },
    { key = "Buffs", label = "Buffs", section = "auras" },
    { key = "ControlAura", label = "Control effect", section = "auras" },
    { key = "SoftTarget", label = "Soft target icon", section = "signals" },
}
-- control: the whole label of the group's control switch, translated as one
-- text so each language keeps its own word order.
Style.AuraGroups = {
    { key = "enemyNpc", label = "Enemy NPC", control = "Enemy NPC Crowd control",
      cvar = "nameplateEnemyNpcAuraDisplay" },
    { key = "enemyPlayer", label = "Enemy player", control = "Enemy player Loss of control",
      cvar = "nameplateEnemyPlayerAuraDisplay" },
    { key = "friendlyPlayer", label = "Friendly player", control = "Friendly player Loss of control",
      cvar = "nameplateFriendlyPlayerAuraDisplay" },
}
Style.AuraCVar = {}
for _, group in ipairs(Style.AuraGroups) do Style.AuraCVar[group.key] = group.cvar end
Style.AuraBits = { Buffs = 1, Debuffs = 2, Control = 3 }

-- The active Blizzard setup is authoritative for the preview. A profile
-- choice can be ahead of the CVar update that has reached visible plates.
function Style.NativeStyleValue(choice)
    local value = C_CVar.GetCVar("nameplateStyle")
    if NS.Public(value) then
        local number = tonumber(value)
        if number and number >= 0 and number <= 6 then return number end
    end
    if type(choice) == "number" and choice >= 2 and choice <= 8 then return choice - 2 end
    return 0
end

function Style.ClassicNativePlate(choice)
    local classic = NamePlateSetupOptions.useClassicHealthBar
    if NS.Public(classic) and type(classic) == "boolean" then return classic end
    return Style.NativeStyleValue(choice) == 6
end

-- The native badge can replace the Suite number. Its space in the native
-- layout is independent from its visibility when a skin hides it.
function Style.LevelMode(forever, classic, styled, enabled, appearance, badgeShown, namesOnly)
    if namesOnly or styled and not enabled then return end
    if forever then
        if not styled or appearance == 2 then return badgeShown ~= false and "badge" or nil end
    elseif classic then
        return "classic"
    elseif badgeShown ~= false then
        return "badge"
    elseif not styled or not enabled then
        return
    end
    return "number"
end

-- Stable Retail geometry for portable profiles. The native clients use
-- different constants (upstream/live vs upstream/forever Camelot); offsets
-- alone cannot carry a plate's dimensions between them. Preview and runtime
-- share these bases and still use Blizzard's selected size scales.
function Style.BarDimensions(mode, choice, horizontal, vertical)
    if mode ~= 2 then return end
    local style = Style.NativeStyleValue(choice)
    local classic = Style.ClassicNativePlate(choice)
    local health = not classic and (style == 0 or style == 2 or style == 3) and 20 or 10
    local cast = not classic and (style == 2 or style == 4) and 16 or 10
    return (classic and 152 or 230) * horizontal, health * vertical,
        cast * vertical, (classic and 14 or 12) * vertical
end

function Style.CastWidth(base, health, mode, manual, delta)
    if mode == 2 then return math.max(30, health) end
    if mode == 3 then return math.max(30, manual) end
    return base + delta
end

-- The Modern artwork extends left/top by 2/3 and right/bottom by 6/6.
-- Move only the rendered corners. The selection border still anchors to
-- the unchanged native region.
function Style.FitModernHealthBackground(texture, fit)
    local left, top, right, bottom = 0, 0, 0, 0
    if fit then left, top, right, bottom = 2, -3, -6, 6 end
    texture:SetVertexOffset(1, left, top)     -- upper left
    texture:SetVertexOffset(2, left, bottom)  -- lower left
    texture:SetVertexOffset(3, right, top)    -- upper right
    texture:SetVertexOffset(4, right, bottom) -- lower right
end

-- Zero keeps the native height or icon dimensions.
function Style.CastDimensions(height, icon, castHeight, iconWidth, iconHeight)
    if type(height) == "number" and height > 0 then castHeight = height end
    if type(icon) == "number" and icon > 0 then iconWidth, iconHeight = icon, icon end
    return castHeight, iconWidth, iconHeight
end
-- The native percent-only header can be mirrored without reading its text.
function Style.MirrorHeader(enabled, mode, anchor, namesOnly)
    return enabled == true and mode == 2 and anchor == 2 and namesOnly == false
end

function Style.PlaceMirroredHeader(name, value, health, container, spacing, nx, ny, hx, hy, point)
    name:ClearAllPoints()
    value:ClearAllPoints()
    point(value, "BOTTOMLEFT", health, "TOPLEFT", 4 + hx, 2 + hy)
    point(name, "BOTTOMLEFT", value, "BOTTOMRIGHT", 2 + nx - hx, ny - hy)
    point(name, "BOTTOMRIGHT", container, "TOPRIGHT", -4 + nx, spacing + ny)
end

function Style.RepairGeometry(modules)
    local plates = modules.nameplates
    -- Recognize the supplied pre-geometry Mapko export too, so importing that
    -- original string on Forever gets the same dimensions. Other old profiles
    -- keep their native bases; current exports explicitly carry the choice.
    if type(plates) == "table" and next(plates) and plates.barGeometry == nil then
        local mapko = plates.look == 4
        if plates.look == 3 then
            mapko = true
            -- A key the export lacks is a setting added after it was made.
            for key, value in pairs(NS.SuiteCatalog.nameplates.look.presets[4]) do
                if key ~= "barGeometry" and key ~= "levelAppearance" and plates[key] ~= nil and plates[key] ~= value then
                    mapko = false
                    break
                end
            end
        end
        plates.barGeometry = mapko and 2 or 1
    end
end
-- Stable order: the first seven entries were already stored as preview choices.
Style.Roles = {
    { key = "Melee", label = "Melee", sample = "Mire Laborer", color = "be301d" },
    { key = "Caster", label = "Caster", sample = "Dungeoneer's Trainee", color = "00bfff" },
    { key = "Miniboss", label = "Rare / lieutenant", sample = "Rare Enemy", color = "9370db" },
    { key = "Boss", label = "Boss", sample = "Boss Enemy", color = "ff00ff" },
    { key = "Quest", label = "Quest", sample = "Quest Enemy", color = "ff7e00" },
    { key = "Tapped", label = "Tapped", sample = "Tapped Enemy", color = "6e6e6e" },
    { key = "Focus", label = "Focus", sample = "Focused Enemy", color = "ff00ff" },
    { key = "Neutral", label = "Neutral", sample = "Neutral Enemy", color = "e5db00" },
    { key = "Trivial", label = "Trivial", sample = "Minor Enemy", color = "be301d" },
    { key = "ThreatLost", label = "Threat lost / taking aggro", sample = "Loose Enemy", color = "dd6f00" },
    { key = "ThreatWarning", label = "Threat warning", sample = "Unstable Aggro", color = "ffe93a" },
    { key = "TankMode", label = "Tank safe", sample = "Tank Enemy", color = "26d9ff" },
    { key = "OtherTank", label = "Held by another tank", sample = "Offtank Enemy", color = "3fc77a" },
}
Style.RoleLabels = {}
for index, role in ipairs(Style.Roles) do Style.RoleLabels[index] = role.label end
Style.Outline = { "OUTLINE", "THICKOUTLINE", "", "OUTLINE,SLUG", "THICKOUTLINE,SLUG", "MONOCHROME,OUTLINE" }
Style.OutlineLabels = { "Outline", "Thick outline", "None", "Outline + SLUG", "Thick outline + SLUG", "Monochrome outline", "Follow MSUF" }
for _, option in ipairs({
    { "Monochrome", "MONOCHROME" }, { "Monochrome thick outline", "THICKOUTLINE,MONOCHROME" },
    { "SLUG", "SLUG" }, { "Monochrome + SLUG", "MONOCHROME,SLUG" },
    { "Monochrome outline + SLUG", "OUTLINE,MONOCHROME,SLUG" },
    { "Monochrome thick outline + SLUG", "THICKOUTLINE,MONOCHROME,SLUG" },
}) do
    local index = #Style.OutlineLabels + 1
    Style.OutlineLabels[index], Style.Outline[index] = option[1], option[2]
end
Style.AnchorLabels, Style.Anchors = { "Default" }, {}
for index, point in ipairs(NS.AnchorPoints) do
    Style.AnchorLabels[index + 1], Style.Anchors[index + 1] = NS.AnchorLabels[index], point
end
Style.TargetAtlases = {
    { "common-icon-forwardarrow", true },
    { "CovenantSanctum-Renown-Arrow", false },
    { "CovenantSanctum-Renown-DoubleArrow", false },
    { "CovenantSanctum-Renown-DoubleArrow-Hover", false },
    { "gearupdate-arrow-bullet-point", true },
    { "shop-header-arrow-hover", false },
    { "wowlabs-spectatecycling-arrowright", true },
    { "pvptalents-selectedarrow", true },
}
Style.TargetLabels = { "MSUF double arrow", "Forward arrow", "Renown arrow", "Renown double arrow",
    "Renown double arrow glow", "Bullet arrow", "Shop arrow", "Spectate arrow", "MSUF border",
    "MSUF arrow", "MSUF triple arrow", "MSUF diamond", "MSUF cross", "MSUF border + arrow", "PvP talent arrow" }
local TARGET_SHAPES = { [1] = "DOUBLE_ARROW", [9] = "BORDER", [10] = "ARROW", [11] = "TRIPLE_ARROW",
    [12] = "DIAMOND", [13] = "CROSS", [14] = "BORDER_ARROW" }
Style.TargetDirections = { "RIGHT", "LEFT", "UP", "DOWN" }
Style.TargetLayouts = { "SINGLE", "BOTH_IN", "BOTH_OUT" }

function Style.TargetConfig(config, barSettings, side)
    local size = config.enemyTargetMarkerSize or 16
    local r, g, b = NS.RGB(config.enemyTargetColor or "ffffff")
    local layout = Style.TargetLayouts[config.enemyTargetLayout or 2]
    local anchor = NS.AnchorPoints[config.enemyTargetAnchor or 4] or "LEFT"
    -- Keep saved pair spacing as the base for the two independent offsets.
    local x = (config.enemyTargetOffsetX or 0) - ((layout ~= "SINGLE" or anchor == "LEFT") and size + 3 or 0)
    local y = config.enemyTargetOffsetY or 0
    return {
        bossTarget = true, bossTargetStyle = TARGET_SHAPES[config.enemyTargetStyle or 1] or "ARROW",
        bossTargetSize = size, bossTargetLayout = layout, bossTargetAnchor = anchor,
        bossTargetDirection = Style.TargetDirections[config.enemyTargetDirection or 1],
        bossTargetX = x, bossTargetY = y,
        primaryX = x + (config.enemyTargetPrimaryOffsetX or 0), primaryY = y + (config.enemyTargetPrimaryOffsetY or 0),
        mirrorX = -x + (config.enemyTargetMirrorOffsetX or 0), mirrorY = y + (config.enemyTargetMirrorOffsetY or 0),
        bossTargetR = r, bossTargetG = g, bossTargetB = b,
        -- Append new choices without renumbering saved MSUF shape choices 9-14.
        atlas = not TARGET_SHAPES[config.enemyTargetStyle or 1]
            and Style.TargetAtlases[config.enemyTargetStyle == 15 and 8 or (config.enemyTargetStyle or 1) - 1] or nil,
        color = config.enemyTargetColor or "ffffff",
        hideBorder = Style.OutlineOff(barSettings or config, side or "enemy"),
    }
end

local TARGET_ANGLES = { RIGHT = 0, LEFT = math.pi, UP = math.pi / 2, DOWN = -math.pi / 2 }
-- The EQoL atlas choices use the same MSUF size, anchor, direction and
-- mirrored layout. Their textures replace only the renderer's lines.
local function TargetAtlas(frame, direction, cfg)
    if not frame then return end
    if cfg.atlas then
        if not frame._suiteAtlas then
            frame._suiteAtlas = frame:CreateTexture(nil, "OVERLAY")
            frame._suiteAtlas:SetAllPoints(frame)
        end
        frame._suiteAtlas:SetAtlas(cfg.atlas[1])
        local angle = TARGET_ANGLES[direction] or 0
        frame._suiteAtlas:SetRotation(angle + (cfg.atlas[2] and 0 or math.pi))
        frame._suiteAtlas:SetVertexColor(cfg.bossTargetR, cfg.bossTargetG, cfg.bossTargetB)
        frame._suiteAtlas:Show()
        for _, line in ipairs(frame.lines) do line:Hide() end
    elseif frame._suiteAtlas then
        frame._suiteAtlas:Hide()
    end
end

local function TargetLevelGaps(marker, cfg, rightGap, leftGap, reanchored)
    if not marker then return end
    local paired = cfg.bossTargetLayout ~= "SINGLE"
    local anchor = cfg.bossTargetAnchor or "LEFT"
    local primary = 0
    if paired or anchor:find("LEFT", 1, true) then primary = -(leftGap or 0)
    elseif anchor:find("RIGHT", 1, true) then primary = rightGap or 0 end
    local scale = marker._scale or 1
    local x = (cfg.primaryX - (marker._leftExtent or 0)) * scale + primary
    local y = cfg.primaryY * scale
    if reanchored or marker._suiteTargetX ~= x or marker._suiteTargetY ~= y then
        marker:SetPointsOffset(x, y)
        marker._suiteTargetX, marker._suiteTargetY = x, y
    end
    local mirror = marker.mirror
    if mirror and paired then
        local mx = (cfg.mirrorX + (marker._rightExtent or 0)) * scale + (rightGap or 0)
        local my = cfg.mirrorY * scale
        if reanchored or mirror._suiteTargetX ~= mx or mirror._suiteTargetY ~= my then
            mirror:SetPointsOffset(mx, my)
            mirror._suiteTargetX, mirror._suiteTargetY = mx, my
        end
    end
end

-- Use the same renderer as MSUF's boss frame. Only our own host receives its
-- fields; no Blizzard frame state or MSUF profile is modified.
function Style.PaintTarget(visual, owner, visible, cfg, parent, rightLevelGap, leftLevelGap)
    if not visible then
        if visual.targetHost then visual.targetHost:Hide() end
        return
    end
    -- MSUF's boss target renderer; Platform.lua asserts the MSUF namespace.
    local indicator = NS.HostBridge.BossTargetIndicator()
    if not indicator then return end
    local host = visual.targetHost
    if not host then
        host = CreateFrame("Frame", nil, parent or owner)
        host:SetAllPoints(owner)
        host:EnableMouse(false)
        visual.targetHost, visual.targetBorder = host, Style.CreateBorder(host)
    end
    host:Show()
    if visual.targetConfig == cfg then
        local marker = indicator.HasMarker(cfg) and host._msufBossTargetIndicator or nil
        TargetLevelGaps(marker, cfg, rightLevelGap, leftLevelGap)
        return marker
    end
    local previous = visual.targetConfig
    visual.targetConfig = cfg
    if previous and previous.atlas ~= cfg.atlas and host._msufBossTargetIndicator then
        -- Invalidate only our owned marker when entering/leaving an atlas.
        host._msufBossTargetIndicator._style = nil
    end
    Style.PaintBorder(visual.targetBorder, host, not cfg.hideBorder and indicator.HasBorder(cfg) and 1 or 0, cfg.color)
    local marker = indicator.Apply(host, cfg, 1)
    if not marker then return end
    marker:Show()
    local paired = cfg.bossTargetLayout ~= "SINGLE"
    local direction = paired and (cfg.bossTargetLayout == "BOTH_OUT" and "LEFT" or "RIGHT") or cfg.bossTargetDirection
    TargetAtlas(marker, direction, cfg)
    TargetAtlas(marker.mirror, direction == "RIGHT" and "LEFT" or "RIGHT", cfg)
    -- Camelot's native level badge sits on the right. The base client can
    -- place its player level indicator on the left.
    TargetLevelGaps(marker, cfg, rightLevelGap, leftLevelGap, true)
    return marker
end
Style.Markers = {
    elite = { anchor = "LEFT", atlas = "UI-HUD-UnitFrame-Target-PortraitOn-Boss-Rare-Star" },
    quest = { anchor = "CENTER", atlas = "QuestNormal" },
}

-- Core media helpers are available before any optional module is loaded.
Style.ResolveFont = NS.ResolveFont

function Style.Font(key)
    if key == "" and type(_G.MSUF_GetFontPath) == "function" then
        local path = _G.MSUF_GetFontPath()
        if NS.Public(path) and type(path) == "string" then return path end
    end
    return Style.ResolveFont(key)
end

function Style.FontFlags(choice)
    if choice == 7 and type(_G.MSUF_GetFontFlags) == "function" then
        local flags = _G.MSUF_GetFontFlags()
        if NS.Public(flags) and type(flags) == "string" then return flags end
    end
    return Style.Outline[choice or 1] or "OUTLINE"
end

-- The mouseover highlight: an additive wash over the whole health bar, above
-- the role tint and below the native text.
local HIGHLIGHT_ALPHA = 0.25
function Style.CreateHighlight(owner)
    local texture = owner:CreateTexture(nil, "ARTWORK", nil, 7)
    texture:SetAllPoints(owner)
    texture:SetBlendMode("ADD")
    texture:Hide()
    return texture
end

function Style.PaintHighlight(texture, hex)
    local r, g, b = NS.RGB(hex)
    texture:SetColorTexture(r, g, b, HIGHLIGHT_ALPHA)
end

function Style.CreateBorder(owner)
    local visual = { edges = {}, borderShown = false }
    for i = 1, 4 do
        local edge = owner:CreateTexture(nil, "OVERLAY", nil, 7)
        edge:Hide()
        visual.edges[i] = edge
    end
    return visual
end

function Style.PaintBorder(visual, owner, size, color)
    local edges = visual.edges
    local slanted = visual.paintSlantedRim and visual.paintSlantedRim(visual, size, color)
    if size <= 0 or slanted then
        if visual.borderShown then
            for i = 1, 4 do edges[i]:Hide() end
            visual.borderShown = false
        end
        visual.borderSize = slanted and size or 0
        return
    end
    if visual.borderColor ~= color then
        local r, g, b = NS.RGB(color)
        for i = 1, 4 do edges[i]:SetColorTexture(r, g, b, 1) end
        visual.borderColor = color
    end
    if visual.borderGeometrySize ~= size then
        for i = 1, 4 do edges[i]:ClearAllPoints() end
        edges[1]:SetPoint("TOPLEFT", owner, "TOPLEFT", -size, size)
        edges[1]:SetPoint("TOPRIGHT", owner, "TOPRIGHT", size, size)
        edges[1]:SetHeight(size)
        edges[2]:SetPoint("BOTTOMLEFT", owner, "BOTTOMLEFT", -size, -size)
        edges[2]:SetPoint("BOTTOMRIGHT", owner, "BOTTOMRIGHT", size, -size)
        edges[2]:SetHeight(size)
        edges[3]:SetPoint("TOPLEFT", owner, "TOPLEFT", -size, 0)
        edges[3]:SetPoint("BOTTOMLEFT", owner, "BOTTOMLEFT", -size, 0)
        edges[3]:SetWidth(size)
        edges[4]:SetPoint("TOPRIGHT", owner, "TOPRIGHT", size, 0)
        edges[4]:SetPoint("BOTTOMRIGHT", owner, "BOTTOMRIGHT", size, 0)
        edges[4]:SetWidth(size)
        visual.borderGeometrySize = size
    end
    if not visual.borderShown then
        for i = 1, 4 do edges[i]:Show() end
        visual.borderShown = true
    end
    visual.borderSize = size
end

function Style.PaintCastOutline(visual, owner, size, style)
    Style.PaintBorder(visual, owner, size, "ffffff")
    if size <= 0 then return end
    local r, g, b, a = style.outlineR or 0, style.outlineG or 0, style.outlineB or 0, style.outlineA or 1
    if visual.r == r and visual.g == g and visual.b == b and visual.a == a then return end
    for _, edge in ipairs(visual.edges) do edge:SetVertexColor(r, g, b, a) end
    visual.r, visual.g, visual.b, visual.a = r, g, b, a
end

local BLIZZARD_OUTLINE, CUSTOM_OUTLINE, NO_OUTLINE = 2, 3, 4

function Style.OutlineOff(config, side)
    return config.hideHealthBarBorders == true or config[side .. "OutlineMode"] == NO_OUTLINE
end

function Style.CustomOutlineEnabled(config, side)
    return Style.OutlineSize(config[side .. "OutlineMode"], config[side .. "BorderEnabled"],
        config[side .. "BorderSize"], config.hideHealthBarBorders) > 0
end

function Style.OutlineSize(mode, enabled, size, hide)
    if hide or mode == BLIZZARD_OUTLINE or mode == NO_OUTLINE or mode ~= CUSTOM_OUTLINE and enabled == false then
        return 0
    end
    if mode == CUSTOM_OUTLINE then return math.max(1, size or 1) end
    return size or 0
end

function Style.HideNativeOutline(config, side)
    local mode = config[side .. "OutlineMode"]
    if mode and mode ~= 1 then return mode ~= BLIZZARD_OUTLINE end
    return NS.Client.isForever and config[side .. "NativeBorderEnabled"] == false
end

function Style.UsesNativeOutline(config, side)
    return config[side .. "OutlineMode"] == BLIZZARD_OUTLINE and not config.hideHealthBarBorders
end

function Style.SharedBars()
    local bridge = NS.HostBridge
    if bridge and bridge.SharedNameplateBars then return bridge.SharedNameplateBars() end
end

function Style.BarSettings(config, shared)
    if config.barsOverride or not shared then return config end
    if config.highlightAggroOverride then shared.highlightAggroColor = nil end
    return setmetatable(shared, { __index = config })
end

local HIGHLIGHT_KEYS = { "target", "focus", "aggro", "mouseover" }

function Style.HighlightOrder(order)
    local result, seen = {}, {}
    for digit in (order or ""):gmatch("[1-4]") do
        local key = HIGHLIGHT_KEYS[tonumber(digit)]
        if not seen[key] then result[#result + 1], seen[key] = key, true end
    end
    for _, key in ipairs(HIGHLIGHT_KEYS) do
        if not seen[key] then result[#result + 1] = key end
    end
    return result
end

function Style.AggroHighlightEnabled(config)
    local bridge = NS.HostBridge
    local read = bridge and bridge.SharedAggroBorderEnabled
    if config.highlightAggroOverride ~= true and read then
        local enabled = read()
        if type(enabled) == "boolean" then return enabled end
    end
    return config.highlightAggro == true
end

function Style.CompileHighlights(config, sample)
    local target = (config.highlightTarget or sample == "target") and (config.selectionTargetColor or "ffffff")
    local focus = (config.highlightFocus or sample == "focus") and (config.selectionFocusColor or "ff66ff")
    local aggro = (sample == "aggro" or Style.AggroHighlightEnabled(config)) and (config.highlightAggroColor or "ff5252")
    local mouseover = (config.highlightMouseover or sample == "mouseover") and (config.highlightMouseoverColor or "ffffff")
    if target or focus or aggro or mouseover then
        return { target = target, focus = focus, aggro = aggro, mouseover = mouseover,
            size = config.highlightBorderSize or 2,
            order = config.highlightPriority and Style.HighlightOrder(config.highlightOrder) or nil }
    end
end

function Style.HighlightColor(plan, target, focus, aggro, mouseover)
    if plan.order then
        for _, key in ipairs(plan.order) do
            local color = plan[key]
            if color and (key == "target" and target or key == "focus" and focus
                or key == "aggro" and aggro or key == "mouseover" and mouseover) then
                return color, not not (target and plan.target or focus and plan.focus)
            end
        end
        return
    end
    if target and plan.target then return plan.target, true end
    if focus and plan.focus then return plan.focus, true end
    if aggro and plan.aggro then return plan.aggro end
    if mouseover then return plan.mouseover end
end

function Style.PlaceMarker(region, owner, kind, x, y, anchor)
    region:ClearAllPoints()
    region:SetPoint("CENTER", owner, Style.Anchors[anchor or 1] or Style.Markers[kind].anchor, x, y)
end

function Style.PaintMarker(texture, kind, size, color, variant)
    local atlas = variant == "boss" and "worldquest-icon-boss" or Style.Markers[kind].atlas
    if kind == "elite" then color = variant == "elite" and "ffd45e" or "ffffff" end
    if kind == "quest" then color = "ffffff" end
    if texture._msufMarkerAtlas ~= atlas then
        texture:SetAtlas(atlas)
        texture._msufMarkerAtlas = atlas
    end
    if texture._msufMarkerSize ~= size then
        texture:SetSize(size, size)
        texture._msufMarkerSize = size
    end
    if texture._msufMarkerColor ~= color then
        local r, g, b = NS.RGB(color)
        texture:SetVertexColor(r, g, b)
        texture._msufMarkerColor = color
    end
end

-- Optional decoration. Geometry follows native anchors; health never enters Lua.
local Decor = {}
Style.Decor = Decor
local DECOR_MEDIA = "Interface\\AddOns\\MSUF_Suite\\Media\\Nameplates\\"
-- Opacity of the static effects: each has a firm inner and a faint outer ring.
local SHADOW_ALPHA, SHADOW_SOFT_ALPHA, GLOW_ALPHA, GLOW_SOFT_ALPHA = 0.35, 0.12, 0.25, 0.1
local THRESHOLD_WIDTH = 1

local function Joined(c, prefix)
    if NS.Client.isForever and c.barGeometry ~= 2 then return false end
    for _, suffix in ipairs({ "HealthWidthDelta", "HealthOffsetX", "HealthOffsetY",
        "CastOffsetX", "CastOffsetY", "CastIconOffsetX", "CastIconOffsetY" }) do
        if (c[prefix .. suffix] or 0) ~= 0 then return false end
    end
    return true
end

function Decor.Plan(c, prefix)
    local enabled = c.look ~= 2 and c[prefix] ~= false
    local framed = enabled and not Style.OutlineOff(c, prefix)
    local borderSize = Style.OutlineSize(c[prefix .. "OutlineMode"], c[prefix .. "BorderEnabled"],
        c[prefix .. "BorderSize"], not framed)
    local p = {
        joined = Joined(c, prefix),
        border = borderSize > 0 and c[prefix .. "BorderStyle"] == 2,
        borderSize = borderSize, borderColor = c[prefix .. "BorderColor"] or "000000",
        shadow = framed and c[prefix .. "ShadowEnabled"] == true,
        glow = framed and c[prefix .. "GlowEnabled"] and ((c[prefix .. "GlowMode"] or 1) + 1) or 1,
        glowColor = c[prefix .. "GlowColor"] or "ffffff", effectSize = c[prefix .. "EffectSize"] or 4,
        outer = framed and c[prefix .. "OuterFrame"] == true,
        outerSize = c[prefix .. "OuterFrameSize"] or 1, outerColor = c[prefix .. "OuterFrameColor"] or "000000",
        threshold = enabled and prefix == "enemy" and c.enemyThresholdEnabled == true,
        percent = (c.enemyThresholdPercent or 20) / 100, thresholdColor = c.enemyThresholdColor or "ffffff",
        thresholdWidth = c.enemyThresholdWidth or THRESHOLD_WIDTH,
        focus = enabled and prefix == "enemy" and c.enemyFocusMarker == true,
        focusSize = c.enemyFocusMarkerSize or 12, focusColor = c.enemyFocusMarkerColor or "ff66ff",
        focusX = c.enemyFocusMarkerX or -56, focusY = c.enemyFocusMarkerY or 0,
    }
    p.active = p.border or p.shadow or p.glow ~= 1 or p.outer or p.threshold or p.focus
    return p
end

function Decor.TargetScale(c, fallback)
    return c.targetScaleEnabled and (c.targetScalePercent or 120) / 100 or fallback or 1
end

local function Shown(region, on)
    if region._npDecorShown == on or NS.Safety.IsForbidden(region) then return end
    region._npDecorShown = on
    region:SetShown(on)
end

local function Ring(state, key, owner)
    local ring = state[key]
    if ring then return ring end
    local host = CreateFrame("Frame", nil, state.health)
    ring = { host = host, border = Style.CreateBorder(host) }
    state[key] = ring
    return ring
end

local function AnchorRing(ring, first, last, inset)
    local host = ring.host
    if ring.first == first and ring.last == last and ring.inset == inset then return end
    host:ClearAllPoints()
    host:SetPoint("TOPLEFT", first, "TOPLEFT", -inset, inset)
    host:SetPoint("BOTTOMRIGHT", last, "BOTTOMRIGHT", inset, -inset)
    ring.first, ring.last, ring.inset = first, last, inset
end

local function PaintRing(state, key, first, last, inset, size, color, alpha, on)
    local ring = state[key]
    if not on and not ring then return end
    ring = ring or Ring(state, key)
    if on or ring.first == nil then
        AnchorRing(ring, first, last, inset)
        if ring.size ~= size or ring.color ~= color then
            Style.PaintBorder(ring.border, ring.host, size, color)
            ring.size, ring.color = size, color
        end
        if ring.alpha ~= alpha then
            ring.host:SetAlpha(alpha)
            ring.alpha = alpha
        end
    end
    Shown(ring.host, on)
end

local function Effects(state, p, last, target, focus, visible)
    local glow = p.glow == 2 or p.glow == 3 and target or p.glow == 4 and focus
    local size = p.effectSize
    if p.shadow then
        Ring(state, "shadow")
        Ring(state, "shadowSoft")
    end
    if p.outer then Ring(state, "outer") end
    if p.border then Ring(state, "double") end
    if p.glow ~= 1 then
        Ring(state, "glow")
        Ring(state, "glowSoft")
    end
    PaintRing(state, "shadow", state.health, last, size, 2, "000000", SHADOW_ALPHA, p.shadow and visible)
    PaintRing(state, "shadowSoft", state.health, last, size + 2, 2, "000000", SHADOW_SOFT_ALPHA, p.shadow and visible)
    PaintRing(state, "glow", state.health, last, 1, size, p.glowColor, GLOW_ALPHA, glow and visible)
    PaintRing(state, "glowSoft", state.health, last, size + 1, 2, p.glowColor, GLOW_SOFT_ALPHA, glow and visible)
    PaintRing(state, "double", state.health, state.health, p.borderSize + 2, 1,
        p.borderColor, 1, p.border and p.borderSize > 0 and visible)
    PaintRing(state, "outer", state.health, last, 1, p.outerSize, p.outerColor, 1, p.outer and visible)
end

local function Threshold(state, p)
    local line = state.threshold
    if not p.threshold then
        if line then Shown(line, false) end
        return
    end
    if not line then
        local host = CreateFrame("Frame", nil, state.health)
        host:SetPoint("TOPLEFT", state.health, "TOPLEFT", 0, 0)
        host:SetPoint("BOTTOMRIGHT", state.health, "BOTTOMRIGHT", 0, 0)
        local marker = CreateFrame("StatusBar", nil, host)
        marker:SetAllPoints(host)
        marker:SetMinMaxValues(0, 1)
        marker:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
        marker:SetAlpha(0)
        line = host:CreateTexture(nil, "OVERLAY")
        line:SetPoint("TOP", marker:GetStatusBarTexture(), "TOPRIGHT", 0, 0)
        line:SetPoint("BOTTOM", marker:GetStatusBarTexture(), "BOTTOMRIGHT", 0, 0)
        state.threshold, state.thresholdBar = line, marker
    end
    if state.thresholdWidth ~= p.thresholdWidth then
        line:SetWidth(p.thresholdWidth)
        state.thresholdWidth = p.thresholdWidth
    end
    if state.percent ~= p.percent then
        state.thresholdBar:SetValue(p.percent)
        state.percent = p.percent
    end
    if state.thresholdColor ~= p.thresholdColor then
        line:SetColorTexture(NS.RGB(p.thresholdColor))
        state.thresholdColor = p.thresholdColor
    end
    Shown(line, true)
end

local function FocusMarker(state, p, focus)
    local marker = state.focusMarker
    if not p.focus then
        if marker then Shown(marker, false) end
        return
    end
    if not marker then
        marker = state.health:CreateTexture(nil, "OVERLAY", nil, 7)
        marker:SetTexture(DECOR_MEDIA .. "Focus.tga")

        state.focusMarker = marker
    end
    if state.focusX ~= p.focusX or state.focusY ~= p.focusY then
        marker:ClearAllPoints()
        marker:SetPoint("CENTER", state.health, "LEFT", p.focusX, p.focusY)
        state.focusX, state.focusY = p.focusX, p.focusY
    end
    if state.focusSize ~= p.focusSize then
        marker:SetSize(p.focusSize, p.focusSize)
        state.focusSize = p.focusSize
    end
    if state.focusColor ~= p.focusColor then
        marker:SetVertexColor(NS.RGB(p.focusColor))
        state.focusColor = p.focusColor
    end
    Shown(marker, focus)
end

function Decor.Paint(state, p, target, focus, castShown)
    if not state.single then
        state.single = { parent = state.parent, health = state.health }
        state.combined = { parent = state.parent, health = state.health }
    end
    local joined = p.joined and not state.separate and not Style.ClassicNativePlate()
    local combined = p.outer and joined and castShown and state.cast ~= nil
    Effects(state.single, p, state.health, target, focus, not combined)
    if p.outer and joined and state.cast then
        Effects(state.combined, p, state.cast, target, focus, combined)
    else
        Decor.Hide(state.combined)
    end
    if p.outer and not joined and state.cast then
        if not state.castOnly then state.castOnly = { parent = state.parent, health = state.cast } end
        Effects(state.castOnly, p, state.cast, target, focus, castShown)
    else
        Decor.Hide(state.castOnly)
    end
    Threshold(state, p)
    FocusMarker(state, p, focus)
end

local RINGS = { "shadow", "shadowSoft", "glow", "glowSoft", "double", "outer" }
function Decor.Hide(state)
    if not state then return end
    if state.single then Decor.Hide(state.single) end
    if state.combined then Decor.Hide(state.combined) end
    if state.castOnly then Decor.Hide(state.castOnly) end
    for i = 1, #RINGS do
        local ring = state[RINGS[i]]
        if ring then Shown(ring.host, false) end
    end
    if state.threshold then Shown(state.threshold, false) end
    if state.focusMarker then Shown(state.focusMarker, false) end
end

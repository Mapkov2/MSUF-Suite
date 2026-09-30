local _, NS = ...
-- Presentation shared by the native skin and its options preview. Loading
-- this file creates no frames, hooks, timers or event listeners.
local Style = {}
NS.NameplateStyle = Style
-- Blizzard's array CVars store six bits per data byte after a version byte.
-- Keep one decoder for the runtime and preview; callers choose their flags.
function Style.CVarFlags(value)
    if not NS.Public(value) or type(value) ~= "string" or #value == 0 then return nil end
    local byte = value:byte(2) or 64
    if byte < 64 or byte > 127 then return nil end
    return byte - 64
end
function Style.NativeBit(cvar, index, fallback)
    local api = _G.C_CVar
    local value = api and type(api.GetCVar) == "function" and api.GetCVar(cvar)
    local flags = Style.CVarFlags(value)
    if flags == nil then return fallback end
    return math.floor(flags / 2 ^ (index - 1)) % 2 == 1
end
function Style.NativeToggle(cvar, fallback)
    local api = _G.C_CVar
    local value = api and type(api.GetCVar) == "function" and api.GetCVar(cvar)
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
Style.AuraGroups = {
    { key = "enemyNpc", label = "Enemy NPC", control = "Crowd control",
      cvar = "nameplateEnemyNpcAuraDisplay" },
    { key = "enemyPlayer", label = "Enemy player", control = "Loss of control",
      cvar = "nameplateEnemyPlayerAuraDisplay" },
    { key = "friendlyPlayer", label = "Friendly player", control = "Loss of control",
      cvar = "nameplateFriendlyPlayerAuraDisplay" },
}
Style.AuraCVar = {}
for _, group in ipairs(Style.AuraGroups) do Style.AuraCVar[group.key] = group.cvar end
Style.AuraBits = { Buffs = 1, Debuffs = 2, Control = 3 }

-- The active Blizzard setup is authoritative for the preview. A profile
-- choice can be ahead of the CVar update that has reached visible plates.
function Style.NativeStyleValue(choice)
    local api = _G.C_CVar
    local value = api and type(api.GetCVar) == "function" and api.GetCVar("nameplateStyle")
    if NS.Public(value) then
        local number = tonumber(value)
        if number and number >= 0 and number <= 6 then return number end
    end
    if type(choice) == "number" and choice >= 2 and choice <= 8 then return choice - 2 end
    return 0
end

function Style.ClassicNativePlate(choice)
    local setup = _G.NamePlateSetupOptions
    local classic = setup and setup.useClassicHealthBar
    if NS.Public(classic) and type(classic) == "boolean" then return classic end
    return Style.NativeStyleValue(choice) == 6
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
function Style.RepairGeometry(modules)
    local plates = modules.nameplates
    -- Recognize the supplied pre-geometry Mapko export too, so importing that
    -- original string on Forever gets the same dimensions. Other old profiles
    -- keep their native bases; current exports explicitly carry the choice.
    if type(plates) == "table" and next(plates) and plates.barGeometry == nil then
        local mapko = plates.look == 4
        if plates.look == 3 then
            mapko = true
            for key, value in pairs(NS.SuiteCatalog.nameplates.look.presets[4]) do
                if key ~= "barGeometry" and key ~= "levelAppearance" and plates[key] ~= value then
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

function Style.TargetConfig(config)
    local size = config.enemyTargetMarkerSize or 16
    local r, g, b = NS.RGB(config.enemyTargetColor or "ffffff")
    local layout = Style.TargetLayouts[config.enemyTargetLayout or 2]
    local anchor = NS.AnchorPoints[config.enemyTargetAnchor or 4] or "LEFT"
    return {
        bossTarget = true, bossTargetStyle = TARGET_SHAPES[config.enemyTargetStyle or 1] or "ARROW",
        bossTargetSize = size, bossTargetLayout = layout, bossTargetAnchor = anchor,
        bossTargetDirection = Style.TargetDirections[config.enemyTargetDirection or 1],
        -- Preserve the existing nameplate X offset: zero puts the marker just outside the bar.
        bossTargetX = (config.enemyTargetOffsetX or 0) - ((layout ~= "SINGLE" or anchor == "LEFT") and size + 3 or 0),
        bossTargetY = config.enemyTargetOffsetY or 0,
        bossTargetR = r, bossTargetG = g, bossTargetB = b,
        -- Append new choices without renumbering saved MSUF shape choices 9-14.
        atlas = not TARGET_SHAPES[config.enemyTargetStyle or 1]
            and Style.TargetAtlases[config.enemyTargetStyle == 15 and 8 or (config.enemyTargetStyle or 1) - 1] or nil,
        color = config.enemyTargetColor or "ffffff",
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
    local y = (cfg.bossTargetY or 0) * scale
    local x = ((cfg.bossTargetX or -28) - (marker._leftExtent or 0)) * scale + primary
    if reanchored or marker._suiteTargetX ~= x or marker._suiteTargetY ~= y then
        marker:SetPointsOffset(x, y)
        marker._suiteTargetX, marker._suiteTargetY = x, y
    end
    local mirror = marker.mirror
    if mirror and paired then
        local mx = (-(cfg.bossTargetX or -28) + (marker._rightExtent or 0)) * scale + (rightGap or 0)
        if reanchored or mirror._suiteTargetX ~= mx or mirror._suiteTargetY ~= y then
            mirror:SetPointsOffset(mx, y)
            mirror._suiteTargetX, mirror._suiteTargetY = mx, y
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
    local indicator = _G.MSUF_NS and _G.MSUF_NS.BossTargetIndicator
    if not indicator or not indicator.Apply then return end
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
    Style.PaintBorder(visual.targetBorder, host, indicator.HasBorder(cfg) and 1 or 0, cfg.color)
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

function Style.CreateBorder(owner)
    local visual = { edges = {} }
    for i = 1, 4 do visual.edges[i] = owner:CreateTexture(nil, "OVERLAY", nil, 7) end
    return visual
end

function Style.PaintBorder(visual, owner, size, color)
    local edges = visual.edges
    if size <= 0 then
        for i = 1, 4 do edges[i]:Hide() end
        visual.borderSize = 0
        return
    end
    if visual.borderColor ~= color then
        local r, g, b = NS.RGB(color)
        for i = 1, 4 do edges[i]:SetColorTexture(r, g, b, 1) end
        visual.borderColor = color
    end
    if visual.borderSize ~= size then
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
        visual.borderSize = size
    end
    for i = 1, 4 do edges[i]:Show() end
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

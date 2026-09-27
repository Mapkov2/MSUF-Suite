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
-- Offset keys describe existing Blizzard regions, relative to their native
-- layout. The same descriptors drive the settings and preview handles.
Style.Elements = {
    { key = "Name", label = "Name", section = "enemy" },
    { key = "HealthText", label = "Health text", section = "enemy" },
    { key = "Cast", label = "Castbar", section = "castbar" },
    { key = "CastText", label = "Spell name", section = "castbar" },
    { key = "Auras", label = "Auras", section = "enemy" },
    { key = "RaidIcon", label = "Raid marker", section = "enemy" },
    { key = "Classification", label = "Blizzard elite / rare icon", section = "enemy" },
    { key = "CastIcon", label = "Blizzard spell icon", section = "castbar" },
    { key = "CastShield", label = "Blizzard interrupt shield", section = "castbar" },
    { key = "CastTarget", label = "Spell target", section = "castbar" },
    { key = "Health", label = "Health bar", section = "enemy" },
}
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
Style.TargetLabels = { "MSUF double arrow (Jundies)", "Forward arrow", "Renown arrow", "Renown double arrow",
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

-- Use the same renderer as MSUF's boss frame. Only our own host receives its
-- fields; no Blizzard frame state or MSUF profile is modified.
function Style.PaintTarget(visual, owner, visible, cfg, parent)
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
    if visual.targetConfig == cfg then return indicator.HasMarker(cfg) and host._msufBossTargetIndicator or nil end
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

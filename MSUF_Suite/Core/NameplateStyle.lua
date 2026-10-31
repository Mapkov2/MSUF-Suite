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

-- Explicit dimensions are opt-in. Old profiles keep their portable native
-- bases; the same overrides drive the real cast and its options preview.
function Style.CastDimensions(mode, height, icon, castHeight, iconHeight)
    if mode == 2 then
        if type(height) == "number" and height > 0 then castHeight = height end
        if type(icon) == "number" and icon > 0 then iconHeight = icon end
    end
    return castHeight, iconHeight
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

-- The mouseover highlight: an additive wash over the whole health bar, above
-- the role tint and below the texture finish and the native text.
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

-- Optional decoration. Geometry follows native anchors; health never enters Lua.
local Decor = {}
Style.Decor = Decor
local DECOR_MEDIA = "Interface\\AddOns\\MSUF_Suite\\Media\\Nameplates\\"
local TEXTURES = { DECOR_MEDIA .. "Soft.tga", DECOR_MEDIA .. "Stripes.tga" }
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
    local p = {
        joined = Joined(c, prefix),
        border = enabled and c[prefix .. "BorderEnabled"] ~= false and c[prefix .. "BorderStyle"] == 2,
        borderSize = c[prefix .. "BorderSize"] or 1, borderColor = c[prefix .. "BorderColor"] or "000000",
        shadow = enabled and c[prefix .. "ShadowEnabled"] == true,
        glow = enabled and c[prefix .. "GlowEnabled"] and ((c[prefix .. "GlowMode"] or 1) + 1) or 1,
        glowColor = c[prefix .. "GlowColor"] or "ffffff", effectSize = c[prefix .. "EffectSize"] or 4,
        outer = enabled and c[prefix .. "OuterFrame"] == true,
        outerSize = c[prefix .. "OuterFrameSize"] or 1, outerColor = c[prefix .. "OuterFrameColor"] or "000000",
        texture = enabled and c[prefix .. "TextureEnabled"] and TEXTURES[c[prefix .. "FillTexture"] or 1] or nil,
        threshold = enabled and prefix == "enemy" and c.enemyThresholdEnabled == true,
        percent = (c.enemyThresholdPercent or 20) / 100, thresholdColor = c.enemyThresholdColor or "ffffff",
        thresholdWidth = c.enemyThresholdWidth or THRESHOLD_WIDTH,
        focus = enabled and prefix == "enemy" and c.enemyFocusMarker == true,
        focusSize = c.enemyFocusMarkerSize or 12, focusColor = c.enemyFocusMarkerColor or "ff66ff",
        focusX = c.enemyFocusMarkerX or -56, focusY = c.enemyFocusMarkerY or 0,
    }
    p.active = p.border or p.shadow or p.glow ~= 1 or p.outer or p.texture ~= nil or p.threshold or p.focus
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

local function FillFinish(state, p)
    local texture = state.finish
    if not p.texture then
        if texture then Shown(texture, false) end
        return
    end
    local native = state.fillSource or state.health:GetStatusBarTexture()
    if not native or NS.Safety.IsForbidden(native) then
        if texture then Shown(texture, false) end
        return
    end
    if not texture then
        texture = state.health:CreateTexture(nil, "OVERLAY", nil, 0)
        texture:SetBlendMode("MOD")
        state.finish = texture
    end
    if state.fill ~= native then
        texture:ClearAllPoints()
        texture:SetAllPoints(native)
        state.fill = native
    end
    if state.texture ~= p.texture then
        texture:SetTexture(p.texture)
        state.texture = p.texture
    end
    Shown(texture, true)
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
    FillFinish(state, p)
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
    if state.finish then Shown(state.finish, false) end
    if state.threshold then Shown(state.threshold, false) end
    if state.focusMarker then Shown(state.focusMarker, false) end
end

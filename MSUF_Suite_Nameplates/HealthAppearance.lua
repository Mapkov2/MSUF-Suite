local _, private = ...
local NS, S, Style = private.NS, private.Suite, private.NS.NameplateStyle
local Prefix, Mode, Text, Level = private.PlatePrefix, private.Mode, private.Text, private.Level
local LevelBadgeShown = private.Geometry.LevelBadgeShown
local Key, RoleKey, Textures, Selection = private.Key, private.RoleKey, private.Textures, private.Selection
local Border = Style.PaintBorder
local Safe, M, ShowVisual, outlineSizes

local function Color(texture, hex, alpha)
    local r, g, b = S.RGB(hex)
    texture:SetVertexColor(1, 1, 1, 1)
    texture:SetColorTexture(r, g, b, alpha or 1)
end

local function PaintMarker(texture, health, kind, enabled, size, x, y, color, anchor, variant)
    if not enabled then return ShowVisual(texture, false) end
    Style.PaintMarker(texture, kind, size, color, variant)
    if texture._msufX ~= x or texture._msufY ~= y or texture._msufAnchor ~= anchor then
        Style.PlaceMarker(texture, health, kind, x, y, anchor)
        texture._msufX, texture._msufY, texture._msufAnchor = x, y, anchor
    end
    ShowVisual(texture, true)
end

local function RoleFillColor(health, prefix)
    local c = M.config
    local role = prefix == "enemy" and c.enemyRoleColors and M.roles[health]
    local keys = role and RoleKey[role]
    if not keys or c[keys.enabled] == false then return end
    if role == "Quest" and c.questReactionColors then
        return c[M.facts[health].questNeutral and "questNeutralColor" or "questHostileColor"]
    end
    return c[keys.color]
end

local function PaintFill(uf, health, visual, prefix)
    local hex = RoleFillColor(health, prefix)
    if not hex then return ShowVisual(visual.fill, false) end
    local fillTexture = health:GetStatusBarTexture()
    if not Safe(fillTexture) then return ShowVisual(visual.fill, false) end
    if visual.fillTarget ~= fillTexture then
        visual.fill:ClearAllPoints()
        visual.fill:SetAllPoints(fillTexture)
        visual.fillTarget = fillTexture
    end
    local path = visual.focusFill or Textures.healthFill
    if M.scopedBars then path = Textures.HealthFill(uf) end
    if visual.fillColor ~= hex or visual.fillPath ~= path then Textures.TintRole(visual, hex, path) end
    ShowVisual(visual.fill, true)
end

local function PaintHealth(uf, health, visual, prefix, scope, bars)
    local c, keys = M.config, Key[prefix]
    local backColor = c[keys.BackdropColor]
    local backAlpha = (c[keys.BackdropAlpha] or 100) / 100
    if visual.backColor ~= backColor or visual.backAlpha ~= backAlpha then
        Color(visual.back, backColor, backAlpha)
        visual.backColor, visual.backAlpha = backColor, backAlpha
    end
    local borderSize = outlineSizes[scope]
    local borderColor = bars[keys.BorderColor]
    if not Selection.highlights then Border(visual, health, borderSize, borderColor) end
    local customBackground = (M.scopedBars or Textures.healthBack) and Textures.HealthBackground(prefix, scope)
    ShowVisual(visual.back, not customBackground and c[keys.BackdropEnabled] ~= false and backAlpha > 0)
    PaintFill(uf, health, visual, prefix)
    local facts = M.facts[health]
    local marker, quest = facts and facts.marker, facts and facts.quest
    PaintMarker(visual.elite, health, "elite", c[keys.EliteMarker] and marker,
        c[keys.EliteMarkerSize] or 14, c[keys.EliteOffsetX] or -13,
        c[keys.EliteOffsetY] or 0, c.enemyMinibossColor, c[keys.EliteMarkerAnchor], marker)
    PaintMarker(visual.quest, health, "quest", c[keys.QuestMarker] and quest,
        c[keys.QuestMarkerSize] or 15, c[keys.QuestOffsetX] or 0,
        c[keys.QuestOffsetY] or 17, c.enemyQuestColor, c[keys.QuestMarkerAnchor])
    return borderSize, borderColor
end

-- The arrows keep clear of the level badge or number beside the bar.
local function TargetGaps(uf, unit)
    local prefix = Prefix(uf)
    if prefix and M.config[Key[prefix].LevelEnabled] == false then return 0, 0 end
    local setup = NamePlateSetupOptions
    local badge = not NS.Client.isForever or M.config.levelAppearance == Mode.LEVEL_BADGE
    local classic = badge and S.Public(setup.useClassicHealthBar) and setup.useClassicHealthBar == true
    local width = classic and setup.levelIconWidth
    local rightGap = S.Finite(width) and width + 4 or classic and 19 or 0
    local leftWidth = setup.playerLevelDiffWidth
    local diffBadge = badge and LevelBadgeShown(uf, unit) == true or not badge and Level.NativeBadgeVisible(uf)
    local diffGap = diffBadge
        and (S.Finite(leftWidth) and leftWidth > 0 and leftWidth + (NS.Client.isForever and 5 or 4)
            or (NS.Client.isForever and 33 or 20)) or 0
    if not NS.Client.isForever then return rightGap, diffGap end
    local label = M.levelLabels[uf]
    local number = Safe(label) and label:IsShown()
    local nativeAnchor = not label or label._suiteLevelAnchor == 1
    return math.max(rightGap, diffGap), number and nativeAnchor and (label._suiteLevelWidth or 24) + 4 or 0
end

local function PaintTarget(uf, health, visual, prefix)
    local unit = M.units[health]
    local target = unit and UnitIsUnit(unit, "target")
    local visible = M.config.enemyTargetMarker and (prefix == "enemy" or M.config.enemyTargetHideFriendly == false)
        and S.Public(target) and target == true
    if visible then M.targetUF = uf elseif M.targetUF == uf then M.targetUF = nil end
    local rightGap, leftGap
    if visible then rightGap, leftGap = TargetGaps(uf, unit) end
    local config = prefix == "enemy" and M.targetConfig or M.friendlyTargetConfig
    Style.PaintTarget(visual, health, visible, config, uf, rightGap, leftGap)
end

local function PaintFonts(uf, health, cast, prefix)
    local nameStyle = Text.styles[prefix]
    Text.Apply(uf.name, nameStyle, nameStyle.size)
    Text.ApplyHealth(health, nameStyle, private.HealthNameOnly(uf))
    if cast then Text.ApplyCast(cast, Text.styles[Key[prefix].Cast]) end
end

private.HealthAppearance = { RoleFillColor = RoleFillColor }
function private.HealthAppearance.RestoreFonts(uf, health, cast)
    Text.Restore(uf.name)
    Text.RestoreHealth(health)
    if cast then
        Text.RestoreCast(cast)
        private.CastTime.Restore(cast)
    end
end

function private.HealthAppearance.Bind(module, show, sizes, safe)
    M, ShowVisual, outlineSizes, Safe = module, show, sizes, safe
    return PaintHealth, PaintTarget, PaintFonts
end

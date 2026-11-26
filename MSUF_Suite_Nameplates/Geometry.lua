local _, private = ...
local NS = private.NS
local SAME_GEOMETRY = private.Mode.SAME_GEOMETRY
local Key = private.Key
local Safety, Public, Finite = NS.Safety, NS.Public, NS.Finite
local G = {}
private.Geometry = G

-- Every anchor the Suite writes on a plate snaps to physical pixels
-- (PixelUtil, Blizzard_SharedXMLBase on Retail and Forever).
function G.Point(region, point, owner, relative, x, y)
    PixelUtil.SetPoint(region, point, owner, relative, x, y)
end

local Point = G.Point

local function Accessible(region)
    return region and not Safety.IsForbidden(region)
end

-- Restricted nameplate regions cannot be measured, even outside combat.
-- SetPointsOffset changes their displacement without reading/replacing native
-- anchors. We store only our own offsets, never GetPoint/GetRect results.
local function Offset(state, region, x, y, force)
    local old = state.offsets[region]
    if x == 0 and y == 0 and not old then return end
    if not force and old and old[1] == x and old[2] == y then return end
    if not Accessible(region) then return end
    region:SetPointsOffset(x, y)
    if x == 0 and y == 0 then
        state.offsets[region] = nil
    else
        old = old or {}
        old[1], old[2] = x, y
        state.offsets[region] = old
    end
end

-- A few native regions have anchors to two independently movable elements.
-- Correct only those links; their public base anchors come from upstream/live
-- Blizzard_NamePlateUnitFrame:UpdateAnchors and CastingBar:ApplyStyleAndAnchoring
-- (also present in upstream/forever). No native setup method is invoked.
local function Link(state, region, point, owner, relative, x, y, dx, dy)
    if dx == 0 and dy == 0 or not Accessible(region) or not owner then return end
    state.links[#state.links + 1] = { region, point, owner, relative, x, y }
    Point(region, point, owner, relative, x - dx, y - dy)
end

G.Accessible, G.Offset, G.Link = Accessible, Offset, Link

-- Whether the native level badge (PlayerLevelDiffFrame) holds its space on
-- this plate; nil while that is unknown. On Retail that is its shown state.
-- Forever reserves the space whenever Camelot's
-- NameplateLevelFrameMixin:ShouldDisplay (upstream/forever
-- Blizzard_NamePlates/Camelot) allows the badge, also while it is hidden for
-- a moment. The same rule is evaluated here from the public unit predicates,
-- so no Blizzard method runs in addon code and a restricted answer reads as
-- unknown.
function G.LevelBadgeShown(uf, unit)
    local badge = uf.PlayerLevelDiffFrame
    if not badge then return false end
    if NS.Safety.IsForbidden(badge) then return nil end
    if not NS.Client.isForever then
        local shown = badge:IsShown()
        if NS.Public(shown) then return shown end
        return nil
    end
    if not unit then return false end
    local object = UnitIsGameObject(unit)
    if not NS.Public(object) then return nil end
    if object then return false end
    local friend, player = UnitIsFriend("player", unit), UnitIsPlayer(unit)
    if not NS.Public(friend) or not NS.Public(player) then return nil end
    if friend and player then
        return not C_CVar.GetCVarBool("nameplateShowOnlyNameForFriendlyPlayerUnits")
    end
    return true
end

-- Never measure restricted frames. These bases are public setup values from
-- Blizzard_NamePlateUnitFrame:UpdateAnchors on upstream/live and forever.
function G.LevelReserve(uf, setup)
    if not NS.Client.isForever then return 0 end
    local shown = G.LevelBadgeShown(uf, uf.unit)
    if shown == nil then return nil end
    if not shown then return 0 end
    if NS.Finite(setup.playerLevelDiffWidth) then return setup.playerLevelDiffWidth + 5 end
end

local function Writable(frame)
    if not Accessible(frame) then return false end
    local allowed = frame:CanBeAccessedInContext()
    return Public(allowed) and allowed == true
end

G.Writable = Writable

local spareAuraRows = setmetatable({}, { __mode = "k" })

-- Empty native rows must already carry the configured layout when Blizzard
-- adds its first icon. Reuse the cleared table after a successful restore.
-- A refused restore keeps the original values until the row is writable.
local function ReleaseAuraRow(state, frame, saved)
    saved.scale, saved.alpha, saved.layer, saved.plan = nil, nil, nil, nil
    saved.appliedScale, saved.appliedAlpha, saved.appliedLayer = nil, nil, nil
    state.auraStyles[frame], spareAuraRows[frame] = nil, saved
end

local function ReleaseEmptyAuraList(state)
    if state.auraStyles and not next(state.auraStyles) then
        state.spareAuraStyles, state.auraStyles = state.auraStyles, nil
    end
end

local function HasAuraProperties(saved)
    return saved.scale or saved.alpha or saved.layer
end

function G.RestoreAuraStyles(state)
    local complete = true
    for frame, saved in pairs(state.auraStyles) do
        if not HasAuraProperties(saved) or Writable(frame) then
            if saved.scale then frame:SetScale(saved.scale) end
            if saved.alpha then frame:SetAlpha(saved.alpha) end
            if saved.layer then frame:SetFrameLevel(saved.layer) end
            ReleaseAuraRow(state, frame, saved)
        else
            complete = false
        end
    end
    ReleaseEmptyAuraList(state)
    return complete
end

local function AuraProperty(frame, saved, field, applied, value, get, set, relative)
    local original = saved[field]
    if value == nil then
        if original then set(frame, original) end
        saved[field], saved[applied] = nil, nil
        return true
    end
    if not original then
        original = get(frame)
        if not NS.Finite(original) then return false end
        saved[field] = original
    end
    local result = relative and original + value or original * value
    if saved[applied] ~= result then
        set(frame, result)
        saved[applied] = result
    end
    return true
end

local function StyleAuraRow(state, frame, style)
    if not frame then return true end
    local previous = state.auraStyles and state.auraStyles[frame]
    if not style and not previous or style and previous and previous.plan == style then return true end
    if not style and not HasAuraProperties(previous) then
        ReleaseAuraRow(state, frame, previous)
        return true
    end
    if not Writable(frame) then return false end
    if not previous then
        previous = spareAuraRows[frame] or {}
        if not state.auraStyles then
            state.auraStyles, state.spareAuraStyles = state.spareAuraStyles or {}, nil
        end
        state.auraStyles[frame], spareAuraRows[frame] = previous, nil
    end
    local scale = AuraProperty(frame, previous, "scale", "appliedScale", style and style.scale, frame.GetScale, frame.SetScale)
    local alpha = AuraProperty(frame, previous, "alpha", "appliedAlpha", style and style.alpha, frame.GetAlpha, frame.SetAlpha)
    local layer = AuraProperty(frame, previous, "layer", "appliedLayer", style and style.layer, frame.GetFrameLevel, frame.SetFrameLevel, true)
    local complete = scale and alpha and layer
    if style then previous.plan = complete and style or nil else ReleaseAuraRow(state, frame, previous) end
    return complete
end

function G.ApplyAuraStyles(state, uf, styles)
    if not styles then return not state.auraStyles or G.RestoreAuraStyles(state) end
    local auras = uf.AurasFrame
    if not Writable(auras) then return false end
    local complete = true
    for _, row in ipairs(NS.NameplateAuraDisplay.NativeRows) do
        local style = styles and styles[row.key]
        if not StyleAuraRow(state, auras[row.frame], style) then complete = false end
        if row.playerFrame and not StyleAuraRow(state, auras[row.playerFrame], style) then complete = false end
    end
    ReleaseEmptyAuraList(state)
    return complete
end

local function NameAnchorWritable(label)
    if not Writable(label) then return false end
    local restricted = label:IsAnchoringRestricted()
    return NS.Public(restricted) and restricted == false
end

-- A plate can keep one empty restore record between native bindings. The
-- extents and frame owners themselves always come from the new layout.
local spareNamePoints = setmetatable({}, { __mode = "k" })

local function ForgetNameAnchor(state, uf, saved)
    if saved.native and not saved.restoring then
        saved.owner = nil
        saved.right = nil
        spareNamePoints[uf] = saved
    end
    state.nameAnchor = nil
end

function G.NativeAnchorsReset(state, uf)
    state.header = nil
    if state.nameAnchor then ForgetNameAnchor(state, uf, state.nameAnchor) end
end

function G.RestoreNameAnchor(state, uf)
    local saved = state.nameAnchor
    if not saved then return true end
    local label = uf.name
    local shape = saved.native
    local writable = shape and Writable or NameAnchorWritable
    if not writable(label) then
        return false
    end
    -- A frame hook can rebind this plate during the writes. Its old snapshot
    -- stays readable until the last write, and the new record stays owned.
    local restoring = saved.restoring
    saved.restoring = true
    label:ClearAllPoints()
    if shape then
        label:SetPoint(shape[1], saved.owner, shape[2], shape[3], saved.y)
        if shape[4] then label:SetPoint(shape[4], saved.right, shape[5], shape[6], shape[7]) end
    else
        for _, point in ipairs(saved.points) do label:SetPoint(unpack(point)) end
    end
    label:SetJustifyH(saved.justify)
    saved.restoring = restoring
    if state.nameAnchor == saved then ForgetNameAnchor(state, uf, saved) end
    return true
end

local function SetNameSpan(label, point, owner, relative, x, y, width)
    local edge = point:match("^TOP") or point:match("^BOTTOM") or ""
    local left = x
    if point:match("RIGHT$") then left = x - width
    elseif not point:match("LEFT$") then left = x - width / 2 end
    label:SetPoint(edge .. "LEFT", owner, relative, left, y)
    label:SetPoint(edge .. "RIGHT", owner, relative, left + width, y)
end

function G.ApplyNameAnchor(state, uf, plan, width)
    local anchor, label, owner = plan.nameAnchor, uf.name, uf.HealthBarsContainer.healthBar
    if not anchor or private.HealthNameOnly(uf) or not NameAnchorWritable(label) or not Accessible(owner) then return end
    local points, justify = {}, label:GetJustifyH()
    if not NS.Public(justify) then return end
    local count = label:GetNumPoints()
    if not NS.Finite(count) then return end
    for index = 1, count do
        local point, relative, relativePoint, x, y = label:GetPoint(index)
        if not NS.Public(point) or not NS.Public(relative) or not NS.Public(relativePoint)
            or not NS.Finite(x) or not NS.Finite(y) then return end
        points[index] = { point, relative, relativePoint, x, y }
    end
    state.nameAnchor = { points = points, justify = justify }
    label:ClearAllPoints()
    if width then
        SetNameSpan(label, anchor, owner, anchor, plan.Name[1], plan.Name[2], width)
    else
        Point(label, anchor, owner, anchor, plan.Name[1], plan.Name[2])
    end
    label:SetJustifyH(anchor:find("LEFT", 1, true) and "LEFT" or anchor:find("RIGHT", 1, true) and "RIGHT" or "CENTER")
    return true
end

-- Blizzard's point names, horizontal offsets and the second vertical offset
-- are constant for each anchor style. Only the live owners and first y vary.
local INSIDE_NAME = { "LEFT", "LEFT", 4, "RIGHT", "RIGHT", -4, 0 }
local ABOVE_NAME = { "BOTTOMLEFT", "TOPLEFT", 4, "BOTTOMRIGHT", "TOPRIGHT", -4, 2 }
local INSIDE_BAR = { "LEFT", "LEFT", 4, "RIGHT", "LEFT", -2, 0 }
local CENTER_ABOVE = { "BOTTOM", "TOP", 0 }
local ABOVE_BAR = { "BOTTOMLEFT", "TOPLEFT", 4, "BOTTOMRIGHT", "BOTTOMLEFT", -2, 0 }
local ABOVE_BADGE = { "BOTTOMLEFT", "TOPLEFT", 0, "RIGHT", "RIGHT", 0, 0 }
local ABOVE_TEXT = { "BOTTOMLEFT", "TOPLEFT", 0, "RIGHT", "LEFT", -2, 0 }

local function NamePoints(uf, shape, owner, right, y)
    local saved = spareNamePoints[uf] or {}
    spareNamePoints[uf] = nil
    saved.native = shape
    saved.owner = owner
    saved.right = right
    saved.y = y
    return saved
end

-- The native name points from Blizzard_NamePlateUnitFrame:UpdateAnchors.
-- They can be restored even when FrameMeasurement is blocked for the label.
local function NativeNamePoints(uf, setup, badgeShown)
    local container = uf.HealthBarsContainer
    local health = container and container.healthBar
    local healthText = health and health.Text
    if not Public(healthText) or not healthText or Safety.IsForbidden(healthText) then return end
    local style, spacing = setup.unitNameAnchorStyle, setup.healthBarToNameAboveSpacing
    if uf.showOnlyName then
        if style == 1 then return NamePoints(uf, INSIDE_NAME, container, container, 0) end
        return NamePoints(uf, ABOVE_NAME, container, container, 2)
    end
    if style == 1 then return NamePoints(uf, INSIDE_BAR, container, healthText, 0) end
    if not Finite(spacing) then return end
    if style == 3 then return NamePoints(uf, CENTER_ABOVE, container, nil, spacing) end
    if style ~= 2 then return end
    if not NS.Client.isForever then
        return NamePoints(uf, ABOVE_BAR, container, healthText, spacing)
    end
    local inside = setup.healthTextInsideBarWhenNameAboveHealthBar
    if not Public(inside) or type(inside) ~= "boolean" or badgeShown == nil then return end
    if badgeShown or inside then
        local right = container
        if badgeShown then right = uf.PlayerLevelDiffFrame end
        return NamePoints(uf, ABOVE_BADGE, container, right, spacing)
    end
    return NamePoints(uf, ABOVE_TEXT, container, healthText, spacing)
end

function G.LimitNativeName(uf, setup, badgeShown, plan, width)
    local label, points = uf.name, NativeNamePoints(uf, setup, badgeShown)
    if not points then return end
    local justify = label:GetJustifyH()
    if not Public(justify) or type(justify) ~= "string" then return end
    local healthText = uf.HealthBarsContainer.healthBar.Text
    local shape = points.native
    local point, owner, relative, x, y = shape[1], points.owner, shape[2], shape[3], points.y
    if shape[4] and justify == "RIGHT" and points.right ~= healthText then
        point, owner, relative, x, y = shape[4], points.right, shape[5], shape[6], shape[7]
    end
    if uf.showOnlyName and justify == "CENTER" then
        point, relative, x = setup.unitNameAnchorStyle == 1 and "CENTER" or "BOTTOM",
            setup.unitNameAnchorStyle == 1 and "CENTER" or "TOP", 0
    end
    if not Public(owner) or not Accessible(owner) then return end
    -- Keep a static edge. HP text can change width during the fight.
    label:ClearAllPoints()
    SetNameSpan(label, point, owner, relative, x + plan.Name[1], y + plan.Name[2], width)
    points.centered = nil
    points.justify = justify
    return points
end

function G.CenterEnabled(kind, config)
    local scope = NS.NameplateExtensions.OpacityScope(kind)
    return scope and config[Key[scope].CenterName]
        and not (kind == "friendlyNpc" and config.friendlyNPCs == private.Mode.NPC_NAMES_ONLY)
end

function G.CombatWritable(region)
    if not NS.Public(region) or not region or NS.Safety.IsForbidden(region) then return false end
    local accessible = region:CanBeAccessedInContext()
    if not NS.Public(accessible) or accessible ~= true then return false end
    local protected = region:IsProtected()
    return NS.Public(protected) and protected == false
end

local function CombatPointWritable(region)
    return G.CombatWritable(region) and NS.Finite(region:GetEffectiveScale())
end

local function OptionalCombatWritable(region, point)
    if not NS.Public(region) then return false end
    return not region or G.CombatWritable(region) and (not point or NS.Finite(region:GetEffectiveScale()))
end

-- Cast sizing and placement share a container with the health bar.
-- Preflight every region before applying either half of the layout.
function G.CombatCast(uf)
    if not G.CombatWritable(uf) then return end
    local container = uf.CastBarsContainer
    if not CombatPointWritable(container) or not CombatPointWritable(uf.HealthBarsContainer) then return end
    local cast = container.castBar
    if not CombatPointWritable(cast) or not CombatPointWritable(cast.Icon)
        or not OptionalCombatWritable(cast.Text) or not OptionalCombatWritable(cast.Border)
        or not OptionalCombatWritable(cast.BorderShield) or not OptionalCombatWritable(cast.CastTargetNameText, true) then return end
    return cast
end

function G.CombatControlAuras(uf)
    local auras = uf.AurasFrame
    return NS.Public(auras) and (not auras or OptionalCombatWritable(auras.CrowdControlListFrame, true)
        and OptionalCombatWritable(auras.LossOfControlFrame, true))
end

function G.CenterName(uf, setup, healthHeight, offsetY, badgeShown, geometry, width)
    local label = uf.name
    local spacing, gap = setup.castBarToHealthBarSpacing, setup.healthBarToNameAboveSpacing
    local castHeight = geometry and geometry.castHeight or setup.castBarHeight
    local iconHeight = geometry and geometry.iconHeight or setup.castIconHeight
    local inside = setup.spellNameInsideCastBar
    if not Public(inside) or not Public(setup.unitNameAnchorStyle)
        or not Finite(castHeight) or not inside and not Finite(iconHeight) or not Finite(healthHeight)
        or not Finite(spacing) or not Finite(gap) then return end
    local justify = label:GetJustifyH()
    if not Public(justify) or type(justify) ~= "string" then return end
    local points = NativeNamePoints(uf, setup, badgeShown)
    if not points then return end
    local y = castHeight + (inside and 0 or iconHeight) + spacing + healthHeight + (uf.showOnlyName and 2 or gap) + offsetY
    -- AcquireUnitFrame stretches uf across the world-positioned plate. Its
    -- center is stable when either bar or the level badge moves sideways.
    label:ClearAllPoints()
    if width then
        SetNameSpan(label, "BOTTOM", uf, "BOTTOM", 0, y, width)
    else
        label:SetPoint("BOTTOMLEFT", uf, "BOTTOMLEFT", 4, y)
        label:SetPoint("BOTTOMRIGHT", uf, "BOTTOMRIGHT", -4, y)
    end
    label:SetJustifyH("CENTER")
    points.centered = true
    points.justify = justify
    return points
end

-- With the health text suppressed it must no longer reserve the right edge
-- of the name. Keep Blizzard's alignment and the user's manual offsets.
function G.FitNameOnly(uf, setup, x, y, badgeShown, manual, width)
    local label, bar = uf.name, uf.HealthBarsContainer
    local original = label:GetJustifyH()
    local style = setup.unitNameAnchorStyle
    if not NS.Public(original) or not NS.Public(style) or not NS.Finite(setup.healthBarToNameAboveSpacing) then return end
    if original ~= "LEFT" and original ~= "CENTER" and original ~= "RIGHT" then return end
    local points = NativeNamePoints(uf, setup, badgeShown)
    if not points then return end
    local edge, relative, justify = "", "", original
    if manual and not private.HealthNameOnly(uf) then
        bar = bar.healthBar
        edge = manual:match("^TOP") or manual:match("^BOTTOM") or ""
        relative = edge
        justify = manual:match("LEFT$") or manual:match("RIGHT$") or "CENTER"
    elseif style ~= 1 then
        edge, relative = "BOTTOM", "TOP"
        y = y + (uf.showOnlyName and 2 or setup.healthBarToNameAboveSpacing)
    end
    label:ClearAllPoints()
    if width then
        local side = justify ~= "CENTER" and justify or ""
        local point, target = edge .. side, relative .. side
        SetNameSpan(label, point ~= "" and point or "CENTER", bar, target ~= "" and target or "CENTER", x, y, width)
    else
        label:SetPoint(edge .. "LEFT", bar, relative .. "LEFT", x, y)
        label:SetPoint(edge .. "RIGHT", bar, relative .. "RIGHT", x, y)
    end
    label:SetJustifyH(justify)
    points.centered = nil
    points.justify = original
    return points
end

-- The plate width constants carry different names on Retail
-- (NAMEPLATE_WIDTH, CLASSIC_NAMEPLATE_WIDTH) and on Forever (Camelot's
-- NAME_PLATE_WIDTH, CLASSIC_NAME_PLATE_WIDTH).
local function NativeWidth(classic)
    local constants = NamePlateConstants
    if classic then return constants.CLASSIC_NAMEPLATE_WIDTH or constants.CLASSIC_NAME_PLATE_WIDTH end
    return constants.NAMEPLATE_WIDTH or constants.NAME_PLATE_WIDTH
end

function G.NameWidthWithinPlate(width, uf, setup, config, badgeShown, delta, healthFontSize)
    local scale, inset, classic = setup.horizontalScale, setup.insetWidth, setup.useClassicHealthBar
    if not NS.Finite(scale) or not NS.Finite(inset) or not NS.Public(classic) then return end
    local size
    if NS.Finite(setup.verticalScale) then
        size = NS.NameplateStyle.BarDimensions(config.barGeometry, config.nativeStyle, scale, setup.verticalScale)
    end
    if not size then
        local native = NativeWidth(classic)
        if not NS.Finite(native) then return end
        size = native * scale
    end
    local available = size - 2 * inset - 8 + delta
    if badgeShown ~= false and NS.Client.isForever then
        local badgeWidth = setup.playerLevelDiffWidth
        if not NS.Finite(badgeWidth) then return end
        available = available - badgeWidth - 5
    end
    local style, mode = setup.unitNameAnchorStyle, config.enemyTextMode
    if not uf.showOnlyName and mode ~= 5 and (style == 1 or style == 2) then
        -- Budget the neighboring HP column from the public text mode/size.
        -- The native word or number width can itself be restricted.
        local glyphs = mode == 2 and 5 or mode == 3 and 9 or 15
        available = available - glyphs * healthFontSize * .75 - 2
    end
    if available > 0 then return math.min(width, available) end
end

-- Native cast and health share the horizontal insets. The health bar also
-- reserves the level badge and can have its own width delta.
function G.CastWidthDelta(uf, setup, config, prefix, healthDelta)
    local p = prefix .. "Cast"
    local mode = config[p .. "WidthMode"] or 1
    if mode == 1 then return config[p .. "WidthDelta"] or 0 end
    local style, scale = NS.NameplateStyle, setup.horizontalScale
    if not NS.Finite(scale) or not NS.Finite(setup.insetWidth) or not NS.Finite(setup.verticalScale)
        or not NS.Public(setup.useClassicHealthBar) then return end
    local classic = setup.useClassicHealthBar == true
    local total = style.BarDimensions(config.barGeometry, config.nativeStyle, scale, setup.verticalScale)
    local reserve = total and 0 or G.LevelReserve(uf, setup)
    local nativeWidth = NativeWidth(classic)
    if not reserve or not NS.Finite(nativeWidth) then return end
    local width = total or nativeWidth * scale
    local base = width - 2 * setup.insetWidth - (setup.useClassicCastBar and 24.25 * scale or 0)
    local health = width - 2 * setup.insetWidth - (classic and 24.25 * scale or 0) - reserve + healthDelta
    return style.CastWidth(base, health, mode, config[p .. "ManualWidth"] or 160, 0) - base
end

function G.RestoreIconZoom(state)
    local zoom = state.iconZoom
    if not zoom then return true end
    local icon = zoom.icon
    if NS.Safety.IsForbidden(icon) then return false end
    local accessible = icon:CanBeAccessedInContext()
    if not NS.Public(accessible) or not accessible then return false end
    icon:SetTexCoord(unpack(zoom.coords))
    state.iconZoom = nil
    return true
end

local castIconBorders = setmetatable({}, { __mode = "k" })
local function SyncCastIconBorder(cast)
    local border = castIconBorders[cast]
    if not border or NS.Safety.IsForbidden(cast) or NS.Safety.IsForbidden(border.icon) then return end
    if not border.enabled then return end
    local accessible = border.icon:CanBeAccessedInContext()
    if not NS.Public(accessible) or not accessible then
        border.host:Hide()
        return
    end
    local shown = border.icon:IsShown()
    border.host:SetShown(NS.Public(shown) and shown == true)
end

function G.HideCastIconBorder(state)
    local border = state.castIconBorder
    if border then
        border.enabled = false
        border.host:Hide()
    end
    state.castIconStyle = nil
end

local function GetCastIconBorder(cast, icon)
    local border = castIconBorders[cast]
    if not border then
        local host = CreateFrame("Frame", nil, cast)
        host:SetAllPoints(icon)
        border = NS.NameplateStyle.CreateBorder(host)
        border.host, border.icon = host, icon
        castIconBorders[cast] = border
        hooksecurefunc(cast, "UpdateIconShown", SyncCastIconBorder)
    end
    return border
end

function G.CastIconZoom(state, cast, percent)
    if not percent then return G.RestoreIconZoom(state) end
    if not cast or NS.Safety.IsForbidden(cast) then return false end
    local icon = cast.Icon
    if not icon or NS.Safety.IsForbidden(icon) then return false end
    local accessible = icon:CanBeAccessedInContext()
    if not NS.Public(accessible) or not accessible then return false end
    local zoom = state.iconZoom
    if not zoom then
        local coords = { icon:GetTexCoord() }
        if #coords ~= 8 then return false end
        for _, value in ipairs(coords) do if not NS.Finite(value) then return false end end
        zoom = { icon = icon, coords = coords }
        state.iconZoom = zoom
    end
    if zoom.percent == percent then return true end
    local c, scale = zoom.coords, 100 / percent
    local x, y = (c[1] + c[3] + c[5] + c[7]) / 4, (c[2] + c[4] + c[6] + c[8]) / 4
    icon:SetTexCoord(x + (c[1] - x) * scale, y + (c[2] - y) * scale, x + (c[3] - x) * scale, y + (c[4] - y) * scale,
        x + (c[5] - x) * scale, y + (c[6] - y) * scale, x + (c[7] - x) * scale, y + (c[8] - y) * scale)
    zoom.percent = percent
    return true
end

function G.CastIconStyle(state, uf, plan)
    local cast = uf.CastBarsContainer and uf.CastBarsContainer.castBar
    if not G.CastIconZoom(state, cast, plan.iconZoom) then return false end
    if plan.iconBorder then
        if not cast or NS.Safety.IsForbidden(cast) then return false end
        local icon = cast.Icon
        if not icon or NS.Safety.IsForbidden(icon) then return false end
        local accessible = icon:CanBeAccessedInContext()
        if not NS.Public(accessible) or not accessible then return false end
        local border = GetCastIconBorder(cast, icon)
        state.castIconBorder = border
        NS.NameplateStyle.PaintBorder(border, icon, plan.iconBorder, plan.iconBorderColor)
        border.enabled = true
        SyncCastIconBorder(cast)
    elseif state.castIconBorder then
        G.HideCastIconBorder(state)
    end
    state.castIconStyle = plan.castIconStyle
    return true
end

-- Rebuild the native castbar edges with the configured width and position.
-- Its parent anchors the health bar and keeps its own size.
local function CastWidth(state, cast, container, setup, plan, delta)
    local half = delta / 2
    local x, y = plan.Cast[1], plan.Cast[2]
    if setup.useClassicCastBar then
        local h, baseY = setup.horizontalScale, .5 * setup.verticalScale
        Link(state, cast, "TOPLEFT", container, "TOPLEFT", 20.75 * h, baseY, half - x, -y)
        Link(state, cast, "BOTTOMRIGHT", container, "BOTTOMRIGHT", -3.5 * h, baseY, -half - x, -y)
    elseif setup.spellNameInsideCastBar then
        Link(state, cast, "TOPLEFT", container, "TOPLEFT", 0, 0, half - x, -y)
        Link(state, cast, "BOTTOMRIGHT", container, "BOTTOMRIGHT", 0, 0, -half - x, -y)
    else
        local iconX, iconY = plan.CastIcon[1], plan.CastIcon[2]
        Link(state, cast, "LEFT", container, "BOTTOMLEFT", 0, 0, half - x, -y)
        Link(state, cast, "RIGHT", container, "BOTTOMRIGHT", 0, 0, -half - x, -y)
        Link(state, cast.Icon, "BOTTOMLEFT", container, "BOTTOMLEFT", 0, 0, half - iconX, -iconY)
        Link(state, cast, "BOTTOM", cast.Icon, "TOP", 0, 0, iconX - half - x, iconY - y)
    end
end

function G.CastOffsets(state, uf, plan, setup, force, delta, castTimes)
    local container = uf.CastBarsContainer
    local cast = container and container.castBar
    local customWidth = delta ~= 0
    local classic, inside = setup.useClassicCastBar == true, setup.spellNameInsideCastBar == true
    if customWidth and (not Accessible(container) or not Accessible(cast)
        or not classic and not inside and not Accessible(cast.Icon)) then
        return false
    end
    if not cast then return true end
    local bar, text, time, icon = plan.Cast, plan.CastText, plan.CastTime, plan.CastIcon
    local shield, target = plan.CastShield, plan.CastTarget
    Offset(state, cast, customWidth and 0 or bar[1], customWidth and 0 or bar[2], force)
    Offset(state, cast.Border, classic and bar[1] or 0, classic and bar[2] or 0, force)
    if classic or inside then
        -- Classic's icon follows Border; Modern-inside follows the bar.
        Offset(state, cast.Icon, icon[1] - bar[1], icon[2] - bar[2], force)
    elseif customWidth then
        Offset(state, cast.Icon, 0, 0, force)
    else
        Offset(state, cast.Icon, icon[1], icon[2], force)
        Link(state, cast, "BOTTOM", cast.Icon, "TOP", 0, 0, icon[1], icon[2])
    end
    if customWidth then CastWidth(state, cast, container, setup, plan, delta) end
    local parent = classic and bar or icon
    Offset(state, cast.Text, text[1] - parent[1], text[2] - parent[2], force)
    local castTime = castTimes[cast]
    Offset(state, castTime and castTime.label, time[1] - bar[1], time[2] - bar[2], force)
    Offset(state, cast.BorderShield, shield[1] - parent[1], shield[2] - parent[2], force)
    Offset(state, cast.CastTargetNameText, target[1] - bar[1], target[2] - bar[2], force)
    if not classic then
        Link(state, cast.CastTargetNameText, "LEFT", cast.Text, "RIGHT", 2, 0,
            text[1] - bar[1], text[2] - bar[2])
    end
    return true
end

local SETUP_NUMBERS = { "insetWidth", "castBarToHealthBarSpacing", "healthBarHeight",
    "castBarHeight", "castIconWidth", "castIconHeight", "horizontalScale", "verticalScale" }
local function Ready(uf, setup)
    local container, health = uf.CastBarsContainer, uf.HealthBarsContainer
    if not container or not health or NS.Safety.IsForbidden(container) or NS.Safety.IsForbidden(health) then return end
    local cast = container.castBar
    if not cast or NS.Safety.IsForbidden(cast) or not cast.Icon or NS.Safety.IsForbidden(cast.Icon) then return end
    for _, key in ipairs(SETUP_NUMBERS) do
        if not NS.Finite(setup[key]) then return end
    end
    return container, health, cast
end

local function CastSize(container, cast, setup, height, iconWidth, iconHeight, old, force)
    local inside = setup.spellNameInsideCastBar
    local previousHeight = old and old.castHeight or setup.castBarHeight
    local previousIconHeight = old and old.iconHeight or setup.castIconHeight
    if force or height + (inside and 0 or iconHeight) ~= previousHeight + (inside and 0 or previousIconHeight) then
        container:SetHeight(height + (inside and 0 or iconHeight))
    end
    if force or height ~= previousHeight then cast:SetHeight(height) end
    if force or iconWidth ~= (old and old.iconWidth or setup.castIconWidth) or iconHeight ~= previousIconHeight then
        cast.Icon:SetSize(iconWidth, iconHeight)
    end
end

local function CastBorderSize(cast, setup, width, height)
    if not setup.useClassicCastBar then return true end
    local border = cast.Border
    if not border or NS.Safety.IsForbidden(border) or not NS.Finite(setup.castBarBorderWidth)
        or not NS.Finite(setup.castBarBorderHeight) then return false end
    border:SetSize(setup.castBarBorderWidth + width, setup.castBarBorderHeight + height)
    return true
end

function G.Restore(state, uf, setup)
    local old = state.geometry
    if not old then return true end
    local container, health, cast = Ready(uf, setup)
    if not container then return false end
    local reserve = old.inset and G.LevelReserve(uf, setup)
    if old.inset and not reserve then return false end
    if old.borderWidth and not CastBorderSize(cast, setup, 0, 0) then return false end
    if old.inset then
        G.Point(container, "BOTTOMLEFT", uf, "BOTTOMLEFT", setup.insetWidth, 0)
        G.Point(container, "BOTTOMRIGHT", uf, "BOTTOMRIGHT", -setup.insetWidth, 0)
        G.Point(health, "BOTTOMRIGHT", container, "TOPRIGHT", -reserve, setup.castBarToHealthBarSpacing)
        health:SetHeight(setup.healthBarHeight)
    end
    CastSize(container, cast, setup, setup.castBarHeight, setup.castIconWidth, setup.castIconHeight, old)
    state.geometry = nil
    return true
end

function G.Apply(state, uf, setup, config, force, prefix, width)
    local keys, old = Key[prefix], state.geometry
    local height, icon = config[keys.CastHeight] or 0, config[keys.CastIconSize] or 0
    width = width or config[keys.CastWidthDelta] or 0
    local uniform = config.barGeometry == SAME_GEOMETRY
    local classicBorder = setup.useClassicCastBar and (width ~= 0 or height ~= 0)
    local customCast = height ~= 0 or icon ~= 0 or classicBorder
    if not uniform and (not customCast or old and old.inset ~= nil) then
        if not G.Restore(state, uf, setup) then return end
        if not customCast then return setup.healthBarHeight end
        old = nil
    end
    local container, health, cast = Ready(uf, setup)
    if not container then return end
    local inset, healthHeight = nil, setup.healthBarHeight
    local castHeight, iconWidth, iconHeight = setup.castBarHeight, setup.castIconWidth, setup.castIconHeight
    if uniform then
        local totalWidth
        totalWidth, healthHeight, castHeight, iconHeight = NS.NameplateStyle.BarDimensions(
            config.barGeometry, config.nativeStyle, setup.horizontalScale, setup.verticalScale)
        local nativeWidth = NativeWidth(setup.useClassicHealthBar == true)
        if not NS.Finite(nativeWidth) then return end
        inset = setup.insetWidth + (nativeWidth * setup.horizontalScale - totalWidth) / 2
        iconWidth = iconHeight
    end
    castHeight, iconWidth, iconHeight = NS.NameplateStyle.CastDimensions(height, icon, castHeight, iconWidth, iconHeight)
    local borderWidth = classicBorder and width or nil
    if force or not old or old.inset ~= inset or old.healthHeight ~= healthHeight or old.castHeight ~= castHeight
        or old.iconWidth ~= iconWidth or old.iconHeight ~= iconHeight or old.borderWidth ~= borderWidth then
        if (borderWidth or old and old.borderWidth)
            and (force or not old or old.borderWidth ~= borderWidth or old.castHeight ~= castHeight) then
            local borderHeight = borderWidth and castHeight - setup.castBarHeight or 0
            if not CastBorderSize(cast, setup, borderWidth or 0, borderHeight) then return end
        end
        if inset then
            G.Point(container, "BOTTOMLEFT", uf, "BOTTOMLEFT", inset, 0)
            G.Point(container, "BOTTOMRIGHT", uf, "BOTTOMRIGHT", -inset, 0)
            -- The level badge remains a separate element and cannot shrink the bar.
            G.Point(health, "BOTTOMRIGHT", container, "TOPRIGHT", 0, setup.castBarToHealthBarSpacing)
            if force or not old or old.inset == nil or old.healthHeight ~= healthHeight then health:SetHeight(healthHeight) end
        end
        CastSize(container, cast, setup, castHeight, iconWidth, iconHeight, old, force)
        old = old or {}
        old.inset, old.healthHeight, old.castHeight = inset, healthHeight, castHeight
        old.iconWidth, old.iconHeight, old.borderWidth = iconWidth, iconHeight, borderWidth
        state.geometry = old
    end
    return healthHeight
end

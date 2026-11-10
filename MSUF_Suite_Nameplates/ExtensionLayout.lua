local _, P = ...
local NS, S = P.NS, P.Suite
local L = {}
P.ExtensionLayout = L
local Point = P.Geometry.Point

local function Safe(region)
    return not NS.IsSecret(region) and region and not NS.Safety.IsForbidden(region)
end

function L.Mutable(state, region)
    if not Safe(region) then return false end
    if NS.IsCombatLocked() then
        local protected, ownerProtected = region:IsProtected(), state.uf:IsProtected()
        if NS.IsSecret(protected) or NS.IsSecret(ownerProtected) or protected ~= false or ownerProtected ~= false then
            state.owner.pendingPlates[state.uf] = true
            return false
        end
    end
    return true
end

local function PartMutable(state, region)
    return not Safe(region) or L.Mutable(state, region)
end

local function LayoutMutable(state)
    local uf, cast = state.uf, state.cast
    return L.Mutable(state, uf) and PartMutable(state, uf.name) and PartMutable(state, uf.RaidTargetFrame)
        and PartMutable(state, cast) and (not cast or PartMutable(state, cast.Icon) and PartMutable(state, cast.Text))
end

-- Alpha and scale are captured only when first changed. Blizzard's native
-- distance/selection alpha lives on the outer nameplate and still applies.
function L.Alpha(state, alpha, inRange, outMultiplier)
    local uf = state.uf
    local opaqueRange = NS.IsSecret(inRange)
    if alpha == 1 and state.baseAlpha == nil and not opaqueRange then return end
    if not Safe(uf) then return end
    if state.baseAlpha == nil then
        local native = uf:GetAlpha()
        if not S.Finite(native) then return end
        state.baseAlpha = native
    end
    local value = state.baseAlpha * alpha
    if opaqueRange then
        uf:SetAlphaFromBoolean(inRange, value, value * outMultiplier)
        state.alpha = nil
        return
    end
    if state.alpha ~= value then uf:SetAlpha(value) state.alpha = value end
    if alpha == 1 then state.baseAlpha, state.alpha = nil, nil end
end

function L.Scale(state, scale)
    local uf = state.uf
    if scale == 1 and state.baseScale == nil then return end
    if not L.Mutable(state, uf) then return end
    if state.baseScale == nil then
        local native = uf:GetScale()
        if not S.Finite(native) then return end
        state.baseScale = native
    end
    local value = state.baseScale * scale
    if state.scale ~= value then uf:SetScale(value) state.scale = value end
    if scale == 1 then state.baseScale, state.scale = nil, nil end
end

function L.Name(state)
    local name, side = state.uf.name, state.plan[state.prefix]
    if not side or not Safe(name) then return end
    local alpha = state.casting == true and (side.nameCast == 3 and 0 or side.nameCast == 2 and side.nameAlpha) or 1
    if alpha == 1 and state.baseNameAlpha == nil then return end
    if state.baseNameAlpha == nil then
        local native = name:GetAlpha()
        if not S.Finite(native) then return end
        state.baseNameAlpha = native
    end
    local value = state.baseNameAlpha * alpha
    if state.nameAlpha ~= value then name:SetAlpha(value) state.nameAlpha = value end
    if alpha == 1 then state.baseNameAlpha, state.nameAlpha = nil, nil end
end

function L.RestoreName(state)
    if state.baseNameAlpha ~= nil and Safe(state.uf.name) then state.uf.name:SetAlpha(state.baseNameAlpha) end
    state.baseNameAlpha, state.nameAlpha = nil, nil
end

local function Foreground(state, enabled)
    local cast = state.cast
    if not Safe(cast) or not L.Mutable(state, cast) then return end
    if enabled then
        if state.baseCastLevel == nil then
            local level = cast:GetFrameLevel()
            if not S.Finite(level) then return end
            state.baseCastLevel = level
        end
        local level = state.uf:GetFrameLevel()
        if S.Finite(level) then cast:SetFrameLevel(math.max(state.baseCastLevel, level + 10)) end
    elseif state.baseCastLevel ~= nil then
        cast:SetFrameLevel(state.baseCastLevel)
        state.baseCastLevel = nil
    end
end

local function NativeRaid(state)
    local uf, region = state.uf, state.uf.RaidTargetFrame
    if not Safe(region) or NS.IsSecret(uf.showOnlyName) then return false end
    local offset, level = 0, uf.PlayerLevelDiffFrame
    if NS.Client.isForever and not uf.showOnlyName and Safe(level) then
        local shown = level:IsShown()
        if NS.IsSecret(shown) then return false end
        if shown then
            local _, _, anchor, x = level:GetPoint()
            local width = level:GetWidth()
            if NS.IsSecret(anchor) or not S.Finite(x) or not S.Finite(width) then return false end
            if anchor == "LEFT" then offset = -width - math.abs(x) end
        end
    end
    region:ClearAllPoints()
    if uf.showOnlyName then
        Point(region, "BOTTOM", uf.name, "TOP", 0, 10)
    else
        Point(region, "RIGHT", uf.HealthBarsContainer, "LEFT", offset, 0)
    end
    return true
end

local function Raid(state, choice)
    local uf, region = state.uf, state.uf.RaidTargetFrame
    if not Safe(region) then return end
    if choice == 1 then
        if state.raidMoved and NativeRaid(state) then
            state.raidMoved = nil
            P.Layout.Reapply(uf, state.prefix, state.owner.config)
        end
        return
    end
    local c, prefix = state.owner.config, state.prefix
    local x, y = c[prefix .. "RaidIconOffsetX"] or 0, c[prefix .. "RaidIconOffsetY"] or 0
    region:ClearAllPoints()
    if choice == 2 then
        Point(region, "RIGHT", uf.name, "LEFT", x - 3, y)
    elseif choice == 3 then
        Point(region, "LEFT", uf.name, "RIGHT", x + 3, y)
    elseif choice == 4 then
        Point(region, "BOTTOM", uf.name, "TOP", x, y + 3)
    else
        Point(region, "CENTER", state.health, "CENTER", x, y)
    end
    state.raidMoved = true
end

local function NativeIcon(state)
    local cast, setup = state.cast, NamePlateSetupOptions
    if not Safe(cast) or not Safe(cast.Icon) or NS.IsSecret(setup.useClassicCastBar)
        or NS.IsSecret(setup.spellNameInsideCastBar) then return false end
    if setup.useClassicCastBar and not S.Finite(setup.horizontalScale) then return false end
    cast.Icon:ClearAllPoints()
    if setup.useClassicCastBar then
        Point(cast.Icon, "CENTER", cast.Border, "LEFT", 11.5 * setup.horizontalScale, 0)
    elseif setup.spellNameInsideCastBar then
        Point(cast.Icon, "LEFT", cast, "LEFT", 0, 0)
    else
        Point(cast.Icon, "BOTTOMLEFT", state.uf.CastBarsContainer, "BOTTOMLEFT", 0, 0)
        cast:ClearAllPoints()
        Point(cast, "BOTTOM", cast.Icon, "TOP", 0, 0)
        Point(cast, "LEFT", state.uf.CastBarsContainer, "BOTTOMLEFT", 0, 0)
        Point(cast, "RIGHT", state.uf.CastBarsContainer, "BOTTOMRIGHT", 0, 0)
    end
    if not setup.useClassicCastBar and Safe(cast.Text) then
        cast.Text:ClearAllPoints()
        Point(cast.Text, "LEFT", cast.Icon, "RIGHT", 2, 0)
    end
    return true
end

local function Icon(state, choice)
    local cast, setup = state.cast, NamePlateSetupOptions
    if not Safe(cast) or not Safe(cast.Icon) then return end
    if choice == 1 then
        if state.iconMoved and NativeIcon(state) then
            state.iconMoved = nil
            P.Layout.Reapply(state.uf, state.prefix, state.owner.config)
        end
        return
    end
    if NS.IsSecret(setup.useClassicCastBar) or NS.IsSecret(setup.spellNameInsideCastBar) then return end
    local c, prefix = state.owner.config, state.prefix
    local x, y = c[prefix .. "CastIconOffsetX"] or 0, c[prefix .. "CastIconOffsetY"] or 0
    if not setup.useClassicCastBar and not setup.spellNameInsideCastBar then
        -- Break the native cast -> icon link before making icon -> cast.
        -- Its original bottom lies one public icon height above the container.
        if not S.Finite(setup.castIconHeight) then return end
        local cx, cy = c[prefix .. "CastOffsetX"] or 0, c[prefix .. "CastOffsetY"] or 0
        local half = (c[prefix .. "CastWidthDelta"] or 0) / 2
        local height = c[prefix .. "CastIconSize"] or 0
        if height <= 0 then height = setup.castIconHeight end
        cast:ClearAllPoints()
        Point(cast, "BOTTOMLEFT", state.uf.CastBarsContainer, "BOTTOMLEFT", cx - half, cy + height)
        Point(cast, "BOTTOMRIGHT", state.uf.CastBarsContainer, "BOTTOMRIGHT", cx + half, cy + height)
    end
    cast.Icon:ClearAllPoints()
    local target = choice > 3 and state.health or cast
    local right = choice == 3 or choice == 5
    Point(cast.Icon, right and "LEFT" or "RIGHT", target, right and "RIGHT" or "LEFT", x + (right and 3 or -3), y)
    if not setup.useClassicCastBar and Safe(cast.Text) then
        cast.Text:ClearAllPoints()
        Point(cast.Text, "LEFT", cast, "LEFT", 2 + (c[prefix .. "CastTextOffsetX"] or 0), c[prefix .. "CastTextOffsetY"] or 0)
    end
    state.iconMoved = true
end

function L.Anchors(state, force)
    if state.layoutPlan == state.plan and not force then return end
    if not LayoutMutable(state) then return end
    local side = state.plan[state.prefix]
    if not side then return end
    Foreground(state, side.foreground)
    Icon(state, side.iconAnchor)
    Raid(state, side.raidAnchor)
    state.layoutPlan = state.plan
end

local function PublicAnchors(anchors)
    if NS.IsSecret(anchors) or type(anchors) ~= "table" or not canaccesstable(anchors) then return false end
    for _, point in ipairs(anchors) do
        if NS.IsSecret(point) or type(point) ~= "table" or not canaccesstable(point) then return false end
        if NS.IsSecret(point.point) or NS.IsSecret(point.relativeTo) or NS.IsSecret(point.relativePoint)
            or NS.IsSecret(point.offsetX) or NS.IsSecret(point.offsetY) then return false end
    end
    return true
end

function L.HitTest(state, hidden, force)
    local plate, plan = state.plate, state.plan
    if not Safe(plate) or not plate.CanChangeHitTestPoints then return true end
    local clear = hidden or plan.clickThrough and state.prefix == "friendly"
    local mode = clear and "clear" or plan.clickbox and "custom" or "native"
    if not force and state.hitMode == mode and state.hitPlan == plan then return true end
    if mode == "native" and not state.hitOriginal then return true end
    local allowed = plate:CanChangeHitTestPoints()
    if NS.IsSecret(allowed) or allowed ~= true then
        state.owner.pendingPlates[state.uf] = true
        return false
    end
    if not state.hitOriginal then
        local anchors = plate:GetHitTestPoints()
        if not PublicAnchors(anchors) then return false end
        state.hitOriginal = anchors
    end
    if clear then
        -- Native UpdateHitTestArea uses this same operation for name-only
        -- and widget-only plates on both supported clients.
        plate:ClearAllHitTestPoints()
    elseif mode == "custom" then
        local points = state.hitPoints
        if not points then
            points = { { point = "TOPLEFT", relativePoint = "CENTER" }, { point = "BOTTOMRIGHT", relativePoint = "CENTER" } }
            state.hitPoints = points
        end
        points[1].relativeTo, points[2].relativeTo = state.health, state.health
        points[1].offsetX, points[1].offsetY = -plan.clickWidth / 2, plan.clickHeight / 2
        points[2].offsetX, points[2].offsetY = plan.clickWidth / 2, -plan.clickHeight / 2
        plate:SetHitTestPoints(points)
    else
        plate:SetHitTestPoints(state.hitOriginal)
        state.hitOriginal = nil
    end
    state.hitMode, state.hitPlan = mode, plan
    return true
end

function L.NativeHitTest(state)
    state.hitOriginal, state.hitMode, state.hitPlan = nil, nil, nil
end

function L.Restore(state)
    L.Alpha(state, 1)
    L.RestoreName(state)
    if not LayoutMutable(state) then return false end
    L.Scale(state, 1)
    Foreground(state, false)
    if state.iconMoved and not NativeIcon(state) then return false end
    if state.raidMoved and not NativeRaid(state) then return false end
    if state.iconMoved or state.raidMoved then
        if state.owner.active then
            P.Layout.Reapply(state.uf, state.prefix, state.owner.config)
        else
            P.Layout.Restore(state.uf)
        end
    end
    state.iconMoved, state.raidMoved, state.layoutPlan = nil, nil, nil
    if state.hitOriginal then
        local allowed = state.plate:CanChangeHitTestPoints()
        if NS.IsSecret(allowed) or allowed ~= true then return false end
        state.plate:SetHitTestPoints(state.hitOriginal)
    end
    L.NativeHitTest(state)
    return true
end

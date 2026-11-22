local _, private = ...
local NS = private.NS
local Mode, Key = private.Mode, private.Key
local Layout = {}
private.Layout = Layout
local Geometry = private.Geometry
local Point = Geometry.Point
local states = setmetatable({}, { __mode = "k" })
local hooked = setmetatable({}, { __mode = "k" })
local plans, generation, module = {}, 0
local elements, X = NS.NameplateStyle.Elements, NS.NameplateExtensions
local AuraModel = NS.NameplateAuraDisplay

local function Accessible(region)
    return region and not NS.Safety.IsForbidden(region)
end

-- A write this plate could not make now: the end of combat applies the
-- plate again (Skin.lua OnCombatEnded).
local function Defer(uf)
    module.pendingPlates[uf] = true
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

-- Blizzard's aura list anchors include fixed offsets (-5, +5 and the debuff
-- padding). SetPointsOffset replaces those offsets on every point, so move
-- each known native anchor from its own base instead. nativeFixed marks an
-- anchor from Blizzard's XML, which UpdateAnchors never rebuilds (OnAnchors
-- restores it before the offsets are applied again).
local NATIVE_FIXED = true
local function AuraAnchor(state, uf, region, point, owner, relative, x, y, dx, dy, nativeFixed)
    if dx == 0 and dy == 0 then return end
    if not Accessible(region) or not owner then
        Defer(uf)
        return
    end
    local link = { region, point, owner, relative, x, y }
    link.nativeFixed = nativeFixed
    state.links[#state.links + 1] = link
    Point(region, point, owner, relative, x + dx, y + dy)
end

local function RestoreLinks(state, uf, recycled)
    for i = #state.links, 1, -1 do
        local link = state.links[i]
        if recycled and not link.nativeFixed then
            table.remove(state.links, i)
        elseif Accessible(link[1]) then
            Point(unpack(link))
            table.remove(state.links, i)
        else
            Defer(uf)
        end
    end
end

-- Blizzard anchors the health container to the cast container. Widen from
-- the left so the native level badge (anchored at the right) stays attached;
-- the health bar, text, skin and hit-test anchors follow that container.
local function HealthSize(state, uf, setup, width, height, force, baseHeight)
    local previous = state.healthSize
    if not previous and width == 0 and height == 0 then return end
    local container, cast = uf.HealthBarsContainer, uf.CastBarsContainer
    local spacing, nativeHeight = setup.castBarToHealthBarSpacing, baseHeight or setup.healthBarHeight
    if not Accessible(container) or not cast or not NS.Finite(spacing) or not NS.Finite(nativeHeight) then
        Defer(uf)
        return
    end
    if not force and previous and previous[1] == width and previous[2] == height
        and previous[3] == spacing and previous[4] == nativeHeight then return end
    Point(container, "BOTTOMLEFT", cast, "TOPLEFT", -width, spacing)
    container:SetHeight(nativeHeight + height)
    state.healthSize = (width ~= 0 or height ~= 0) and { width, height, spacing, nativeHeight } or nil
end

local function RestoreHealthSize(state, uf)
    local previous = state.healthSize
    if not previous then return end
    local container, cast = uf.HealthBarsContainer, uf.CastBarsContainer
    local setup = NamePlateSetupOptions
    local spacing = setup.castBarToHealthBarSpacing or previous[3]
    local height = setup.healthBarHeight or previous[4]
    if not Accessible(container) or not cast or not NS.Finite(spacing) or not NS.Finite(height) then
        Defer(uf)
        return
    end
    Point(container, "BOTTOMLEFT", cast, "TOPLEFT", 0, spacing)
    container:SetHeight(height)
    state.healthSize = nil
end

-- Native UpdateAnchors on upstream/ptr and upstream/forever rebuilds these
-- points from public setup constants. Capture those constants, never restricted
-- GetPoint/GetWidth results, so turning the optional mirror off is reversible.
local function RestoreHeader(state, uf)
    local h = state.header
    if not h then return true end
    if not Accessible(h.name) or not Accessible(h.value) then
        Defer(uf)
        return false
    end
    h.name:ClearAllPoints()
    h.value:ClearAllPoints()
    h.name:SetJustifyH(h.justify)
    if h.inside then
        Point(h.value, "RIGHT", h.health.RightText, "LEFT", 2, 0)
    else
        Point(h.value, "BOTTOMRIGHT", h.health.RightText, "BOTTOMLEFT", 2, 0)
    end
    Point(h.name, "BOTTOMLEFT", h.container, "TOPLEFT", h.forever and 0 or 4, h.spacing)
    if not h.forever then
        Point(h.name, "BOTTOMRIGHT", h.health.Text, "BOTTOMLEFT", -2, 0)
    elseif h.badge then
        Point(h.name, "RIGHT", uf.PlayerLevelDiffFrame, "RIGHT", 0, 0)
    elseif h.inside then
        Point(h.name, "RIGHT", h.container, "RIGHT", 0, 0)
    else
        Point(h.name, "RIGHT", h.health.Text, "LEFT", -2, 0)
    end
    state.offsets[h.name], state.offsets[h.value] = nil, nil
    state.header = nil
    return true
end

local function MirrorHeader(state, uf, prefix, plan, setup, config)
    local style = NS.NameplateStyle
    if prefix ~= "enemy" or not style.MirrorHeader(config.enemyMirrorHeader,
        config.enemyTextMode, setup.unitNameAnchorStyle, uf.showOnlyName) then return false end
    local container, name = uf.HealthBarsContainer, uf.name
    local health = container and container.healthBar
    -- TextStatusBar's percent-only mode displays TextString (= Text). The
    -- LeftText/RightText regions are hidden and only own the native chain.
    local value = health and health.Text
    local spacing = setup.healthBarToNameAboveSpacing
    if not Accessible(container) or not Accessible(health) or not Accessible(name)
        or not Accessible(value) or not NS.Finite(spacing) then
        Defer(uf)
        return nil
    end
    local forever, inside, justify, badge = NS.Client.isForever, false, "LEFT", false
    if forever then
        inside, justify = setup.healthTextInsideBarWhenNameAboveHealthBar, setup.nameJustificationWhenAboveHealthBar
        if not NS.Public(inside) or not NS.Public(justify) or type(inside) ~= "boolean"
            or type(justify) ~= "string" then
            Defer(uf)
            return nil
        end
        badge = Geometry.LevelBadgeShown(uf, uf.unit)
        if badge == nil then
            Defer(uf)
            return nil
        end
    end
    state.header = { name = name, value = value, health = health, container = container,
        forever = forever, inside = inside, justify = justify, badge = badge, spacing = spacing }
    name:SetPointsOffset(0, 0)
    value:SetPointsOffset(0, 0)
    state.offsets[name], state.offsets[value] = nil, nil
    style.PlaceMirroredHeader(name, value, health, container, spacing,
        plan.Name[1], plan.Name[2], plan.HealthText[1], plan.HealthText[2], Point)
    name:SetJustifyH("RIGHT")
    return true
end

local function AuraWritable(frame)
    if not Accessible(frame) then return false end
    local allowed = frame:CanBeAccessedInContext()
    return NS.Public(allowed) and allowed == true
end

local function RestoreAuraStyles(state, uf)
    if not state.auraStyles then return end
    for frame, saved in pairs(state.auraStyles) do
        if AuraWritable(frame) then
            if saved.scale then frame:SetScale(saved.scale) end
            if saved.alpha then frame:SetAlpha(saved.alpha) end
            if saved.layer then frame:SetFrameLevel(saved.layer) end
            state.auraStyles[frame] = nil
        else
            Defer(uf)
        end
    end
    if not next(state.auraStyles) then state.auraStyles = nil end
end

local function NameAnchorWritable(label)
    if not AuraWritable(label) then return false end
    local restricted = label:IsAnchoringRestricted()
    return NS.Public(restricted) and restricted == false
end

local function RestoreNameAnchor(state, uf)
    local saved = state.nameAnchor
    if not saved then return true end
    local writable = saved.native and AuraWritable or NameAnchorWritable
    if not writable(uf.name) then
        Defer(uf)
        return false
    end
    uf.name:ClearAllPoints()
    for _, point in ipairs(saved.points) do uf.name:SetPoint(unpack(point)) end
    uf.name:SetJustifyH(saved.justify)
    state.nameAnchor = nil
    return true
end

local function ApplyNameAnchor(state, uf, plan)
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
    Point(label, anchor, owner, anchor, plan.Name[1], plan.Name[2])
    label:SetJustifyH(anchor:find("LEFT", 1, true) and "LEFT" or anchor:find("RIGHT", 1, true) and "RIGHT" or "CENTER")
    return true
end

local function PlaceNativeName(state, uf, plan, setup, baseHeight, badgeShown, center, nativeReset)
    if AuraWritable(uf.name) then
        local anchor
        if center then
            local size = not nativeReset and state.healthSize
            local height = size and size[4] + size[2] or baseHeight
            local geometry = not nativeReset and state.geometry
            anchor = Geometry.CenterName(uf, setup, height, plan.Name[2], badgeShown, geometry)
        else
            anchor = Geometry.FitNameOnly(uf, setup, plan.Name[1], plan.Name[2], badgeShown, plan.nameAnchor)
        end
        if anchor then
            Offset(state, uf.name, 0, 0, true)
            anchor.generation = generation
            state.nameAnchor = anchor
            return true
        end
    end
    Defer(uf)
    return nil, true
end

local function AnchorName(state, uf, plan, center, setup, height, badgeShown)
    if center or plan.fitName and private.FriendlyNames.IsNameOnly(uf) then
        return PlaceNativeName(state, uf, plan, setup, height, badgeShown, center)
    elseif plan.nameAnchor then
        Offset(state, uf.name, 0, 0, true)
        return ApplyNameAnchor(state, uf, plan)
    end
end

-- The cold-layout handoff. A pass that may write the cast's geometry (its
-- size in Geometry.Apply and Geometry.Restore, its anchors in CastOffsets)
-- returns true, and the entry point that ran the pass reports the plate once,
-- after its last write, so the castbar's spark is sized from the final
-- geometry (Textures.OnLayout). A pass that returns at its combat or
-- generation gate wrote nothing and returns nothing. The result belongs to
-- its call: a native setter can run the layout of another plate inside this
-- pass, which reports that plate and leaves this one's result alone.
-- Blizzard's own rebuild is reported by Textures.OnAnchors.
local function Settle(uf)
    local textures = private.Textures
    if textures and textures.inUse then textures.OnLayout(uf) end
end

local function Restore(uf, recycled)
    local state = states[uf]
    if not state then return end
    if NS.IsCombatLocked() or NS.Safety.IsForbidden(uf) then
        Defer(uf)
        return
    end
    if recycled then
        -- ApplyFrameOptions and UpdateAnchors rebuild these sizes, anchors
        -- and justification before the pooled frame represents a new unit.
        state.geometry, state.healthSize = nil, nil
        state.nameAnchor, state.header = nil, nil
    elseif not RestoreNameAnchor(state, uf) or not RestoreHeader(state, uf) then
        return true
    end
    RestoreLinks(state, uf, recycled)
    if not recycled then RestoreHealthSize(state, uf) end
    RestoreAuraStyles(state, uf)
    if state.iconZoom and not Geometry.RestoreIconZoom(state) then Defer(uf) end
    if state.castIconBorder then Geometry.HideCastIconBorder(state) end
    if state.geometry and not Geometry.Restore(state, uf, NamePlateSetupOptions) then Defer(uf) end
    for region in pairs(state.offsets) do
        if Accessible(region) then
            region:SetPointsOffset(0, 0)
            state.offsets[region] = nil
        else
            Defer(uf)
        end
    end
    if not next(state.offsets) and #state.links == 0 and not state.healthSize and not state.geometry
        and not state.iconZoom and not (state.auraStyles and next(state.auraStyles)) then states[uf] = nil end
    return true
end

function Layout.Restore(uf, recycled)
    if Restore(uf, recycled) then Settle(uf) end
end

local function OnAnchors(uf)
    local textures = private.Textures
    if textures and textures.inUse then textures.OnAnchors(uf) end
    local state = states[uf]
    local forbidden = NS.Safety.IsForbidden(uf)
    local locked = forbidden or NS.IsCombatLocked()
    if state then
        -- UpdateAnchors rebuilds dynamic links, including Forever's CC
        -- badge reservation. Restore only fixed XML links before applying
        -- saved offsets again; rebuilt anchors belong to Blizzard.
        local pending = {}
        for _, link in ipairs(state.links) do
            if link.nativeFixed then
                if locked then
                    pending[#pending + 1] = link
                elseif Accessible(link[1]) then
                    Point(unpack(link))
                else
                    Defer(uf)
                end
            end
        end
        state.links = pending
        state.header, state.nameAnchor = nil, nil -- Blizzard rebuilt the anchors and justification.
        state.healthTextApplied, state.generation = nil, nil
        state.nativeReset = true
    end
    local active = not forbidden and module.active
        and (not private.IsSkinSuppressed or not private.IsSkinSuppressed(uf))
    if locked then
        Defer(uf)
    elseif not active then
        Layout.Restore(uf)
        return
    end
    if active then
        local prefix = private.PlatePrefix(uf)
        if prefix then
            -- Blizzard can rebuild a recycled frame several times during SetUnit.
            -- OnAdded paints the settled frame once, after native setup.
            local unit = uf.unit
            if NS.Public(unit) and type(unit) == "string" and module.activeUnits[unit] == uf then
                Layout.Reapply(uf, prefix, module.config)
            end
        elseif not locked then
            return
        end
    end
    private.Extensions.OnAnchors(uf)
end

function Layout.Observe(uf)
    if hooked[uf] then return end
    hooksecurefunc(uf, "UpdateAnchors", OnAnchors)
    hooked[uf] = true
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

local function CastOffsets(state, uf, plan, setup, force, delta)
    local container = uf.CastBarsContainer
    local cast = container and container.castBar
    local customWidth = delta ~= 0
    local classic, inside = setup.useClassicCastBar == true, setup.spellNameInsideCastBar == true
    if customWidth and (not Accessible(container) or not Accessible(cast)
        or not classic and not inside and not Accessible(cast.Icon)) then
        Defer(uf)
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
    local castTime = module.castTimes[cast]
    Offset(state, castTime and castTime.label, time[1] - bar[1], time[2] - bar[2], force)
    Offset(state, cast.BorderShield, shield[1] - parent[1], shield[2] - parent[2], force)
    Offset(state, cast.CastTargetNameText, target[1] - bar[1], target[2] - bar[2], force)
    if not classic then
        Link(state, cast.CastTargetNameText, "LEFT", cast.Text, "RIGHT", 2, 0,
            text[1] - bar[1], text[2] - bar[2])
    end
    return true
end

-- The native level frames and the Suite's own level number. The badge is
-- evaluated once per layout pass: Blizzard's name anchor and the control
-- aura reservation below depend on it too.
local function LevelOffsets(state, uf, prefix, plan, setup, config, force)
    local level = plan.Level
    local classic = NS.Public(setup.useClassicHealthBar) and setup.useClassicHealthBar == true
    local namesOnly = private.HealthNameOnly(uf)
    namesOnly = NS.Public(namesOnly) and namesOnly == true
    local badgeShown = Geometry.LevelBadgeShown(uf, uf.unit)
    local mode = NS.NameplateStyle.LevelMode(NS.Client.isForever, classic, true,
        config[Key[prefix].LevelEnabled], config.levelAppearance, badgeShown, namesOnly)
    local classicLevel = mode == "classic"
    Offset(state, uf.LevelFrame, classicLevel and level[1] or 0, classicLevel and level[2] or 0, force)
    local moveBadge = badgeShown == true and mode == "badge"
    Offset(state, uf.PlayerLevelDiffFrame, moveBadge and level[1] or 0, moveBadge and level[2] or 0, force)
    local ownLevel = mode == "number"
    Offset(state, module.levelLabels[uf], ownLevel and level[1] or 0, ownLevel and level[2] or 0, force)
    return badgeShown
end

-- The name follows the health text when Blizzard anchors it there.
-- NamePlateConstants.NAME_ANCHOR_STYLES (Blizzard_NamePlateConstants.lua).
local INSIDE_BAR, ABOVE_BAR = 1, 2
local function NameLinkPoint(uf, setup, badgeShown)
    local anchor = setup.unitNameAnchorStyle
    if uf.showOnlyName == true or (anchor ~= INSIDE_BAR and anchor ~= ABOVE_BAR) then return end
    local inside = anchor == INSIDE_BAR
    local point, relative = inside and "RIGHT" or "BOTTOMRIGHT", inside and "LEFT" or "BOTTOMLEFT"
    if anchor == ABOVE_BAR and NS.Public(setup.nameJustificationWhenAboveHealthBar)
        and setup.nameJustificationWhenAboveHealthBar ~= nil then
        -- Camelot can anchor the name to its level frame before that
        -- frame becomes visible. Its endpoint is Blizzard-owned.
        if NS.Client.isForever and uf.PlayerLevelDiffFrame or badgeShown ~= false then
            point = nil
        else
            point, relative = "RIGHT", "LEFT"
        end
    end
    return point, relative
end

local function NameLink(state, uf, plan, setup, badgeShown)
    local health = uf.HealthBarsContainer and uf.HealthBarsContainer.healthBar
    if not health then return end
    local point, relative = NameLinkPoint(uf, setup, badgeShown)
    local value = plan.HealthText
    if point then Link(state, uf.name, point, health.Text, relative, -2, 0, value[1], value[2]) end
end

local CombatWritable = Geometry.CombatWritable

local function CombatCenter(state, uf, plan, config)
    if not NS.Public(uf.unit) or not uf.unit or module.activeUnits[uf.unit] ~= uf then return state end
    local anchor = state and state.nameAnchor
    local center = plan.centerName and Geometry.CenterEnabled(private.UnitKinds[uf] or X.UnitKind(uf, uf.unit), config)
    local wanted = center or plan.fitName and private.FriendlyNames.IsNameOnly(uf)
    if wanted and anchor and anchor.generation == generation and (anchor.centered == true) == (center == true)
        or not wanted and not (anchor and anchor.native) then return state end
    if not CombatWritable(uf) or not CombatWritable(uf.name) or not NS.Public(uf.showOnlyName) then return state end
    if anchor and not RestoreNameAnchor(state, uf) then return state end
    if wanted then
        state = state or { offsets = {}, links = {} }
        states[uf] = state
        local setup = NamePlateSetupOptions
        PlaceNativeName(state, uf, plan, setup, setup.healthBarHeight, Geometry.LevelBadgeShown(uf, uf.unit), center, state.nativeReset)
        Layout.Observe(uf)
    end
    return state
end

-- Native acquisition/rebuild can happen during lockdown. Place the ordinary
-- HP text on writable plates now so it matches plates laid out before combat.
-- The rest of the layout still uses the existing post-combat replay.
local function ApplyCombatHealthText(state, uf, prefix, plan, config)
    local x, y = plan.HealthText[1], plan.HealthText[2]
    if x == 0 and y == 0 or state and (state.healthTextApplied or state.header) then return end
    if not CombatWritable(uf) then return end
    local namesOnly, setup = private.HealthNameOnly(uf), NamePlateSetupOptions
    if not NS.Public(namesOnly) or namesOnly ~= false or not NS.Public(setup.unitNameAnchorStyle) then return end
    if prefix == "enemy" and NS.NameplateStyle.MirrorHeader(config.enemyMirrorHeader,
        config.enemyTextMode, setup.unitNameAnchorStyle, namesOnly) then return end

    local container = uf.HealthBarsContainer
    if not CombatWritable(container) then return end
    local health = container.healthBar
    if not CombatWritable(health) then return end
    local label = health.LeftText
    if not NS.Public(label) then return end
    label = label or health.Text
    if not CombatWritable(label) then return end

    local point, relative
    if not state or not state.nameAnchor then point, relative = NameLinkPoint(uf, setup) end
    if point then
        local name = uf.name
        -- PixelUtil snaps the compensating name anchor using this scale.
        if not CombatWritable(name) or not CombatWritable(health.Text)
            or not NS.Finite(name:GetEffectiveScale()) then return end
    end
    state = state or { offsets = {}, links = {} }
    states[uf] = state
    Offset(state, label, x, y, true)
    if point then Link(state, uf.name, point, health.Text, relative, -2, 0, x, y) end
    state.healthTextApplied = true
    Layout.Observe(uf)
end

-- upstream/forever 70009: UpdateAnchors reserves the badge width plus its
-- 5px XML gap before the control aura lists. Use the public setup width,
-- never measure restricted regions.
local function ControlAuraAnchors(state, uf, plan, setup, config, badgeShown)
    local control, container, auraFrame = plan.ControlAura, uf.HealthBarsContainer, uf.AurasFrame
    local baseX = 5
    if NS.Client.isForever then
        if badgeShown == nil then
            baseX = nil
        elseif badgeShown then
            local width = setup.playerLevelDiffWidth
            baseX = NS.Finite(width) and baseX + width + 5 or nil
        end
    end
    if not baseX then
        if control[1] ~= 0 or control[2] ~= 0 then Defer(uf) end
        return
    end
    local correction = config.barGeometry == Mode.SAME_GEOMETRY and baseX - 5 or 0
    local nativeFixed = not NS.Client.isForever
    AuraAnchor(state, uf, auraFrame and auraFrame.CrowdControlListFrame, "LEFT", container,
        "RIGHT", baseX, 0, control[1] - correction, control[2], nativeFixed)
    AuraAnchor(state, uf, auraFrame and auraFrame.LossOfControlFrame, "LEFT", container,
        "RIGHT", baseX, 0, control[1] - correction, control[2], nativeFixed)
end

-- The debuff and buff lists at their fixed native anchors.
local function AuraAnchors(state, uf, plan)
    local auras, auraFrame = plan.Auras, uf.AurasFrame
    AuraAnchor(state, uf, auraFrame and auraFrame.DebuffListFrame, "LEFT", uf.HealthBarsContainer, "LEFT",
        0, 0, auras[1], auras[2], NATIVE_FIXED)
    local buff = plan.Buffs
    AuraAnchor(state, uf, auraFrame and auraFrame.BuffListFrame, "RIGHT", uf.ClassificationFrame,
        "LEFT", -5, 0, buff[1], buff[2], NATIVE_FIXED)
end

-- The debuffs also follow the name or health bar through Blizzard's padding
-- CVar (GetCVarNumberOrDefault, Blizzard_SharedXMLBase/CvarUtil.lua).
local function DebuffPaddingAnchor(state, uf, plan, setup)
    local auras, name, anchor = plan.Auras, plan.Name, setup.unitNameAnchorStyle
    local debuffs = uf.AurasFrame and uf.AurasFrame.DebuffListFrame
    local centered = state.nameAnchor and state.nameAnchor.centered
    local debuffX = auras[1] - (anchor ~= 1 and not centered and name[1] or 0)
    local debuffY = auras[2] - (anchor ~= 1 and name[2] or 0)
    if not debuffs or (debuffX == 0 and debuffY == 0) then return end
    local padding = GetCVarNumberOrDefault(NamePlateConstants.DEBUFF_PADDING_CVAR)
    if NS.Finite(padding) then
        local health = uf.HealthBarsContainer and uf.HealthBarsContainer.healthBar
        AuraAnchor(state, uf, debuffs, "BOTTOM", anchor == 1 and health or uf.name, "TOP", 0, padding,
            debuffX, debuffY)
    else
        Defer(uf)
    end
end

local function ElementOffsets(state, uf, plan, force, anchored)
    local health = uf.HealthBarsContainer and uf.HealthBarsContainer.healthBar
    local name, value, raid = plan.Name, plan.HealthText, plan.RaidIcon
    local namesOnly = private.HealthNameOnly(uf) == true
    Offset(state, uf.HealthBarsContainer, plan.Health[1], plan.Health[2], force)
    if not anchored then Offset(state, uf.name, name[1], name[2], force) end
    local label = health and (health.LeftText or health.Text)
    Offset(state, label, value[1], value[2], force)
    state.healthTextApplied = state.offsets[label] ~= nil
    Offset(state, uf.SoftTargetFrame, plan.SoftTarget[1], plan.SoftTarget[2], force)
    local centered = state.nameAnchor and state.nameAnchor.centered
    Offset(state, uf.RaidTargetFrame, raid[1] - (namesOnly and not centered and name[1] or 0),
        raid[2] - (namesOnly and name[2] or 0), force)
    Offset(state, uf.ClassificationFrame and uf.ClassificationFrame.classificationIndicator,
        plan.Classification[1] - raid[1], plan.Classification[2] - raid[2], force)
end

local function AuraProperty(frame, saved, field, value, get, set, relative)
    local original, applied = saved[field], "applied" .. field
    if value == nil then
        if original then set(frame, original) end
        saved[field], saved[applied] = nil, nil
        return
    end
    if not original then
        original = get(frame)
        if not NS.Finite(original) then return end
        saved[field] = original
    end
    local result = relative and original + value or original * value
    if saved[applied] ~= result then
        set(frame, result)
        saved[applied] = result
    end
end

local function StyleAuraRow(state, uf, frame, style)
    if not frame then return end
    local previous = state.auraStyles and state.auraStyles[frame]
    if not style and not previous then return end
    if not AuraWritable(frame) then
        Defer(uf)
        return
    end
    if not previous then
        previous = {}
        state.auraStyles = state.auraStyles or {}
        state.auraStyles[frame] = previous
    end
    AuraProperty(frame, previous, "scale", style and style.scale, frame.GetScale, frame.SetScale)
    AuraProperty(frame, previous, "alpha", style and style.alpha, frame.GetAlpha, frame.SetAlpha)
    AuraProperty(frame, previous, "layer", style and style.layer, frame.GetFrameLevel, frame.SetFrameLevel, true)
    if not style then state.auraStyles[frame] = nil end
end

local function ApplyAuraStyles(state, uf, styles)
    local auras = uf.AurasFrame
    if not AuraWritable(auras) then
        Defer(uf)
        return
    end
    for _, row in ipairs(AuraModel.NativeRows) do
        local style = styles and styles[row.key]
        StyleAuraRow(state, uf, auras[row.frame], style)
        if row.playerFrame then StyleAuraRow(state, uf, auras[row.playerFrame], style) end
    end
    if state.auraStyles and not next(state.auraStyles) then state.auraStyles = nil end
end

-- Lays one plate out, once per settings generation (Layout.Configure).
-- force (Layout.Reapply) writes every offset again. true: the pass reached
-- the cast's geometry (see Settle), also when it stopped after that.
local function Lay(uf, prefix, config, force)
    local plan, state = plans[prefix], states[uf]
    local enabled = plan and plan.active and config.look ~= Mode.LOOK_BLIZZARD and config[prefix]
    if not enabled then
        if state then return Restore(uf) end
        return
    end
    local locked = NS.IsCombatLocked()
    if locked or NS.Safety.IsForbidden(uf) then
        if locked then
            if (plan.centerName or plan.fitName or state and state.nameAnchor and state.nameAnchor.native) and not NS.Safety.IsForbidden(uf) then
                state = CombatCenter(state, uf, plan, config)
            end
            ApplyCombatHealthText(state, uf, prefix, plan, config)
        end
        Defer(uf)
        return
    end
    local unitKind, kind
    if plan.centerName or plan.sizeByKind then unitKind = private.UnitKinds[uf] or X.UnitKind(uf, uf.unit) end
    if plan.sizeByKind and NS.Public(uf.unit) then kind = X.PlateKind(uf, uf.unit, unitKind) end
    if state and state.generation == generation and state.prefix == prefix and state.kind == kind and state.unitKind == unitKind and not force then return end
    local setup = NamePlateSetupOptions
    if not NS.Public(setup.useClassicCastBar) or not NS.Public(setup.spellNameInsideCastBar)
        or not NS.Public(setup.unitNameAnchorStyle) or not NS.Public(uf.showOnlyName) then return end
    state = state or { offsets = {}, links = {} }
    states[uf] = state
    force = force or state.nativeReset
    if state.nameAnchor and not RestoreNameAnchor(state, uf) then return end
    if not RestoreHeader(state, uf) then return end
    if state.links[1] then RestoreLinks(state, uf) end
    local wasUniform = state.geometry ~= nil and state.geometry.inset ~= nil
    local geometryChanged = (config.barGeometry == Mode.SAME_GEOMETRY) ~= wasUniform
    local keys = Key[prefix]
    local width, height = config[keys.HealthWidthDelta] or 0, config[keys.HealthHeightDelta] or 0
    if kind then width, height = X.HealthDimensions(config, prefix, kind) end
    local delta = plan.castWidth
    if plan.castWidthMode then
        delta = Geometry.CastWidthDelta(uf, setup, config, prefix, width)
        if delta == nil then
            Defer(uf)
            return
        end
    end
    state.castWidth = delta
    local baseHeight = Geometry.Apply(state, uf, setup, config, force, prefix, delta)
    if not baseHeight then
        Defer(uf)
        return true
    end
    HealthSize(state, uf, setup, width, height, force or geometryChanged, baseHeight)
    local badgeShown = LevelOffsets(state, uf, prefix, plan, setup, config, force)
    local anchored, centerPending
    if plan.centerName or plan.fitName or plan.nameAnchor then
        local center = plan.centerName and Geometry.CenterEnabled(unitKind, config)
        anchored, centerPending = AnchorName(state, uf, plan, center, setup, baseHeight, badgeShown)
    end
    ElementOffsets(state, uf, plan, force, anchored)
    if not anchored then
        local mirrored = MirrorHeader(state, uf, prefix, plan, setup, config)
        if mirrored == nil then return true end
        if not mirrored then NameLink(state, uf, plan, setup, badgeShown) end
    end
    AuraAnchors(state, uf, plan)
    ControlAuraAnchors(state, uf, plan, setup, config, badgeShown)
    DebuffPaddingAnchor(state, uf, plan, setup)
    if plan.auraStyles or state.auraStyles then ApplyAuraStyles(state, uf, plan.auraStyles) end
    if not CastOffsets(state, uf, plan, setup, force, delta) then return true end
    if (plan.castIconStyle or state.castIconStyle) and not Geometry.CastIconStyle(state, uf, plan) then
        Defer(uf)
        return true
    end
    state.generation, state.prefix, state.kind, state.unitKind = not centerPending and generation or nil, prefix, kind, unitKind
    state.nativeReset = nil
    Layout.Observe(uf)
    return true
end

local function Apply(uf, prefix, config, force)
    if Lay(uf, prefix, config, force) then Settle(uf) end
end
Layout.Apply = Apply

-- Lays the plate out again although its generation is current: Blizzard
-- rebuilt its anchors (UpdateAnchors).
function Layout.Reapply(uf, prefix, config)
    Apply(uf, prefix, config, true)
end

function Layout.InvalidateName(uf)
    local state = states[uf]
    if state then state.generation = nil end
end

function Layout.CastWidthDelta(uf, config, prefix)
    local state = states[uf]
    return state and state.castWidth or config[prefix .. "CastWidthDelta"] or 0
end

function Layout.Bind(owner) module = owner end

function Layout.RestoreAll()
    for uf in pairs(states) do Layout.Restore(uf) end
end

local function AuraStyles(config, prefix)
    local scope = AuraModel.Scope(prefix)
    local styles
    for _, row in ipairs(AuraModel.NativeRows) do
        local key = AuraModel.Prefix(scope, row)
        local scale, alpha, layer = config[key .. "Scale"] or 100, config[key .. "Alpha"] or 100, config[key .. "Layer"] or 0
        if scale ~= 100 or alpha ~= 100 or layer ~= 0 then
            styles = styles or {}
            styles[row.key] = { scale = scale ~= 100 and scale / 100 or nil,
                alpha = alpha ~= 100 and alpha / 100 or nil, layer = layer ~= 0 and layer or nil }
        end
    end
    return styles
end

function Layout.Configure(config)
    local shared = NS.NameplateText.Shared(config)
    local baseline = shared and shared.fontBaselineOffset or 0
    generation = generation + 1
    for _, prefix in ipairs({ "enemy", "friendly" }) do
        local auraStyles = AuraStyles(config, prefix)
        local anchor = NS.NameplateText.NameAnchor(config, prefix)
        local centerName = prefix == "enemy" and (config.enemyCenterName or config.neutralCenterName)
            or prefix == "friendly" and (config.friendlyCenterName or config.friendlyNpcCenterName
                or config.neutralCenterName and X.NeutralNameSplit(config))
        local fitName = private.FriendlyNames and (prefix == "enemy" and (config.enemyPlateNameOnly or config.neutralPlateNameOnly)
            or prefix == "friendly" and X.CustomNameOnly(config, "friendlyNpc"))
        local plan = { auraStyles = auraStyles, nameAnchor = anchor, centerName = centerName, fitName = fitName,
            sizeByKind = X and (prefix == "enemy" and config.neutralNpcSizeOverride or prefix == "friendly" and config.friendlyNpcSizeOverride),
            active = centerName or fitName or auraStyles ~= nil or anchor ~= nil or config.barGeometry == Mode.SAME_GEOMETRY
            or prefix == "enemy" and config.enemyMirrorHeader == true }
        for i = 1, #elements do
            local element = elements[i]
            local key = prefix .. element.key .. "Offset"
            local x, y = config[key .. "X"] or 0, config[key .. "Y"] or 0
            if element.key == "Name" or element.key == "HealthText" or element.key == "CastText"
                or element.key == "CastTime" or element.key == "CastTarget" then y = y + baseline end
            plan.active = plan.active or x ~= 0 or y ~= 0
            if element.section == "castbar" and element.key ~= "Cast" then
                x, y = x + (config[prefix .. "CastOffsetX"] or 0), y + (config[prefix .. "CastOffsetY"] or 0)
            end
            plan[element.key] = { x, y }
        end
        plan.castWidth = config[Key[prefix].CastWidthDelta] or 0
        plan.castWidthMode = (config[prefix .. "CastWidthMode"] or 1) ~= 1
        local zoom = config[prefix .. "CastIconZoom"] or 100
        plan.iconZoom = zoom > 100 and zoom or nil
        plan.iconBorder = config[prefix .. "CastIconBorder"] and (config[prefix .. "CastIconBorderSize"] or 1) or nil
        plan.iconBorderColor = config[prefix .. "CastIconBorderColor"] or "000000"
        plan.castIconStyle = plan.iconZoom or plan.iconBorder
        plans[prefix] = plan
        plan.active = plan.active or (config[prefix .. "HealthWidthDelta"] or 0) ~= 0
            or (config[prefix .. "HealthHeightDelta"] or 0) ~= 0
            or (prefix == "enemy" and config.neutralNpcSizeOverride or prefix == "friendly" and config.friendlyNpcSizeOverride)
            or plan.castIconStyle or plan.castWidthMode or plan.castWidth ~= 0 or (config[Key[prefix].CastHeight] or 0) > 0
            or (config[Key[prefix].CastIconSize] or 0) > 0
    end
end

local _, private = ...
local NS = private.NS
local Mode, Key = private.Mode, private.Key
local Layout = {}
private.Layout = Layout
local Geometry = private.Geometry
local Point, Offset, Link, Accessible = Geometry.Point, Geometry.Offset, Geometry.Link, Geometry.Accessible
local CastOffsets, Writable = Geometry.CastOffsets, Geometry.Writable
local states = setmetatable({}, { __mode = "k" })
local spareStates = setmetatable({}, { __mode = "k" })
local hooked = setmetatable({}, { __mode = "k" })
local plans, generation, module = {}, 0
local nameLimits = {}
local elements, X = NS.NameplateStyle.Elements, NS.NameplateExtensions
local AuraModel = NS.NameplateAuraDisplay

-- A write this plate could not make now: the end of combat applies the
-- plate again (Skin.lua OnCombatEnded).
local function Defer(uf)
    module.pendingPlates[uf] = true
end

local function AcquireState(uf)
    local state = spareStates[uf]
    if state then
        spareStates[uf] = nil
        return state
    end
    return { offsets = {}, links = {} }
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

local function MirrorHeader(state, uf, prefix, plan, setup, config, nameWidth)
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
        plan.Name[1], plan.Name[2], plan.HealthText[1], plan.HealthText[2], Point, nameWidth)
    name:SetJustifyH("RIGHT")
    return true
end

local function RestoreNameAnchor(state, uf)
    if Geometry.RestoreNameAnchor(state, uf) then return true end
    Defer(uf)
    return false
end

local function PlaceNativeName(state, uf, plan, setup, baseHeight, badgeShown, center, nativeReset, width)
    if Writable(uf.name) then
        local offset = width and state.offsets[uf.name]
        if offset then Offset(state, uf.name, 0, 0, true) end
        local anchor
        if center then
            local size = not nativeReset and state.healthSize
            local height = size and size[4] + size[2] or baseHeight
            local geometry = not nativeReset and state.geometry
            anchor = Geometry.CenterName(uf, setup, height, plan.Name[2], badgeShown, geometry, width)
        elseif plan.fitName and private.FriendlyNames.IsNameOnly(uf) then
            anchor = Geometry.FitNameOnly(uf, setup, plan.Name[1], plan.Name[2], badgeShown, plan.nameAnchor, width)
        elseif width then
            anchor = Geometry.LimitNativeName(uf, setup, badgeShown, plan, width)
        end
        if anchor then
            if not width then Offset(state, uf.name, 0, 0, true) end
            anchor.generation, anchor.width = generation, width
            state.nameAnchor = anchor
            return true
        end
        if offset then Offset(state, uf.name, offset[1], offset[2], true) end
    end
    Defer(uf)
    return nil, true
end

local function AnchorName(state, uf, plan, center, setup, height, badgeShown, width)
    if center or plan.fitName and private.FriendlyNames.IsNameOnly(uf) then
        return PlaceNativeName(state, uf, plan, setup, height, badgeShown, center, nil, width)
    elseif plan.nameAnchor then
        Offset(state, uf.name, 0, 0, true)
        return Geometry.ApplyNameAnchor(state, uf, plan, width)
    end
end

-- The cold-layout handoff. A pass that may write the cast's geometry (its
-- size in Geometry.Apply and Geometry.Restore, its anchors in CastOffsets)
-- returns true, and the entry point that ran the pass reports the plate once,
-- after its last write, so the castbar's spark is sized from the final
-- geometry (Textures.OnLayout). A pass that returns at its combat or
-- generation gate wrote nothing and returns nothing. The result belongs to
-- its call, including a guarded combat pass. Blizzard's own rebuild
-- is reported by Textures.OnAnchors.
local function Settle(uf)
    local textures = private.Textures
    if textures and textures.inUse then textures.OnLayout(uf) end
end

local function Restore(uf, recycled)
    local state = states[uf]
    if not state then return end
    if recycled then state.nameWidthGeneration = nil end
    if NS.IsCombatLocked() or NS.Safety.IsForbidden(uf) then
        Defer(uf)
        return
    end
    if recycled then
        -- ApplyFrameOptions and UpdateAnchors rebuild these sizes, anchors
        -- and justification before the pooled frame represents a new unit.
        state.geometry, state.healthSize = nil, nil
        Geometry.NativeAnchorsReset(state, uf)
    elseif not RestoreNameAnchor(state, uf) or not RestoreHeader(state, uf) then
        return true
    end
    state.nameWidthGeneration = nil
    RestoreLinks(state, uf, recycled)
    if not recycled then RestoreHealthSize(state, uf) end
    if state.auraStyles and not Geometry.RestoreAuraStyles(state) then Defer(uf) end
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
        and not state.iconZoom and not (state.auraStyles and next(state.auraStyles)) then
        local offsets, links, auraList = state.offsets, state.links, state.spareAuraStyles
        for key in pairs(state) do state[key] = nil end
        state.offsets, state.links, state.spareAuraStyles = offsets, links, auraList
        state.recycled = recycled
        states[uf], spareStates[uf] = nil, state
    end
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
    local spare = not state and spareStates[uf]
    if spare and spare.recycled and not locked and module.active then
        -- A completed native release has no layout to invalidate. SetUnit
        -- can rebuild the same frame three times before the next binding.
        local unit = uf.unit
        if NS.Public(unit) and type(unit) == "string" and module.activeUnits[unit] ~= uf then
            if not private.IsSkinSuppressed or not private.IsSkinSuppressed(uf) then private.Extensions.OnAnchors(uf) end
            return
        end
    end
    if state then
        -- UpdateAnchors rebuilds dynamic links, including Forever's CC
        -- badge reservation. Restore only fixed XML links before applying
        -- saved offsets again; rebuilt anchors belong to Blizzard.
        local links, retained = state.links, 0
        for _, link in ipairs(links) do
            if link.nativeFixed then
                if locked then
                    retained = retained + 1
                    links[retained] = link
                elseif Accessible(link[1]) then
                    Point(unpack(link))
                else
                    Defer(uf)
                end
            end
        end
        for index = retained + 1, #links do links[index] = nil end
        Geometry.NativeAnchorsReset(state, uf) -- Blizzard rebuilt the anchors and justification.
        state.nameWidthGeneration = nil
        state.healthTextApplied, state.generation = nil, nil
        state.nativeReset, state.combatCastApplied = true, nil
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

local function ConfiguredNameWidth(uf, limit, setup, config, badge, delta)
    if not limit then return end
    local override = uf.UpdateNameOverride
    if not NS.Public(override) or override then return end
    return Geometry.NameWidthWithinPlate(limit.pixels, uf, setup, config, badge, delta, limit.healthSize)
end

local function NativeNameLayout(state, uf, plan, config, castApplied, limit, locked)
    if not NS.Public(uf.unit) or not uf.unit or module.activeUnits[uf.unit] ~= uf then return state end
    local anchor = state and state.nameAnchor
    local center = plan.centerName and Geometry.CenterEnabled(private.UnitKinds[uf] or X.UnitKind(uf, uf.unit), config)
    local nameOnly = plan.fitName and private.FriendlyNames.IsNameOnly(uf)
    if locked and limit and not center and not nameOnly and plan.nameAnchor then return state end
    local setup = NamePlateSetupOptions
    local widthChanged = limit and (not state or state.nameWidthGeneration ~= generation)
    local wanted = center or nameOnly or limit
    if wanted and anchor and not widthChanged and not castApplied and anchor.generation == generation
        and (limit or not anchor.width) and (anchor.centered == true) == (center == true) then return state end
    if not wanted and not (anchor and anchor.native) then return state end
    if state and state.header and limit then return state end
    local writable = locked and CombatWritable or Writable
    if not NS.Public(uf.showOnlyName) or not NS.Public(setup.unitNameAnchorStyle)
        or not writable(uf) or not writable(uf.name) then
        Defer(uf)
        return state
    end
    if anchor and not RestoreNameAnchor(state, uf) then return state end
    state = state or AcquireState(uf)
    states[uf] = state
    local pending
    if wanted then
        local badge = Geometry.LevelBadgeShown(uf, uf.unit)
        local delta = state.healthSize and state.healthSize[1] or 0
        local width = ConfiguredNameWidth(uf, limit, setup, config, badge, delta)
        local castCurrent = state.combatCastApplied and not state.combatCastWriting
        local geometry = castCurrent and state.geometry
        if center or nameOnly or width then
            local _, deferred = PlaceNativeName(state, uf, plan, setup, geometry and geometry.healthHeight or setup.healthBarHeight,
                badge, center, state.nativeReset and not castCurrent, width)
            pending = deferred
            Layout.Observe(uf)
        end
    end
    state.nameWidthGeneration = generation
    state.nameWidthDeferred = pending or nil
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
    state = state or AcquireState(uf)
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

local function PlaceNameAndOffsets(state, uf, prefix, plan, setup, config, height, badge, center, width, force)
    local anchored, pending
    if plan.centerName or plan.fitName or plan.nameAnchor then
        anchored, pending = AnchorName(state, uf, plan, center, setup, height, badge, width)
    end
    if not anchored and width and not NS.NameplateStyle.MirrorHeader(config.enemyMirrorHeader,
        config.enemyTextMode, setup.unitNameAnchorStyle, uf.showOnlyName) then
        anchored, pending = PlaceNativeName(state, uf, plan, setup, height, badge, false, nil, width)
    end
    ElementOffsets(state, uf, plan, force, anchored)
    if not anchored then
        local mirrored = MirrorHeader(state, uf, prefix, plan, setup, config, width)
        if mirrored == nil then return end
        if not mirrored then NameLink(state, uf, plan, setup, badge) end
    end
    return true, pending
end

local function ApplyAuraStyles(state, uf, styles)
    state.auraPending = not Geometry.ApplyAuraStyles(state, uf, styles) or nil
    if state.auraPending then Defer(uf) end
end

local function BarDimensions(uf, setup, config, prefix, plan, kind)
    local width, height
    if kind then
        width, height = X.HealthDimensions(config, prefix, kind)
    else
        local keys = Key[prefix]
        width, height = config[keys.HealthWidthDelta] or 0, config[keys.HealthHeightDelta] or 0
    end
    local delta = plan.castWidth
    if plan.castWidthMode then delta = Geometry.CastWidthDelta(uf, setup, config, prefix, width) end
    return width, height, delta
end

-- Restore cast geometry after a cold acquisition or native rebuild in combat.
local function ApplyCombatCast(state, uf, prefix, plan, config)
    if not plan.castLayout or state and (state.combatCastWriting or state.combatCastApplied or state.prefix and not state.nativeReset) then return end
    local unit, setup = uf.unit, NamePlateSetupOptions
    if not NS.Public(unit) or type(unit) ~= "string" or module.activeUnits[unit] ~= uf then return end
    if not NS.Public(setup.useClassicCastBar) or not NS.Public(setup.useClassicHealthBar)
        or not NS.Public(setup.spellNameInsideCastBar) then return end
    local cast = Geometry.CombatCast(uf)
    if not cast then return end
    local castTime = module.castTimes[cast]
    local label = castTime and castTime.label
    if label and not CombatWritable(label) then return end
    local badge
    if NS.Client.isForever and config.barGeometry == Mode.SAME_GEOMETRY then
        badge = Geometry.LevelBadgeShown(uf, unit)
        if badge == nil or badge and (not NS.Finite(setup.playerLevelDiffWidth) or not Geometry.CombatControlAuras(uf)) then return end
    end
    local kind
    if plan.sizeByKind then kind = X.PlateKind(uf, unit, private.UnitKinds[uf] or X.UnitKind(uf, unit)) end
    local width, height, delta = BarDimensions(uf, setup, config, prefix, plan, kind)
    if delta == nil then return end
    state = state or AcquireState(uf)
    states[uf] = state
    state.combatCastApplied, state.combatCastWriting = true, true
    Layout.Observe(uf)
    local baseHeight = Geometry.Apply(state, uf, setup, config, true, prefix, delta)
    if baseHeight and state.combatCastApplied then
        HealthSize(state, uf, setup, width, height, true, baseHeight)
        if badge then ControlAuraAnchors(state, uf, plan, setup, config, badge) end
        if CastOffsets(state, uf, plan, setup, true, delta, module.castTimes) then state.castWidth = delta end
    elseif not baseHeight then
        state.combatCastApplied = nil
    end
    state.combatCastWriting = nil
    return baseHeight ~= nil
end

local function ApplyCombatLayout(state, uf, prefix, plan, config, limit)
    local castApplied = ApplyCombatCast(state, uf, prefix, plan, config)
    state = states[uf]
    local anchor = state and state.nameAnchor
    local widthChanged = limit and (not state or state.nameWidthGeneration ~= generation)
    if (plan.centerName or plan.fitName or widthChanged or anchor and anchor.native and (not anchor.width or castApplied or not limit))
        and not NS.Safety.IsForbidden(uf) then
        state = NativeNameLayout(state, uf, plan, config, castApplied, limit, true)
    end
    ApplyCombatHealthText(state, uf, prefix, plan, config)
    return castApplied
end

local function LimitNameOnly(state, uf, plan, config, limit, locked)
    if state and state.nameLimitOnly and state.nameWidthGeneration == generation then
        if not state.nameWidthDeferred or locked then return end
        state.nameWidthGeneration = nil
    end
    local restored
    if state and not state.nameLimitOnly then
        restored = Restore(uf)
        if states[uf] then return restored end
        state = nil
    end
    state = NativeNameLayout(state, uf, plan, config, false, limit, locked)
    if state then state.nameLimitOnly = true end
    return restored
end

local function Lay(uf, prefix, config, force)
    local plan, state = plans[prefix], states[uf]
    local limit = nameLimits[prefix]
    local enabled = plan and (plan.active or limit) and config.look ~= Mode.LOOK_BLIZZARD and config[prefix]
    if not enabled then
        if state then return Restore(uf) end
        return
    end
    local locked, forbidden = NS.IsCombatLocked(), NS.Safety.IsForbidden(uf)
    if not plan.active then
        if forbidden then
            Defer(uf)
            return
        end
        if force and state then state.nameWidthGeneration = nil end
        return LimitNameOnly(state, uf, plan, config, limit, locked)
    end
    if locked or forbidden then
        Defer(uf)
        if locked then return ApplyCombatLayout(state, uf, prefix, plan, config, limit) end
        return
    end
    local unitKind, kind
    if plan.centerName or plan.sizeByKind then unitKind = private.UnitKinds[uf] or X.UnitKind(uf, uf.unit) end
    if plan.sizeByKind and NS.Public(uf.unit) then kind = X.PlateKind(uf, uf.unit, unitKind) end
    if state and state.generation == generation and state.prefix == prefix and state.kind == kind and state.unitKind == unitKind and not force then
        if state.auraPending then ApplyAuraStyles(state, uf, plan.auraStyles) end
        return
    end
    local setup = NamePlateSetupOptions
    if not NS.Public(setup.useClassicCastBar) or not NS.Public(setup.spellNameInsideCastBar)
        or not NS.Public(setup.unitNameAnchorStyle) or not NS.Public(uf.showOnlyName) then return end
    state = state or AcquireState(uf)
    states[uf] = state
    state.nameLimitOnly = nil
    force = force or state.nativeReset
    if state.nameAnchor and not RestoreNameAnchor(state, uf) then return end
    if not RestoreHeader(state, uf) then return end
    if state.links[1] then RestoreLinks(state, uf) end
    local wasUniform = state.geometry ~= nil and state.geometry.inset ~= nil
    local geometryChanged = (config.barGeometry == Mode.SAME_GEOMETRY) ~= wasUniform
    local width, height, delta = BarDimensions(uf, setup, config, prefix, plan, kind)
    if delta == nil then
        Defer(uf)
        return
    end
    state.castWidth = delta
    local baseHeight = Geometry.Apply(state, uf, setup, config, force, prefix, delta)
    if not baseHeight then
        Defer(uf)
        return true
    end
    HealthSize(state, uf, setup, width, height, force or geometryChanged, baseHeight)
    local badgeShown = LevelOffsets(state, uf, prefix, plan, setup, config, force)
    local nameWidth = ConfiguredNameWidth(uf, limit, setup, config, badgeShown, width)
    local center = plan.centerName and Geometry.CenterEnabled(unitKind, config)
    local placed, namePending = PlaceNameAndOffsets(state, uf, prefix, plan, setup, config, baseHeight,
        badgeShown, center, nameWidth, force)
    if not placed then return true end
    state.nameWidthGeneration = generation
    AuraAnchors(state, uf, plan)
    ControlAuraAnchors(state, uf, plan, setup, config, badgeShown)
    DebuffPaddingAnchor(state, uf, plan, setup)
    if plan.auraStyles or state.auraStyles or state.auraPending then ApplyAuraStyles(state, uf, plan.auraStyles) end
    if not CastOffsets(state, uf, plan, setup, force, delta, module.castTimes)
        or (plan.castIconStyle or state.castIconStyle) and not Geometry.CastIconStyle(state, uf, plan) then
        Defer(uf)
        return true
    end
    state.generation, state.prefix, state.kind, state.unitKind = not namePending and generation or nil, prefix, kind, unitKind
    state.nativeReset, state.combatCastApplied = nil, nil
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

function Layout.NameLimits()
    nameLimits = private.NameText.limits or {}
    generation = generation + 1
end

function Layout.InvalidateName(uf)
    local state = states[uf]
    if state then state.generation, state.nameWidthGeneration = nil, nil end
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
            if element.section == "castbar" then
                plan.castLayout = plan.castLayout or x ~= 0 or y ~= 0
                if element.key ~= "Cast" then
                    x, y = x + (config[prefix .. "CastOffsetX"] or 0), y + (config[prefix .. "CastOffsetY"] or 0)
                end
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
        plan.castLayout = plan.castLayout or config.barGeometry == Mode.SAME_GEOMETRY
            or plan.castWidthMode or plan.castWidth ~= 0 or (config[Key[prefix].CastHeight] or 0) > 0
            or (config[Key[prefix].CastIconSize] or 0) > 0
        plans[prefix] = plan
        plan.active = plan.active or plan.castLayout or (config[prefix .. "HealthWidthDelta"] or 0) ~= 0
            or (config[prefix .. "HealthHeightDelta"] or 0) ~= 0
            or (prefix == "enemy" and config.neutralNpcSizeOverride or prefix == "friendly" and config.friendlyNpcSizeOverride)
            or plan.castIconStyle
    end
end

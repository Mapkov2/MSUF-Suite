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
local elements = NS.NameplateStyle.Elements

local function Accessible(region)
    return region and not NS.Safety.IsForbidden(region)
end

-- Restricted nameplate regions cannot be measured, even outside combat.
-- SetPointsOffset changes their displacement without reading/replacing native
-- anchors. We store only our own offsets, never GetPoint/GetRect results.
local function Offset(state, region, x, y, force)
    if not Accessible(region) then return end
    local old = state.offsets[region]
    if x == 0 and y == 0 and not old then return end
    if not force and old and old[1] == x and old[2] == y then return end
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
local function AuraAnchor(state, region, point, owner, relative, x, y, dx, dy, nativeFixed)
    if dx == 0 and dy == 0 then return end
    if not Accessible(region) or not owner then
        module.needsRefresh = true
        return
    end
    local link = { region, point, owner, relative, x, y }
    link.nativeFixed = nativeFixed
    state.links[#state.links + 1] = link
    Point(region, point, owner, relative, x + dx, y + dy)
end

local function RestoreLinks(state)
    for i = #state.links, 1, -1 do
        local link = state.links[i]
        if Accessible(link[1]) then
            Point(unpack(link))
            table.remove(state.links, i)
        else
            module.needsRefresh = true
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
        module.needsRefresh = true
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
        module.needsRefresh = true
        return
    end
    Point(container, "BOTTOMLEFT", cast, "TOPLEFT", 0, spacing)
    container:SetHeight(height)
    state.healthSize = nil
end

function Layout.Restore(uf)
    local state = states[uf]
    if not state then return end
    if NS.IsCombatLocked() or NS.Safety.IsForbidden(uf) then
        module.needsRefresh = true
        return
    end
    RestoreLinks(state)
    RestoreHealthSize(state, uf)
    if not Geometry.Restore(state, uf, NamePlateSetupOptions) then module.needsRefresh = true end
    for region in pairs(state.offsets) do
        if Accessible(region) then
            region:SetPointsOffset(0, 0)
            state.offsets[region] = nil
        else
            module.needsRefresh = true
        end
    end
    if not next(state.offsets) and #state.links == 0 and not state.healthSize and not state.geometry then states[uf] = nil end
end

local function OnAnchors(uf)
    local state = states[uf]
    local locked = NS.IsCombatLocked() or NS.Safety.IsForbidden(uf)
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
                    module.needsRefresh = true
                end
            end
        end
        state.links = pending
        state.generation = nil
        state.nativeReset = true
    end
    if locked then
        module.needsRefresh = true
        return
    end
    if not module.active then
        Layout.Restore(uf)
        return
    end
    if not NS.Public(uf.isFriend) then return end
    Layout.Reapply(uf, uf.isFriend and "friendly" or "enemy", module.config)
end

local function CastOffsets(state, uf, plan, setup, force)
    local cast = uf.CastBarsContainer and uf.CastBarsContainer.castBar
    if not cast then return end
    local bar, text, time, icon = plan.Cast, plan.CastText, plan.CastTime, plan.CastIcon
    local shield, target = plan.CastShield, plan.CastTarget
    local classic, inside = setup.useClassicCastBar == true, setup.spellNameInsideCastBar == true
    Offset(state, cast, bar[1], bar[2], force)
    Offset(state, cast.Border, classic and bar[1] or 0, classic and bar[2] or 0, force)
    if classic or inside then
        -- Classic's icon follows Border; Modern-inside follows the bar.
        Offset(state, cast.Icon, icon[1] - bar[1], icon[2] - bar[2], force)
    else
        Offset(state, cast.Icon, icon[1], icon[2], force)
        Link(state, cast, "BOTTOM", cast.Icon, "TOP", 0, 0, icon[1], icon[2])
    end
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
end

-- The native level frames and the Suite's own level number. The badge is
-- evaluated once per layout pass: Blizzard's name anchor and the control
-- aura reservation below depend on it too.
local function LevelOffsets(state, uf, prefix, plan, setup, config, force)
    local level = plan.Level
    local nativeLevel = setup.useClassicHealthBar == true
    if NS.Client.isForever then
        nativeLevel = config.levelAppearance == Mode.LEVEL_BADGE and config[Key[prefix].LevelEnabled]
    end
    local classicLevel = nativeLevel and setup.useClassicHealthBar == true and not NS.Client.isForever
    Offset(state, uf.LevelFrame, classicLevel and level[1] or 0, classicLevel and level[2] or 0, force)
    local badgeShown = Geometry.LevelBadgeShown(uf, uf.unit)
    local moveBadge = badgeShown == true
        and (NS.Client.isForever and nativeLevel or not NS.Client.isForever and not classicLevel)
    Offset(state, uf.PlayerLevelDiffFrame, moveBadge and level[1] or 0, moveBadge and level[2] or 0, force)
    local ownLevel = not nativeLevel and config[Key[prefix].LevelEnabled]
    Offset(state, module.levelLabels[uf], ownLevel and level[1] or 0, ownLevel and level[2] or 0, force)
    return badgeShown
end

-- The name follows the health text when Blizzard anchors it there.
-- NamePlateConstants.NAME_ANCHOR_STYLES (Blizzard_NamePlateConstants.lua).
local INSIDE_BAR, ABOVE_BAR = 1, 2
local function NameLink(state, uf, plan, setup, badgeShown)
    local health = uf.HealthBarsContainer and uf.HealthBarsContainer.healthBar
    local anchor = setup.unitNameAnchorStyle
    if not health or uf.showOnlyName == true or (anchor ~= INSIDE_BAR and anchor ~= ABOVE_BAR) then return end
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
    local value = plan.HealthText
    if point then Link(state, uf.name, point, health.Text, relative, -2, 0, value[1], value[2]) end
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
        if control[1] ~= 0 or control[2] ~= 0 then module.needsRefresh = true end
        return
    end
    local correction = config.barGeometry == Mode.SAME_GEOMETRY and baseX - 5 or 0
    local nativeFixed = not NS.Client.isForever
    AuraAnchor(state, auraFrame and auraFrame.CrowdControlListFrame, "LEFT", container,
        "RIGHT", baseX, 0, control[1] - correction, control[2], nativeFixed)
    AuraAnchor(state, auraFrame and auraFrame.LossOfControlFrame, "LEFT", container,
        "RIGHT", baseX, 0, control[1] - correction, control[2], nativeFixed)
end

-- The debuff and buff lists at their fixed native anchors.
local function AuraAnchors(state, uf, plan)
    local auras, auraFrame = plan.Auras, uf.AurasFrame
    AuraAnchor(state, auraFrame and auraFrame.DebuffListFrame, "LEFT", uf.HealthBarsContainer, "LEFT",
        0, 0, auras[1], auras[2], NATIVE_FIXED)
    local buff = plan.Buffs
    AuraAnchor(state, auraFrame and auraFrame.BuffListFrame, "RIGHT", uf.ClassificationFrame,
        "LEFT", -5, 0, buff[1], buff[2], NATIVE_FIXED)
end

-- The debuffs also follow the name or health bar through Blizzard's padding
-- CVar (GetCVarNumberOrDefault, Blizzard_SharedXMLBase/CvarUtil.lua).
local function DebuffPaddingAnchor(state, uf, plan, setup)
    local auras, name, anchor = plan.Auras, plan.Name, setup.unitNameAnchorStyle
    local debuffs = uf.AurasFrame and uf.AurasFrame.DebuffListFrame
    local debuffX = auras[1] - (anchor ~= 1 and name[1] or 0)
    local debuffY = auras[2] - (anchor ~= 1 and name[2] or 0)
    if not debuffs or (debuffX == 0 and debuffY == 0) then return end
    local padding = GetCVarNumberOrDefault(NamePlateConstants.DEBUFF_PADDING_CVAR)
    if NS.Finite(padding) then
        local health = uf.HealthBarsContainer and uf.HealthBarsContainer.healthBar
        AuraAnchor(state, debuffs, "BOTTOM", anchor == 1 and health or uf.name, "TOP", 0, padding, debuffX, debuffY)
    else
        module.needsRefresh = true
    end
end

local function ElementOffsets(state, uf, plan, force)
    local health = uf.HealthBarsContainer and uf.HealthBarsContainer.healthBar
    local name, value, raid = plan.Name, plan.HealthText, plan.RaidIcon
    local namesOnly = uf.showOnlyName == true
    Offset(state, uf.HealthBarsContainer, plan.Health[1], plan.Health[2], force)
    Offset(state, uf.name, name[1], name[2], force)
    Offset(state, health and (health.LeftText or health.Text), value[1], value[2], force)
    Offset(state, uf.SoftTargetFrame, plan.SoftTarget[1], plan.SoftTarget[2], force)
    Offset(state, uf.RaidTargetFrame, raid[1] - (namesOnly and name[1] or 0),
        raid[2] - (namesOnly and name[2] or 0), force)
    Offset(state, uf.ClassificationFrame and uf.ClassificationFrame.classificationIndicator,
        plan.Classification[1] - raid[1], plan.Classification[2] - raid[2], force)
end

-- Lays one plate out, once per settings generation (Layout.Configure).
-- force (Layout.Reapply) writes every offset again.
local function Apply(uf, prefix, config, force)
    local plan, state = plans[prefix], states[uf]
    local enabled = plan and plan.active and config.look ~= Mode.LOOK_BLIZZARD and config[prefix]
    if not enabled then
        if state then Layout.Restore(uf) end
        return
    end
    if NS.IsCombatLocked() or NS.Safety.IsForbidden(uf) then
        module.needsRefresh = true
        return
    end
    if state and state.generation == generation and state.prefix == prefix and not force then return end
    local setup = NamePlateSetupOptions
    if not NS.Public(setup.useClassicCastBar) or not NS.Public(setup.spellNameInsideCastBar)
        or not NS.Public(setup.unitNameAnchorStyle) or not NS.Public(uf.showOnlyName) then return end
    state = state or { offsets = {}, links = {} }
    states[uf] = state
    force = force or state.nativeReset
    RestoreLinks(state)
    local geometryChanged = (config.barGeometry == Mode.SAME_GEOMETRY) ~= (state.geometry ~= nil)
    local baseHeight = Geometry.Apply(state, uf, setup, config, force)
    if not baseHeight then
        module.needsRefresh = true
        return
    end
    local keys = Key[prefix]
    HealthSize(state, uf, setup, config[keys.HealthWidthDelta] or 0,
        config[keys.HealthHeightDelta] or 0, force or geometryChanged, baseHeight)
    ElementOffsets(state, uf, plan, force)
    local badgeShown = LevelOffsets(state, uf, prefix, plan, setup, config, force)
    NameLink(state, uf, plan, setup, badgeShown)
    AuraAnchors(state, uf, plan)
    ControlAuraAnchors(state, uf, plan, setup, config, badgeShown)
    DebuffPaddingAnchor(state, uf, plan, setup)
    CastOffsets(state, uf, plan, setup, force)
    state.generation, state.prefix = generation, prefix
    state.nativeReset = nil
    if not hooked[uf] then
        hooksecurefunc(uf, "UpdateAnchors", OnAnchors)
        hooked[uf] = true
    end
end
Layout.Apply = Apply

-- Lays the plate out again although its generation is current: Blizzard
-- rebuilt its anchors (UpdateAnchors).
function Layout.Reapply(uf, prefix, config)
    Apply(uf, prefix, config, true)
end

function Layout.Bind(owner) module = owner end

function Layout.RestoreAll()
    for uf in pairs(states) do Layout.Restore(uf) end
end

function Layout.Configure(config)
    generation = generation + 1
    for _, prefix in ipairs({ "enemy", "friendly" }) do
        local plan = { active = config.barGeometry == Mode.SAME_GEOMETRY }
        for i = 1, #elements do
            local element = elements[i]
            local key = prefix .. element.key .. "Offset"
            local x, y = config[key .. "X"] or 0, config[key .. "Y"] or 0
            plan.active = plan.active or x ~= 0 or y ~= 0
            if element.section == "castbar" and element.key ~= "Cast" then
                x, y = x + (config[prefix .. "CastOffsetX"] or 0), y + (config[prefix .. "CastOffsetY"] or 0)
            end
            plan[element.key] = { x, y }
        end
        plans[prefix] = plan
        plan.active = plan.active or (config[prefix .. "HealthWidthDelta"] or 0) ~= 0
            or (config[prefix .. "HealthHeightDelta"] or 0) ~= 0
    end
end

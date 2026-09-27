local _, private = ...
local NS = private.NS
local Layout = {}
private.Layout = Layout
local states = setmetatable({}, { __mode = "k" })
local hooked = setmetatable({}, { __mode = "k" })
local plans, generation, module = {}, 0
local elements = NS.NameplateStyle.Elements

local function Accessible(region)
    return region and not NS.Safety.IsForbidden(region) and type(region.SetPointsOffset) == "function"
end

local function Point(region, point, owner, relative, x, y)
    if PixelUtil and PixelUtil.SetPoint then
        PixelUtil.SetPoint(region, point, owner, relative, x, y)
    else
        region:SetPoint(point, owner, relative, x, y)
    end
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

function Layout.Restore(uf)
    local state = states[uf]
    if not state then return end
    if NS.IsCombatLocked() or NS.Safety.IsForbidden(uf) then module.needsRefresh = true; return end
    RestoreLinks(state)
    for region in pairs(state.offsets) do
        if Accessible(region) then
            region:SetPointsOffset(0, 0)
            state.offsets[region] = nil
        else
            module.needsRefresh = true
        end
    end
    if not next(state.offsets) and #state.links == 0 then states[uf] = nil end
end

local function OnAnchors(uf)
    local state = states[uf]
    if state then
        -- Blizzard has just rebuilt these links. Old style anchors must not
        -- be restored over its new ones (Modern/Classic/names-only changes).
        state.links = {}
        state.generation = nil
        state.nativeReset = true
    end
    if not module.active then Layout.Restore(uf); return end
    if NS.Safety.IsForbidden(uf) or not NS.Public(uf.isFriend) then return end
    Layout.Apply(uf, uf.isFriend and "friendly" or "enemy", module.config, true)
end

local function CastOffsets(state, uf, plan, setup, force)
    local cast = uf.CastBarsContainer and uf.CastBarsContainer.castBar
    if not cast then return end
    local bar, text, icon = plan.Cast, plan.CastText, plan.CastIcon
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
    Offset(state, cast.BorderShield, shield[1] - parent[1], shield[2] - parent[2], force)
    Offset(state, cast.CastTargetNameText, target[1] - bar[1], target[2] - bar[2], force)
    if not classic then
        Link(state, cast.CastTargetNameText, "LEFT", cast.Text, "RIGHT", 2, 0,
            text[1] - bar[1], text[2] - bar[2])
    end
end

function Layout.Apply(uf, prefix, config, force)
    local plan, state = plans[prefix], states[uf]
    local enabled = plan and plan.active and config.look ~= 2 and config[prefix]
    if not enabled then if state then Layout.Restore(uf) end; return end
    if NS.IsCombatLocked() or NS.Safety.IsForbidden(uf) then module.needsRefresh = true; return end
    if state and state.generation == generation and state.prefix == prefix and not force then return end
    local setup = _G.NamePlateSetupOptions
    if not setup or not NS.Public(setup.useClassicCastBar) or not NS.Public(setup.spellNameInsideCastBar)
        or not NS.Public(setup.unitNameAnchorStyle) or not NS.Public(uf.showOnlyName) then return end
    state = state or { offsets = {}, links = {} }
    states[uf] = state
    force = force or state.nativeReset
    RestoreLinks(state)
    local health = uf.HealthBarsContainer and uf.HealthBarsContainer.healthBar
    local name, value, auras, raid, classification = plan.Name, plan.HealthText, plan.Auras, plan.RaidIcon, plan.Classification
    local namesOnly, anchor = uf.showOnlyName == true, setup.unitNameAnchorStyle
    Offset(state, uf.name, name[1], name[2], force)
    Offset(state, health and (health.LeftText or health.Text), value[1], value[2], force)
    if health and not namesOnly and (anchor == 1 or anchor == 2) then
        local point, relative = anchor == 1 and "RIGHT" or "BOTTOMRIGHT", anchor == 1 and "LEFT" or "BOTTOMLEFT"
        if anchor == 2 and NS.Public(setup.nameJustificationWhenAboveHealthBar)
            and setup.nameJustificationWhenAboveHealthBar ~= nil then
            -- Forever's above-bar name has a RIGHT link and can end at the
            -- level frame instead. Preserve that dynamic link while shown;
            -- its anchor/width cannot be measured by addon code either.
            local level = uf.PlayerLevelDiffFrame
            local shown = level and level:IsShown()
            if not NS.Public(shown) or shown then point = nil
            else point, relative = "RIGHT", "LEFT" end
        end
        if point then Link(state, uf.name, point, health.Text, relative, -2, 0, value[1], value[2]) end
    end
    local debuffs = uf.AurasFrame and uf.AurasFrame.DebuffListFrame
    Offset(state, debuffs, auras[1], auras[2], force)
    if debuffs and anchor ~= 1 and (name[1] ~= 0 or name[2] ~= 0) then
        local key = _G.NamePlateConstants and NamePlateConstants.DEBUFF_PADDING_CVAR
        local padding = key and CVarCallbackRegistry and CVarCallbackRegistry:GetCVarNumberOrDefault(key)
        if NS.Finite(padding) then
            Link(state, debuffs, "BOTTOM", uf.name, "TOP", 0, padding, name[1], name[2])
        end
    end
    Offset(state, uf.RaidTargetFrame, raid[1] - (namesOnly and name[1] or 0),
        raid[2] - (namesOnly and name[2] or 0), force)
    Offset(state, uf.ClassificationFrame and uf.ClassificationFrame.classificationIndicator,
        classification[1] - raid[1], classification[2] - raid[2], force)
    CastOffsets(state, uf, plan, setup, force)
    state.generation, state.prefix = generation, prefix
    state.nativeReset = nil
    if not hooked[uf] and type(uf.UpdateAnchors) == "function" then
        hooksecurefunc(uf, "UpdateAnchors", OnAnchors)
        hooked[uf] = true
    end
end

function Layout.Bind(owner) module = owner end

function Layout.RestoreAll()
    for uf in pairs(states) do Layout.Restore(uf) end
end

function Layout.Configure(config)
    generation = generation + 1
    for _, prefix in ipairs({ "enemy", "friendly" }) do
        local plan = { active = false }
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
    end
end

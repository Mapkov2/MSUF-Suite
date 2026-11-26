local _, private = ...
local NS, S = private.NS, private.Suite
local Layout = private.ExtensionLayout
local Markers = {}
private.UnitMarkers = Markers

local actions = { hide = 1, icon = 2, dim = 3 }
local arenaUnits = { "arena1", "arena2", "arena3", "arena4", "arena5" }
local unitIcon = "Interface\\Icons\\INV_Misc_Head_Murloc_01"
local sightingLimit, sightings, sightingOrder, cursor = 128, {}, {}, 0
local objectiveArt = {
    FlagCarrierAlliance = "nameplates-icon-flag-alliance",
    FlagCarrierHorde = "nameplates-icon-flag-horde",
    FlagCarrierNeutral = "nameplates-icon-flag-neutral",
    OrbCarrierBlue = "nameplates-icon-orb-blue",
    OrbCarrierGreen = "nameplates-icon-orb-green",
    OrbCarrierOrange = "nameplates-icon-orb-orange",
    OrbCarrierPurple = "nameplates-icon-orb-purple",
}
local objectiveByClassification = {}
for key, atlas in pairs(objectiveArt) do
    local classification = Enum and Enum.PvPUnitClassification and Enum.PvPUnitClassification[key]
    if classification then objectiveByClassification[classification] = atlas end
end

local function Text(value)
    return NS.Public(value) and type(value) == "string" and value ~= "" and value or nil
end

local function RuleList(rules, source, action)
    if not Text(source) then return end
    for element in source:gmatch("[^,\r\n]+") do
        local value = element:match("^%s*(.-)%s*$")
        local id = value:match("^%d+$") and tonumber(value)
        if id and id > 0 then
            rules.ids[id] = rules.ids[id] or action
        elseif value ~= "" and not id then
            local key = value:lower()
            rules.names[key] = rules.names[key] or action
        end
    end
end

local function TotemList(source)
    local totems = {}
    local spellAPI = C_Spell
    if not spellAPI then return totems end
    local defaults = NS.Client.isForever and "8177, 8143, 2484" or "204336, 8143, 192058, 51485"
    for element in (Text(source) or defaults):gmatch("[^,\r\n]+") do
        local id, seconds = element:match("^%s*(%d+)%s*:%s*(%d+)%s*$")
        id = tonumber(id or element:match("^%s*(%d+)%s*$"))
        if S.Finite(id) and id > 0 and id < 2147483648 then
            local name = Text(spellAPI.GetSpellName(id))
            local icon = spellAPI.GetSpellTexture(id)
            if name and NS.Public(icon) and icon then
                local duration = tonumber(seconds)
                totems[name:lower()] = { id = id, icon = icon, seconds = duration and math.min(duration, 600) or nil }
            end
        end
    end
    return totems
end

function Markers.Compile(config)
    local hide, dim, icon = Text(config.nameplateNpcHideList), Text(config.nameplateNpcDimList), Text(config.nameplateNpcIconList)
    local pvp = config.nameplateArenaNumbers == true or config.nameplateArenaSpecs == true
    local group, objectives = config.nameplateGroupPointer == true, config.nameplateObjectives == true
    local useTotems = config.nameplateTotemIcons == true
    if not hide and not dim and not icon and not pvp and not group and not objectives and not useTotems then return end
    local rules = { ids = {}, names = {} }
    RuleList(rules, hide, actions.hide)
    RuleList(rules, icon, actions.icon)
    RuleList(rules, dim, actions.dim)
    local npcs = next(rules.ids) ~= nil or next(rules.names) ~= nil
    local totems = useTotems and TotemList(config.nameplateTotemList)
    return {
        arena = pvp, arenaNumber = config.nameplateArenaNumbers == true, arenaSpec = config.nameplateArenaSpecs == true,
        group = group, objectives = objectives, npcs = npcs, rules = rules, totems = totems,
        totemOnly = config.nameplateTotemIconOnly == true, labels = {}, size = config.nameplateMarkerSize or 18,
        y = config.nameplateMarkerY or 4, dim = (config.nameplateNpcDimOpacity or 30) / 100,
    }
end

function Markers.Context(plan)
    local _, kind = IsInInstance()
    local arena, battle = NS.Public(kind) and kind == "arena", NS.Public(kind) and kind == "pvp"
    local changed = arena ~= plan.inArena or battle ~= plan.inBattle
    plan.inArena, plan.inBattle = arena, battle
    if not plan.arena or not arena then return changed end
    local specAPI = GetArenaOpponentSpec or (C_PvP and C_PvP.GetArenaOpponentSpec)
    for i = 1, #arenaUnits do
        local text = plan.arenaNumber and tostring(i) or nil
        if plan.arenaSpec and specAPI and GetSpecializationInfoByID then
            local id = specAPI(i)
            if NS.Public(id) and S.Finite(id) and id > 0 then
                local _, name = GetSpecializationInfoByID(id)
                name = Text(name)
                if name then
                    local abbreviation = NS.NameplatePortableText.Format({}, name, "CUT", 4, false, "RIGHT")
                    text = text and (text .. " " .. abbreviation) or abbreviation
                end
            end
        end
        plan.labels[i] = text
    end
    return changed
end

local function NPCID(guid)
    if not guid then return end
    local category, id = guid:match("^([^-]+)%-[^-]+%-[^-]+%-[^-]+%-[^-]+%-(%d+)%-[^-]+$")
    if category == "Creature" or category == "Pet" or category == "Vehicle" then return tonumber(id) end
end

local function FirstSighting(state, guid, totem)
    if not totem or not totem.seconds or totem.seconds <= 0 then return end
    local current = state.totemGUID == guid and state.totemID == totem.id and state.totemStart
    if not guid then return current or GetTime() end
    local cached = sightings[guid]
    if cached then return current or cached end
    cursor = cursor % sightingLimit + 1
    local old = sightingOrder[cursor]
    if old then sightings[old] = nil end
    local start = current or GetTime()
    sightingOrder[cursor], sightings[guid] = guid, start
    return start
end

local function NPCFacts(state, plan)
    if state.markerPlan == plan then return end
    local byID, byName = plan.rules.ids, plan.rules.names
    local unit = state.unit
    local name = (next(byName) or plan.totems) and Text(UnitName(unit)) or nil
    local key = name and name:lower()
    local totem = key and plan.totems and plan.totems[key]
    if totem then
        local owned = UnitIsOwnerOrControllerOfUnit("player", unit)
        if not NS.Public(owned) or owned ~= false then totem = nil end
    end
    local guid = (next(byID) or totem and totem.seconds) and Text(UnitGUID(unit))
    local id = guid and next(byID) and NPCID(guid)
    local named, numbered = key and byName[key], id and byID[id]
    state.markerRule = named and numbered and math.min(named, numbered) or named or numbered
    state.totemStart = FirstSighting(state, guid, totem)
    state.totemID, state.totemGUID, state.totemRule, state.markerPlan = totem and totem.id, totem and guid, totem, plan
end

function Markers.Invalidate(state)
    state.markerPlan = nil
end

local function NewMarker(uf, parent)
    local frame = CreateFrame("Frame", nil, parent)
    frame:SetSize(1, 1)
    local level = uf:GetFrameLevel()
    if S.Finite(level) then frame:SetFrameLevel(level + 5) end
    return { frame = frame, parent = parent, labels = {} }
end

local function Glyph(marker, key, x, height)
    local label = marker.labels[key]
    if not label then
        label = marker.frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        label:SetSize(64, 20)
        label:SetPoint("BOTTOM", marker.frame, "TOP", x, 0)
        marker.labels[key] = label
    end
    marker.textHeights = marker.textHeights or {}
    if marker.textHeights[key] ~= height then
        label:SetTextHeight(height)
        marker.textHeights[key] = height
    end
    return label
end

local function Image(marker, key, x)
    local texture = marker[key]
    if not texture then
        texture = marker.frame:CreateTexture(nil, "OVERLAY")
        texture:SetPoint("BOTTOM", marker.frame, "TOP", x, 0)
        marker[key] = texture
    end
    return texture
end

local function GroupPointer(state, marker, show, size)
    if not show then
        if marker.labels.group then marker.labels.group:Hide() end
        return
    end
    local label = Glyph(marker, "group", 0, size)
    local _, token = UnitClass(state.unit)
    local color = Text(token) and RAID_CLASS_COLORS and RAID_CLASS_COLORS[token]
    if color then label:SetTextColor(color.r, color.g, color.b) else label:SetTextColor(1, 1, 1) end
    label:SetText("▼")
    label:Show()
end

local function ArenaLabels(state, marker, plan, show)
    for i, token in ipairs(arenaUnits) do
        local text = show and plan.labels[i]
        local match = text and UnitIsUnit(state.unit, token)
        local restricted = NS.IsSecret(match)
        if text and (restricted or match == true) then
            local label = Glyph(marker, i, 0, plan.size)
            label:SetText(text)
            if restricted then label:SetAlphaFromBoolean(match, 1, 0) else label:SetAlpha(1) end
            label:Show()
        elseif marker.labels[i] then
            marker.labels[i]:Hide()
        end
    end
end

local function ObjectiveAtlas(state, plan)
    if not plan.objectives or not plan.inBattle then return end
    local classification = UnitPvpClassification(state.unit)
    if not S.Finite(classification) then return end
    local native = state.uf.ClassificationFrame
    if native and not NS.Safety.IsForbidden(native) then
        local shown = native:IsShown()
        if not NS.Public(shown) or shown then return end
    end
    return objectiveByClassification[classification]
end

local function TotemTimer(marker, rule, start)
    local seconds = rule and rule.seconds
    if marker.timerStart == start and marker.timerDuration == seconds then return end
    marker.timerStart, marker.timerDuration = start, seconds
    if not start or not seconds or seconds <= 0 or GetTime() >= start + seconds then
        if marker.cooldown then marker.cooldown:Hide() end
        return
    end
    if not marker.cooldown then
        local cooldown = CreateFrame("Cooldown", nil, marker.frame, "CooldownFrameTemplate")
        cooldown:SetAllPoints(marker.icon)
        cooldown:SetDrawEdge(false)
        marker.cooldown = cooldown
    end
    marker.cooldown:SetCooldown(start, seconds)
    marker.cooldown:Show()
end

local function Icon(marker, texture, totem, size, start)
    if marker.iconTexture == texture and marker.iconTotem == totem and marker.iconSize == size then
        TotemTimer(marker, totem, start)
        return
    end
    marker.iconTexture, marker.iconTotem, marker.iconSize = texture, totem, size
    if not texture then
        if marker.icon then marker.icon:Hide() end
        if marker.glow then marker.glow:Hide() end
    else
        local image = Image(marker, "icon", 0)
        image:SetSize(size, size)
        image:SetTexture(texture)
        image:Show()
        if totem then
            local glow = marker.glow or marker.frame:CreateTexture(nil, "BACKGROUND")
            marker.glow = glow
            glow:SetPoint("CENTER", image, "CENTER")
            glow:SetSize(size + 15, size + 15)
            glow:SetTexture("Interface\\Buttons\\UI-ActionButton-Border")
            glow:SetBlendMode("ADD")
            glow:Show()
        elseif marker.glow then
            marker.glow:Hide()
        end
    end
    TotemTimer(marker, totem, start)
end

local function GroupMember(unit)
    local party = UnitInParty(unit)
    if NS.Public(party) and party == true then return true end
    local index = UnitInRaid(unit)
    return S.Finite(index) and index > 0
end

local function UnitVisuals(state, plan, player)
    if player then
        state.markerOpacity = nil
        return
    end
    NPCFacts(state, plan)
    local rule, totem = state.markerRule, state.totemRule
    if not rule and not totem then
        state.markerOpacity = nil
        return
    end
    local identity = C_Secrets and C_Secrets.ShouldUnitIdentityBeSecret
    if identity then
        local restricted = identity(state.unit)
        if not NS.Public(restricted) or restricted == true then
            state.markerOpacity = nil
            return
        end
    end
    local selected = UnitIsUnit(state.unit, "target")
    local canFade = NS.Public(selected) and selected == false
    local replace = canFade and (rule == actions.icon or totem and plan.totemOnly)
    local hide = canFade and rule == actions.hide
    state.markerOpacity = (hide or replace) and 0 or (canFade and rule == actions.dim and plan.dim) or nil
    if hide then return end
    return totem, replace
end

function Markers.Paint(state, plan)
    if not plan then
        if state.markerOpacity then state.markerOpacity = nil end
        if Layout.Mutable(state, state.uf) then Markers.Release(state) end
        return
    end
    if not Layout.Mutable(state, state.uf) then return end
    if state.visible == false then
        Markers.Release(state)
        return
    end
    state.markersActive = true
    local player = state.kind == "friendlyPlayer" or state.kind == "enemyPlayer"
    local totem, replace = UnitVisuals(state, plan, player)
    local parent = state.uf
    if replace then
        local plate = state.plate
        if NS.Public(plate) and plate and Layout.Mutable(state, plate) then
            parent = plate
        else
            replace, state.markerOpacity = nil, nil
        end
    end
    local group = player and state.prefix == "friendly" and plan.group and GroupMember(state.unit)
    local arena = player and state.prefix == "enemy" and plan.arena and plan.inArena
    local atlas = player and ObjectiveAtlas(state, plan)
    local marker = state.unitMarker
    if not group and not arena and not atlas and not totem and not replace then
        if marker then marker.frame:Hide() end
        return
    end
    marker = marker or NewMarker(state.uf, parent)
    state.unitMarker = marker
    -- The replacement is a sibling of the hidden unit frame. It still
    -- inherits the native nameplate's distance and occlusion fading.
    if marker.parent ~= parent then
        marker.frame:SetParent(parent)
        marker.parent, marker.y = parent, nil
    end
    if marker.y ~= plan.y then
        marker.frame:ClearAllPoints()
        local label = state.uf.name
        local anchor = NS.Public(label) and label and not NS.Safety.IsForbidden(label) and label or state.uf
        marker.frame:SetPoint("BOTTOM", anchor, "TOP", 0, plan.y)
        marker.y = plan.y
    end
    GroupPointer(state, marker, group, plan.size)
    if arena or marker.arena then ArenaLabels(state, marker, plan, arena) end
    marker.arena = arena
    if atlas then
        local indicator = Image(marker, "objective", 20)
        indicator:SetSize(plan.size, plan.size)
        indicator:SetAtlas(atlas)
        indicator:Show()
    elseif marker.objective then
        marker.objective:Hide()
    end
    Icon(marker, totem and totem.icon or replace and unitIcon, totem, plan.size, state.totemStart)
    marker.frame:Show()
end

function Markers.Extend(plan, config)
    if config.look == private.Mode.LOOK_BLIZZARD then return end
    local markers = Markers.Compile(config)
    if not markers then return end
    plan.markers = markers
    plan.enabled, plan.questTextOnly = true, false
    Markers.Context(markers)
end

function Markers.Refresh(plan, event, unit, states, activeUnits, restores, paint)
    if not plan then return end
    if event == "UNIT_CLASSIFICATION_CHANGED" then
        local state = unit and states[activeUnits[unit]]
        if state and not restores[state] and not NS.Safety.IsForbidden(state.uf) then paint(state) end
        return
    end
    Markers.Context(plan)
    for _, state in pairs(states) do
        if state.unit and not restores[state] and not NS.Safety.IsForbidden(state.uf) then paint(state) end
    end
end

function Markers.NameChanged(state, restores, paint)
    if not state or restores[state] or NS.Safety.IsForbidden(state.uf) then return end
    Markers.Invalidate(state)
    paint(state)
end

function Markers.Events(subscribe, refresh, plan, units)
    subscribe("UNIT_CLASSIFICATION_CHANGED", refresh, plan and plan.objectives, units)
    subscribe("GROUP_ROSTER_UPDATE", refresh, plan and plan.group)
    subscribe("ARENA_OPPONENT_UPDATE", refresh, plan and plan.arena)
    subscribe("ARENA_PREP_OPPONENT_SPECIALIZATIONS", refresh, plan and plan.arena)
end

function Markers.Release(state)
    local marker = state.unitMarker
    if marker then
        marker.frame:Hide()
        if marker.cooldown then marker.cooldown:Hide() end
        marker.timerStart, marker.timerDuration, marker.iconSize = nil, nil, nil
    end
    state.markersActive, state.markerPlan, state.markerRule, state.totemRule, state.markerOpacity = nil, nil, nil, nil, nil
    state.totemID, state.totemGUID, state.totemStart = nil, nil, nil
end

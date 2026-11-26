local _, P = ...
local NS, S = P.NS, P.Suite
local T = {}
P.ExtensionText = T
local X = NS.NameplateExtensions
local SOURCES = { target = 2, quest = 3, guild = 4, title = X.NPCTitleSource,
    threat = 6, difference = 7, power = 8, absorb = 9, forces = 10 }
-- A tooltip data instance belongs to a particular plate binding. Several
-- plate bindings may refer to the same data, and the native ID may be nil.
local questStates, tooltipIDs, tooltipGroups = {}, {}, {}
local missingText, spareGroup = {}
local sparseContext, flushSparse, sparseQueued, RetryUnidentified
local sparseDelay = .5
T.pendingMetadata = {}
local QUEST_ONLY = { [SOURCES.quest] = true }
local TITLE_ONLY = { [SOURCES.title] = true }
local QUEST_AND_TITLE = { [SOURCES.quest] = true, [SOURCES.title] = true }
local DEFAULT_QUEST_SLOT = { source = SOURCES.quest, anchor = 1, x = 0, y = 2, size = 10, color = "ffffff" }
local ANCHORS = X.TextPoints
local EVENT_SOURCES = {
    TOOLTIP_DATA_UPDATE = { [3] = true, [SOURCES.title] = true },
    UNIT_TARGET = { [2] = true, [6] = true, [7] = true },
    UNIT_NAME_UPDATE = { [2] = true, [3] = true, [4] = true, [SOURCES.title] = true, [10] = true },
    UNIT_THREAT_LIST_UPDATE = { [6] = true, [7] = true },
    UNIT_THREAT_SITUATION_UPDATE = { [6] = true, [7] = true },
    UNIT_POWER_UPDATE = { [8] = true },
    UNIT_MAXPOWER = { [8] = true },
    UNIT_DISPLAYPOWER = { [8] = true },
    UNIT_ABSORB_AMOUNT_CHANGED = { [9] = true },
}

function T.Configure(scopes)
    for _, scope in pairs(scopes) do
        local routes = {}
        for event, sources in pairs(EVENT_SOURCES) do
            local slots
            for _, slot in ipairs(scope.slots) do
                if sources[slot.source] then
                    slots = slots or {}
                    slots[#slots + 1] = slot
                end
            end
            routes[event] = slots
        end
        scope.textRoutes = routes
    end
end

local function PublicTable(value)
    return not NS.IsSecret(value) and type(value) == "table" and canaccesstable(value)
end

local function PublicText(value)
    if not NS.IsSecret(value) and type(value) == "string" and value ~= "" then return value end
end

local function IdentityAllowed(unit)
    local restricted = C_Secrets.ShouldUnitIdentityBeSecret(unit)
    return not NS.IsSecret(restricted) and restricted == false
end

local function NPC(kind)
    return kind == "enemyNpc" or kind == "friendlyNpc" or kind == "neutralNpc"
end

-- Keep sparse delivery proportional to the subscribers for its ID. Each
-- group also covers two displayed units sharing the same native data.
local function WatchTooltip(state, id, data, missing)
    -- Blizzard keeps info.tooltipData alive while testing its instance ID.
    -- Follow the same lifetime for this binding, including a recycled ID.
    state.tooltipData = data
    missingText[state] = missing or nil
    local previous = tooltipIDs[state]
    if previous == id then return end
    if previous then
        local group = tooltipGroups[previous]
        group[state] = nil
        if not next(group) then
            tooltipGroups[previous] = nil
            spareGroup = group
            if previous == true then
                if sparseQueued then sparseContext:Cancel(RetryUnidentified) end
                sparseQueued, sparseDelay = false, .5
            end
        end
    end
    tooltipIDs[state] = id
    if id then
        local group = tooltipGroups[id]
        if not group then
            group, spareGroup = spareGroup or {}, nil
            tooltipGroups[id] = group
        end
        group[state] = true
    end
end

-- Both clients tag objective/level/type lines. The untyped line immediately
-- after an NPC's UnitName is its native subtitle, when one is present.
-- Blizzard keeps NPC identity secret even in the open world (an innkeeper's
-- line 2 is secret text there). The title still goes to its label, unread:
-- FontString:SetText takes secret text. Quests need public text, and PvP
-- instances are not read.
local function Tooltip(state, values, sources)
    local quest, title = sources[SOURCES.quest], sources[SOURCES.title] and NPC(state.kind)
    if state.visible == false and (quest or title) then
        if not state.tooltipSuspended then T.Unwatch(state, true) end
        return
    end
    state.tooltipSuspended = nil
    questStates[state] = quest or nil
    if not quest and not title then
        WatchTooltip(state, nil)
        return
    end
    values.quest, values.title = nil, nil
    local identity, roles = IdentityAllowed(state.unit), P.Roles
    local related = quest and identity and roles.Quest(state.unit)
    if not related and (not title or not identity and roles.inInstance and not roles.instanced) then
        WatchTooltip(state, false)
        return
    end
    local info = C_TooltipInfo.GetUnit(state.unit)
    local public = PublicTable(info)
    local id = public and info.dataInstanceID
    local lines = public and info.lines
    local readable = PublicTable(lines)
    local owner = S.Finite(id) and id or nil
    if not readable then
        WatchTooltip(state, owner or true, public and info or nil, true)
        return
    end
    local types, ours, player = Enum.TooltipDataLineType, true, nil
    local first, last = related and 1 or 2, related and 40 or 2
    for i = first, math.min(#lines, last) do
        local row = lines[i]
        if PublicTable(row) and not NS.IsSecret(row.type) then
            if related and row.type == types.QuestTitle then ours = true
            elseif related and row.type == types.QuestPlayer then
                player = player or PublicText(UnitName("player"))
                ours = player ~= nil and PublicText(row.leftText) == player
            elseif related and ours and row.type == types.QuestObjective and not values.quest then
                if P.Roles.QuestObjectiveIncomplete(row.leftText) then values.quest = PublicText(row.leftText) end
            elseif title and i == 2 and row.type == types.None then
                local text = row.leftText
                if NS.IsSecret(text) then values.title = text else values.title = PublicText(text) end
            end
        end
    end
    local missing = title and not NS.IsSecret(values.title) and values.title == nil or related and values.quest == nil
    -- An ordinary typed second line is a complete tooltip without a subtitle.
    local second = lines[2]
    local unknown = missing and (related or not PublicTable(second) or NS.IsSecret(second.type) or second.type == types.None)
    WatchTooltip(state, owner or unknown or false, (owner or unknown) and info or nil, missing)
end

local function QueueGroup(group)
    if not group or not next(group) then return false end
    for state in pairs(group) do T.pendingMetadata[state] = true end
    return true
end

function T.QueueQuests()
    return QueueGroup(questStates)
end

-- A lookup with no usable ID cannot be matched to an individual sparse
-- delivery. Retry only after an event and back off when the ID stays absent.
RetryUnidentified = function()
    sparseQueued = false
    if sparseContext and QueueGroup(tooltipGroups[true]) then
        flushSparse()
        if tooltipGroups[true] then sparseDelay = math.min(8, sparseDelay * 2) end
    end
end

function T.ConfigureSparse(context, flush)
    if not context and sparseQueued then sparseContext:Cancel(RetryUnidentified) end
    sparseContext, flushSparse = context, flush
    if not context then sparseQueued, sparseDelay = false, .5 end
end

function T.QueueTooltips(id)
    if NS.IsSecret(id) or id ~= nil and not S.Finite(id) then return QueueGroup(missingText) end
    if id == nil then return QueueGroup(tooltipIDs) end
    local matched = QueueGroup(tooltipGroups[id])
    if sparseContext and tooltipGroups[true] and not sparseQueued then
        sparseQueued = true
        sparseContext:After(sparseDelay, RetryUnidentified)
    end
    return matched
end

function T.QueueUnit(state)
    if state and (tooltipIDs[state] ~= nil or questStates[state]) then
        T.pendingMetadata[state] = true
        return true
    end
end

local function Metadata(state)
    local values, sources = state.textValues, state.interaction.sources
    Tooltip(state, values, sources)
    if sources[4] then
        values.guild = IdentityAllowed(state.unit) and PublicText(GetGuildInfo(state.unit)) or nil
    end
    if sources[10] then
        values.forces = nil
        local active = C_ChallengeMode.IsChallengeModeActive()
        if not NS.IsSecret(active) and active == true and NS.NameplateExtensions.Capability("forces")
            and state.kind == "enemyNpc" then
            local actual, percent = C_ScenarioInfo.GetUnitCriteriaProgressValues(state.unit)
            if S.Finite(actual) and S.Finite(percent) and actual > 0 and percent > 0 and percent <= 100 then
                values.forces = percent
            end
        end
    end
    state.metadataReady = true
end

local function Target(state)
    local values, unit = state.textValues, state.unit .. "target"
    local exists = UnitExists(unit)
    values.target = nil
    if not NS.IsSecret(exists) and exists == true then values.target = UnitName(unit) end
end

local function Threat(state)
    local values, unit = state.textValues, state.unit
    local _, _, scaled, _, amount = UnitDetailedThreatSituation("player", unit)
    values.threat, values.difference = scaled, nil
    if not state.interaction.sources[7] or not S.Finite(amount) then return end
    local tanking, _, _, _, tankAmount = UnitDetailedThreatSituation(unit .. "target", unit)
    if not NS.IsSecret(tanking) and tanking == true and S.Finite(tankAmount) then
        values.difference = amount - tankAmount
    end
end

local function Read(state, event)
    local sources, values = state.interaction.sources, state.textValues
    local changed = EVENT_SOURCES[event] or sources
    if event == "TOOLTIP_DATA_UPDATE" then
        Tooltip(state, values, sources)
    elseif not state.metadataReady then
        Metadata(state)
    end
    if sources[2] and changed[2] then Target(state) end
    if (sources[6] and changed[6]) or (sources[7] and changed[7]) then Threat(state) end
    if sources[8] and changed[8] then
        values.power, values.maximum = UnitPower(state.unit), UnitPowerMax(state.unit)
    end
    if sources[9] and changed[9] then values.absorb = UnitGetTotalAbsorbs(state.unit) end
end

local FORMATS = { [6] = "%.0f%%", [7] = "%+.0f", [9] = "%.0f", [10] = "+%.2f%%" }
local KEYS = {}
for key, source in pairs(SOURCES) do KEYS[source] = key end

local function Write(label, slot, values)
    local source = slot.source
    local value = values[KEYS[source]]
    if source == 8 then
        local maximum = values.maximum
        if NS.IsSecret(value) or NS.IsSecret(maximum) or S.Finite(value) and S.Finite(maximum) then
            label:SetFormattedText("%s / %s", value, maximum)
            label:Show()
            return
        end
    elseif NS.IsSecret(value) then
        if FORMATS[source] then label:SetFormattedText(FORMATS[source], value) else label:SetText(value) end
        label:Show()
        return
    elseif PublicText(value) or S.Finite(value) then
        if FORMATS[source] then label:SetFormattedText(FORMATS[source], value) else label:SetText(value) end
        label:Show()
        return
    end
    label:SetText(slot.unknown and "?" or "")
    label:SetShown(slot.unknown)
end

local function Place(label, slot, state, anchor)
    anchor = anchor or ANCHORS[slot.anchor]
    local owner = anchor[2] == "name" and state.uf.name or state.health
    label:ClearAllPoints()
    P.Geometry.Point(label, anchor[1], owner, anchor[3], anchor[4] + slot.x, anchor[5] + slot.y)
    local style = P.Text.styles[state.prefix]
    S.SetFont(label, style and style.font or S.GlobalFontPath(), slot.size, "OUTLINE")
    label:SetTextColor(S.RGB(slot.color))
end

local function CreateLabel(state, slot)
    local owner = state.uf
    if slot.layer then
        owner = CreateFrame("Frame", nil, state.uf)
        owner:SetAllPoints(state.uf)
        state.threatTextFrame = owner
    end
    local label = owner:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    state.labels[slot.source] = label
    if state.layerFade then P.ExtensionLayout.FadeText(state, label) end
    return label
end

local function PaintNameOnlyText(state, slot, changed, anchor)
    local label = state.labels[slot.source]
    if not label then
        local value = state.textValues[KEYS[slot.source]]
        if not NS.IsSecret(value) and not value and not slot.unknown then return end
        label = CreateLabel(state, slot)
        changed = true
    end
    if changed then Place(label, slot, state, anchor) end
    Write(label, slot, state.textValues)
end

local function ApplyNameOnly(state, quest, title, event)
    local sources = quest and (title and QUEST_AND_TITLE or QUEST_ONLY) or TITLE_ONLY
    local changed = state.textPlan ~= sources or state.questSlot ~= quest or state.titleSlot ~= title
    if not changed and state.metadataReady and event ~= "TOOLTIP_DATA_UPDATE" then return end
    state.textValues, state.labels = state.textValues or {}, state.labels or {}
    if changed then T.Hide(state) end
    Tooltip(state, state.textValues, sources)
    if quest then PaintNameOnlyText(state, quest, changed) end
    if title then PaintNameOnlyText(state, title, changed, X.NPCSubtitlePoint) end
    state.metadataReady, state.textPlan, state.questSlot, state.titleSlot = true, sources, quest, title
end

function T.Apply(state, event)
    local scope = state.interaction
    local names = P.FriendlyNames
    local wasNameOnly = state.questSlot or state.titleSlot
    if names and names.IsNameOnly(state.uf) then
        local quest = names.KeepsQuestText and names.KeepsQuestText(state.uf)
            and (state.plan.interaction.neutral.questSlot or DEFAULT_QUEST_SLOT)
        local title = scope and scope.titleSlot and NPC(state.kind) and scope.titleSlot
        if quest or title then return ApplyNameOnly(state, quest, title, event) end
        if state.textPlan then T.Invalidate(state) end
        T.Hide(state)
        return
    end
    if wasNameOnly then T.Invalidate(state) end
    if not scope or #scope.slots == 0 then
        T.Hide(state)
        return
    end
    state.textValues, state.labels = state.textValues or {}, state.labels or {}
    local changed = state.textPlan ~= scope
    if changed then T.Hide(state) end
    local slots = scope.slots
    if event and not changed and (state.metadataReady or event == "UNIT_NAME_UPDATE") then
        slots = scope.textRoutes[event]
        if not slots then return end
    else
        event = nil
    end
    Read(state, event)
    for _, slot in ipairs(slots) do
        local label = state.labels[slot.source] or CreateLabel(state, slot)
        if changed then
            Place(label, slot, state)
            if slot.layer then
                local level = state.uf:GetFrameLevel()
                if S.Finite(level) then state.threatTextFrame:SetFrameLevel(level + slot.layer) end
            end
        end
        Write(label, slot, state.textValues)
    end
    state.textPlan = scope
end

function T.Unwatch(state, suspended)
    state.tooltipSuspended = suspended
    if not suspended then state.metadataReady = nil end
    WatchTooltip(state, nil)
    questStates[state], T.pendingMetadata[state] = nil, nil
end

function T.SuspendTooltip(state)
    if tooltipIDs[state] ~= nil or questStates[state] then T.Unwatch(state, true) end
end

function T.Hide(state)
    T.Unwatch(state)
    if state.labels then for _, label in pairs(state.labels) do label:Hide() end end
end

function T.Invalidate(state)
    T.Unwatch(state)
    state.metadataReady, state.textPlan, state.questSlot, state.titleSlot = nil, nil, nil, nil
    if state.textValues then for key in pairs(state.textValues) do state.textValues[key] = nil end end
end

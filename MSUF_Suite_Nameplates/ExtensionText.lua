local _, P = ...
local NS, S = P.NS, P.Suite
local T = {}
P.ExtensionText = T
local SOURCES = { target = 2, quest = 3, guild = 4, title = 5, threat = 6, difference = 7, power = 8, absorb = 9, forces = 10 }
local ANCHORS = {
    { "BOTTOM", "name", "TOP", 0, 2 }, { "TOP", "health", "BOTTOM", 0, -2 },
    { "CENTER", "health", "CENTER", 0, 0 }, { "RIGHT", "health", "LEFT", -4, 0 },
    { "LEFT", "health", "RIGHT", 4, 0 },
}

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

-- Both clients tag objective/level/type lines. The untyped line immediately
-- after an NPC's UnitName is its native subtitle, when one is present.
local function Tooltip(state, values, sources)
    if not sources[3] and not sources[5] then return end
    values.quest, values.title = nil, nil
    if not IdentityAllowed(state.unit) then return end
    local related = sources[3] and P.Roles.Quest(state.unit)
    if not related and not sources[5] then return end
    local info = C_TooltipInfo.GetUnit(state.unit)
    if not PublicTable(info) or not PublicTable(info.lines) then return end
    local types, ours, player = Enum.TooltipDataLineType, true, PublicText(UnitName("player"))
    for i = 1, math.min(#info.lines, 40) do
        local row = info.lines[i]
        if PublicTable(row) and not NS.IsSecret(row.type) then
            if related and row.type == types.QuestTitle then ours = true
            elseif related and row.type == types.QuestPlayer then
                ours = player ~= nil and PublicText(row.leftText) == player
            elseif related and ours and row.type == types.QuestObjective and not values.quest then
                if P.Roles.QuestObjectiveIncomplete(row.leftText) then values.quest = PublicText(row.leftText) end
            elseif sources[5] and i == 2 and (state.kind == "enemyNpc" or state.kind == "friendlyNpc") then
                if row.type == types.None then values.title = PublicText(row.leftText) end
            end
        end
    end
end

local function Metadata(state)
    local values, sources = state.textValues, state.plan.sources
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
    if not state.plan.sources[7] or not S.Finite(amount) then return end
    local tanking, _, _, _, tankAmount = UnitDetailedThreatSituation(unit .. "target", unit)
    if not NS.IsSecret(tanking) and tanking == true and S.Finite(tankAmount) then
        values.difference = amount - tankAmount
    end
end

local function Read(state, event)
    local sources, values, all = state.plan.sources, state.textValues, event == nil
    if not state.metadataReady then Metadata(state) end
    if sources[2] and (all or event == "UNIT_TARGET" or event == "UNIT_NAME_UPDATE") then Target(state) end
    if (sources[6] or sources[7]) and (all or event == "UNIT_THREAT_LIST_UPDATE" or event == "UNIT_THREAT_SITUATION_UPDATE"
        or event == "UNIT_TARGET") then Threat(state) end
    if sources[8] and (all or event == "UNIT_POWER_UPDATE" or event == "UNIT_MAXPOWER" or event == "UNIT_DISPLAYPOWER") then
        values.power, values.maximum = UnitPower(state.unit), UnitPowerMax(state.unit)
    end
    if sources[9] and (all or event == "UNIT_ABSORB_AMOUNT_CHANGED") then values.absorb = UnitGetTotalAbsorbs(state.unit) end
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

local function Eligible(slot, state)
    return slot.side == 1 or slot.side == 2 and state.prefix == "enemy" or slot.side == 3 and state.prefix == "friendly"
end

local function Place(label, slot, state)
    local anchor = ANCHORS[slot.anchor]
    local owner = anchor[2] == "name" and state.uf.name or state.health
    label:ClearAllPoints()
    P.Geometry.Point(label, anchor[1], owner, anchor[3], anchor[4] + slot.x, anchor[5] + slot.y)
    local style = P.Text.styles[state.prefix]
    S.SetFont(label, style and style.font or S.GlobalFontPath(), slot.size, "OUTLINE")
    label:SetTextColor(S.RGB(slot.color))
end

function T.Apply(state, event)
    local slots = state.plan.slots
    if #slots == 0 then
        T.Hide(state)
        return
    end
    state.textValues, state.labels = state.textValues or {}, state.labels or {}
    Read(state, event)
    for _, slot in ipairs(slots) do
        local label = state.labels[slot.index]
        if Eligible(slot, state) then
            if not label then
                label = state.uf:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
                state.labels[slot.index] = label
            end
            if state.textPlan ~= state.plan then Place(label, slot, state) end
            Write(label, slot, state.textValues)
        elseif label then
            label:Hide()
        end
    end
    -- Slots removed by a settings edit must not retain their previous text.
    for index, label in pairs(state.labels) do
        local enabled = false
        for _, slot in ipairs(slots) do if slot.index == index then enabled = true break end end
        if not enabled then label:Hide() end
    end
    state.textPlan = state.plan
end

function T.Hide(state)
    if state.labels then for _, label in pairs(state.labels) do label:Hide() end end
end

function T.Invalidate(state)
    state.metadataReady, state.textPlan = nil, nil
    if state.textValues then for key in pairs(state.textValues) do state.textValues[key] = nil end end
end

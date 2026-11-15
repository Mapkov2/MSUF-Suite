local _, private = ...
local NS = private.NS
local Filter = {}
private.AuraFilter = Filter

local function Accessible(frame)
    if not NS.Public(frame) or not frame or NS.Safety.IsForbidden(frame) then return false end
    local allowed = frame:CanBeAccessedInContext()
    return NS.Public(allowed) and allowed == true
end

local function Visible(button)
    if not Accessible(button) then return false end
    local shown = button:IsVisible()
    return NS.Public(shown) and shown == true
end

local function CanMatchSource(filter, lane)
    local mine = lane.requireSourceIsLocalPlayer
    return not filter:find("|PLAYER|", 1, true) or NS.Public(mine) and mine == true
end

local function PublicTable(value)
    return NS.Public(value) and type(value) == "table" and canaccesstable(value)
end

-- Blizzard exposes frames, not their assignments. Only claim IDs when the
-- public candidates fit and the exact number of replacements is visible.
local function ConfirmedIDs(record, key, filter, candidate, visible)
    local result = record.dedup[key]
    if result ~= nil then return result end
    record.dedup[key] = false
    if visible == 0 then return false end
    local auras = record.auras[filter]
    if auras == nil then
        local fetched = C_UnitAuras.GetUnitAuras(record.unit, filter)
        auras = PublicTable(fetched) and fetched or false
        record.auras[filter] = auras
    end
    if not auras then return false end
    local ids, count = {}, 0
    for _, aura in ipairs(auras) do
        if not PublicTable(aura) then return false end
        local id = aura.spellId
        if not NS.Finite(id) then return false end
        if candidate.includeSpellIDs[id] and not (record.excluded and record.excluded[id]) then
            local duration, maxDuration = aura.duration, candidate.maxDuration
            if maxDuration and not NS.Finite(duration) then return false end
            if not maxDuration or duration > 0 and duration <= maxDuration then
                count = count + 1
                if count > visible then return false end
                ids[id] = ids[id] == nil
            end
        end
    end
    if count ~= visible then return false end
    record.dedup[key] = ids
    return ids
end

local function Fixed(record, id, lane)
    if not Accessible(record.frame) or type(record.frame.GetAuraSlotFrame) ~= "function" then return false end
    for index, row in ipairs(record.c.rows) do
        local ids = row.candidate.includeSpellIDs
        if ids[id] and not (record.excluded and record.excluded[id]) and CanMatchSource(row.filter, lane) then
            if not Visible(record.frame:GetAuraSlotFrame(record.slots[index].key)) then return false end
            if next(ids) == id and not next(ids, id) then return true end
            local confirmed = ConfirmedIDs(record, index, row.filter, row.candidate, 1)
            return confirmed and confirmed[id]
        end
    end
    return false
end

local function PackedIDs(record, group, filter, candidate)
    local result = record.dedup[group]
    if result ~= nil then return result end
    local frame = record.frame
    if not Accessible(frame) or type(frame.GetAuraGroupFrameCount) ~= "function" then return false end
    local owned = frame:GetAuraGroupFrameCount(group)
    if not NS.Finite(owned) or owned == 0 then return false end
    local visible = 0
    for index = 1, owned do
        if Visible(frame:GetAuraGroupFrame(group, index)) then visible = visible + 1 end
    end
    return ConfirmedIDs(record, group, filter, candidate, visible)
end

local function Packed(record, id, lane)
    local c = record.c
    if c.groupCount > 0 and c.candidate.includeSpellIDs[id] and CanMatchSource(c.filter, lane) then
        local ids = PackedIDs(record, "auras", c.filter, c.candidate)
        return ids and ids[id]
    end
    if c.anyCount > 0 and c.anyCandidate.includeSpellIDs[id] then
        local ids = PackedIDs(record, "any", c.anyFilter, c.anyCandidate)
        return ids and ids[id]
    end
end

function Filter.Visible(state)
    return state.visible and Visible(state.wrapper)
end

function Filter.Match(state, helpful, id, lane)
    for _, record in pairs(state.sides[state.side].records) do
        local c = record.c
        if record.shown and c.hideDuplicates and c.helpful == helpful and c.alpha > 0 then
            if c.fixed then
                if Fixed(record, id, lane) then return true end
            elseif Packed(record, id, lane) then
                return true
            end
        end
    end
    return false
end

function Filter.End(state)
    for _, record in pairs(state.sides[state.side].records) do
        if record.dedup then
            wipe(record.dedup)
            wipe(record.auras)
        end
    end
end

local _, P = ...
local NS, S = P.NS, P.Suite
if NS.Client.isForever then return end

-- Observed enemy forces of the current pull: living, attackable enemies in
-- combat that the player sees as a nameplate or target, each counted once
-- by its GUID with Blizzard's per-unit criteria value (live 12.1.0 build
-- 69875+). In a keystone only the party fights, so combat itself marks the
-- pull. A mob's value never changes during a run: it is read once per GUID.
-- A unit without criteria progress (a boss, an add that does not count)
-- adds nothing; a secret value hides the sum, as identities may be secret
-- when the client restricts them. Unit events coalesce into one paint per
-- PAINT_DELAY seconds.
local H = {}
local Public, Finite, Text = S.Public, S.Finite, S.PublicText
local PAINT_DELAY = .25
local EVENTS = { "NAME_PLATE_UNIT_ADDED", "NAME_PLATE_UNIT_REMOVED", "PLAYER_TARGET_CHANGED",
    "UNIT_THREAT_LIST_UPDATE", "UNIT_FLAGS", "PLAYER_REGEN_ENABLED", "PLAYER_REGEN_DISABLED" }
local NAMEPLATES = {}
local TOKENS = { target = true }
for i = 1, 60 do
    NAMEPLATES[i] = "nameplate" .. i
    TOKENS[NAMEPLATES[i]] = true
end
local LABEL_TOTAL = S.Text("Observed enemies  +%.1f%%  (total %.1f%%)")
local LABEL_SUM = S.Text("Observed enemies  +%.1f%%")
local LABEL_UNKNOWN = S.Text("Observed enemies  --")

-- The share of one unit: its percent and GUID, 0 when it adds nothing, or
-- nil while a value is secret.
local function Share(state, unit)
    local exists = UnitExists(unit)
    if not Public(exists) then return nil end
    if not exists then return 0 end
    local dead, attack, combat = UnitIsDeadOrGhost(unit), UnitCanAttack("player", unit), UnitAffectingCombat(unit)
    if not Public(dead) or not Public(attack) or not Public(combat) then return nil end
    if dead or not attack or not combat then return 0 end
    local guid = UnitGUID(unit)
    if not Public(guid) then return nil end
    if not Text(guid) then return 0 end
    local cached = state.percent[guid]
    if cached then return cached, guid end
    local actual, percent = C_ScenarioInfo.GetUnitCriteriaProgressValues(unit)
    if not Public(actual) or not Public(percent) then return nil end
    -- The API may return nothing: the unit does not count.
    if percent == nil then return 0, guid end
    if not Finite(actual) or actual < 0 or not Finite(percent) or percent < 0 or percent > 100 then return nil end
    state.percent[guid] = percent
    return percent, guid
end

local function Paint(owner)
    local state, view = owner.observedPull, owner.mplus
    if not state or not view or not view.observedPull then return end
    local seen, sum, unknown = state.seen, 0, false
    for guid in pairs(seen) do seen[guid] = nil end
    for unit in pairs(state.units) do
        local share, guid = Share(state, unit)
        if share == nil then
            unknown = true
            break
        end
        if guid and not seen[guid] then
            seen[guid] = true
            sum = sum + share
        end
    end
    state.sum = not unknown and sum or nil
    local label
    if unknown then
        label = LABEL_UNKNOWN
    elseif Finite(view.forcesPercent) then
        label = LABEL_TOTAL:format(sum, view.forcesPercent + sum)
    else
        label = LABEL_SUM:format(sum)
    end
    local line = view.observedPull
    if line.cachedText ~= label then
        line:SetText(label)
        line.cachedText = label
    end
end

-- One timer per PAINT_DELAY, whatever the number of unit events. A timer
-- from before Stop belongs to an older generation and paints nothing.
local function Queue(state)
    if state.queued then return end
    state.queued, state.queuedGeneration = true, state.generation
    C_Timer.After(PAINT_DELAY, state.flush)
end

local function Snapshot(state)
    local units = state.units
    for unit in pairs(units) do units[unit] = nil end
    units.target = true
    for i = 1, #NAMEPLATES do
        local unit = NAMEPLATES[i]
        local exists = UnitExists(unit)
        if Public(exists) and exists == true then units[unit] = true end
    end
end

local function Event(owner, event, unit)
    local state = owner.observedPull
    if event == "PLAYER_REGEN_ENABLED" or event == "PLAYER_REGEN_DISABLED" then
        -- Player combat can end while the party still fights. Re-read current
        -- unit combat state instead of declaring the party pull empty.
        Snapshot(state)
    elseif event == "PLAYER_TARGET_CHANGED" then
        state.units.target = true
    elseif not Public(unit) or not TOKENS[unit] then
        return
    elseif event == "NAME_PLATE_UNIT_REMOVED" then
        state.units[unit] = nil
    elseif event == "NAME_PLATE_UNIT_ADDED" then
        state.units[unit] = true
    end
    Queue(state)
end

local function OnEvent(frame, event, unit)
    Event(frame.owner, event, unit)
end

local function NewState(owner)
    local state = { frame = S.CreateFrame("Frame"), units = {}, seen = {}, percent = {}, generation = 0 }
    state.frame.owner = owner
    state.frame:SetScript("OnEvent", OnEvent)
    state.flush = function()
        if state.queuedGeneration ~= state.generation then return end
        state.queued = false
        if state.active then Paint(owner) end
    end
    return state
end

function H.Sync(owner)
    local enabled = owner.mplusActive and owner.config.showObservedPull and not owner.mplus.completed
    if not enabled then
        H.Stop(owner)
        return
    end
    local state = owner.observedPull
    if not state then
        state = NewState(owner)
        owner.observedPull = state
    end
    if state.active then return end
    state.active = true
    for _, event in ipairs(EVENTS) do state.frame:RegisterEvent(event) end
    Snapshot(state)
    Paint(owner)
end

function H.Update(owner)
    local state = owner.observedPull
    if state and state.active then Paint(owner) end
end

-- A new run starts with an empty value cache.
function H.Stop(owner)
    local state = owner.observedPull
    if not state then return end
    state.frame:UnregisterAllEvents()
    state.active, state.queued, state.sum = nil, false, nil
    state.generation = state.generation + 1
    for unit in pairs(state.units) do state.units[unit] = nil end
    for guid in pairs(state.percent) do state.percent[guid] = nil end
end

S.MythicPlusPull = H

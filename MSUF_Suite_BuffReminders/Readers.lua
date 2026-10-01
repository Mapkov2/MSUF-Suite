local _, P = ...
local S = P.Suite
local R = P.BuffReminders
-- Client readers: known spells, item counts, icons, auras, food, temporary
-- weapon enchants and poison states. Every reader checks each returned value
-- with S.Public and reports a restricted (secret) read as unknown (nil),
-- never as missing.
local Public = S.Public
local QUESTION_MARK = 134400
local EMPTY = {}
local FOOD_ICONS = R.FOOD_ICONS
local FOOD_AURAS = R.FOOD_AURAS
local GetItemCount = C_Item.GetItemCount
local PLAYER_BANK = Enum.SpellBookSpellBank.Player
local rankNames = {}

function R.RankName(spellID)
    local name = rankNames[spellID]
    if name == nil then
        name = C_Spell.GetSpellName(spellID)
        name = Public(name) and type(name) == "string" and name ~= "" and name or false
        rankNames[spellID] = name
    end
    return name or nil
end

-- Forever's ranked buffs share their spell name across ranks. Returns false
-- when the name is unreadable (nothing to look up), else true and the aura.
function R.RankAura(unit, spellID, own)
    local name = R.RankName(spellID)
    if not name then return false end
    return true, C_UnitAuras.GetAuraDataBySpellName(unit, name, own and "HELPFUL|PLAYER" or "HELPFUL")
end

-- Aura lookups (RequiresNonSecretAura) return nothing instead of raising
-- while aura data is restricted. C_Secrets reports that state; a reader then
-- answers unknown, never missing.
function R.AurasRestricted()
    local restricted = C_Secrets.ShouldAurasBeSecret()
    return not Public(restricted) or restricted ~= false
end

function R.Clear(t)
    for key in pairs(t) do t[key] = nil end
end
local Clear = R.Clear

-- C_SpellBook directly: the global IsPlayerSpell and IsSpellKnown shims exist
-- only while Blizzard's deprecation fallbacks are loaded.
function R.Known(spellID)
    local known = C_SpellBook.IsSpellKnown(spellID, PLAYER_BANK)
    if Public(known) and known == true then return true end
    local inBook = C_SpellBook.IsSpellInSpellBook(spellID, PLAYER_BANK, false)
    return Public(inBook) and inBook == true
end

function R.ItemCount(itemID)
    local count = GetItemCount(itemID)
    if Public(count) and type(count) == "number" then return count end
end

function R.Texture(kind, id)
    local value
    if kind == "spell" then
        value = C_Spell.GetSpellTexture(id)
    else
        value = C_Item.GetItemIconByID(id)
    end
    return Public(value) and value or QUESTION_MARK
end

local function AuraExpiry(data)
    local expiration, duration = data.expirationTime, data.duration
    if Public(expiration) and Public(duration)
        and type(expiration) == "number" and type(duration) == "number"
        and expiration > 0 and duration > 0 and expiration < math.huge then
        return expiration
    end
end

-- Copies the public identity and timing of an aura into target.
local function FillSnapshot(target, data, spellID)
    local instanceID = data.auraInstanceID
    if not Public(instanceID) or type(instanceID) ~= "number" then instanceID = nil end
    local auraSpellID = data.spellId
    if Public(auraSpellID) and type(auraSpellID) == "number" then spellID = auraSpellID end
    local expiration = AuraExpiry(data)
    target.auraInstanceID, target.expirationTime = instanceID, expiration
    target.spellID = spellID
    target.duration = expiration and data.duration or nil
    return target
end

-- Food snapshots are recycled: a rescan or an aura delta reuses the tables
-- of the food auras that went away instead of allocating new ones.
local spareSnapshots = {}
local function Snapshot(data, spellID)
    local count = #spareSnapshots
    local target = spareSnapshots[count]
    if target then
        spareSnapshots[count] = nil
    else
        target = {}
    end
    return FillSnapshot(target, data, spellID)
end

local function ReleaseSnapshot(ids, key)
    local snapshot = ids[key]
    if not snapshot then return false end
    ids[key] = nil
    spareSnapshots[#spareSnapshots + 1] = snapshot
    return true
end

-- One targeted lookup per aura ID. nil when a lookup was restricted (secret),
-- else whether the player has one of the entry's auras, with its timing.
function R.AuraPresent(entry)
    if R.AurasRestricted() then return nil end
    local ids = entry.aliases
    local count = ids and #ids or 1
    local unknown = false
    for index = 1, count do
        local id = ids and ids[index] or entry.aura
        local ok, data = true, nil
        if entry.ranked then ok, data = R.RankAura("player", id)
        else data = C_UnitAuras.GetPlayerAuraBySpellID(id) end
        if not ok or not Public(data) then
            unknown = true
        elseif data then
            local instanceID = data.auraInstanceID
            if not Public(instanceID) or type(instanceID) ~= "number" then instanceID = nil end
            local expiration = AuraExpiry(data)
            return true, instanceID, expiration, nil, expiration and data.duration or nil
        end
    end
    if unknown then return nil end
    return false
end

local function MatchesAuraID(entry, spellID, name)
    if entry.ranked then
        if not Public(name) or type(name) ~= "string" then return true end
        for _, id in ipairs(entry.aliases) do if name == R.RankName(id) then return true end end
        return false
    end
    local aliases = entry.aliases
    if not aliases then return entry.aura == spellID end
    for index = 1, #aliases do
        if aliases[index] == spellID then return true end
    end
    return false
end

-- A public list of aura instance IDs, nil (absent), or false (unreadable).
local function IDList(list)
    if not Public(list) or (list ~= nil and type(list) ~= "table") then return false end
    return list
end

local function ListTouches(list, entry, instanceID)
    for _, id in ipairs(list) do
        if not Public(id) or type(id) ~= "number" or id == instanceID
            or (entry.instanceIDs and entry.instanceIDs[id]) then
            return true
        end
    end
    return false
end

-- Whether one UNIT_AURA delta can change an entry (or a poison state): only
-- its own auras, or data the delta could not show, need a fresh lookup.
function R.AuraChangeAffects(entry, info)
    if not Public(info) or type(info) ~= "table" then return true end
    local full = info.isFullUpdate
    if not Public(full) or full then return true end
    if entry.present == nil then return true end
    local added = IDList(info.addedAuras)
    if added == false then return true end
    if added then
        for _, aura in ipairs(added) do
            if not Public(aura) then return true end
            local spellID = aura.spellId
            if not Public(spellID) or type(spellID) ~= "number" or MatchesAuraID(entry, spellID, aura.name) then return true end
        end
    end
    if entry.present == false then return false end
    local instanceID = entry.auraInstanceID
    if not instanceID then return true end
    local removed = IDList(info.removedAuraInstanceIDs)
    if removed == false or (removed and ListTouches(removed, entry, instanceID)) then return true end
    local updated = IDList(info.updatedAuraInstanceIDs)
    if updated == false or (updated and ListTouches(updated, entry, instanceID)) then return true end
    return false
end

-- Food auras are known two ways: a UNIT_AURA delta learns any added aura with
-- a food icon (R.FoodDelta), and a rescan runs targeted player lookups. An
-- indexed aura read can itself raise under Midnight's secret/taint rules,
-- before Public can inspect the result, so the rescan never scans by index.
-- A rescan (enable, combat end, zone change, full update) keeps what a delta
-- learned: it re-checks each known aura by spell ID and drops only the auras
-- that are gone. Instance-ID queries can raise on secret auras even before
-- Public can inspect the result. After a reload, the listed IDs
-- and their spell name (Well Fed) find the usual variants, but no targeted
-- lookup finds a food aura with another name and an unlisted ID, so such an
-- aura reads as missing until its next UNIT_AURA delta.
local foodNames, foodNameSet

local function FoodNames()
    if foodNames then return foodNames end
    foodNames, foodNameSet = {}, {}
    for index = 1, #FOOD_AURAS do
        local name = C_Spell.GetSpellName(FOOD_AURAS[index])
        if Public(name) and type(name) == "string" and not foodNameSet[name] then
            foodNames[#foodNames + 1] = name
            foodNameSet[name] = true
        end
    end
    return foodNames
end

-- An added aura is food by the Well Fed icon or by a food buff's name.
local function FoodAura(aura)
    if type(aura.icon) == "number" and FOOD_ICONS[aura.icon] then return true end
    local name = aura.name
    if not Public(name) or type(name) ~= "string" then return false end
    FoodNames()
    return foodNameSet[name] == true
end

-- Stores one looked-up food aura under its instance ID (or under the lookup
-- key while the ID is not a number). False when the lookup was restricted.
local function LearnFood(ids, data, lookupKey)
    if not Public(data) then return false end
    if not data then return true end
    local instanceID = data.auraInstanceID
    if not Public(instanceID) then return false end
    local spellID = data.spellId
    if not Public(spellID) then return false end
    if type(spellID) ~= "number" then spellID = type(lookupKey) == "number" and lookupKey or nil end
    if not spellID then return false end
    local key = type(instanceID) == "number" and instanceID or lookupKey
    ids[key] = ids[key] and FillSnapshot(ids[key], data, spellID) or Snapshot(data, spellID)
    return true
end

local function ScanFood(self)
    local ids = self.foodIDs
    local keys = self.foodScanKeys
    if not keys then
        keys = {}
        self.foodScanKeys = keys
    end
    for index = #keys, 1, -1 do keys[index] = nil end
    for key in pairs(ids) do keys[#keys + 1] = key end
    local known = true
    for index = 1, #keys do
        local key = keys[index]
        local snapshot = ids[key]
        if snapshot then
            local spellID = snapshot.spellID
            local data = spellID and C_UnitAuras.GetPlayerAuraBySpellID(spellID)
            if not spellID or not Public(data) then
                known = false
            elseif data then
                local instanceID = data.auraInstanceID
                if not Public(instanceID) or not Public(data.spellId) then
                    known = false
                elseif type(instanceID) == "number" and instanceID ~= key then
                    ReleaseSnapshot(ids, key)
                    if not LearnFood(ids, data, spellID) then known = false end
                else
                    FillSnapshot(snapshot, data, spellID)
                end
            else
                -- Gone, or stored under a lookup key: the lookups below re-add it.
                ReleaseSnapshot(ids, key)
            end
        end
    end
    for index = 1, #FOOD_AURAS do
        local spellID = FOOD_AURAS[index]
        if not LearnFood(ids, C_UnitAuras.GetPlayerAuraBySpellID(spellID), spellID) then known = false end
    end
    local names = FoodNames()
    for index = 1, #names do
        local name = names[index]
        if not LearnFood(ids, C_UnitAuras.GetAuraDataBySpellName("player", name, "HELPFUL"), name) then
            known = false
        end
    end
    self.foodKnown = known
end

-- Removed and added food auras of one delta; false when a list is unreadable.
local function ApplyFoodLists(ids, info)
    local changed = false
    local removed = IDList(info.removedAuraInstanceIDs)
    if removed == false then return false end
    if removed then
        for _, id in ipairs(removed) do
            if not Public(id) then return false end
            if ReleaseSnapshot(ids, id) then changed = true end
        end
    end
    local added = IDList(info.addedAuras)
    if added == false then return false end
    if added then
        for _, aura in ipairs(added) do
            if not Public(aura) or not Public(aura.icon) or not Public(aura.auraInstanceID) then return false end
            local id = aura.auraInstanceID
            if type(id) == "number" and FoodAura(aura) then
                local spellID = aura.spellId
                if not Public(spellID) or type(spellID) ~= "number" then return false end
                ids[id] = ids[id] and FillSnapshot(ids[id], aura, spellID) or Snapshot(aura, spellID)
                changed = true
            end
        end
    end
    return true, changed
end

-- Applies one UNIT_AURA delta to the known food auras. Returns true when the
-- food reminder must be re-evaluated; foodKnown nil forces a rescan, false
-- keeps the reminder unknown. A delta is applied in every state: a pending
-- rescan re-checks what it learned instead of forgetting it.
function R.FoodDelta(self, info)
    if not self.hasFood then return false end
    if not Public(info) then
        self.foodKnown = false
        return true
    end
    if info == nil then
        self.foodKnown = nil
        return true
    end
    if type(info) ~= "table" or not Public(info.isFullUpdate) then
        self.foodKnown = false
        return true
    end
    if info.isFullUpdate then
        self.foodKnown = nil
        return true
    end
    local ids = self.foodIDs
    local readable, changed = ApplyFoodLists(ids, info)
    if not readable then
        self.foodKnown = false
        return true
    end
    local updated = IDList(info.updatedAuraInstanceIDs)
    if updated == false then
        self.foodKnown = false
        return true
    end
    if updated then
        for _, id in ipairs(updated) do
            if not Public(id) then
                self.foodKnown = false
                return true
            end
            if ids[id] then
                self.foodKnown = nil
                return true
            end
        end
    end
    return changed
end

function R.FoodPresent(self)
    if R.AurasRestricted() then return nil end
    if self.foodKnown == nil then ScanFood(self) end
    if not self.foodKnown then return nil end
    local present, expiresAt, totalDuration = false, nil, nil
    for _, aura in pairs(self.foodIDs) do
        present = true
        local expiration = aura.expirationTime
        if expiration and (not expiresAt or expiration > expiresAt) then
            expiresAt, totalDuration = expiration, aura.duration
        end
    end
    return present, expiresAt, totalDuration
end

function R.EnchantPresent(slot)
    local data = C_PaperDollInfo.GetTemporaryEnchantmentInfo(slot)
    if not Public(data) then return nil end
    if data == nil then return false end
    local remaining, timed = data.remainingTimeMs, data.hasExpirationTime
    if Public(remaining) and Public(timed) and timed == true
        and type(remaining) == "number" and remaining > 0 and remaining < math.huge then
        return true, GetTime() + remaining / 1000
    end
    return true
end

local function PoisonLatestFirst(left, right)
    return (left.expiresAt or math.huge) > (right.expiresAt or math.huge)
end

-- The active poisons of one category (lethal or nonlethal), latest first.
function R.ReadPoisonState(state)
    local active, instanceIDs = state.active, state.instanceIDs
    Clear(instanceIDs)
    local count, unknown = 0, R.AurasRestricted()
    state.auraInstanceID = nil
    for _, spellID in ipairs(unknown and EMPTY or state.aliases) do
        local data = C_UnitAuras.GetPlayerAuraBySpellID(spellID)
        if not Public(data) then
            unknown = true
        elseif data then
            count = count + 1
            local record = active[count] or {}
            active[count] = record
            record.spellID = spellID
            record.expiresAt = AuraExpiry(data)
            record.duration = record.expiresAt and data.duration or nil
            local instanceID = data.auraInstanceID
            if Public(instanceID) and type(instanceID) == "number" then
                instanceIDs[instanceID] = true
                state.auraInstanceID = instanceID
            end
        end
    end
    for index = count + 1, #active do active[index] = nil end
    if count > 1 then table.sort(active, PoisonLatestFirst) end
    if unknown then state.present = nil else state.present = count > 0 end
    state.unknown = unknown
end

-- Fills state.warnings with the poison each missing or expiring slot should
-- cast; returns the next advance-warning deadline.
function R.BuildPoisonWarnings(state, now, threshold)
    local active, warnings = state.active, state.warnings
    for index = #warnings, 1, -1 do warnings[index] = nil end
    if state.unknown then return end
    local missing = math.max(0, state.required - #active)
    for _, candidate in ipairs(state.candidates) do
        if #warnings >= missing then break end
        local inUse = false
        for _, aura in ipairs(active) do
            if aura.spellID == candidate then
                inUse = true
                break
            end
        end
        if not inUse then warnings[#warnings + 1] = candidate end
    end
    local nextDue
    if now and threshold > 0 then
        for index = 1, math.min(state.required, #active) do
            local aura = active[index]
            if aura.expiresAt and aura.duration and aura.duration > threshold then
                local due = aura.expiresAt - threshold
                if due <= now then
                    warnings[#warnings + 1] = aura.spellID
                elseif not nextDue or due < nextDue then
                    nextDue = due
                end
            end
        end
    end
    return nextDue
end

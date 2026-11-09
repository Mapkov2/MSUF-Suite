local _, NS = ...
local Public, PublicText, Finite = NS.Public, NS.PublicText, NS.Finite
local Mount = {}
NS.UnitMount = Mount

local function PublicTable(value)
    return Public(value) and type(value) == "table" and canaccesstable(value)
end

-- Proceed only when the client's predicate returns a public false.
local function Restricted(query, ...)
    local value = query(...)
    return not Public(value) or value ~= false
end

local function ReadAura(aura)
    local spellID = aura.spellId
    if not Finite(spellID) or spellID <= 0 then return end
    local mountID = C_MountJournal.GetMountFromSpell(spellID)
    if not Finite(mountID) or mountID <= 0 then return end
    local name, _, _, _, _, _, _, _, _, _, collected = C_MountJournal.GetMountInfoByID(mountID)
    name = PublicText(name)
    if not name then return end
    if not Public(collected) or type(collected) ~= "boolean" then collected = nil end
    local instanceID = aura.auraInstanceID
    if not Finite(instanceID) or instanceID <= 0 then instanceID = nil end
    return name, collected, instanceID
end

-- Accepts a helpful aura supplied by the caller after checking unit access.
function Mount.FromAura(aura)
    if PublicTable(aura) then return ReadAura(aura) end
end

-- Return the mount, a stop marker on restricted data, or the next page.
local function ScanSlots(unit, continuation, ...)
    if not Public(continuation) or continuation ~= nil and not Finite(continuation) then return "stop" end
    for index = 1, select("#", ...) do
        local slot = select(index, ...)
        if not Finite(slot) or Restricted(C_Secrets.ShouldUnitAuraSlotBeSecret, unit, slot) then return "stop" end
        local aura = C_UnitAuras.GetAuraDataBySlot(unit, slot)
        if not Public(aura) then return "stop" end
        if aura ~= nil then
            if type(aura) ~= "table" or not canaccesstable(aura) then return "stop" end
            local name, collected, instanceID = ReadAura(aura)
            if name then return "found", name, collected, instanceID end
        end
    end
    return continuation
end

function Mount.Read(unit)
    if Restricted(C_Secrets.ShouldAurasBeSecret) then return end
    local continuation, seen
    repeat
        local result, name, collected, instanceID =
            ScanSlots(unit, C_UnitAuras.GetAuraSlots(unit, "HELPFUL", 32, continuation))
        if result == "found" then return name, collected, instanceID end
        if result == "stop" or result == nil then return end
        -- Allocate only for a scan that actually paginates.
        if not seen then seen = {} end
        if seen[result] then return end
        seen[result] = true
        continuation = result
    until false
end

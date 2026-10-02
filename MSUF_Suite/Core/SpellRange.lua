local _, NS = ...
local S = NS.Suite
local owners, counts, foreign = {}, {}, {}
local hooked, writing = false, false

local function WriteRange(spellID, enabled)
    local previous = writing
    writing = true
    C_Spell.EnableSpellRangeCheck(spellID, enabled)
    writing = previous
end

-- Range registration is global and not reference counted. From the first
-- Suite request on, this observer sees every enable made through
-- C_Spell.EnableSpellRangeCheck: a spell another addon enabled is never
-- switched off when the Suite lets go of it. Blizzard resets its items
-- without reference counting, before clearing their range fields, so a
-- native disable re-enables a spell the Suite still uses. Enables made
-- before the first request, or by code holding its own reference to the
-- function, are not seen.
local function EnsureHook()
    if hooked then return end
    hooked = true
    hooksecurefunc(C_Spell, "EnableSpellRangeCheck", function(spellID, enabled)
        if writing or not NS.Finite(spellID) or not NS.Public(enabled) then return end
        if enabled == true then
            foreign[spellID] = true
        elseif enabled == false then
            foreign[spellID] = nil
            if counts[spellID] then WriteRange(spellID, true) end
        end
    end)
end

local function ViewerNeedsRange(viewer, spellID)
    -- Unknown native ownership must not be treated as permission to disable it.
    if not NS.Public(viewer) then return true end
    if not viewer then return false end
    if viewer:IsForbidden() then return true end
    local pool = viewer.itemFramePool
    if not NS.Public(pool) then return true end
    if not pool then return false end
    for item in pool:EnumerateActive() do
        if not NS.Public(item) or item:IsForbidden() then return true end
        local needed = item.needsRangeCheck
        if not NS.Public(needed) then return true end
        if needed then
            local id = item.rangeCheckSpellID
            if not NS.Finite(id) or id == spellID then return true end
        end
    end
    return false
end

-- Range registration is global. Share Suite interest and preserve other
-- owners: addons seen enabling the spell, and Blizzard's Essential/Utility
-- items (live and Forever CooldownViewer.lua). Hidden viewers retain their
-- items; globals are read on release to include late-created pools.
function S.SetNativeSpellRange(owner, spellID, enabled)
    if not NS.Public(owner) or type(owner) ~= "string" or not NS.Finite(spellID)
        or spellID <= 0 or not NS.Public(enabled) then return end
    local spells = owners[owner]
    if enabled then
        EnsureHook()
        if not spells then
            spells = {}
            owners[owner] = spells
        end
        if spells[spellID] then return end
        spells[spellID] = true
        local count = (counts[spellID] or 0) + 1
        counts[spellID] = count
        if count == 1 then WriteRange(spellID, true) end
    elseif spells and spells[spellID] then
        spells[spellID] = nil
        local count = counts[spellID] - 1
        counts[spellID] = count > 0 and count or nil
        if count == 0 and not foreign[spellID]
            and not ViewerNeedsRange(_G.EssentialCooldownViewer, spellID)
            and not ViewerNeedsRange(_G.UtilityCooldownViewer, spellID) then
            WriteRange(spellID, false)
        end
        if not next(spells) then owners[owner] = nil end
    end
end

function S.ClearNativeSpellRanges(owner)
    local spells = owners[owner]
    if not spells then return end
    for spellID in pairs(spells) do S.SetNativeSpellRange(owner, spellID, false) end
end

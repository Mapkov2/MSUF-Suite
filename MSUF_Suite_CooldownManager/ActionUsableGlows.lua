local _, P = ...
local NS, S = P.NS, P.Suite
local C = P.CDM
-- Optional action-bar feedback from public native usability and the main
-- cooldown answer already read by Time.SpellState. No aura access or polling.
-- Shared/ActionButton.lua on Retail and Forever uses ACTION_USABLE_CHANGED
-- (slot, usable, noMana); the payload-less fallback queries selected slots only.
local U = { wanted = false, pending = false }
C.ActionUsableGlows = U
local Routes, Effects = C.ActionGlows, C.Effects
local Slot, Spell, Public = Routes.ButtonSlot, Routes.SlotSpell, S.Public
local pairs, type = pairs, type
local records, byEntry, bySlot, pool = {}, {}, {}, {}
local stamp, armed, current = 0, false, nil

local function Wants(entry)
    local view = entry.slot and C.views[entry.slot]
    return view and view.on and entry.family == C.Const.FAMILY.COOLDOWN and entry.ov and entry.ov.actionUsableGlow == true and entry.spell ~= nil
        and (entry.src == "b" or entry.src == "s") and not entry.equipSlot
        and (entry.spellCategory == nil or entry.spellCategory == 0)
end

local function Paint(rec)
    local entry = rec.entry
    local bars = S.states.actionbars
    local on = not rec.free and C.M.active and bars and bars.active and not C.state.preview and Wants(entry)
        and C.entries[entry.key] == entry and entry.actionGlowCooling == false and rec.usable == true
        and (not C.state.readyGlowCombat or C.state.inCombat)
    if on then on = Slot(rec.button) == rec.slot and Spell(rec.slot) == rec.spell end
    on = on and true or false
    if rec.on == on then return end
    rec.on = on
    Effects.SetGlow(rec.host, "ready", on)
end

local function Free(rec)
    rec.free = true
    Paint(rec)
end

local function ClearMap(map)
    for key, list in pairs(map) do
        C.wipe(list)
        pool[#pool + 1] = list
        map[key] = nil
    end
end

local function List(map, key)
    local list = map[key]
    if list then return list end
    list = pool[#pool] or {}
    pool[#pool] = nil
    map[key] = list
    return list
end

-- Owned hosts inherit action-button geometry, including scale/size edits.
local function Resize(host, w, h)
    if not host.entry or not Public(w) or not Public(h) then return end
    if type(w) ~= "number" or type(h) ~= "number" or w <= 0 or h <= 0 then return end
    if host.w == w and host.h == h then return end
    host.w, host.h = w, h
    Effects.Refit(host)
end

local function Take(button, entry)
    local list = records[button]
    if not list then
        list = {}
        records[button] = list
    end
    for i = 1, #list do
        if list[i].key == entry.key then return list[i] end
    end
    for i = 1, #list do
        if list[i].free then return list[i] end
    end
    local host = S.CreateFrame("Frame", nil, button)
    host:SetAllPoints(button)
    host:SetFrameLevel(button:GetFrameLevel() + 1)
    host:SetScript("OnSizeChanged", Resize)
    local rec = { host = host, button = button }
    list[#list + 1] = rec
    return rec
end

local function Visit(button)
    local entry = current
    local slot = Slot(button)
    local spell = slot and Spell(slot)
    if not slot or not spell then return end
    local w, h = button:GetSize()
    if not Public(w) or not Public(h) then return end
    if type(w) ~= "number" or type(h) ~= "number" or w <= 0 or h <= 0 then return end
    local rec = Take(button, entry)
    rec.entry, rec.key, rec.slot, rec.spell, rec.stamp, rec.free = entry, entry.key, slot, spell, stamp, false
    rec.host.entry = entry
    Resize(rec.host, w, h)
    Effects.PrepareGlow(rec.host)
    local entries, slots = List(byEntry, entry), List(bySlot, slot)
    entries[#entries + 1] = rec
    if #slots == 0 then
        local usable = C_ActionBar.IsUsableAction(slot)
        slots.usable = Public(usable) and usable == true
    end
    slots[#slots + 1] = rec
    rec.usable = slots.usable
    Paint(rec)
    Effects.Refit(rec.host)
end

-- Called by Time before recharge presentation can extend the cooling state.
-- One available charge is enough; a missing/secret cooldown answer stays off.
function U.Cooldown(entry, cooling)
    entry.actionGlowCooling = cooling
    local list = byEntry[entry]
    if list then for i = 1, #list do Paint(list[i]) end end
end

-- Info and active have already been read by Time; unknown is conservative.
function U.Timing(entry, info, active, cooling, exact)
    local known = Public(info) and info ~= nil and Public(active) and type(active) == "boolean"
    local proven = known and (active == false or Public(exact) and exact == true)
    U.Cooldown(entry, not proven or cooling)
end

local function SetUsable(list, usable)
    usable = Public(usable) and usable == true
    list.usable = usable
    for i = 1, #list do
        local rec = list[i]
        rec.usable = usable
        Paint(rec)
    end
end

local function Fire()
    armed = false
    if not U.wanted or not C.M.active then return end
    for slot, list in pairs(bySlot) do
        local usable = C_ActionBar.IsUsableAction(slot)
        SetUsable(list, usable)
    end
end

function U.Queue()
    if armed or not U.wanted then return end
    armed = true
    C_Timer.After(0, Fire)
end

function U.Changed(_, _, changes)
    if not Public(changes) or type(changes) ~= "table" then return U.Queue() end
    for i = 1, #changes do
        local change = changes[i]
        if Public(change) and type(change) == "table" then
            local slot = change.slot
            local list = Public(slot) and slot ~= nil and bySlot[slot]
            if list then SetUsable(list, change.usable) end
        end
    end
end

function U.Repaint()
    if not U.wanted then return end
    for _, list in pairs(records) do for i = 1, #list do Paint(list[i]) end end
end

function U.Follow()
    if not U.wanted then return end
    for _, list in pairs(records) do
        for i = 1, #list do
            list[i].usable = false
            Paint(list[i])
        end
    end
    U.Queue()
end

local function Wanted(visit)
    if not visit then return false end
    local wanted = false
    for _, entry in pairs(C.entries) do
        if Wants(entry) then
            wanted = true
            if entry.actionGlowCooling == nil then C.Flush.Mark(entry, "full") end
        else
            entry.actionGlowCooling = nil
        end
    end
    return wanted
end

function U.Refresh()
    local visit = C.M.active and Routes.Visitor() or nil
    local wanted = Wanted(visit)
    if U.wanted ~= wanted then
        U.wanted = wanted
        C.Flush.dirty.events = true
        C.Schedule()
    end
    if not wanted then return U.Release() end
    if NS.IsCombatLocked() then
        U.pending = true
        U.Follow()
        return
    end
    U.pending = false
    stamp = stamp + 1
    ClearMap(byEntry)
    ClearMap(bySlot)
    for _, list in pairs(records) do
        for i = 1, #list do
            local rec = list[i]
            if C.entries[rec.key] ~= rec.entry or not Wants(rec.entry) then
                rec.entry.actionGlowCooling = nil
                Free(rec)
            end
        end
    end
    for _, entry in pairs(C.entries) do
        if Wants(entry) then
            current = entry
            visit(entry.base or entry.spell, Visit)
        end
    end
    current = nil
    for _, list in pairs(records) do
        for i = 1, #list do if list[i].stamp ~= stamp then Free(list[i]) end end
    end
end

function U.Release()
    for entry in pairs(byEntry) do entry.actionGlowCooling = nil end
    for _, list in pairs(records) do for i = 1, #list do Free(list[i]) end end
    ClearMap(byEntry)
    ClearMap(bySlot)
    U.wanted, U.pending = false, false
end

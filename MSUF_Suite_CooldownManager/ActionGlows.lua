local _, P = ...
local NS, S = P.NS, P.Suite
local C = P.CDM
-- Glows on the suite action bars' buttons for entries with an action-bar
-- glow spell (ov.actionGlowSpell): one native aura slot per button shows
-- the entry's buff (mode 1) or its stacks (mode 2), drawn with the aura
-- layer's primitives (AuraGlows.lua). The action bars, their own
-- load-on-demand module, visit the buttons that hold a spell
-- (S.ForEachActionBarButtonForSpell, out of combat only); nothing here
-- tells them about aura presence or stack counts.
--  * Routes: slot, page, form and binding events come in storms (100+ at
--    login, spec and talent swaps). One trailing pass 0.2 s after the first
--    event follows them all, like the key texts (Keybinds.Request).
--  * In combat (and while auras are secret) a page can change under a
--    binding, and the action bars refuse the visit: the trailing pass only
--    switches each placed record off or back on by whether its button's
--    action slot still holds its spell (plain reads, container-level
--    switches: legal in combat). The full pass runs when combat ends.
--  * Containers cannot be freed. A button keeps its records; one that no
--    entry placed in a pass is switched off and taken by the next entry
--    with the same glow mode on that button.
local ActionGlows = { wanted = false, pending = false }
C.ActionGlows = ActionGlows
local AuraButtons, K = C.AuraButtons, C.Const
local ACTION_GLOW = K.ACTION_GLOW
local Public = S.Public
local pairs, next, type = pairs, next, type
local DELAY = 0.2
local records = {} -- action button -> its records
local stamp = 0
local currentEntry, currentView
local armed = false

local Draw = C.AuraGlows
local NewGlow, ApplyStack, ApplyGlow = Draw.NewGlow, Draw.ApplyStack, Draw.ApplyGlow
local ApplyCombatGate, Overlay, BridgeStack = Draw.ApplyCombatGate, Draw.Overlay, Draw.BridgeStack

------------------------------------------------------------------ routes
-- The suite action bars own every button a record decorates: without
-- them running there is nothing to visit and no slot event to follow.
local function Visitor()
    local visit, bars = S.ForEachActionBarButtonForSpell, S.states.actionbars
    if type(visit) == "function" and bars and bars.active == true then return visit end
end

local function Wants(entry)
    local ov, ids = entry.ov, entry.auraIDs
    return ov ~= nil and ov.actionGlowSpell ~= nil and ids ~= nil and next(ids) ~= nil
end

-- The action slot a button shows now: the field Blizzard's action buttons
-- keep (native mode), else the secure "action" attribute the suite bars'
-- page handler writes. Plain reads, legal in combat.
local function ButtonSlot(button)
    local slot = button.action
    if not (Public(slot) and type(slot) == "number") then slot = button:GetAttribute("action") end
    if Public(slot) and type(slot) == "number" then return slot end
end

-- The spell an action slot casts: a spell, or a macro that shows one
-- (Blizzard's rule, AssistedCombatManager.lua). Nothing while secret.
local function SlotSpell(slot)
    local kind, id, sub = GetActionInfo(slot)
    if not (Public(kind) and Public(id) and Public(sub)) then return nil end
    if kind == "spell" or (kind == "macro" and sub == "spell") then return id end
end

------------------------------------------------------------------ records
-- Action-bar bridges bind their own native aura slot, without exporting
-- aura presence or stack counts to the action-bar controller.
local function InitBridge(rec, button)
    Overlay(button, rec.button)
    local level = button:GetFrameLevel() + 1
    local part = { button = button, pos = 1, rec = rec }
    rec.parts[1] = part
    if rec.mode == ACTION_GLOW.STACKS then
        BridgeStack(rec, part, rec.ov, level)
    else
        part.glow = NewGlow(button, button, level)
        ApplyGlow(rec, part, rec.ov, false)
        ApplyCombatGate(part.glow, part.gOn, false)
        part.bound = true
    end
end

local function StyleBridge(rec)
    if not AuraButtons.Mutable(rec) then return false end
    local part = rec.parts[1]
    if not part then return true end
    if part.glow then
        ApplyGlow(rec, part, rec.ov, false)
        ApplyCombatGate(part.glow, part.gOn, false)
    end
    if part.stack then
        ApplyStack(rec, part, rec.ov, false)
        ApplyCombatGate(part.stack.glow, part.stack.on, false)
    end
    return true
end

-- The record of this entry on the button: its own from the last pass,
-- else one that no entry placed last pass, with the same mode.
local function Take(list, key, mode)
    for i = 1, #list do
        local rec = list[i]
        if rec.key == key and rec.mode == mode then return rec end
    end
    for i = 1, #list do
        local rec = list[i]
        if rec.free and rec.mode == mode then return rec end
    end
end

local function Switch(rec, on)
    if rec.on == on then return end
    rec.on = on
    rec.frame:SetEnabled(on)
end

local function Visit(button)
    local entry, view = currentEntry, currentView
    local ov = entry.ov
    local mode = ov.actionGlowMode or ACTION_GLOW.PRESENT
    local width, height = button:GetSize()
    if not Public(width) or not Public(height) or width <= 0 or height <= 0 then return end
    local list = records[button]
    if not list then
        list = {}
        records[button] = list
    end
    local rec = Take(list, entry.key, mode)
    if not rec then
        local frame = CreateFrame("AuraContainer", nil, button, "CustomAuraContainerTemplate")
        frame:SetAllPoints(button)
        frame:SetUnit("player")
        rec = { frame = frame, parts = {}, lk = {}, mode = mode, ov = {}, ids = {}, button = button }
        list[#list + 1] = rec
    end
    rec.stamp, rec.free, rec.key, rec.spell = stamp, false, entry.key, ov.actionGlowSpell
    rec.lk.w, rec.lk.h, rec.lk.px = width, height, K.Px()
    rec.gStyle, rec.gTint, rec.gR, rec.gG, rec.gB = view.glowStyle, view.glowTint, view.glowR, view.glowG, view.glowB
    rec.ov.auraGlow = true
    rec.ov.glowStyle, rec.ov.glowColor = ov.glowStyle, ov.glowColor
    rec.ov.stackGlow, rec.ov.stackGlowOp = ov.stackGlow, ov.stackGlowOp
    local ids = entry.auraIDs
    local different = not K.SameSet(rec.ids, ids)
    if different then K.CopySet(rec.ids, ids) end
    if not rec.bound then
        rec.frame:AddAuraSlot("glow", "HELPFUL", { candidateFilters = { includeSpellIDs = rec.ids },
            initializeFrame = function(auraButton) InitBridge(rec, auraButton) end })
        rec.bound = true
    else
        if different then rec.frame:SetAuraSlotCandidateFilters("glow", { includeSpellIDs = rec.ids }) end
        if not StyleBridge(rec) then ActionGlows.pending = true end
    end
    Switch(rec, true)
    rec.frame:Show()
end

local function Free(rec)
    rec.free = true
    Switch(rec, false)
    rec.frame:Hide()
    Draw.ReleaseGlows(rec)
end
-- Before a pass: records whose entry no longer asks for their glow mode
-- are free, so the pass can hand them to another entry at once.
local function Unwanted()
    for _, list in pairs(records) do
        for i = 1, #list do
            local rec = list[i]
            if not rec.free then
                local entry = C.entries[rec.key]
                if not (entry and Wants(entry) and (entry.ov.actionGlowMode or ACTION_GLOW.PRESENT) == rec.mode) then
                    Free(rec)
                end
            end
        end
    end
end
-- After a pass: records no entry placed (their spell left the button).
local function Sweep()
    for _, list in pairs(records) do
        for i = 1, #list do
            local rec = list[i]
            if rec.stamp ~= stamp and not rec.free then Free(rec) end
        end
    end
end

-- In combat or while auras are secret: a placed record stays on only while
-- its button still shows its spell.
local function Follow()
    for _, list in pairs(records) do
        for i = 1, #list do
            local rec = list[i]
            if not rec.free then
                local slot = ButtonSlot(rec.button)
                Switch(rec, slot ~= nil and SlotSpell(slot) == rec.spell)
            end
        end
    end
end

------------------------------------------------------------------ passes
function ActionGlows.Refresh()
    local visit = C.M.active and Visitor() or nil
    local wanted = false
    if visit then
        for _, entry in pairs(C.entries) do
            if Wants(entry) then
                wanted = true
                break
            end
        end
    end
    -- The slot, page and form events follow what is wanted (Events).
    if ActionGlows.wanted ~= wanted then
        ActionGlows.wanted = wanted
        C.Flush.dirty.events = true
        C.Schedule()
    end
    if NS.IsCombatLocked() or not AuraButtons.Quiet() then
        ActionGlows.pending = true
        return
    end
    ActionGlows.pending = false
    stamp = stamp + 1
    Unwanted()
    if wanted then
        for _, entry in pairs(C.entries) do
            if Wants(entry) then
                currentEntry, currentView = entry, C.views[entry.slot]
                if currentView then visit(entry.ov.actionGlowSpell, Visit) end
            end
        end
    end
    currentEntry, currentView = nil, nil
    Sweep()
end

local function Fire()
    armed = false
    if not C.M.active then return end
    if NS.IsCombatLocked() or not AuraButtons.Quiet() then
        Follow()
        ActionGlows.pending = true
        return
    end
    ActionGlows.Refresh()
end

-- A slot, page, form or binding event: one trailing pass for the storm.
-- always: the action bars started or stopped (what is wanted may change).
function ActionGlows.RouteChanged(always)
    if armed or not (ActionGlows.wanted or always) then return end
    armed = true
    C_Timer.After(DELAY, Fire)
end

function ActionGlows.Release()
    for _, list in pairs(records) do
        for i = 1, #list do Free(list[i]) end
    end
    ActionGlows.wanted, ActionGlows.pending = false, false
end

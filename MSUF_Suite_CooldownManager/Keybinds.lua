local _, P = ...
local NS, S = P.NS, P.Suite
local C = P.CDM
-- Spell -> short key text for icons on bars that show keybinds. Texts are
-- cached per spell (items per item ID); icons get theirs through
-- Icons.SetKeybind. Binding and action slot events drop the cache, bar
-- content changes only push cached texts (new spells are looked up once);
-- a burst of requests shares one pass 0.2 s after its first request.
-- Nothing here runs per cooldown event. Key texts are the action bars' own
-- (S.KeyText), so an icon and its button show the same label.
local KB = { map = {} }
C.Keybinds = KB
local Public = S.Public
local type, pairs = type, pairs
local wipe = C.wipe
local DELAY = 0.2

-- Action slots and the binding command that presses each, in the order a
-- key is preferred: the eight Blizzard bars, the suite's bars 9 (slots
-- 13-24) and 10 (slots 109-120), then the form pages (stances, shapeshift
-- forms) that the main bar keys press, which only count when no other slot
-- has a key. With Blizzard's bars the suite commands have no keys, so slots
-- 109-120 fall through to their form page. The suite action bars answer for
-- themselves while they run (S.ActionBarsBindingForSpell).
local RANGES = {
    { 1, 12, "ACTIONBUTTON" }, { 61, 72, "MULTIACTIONBAR1BUTTON" }, { 49, 60, "MULTIACTIONBAR2BUTTON" },
    { 25, 36, "MULTIACTIONBAR3BUTTON" }, { 37, 48, "MULTIACTIONBAR4BUTTON" }, { 145, 156, "MULTIACTIONBAR5BUTTON" },
    { 157, 168, "MULTIACTIONBAR6BUTTON" }, { 169, 180, "MULTIACTIONBAR7BUTTON" },
    { 13, 24, "MSUFSUITE_BAR9_BUTTON" }, { 109, 120, "MSUFSUITE_BAR10_BUTTON" },
    { 73, 120, "ACTIONBUTTON" },
}
local SLOTS, COMMANDS = {}, {}
for i = 1, #RANGES do
    local first, last, prefix = RANGES[i][1], RANGES[i][2], RANGES[i][3]
    for slot = first, last do
        local n = #SLOTS + 1
        SLOTS[n], COMMANDS[n] = slot, prefix .. ((slot - first) % 12 + 1)
    end
end

local function BoundKey(command)
    if type(GetBindingKey) ~= "function" then return nil end
    local key = GetBindingKey(command)
    if Public(key) and type(key) == "string" and key ~= "" then return key end
end

-- The first candidate whose slot is in `wanted` and has a key; "" for none.
local function FirstKey(wanted)
    for i = 1, #SLOTS do
        if wanted[SLOTS[i]] then
            local key = BoundKey(COMMANDS[i])
            if key then return S.KeyText(key) end
        end
    end
    return ""
end

local spellSlots = {}
local function Lookup(spell)
    local export = S.ActionBarsBindingForSpell
    if type(export) == "function" then
        local text = export(spell)
        if Public(text) and type(text) == "string" then return text end
    end
    local actionBar = _G.C_ActionBar
    local find = actionBar and actionBar.FindSpellActionButtons
    local slots = find and find(spell)
    if not (Public(slots) and type(slots) == "table") then return "" end
    wipe(spellSlots)
    for i = 1, #slots do
        local slot = slots[i]
        if Public(slot) and type(slot) == "number" then spellSlots[slot] = true end
    end
    return FirstKey(spellSlots)
end

function KB.Text(spell)
    if not spell then return "" end
    local text = KB.map[spell]
    if text == nil then
        text = Lookup(spell)
        KB.map[spell] = text
    end
    return text
end

-- Trinkets and other items sit on the bars as item actions, which
-- FindSpellActionButtons never matches (there is no item counterpart): one
-- scan of the candidate slots per item, in the same key preference, cached
-- like spells.
local itemMap, itemSlots = {}, {}
local function ItemLookup(item)
    local info = _G.GetActionInfo
    if type(info) ~= "function" then return "" end
    wipe(itemSlots)
    for i = 1, #SLOTS do
        local slot = SLOTS[i]
        if itemSlots[slot] == nil then
            local kind, id = info(slot)
            itemSlots[slot] = Public(kind) and kind == "item" and Public(id) and id == item or false
        end
    end
    return FirstKey(itemSlots)
end

-- An item entry (Blizzard's trinket records, the equipment-slot rows and
-- custom items) takes the key of its item action, else its use spell's.
function KB.EntryText(entry)
    local item = entry.itemID
    if item and (entry.equipSlot or entry.src == "e" or entry.src == "i") then
        local text = itemMap[item]
        if text == nil then
            text = ItemLookup(item)
            itemMap[item] = text
        end
        if text ~= "" then return text end
    end
    -- Action slots hold the base spell of an override.
    return KB.Text(entry.base or entry.spell)
end

-- Cold: pushes key text to every entry of a cooldown bar that shows
-- keybinds, from the cache where it has the spell.
function KB.Refresh()
    for slot, plan in pairs(C.plans) do
        local view = C.views[slot]
        if plan.kind == 1 and view and view.keybind then
            local entries = plan.entries
            for i = 1, #entries do
                local entry = entries[i]
                if entry.src ~= "p" then
                    local text = KB.EntryText(entry)
                    if entry.keyText ~= text then C.Icons.SetKeybind(entry, text) end
                end
            end
        end
    end
end

-- Bindings or action slots changed: every text is looked up again.
function KB.Rebuild()
    wipe(KB.map)
    wipe(itemMap)
    KB.Refresh()
end

-- One pass 0.2 s after the first request of a burst (requests in between
-- join it); stale (binding and action slot events) drops the cache first.
local armed, stale = false, false
local function Fire()
    armed = false
    local fresh = stale
    stale = false
    if not C.M.active then return end
    if fresh then
        KB.Rebuild()
    else
        KB.Refresh()
    end
end

function KB.Request(bindings)
    if bindings then stale = true end
    if armed then return end
    local timer = _G.C_Timer
    if not (timer and timer.After) then return Fire() end
    armed = true
    timer.After(DELAY, Fire)
end

function KB.Clear()
    wipe(KB.map)
    wipe(itemMap)
    stale = false
end

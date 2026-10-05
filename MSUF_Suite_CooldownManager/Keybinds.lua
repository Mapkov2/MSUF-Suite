local _, P = ...
local NS, S = P.NS, P.Suite
local C = P.CDM
-- Spell -> short key text for icons on bars that show keybinds. Texts are
-- cached per spell (items per item ID); icons get theirs through
-- Icons.SetKeybind. Binding and action slot events and changes of the suite
-- action bars (MSUFSuite.ActionBars.BindingsChanged) drop the cache, bar
-- content changes only push cached texts (new spells are looked up once);
-- a burst of requests shares one pass 0.2 s after its first request.
-- Nothing here runs per cooldown event. Key texts are the action bars' own
-- (S.KeyText), so an icon and its button show the same label.
local Keybinds = { map = {} }
C.Keybinds = Keybinds
local Public = S.Public
local type, pairs = type, pairs
local wipe = C.wipe
local KIND = C.Const.KIND
local DELAY = 0.2

-- Action slots and the binding command that presses each, in the order a
-- key is preferred: the eight Blizzard bars, the suite's bars 9 (slots
-- 13-24) and 10 (slots 109-120), then the form pages (stances, shapeshift
-- forms) that the main bar keys press, which only count when no other slot
-- has a key. With Blizzard's bars the suite commands have no keys, so slots
-- 109-120 fall through to their form page. The suite action bars answer for
-- themselves while they run (S.ActionBarsBindingForSpell). With "Keep key
-- labels stable across action pages and forms" off, the main bar keys count
-- only for the page they press now (MainPage).
local RANGES = {
    { 1, 12, "ACTIONBUTTON" }, { 61, 72, "MULTIACTIONBAR1BUTTON" }, { 49, 60, "MULTIACTIONBAR2BUTTON" },
    { 25, 36, "MULTIACTIONBAR3BUTTON" }, { 37, 48, "MULTIACTIONBAR4BUTTON" }, { 145, 156, "MULTIACTIONBAR5BUTTON" },
    { 157, 168, "MULTIACTIONBAR6BUTTON" }, { 169, 180, "MULTIACTIONBAR7BUTTON" },
    { 13, 24, "MSUFSUITE_BAR9_BUTTON" }, { 109, 120, "MSUFSUITE_BAR10_BUTTON" },
    { 73, 120, "ACTIONBUTTON" },
}
local SLOTS, COMMANDS, MAIN = {}, {}, {}
for i = 1, #RANGES do
    local first, last, prefix = RANGES[i][1], RANGES[i][2], RANGES[i][3]
    for slot = first, last do
        local n = #SLOTS + 1
        SLOTS[n], COMMANDS[n], MAIN[n] = slot, prefix .. ((slot - first) % 12 + 1), prefix == "ACTIONBUTTON"
    end
end
local MAIN_COMMANDS = {}
for n = 1, 12 do MAIN_COMMANDS[n] = "ACTIONBUTTON" .. n end

local function BoundKey(command)
    local key = GetBindingKey(command)
    if Public(key) and type(key) == "string" and key ~= "" then return key end
end

local function Yes(value) return Public(value) and value == true end
-- The page the main bar keys (ACTIONBUTTON1-12) press now, as Blizzard pages
-- MainActionBar (ActionBarController_UpdateAll, Retail and Forever).
local function MainPage()
    local bar, page = C_ActionBar, nil
    if Yes(bar.HasVehicleActionBar()) then
        page = bar.GetVehicleBarIndex()
    elseif Yes(bar.HasOverrideActionBar()) then
        page = bar.GetOverrideBarIndex()
    elseif Yes(bar.HasTempShapeshiftActionBar()) then
        page = bar.GetTempShapeshiftBarIndex()
    else
        page = bar.GetActionBarPage()
        if S.Finite(page) and page == 1 and Yes(bar.HasBonusActionBar()) then page = bar.GetBonusBarIndex() end
    end
    return S.Finite(page) and page or 1
end

-- The first candidate whose slot is in `wanted` and has a key; "" for none.
-- Following the page, the main bar keys answer only for their current page.
local function FirstKey(wanted)
    local follow = C.state.keybindStable == false
    if follow then
        local first = (MainPage() - 1) * 12
        for n = 1, 12 do
            if wanted[first + n] then
                local key = BoundKey(MAIN_COMMANDS[n])
                if key then return S.KeyText(key) end
            end
        end
    end
    for i = 1, #SLOTS do
        if wanted[SLOTS[i]] and not (follow and MAIN[i]) then
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
        local text = export(spell, C.state.keybindStable == false)
        if Public(text) and type(text) == "string" then return text end
    end
    local slots = C_ActionBar.FindSpellActionButtons(spell)
    if not (Public(slots) and type(slots) == "table") then return "" end
    wipe(spellSlots)
    for i = 1, #slots do
        local slot = slots[i]
        if Public(slot) and type(slot) == "number" then spellSlots[slot] = true end
    end
    return FirstKey(spellSlots)
end

function Keybinds.Text(spell)
    if not spell then return "" end
    local text = Keybinds.map[spell]
    if text == nil then
        text = Lookup(spell)
        Keybinds.map[spell] = text
    end
    return text
end

-- Trinkets and other items sit on the bars as item actions, which
-- FindSpellActionButtons never matches (there is no item counterpart): one
-- scan of the candidate slots per item, in the same key preference, cached
-- like spells.
local itemMap, itemSlots = {}, {}
local function ItemLookup(item)
    wipe(itemSlots)
    for i = 1, #SLOTS do
        local slot = SLOTS[i]
        if itemSlots[slot] == nil then
            local kind, id = GetActionInfo(slot)
            itemSlots[slot] = Public(kind) and kind == "item" and Public(id) and id == item or false
        end
    end
    return FirstKey(itemSlots)
end

-- An item entry (Blizzard's trinket records, the equipment-slot rows and
-- custom items) takes the key of its item action, else its use spell's.
function Keybinds.EntryText(entry)
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
    return Keybinds.Text(entry.base or entry.spell)
end

-- Cold: pushes key text to every entry of a cooldown bar that shows
-- keybinds, from the cache where it has the spell.
function Keybinds.Refresh()
    for slot, plan in pairs(C.plans) do
        local view = C.views[slot]
        if plan.kind == KIND.COOLDOWN and view and view.keybind then
            local entries = plan.entries
            for i = 1, #entries do
                local entry = entries[i]
                if entry.src ~= "p" then
                    local text = Keybinds.EntryText(entry)
                    if entry.keyText ~= text then C.Icons.SetKeybind(entry, text) end
                end
            end
        end
    end
    C.Effects.Recommendation()
end

-- Bindings or action slots changed: every text is looked up again.
function Keybinds.Rebuild()
    wipe(Keybinds.map)
    wipe(itemMap)
    Keybinds.Refresh()
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
        Keybinds.Rebuild()
    else
        Keybinds.Refresh()
    end
end

function Keybinds.Request(bindings)
    if bindings then stale = true end
    if armed then return end
    armed = true
    C_Timer.After(DELAY, Fire)
end

function Keybinds.Clear()
    wipe(Keybinds.map)
    wipe(itemMap)
    stale = false
end

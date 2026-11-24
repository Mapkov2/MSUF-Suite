local _, NS = ...
-- Action bar flyouts: one macro on any Suite action button opens a row of
-- spells, items, toys, mounts or macros next to it, also in combat
-- (MSUF_Suite_ActionBars/Flyouts.lua and FlyoutFrames.lua). The flyouts
-- belong to the account and to the WoW version: Retail and WoW Forever keep
-- separate lists in MSUFSuiteFlyoutsDB. The core holds their shape, limits and
-- presets so the options page can read them without the action bar addon.
local Flyouts = { VERSION = 1, MAX_FLYOUTS = 40, MAX_ENTRIES = 120, MAX_SHOWN = 24, MAX_NAME = 16, PER_LINE = 12 }
NS.ActionBarFlyouts = Flyouts

-- Entry kinds. "bag" is a group the runtime fills from the bags (food: every
-- usable Food & Drink item the character carries).
Flyouts.KINDS = { spell = true, item = true, toy = true, mount = true, macro = true, bag = true }
Flyouts.BAGS = { food = true }

-- WoW Forever cooked food and drinks with a food bonus, best first (nominal
-- recovery, then item ID). Verified 2026-10-31:
-- https://www.wowhead.com/forever/news/all-cooking-food-that-currently-gives-xp-buffs-in-wow-forever-382928
-- The consumable macros read the same list (MSUF_Suite_QualityOfLife/MacroConsumableData.lua).
NS.ForeverCookedFood = {
    249870, 249876, 13928, 13929, 13932, 13933, 13934, 13935, 20452, 250066, 250067, 250068, 250069, 250070, 250071,
    250072, 250075, 267341, 249869, 249875, 8957, 12212, 12218, 13927, 13930, 13931, 17222, 18045, 18254, 250065,
    250076, 286152, 10841, 249868, 249874, 4457, 4594, 6038, 8364, 12215, 12216, 13851, 20074, 250073, 250074,
    250078, 274971, 274976, 249867, 249873, 1017, 2685, 3664, 3665, 3666, 3727, 3729, 4592, 4593, 5480, 12209, 12210,
    12214, 21217, 249866, 249872, 724, 733, 787, 1082, 2683, 2684, 2687, 3220, 3662, 3726, 5476, 5479, 12213, 21072,
    250077, 250080, 249865, 249871, 2680, 2681, 2682, 2888, 3663, 5095, 5472, 5477, 6290, 6316, 6888, 6890, 12224,
    250079, 263509, 263512,
}

-- WoW Forever food from innkeepers and food vendors (bread, fruit, meat,
-- cheese, mushrooms and fish), best first.
local VENDOR_FOOD = {
    8932, 8948, 8950, 8952, 8953, 3927, 4599, 4601, 4602, 4608, 8957, 21552, 1707, 3771, 4539, 4544, 4594, 4607, 422,
    3770, 4538, 4542, 4592, 4593, 4606, 414, 787, 2287, 4537, 4541, 4605, 117, 2070, 4536, 4540, 4604,
}
-- WoW Forever vendor water, best first.
local VENDOR_DRINKS = { 8766, 1645, 1708, 1205, 1179, 159 }

local function Items(ids)
    local entries = {}
    for i, id in ipairs(ids) do entries[i] = { kind = "item", id = id } end
    return entries
end

-- Presets per WoW version. flyoutName is the new flyout's name (a macro name, at
-- most MAX_NAME characters); iconItem gives the macro its icon.
local BAG_FOOD = { { kind = "bag", id = "food" } }
Flyouts.PRESETS = {
    forever = {
        { key = "vendorFood", label = "Vendor food", flyoutName = "Food", iconItem = 4540, entries = Items(VENDOR_FOOD),
          description = "Bread, fruit, meat, cheese, mushrooms and fish from vendors. Shows what you carry, best first." },
        { key = "vendorDrinks", label = "Vendor drinks", flyoutName = "Drinks", iconItem = 159, entries = Items(VENDOR_DRINKS),
          description = "Water from innkeepers and vendors. Shows what you carry, best first." },
        { key = "cooking", label = "Cooking", flyoutName = "Cooking", iconItem = 2681, entries = Items(NS.ForeverCookedFood),
          description = "Cooked food and drinks with a food bonus. Shows what you carry, best first." },
        { key = "bagFood", label = "Food and drink in bags", flyoutName = "Bag food", iconItem = 4540, entries = BAG_FOOD,
          description = "Every food and drink in your bags that you can use, highest level first." },
    },
    retail = {
        { key = "bagFood", label = "Food and drink", flyoutName = "Food", iconItem = 4540, entries = BAG_FOOD,
          description = "Every food and drink in your bags that you can use, highest level first." },
    },
}

function Flyouts.Client()
    return NS.Client.isForever and "forever" or "retail"
end

function Flyouts.Presets()
    return Flyouts.PRESETS[Flyouts.Client()]
end

function Flyouts.Preset(key)
    for _, preset in ipairs(Flyouts.Presets()) do
        if preset.key == key then return preset end
    end
end

local function Whole(value, limit)
    return type(value) == "number" and value >= 1 and value <= limit and value == math.floor(value)
end

-- At most `limit` characters of UTF-8 text, never a broken character.
local function Prefix(text, limit)
    local out, count = {}, 0
    for char in text:gmatch("[%z\1-\127\194-\244][\128-\191]*") do
        count = count + 1
        if count > limit then break end
        out[count] = char
    end
    return table.concat(out)
end

-- A flyout or macro name: one line, trimmed, at most MAX_NAME characters.
function Flyouts.CleanName(name)
    if type(name) ~= "string" then return nil end
    name = name:gsub("%c", " "):match("^%s*(.-)%s*$")
    if name == "" then return nil end
    name = Prefix(name, Flyouts.MAX_NAME):match("^(.-)%s*$")
    return name ~= "" and name or nil
end

-- One entry as saved: { kind, id }; nil when malformed.
function Flyouts.CleanEntry(entry)
    if type(entry) ~= "table" or not Flyouts.KINDS[entry.kind] then return nil end
    local kind, id = entry.kind, entry.id
    if kind == "bag" then return Flyouts.BAGS[id] and { kind = kind, id = id } or nil end
    if kind == "macro" then
        id = Flyouts.CleanName(id)
        return id and { kind = kind, id = id } or nil
    end
    return Whole(id, 2147483647) and { kind = kind, id = id } or nil
end

local function SameEntry(a, b)
    return a.kind == b.kind and a.id == b.id
end
Flyouts.SameEntry = SameEntry

-- One flyout as saved; nil when it has no valid id or name.
function Flyouts.CleanFlyout(flyout)
    if type(flyout) ~= "table" or not Whole(flyout.id, 999999) then return nil end
    local name = Flyouts.CleanName(flyout.name)
    if not name then return nil end
    local clean = { id = flyout.id, name = name, owned = flyout.owned ~= false, entries = {},
        icon = Whole(flyout.icon, 2147483647) and flyout.icon or nil,
        preset = type(flyout.preset) == "string" and #flyout.preset <= 32 and flyout.preset or nil }
    if type(flyout.entries) == "table" then
        for _, entry in ipairs(flyout.entries) do
            local valid = Flyouts.CleanEntry(entry)
            local duplicate = false
            for _, kept in ipairs(clean.entries) do
                if valid and SameEntry(kept, valid) then duplicate = true break end
            end
            if valid and not duplicate and #clean.entries < Flyouts.MAX_ENTRIES then
                clean.entries[#clean.entries + 1] = valid
            end
        end
    end
    return clean
end

-- One WoW version's saved flyouts: { version, nextID, list }.
function Flyouts.CleanStore(saved)
    local store = { version = Flyouts.VERSION, nextID = 1, list = {} }
    if type(saved) ~= "table" then return store end
    local seen = {}
    if type(saved.list) == "table" then
        for _, flyout in ipairs(saved.list) do
            local clean = Flyouts.CleanFlyout(flyout)
            if clean and not seen[clean.id] and #store.list < Flyouts.MAX_FLYOUTS then
                seen[clean.id] = true
                store.list[#store.list + 1] = clean
                if clean.id >= store.nextID then store.nextID = clean.id + 1 end
            end
        end
    end
    if Whole(saved.nextID, 999999) and saved.nextID > store.nextID then store.nextID = saved.nextID end
    return store
end

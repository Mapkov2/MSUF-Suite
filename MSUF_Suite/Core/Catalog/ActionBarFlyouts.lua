local _, NS = ...
-- Action bar flyouts: one macro on any Suite action button opens a row of
-- spells, items, toys, mounts or macros next to it, also in combat
-- (MSUF_Suite_ActionBars/Flyouts.lua and FlyoutFrames.lua). The flyouts
-- belong to the account and to the WoW version: Retail and WoW Forever keep
-- separate lists in MSUFSuiteFlyoutsDB. The core holds their shape, limits and
-- presets so the options page can read them without the action bar addon.
local Flyouts = { VERSION = 1, MAX_FLYOUTS = 40, MAX_ENTRIES = 120, MAX_SHOWN = 24, MAX_NAME = 16, PER_LINE = 12 }
NS.ActionBarFlyouts = Flyouts

local ARROW_MEDIA = "Interface\\AddOns\\MSUF_Suite\\Media\\FlyoutArrow"
local ARROW_TEXTURES = { [2] = ARROW_MEDIA .. "Modern", [3] = ARROW_MEDIA .. "Dark", [4] = ARROW_MEDIA .. "Forever" }
local ARROW_LAYOUT = {
    UP = { "TOP", 0, -1, 0 },
    DOWN = { "BOTTOM", 0, 1, math.pi },
    LEFT = { "LEFT", 1, 0, math.pi / 2 },
    RIGHT = { "RIGHT", -1, 0, -math.pi / 2 },
}

function Flyouts.StyleArrow(arrow, style, size)
    local texture = ARROW_TEXTURES[style]
    if texture then
        arrow:SetTexture(texture)
        arrow:SetSize(size, size)
    else
        arrow:SetAtlas("ui-hud-actionbar-pageuparrow-up", false)
        arrow:SetSize(size, math.floor(size * 11 / 14 + .5))
    end
end

function Flyouts.PositionArrow(arrow, anchor, direction)
    local layout = ARROW_LAYOUT[direction] or ARROW_LAYOUT.UP
    arrow:ClearAllPoints()
    arrow:SetPoint(layout[1], anchor, layout[1], layout[2], layout[3])
    arrow:SetRotation(layout[4])
end

-- Bag and spellbook entries follow the character instead of saving a snapshot.
Flyouts.KINDS = { spell = true, item = true, toy = true, mount = true, macro = true, bag = true, spellbook = true }
Flyouts.BAGS = { food = true, potion = true, bandage = true, keys = true, keystone = true }
Flyouts.MAGE_BOOKS = { magePortals = { 12, 11 }, mageTeleports = { 8, 1 } }
Flyouts.SHAMAN_BOOK = "shamanUtility"

-- Blizzard's Hero's Path flyouts. Each set fits on an action bar flyout.
-- The menu takes the expansion labels from GetFlyoutInfo at runtime.
local DUNGEON_BOOKS = {
    { 246, "Midnight Paths" }, { 232, "TWW Paths" }, { 227, "Dragonflight" },
    { 220, "Shadowlands" }, { 223, "BfA Paths" }, { 224, "Legion Paths" },
    { 96, "Draenor Paths" }, { 84, "Pandaria Paths" }, { 230, "Cataclysm" }, { 274, "Wrath Paths" },
}
local RAID_BOOKS = { { 242, "TWW Raids" }, { 231, "DF Raids" }, { 222, "SL Raids" } }

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

local function Entries(kind, ids, entries)
    entries = entries or {}
    for _, id in ipairs(ids) do entries[#entries + 1] = { kind = kind, id = id } end
    return entries
end

local function Bag(id)
    return { { kind = "bag", id = id } }
end

local function Spellbook(id)
    return { { kind = "spellbook", id = id } }
end

-- Presets per WoW version. flyoutName is the new flyout's name (a macro name, at
-- most MAX_NAME characters); iconItem or iconSpell gives the macro its icon.
local BAG_FOOD = Bag("food")
local FOREVER_RETURN = Entries("spell", { 556, 18960 }, Entries("item", { 6948 }))
local RETAIL_RETURN = Entries("item", { 6948 })
Entries("toy", { 110560, 140192 }, RETAIL_RETURN)
Entries("spell", { 556, 193753, 18960, 126892, 50977, 265225, 1238686 }, RETAIL_RETURN)
Entries("item", { 63206, 63207, 63352, 63353, 65360, 65274, 44934, 44935, 40585, 46874 }, RETAIL_RETURN)
Entries("toy", { 54452, 64488, 142542, 162973, 165669, 168907, 172179, 184353 }, RETAIL_RETURN)

-- These two Forever items are toys on Retail, alongside the newer devices.
local FOREVER_ENGINEERING = { 18984, 18986 }
local RETAIL_ENGINEERING = {
    248485, 221966, 198156, 172924, 168807, 168808, 151652, 112059, 87215, 48933, 18984, 18986, 30542, 30544,
}

-- Language packs can be loaded after this catalog. Translate when a preset
-- is described or picked up, so the current Suite language is used.
local function Preset(preset, label, description, macroName)
    preset.flyoutName = preset.flyoutName or macroName or label
    function preset.Text()
        local title = label and NS.Text(label)
        return title, macroName and NS.Text(macroName) or title or preset.flyoutName,
            description and NS.Text(description)
    end
    return preset
end

local COMMON_PRESETS = {
    Preset({ key = "magePortals", iconSpell = 10059, class = "MAGE", entries = Spellbook("magePortals") },
        "Mage portals", "Shows the spells you have learned."),
    Preset({ key = "mageTeleports", iconSpell = 3561, class = "MAGE", entries = Spellbook("mageTeleports") },
        "Mage teleports", "Shows the spells you have learned."),
    Preset({ key = "potions", iconItem = 13446, entries = Bag("potion") },
        "Potions", "Shows what you can use from your bags."),
    Preset({ key = "bandages", iconItem = 14530, entries = Bag("bandage") },
        "Bandages", "Shows what you can use from your bags."),
}

Flyouts.PRESETS = {
    forever = {
        Preset({ key = Flyouts.SHAMAN_BOOK, iconSpell = 8143, class = "SHAMAN", entries = Spellbook(Flyouts.SHAMAN_BOOK) },
            "Shaman utility", "Shows the spells you have learned."),
        Preset({ key = "keys", icon = 134237, entries = Bag("keys") },
            "Keys", "Shows keys in your bags and keyring."),
        Preset({ key = "hearthstones", iconItem = 6948, entries = FOREVER_RETURN },
            "Hearthstone / portals", nil, "Hearthstone"),
        Preset({ key = "engineering", iconItem = 18984, entries = Entries("item", FOREVER_ENGINEERING) },
            "Engineering teleports", nil, "Eng. teleports"),
        Preset({ key = "vendorFood", iconItem = 4540, entries = Entries("item", VENDOR_FOOD) },
            "Vendor food", "Bread, fruit, meat, cheese, mushrooms and fish from vendors. Shows what you carry, best first.", "Food"),
        Preset({ key = "vendorDrinks", iconItem = 159, entries = Entries("item", VENDOR_DRINKS) },
            "Vendor drinks", "Water from innkeepers and vendors. Shows what you carry, best first.", "Drinks"),
        Preset({ key = "cooking", iconItem = 2681, entries = Entries("item", NS.ForeverCookedFood) },
            "Cooking", "Cooked food and drinks with a food bonus. Shows what you carry, best first."),
        Preset({ key = "bagFood", iconItem = 4540, entries = BAG_FOOD },
            "Food and drink in bags", "Every food and drink in your bags that you can use, highest level first.", "Bag food"),
    },
    retail = {
        Preset({ key = "keystone", iconItem = 180653, entries = Bag("keystone") },
            "Keystone", "Click to pick up the Mythic+ keystone in your bags."),
        Preset({ key = "dungeonSeason", iconSpell = 1254400, category = "dungeons", entries = Spellbook("dungeonSeason") },
            "Current season", "Shows the spells you have learned.", "Season portals"),
        Preset({ key = "hearthstones", iconItem = 6948, entries = RETAIL_RETURN },
            "Hearthstone / portals", nil, "Hearthstone"),
        Preset({ key = "engineering", iconItem = 248485, entries = Entries("toy", RETAIL_ENGINEERING) },
            "Engineering teleports", nil, "Eng. teleports"),
        Preset({ key = "bagFood", iconItem = 4540, entries = BAG_FOOD },
            "Food and drink", "Every food and drink in your bags that you can use, highest level first.", "Food"),
    },
}

for _, presets in pairs(Flyouts.PRESETS) do
    for _, preset in ipairs(COMMON_PRESETS) do presets[#presets + 1] = preset end
end

local function AddPathPresets(books, category)
    local presets = Flyouts.PRESETS.retail
    for _, book in ipairs(books) do
        local id, name = book[1], book[2]
        presets[#presets + 1] = Preset({ key = "path" .. id, category = category, nativeBook = id,
            flyoutName = name, entries = Spellbook(id) }, nil, "Shows the spells you have learned.")
    end
end
AddPathPresets(DUNGEON_BOOKS, "dungeons")
AddPathPresets(RAID_BOOKS, "raids")

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
    if kind == "spellbook" then
        if not Flyouts.MAGE_BOOKS[id] and id ~= Flyouts.SHAMAN_BOOK and id ~= "dungeonSeason"
            and not Whole(id, 2147483647) then return nil end
        return { kind = kind, id = id }
    end
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

function Flyouts.ExclusionField(entry)
    if entry.kind == "bag" then return entry.id == "food" and "excludedFood" or "excludedItems" end
    if entry.kind == "spellbook" then return "excludedSpells" end
end

local function CleanExclusions(saved)
    if type(saved) ~= "table" then return nil end
    local excluded = {}
    for id, value in pairs(saved) do
        if value == true and Whole(id, 2147483647) then excluded[id] = true end
    end
    return next(excluded) and excluded or nil
end

-- One flyout as saved; nil when it has no valid id or name.
function Flyouts.CleanFlyout(flyout)
    if type(flyout) ~= "table" or not Whole(flyout.id, 999999) then return nil end
    local name = Flyouts.CleanName(flyout.name)
    if not name then return nil end
    local clean = { id = flyout.id, name = name, owned = flyout.owned ~= false, entries = {},
        icon = Whole(flyout.icon, 2147483647) and flyout.icon or nil,
        preset = type(flyout.preset) == "string" and #flyout.preset <= 32 and flyout.preset or nil }
    clean.excludedFood = CleanExclusions(flyout.excludedFood)
    clean.excludedItems = CleanExclusions(flyout.excludedItems)
    clean.excludedSpells = CleanExclusions(flyout.excludedSpells)
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

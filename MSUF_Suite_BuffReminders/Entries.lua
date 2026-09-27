local _, P = ...
local NS, S = P.NS, P.Suite
local R = P.BuffReminders
-- The reminder list: class buff, Rogue poisons, the configured spells, items
-- and weapon enchants, then the first owned consumable of each enabled
-- category. Selection runs on configuration, spell, spec, equipment and bag
-- events only, never on a timer.
local Public = S.Public
local MAX_ENTRIES = 12
local CLASS_BUFF, FLASKS, FOODS, RUNES, OILS = R.CLASS_BUFF, R.FLASKS, R.FOODS, R.RUNES, R.OILS
local FLASK_AURAS, RUNE_AURAS, OIL_WEAPON_LOCATIONS = R.FLASK_AURAS, R.RUNE_AURAS, R.OIL_WEAPON_LOCATIONS
local LETHAL_POISONS, NONLETHAL_POISONS = R.LETHAL_POISONS, R.NONLETHAL_POISONS
local ASSASSINATION_LETHAL_POISONS, OTHER_LETHAL_POISONS = R.ASSASSINATION_LETHAL_POISONS, R.OTHER_LETHAL_POISONS
local Clear, Known, ItemCount = R.Clear, R.Known, R.ItemCount
-- The automatic consumable picks remembered by Compile. A bag update only
-- recompiles when one of these picks changed.
local STOCK = {
    { key = "stockFlask", items = FLASKS },
    { key = "stockFood", items = FOODS },
    { key = "stockRune", items = RUNES },
    { key = "stockOil", items = OILS },
}

local function ID(value)
    local id = tonumber(value)
    if id and id > 0 and id < 10000000 and id == math.floor(id) then return id end
end

local function FirstStocked(items)
    for index = 1, #items do
        local itemID = items[index]
        local count = ItemCount(itemID)
        if count and count > 0 then return itemID end
    end
end

local function OilWeaponEquipped(slot)
    local itemID = GetInventoryItemID("player", slot)
    if not Public(itemID) or type(itemID) ~= "number" then return false end
    local _, _, _, location, _, classID = C_Item.GetItemInfoInstant(itemID)
    if not Public(location) or not Public(classID) then return false end
    -- ItemClass.Weapon is 2; a shield, held item or ranged weapon is not an oil target.
    return classID == 2 and OIL_WEAPON_LOCATIONS[location] == true
end

local function OwnWeaponImbueKnown()
    local _, class = UnitClass("player")
    if not Public(class) or type(class) ~= "string" then return true end
    if class == "SHAMAN" then
        return Known(382021) or Known(318038) or Known(33757)
    end
    if class == "PALADIN" then return Known(433583) or Known(433568) end
    return false
end

-- Compile builds the reminder list into the idle one of two buffers and keeps
-- it only when it differs from the active list. An unchanged compile (every
-- SPELLS_CHANGED, equipment or bag event) reuses the records and allocates
-- nothing; duplicates are tracked by numeric aura and slot IDs.
local function NewBuffer()
    return { list = {}, records = {}, lethal = {}, nonlethal = {} }
end
local buffers = { NewBuffer(), NewBuffer() }
local building
local seenAuras, seenSlots = {}, {}
local seenFood = false

local function Full()
    return #building.list >= MAX_ENTRIES
end

-- Whether an entry of this kind, aura or slot is already in the list; marks
-- it taken otherwise.
local function Claim(kind, auraID, slot, aliases, poison, poisonRank)
    -- Each poison rank is added once by its group; weapon, food and aura
    -- entries are unique per slot, kind or aura.
    if slot then
        if seenSlots[slot] then return false end
    elseif kind == "food" then
        if seenFood then return false end
    elseif not poison and seenAuras[auraID] then
        return false
    end
    local claimsAliases = aliases and not (poison and poisonRank > 1)
    if claimsAliases then
        for index = 1, #aliases do
            if seenAuras[aliases[index]] then return false end
        end
    end
    if slot then
        seenSlots[slot] = true
    elseif kind == "food" then
        seenFood = true
    elseif not poison then
        seenAuras[auraID] = true
    end
    if claimsAliases then
        for index = 1, #aliases do seenAuras[aliases[index]] = true end
    end
    return true
end

local function Add(kind, itemID, auraID, slot, aliases, poison, poisonRank, candidates)
    if not itemID or Full() or not Claim(kind, auraID, slot, aliases, poison, poisonRank) then return end
    local list, records = building.list, building.records
    local count = #list + 1
    local entry = records[count]
    if not entry then
        entry = {}
        records[count] = entry
    end
    entry.kind, entry.id, entry.aura, entry.slot = kind, itemID, auraID, slot
    entry.aliases, entry.poison, entry.poisonRank, entry.candidates = aliases, poison, poisonRank, candidates
    -- A reused record forgets the runtime state of its previous entry.
    entry.bit, entry.present, entry.expiresAt, entry.totalDuration = nil, nil, nil, nil
    entry.auraInstanceID, entry.instanceIDs, entry.actionID, entry.count = nil, nil, nil, nil
    list[count] = entry
end

function R.SameEntries(left, right)
    if not left or #left ~= #right then return false end
    for index = 1, #right do
        local a, b = left[index], right[index]
        if a.kind ~= b.kind or a.id ~= b.id or a.aura ~= b.aura
            or a.slot ~= b.slot or a.aliases ~= b.aliases or a.poison ~= b.poison
            or a.poisonRank ~= b.poisonRank then
            return false
        end
        if a.candidates or b.candidates then
            if not a.candidates or not b.candidates or #a.candidates ~= #b.candidates then return false end
            for offset = 1, #a.candidates do
                if a.candidates[offset] ~= b.candidates[offset] then return false end
            end
        end
    end
    return true
end

local function PlayerClass()
    local _, value = UnitClass("player")
    if Public(value) then return value end
end

-- name is "lethal" or "nonlethal": the building buffer's candidate list.
local function AddPoisonGroup(name, aliases, priority, perCategory)
    local candidates = building[name]
    for index = #candidates, 1, -1 do candidates[index] = nil end
    for index = 1, #priority do
        local spellID = priority[index]
        if Known(spellID) then candidates[#candidates + 1] = spellID end
    end
    for rank = 1, math.min(perCategory, #candidates) do
        Add("spell", candidates[rank], candidates[rank], nil, aliases, name, rank, candidates)
    end
end

-- C_SpecializationInfo directly: the global GetSpecialization shims exist only
-- while Blizzard's deprecation fallbacks are loaded.
local function AddRoguePoisons()
    local specIndex = C_SpecializationInfo.GetSpecialization()
    if not Public(specIndex) or type(specIndex) ~= "number" or specIndex <= 0 then return end
    local specID = C_SpecializationInfo.GetSpecializationInfo(specIndex)
    if not Public(specID) or not (specID == 259 or specID == 260 or specID == 261) then return end
    -- Dragon-Tempered Blades permits two poisons per category on Assassination.
    local perCategory = specID == 259 and Known(381801) and 2 or 1
    AddPoisonGroup("lethal", LETHAL_POISONS,
        specID == 259 and ASSASSINATION_LETHAL_POISONS or OTHER_LETHAL_POISONS, perCategory)
    AddPoisonGroup("nonlethal", NONLETHAL_POISONS, NONLETHAL_POISONS, perCategory)
end

-- The configured ID lists are parsed when their setting text changes.
local configured = { spellText = false, spells = {}, itemText = false, items = {}, itemAuras = {} }
local function ParseConfigured(c)
    if configured.spellText ~= c.spellIDs then
        local spells = configured.spells
        for index = #spells, 1, -1 do spells[index] = nil end
        for token in c.spellIDs:gmatch("%d+") do
            local spellID = ID(token)
            if spellID then spells[#spells + 1] = spellID end
        end
        configured.spellText = c.spellIDs
    end
    if configured.itemText ~= c.items then
        local items, auras = configured.items, configured.itemAuras
        for index = #items, 1, -1 do items[index], auras[index] = nil, nil end
        for token in c.items:gmatch("[^,%s]+") do
            local item, aura = token:match("^(%d+):(%d+)$")
            local itemID, auraID = ID(item), ID(aura)
            if itemID and auraID then
                local index = #items + 1
                items[index], auras[index] = itemID, auraID
            end
        end
        configured.itemText = c.items
    end
end

local function AddConfigured(c)
    ParseConfigured(c)
    local spells, items, auras = configured.spells, configured.items, configured.itemAuras
    for index = 1, #spells do Add("spell", spells[index], spells[index]) end
    for index = 1, #items do Add("item", items[index], auras[index]) end
    local mainID, offID = ID(c.mainHandItem), ID(c.offHandItem)
    if mainID then Add("weapon", mainID, nil, 16) end
    if offID then Add("weapon", offID, nil, 17) end
    return mainID, offID
end

-- Automatic consumables: the first owned item of each enabled category.
-- Every evaluated pick is remembered (false for "none owned").
local function AddStocked(self, c, mainID, offID)
    if c.autoFlask and not Full() then
        local itemID = FirstStocked(FLASKS)
        self.stockFlask = itemID or false
        if itemID then Add("item", itemID, FLASK_AURAS[1], nil, FLASK_AURAS) end
    end
    if c.autoFood and not Full() then
        local itemID = FirstStocked(FOODS)
        self.stockFood = itemID or false
        if itemID then Add("food", itemID) end
    end
    if c.autoRune and not Full() then
        local itemID = FirstStocked(RUNES)
        self.stockRune = itemID or false
        if itemID then Add("item", itemID, RUNE_AURAS[1], nil, RUNE_AURAS) end
    end
    if c.autoWeapon and not Full() and (not mainID or not offID) then
        local itemID = FirstStocked(OILS)
        self.stockOil = itemID or false
        if itemID and not OwnWeaponImbueKnown() then
            if not mainID and OilWeaponEquipped(16) then Add("weapon", itemID, nil, 16) end
            if not offID and not Full() and OilWeaponEquipped(17) then Add("weapon", itemID, nil, 17) end
        end
    end
end

-- Whether a bag update changed one of the remembered consumable picks.
function R.StockChanged(self)
    for i = 1, #STOCK do
        local picked = self[STOCK[i].key]
        if picked ~= nil and (FirstStocked(STOCK[i].items) or false) ~= picked then return true end
    end
    return false
end

-- Returns the new list, built into the buffer that self.entries does not use.
function R.BuildEntries(self)
    building = self.entries == buffers[1].list and buffers[2] or buffers[1]
    local list = building.list
    for index = #list, 1, -1 do list[index] = nil end
    Clear(seenAuras)
    Clear(seenSlots)
    seenFood = false
    local c = self.config
    local class = PlayerClass()
    for i = 1, #STOCK do self[STOCK[i].key] = nil end
    if c.classBuff then
        local buff = CLASS_BUFF[class]
        if buff and Known(buff.cast) then Add("spell", buff.cast, buff.auras[1], nil, buff.auras) end
    end
    if NS.Client.modernEquipment and c.autoRoguePoisons and class == "ROGUE" then AddRoguePoisons() end
    local mainID, offID = AddConfigured(c)
    if NS.Client.modernEquipment then AddStocked(self, c, mainID, offID) end
    return list
end

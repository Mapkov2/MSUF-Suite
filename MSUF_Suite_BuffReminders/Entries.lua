local _, P = ...
local NS, S = P.NS, P.Suite
local R = P.BuffReminders
-- The reminder list: class buff, Rogue poisons, the configured spells, items
-- and weapon enchants, then the first owned consumable of each enabled
-- category. Selection runs on configuration, spell, spec, equipment and bag
-- events only, never on a timer.
local Public = S.Public
local MAX_ENTRIES = 12
local FLASKS, RUNES, OILS = R.FLASKS, R.RUNES, R.OILS
local FLASK_AURAS, RUNE_AURAS, OIL_WEAPON_LOCATIONS = R.FLASK_AURAS, R.RUNE_AURAS, R.OIL_WEAPON_LOCATIONS
local LETHAL_POISONS, NONLETHAL_POISONS = R.LETHAL_POISONS, R.NONLETHAL_POISONS
local ASSASSINATION_LETHAL_POISONS, OTHER_LETHAL_POISONS = R.ASSASSINATION_LETHAL_POISONS, R.OTHER_LETHAL_POISONS
local Clear, Known, ItemCount = R.Clear, R.Known, R.ItemCount
-- The automatic consumable picks remembered by Compile (the stock state's
-- fields). A bag update only recompiles when one of these picks changed. A
-- choice is the item the player wants used first while it is in the bags.
local STOCK = {
    { key = "flask", choice = "flaskChoice", items = FLASKS },
    { key = "rune", choice = "runeChoice", items = RUNES },
    { key = "oil", choice = "oilChoice", items = OILS },
}

local function ID(value)
    local id = tonumber(value)
    if id and id > 0 and id < 10000000 and id == math.floor(id) then return id end
end

local function Preferred(items, value)
    local id = ID(value)
    if id then
        for index = 1, #items do
            if items[index] == id then return id end
        end
    end
end

local function FirstStocked(items, preference)
    local preferred = Preferred(items, preference)
    if preferred then
        local count = ItemCount(preferred)
        if count and count > 0 then return preferred end
    end
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
local buildingCategory = "personal"
local seenAuras, seenSlots = {}, {}
local seenFood = false

local function Full()
    return #building.list >= MAX_ENTRIES
end

-- Whether none of the aliases is in the list yet; marks them taken then.
local function ClaimAliases(aliases)
    if not aliases then return true end
    for index = 1, #aliases do
        if seenAuras[aliases[index]] then return false end
    end
    for index = 1, #aliases do seenAuras[aliases[index]] = true end
    return true
end

-- Whether neither the aura nor one of its aliases is in the list yet; marks
-- them taken then.
local function ClaimAura(auraID, aliases)
    if seenAuras[auraID] or not ClaimAliases(aliases) then return false end
    seenAuras[auraID] = true
    return true
end

-- The next record of the building list, reset to a new entry of this kind.
-- A reused record forgets the runtime state of its previous entry.
local function Append(kind, id)
    local list, records = building.list, building.records
    local count = #list + 1
    local entry = records[count]
    if not entry then
        entry = {}
        records[count] = entry
    end
    entry.kind, entry.id, entry.aura, entry.slot = kind, id, nil, nil
    entry.aliases, entry.poison, entry.poisonRank, entry.candidates = nil, nil, nil, nil
    entry.restock = false
    entry.category = buildingCategory
    entry.group, entry.notice, entry.missingCount = nil, nil, nil
    entry.ranked, entry.spellName = nil, nil
    entry.bit, entry.present, entry.expiresAt, entry.totalDuration = nil, nil, nil, nil
    entry.auraInstanceID, entry.instanceIDs, entry.actionID, entry.count = nil, nil, nil, nil
    list[count] = entry
    return entry
end

-- One constructor per reminder kind. Each returns the new entry, or nil when
-- the list is full or the entry's aura, slot or the food reminder is taken.
-- restock marks the gray, inert reminder of an empty stack.

-- A spell the player casts; its aura (or one of the aliases) satisfies it.
local function AddSpell(spellID, auraID, aliases)
    if not spellID or Full() or not ClaimAura(auraID, aliases) then return end
    local entry = Append("spell", spellID)
    entry.aura, entry.aliases = auraID, aliases
    return entry
end

-- An item the player uses; its aura (or one of the aliases) satisfies it.
local function AddItem(itemID, auraID, restock, aliases)
    if not itemID or Full() or not ClaimAura(auraID, aliases) then return end
    local entry = Append("item", itemID)
    entry.aura, entry.aliases, entry.restock = auraID, aliases, restock == true
    return entry
end

-- A temporary enchant on one weapon slot (16 main hand, 17 off hand).
local function AddWeapon(itemID, slot, restock)
    if not itemID or Full() or seenSlots[slot] then return end
    seenSlots[slot] = true
    local entry = Append("weapon", itemID)
    entry.slot, entry.restock = slot, restock == true
    return entry
end

-- The one food reminder: the food it clicks, or the Well Fed spell.
local function AddFood(id, restock)
    if not id or Full() or seenFood then return end
    seenFood = true
    local entry = Append("food", id)
    entry.restock = restock == true
    return entry
end

-- One slot (rank) of a Rogue poison group, "lethal" or "nonlethal". Only the
-- first rank claims the group's aliases; candidates are the group's known
-- poisons in the order the slots take them.
local function AddPoison(group, rank, candidates, aliases)
    local spellID = candidates[rank]
    if not spellID or Full() or rank == 1 and not ClaimAliases(aliases) then return end
    local entry = Append("spell", spellID)
    entry.aura, entry.aliases, entry.candidates = spellID, aliases, candidates
    entry.poison, entry.poisonRank = group, rank
    return entry
end

function R.SameEntries(left, right)
    if not left or #left ~= #right then return false end
    for index = 1, #right do
        local a, b = left[index], right[index]
        if a.kind ~= b.kind or a.id ~= b.id or a.aura ~= b.aura
            or a.slot ~= b.slot or a.aliases ~= b.aliases or a.poison ~= b.poison
            or a.poisonRank ~= b.poisonRank or a.restock ~= b.restock or a.group ~= b.group or a.notice ~= b.notice
            or a.category ~= b.category or a.ranked ~= b.ranked or a.spellName ~= b.spellName then
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

-- group is "lethal" or "nonlethal": the building buffer's candidate list.
local function AddPoisonGroup(group, aliases, priority, perCategory)
    local candidates = building[group]
    for index = #candidates, 1, -1 do candidates[index] = nil end
    for index = 1, #priority do
        local spellID = priority[index]
        if Known(spellID) then candidates[#candidates + 1] = spellID end
    end
    for rank = 1, math.min(perCategory, #candidates) do AddPoison(group, rank, candidates, aliases) end
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

-- A spell the client has data for (a name); asked on compile only.
local function SpellExists(spellID)
    local name = C_Spell.GetSpellName(spellID)
    return Public(name) and name ~= nil
end

local function AddConfigured(c)
    ParseConfigured(c)
    local spells, items, auras = configured.spells, configured.items, configured.itemAuras
    buildingCategory = "personal"
    -- Camp Benefits cannot be cast: the reminder is a notice without a click.
    if NS.Client.isForever and c.campfireBuff and SpellExists(R.CAMP_BENEFITS) then
        local entry = AddSpell(R.CAMP_BENEFITS, R.CAMP_BENEFITS)
        if entry then entry.notice = "camp" end
    end
    for index = 1, #spells do AddSpell(spells[index], spells[index]) end
    buildingCategory = "consumable"
    for index = 1, #items do AddItem(items[index], auras[index]) end
    local mainID, offID = ID(c.mainHandItem), ID(c.offHandItem)
    if mainID then AddWeapon(mainID, 16) end
    if offID then AddWeapon(offID, 17) end
    return mainID, offID
end

-- The item a category uses: the first one in the bags (false for none), and
-- the gray restock item when none is left and restock notices are on.
local function Pick(self, c, stock)
    local itemID = FirstStocked(stock.items, c[stock.choice])
    self.stock[stock.key] = itemID or false
    if itemID then return itemID, false end
    if c.restockNotice ~= true then return nil, false end
    return Preferred(stock.items, c[stock.choice]) or stock.items[1], true
end

-- Bag items that are food: a Food & Drink consumable whose use spell is one
-- of the game's eating spells (R.EATING_SPELLS). The answer is kept per item
-- ID for the session; an item whose data has not arrived is asked again.
local EATING_SPELLS = R.EATING_SPELLS
local CONSUMABLE, FOOD_AND_DRINK = Enum.ItemClass.Consumable, Enum.ItemConsumableSubclass.Fooddrink
local foodItems = {}

local function IsFood(itemID)
    local food = foodItems[itemID]
    if food ~= nil then return food end
    local _, _, _, _, _, classID, subClassID = C_Item.GetItemInfoInstant(itemID)
    if not Public(classID) or not Public(subClassID) or classID ~= CONSUMABLE or subClassID ~= FOOD_AND_DRINK then
        foodItems[itemID] = false
        return false
    end
    local _, spellID = C_Item.GetItemSpell(itemID)
    if not Public(spellID) or type(spellID) ~= "number" then return false end
    food = EATING_SPELLS[spellID] == true
    foodItems[itemID] = food
    return food
end

-- The food in the bags with the highest item ID (the newest recipe).
local function BagFood()
    local best
    for bag = 0, Constants.InventoryConstants.NumBagSlots do
        for slot = 1, C_Container.GetContainerNumSlots(bag) do
            local itemID = C_Container.GetContainerItemID(bag, slot)
            if Public(itemID) and type(itemID) == "number" and (not best or itemID > best) and IsFood(itemID) then
                best = itemID
            end
        end
    end
    return best
end

-- The food the reminder clicks: the chosen one while it is in the bags, else
-- the newest food in the bags (false for none).
local function FoodPick(c)
    local choice = ID(c.foodChoice)
    if choice then
        local count = ItemCount(choice)
        if count and count > 0 then return choice end
    end
    return BagFood() or false
end

-- The Well Fed aura decides; the picked food is the click action. Without
-- food in the bags the reminder is a gray restock reminder (with restock
-- notices on) or a notice without a click.
local function AddFoodReminder(self, c)
    local stock = self.stock
    local food = FoodPick(c)
    stock.food = food
    if food then
        stock.lastFood = food
        AddFood(food)
        return
    end
    local restock = c.restockNotice == true
    local item = ID(c.foodChoice) or stock.lastFood
    if restock and item then
        AddFood(item, restock)
        return
    end
    local entry = AddFood(R.WELL_FED, restock)
    if entry then entry.notice = "food" end
end

-- Automatic consumables: the first owned item of each enabled category.
-- Every evaluated pick is remembered (false for "none owned").
local function AddStocked(self, c, mainID, offID)
    if c.autoFlask and not Full() then
        local itemID, restock = Pick(self, c, STOCK[1])
        if itemID then AddItem(itemID, FLASK_AURAS[1], restock, FLASK_AURAS) end
    end
    if c.autoFood and not Full() then AddFoodReminder(self, c) end
    if c.autoRune and not Full() then
        local itemID, restock = Pick(self, c, STOCK[2])
        if itemID then AddItem(itemID, RUNE_AURAS[1], restock, RUNE_AURAS) end
    end
    if c.autoWeapon and not Full() and (not mainID or not offID) then
        local itemID, restock = Pick(self, c, STOCK[3])
        if itemID and not OwnWeaponImbueKnown() then
            if not mainID and OilWeaponEquipped(16) then AddWeapon(itemID, 16, restock) end
            if not offID and not Full() and OilWeaponEquipped(17) then AddWeapon(itemID, 17, restock) end
        end
    end
end

-- The potion the player wants on the maps they picked. The item's own use
-- spell is the aura it gives, asked from the game; an item whose data has
-- not arrived yet is requested and found by a later compile.
local potionMaps = { text = false, maps = {} }

function R.OnPotionMap(self)
    local c = self.config
    if not c.mapPotion then return false end
    if potionMaps.text ~= c.mapPotionMaps then
        Clear(potionMaps.maps)
        for token in c.mapPotionMaps:gmatch("%d+") do
            local mapID = ID(token)
            if mapID then potionMaps.maps[mapID] = true end
        end
        potionMaps.text = c.mapPotionMaps
    end
    if not next(potionMaps.maps) then return false end
    local map = C_Map.GetBestMapForUnit("player")
    return Public(map) and potionMaps.maps[map] == true
end

local function PotionAura(itemID)
    local _, spellID = C_Item.GetItemSpell(itemID)
    if Public(spellID) and type(spellID) == "number" then return spellID end
    C_Item.RequestLoadItemDataByID(itemID)
end

-- stock.potion remembers whether the potion was in the bags, so a bag update
-- that empties or refills the stack compiles again (R.StockChanged).
local function AddMapPotion(self, c)
    local stock = self.stock
    stock.onPotionMap = R.OnPotionMap(self)
    if not stock.onPotionMap then return end
    local itemID = ID(c.mapPotionItem)
    local aura = itemID and PotionAura(itemID)
    if not aura then return end
    local count = ItemCount(itemID)
    if count then stock.potion = count > 0 end
    if count and (count > 0 or c.restockNotice == true) then
        buildingCategory = "consumable"
        AddItem(itemID, aura, count == 0)
    end
end

local function PotionStockChanged(self)
    local potion = self.stock.potion
    if potion == nil then return false end
    local itemID = ID(self.config.mapPotionItem)
    local count = itemID and ItemCount(itemID)
    return count ~= nil and (count > 0) ~= potion
end

-- Whether a bag update changed one of the remembered consumable picks or
-- emptied or refilled the map potion.
function R.StockChanged(self)
    local picks = self.stock
    for i = 1, #STOCK do
        local stock = STOCK[i]
        local picked = picks[stock.key]
        if picked ~= nil and (FirstStocked(stock.items, self.config[stock.choice]) or false) ~= picked then return true end
    end
    if picks.food ~= nil and FoodPick(self.config) ~= picks.food then return true end
    return PotionStockChanged(self)
end

-- Returns the new list, built into the buffer the active list does not use.
function R.BuildEntries(self)
    building = self.list.entries == buffers[1].list and buffers[2] or buffers[1]
    local list = building.list
    for index = #list, 1, -1 do list[index] = nil end
    Clear(seenAuras)
    Clear(seenSlots)
    seenFood = false
    local c = self.config
    local class = PlayerClass()
    buildingCategory = "class"
    R.GroupRoster(self)
    local stock = self.stock
    for i = 1, #STOCK do stock[STOCK[i].key] = nil end
    stock.food, stock.potion = nil, nil
    if c.classBuff or c.groupBuff then
        local buff = R.ClassBuff(class)
        if buff and Known(buff.cast) then
            local entry = AddSpell(buff.cast, buff.auras[1], buff.auras)
            if entry then
                entry.group = c.groupBuff == true
                entry.ranked = NS.Client.isForever == true
                if entry.ranked then entry.spellName = R.RankName(buff.cast) end
            end
        end
    end
    if c.otherClassBuffs then
        for _, other in ipairs(R.BUFF_CLASSES) do
            local buff = R.ClassBuff(other)
            if buff and other ~= class and self.group.classes[other] then
                local entry = AddSpell(buff.cast, buff.auras[1], buff.auras)
                if entry then entry.notice = true; entry.ranked = NS.Client.isForever == true end
            end
        end
    end
    buildingCategory = "personal"
    if NS.Client.modernEquipment and c.autoRoguePoisons and class == "ROGUE" then AddRoguePoisons() end
    local mainID, offID = AddConfigured(c)
    if NS.Client.modernEquipment then AddStocked(self, c, mainID, offID) end
    AddMapPotion(self, c)
    return list
end

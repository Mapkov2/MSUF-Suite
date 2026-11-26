local _, P = ...
local NS, S = P.NS, P.Suite
local R = P.BuffReminders
local Public, Known, ItemCount = S.Public, R.Known, R.ItemCount

-- Forever 1.60.1.71139: SpellName, SpellEffect and the ItemXItemEffect join.
local CENSERS, MAGICAL_AWARENESS = { 275730, 281371 }, 1297774
local GATHER, TREASURE = { 2383, 2580 }, 2481
local SACRIFICE, IMP = 18788, 688
local SACRIFICE_AURAS = { 18789, 18790, 18791, 18792 }
local SACRIFICE_FAMILIES = { [15] = true, [16] = true, [17] = true, [23] = true }
R.SleepingBagResting = 1331671

-- An item's use effect applies these auras directly. Options ask for
-- coverage of a stat, so any rank of that stat's items satisfies it.
local STATS = {
    { key = "foreverIntellect", class = "MAGE", items = {
        { 250328, 1250918 }, { 9179, 11396 }, { 13447, 17535 }, { 10308, 12176 }, { 4419, 8098 },
        { 250354, 1250989 }, { 2290, 8097 }, { 250353, 1250988 }, { 955, 8096 }, { 3383, 3166 },
    } },
    { key = "foreverStrength", items = {
        { 250351, 1250986 }, { 9206, 11405 }, { 250350, 1250985 }, { 10310, 12179 }, { 4426, 8120 },
        { 250349, 1250984 }, { 2289, 8119 }, { 3391, 3164 }, { 6662, 8212 }, { 954, 8118 }, { 2454, 2367 },
    } },
    { key = "foreverAgility", items = {
        { 13452, 17538 }, { 250328, 1250918 }, { 9187, 11334 }, { 250350, 1250985 }, { 10309, 12174 },
        { 8949, 11328 }, { 4425, 8117 }, { 1477, 8116 }, { 3390, 3160 }, { 3012, 8115 }, { 2457, 2374 },
    } },
    { key = "foreverStamina", class = "PRIEST", items = {
        { 10307, 12178 }, { 4422, 8101 }, { 1711, 8100 }, { 1180, 8099 },
    } },
    { key = "foreverSpirit", class = "PRIEST", buff = R.DIVINE_SPIRIT, items = {
        { 250348, 1250981 }, { 250338, 1250941 }, { 250347, 1250979 }, { 13447, 17535 }, { 10306, 12177 },
        { 4424, 8114 }, { 250346, 1250978 }, { 1712, 8113 }, { 250345, 1250976 }, { 1181, 8112 }, { 250344, 1250974 },
    } },
    { key = "foreverHealth", items = {
        { 250329, 1250920 }, { 250335, 1250931 }, { 250334, 1250928 }, { 3825, 3593 }, { 2458, 2378 },
    } },
    { key = "foreverArmor", items = {
        { 250329, 1250920 }, { 13445, 11348 }, { 8951, 11349 }, { 10305, 12175 }, { 4421, 8095 },
        { 3389, 3220 }, { 1478, 8094 }, { 3013, 8091 }, { 5997, 673 },
    } },
}
for _, stat in ipairs(STATS) do
    local ids, auras = {}, {}
    stat.ids, stat.auras = ids, auras
    for _, item in ipairs(stat.items) do
        ids[#ids + 1], auras[#auras + 1] = item[1], item[2]
    end
end

-- SpellEquippedItems from the same build supplies the subclass masks.
-- Poisons and conjured stones use the imbue layer (effect 360). Oils and
-- blacksmithing stones use the independent temporary layer (effect 54).
local CLASS_IMBUES = {
    ROGUE = { mask = 173555, items = {
        8928, 8927, 8926, 6950, 6949, 6947, 20844, 8985, 8984, 2893, 2892,
        10922, 10921, 10920, 10918, 9186, 6951, 5237, 3776, 3775,
    } },
    -- The stones allow generic, two-handed and main-hand weapons.
    WARLOCK = { mainHandType = true, items = { 13701, 13700, 13699, 1254, 13603, 13602, 5522 } },
}
local TEMPORARY = {
    { mask = 42483, items = { 18262, 287980 } },
    { mask = 33219, items = { 12404, 7964, 2871, 2863, 2862, 287978 } },
    { mask = 9264, items = { 12643, 7965, 3241, 3240, 3239 } },
    { items = { 20749, 20750, 20746, 287979, 20744, 20748, 20747, 20745, 23123 } },
    { mask = 173555, items = { 3829, 3824 } },
    { mask = 1097203, items = { 23122 } },
}
local layerByItem = {}
for _, imbue in pairs(CLASS_IMBUES) do
    for _, item in ipairs(imbue.items) do layerByItem[item] = "imbue" end
end
for _, finish in ipairs(TEMPORARY) do
    for _, item in ipairs(finish.items) do layerByItem[item] = "temporary" end
end

function R.ForeverItemLayer(item)
    return layerByItem[item]
end

local function Stocked(items, checkUsable)
    for i = 1, #items do
        local id = items[i]
        local count = ItemCount(id)
        if count and count > 0 then
            if not checkUsable then return id, i end
            local usable = C_Item.IsUsableItem(id)
            if Public(usable) and usable == true then return id, i end
        end
    end
end

local function Fits(family, subclass)
    return family.mask == nil or bit.band(family.mask, 2 ^ subclass) ~= 0
end

local function TemporaryItem(subclass)
    for _, family in ipairs(TEMPORARY) do
        if Fits(family, subclass) then
            local item = Stocked(family.items, true)
            if item then return item end
        end
    end
end

local function UpdatePick(picks, key, item, building)
    if building then
        picks[key] = item or false
    else
        return picks[key] ~= (item or false)
    end
end

local function WeaponStock(self, class, picks, addWeapon, weaponSubclass)
    local c = self.config
    local imbue = c.foreverWeaponImbues and CLASS_IMBUES[class]
    local temp = c.foreverWeaponItems
    if not (imbue or temp) then return false end
    for slot = 16, 17 do
        local subclass, location = weaponSubclass(slot)
        local imbueItem = subclass and imbue and (not imbue.mainHandType or location ~= "INVTYPE_WEAPONOFFHAND")
            and Fits(imbue, subclass) and Stocked(imbue.items, true)
        local tempItem = subclass and temp and TemporaryItem(subclass)
        if UpdatePick(picks, slot, imbueItem, addWeapon) or UpdatePick(picks, -slot, tempItem, addWeapon) then
            return true
        end
        if addWeapon then
            if imbueItem then addWeapon(imbueItem, slot, false, "imbue") end
            if tempItem then addWeapon(tempItem, slot, false, "temporary") end
        end
    end
    return false
end

local function ConsumableStock(self, class, picks, addItem)
    local c = self.config
    if c.foreverMagicalAwareness and self.environment.instanceType == "party" then
        local item = Stocked(CENSERS)
        if UpdatePick(picks, "censer", item, addItem) then return true end
        if addItem and item then addItem(item, MAGICAL_AWARENESS) end
    end
    for _, stat in ipairs(STATS) do
        if c[stat.key] then
            local equivalent = stat.buff or R.ClassBuff(stat.class)
            local item, position
            if not equivalent or class ~= stat.class or not R.RaidBuffCast(equivalent) then
                item, position = Stocked(stat.ids, true)
            end
            if UpdatePick(picks, stat.key, item, addItem) then return true end
            if addItem and item then
                local entry = addItem(item, stat.auras[position], false, stat.auras, true)
                if entry then entry.blockingAuras = equivalent and equivalent.auras end
            end
        end
    end
    return false
end

local OPTION_KEYS = {
    "foreverMagicalAwareness", "foreverWeaponImbues", "foreverWeaponItems",
    "foreverGatherTracking", "foreverFindTreasure",
}
for _, stat in ipairs(STATS) do OPTION_KEYS[#OPTION_KEYS + 1] = stat.key end

function R.ForeverOptionsChanged(settings, config)
    local changed = false
    for _, key in ipairs(OPTION_KEYS) do
        if settings[key] ~= config[key] then settings[key], changed = config[key], true end
    end
    return changed
end

local function HasItemOptions(c)
    if c.foreverMagicalAwareness or c.foreverWeaponImbues or c.foreverWeaponItems then return true end
    for _, stat in ipairs(STATS) do if c[stat.key] then return true end end
    return false
end

function R.SyncForeverItemEvents(self, callback)
    local c = self.config
    if c.foreverSleepingBag or HasItemOptions(c) then
        R.Listen(self, "PLAYER_LEVEL_UP", callback)
    else
        self.context:RemoveEvent("PLAYER_LEVEL_UP")
    end
    if c.foreverWellFed and not self.listen.suspended then
        R.Listen(self, "ITEM_DATA_LOAD_RESULT", callback)
    else
        self.context:RemoveEvent("ITEM_DATA_LOAD_RESULT")
    end
end

function R.ForeverStockChanged(self, weaponSubclass)
    local picks = self.stock.forever
    local class = R.PlayerClass()
    return ConsumableStock(self, class, picks) or WeaponStock(self, class, picks, nil, weaponSubclass)
end

function R.AddForeverStock(self, class, addItem, addWeapon, weaponSubclass)
    local stock = self.stock
    if not HasItemOptions(self.config) then
        stock.forever = nil
        return
    end
    local picks = stock.forever or {}
    stock.forever = picks
    R.Clear(picks)
    ConsumableStock(self, class, picks, addItem)
    WeaponStock(self, class, picks, addWeapon, weaponSubclass)
end

function R.WantsSacrifice(self, class)
    local c = self.config
    return NS.Client.isForever and c.classReminders == true and c.classDemonicSacrifice == true
        and (class or R.PlayerClass()) == "WARLOCK" and Known(SACRIFICE)
end

local function SacrificeCast()
    local exists = UnitExists("pet")
    if not Public(exists) then return end
    if exists == false then
        if Known(IMP) then return IMP end
    elseif exists == true then
        local dead = UnitIsDeadOrGhost("pet")
        local _, family = UnitCreatureFamily("pet")
        if Public(dead) and dead == false and Public(family) and SACRIFICE_FAMILIES[family] then return SACRIFICE end
    end
end

function R.SacrificeChanged(self)
    local spell = self.stock.sacrifice
    return spell ~= nil and spell ~= (SacrificeCast() or false)
end

local function AddSacrifice(self, class, addSpell)
    self.stock.sacrifice = nil
    if not R.WantsSacrifice(self, class) then return end
    local spell = SacrificeCast()
    self.stock.sacrifice = spell or false
    if spell then
        local entry = addSpell(spell, SACRIFICE_AURAS[1], SACRIFICE_AURAS)
        if entry then
            entry.category = "class"
            if spell == SACRIFICE then entry.unit = "pet" end
        end
    end
end

function R.WantsForeverTracking(self)
    local c = self.config
    return NS.Client.isForever and (c.foreverFindTreasure and Known(TREASURE)
        or c.foreverGatherTracking and (Known(GATHER[1]) or Known(GATHER[2])))
end

function R.AddForeverSpells(self, class, addSpell)
    local c = self.config
    AddSacrifice(self, class, addSpell)
    if c.foreverGatherTracking then
        local spell = Known(GATHER[1]) and GATHER[1] or Known(GATHER[2]) and GATHER[2]
        local entry = spell and addSpell(spell, GATHER[1], GATHER)
        if entry then entry.tracking = "gathering" end
    end
    if c.foreverFindTreasure and Known(TREASURE) then
        local entry = addSpell(TREASURE, TREASURE)
        if entry then entry.tracking = "treasure" end
    end
end

-- Gathering is an aura; a class's active spell tracker shares its slot.
-- Find Treasure uses an independent minimap toggle without a player aura.
function R.TrackingPresent(mode)
    local count = C_Minimap.GetNumTrackingTypes()
    if not Public(count) or type(count) ~= "number" then return nil end
    local unknown = false
    for i = 1, count do
        local entry = C_Minimap.GetTrackingInfo(i)
        if not Public(entry) or entry and not (Public(entry.active) and Public(entry.type) and Public(entry.spellID)) then
            unknown = true
        elseif entry and entry.type == "spell" and entry.active then
            local spell = entry.spellID
            if spell == nil then
                unknown = true
            elseif (spell == TREASURE) == (mode == "treasure") then
                return true
            end
        end
    end
    if not unknown then return false end
end

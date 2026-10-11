-- Buff reminders brought back in the module's own form: the Forever campfire
-- buff, a potion on maps the player picks, food found in the bags from the
-- game's eating spells, learned demon looks and the keystone and ready check
-- options. The client model follows Blizzard's API on Retail and Forever.
local root = assert(arg[1], "repository root required")
local Support = dofile(root .. "/tools/tests/suite_test_support.lua")
local function eq(a, b, label) assert(a == b, label .. ": " .. tostring(a) .. " ~= " .. tostring(b)) end

local function Widget()
    local w = { shown = true, attributes = {}, events = {} }
    function w:SetScript(name, callback) self[name] = callback end
    function w:SetAttribute(key, value) self.attributes[key] = value end
    function w:CreateTexture() return Widget() end
    function w:CreateFontString() return Widget() end
    function w:RegisterForClicks() end
    function w:SetShown(value) self.shown = value end
    function w:Show() self.shown = true end
    function w:Hide() self.shown = false end
    function w:SetText(value) self.text = value end
    function w:SetTexture(value) self.texture = value end
    function w:SetDesaturated(value) self.desaturated = value end
    function w:SetTexCoord() end
    function w:SetColorTexture() end
    function w:SetAllPoints() end
    function w:SetPoint() end
    function w:ClearAllPoints() end
    function w:SetSize() end
    function w:SetAlpha() end
    function w:CreateAnimationGroup()
        local group = {}
        function group:SetLooping() end
        function group:Play() self.playing = true end
        function group:Stop() self.playing = false end
        function group:CreateAnimation()
            return { SetFromAlpha = function() end, SetToAlpha = function() end, SetDuration = function() end }
        end
        return group
    end
    return w
end
UIParent = Widget()
CreateFrame = function() return Widget() end
RegisterStateDriver, UnregisterStateDriver = function() end, function() end
GameTooltip = Widget()
function GameTooltip:SetOwner() self.lines = {} end
function GameTooltip:SetSpellByID(id) self.spell = id end
function GameTooltip:SetItemByID(id) self.item = id end
function GameTooltip:AddLine(text) self.lines[#self.lines + 1] = text end

local known = {}
local spellNames = { [104280] = "Well Fed", [1219179] = "Become Well Fed", [1232076] = "Hearty Well Fed" }
local auras, namedAuras, inventory = {}, {}, {}
Enum = {
    SpellBookSpellBank = { Player = 0, Pet = 1 }, PowerType = { Mana = 0 },
    ItemClass = { Consumable = 0 }, ItemConsumableSubclass = { Fooddrink = 5 },
}
Constants = { InventoryConstants = { NumBagSlots = 4 } }
DifficultyUtil = { ID = { DungeonTimewalker = 24, RaidTimewalker = 33 } }
C_SpellBook = {
    IsSpellKnown = function(id) return known[id] == true end,
    IsSpellInSpellBook = function() return false end,
}
C_Spell = {
    GetSpellName = function(id) return spellNames[id] end,
    GetSpellTexture = function(id) return id end,
}
-- Bag contents: bag -> { slot -> item ID }; every item ID has its game data.
local bags = { [0] = {}, [1] = {}, [2] = {}, [3] = {}, [4] = {} }
local itemData = {}
local itemDataReads = 0
C_Container = {
    GetContainerNumSlots = function(bag) return bags[bag] and 16 or 0 end,
    GetContainerItemID = function(bag, slot) return bags[bag] and bags[bag][slot] end,
}
C_Item = {
    GetItemCount = function(id)
        local count = 0
        for _, slots in pairs(bags) do
            for _, itemID in pairs(slots) do if itemID == id then count = count + 1 end end
        end
        return count + (inventory[id] or 0)
    end,
    GetItemIconByID = function(id) return id end,
    GetItemInfoInstant = function(id)
        itemDataReads = itemDataReads + 1
        local data = itemData[id]
        if not data then return id, "Misc", "Junk", "", 0, 15, 0 end
        return id, "Consumable", "Food & Drink", "", 0, data.class or 0, data.subclass or 5
    end,
    GetItemSpell = function(id)
        local data = itemData[id]
        if data and data.spell then return "Refreshment", data.spell end
    end,
}
C_UnitAuras = {
    GetPlayerAuraBySpellID = function(id) return auras[id] end,
    GetAuraDataBySpellName = function(_, name) return namedAuras[name] end,
}
C_Secrets = { ShouldAurasBeSecret = function() return false end }
C_Timer = { NewTimer = function(_, callback) return { callback = callback, Cancel = function(t) t.cancelled = true end } end,
    After = function() end }
GetTime = function() return 100 end
UnitClass = function() return "Mage", "MAGE" end
IsInRaid = function() return false end
GetNumSubgroupMembers = function() return 0 end
GetInventoryItemID = function() return nil end

local S = {
    Public = function(value) return not (type(value) == "table" and value.secret) end,
    Install = function(_, module) _G.restoredModule = module end,
    Text = function(value) return value end,
    CreateFrame = function(...) return CreateFrame(...) end,
    CreateTexture = function(parent, ...) return parent:CreateTexture(...) end,
    CreateFontString = function(parent, ...) return parent:CreateFontString(...) end,
    RGB = function() return 1, 1, 1 end,
    SetFont = function() end, ResolveFont = function(value) return value end,
    RegisterOwnedMover = function() end,
}
local config, catalogNS = Support.CatalogDefaults(root, "buffReminders")
local NS = { IsCombatLocked = function() return false end, Client = { isForever = false, modernEquipment = true,
    SupportsEvent = function() return true end }, AnchorPoints = { "CENTER" },
    BuffReminderDemons = catalogNS.BuffReminderDemons }
-- The module reads the catalog defaults where a profile lacks a key.
catalogNS.Defaults = {}
catalogNS.FinalizeCatalog()
NS.Defaults = catalogNS.Defaults
local private = { NS = NS, Suite = S }
Support.Load(root, "MSUF_Suite_BuffReminders", private, nil, { ["Bootstrap.lua"] = true })
local R = private.BuffReminders
local function Owner(overrides)
    local owner = R.NewState({ config = {} })
    for key, value in pairs(config) do owner.config[key] = value end
    for key, value in pairs(overrides or {}) do owner.config[key] = value end
    return owner
end
local function Find(list, id)
    for _, entry in ipairs(list) do if entry.id == id then return entry end end
end

-- Forever's campfire buff: a notice (no click) while the buff is missing, on
-- Forever only and only while the client knows the spell.
do
    local owner = Owner({ classBuff = false, campfireBuff = true })
    spellNames[R.CAMP_BENEFITS] = "Camp Benefits"
    eq(Find(R.BuildEntries(owner), R.CAMP_BENEFITS), nil, "the campfire reminder showed on Retail")
    NS.Client.isForever, NS.Client.modernEquipment = true, false
    spellNames[R.CAMP_BENEFITS] = nil
    eq(Find(R.BuildEntries(owner), R.CAMP_BENEFITS), nil, "the campfire reminder ran without the client knowing the spell")
    spellNames[R.CAMP_BENEFITS] = "Camp Benefits"
    local entry = Find(R.BuildEntries(owner), R.CAMP_BENEFITS)
    assert(entry and entry.notice == "camp" and entry.kind == "spell" and entry.category == "personal",
        "the campfire buff is not a personal notice on Forever")
    eq(R.AuraPresent(entry), false, "a missing Camp Benefits buff was not reported missing")
    auras[R.CAMP_BENEFITS] = { auraInstanceID = 5, expirationTime = 0, duration = 0 }
    eq(R.AuraPresent(entry), true, "an active Camp Benefits buff still showed the reminder")
    auras[R.CAMP_BENEFITS] = nil
    owner.config.campfireBuff = false
    eq(Find(R.BuildEntries(owner), R.CAMP_BENEFITS), nil, "the campfire reminder ignored its switch")
    NS.Client.isForever, NS.Client.modernEquipment = false, true
end

-- A potion on maps the player picks (Inky Black Potion by default). Its aura
-- is the item's own use spell; subzone steps are followed only while the
-- option has maps, and they compile only when the player crossed a map edge.
local currentMap = 100
C_Map = { GetBestMapForUnit = function(unit) assert(unit == "player"); return currentMap end }
local loadRequests = {}
C_Item.RequestLoadItemDataByID = function(id) loadRequests[#loadRequests + 1] = id end
do
    local potion = tonumber(config.mapPotionItem)
    eq(potion, 124640, "the map potion no longer suggests Inky Black Potion")
    local owner = Owner({ classBuff = false, mapPotion = true, mapPotionMaps = "200, 300", restockNotice = true })
    currentMap = 300
    eq(Find(R.BuildEntries(owner), potion), nil, "a potion without item data became a reminder")
    eq(loadRequests[#loadRequests], potion, "the potion's item data was not requested")
    itemData[potion] = { class = 0, subclass = 1, spell = 185394 }
    currentMap = 100
    eq(Find(R.BuildEntries(owner), potion), nil, "the potion showed off its maps")
    currentMap = 300
    owner.config.restockNotice = false
    eq(Find(R.BuildEntries(owner), potion), nil, "a potion that is not in the bags showed without restock notices")
    owner.config.restockNotice = true
    local entry = Find(R.BuildEntries(owner), potion)
    assert(entry and entry.restock and entry.aura == 185394 and entry.category == "consumable",
        "an empty potion stack did not show as a gray restock reminder")
    -- A bag update that refills or empties the stack compiles the reminder again.
    eq(R.StockChanged(owner), false, "an unchanged empty potion stack counted as a bag change")
    bags[1][3] = potion
    eq(R.StockChanged(owner), true, "a potion arriving in the bags left the gray restock reminder")
    owner.config.restockNotice = false
    entry = Find(R.BuildEntries(owner), potion)
    assert(entry and not entry.restock and entry.aura == 185394, "the potion in the bags is not a clickable reminder")
    eq(R.StockChanged(owner), false, "an unchanged potion stack counted as a bag change")
    bags[1][3] = nil
    eq(R.StockChanged(owner), true, "drinking the last potion left a clickable reminder")
    bags[1][3] = potion
    owner.config.mapPotion = false
    eq(Find(R.BuildEntries(owner), potion), nil, "the potion ignored its switch")
    bags[1][3] = nil
    itemData[potion] = nil
end

-- Food from the bags again, found from the game's own eating spells: a Food &
-- Drink item whose use spell is an eating spell is food; the chosen food
-- comes first, then the newest food (highest item ID). The answer per item
-- is kept, so a second compile asks the game nothing new.
do
    local EATING = R.EATING_SPELLS
    assert(EATING[1219187] and EATING[1233738] and not EATING[1219182],
        "the eating spells are not the game's Refreshment spells")
    itemData[250001] = { spell = 1219187 }                 -- food
    itemData[250010] = { spell = 1233738 }                 -- hearty food
    itemData[250020] = { spell = 430 }                     -- a plain drink
    itemData[250030] = { class = 0, subclass = 1, spell = 1219187 } -- a potion that shares nothing
    bags[0][1], bags[0][2], bags[2][5], bags[3][1] = 250001, 250020, 250010, 250030
    local owner = Owner({ classBuff = false, autoFlask = false, autoRune = false, autoWeapon = false })
    local entry = Find(R.BuildEntries(owner), 250010)
    assert(entry and entry.kind == "food" and not entry.restock and not entry.notice,
        "the newest food in the bags is not the food reminder's click")
    local reads = itemDataReads
    R.BuildEntries(owner)
    eq(itemDataReads, reads, "a second compile asked the game about the same bag items again")
    owner.config.foodChoice = "250001"
    assert(Find(R.BuildEntries(owner), 250001), "the chosen food did not come first")
    owner.config.foodChoice = ""
    R.BuildEntries(owner)
    eq(R.StockChanged(owner), false, "an unchanged bag counted as a new food pick")
    bags[2][5] = nil
    eq(R.StockChanged(owner), true, "eating the last hearty food did not change the pick")
    bags[0][1] = nil
    owner.config.restockNotice = true
    entry = R.BuildEntries(owner)[1]
    assert(entry and entry.kind == "food" and entry.restock and entry.id == 250010,
        "no food left did not show the last food as a gray restock reminder")
    owner.config.restockNotice = false
    entry = R.BuildEntries(owner)[1]
    assert(entry and entry.notice == "food" and entry.id == R.WELL_FED and not entry.restock,
        "no food left without restock notices is not a notice")
    for bag in pairs(bags) do for slot in pairs(bags[bag]) do bags[bag][slot] = nil end end
    -- A Hearty Well Fed buff (its own name and icon) counts as food.
    local fed = R.NewState({})
    fed.list.hasFood, fed.food.ids, fed.food.known = true, {}, true
    local changed = R.FoodDelta(fed, { isFullUpdate = false, addedAuras = {
        { name = "Hearty Well Fed", icon = 133950, auraInstanceID = 7, spellId = 1232080,
          expirationTime = 3700, duration = 3600 } } })
    assert(changed and fed.food.ids[7] and R.FoodPresent(fed) == true, "a Hearty Well Fed buff did not count as food")
end

-- Demon looks: a family no base demon reports counts as the demon whose
-- summon the player just started once a new pet appears, and that look is
-- kept for every later summon. Ticking a demon needs no learned spell.
do
    local now = 100
    GetTime = function() return now end
    local petGUID, family = "Pet-1", 23
    UnitGUID = function(unit) assert(unit == "pet"); return petGUID end
    UnitExists = function(unit) return unit == "pet" end
    UnitIsDeadOrGhost = function() return false end
    UnitCreatureFamily = function() return "Demon", family end
    UnitClass = function() return "Warlock", "WARLOCK" end
    known[688], known[697] = true, true
    local registered = {}
    local owner = Owner({ demonChoiceWarning = true, demonVoidwalker = false })
    owner.context = {
        Event = function(_, event, callback, _, unit) registered[event] = { callback = callback, unit = unit } end,
        RemoveEvent = function(_, event) registered[event] = nil end,
    }
    R.SyncSpecialEvents(owner, function() end)
    local sent = registered.UNIT_SPELLCAST_SENT
    assert(sent and sent.unit == "player", "summon casts are not followed for the player only")
    local function Summon(spellID) sent.callback(owner, "UNIT_SPELLCAST_SENT", "player", "", "Cast-1", spellID) end
    family = 101
    R.ReadPet(owner)
    eq(owner.notices.wrongDemon, nil, "an unknown look was judged before it was learned")
    Summon(697)
    petGUID = "Pet-2"
    now = 104
    R.ReadPet(owner)
    eq(MSUFSuiteDemonLooks[101], "demonVoidwalker", "the new pet's look was not learned for its summon")
    eq(owner.notices.wrongDemon, true, "an unticked demon in another look did not get its notice")
    R.ReadPet(owner)
    eq(owner.notices.wrongDemon, true, "a learned look was forgotten")
    -- The old pet during a cast, or a pet long after it, teaches nothing.
    Summon(688)
    family = 102
    R.ReadPet(owner)
    eq(MSUFSuiteDemonLooks[102], nil, "the previous pet's look was learned for a new summon")
    petGUID, now = "Pet-3", 200
    R.ReadPet(owner)
    eq(MSUFSuiteDemonLooks[102], nil, "a pet long after the summon taught a look")
    -- A ticked demon the character has not learned is allowed; with no
    -- ticked demon available nothing warns.
    family = 16
    owner.config.demonImp, owner.config.demonVoidwalker = false, false
    owner.config.demonFelguard = true
    R.ReadPet(owner)
    eq(owner.notices.wrongDemon, nil, "a notice came although no ticked demon can be summoned")
    owner.config.demonChoiceWarning = false
    R.SyncSpecialEvents(owner, function() end)
    eq(registered.UNIT_SPELLCAST_SENT, nil, "summon casts are followed without the demon check")
    known[688], known[697] = nil, nil
    UnitClass = function() return "Mage", "MAGE" end
    GetTime = function() return 100 end
end
-- The options page shows every demon, learned or not.
do
    local source = assert(io.open(root .. "/MSUF_Suite_Options/Pages/BuffReminders.lua", "rb")):read("*a")
    assert(not source:find("IsSpellKnown", 1, true) and not source:find("IsSpellInSpellBook", 1, true),
        "the demon picker hides or blocks demons the character has not learned")
end

-- Before a keystone starts, buffs can be asked to last the dungeon's own
-- timer: the challenge map of this instance gives the time limit.
do
    GetInstanceInfo = function() return "Dungeon", "party", 8, "Mythic Keystone", 5, 0, false, 2290 end
    GetDifficultyInfo = function() return "Mythic Keystone", "party", false, true, false, false end
    local mapReads = 0
    C_ChallengeMode = {
        IsChallengeModeActive = function() return false end,
        GetMapTable = function() return { 375, 376 } end,
        GetMapUIInfo = function(id)
            mapReads = mapReads + 1
            if id == 376 then return "The Dungeon", 376, 1980, nil, 0, 2290 end
            return "Another", 375, 1700, nil, 0, 2287
        end,
    }
    local owner = Owner({ remindBeforeMinutes = 5 })
    eq(owner.config.keystoneCover, 1, "the keystone cover does not start at the normal warning time")
    eq(owner.config.readyCheckManaPercent, 70, "the ready check limit kept the old default")
    eq(owner.config.readyCheckDuration, 8, "the ready check display time kept the old default")
    R.ReadEnvironment(owner, "PLAYER_ENTERING_WORLD")
    eq(R.Threshold(owner), 300, "the normal warning time changed before a keystone")
    eq(mapReads, 0, "the dungeon timer was read without being chosen")
    owner.config.keystoneCover = 2
    R.ReadEnvironment(owner, "PLAYER_ENTERING_WORLD")
    eq(R.Threshold(owner), 1980, "buffs were not asked to last the dungeon's timer")
    owner.config.keystoneCover, owner.config.keystoneMinutes = 3, 40
    R.ReadEnvironment(owner, "PLAYER_ENTERING_WORLD")
    eq(R.Threshold(owner), 2400, "the chosen minutes did not apply before a keystone")
    R.ReadEnvironment(owner, "CHALLENGE_MODE_START")
    eq(R.Threshold(owner), 300, "the normal warning time did not return once the key started")
    -- S18-K1: missing settings follow the catalog defaults (30 minutes, 5 minutes).
    owner.config.keystoneMinutes, owner.config.remindBeforeMinutes = nil, nil
    R.ReadEnvironment(owner, "PLAYER_ENTERING_WORLD")
    eq(R.Threshold(owner), 1800, "a missing keystone minutes setting did not follow the catalog default")
    R.ReadEnvironment(owner, "CHALLENGE_MODE_START")
    eq(R.Threshold(owner), 300, "a missing advance warning did not follow the catalog default")
    GetInstanceInfo = function() return "World", "none" end
    GetDifficultyInfo = function() end
end

-- The ready check note: own limit and display time, red below half the limit.
do
    UnitGroupRolesAssigned = function() return "HEALER" end
    local mana = 30
    UnitPower, UnitPowerMax = function() return mana end, function() return 100 end
    local timerDelay
    C_Timer.After = function(delay) timerDelay = delay end
    local owner = Owner({ readyCheckMana = true })
    -- The note's hide is a context wait (MSUF_Suite_Modules/Timers.lua).
    NS.Dispatch = function(callback, ...) return callback(...) end
    owner.context = Support.ModuleTimers(root, S, NS)("buffReminders", owner, {})
    owner.view.host = Widget()
    function owner.view.host:CreateFontString()
        local text = Widget()
        function text:SetTextColor(r, g, b) self.color = { r, g, b } end
        return text
    end
    R.ReadyCheck(owner)
    local note = owner.readyCheck.label
    assert(note and note.shown and note.text:find("30%%") and note.color[2] < .5 and timerDelay == 8,
        "a mana note far below the limit is not red for the chosen time")
    mana = 60
    R.ReadyCheck(owner)
    assert(note.shown and note.text:find("60%%") and note.color[2] > .5, "a mana note near the limit turned red")
    mana = 80
    R.ReadyCheck(owner)
    assert(not note.shown, "mana above the limit still showed a note")
    -- S18-K1: a profile without the two settings follows the catalog defaults
    -- (70 percent, 8 seconds), not private fallbacks, and never divides nil.
    owner.config.readyCheckManaPercent, owner.config.readyCheckDuration = nil, nil
    mana = 75
    R.ReadyCheck(owner)
    assert(not note.shown, "a missing limit used a fallback that disagrees with the catalog default")
    mana = 65
    R.ReadyCheck(owner)
    assert(note.shown and note.color[2] > .5, "a missing limit did not follow the catalog default")
    assert(owner.context.timers[R.HideReadyCheck].due == GetTime() + 8,
        "a missing display time did not follow the catalog default")
    mana = 30
    R.ReadyCheck(owner)
    assert(note.shown and note.color[2] < .5, "a missing limit broke the red note below half the limit")
end

-- The module follows subzone steps only for the map potion.
local events = {}
local context = {}
function context:Event(event, callback, _, unit) events[event] = unit or callback end
function context:RemoveEvent(event) events[event] = nil end
local module = assert(restoredModule)
-- The shipped context timers (MSUF_Suite_Modules/Timers.lua) on the stub.
NS.Dispatch = NS.Dispatch or function(callback, ...) return callback(...) end
module.context, module.active = Support.ModuleTimers(root, S, NS)("buffReminders", module, context), true
module.config = Owner({ classBuff = false }).config
GetInstanceInfo = function() return "World", "none" end
DifficultyUtil = { ID = { DungeonTimewalker = 24, RaidTimewalker = 33 } }
GetDifficultyInfo = function() end
UnitExists = function() return false end
UnitIsDeadOrGhost, UnitInVehicle, IsMounted = function() return false end, function() return false end, function() return false end
module:Enable()
assert(not events.ZONE_CHANGED and not events.ZONE_CHANGED_INDOORS, "subzone steps were followed without a map potion")
module.config.mapPotion, module.config.mapPotionMaps = true, "300"
module:Refresh()
assert(events.ZONE_CHANGED and events.ZONE_CHANGED_INDOORS, "the map potion does not follow subzone steps")
local compiles = 0
local compile = module.Compile
module.Compile = function(...) compiles = compiles + 1; return compile(...) end
currentMap = 301
events.ZONE_CHANGED(module, "ZONE_CHANGED")
events.ZONE_CHANGED_INDOORS(module, "ZONE_CHANGED_INDOORS")
eq(compiles, 1, "stepping off a potion map did not compile once")
events.ZONE_CHANGED(module, "ZONE_CHANGED")
eq(compiles, 1, "a subzone step on the same side of the map edge compiled")
module.Compile = compile
module:Disable()
assert(not events.ZONE_CHANGED, "disable kept the subzone events")

-- Combat end. The 2026-10-11 raid trace compiled at all 4 combat ends
-- (M:Compile 3.0 ms, most of it BuildEntries' bag scans). In combat the
-- compile inputs only take note; combat end compiles when one of them
-- changed, else it reads only what a compile reads besides the list. After
-- every fight a full compile changes nothing: the list is the one a compile
-- would have built.
do
    local combat, itemReads = false, 0
    NS.IsCombatLocked = function() return combat end
    local count = C_Item.GetItemCount
    C_Item.GetItemCount = function(id) itemReads = itemReads + 1; return count(id) end
    local potion = tonumber(config.mapPotionItem)
    itemData[potion] = { class = 0, subclass = 1, spell = 185394 }
    bags[1][3], bags[1][4] = potion, potion
    currentMap = 300
    local roster, members = { player = "MAGE" }, 0
    UnitClass = function(unit) return roster[unit], roster[unit] end
    GetNumSubgroupMembers = function() return members end
    UnitIsUnit = function(unit, other) return unit == other end
    module.config = Owner({ classBuff = false, mapPotion = true, mapPotionMaps = "300", restockNotice = true,
        otherClassBuffs = true }).config
    module:Enable()
    local compiles, compile = 0, module.Compile
    module.Compile = function(...) compiles = compiles + 1; return compile(...) end
    local function Same(label)
        local entries = module.list.entries
        assert(compile(module) == false and module.list.entries == entries,
            label .. ": a full compile after combat changed the reminder list")
    end
    -- check runs right after combat end, before that full compile.
    local function Fight(label, inCombat, wanted, check)
        events.PLAYER_REGEN_DISABLED(module, "PLAYER_REGEN_DISABLED")
        combat = true
        if inCombat then
            local entries = module.list.entries
            itemReads = 0
            inCombat()
            assert(itemReads == 0 and module.list.entries == entries, label .. ": an input in combat did work")
        end
        combat = false
        compiles = 0
        events.PLAYER_REGEN_ENABLED(module, "PLAYER_REGEN_ENABLED")
        eq(compiles, wanted, label .. ": compiles at combat end")
        if check then check() end
        Same(label)
    end
    local function Event(event) events[event](module, event) end
    local function Entry(id) return Find(module.list.entries, id) end
    assert(Entry(potion) and not Entry(potion).restock and Entry(potion).count == 2, "the map potion did not show")
    -- Only PLAYER_REGEN_ENABLED and the compile inputs are heard in combat.
    events.PLAYER_REGEN_DISABLED(module, "PLAYER_REGEN_DISABLED")
    assert(events.BAG_UPDATE_DELAYED and events.SPELLS_CHANGED and events.PLAYER_EQUIPMENT_CHANGED
        and events.GROUP_ROSTER_UPDATE and events.PLAYER_REGEN_ENABLED and not events.UNIT_AURA
        and not events.ZONE_CHANGED and not events.PLAYER_ALIVE, "combat kept the wrong listeners")
    events.PLAYER_REGEN_ENABLED(module, "PLAYER_REGEN_ENABLED")
    Fight("a fight without inputs", nil, 0)
    Fight("a spell change", function() Event("SPELLS_CHANGED") end, 1)
    Fight("a weapon swap", function() Event("PLAYER_EQUIPMENT_CHANGED") end, 1)
    -- A potion drunk in combat: the count follows; the pick stays while one is left.
    Fight("a potion drunk", function() bags[1][4] = nil; Event("BAG_UPDATE_DELAYED") end, 0)
    eq(Entry(potion).count, 1, "the potion count stayed stale after combat")
    -- The last potion drunk in combat: the stock changed, the list compiles.
    Fight("the last potion drunk", function() bags[1][3] = nil; Event("BAG_UPDATE_DELAYED") end, 1)
    assert(Entry(potion).restock and Entry(potion).count == 0, "the empty potion stack was not a restock reminder")
    -- A step off the potion map in combat (no subzone event is heard then).
    Fight("a step off the potion map", function() currentMap = 301 end, 1)
    eq(Entry(potion), nil, "the potion stayed off its maps")
    currentMap = 300
    module:Refresh()
    -- A member of a class without a buff joined: the roster is read, no compile.
    roster.party1, members = "ROGUE", 1
    Fight("a rogue joined", function() Event("GROUP_ROSTER_UPDATE") end, 0, function()
        assert(module.group.units.party1 and #module.group.unitList == 2, "the roster was not read at combat end")
    end)
    -- A Priest joined: another class's buff, the list compiles.
    roster.party2, members = "PRIEST", 2
    Fight("a priest joined", function() Event("GROUP_ROSTER_UPDATE") end, 1)
    assert(Entry(R.ClassBuff("PRIEST").cast), "the joined Priest's buff notice is missing")
    -- A roster pass still waiting when combat starts is owed.
    roster.party3, members = "DRUID", 3
    Event("GROUP_ROSTER_UPDATE")
    Fight("a roster pass pending at combat start", nil, 1)
    assert(Entry(R.ClassBuff("DRUID").cast), "the pending roster change was lost in combat")
    -- A settings change refused in combat compiles at combat end.
    Fight("a refresh in combat", function() module.config.otherClassBuffs = false; module:Refresh() end, 1)
    eq(Entry(R.ClassBuff("PRIEST").cast), nil, "the settings change refused in combat was lost")
    -- Without a compile, combat end still reads the member list, the
    -- Healthstone and the pet as a compile does.
    module.config.groupBuff, module.config.healthstoneFromWarlock, module.config.petPassiveWarning = true, true, true
    roster.party4, members = "WARLOCK", 4
    inventory[5512] = 1
    local petPassive = false
    UnitExists = function(unit) return unit == "pet" end
    NUM_PET_ACTION_SLOTS = 1
    GetPetActionInfo = function() return "PET_MODE_PASSIVE", nil, true, petPassive end
    module:Refresh()
    eq(module.notices.healthstoneMissing, false, "the Healthstone in the bags was not seen")
    eq(#events.UNIT_AURA, 5, "the member events do not follow the party")
    -- The Rogue leaves (party tokens move up): no class with a buff changed.
    Fight("a Healthstone used, a pet set passive, a member left", function()
        inventory[5512] = 0
        Event("BAG_UPDATE_DELAYED")
        petPassive = true
        roster.party1, roster.party2, roster.party3, roster.party4, members = "PRIEST", "DRUID", "WARLOCK", nil, 3
        Event("GROUP_ROSTER_UPDATE")
    end, 0, function()
        assert(events.UNIT_AURA == module.group.unitList and #events.UNIT_AURA == 4,
            "the member events did not follow the roster read at combat end")
        assert(module.notices.healthstoneMissing == true and module.notices.petPassive == true,
            "combat end did not read the Healthstone or the pet")
    end)
    module.config.groupBuff, module.config.healthstoneFromWarlock, module.config.petPassiveWarning = false, false, false
    roster.party1, roster.party2, roster.party3, members = "ROGUE", "PRIEST", "DRUID", 3
    inventory[5512] = nil
    UnitExists = function() return false end
    module:Refresh()
    -- Item data a compile still waited for: combat end asks again.
    itemData[potion] = nil
    module:Refresh()
    assert(module.stock.pending and not Entry(potion), "missing potion data did not leave the compile pending")
    itemData[potion] = { class = 0, subclass = 1, spell = 185394 }
    Fight("item data arrived", nil, 1)
    assert(not module.stock.pending and Entry(potion), "the potion did not show once its data arrived")
    module.Compile = compile
    module:Disable()
    C_Item.GetItemCount = count
    NS.IsCombatLocked = function() return false end
    UnitClass = function() return "Mage", "MAGE" end
    GetNumSubgroupMembers = function() return 0 end
    itemData[potion] = nil
end

print("Suite buff reminders: restored campfire, map potion, bag food, demon looks, keystone and ready check options passed")

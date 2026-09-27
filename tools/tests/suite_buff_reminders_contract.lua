local root = assert(arg[1], "repository root required")
local combat, auraReads, itemReads, foodReads = false, 0, 0, 0
local attributeWrites, textureWrites, enchantReads = 0, 0, 0
local inventory
local auras = {}
local enchant = {}
local offhandItemID
local frames = {}
local driver, undriven

local function Widget()
    local w = { shown=true, events={}, attributes={} }
    function w:SetScript(event, callback) self[event] = callback end
    function w:RegisterEvent(event) self.events[event] = true end
    function w:RegisterUnitEvent(event, unit) self.events[event] = unit end
    function w:UnregisterEvent(event) self.events[event] = nil end
    function w:UnregisterAllEvents() self.events = {} end
    function w:CreateTexture() return Widget() end
    function w:CreateFontString() return Widget() end
    function w:RegisterForClicks(...) self.clicks = { ... } end
    function w:SetAttribute(key, value)
        attributeWrites = attributeWrites + 1
        self.attributes[key] = value
    end
    function w:SetShown(value) self.shown = value end
    function w:Show() self.shown = true end
    function w:Hide() self.shown = false end
    function w:SetText(value) self.text = value end
    function w:SetTexture(value)
        textureWrites = textureWrites + 1
        self.texture = value
    end
    function w:SetTexCoord() end
    function w:SetColorTexture() end
    function w:SetAllPoints() end
    function w:SetPoint() end
    function w:ClearAllPoints() end
    function w:SetSize() end
    return w
end

UIParent = Widget()
CreateFrame = function(kind)
    local frame = Widget()
    frame.kind = kind
    frames[#frames + 1] = frame
    return frame
end
RegisterStateDriver = function(frame, state, condition)
    assert(state == "visibility" and condition == "[combat] hide; show")
    driver = frame
end
UnregisterStateDriver = function(frame, state)
    assert(state == "visibility")
    undriven = frame
end
-- The global IsPlayerSpell, IsSpellKnown and GetSpecialization shims exist
-- only while Blizzard's deprecation fallbacks load: the module calls the C
-- APIs both clients always have.
local knownSpell = function(id) return id == 1459 end
Enum = { SpellBookSpellBank = { Player = 0, Pet = 1 } }
C_SpellBook = {
    IsSpellKnown = function(id, bank)
        assert(bank == Enum.SpellBookSpellBank.Player)
        return knownSpell(id)
    end,
    IsSpellInSpellBook = function(_, bank, includeOverrides)
        assert(bank == Enum.SpellBookSpellBank.Player and includeOverrides == false)
        return false
    end,
}
GetTime = function() return 0 end
UnitClass = function() return "Mage", "MAGE" end
UnitIsDeadOrGhost = function() return false end
UnitInVehicle = function() return false end
IsMounted = function() return false end
GetInstanceInfo = function() return "World", "none" end
GetInventoryItemID = function(_, slot)
    if slot == 16 then return 900001 end
    if slot == 17 then return offhandItemID end
end
-- The listed Well Fed IDs share one spell name; the food rescan looks that
-- name up once per scan.
local FOOD_NAME_IDS = { [104280] = true, [1219179] = true, [1285644] = true }
C_Spell = {
    GetSpellTexture = function(id) return id end,
    GetSpellName = function(id) return FOOD_NAME_IDS[id] and "Well Fed" or ("Spell " .. id) end,
}
C_Item = {
    GetItemCount = function(id)
        itemReads = itemReads + 1
        return inventory and (inventory[id] or 0) or 2
    end,
    GetItemIconByID = function(id) return id end,
    GetItemInfoInstant = function(id)
        if id == 900003 then return id, "Armor", "Shield", "INVTYPE_SHIELD", 0, 4, 0 end
        return id, "Weapon", "Sword", "INVTYPE_WEAPON", 0, 2, 0
    end,
}
C_PaperDollInfo = { GetTemporaryEnchantmentInfo = function(slot)
    enchantReads = enchantReads + 1
    return enchant[slot]
end }
-- Auras by instance ID and by spell name; only the food reader uses these
-- lookups, so each one counts as a food read.
local instanceAuras, namedAuras = {}, {}
C_UnitAuras = {
    GetPlayerAuraBySpellID = function(id)
        auraReads = auraReads + 1
        if id == 104280 or id == 1219179 or id == 1285644 then foodReads = foodReads + 1 end
        return auras[id]
    end,
    GetAuraDataByAuraInstanceID = function(unit, id)
        assert(unit == "player" and type(id) == "number", "food re-check must name the player and an instance ID")
        foodReads = foodReads + 1
        return instanceAuras[id]
    end,
    GetAuraDataBySpellName = function(unit, name, filter)
        assert(unit == "player" and type(name) == "string" and filter == "HELPFUL",
            "food name lookup must be a targeted helpful player lookup")
        foodReads = foodReads + 1
        return namedAuras[name]
    end,
}
-- Blizzard_GameTooltip builds GameTooltip at startup on both clients.
GameTooltip = Widget()
function GameTooltip:SetOwner(owner) self.owner, self.spell, self.item = owner, nil, nil end
function GameTooltip:SetSpellByID(id) self.spell = id end
function GameTooltip:SetItemByID(id) self.item = id end

-- Regions made through the shared Suite helpers (pixel layout).
local mover, suiteRegions = nil, {}
local S = { Public=function(value) return not (type(value) == "table" and value.secret) end,
    Install=function(id, module) assert(id == "buffReminders"); _G.testModule = module end,
    RegisterOwnedMover=function(id, element, spec)
        assert(id == "buffReminders" and element == "buffs")
        mover = spec
    end,
    Config=function() return testModule.config end,
    Set=function(_,key,value) testModule.config[key]=value;testModule:Refresh();return true end,
    Text=function(value) return value end,
    CreateFrame=function(...) return CreateFrame(...) end,
    CreateTexture=function(parent, ...)
        local region = parent:CreateTexture(...)
        suiteRegions[region] = "texture"
        return region
    end,
    CreateFontString=function(parent, ...)
        local region = parent:CreateFontString(...)
        suiteRegions[region] = "font"
        return region
    end,
    RGB=function(hex)
        return tonumber(hex:sub(1, 2), 16) / 255, tonumber(hex:sub(3, 4), 16) / 255, tonumber(hex:sub(5, 6), 16) / 255
    end,
    editMode=false }
local NS = { IsCombatLocked=function() return combat end,
    Client={ SupportsEvent=function() return true end } }
-- Data, readers, entry selection and the controller load in TOC order into
-- one private table (Bootstrap only fills it from _G.MSUFSuite).
local Support = dofile(root .. "/tools/tests/suite_test_support.lua")
local BR_FILES = { "Bootstrap.lua", "Data.lua", "Readers.lua", "Entries.lua", "Controller.lua" }
local tocFiles = Support.TocFiles(root, "MSUF_Suite_BuffReminders")
assert(#tocFiles == #BR_FILES, "the BuffReminders TOC must list " .. #BR_FILES .. " files")
for i = 1, #BR_FILES do
    assert(tocFiles[i] == BR_FILES[i], "BuffReminders TOC order: expected " .. BR_FILES[i] .. " at " .. i)
end
local private = { NS=NS, Suite=S }
Support.Load(root, "MSUF_Suite_BuffReminders", private, nil, { ["Bootstrap.lua"] = true })
local module = assert(testModule)
assert(private.BuffReminders and private.BuffReminders.FLASKS and private.BuffReminders.BuildEntries,
    "the BuffReminders files do not share P.BuffReminders")
module.config = { classBuff=true, spellIDs="777", items="123:888", mainHandItem="456", offHandItem="",
    instancesOnly=false, hideMounted=true, size=38, spacing=5, columns=6, borderColor="e8b855", point=1, x=0, y=0,
    remindBeforeMinutes=0 }
-- The module context: events are registered per name (unit events keep their
-- unit); eventFrame.OnEvent dispatches like the runtime does.
local eventFrame, callbacks = { events = {} }, {}
module.context = {
    Event = function(_, event, callback, allowCombat, unit)
        assert(allowCombat == true, "buff reminder event must run its own combat checks")
        callbacks[event] = callback
        eventFrame.events[event] = unit or true
    end,
    RemoveEvent = function(_, event)
        callbacks[event] = nil
        eventFrame.events[event] = nil
    end,
}
function eventFrame.OnEvent(_, event, ...)
    local callback = callbacks[event]
    if callback and module.active then callback(module, event, ...) end
end
-- Memory allocated by repeating one event while garbage collection is paused.
local function EventAllocation(event, times)
    collectgarbage("collect")
    collectgarbage("stop")
    local before = collectgarbage("count")
    for _ = 1, times do eventFrame.OnEvent(eventFrame, event) end
    local grown = collectgarbage("count") - before
    collectgarbage("restart")
    return grown
end
-- A compile event that changes nothing (SPELLS_CHANGED fires often) keeps the
-- active reminder list and allocates no tables or string keys.
local function AssertQuietCompile(label)
    local active = module.entries
    local grown = EventAllocation("SPELLS_CHANGED", 100)
    assert(module.entries == active and grown < 1,
        label .. ": an unchanged compile rebuilt the reminder list (" .. grown .. " KB)")
end
module.active = true
module:Enable()
assert(driver == module.host and #module.entries == 4 and #module.buttons == 4,
    "enabled module did not create exactly the configured secure buttons")
assert(module.buttons[1].attributes.type1 == "spell" and module.buttons[1].attributes.spell1 == 1459)
assert(module.buttons[3].attributes.type1 == "item" and module.buttons[3].attributes.item1 == "item:123")
assert(module.buttons[4].attributes["target-slot"] == 16,
    "manual weapon enchant did not target the main hand")
assert(module.mask == 15 and module.buttons[4].shown, "missing buffs did not show")
-- Hovering a reminder shows the spell or item its secure button uses.
module.buttons[1]:OnEnter()
assert(GameTooltip.owner == module.buttons[1] and GameTooltip.spell == 1459 and GameTooltip.shown,
    "a spell reminder did not show its spell tooltip")
module.buttons[1]:OnLeave()
assert(not GameTooltip.shown, "leaving a reminder kept its tooltip")
module.buttons[3]:OnEnter()
assert(GameTooltip.owner == module.buttons[3] and GameTooltip.item == 123 and not GameTooltip.spell,
    "an item reminder did not show its item tooltip")
module.buttons[3]:OnLeave()
assert(module.buttons[3].count.text == "2", "item count was not shown")
-- Only the secure frames stay raw CreateFrame; their regions and the preview
-- text use the shared Suite helpers.
assert(suiteRegions[module.buttons[1].icon] == "texture" and suiteRegions[module.buttons[1].border] == "texture"
    and suiteRegions[module.buttons[1].count] == "font" and suiteRegions[module.preview] == "font",
    "buff reminder regions bypassed S.CreateTexture/S.CreateFontString")
assert(eventFrame.events.UNIT_AURA == "player" and eventFrame.events.UNIT_INVENTORY_CHANGED == "player")
local before = auraReads
eventFrame.OnEvent(eventFrame, "UNIT_AURA", "target")
assert(auraReads == before, "another unit caused aura work")
auras[1459] = { spellId=1459 }
eventFrame.OnEvent(eventFrame, "UNIT_AURA", "player")
assert(module.mask == 14 and not module.buttons[1].shown and module.buttons[2].shown)
assert(auraReads == before + 3, "player event did more than one targeted lookup per aura")
before, itemReads = auraReads, 0
eventFrame.OnEvent(eventFrame, "UNIT_AURA", "player")
assert(auraReads == before + 3 and itemReads == 0, "unchanged auras repainted item counts")
eventFrame.OnEvent(eventFrame, "PLAYER_REGEN_DISABLED")
assert(not eventFrame.events.UNIT_AURA and not eventFrame.events.BAG_UPDATE_DELAYED
    and not eventFrame.events.UNIT_INVENTORY_CHANGED and eventFrame.events.PLAYER_REGEN_ENABLED,
    "combat kept event listeners whose handlers do nothing in combat")
combat = true
before = auraReads
eventFrame.OnEvent(eventFrame, "UNIT_AURA", "player")
assert(auraReads == before, "combat caused aura queries")
combat = false
enchant[16] = {}
eventFrame.OnEvent(eventFrame, "PLAYER_REGEN_ENABLED")
assert(module.mask == 6 and not module.buttons[4].shown, "weapon enchant presence was ignored")
assert(eventFrame.events.UNIT_AURA == "player" and eventFrame.events.UNIT_INVENTORY_CHANGED == "player"
    and eventFrame.events.BAG_UPDATE_DELAYED, "combat end did not restore the event listeners")
auras[888] = { secret=true }
eventFrame.OnEvent(eventFrame, "UNIT_AURA", "player")
assert(module.mask == 2 and not module.buttons[3].shown, "secret aura result created a false reminder")
module:RegisterMovers()
assert(mover and #mover.extraControls==3 and #mover.historyKeys==3
    and mover.extraControls[1].get()==38 and mover.extraControls[3].get()==6,
    "buff reminder popup omitted icon layout controls")
local beforeAttributes = attributeWrites
assert(mover.extraControls[1].set(42) and module.config.size==42
    and mover.extraControls[1].set(38),"buff reminder popup icon size did not apply")
assert(attributeWrites == beforeAttributes, "layout-only change rewrote secure actions")
beforeAttributes, before = attributeWrites, auraReads
module.config.x = 12
module:Refresh()
assert(attributeWrites == beforeAttributes and auraReads == before,
    "position-only change rebuilt actions or queried auras")
module.config.x = 0
module:Refresh()
module:Disable()
assert(undriven == module.host and not module.host.shown and not next(eventFrame.events))
before = auraReads
module.active = false
eventFrame.OnEvent(eventFrame, "UNIT_AURA", "player")
assert(auraReads == before, "disabled module still queried auras")

-- Mainline defaults select only owned items. Food starts with targeted reads,
-- then unrelated aura deltas must not query those auras again.
NS.Client.modernEquipment = true
inventory = { [241324]=2, [242275]=1, [259085]=3, [243733]=1 }
module.config.spellIDs, module.config.items = "", ""
module.config.mainHandItem, module.config.offHandItem = "", ""
module.config.autoFlask, module.config.autoFood = true, true
module.config.autoRune, module.config.autoWeapon = true, true
enchant[16] = nil
C_UnitAuras.GetAuraDataByIndex = function() error("indexed food aura read is forbidden") end
module.active = true
module:Enable()
assert(#module.entries == 5 and #module.buttons == 5, "Mainline defaults did not select all owned categories")
AssertQuietCompile("consumables")
assert(module.entries[2].id == 241324 and module.entries[3].kind == "food"
    and module.entries[4].id == 259085 and module.entries[5].id == 243733)
assert(module.buttons[5].attributes.type1 == "item" and module.buttons[5].attributes.item1 == "item:243733"
    and module.buttons[5].attributes["target-slot"] == 16,
    "automatic oil did not securely target the main hand")
-- One scan: the three listed Well Fed IDs plus their one shared spell name.
assert(module.mask == 30 and foodReads == 4, "missing default consumables were not shown")
-- The augment rune is a separate consumable. Its primary-stat aura must not
-- satisfy the flask reminder when no flask aura is active.
auras[1264426] = { spellId = 1264426, auraInstanceID = 81 }
eventFrame.OnEvent(eventFrame, "UNIT_AURA", "player",
    { addedAuras = { auras[1264426] } })
assert(module.mask == 22 and module.buttons[2].shown and not module.buttons[4].shown,
    "augment rune suppressed the missing-flask reminder")
auras[1264426] = nil
eventFrame.OnEvent(eventFrame, "UNIT_AURA", "player", { removedAuraInstanceIDs = { 81 } })
assert(module.mask == 30 and module.buttons[2].shown and module.buttons[4].shown,
    "removing the rune did not restore its reminder alongside the flask")
local beforeAura, beforeEnchant, beforeTexture = auraReads, enchantReads, textureWrites
beforeAttributes = attributeWrites
local compiled, compile = 0, module.Compile
module.Compile = function(...) compiled = compiled + 1; return compile(...) end
eventFrame.OnEvent(eventFrame, "BAG_UPDATE_DELAYED")
module.Compile = compile
assert(auraReads == beforeAura and enchantReads == beforeEnchant
    and attributeWrites == beforeAttributes and textureWrites == beforeTexture,
    "unchanged bag update queried buffs or rebound secure buttons")
assert(compiled == 0, "a bag update that kept every consumable pick rebuilt the reminder list")
auras[1459], auras[432778] = nil, { spellId=432778, auraInstanceID=72 }
eventFrame.OnEvent(eventFrame, "UNIT_AURA", "player")
beforeAura, beforeEnchant = auraReads, enchantReads
local beforeFood = foodReads
itemReads = 0
eventFrame.OnEvent(eventFrame, "UNIT_AURA", "player", { addedAuras={ {spellId=7, icon=7, auraInstanceID=71} } })
assert(module.mask == 30 and itemReads == 0 and foodReads == beforeFood
    and auraReads == beforeAura and enchantReads == beforeEnchant,
    "unrelated aura delta queried buffs, items or weapon enchants")
auras[432778] = nil
eventFrame.OnEvent(eventFrame, "UNIT_AURA", "player", { removedAuraInstanceIDs={ 72 } })
assert(module.mask == 31 and auraReads > beforeAura,
    "removed tracked class aura did not trigger a fresh lookup")
auras[432778] = { spellId=432778, auraInstanceID=73 }
eventFrame.OnEvent(eventFrame, "UNIT_AURA", "player",
    { addedAuras={ {spellId=432778, auraInstanceID=73} } })
assert(module.mask == 30, "added class aura alias did not clear the reminder")
assert(eventFrame.events.WEAPON_ENCHANT_CHANGED and eventFrame.events.WEAPON_SLOT_CHANGED,
    "weapon enchant events were not registered")
enchant[16] = {}
eventFrame.OnEvent(eventFrame, "WEAPON_ENCHANT_CHANGED")
assert(module.mask == 14, "weapon enchant event did not hide the oil reminder")
enchant[16] = nil
eventFrame.OnEvent(eventFrame, "WEAPON_ENCHANT_CHANGED")
assert(module.mask == 30, "removed weapon enchant did not restore the oil reminder")
offhandItemID = 900002
eventFrame.OnEvent(eventFrame, "PLAYER_EQUIPMENT_CHANGED", 17)
assert(#module.entries == 6 and module.mask == 62
    and module.buttons[6].attributes.item1 == "item:243733"
    and module.buttons[6].attributes["target-slot"] == 17,
    "equipped off-hand weapon did not receive an oil target")
offhandItemID = 900003
eventFrame.OnEvent(eventFrame, "PLAYER_EQUIPMENT_CHANGED", 17)
assert(#module.entries == 5 and module.mask == 30,
    "an off-hand shield received an oil reminder")
local oldUnitClass, oldKnownSpell = UnitClass, knownSpell
UnitClass = function() return "Paladin", "PALADIN" end
knownSpell = function(id) return id == 433583 end
eventFrame.OnEvent(eventFrame, "PLAYER_SPECIALIZATION_CHANGED", "player")
assert(#module.entries == 3 and module.mask == 7,
    "a known class weapon imbue did not suppress automatic oil")
UnitClass = function() return "Rogue", "ROGUE" end
knownSpell = function() return false end
eventFrame.OnEvent(eventFrame, "PLAYER_SPECIALIZATION_CHANGED", "player")
assert(#module.entries == 4 and module.entries[4].slot == 16,
    "Rogue without a temporary enchant could not use an oil")
UnitClass, knownSpell = oldUnitClass, oldKnownSpell
eventFrame.OnEvent(eventFrame, "PLAYER_SPECIALIZATION_CHANGED", "player")
assert(#module.entries == 5 and module.mask == 30)
eventFrame.OnEvent(eventFrame, "UNIT_AURA", "player", { addedAuras={ {spellId=7, icon=7, auraInstanceID=70} } })
assert(foodReads == beforeFood and module.mask == 30, "unrelated aura delta rescanned food")
eventFrame.OnEvent(eventFrame, "UNIT_AURA", "player", { addedAuras={ {spellId=104280, icon=136000, auraInstanceID=42} } })
assert(module.mask == 26 and foodReads == beforeFood, "Well Fed delta did not hide food")
eventFrame.OnEvent(eventFrame, "UNIT_AURA", "player", { removedAuraInstanceIDs={ 42 } })
assert(module.mask == 30 and foodReads == beforeFood, "removed Well Fed aura did not show food")
-- Food snapshots are recycled: a food aura that follows a removed one reuses
-- its table instead of allocating a new one per aura event.
eventFrame.OnEvent(eventFrame, "UNIT_AURA", "player", { addedAuras={ {spellId=104280, icon=136000, auraInstanceID=43} } })
local foodSnapshot = assert(module.foodIDs[43], "added Well Fed aura was not tracked")
eventFrame.OnEvent(eventFrame, "UNIT_AURA", "player", { removedAuraInstanceIDs={ 43 } })
eventFrame.OnEvent(eventFrame, "UNIT_AURA", "player", { addedAuras={ {spellId=104280, icon=133950, auraInstanceID=44} } })
assert(module.foodIDs[44] == foodSnapshot and module.foodIDs[43] == nil and module.mask == 26,
    "a new food aura did not reuse the released snapshot")
eventFrame.OnEvent(eventFrame, "UNIT_AURA", "player", { removedAuraInstanceIDs={ 44 } })
assert(module.mask == 30 and foodReads == beforeFood and not next(module.foodIDs),
    "removed recycled food aura did not show food")
-- Restricted targeted aura data remains unknown, never a missing buff.
auras[104280] = { secret=true }
eventFrame.OnEvent(eventFrame, "UNIT_AURA", "player", { isFullUpdate=true })
assert(module.mask == 26 and not module.buttons[3].shown,
    "restricted food aura data created a false reminder")
auras[104280] = nil
inventory[259085] = 0
eventFrame.OnEvent(eventFrame, "BAG_UPDATE_DELAYED")
assert(#module.entries == 4 and module.entries[4].id == 243733,
    "bag update did not drop an unowned default")
combat = true
before, itemReads = auraReads, 0
eventFrame.OnEvent(eventFrame, "BAG_UPDATE_DELAYED")
assert(auraReads == before and itemReads == 0, "combat caused consumable selection work")
combat = false
module:Disable()
module.config.spellIDs = "1001,1002,1003,1004,1005,1006,1007,1008,1009,1010,1011"
itemReads = 0
module.active = true
module:Enable()
assert(#module.entries == 12 and itemReads == 0,
    "full reminder pool still resolved unused automatic consumables")
module:Disable()

-- Rogue spec defaults and the one-shot advance reminder.
local now, scheduled, specID = 1000, {}, 259
GetTime = function() return now end
C_SpecializationInfo = {
    GetSpecialization = function() return 1 end,
    GetSpecializationInfo = function() return specID end,
}
C_Timer = { NewTimer=function(delay, callback)
    local timer = { due=now + delay, callback=callback, cancelled=false }
    function timer:Cancel() self.cancelled = true end
    scheduled[#scheduled + 1] = timer
    return timer
end }
local function FireNext()
    local first
    for _, timer in ipairs(scheduled) do
        if not timer.cancelled and not timer.fired and (not first or timer.due < first.due) then
            first = timer
        end
    end
    assert(first, "no threshold timer scheduled")
    now, first.fired = first.due, true
    first.callback()
    return first
end
UnitClass = function() return "Rogue", "ROGUE" end
local knownPoison = { [2823]=true, [315584]=true, [381637]=true, [3408]=true }
knownSpell = function(id) return knownPoison[id] == true end
module.config = { classBuff=false, autoRoguePoisons=true, spellIDs="", items="",
    mainHandItem="", offHandItem="", autoFlask=false, autoFood=false,
    autoRune=false, autoWeapon=false, remindBeforeMinutes=5,
    instancesOnly=false, hideMounted=true, size=38, spacing=5, columns=6,
    borderColor="e8b855", point=1, x=0, y=0 }
auras[1459], auras[432778], auras[888] = nil, nil, nil
auras[2823] = { spellId=2823, auraInstanceID=100, expirationTime=now+420, duration=3600 }
auras[381637] = { spellId=381637, auraInstanceID=101, expirationTime=now+600, duration=3600 }
module.active = true
module:Enable()
assert(#module.entries == 2 and module.entries[1].id == 2823
    and module.entries[2].id == 381637 and module.mask == 0,
    "Assassination did not select its lethal and known nonlethal poisons")
AssertQuietCompile("Rogue poisons")
assert(module.thresholdAt == 1120, "advance reminder was not scheduled at five minutes remaining")
before = auraReads
FireNext()
assert(module.mask == 1 and auraReads == before and module.buttons[1].shown,
    "threshold timer did not reveal the expiring poison without scanning auras")
module.config.remindBeforeMinutes = 0
module:Refresh()
assert(module.mask == 0 and module.thresholdTimer == nil,
    "zero-minute setting did not disable advance reminders")
module.config.remindBeforeMinutes = 5
module:Refresh()
assert(module.mask == 1, "restoring advance warning did not refresh the visible reminder")
auras[2823] = { spellId=2823, auraInstanceID=100, expirationTime=now+900, duration=3600 }
auras[381637] = { spellId=381637, auraInstanceID=101, expirationTime=now+1200, duration=3600 }
eventFrame.OnEvent(eventFrame, "UNIT_AURA", "player", { isFullUpdate=true })
assert(module.mask == 0 and module.thresholdAt == now+600,
    "refreshing a poison did not postpone its advance reminder")
auras[2823] = { spellId=2823, auraInstanceID=100, expirationTime={secret=true}, duration=3600 }
eventFrame.OnEvent(eventFrame, "UNIT_AURA", "player", { isFullUpdate=true })
assert(module.mask == 0, "a secret expiration time created a false advance reminder")
specID = 260
auras[2823] = nil
auras[315584] = { spellId=315584, auraInstanceID=102, expirationTime=now+900, duration=3600 }
eventFrame.OnEvent(eventFrame, "PLAYER_SPECIALIZATION_CHANGED", "player")
assert(module.entries[1].id == 315584 and module.mask == 0,
    "switching from Assassination to Outlaw did not replace Deadly Poison")
module:Disable()

for _, expectedSpec in ipairs({ 260, 261 }) do
    specID = expectedSpec
    auras[2823] = nil
    auras[315584] = { spellId=315584, auraInstanceID=102, expirationTime=now+900, duration=3600 }
    module.active = true
    module:Enable()
    assert(#module.entries == 2 and module.entries[1].id == 315584 and module.mask == 0,
        "Outlaw or Subtlety did not prefer Instant Poison")
    auras[315584] = nil
    auras[8679] = { spellId=8679, auraInstanceID=103, expirationTime=now+900, duration=3600 }
    eventFrame.OnEvent(eventFrame, "UNIT_AURA", "player", { isFullUpdate=true })
    assert(module.mask == 0, "an active alternative lethal poison created a false reminder")
    auras[315584] = { spellId=315584, auraInstanceID=102,
        expirationTime=now+120, duration=3600 }
    eventFrame.OnEvent(eventFrame, "UNIT_AURA", "player", { isFullUpdate=true })
    assert(module.mask == 0, "an expiring poison overrode a longer active alternative")
    auras[315584] = nil
    before = auraReads
    eventFrame.OnEvent(eventFrame, "UNIT_AURA", "player",
        { removedAuraInstanceIDs={ 102 } })
    assert(module.mask == 0 and auraReads > before,
        "removing one of two active poisons skipped a targeted refresh")
    module:Disable()
    auras[8679] = nil
end

-- Dragon-Tempered Blades permits two lethal and two nonlethal poisons on
-- Assassination. Missing slots select an actually absent known spell.
specID = 259
knownPoison[381801], knownPoison[381664], knownPoison[5761] = true, true, true
auras[2823] = { spellId=2823, auraInstanceID=200, expirationTime=now+900, duration=3600 }
auras[381664] = { spellId=381664, auraInstanceID=201, expirationTime=now+900, duration=3600 }
auras[381637] = { spellId=381637, auraInstanceID=202, expirationTime=now+900, duration=3600 }
auras[5761] = { spellId=5761, auraInstanceID=203, expirationTime=now+900, duration=3600 }
module.active = true
module:Enable()
assert(#module.entries == 4 and module.entries[1].id == 2823
    and module.entries[2].id == 381664 and module.entries[3].id == 381637
    and module.entries[4].id == 5761 and module.mask == 0,
    "Dragon-Tempered Blades did not track all four poison slots")
auras[2823], auras[381664], auras[381637], auras[5761] = nil, nil, nil, nil
eventFrame.OnEvent(eventFrame, "UNIT_AURA", "player", { isFullUpdate=true })
assert(module.mask == 15 and module.buttons[1].attributes.spell1 == 2823
    and module.buttons[2].attributes.spell1 == 381664
    and module.buttons[3].attributes.spell1 == 381637
    and module.buttons[4].attributes.spell1 == 5761,
    "four missing poisons did not create four distinct secure reminders")
auras[2823] = { spellId=2823, auraInstanceID=200, expirationTime=now+900, duration=3600 }
auras[381664] = { spellId=381664, auraInstanceID=201, expirationTime=now+900, duration=3600 }
auras[381637] = { spellId=381637, auraInstanceID=202, expirationTime=now+900, duration=3600 }
auras[5761] = { spellId=5761, auraInstanceID=203, expirationTime=now+900, duration=3600 }
eventFrame.OnEvent(eventFrame, "UNIT_AURA", "player", { isFullUpdate=true })
assert(module.mask == 0)
auras[381664] = nil
eventFrame.OnEvent(eventFrame, "UNIT_AURA", "player", { removedAuraInstanceIDs={ 201 } })
assert(module.mask == 1 and module.buttons[1].attributes.spell1 == 381664,
    "missing second lethal poison did not select Amplifying Poison")
auras[8679] = { spellId=8679, auraInstanceID=204, expirationTime=now+900, duration=3600 }
eventFrame.OnEvent(eventFrame, "UNIT_AURA", "player",
    { addedAuras={ {spellId=8679, auraInstanceID=204} } })
assert(module.mask == 0, "an active alternative did not fill the second lethal slot")
auras[8679], auras[5761] = nil, nil
eventFrame.OnEvent(eventFrame, "UNIT_AURA", "player",
    { removedAuraInstanceIDs={ 204, 203 } })
assert(module.mask == 5 and module.buttons[3].attributes.spell1 == 5761,
    "missing lethal and nonlethal slots did not produce distinct reminders")
auras[381664] = { spellId=381664, auraInstanceID=205, expirationTime=now+900, duration=3600 }
auras[5761] = { spellId=5761, auraInstanceID=206, expirationTime=now+900, duration=3600 }
eventFrame.OnEvent(eventFrame, "UNIT_AURA", "player", { isFullUpdate=true })
assert(module.mask == 0, "reapplied poisons did not clear all four reminders")
auras[2823] = { spellId=2823, auraInstanceID=200, expirationTime=now+120, duration=3600 }
eventFrame.OnEvent(eventFrame, "UNIT_AURA", "player", { isFullUpdate=true })
assert(module.mask == 1 and module.buttons[1].attributes.spell1 == 2823,
    "expiring Deadly Poison did not rebind its own reminder")
knownPoison[381801] = nil
eventFrame.OnEvent(eventFrame, "SPELLS_CHANGED")
assert(#module.entries == 2 and module.mask == 0,
    "losing Dragon-Tempered Blades retained four required poisons")
module:Disable()
auras[2823], auras[381664], auras[381637], auras[5761] = nil, nil, nil, nil

-- The same threshold applies to temporary weapon enchants.
module.config.autoRoguePoisons = false
module.config.mainHandItem = "456"
enchant[16] = { hasExpirationTime=true, remainingTimeMs=420000 }
module.active = true
module:Enable()
assert(#module.entries == 1 and module.mask == 0 and module.thresholdAt == now+120,
    "weapon enchant did not schedule its advance reminder")
before = enchantReads
FireNext()
assert(module.mask == 1 and enchantReads == before,
    "weapon advance reminder queried equipment at the threshold")
local pending = module.thresholdTimer
module:Disable()
assert(module.thresholdTimer == nil and (not pending or pending.cancelled),
    "disabling did not cancel the pending threshold timer")

-- Food warnings use the same timer, while a short eating aura is not treated
-- as an already expiring one-hour food buff.
module.config.mainHandItem, module.config.autoFood = "", true
local foodAura = { spellId=104280, icon=136000, auraInstanceID=555,
    expirationTime=now+420, duration=3600 }
auras[104280] = foodAura
module.active = true
module:Enable()
assert(#module.entries == 1 and module.entries[1].kind == "food"
    and module.mask == 0 and module.thresholdAt == now+120,
    "food did not schedule its advance warning")
before = foodReads
FireNext()
assert(module.mask == 1 and foodReads == before,
    "food warning rescanned auras at the threshold")
module:Disable()
foodAura = { spellId=104280, icon=133950, auraInstanceID=556,
    expirationTime=now+120, duration=120 }
auras[104280] = foodAura
module.active = true
module:Enable()
assert(module.mask == 0 and module.thresholdTimer == nil,
    "short eating aura was incorrectly treated as expiring food")
module:Disable()
auras[104280] = nil

-- A food aura learned from a UNIT_AURA delta by its icon, whose spell ID is
-- not in FOOD_AURAS, survives combat end, zone changes and full updates: a
-- rescan re-checks it by its instance ID instead of forgetting it.
local learnedFood = { spellId=990001, icon=136000, auraInstanceID=700 }
module.active = true
module:Enable()
assert(#module.entries == 1 and module.entries[1].kind == "food" and module.mask == 1,
    "missing food did not show its reminder")
instanceAuras[700] = learnedFood
eventFrame.OnEvent(eventFrame, "UNIT_AURA", "player", { addedAuras={ learnedFood } })
assert(module.mask == 0 and module.foodIDs[700], "a food aura learned by icon did not hide the reminder")
eventFrame.OnEvent(eventFrame, "PLAYER_REGEN_DISABLED")
eventFrame.OnEvent(eventFrame, "PLAYER_REGEN_ENABLED")
assert(module.mask == 0 and module.foodIDs[700],
    "combat end forgot a food aura whose spell ID is not in the list (false Food reminder)")
for _, event in ipairs({ "ZONE_CHANGED_NEW_AREA", "PLAYER_ENTERING_WORLD" }) do
    eventFrame.OnEvent(eventFrame, event)
    assert(module.mask == 0 and module.foodIDs[700], event .. " forgot a food aura learned by icon")
end
eventFrame.OnEvent(eventFrame, "UNIT_AURA", "player", { isFullUpdate=true })
assert(module.mask == 0 and module.foodIDs[700], "a full aura update forgot a food aura learned by icon")
-- An update of the learned aura refreshes it in place.
learnedFood.expirationTime, learnedFood.duration = now + 3000, 3600
eventFrame.OnEvent(eventFrame, "UNIT_AURA", "player", { updatedAuraInstanceIDs={ 700 } })
assert(module.mask == 0 and module.foodIDs[700] and module.foodIDs[700].expirationTime == now + 3000,
    "an updated food aura learned by icon was dropped or kept stale timing")
-- A restricted re-check is unknown, never missing, and keeps the aura.
instanceAuras[700] = { secret=true }
eventFrame.OnEvent(eventFrame, "PLAYER_REGEN_ENABLED")
assert(module.mask == 0 and module.foodIDs[700], "a restricted food re-check created a false reminder")
-- Food that ran out in combat (no aura listener then) is dropped by the re-check.
instanceAuras[700] = nil
eventFrame.OnEvent(eventFrame, "PLAYER_REGEN_DISABLED")
eventFrame.OnEvent(eventFrame, "PLAYER_REGEN_ENABLED")
assert(module.mask == 1 and not module.foodIDs[700], "an expired learned food aura was kept")
module:Disable()
-- After a reload nothing is learned yet: the targeted lookup by the listed
-- Well Fed spell name finds a variant whose spell ID is not in the list.
local renamedFood = { spellId=990002, icon=133950, auraInstanceID=701 }
namedAuras["Well Fed"], instanceAuras[701] = renamedFood, renamedFood
module.active = true
module:Enable()
assert(module.mask == 0 and module.foodIDs[701], "an unlisted Well Fed aura was not found after a reload")
namedAuras["Well Fed"], instanceAuras[701] = nil, nil
eventFrame.OnEvent(eventFrame, "UNIT_AURA", "player", { removedAuraInstanceIDs={ 701 } })
assert(module.mask == 1 and not next(module.foodIDs), "a removed Well Fed aura kept the food satisfied")
module:Disable()
-- With "instances only", no rescan runs in the open world; a food aura eaten
-- there is still learned and still counts after entering a dungeon.
module.config.instancesOnly = true
module.active = true
module:Enable()
assert(module.mask == 0 and module.foodKnown == nil, "the open world ran a food scan under instances only")
eventFrame.OnEvent(eventFrame, "UNIT_AURA", "player", { addedAuras={ learnedFood } })
instanceAuras[700] = learnedFood
GetInstanceInfo = function() return "Dungeon", "party" end
eventFrame.OnEvent(eventFrame, "PLAYER_ENTERING_WORLD")
assert(module.mask == 0 and module.foodIDs[700],
    "a food aura learned before the first rescan was forgotten on entering an instance")
module:Disable()
GetInstanceInfo = function() return "World", "none" end
module.config.instancesOnly = false
instanceAuras[700] = nil

-- Retail and WoW Forever always have the APIs the module calls (GameTooltip
-- included). The seasonal ID tables live only in Data.lua; every runtime file
-- reads P.BuffReminders in its header.
for i = 2, #BR_FILES do
    local name = BR_FILES[i]
    local file = assert(io.open(root .. "/MSUF_Suite_BuffReminders/" .. name, "rb"))
    local source = file:read("*a"):gsub("\r", "")
    file:close()
    local code = source:gsub("%-%-[^\n]*", "")
    local guarded = code:match("type%(([^)]*)%)%s*[~=]=%s*\"function\"") or code:match("(_G%.GameTooltip)")
    assert(not guarded, name .. " guards " .. tostring(guarded) .. " as if a client lacked it")
    local tables = code:find("local FLASKS = {", 1, true) or code:find("local FOOD_ICONS = {", 1, true)
    assert((name == "Data.lua") == (tables ~= nil), name .. " holds the seasonal ID tables")
    if name == "Data.lua" then
        assert(source:find("^local _, P = %.%.%.\n") and source:find("\nlocal R = {}\nP.BuffReminders = R\n", 1, true),
            "Data.lua does not create P.BuffReminders")
    else
        assert(source:find("^local _, P = %.%.%.\n[^\n]*\nlocal R = P%.BuffReminders\n"),
            name .. " does not read P.BuffReminders in its header")
    end
    assert((name == "Controller.lua") == (code:find("S.Install(", 1, true) ~= nil), name .. " install mismatch")
end
print("Suite buff reminders: secure pool, targeted checks, Rogue spec poisons, advance warnings, restricted aura suppression, combat silence and cleanup passed")

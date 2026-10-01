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
    function w:SetTextColor(r, g, b) self.color = { r, g, b } end
    function w:SetTexture(value)
        textureWrites = textureWrites + 1
        self.texture = value
    end
    function w:SetDesaturated(value) self.desaturated = value end
    function w:SetAlpha(value) self.alpha = value end
    function w:CreateAnimationGroup()
        local group = { playing = false }
        function group:SetLooping(value) self.looping = value end
        function group:Play() self.playing = true end
        function group:Stop() self.playing = false end
        function group:CreateAnimation()
            return { SetFromAlpha=function() end, SetToAlpha=function() end, SetDuration=function() end }
        end
        return group
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
Enum = { SpellBookSpellBank = { Player = 0, Pet = 1 }, PowerType = { Mana = 0 },
    ItemClass = { Consumable = 0 }, ItemConsumableSubclass = { Fooddrink = 5 } }
-- Empty bags unless a test fills them: food is found by its eating spell.
Constants = { InventoryConstants = { NumBagSlots = 4 } }
local bagItems = {}
C_Container = {
    GetContainerNumSlots = function(bag) return bag <= 4 and 16 or 0 end,
    GetContainerItemID = function(bag, slot) return bagItems[bag * 100 + slot] end,
}
DifficultyUtil = { ID={ DungeonTimewalker=24, RaidTimewalker=33 } }
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
-- The listed Well Fed IDs share one spell name here; Hearty Well Fed has
-- its own. The food rescan looks each name up once per scan.
local FOOD_NAME_IDS = { [104280] = true, [1219179] = true, [1232076] = true }
C_Spell = {
    GetSpellTexture = function(id) return id end,
    GetSpellName = function(id)
        if id == 1232076 then return "Hearty Well Fed" end
        return FOOD_NAME_IDS[id] and "Well Fed" or ("Spell " .. id)
    end,
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
-- A targeted name lookup finds Well Fed variants after reload. Instance-ID
-- lookups are forbidden: they raise on tainted secret auras in live M+.
local namedAuras = {}
C_UnitAuras = {
    GetPlayerAuraBySpellID = function(id)
        auraReads = auraReads + 1
        if FOOD_NAME_IDS[id] or id == 990001 or id == 990002 then foodReads = foodReads + 1 end
        return auras[id]
    end,
    GetAuraDataByAuraInstanceID = function() error("instance-ID aura read is forbidden") end,
    GetAuraDataBySpellName = function(unit, name, filter)
        assert(unit == "player" and type(name) == "string" and filter == "HELPFUL",
            "food name lookup must be a targeted helpful player lookup")
        foodReads = foodReads + 1
        return namedAuras[name]
    end,
}
-- Blizzard_GameTooltip builds GameTooltip at startup on both clients.
-- RequiresNonSecretAura lookups return nothing while aura data is restricted;
-- C_Secrets.ShouldAurasBeSecret reports that state.
local auraRestricted = false
C_Secrets = { ShouldAurasBeSecret = function() return auraRestricted end }
-- Coalesced group passes run through C_Timer.After.
local afterQueue = {}
local function RunAfter()
    local queued = afterQueue
    afterQueue = {}
    for _, job in ipairs(queued) do job.callback() end
    return #queued
end
GameTooltip = Widget()
function GameTooltip:SetOwner(owner) self.owner, self.spell, self.item = owner, nil, nil end
function GameTooltip:SetSpellByID(id) self.spell = id end
function GameTooltip:SetItemByID(id) self.item = id end
function GameTooltip:AddLine(value) self.extraLine = value end

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
    ResolveFont=function(value) return value end,
    SetFont=function(font, path, size, flags) font.fontPath, font.fontSize, font.fontFlags = path, size, flags end,
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
    AnchorPoints={ "TOPLEFT", "TOP", "TOPRIGHT", "LEFT", "CENTER", "RIGHT", "BOTTOMLEFT", "BOTTOM", "BOTTOMRIGHT" },
    Client={ SupportsEvent=function() return true end } }
-- Data, readers, entry selection and the controller load in TOC order into
-- one private table (Bootstrap only fills it from _G.MSUFSuite).
local Support = dofile(root .. "/tools/tests/suite_test_support.lua")
local BR_FILES = { "Bootstrap.lua", "Data.lua", "Readers.lua", "Group.lua", "Entries.lua", "Preparation.lua", "Alerts.lua", "Special.lua", "Cursor.lua", "Controller.lua" }
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
-- Edit Mode shows enabled reminders despite real presence, without reading
-- live auras or replacing their count/presence cache with sample values.
local cachedPresent,cachedCount=module.entries[1].present,module.entries[3].count
S.editMode=true
before=auraReads
module:Update("visual")
assert(module.mask==15 and module.buttons[1].shown and module.buttons[3].count.text=="5")
assert(auraReads==before and module.entries[1].present==cachedPresent and module.entries[3].count==cachedCount)
assert(not module.thresholdTimer and not module.cursorFollowing)
S.editMode=false
module:Update("visual")
assert(module.mask==14 and not module.buttons[1].shown and module.buttons[3].count.text=="2",
    "closing preview must restore actual presence and counts even when cache values did not change")
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
-- One scan: the three listed food buff IDs plus their two spell names.
assert(module.mask == 30 and foodReads == 5, "missing default consumables were not shown")
-- The augment rune is a separate consumable. Its primary-stat aura must not
-- satisfy the flask reminder when no flask aura is active.
auras[1264426] = { spellId = 1264426, auraInstanceID = 81 }
-- Rune auras run from the highest spell ID down, like the item lists: the
-- current rune is found with one lookup.
do
    local runeAuras = private.BuffReminders.RUNE_AURAS
    for i = 2, #runeAuras do assert(runeAuras[i] < runeAuras[i - 1], "rune auras are not ordered newest first") end
    local lookups, lookup = 0, C_UnitAuras.GetPlayerAuraBySpellID
    C_UnitAuras.GetPlayerAuraBySpellID = function(id) lookups = lookups + 1; return lookup(id) end
    assert(module.entries[4].aliases == runeAuras and private.BuffReminders.AuraPresent(module.entries[4]) == true
        and lookups == 1, "finding the current rune took " .. lookups .. " aura lookups")
    C_UnitAuras.GetPlayerAuraBySpellID = lookup
end
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
eventFrame.OnEvent(eventFrame, "UNIT_AURA", "player", { addedAuras={ {spellId=104280, icon=136000, auraInstanceID=44} } })
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
-- rescan re-checks it by spell ID instead of forgetting it.
local learnedFood = { spellId=990001, icon=136000, auraInstanceID=700 }
module.active = true
module:Enable()
assert(#module.entries == 1 and module.entries[1].kind == "food" and module.mask == 1,
    "missing food did not show its reminder")
auras[990001] = learnedFood
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
-- A recreated food aura gets a new instance ID without ever using an
-- instance-ID lookup; the next removal must address the new ID.
local replacedFood = { spellId=990001, icon=136000, auraInstanceID=702 }
auras[990001] = replacedFood
eventFrame.OnEvent(eventFrame, "UNIT_AURA", "player", { isFullUpdate=true })
assert(module.mask == 0 and module.foodIDs[702] and not module.foodIDs[700],
    "a food aura with a new instance ID kept its old key")
auras[990001] = learnedFood
eventFrame.OnEvent(eventFrame, "UNIT_AURA", "player", { isFullUpdate=true })
assert(module.mask == 0 and module.foodIDs[700] and not module.foodIDs[702],
    "the food snapshot did not follow a second instance-ID change")
-- An update of the learned aura refreshes it in place.
learnedFood.expirationTime, learnedFood.duration = now + 3000, 3600
eventFrame.OnEvent(eventFrame, "UNIT_AURA", "player", { updatedAuraInstanceIDs={ 700 } })
assert(module.mask == 0 and module.foodIDs[700] and module.foodIDs[700].expirationTime == now + 3000,
    "an updated food aura learned by icon was dropped or kept stale timing")
-- A restricted re-check is unknown, never missing, and keeps the aura.
auras[990001] = { secret=true }
eventFrame.OnEvent(eventFrame, "PLAYER_REGEN_ENABLED")
assert(module.mask == 0 and module.foodIDs[700], "a restricted food re-check created a false reminder")
-- Food that ran out in combat (no aura listener then) is dropped by the re-check.
auras[990001] = nil


eventFrame.OnEvent(eventFrame, "PLAYER_REGEN_DISABLED")
eventFrame.OnEvent(eventFrame, "PLAYER_REGEN_ENABLED")
assert(module.mask == 1 and not module.foodIDs[700], "an expired learned food aura was kept")
module:Disable()
-- After a reload nothing is learned yet: the targeted lookup by the listed
-- Well Fed spell name finds a variant whose spell ID is not in the list.
local renamedFood = { spellId=990002, icon=133950, auraInstanceID=701 }
namedAuras["Well Fed"], auras[990002] = renamedFood, renamedFood
module.active = true
module:Enable()
assert(module.mask == 0 and module.foodIDs[701], "an unlisted Well Fed aura was not found after a reload")
namedAuras["Well Fed"], auras[990002] = nil, nil
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
auras[990001] = learnedFood
GetInstanceInfo = function() return "Dungeon", "party" end
eventFrame.OnEvent(eventFrame, "PLAYER_ENTERING_WORLD")
assert(module.mask == 0 and module.foodIDs[700],
    "a food aura learned before the first rescan was forgotten on entering an instance")
module:Disable()
GetInstanceInfo = function() return "World", "none" end
module.config.instancesOnly = false
auras[990001] = nil

-- A preferred supported item wins when stocked, falls back when depleted,
-- and an empty category stays as an inert restock reminder.
module.config = { classBuff=false, spellIDs="", items="", mainHandItem="", offHandItem="",
    autoFlask=true, restockNotice=true, flaskChoice="241325", instancesOnly=false,
    hideMounted=true, size=38, spacing=5, columns=6, borderColor="e8b855", point=1, x=0, y=0,
    remindBeforeMinutes=5, keystoneCover=3, keystoneMinutes=30, countFont="test-face", countSize=17, countPosition=1, countX=3, countY=-4 }
NS.Client.modernEquipment = true
inventory = { [241324]=3, [241325]=2 }
auras = {}
module.active = true
module:Enable()
assert(module.entries[1].id == 241325 and module.buttons[1].count.fontSize == 17,
    "preferred stocked flask or count styling was ignored")
inventory[241325] = 0
eventFrame.OnEvent(eventFrame, "BAG_UPDATE_DELAYED")
assert(module.entries[1].id == 241324 and not module.entries[1].restock,
    "depleted preferred flask did not fall back")
inventory[241324] = 0
eventFrame.OnEvent(eventFrame, "BAG_UPDATE_DELAYED")
assert(module.entries[1].id == 241325 and module.entries[1].restock and module.mask == 1
    and module.buttons[1].attributes.type1 == nil and module.buttons[1].attributes.item1 == nil
    and module.buttons[1].icon.desaturated and module.buttons[1].count.text == "0",
    "out-of-stock category must be a gray, non-actionable reminder")
module.buttons[1]:OnEnter()
assert(GameTooltip.extraLine and GameTooltip.extraLine:find("restock", 1, true), "restock tooltip did not explain the disabled action")
inventory[241325] = 4
eventFrame.OnEvent(eventFrame, "BAG_UPDATE_DELAYED")
assert(not module.entries[1].restock and module.buttons[1].attributes.item1 == "item:241325"
    and not module.buttons[1].icon.desaturated, "restocking did not restore the secure click action")
AssertQuietCompile("preferred consumable selection")

-- Pre-key warning uses the longer threshold only before the run; one native
-- challenge edge changes the policy without rescanning the aura.
local challengeActive = false
DifficultyUtil = { ID={ DungeonTimewalker=24, RaidTimewalker=33 } }
GetInstanceInfo = function() return "Dungeon", "party", 23 end
GetDifficultyInfo = function() return "Mythic", "party", false, false, false, true end
C_ChallengeMode = { IsChallengeModeActive=function() return challengeActive end }
auras[1235110] = { spellId=1235110, auraInstanceID=801, expirationTime=now+1200, duration=3600 }
eventFrame.OnEvent(eventFrame, "PLAYER_ENTERING_WORLD")
assert(module.mask == 1 and private.BuffReminders.Threshold(module) == 1800,
    "pre-key threshold did not show a buff that expires during the configured run time")
before = auraReads
challengeActive = true
eventFrame.OnEvent(eventFrame, "CHALLENGE_MODE_START")
assert(module.mask == 0 and auraReads == before and private.BuffReminders.Threshold(module) == 300,
    "key start did not restore the normal threshold without an aura scan")
challengeActive = false
eventFrame.OnEvent(eventFrame, "CHALLENGE_MODE_COMPLETED")
assert(private.BuffReminders.Threshold(module) == 300, "completed key was treated as a new pre-key lobby")
eventFrame.OnEvent(eventFrame, "CHALLENGE_MODE_RESET")
assert(private.BuffReminders.Threshold(module) == 1800, "reset did not restore pre-key preparation")
module.config.showDungeonMythic = false
module:Refresh()
assert(module.mask == 0, "content visibility did not hide reminders")
module.config.showDungeonMythic = true

-- Readycheck mana is evaluated once at the check. No aura or inventory work
-- is necessary, and entering combat cancels the one temporary warning timer.
module.config.readyCheckMana, module.config.readyCheckManaPercent = true, 80
module.config.readyCheckDuration = 10
UnitGroupRolesAssigned = function() return "HEALER" end
UnitPower = function() return 50 end
UnitPowerMax = function() return 100 end
module:Refresh()
before = auraReads
eventFrame.OnEvent(eventFrame, "READY_CHECK")
assert(module.readyCheckWarning.shown and module.readyCheckWarning.text:find("50%%")
    and auraReads == before and module.readyCheckTimer, "readycheck low-mana warning failed")
local warningTimer = module.readyCheckTimer
UnitPower = function() return { secret=true } end
eventFrame.OnEvent(eventFrame, "READY_CHECK")
assert(not module.readyCheckWarning.shown and warningTimer.cancelled, "secret mana was treated as low mana")
UnitPower = function() return 10 end
UnitGroupRolesAssigned = function() return "DAMAGER" end
eventFrame.OnEvent(eventFrame, "READY_CHECK")
assert(not module.readyCheckWarning.shown, "non-healer got a healer mana warning")
UnitGroupRolesAssigned = function() return "HEALER" end
eventFrame.OnEvent(eventFrame, "READY_CHECK")
warningTimer = module.readyCheckTimer
combat = true
eventFrame.OnEvent(eventFrame, "PLAYER_REGEN_DISABLED")
assert(warningTimer.cancelled and not eventFrame.events.READY_CHECK and not eventFrame.events.CHALLENGE_MODE_START,
    "combat kept preparation listeners or the warning timer running")
combat = false
eventFrame.OnEvent(eventFrame, "PLAYER_REGEN_ENABLED")
module:Disable()
assert(not eventFrame.events.READY_CHECK and not eventFrame.events.CHALLENGE_MODE_START, "disable leaked preparation events")

-- Alert identity is independent of positions and event count. Pulse runs in
-- the animation engine, and disappearing/disable stops its animation.
local sounds = 0
SOUNDKIT = { RAID_WARNING=1, READY_CHECK=2, IG_QUEST_LOG_OPEN=3 }
PlaySound = function(id, channel) assert(id == 1 and channel == "Dialog"); sounds = sounds + 1 end
local alertOwner = { config={ reminderSound=2, reminderSoundChannel=3, reminderGlow=3,
    reminderGlowColor="ff0000" }, buttons={} }
local alertButton = { border=Widget() }
alertOwner.buttons[1] = alertButton
local alertEntry = { kind="spell", id=1459 }
local BR = private.BuffReminders
BR.AlertTransition(alertOwner, alertButton, alertEntry, true)
BR.PlayReminderAlert(alertOwner)
assert(sounds == 1 and alertButton.alertPulse.playing, "new reminder did not sound/pulse")
BR.AlertTransition(alertOwner, alertButton, alertEntry, true)
BR.PlayReminderAlert(alertOwner)
assert(sounds == 1, "unchanged reminder repeated its sound")
BR.AlertTransition(alertOwner, alertButton, alertEntry, false)
assert(not alertButton.alertPulse.playing, "hidden reminder kept its pulse running")
BR.AlertTransition(alertOwner, alertButton, alertEntry, true)
BR.PlayReminderAlert(alertOwner)
assert(sounds == 2, "reappearing reminder did not alert")
-- A visible reminder keeps its running pulse: further mask changes neither
-- restart it nor build identity strings.
do
    local group = alertButton.alertPulse
    local plays, stops = 0, 0
    local play, stop = group.Play, group.Stop
    group.Play = function(self) plays = plays + 1; return play(self) end
    group.Stop = function(self) stops = stops + 1; return stop(self) end
    collectgarbage("collect")
    collectgarbage("stop")
    local before = collectgarbage("count")
    for _ = 1, 500 do BR.AlertTransition(alertOwner, alertButton, alertEntry, true) end
    local grown = collectgarbage("count") - before
    collectgarbage("restart")
    assert(plays == 0 and stops == 0 and group.playing, "an unchanged reminder restarted its pulse")
    assert(grown < 1, "unchanged alert transitions allocated " .. grown .. " KB")
    group.Play, group.Stop = play, stop
    -- The identity is compared field by field; no string is built for it.
    local concats = 0
    local counted = { kind = "spell", id = setmetatable({}, { __concat = function()
        concats = concats + 1
        return "id"
    end }) }
    for _ = 1, 3 do BR.AlertTransition(alertOwner, alertButton, counted, true) end
    assert(concats == 0, "an alert transition built an identity string")
    BR.AlertTransition(alertOwner, alertButton, alertEntry, true)
    alertOwner.newReminderAlert = nil
end
BR.StopReminderAlerts(alertOwner)
assert(not alertButton.alertPulse.playing and alertButton.alertKind == nil and alertButton.alertID == nil,
    "alert teardown leaked")

-- Group coverage uses eligible roster members and targeted aura reads. An
-- invisible/disconnected unit and a restricted lookup cannot imply absence.
do
    local roster={ player="MAGE", party1="PRIEST", party2="WARRIOR" }
    local groupAuras={player=true,party1=false,party2=false}
    local invisible={party2=true}
    local reads=0
    UnitClass=function(unit) return roster[unit],roster[unit] end
    knownSpell=function(id) return id==1459 end
    IsInRaid=function() return false end
    GetNumSubgroupMembers=function() return 2 end
    GetNumGroupMembers=function() return 0 end
    UnitIsUnit=function(unit,other) return unit==other end
    UnitExists=function(unit) return roster[unit]~=nil end
    UnitIsConnected=function() return true end
    UnitIsVisible=function(unit) return not invisible[unit] end
    UnitIsDeadOrGhost=function() return false end
    C_Secrets={ShouldAurasBeSecret=function() return false end}
    C_UnitAuras.GetUnitAuraBySpellID=function(unit)
        reads=reads+1
        return groupAuras[unit] and {} or nil
    end
    local owner={config={groupBuff=true,classBuff=true,otherClassBuffs=true}}
    BR.GroupRoster(owner)
    assert(owner.groupClasses.PRIEST and owner.groupClasses.WARRIOR,"roster class coverage missing")
    BR.RefreshGroup(owner)
    local entry={}
    assert(not BR.GroupPresent(owner,entry) and entry.missingCount==1,"invisible member was reported missing")
    local beforeReads=reads
    groupAuras.party1=true
    BR.RefreshGroup(owner,"party1")
    assert(BR.GroupPresent(owner,entry) and reads==beforeReads+1,"unit delta rescanned the roster")
    local reader=C_UnitAuras.GetUnitAuraBySpellID
    C_Secrets.ShouldAurasBeSecret=function() return true end
    C_UnitAuras.GetUnitAuraBySpellID=function() end
    BR.RefreshGroup(owner,"party1")
    assert(BR.GroupPresent(owner,entry),"a restricted aura lookup that returned nothing became false absence")
    C_Secrets.ShouldAurasBeSecret=function() return false end
    C_UnitAuras.GetUnitAuraBySpellID=reader
    C_Secrets.ShouldAurasBeSecret=function() return true end
    BR.RefreshGroup(owner)
    assert(BR.GroupPresent(owner,entry),"restricted group state became false absence")
    C_Secrets.ShouldAurasBeSecret=function() return false end
    knownSpell=function(id) return id==20707 end
    owner.config={soulstoneOnAlly=true}
    invisible.party2=nil
    local stoneSource
    C_UnitAuras.GetAuraDataBySpellName=function(unit,name,filter)
        assert(name=="Spell 20707" and filter=="HELPFUL|PLAYER")
        if unit=="party1" and stoneSource=="player" then return {sourceUnit=stoneSource} end
    end
    BR.RefreshGroup(owner)
    assert(owner.soulstoneMissing,"missing own Soulstone not detected")
    stoneSource="party2"; BR.RefreshGroup(owner,"party1")
    assert(owner.soulstoneMissing,"another Warlock's Soulstone incorrectly satisfied own reminder")
    stoneSource="player"; BR.RefreshGroup(owner,"party1")
    assert(owner.soulstoneMissing==false,"own Soulstone on party member was not detected")
    -- A member out of sight (or offline, or dead) cannot hold a readable
    -- Soulstone: in a raid one such member must not silence the notice.
    stoneSource=nil; invisible.party2=true; BR.RefreshGroup(owner)
    assert(owner.soulstoneMissing==true,"an out-of-sight member silenced the missing-Soulstone notice")
    stoneSource="player"; BR.RefreshGroup(owner,"party1")
    assert(owner.soulstoneMissing==false,"own Soulstone beside an out-of-sight member was not detected")
    local restrictedGroup=C_Secrets.ShouldAurasBeSecret
    C_Secrets.ShouldAurasBeSecret=function() return true end
    stoneSource=nil; BR.RefreshGroup(owner)
    assert(owner.soulstoneMissing==nil,"restricted aura data must not imply a missing Soulstone")
    C_Secrets.ShouldAurasBeSecret=restrictedGroup
end
do
    local owner={config={petPassiveWarning=true,healthstoneFromWarlock=true},groupClasses={WARLOCK=true},host=Widget()}
    NUM_PET_ACTION_SLOTS=10
    UnitExists=function(unit) return unit=="pet" end
    UnitIsDeadOrGhost=function() return false end
    local passive=true
    GetPetActionInfo=function(index)
        if index==10 then return "PET_MODE_PASSIVE",nil,true,passive end
    end
    BR.ReadPet(owner)
    assert(owner.petPassive,"active passive pet mode was not detected")
    passive={secret=true}
    BR.ReadPet(owner)
    assert(owner.petPassive==nil,"secret pet reaction became a warning")
    inventory={[5512]=0,[224464]=0}
    BR.ReadHealthstone(owner)
    BR.SpecialText(owner,true)
    assert(owner.healthstoneMissing and owner.specialWarning.shown,"missing healthstone warning not shown")
    inventory[224464]=1
    BR.ReadHealthstone(owner)
    BR.SpecialText(owner,true)
    assert(not owner.healthstoneMissing and not owner.specialWarning.shown,"demonic healthstone did not satisfy reminder")
    owner.groupClasses.WARLOCK=nil
    inventory[224464]=0
    BR.ReadHealthstone(owner)
    assert(not owner.healthstoneMissing,"healthstone warning remained after Warlock left")
    NS.BuffReminderDemons={
        {key="demonImp",spells={688},family=23},
        {key="demonFelguard",spells={30146},family=29},
    }
    owner.config={demonChoiceWarning=true,demonImp=false,demonFelguard=true}
    UnitClass=function() return "Warlock","WARLOCK" end
    knownSpell=function(id) return id==688 or id==30146 end
    local family=23
    UnitCreatureFamily=function() return "Pet",family end
    BR.ReadPet(owner); assert(owner.wrongDemon,"disallowed Imp did not warn")
    family=29; BR.ReadPet(owner); assert(owner.wrongDemon==false,"a chosen Felguard warned")
    -- A family the check does not know (a cosmetic version) is never judged.
    family=104; BR.ReadPet(owner); assert(owner.wrongDemon==nil,"an unrecognized demon family caused a warning")
    family={secret=true}; BR.ReadPet(owner); assert(owner.wrongDemon==nil,"secret family caused a demon warning")
    knownSpell=function(id) return id==688 end
    family=23; BR.ReadPet(owner); assert(owner.wrongDemon==nil,"unavailable allowed summon caused an impossible warning")
    -- One known summon of a chosen demon is enough: the spell checks stop
    -- there, and the list stops once the pet's demon is known as well.
    NS.BuffReminderDemons={
        {key="demonImp",spells={688},family=23},
        {key="demonVoidwalker",spells={697},family=16},
        {key="demonFelhunter",spells={691},family=15},
        {key="demonSayaad",spells={366222,712,713},family=17},
        {key="demonFelguard",spells={30146},family=29},
    }
    owner.config={demonChoiceWarning=true,demonImp=false}
    local spellChecks=0
    knownSpell=function(id) spellChecks=spellChecks+1; return id~=688 end
    for _,pet in ipairs({16,29}) do
        spellChecks=0; family=pet; BR.ReadPet(owner)
        assert(owner.wrongDemon==false and spellChecks==1,
            "the demon check read "..spellChecks.." summon spells for family "..pet)
    end
    spellChecks=0; family=23; BR.ReadPet(owner)
    assert(owner.wrongDemon==true and spellChecks==1,"a disallowed Imp did not warn after one summon check")
    local visited={}
    for index,demon in ipairs(NS.BuffReminderDemons) do
        NS.BuffReminderDemons[index]=setmetatable({},{__index=function(_,key)
            if key=="family" then visited[index]=true end
            return demon[key]
        end})
    end
    family=16; BR.ReadPet(owner)
    assert(owner.wrongDemon==false and visited[2] and not visited[3],"the demon list went on after both answers were known")
end

-- Game IDs live in Data.lua only; the selection code reads them from there.
-- Food is found from the game's eating spells, never from an item list.
do
    for _, name in ipairs({ "Entries.lua", "Controller.lua", "Special.lua" }) do
        local file = assert(io.open(root .. "/MSUF_Suite_BuffReminders/" .. name, "rb"))
        local source = file:read("*a")
        file:close()
        for _, id in ipairs({ "1229741", "124640" }) do
            assert(not source:find(id, 1, true), name .. " holds the game ID " .. id .. " outside Data.lua")
        end
    end
    assert(BR.CAMP_BENEFITS == 1229741, "Data.lua lost the Camp Benefits spell")
    assert(BR.FOODS == nil, "food reminders read an item list again")
end

-- Retail and WoW Forever always have the APIs the module calls (GameTooltip
do
    local moves=0
    local owner={active=true,mask=1,host=Widget(),config={followCursor=true,cursorOffsetX=24,cursorOffsetY=24,point=1,x=0,y=0}}
    owner.host.SetPoint=function() assert(not combat,"cursor moved a protected host in combat");moves=moves+1 end
    UIParent.GetEffectiveScale=function() return 2 end
    local cx,cy=100,200
    GetCursorPosition=function() return cx,cy end
    BR.SyncCursor(owner)
    assert(owner.cursorDriver.OnUpdate and moves==1)
    owner.cursorDriver.OnUpdate(owner.cursorDriver)
    assert(moves==1,"unchanged cursor rewrote the anchor")
    cx=120;owner.cursorDriver.OnUpdate(owner.cursorDriver)
    assert(moves==2)
    combat=true;owner.cursorDriver.OnUpdate(owner.cursorDriver)
    assert(not owner.cursorDriver.OnUpdate and moves==2,"combat did not immediately stop cursor input")
    combat=false;BR.SyncCursor(owner)
    owner.mask=0;BR.SyncCursor(owner)
    assert(not owner.cursorDriver.OnUpdate and not owner.cursorFollowing,"no visible reminder kept a cursor reader")
    assert(not owner.cursorDisplaced,"restoring the anchor retained displacement")
    owner.mask=1;BR.SyncCursor(owner)
    local before=moves
    combat=true;BR.StopCursor(owner,false)
    owner.config.followCursor=false;BR.SyncCursor(owner)
    assert(moves==before and owner.cursorDisplaced,"combat suspension forgot pending anchor restoration")
    combat=false;BR.SyncCursor(owner)
    assert(moves==before+1 and not owner.cursorDisplaced,"combat exit did not restore the static anchor")
    owner.config.followCursor=true;BR.SyncCursor(owner)
    before=moves
    owner.active=false;BR.StopCursor(owner,false)
    owner.config.followCursor=false;owner.active=true;BR.SyncCursor(owner)
    assert(moves==before+1 and not owner.cursorDisplaced,"disable/re-enable lost the static anchor")
end

do
    NS.Client.isForever=true
    knownSpell=function(id) return id==1243 end
    UnitClass=function() return "Priest","PRIEST" end
    IsInRaid=function() return false end
    GetNumSubgroupMembers=function() return 1 end
    UnitIsUnit=function(a,b) return a==b end
    UnitExists=function() return true end
    UnitIsConnected=function() return true end
    UnitIsVisible=function() return true end
    UnitIsDeadOrGhost=function() return false end
    local rankAura={spellId=10938,name="Spell 1243",auraInstanceID=101,duration=0,expirationTime=0}
    local groupRank=true
    C_UnitAuras.GetAuraDataBySpellName=function(unit,name,filter)
        assert(filter=="HELPFUL")
        if name=="Spell 1243" and (unit=="player" or groupRank) then return rankAura end
    end
    local owner={config={classBuff=true,groupBuff=true,spellIDs="",items="",mainHandItem="",offHandItem=""}}
    local entries=BR.BuildEntries(owner)
    local entry=entries[1]
    assert(#entries==1 and entry.id==1243 and entry.ranked and entry.spellName=="Spell 1243",
        "Forever priest must use Fortitude and its native named cast")
    assert(BR.AuraPresent(entry)==true,"higher-rank Fortitude was falsely missing")
    entry.present=false
    assert(BR.AuraChangeAffects(entry,{addedAuras={rankAura}}),"added higher rank did not invalidate absence")
    assert(not BR.AuraChangeAffects(entry,{addedAuras={{spellId=999,name="unrelated"}}}),"unrelated aura invalidated rank cache")
    BR.RefreshGroup(owner)
    assert(BR.GroupPresent(owner,entry),"native group rank was falsely missing")
    groupRank=false;BR.RefreshGroup(owner,"party1")
    assert(not BR.GroupPresent(owner,entry) and entry.missingCount==1)
    local secrets=C_Secrets.ShouldAurasBeSecret
    C_Secrets.ShouldAurasBeSecret=function() return true end
    C_UnitAuras.GetAuraDataBySpellName=function() end
    assert(BR.AuraPresent(entry)==nil,"a restricted rank lookup that returned nothing became absence")
    BR.RefreshGroup(owner,"party1")
    assert(BR.GroupPresent(owner,entry),"a restricted group rank lookup became absence")
    C_Secrets.ShouldAurasBeSecret=secrets
    NS.Client.isForever=false
    assert(BR.ClassBuff("PRIEST").cast==21562,"Forever table replaced Retail catalog")
end

do
    local owner={config={beaconOnAlly=true},groupUnits={player=true,party1=true,party2=true},groupClasses={WARLOCK=true}}
    local knownReads, queries = 0, 0
    knownSpell=function(id) knownReads=knownReads+1;return id==53563 or id==156910 end
    local light,faith,restricted
    C_UnitAuras.GetUnitAuraBySpellID=function() error("own aura must use the native caster filter") end
    C_UnitAuras.GetAuraDataBySpellName=function(unit,name,filter)
        queries=queries+1
        assert(filter=="HELPFUL|PLAYER","own buffs must select their caster natively")
        if restricted==unit then return {secret=true} end
        if name=="Spell 53563" and unit==light or name=="Spell 156910" and unit==faith then
            return {sourceUnit={secret=true}} -- Ownership already selected natively.
        end
    end
    BR.RefreshGroup(owner)
    assert(owner.beaconMissing,"known Beacons missing everywhere must warn")
    light="party1";BR.RefreshGroup(owner,"party1")
    assert(owner.beaconMissing,"Faith remains required when only Light is active")
    local beforeKnown=knownReads
    faith="party2";BR.RefreshGroup(owner,"party2")
    assert(not owner.beaconMissing and knownReads==beforeKnown,"targeted Beacon update must reuse spell knowledge")
    local beforeQueries=queries
    BR.RefreshGroup(owner,"nameplate1")
    assert(queries==beforeQueries,"untracked unit event queried group buffs")
    faith=nil;restricted="party2";BR.RefreshGroup(owner,"party2")
    assert(not owner.beaconMissing,"unknown group presence must not become a missing Beacon")
    restricted=nil;BR.RefreshGroup(owner,"party2")
    assert(owner.beaconMissing,"native own-filter absence must warn even if another caster has a Beacon")
    knownSpell=function() return false end;BR.RefreshGroup(owner)
    assert(not owner.beaconMissing,"unavailable Beacon must not warn")

    NS.Client.isForever=true
    owner.config={soulstoneOnAlly=true,healthstoneFromWarlock=true}
    knownSpell=function(id) return id==20757 end
    local ranked=false
    C_UnitAuras.GetAuraDataBySpellName=function(unit,name,filter)
        assert(name=="Spell 20707" and filter=="HELPFUL|PLAYER")
        if unit=="party1" and ranked then return {spellId=20765} end
    end
    BR.RefreshGroup(owner)
    assert(owner.soulstoneMissing,"Forever creation-spell knowledge must enable the reminder")
    ranked=true;BR.RefreshGroup(owner,"party1")
    assert(owner.soulstoneMissing==false,"higher-rank own Soulstone must satisfy native family lookup")
    for _,id in ipairs(BR.FOREVER_HEALTHSTONES) do
        inventory={[id]=1};BR.ReadHealthstone(owner)
        assert(owner.healthstoneMissing==false,"missing Forever Healthstone variant "..id)
    end
    inventory={};BR.ReadHealthstone(owner);assert(owner.healthstoneMissing==true)
    inventory={[19013]={secret=true}};BR.ReadHealthstone(owner)
    assert(owner.healthstoneMissing==nil,"unreadable stone count must remain unknown")
    NS.Client.isForever=false
    inventory={[224464]=1};BR.ReadHealthstone(owner);assert(owner.healthstoneMissing==false)
end

do
    local roster = { player = "MAGE", party1 = "PRIEST", party2 = "WARRIOR" }
    local memberAuras = { player = true, party1 = false, party2 = true }
    UnitClass = function(unit) return roster[unit], roster[unit] end
    knownSpell = function(id) return id == 1459 end
    IsInRaid = function() return false end
    local members = 2
    GetNumSubgroupMembers = function() return members end
    UnitIsUnit = function(unit, other) return unit == other end
    UnitExists = function(unit) return roster[unit] ~= nil end
    UnitIsConnected = function() return true end
    UnitIsVisible = function() return true end
    UnitIsDeadOrGhost = function() return false end
    C_Secrets.ShouldAurasBeSecret = function() return false end
    C_UnitAuras.GetUnitAuraBySpellID = function(unit) return memberAuras[unit] and {} or nil end
    C_Timer.After = function(delay, callback)
        assert(delay == 0.1, "group pass delay changed")
        afterQueue[#afterQueue + 1] = { callback = callback }
    end
    NS.Client.isForever, NS.Client.modernEquipment = false, false
    inventory = { [123] = 4 }
    module.config = { classBuff=true, groupBuff=true, spellIDs="", items="123:888", mainHandItem="",
        offHandItem="", instancesOnly=false, hideMounted=true, size=38, spacing=5, columns=6,
        borderColor="e8b855", point=1, x=0, y=0, remindBeforeMinutes=0 }
    afterQueue = {}
    module.active = true
    module:Enable()
    RunAfter()
    assert(not eventFrame.events.ZONE_CHANGED and not eventFrame.events.ZONE_CHANGED_INDOORS,
        "subzone steps still recompile the reminders")
    local list = eventFrame.events.UNIT_AURA
    assert(type(list) == "table" and #list == 3 and list[1] == "player" and list[2] == "party1" and list[3] == "party2",
        "group options did not limit UNIT_AURA to the player and the roster units")
    for _, event in ipairs({ "UNIT_CONNECTION", "UNIT_FLAGS", "UNIT_PHASE" }) do
        assert(eventFrame.events[event] == list, event .. " is not limited to the roster units")
    end
    local updates, compiles = 0, 0
    local update, compile = module.Update, module.Compile
    module.Update = function(...) updates = updates + 1; return update(...) end
    module.Compile = function(...) compiles = compiles + 1; return compile(...) end
    itemReads = 0
    for _ = 1, 10 do
        eventFrame.OnEvent(eventFrame, "UNIT_AURA", "party1")
        eventFrame.OnEvent(eventFrame, "UNIT_FLAGS", "party2")
        eventFrame.OnEvent(eventFrame, "UNIT_AURA", "party2")
    end
    assert(updates == 0 and #afterQueue == 1, "member events did immediate work or queued more than one pass")
    memberAuras.party1 = true
    assert(RunAfter() == 1 and updates == 1 and itemReads == 0,
        "the coalesced member pass did not update once without item counts")
    assert(module.entries[1].group and module.entries[1].missingCount == 0,
        "the member pass did not refresh the marked unit")
    -- The player's own aura delta refreshes the player's group state inside
    -- its personal update: no member pass follows it.
    updates = 0
    memberAuras.player = false
    eventFrame.OnEvent(eventFrame, "UNIT_AURA", "player", { isFullUpdate = true })
    assert(updates == 1 and #afterQueue == 0 and module.entries[1].missingCount == 1,
        "the player's aura update queued a second group pass or missed the player's group state")
    memberAuras.player = true
    eventFrame.OnEvent(eventFrame, "UNIT_AURA", "player", { isFullUpdate = true })
    assert(updates == 2 and #afterQueue == 0 and module.entries[1].missingCount == 0,
        "the player's own aura did not refresh the group reminder at once")
    -- A roster storm compiles once and relists the member units.
    roster.party3, members = "WARLOCK", 3
    for _ = 1, 20 do eventFrame.OnEvent(eventFrame, "GROUP_ROSTER_UPDATE") end
    assert(compiles == 0 and #afterQueue == 1, "roster events compiled immediately")
    RunAfter()
    list = eventFrame.events.UNIT_AURA
    assert(compiles == 1 and #list == 4 and list[4] == "party3", "the roster pass did not relist the member units")
    -- Entering combat drops a pending pass with its marks.
    eventFrame.OnEvent(eventFrame, "UNIT_AURA", "party1")
    eventFrame.OnEvent(eventFrame, "PLAYER_REGEN_DISABLED")
    combat = true
    updates = 0
    RunAfter()
    assert(updates == 0 and not next(module.groupDirty), "a member pass ran in combat")
    combat = false
    eventFrame.OnEvent(eventFrame, "PLAYER_REGEN_ENABLED")
    -- Group options that need the roster alone (other classes' buffs, a
    -- Warlock's Healthstone) leave the member events alone: UNIT_AURA follows
    -- the player only, and roster changes still recompile.
    module.config.groupBuff, module.config.otherClassBuffs, module.config.healthstoneFromWarlock = false, true, true
    module:Refresh()
    RunAfter()
    assert(eventFrame.events.UNIT_AURA == "player" and eventFrame.events.GROUP_ROSTER_UPDATE,
        "roster-only group options followed the members' auras or stopped following the roster")
    for _, event in ipairs({ "UNIT_CONNECTION", "UNIT_FLAGS", "UNIT_PHASE" }) do
        assert(not eventFrame.events[event], event .. " followed the members without an option reading their auras")
    end
    for _, key in ipairs({ "groupBuff", "soulstoneOnAlly", "beaconOnAlly" }) do
        module.config.otherClassBuffs, module.config.healthstoneFromWarlock = false, false
        module.config.groupBuff, module.config.soulstoneOnAlly, module.config.beaconOnAlly = false, false, false
        module.config[key] = true
        module:Refresh()
        RunAfter()
        list = eventFrame.events.UNIT_AURA
        assert(type(list) == "table" and #list == 4 and eventFrame.events.UNIT_PHASE == list,
            key .. " does not follow the members' aura events")
    end
    module.config.soulstoneOnAlly, module.config.beaconOnAlly, module.config.groupBuff = false, false, true
    module:Refresh()
    RunAfter()
    module.Update, module.Compile = update, compile
    module:Disable()
    assert(not eventFrame.events.UNIT_AURA and not eventFrame.events.GROUP_ROSTER_UPDATE,
        "disable kept member events")
end

-- With the group option on, the class buff entry counts the members; the
-- advance warning (remindBeforeMinutes) still follows the player's own copy.
do
    local roster = { player = "MAGE", party1 = "PRIEST" }
    UnitClass = function(unit) return roster[unit], roster[unit] end
    knownSpell = function(id) return id == 1459 end
    IsInRaid = function() return false end
    GetNumSubgroupMembers = function() return 1 end
    UnitIsUnit = function(unit, other) return unit == other end
    UnitExists = function(unit) return roster[unit] ~= nil end
    UnitIsConnected = function() return true end
    UnitIsVisible = function() return true end
    UnitIsDeadOrGhost = function() return false end
    C_Secrets.ShouldAurasBeSecret = function() return false end
    C_UnitAuras.GetUnitAuraBySpellID = function() return {} end
    NS.Client.isForever, NS.Client.modernEquipment = false, false
    afterQueue, scheduled = {}, {}
    now = 5000
    auras[1459] = { spellId = 1459, auraInstanceID = 950, expirationTime = now + 120, duration = 3600 }
    module.config = { classBuff=true, groupBuff=true, spellIDs="", items="", mainHandItem="", offHandItem="",
        instancesOnly=false, hideMounted=true, size=38, spacing=5, columns=6, borderColor="e8b855",
        point=1, x=0, y=0, remindBeforeMinutes=5 }
    module.active = true
    module:Enable()
    RunAfter()
    local entry = module.entries[1]
    assert(entry and entry.group and entry.present == true and entry.missingCount == 0,
        "the group buff entry did not see every member buffed")
    assert(module.mask % (entry.bit * 2) >= entry.bit and entry.expiresAt == now + 120,
        "the group buff ignored the advance warning of the player's own buff")
    auras[1459] = { spellId = 1459, auraInstanceID = 950, expirationTime = now + 1800, duration = 3600 }
    eventFrame.OnEvent(eventFrame, "UNIT_AURA", "player", { updatedAuraInstanceIDs = { 950 } })
    assert(module.mask == 0 and module.thresholdAt == now + 1500,
        "a refreshed own buff did not move the group buff's advance warning")
    now = now + 1500
    FireNext()
    assert(module.mask % (entry.bit * 2) >= entry.bit, "the group buff's advance warning did not fire")
    module.config.classBuff = false
    module:Refresh()
    RunAfter()
    assert(module.mask == 0 and module.entries[1].expiresAt == nil,
        "without the class buff option the player's own buff still warned")
    module:Disable()
    auras[1459] = nil
end

-- Retail and WoW Forever always have the APIs the module calls (GameTooltip
-- included). The seasonal ID tables live only in Data.lua; every runtime file
-- reads P.BuffReminders in its header.
for i = 2, #BR_FILES do
    local name = BR_FILES[i]
    local file = assert(io.open(root .. "/MSUF_Suite_BuffReminders/" .. name, "rb"))
    local source = file:read("*a"):gsub("\r", "")
    file:close()
    local code = source:gsub("%-%-[^\n]*", "")
    -- Restricted aura lookups return nothing instead of raising: no file
    -- needs a protected call.
    assert(not code:find("pcall", 1, true), name .. " uses pcall or xpcall")
    local guarded = code:match("type%(([^)]*)%)%s*[~=]=%s*\"function\"") or code:match("(_G%.GameTooltip)")
    assert(not guarded or name == "Preparation.lua", name .. " guards " .. tostring(guarded) .. " as if a client lacked it")
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

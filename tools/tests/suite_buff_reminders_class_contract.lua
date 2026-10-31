-- Buff reminders: class reminders and the reminder comfort options. The
-- catalog list (NS.BuffReminderClassReminders) against the module: the master
-- switch, known-spell gating, every aura, imbue and ally reminder appearing
-- while missing and clearing once present, WoW Forever's smaller set, "Hide
-- while resting", "dismiss until reload" on the secure button, the longer
-- sound list and the menu preview. arg 2 names a mutation: the test loads the
-- module with one piece of the change taken out and must then fail.
local root = assert(arg[1], "repository root required")
local mutation = arg[2]
local Support = dofile(root .. "/tools/tests/suite_test_support.lua")
local function eq(a, b, label) assert(a == b, label .. ": " .. tostring(a) .. " ~= " .. tostring(b)) end

local MUTATIONS = {
    known = { "Entries.lua", "return FirstKnown(plan.casts)", "return plan.casts[1]" },
    master = { "Entries.lua", "if c.classReminders == true and class then", "if class then" },
    forever = { "Data.lua", "if P.NS.Client.isForever then return def.forever end", "" },
    imbue = { "Entries.lua", "Known(rule.spell) and SlotHolds(rule.slot, rule.equip)", "Known(rule.spell)" },
    ally = { "Group.lua", "entry.allyMissing = not alone and OwnMissing(", "entry.allyMissing = false and OwnMissing(" },
    allyPlayer = { "Group.lua", "if ally and unit == \"player\" then return false end", "" },
    allySpell = { "Group.lua", "if Listed(aliases, spellID) then return true end", "if true then return true end" },
    resting = { "Preparation.lua", "or Public(resting) and resting == true", "or false" },
    dismiss = { "Controller.lua", " and not (entry and entry.dismissed)", "" },
    secure = { "Alerts.lua", "    entry.dismissed = true\n", "    entry.dismissed = true\n    button:SetAttribute(\"type1\", nil)\n" },
    sounds = { "Alerts.lua", "\"MAP_PING\",", "" },
}
local originalLoad = loadfile
if mutation then
    local change = assert(MUTATIONS[mutation], "unknown mutation " .. mutation)
    loadfile = function(path)
        if not path:find("MSUF_Suite_BuffReminders/" .. change[1], 1, true) then return originalLoad(path) end
        local file = assert(io.open(path, "rb"))
        local source = file:read("*a")
        file:close()
        local first, last = source:find(change[2], 1, true)
        assert(first, "the mutation anchor moved")
        return assert(loadstring(source:sub(1, first - 1) .. change[3] .. source:sub(last + 1), "@" .. path))
    end
end

local function Widget()
    local w = { shown = false, attributes = {} }
    function w:SetScript(name, callback) self[name] = callback end
    function w:SetAttribute(key, value) self.attributes[key] = value end
    function w:RegisterForClicks(...) self.clicks = { ... } end
    function w:CreateTexture() return Widget() end
    function w:CreateFontString() return Widget() end
    function w:SetShown(value) self.shown = value end
    function w:Show() self.shown = true end
    function w:Hide() self.shown = false end
    function w:SetText(value) self.text = value end
    function w:SetTexture(value) self.texture = value end
    function w:SetDesaturated() end
    function w:SetAlpha() end
    function w:CreateAnimationGroup()
        local group = {}
        function group:SetLooping() end
        function group:Play() end
        function group:Stop() end
        function group:CreateAnimation()
            return { SetFromAlpha = function() end, SetToAlpha = function() end, SetDuration = function() end }
        end
        return group
    end
    for _, name in ipairs({ "SetTexCoord", "SetColorTexture", "SetVertexColor", "SetDrawLayer", "SetAllPoints",
        "SetPoint", "ClearAllPoints", "SetSize", "SetFrameLevel", "SetTextColor", "SetWidth", "SetHeight" }) do
        w[name] = function() end
    end
    function w:GetFrameLevel() return 1 end
    return w
end
UIParent = Widget()
CreateFrame = function() return Widget() end
RegisterStateDriver, UnregisterStateDriver = function() end, function() end
GameTooltip = Widget()
function GameTooltip:SetOwner(owner) self.owner, self.lines = owner, {} end
function GameTooltip:IsOwned(frame) return self.owner == frame end
function GameTooltip:SetSpellByID(id) self.spell = id end
function GameTooltip:SetItemByID(id) self.item = id end
function GameTooltip:AddLine(text) self.lines[#self.lines + 1] = text end

-- The game state the module reads.
local class, specID, resting, combat = "PRIEST", 258, false, false
local known, playerAuras, enchants, equipment = {}, {}, {}, {}
local roster, memberAuras, restingReads = {}, {}, 0
local WEAPON, SHIELD = 900001, 900003
Enum = { SpellBookSpellBank = { Player = 0, Pet = 1 }, PowerType = { Mana = 0 },
    ItemClass = { Consumable = 0 }, ItemConsumableSubclass = { Fooddrink = 5 } }
Constants = { InventoryConstants = { NumBagSlots = 4 } }
DifficultyUtil = { ID = { DungeonTimewalker = 24, RaidTimewalker = 33 } }
C_SpellBook = {
    IsSpellKnown = function(id) return known[id] == true end,
    IsSpellInSpellBook = function() return false end,
}
-- Earth Shield on the shaman (Elemental Orbit, 383648) shares the name of the
-- ally spell 974.
local SPELL_NAMES = { [383648] = "Earth Shield", [974] = "Earth Shield" }
C_Spell = { GetSpellName = function(id) return SPELL_NAMES[id] or "Spell " .. id end, GetSpellTexture = function(id) return id end }
C_SpecializationInfo = { GetSpecialization = function() return 1 end, GetSpecializationInfo = function() return specID end }
C_Container = { GetContainerNumSlots = function() return 0 end, GetContainerItemID = function() end }
C_Item = {
    GetItemCount = function() return 0 end,
    GetItemIconByID = function(id) return id end,
    GetItemInfoInstant = function(id)
        if id == SHIELD then return id, "Armor", "Shield", "INVTYPE_SHIELD", 0, 4, 6 end
        return id, "Weapon", "Sword", "INVTYPE_WEAPON", 0, 2, 0
    end,
}
C_PaperDollInfo = { GetTemporaryEnchantmentInfo = function(slot) return enchants[slot] end }
C_Secrets = { ShouldAurasBeSecret = function() return false end }
C_UnitAuras = {
    GetPlayerAuraBySpellID = function(id) return playerAuras[id] end,
    -- The ally reminders ask for the player's own aura on a member by name;
    -- memberAuras[unit] is the spell ID of that aura.
    GetAuraDataBySpellName = function(unit, name, filter)
        assert(filter == "HELPFUL|PLAYER", "an ally reminder must ask for the player's own aura")
        local id = memberAuras[unit]
        if id and C_Spell.GetSpellName(id) == name then return { spellId = id } end
    end,
}
local after = {}
C_Timer = { After = function(_, callback) after[#after + 1] = callback end }
local function RunAfter()
    local queued = after
    after = {}
    for _, callback in ipairs(queued) do callback() end
    return #queued
end
GetTime = function() return 100 end
UnitClass = function(unit)
    if unit == "player" then return class, class end
    return roster[unit], roster[unit]
end
UnitIsUnit = function(unit, other) return unit == other end
UnitExists = function(unit) return unit == "player" or roster[unit] ~= nil end
UnitIsConnected, UnitIsVisible = function() return true end, function() return true end
UnitIsDeadOrGhost, UnitInVehicle, IsMounted = function() return false end, function() return false end, function() return false end
IsResting = function() restingReads = restingReads + 1; return resting end
IsInRaid = function() return false end
GetNumSubgroupMembers = function()
    local count = 0
    for _ in pairs(roster) do count = count + 1 end
    return count
end
GetInventoryItemID = function(_, slot) return equipment[slot] end
GetInstanceInfo = function() return "World", "none" end
GetDifficultyInfo = function() end
local played = {}
SOUNDKIT = { RAID_WARNING = 8959, READY_CHECK = 8960, IG_QUEST_LOG_OPEN = 844, ALARM_CLOCK_WARNING_3 = 12889,
    MAP_PING = 3175, TELL_MESSAGE = 3081 }
PlaySound = function(kit, channel) played[#played + 1] = { kit = kit, channel = channel } end

local S = {
    Public = function(value) return not (type(value) == "table" and value.secret) end,
    Install = function(_, module) _G.classModule = module end,
    Text = function(value) return value end,
    CreateFrame = function(...) return CreateFrame(...) end,
    CreateTexture = function(parent, ...) return parent:CreateTexture(...) end,
    CreateFontString = function(parent, ...) return parent:CreateFontString(...) end,
    RGB = function() return 1, 1, 1 end,
    SetFont = function() end, ResolveFont = function(value) return value end,
    RegisterOwnedMover = function() end, editMode = false,
}
local config, catalogNS = Support.CatalogDefaults(root, "buffReminders")
local NS = { IsCombatLocked = function() return combat end,
    Client = { isForever = false, modernEquipment = true, SupportsEvent = function() return true end },
    AnchorPoints = { "TOPLEFT", "TOP", "TOPRIGHT", "LEFT", "CENTER", "RIGHT", "BOTTOMLEFT", "BOTTOM", "BOTTOMRIGHT" },
    BuffReminderClassReminders = catalogNS.BuffReminderClassReminders }
catalogNS.Defaults = {}
catalogNS.FinalizeCatalog()
NS.Defaults, NS.IconShapeIds = catalogNS.Defaults, catalogNS.IconShapeIds
assert(loadfile(root .. "/MSUF_Suite/Core/HostBridge.lua"))("MSUF_Suite", NS)
NS.Dispatch = function(callback, ...) return callback(...) end
local private = { NS = NS, Suite = S }
Support.Load(root, "MSUF_Suite_BuffReminders", private, nil, { ["Bootstrap.lua"] = true })
local R = private.BuffReminders
local module = assert(classModule)
local DEFS = NS.BuffReminderClassReminders

-- The catalog: a master switch that is off, one switch per reminder that is
-- on and follows it, the resting option and the longer sound list.
do
    local rules = catalogNS.SuiteCatalog.buffReminders.rules
    eq(rules.classReminders.default, false, "the class reminders start switched on")
    eq(rules.hideResting.default, false, "Hide while resting starts switched on")
    eq(#rules.reminderSound.choices, 7, "the sound list did not grow")
    eq(rules.reminderSound.choices[4], "Quest log", "an old sound moved")
    for _, def in ipairs(DEFS) do
        local rule = assert(rules[def.key], def.key .. " has no catalog rule")
        assert(rule.default == true and rule.enableKey == "classReminders" and rule.hidden == nil,
            def.key .. " is not an on-by-default switch under the master switch")
        assert(def.retail and (def.forever == nil or def.forever.kind == "aura"), def.key .. " has a Forever plan of another kind")
    end
    -- Forever hides the reminders it lacks.
    local _, foreverNS = Support.CatalogDefaults(root, "buffReminders", nil, { isForever = true })
    local foreverRules = foreverNS.SuiteCatalog.buffReminders.rules
    local shown = 0
    for _, def in ipairs(foreverNS.BuffReminderClassReminders) do
        eq(foreverRules[def.key].hidden, def.forever == nil or nil, def.key .. " Forever visibility")
        if def.forever then shown = shown + 1 end
    end
    eq(shown, 2, "Forever keeps more or fewer than Shadowform and the stances")
end

local function Owner(overrides)
    local owner = R.NewState({ config = {} })
    for key, value in pairs(config) do owner.config[key] = value end
    owner.config.classBuff, owner.config.autoRoguePoisons = false, false
    owner.config.autoFlask, owner.config.autoFood, owner.config.autoRune, owner.config.autoWeapon = false, false, false, false
    for key, value in pairs(overrides or {}) do owner.config[key] = value end
    return owner
end
local function Set(...)
    known = {}
    for _, id in ipairs({ ... }) do known[id] = true end
end
local function Ids(list)
    local ids = {}
    for index, entry in ipairs(list) do ids[index] = entry.id .. (entry.slot and "@" .. entry.slot or "") end
    return table.concat(ids, ",")
end
local function ForeverPlan(key)
    for _, def in ipairs(DEFS) do
        if def.key == key then return def.forever end
    end
end
local function Reset(spec, items)
    class, specID, equipment, roster, memberAuras = spec[1], spec[2], items or {}, {}, {}
    playerAuras, enchants, resting, combat = {}, {}, false, false
    NS.Client.isForever, NS.Client.modernEquipment = false, true
end

-- The master switch gates everything; each reminder needs its spell and its
-- own switch.
do
    local all = {}
    for _, def in ipairs(DEFS) do
        for _, id in ipairs(def.retail.casts or {}) do all[#all + 1] = id end
        for _, rule in ipairs(def.retail.imbues or {}) do all[#all + 1] = rule.spell end
    end
    for _, spec in ipairs({ { "PRIEST", 258 }, { "PALADIN", 70 }, { "WARRIOR", 73 }, { "SHAMAN", 264 },
        { "EVOKER", 1473 }, { "DRUID", 105 }, { "MAGE", 62 } }) do
        Reset(spec, { [16] = WEAPON, [17] = SHIELD })
        Set(unpack(all))
        eq(#R.BuildEntries(Owner({ classReminders = false })), 0, spec[1] .. " got a reminder with the master switch off")
        assert(#R.BuildEntries(Owner({ classReminders = true })) > 0, spec[1] .. " got no reminder with the master switch on")
    end
    Reset({ "PRIEST", 258 })
    Set()
    eq(#R.BuildEntries(Owner({ classReminders = true })), 0, "a spell the character does not know became a reminder")
    Set(232698)
    local entries = R.BuildEntries(Owner({ classReminders = true }))
    eq(Ids(entries), "232698", "Shadowform")
    assert(entries[1].category == "class" and entries[1].aura == 232698 and entries[1].aliases[2] == 194249,
        "Shadowform is not a class reminder satisfied by Voidform too")
    eq(#R.BuildEntries(Owner({ classReminders = true, classShadowform = false })), 0, "a reminder ignored its switch")
    Reset({ "WARRIOR", 73 })
    Set(386164, 386208, 386196)
    local stance = R.BuildEntries(Owner({ classReminders = true }))
    eq(Ids(stance), "386208", "a protection warrior is not asked for Defensive Stance")
    specID = 72
    eq(Ids(R.BuildEntries(Owner({ classReminders = true }))), "386196", "a fury warrior is not asked for Berserker Stance")
    specID = 71
    eq(Ids(R.BuildEntries(Owner({ classReminders = true }))), "386164", "an arms warrior is not asked for Battle Stance")
    Set(386196)
    eq(Ids(R.BuildEntries(Owner({ classReminders = true }))), "386196", "the stance fell back to a spell the character lacks")
end

-- Shows the module with a configuration; returns the shown spell and slot list.
local events, units = {}, {}
local context = {}
function context:Event(event, callback, _, unit) events[event], units[event] = callback, unit end
function context:RemoveEvent(event) events[event], units[event] = nil, nil end
module.context = Support.ModuleTimers(root, S, NS)("buffReminders", module, context)
module.active = true
local function Fire(event, ...) events[event](module, event, ...) end
local function Start(overrides)
    module.config = Owner(overrides).config
    module:Enable()
end
local function Shown()
    local shown = {}
    for _, button in ipairs(module.view.buttons) do
        if button.shown then shown[#shown + 1] = button.entry.id .. (button.entry.slot and "@" .. button.entry.slot or "") end
    end
    return table.concat(shown, ",")
end

-- Every aura reminder shows while its aura is missing and clears once present.
for _, def in ipairs(DEFS) do
    local plan = def.retail
    if plan.kind == "aura" then
        local spec = { def.class, def.class == "WARRIOR" and 71 or 62 }
        Reset(spec)
        Set(unpack(plan.casts))
        Start({ classReminders = true })
        local cast = plan.casts[1]
        eq(Shown(), tostring(cast), def.key .. " did not show while its aura is missing")
        eq(module.view.buttons[1].attributes.spell1, cast, def.key .. " casts another spell")
        eq(module.view.buttons[1].attributes.unit, "player", def.key .. " does not cast on the player")
        playerAuras[plan.auras[#plan.auras]] = {}
        Fire("UNIT_AURA", "player")
        eq(Shown(), "", def.key .. " stayed after its aura came up")
        playerAuras = {}
        Fire("UNIT_AURA", "player", { isFullUpdate = true })
        eq(Shown(), tostring(cast), def.key .. " did not return when its aura ended")
        module:Disable()
    end
end

-- Weapon and shield imbues read the slot's temporary enchant, per specialization.
do
    local function Imbues(spec, items, ...)
        Reset(spec, items)
        Set(...)
        return Ids(R.BuildEntries(Owner({ classReminders = true })))
    end
    eq(Imbues({ "SHAMAN", 263 }, { [16] = WEAPON, [17] = WEAPON }, 33757, 318038), "33757@16,318038@17", "Enhancement")
    eq(Imbues({ "SHAMAN", 263 }, { [16] = WEAPON, [17] = SHIELD }, 33757, 318038, 462757), "33757@16,462757@17", "Enhancement, shield")
    eq(Imbues({ "SHAMAN", 262 }, { [16] = WEAPON, [17] = SHIELD }, 318038, 462757, 33757), "318038@16,462757@17", "Elemental")
    eq(Imbues({ "SHAMAN", 262 }, { [16] = WEAPON, [17] = WEAPON }, 318038, 462757), "318038@16", "Elemental, no shield")
    eq(Imbues({ "SHAMAN", 264 }, { [16] = WEAPON, [17] = SHIELD }, 382021, 457481, 318038), "382021@16,457481@17", "Restoration")
    eq(Imbues({ "SHAMAN", 264 }, {}, 382021), "", "an unarmed shaman is asked for an imbue")
    eq(Imbues({ "PALADIN", 65 }, { [16] = WEAPON }, 433583), "433583@16", "Rite of Adjuration")
    eq(Imbues({ "PALADIN", 66 }, { [16] = WEAPON }, 433568), "433568@16", "Rite of Sanctification")
    eq(Imbues({ "PALADIN", 66 }, { [16] = WEAPON }), "", "a rite the paladin lacks")
    Reset({ "SHAMAN", 263 }, { [16] = WEAPON, [17] = WEAPON })
    Set(33757, 318038)
    Start({ classReminders = true })
    eq(Shown(), "33757@16,318038@17", "missing imbues did not show")
    local main = module.view.buttons[1]
    eq(main.attributes.type1, "spell", "an imbue reminder is not a cast")
    eq(main.attributes["target-slot"], 16, "an imbue reminder lost its weapon slot")
    enchants[16] = {}
    Fire("WEAPON_ENCHANT_CHANGED")
    eq(Shown(), "318038@17", "an imbued main hand still showed")
    enchants[17] = {}
    Fire("WEAPON_ENCHANT_CHANGED")
    eq(Shown(), "", "both imbues present still showed")
    enchants = {}
    Fire("WEAPON_ENCHANT_CHANGED")
    eq(Shown(), "33757@16,318038@17", "a lost imbue did not return")
    module:Disable()
end

-- Ally reminders: the player's own aura on any group member, read through the
-- group pass; alone in the group there is nobody to buff.
do
    Reset({ "EVOKER", 1473 })
    Set(369459)
    Start({ classReminders = true })
    eq(Shown(), "", "an ally reminder showed with nobody to buff")
    assert(events.GROUP_ROSTER_UPDATE and units.UNIT_AURA, "the ally reminder does not follow the group")
    roster.party1 = "MAGE"
    Fire("GROUP_ROSTER_UPDATE")
    RunAfter()
    eq(Shown(), "369459", "a buff on nobody did not show")
    memberAuras.player = 369459
    Fire("UNIT_AURA", "player")
    eq(Shown(), "369459", "the player's own copy counted as a buff on an ally")
    memberAuras.player = nil
    Fire("UNIT_AURA", "player")
    eq(type(units.UNIT_AURA), "table", "member auras are not followed")
    local button = module.view.buttons[1]
    eq(button.attributes.type1, "spell", "the ally reminder is not a cast")
    eq(button.attributes.unit, "target", "the ally reminder does not cast on the target")
    memberAuras.party1 = 369459
    Fire("UNIT_AURA", "party1")
    eq(RunAfter(), 1, "the member pass was not coalesced")
    eq(Shown(), "", "the buff on a member still showed")
    memberAuras.party1 = nil
    Fire("UNIT_AURA", "party1")
    RunAfter()
    eq(Shown(), "369459", "the lost buff did not return")
    module:Disable()
    assert(not events.GROUP_ROSTER_UPDATE and not events.UNIT_AURA, "disable kept the group events")
    -- No known spell, no roster or member events.
    Set()
    Start({ classReminders = true })
    assert(not events.GROUP_ROSTER_UPDATE and units.UNIT_AURA == nil, "a spell the character lacks followed the group")
    module:Disable()
    -- Earth Shield belongs to Restoration.
    Reset({ "SHAMAN", 262 })
    Set(974)
    Start({ classReminders = true })
    assert(not events.GROUP_ROSTER_UPDATE and #module.list.entries == 0, "Earth Shield reached an Elemental shaman")
    module:Disable()
    Reset({ "SHAMAN", 264 })
    Set(974)
    roster.party1 = "PRIEST"
    Start({ classReminders = true })
    eq(Shown(), "974", "Earth Shield on nobody did not show for Restoration")
    -- Only an ally counts: Earth Shield on the shaman, Elemental Orbit's
    -- 383648 (the ally spell's name) or 974 cast on themselves, leaves the
    -- reminder up, and so does another spell of that name on a member.
    for _, id in ipairs({ 383648, 974 }) do
        memberAuras.player = id
        Fire("UNIT_AURA", "player")
        eq(Shown(), "974", "Earth Shield " .. id .. " on the shaman counted as on an ally")
    end
    memberAuras.party1 = 383648
    Fire("UNIT_AURA", "party1")
    RunAfter()
    eq(Shown(), "974", "another spell named Earth Shield counted as Earth Shield on an ally")
    memberAuras.party1 = 974
    Fire("UNIT_AURA", "party1")
    RunAfter()
    eq(Shown(), "", "Earth Shield on an ally still showed")
    module:Disable()
end

-- Hide while resting is read in the environment pass; the resting event is
-- followed only while the option is on.
do
    Reset({ "PRIEST", 258 })
    Set(232698)
    resting, restingReads = true, 0
    Start({ classReminders = true })
    eq(Shown(), "232698", "resting hid a reminder with the option off")
    eq(restingReads, 0, "the resting state was read without the option")
    assert(events.PLAYER_UPDATE_RESTING == nil, "the resting event was followed without the option")
    module.config.hideResting = true
    module:Refresh()
    eq(Shown(), "", "a resting player still saw a reminder")
    assert(events.PLAYER_UPDATE_RESTING, "the resting event is not followed")
    resting = false
    Fire("PLAYER_UPDATE_RESTING")
    eq(Shown(), "232698", "leaving a rest area did not bring the reminder back")
    resting = true
    Fire("PLAYER_UPDATE_RESTING")
    eq(Shown(), "", "entering a rest area did not hide the reminder")
    module.config.hideResting = false
    module:Refresh()
    eq(Shown(), "232698", "switching the option off kept the reminder hidden")
    assert(events.PLAYER_UPDATE_RESTING == nil, "switching the option off kept the resting event")
    module:Disable()
end

-- Dismiss until reload: a right or middle click hides a reminder and leaves
-- its secure attributes alone; the left click stays the cast.
do
    Reset({ "PRIEST", 258 })
    Set(232698)
    Start({ classReminders = true, spellIDs = "777" })
    eq(Shown(), "232698,777", "fixture")
    local button = module.view.buttons[1]
    local clicks = table.concat(button.clicks, ",")
    for _, click in ipairs({ "LeftButtonDown", "LeftButtonUp", "RightButtonUp", "MiddleButtonUp" }) do
        assert(clicks:find(click, 1, true), "the button does not register " .. click)
    end
    local function Snapshot(frame)
        local keys = {}
        for key, value in pairs(frame.attributes) do keys[#keys + 1] = key .. "=" .. tostring(value) end
        table.sort(keys)
        return table.concat(keys, ";")
    end
    local before = Snapshot(button)
    eq(button.attributes.type1, "spell", "the left click is not the cast")
    for _, key in ipairs({ "type", "type2", "type3", "*type2", "*type3", "spell2", "spell3", "macrotext" }) do
        eq(button.attributes[key], nil, "the button has an action on " .. key)
    end
    button.PostClick(button, "LeftButton", true)
    button.PostClick(button, "LeftButton", false)
    eq(Shown(), "232698,777", "a left click dismissed the reminder")
    combat = true
    button.PostClick(button, "RightButton", false)
    combat = false
    eq(Shown(), "232698,777", "a click in combat dismissed the reminder")
    S.editMode = true
    button.PostClick(button, "RightButton", false)
    S.editMode = false
    eq(Shown(), "232698,777", "a click in Edit Mode dismissed the reminder")
    button.PostClick(button, "RightButton", false)
    eq(Shown(), "777", "a right click did not dismiss the reminder")
    eq(Snapshot(button), before, "dismissing changed the secure attributes")
    -- It lasts: the aura coming and going, a recompile and the other reminder's changes.
    playerAuras[232698] = {}
    Fire("UNIT_AURA", "player")
    playerAuras = {}
    Fire("UNIT_AURA", "player", { isFullUpdate = true })
    eq(Shown(), "777", "the dismissed reminder returned with its aura loss")
    module.config.spellIDs = "777,778"
    module:Refresh()
    eq(Shown(), "777,778", "a recompile forgot the dismissed reminder")
    module.view.buttons[2].PostClick(module.view.buttons[2], "MiddleButton", false)
    eq(Shown(), "778", "a middle click did not dismiss the reminder")
    eq(module.view.buttons[2].attributes.type1, "spell", "the middle click changed the cast")
    module:Disable()
    module:Enable()
    eq(Shown(), "232698,777,778", "turning the module off and on did not bring the reminders back")
    module:Disable()
end

-- WoW Forever keeps Shadowform and the warrior stances, with its own spells.
do
    Reset({ "PRIEST", 258 })
    NS.Client.isForever, NS.Client.modernEquipment = true, false
    Set(15473, 232698)
    local entries = R.BuildEntries(Owner({ classReminders = true }))
    eq(Ids(entries), "15473", "Forever Shadowform")
    eq(entries[1].aliases[1], 15473, "Forever Shadowform aura")
    Reset({ "WARRIOR", 71 })
    NS.Client.isForever, NS.Client.modernEquipment = true, false
    Set(2457, 71, 2458, 386164)
    eq(Ids(R.BuildEntries(Owner({ classReminders = true }))), "2457", "Forever stance")
    for _, case in ipairs({ { "PALADIN", 465, 433583 }, { "SHAMAN", 192106, 33757 }, { "EVOKER", 369459, 360827 },
        { "DRUID", 474750 }, { "MAGE", 205022 } }) do
        Reset({ case[1], 1 }, { [16] = WEAPON, [17] = SHIELD })
        NS.Client.isForever, NS.Client.modernEquipment = true, false
        Set(unpack(case, 2))
        local owner = Owner({ classReminders = true })
        eq(#R.BuildEntries(owner), 0, case[1] .. " got a Retail reminder on Forever")
        eq(R.WantsAllies(owner), false, case[1] .. " reads member auras on Forever")
    end
    eq(ForeverPlan("classPaladinAura"), nil, "Forever has a Paladin aura plan")
    assert(ForeverPlan("classShadowform"), "Forever lost Shadowform")
    Reset({ "PRIEST", 258 })
end

-- The longer sound list: the old four keep their place.
do
    Reset({ "PRIEST", 258 })
    Set(232698)
    for choice, kit in pairs({ [2] = 8959, [3] = 8960, [4] = 844, [5] = 12889, [6] = 3175, [7] = 3081 }) do
        played = {}
        Start({ classReminders = true, reminderSound = choice, reminderSoundChannel = 2 })
        eq(played[1] and played[1].kit, kit, "sound choice " .. choice)
        eq(played[1] and played[1].channel, "SFX", "sound channel")
        module:Disable()
    end
end

-- The menu preview shows the class reminders: the character's own, and a
-- sample class's.
do
    Reset({ "PRIEST", 258 })
    Set(232698)
    local stage, open = Widget(), function() end
    local sample = { "PRIEST", 5, 21562, 10060, 17, 135940 }
    local preview = Owner({ classReminders = true })
    local _, _, own = S.BuffRemindersDrawPreview(stage, preview.config, true, open)
    eq(own, 1, "the character's preview misses its class reminder")
    local _, _, withSample = S.BuffRemindersDrawPreview(stage, preview.config, false, open, sample)
    eq(withSample, 4, "the class sample misses the class reminders")
    eq(stage.buffReminderPreview.view.buttons[4].entry.id, 232698, "the sample's class reminder icon")
    preview.config.classShadowform = false
    eq(select(3, S.BuffRemindersDrawPreview(stage, preview.config, false, open, sample)), 3, "the sample ignored a switch")
    preview.config.classShadowform = true
    preview.config.classReminders = false
    eq(select(3, S.BuffRemindersDrawPreview(stage, preview.config, false, open, sample)), 3, "the sample ignored the master switch")
    eq(select(3, S.BuffRemindersDrawPreview(stage, preview.config, false, open)), 0, "the preview showed a reminder with the master switch off")
end

print("Suite buff reminders class: " .. (mutation and ("mutation " .. mutation .. " survived") or
    "catalog, spell gating, aura, imbue and ally reminders, resting, dismiss, Forever, sounds and preview passed"))

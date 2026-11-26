local root = assert(arg[1])
local fixture = assert(loadfile(root .. "/tools/tests/suite_buff_reminders_contract.lua"))()
local NS, S = fixture.namespace.NS, fixture.namespace.Suite
local module, Fire = fixture.module, fixture.fire
local starting, combat, blocked, keyDown, restricted, raid, resting = false, false, false, false, false, false, false
local class, cast, nearby
local spellReads, auraReads, rangeReads, driverWrites, throws = 0, 0, 0, 0, 0
local member, range, phase = {}, {}, {}
local secret = { secret = true }
local registerDriver = RegisterStateDriver

local function Read(table, unit)
    auraReads = auraReads + 1
    if table[unit] == true then return { spellId = 1459 } end
    if table[unit] == secret then return secret end
end

NS.IsCombatLocked = function() return combat end
NS.InCombat = function() return combat or starting end
SecureCmdOptionParse = function() return blocked and "blocked" or nil end
SecureActionButton_ShouldUseOnKeyDown = function(button)
    local value = button:GetAttribute("useOnKeyDown")
    if value ~= nil then return value end
    return keyDown
end
RegisterStateDriver = function(frame, state, condition)
    driverWrites = driverWrites + 1
    registerDriver(frame, state, condition)
end
C_Timer.NewTicker = function() error("group casting started a ticker") end
C_SpellBook.IsSpellKnown = function(id)
    spellReads = spellReads + 1
    return id == cast
end
C_Spell.IsSpellInRange = function(_, unit)
    rangeReads = rangeReads + 1
    return range[unit]
end
C_Secrets.ShouldAurasBeSecret = function() return restricted == true end
C_Secrets.ShouldSpellAuraBeSecret = function() return restricted == secret and secret or false end
C_UnitAuras.GetUnitAuraBySpellID = function(unit) return Read(member, unit) end
C_UnitAuras.GetPlayerAuraBySpellID = function() return Read(member, "player") end
C_UnitAuras.GetAuraDataBySpellName = function(unit) return Read(member, unit) end
GetInstanceInfo = function() return "World", "none" end
UnitClass = function(unit)
    if unit == "party3" then return "Rogue", "ROGUE" end
    return class, class
end
UnitExists = function(unit) return unit ~= "party4" end
UnitIsConnected = function() return true end
UnitIsVisible = function() return true end
UnitPhaseReason = function(unit) return phase[unit] end
UnitIsDeadOrGhost = function() return false end
UnitInVehicle = function() return false end
UnitCanAssist = function() return true end
UnitInRange = function(unit) return nearby == unit, true end
IsResting = function() return resting end
IsMounted = function() return false end
IsInRaid = function() return raid end
GetNumSubgroupMembers = function() return 4 end
GetNumGroupMembers = function() return 4 end
UnitIsUnit = function(unit, other) return (unit == "raid1" and "player" or unit) == other end
local distanceUnavailable, distanceSquared = false, 100
UnitDistanceSquared = function(unit)
    if not distanceUnavailable then return nearby == unit and distanceSquared or 20000, true end
end
CheckInteractDistance = function(unit, index)
    assert(index == 2)
    return nearby == unit and distanceSquared <= 100
end

local function Click(button, mouse, down)
    if button.PreClick then button:PreClick(mouse, down) end
    local spell, unit
    if not combat and mouse == "LeftButton" and down == SecureActionButton_ShouldUseOnKeyDown(button)
        and button:GetAttribute("type1") == "spell" then
        spell, unit = button:GetAttribute("spell1"), button:GetAttribute("unit")
        throws = throws + 1
    end
    if button.PostClick then button:PostClick(mouse, down) end
    return spell, unit
end

local function Start(forever)
    NS.Client.isForever, NS.Client.modernEquipment = forever, not forever
    module.active = true
    module.config = { castGroupBuffs = true, spellIDs = "", items = "", mainHandItem = "", offHandItem = "",
        size = 38, spacing = 5, columns = 6, borderColor = "e8b855", point = 1, x = 0, y = 0, remindBeforeMinutes = 0 }
    module:Enable()
end

local function Check(forever)
    assert(NS.Defaults.suite.modules.buffReminders.castGroupBuffs == false, "group buff casting must be opt-in")
    class, cast = "MAGE", forever and 10157 or 1459
    member, range, phase = { player = true, party1 = true }, { party1 = true, party2 = true, party3 = true }, {}
    local driversBefore = driverWrites
    Start(forever)
    local key = assert(module.view.selfBuffButton, "group option must enable the existing bind with reminders off")
    assert(key.name == "MSUFSuiteSelfBuff" and key.template == "InsecureActionButtonTemplate" and key.clicks[1] == "AnyUp")
    assert(driverWrites == driversBefore + 1 and not key.OnUpdate, "the group bind added background state work")
    assert(not fixture.events.UNIT_AURA and not fixture.events.GROUP_ROSTER_UPDATE, "the standalone bind added aura or roster listeners")
    assert(key:GetAttribute("type1") == nil, "the bind armed itself before a press")
    local spell = forever and C_Spell.GetSpellName(cast) or cast
    local function ExpectGroup(button, unit)
        local actualSpell, actualUnit = Click(button, "LeftButton", false)
        assert(actualSpell == spell and actualUnit == unit, "the click did not use the expected spell and missing group member")
        assert(not button:GetAttribute("type1"), "the button kept a group cast armed after a click")
    end
    ExpectGroup(key, "party2")
    member.party1, member.party2 = nil, true
    ExpectGroup(key, "party1")
    range.party1 = secret
    local _, target = Click(key, "LeftButton", false)
    assert(target == (not forever and "party3" or nil), "secret range or a non-mana class was selected")
    range.party1, member.party3 = true, true
    member.party1 = secret
    assert(not Click(key, "LeftButton", false), "an unreadable aura was treated as missing")
    member.party1 = nil
    phase.party1 = 1
    assert(not Click(key, "LeftButton", false), "a phased member was selected")
    phase.party1 = nil
    restricted = true
    if forever then
        assert(not Click(key, "LeftButton", false), "restricted ranked auras were used")
    else
        ExpectGroup(key, "party1")
        restricted = secret
        assert(not Click(key, "LeftButton", false), "a per-spell restriction was treated as absence")
    end
    restricted = false
    resting = true
    module.config.hideResting = true
    module:Refresh()
    assert(not module.view.allowed, "fixture did not hide the reminder")
    ExpectGroup(key, "party1")
    resting = false

    S.editMode, blocked = true, false
    assert(not Click(key, "LeftButton", false), "edit mode accepted a cast")
    S.editMode, blocked = false, true
    assert(not Click(key, "LeftButton", false), "a pet battle or vehicle key press accepted a cast")
    blocked = false
    local spellsBefore, aurasBefore, rangeBefore, throwsBefore = spellReads, auraReads, rangeReads, throws
    starting = true
    Fire("PLAYER_REGEN_DISABLED")
    assert(not Click(key, "LeftButton", false), "a press at combat start accepted a cast")
    combat, starting = true, false
    Fire("GROUP_ROSTER_UPDATE")
    Fire("UNIT_AURA", "party1")
    assert(not Click(key, "LeftButton", false), "a press in combat accepted a cast")
    assert(throws == throwsBefore and spellReads == spellsBefore and auraReads == aurasBefore and rangeReads == rangeBefore,
        "group casting read spells, auras, or range in combat")
    combat = false
    Fire("PLAYER_REGEN_ENABLED")
    ExpectGroup(key, "party1")

    module.config.groupBuff, module.config.classBuff = true, true
    module.config.raidBuffOverview, restricted = not forever, not forever
    module:Refresh()
    local icon = module.view.buttons[1]
    assert(icon.template == "InsecureActionButtonTemplate", "icon does not use the native out-of-combat action guard")
    assert(icon.shown, "missing group buff is not represented by a clickable icon")
    member.party1, member.party2 = true, nil
    Fire("GROUP_ROSTER_UPDATE")
    ExpectGroup(icon, "party2")
    keyDown = true
    local castAtStart = throws
    local actualSpell, actualUnit = Click(icon, "LeftButton", true)
    assert(actualSpell == spell and actualUnit == "party2", "click-down client setting lost group targeting")
    assert(not Click(icon, "LeftButton", false) and throws == castAtStart + 1, "one mouse click fired twice")
    ExpectGroup(key, "party2")
    keyDown = false
    fixture.runAfter()
    Click(icon, "RightButton", false)
    assert(not icon.shown, "right-click no longer dismisses group reminders")
    ExpectGroup(key, "party2")

    module.config.castGroupBuffs, module.config.groupBuff, module.config.raidBuffOverview = false, false, false
    restricted = false
    module:Refresh()
    assert(not Click(key, "LeftButton", false), "the opt-out left an active group cast")
    module:Disable()
    module.config.selfBuffKey = true
    member.player = nil
    module:Enable()
    local ownSpell, ownUnit = Click(key, "LeftButton", false)
    assert(ownSpell == spell and ownUnit == "player", "the opt-out changed the original self-buff bind")
    module:Disable()
    assert(not Click(key, "LeftButton", false), "a disabled module accepted a bound cast")
end

Check(false)
Check(true)

class, cast = "MAGE", 23028
member, nearby = { player = true, party1 = true }, "party2"
Start(true)
local variant, recipient = Click(module.view.selfBuffButton, "LeftButton", false)
assert(variant == C_Spell.GetSpellName(cast) and recipient == "player", "the raid-wide group rank must cast around the player")
module:Disable()

class, cast, raid, nearby = "WARRIOR", 6673, true, "raid3"
member = { player = true }
Start(true)
local key = module.view.selfBuffButton
local spell, unit = Click(key, "LeftButton", false)
assert(spell == C_Spell.GetSpellName(cast) and unit == "player", "Forever Battle Shout must cast from the player")
nearby = "raid2"
spell, unit = Click(key, "LeftButton", false)
assert(spell and unit == "player", "Forever Battle Shout missed a nearby member of another raid subgroup")
distanceUnavailable = true
spell, unit = Click(key, "LeftButton", false)
assert(spell and unit == "player", "Forever Battle Shout needs a nearby fallback in instances")
distanceSquared = 900
assert(not Click(key, "LeftButton", false), "generic group range must not prove 20-yard Battle Shout coverage")
module:Disable()
raid, nearby, distanceUnavailable, distanceSquared = false, "party2", false, 6400
Start(false)
spell, unit = Click(key, "LeftButton", false)
assert(spell == 6673 and unit == "player", "Retail Battle Shout missed a member within its radius")
distanceUnavailable = true
spell, unit = Click(key, "LeftButton", false)
assert(spell == 6673 and unit == "player", "Retail Battle Shout needs the instance group range fallback")
module:Disable()
print("Retail and Forever group buff casting selected fresh recipients without adding combat or timer work")

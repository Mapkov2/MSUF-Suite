local _, P = ...
local NS, S = P.NS, P.Suite
local R = P.BuffReminders
local Public = S.Public
local Clear = R.Clear
local CLASSES = { "DRUID", "MAGE", "PRIEST", "SHAMAN", "WARRIOR", "EVOKER" }
R.BUFF_CLASSES = CLASSES
-- Settings whose change forces a full group refresh.
local GROUP_OPTIONS = { "groupBuff", "classBuff", "otherClassBuffs", "healthstoneFromWarlock",
    "soulstoneOnAlly", "beaconOnAlly", "onlyInRange" }
-- Member events arrive in bursts (buffing before a pull, a busy city, a
-- roster storm). They only mark their unit; one pass this much later
-- refreshes the marked units and the display once, without item counts.
local FLUSH_DELAY = 0.1
local RANGE_EVENT = "UNIT_IN_RANGE_UPDATE"

function R.WantsGroup(self)
    local c = self.config
    return c.groupBuff == true or c.otherClassBuffs == true or c.healthstoneFromWarlock == true
        or c.soulstoneOnAlly == true or c.beaconOnAlly == true or R.WantsAllies(self) or c.raidBuffOverview == true
end

-- The group options that read the members' auras (R.RefreshGroup), the ally
-- class reminders among them; only these follow the members' aura,
-- connection, flag and phase events. The other group options need the roster
-- alone.
function R.WantsMemberAuras(self)
    local c = self.config
    return c.groupBuff == true or c.soulstoneOnAlly == true or c.beaconOnAlly == true or R.WantsAllies(self)
        or c.raidBuffOverview == true and self.group.unitList and #self.group.unitList > 1
end

local function NewRoster()
    return { units = {}, list = {} }
end

-- The members are built into the idle one of two roster buffers, so a
-- rebuild can tell a changed membership apart without allocating.
local function FillRoster(roster)
    local units, list = roster.units, roster.list
    units.player = true
    list[1] = "player"
    local raid = IsInRaid()
    local count = raid and GetNumGroupMembers() or GetNumSubgroupMembers()
    if not Public(count) or type(count) ~= "number" then return end
    for i = 1, math.min(count, raid and 40 or 4) do
        local unit = (raid and "raid" or "party") .. i
        local player = UnitIsUnit(unit, "player")
        if Public(player) and player == false then
            units[unit] = true
            list[#list + 1] = unit
        end
    end
end

local function SameMembers(previous, roster)
    if not previous then return false end
    local count = 0
    for unit in pairs(previous) do
        if not roster.units[unit] then return false end
        count = count + 1
    end
    return count == #roster.list
end

-- Roster work is cold; individual member events refresh only their unit.
-- group.unitList ("player" first) is the unit filter of the member events.
function R.GroupRoster(self)
    local group = self.group
    local settings = group.settings or {}
    group.settings = settings
    for _, key in ipairs(GROUP_OPTIONS) do
        local enabled = self.config[key] == true
        if settings[key] ~= enabled then
            self.list.needsFullRefresh = true
            settings[key] = enabled
        end
    end
    local buffers = group.buffers or { NewRoster(), NewRoster() }
    group.buffers = buffers
    local roster = group.units == buffers[1].units and buffers[2] or buffers[1]
    Clear(roster.units)
    Clear(roster.list)
    local classes = group.classes or {}
    group.classes = classes
    Clear(classes)
    group.allies = R.WantsAllies(self)
    if R.WantsGroup(self) then FillRoster(roster) end
    if not SameMembers(group.units, roster) then
        group.listChanged = true
        self.list.needsFullRefresh = true
    end
    group.units, group.unitList = roster.units, roster.list
    for unit in pairs(roster.units) do
        local _, class = UnitClass(unit)
        if Public(class) and type(class) == "string" then classes[class] = true end
    end
    -- Spell/class changes already compile the roster. Keep this selection
    -- off member aura events, which only need to refresh the cached buff.
    local buff = self.config.groupBuff and R.ClassBuff(R.PlayerClass())
    group.buff = buff and R.Known(buff.cast) and buff or nil
end

-- Combat end after a roster change in combat (Controller.lua
-- CompileAfterCombat): reads the roster and tells whether a class another
-- class's buff notice depends on (otherClassBuffs) came or went, the only
-- roster input of the reminder list.
local hadClass = {}
function R.RosterChanged(self)
    local watched, classes = self.config.otherClassBuffs == true or self.config.raidBuffOverview == true, self.group.classes
    for i = 1, #CLASSES do hadClass[i] = classes ~= nil and classes[CLASSES[i]] == true end
    R.GroupRoster(self)
    if not watched then return false end
    classes = self.group.classes
    for i = 1, #CLASSES do
        if (classes[CLASSES[i]] == true) ~= hadClass[i] then return true end
    end
    return false
end

local function Eligible(unit)
    local exists, connected, visible, dead = UnitExists(unit), UnitIsConnected(unit), UnitIsVisible(unit), UnitIsDeadOrGhost(unit)
    return Public(exists) and exists == true and Public(connected) and connected == true
        and Public(visible) and visible == true and Public(dead) and dead == false
end

local function RangeEligible(unit)
    if not Eligible(unit) then return false end
    local phase = UnitPhaseReason(unit)
    return Public(phase) and phase == nil
end

local function ReadMemberRange(unit, cached)
    if unit == "player" or not RangeEligible(unit) then return nil end
    if cached ~= nil then return cached end
    local inRange, checked = UnitInRange(unit)
    if Public(checked) and (checked == true or checked == 1) and Public(inRange) then return inRange end
end

-- Consume the same native range result as MSUF's group frames. Only a
-- member without a prior readable sample may need its auras read on entry.
local function RangeChanged(self, _, unit, inRange)
    local group = self.group
    local range = group.range
    if not range or not Public(unit) or unit == "player" or not group.units[unit] then return end
    if not Public(inRange) then inRange = nil end
    local before = range[unit]
    if inRange == before or (before == nil and (inRange ~= true or not RangeEligible(unit))) then return end
    range[unit] = inRange
    if (before == true) ~= (inRange == true) then
        R.QueueMemberWork(self, before == nil and unit or nil)
    end
end

local function HasRangeReminder(self)
    local group = self.group
    if group.soulstoneKnown or group.beaconLightKnown or group.beaconFaithKnown then return true end
    for _, entry in ipairs(self.list.entries) do
        if entry.group then return true end
    end
    return false
end

function R.SyncRange(self, allowed)
    local group = self.group
    if allowed and self.config.onlyInRange and self.listen.aura == "group" and #group.unitList > 1
        and HasRangeReminder(self) then
        if group.range then return end
        group.range = {}
        R.Listen(self, RANGE_EVENT, RangeChanged, group.unitList)
    elseif group.range then
        group.range = nil
        self.context:RemoveEvent(RANGE_EVENT)
    end
end

function R.CanRemindAlly(self)
    if not self.config.onlyInRange then return true end
    local range = self.group.range
    if range then
        for _, inRange in pairs(range) do
            if inRange == true then return true end
        end
    end
    return false
end

local function Listed(ids, id)
    for i = 1, #ids do
        if ids[i] == id then return true end
    end
    return false
end

-- Whether a member has one of the auras: true, false, or nil while that is
-- unknown. The lookups return nothing instead of raising while aura data is
-- restricted, which R.AurasRestricted reports.
--
-- The player's own Soulstone or Beacon, looked up by name with the PLAYER
-- filter: it selects the caster natively, also when another caster has the
-- same aura on this unit (no first-instance guess). A member that is
-- offline, out of sight or dead cannot be read and holds none (false), so
-- one such raid member does not silence that notice for everyone.
-- An ally reminder (ally) counts the other members only, and only its own
-- spells: Earth Shield on the shaman (Elemental Orbit, 383648) shares the
-- name of the ally spell 974. The roster holds the player as "player" alone
-- (FillRoster).
local function OwnAuraOn(unit, aliases, ally)
    if ally and unit == "player" then return false end
    if R.AurasRestricted() then return nil end
    if not Eligible(unit) then return false end
    for i = 1, #aliases do
        local known, data = R.RankAura(unit, aliases[i], R.OWN_HELPFUL)
        if not known or not Public(data) then return nil end
        if data then
            if not ally then return true end
            local spellID = data.spellId
            if not Public(spellID) then return nil end
            if Listed(aliases, spellID) then return true end
        end
    end
    return false
end

-- The group buff on a member, by name for Forever's ranked buffs, else by
-- spell ID. A member that cannot be read is skipped (nil).
local function BuffOn(unit, aliases, ranked)
    if R.AurasRestricted() or not Eligible(unit) then return nil end
    for i = 1, #aliases do
        local known, data = true, nil
        if ranked then
            known, data = R.RankAura(unit, aliases[i], R.HELPFUL)
        else
            data = C_UnitAuras.GetUnitAuraBySpellID(unit, aliases[i])
        end
        if not known or not Public(data) then return nil end
        if data then return true, data end
    end
    return false
end
R.GroupBuffOn = BuffOn

-- Whether the player's own aura is on no member: true, false, or nil while
-- a member is unknown. The members' answers are kept in group[key], or in
-- group.allyStates[key] for an ally reminder (ally).
local function OwnMissing(self, key, aliases, changedUnit, ally)
    local group = self.group
    local parent = ally and group.allyStates or group
    local states = parent[key] or {}
    parent[key] = states
    if changedUnit then
        states[changedUnit] = OwnAuraOn(changedUnit, aliases, ally)
    else
        Clear(states)
        for unit in pairs(group.units) do states[unit] = OwnAuraOn(unit, aliases, ally) end
    end
    local unknown = false
    for unit in pairs(group.units) do
        if states[unit] == true then return false end
        if states[unit] == nil then unknown = true end
    end
    if not unknown then return true end
end

local function SoulstoneKnown()
    if not NS.Client.isForever then return R.Known(R.SOULSTONE_AURA) end
    for _, id in ipairs(R.FOREVER_SOULSTONE_SPELLS) do if R.Known(id) then return true end end
    return false
end

local SOULSTONE, LIGHT, FAITH = { R.SOULSTONE_AURA }, { R.BEACON_OF_LIGHT }, { R.BEACON_OF_FAITH }
local function RefreshOwnBuffs(self, changedUnit)
    local c, group, notices = self.config, self.group, self.notices
    notices.soulstoneMissing, notices.beaconMissing = nil, nil
    if not changedUnit then
        group.soulstoneKnown = c.soulstoneOnAlly and SoulstoneKnown() or false
        group.beaconLightKnown = c.beaconOnAlly and R.Known(R.BEACON_OF_LIGHT) or false
        group.beaconFaithKnown = c.beaconOnAlly and R.Known(R.BEACON_OF_FAITH) or false
    end
    if c.soulstoneOnAlly and group.soulstoneKnown then
        notices.soulstoneMissing = OwnMissing(self, "soulstonePresence", SOULSTONE, changedUnit)
    end
    if not c.beaconOnAlly then return end
    if group.beaconLightKnown and OwnMissing(self, "beaconLightPresence", LIGHT, changedUnit) then
        notices.beaconMissing = true
    end
    if group.beaconFaithKnown and OwnMissing(self, "beaconFaithPresence", FAITH, changedUnit) then
        notices.beaconMissing = true
    end
end

-- The ally class reminders: each one's allyMissing says whether the player's
-- own aura is on no other member. Alone in the group, nobody can be buffed.
local function RefreshAllies(self, changedUnit)
    local entries = self.list.entries
    if not entries then return end
    local group = self.group
    local alone = #group.unitList < 2
    group.allyStates = group.allyStates or {}
    for _, entry in ipairs(entries) do
        local def = entry.ally
        if def then
            entry.allyMissing = not alone and OwnMissing(self, def.key, entry.aliases, changedUnit, true)
        end
    end
end

-- Present while the player's aura is on a member; nil while unknown.
function R.AllyPresent(entry)
    local missing = entry.allyMissing
    if missing == nil then return nil end
    return not missing
end

function R.RefreshGroup(self, changedUnit)
    local group = self.group
    local units = group.units
    if NS.IsCombatLocked() or not units then return end
    if changedUnit and not units[changedUnit] then return end
    RefreshOwnBuffs(self, changedUnit)
    if group.allies then RefreshAllies(self, changedUnit) end
    local config = self.config
    if config.raidBuffOverview then R.RefreshRaidOverview(self, changedUnit) end
    if not changedUnit and (config.onlyInRange or group.range) then
        R.SyncRange(self, true)
        local range = group.range
        if range then
            Clear(range)
            for unit in pairs(units) do range[unit] = ReadMemberRange(unit) end
        end
    end
    if not config.groupBuff then return end
    local buff = group.buff
    if not buff then return end
    if config.raidBuffOverview then
        local shared = R.RaidBuffPresence(self, buff)
        if shared then
            group.presence = shared
            return
        end
    end
    local states = group.presence or {}
    group.presence = states
    local ranked = NS.Client.isForever
    if changedUnit then
        states[changedUnit] = BuffOn(changedUnit, buff.auras, ranked)
        return
    end
    Clear(states)
    for unit in pairs(units) do states[unit] = BuffOn(unit, buff.auras, ranked) end
end

-- The advance warning (remindBeforeMinutes) of the group buff entry follows
-- the player's own copy, as it does for the class buff without the group
-- option; the member count alone has no expiration. entry.own is the
-- player's aura record, kept apart so the group presence does not decide
-- which aura deltas need a fresh lookup.
function R.OwnGroupBuffTiming(self, entry, fullRefresh, updateInfo)
    if entry.ally then return end
    if not self.config.classBuff then
        entry.expiresAt, entry.totalDuration = nil, nil
        return
    end
    local own = entry.own
    if not own then
        own = {}
        entry.own = own
    end
    if own.aura ~= entry.aura or own.aliases ~= entry.aliases or own.ranked ~= entry.ranked then
        own.aura, own.aliases, own.ranked, own.present = entry.aura, entry.aliases, entry.ranked, nil
    end
    if fullRefresh or R.AuraChangeAffects(own, updateInfo) then
        own.present, own.auraInstanceID, own.expiresAt, own.instanceIDs, own.totalDuration = R.AuraPresent(own)
    end
    if own.present == true then
        entry.expiresAt, entry.totalDuration = own.expiresAt, own.totalDuration
    else
        entry.expiresAt, entry.totalDuration = nil, nil
    end
end

function R.GroupPresent(self, entry)
    if entry.ally then
        if not R.CanRemindAlly(self) then return true end
        return R.AllyPresent(entry)
    end
    local group = self.group
    local presence = group.presence
    local missing = 0
    if presence then
        local config = self.config
        local classBuff = config.classBuff
        if config.onlyInRange then
            if classBuff and presence.player == false then missing = 1 end
            if group.range then
                for unit, inRange in pairs(group.range) do
                    if inRange == true and presence[unit] == false then missing = missing + 1 end
                end
            end
        else
            for unit, present in pairs(presence) do
                if present == false and (unit ~= "player" or classBuff) then missing = missing + 1 end
            end
        end
    end
    entry.missingCount = missing
    return missing == 0
end

-- The pass runs only while the module is active (a context job).
local function Flush(self)
    local group = self.group
    local dirty = group.dirty
    if self.listen.suspended or NS.IsCombatLocked() then
        Clear(dirty)
        group.rosterDirty = false
        return
    end
    if group.rosterDirty then
        -- A roster change can change who provides which buff: recompile.
        group.rosterDirty = false
        Clear(dirty)
        self:Compile()
        self:Update("all")
        return
    end
    local range = group.range
    for unit, refreshRange in pairs(dirty) do
        dirty[unit] = nil
        if range and refreshRange and group.units[unit] then range[unit] = ReadMemberRange(unit, range[unit]) end
        R.RefreshGroup(self, unit)
    end
    self:Update("visual")
end

-- The set of marked members and the pass (a context job), made on first use.
local function NewDirty(self, group)
    local dirty = {}
    group.dirty = dirty
    group.pass = self.context:Coalesce(FLUSH_DELAY, Flush)
    return dirty
end

-- Marks one member for the next pass. Member events come in bursts, so the
-- common case only marks the unit.
function R.QueueMemberWork(self, unit, refreshRange)
    local group = self.group
    local dirty = group.dirty or NewDirty(self, group)
    if unit then dirty[unit] = dirty[unit] or refreshRange or false end
    group.pass:Request()
end

-- Marks the roster for the next pass, which recompiles.
function R.QueueRosterWork(self)
    local group = self.group
    if not group.dirty then NewDirty(self, group) end
    group.rosterDirty = true
    group.pass:Request()
end

function R.CancelGroupWork(self)
    local group = self.group
    if group.dirty then Clear(group.dirty) end
    group.rosterDirty = false
end

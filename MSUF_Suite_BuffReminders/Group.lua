local _, P = ...
local NS, S = P.NS, P.Suite
local R = P.BuffReminders
local Public = S.Public
local Clear = R.Clear
local CLASSES = { "DRUID", "MAGE", "PRIEST", "SHAMAN", "WARRIOR", "EVOKER" }
R.BUFF_CLASSES = CLASSES
-- Settings whose change forces a full group refresh.
local GROUP_OPTIONS = { "groupBuff", "classBuff", "otherClassBuffs", "healthstoneFromWarlock",
    "soulstoneOnAlly", "beaconOnAlly" }
-- Member events arrive in bursts (buffing before a pull, a busy city, a
-- roster storm). They only mark their unit; one pass this much later
-- refreshes the marked units and the display once, without item counts.
local FLUSH_DELAY = 0.1

function R.WantsGroup(self)
    local c = self.config
    return c.groupBuff == true or c.otherClassBuffs == true or c.healthstoneFromWarlock == true
        or c.soulstoneOnAlly == true or c.beaconOnAlly == true
end

-- The group options that read the members' auras (R.RefreshGroup); only
-- these follow the members' aura, connection, flag and phase events. The
-- other group options need the roster alone.
function R.WantsMemberAuras(self)
    local c = self.config
    return c.groupBuff == true or c.soulstoneOnAlly == true or c.beaconOnAlly == true
end

local function NewRoster()
    return { units = {}, list = {} }
end

-- The members are built into the idle one of two roster buffers, so a
-- rebuild can tell a changed membership apart without allocating.
local function FillRoster(self, roster)
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
        if settings[key] ~= enabled then self.list.needsFullRefresh = true; settings[key] = enabled end
    end
    local buffers = group.buffers or { NewRoster(), NewRoster() }
    group.buffers = buffers
    local roster = group.units == buffers[1].units and buffers[2] or buffers[1]
    Clear(roster.units)
    Clear(roster.list)
    local classes = group.classes or {}
    group.classes = classes
    Clear(classes)
    if R.WantsGroup(self) then FillRoster(self, roster) end
    if not SameMembers(group.units, roster) then group.listChanged = true end
    group.units, group.unitList = roster.units, roster.list
    for unit in pairs(roster.units) do
        local _, class = UnitClass(unit)
        if Public(class) and type(class) == "string" then classes[class] = true end
    end
end

local function Eligible(unit)
    local exists, connected, visible, dead = UnitExists(unit), UnitIsConnected(unit), UnitIsVisible(unit), UnitIsDeadOrGhost(unit)
    return Public(exists) and exists == true and Public(connected) and connected == true
        and Public(visible) and visible == true and Public(dead) and dead == false
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
local function OwnAuraOn(unit, aliases)
    if R.AurasRestricted() then return nil end
    if not Eligible(unit) then return false end
    for i = 1, #aliases do
        local known, data = R.RankAura(unit, aliases[i], R.OWN_HELPFUL)
        if not known or not Public(data) then return nil end
        if data then return true end
    end
    return false
end

-- The group buff on a member, by name for Forever's ranked buffs, else by
-- spell ID. A member that cannot be read is skipped (nil).
local function BuffOn(unit, aliases, ranked)
    if R.AurasRestricted() or not Eligible(unit) then return nil end
    for i = 1, #aliases do
        local known, data = true, nil
        if ranked then known, data = R.RankAura(unit, aliases[i], R.HELPFUL)
        else data = C_UnitAuras.GetUnitAuraBySpellID(unit, aliases[i]) end
        if not known or not Public(data) then return nil end
        if data then return true end
    end
    return false
end

-- Whether the player's own aura is on no member: true, false, or nil while
-- a member is unknown.
local function OwnMissing(self, key, aliases, changedUnit)
    local group = self.group
    local states = group[key] or {}
    group[key] = states
    if changedUnit then
        states[changedUnit] = OwnAuraOn(changedUnit, aliases)
    else
        Clear(states)
        for unit in pairs(group.units) do states[unit] = OwnAuraOn(unit, aliases) end
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

function R.RefreshGroup(self, changedUnit)
    local group = self.group
    local units = group.units
    if NS.IsCombatLocked() or not units then return end
    if changedUnit and not units[changedUnit] then return end
    RefreshOwnBuffs(self, changedUnit)
    if not self.config.groupBuff then return end
    local _, class = UnitClass("player")
    local buff = Public(class) and R.ClassBuff(class)
    if not buff or not R.Known(buff.cast) then return end
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
    local group = self.group
    local presence = group.presence
    local missing = 0
    for unit in pairs(group.units or {}) do
        if (unit ~= "player" or self.config.classBuff) and presence
            and presence[unit] == false then missing = missing + 1 end
    end
    entry.missingCount = missing
    return missing == 0
end

local function Flush(self)
    local group = self.group
    group.flushPending = false
    local dirty = group.dirty
    if not self.active or self.listen.suspended or NS.IsCombatLocked() then
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
    for unit in pairs(dirty) do
        dirty[unit] = nil
        R.RefreshGroup(self, unit)
    end
    self:Update("visual")
end

-- The set of marked members, made with the pass callback on first use.
local function NewDirty(self, group)
    local dirty = {}
    group.dirty = dirty
    group.flush = function() Flush(self) end
    return dirty
end

local function SchedulePass(group)
    group.flushPending = true
    C_Timer.After(FLUSH_DELAY, group.flush)
end

-- Marks one member for the next pass. Member events come in bursts, so the
-- common case only marks the unit.
function R.QueueMemberWork(self, unit)
    local group = self.group
    local dirty = group.dirty or NewDirty(self, group)
    if unit then dirty[unit] = true end
    if not group.flushPending then SchedulePass(group) end
end

-- Marks the roster for the next pass, which recompiles.
function R.QueueRosterWork(self)
    local group = self.group
    if not group.dirty then NewDirty(self, group) end
    group.rosterDirty = true
    if not group.flushPending then SchedulePass(group) end
end

function R.CancelGroupWork(self)
    local group = self.group
    if group.dirty then Clear(group.dirty) end
    group.rosterDirty = false
end

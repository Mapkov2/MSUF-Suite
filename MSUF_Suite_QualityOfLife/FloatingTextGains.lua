local _, P = ...
local S, NS = P.Suite, P.NS
local Feed = NS.FloatingCombatFeed
local Gains = {}
P.FloatingTextGains = Gains
local DIRECT = { inCombat = true, direct = true }
local POWER_EVENTS = { "UNIT_POWER_UPDATE", "UNIT_DISPLAYPOWER", "UNIT_MAXPOWER" }
local PASSIVE_POWER = { MANA = true, FOCUS = true, ENERGY = true, ESSENCE = true }
local POWER_BATCH_SECONDS = 0.5
local powerType = NS.Client.isForever and Enum.PowerType
local PLAYER_POWER = powerType and {
    MANA = powerType.Mana, RAGE = powerType.Rage, FOCUS = powerType.Focus, ENERGY = powerType.Energy,
    COMBO_POINTS = powerType.ComboPoints, RUNES = powerType.Runes, RUNIC_POWER = powerType.RunicPower,
    SOUL_SHARDS = powerType.SoulShards, LUNAR_POWER = powerType.LunarPower, HOLY_POWER = powerType.HolyPower,
    MAELSTROM = powerType.Maelstrom, CHI = powerType.Chi, INSANITY = powerType.Insanity,
    ARCANE_CHARGES = powerType.ArcaneCharges, FURY = powerType.Fury, PAIN = powerType.Pain,
    ESSENCE = powerType.Essence, DEMONIC_FURY = powerType.DemonicFury,
}
local XP_FORMAT = S.Text("+%s XP")
local REP_FORMAT = S.Text("%s Reputation")
local HONOR_FORMAT = S.Text("+%s Honor")
local POWER_FORMAT = S.Text("+%s Resource")
local LEVEL_FORMAT = S.Text("Level %d")
local COMBAT_START, COMBAT_END = S.Text("Entering combat"), S.Text("Leaving combat")

Gains.Formats = {
    xp = XP_FORMAT, level = LEVEL_FORMAT, reputation = REP_FORMAT, honor = HONOR_FORMAT, power = POWER_FORMAT,
}
Gains.CombatStart, Gains.CombatEnd = COMBAT_START, COMBAT_END

local EVENT_KINDS = {
    ENERGIZE = "power", PERIODIC_ENERGIZE = "power", FACTION = "reputation", HONOR_GAINED = "honor",
}

local function ReadPower(index)
    local current = UnitPower("player", index)
    if S.Finite(current) and current >= 0 then return current end
end

local function PlayerPowerOwns(self, token)
    local values = self.powerValues
    if not values then return false end
    local activeUnit = C_CombatText.GetActiveUnit()
    if not S.Public(activeUnit) or (activeUnit and activeUnit ~= "player") then return false end
    -- If the native token is secret, use the readability of the active
    -- resource to choose between the player counter and native text.
    if not S.Public(token) then return next(values) ~= nil and ReadPower(nil) ~= nil end
    local index = PLAYER_POWER[token]
    if index == nil or values[token] == nil then return false end
    if ReadPower(index) ~= nil then return true end
    values[token] = nil
    return false
end

local function CombatText(self, _, messageType)
    -- Own combat text owns damage received and healing. Only progress and
    -- resource gains reach this renderer, from the existing player stream.
    if not S.Public(messageType) then return end
    local kind = EVENT_KINDS[messageType]
    if not kind or not self.display.enabled[kind] then return end
    if kind == "honor" and self.listeningHonor then
        local readable = S.HonorProgress() ~= nil
        if readable and self.honorLevel then return end
        if not readable then self.honorValue, self.honorMax, self.honorLevel = nil, nil, nil end
    end
    local first, second = C_CombatText.GetCurrentEventInfo()
    if kind == "power" and PlayerPowerOwns(self, second) then return end
    local amount = first
    if kind == "reputation" then amount = second end
    if S.Public(amount) and amount == nil then return end
    if kind == "reputation" then
        self.display:Show("gain", false, REP_FORMAT, amount)
    elseif kind == "honor" then
        self.display:Show("gain", false, HONOR_FORMAT, amount)
    else
        self.display:Show("power", false, POWER_FORMAT, amount)
    end
end

local function XP()
    local level, current, maximum = UnitLevel("player"), UnitXP("player"), UnitXPMax("player")
    if S.Finite(level) and S.Finite(current) and S.Finite(maximum)
        and level > 0 and current >= 0 and maximum >= 0 then
        return level, current, maximum
    end
end

local function SeedXP(self)
    if self.listeningXP then self.xpLevel, self.xpValue, self.xpMax = XP() end
end

local function EnsurePlayerStream()
    local api = C_CombatText
    if NS.InCombat() then return end
    local current = api.GetActiveUnit()
    if not S.Public(current) or current ~= nil then return end
    local restricted = C_Secrets.ShouldUnitIdentityBeSecret("player")
    if not S.Public(restricted) or restricted then return end
    -- Fill only an empty selection. Blizzard and Own combat text retain
    -- ownership of any selection already made, including a vehicle.
    api.SetActiveUnit("player")
end

local function ProgressDelta(level, current, previousLevel, previous, previousMax)
    if not previousLevel then return end
    if level == previousLevel then return current - previous end
    if level == previousLevel + 1 and previousMax >= previous then
        return previousMax - previous + current
    end
end

local function ReconcileXP(self)
    local level, current, maximum = XP()
    if not level then return end
    local previousLevel, previous, previousMax = self.xpLevel, self.xpValue, self.xpMax
    -- The rollover can update the counter before the unit's level.
    if level == previousLevel and current < previous then return end
    self.xpLevel, self.xpValue, self.xpMax = level, current, maximum
    local gain = ProgressDelta(level, current, previousLevel, previous, previousMax)
    if gain and gain > 0 then self.display:Show("xp", false, XP_FORMAT, gain) end
end

local function RecheckXP(self)
    self.xpRecheck = nil
    if self.listeningXP and self.worldTextHidden then ReconcileXP(self) end
end

local function QueueXP(self)
    -- XP, level and chat notifications can precede each other's counter
    -- updates. Read the combined state once, after this frame's updates.
    if self.xpRecheck then return end
    self.xpRecheck = true
    self.context:After(0, RecheckXP)
end

local function XPChanged(self, _, unit)
    if not S.Public(unit) or (unit and unit ~= "player") then return end
    if self.worldTextHidden then QueueXP(self) else ReconcileXP(self) end
end

local function LevelUp(self, _, level)
    if self.listeningXP and self.worldTextHidden then QueueXP(self) end
    if self.display.enabled.level and S.Finite(level) then self.display:Show("gain", true, LEVEL_FORMAT, level) end
end

local function SeedHonor(self)
    self.honorValue, self.honorMax, self.honorLevel = S.HonorProgress()
end

local function HonorChanged(self, _, unit)
    if not S.Public(unit) or (unit and unit ~= "player") then return end
    local current, maximum, level = S.HonorProgress()
    if level and level == self.honorLevel and current < self.honorValue then return end
    local gain = level and ProgressDelta(level, current, self.honorLevel, self.honorValue, self.honorMax)
    self.honorValue, self.honorMax, self.honorLevel = current, maximum, level
    if gain and gain > 0 then self.display:Show("gain", false, HONOR_FORMAT, gain) end
end

local function SeedPower(values, token, index)
    local maximum = UnitPowerMax("player", index)
    values[token] = S.Finite(maximum) and maximum > 0 and ReadPower(index) or nil
end

local function SeedAllPower(self)
    wipe(self.powerGains)
    for token, index in pairs(PLAYER_POWER) do SeedPower(self.powerValues, token, index) end
end

local function FlushPower(self)
    local gains = self.powerGains
    if not gains then return end
    for _, gain in pairs(gains) do self.display:Show("power", false, POWER_FORMAT, gain) end
    wipe(gains)
end

local function ShowPower(self, token, gain)
    if not PASSIVE_POWER[token] then
        self.display:Show("power", false, POWER_FORMAT, gain)
        return
    end
    -- Continuous regeneration shares a lane with progression by default.
    -- Batch its ticks so they do not immediately recycle those messages.
    local gains = self.powerGains
    if not next(gains) then self.context:After(POWER_BATCH_SECONDS, FlushPower) end
    gains[token] = (gains[token] or 0) + gain
end

local function PowerChanged(self, event, unit, token)
    if not S.Public(unit) or unit ~= "player" then return end
    if event == "UNIT_DISPLAYPOWER" then
        SeedAllPower(self)
        return
    end
    local values = self.powerValues
    if not S.Public(token) then
        wipe(values)
        return
    end
    local index = PLAYER_POWER[token]
    if index == nil then return end
    local previous = values[token]
    if event == "UNIT_MAXPOWER" or previous == nil then
        SeedPower(values, token, index)
        return
    end
    local current = ReadPower(index)
    values[token] = current
    if current and current > previous then ShowPower(self, token, current - previous) end
end

function Gains.WorldChanged(self)
    SeedXP(self)
    if self.listeningHonor then SeedHonor(self) end
    if self.powerValues then SeedAllPower(self) end
    if self.listeningGains then EnsurePlayerStream() end
end

local function CombatState(self, event)
    self.display:Show("combat", false, nil, event == "PLAYER_REGEN_DISABLED" and COMBAT_START or COMBAT_END)
end

local function SetEvent(context, event, callback, active)
    if active then context:Event(event, callback, DIRECT) else context:RemoveEvent(event) end
end

local function RefreshPlayerGains(self, enabled, context)
    -- The world-text renderer can be hidden while the player's own counters
    -- continue updating. Use one source per gain to avoid double messages.
    local honor = self.worldTextHidden and enabled.honor and NS.Client.SupportsEvent("HONOR_XP_UPDATE") or false
    if honor ~= self.listeningHonor then
        self.listeningHonor = honor
        if honor then SeedHonor(self) else self.honorValue, self.honorMax, self.honorLevel = nil, nil, nil end
        SetEvent(context, "HONOR_XP_UPDATE", HonorChanged, honor)
    end
    local power = self.worldTextHidden and enabled.power and PLAYER_POWER and NS.Client.SupportsEvent("UNIT_POWER_UPDATE") or false
    if power == (self.powerValues ~= nil) then return end
    if power then
        self.powerValues, self.powerGains = {}, {}
        SeedAllPower(self)
        for _, event in ipairs(POWER_EVENTS) do context:Event(event, PowerChanged, true, "player") end
    else
        self.powerValues, self.powerGains = nil, nil
        context:Cancel(FlushPower)
        for _, event in ipairs(POWER_EVENTS) do context:RemoveEvent(event) end
    end
end

function Gains.Refresh(self)
    local enabled, context = self.display.enabled, self.context
    local xp = (enabled.xp or self.worldTextHidden) and Feed.Experience() or false
    if self.listeningXP ~= xp then
        self.listeningXP = xp
        if xp then SeedXP(self) else self.xpLevel, self.xpValue, self.xpMax = nil, nil, nil end
        SetEvent(context, "PLAYER_XP_UPDATE", XPChanged, xp)
    end
    local replaceXP = xp and self.worldTextHidden
    SetEvent(context, "CHAT_MSG_COMBAT_XP_GAIN", QueueXP, replaceXP)
    SetEvent(context, "PLAYER_LEVEL_UP", LevelUp, (enabled.level or replaceXP) and Feed.LevelUp())
    RefreshPlayerGains(self, enabled, context)
    local gains = (enabled.reputation or enabled.power or enabled.honor) and Feed.Gains()
    if self.listeningGains ~= gains then
        self.listeningGains = gains
        if gains then EnsurePlayerStream() end
        SetEvent(context, "COMBAT_TEXT_UPDATE", CombatText, gains)
    end
    SetEvent(context, "PLAYER_REGEN_DISABLED", CombatState, enabled.combat)
    SetEvent(context, "PLAYER_REGEN_ENABLED", CombatState, enabled.combat)
end

function Gains.Disable(self)
    self.listeningGains = nil
    self.listeningXP, self.xpLevel, self.xpValue, self.xpMax, self.xpRecheck = nil, nil, nil, nil, nil
    self.listeningHonor, self.honorLevel, self.honorValue, self.honorMax = nil, nil, nil, nil
    self.powerValues, self.powerGains = nil, nil
end

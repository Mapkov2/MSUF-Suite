local _, P = ...
local S, NS = P.Suite, P.NS
local Feed = NS.FloatingCombatFeed
local Gains = {}
P.FloatingTextGains = Gains
local DIRECT = { inCombat = true, direct = true }
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

local function CombatText(self, _, messageType)
    -- Own combat text owns damage received and healing. Only progress and
    -- resource gains reach this renderer, from the existing player stream.
    if not S.Public(messageType) then return end
    local kind = EVENT_KINDS[messageType]
    if not kind or not self.display.enabled[kind] then return end
    local first, second = C_CombatText.GetCurrentEventInfo()
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

function Gains.WorldChanged(self)
    SeedXP(self)
    if self.listeningGains then EnsurePlayerStream() end
end

local function XPChanged(self, _, unit)
    if not S.Public(unit) or (unit and unit ~= "player") then return end
    local level, current, maximum = XP()
    if not level then return end
    local lastLevel, lastXP, lastMax = self.xpLevel, self.xpValue, self.xpMax
    -- A rollover update may reach Lua before the unit's level changes.
    if level == lastLevel and current < lastXP then return end
    self.xpLevel, self.xpValue, self.xpMax = level, current, maximum
    if not lastLevel then return end
    local gain
    if level == lastLevel then
        gain = current - lastXP
    elseif level == lastLevel + 1 and lastMax >= lastXP then
        gain = lastMax - lastXP + current
    end
    if gain and gain > 0 then self.display:Show("gain", false, XP_FORMAT, gain) end
end

local function LevelUp(self, _, level)
    if S.Finite(level) then self.display:Show("gain", true, LEVEL_FORMAT, level) end
end

local function CombatState(self, event)
    self.display:Show("combat", false, nil, event == "PLAYER_REGEN_DISABLED" and COMBAT_START or COMBAT_END)
end

local function SetEvent(context, event, callback, active)
    if active then context:Event(event, callback, DIRECT) else context:RemoveEvent(event) end
end

function Gains.Refresh(self)
    local enabled, context = self.display.enabled, self.context
    local xp = enabled.xp and Feed.Experience()
    if self.listeningXP ~= xp then
        self.listeningXP = xp
        if xp then SeedXP(self) else self.xpLevel, self.xpValue, self.xpMax = nil, nil, nil end
        SetEvent(context, "PLAYER_XP_UPDATE", XPChanged, xp)
        SetEvent(context, "PLAYER_LEVEL_UP", LevelUp, xp)
    end
    local gains = (enabled.power or enabled.reputation or enabled.honor) and Feed.Gains()
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
    self.listeningXP, self.xpLevel, self.xpValue, self.xpMax = nil, nil, nil, nil
end

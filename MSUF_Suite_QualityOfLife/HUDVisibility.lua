local _, P = ...
local NS, S = P.NS, P.Suite
local Hub = NS.HUDVisibility
local ID = "hudVisibility"
local ON_TARGET, ON_COMBAT, COMBAT_OR_TARGET = 1, 2, 3
local IN_COMBAT = { inCombat = true }
local Module = {}
local events = { "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED", "PLAYER_ENTERING_WORLD",
    "PLAYER_TARGET_CHANGED", "PLAYER_CONTROL_LOST", "PLAYER_CONTROL_GAINED" }
local disabled = {}

local function Cancel(self)
    if self.timer then self.timer:Cancel() end
    self.timer = nil
end

local function ShouldDim(config, event)
    if config.worldOnly then
        local inside = IsInInstance()
        if not S.Public(inside) or inside == true then return false end
    end
    if config.onTaxi then
        local taxi = UnitOnTaxi("player")
        if S.Public(taxi) and taxi == true then return true end
    end
    local rule = config.mode
    if rule == ON_COMBAT then return not NS.InCombat(event) end
    if rule == COMBAT_OR_TARGET and NS.InCombat(event) then return false end
    if rule ~= ON_TARGET and rule ~= COMBAT_OR_TARGET then return false end
    local target = UnitExists("target")
    return S.Public(target) and target == false
end

local function SetFactor(self, factor)
    self.factor = factor
    Hub.Changed(self.scopes, factor, self.config.hover)
end

local function Expire()
    Module.timer = nil
    if Module.active and ShouldDim(Module.config) then SetFactor(Module, Module.config.opacity / 100) end
end

local function RefreshVisibility(self, event)
    if self.config.opacity >= 100 or not ShouldDim(self.config, event) then
        Cancel(self)
        SetFactor(self, 1)
    elseif self.timer then
        return
    elseif self.config.delay > 0 and self.factor == 1 then
        self.timer = C_Timer.NewTimer(self.config.delay, Expire)
    else
        SetFactor(self, self.config.opacity / 100)
    end
end

function Module:Refresh()
    Cancel(self)
    local c = self.config
    self.scopes = { actionBars = c.actionBars or nil, cooldownManager = c.cooldownManager or nil,
        dataTexts = c.dataTexts or nil, procAlerts = c.procAlerts or nil }
    if self.factor == nil then self.factor = 1 end
    if self.factor == 1 then Hub.Changed(self.scopes, 1, c.hover) end
    RefreshVisibility(self)
end

function Module:Enable()
    self:Refresh()
    for index = 1, #events do self.context:Event(events[index], RefreshVisibility, IN_COMBAT) end
end

function Module:Disable()
    Cancel(self)
    self.factor = nil
    Hub.Changed(disabled, 1, false)
end

S.Install(ID, Module)

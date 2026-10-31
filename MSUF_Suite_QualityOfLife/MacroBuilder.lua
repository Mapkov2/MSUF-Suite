local _, P = ...
local NS, S = P.NS, P.Suite
local Store = NS.Macros.Store
local Module = {}
local PREPARE_EVENTS = { "BAG_UPDATE_DELAYED", "BAG_UPDATE_COOLDOWN", "SPELLS_CHANGED",
    "PLAYER_LEVEL_UP", "SKILL_LINES_CHANGED", "PLAYER_EQUIPMENT_CHANGED", "ITEM_DATA_LOAD_RESULT" }

local function Cancel()
    if Module.pending then
        Module.pending:Cancel()
        Module.pending = nil
    end
end

local function Flush()
    Module.pending = nil
    if Module.active and not Module.suspended and not NS.InCombat() then Store.RefreshManaged() end
end

local function Queue()
    if Module.active and not Module.suspended and not Module.pending and not NS.InCombat() then
        Module.pending = C_Timer.NewTimer(0.1, Flush)
    end
end

local function Suspend()
    Module.suspended = true
    Cancel()
    Module.frame:UnregisterAllEvents()
    Module.frame:RegisterEvent("PLAYER_REGEN_ENABLED")
end

local function RegisterPreparation()
    Module.frame:UnregisterAllEvents()
    Module.suspended = false
    for _, event in ipairs(PREPARE_EVENTS) do
        if NS.Client.SupportsEvent(event) then Module.frame:RegisterEvent(event) end
    end
    Module.frame:RegisterEvent("PLAYER_REGEN_DISABLED")
end

local function OnEvent(_, event)
    if event == "PLAYER_REGEN_DISABLED" then
        Suspend()
    elseif event == "PLAYER_REGEN_ENABLED" then
        Module:Refresh()
    else
        Queue()
    end
end

function Module:Open()
    if NS.InCombat() then return false end
    return NS.Menu.Open("suite_macros")
end

function Module:Refresh()
    Cancel()
    if not self.active then return end
    if not Store.HasManaged() then
        if self.frame then self.frame:UnregisterAllEvents() end
        self.suspended = false
        return
    end
    if not self.frame then
        self.frame = S.CreateFrame("Frame")
        self.frame:SetScript("OnEvent", OnEvent)
    end
    if NS.InCombat() then
        Suspend()
    else
        RegisterPreparation()
        Queue()
    end
end

function Module:Enable()
    self:Refresh()
end

function Module:Disable()
    Cancel()
    if self.frame then self.frame:UnregisterAllEvents() end
    self.suspended = false
end

Store.OnChange = function()
    if Module.active then Module:Refresh() end
end

S.Install("macroBuilder", Module)

local _, P = ...
local NS, S = P.NS, P.Suite

-- Clear only fanfares received while this opt-in helper is active. The
-- collection journals own their lists and filters; no scan or UI hook is used.
local M = {}
local EVENTS = {
    mounts = "NEW_MOUNT_ADDED",
    pets = "NEW_PET_ADDED",
    toys = "NEW_TOY_ADDED",
}

local function ValidID(kind, id)
    if kind == "pets" then return S.PublicText(id) end
    if S.Finite(id) and id > 0 and id == math.floor(id) then return id end
end

local Flush
local function AfterCombat(self)
    self.context:RemoveEvent("PLAYER_REGEN_ENABLED")
    Flush(self)
end

Flush = function(self)
    if not self.active then return end
    if NS.IsCombatLocked() then
        self.context:Event("PLAYER_REGEN_ENABLED", AfterCombat)
        return
    end
    self.context:RemoveEvent("PLAYER_REGEN_ENABLED")
    local pending = self.pending
    self.pending = nil
    if not pending then return end
    for id in pairs(pending.mounts or {}) do C_MountJournal.ClearFanfare(id) end
    for id in pairs(pending.pets or {}) do C_PetJournal.ClearFanfare(id) end
    for id in pairs(pending.toys or {}) do C_ToyBoxInfo.ClearFanfare(id) end
end

local function Schedule(self, kind, id)
    if not self.active or not self.config[kind] then return end
    id = ValidID(kind, id)
    if not id then return end
    self.pending = self.pending or {}
    self.pending[kind] = self.pending[kind] or {}
    self.pending[kind][id] = true
    -- One flush on the next frame for every fanfare of a burst.
    self.flushJob:Request()
end

local function Sync(self)
    for kind, event in pairs(EVENTS) do
        if self.config[kind] then
            self.context:Event(event, function(module, _, id) Schedule(module, kind, id) end)
        else
            self.context:RemoveEvent(event)
            if self.pending then self.pending[kind] = nil end
        end
    end
end

function M:Enable()
    self.flushJob = self.context:Coalesce(0, Flush)
    Sync(self)
end

function M:Refresh() Sync(self) end

-- The context's Release drops a flush still due.
function M:Disable()
    self.pending = nil
    for _, event in pairs(EVENTS) do self.context:RemoveEvent(event) end
    self.context:RemoveEvent("PLAYER_REGEN_ENABLED")
end

S.Install("collectionNewMarkers", M)

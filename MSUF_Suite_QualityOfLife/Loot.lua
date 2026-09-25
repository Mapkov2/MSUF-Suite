local _, P = ...
local NS, S = P.NS, P.Suite
local M = { addons = { Blizzard_FrameXML = true, Blizzard_UIPanels_Game = true } }
local Public = S.Public
local LOOT_EVENTS = { "LOOT_READY", "LOOT_OPENED", "LOOT_CLOSED" }
-- Script hooks cannot be removed. Each history frame is hooked once; the
-- hooks act only while this module manages that frame (M.history).
local hookedHistory = setmetatable({}, { __mode = "k" })

local function Collect(self, event, autoLoot)
    if event == "LOOT_CLOSED" then
        self.attempted = false
        self.session = (self.session or 0) + 1
        return
    end
    if not self.active or not self.config.quickLoot or self.attempted then return end
    -- Native auto-loot already owns this operation. Never issue a second batch.
    if not Public(autoLoot) or autoLoot then return end
    local mode = self.config.lootModifier
    if mode ~= 1 then
        if type(IsShiftKeyDown) ~= "function" then return end
        local shift = IsShiftKeyDown()
        if not Public(shift) or (mode == 2 and shift) or (mode == 3 and not shift) then return end
    end
    if type(GetNumLootItems) ~= "function" or type(GetLootSlotInfo) ~= "function"
        or type(LootSlot) ~= "function" then
        return
    end
    local count = GetNumLootItems()
    if not Public(count) or type(count) ~= "number" or count ~= count or count < 1 or count > 200
        or count ~= math.floor(count) then
        return
    end
    self.attempted = true
    local session = self.session
    -- Descending slot order remains valid when native collection removes rows.
    -- No confirmations, roll choices, closing or hiding of LootFrame here.
    for slot = count, 1, -1 do
        if not self.active or self.session ~= session then break end
        local _, _, _, _, _, locked = GetLootSlotInfo(slot)
        if Public(locked) and locked == false then LootSlot(slot) end
    end
end

local function Accessible(frame)
    return frame and not NS.Safety.IsForbidden(frame)
        and type(frame.HookScript) == "function" and type(frame.IsShown) == "function"
        and type(frame.Hide) == "function"
end

local function CancelHistory(self)
    local timer = self.historyTimer
    self.historyTimer = nil
    if timer then timer:Cancel() end
    self.pendingHistory = nil
    self.context:RemoveEvent("PLAYER_REGEN_ENABLED")
end

local CloseHistory
local function HistoryAfterCombat(module)
    module.context:RemoveEvent("PLAYER_REGEN_ENABLED")
    if module.pendingHistory then
        module.pendingHistory = nil
        CloseHistory(module)
    end
end

CloseHistory = function(self)
    local frame = self.history
    if not self.active or not self.config.manageHistory or not frame then return end
    if not Accessible(frame) or not frame:IsShown() then return end
    if NS.IsCombatLocked() then
        self.pendingHistory = true
        self.context:Event("PLAYER_REGEN_ENABLED", HistoryAfterCombat)
        return
    end
    frame:Hide()
end

local function ScheduleHistory(self)
    CancelHistory(self)
    if not self.active or not self.config.manageHistory
        or not (C_Timer and type(C_Timer.NewTimer) == "function") then
        return
    end
    local delay = self.config.historyMode == 1 and 0 or self.config.historyDelay
    local timer
    -- Defer even immediate suppression until native OnShow and its caller finish.
    timer = C_Timer.NewTimer(delay, function()
        if self.historyTimer ~= timer then return end
        self.historyTimer = nil
        CloseHistory(self)
    end)
    self.historyTimer = timer
end

-- Post-hooks: Blizzard's own OnShow/OnHide run first and stay untouched.
local function HistoryShown(frame)
    if M.history == frame and frame:IsShown() then ScheduleHistory(M) end
end

local function HistoryHidden(frame)
    if M.history == frame then CancelHistory(M) end
end

local function ReleaseHistory(self)
    CancelHistory(self)
    self.history = nil
end

local function AttachHistory(self)
    if not self.config.manageHistory then
        ReleaseHistory(self)
        return
    end
    if NS.IsCombatLocked() then
        S.Queue("loot")
        return
    end
    local frame = GroupLootHistoryFrame
    if self.history and self.history ~= frame then ReleaseHistory(self) end
    if not Accessible(frame) then return end
    if not hookedHistory[frame] then
        hookedHistory[frame] = true
        frame:HookScript("OnShow", HistoryShown)
        frame:HookScript("OnHide", HistoryHidden)
    end
    self.history = frame
    if frame:IsShown() then ScheduleHistory(self) end
end

local function HistoryAddonLoaded(self)
    AttachHistory(self)
    if self.history then self.context:RemoveEvent("ADDON_LOADED") end
end

function M:Refresh()
    local context = self.context
    if self.config.quickLoot then
        for i = 1, #LOOT_EVENTS do context:Event(LOOT_EVENTS[i], Collect, true) end
    else
        for i = 1, #LOOT_EVENTS do context:RemoveEvent(LOOT_EVENTS[i]) end
        self.attempted = false
        self.session = (self.session or 0) + 1
    end
    CancelHistory(self)
    AttachHistory(self)
    if self.config.manageHistory and not self.history then
        context:Event("ADDON_LOADED", HistoryAddonLoaded)
    else
        context:RemoveEvent("ADDON_LOADED")
    end
end

function M:Enable()
    self.attempted = false
    self.session = 0
    self:Refresh()
end

function M:Disable()
    self.attempted = false
    self.session = (self.session or 0) + 1
    ReleaseHistory(self)
end

S.Install("loot", M)

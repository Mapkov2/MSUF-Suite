local _, P = ...
local NS, S = P.NS, P.Suite
local M = { addons = { Blizzard_FrameXML=true, Blizzard_UIPanels_Game=true } }

local function Public(value)
    return not (type(issecretvalue)=="function" and issecretvalue(value))
end

local function Collect(self, event, autoLoot)
    if event=="LOOT_CLOSED" then
        self.attempted=false
        self.session=(self.session or 0)+1
        return
    end
    if not self.active or not self.config.quickLoot or self.attempted then return end
    -- Native auto-loot already owns this operation. Never issue a second batch.
    if not Public(autoLoot) or autoLoot then return end
    local mode=self.config.lootModifier
    if mode~=1 then
        if type(IsShiftKeyDown)~="function" then return end
        local shift=IsShiftKeyDown()
        if not Public(shift) or (mode==2 and shift) or (mode==3 and not shift) then return end
    end
    if type(GetNumLootItems)~="function" or type(GetLootSlotInfo)~="function" or type(LootSlot)~="function" then return end
    local count=GetNumLootItems()
    if not Public(count) or type(count)~="number" or count~=count or count<1 or count>200 or count~=math.floor(count) then return end
    self.attempted=true
    local session=self.session
    -- Descending slot order remains valid when native collection removes rows.
    -- No confirmations, roll choices, closing or hiding of LootFrame here.
    for slot=count,1,-1 do
        if not self.active or self.session~=session then break end
        local _, _, _, _, _, locked=GetLootSlotInfo(slot)
        if Public(locked) and locked==false then LootSlot(slot) end
    end
end

local function Accessible(frame)
    return frame and not NS.Safety.IsForbidden(frame)
        and type(frame.GetScript)=="function" and type(frame.SetScript)=="function"
        and type(frame.IsShown)=="function" and type(frame.Hide)=="function"
end

local function CancelHistory(self)
    local timer=self.historyTimer
    self.historyTimer=nil
    if timer then timer:Cancel() end
    self.pendingHistory=nil
    self.context:RemoveEvent("PLAYER_REGEN_ENABLED")
end

local function CloseHistory(self)
    local record=self.history
    if not self.active or not self.config.manageHistory or not record then return end
    local frame=record.frame
    if not Accessible(frame) or frame:GetScript("OnShow")~=record.show or not frame:IsShown() then return end
    if NS.IsCombatLocked() then
        self.pendingHistory=true
        self.context:Event("PLAYER_REGEN_ENABLED",function(module)
            module.context:RemoveEvent("PLAYER_REGEN_ENABLED")
            if module.pendingHistory then module.pendingHistory=nil; CloseHistory(module) end
        end)
        return
    end
    frame:Hide()
end

local function ScheduleHistory(self)
    CancelHistory(self)
    if not self.active or not self.config.manageHistory or not (C_Timer and type(C_Timer.NewTimer)=="function") then return end
    local delay=self.config.historyMode==1 and 0 or self.config.historyDelay
    local timer
    -- Defer even immediate suppression until native OnShow and its caller finish.
    timer=C_Timer.NewTimer(delay,function()
        if self.historyTimer~=timer then return end
        self.historyTimer=nil
        CloseHistory(self)
    end)
    self.historyTimer=timer
end

local function ReleaseHistory(self)
    CancelHistory(self)
    local record=self.history
    self.history=nil
    if not record or not Accessible(record.frame) then return end
    local frame=record.frame
    if frame:GetScript("OnShow")==record.show then frame:SetScript("OnShow",record.beforeShow) end
    if frame:GetScript("OnHide")==record.hide then frame:SetScript("OnHide",record.beforeHide) end
end

local function AttachHistory(self)
    if not self.config.manageHistory then ReleaseHistory(self); return end
    if NS.IsCombatLocked() then S.Queue("loot"); return end
    local frame=GroupLootHistoryFrame
    if self.history and self.history.frame~=frame then ReleaseHistory(self) end
    if not Accessible(frame) then return end
    if not self.history then
        local record={frame=frame,beforeShow=frame:GetScript("OnShow"),beforeHide=frame:GetScript("OnHide")}
        record.show=function(target,...)
            if record.beforeShow then record.beforeShow(target,...) end
            if self.history==record and target:IsShown() then ScheduleHistory(self) end
        end
        record.hide=function(target,...)
            if self.history==record then CancelHistory(self) end
            if record.beforeHide then record.beforeHide(target,...) end
        end
        self.history=record
        frame:SetScript("OnShow",record.show)
        frame:SetScript("OnHide",record.hide)
    end
    if frame:IsShown() then ScheduleHistory(self) end
end

local function HistoryAddonLoaded(self)
    AttachHistory(self)
    if self.history then self.context:RemoveEvent("ADDON_LOADED") end
end

function M:Refresh()
    if self.config.quickLoot then
        self.context:Event("LOOT_READY",Collect,true)
        self.context:Event("LOOT_OPENED",Collect,true)
        self.context:Event("LOOT_CLOSED",Collect,true)
    else
        self.context:RemoveEvent("LOOT_READY")
        self.context:RemoveEvent("LOOT_OPENED")
        self.context:RemoveEvent("LOOT_CLOSED")
        self.attempted=false
        self.session=(self.session or 0)+1
    end
    CancelHistory(self)
    AttachHistory(self)
    if self.config.manageHistory and not self.history then self.context:Event("ADDON_LOADED",HistoryAddonLoaded)
    else self.context:RemoveEvent("ADDON_LOADED") end
end

function M:Enable()
    self.attempted=false
    self.session=0
    self:Refresh()
end

function M:Disable()
    self.attempted=false
    self.session=(self.session or 0)+1
    ReleaseHistory(self)
end

S.Install("loot",M)

local _, P = ...
local NS, S = P.NS, P.Suite
local IN_COMBAT = { inCombat = true }
local M = {}
local POPUP = "MSUF_SUITE_TRAINER_LEARN_ALL"
local MAX_SERVICES = 2000
-- GetCoinTextureString exists only with the loadDeprecationFallbacks CVar on
-- (Blizzard_DeprecatedCurrencyScript); C_CurrencyInfo has it on every client.
local function Coins(copper)
    return C_CurrencyInfo.GetCoinTextureString(copper)
end

local function TrainerOpen(self)
    local frame = _G.ClassTrainerFrame
    return self.active and frame and not NS.Safety.IsForbidden(frame)
        and frame:IsShown() and not NS.IsCombatLocked()
end

local function Money()
    local value = GetMoney()
    return S.Finite(value) and value >= 0 and value or nil
end

local function Service(index)
    local name, kind, icon, level = GetTrainerServiceInfo(index)
    kind = S.PublicText(kind)
    if not kind then return nil, false end
    if kind ~= "available" then return nil, true end
    name = S.PublicText(name)
    if not name or not S.Public(icon) or not S.Public(level)
        or icon ~= nil and type(icon) ~= "number" and type(icon) ~= "string" then return nil, false end
    if level ~= nil and not S.Finite(level) then return nil, false end
    local cost, profession = GetTrainerServiceCost(index)
    if not S.Public(cost) or not S.Public(profession) then return nil, false end
    if cost == nil then cost = 0 end
    if not S.Finite(cost) or cost < 0 or cost ~= math.floor(cost) then return nil, false end
    return { index = index, name = name, icon = icon, level = level,
        cost = cost, profession = profession == true }, true
end

local function Same(a, b)
    return a.name == b.name and a.icon == b.icon and a.level == b.level
        and a.cost == b.cost and a.profession == b.profession
end

local function Signature(entry)
    local icon = tostring(entry.icon or "")
    return #entry.name .. ":" .. entry.name .. #icon .. ":" .. icon .. ":"
        .. tostring(entry.level or "") .. ":" .. entry.cost
end

-- Capture only the services already available when the user reviews the
-- total. A newly unlocked service requires a fresh click and confirmation.
local function Plan(self)
    if not TrainerOpen(self) then return nil end
    local count, step, money = GetNumTrainerServices(), GetTrainerServiceStepIndex(), Money()
    if not S.Finite(count) or count < 0 or count > MAX_SERVICES
        or count ~= math.floor(count) or not S.Public(step) or not money then return nil end
    local entries, signatures, total, ambiguous = {}, {}, 0, false
    for index = 1, count do
        local service, safe = Service(index)
        if not safe then return nil end
        if service and not service.profession and index ~= step then
            total = total + service.cost
            if not S.Finite(total) then return nil end
            entries[#entries + 1] = service
            local key = Signature(service)
            if signatures[key] then ambiguous = true end
            signatures[key] = true
        end
    end
    return { entries = entries, total = total, money = money, ambiguous = ambiguous }
end

local function SamePlan(a, b)
    if not a or not b or #a.entries ~= #b.entries or a.total ~= b.total then return false end
    for i = 1, #a.entries do
        if not Same(a.entries[i], b.entries[i]) then return false end
    end
    return true
end

-- Service indices can shift when Blizzard's Available filter is enabled.
-- Match the reviewed service by its public identity and require uniqueness.
local function Find(self, expected)
    if not TrainerOpen(self) then return nil end
    local count = GetNumTrainerServices()
    if not S.Finite(count) or count < 0 or count > MAX_SERVICES
        or count ~= math.floor(count) then return nil end
    local step = GetTrainerServiceStepIndex()
    if not S.Public(step) then return nil end
    local found, matches = nil, 0
    for index = 1, count do
        local service, safe = Service(index)
        if not safe then return nil end
        if service and index ~= step and Same(service, expected) then
            found, matches = index, matches + 1
            if matches > 1 then return nil end
        end
    end
    return found or false
end

local function Stop(self, reason)
    local hadQueue = self.queue ~= nil
    self.queue, self.awaiting, self.purchasing, self.deferred = nil, nil, nil, nil
    self.nextIndex, self.spent, self.approvedTotal = nil, nil, nil
    self.resumeJob:Cancel()
    if hadQueue and reason then NS.Print(S.Text(reason)) end
    self:UpdateButton()
end

local function Advance(self)
    if not self.queue then return end
    if not TrainerOpen(self) then
        Stop(self, "Training stopped because the trainer closed or combat started.")
        return
    end
    if self.awaiting then
        local stillAvailable = Find(self, self.awaiting)
        if stillAvailable == nil then
            Stop(self, "Training stopped because the trainer list changed.")
        elseif stillAvailable == false then
            self.awaiting = nil
        end
        if self.awaiting or not self.queue then return end
    end
    local entry = self.queue[self.nextIndex]
    if not entry then
        local learned, spent = #self.queue, self.spent
        Stop(self)
        NS.Print(string.format(S.Text("Trainer purchase requests finished: %d abilities, up to %s."),
            learned, Coins(spent)))
        return
    end
    local index = Find(self, entry)
    local money = Money()
    if not index or not money or money < entry.cost
        or self.spent + entry.cost > self.approvedTotal then
        Stop(self, "Training stopped because a skill or its cost changed.")
        return
    end
    self.awaiting = entry
    self.nextIndex = self.nextIndex + 1
    self.spent = self.spent + entry.cost
    self.purchasing = true
    -- A purchase call that raises is reported and releases the queue. Never
    -- retry it: the client may have accepted the request anyway.
    local ok = S.Dispatch(NS.Finish, BuyTrainerService, index)
    self.purchasing = false
    if not ok then
        Stop(self, "Training stopped because the purchase call failed.")
        return
    end
    -- A trainer update that arrived inside the purchase call resumes the
    -- queue on the next frame (self.resumeJob); Stop cancels it.
    if self.deferred then
        self.deferred = nil
        self.resumeJob:Request()
    end
    self:UpdateButton()
end

local function Resume(self)
    if self.queue then Advance(self) end
end

local function OnAccept(preview)
    if not M.active or M.queue or type(preview) ~= "table" then return end
    local current = Plan(M)
    if not SamePlan(preview, current) or current.money < current.total
        or #current.entries == 0 then
        NS.Print(S.Text("Trainer list or cost changed; review it again."))
        M:UpdateButton()
        return
    end
    -- No stable spell ID is exposed by the trainer list. Refuse collisions.
    if current.ambiguous then
        NS.Print(S.Text("Trainer has ambiguous skills; train them individually."))
        return
    end
    M.queue, M.approvedTotal, M.nextIndex, M.spent = current.entries, current.total, 1, 0
    M.resumeJob:Cancel()
    Advance(M)
end

local function OnClick()
    if M.queue then
        Stop(M, "Training stopped.")
        return
    end
    local plan = Plan(M)
    if not plan or #plan.entries == 0 or plan.total > plan.money or plan.ambiguous then return end
    -- Blizzard's generic confirmation (S.Confirm, MSUF_Suite_Modules/Dialogs.lua).
    S.Confirm(POPUP, {
        text = S.Text("Learn %d available abilities for %s? Profession choices and rank steps are excluded."),
        text_arg1 = #plan.entries, text_arg2 = Coins(plan.total),
        acceptText = S.BlizzardText("ACCEPT", "Accept"), cancelText = S.BlizzardText("CANCEL", "Cancel"),
        showAlert = true,
        callback = function() OnAccept(plan) end,
    })
end

-- OnLeave hides the shared tooltip only while this frame still owns it.
local function LeaveTooltip(owner)
    if GameTooltip:IsOwned(owner) then GameTooltip:Hide() end
end

local function OnEnter(button)
    if NS.Safety.IsForbidden(_G.GameTooltip) then return end
    GameTooltip:SetOwner(button, "ANCHOR_RIGHT")
    GameTooltip:SetText(S.Text("Learn available abilities"))
    if M.queue then
        GameTooltip:AddLine(S.Text("Click to stop after the current purchase."), .8, .85, .9, true)
    else
        local plan = Plan(M)
        if plan and #plan.entries > 0 then
            GameTooltip:AddLine(string.format(S.Text("%d abilities, total %s"),
                #plan.entries, Coins(plan.total)), 1, .88, .6)
            if plan.total > plan.money then
                GameTooltip:AddLine(S.Text("Not enough gold for all available abilities."), 1, .45, .4, true)
            elseif plan.ambiguous then
                GameTooltip:AddLine(S.Text("Some services cannot be distinguished; train them individually."),
                    1, .45, .4, true)
            end
        end
        GameTooltip:AddLine(S.Text("Profession choices and rank steps are excluded. Review the cost before training."),
            .78, .83, .9, true)
    end
    GameTooltip:Show()
end

local function Attach(self)
    local frame = _G.ClassTrainerFrame
    if not frame or NS.Safety.IsForbidden(frame) then return end
    if self.button then return end
    if NS.IsCombatLocked() then
        self.context:Event("PLAYER_REGEN_ENABLED", Attach, IN_COMBAT)
        return
    end
    self.context:RemoveEvent("PLAYER_REGEN_ENABLED")
    -- Parented after creation: on WoW Forever's Gamepad UI the open trainer
    -- is a panel SmartNavigation rescans from a CreateFrame post-hook in the
    -- caller's execution (SmartNavigation.lua SetupFrameHooks, UpdateParent).
    local button = S.CreateFrame("Button", nil, nil, "UIPanelButtonTemplate")
    button:SetParent(frame)
    button:SetSize(125, 22)
    button:SetPoint("RIGHT", ClassTrainerTrainButton, "LEFT", -8, 0)
    button:SetFrameLevel(frame:GetFrameLevel() + 10)
    button:SetText(S.Text("Learn all"))
    button:SetScript("OnClick", OnClick)
    button:SetScript("OnEnter", OnEnter)
    button:SetScript("OnLeave", LeaveTooltip)
    frame:HookScript("OnShow", function() if M.active then M:UpdateButton() end end)
    frame:HookScript("OnHide", function()
        if M.queue then Stop(M, "Training stopped because the trainer closed.") end
        button:Hide()
    end)
    self.button = button
    self:UpdateButton()
end

function M:UpdateButton()
    if not self.button then return end
    if not TrainerOpen(self) then
        self.button:Hide()
        return
    end
    self.button:Show()
    if self.queue then
        self.button:SetText(S.Text("Stop training"))
        self.button:SetEnabled(true)
        return
    end
    local plan = Plan(self)
    self.button:SetText(S.Text("Learn all"))
    self.button:SetEnabled(plan and #plan.entries > 0 and plan.total <= plan.money
        and not plan.ambiguous or false)
end

local function OnLoaded(self, _, addon)
    if addon == "Blizzard_TrainerUI" then Attach(self) end
end

local function OnTrainer(self, event)
    if event == "TRAINER_CLOSED" then
        if self.queue then Stop(self, "Training stopped because the trainer closed.") end
        if self.button then self.button:Hide() end
        return
    end
    Attach(self)
    if self.purchasing then
        self.deferred = true
        return
    end
    if self.queue then Advance(self) else self:UpdateButton() end
end

local function AfterCombat(self)
    self.context:RemoveEvent("PLAYER_REGEN_ENABLED")
    self:UpdateButton()
end

-- PLAYER_REGEN_DISABLED arrives before InCombatLockdown() turns true, so
-- TrainerOpen still answers open here: the button hides for the fight.
local function OnCombat(self)
    if self.queue then Stop(self, "Training stopped because combat started.") end
    if self.button then
        self.button:Hide()
        self.context:Event("PLAYER_REGEN_ENABLED", AfterCombat, IN_COMBAT)
    end
end

function M:Enable()
    self.resumeJob = self.context:Coalesce(0, Resume)
    self.context:Event("ADDON_LOADED", OnLoaded, IN_COMBAT)
    self.context:Event("TRAINER_SHOW", OnTrainer, IN_COMBAT)
    self.context:Event("TRAINER_UPDATE", OnTrainer, IN_COMBAT)
    self.context:Event("TRAINER_CLOSED", OnTrainer, IN_COMBAT)
    self.context:Event("PLAYER_REGEN_DISABLED", OnCombat, IN_COMBAT)
    Attach(self)
end

function M:Refresh()
    Attach(self)
    self:UpdateButton()
end

function M:Disable()
    if self.queue then Stop(self) end
    if self.button then self.button:Hide() end
    S.HideQuestion(POPUP)
end

S.Install("trainerLearnAll", M)

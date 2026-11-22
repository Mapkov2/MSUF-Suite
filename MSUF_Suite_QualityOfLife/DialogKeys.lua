local _, P = ...
local NS, S = P.NS, P.Suite
local Keys = { proxies = {}, labels = {} }
local CONTINUE = "MSUFSuiteQuestContinue"
local CHOICES = 10
local EVENTS = { "GOSSIP_SHOW", "GOSSIP_CLOSED", "QUEST_DETAIL", "QUEST_PROGRESS", "QUEST_COMPLETE",
    "QUEST_FINISHED", "QUEST_GREETING", "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED", "UPDATE_BINDINGS" }
local IN_COMBAT = { inCombat = true }

local function Visible(frame)
    if not frame or NS.Safety.IsForbidden(frame) then return false end
    local shown = frame:IsVisible()
    return S.Public(shown) and shown == true
end

local function Clickable(button)
    if not Visible(button) then return false end
    local enabled = button:IsEnabled()
    return S.Public(enabled) and enabled == true
end

local function Proxy(self, slot)
    local proxy = self.proxies[slot]
    if proxy then return proxy end
    local name = slot == 0 and CONTINUE or "MSUFSuiteQuestOption" .. slot
    proxy = S.CreateFrame("Button", name, self.owner, "SecureActionButtonTemplate")
    proxy:RegisterForClicks("AnyUp")
    proxy:SetAttribute("useOnKeyDown", false)
    proxy:SetAttribute("type1", "click")
    SecureHandlerWrapScript(proxy, "OnClick", self.owner, [[
        local target = self:GetFrameRef("dialogTarget")
        if not control:IsVisible() or not target or not target:IsVisible() then return false end
    ]])
    self.proxies[slot] = proxy
    return proxy
end

local function Clear(self)
    for _, label in pairs(self.labels) do label:Hide() end
    if not self.owner or not self.bound or NS.IsCombatLocked() then return end
    self.bound = nil
    ClearOverrideBindings(self.owner)
    for _, proxy in pairs(self.proxies) do proxy:SetAttribute("clickbutton1", nil) end
end

local function Ordered(rows, button)
    if not Clickable(button) then return end
    local top = button:GetTop()
    if not S.Finite(top) then return end
    local left = button:GetLeft()
    if not S.Finite(left) then return end
    rows[#rows + 1] = { button = button, top = top, left = left }
end

local function TopFirst(a, b)
    if a.top ~= b.top then return a.top > b.top end
    return a.left < b.left
end

local function GossipRows(scroll)
    local rows = {}
    if not scroll then return rows end
    scroll:ForEachFrame(function(button, data)
        if S.Public(data) and type(data) == "table" and canaccesstable(data)
            and S.Finite(data.index) and S.Public(data.buttonType) and S.Public(data.info)
            and data.info ~= nil and button:IsObjectType("Button") then
            Ordered(rows, button)
        end
    end)
    table.sort(rows, TopFirst)
    return rows
end

local function GreetingRows(panel)
    local rows, pool = {}, panel.titleButtonPool
    if not pool then return rows end
    for button in pool:EnumerateActive() do Ordered(rows, button) end
    table.sort(rows, TopFirst)
    return rows
end

local function RewardRows()
    local rows = {}
    local rewards = NS.Safety.Field(QuestInfoRewardsFrame, "RewardButtons")
    if not S.Public(rewards) or type(rewards) ~= "table" or not canaccesstable(rewards) then return rows end
    for _, button in ipairs(rewards) do
        local kind = button.type
        if S.Public(kind) and kind == "choice" then Ordered(rows, button) end
    end
    table.sort(rows, TopFirst)
    return rows
end

local function Targets(self)
    if Visible(QuestFrame) then
        if Visible(QuestFrameRewardPanel) then
            local n = GetNumQuestChoices()
            if not S.Finite(n) then return end
            local selected = NS.Safety.Field(QuestInfoFrame, "itemChoice")
            if n <= 1 then return QuestFrameCompleteQuestButton end
            local primary = S.Finite(selected) and selected >= 1 and selected <= n and QuestFrameCompleteQuestButton
            return primary, RewardRows()
        end
        if Visible(QuestFrameProgressPanel) then return QuestFrameCompleteButton end
        if Visible(QuestFrameDetailPanel) then return QuestFrameAcceptButton end
        if Visible(QuestFrameGreetingPanel) then
            local rows = GreetingRows(QuestFrameGreetingPanel)
            return rows[1] and rows[1].button, rows
        end
    end
    if Visible(GossipFrame) then
        local rows = GossipRows(self.scroll)
        return rows[1] and rows[1].button, rows
    end
end

local function Number(self, slot, button)
    local label = self.labels[slot]
    if not label then
        label = S.CreateFontString(self.owner, nil, "OVERLAY", "GameFontNormalSmall")
        self.labels[slot] = label
    end
    label:ClearAllPoints()
    label:SetPoint("TOPRIGHT", button, "TOPRIGHT", -3, -2)
    label:SetText(tostring(slot % CHOICES))
    label:Show()
end

local function Bind(self, slot, button, key)
    if not Clickable(button) then return end
    local proxy = Proxy(self, slot)
    proxy:SetAttribute("clickbutton1", button)
    SecureHandlerSetFrameRef(proxy, "dialogTarget", button)
    self.bound = true
    if key then SetOverrideBindingClick(self.owner, true, key, proxy:GetName(), "LeftButton") end
end

local function Route(self)
    Clear(self)
    if not self.active or NS.InCombat() or S.GamepadUI() or not self.owner:IsVisible() then return end
    local focus = GetCurrentKeyBoardFocus()
    if not S.Public(focus) or focus ~= nil then return end
    local primary, rows = Targets(self)
    local first, second = GetBindingKey("CLICK " .. CONTINUE .. ":LeftButton")
    local space = not S.PublicText(first) and not S.PublicText(second) and self.config.useSpace
    Bind(self, 0, primary, space and "SPACE" or nil)
    if not rows or not self.config.numberChoices then return end
    for i = 1, math.min(#rows, CHOICES) do
        local button = rows[i].button
        Bind(self, i, button, tostring(i % CHOICES))
        Number(self, i, button)
    end
end

local function Rebuild(self)
    if self.rebuilding then return end
    self.rebuilding = true
    Route(self)
    self.rebuilding = nil
end

local function Changed(self, event)
    if self.rebuilding then return end
    if event == "PLAYER_REGEN_DISABLED" then Clear(self) return end
    Rebuild(self)
    self.context:After(0, Rebuild)
end

function Keys:Enable()
    if not self.owner then
        local owner = S.CreateFrame("Frame", nil, UIParent, "SecureHandlerStateTemplate")
        owner:SetFrameStrata("TOOLTIP")
        owner:SetAttribute("_onstate-msufdialog", [[if newstate == "blocked" then self:ClearBindings() end]])
        self.owner = owner
        RegisterStateDriver(owner, "msufdialog", "[combat][petbattle][vehicleui] blocked; normal")
        RegisterStateDriver(owner, "visibility", "[combat][petbattle][vehicleui] hide; show")
    end
    if not self.hooked then
        local function Refresh() if self.active then Changed(self) end end
        local function Closed() if self.active then Clear(self) end end
        for _, panel in ipairs({ QuestFrame, GossipFrame }) do
            panel:HookScript("OnShow", Refresh)
            panel:HookScript("OnHide", Closed)
        end
        hooksecurefunc("QuestInfo_Display", Refresh)
        hooksecurefunc("QuestInfoItem_OnClick", Refresh)
        hooksecurefunc("ChatEdit_ActivateChat", Closed)
        hooksecurefunc("ChatEdit_DeactivateChat", Refresh)
        local panel = NS.Safety.Field(GossipFrame, "GreetingPanel")
        self.scroll = panel and panel.ScrollBox
        self.hooked = true
    end
    if self.scroll then
        self.scroll:RegisterCallback(ScrollBoxListMixin.Event.OnUpdate, function() Changed(self) end, self)
    end
    for _, event in ipairs(EVENTS) do self.context:Event(event, Changed, IN_COMBAT) end
    if NS.Client.isForever then self.context:Event("INPUT_DEVICE_INTERFACE_TRANSITION", Changed, IN_COMBAT) end
    self:Refresh()
end

function Keys:Refresh() Changed(self) end

function Keys:Disable()
    Clear(self)
    if self.scroll then self.scroll:UnregisterCallback(ScrollBoxListMixin.Event.OnUpdate, self) end
end

S.Install("dialogKeys", Keys)

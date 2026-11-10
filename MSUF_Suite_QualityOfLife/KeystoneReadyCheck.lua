local _, P = ...
local NS, S = P.NS, P.Suite
if NS.Client.isForever then return end

local M = {}
local Refresh, Open
local IN_COMBAT = { inCombat = true }
local EVENTS = {
    "GROUP_ROSTER_UPDATE", "PARTY_LEADER_CHANGED", "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED",
    "READY_CHECK", "READY_CHECK_FINISHED", "CHALLENGE_MODE_START", "START_PLAYER_COUNTDOWN", "CANCEL_PLAYER_COUNTDOWN",
}

local function Permitted()
    local group, leader, assistant = IsInGroup(), UnitIsGroupLeader("player"), UnitIsGroupAssistant("player")
    return S.Public(group) and group == true and S.Public(leader) and S.Public(assistant)
        and (leader == true or assistant == true)
end

local function Restricted(event)
    return NS.InCombat(event) or NS.GroupActionsRestricted()
end

local function ClearCountdown(self)
    self.endsAt, self.lastSecond, self.elapsed = nil, nil, nil
    if self.panel then self.panel:SetScript("OnUpdate", nil) end
end

local function NativeCountdown(seconds)
    local success
    local called = S.QoLRestrictedCall(function() success = C_PartyInfo.DoCountdown(seconds) end)
    return called and S.Public(success) and success == true
end

local function Stop(self, event)
    if self.endsAt and Permitted() and not Restricted(event) then NativeCountdown(0) end
    ClearCountdown(self)
end

local function Paint(self, event)
    if not self.panel then return end
    local permitted = self.active and Permitted() and not Restricted(event)
    self.ready:SetEnabled(permitted and not self.readyRunning)
    self.pull:SetEnabled(permitted)
    self.ready:SetText(S.Text(self.readyRunning and "Ready check in progress" or "Ready check"))
    if self.endsAt then
        local now = GetTime()
        local second = S.Finite(now) and math.max(0, math.ceil(self.endsAt - now)) or 0
        if second ~= self.lastSecond then
            self.lastSecond = second
            self.pull:SetText(string.format(S.Text("Cancel countdown (%d)"), second))
        end
    else
        self.pull:SetText(string.format(S.Text("Countdown (%d s)"), self.config.countdownSeconds))
    end
end

local function Tick(_, elapsed)
    M.elapsed = (M.elapsed or 0) + elapsed
    if M.elapsed < .1 then return end
    M.elapsed = 0
    local now = GetTime()
    if not M.active or not Permitted() or Restricted() then
        Stop(M)
    elseif not S.Finite(now) or now >= M.endsAt then
        ClearCountdown(M)
    end
    Paint(M)
end

local function CanClick(self)
    if not self.active or not self.panel:IsShown() then return false end
    if not Permitted() then
        S.Print(S.Text("Group leader or assistant required"))
        return false
    end
    if Restricted() then
        S.Print(NS.RestrictedNotice())
        return false
    end
    return true
end

local function ReadyClick()
    if not CanClick(M) or M.readyRunning then return end
    if not S.QoLRestrictedCall(C_PartyInfo.DoReadyCheck) then S.Print(NS.RestrictedNotice()) end
end

local function PullClick(_, button)
    if not CanClick(M) then return end
    if M.endsAt then
        Stop(M)
    else
        local seconds = button == "RightButton" and M.config.shortCountdownSeconds or M.config.countdownSeconds
        local now = GetTime()
        if not S.Finite(seconds) or seconds < 1 or seconds > 60 or not S.Finite(now) then return end
        if not NativeCountdown(seconds) then
            S.Print(S.Text("Countdown could not be started"))
            return
        end
        M.endsAt, M.elapsed = now + seconds, 0
        M.panel:SetScript("OnUpdate", Tick)
    end
    Paint(M)
end

local function Button(self, x, action)
    local button = S.CreateFrame("Button", nil, self.panel, "UIPanelButtonTemplate")
    button:SetSize(166, 26)
    button:SetPoint("LEFT", self.panel, "LEFT", x, 0)
    button:SetScript("OnClick", action)
    button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    S.SetStyledFont(button:GetFontString(), S.GlobalFontPath(), 12, "OUTLINE", 1, true, 70, 1)
    return button
end

local function Create(self)
    -- Blizzard live 297d7aaa: ChallengesUI owns the native StartButton and
    -- frame reset. Keep our controls on a separate child, below the window.
    self.panel = S.CreateFrame("Frame", nil, self.parent)
    self.panel:SetSize(354, 44)
    self.panel:SetPoint("TOP", self.parent, "BOTTOM", 0, -4)
    local fill = S.CreateTexture(self.panel, nil, "BACKGROUND")
    fill:SetAllPoints(self.panel)
    fill:SetColorTexture(.04, .05, .07, .96)
    self.ready, self.pull = Button(self, 8, ReadyClick), Button(self, 180, PullClick)
    self.panel:Hide()
end

local function Style(self)
    local skin = self.context:Skin()
    if skin then
        skin:SkinFrame(self.panel)
        skin:SkinButton(self.ready)
        skin:SkinButton(self.pull)
    end
end

local function Close(self)
    Stop(self)
    self.readyRunning = nil
    if self.panel then self.panel:Hide() end
    for _, event in ipairs(EVENTS) do self.context:RemoveEvent(event) end
end

Refresh = function(self, event)
    if event == "READY_CHECK" then self.readyRunning = true end
    if event == "READY_CHECK_FINISHED" then self.readyRunning = nil end
    -- WorldStateInfo's events are synchronous: our own start fires before
    -- endsAt is set. A later start or cancellation supersedes our countdown.
    -- Payloads may be secret; only the event itself is needed here.
    if event == "START_PLAYER_COUNTDOWN" or event == "CANCEL_PLAYER_COUNTDOWN" then ClearCountdown(self) end
    if event == "CHALLENGE_MODE_START" then Close(self) return end
    if self.endsAt and (not Permitted() or Restricted(event)) then Stop(self, event) end
    Paint(self, event)
end

local function Resume(self)
    if self.parent:IsShown() then Open(self) else self.context:RemoveEvent("PLAYER_REGEN_ENABLED") end
end

Open = function(self)
    if not self.active then return end
    if Restricted() then
        self.context:Event("PLAYER_REGEN_ENABLED", Resume, IN_COMBAT)
        return
    end
    if not self.panel then Create(self) end
    Style(self)
    local remaining = GetReadyCheckTimeLeft()
    self.readyRunning = S.Finite(remaining) and remaining > 0
    for _, event in ipairs(EVENTS) do self.context:Event(event, Refresh, IN_COMBAT) end
    self.panel:Show()
    Paint(self)
end

local function Hook(self)
    if self.parent then
        self.context:RemoveEvent("ADDON_LOADED")
        return
    end
    local parent = _G.ChallengesKeystoneFrame
    if not parent then return end
    self.parent = parent
    parent:HookScript("OnShow", function() Open(self) end)
    parent:HookScript("OnHide", function() Close(self) end)
    self.context:RemoveEvent("ADDON_LOADED")
    if parent:IsShown() then Open(self) end
end

function M:Enable()
    self.context:Event("ADDON_LOADED", Hook)
    Hook(self)
    if self.parent and self.parent:IsShown() then Open(self) end
end

function M:Refresh()
    if not self.parent then return end
    Stop(self)
    if self.parent:IsShown() then Open(self) end
end

function M:Disable()
    Close(self)
    self.context:RemoveEvent("ADDON_LOADED")
end

S.Install("keystoneReadyCheck", M)

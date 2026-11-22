local _, P = ...
local NS, S = P.NS, P.Suite
if NS.Client.isForever then return end
local Guard = {}
local IN_COMBAT = { inCombat = true }

local function HideTooltip(overlay)
    if GameTooltip:IsOwned(overlay) then GameTooltip:Hide() end
end

local function Overlay(parent, button, label)
    local overlay = S.CreateFrame("Button", nil, parent, "SecureActionButtonTemplate")
    overlay:EnableMouse(true)
    overlay:SetAllPoints(button)
    overlay:SetFrameLevel(button:GetFrameLevel() + 1)
    overlay:RegisterForClicks("AnyUp")
    overlay:SetAttribute("useOnKeyDown", false)
    overlay:SetAttribute("shift-type1", "click")
    overlay:SetAttribute("shift-clickbutton1", button)
    overlay:SetScript("OnEnter", function(frame)
        GameTooltip:SetOwner(frame, "ANCHOR_RIGHT")
        GameTooltip:SetText(label)
        GameTooltip:Show()
    end)
    overlay:SetScript("OnLeave", HideTooltip)
    overlay:SetScript("OnHide", HideTooltip)
    return overlay
end

local function Setup(self, prompt)
    local host = S.CreateFrame("Frame", nil, UIParent, "SecureHandlerStateTemplate")
    host:SetFrameStrata(prompt:GetFrameStrata())
    host:SetFrameLevel(prompt:GetFrameLevel() + 1)
    local container = S.CreateFrame("Frame", nil, host)
    container:SetAllPoints(prompt)
    self.host, self.container = host, container
    self.rollOverlay = Overlay(container, prompt.RollButton, ROLL)
    self.passOverlay = Overlay(container, prompt.PassButton, PASS)
    local text = S.CreateFontString(container, nil, "OVERLAY", "GameFontNormalSmall")
    text:SetPoint("TOP", prompt, "BOTTOM", 0, -5)
    text:SetText(S.Text("Hold Shift to confirm a bonus roll or pass"))
    text:SetTextColor(1, .82, 0)
    RegisterStateDriver(host, "visibility", "[combat][petbattle][vehicleui] hide; show")
end

local function Enabled(button)
    local visible, enabled = button:IsVisible(), button:IsEnabled()
    return S.Public(visible) and visible == true and S.Public(enabled) and enabled == true
end

local function Update(self, event)
    if NS.InCombat(event) then return end
    local prompt = NS.Safety.Field(BonusRollFrame, "PromptFrame")
    local visible = prompt and prompt:IsVisible()
    if not self.active or not S.Public(visible) or visible ~= true then
        if self.container then self.container:Hide() end
        return
    end
    if not (prompt.RollButton and prompt.PassButton) then return end
    if not self.container then Setup(self, prompt) end
    local roll, pass = Enabled(prompt.RollButton), Enabled(prompt.PassButton)
    self.rollOverlay:SetShown(roll)
    self.passOverlay:SetShown(pass)
    self.container:SetShown(roll or pass)
end

function Guard:Enable()
    local prompt = NS.Safety.Field(BonusRollFrame, "PromptFrame")
    if not self.hooked and prompt then
        local function Refresh() Update(self) end
        prompt:HookScript("OnShow", Refresh)
        prompt:HookScript("OnHide", Refresh)
        hooksecurefunc("BonusRollFrame_StartBonusRoll", Refresh)
        hooksecurefunc("BonusRollFrame_CloseBonusRoll", Refresh)
        self.hooked = true
    end
    self.context:Event("PLAYER_REGEN_ENABLED", Update, IN_COMBAT)
    self.context:Event("PLAYER_ENTERING_WORLD", Update)
    self:Refresh()
end

function Guard:Refresh() Update(self) end

function Guard:Disable()
    if not self.container then return end
    if not NS.InCombat() then
        self.container:Hide()
        return
    end
    if not self.cleanup then
        local cleanup = S.CreateFrame("Frame")
        cleanup:SetScript("OnEvent", function(frame)
            frame:UnregisterEvent("PLAYER_REGEN_ENABLED")
            if not self.active then self.container:Hide() end
        end)
        self.cleanup = cleanup
    end
    self.cleanup:RegisterEvent("PLAYER_REGEN_ENABLED")
end

S.Install("bonusRollConfirm", Guard)

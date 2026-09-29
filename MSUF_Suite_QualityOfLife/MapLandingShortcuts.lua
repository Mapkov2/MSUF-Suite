local _, P = ...
local NS, S = P.NS, P.Suite
local M = {}

-- Blizzard owns the landing button and its click script (which does not
-- distinguish mouse buttons). This small adjacent button opens a separate
-- native context menu and never changes or intercepts Blizzard's handler.
local function Wanted(c)
    return c.showLandingPage or c.showVault or c.showJournal or c.showMap
end

local function CanJournal()
    if type(_G.ToggleEncounterJournal) ~= "function" then return false end
    if type(_G.CanShowEncounterJournal) ~= "function" then return true end
    local allowed = CanShowEncounterJournal()
    return S.Public(allowed) and allowed == true
end

local function CanVault()
    -- The Great Vault bootstrap is LoadOnDemand; its opener may not exist yet.
    return type(_G.WeeklyRewards_ShowUI) == "function"
end

local function OpenMenu(button)
    MenuUtil.CreateContextMenu(button, function(_, root)
        root:CreateTitle(S.Text("Expansion shortcuts"))
        local locked = NS.IsCombatLocked()
        local c = M.config
        if c.showLandingPage then
            local entry = root:CreateButton(S.Text("Expansion landing page"), function()
                if not NS.IsCombatLocked() and M.native then M.native:ToggleLandingPage() end
            end)
            entry:SetEnabled(not locked and M.native ~= nil)
        end
        if c.showVault then
            local entry = root:CreateButton(S.Text("Great Vault"), function()
                if not NS.IsCombatLocked() and CanVault() then WeeklyRewards_ShowUI() end
            end)
            entry:SetEnabled(not locked and CanVault())
        end
        if c.showJournal then
            local entry = root:CreateButton(S.Text("Adventure Guide"), function()
                if not NS.IsCombatLocked() and CanJournal() then ToggleEncounterJournal() end
            end)
            entry:SetEnabled(not locked and CanJournal())
        end
        if c.showMap then
            local entry = root:CreateButton(S.Text("World map"), function()
                if not NS.IsCombatLocked() then ToggleWorldMap() end
            end)
            entry:SetEnabled(not locked)
        end
    end)
end

local function Create(self)
    if self.button then return end
    local button = S.CreateFrame("Button", nil, UIParent)
    button:SetFrameStrata("HIGH")
    button:RegisterForClicks("AnyUp")
    button:EnableMouse(true)
    local panel = S.CreateTexture(button, nil, "BACKGROUND")
    panel:SetAllPoints()
    panel:SetColorTexture(.08, .1, .13, .95)
    local border = S.CreateTexture(button, nil, "BORDER")
    border:SetPoint("TOPLEFT")
    border:SetPoint("BOTTOMLEFT")
    border:SetWidth(2)
    border:SetColorTexture(.81, .66, .38)
    local glyph = S.CreateFontString(button, nil, "OVERLAY")
    glyph:SetPoint("CENTER", 0, 1)
    S.SetFont(glyph, nil, 13, "OUTLINE")
    glyph:SetText("...")
    glyph:SetTextColor(1, .88, .63)
    button:SetScript("OnClick", OpenMenu)
    button:SetScript("OnEnter", function(owner)
        GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
        GameTooltip:SetText(S.Text("Expansion shortcuts"))
        GameTooltip:Show()
    end)
    button:SetScript("OnLeave", function() GameTooltip:Hide() end)
    button:Hide()
    self.button, self.panel, self.border, self.glyph = button, panel, border, glyph
end

local function Update(self)
    if not self.button or not self.native or not Wanted(self.config) then
        if self.button then self.button:Hide() end
        return
    end
    local visible = self.native:IsVisible()
    if not S.Public(visible) or not visible then self.button:Hide() return end
    local c = self.config
    local style = S.QoLStyle(c)
    S.QoLColor(self.panel, style.background, .95)
    S.QoLColor(self.border, style.accent)
    self.glyph:SetTextColor(S.RGB(style.accent))
    self.button:SetSize(c.size, c.size)
    self.button:ClearAllPoints()
    self.button:SetPoint("TOPLEFT", self.native, "BOTTOMRIGHT", c.offsetX, c.offsetY)
    self.button:Show()
end

local function Attach(self)
    if NS.IsCombatLocked() then
        self.context:Event("PLAYER_REGEN_ENABLED", Attach, true)
        return
    end
    self.context:RemoveEvent("PLAYER_REGEN_ENABLED")
    local native = _G.ExpansionLandingPageMinimapButton
    if not native or NS.Safety.IsForbidden(native) then
        if self.button then self.button:Hide() end
        return
    end
    Create(self)
    if self.native ~= native then
        self.native = native
        native:HookScript("OnShow", function() if M.active then Update(M) end end)
        native:HookScript("OnHide", function() if M.button then M.button:Hide() end end)
    end
    self.context:RemoveEvent("ADDON_LOADED")
    Update(self)
end

local function OnLoaded(self)
    -- The landing button can be created by different LoadOnDemand addons
    -- across client builds. ADDON_LOADED is removed as soon as it exists.
    if _G.ExpansionLandingPageMinimapButton then Attach(self) end
end

function M:Enable()
    self.context:Event("PLAYER_ENTERING_WORLD", Attach, true)
    self.context:Event("ADDON_LOADED", OnLoaded, true)
    Attach(self)
end

function M:Refresh()
    Attach(self)
end

function M:Disable()
    if self.button then self.button:Hide() end
end

S.Install("mapLandingShortcuts", M)

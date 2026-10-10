local _, P = ...
local NS, S = P.NS, P.Suite
local IN_COMBAT = { inCombat = true }
local M = {}
local ID = "mapLandingShortcuts"
-- The button beside Blizzard's landing button; Refresh sizes it.
local CARD = { kind = "Button", mouse = true, fill = { .08, .1, .13, .95 }, stripe = 2, line = { .81, .66, .38 } }

-- Blizzard owns the landing button and its click script (which does not
-- distinguish mouse buttons). This small adjacent button opens a separate
-- native context menu and never changes or intercepts Blizzard's handler.
local function Wanted(c)
    return c.showLandingPage or c.showVault or c.showJournal or c.showMap
end

-- The Great Vault and Adventure Guide openers live in [Bootstrap] files of
-- their load-on-demand addons, which the Retail client loads at login.
-- Blizzard's Lua runs through Dispatch, so an error there stays its own.
local function CanJournal()
    local ok, allowed = S.Dispatch(NS.Finish, CanShowEncounterJournal)
    return ok == true and S.Public(allowed) and allowed == true
end

local function Run(callback, ...)
    if not NS.IsCombatLocked() then S.Dispatch(NS.Finish, callback, ...) end
end

-- Blizzard's context menu (S.ContextMenu, MSUF_Suite_Modules/Dialogs.lua).
local function OpenMenu(button)
    S.ContextMenu(button, function(_, root)
        root:CreateTitle(S.Text("Expansion shortcuts"))
        local locked = NS.IsCombatLocked()
        local c = M.config
        if c.showLandingPage then
            local entry = root:CreateButton(S.Text("Expansion landing page"), function()
                if M.native then Run(M.native.ToggleLandingPage, M.native) end
            end)
            entry:SetEnabled(not locked and M.native ~= nil)
        end
        if c.showVault then
            local entry = root:CreateButton(S.Text("Great Vault"), function()
                Run(WeeklyRewards_ShowUI)
            end)
            entry:SetEnabled(not locked)
        end
        if c.showJournal then
            local entry = root:CreateButton(S.Text("Adventure Guide"), function()
                if CanJournal() then Run(ToggleEncounterJournal) end
            end)
            entry:SetEnabled(not locked and CanJournal())
        end
        if c.showMap then
            local entry = root:CreateButton(S.Text("World map"), function()
                Run(ToggleWorldMap)
            end)
            entry:SetEnabled(not locked)
        end
    end)
end

-- OnLeave hides the shared tooltip only while this frame still owns it.
local function LeaveTooltip(owner)
    if GameTooltip:IsOwned(owner) then GameTooltip:Hide() end
end

local function Create(self)
    if self.button then return end
    local button, panel, border = S.QoLCard(CARD)
    button:RegisterForClicks("AnyUp")
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
    button:SetScript("OnLeave", LeaveTooltip)
    button:Hide()
    self.button, self.panel, self.border, self.glyph = button, panel, border, glyph
end

local function Update(self)
    if not self.button or not self.native or not Wanted(self.config) then
        if self.button then self.button:Hide() end
        return
    end
    local visible = self.native:IsVisible()
    if not S.Public(visible) or not visible then
        self.button:Hide()
        return
    end
    local c = self.config
    local style = S.PaintQoLCard(ID, c, self.panel)
    S.QoLColor(self.border, style.accent)
    self.glyph:SetTextColor(S.RGB(style.accent))
    self.button:SetSize(c.size, c.size)
    self.button:ClearAllPoints()
    self.button:SetPoint("TOPLEFT", self.native, "BOTTOMRIGHT", c.offsetX, c.offsetY)
    self.button:Show()
end

local function Attach(self)
    if NS.IsCombatLocked() then
        self.context:Event("PLAYER_REGEN_ENABLED", Attach, IN_COMBAT)
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
    self.context:Event("PLAYER_ENTERING_WORLD", Attach, IN_COMBAT)
    self.context:Event("ADDON_LOADED", OnLoaded, IN_COMBAT)
    Attach(self)
end

function M:Refresh()
    Attach(self)
end

function M:Disable()
    if self.button then self.button:Hide() end
end

S.Install(ID, M)

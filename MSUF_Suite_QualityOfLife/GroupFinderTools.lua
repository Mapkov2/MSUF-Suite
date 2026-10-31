local _, P = ...
local NS, S = P.NS, P.Suite
if NS.Client.isForever then return end
local Stats, Filters = P.GroupFinderStatistics, P.GroupFinderFilters
local M = { CanApplyFilters = Filters.Eligible, ApplyFilters = Filters.Apply }
local ID, IN_COMBAT = "groupFinderTools", { inCombat = true }
local function Text(parent, size)
    local text = S.CreateFontString(parent, nil, "OVERLAY")
    S.SetFont(text, nil, size, "")
    text:SetJustifyH("LEFT")
    return text
end
local function Draw()
    if not M.frame then return end
    S.QoLColor(M.back, S.QoLStyle(M.config).background, .96)
    if not M.active or not LFGListFrame.SearchPanel:IsVisible() then M.frame:Hide()
    return end
    M.filters:SetShown(M.config.filters)
    local eligible = Filters.Eligible()
    M.filters:SetEnabled(eligible)
    M.reason:SetShown(M.config.filters and not eligible)
    if M.config.filters and not eligible then
        M.reason:ClearAllPoints()
        M.reason:SetPoint("TOPLEFT", 8, M.config.statistics and -160 or -62)
    end
    M.scope:SetShown(M.config.statistics)
    M.reset:SetShown(M.config.statistics)
    M.lines:SetText(M.config.statistics and Stats.Lines(M.config.scope) or "")
    M.frame:SetHeight((M.config.statistics and 205 or 62) + (M.config.filters and not eligible and 48 or 0))
    M.frame:SetShown(M.config.filters or M.config.statistics)
end
local function Button(parent, title, x, action)
    local button = S.CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    button:SetSize(104, 24)
    button:SetPoint("TOPLEFT", x, -29)
    button:SetText(S.Text(title))
    button:SetScript("OnClick", action)
    return button
end
local function CycleScope()
    if M.active and not NS.InCombat() then S.Set(ID, "scope", M.config.scope % 3 + 1) end
end
local function Reset()
    if not M.active or NS.InCombat() then return end
    local scope, profile = M.config.scope, NS.DB
    S.Confirm("suite-application-statistics", S.Text("Reset the selected application statistics?"), function()
        if M.active and NS.DB == profile and M.config.scope == scope then Stats.Reset(scope)
        Draw() end
    end)
end
local function Build()
    if M.frame or not _G.LFGListFrame then return end
    local frame = S.CreateFrame("Frame", nil, LFGListFrame.SearchPanel)
    frame:SetPoint("TOPLEFT", LFGListFrame, "TOPRIGHT", 8, -26)
    frame:SetSize(252, 205)
    local back = S.CreateTexture(frame, nil, "BACKGROUND")
    back:SetAllPoints(frame)
    back:SetColorTexture(.04, .05, .07, .96)
    M.back = back
    M.frame = frame
    local title = Text(frame, 12)
    title:SetPoint("TOPLEFT", 8, -8)
    title:SetText(S.Text("Group finder filters and statistics"))
    M.filters = Button(frame, "Search filters", 8, Filters.Menu)
    M.scope = Button(frame, "Statistics scope", 120, CycleScope)
    M.lines = Text(frame, 11)
    M.lines:SetPoint("TOPLEFT", 8, -62)
    M.lines:SetPoint("TOPRIGHT", -8, -62)
    M.lines:SetWordWrap(true)
    M.reason = Text(frame, 11)
    M.reason:SetPoint("BOTTOMLEFT", 8, 35)
    M.reason:SetSize(236, 42)
    M.reason:SetWordWrap(true)
    M.reason:SetText(S.Text("Saved filters require a dungeon search at maximum level, outside combat."))
    M.reset = Button(frame, "Reset statistics", 8, Reset)
    M.reset:ClearAllPoints()
    M.reset:SetPoint("BOTTOMLEFT", 8, 6)
    local function Changed() if M.active then M.job:Request() end end
    LFGListFrame.SearchPanel:HookScript("OnShow", Changed)
    hooksecurefunc("LFGListSearchPanel_SetCategory", Changed)
end
local function Event(_, event, id, status, old)
    if event == "LFG_LIST_APPLICATION_STATUS_UPDATED" then
        if M.config.statistics and Stats.Changed(id, status, old) then M.job:Request() end
    elseif event == "ADDON_LOADED" then
        M:Refresh()
    else
        M.job:Request() end
end
function M:Refresh()
    Build()
    if self.frame then self.context:RemoveEvent("ADDON_LOADED") end
    if self.config.statistics then
        if not self.tracking then Stats.Start() end
        self.tracking = true
        self.context:Event("LFG_LIST_APPLICATION_STATUS_UPDATED", Event, IN_COMBAT)
    else
        self.tracking = nil
        self.context:RemoveEvent("LFG_LIST_APPLICATION_STATUS_UPDATED")
    end
    for _, event in ipairs({ "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED", "PLAYER_LEVEL_UP" }) do
        if self.config.filters then self.context:Event(event, Event, IN_COMBAT)
        else
            self.context:RemoveEvent(event)
        end
    end
    if self.scope then
        local labels = { "Session", "Character", "Account" }
        self.scope:SetText(S.Text(labels[self.config.scope]))
    end
    self.job:Request()
end
function M:Enable()
    self.job = self.context:Coalesce(.05, Draw)
    self.context:Event("ADDON_LOADED", Event)
    self:Refresh()
end
function M:Disable()
    self.tracking = nil
    if self.frame then self.frame:Hide() end
    for id in pairs(Stats.applications) do Stats.applications[id] = nil end
end
S.Install(ID, M)

local _, NS = ...
local Host, Suite, Text = NS.Host, NS.Suite, NS.Text
local Gear, Pages, Model, Reputation = NS.Gear, NS.Pages, Host.CharacterTabs, NS.Reputation
local Preview = {}
Preview.__index = Preview
Suite.CharacterPanelPreview = Preview

local OWN, OVERVIEW, EQUIPMENT, COMPARE, ATTRIBUTES, REPUTATION = "own", "overview", "gear", "compare", "attributes", "reputation"
local MAX_HEIGHT = 426
local NO_DATA = Text("No data available")

local function ReportSample(title, label, value)
    return { title = Text(title), rows = { { label = Text(label), value = value } } }
end

local reportSamples = {
    reputation = ReportSample("Reputation", "Progress", "640 / 3000"),
    currency = ReportSample("Currency", "Quantity", 125),
    skills = Host.Client.isForever and ReportSample("Skills", "Defense", "115 / 150")
        or ReportSample("Skills", "Professions", "35 / 75"),
    pvp = ReportSample("PvP", Host.Client.isForever and "Rank" or "Honor level", 12),
    statistics = ReportSample("Statistics", "Quests", 84),
}

local function ReadBuiltIn(tab, groups, config)
    Pages.Read(tab, groups, config)
    local sample = reportSamples[tab]
    if sample and (#groups == 0 or (#groups == 1 and groups[1].title == NO_DATA and #groups[1].rows == 0)) then
        if tab == REPUTATION then Reputation.Sample(sample.rows[1], config) end
        groups[1] = sample
    end
end

local function SampleGear(sample)
    local model = Gear.New()
    local level = tonumber(sample.itemLevel)
    for _, row in ipairs(model.rows) do
        local icon = GetInventoryItemTexture("player", row.slot)
        if not NS.Public(icon) then icon = nil end
        if icon then
            row.icon, row.name, row.level = icon, row.label, level
        else
            row.icon, row.name = row.emptyIcon, Text("Empty slot")
        end
    end
    model.durability, model.missingEnchants, model.emptySockets = 88, 1, 2
    return model
end

local function FillGear(preview)
    local view, model, groups, details = preview.view, preview.gear[preview.mode], preview.groups, preview.details
    wipe(details)
    if preview.slot then Gear.Details(details, model, preview.slot, preview.mode ~= OWN) end
    if #details == 0 then
        if preview.mode == OWN then
            if preview.tab == OVERVIEW then Pages.Overview(groups, preview.fullStats, preview.combat) end
            Pages.EquipmentSummary(groups, model)
        else
            local sample = preview.samples[preview.mode]
            local group = preview.inspectSummary
            group.rows[1].value, group.rows[2].value = sample.class, sample.level
            groups[1] = group
        end
    end
    view:ShowGear(model.left, model.right, model.weapons, groups, preview.slot, details,
        preview.tab == OVERVIEW, preview.combat)
end

local function PaintBody(preview)
    local tab, view, mode = preview.tab, preview.view, preview.mode
    local own, groups = mode == OWN, preview.groups
    view:SetContextAction(not own and Text("Blizzard Inspect") or tab == EQUIPMENT and Text("Equipment sets") or nil)
    if not preview.definition then preview:ContentChanging() end
    wipe(groups)
    if tab == OVERVIEW or tab == EQUIPMENT then
        preview.gear[mode] = preview.gear[mode] or SampleGear(preview.samples[mode])
        FillGear(preview)
    elseif tab == ATTRIBUTES then
        view:ShowGroups(Pages.Overview(groups, true, preview.combat), preview.combat)
    else
        if tab == COMPARE then
            local ownGear = preview.gear[OWN] or SampleGear(preview.samples[OWN])
            local inspectGear = preview.gear[mode] or SampleGear(preview.samples[mode])
            preview.gear[OWN], preview.gear[mode] = ownGear, inspectGear
            Gear.Compare(groups, ownGear, inspectGear)
        elseif preview.definition then
            Pages.Custom(groups, Pages.CustomPlan(preview.definition), nil, nil, preview.config)
        else
            ReadBuiltIn(tab, groups, preview.config)
        end
        view:ShowGroups(groups)
    end
    if not preview.definition then preview:ContentChanged() end
end

local function Noop() end

function Preview.New(parent, samples, selectTab)
    local preview = setmetatable({
        samples = samples, groups = {}, details = {}, gear = {}, context = Suite.NewContext("characterPanelPreview"),
        inspectSummary = { title = Text("Inspect"), rows = { { label = Text("Class") }, { label = Text("Level") } } },
    }, Preview)
    local function Slot(slot, _, mouse)
        if Host.InCombat() or (mouse and mouse ~= "LeftButton") then return end
        if slot == preview.slot then slot = nil end
        preview.slot = slot
        PaintBody(preview)
    end
    preview.view = NS.View.New({
        tab = selectTab, slot = Slot, field = Noop, enter = Noop, leave = Noop, drag = Noop, drop = Noop, group = Noop,
    }, parent)
    preview.view.report.preview = preview
    preview.view.frame:ClearAllPoints()
    preview.view.frame:SetPoint("TOP")
    return preview
end

function Preview:Paint(config, mode, order, tab, overrides, width)
    local view, sample = self.view, self.samples[mode]
    local frame = view.frame
    local scale = math.min(1, width / frame:GetWidth(), MAX_HEIGHT / frame:GetHeight())
    if self.scale ~= scale then
        self.scale = scale
        frame:SetScale(scale)
    end
    view.previewLayers = overrides
    view:RefreshAppearance(self.context:Skin(), config)
    view:SetTabs(order, tab)
    local tabsShown = overrides.tabs ~= false
    if view.tabBar:IsShown() ~= tabsShown then view.tabBar:SetShown(tabsShown) end
    view:SetHeader(sample.name, sample.class, sample.itemLevel, sample.portrait, mode, sample)
    if not frame:IsShown() then frame:Show() end

    local definition = mode == OWN and Model.Find(config, tab)
    local fullStats = config.showFullStats ~= false
    local combat = mode == OWN and (tab == OVERVIEW or tab == ATTRIBUTES) and Host.InCombat()
    local reputationKey = mode == OWN and Pages.ReputationKey(tab, config, definition and Pages.CustomPlan(definition))
    local switched = self.mode ~= mode or self.tab ~= tab
    if switched then self.slot = nil end
    if switched or self.definition ~= definition or self.fullStats ~= fullStats or self.combat ~= combat
        or self.reputationKey ~= reputationKey or self.reopen then
        self.mode, self.tab, self.definition, self.fullStats, self.combat = mode, tab, definition, fullStats, combat
        self.config, self.reputationKey = config, reputationKey
        self.reopen = nil
        PaintBody(self)
    end
    return frame:GetHeight() * scale
end

function Preview:SetContentChanging(callback)
    self.contentChanging = callback
end

function Preview:SetContentChanged(callback)
    self.contentChanged = callback
end

function Preview:ContentChanging()
    if self.contentChanging then self.contentChanging(self) end
end

function Preview:ContentChanged()
    if self.contentChanged then self.contentChanged(self) end
end

function Preview:VisitContent(visitor)
    local view = self.view
    if self.definition and view.report.previewDefinition == self.definition
        and view.frame:IsShown() and view.report.scroll:IsShown() then
        view:VisitReport(visitor)
    end
end

function Preview:Hide()
    if not self.view.frame:IsShown() then return end
    self:ContentChanging()
    self.view.frame:Hide()
    self.view:RefreshAppearance(nil)
    self.reopen = true
    self:ContentChanged()
end

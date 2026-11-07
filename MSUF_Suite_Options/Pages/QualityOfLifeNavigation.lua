local _, P = ...
local V, HM, Tr = P.QoLView, P.HM, P.Tr
local FILTERS = { all = true, enabled = true, disabled = true, unavailable = true }
local QOL_PAGE, GRAPHICS_CATEGORY = "suite_qualityOfLife", "interface"

local function Matches(ui, group)
    if ui.retained == group then return true end
    local available = P.Available(group.id)
    if ui.filter == "unavailable" then return not available end
    if not available then return false end
    if ui.filter == "enabled" then return V.GroupEnabled(group) end
    if ui.filter == "disabled" then return not V.GroupEnabled(group) end
    return true
end

local function Resize(ui)
    local panel = ui.panels[ui.selected]
    if not panel then return end
    local height = ui.top + math.max(ui.emptyShown and 80 or 1, panel.height)
    if ui.height == height then return end
    ui.height = height
    P.FinishBody(ui.builder, ui.body, -height, 0)
end

local function Layout(ui)
    local panel = ui.panels[ui.selected]
    if not panel or panel.building then return end
    if ui.selector then
        local bottom = ui.selector:GetLayoutMetrics().bottomY
        local y = ui.inlineFilter and -16 or bottom - 8
        if ui.filterY ~= y then
            ui.filterControl:ClearAllPoints()
            ui.filterControl:SetPoint("TOPRIGHT", ui.body, "TOPRIGHT", -8, y)
            ui.filterY = y
        end
        local top = math.max(-bottom, -y + 26) + 12
        if ui.top ~= top then
            ui.top = top
            for _, value in pairs(ui.panels) do
                value.frame:ClearAllPoints()
                value.frame:SetPoint("TOPLEFT", ui.body, "TOPLEFT", 0, -top)
            end
        end
    end
    local flow, count, index = panel.visibleFlow, 0, 0
    for _, subgroup in ipairs(panel.category.subgroups) do
        local heading, shown = panel.headings[subgroup.id], false
        for _, group in ipairs(subgroup.features) do if Matches(ui, group) then shown = true end end
        if heading then
            if heading.shown ~= shown then heading.frame:SetShown(shown) heading.shown = shown end
            if shown then index = index + 1 flow[index] = heading.flow end
        end
        for _, group in ipairs(subgroup.features) do
            local record, visible = panel.records[group], Matches(ui, group)
            if record.shown ~= visible then record.row:SetShown(visible) record.shown = visible end
            if visible then
                index, count = index + 1, count + 1
                flow[index] = record.flow
            end
        end
    end
    if panel.graphics then
        local graphics = HM.GetSectionEntry(panel.graphics)
        local visible = ui.filter == "all" or ui.retained == panel.graphics
        graphics.outer:SetShown(visible)
        if visible then
            index, count = index + 1, count + 1
            flow[index] = graphics
        end
    end
    for item = #flow, index + 1, -1 do flow[item] = nil end
    P.Suite.HostBridge.SetMenuFlowEntries(panel.builder, flow)
    ui.emptyShown = count == 0
    if ui.empty then
        ui.empty:SetShown(ui.emptyShown)
        ui.clearFilter:SetShown(ui.emptyShown)
        if ui.emptyTop ~= ui.top then
            ui.empty:ClearAllPoints()
            ui.empty:SetPoint("TOPLEFT", ui.body, "TOPLEFT", 16, -ui.top - 12)
            ui.clearFilter:ClearAllPoints()
            ui.clearFilter:SetPoint("TOPLEFT", ui.body, "TOPLEFT", 16, -ui.top - 40)
            ui.emptyTop = ui.top
        end
    end
    Resize(ui)
end

local function RevealGraphics(ui)
    if not ui:SelectCategory(GRAPHICS_CATEGORY) then return nil end
    local section = ui.panels[GRAPHICS_CATEGORY].graphics
    ui.retained = section
    ui:Layout()
    return section
end

local function BuildPanel(ui, category)
    local frame = CreateFrame("Frame", nil, ui.body)
    frame:SetPoint("TOPLEFT", ui.body, "TOPLEFT", 0, -ui.top)
    frame:SetSize(ui.width, 1)
    frame:Hide()
    local panel = HM.SetBuilderInsets({ wrapper = frame, frame = frame, width = ui.width, height = 1,
        category = category, records = {}, headings = {}, visibleFlow = {}, building = true }, 0, -12)
    setmetatable(panel, { __index = ui.ctx })
    ui.panels[category.id], ui.frames[category.id] = panel, frame
    function panel:SetContentHeight(height)
        local wanted = math.max(1, height - 42)
        if self.height ~= wanted then self.height = wanted self.frame:SetHeight(wanted) end
        if not self.building then Resize(ui) end
    end
    panel.builder = P.W.PageBuilder(panel)
    for _, subgroup in ipairs(category.subgroups) do
        if #category.subgroups > 1 or ui.heading then
            local body = P.Suite.HostBridge.MenuFlowSection(panel.builder, 26, 4)
            P.Text(body, ui.heading or subgroup.title, 8, -5, ui.width - 16, P.T.colors.textMuted)
            panel.headings[subgroup.id] = { frame = body, flow = panel.builder.layoutEntries[#panel.builder.layoutEntries] }
        end
        for _, group in ipairs(subgroup.features) do V.BuildAccordionRecord(ui, panel, group) end
    end
    if ui.page == QOL_PAGE and category.id == GRAPHICS_CATEGORY then
        panel.graphics = P.BuildGraphicsPerformance(ui.ctx, panel.builder, function()
            return RevealGraphics(ui)
        end)
    end
    panel.building = false
    return panel
end

local function InstallSelection(ui)
    ui.Layout = Layout
    function ui:SelectCategory(id)
        local category = self.categories[id]
        if not category or P.Combat() then return false end
        if self.selected ~= id then self.retained = nil end
        if self.reveal then self.reveal() end
        self.selected, self.saved.category = id, id
        if not self.panels[id] then BuildPanel(self, category) end
        Layout(self)
        for key, panel in pairs(self.panels) do panel.frame:SetShown(key == id) end
        if self.selector then self.selector:SetValue(id) end
        return true
    end
    function ui:SetFilter(value)
        self.filter = FILTERS[value] and value or "all"
        self.saved.filter, self.retained = self.filter, nil
        Layout(self)
        P.Refresh()
    end
end

local function InstallRoutes(ui, categories)
    local entry = ui.ctx.entry
    if ui.page == QOL_PAGE then
        ui.routes[P.GraphicsPerformanceSection] = function()
            local section = RevealGraphics(ui)
            P.EnsureSectionContent(section)
            return section
        end
    end
    for _, category in ipairs(categories) do
        local function RevealCategory()
            if not ui:SelectCategory(category.id) then return nil end
            return ui.panels[category.id].frame
        end
        ui.routes["suite_qualityOfLife_category_" .. category.id] = RevealCategory
        for old, current in pairs(V.LegacyCategories) do
            if current == category.id then ui.routes["suite_qualityOfLife_category_" .. old] = RevealCategory end
        end
        for _, subgroup in ipairs(category.subgroups) do
          for _, group in ipairs(subgroup.features) do
            local id = V.FeatureSectionId(group)
            ui.order[#ui.order + 1] = id
            local function Reveal(force, expand)
                if not ui:SelectCategory(category.id) then return nil end
                return ui.rows[id].reveal(force, expand)
            end
            group.reveal = Reveal
            for _, section in ipairs(group.sections) do
                ui.routes["suite_qualityOfLife_" .. group.id .. "_" .. section] = Reveal
            end
          end
        end
    end
    ui.ctx.qualityOfLifeFeatureRows, ui.ctx.qualityOfLifeFeatureOrder = ui.rows, ui.order
    if not entry then return end
    entry.qualityOfLifeFeatureRows, entry.qualityOfLifeFeatureOrder = ui.rows, ui.order
    entry.qualityOfLifeView = ui
    local previous = HM.GetMissingSectionResolver(entry)
    HM.SetMissingSectionResolver(entry, function(id)
        if ui.routes[id] then return ui.routes[id](true) end
        return previous and previous(id) or nil
    end)
end

local function BuildFilters(ui)
    ui.filterControl = P.M.BindDropdownAt(ui.ctx, ui.body, Tr("Show"), 0, 0, {
        { value = "all", text = Tr("All") },
        { value = "enabled", text = Tr("Enabled only") },
        { value = "disabled", text = Tr("Disabled only") },
        { value = "unavailable", text = Tr("Unavailable") },
    }, math.min(170, ui.width / 2), function() return ui.filter end,
        function(value) ui:SetFilter(value) end, P.Meta(ui.page, "qol", "view.enabled", "ephemeral"))
    P.HideControlTitle(ui.filterControl)
    ui.empty = P.Text(ui.body, "No features match this filter.", 16, 0, ui.width - 32)
    ui.clearFilter = P.T.Button(ui.body, "Show all", 140, 25)
    ui.clearFilter:SetScript("OnClick", function() ui:SetFilter("all") end)
end

local function BuildSelector(ui, categories)
    local values = {}
    local measure = P.T.Font(ui.body, "GameFontHighlightSmall", "", P.T.colors.text, "control")
    measure:Hide()
    ui.inlineFilter = ui.width >= 960
    local width = ui.width - (ui.inlineFilter and 190 or 0)
    for _, category in ipairs(categories) do
        local label = Tr(category.title)
        P.SetTranslatedText(measure, label)
        local measured = measure:GetStringWidth() or 0
        values[#values + 1] = { value = category.id, text = label,
            width = math.min(width, math.max(74, (measured > 0 and measured or #label * 6) + 32)) }
    end
    ui.selector = P.W.ScopeOverrideBar(ui.ctx, ui.body, {
        label = Tr("Category"), labelWidth = 0, values = values, width = width,
        startX = 0, maxRight = width,
        getValue = function() return ui.selected end,
        setValue = function(id) ui:SelectCategory(id) end,
    })
    ui.selector.label:Hide()
end

function V.BuildSelected(ctx, builder, categories, page, opts)
    if #categories == 0 then return end
    opts = opts or {}
    local body = P.Suite.HostBridge.MenuFlowSection(builder, 80)
    local state = P.Suite.HostBridge.GetPersistentMenuState(P.M, "MSUF_Suite_QoL")
    state[page] = state[page] or {}
    local saved = state[page]
    local ui = { ctx = ctx, builder = builder, body = body, page = page, saved = saved,
        width = HM.GetSectionWidth(body) or builder.width or 720,
        panels = {}, frames = {}, categories = {}, rows = {}, order = {}, routes = {},
        top = 0, heading = opts.heading,
        filter = not opts.compact and FILTERS[saved.filter] and saved.filter or "all" }
    for _, category in ipairs(categories) do ui.categories[category.id] = category end
    ui.selected = ui.categories[saved.category] and saved.category or categories[1].id
    InstallSelection(ui)
    InstallRoutes(ui, categories)
    if not opts.compact then BuildFilters(ui) BuildSelector(ui, categories) end
    ui:SelectCategory(ui.selected)
    ui.reveal = opts.reveal
    P.M.TrackRefresh(ctx, function() Layout(ui) end)
    return ui
end

function V.BuildGameplay(ctx, builder)
    P.SortQualityOfLifeCategories()
    return V.BuildSelected(ctx, builder, { V.GameplayCategory }, "gameplay", { compact = true })
end

function V.RevealFeature(group, entry, expand)
    local ui = entry and entry.qualityOfLifeView
    local reveal = ui and ui.routes[V.FeatureSectionId(group)]
    return reveal and reveal(true, expand) or nil
end

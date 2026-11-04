local _, P = ...
local V, HM, Tr = P.QoLView, P.HM, P.Tr
local FILTERS = { all = true, enabled = true, disabled = true }

local function Matches(ui, panel, group)
    if panel.selected == group or ui.retained == group then return true end
    if ui.filter == "enabled" then return V.GroupEnabled(group) end
    if ui.filter == "disabled" then return not V.GroupEnabled(group) end
    return true
end

local function PlaceRecord(panel, record, shown, selected, offset)
    if record.shown ~= shown then
        record.row:SetShown(shown)
        record.shown = shown
    end
    if shown and record.rowY ~= offset then
        record.row:ClearAllPoints()
        record.row:SetPoint("TOPLEFT", panel.frame, "TOPLEFT", 0, -offset)
        record.rowY = offset
    end
    if shown then offset = offset + V.RowHeight end
    if record.details and selected then
        if record.detailsY ~= offset then
            record.details:ClearAllPoints()
            record.details:SetPoint("TOPLEFT", panel.frame, "TOPLEFT", 0, -offset - 4)
            record.detailsY = offset
        end
        offset = offset + record.detailHeight + 12
    end
    if record.details and record.detailsShown ~= selected then
        record.details:SetShown(selected)
        record.detailsShown = selected
    end
    if record.row._msufSuiteSelected ~= selected then
        record.row._msufSuiteSelected = selected
        if record.settings then record.settings:SetActive(selected) end
        V.PaintFeatureRow(record.row)
    end
    return offset
end

local function Layout(ui)
    -- The host's Unitframes selector wraps on resize. Keep the lazy content
    -- height in step with that header before any filter/detail refresh.
    if ui.selector then
        local top = -ui.selector:GetLayoutMetrics().bottomY + 68
        if ui.top ~= top then
            ui.top = top
            for _, panel in pairs(ui.panels) do
                panel.frame:ClearAllPoints()
                panel.frame:SetPoint("TOPLEFT", ui.body, "TOPLEFT", 16, -top)
            end
        end
    end
    local panel = ui.panels[ui.selected]
    if not panel then return end
    local offset, count, enabled = 0, 0, 0
    for _, subgroup in ipairs(panel.category.subgroups) do
        local shown = false
        for _, group in ipairs(subgroup.features) do
            if V.GroupEnabled(group) then enabled = enabled + 1 end
            if Matches(ui, panel, group) then shown = true end
        end
        local heading = panel.headings[subgroup.id]
        if heading._suiteShown ~= shown then
            heading:SetShown(shown)
            heading._suiteShown = shown
        end
        if shown then
            if heading._suiteOffset ~= offset then
                heading:ClearAllPoints()
                heading:SetPoint("TOPLEFT", panel.frame, "TOPLEFT", 8, -offset - 5)
                heading._suiteOffset = offset
            end
            offset = offset + 30
        end
        for _, group in ipairs(subgroup.features) do
            local visible = Matches(ui, panel, group)
            if visible then count = count + 1 end
            offset = PlaceRecord(panel, panel.records[group], visible, panel.selected == group, offset)
        end
        if shown then offset = offset + 8 end
    end
    ui.empty:SetShown(count == 0)
    ui.clearFilter:SetShown(count == 0)
    local height = math.max(count == 0 and 80 or 1, offset)
    if panel.height ~= height then
        panel.frame:SetHeight(height)
        panel.height = height
    end
    local countText = Tr("%d/%d enabled"):format(enabled, #panel.category.features)
    if ui.countText ~= countText then
        P.SetTranslatedText(ui.count, countText)
        ui.countText = countText
    end
    if ui.height ~= height or ui.heightCategory ~= ui.selected then
        P.FinishBody(ui.builder, ui.body, -ui.top - height, 12)
        ui.height, ui.heightCategory = height, ui.selected
    end
end

local function SelectFeature(ui, panel, group, force, expand)
    if P.Combat() then return nil end
    ui:SelectCategory(panel.category.id)
    local record = panel.records[group]
    if record.hasDetails and expand ~= false and not record.details then
        record.details, record.detailHeight, record.colorShortcut = V.BuildFeatureDetails(
            ui.ctx, panel.frame, group, record.sectionId, ui.width, record.sections, record.allRules, record.keywords)
        if ui.sectionEntry then HM.SetSectionEntry(record.details, ui.sectionEntry) end
        P.Refresh()
    end
    if not force and panel.selected == group then panel.selected = nil
    else panel.selected = group end
    ui.retained = group
    Layout(ui)
    return expand ~= false and record.details or record.row
end

local function BuildRecord(ui, panel, group, index)
    local sectionId = V.FeatureSectionId(group)
    local sections, rules = V.FeatureRules(group)
    local hasDetails = V.HasDetails(group, rules)
    local row, toggle, settings, keywords = V.BuildFeatureRow(ui.ctx, panel.frame, group, panel.category,
        sectionId, ui.width, index, hasDetails,
        function(feature, force) SelectFeature(ui, panel, feature, force) end,
        function(feature) ui.retained = feature end)
    if ui.sectionEntry then HM.SetSectionEntry(row, ui.sectionEntry) end
    local record = {
        row = row, toggle = toggle, settings = settings, hasDetails = hasDetails,
        sectionId = sectionId, sections = sections, allRules = rules, group = group,
        category = panel.category.id, tab = group.tab, title = group.title, keywords = keywords,
    }
    record.reveal = function(force, expand) return SelectFeature(ui, panel, group, force ~= false, expand) end
    panel.records[group], ui.rows[sectionId] = record, record
    return record
end

local function BuildPanel(ui, category)
    local frame = CreateFrame("Frame", nil, ui.body)
    frame:SetPoint("TOPLEFT", ui.body, "TOPLEFT", 16, -ui.top)
    frame:SetSize(ui.width, 100)
    local panel = { frame = frame, category = category, records = {}, headings = {} }
    ui.panels[category.id], ui.frames[category.id] = panel, frame
    local index = 0
    for _, subgroup in ipairs(category.subgroups) do
        local heading = P.Text(frame, subgroup.title, 8, 0, ui.width - 16, P.T.colors.textMuted)
        panel.headings[subgroup.id] = heading
        for _, group in ipairs(subgroup.features) do
            index = index + 1
            BuildRecord(ui, panel, group, index)
        end
    end
    return panel
end

local function InstallSelection(ui)
    function ui:SelectCategory(id)
        local category = self.categories[id]
        if not category or P.Combat() then return false end
        if self.selected ~= id then self.retained = nil end
        self.selected, self.saved.category = id, id
        if not self.panels[id] then BuildPanel(self, category) end
        for key, panel in pairs(self.panels) do panel.frame:SetShown(key == id) end
        if self.selector then self.selector:SetValue(id) end
        Layout(self)
        return true
    end
    function ui:SetFilter(value)
        self.filter = FILTERS[value] and value or "all"
        self.saved.filter, self.retained = self.filter, nil
        for _, panel in pairs(self.panels) do panel.selected = nil end
        Layout(self)
        P.Refresh()
    end
end

local function InstallRoutes(ui, categories)
    local entry = ui.ctx.entry
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

local function BuildSelector(ui, categories)
    local values = {}
    local measure = P.T.Font(ui.body, "GameFontHighlightSmall", "", P.T.colors.text, "control")
    measure:Hide()
    for _, category in ipairs(categories) do
        local label = Tr(category.title)
        P.SetTranslatedText(measure, label)
        local width = measure:GetStringWidth() or 0
        values[#values + 1] = { value = category.id, text = label,
            width = math.min(ui.width, math.max(74, (width > 0 and width or #label * 6) + 32)) }
    end
    ui.selector = P.W.ScopeOverrideBar(ui.ctx, ui.body, {
        label = Tr("Category"), labelWidth = 0, values = values, width = ui.width + 32,
        startX = 16, maxRight = ui.width + 16,
        getValue = function() return ui.selected end,
        setValue = function(id) ui:SelectCategory(id) end,
    })
    ui.selector.label:Hide()
    ui.filterY = ui.selector:GetLayoutMetrics().bottomY - 12
    ui.top = -ui.filterY + 56
end

local function BuildFilters(ui, single)
    local y = single and -26 or ui.filterY
    ui.filterControl = P.M.BindDropdownAt(ui.ctx, ui.body, Tr("Show"), 16, y, {
        { value = "all", text = Tr("All") },
        { value = "enabled", text = Tr("Enabled only") },
        { value = "disabled", text = Tr("Disabled only") },
    }, math.min(210, ui.width / 2), function() return ui.filter end,
        function(value) ui:SetFilter(value) end, P.Meta(ui.page, "qol", "view.enabled", "ephemeral"))
    P.HideControlTitle(ui.filterControl)
    ui.count = P.Text(ui.body, "", ui.width - 170, y - 19, 170, P.T.colors.textMuted)
    ui.count:SetJustifyH("RIGHT")
    ui.empty = P.Text(ui.body, "No features match this filter.", 24, -ui.top - 16, ui.width - 16)
    ui.clearFilter = P.T.Button(ui.body, "Show all", 140, 25)
    ui.clearFilter:SetPoint("TOPLEFT", ui.body, "TOPLEFT", 24, -ui.top - 44)
    ui.clearFilter:SetScript("OnClick", function() ui:SetFilter("all") end)
end

function V.BuildSelected(ctx, builder, categories, page)
    if not builder.Section then return end
    local topY = builder.y
    local body = builder:Section(Tr(page == "gameplay" and "Combat helpers" or "Quality of Life"), 120)
    P.Suite.HostBridge.TrackDynamicSection(builder, body, topY)
    local single = #categories == 1
    if body.title and not single then body.title:Hide() end
    local state = P.Suite.HostBridge.GetPersistentMenuState(P.M, "MSUF_Suite_QoL")
    state[page] = state[page] or {}
    local saved = state[page]
    local ui = { ctx = ctx, builder = builder, body = body, page = page, saved = saved,
        width = math.max(240, (HM.GetSectionWidth(body) or builder.width or 720) - 32),
        panels = {}, frames = {}, categories = {}, rows = {}, order = {}, routes = {},
        top = single and 82 or 108, filter = FILTERS[saved.filter] and saved.filter or "all",
        sectionEntry = HM.GetSectionEntry(body) }
    for _, category in ipairs(categories) do ui.categories[category.id] = category end
    ui.selected = ui.categories[saved.category] and saved.category or categories[1].id
    InstallSelection(ui)
    InstallRoutes(ui, categories)
    if not single then BuildSelector(ui, categories) end
    BuildFilters(ui, single)
    ui:SelectCategory(ui.selected)
    P.M.TrackRefresh(ctx, function() Layout(ui) end)
    return ui
end

function V.BuildGameplay(ctx, builder)
    P.SortQualityOfLifeCategories()
    return V.BuildSelected(ctx, builder, { V.GameplayCategory }, "gameplay")
end

function V.RevealFeature(group, entry, expand)
    local ui = entry and entry.qualityOfLifeView
    local reveal = ui and ui.routes[V.FeatureSectionId(group)]
    return reveal and reveal(true, expand) or nil
end

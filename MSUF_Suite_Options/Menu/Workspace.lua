local _, P = ...
local W, M, HM, Tr = P.W, P.M, P.HM, P.Tr
local Workspace, selections = {}, {}
P.MenuWorkspace = Workspace

function Workspace.PlaceTabDivider(toolbar, selector)
    local divider = toolbar and rawget(toolbar, "divider")
    if not divider then return end
    divider:ClearAllPoints()
    divider:SetPoint("TOPLEFT", selector, "BOTTOMLEFT", -4, -3)
    divider:SetPoint("TOPRIGHT", selector, "BOTTOMRIGHT", 4, -3)
end

function Workspace.FitHeader(ui, required)
    local height = math.max(ui.spec.height or 62, required)
    if ui.header:GetHeight() == height then return end
    HM.SetFixedPreviewHeight(ui.header, height)
    ui.header:SetHeight(height)
    if M.RelayoutPageHeaderHost then M.RelayoutPageHeaderHost() end
end

local function RuleSwitch(ctx, body, page, module, section, rule, opts)
    local row = P.RuleRow(page, module, rule, opts.keyFn, section)
    local toggle = P.BindSectionSwitch(ctx, body, {
        label = row.label, displayLabel = Tr(opts.switchLabel or "Enable"), dim = opts.dimSwitch,
        get = row.get, meta = row,
        set = function(value)
            if P.RuleEnabled(module, rule, opts.keyFn, false, opts.editWhileOff) then row.set(value) end
        end,
    })
    local entries = { { rule = rule, widget = toggle, meta = row, label = row.label } }
    P.GateControls(ctx, module, entries, opts.keyFn, opts.editWhileOff)
    Workspace.Prepare(body, entries)
    P.AttachRowsSummary(ctx, body)
end

function Workspace.Rules(ctx, builder, page, module, section, title, rules, opts)
    opts = opts or {}
    if opts.switchKey and W.SectionSwitch then
        local bodyRules, switch = {}, nil
        for _, rule in ipairs(rules) do
            if rule.key == opts.switchKey then switch = rule else bodyRules[#bodyRules + 1] = rule end
        end
        if switch then
            local head = opts.head
            opts.head = function(body)
                if head then head(body) end
                RuleSwitch(ctx, body, page, module, section, switch, opts)
            end
            opts.resetRules = opts.resetRules or rules
            rules = bodyRules
        end
    end
    local before = opts.onBuilt
    opts.onBuilt = function(body, entries)
        Workspace.Prepare(body, entries, module)
        if before then before(body, entries) end
    end
    return P.RuleSection(ctx, builder, page, module, section, title, rules, opts)
end

local function Height(ui)
    local group = ui.groups[ui.selected]
    HM.SetSectionCursor(ui.body, -(group and group.height or 80) + 12)
    ui.builder:FinishSection(ui.body, 12)
end

local function Choose(ui, key)
    if not ui.groups[key] then return false end
    ui.selected, selections[ui.spec.page] = key, key
    for id, group in pairs(ui.groups) do group.frame:SetShown(id == key) end
    if ui.selector then ui.selector:SetValue(key) end
    Height(ui)
    if ui.refreshPreview then ui.refreshPreview() end
    return true
end

local function Child(ui, id)
    if ui.groups[id] then return ui.groups[id].builder end
    local panel = CreateFrame("Frame", nil, ui.body)
    panel:SetPoint("TOPLEFT")
    panel:SetWidth(ui.width)
    panel:SetShown(id == ui.selected)
    -- The group is also its builder context: height updates belong to this tab.
    local group = HM.SetBuilderInsets({ wrapper = panel, frame = panel, height = 80, width = ui.width }, 0, 0)
    setmetatable(group, { __index = ui.ctx })
    ui.groups[id] = group
    function group:SetContentHeight(height)
        self.height = math.max(80, height)
        self.frame:SetHeight(self.height)
        if ui.finished and ui.selected == id then Height(ui) end
    end
    group:SetContentHeight(80)
    group.builder = W.PageBuilder(group)
    return group.builder
end

local function Route(ui, sectionId)
    local suffix = sectionId:sub(#ui.spec.page + 2)
    for _, tab in ipairs(ui.spec.tabs) do
        for name in tab.sections:gmatch("%S+") do
            if name == suffix or name == sectionId then return tab.id end
        end
    end
    return ui.spec.tabs[1].id
end

function Workspace.Prepare(body, entries, module)
    local ui = body._suiteWorkspace
    if not ui then return end
    for _, entry in ipairs(entries or {}) do
        local widget = entry.widget
        if widget then
            local before = HM.GetSearchTargetPrepare(widget)
            local function Reveal()
                ui.select(body._suiteWorkspaceTab)
                if before then before() end
                return true
            end
            HM.SetSearchTargetPrepare(widget, Reveal)
            local meta = entry.meta or P.Meta(ui.spec.page, module or ui.spec.module, entry.rule.key,
                "setting", body._suiteWorkspaceSection)
            P.RegisterWorkspaceSearch(widget, meta, entry.rule, "suiteWorkspace", Reveal, entry.label)
        end
    end
end

function Workspace.Builder(ctx, spec)
    local builder = spec.builder or W.PageBuilder(ctx)
    if not builder.Section then return builder, nil end
    local height = spec.height or 62
    local ui
    local header, toolbar = spec.header, spec.toolbar
    if W.FixedPreviewSection and not header then
        header, toolbar = W.FixedPreviewSection(ctx, builder, {
            title = Tr(spec.title), height = height,
            onActivate = function()
                if ui and ui.refreshPreview then ui.refreshPreview() end
                -- OnShow can resize the preview before its sticky record is active.
                if M.RelayoutPageHeaderHost then M.RelayoutPageHeaderHost() end
            end,
        })
    end
    header = header or builder:Section(Tr(spec.title), height)
    HM.SetFixedPreviewHeight(header, height)
    header:SetHeight(height)
    local body = builder:Section(Tr("Settings"), 120)
    if header.title then header.title:Hide() end
    if body.title then body.title:Hide() end
    ui = { ctx = ctx, spec = spec, builder = builder, body = body, header = header, toolbar = toolbar,
        width = HM.GetSectionWidth(body) or builder.width or 720, groups = {}, sections = {},
        selected = selections[spec.page] or spec.tabs[1].id }
    ctx.suiteWorkspace = ui
    ui.select = function(key)
        if ui.chooseTab then return ui.chooseTab(key) else return Choose(ui, key) end
    end
    function ui:Focus(sectionId)
        local section = self.sections[sectionId]
        if not section then return false end
        self.select(section._suiteWorkspaceTab)
        P.EnsureSectionContent(section)
        if W.FocusCollapsibleSection then W.FocusCollapsibleSection(section, { flash = true }) end
        return true
    end
    for _, tab in ipairs(spec.tabs) do Child(ui, tab.id) end
    if not ui.groups[ui.selected] then ui.selected = spec.tabs[1].id end
    local facade = {}
    function facade:CollapsibleSection(sectionId, title, sectionHeight, open)
        local id = Route(ui, sectionId)
        local owner = Child(ui, id)
        local section = owner:CollapsibleSection(sectionId, title, sectionHeight, open)
        section._suiteWorkspace, section._suiteWorkspaceTab = ui, id
        section._suiteWorkspaceSection, section._suiteWorkspaceBuilder = sectionId, owner
        ui.sections[sectionId] = section
        return section
    end
    function facade:FinishSection(section, pad)
        return section._suiteWorkspaceBuilder:FinishSection(section, pad)
    end
    facade.LazyCollapsibleSection = P.TabLazySection(builder, function() return true end)
    return setmetatable(facade, { __index = builder }), ui
end

local function LayoutSelector(row)
    local available = row.owner:GetWidth()
    local width = math.max(1, (available > 32 and available or row.widthHint) - 32)
    local x, y = 0, 0
    for _, item in ipairs(row.items) do
        local size = math.min(width, item.width)
        if x > 0 and x + size > width then x, y = 0, y - 32 end
        item.button:ClearAllPoints()
        item.button:SetPoint("TOPLEFT", row, "TOPLEFT", x, y)
        item.button:SetSize(size, 26)
        x = x + size + 8
    end
    row:SetSize(width, 26 - y)
end

-- Both supported hosts get visible measured-label wrapping, including older
-- Menu2 versions whose segmented control only offers a single fixed row.
function Workspace.WrappingTabs(ui, values, apply)
    local row = CreateFrame("Frame", nil, ui.header)
    row.owner, row.items, row.widthHint = ui.header, {}, ui.width
    row:SetPoint("TOPLEFT", ui.header, "TOPLEFT", 16, -12)
    local measureWidth = P.T.MeasureTabWidth
    if not measureWidth then
        local measure = P.PreviewCanvas.Text(row, "", 0, 0, 0)
        measure:SetWordWrap(false)
        measure:Hide()
        measureWidth = function(text)
            measure:SetText(text)
            return math.max(56, math.ceil(measure:GetStringWidth()) + 26)
        end
    end
    local function RefreshSelected()
        for _, item in ipairs(row.items) do item.button:SetActive(ui.selected == item.id) end
    end
    local function Choose(id)
        local selected = apply(id)
        RefreshSelected()
        return selected
    end
    for _, value in ipairs(values) do
        local width = measureWidth(value.text)
        local button = P.T.Button(row, value.text, width, 26)
        P.HM.MarkSegmentChoice(button)
        row.items[#row.items + 1] = { id = value.value, button = button, width = width }
        button:SetScript("OnClick", function() Choose(value.value) end)
        if P.M.RegisterControlMetadata then
            P.M.RegisterControlMetadata(button, P.Meta(ui.spec.page, ui.spec.module, "view.topic." .. value.value, "ephemeral"), value.text, "button")
        end
    end
    if P.T.TrackTabLayout then
        P.T.TrackTabLayout(row, function(self)
            for _, item in ipairs(self.items) do item.width = measureWidth(item.button:GetText()) end
            LayoutSelector(self)
        end)
    end
    ui.header:HookScript("OnSizeChanged", function() LayoutSelector(row) end)
    P.M.TrackRefresh(ui.ctx, RefreshSelected)
    LayoutSelector(row)
    RefreshSelected()
    return row, Choose
end

-- Settings inside one accordion keep the preview and section actions above
-- the tabs. Report only the selected panel's height to the accordion.
function Workspace.FeatureTabs(ctx, body, page, module, width, y, values, panels, resize)
    local picker = { ctx = ctx, header = body, width = width + 32, selected = values[1].value,
        spec = { page = page, module = module } }
    local row, top, bottom
    local function Layout()
        local nextTop = y - row:GetHeight() - 10
        if nextTop ~= top then
            top = nextTop
            for _, panel in pairs(panels) do
                panel:ClearAllPoints()
                panel:SetPoint("TOPLEFT", body, "TOPLEFT", 0, top)
            end
        end
        local nextBottom = top - panels[picker.selected]:GetHeight()
        if nextBottom == bottom then return end
        local ready = bottom ~= nil
        bottom = nextBottom
        if ready and resize then resize(bottom) end
    end
    local function ShowTab(key)
        picker.selected = key
        for id, panel in pairs(panels) do panel:SetShown(id == key) end
        Layout()
        return true
    end
    local choose
    row, choose = Workspace.WrappingTabs(picker, values, ShowTab)
    row:ClearAllPoints()
    row:SetPoint("TOPLEFT", body, "TOPLEFT", 16, y)
    row:HookScript("OnSizeChanged", Layout)
    ShowTab(picker.selected)
    return bottom, choose
end

function Workspace.Finish(ui)
    if not ui then return end
    local entry = ui.ctx.entry or ui.ctx
    local previousResolver = HM.GetMissingSectionResolver(entry)
    HM.SetMissingSectionResolver(entry, function(sectionId)
        local section = ui.sections[sectionId]
        if not section then return previousResolver and previousResolver(sectionId) end
        ui.select(section._suiteWorkspaceTab)
        P.EnsureSectionContent(section)
        return section
    end)
    local values, panels = {}, {}
    for _, tab in ipairs(ui.spec.tabs) do
        values[#values + 1] = { value = tab.id, text = Tr(tab.label) }
        panels[tab.id] = ui.groups[tab.id].frame
    end
    for _, body in pairs(ui.sections) do
        local entry = HM.GetSectionEntry(body)
        if entry then
            local before = HM.GetSectionEnsureVisible(entry)
            HM.SetSectionEnsureVisible(entry, function(...)
                ui.select(body._suiteWorkspaceTab)
                if before then return before(...) end
            end)
        end
    end
    -- Keep page areas directly selectable; the shared tabs fit the header width.
    if ui.spec.buildSelector then
        ui.tabs, ui.chooseTab = ui.spec.buildSelector(ui, values, function(id) return Choose(ui, id) end)
    elseif W.SegmentTabs then
        local tabs, refresh, _, choose = W.SegmentTabs(ui.ctx, ui.header, {
            label = "", compact = true, wrap = true, values = values, frames = panels, width = ui.width - 32,
            defaultTab = ui.selected, get = function() return ui.selected end,
            set = function(id) Choose(ui, id) end, afterRefresh = function(id) Choose(ui, id) end,
            x = 16, y = ui.spec.tabY or 12,
        })
        P.HideControlTitle(tabs)
        ui.tabs, ui.chooseTab = tabs, choose
        local function FitTabsHeader()
            Workspace.FitHeader(ui, (ui.spec.height or 62) + tabs:GetHeight() - 26)
        end
        tabs:HookScript("OnSizeChanged", FitTabsHeader)
        FitTabsHeader()
        refresh()
    else
        ui.selector = M.BindDropdownAt(ui.ctx, ui.header, ui.spec.title, 16, ui.spec.tabY or 12, values, ui.width - 32,
            function() return ui.selected end, function(id) Choose(ui, id) end,
            P.Meta(ui.spec.page, ui.spec.module, "view.topic", "ephemeral"))
        P.HideControlTitle(ui.selector)
    end
    if ui.tabs or ui.selector then Workspace.PlaceTabDivider(ui.toolbar, ui.tabs or ui.selector) end
    ui.finished = true
    Choose(ui, ui.selected)
    if M.RelayoutPageHeaderHost then M.RelayoutPageHeaderHost() end
end

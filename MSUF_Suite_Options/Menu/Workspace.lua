local _, P = ...
local W, M, HM, Tr = P.W, P.M, P.HM, P.Tr
local Workspace, selections = {}, {}
P.MenuWorkspace = Workspace

function Workspace.FitHeader(ui, required)
    local height = math.max(ui.spec.height or 62, required)
    if ui.header:GetHeight() == height then return end
    HM.SetFixedPreviewHeight(ui.header, height)
    ui.header:SetHeight(height)
    if M.RelayoutPageHeaderHost then M.RelayoutPageHeaderHost() end
end

function Workspace.Rules(ctx, builder, page, module, section, title, rules, opts)
    opts = opts or {}
    local before = opts.onBuilt
    opts.onBuilt = function(body, entries)
        Workspace.Prepare(body, entries)
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
        for name in tab.sections:gmatch("%S+") do if suffix == name then return tab.id end end
    end
    return ui.spec.tabs[1].id
end

function Workspace.Prepare(body, entries)
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
            local meta = entry.meta or P.Meta(ui.spec.page, ui.spec.module, entry.rule.key,
                "setting", body._suiteWorkspaceSection)
            P.RegisterWorkspaceSearch(widget, meta, entry.rule, "suiteWorkspace", Reveal, entry.label)
        end
    end
end

function Workspace.Builder(ctx, spec)
    local builder = spec.builder or W.PageBuilder(ctx)
    if not builder.Section then return builder, nil end
    local height = spec.height or 62
    local header = spec.header or W.FixedPreviewSection and W.FixedPreviewSection(ctx, builder, { title = Tr(spec.title), height = height })
        or builder:Section(Tr(spec.title), height)
    HM.SetFixedPreviewHeight(header, height)
    header:SetHeight(height)
    local body = builder:Section(Tr("Settings"), 120)
    if header.title then header.title:Hide() end
    if body.title then body.title:Hide() end
    local ui = { ctx = ctx, spec = spec, builder = builder, body = body, header = header,
        width = HM.GetSectionWidth(body) or builder.width or 720, groups = {}, sections = {},
        selected = selections[spec.page] or spec.tabs[1].id }
    ctx.suiteWorkspace = ui
    ui.select = function(key)
        if ui.chooseTab then ui.chooseTab(key) else Choose(ui, key) end
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

function Workspace.Finish(ui)
    if not ui then return end
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
    if W.SegmentTabs and ui.width - 32 >= #values * 180 then
        local tabs, refresh, _, choose = W.SegmentTabs(ui.ctx, ui.header, {
            label = "", values = values, frames = panels, width = ui.width - 32,
            defaultTab = ui.selected, get = function() return ui.selected end,
            set = function(id) Choose(ui, id) end, afterRefresh = function(id) Choose(ui, id) end,
            x = 16, y = ui.spec.tabY or 12,
        })
        P.HideControlTitle(tabs)
        ui.chooseTab = choose
        refresh()
    else
        ui.selector = M.BindDropdownAt(ui.ctx, ui.header, ui.spec.title, 16, ui.spec.tabY or 12, values, ui.width - 32,
            function() return ui.selected end, function(id) Choose(ui, id) end,
            P.Meta(ui.spec.page, ui.spec.module, "view.topic", "ephemeral"))
        P.HideControlTitle(ui.selector)
    end
    ui.finished = true
    Choose(ui, ui.selected)
    if M.RelayoutPageHeaderHost then M.RelayoutPageHeaderHost() end
end

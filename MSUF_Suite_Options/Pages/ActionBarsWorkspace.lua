local _, P = ...
local W, M, Tr = P.W, P.M, P.Tr
local Page = {}
P.ActionBarMenu = Page
local selectedTab = "shared"
local details = {}
local GROUPS = {
    { id = "shared", label = "All action bars", sections = "actionbars_module look appearance cooldowns text behavior" },
    { id = "layout", label = "Layout", sections = "editor bar_layout" },
    { id = "text", label = "Text", sections = "bar_text" },
    { id = "visibility", label = "Visibility", sections = "bar_visibility" },
    { id = "appearance", label = "Appearance", sections = "bar_background bar_ornaments" },
}

function Page.IsShared(ctx)
    local workspace = ctx._msufSuiteActionBarWorkspace
    return (workspace and workspace.selected or selectedTab) == "shared"
end

local function GroupFor(sectionId)
    local suffix = sectionId:match("^suite_actionbars_(.+)$")
    for _, spec in ipairs(GROUPS) do
        for name in spec.sections:gmatch("%S+") do if name == suffix then return spec end end
    end
end

local function UpdateHeight(workspace)
    local group = workspace.groups[workspace.selected]
    local height = workspace.inset + (group and group.height or 80)
    workspace.body._msuf2CursorY = -height + 12
    workspace.builder:FinishSection(workspace.body, 12)
end

local function Choose(workspace, key)
    if not workspace.groups[key] then return end
    workspace.selected, selectedTab = key, key
    for id, group in pairs(workspace.groups) do group.frame:SetShown(id == key) end
    if workspace.selector then workspace.selector:SetValue(key) end
    UpdateHeight(workspace)
    workspace.ctx.RefreshActionBarScope()
end

local function NewWorkspace(ctx, builder)
    local body = builder:Section(Tr("Settings"), 120)
    local workspace = { ctx = ctx, builder = builder, body = body, groups = {}, sections = {}, selected = selectedTab }
    workspace.inset = ctx._msufSuiteActionBarHeader and 0 or 62
    workspace.width = body._msuf2Width or builder.width or 720
    workspace.select = function(key)
        if workspace.chooseTab then workspace.chooseTab(key) else Choose(workspace, key) end
    end
    ctx._msufSuiteActionBarWorkspace = workspace
    return workspace
end

local function ChildBuilder(workspace, spec)
    local group = workspace.groups[spec.id]
    if group then return group.builder end
    local panel = CreateFrame("Frame", nil, workspace.body)
    panel:SetPoint("TOPLEFT", workspace.body, "TOPLEFT", 0, -workspace.inset)
    panel:SetSize(workspace.width, 80)
    panel:SetShown(spec.id == workspace.selected)
    group = { frame = panel, height = 80 }
    workspace.groups[spec.id] = group
    local child = setmetatable({ wrapper = panel, width = workspace.width,
        _msuf2ContentX = 0, _msuf2TopInset = 0 }, { __index = workspace.ctx })
    function child:SetContentHeight(height)
        group.height = math.max(80, height)
        panel:SetHeight(group.height)
        if workspace.finished and workspace.selected == spec.id then UpdateHeight(workspace) end
    end
    group.builder = W.PageBuilder(child)
    return group.builder
end

function Page.Builder(ctx)
    local builder = W.PageBuilder(ctx)
    if not builder.Section then return builder end
    local workspace
    local facade = {}
    function facade:Section(...) return builder:Section(...) end
    function facade:CollapsibleSection(sectionId, title, height, open)
        local spec = GroupFor(sectionId)
        if not spec then return builder:CollapsibleSection(sectionId, title, height, open) end
        workspace = workspace or NewWorkspace(ctx, builder)
        local owner = ChildBuilder(workspace, spec)
        local preferred = sectionId == "suite_actionbars_bar_layout"
        local secondary = sectionId == "suite_actionbars_actionbars_module" or sectionId == "suite_actionbars_editor"
        local expanded = not secondary and (#owner.collapsibles == 0 or preferred)
        local body = owner:CollapsibleSection(sectionId, title, height, expanded)
        body._msufSuiteActionBarSectionId = sectionId
        body._msufSuiteActionBarBuilder = owner
        body._msufSuiteActionBarReveal = function() workspace.select(spec.id) end
        workspace.sections[#workspace.sections + 1] = body
        return body
    end
    function facade:FinishSection(body, pad)
        local owner = body._msufSuiteActionBarBuilder or builder
        return owner:FinishSection(body, pad)
    end
    -- Grouped sections sit in tab panels; hidden ones build on first show.
    facade.LazyCollapsibleSection = P.TabLazySection(builder, function(sectionId) return GroupFor(sectionId) ~= nil end)
    return setmetatable(facade, { __index = builder, __newindex = function(_, key, value) builder[key] = value end })
end

function Page.Prepare(body, entries, revealDetails)
    for _, entry in ipairs(entries or {}) do
        local widget = entry.widget
        if widget then
            local prepare = widget._msuf2PrepareExactSearchTarget
            local function Reveal()
                if body._msufSuiteActionBarReveal then body._msufSuiteActionBarReveal() end
                if revealDetails then revealDetails() end
                if prepare then prepare() end
                return true
            end
            widget._msuf2PrepareExactSearchTarget = Reveal
            local identity = entry.meta or P.Meta("suite_actionbars", "actionbars", entry.rule.key, "setting", body._msufSuiteActionBarSectionId)
            P.RegisterWorkspaceSearch(widget, identity, entry.rule, "actionbarWorkspace", Reveal, entry.label)
        end
    end
end

local function BuildDetails(ctx, builder, body, sectionId, rules, y, width, keyFn)
    if #rules == 0 then return y end
    local toggle = P.T.Button(body, "More settings", width, 26)
    toggle._msuf2SkipHistoryCheckpoint = true
    toggle._msuf2AllowCombatClick = true
    toggle:SetPoint("TOPLEFT", body, "TOPLEFT", 16, y)
    local panel = CreateFrame("Frame", nil, body)
    panel:SetPoint("TOPLEFT", body, "TOPLEFT", 0, y - 38)
    panel:SetSize(width + 32, 80)
    local bottom, entries = P.RuleGrid(ctx, panel, "suite_actionbars", "actionbars", rules, -12, width, keyFn, sectionId)
    panel:SetHeight(-bottom + 12)
    local function Show(open)
        details[sectionId] = open == true
        panel:SetShown(open == true)
        P.SetButtonText(toggle, Tr(open and "Fewer settings" or "More settings"))
        P.FinishBody(builder, body, open and y - 38 + bottom - 12 or y - 38)
    end
    toggle:SetScript("OnClick", function() Show(not details[sectionId]) end)
    if M.RegisterControlMetadata then
        M.RegisterControlMetadata(toggle, P.Meta("suite_actionbars", "actionbars", sectionId .. ".details", "ephemeral", sectionId),
            "More settings", "button")
    end
    Page.Prepare(body, entries, function() Show(true) end)
    body._msufSuiteActionBarDetails = { panel = panel, show = Show, toggle = toggle }
    Show(details[sectionId])
    return details[sectionId] and y - 38 + bottom - 12 or y - 38
end

-- Essential controls remain visible; offsets and optional fine adjustments
-- expand in place. Both sets retain their exact catalog/search identities.
-- A lazy host builds a closed section's controls on first open (P.LazySection).
function Page.Rules(ctx, builder, sectionId, title, rules, opts)
    opts = opts or {}
    local primary, advanced, entries = {}, {}, nil
    for _, rule in ipairs(rules) do
        local suffix = rule.key:match("^bar%d+(.+)$") or rule.key
        local target = (not opts.essential or opts.essential[suffix]) and primary or advanced
        target[#target + 1] = rule
    end
    local built = P.RuleRows("suite_actionbars", "actionbars", primary, opts.keyFn, sectionId)
    local function Content(body)
        body._msufSuiteActionBarSectionId = sectionId
        local width = math.max(240, (body._msuf2Width or builder.width or 720) - 32)
        local y = -18
        if opts.help then
            local hint = P.Description(body, opts.help, 16, y, width, title)
            y = y - math.max(14, math.ceil(hint:GetStringHeight() or 14)) - 12
        end
        y, entries = P.RuleGrid(ctx, body, "suite_actionbars", "actionbars", primary, y, width, opts.keyFn, sectionId, nil, built)
        Page.Prepare(body, entries)
        if opts.extra then y = opts.extra(body, y, width) or y end
        y = BuildDetails(ctx, builder, body, sectionId, advanced, y, width, opts.keyFn)
        P.AttachRuleColors(body, title, "actionbars", rules, opts.keyFn)
        return y
    end
    local body = P.LazySection(builder, sectionId, title, opts.open, {
        content = Content,
        shell = function(section)
            section._msufSuiteActionBarSectionId = sectionId
            P.AttachSectionReset(ctx, section, title, function() return P.ResetRules("actionbars", rules, opts.keyFn) end,
                opts.copy)
        end,
        summary = function(section) P.AttachRowsSummary(ctx, section, built.rows) end,
        finish = function(section, y) P.FinishBody(builder, section, y) end,
    })
    return body, entries
end

local function InstallSelector(workspace, values, panels)
    local ctx = workspace.ctx
    local body = ctx._msufSuiteActionBarHeader or workspace.body
    workspace.navigation = body
    local width = workspace.width - 32
    if W.SegmentTabs and width >= 650 then
        local tabs, refresh, _, selectTab = W.SegmentTabs(ctx, body, {
            label = "", values = values, width = width, frames = panels, defaultTab = values[1].value,
            get = function() return workspace.selected end,
            set = function(key) Choose(workspace, key) end,
            afterRefresh = function(key) Choose(workspace, key) end,
            -- MoveWidget reserves 24px above the control for its title.
            -- Hide that title and put the actual category buttons at -12.
            x = 16, y = 12,
        })
        if tabs._msuf2Title then tabs._msuf2Title:Hide() end
        workspace.chooseTab = selectTab
        refresh()
    else
        workspace.selector = M.BindDropdownAt(ctx, body, "Settings", 16, 12, values, width,
            function() return workspace.selected end, function(key) Choose(workspace, key) end,
            P.Meta("suite_actionbars", "actionbars", "view.settings", "ephemeral"))
        if workspace.selector._msuf2Title then workspace.selector._msuf2Title:Hide() end
    end
    if body.title then body.title:Hide() end
    if workspace.body.title then workspace.body.title:Hide() end
end

function Page.Finish(ctx)
    local workspace = ctx._msufSuiteActionBarWorkspace
    if not workspace then return end
    local values, panels = {}, {}
    for _, spec in ipairs(GROUPS) do
        if workspace.groups[spec.id] then
            values[#values + 1] = { value = spec.id, text = Tr(spec.label) }
            panels[spec.id] = workspace.groups[spec.id].frame
        end
    end
    for _, body in ipairs(workspace.sections) do
        local scopedControl = ctx._msufSuiteActionBarScopedControls[body._msufSuiteActionBarSectionId]
        if scopedControl then Page.Prepare(body, { scopedControl }) end
        local entry = body._msuf2CollapsibleEntry
        if entry then
            local ensure = entry._msuf2EnsureVisible
            entry._msuf2EnsureVisible = function(...)
                body._msufSuiteActionBarReveal()
                if ensure then return ensure(...) end
            end
        end
    end
    InstallSelector(workspace, values, panels)
    workspace.finished = true
    Choose(workspace, workspace.selected)
end

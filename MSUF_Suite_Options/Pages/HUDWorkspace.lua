local _, P = ...
local W, M, Tr, HM = P.W, P.M, P.Tr, P.HM
local Page = {}
P.HUDMenu = Page
local selected = "objectives"
local FEATURES = {
    { id = "objectives", label = "Objective Tracker" },
    { id = "runSummary", label = "Run Summaries" },
    { id = "announcements", label = "Announcements" },
    { id = "afkScreen", label = "AFK Screen" },
}

local function Height(ui)
    HM.SetSectionCursor(ui.body, -(ui.groups[ui.selected].height or 80) + 12)
    ui.builder:FinishSection(ui.body, 12)
end

local function Choose(ui, id)
    if not ui.groups[id] then return end
    ui.selected, selected = id, id
    for key, group in pairs(ui.groups) do group.frame:SetShown(key == id) end
    if ui.selector then ui.selector:SetValue(id) end
    Height(ui)
    ui.preview:Select(id)
end

local function Child(ui, id)
    if ui.groups[id] then return ui.groups[id].builder end
    local panel = CreateFrame("Frame", nil, ui.body)
    panel:SetPoint("TOPLEFT")
    panel:SetSize(ui.width, 80)
    panel:SetShown(id == ui.selected)
    local group = { frame = panel, height = 80 }
    ui.groups[id] = group
    local child = setmetatable(HM.SetBuilderInsets({ wrapper = panel, width = ui.width }, 0, 0),
        { __index = ui.ctx })
    function child:SetContentHeight(height)
        group.height = math.max(80, height)
        panel:SetHeight(group.height)
        if ui.finished and ui.selected == id then Height(ui) end
    end
    group.builder = W.PageBuilder(child)
    return group.builder
end

function Page.Builder(ctx)
    local builder = W.PageBuilder(ctx)
    local header
    if W.FixedPreviewSection then
        header = W.FixedPreviewSection(ctx, builder, { title = Tr("Preview"), height = 310 })
        HM.SetFixedPreviewHeight(header, 310)
        header:SetHeight(310)
    else header = builder:Section(Tr("Preview"), 310) end
    local body = builder:Section(Tr("Settings"), 120)
    if header.title then header.title:Hide() end
    if body.title then body.title:Hide() end
    local ui = { ctx = ctx, builder = builder, body = body, header = header,
        width = HM.GetSectionWidth(body) or builder.width, selected = selected, groups = {}, sections = {} }
    ctx._msufSuiteHUDWorkspace = ui
    ui.select = function(id)
        if ui.chooseTab then ui.chooseTab(id) else Choose(ui, id) end
    end
    local facade = {}
    function facade:CollapsibleSection(sectionId, title, height, open)
        local id = sectionId:match("^suite_hud_([^_]+)_")
        if id == "summary" then id = "runSummary" end
        local owner = Child(ui, id)
        local section = owner:CollapsibleSection(sectionId, title, height, open)
        if sectionId:match("_module$") then ui.groups[id].body = section end
        if sectionId:match("_type$") then ui.groups[id].appearance = section end
        section._msufSuiteHUDSectionID = sectionId
        section._msufSuiteHUDID = id
        section._msufSuiteHUDBuilder = owner
        section._msufSuiteHUDReveal = function() ui.select(id) end
        ui.sections[#ui.sections + 1] = section
        return section
    end
    function facade:FinishSection(section, pad)
        return section._msufSuiteHUDBuilder:FinishSection(section, pad)
    end
    -- Every section sits in a feature panel; hidden ones build on first show.
    facade.LazyCollapsibleSection = P.TabLazySection(builder, function() return true end)
    return setmetatable(facade, { __index = builder })
end

-- Exact search must reveal both the feature before the host opens its accordion. Metadata
-- retains the catalog identity so saved search links and undo still work.
function Page.Prepare(body, entries)
    for _, entry in ipairs(entries or {}) do
        local widget = entry.widget
        if widget then
            local prepare = HM.GetSearchTargetPrepare(widget)
            local function Reveal()
                body._msufSuiteHUDReveal()
                if prepare then prepare() end
                return true
            end
            HM.SetSearchTargetPrepare(widget, Reveal)
            local identity = entry.meta or P.Meta("suite_hud", body._msufSuiteHUDID, entry.rule.key, "setting", body._msufSuiteHUDSectionID)
            P.RegisterWorkspaceSearch(widget, identity, entry.rule, "hudWorkspace", Reveal, entry.label)
        end
    end
end

function Page.PrepareControl(body, widget, key, kind, label)
    local id = body._msufSuiteHUDID
    Page.Prepare(body, { { widget = widget, rule = { key = key, label = label },
        meta = P.Meta("suite_hud", id, key, kind, "suite_hud_" .. id .. "_module") } })
end

function Page.Finish(ctx)
    local ui = ctx._msufSuiteHUDWorkspace
    local values, panels = {}, {}
    for _, spec in ipairs(FEATURES) do
        values[#values + 1] = { value = spec.id, text = Tr(spec.label) }
        panels[spec.id] = ui.groups[spec.id].frame
    end
    for _, body in ipairs(ui.sections) do
        local entry = HM.GetSectionEntry(body)
        if entry then
            local ensure = HM.GetSectionEnsureVisible(entry)
            HM.SetSectionEnsureVisible(entry, function(...)
                body._msufSuiteHUDReveal()
                if ensure then return ensure(...) end
            end)
        end
    end
    ui.preview = P.HUDPreview.Build(ctx, ui.header, ui.width - 32)
    if W.SegmentTabs and ui.width - 32 >= 650 then
        local tabs, refresh, _, selectTab = W.SegmentTabs(ctx, ui.header, {
            label = "", values = values, width = ui.width - 32, frames = panels, defaultTab = selected,
            get = function() return ui.selected end, set = function(id) Choose(ui, id) end,
            afterRefresh = function(id) Choose(ui, id) end, x = 16, y = 12,
        })
        P.HideControlTitle(tabs)
        ui.chooseTab = selectTab
        refresh()
    else
        ui.selector = M.BindDropdownAt(ctx, ui.header, "HUD", 16, 12, values, ui.width - 32,
            function() return ui.selected end, function(id) Choose(ui, id) end,
            P.Meta("suite_hud", "objectives", "view.feature", "ephemeral"))
        P.HideControlTitle(ui.selector)
    end
    ui.finished = true
    Choose(ui, ui.selected)
    if M.RelayoutPageHeaderHost then M.RelayoutPageHeaderHost() end
end

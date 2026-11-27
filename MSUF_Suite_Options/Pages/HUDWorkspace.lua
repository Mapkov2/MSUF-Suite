local _, P = ...
local W, M, Tr, HM = P.W, P.M, P.Tr, P.HM
local Page = {}
P.HUDMenu = Page
local PAGE = "suite_hud"
local selected = "objectives"
local FEATURES = {
    { id = "objectives", label = "Objective Tracker" },
    { id = "runSummary", label = "Run Summaries" },
    { id = "announcements", label = "Announcements" },
    { id = "afkScreen", label = "AFK Screen" },
    { id = "planningTools", label = "Adventure planner" },
    { id = "characterPanel", label = "Character Panel" },
    { id = "extras", label = "Additional displays" },
}

local function CharacterSkinEnabled()
    return P.Suite.Client.AddOnEnabled("MSUF_Suite_Skin")
end

local function ResetFeature(id)
    if id == "extras" then return P.QoLOwners.Reset(PAGE, true) end
    if not P.S.Reset(id) then return false end
    if id == "characterPanel" and CharacterSkinEnabled() then P.SkinPageKit.ResetCharacter() end
    return true
end

function Page.ResetKey()
    return PAGE .. ":" .. selected
end

Page.ResetTargets = {}
for index, feature in ipairs(FEATURES) do
    local id = feature.id
    local target = {
        key = PAGE .. ":" .. id, title = feature.label, ownerPage = PAGE,
        resetPage = function() return ResetFeature(id) end,
    }
    if id == "extras" then
        target.canReset = function() return P.QoLOwners.HasFeatures(PAGE) end
    elseif id == "characterPanel" then
        target.prepareReset = function()
            return not CharacterSkinEnabled() or P.SkinPageKit.Engine() ~= nil
        end
    end
    Page.ResetTargets[index] = target
end

local function Height(ui)
    HM.SetSectionCursor(ui.body, -(ui.groups[ui.selected].height or 80) + 12)
    ui.builder:FinishSection(ui.body, 12)
end

local function PreviewHeight(ui, height)
    ui.previewBaseHeight = height
    height = height + (ui.tabsExtra or 0)
    if ui.previewHeight == height then return end
    ui.previewHeight = height
    HM.SetFixedPreviewHeight(ui.header, height)
    ui.header:SetHeight(height)
    if M.RelayoutPageHeaderHost then M.RelayoutPageHeaderHost() end
end

local function Choose(ui, id)
    if not ui.groups[id] then return end
    local changed = selected ~= id
    ui.selected, selected = id, id
    for key, group in pairs(ui.groups) do group.frame:SetShown(key == id) end
    if ui.selector then ui.selector:SetValue(id) end
    Height(ui)
    local hasPreview = id ~= "extras" and id ~= "characterPanel" and id ~= "planningTools"
    ui.preview:Select(hasPreview and id or nil)
    local character = id == "characterPanel"
    if character and not ui.characterPreview then
        ui.characterPreview = P.CharacterPanelEditor.Build(ui.ctx, ui.previewContent, function(height)
            ui.characterPreviewHeight = height
            if ui.selected == "characterPanel" then PreviewHeight(ui, height) end
        end)
    end
    if ui.characterPreview then ui.characterPreview:SetShown(character) end
    PreviewHeight(ui, character and (ui.characterPreviewHeight or 204) or hasPreview and 326 or 62)
    if changed and M.RefreshToolbarPageReset then M.RefreshToolbarPageReset() end
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
    local header, toolbar
    if W.FixedPreviewSection then
        header, toolbar = W.FixedPreviewSection(ctx, builder, { title = Tr("Preview"), height = 310 })
        HM.SetFixedPreviewHeight(header, 310)
        header:SetHeight(310)
    else header = builder:Section(Tr("Preview"), 310) end
    local body = builder:Section(Tr("Settings"), 120)
    if header.title then header.title:Hide() end
    if body.title then body.title:Hide() end
    local ui = { ctx = ctx, builder = builder, body = body, header = header, toolbar = toolbar,
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
        if sectionId:match("_artwork$") then ui.groups[id].artwork = section end
        if sectionId:match("_frame$") then ui.groups[id].bannerFrame = section end
        section._msufSuiteHUDSectionID = sectionId
        section._msufSuiteHUDID = id
        section._msufSuiteHUDBuilder = owner
        section._msufSuiteHUDReveal = function() ui.select(id) end
        ui.sections[sectionId] = section
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

function Page.BuildHelpers(ctx)
    local ui = ctx._msufSuiteHUDWorkspace
    P.QoLOwners.Build(ctx, Child(ui, "extras"), "suite_hud", function() ui.select("extras") end)
end

local function PrepareSections(ui)
    local page = ui.ctx.entry or ui.ctx
    local previous = HM.GetMissingSectionResolver(page)
    -- Search can land on an already-open accordion inside a hidden HUD tab.
    HM.SetMissingSectionResolver(page, function(sectionId)
        local section = ui.sections[sectionId]
        if not section then return previous and previous(sectionId) end
        section._msufSuiteHUDReveal()
        return section
    end)
    for _, body in pairs(ui.sections) do
        local entry = HM.GetSectionEntry(body)
        if entry then
            local ensure = HM.GetSectionEnsureVisible(entry)
            HM.SetSectionEnsureVisible(entry, function(...)
                body._msufSuiteHUDReveal()
                if ensure then return ensure(...) end
            end)
        end
    end
end

function Page.Finish(ctx)
    local ui = ctx._msufSuiteHUDWorkspace
    local values, panels = {}, {}
    if ui.selected == "extras" and not P.QoLOwners.HasFeatures("suite_hud") then ui.selected, selected = "objectives", "objectives" end
    for _, spec in ipairs(FEATURES) do
        if spec.id ~= "extras" or P.QoLOwners.HasFeatures("suite_hud") then
            values[#values + 1] = { value = spec.id, text = Tr(spec.label) }
            panels[spec.id] = ui.groups[spec.id].frame
        end
    end
    PrepareSections(ui)
    local content = CreateFrame("Frame", nil, ui.header)
    content:SetPoint("TOPLEFT", ui.header, "TOPLEFT", 0, 0)
    content:SetSize(ui.width, 1)
    ui.previewContent = content
    ui.preview = P.HUDPreview.Build(ctx, content, ui.width - 32)
    local selector
    if W.SegmentTabs and ui.width - 32 >= math.max(650, #values * 126) then
        local tabs, refresh, _, selectTab = W.SegmentTabs(ctx, ui.header, {
            label = "", compact = true, wrap = true, values = values, width = ui.width - 32, frames = panels, defaultTab = selected,
            get = function() return ui.selected end, set = function(id) Choose(ui, id) end,
            afterRefresh = function(id) Choose(ui, id) end, x = 16, y = 12,
        })
        P.HideControlTitle(tabs)
        selector = tabs
        ui.chooseTab = selectTab
        local function Fit()
            local extra = math.max(0, tabs:GetHeight() - 26)
            if ui.tabsExtra == extra then return end
            ui.tabsExtra = extra
            content:ClearAllPoints()
            content:SetPoint("TOPLEFT", ui.header, "TOPLEFT", 0, -extra)
            PreviewHeight(ui, ui.previewBaseHeight or 326)
        end
        tabs:HookScript("OnSizeChanged", Fit)
        Fit()
        refresh()
    else
        ui.selector = M.BindDropdownAt(ctx, ui.header, "HUD", 16, 12, values, ui.width - 32,
            function() return ui.selected end, function(id) Choose(ui, id) end,
            P.Meta("suite_hud", "objectives", "view.feature", "ephemeral"))
        P.HideControlTitle(ui.selector)
    end
    P.MenuWorkspace.PlaceTabDivider(ui.toolbar, selector or ui.selector)
    ui.finished = true
    Choose(ui, ui.selected)
    if M.RelayoutPageHeaderHost then M.RelayoutPageHeaderHost() end
end

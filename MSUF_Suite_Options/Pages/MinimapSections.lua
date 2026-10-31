local _, P = ...
local W, M, HM, Tr = P.W, P.M, P.HM, P.Tr
local PAGE, ID = "suite_minimap", "minimap"
local Menu, selections = {}, {}
P.MinimapSections = Menu

function Menu.IsMinimapSectionAvailable(source)
    return not (P.Suite.Client.isForever and (source == "specialization" or source == "landing"))
end

local function MinimapRules(sources, offsets)
    local rules, wanted = {}, {}
    for _, source in ipairs(sources) do wanted[source] = true end
    for _, rule in ipairs(P.catalog[ID].controls) do
        if wanted[rule.section] and rule.key ~= "captured" and (offsets or not rule.previewOnly) then
            rules[#rules + 1] = rule
        end
    end
    return rules
end

local sectionTitles = {}
for _, rule in ipairs(P.catalog[ID].controls) do
    if rule.section then sectionTitles[rule.section] = rule.sectionTitle end
end
sectionTitles.info_calendarday = "Calendar day"
local function MinimapTitle(source)
    return sectionTitles[source] or ""
end

local function PrepareMinimapEntries(menu, entries)
    for _, entry in ipairs(entries or {}) do
        if entry.widget then
            local source = entry.rule.section
            local previous = HM.GetSearchTargetPrepare(entry.widget)
            local function Reveal()
                if not menu:SelectMinimapSettings(source) then return false end
                if previous then previous() end
                return true
            end
            HM.SetSearchTargetPrepare(entry.widget, Reveal)
            local meta = P.Meta(PAGE, ID, entry.rule.key, "setting", PAGE .. "_" .. source)
            P.RegisterWorkspaceSearch(entry.widget, meta, entry.rule, "minimapSection", Reveal, entry.rule.label)
        end
    end
end

local function RefreshMinimapSummary(menu, group)
    if not W.SetCollapsibleSummary then return end
    local parts = {}
    if group.id == "information" then
        for _, field in ipairs(P.Suite.MinimapInfoFields) do
            if P.Get(ID, "info" .. field) then parts[#parts + 1] = Tr(field == "CalendarDay" and "Calendar day" or field) end
        end
        if P.Get(ID, "infoDifficulty") then parts[#parts + 1] = Tr("Difficulty") end
    else
        parts[1] = Tr(MinimapTitle(group.selected))
    end
    W.SetCollapsibleSummary(group.body, #parts > 0 and table.concat(parts, " \194\183 ") or Tr("None"))
end

local function BuildMinimapView(menu, group, source, width)
    local view = group.views[source]
    if view then return view end
    local panel = CreateFrame("Frame", nil, group.body)
    panel:SetPoint("TOPLEFT", group.body, "TOPLEFT", 0, group.top)
    panel:SetWidth(width + 32)
    local first = #menu.ctx.refreshers + 1
    P.Text(panel, MinimapTitle(source), 16, -12, width - 50, P.T.colors.text)
    local y = -42
    if menu.helpBySection[source] then
        local help = P.Description(panel, menu.helpBySection[source], 16, y, width, MinimapTitle(source))
        y = y - math.max(14, math.ceil(help:GetStringHeight() or 14)) - 12
    end
    local rules, entries = MinimapRules({ source }), nil
    y, entries = P.RuleGrid(menu.ctx, panel, PAGE, ID, rules, y, width, nil, PAGE .. "_" .. source)
    P.AttachRuleColors(panel, MinimapTitle(source), ID, rules)
    panel:SetHeight(-y + 12)
    view = { frame = panel, height = -y + 12, entries = entries }
    group.views[source] = view
    PrepareMinimapEntries(menu, entries)
    for index = first, #menu.ctx.refreshers do menu.ctx.refreshers[index]() end
    return view
end

local function RefreshMinimapResetTitle(group)
    if group.popup then P.SetTranslatedText(group.popup.heading, Tr(MinimapTitle(group.selected))) end
end

local function DrawMinimapGroup(menu, group, source, width)
    local view = BuildMinimapView(menu, group, source, width)
    for key, item in pairs(group.views) do item.frame:SetShown(key == source) end
    if group.selector then group.selector:SetValue(source) end
    group.bottom = group.top - view.height
    if group.ready then P.FinishBody(menu.builder, group.body, group.bottom) end
    RefreshMinimapSummary(menu, group)
    RefreshMinimapResetTitle(group)
end

local function BuildMinimapContent(menu, group, body)
    group.body = body
    local width = math.max(240, (HM.GetSectionWidth(body) or menu.builder.width or 720) - 32)
    local values = {}
    for _, source in ipairs(group.sources) do values[#values + 1] = { value = source, text = Tr(MinimapTitle(source)) } end
    group.selector = M.BindDropdownAt(menu.ctx, body, group.label, 16, -18, values, width,
        function() return group.selected end, function(source) menu:SelectMinimapSettings(source) end,
        P.Meta(PAGE, ID, group.id .. ".selected", "ephemeral", PAGE .. "_" .. group.id))
    local hint = P.Text(body, "Changes and resets apply only to the selected item.", 16, -78, width)
    group.top = -78 - math.max(14, math.ceil(hint:GetStringHeight() or 14)) - 12
    group.draw = function(source) DrawMinimapGroup(menu, group, source, width) end
    group.draw(group.selected)
end

local function BuildMinimapGroup(menu, id, title, label, sources)
    local group = { id = id, sources = {}, views = {}, label = label }
    for _, source in ipairs(sources) do
        if Menu.IsMinimapSectionAvailable(source) then
            group.sources[#group.sources + 1] = source
            menu.routes[source] = group
        end
    end
    group.selected = group.sources[1]
    for _, source in ipairs(group.sources) do if selections[id] == source then group.selected = source end end
    menu.groups[id] = group
    group.body = P.LazySection(menu.builder, PAGE .. "_" .. id, Tr(title), false, {
        content = function(body) BuildMinimapContent(menu, group, body) return group.bottom end,
        finish = function(body, y)
            group.ready = true
            P.FinishBody(menu.builder, body, y)
        end,
        summary = function(body)
            group.body = body
            RefreshMinimapSummary(menu, group)
        end,
        shell = function(body)
            P.AttachSectionReset(menu.ctx, body, title, function()
                return P.ResetRules(ID, MinimapRules({ group.selected }, true))
            end, nil, function(popup)
                group.popup = popup
                popup:HookScript("OnShow", function() RefreshMinimapResetTitle(group) end)
                popup:Hide()
            end)
        end,
    })
    for _, source in ipairs(group.sources) do menu.sections[source] = group.body end
    M.TrackRefresh(menu.ctx, function() RefreshMinimapSummary(menu, group) end)
    return group
end

function Menu:SelectMinimapSettings(source)
    local group = self.routes[source]
    if not group then return false end
    if group.sources then
        if P.Combat() and not group.views[source] then
            if group.selector then group.selector:SetValue(group.selected) end
            return false
        end
        group.selected, selections[group.id] = source, source
        if group.draw then group.draw(source) else P.EnsureSectionContent(group.body) end
        return group.views[source] ~= nil
    end
    if P.Combat() and group.body._suiteMinimapReady ~= true then return false end
    P.EnsureSectionContent(group.body)
    return true
end

function Menu:ResolveMinimapSection(source)
    if not self.routes[source] then
        local body = self.sections[source]
        P.EnsureSectionContent(body)
        return body
    end
    if self:SelectMinimapSettings(source) then return self.routes[source].body end
end

local function BuildMinimapSection(menu, source, sources, extra)
    local help = menu.helpBySection[source]
    if #sources > 1 then help = P.Help(help, menu.helpBySection[sources[2]]) end
    local body = P.RuleSection(menu.ctx, menu.builder, PAGE, ID, PAGE .. "_" .. source, Tr(MinimapTitle(source)), MinimapRules(sources), {
        help = help, open = source == "layout", extra = extra,
        onBuilt = function(body, entries)
            body._suiteMinimapReady = true
            PrepareMinimapEntries(menu, entries)
        end,
    })
    for _, name in ipairs(sources) do
        menu.routes[name], menu.sections[name] = { body = body }, body
    end
end

function Menu.BuildMinimapSections(ctx, builder, sections, help, skinStatus)
    local menu = setmetatable({ ctx = ctx, builder = builder, sections = sections, helpBySection = help,
        routes = {}, groups = {} }, { __index = Menu })
    ctx.minimapSections = menu
    BuildMinimapSection(menu, "layout", { "layout", "hover_size" })
    BuildMinimapSection(menu, "shape", { "shape" }, skinStatus)
    BuildMinimapGroup(menu, "decoration", "Decoration", "Decoration", { "style_art", "style_glow", "style_backdrop" })
    BuildMinimapSection(menu, "behavior", { "behavior" })
    BuildMinimapGroup(menu, "buttons", "Blizzard buttons", "Button settings", { "elements", "landing", "dungeon", "specialization" })
    BuildMinimapSection(menu, "addons", { "addons" }, P.MinimapKeptButtons(ctx, builder))
    local info = {}
    for _, field in ipairs(P.Suite.MinimapInfoFields) do info[#info + 1] = "info_" .. field:lower() end
    info[#info + 1], info[#info + 2] = "info_difficulty", "info_colors"
    BuildMinimapGroup(menu, "information", "Information displays", "Information display", info)
    BuildMinimapSection(menu, "info_tooltips", { "info_tooltips" })
    sections.ResolveMinimapSection = function(source) return menu:ResolveMinimapSection(source) end
    if ctx.entry then
        HM.SetMissingSectionResolver(ctx.entry, function(sectionId)
            local source = sectionId:match("^suite_minimap_(.+)$")
            if source then return menu:ResolveMinimapSection(source) end
        end)
    end
    return menu
end

local _, P = ...
local W, M, T, Tr, HM = P.W, P.M, P.T, P.Tr, P.HM
local PAGE, ID = "suite_dataTexts", "dataTexts"
local MODULE_SECTION = PAGE .. "_dataTexts_module"
local DELETE_BARS = { title = Tr("Delete bars"), action = Tr("Delete selected bars"),
    key = "datatext-delete-bars", question = Tr("Delete these bars?") }
local Page = { selectedBar = 1, selections = {} }
P.DataTextPage = Page

local function OpenMenuTarget(page, id, key, kind, section)
    local bridge = M.SearchBridge
    if not bridge or not bridge.OpenSearchTarget then return end
    bridge.OpenSearchTarget(page, "", nil, nil, {}, P.Meta(page, id, key, kind, section))
end

local MENU_ACTION = { role = "success", fontRole = "heading", height = 48, wrap = true }
local function OpenMicroMenuPreset()
    OpenMenuTarget(PAGE, ID, "preset.microMenu", "action", PAGE .. "_presets")
end

function Page.MicroMenuPresetLink(ctx, body, y, width, prepare)
    if not ctx.searchRows then
        local question = P.Text(body, "Prefer a single menu button?", 16, y - 8, width, nil, "heading")
        y = y - math.max(20, math.ceil(question:GetStringHeight() or 20)) - 14
        local help = P.Text(body, "Opens the same game menus as the Modern data bar.", 16, y, width, nil, "section")
        y = y - math.max(18, math.ceil(help:GetStringHeight() or 18)) - 12
    end
    local button = P.SkinSearchButton(ctx, body, "Open the micro menu button preset", 16, y, width,
        OpenMicroMenuPreset, function() return P.Suite.Client.AddOnEnabled("MSUF_Suite_DataTexts") end,
        P.Meta("suite_skin", "skin", "micro.dataTexts", "action", "suite_skin_micro"), MENU_ACTION)
    if button then HM.SetSearchTargetPrepare(button, prepare) end
    return y - (button and button:GetHeight() or MENU_ACTION.height) - 14
end

function Page.OpenMicroMenuSkin()
    OpenMenuTarget("suite_skin", "skin", "skins.microMenu", "setting", "suite_skin_micro")
end

-- A bar the player cleared the name of reads "Bar N", as in the layer
-- overview and search (Menu/Register.lua).
function Page.BarName(bar)
    local name = P.Get(ID, "bar" .. bar .. "Name")
    if type(name) ~= "string" or name == "" then return Tr("Bar %d"):format(bar) end
    return name
end
local builtBarIDs, barRevision = nil, 0

-- Views are built on first selection. Selecting a tab never writes the profile.
function Page.Deck(ctx, parent, width, y, changed, compact)
    local deck = { views = {}, width = width, y = y }
    function deck:SetY(offset)
        if self.y == offset then return end
        self.y = offset
        for _, view in pairs(self.views) do
            view.frame:ClearAllPoints()
            view.frame:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, offset)
        end
    end
    function deck:Select(key, build)
        local view = self.views[key]
        if not view then
            local frame = CreateFrame("Frame", nil, parent)
            frame:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, self.y)
            frame:SetSize(width, 80)
            view = { frame = frame, height = 80 }
            self.views[key] = view
            local child = setmetatable(HM.SetBuilderInsets({ wrapper = frame, width = width }, 0, 0),
                { __index = ctx })
            function child:SetContentHeight(height)
                -- Embedded accordion decks use their laid-out bottom, not the
                -- page builder's extra scroll footer or its trailing row gap.
                if compact then height = math.abs(view.builder.y) - 8 end
                view.height = math.max(compact and 0 or 80, height)
                frame:SetHeight(view.height)
                if deck.selected == key then changed(view.height) end
            end
            view.ctx, view.builder = child, W.PageBuilder(child)
            local first = #ctx.refreshers + 1
            build(view, child, view.builder)
            for index = first, #ctx.refreshers do ctx.refreshers[index]() end
        end
        self.selected = key
        for id, item in pairs(self.views) do item.frame:SetShown(id == key) end
        changed(view.height)
        return view
    end
    return deck
end

function Page.Prepare(entries, sectionId, reveal)
    for _, item in ipairs(entries or {}) do
        local widget = item.widget
        if widget then
            local before = HM.GetSearchTargetPrepare(widget)
            local function Prepare()
                reveal()
                if before then before() end
                return true
            end
            local meta = item.meta or P.Meta(PAGE, ID, item.rule.key, "setting", sectionId)
            meta.prepareExactSearchTarget = Prepare
            meta.searchPrepareKind, meta.searchPrepareValue = "dataTextWorkspace", sectionId
            HM.SetSearchTargetPrepare(widget, Prepare)
            if M.RegisterControlMetadata then
                M.RegisterControlMetadata(widget, meta, item.label or item.rule.label)
            end
        end
    end
end

function Page.Button(ctx, body, label, x, y, width, click, key, section, reveal, enabled)
    local meta = P.Meta(PAGE, ID, key, "action", section)
    local button = P.Button(ctx, body, label, x, y, width, click, enabled or function() return true end, meta)
    if reveal then Page.Prepare({ { widget = button, meta = meta, label = label } }, section, reveal) end
    return button
end

function P.RefreshDataTextPageShape()
    if builtBarIDs == nil or P.Combat() then return end
    local ids = table.concat(P.Suite.DataTextBarIDs(P.S.Config(ID)), ",")
    if builtBarIDs == ids then return end
    builtBarIDs, barRevision = nil, barRevision + 1
    local rebuilt = M.activeKey == PAGE and M.RebuildPageKeepingScroll and M.RebuildPageKeepingScroll(PAGE)
    if not rebuilt and M.InvalidatePage then M.InvalidatePage(PAGE) end
end

function Page.ChangeBars(values, bar)
    local previous = Page.selectedBar
    if bar then Page.selectedBar = bar end
    if P.SetMany(ID, values) then return true end
    Page.selectedBar = previous
    return false
end

local function RemoveBars(ids, removed)
    local kept, values, nextBar = {}, {}, nil
    for _, bar in ipairs(ids) do
        if removed[bar] then
            values["bar" .. bar .. "Enabled"] = false
        else
            kept[#kept + 1] = bar
            if not nextBar and bar > Page.selectedBar then nextBar = bar end
        end
    end
    values.barIds = #kept > 0 and table.concat(kept, ",") or "0"
    local selected = Page.selectedBar
    if removed[selected] then selected = nextBar or kept[#kept] end
    Page.ChangeBars(values, selected)
end

function Page.OpenBarRemoval(anchor, selected)
    if P.Combat() then return end
    local config = P.S.Config(ID)
    local ids, revision = P.Suite.DataTextBarIDs(config), barRevision
    local signature, rows = table.concat(ids, ","), {}
    for _, bar in ipairs(ids) do
        local name = Page.BarName(bar)
        rows[#rows + 1] = { bar = bar, name = name, text = name .. "  #" .. bar, selected = bar == selected }
    end
    P.OpenDeletePicker(anchor, rows, DELETE_BARS, function(picks)
        if config ~= P.S.Config(ID) or revision ~= barRevision
            or signature ~= table.concat(P.Suite.DataTextBarIDs(config), ",") then return end
        local removed = {}
        for _, item in ipairs(picks) do
            if Page.BarName(item.bar) ~= item.name then return end
            removed[item.bar] = true
        end
        RemoveBars(ids, removed)
    end)
end

function Page.Rules(ctx, builder, sectionId, title, rules, reveal, opts)
    opts = opts or { open = true }
    opts.onBuilt = function(_, built) Page.Prepare(built, sectionId, reveal) end
    local body, entries = P.RuleSection(ctx, builder, PAGE, ID, sectionId, title, rules, opts)
    local entry = HM.GetSectionEntry(body)
    if entry then HM.SetSectionEnsureVisible(entry, reveal) end
    return body, entries
end

-- Keep every accordion header in the page, but create its controls only when
-- opened. Exact search uses the same shell and materializes it synchronously.
function Page.LazySection(ctx, builder, sectionId, title, reveal, build)
    local body = builder:CollapsibleSection(sectionId, title, 80, false)
    local entry, built = HM.GetSectionEntry(body), false
    P.FinishBody(builder, body, -68)
    local proxy = setmetatable({}, { __index = builder })
    function proxy:CollapsibleSection() return body end
    -- This section is lazy already: what it builds, it builds at once.
    proxy.LazyCollapsibleSection = false
    local function Ensure()
        if built then return end
        built = true
        local first = #ctx.refreshers + 1
        build(proxy)
        for index = first, #ctx.refreshers do ctx.refreshers[index]() end
    end
    local function Refresh()
        if entry.open then Ensure() end
    end
    if entry then
        HM.SetSectionEnsureVisible(entry, reveal)
        HM.SetSectionRefreshState(entry, Refresh)
        body:HookScript("OnShow", Refresh)
        Refresh()
    else Ensure() end
    return { body = body, ensure = Ensure }
end

function Page.OpenSection(body)
    local entry = body and HM.GetSectionEntry(body)
    if not entry then return end
    entry.open = true
    body:Show()
    local refresh = HM.GetSectionRefreshState(entry)
    if refresh then refresh(entry) end
    entry.builder:RelayoutCollapsibles()
end

function P.DataTextSearchTarget(rule)
    local bar, slot = rule.key:match("^bar(%d+)Slot(%d+)")
    if bar then
        local block = "bar" .. bar .. "Slot" .. slot
        local suffix = (rule.key == block or rule.key == block .. "MenuLabel") and "" or "_details"
        return PAGE .. "_bar" .. bar .. "_slot" .. slot .. suffix
    end
    bar = rule.key:match("^bar(%d+)")
    if not bar then return rule.section and PAGE .. "_" .. rule.section end
    local base = PAGE .. "_bar" .. bar
    if rule.key:find("LoadCond", 1, true) or rule.key == "bar" .. bar .. "Visibility" then
        return base .. "_visibility"
    end
    if rule.key == "bar" .. bar .. "Name" or rule.key == "bar" .. bar .. "Enabled" then return base end
    return base .. "_appearance"
end

local function InstallResolver(ctx, bars, choose)
    local present = {}
    for _, bar in ipairs(bars) do present[bar] = true end
    if ctx.entry then
        HM.SetMissingSectionResolver(ctx.entry, function(section)
            local bar, suffix = section:match("^suite_dataTexts_bar(%d+)(.*)$")
            if bar and present[tonumber(bar)] and suffix == "_presets" then choose("preset" .. bar)
            elseif bar and present[tonumber(bar)] then
                local slot, detail = suffix:match("^_slot(%d+)(.*)$")
                if slot and (tonumber(slot) < 1 or tonumber(slot) > P.Suite.DataTextSlotLimit) then return end
                local mode = slot and (detail == "_details" and "details" or "content") or suffix == "_appearance" and "appearance"
                    or suffix == "_visibility" and "visibility" or nil
                choose(tonumber(bar), mode, tonumber(slot))
            elseif section == PAGE .. "_presets" then choose("add")
            elseif section:match("^suite_dataTexts_") then choose("shared") end
            -- Lazy hosts: exact search reads the controls right after this.
            local body = ctx.entry.sections[section]
            P.EnsureSectionContent(body)
            return body
        end)
    end
    return present
end

local ACTION_ROW_Y, ACTION_HEIGHT = -42, 28
-- MoveWidget positions the dropdown 24 px below its hidden title.
local SELECTOR_TITLE_Y = ACTION_ROW_Y + 24

local function FitNavigation(ctx, navigation, buttons)
    local width = navigation:GetWidth()
    if width <= 0 or navigation.suiteTabsWidth == width then return end
    navigation.suiteTabsWidth = width
    local compact = width < 520
    local actionWidth = compact and (width - 38) / 2 or 146
    local selectorWidth = width - 32 - (compact and 0 or 2 * (actionWidth + 6))
    local selector = ctx.dataTextBarSelector
    local titleY = SELECTOR_TITLE_Y + (selector:GetHeight() - ACTION_HEIGHT) / 2
    W.MoveWidget(selector, navigation, 16, titleY, math.max(1, selectorWidth))
    for index, button in ipairs(buttons) do
        button:SetWidth(math.max(1, actionWidth))
        button:ClearAllPoints()
        local x = compact and 16 or 22 + selectorWidth
        button:SetPoint("TOPLEFT", navigation, "TOPLEFT", x + (index - 1) * (actionWidth + 6), compact and -76 or ACTION_ROW_Y)
    end
    navigation:SetHeight(compact and 116 or 82)
end

-- Navigation and module activation share one fixed panel above the scrolling editor.
local function Navigation(ctx, builder, bars, choose, selection)
    local navigation = builder:Section(Tr("DataTexts"), 82)
    if navigation.title then navigation.title:Hide() end
    P.Text(navigation, "DataTexts", 16, -12, 160, T.colors.text, "heading")
    local toggle = W.SwitchAt(navigation, Tr("Enable"), 0, 0, 68, "LEFT")
    toggle:ClearAllPoints()
    toggle:SetPoint("TOPRIGHT", navigation, "TOPRIGHT", -16, -12)
    M.BindBoolWidget(ctx, toggle, function() return P.Get(ID, "enabled") end,
        function(value) P.Set(ID, "enabled", value == true) end, P.Meta(PAGE, ID, "enabled", "setting", MODULE_SECTION))
    if ctx.entry then
        ctx.entry.sections = ctx.entry.sections or {}
        ctx.entry.sections[MODULE_SECTION] = navigation
    end
    local function Values()
        local values = {}
        for _, bar in ipairs(bars) do values[#values + 1] = { value = bar, text = Page.BarName(bar), translate = false } end
        values[#values + 1] = { value = "shared", text = Tr("All bars"), translate = false }
        return values
    end
    local picker = M.BindDropdownAt(ctx, navigation, "Bar", 16, SELECTOR_TITLE_Y, Values, 180,
        selection, choose, P.Meta(PAGE, ID, "view.bar", "ephemeral"))
    P.HideControlTitle(picker)
    ctx.dataTextBarSelector = picker
    local add = T.RoleButton(navigation, "+ " .. Tr("Add bar"), "success", 146, ACTION_HEIGHT)
    local delete = T.RoleButton(navigation, Tr("Delete bars"), "destructive", 146, ACTION_HEIGHT)
    add:SetScript("OnClick", function() if not P.Combat() then choose("add") end end)
    delete:SetScript("OnClick", function(button) Page.OpenBarRemoval(button) end)
    HM.SkipHistoryCheckpoint(add)
    HM.SkipHistoryCheckpoint(delete)
    Page.Prepare({ { widget = add, label = "Add bar",
        meta = P.Meta(PAGE, ID, "action.addBar", "action", PAGE .. "_presets") } },
        PAGE .. "_presets", function() choose("add") end)
    if M.RegisterControlMetadata then
        M.RegisterControlMetadata(delete, P.Meta(PAGE, ID, "action.deleteBars", "action", MODULE_SECTION), Tr("Delete bars"), "button")
    end
    M.TrackRefresh(ctx, function()
        local editable = not P.Combat()
        W.SetControlEnabled(toggle, editable)
        W.SetControlEnabled(picker, editable)
        add:SetEnabled(editable and #bars < P.Suite.DataTextBarLimit)
        delete:SetEnabled(editable and #bars > 0)
    end)
    local actions = { add, delete }
    local function Fit() FitNavigation(ctx, navigation, actions) end
    if W.AttachStickyPageHeader then
        W.AttachStickyPageHeader(navigation, { ctx = ctx, builder = builder, gap = 8, dynamicHeight = true })
    end
    navigation:HookScript("OnSizeChanged", Fit)
    navigation:HookScript("OnShow", Fit)
    Fit()
    return navigation, { add = add, delete = delete, enabled = toggle }
end

function Page.Build(ctx, builder, shared)
    builtBarIDs = table.concat(P.Suite.DataTextBarIDs(P.S.Config(ID)), ",")
    local bars = P.Suite.DataTextBarIDs(P.S.Config(ID))
    local choose, selection
    local navigation, buttons = Navigation(ctx, builder, bars, function(...) return choose(...) end,
        function() return selection end)
    local host = builder:Section(Tr("DataTexts"), 160)
    if host.title then host.title:Hide() end
    local width = HM.GetSectionWidth(host) or builder.width or 720
    local function Resize(height) P.FinishBody(builder, host, -height, 0) end
    local deck = Page.Deck(ctx, host, width, 0, Resize)
    choose = function(key, mode, slot)
        if type(key) == "number" then Page.selectedBar = key end
        local target = type(key) == "string" and tonumber(key:match("^preset(%d+)$"))
        local view = deck:Select(key, function(item, child, childBuilder)
            if key == "shared" then shared(child, childBuilder, function() choose("shared") end)
            elseif key == "add" or target then
                item.cards = P.DataTextPresetPage.Build(child, childBuilder, function() choose(key) end, target)
            else P.DataTextEditor.Build(child, childBuilder, key, item, function(m, s) choose(key, m, s) end) end
        end)
        if view.select then view.select(mode, slot) end
        selection = (type(key) == "number" or key == "shared") and key or nil
        ctx.dataTextBarSelector:SetValue(selection)
        return view
    end
    ctx.dataTextWorkspace = { deck = deck, choose = choose, buttons = buttons, navigation = navigation,
        presets = function(bar) return choose("preset" .. bar) end }
    local present = InstallResolver(ctx, bars, choose)
    choose(present[Page.selectedBar] and Page.selectedBar or bars[1] or "add")
end

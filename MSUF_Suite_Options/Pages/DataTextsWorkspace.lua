local _, P = ...
local W, M, T, Tr, HM = P.W, P.M, P.T, P.Tr, P.HM
local PAGE, ID = "suite_dataTexts", "dataTexts"
local Page = { selectedBar = 1, selections = {} }
P.DataTextPage = Page
-- A bar the player cleared the name of reads "Bar N", as in the layer
-- overview and search (Menu/Register.lua).
function Page.BarName(bar)
    local name = P.Get(ID, "bar" .. bar .. "Name")
    if type(name) ~= "string" or name == "" then return Tr("Bar %d"):format(bar) end
    return name
end
local builtBarIDs

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

function Page.Tab(body, label, x, y, width, click)
    local button = T.Button(body, label, width, 28)
    button:SetPoint("TOPLEFT", body, "TOPLEFT", x, y)
    HM.SkipHistoryCheckpoint(button)
    button:SetScript("OnClick", click)
    return button
end

function P.RefreshDataTextPageShape()
    if builtBarIDs == nil or P.Combat() then return end
    local ids = table.concat(P.Suite.DataTextBarIDs(P.S.Config(ID)), ",")
    if builtBarIDs == ids then return end
    builtBarIDs = nil
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
        local suffix = rule.key == "bar" .. bar .. "Slot" .. slot and "" or "_details"
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

-- The bar selector owns the fixed page header; editors stay in scroll flow.
function Page.Navigation(ctx, builder)
    local navigation = builder:Section(Tr("DataTexts"), 52)
    if navigation.title then navigation.title:Hide() end
    if W.AttachStickyPageHeader then
        W.AttachStickyPageHeader(navigation, { ctx = ctx, builder = builder, gap = 8 })
    end
    return navigation
end

function Page.Build(ctx, builder, shared, navigation)
    builtBarIDs = table.concat(P.Suite.DataTextBarIDs(P.S.Config(ID)), ",")
    local host = builder:Section(Tr("DataTexts"), 160)
    if host.title then host.title:Hide() end
    local width = HM.GetSectionWidth(host) or builder.width or 720
    local bars, buttons = P.Suite.DataTextBarIDs(P.S.Config(ID)), {}
    local selected, choose, deck
    local navWidth = width - 32
    local function Resize(height) P.FinishBody(builder, host, -height, 0) end
    deck = Page.Deck(ctx, host, width, 0, Resize)
    choose = function(key, mode, slot)
        selected = key
        if type(key) == "number" then Page.selectedBar = key end
        local target = type(key) == "string" and tonumber(key:match("^preset(%d+)$"))
        local view = deck:Select(key, function(item, child, childBuilder)
            if key == "shared" then shared(child, childBuilder, function() choose("shared") end)
            elseif key == "add" or target then
                item.cards = P.DataTextPresetPage.Build(child, childBuilder, function() choose(key) end, target)
            else P.DataTextEditor.Build(child, childBuilder, key, item, function(m, s) choose(key, m, s) end) end
        end)
        if view.select then view.select(mode, slot) end
        for id, button in pairs(buttons) do button:SetActive(id == key) end
        if ctx.dataTextBarSelector and type(key) == "number" then ctx.dataTextBarSelector:SetValue(key) end
        return view
    end
    local available = navWidth - 114
    if #bars <= 5 and available / math.max(1, #bars) >= 84 then
        local size = math.floor(available / math.max(1, #bars))
        for index, bar in ipairs(bars) do
            local button = Page.Tab(navigation, "", 16 + (index - 1) * size, -12, size - 6, function() choose(bar) end)
            buttons[bar] = button
            M.TrackRefresh(ctx, function()
                P.SetButtonText(button, Page.BarName(bar))
            end)
        end
    else
        local function Values()
            local values = {}
            for _, bar in ipairs(bars) do
                values[#values + 1] = { value = bar, text = Page.BarName(bar) }
            end
            return values
        end
        ctx.dataTextBarSelector = M.BindDropdownAt(ctx, navigation, "Bar", 16, 12, Values, available - 6,
            function() return Page.selectedBar end, function(bar) choose(bar) end,
            P.Meta(PAGE, ID, "view.bar", "ephemeral"))
        P.HideControlTitle(ctx.dataTextBarSelector)
    end
    buttons.add = Page.Tab(navigation, "+ " .. Tr("Add bar"), 16 + available, -12, 108, function() choose("add") end)
    Page.Prepare({ { widget = buttons.add, label = "Add bar",
        meta = P.Meta(PAGE, ID, "action.addBar", "action", PAGE .. "_presets") } },
        PAGE .. "_presets", function() choose("add") end)
    ctx.dataTextWorkspace = { deck = deck, choose = choose, buttons = buttons, navigation = navigation,
        presets = function(bar) return choose("preset" .. bar) end }
    local present = InstallResolver(ctx, bars, choose)
    choose(present[Page.selectedBar] and Page.selectedBar or bars[1] or "add")
end

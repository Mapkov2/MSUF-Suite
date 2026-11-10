-- Exercise the actual page builders with the shared menu stand-in. Add a
-- Section-capable host: the older contract deliberately uses a legacy host
-- for Bags, Buff Reminders and Damage Meter.
local root = assert(arg[1], "repository root required")
local mutations = {
    exactTab = { "Menu/Workspace.lua", "ui.select(body._suiteWorkspaceTab)", "-- missing tab reveal" },
    narrowTabs = { "Menu/Workspace.lua", "if W.SegmentTabs then",
        "if W.SegmentTabs and ui.width - 32 >= #values * 180 then" },
    duplicate = { "Pages/BuffRemindersEditor.lua", "tostring(tonumber(token))", "token" },
    combat = { "Pages/BuffRemindersEditor.lua", "if P.Combat() then return false end", "-- missing combat refusal" },
    inheritance = { "Pages/BuffRemindersVisibility.lua", "values[rule.key] = true", "values[rule.key] = false" },
    inlineQoL = { "Pages/QualityOfLifeAccordions.lua", "record.details = body",
        'record.details = body\n        body:ClearAllPoints()\n        body:SetPoint("TOPLEFT", ui.body, "BOTTOMLEFT", 0, -1000)' },
    lazyQoL = { "Pages/QualityOfLifeNavigation.lua", "ui.panels[category.id], ui.frames[category.id] = panel, frame",
        "ui.panels[category.id], ui.frames[category.id] = panel, frame\n    panel.building = false\n    P.M.TrackRefresh(ui.ctx, function() Layout(ui) end)" },
    itemSearch = { "Pages/BuffRemindersEditor.lua", 'if key == "item" then state.kind = "item" end', 'if key == "item" then state.kind = "spell" end' },
    filteredSearch = { "Pages/QualityOfLifeNavigation.lua", "if ui.retained == group then return true end",
        "if ui.retained == group and ui.rows[V.FeatureSectionId(group)].hasDetails then return true end" },
    filterTitle = { "Pages/QualityOfLifeNavigation.lua", "P.HideControlTitle(ui.filterControl)", "-- visible title" },
    copyWrap = { "Pages/ActionBars.lua", "popup:SetHeight(math.max(340, 264 + (popup.suiteCopySummary:GetStringHeight() or 42)))", "-- missing wrapped height" },
    meterDefault = { "Pages/DamageMeter.lua", '{ id = "shared", label = "General settings", sections = "damageMeter_module look general details" },',
        '{ id = "window", label = "Window settings", sections = "windows" },\n            { id = "shared", label = "General settings", sections = "damageMeter_module look general details" },' },
    reminderRelease = { "Pages/BuffRemindersPreview.lua", "S.BuffRemindersReleasePreview(stage)", "do end" },
    reminderScale = { "Pages/BuffRemindersPreview.lua", "stage:SetScale(nativeScale * fit)", "stage:SetScale(.25)" },
    reminderIdle = { "Pages/BuffRemindersPreview.lua", "viewport:UnregisterAllEvents()", "-- kept hidden listeners" },
}
local originalLoad, P, skin = loadfile, nil, nil
local function Chunk(path)
    local chunk
    local mutation = mutations[arg[3]]
    if mutation and path:find("MSUF_Suite_Options/" .. mutation[1], 1, true) then
        local file = assert(io.open(path, "rb"))
        local source = file:read("*a")
        file:close()
        local first, last = assert(source:find(mutation[2], 1, true))
        chunk = assert(loadstring(source:sub(1, first - 1) .. mutation[3] .. source:sub(last + 1), "@" .. path))
    else chunk = assert(originalLoad(path)) end
    return chunk
end
loadfile = function(path)
    local chunk = Chunk(path)
    if path:find("MSUF_Suite_Options/Menu/Workspace.lua", 1, true) then
        return function(addon, namespace) P = namespace; return chunk(addon, namespace) end
    end
    if path:find("MSUF_Suite_Options/Pages/Appearance.lua", 1, true) then
        return function(addon, namespace)
            local register = namespace.RegisterPage
            namespace.RegisterPage = function(spec)
                local build = spec.build
                spec.build = function(ctx)
                    if MapkoSkin then skin = MapkoSkin end
                    return build(ctx)
                end
                return register(spec)
            end
            chunk(addon, namespace)
            namespace.RegisterPage = register
        end
    end
    return chunk
end
assert(originalLoad(root .. "/tools/tests/suite_options_menu_contract.lua"))()
loadfile = originalLoad
-- This renderer fixture omits the optional LoD skin; motion has its own real-provider contracts.
MSUFSuite.Skin.RegisterMenu = function() end
assert(P and P.MenuWorkspace and P.ReminderEditor and P.ReminderVisibility)
C_Spell = { GetSpellName = function(id) return "Spell " .. id end,
    GetSpellTexture = function(id) return id end, GetSpellInfo = function() end }
C_Item = { GetItemNameByID = function(id) return "Item " .. id end, GetItemIconByID = function(id) return id end }
local M, W, HM = P.M, P.W, P.HM
local nativeFrame, frames = CreateFrame, {}
CreateFrame = function(...)
    local frame = nativeFrame(...)
    if select(4, ...) == "ScrollFrameTemplate" then frame.ScrollBar = nativeFrame("Frame") end
    frames[#frames + 1] = frame
    return frame
end
local originalBuilder = W.PageBuilder
local active, buildingPage, immediate = nil, false, false
local originalTrack = M.TrackRefresh
M.TrackRefresh = function(ctx, refresh)
    originalTrack(ctx, refresh)
    if immediate then refresh() end
end
M.RequestRefresh = function()
    if active then for _, refresh in ipairs(active.refreshers) do refresh() end end
end
W.PageBuilder = function(ctx)
    local builder = originalBuilder(ctx)
    function builder:Section(_, height)
        local body = CreateFrame("Frame", nil, ctx.wrapper)
        body._msuf2Width, body.title = ctx.width, CreateFrame("Frame")
        body:SetHeight(height)
        return body
    end
    function builder:LazyCollapsibleSection(id, title, height, open, build, opts)
        local body = self:CollapsibleSection(id, title, height, open)
        body._uxBuild = function()
            if body._uxBuilt then return end
            body._uxBuilt = true
            local previous = immediate
            immediate = not buildingPage
            build(body)
            immediate = previous
        end
        if opts and opts.shell then opts.shell(body) end
        if open and (not opts.deferWhileHidden or body.parent:IsVisible()) then body._uxBuild() end
        return body
    end
    return builder
end
W.EnsureSectionContent = function(body) body._uxBuild() end
local focused = 0
W.FocusCollapsibleSection = function(body)
    focused = focused + 1
    local entry = HM.GetSectionEntry(body)
    if entry then entry.SetOpenByUser(true) else body:Show() end
    if body._uxBuild then body._uxBuild() end
end
local function Context(page, width)
    local ctx = { key = page, width = width, sections = {}, widgets = {}, refreshers = {}, pageItems = {},
        wrapper = CreateFrame("Frame"), entry = { sections = {} } }
    active = ctx
    return ctx
end
local function Build(page, width)
    local ctx = Context(page, width)
    buildingPage = true
    M.pages[page].build(ctx)
    buildingPage = false
    M.RequestRefresh()
    return ctx, ctx.suiteWorkspace
end
local function Control(ctx, suffix)
    for _, widget in ipairs(ctx.widgets) do
        local id = widget.meta and widget.meta.controlId
        if id and id:sub(-#suffix) == suffix then return widget end
    end
    error("missing control " .. suffix)
end
local function Ensure(ctx)
    for _, section in ipairs(ctx.sections) do if section._uxBuild then section._uxBuild() end end
    M.RequestRefresh()
end
local function Serialize(config)
    local rows = {}
    for key, value in pairs(config) do rows[#rows + 1] = tostring(key) .. "=" .. tostring(value) end
    table.sort(rows)
    return table.concat(rows, "|")
end
for _, page in ipairs({ "suite_bags", "suite_buffReminders", "suite_damageMeter" }) do
    local module = page:sub(7)
    local before = Serialize(P.S.Config(module))
    for _, width in ipairs({ 340, 760 }) do
        local ctx, ui = Build(page, width)
        assert(ui and #ui.spec.tabs >= 2, page .. ": no tab workspace")
        if page == "suite_damageMeter" and width == 340 then
            assert(ui.selected == "shared" and ui.spec.tabs[1].id == "shared",
                "damage meter hid general settings on first open")
            assert(ui.sections.suite_damageMeter_general._uxBuilt and ui.groups.shared.frame:IsShown(),
                "damage meter general controls were not visible on first open")
        end
        if page == "suite_damageMeter" and width == 760 then
            assert(ui.selected == "appearance", "damage meter lost the previously selected styling tab")
        end
        assert(ui.header:GetHeight() >= ui.spec.height, page .. ": fixed preview lost its height")
        assert(ui.chooseTab and not ui.selector, page .. ": workspace must keep direct tabs")
        local tabs = assert(ctx.tabControls and ctx.tabControls[1], page .. ": missing area tabs")
        assert(#tabs.segment.values == #ui.spec.tabs, page .. ": missing direct area choice")
        for index, tab in ipairs(ui.spec.tabs) do
            assert(tabs.segment.values[index].value == tab.id, page .. ": wrong area tab order")
        end
        local target = page == "suite_bags" and (ui.sections.suite_bags_bank and "suite_bags_bank" or "suite_bags_categories")
            or page == "suite_buffReminders" and "suite_buffReminders_personalVisibility" or "suite_damageMeter_bars"
        local section = ui.sections[target]
        assert(section and not section._uxBuilt, page .. ": a closed section built eagerly")
        assert(ui:Focus(target) and section._uxBuilt and ui.groups[section._suiteWorkspaceTab].frame:IsShown(),
            page .. ": preview navigation did not reveal and build the target")
        Ensure(ctx)
        if page == "suite_buffReminders" then
            local checked = 0
            for _, row in ipairs(frames) do
                if row.parent == ui.sections.suite_buffReminders_composer and rawget(row, "entry") ~= nil then
                    assert(row:IsShown() == (row.entry ~= false), "empty reminder row remained visible")
                    checked = checked + 1
                end
            end
            assert(checked == 12, "composer rows were not checked")
            ui.select("appearance")
            assert(HM.GetSearchTargetPrepare(Control(ctx, ".composer.item"))())
            assert(ui.selected == "reminders" and Control(ctx, ".composer.kind").get() == "item",
                "item search left the consumable input hidden")
        end
        local suffix = page == "suite_bags" and ".showItemLevel"
            or page == "suite_buffReminders" and ".personal_showWorld" or ".barHeight"
        local widget = Control(ctx, suffix)
        ui.select(ui.spec.tabs[1].id)
        assert(HM.GetSearchTargetPrepare(widget)(), page .. ": exact target preparation failed")
        assert(ui.selected == ui.sections[widget.meta.sectionId]._suiteWorkspaceTab,
            page .. ": search left the target in a hidden tab")
        assert(not widget.scripts.OnUpdate and not ui.header.scripts.OnUpdate, "preview started polling")
    end
    assert(Serialize(P.S.Config(module)) == before, page .. ": navigation modified saved settings")
end
-- Item data is requested once it is needed. Its native completion event
-- refreshes the visible editor; collapsing the section releases the listener.
do
    local c, items, loaded = P.S.Config("buffReminders"), C_Item, false
    local previous, requested = c.items, 0
    c.items = "501:601"
    C_Item = { GetItemNameByID = function() return loaded and "Known consumable" or nil end,
        GetItemIconByID = function() return 501 end,
        RequestLoadItemDataByID = function(id) assert(id == 501); requested = requested + 1 end }
    local ctx, ui = Build("suite_buffReminders", 760)
    Ensure(ctx)
    ui.select("reminders")
    local events, row
    for _, frame in ipairs(frames) do
        if frame.parent == ui.sections.suite_buffReminders_composer then
            if frame.scripts.OnEvent then events = frame end
            if rawget(frame, "entry") and frame.entry.id == 501 then row = frame end
        end
    end
    assert(events and row and requested > 0, "uncached item data was not requested")
    events.scripts.OnShow(events)
    assert(events._events.ITEM_DATA_LOAD_RESULT, "visible editor has no cache completion listener")
    loaded = true
    events.scripts.OnEvent(events, "ITEM_DATA_LOAD_RESULT", 501, true)
    assert(row.label.text:find("Known consumable", 1, true), "loaded item name did not reach the editor")
    events.scripts.OnHide(events)
    assert(not next(events._events), "hidden editor kept its item data listener")
    c.items, C_Item = previous, items
end
assert(focused == 6, "preview links did not focus their exact sections")
-- A cold combat open waits for the native combat-end event. The real LoD
-- renderer is the only drawing provider, including after cached page reuse.
do
    local load, draw, release, combat = C_AddOns.LoadAddOn, P.S.BuffRemindersDrawPreview,
        P.S.BuffRemindersReleasePreview, P.Combat
    local locked, loads, released, paints, dirtyPaints, lastDirty = true, 0, 0, 0, 0
    local before = Serialize(P.S.Config("buffReminders"))
    P.Combat = function() return locked end
    P.S.BuffRemindersDrawPreview, P.S.BuffRemindersReleasePreview = nil, nil
    Chunk(root .. "/MSUF_Suite_Options/Pages/BuffRemindersPreview.lua")("test", P)
    C_AddOns.LoadAddOn = function(name)
        assert(name == "MSUF_Suite_BuffReminders")
        loads = loads + 1
        P.S.BuffRemindersDrawPreview = function(stage, config, dirty)
            paints, lastDirty = paints + 1, dirty
            if dirty then dirtyPaints = dirtyPaints + 1 end
            assert(config == P.S.Config("buffReminders"))
            stage:SetSize(660, 300)
            return 660, 300, 6
        end
        P.S.BuffRemindersReleasePreview = function() released = released + 1 end
        return true
    end
    local ctx, ui = Build("suite_buffReminders", 760)
    local preview = ui.reminderPreview
    assert(loads == 0 and paints == 0 and preview.status.text ~= "", "combat open drew a fake preview")
    locked = false
    preview.viewport.scripts.OnEvent(preview.viewport, "PLAYER_REGEN_ENABLED")
    assert(loads == 1 and paints > 0 and dirtyPaints > 0, "combat end did not load the real reminder renderer")
    assert(preview.stage:GetHeight() == 300 and preview.viewport:GetHeight() == 180 and preview.stage.scale == 1,
        "reminder preview shrank the native icons to a fixed height")
    local priorPaints = paints
    M.RequestRefresh()
    assert(paints == priorPaints, "unchanged reminder refresh redrew the preview")
    local config = P.S.Config("buffReminders")
    local size = config.size
    config.size = size + 1
    M.RequestRefresh()
    assert(paints == priorPaints + 1 and not lastDirty, "appearance refresh rescanned reminder entries")
    config.size = size
    preview.viewport.GetEffectiveScale = function() return 2 end
    M.RequestRefresh()
    assert(preview.stage.scale == .5, "preview did not cancel menu scale")
    preview.viewport.scripts.OnHide(preview.viewport)
    assert(released == 1, "hidden reminder preview did not release its renderer")
    assert(not next(preview.viewport._events), "hidden reminder preview kept native listeners")
    preview.viewport.scripts.OnShow(preview.viewport)
    assert(lastDirty and preview.viewport._events.BAG_UPDATE_DELAYED, "cached reminder page did not reactivate")
    assert(Serialize(P.S.Config("buffReminders")) == before, "preview activation modified saved settings")
    C_AddOns.LoadAddOn, P.S.BuffRemindersDrawPreview, P.S.BuffRemindersReleasePreview, P.Combat = load, draw, release, combat
end
-- Old menu hosts can omit these optional presentation APIs.
do
    local widgets = M.Widgets
    local preview, focus, relayout, segments = widgets.FixedPreviewSection, widgets.FocusCollapsibleSection,
        M.RelayoutPageHeaderHost, widgets.SegmentTabs
    widgets.FixedPreviewSection, widgets.FocusCollapsibleSection, M.RelayoutPageHeaderHost, widgets.SegmentTabs = nil, nil, nil, nil
    local _, ui = Build("suite_bags", 340)
    assert(ui.selector and ui:Focus("suite_bags_appearance"), "legacy host lost navigation")
    widgets.FixedPreviewSection, widgets.FocusCollapsibleSection, M.RelayoutPageHeaderHost, widgets.SegmentTabs = preview, focus, relayout, segments
end
-- The composer keeps the existing persistence keys. Invalid/duplicate input
-- and combat refusal never write; item and spell removal are independent.
do
    local config, writes, locked = { spellIDs = "001,2", items = "10:20" }, 0, false
    local getConfig, set, get, setMany, combat, spells = P.S.Config, P.Set, P.Get, P.SetMany, P.Combat, C_Spell
    P.S.Config = function() return config end
    P.Get = function(_, key) return config[key] end
    P.Set = function(_, key, value) config[key] = value; writes = writes + 1; return true end
    P.SetMany = function(_, values)
        for key, value in pairs(values) do config[key] = value end
        writes = writes + 1
        return true
    end
    P.Combat = function() return locked end
    C_Spell = { GetSpellInfo = function(name) return name == "Known buff" and { spellID = 30 } or nil end }
    local editor = P.ReminderEditor
    assert(not editor.Add("spell", "1", "") and writes == 0, "leading zero bypassed duplicate validation")
    assert(not editor.Add("item", "20", nil) and writes == 0, "missing item wrote a malformed pair")
    assert(not editor.Add("spell", "Unknown buff", "") and writes == 0, "unknown spell name was accepted")
    assert(editor.Add("spell", "Known buff", "") and config.spellIDs == "001,2,30", "spell name did not resolve")
    assert(editor.Add("item", "|Hspell:40|hBuff|h", "|Hitem:50|hItem|h") and config.items == "10:20,50:40",
        "item/aura links did not create a pair")
    assert(editor.Remove(editor.Entries(config)[4]) and config.items == "50:40" and config.spellIDs == "001,2,30",
        "removing an item altered personal spells")
    local before = writes
    locked = true
    assert(not editor.Add("spell", "60", "") and not editor.Remove(editor.Entries(config)[1]) and writes == before,
        "composer wrote settings in combat")
    locked = false
    config.personal_showWorld, config.personal_showRaidNormal, config.class_showWorld = false, false, false
    assert(not P.ReminderVisibility.UsesGlobal("personalVisibility"))
    assert(P.ReminderVisibility.Inherit("personalVisibility") and config.personal_showWorld and config.personal_showRaidNormal
        and config.class_showWorld == false, "global inheritance changed another reminder type")
    P.S.Config, P.Set, P.Get, P.SetMany, P.Combat, C_Spell = getConfig, set, get, setMany, combat, spells
end
-- Switching a meter window updates the original template controls only.
do
    local ctx, ui = Build("suite_damageMeter", 760)
    Ensure(ctx)
    local picker, meter = Control(ctx, ".window.selected"), Control(ctx, ".w1Type")
    local c = P.S.Config("damageMeter")
    picker.set(2)
    M.RequestRefresh()
    assert(picker.get() == 2 and meter.get() == c.w2Type, "sticky picker and controls disagree")
    assert(ui.header:IsVisible(), "window picker scrolled into a feature tab")
end
-- Selected QoL details sit between their row and the following row. The
-- Filters update built rows without rebuilding; exact search reveals a hidden row.
do
    local ctx = Build("suite_qualityOfLife", 760)
    local ui = assert(ctx.entry.qualityOfLifeView)
    assert(not rawget(ui.body, "title") and not HM.GetControlTitle(ui.filterControl):IsShown(),
        "QoL filter overlaps the section title")
    -- Deferred category construction must tolerate eager widget refreshers.
    for _, category in ipairs(P.QoLView.GetCategories()) do
        if not ui.panels[category.id] then
            immediate = true
            ui:SelectCategory(category.id)
            immediate = false
            break
        end
    end
    ui:SelectCategory("interface")
    local chosen = assert(ctx.qualityOfLifeFeatureRows.suite_qualityOfLife_dailyComfort_daily_comfort)
    Control(ctx, ".view.enabled").set("enabled")
    assert(chosen.reveal(true), "QoL settings did not open")
    M.RequestRefresh()
    local point = chosen.details.points[1]
    assert(chosen.details.parent == chosen.row and point and point[2] == chosen.row
        and point[5] < 0 and point[5] > -90, "QoL details stayed below the whole feature list")
    assert(chosen.row:IsShown() and chosen.details:IsShown(), "filter hid the currently edited feature")
    local point, moves = chosen.row.SetPoint, 0
    chosen.row.SetPoint = function(self, ...) moves = moves + 1; return point(self, ...) end
    M.RequestRefresh()
    assert(moves == 0, "unchanged QoL refresh repeated native layout writes")
    chosen.row.SetPoint = point
    local plain
    for _, feature in ipairs(P.QualityOfLifeSearchFeatures) do
        local _, rules = P.QoLView.FeatureRules(feature)
        if P.QoLView.GetFeaturePage(feature) == "suite_qualityOfLife" and P.Available(feature.id)
            and not P.QoLView.HasDetails(feature, rules) then plain = feature break end
    end
    assert(plain, "filtered-search fixture needs a client-available one-switch feature")
    ui:SelectCategory(plain.category)
    local record = assert(ctx.qualityOfLifeFeatureRows[P.QoLView.FeatureSectionId(plain)])
    assert(not record.hasDetails, "filtered-search fixture no longer exercises a one-switch feature")
    local config = P.S.Config(plain.id)
    local previous = config.enabled
    config.enabled = false
    Control(ctx, ".view.enabled").set("enabled")
    M.RequestRefresh()
    assert(not record.row:IsShown(), "enabled-only filter kept a disabled feature")
    Control(ctx, ".view.enabled").set("all")
    M.RequestRefresh()
    assert(record.row:IsShown(), "All filter did not restore the feature")
    Control(ctx, ".view.enabled").set("enabled")
    M.RequestRefresh()
    assert(not record.row:IsShown(), "disabled feature was not filtered")
    record.reveal(true)
    assert(record.row:IsShown(), "search could not reveal a filtered feature without details")
    config.enabled = true
    Control(ctx, ".view.enabled").set("disabled")
    M.RequestRefresh()
    assert(not record.row:IsShown(), "disabled-only filter kept an enabled feature")
    config.enabled = false
    M.RequestRefresh()
    assert(record.row:IsShown(), "disabled-only filter did not show a disabled feature")
    config.enabled = previous
    Control(ctx, ".view.enabled").set("all")
end
-- The skin tab route uses the same native skin surfaces and setting keys.
if (arg[2] or "Mainline") == "Mainline" then
    assert(skin, "skin fixture missing")
    MapkoSkin = skin
    local _, ui = Build("suite_skin", 340)
    assert(ui and #ui.spec.tabs == 4 and ui.chooseTab and not ui.selector and ui.header:GetHeight() >= 240,
        "skinning lacks direct tabs or preview space")
    assert(ui:Focus("suite_skin_character") and ui.selected == "character", "skinning character link opened another tab")
    assert(ui:Focus("suite_skin_advanced") and ui.selected == "maintenance", "skinning maintenance link opened another tab")
    MapkoSkin = nil
end
-- Override discovery includes shared/current-spec entries only and opens
-- the existing editor in the declared scope without writing its data.
do
    local page, entries = P.CDMPage, { { key = "s1", name = "One" }, { key = "s2", name = "Two" },
        { key = "s3", name = "Three" }, { key = "s4", name = "Four" } }
    local data = { e = { s1 = { size = 30 }, s3 = {} }, s = { [62] = { s2 = { size = 40 } }, [63] = { s4 = { size = 50 } } } }
    local overrides, spec, getEntries, key, family, popover, context, combat = page.SpellOverrides, page.Spec,
        page.Entries, page.EntryKey, page.Family, page.TogglePopover, P.ContextMenu, P.Combat
    page.SpellOverrides, page.Spec, page.Entries = function() return data end, function() return 62 end, function() return entries end
    page.EntryKey, page.Family = function(entry) return entry.key end, function() return "cooldown" end
    P.Combat = function() return false end
    local buttons, opened = {}, nil
    P.ContextMenu = function(_, build)
        build(nil, { CreateTitle = function() end, SetScrollMode = function() end,
            CreateButton = function(_, label, run) buttons[#buttons + 1] = { label = label, run = run } end })
    end
    page.TogglePopover = function(entry) opened = entry end
    local rows = P.CDMOverrides.Entries()
    assert(#rows == 2 and rows[1].shared and rows[2].personal, "override list mixed specs or included empty records")
    P.CDMOverrides.Open(CreateFrame("Frame"))
    buttons[1].run()
    assert(opened.key == "s1" and page.spellSpecScope == false, "shared override opened in the spec scope")
    buttons[2].run()
    assert(opened.key == "s2" and page.spellSpecScope == true, "spec override opened in shared scope")
    assert(data.e.s1.size == 30 and data.s[62].s2.size == 40 and data.s[63].s4.size == 50, "override navigation wrote settings")
    page.SpellOverrides, page.Spec, page.Entries, page.EntryKey, page.Family, page.TogglePopover, P.ContextMenu, P.Combat =
        overrides, spec, getEntries, key, family, popover, context, combat
end
-- The copy summary follows destination/category clicks and grows for wrapped
-- translated text without applying the copy operation.
do
    local shared, options = M.UnitSectionsShared, nil
    local make = shared.MakeScopeCopyPopup
    shared.MakeScopeCopyPopup = function(_, opts)
        options = opts
        return { Hide = function() end, Show = function() end, Refresh = function() end }
    end
    local before = Serialize(P.S.Config("actionbars"))
    local ctx = Build("suite_actionbars", 760)
    Ensure(ctx)
    assert(options and options.onPopupCreated, "copy popup has no review summary")
    local popup, toggle = CreateFrame("Frame"), CreateFrame("Button")
    function popup:GetChildren() return toggle end
    function toggle:IsObjectType(kind) return kind == "Button" end
    toggle:SetScript("OnClick", function() options.scopes[options.categories[1].key] = not options.scopes[options.categories[1].key] end)
    options.onPopupCreated(popup)
    local text = popup.suiteCopySummary
    assert(text.text:find("Positions", 1, true), "summary omitted the unchanged positions")
    function text:GetStringHeight() return 196 end
    toggle.scripts.OnClick(toggle)
    assert(popup:GetHeight() >= 460, "wrapped summary overlaps the footer")
    assert(Serialize(P.S.Config("actionbars")) == before, "reviewing the copy changed settings")
    shared.MakeScopeCopyPopup = make
end
print("Suite menu UX: narrow/legacy tabs, lazy exact navigation, read-only previews, reminder input/removal/combat/inheritance, sticky meter and inline QoL passed")

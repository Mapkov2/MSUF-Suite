-- Suite option pages built for real on the client and menu fixture of
-- suite_options_menu_contract.lua: what a player's clicks write and show.
local root = assert(arg[1], "repository root required")
SUITE_OPTIONS_FIXTURE = true
local F = dofile(root .. "/tools/tests/suite_options_menu_contract.lua")
local M, S = F.M, F.S

local function Build(page)
    local ctx = { key = page, width = 720, refreshers = {}, widgets = {}, sections = {}, pageItems = {},
        entry = { sections = {} } }
    F.SetCurrent(ctx)
    M.pages[page].build(ctx)
    for _, refresh in ipairs(ctx.refreshers) do refresh() end
    return ctx
end
-- The Suite facade uses readable host roles before layout, including the
-- green Micro Bar action, and retains the host's own help affordance.
do
    local P, T, W = F.optionsNS, F.T, F.W
    local font, button, apply, style = T.Font, T.Button, T.ApplyMenuFont, T.StyleFontString
    local paint, description = T.ApplyButtonRole, W.Description
    T.Font = function(parent, template, text, color, role)
        local label = font(parent, template, text)
        label.typeRole, label.typeColor = role, color
        return label
    end
    T.ApplyMenuFont = function(label, _, role) label.typeRole = role end
    T.StyleFontString = function(label, color, _, role) label.typeRole, label.typeColor = role, color end
    T.ApplyButtonRole = function(control, role) control.paintRole = role end
    T.Button = function(parent, text, width, height)
        local control = button(parent, text)
        control:SetSize(width or 120, height or 24)
        control._msuf2Label = F.Widget("FontString")
        control._msuf2Label.GetStringHeight = function() return 54 end
        return control
    end
    local parent = CreateFrame("Frame", nil, UIParent)
    local plain = P.Text(parent, "Sample values", 16, -12, 260)
    local supporting = P.T.Font(parent, "GameFontHighlightSmall", "Preview", T.colors.muted, "supporting")
    assert(plain.typeRole == "card" and plain.typeColor == T.colors.text, "Suite copy did not use the reading role")
    assert(supporting.typeRole == "card" and supporting.typeColor == T.colors.text, "compact help kept its tiny, muted role")
    assert(M.Theme == T and M.Widgets == W and P.T ~= T and P.W ~= W, "the Suite replaced the host widget factories")

    W.Description = function()
        local label = F.Widget("FontString")
        label._msuf2HelpTarget = F.Widget("Button")
        label._msuf2HelpTarget:Hide()
        label.IsTruncated = function(self) return self.typeRole == "section" end
        return label
    end
    local help = P.Description(parent, "Sample values", 16, -12, 260, "Preview")
    assert(help.typeRole == "section" and help.typeColor == T.colors.text and help._msuf2HelpTarget:IsShown(),
        "the larger description hid access to wrapped help")

    local ctx = { widgets = {}, refreshers = {} }
    local grid = P.W.SettingsRows(ctx, parent, { x = 16, y = -12, width = 260,
        rows = { { id = "scale", kind = "slider", label = "Scale" } } })
    assert(grid.controls.scale._msuf2Title.typeRole == "card", "host-created Suite setting titles missed the reading role")
    local bottom = P.DataTextPage.MicroMenuPresetLink(ctx, parent, -12, 260)
    local action = assert(F.registeredControls["menu2.suite_skin.skin.micro.dataTexts"])
    assert(action.paintRole == "success" and action._msuf2Label.typeRole == "heading",
        "the Micro Bar action lost its prominent green role")
    assert(action:GetHeight() == 70 and bottom < -12 - action:GetHeight(), "the action clipped its wrapped label")
    T.Font, T.Button, T.ApplyMenuFont, T.StyleFontString = font, button, apply, style
    T.ApplyButtonRole, W.Description = paint, description
end

do
    local skin = { L = {}, Theme = { GetColor = function() return 1, 1, 1, 1 end } }
    local options = { textRoles = {}, TrackRefresh = function() end }
    assert(loadfile(root .. "/MSUF_Suite_Skin_Options/Shell/Theme.lua"))("MSUF_Suite_Skin_Options", { NS = skin, Options = options })
    local parent = { CreateFontString = function()
        local label = F.Widget("FontString")
        label.GetFont = function() return "LocalizedMenu.ttf", 11, "" end
        return label
    end }
    local inherited = options.CreateText(parent, "Example")
    local small = options.CreateText(parent, "Example", 10)
    local title = options.CreateText(parent, "Example", 20, "title")
    assert(inherited.font[2] == 13 and small.font[2] == 13 and title.font[2] == 20
        and small.font[1] == "LocalizedMenu.ttf", "standalone Skinning did not honor the readable size floor")
end

local function Control(ctx, id)
    for _, widget in ipairs(ctx.widgets) do
        if widget.meta and widget.meta.controlId == id then return widget end
    end
    error("no control " .. id)
end
local function Section(ctx, id)
    for _, section in ipairs(ctx.sections) do
        if section.sectionId == id then return section end
    end
    error("no section " .. id)
end

-- Action bars: a copy from the Stance or Pet bar leaves the settings those
-- bars do not have (macro names are hidden there) on the target bars.
do
    local ctx = Build("suite_actionbars")
    assert(S.SetMany("actionbars", { bar1Macro = true, bar1MacroSize = 14, bar1KeybindSize = 12, bar11KeybindSize = 9 }))
    assert(S.catalog.actionbars.rules.bar11Macro.hidden, "fixture: the Stance bar has no macro names")
    Control(ctx, "menu2.suite_actionbars.actionbars.editor.selected").set(11)
    local copy = assert(Section(ctx, "suite_actionbars_bar_text")._msufSuiteSectionCopy, "Text has no Copy section")
    assert(copy.source() == 11 and copy.run(copy.source(), 1), "the copy was refused")
    local bar = S.Config("actionbars")
    assert(bar.bar1KeybindSize == 9, "the keybind size was not copied")
    assert(bar.bar1Macro == true and bar.bar1MacroSize == 14,
        "the Stance bar's hidden macro settings were copied onto Action bar 1")
end

-- Cooldown manager on a lazy host (MSUF_Menu2_Widgets_PageBuilder.lua
-- InstallLazySection: the shell at once, the content when the section is
-- open; the player's saved accordion state wins over the default). With
-- Basics left collapsed, Layout's grow and overflow lists still name the
-- bars and lock the choices the selected bar cannot take.
do
    local W, NS = F.W, F.optionsNS
    local eager = W.PageBuilder
    W.PageBuilder = function(ctx)
        local b = eager(ctx)
        local section = b.CollapsibleSection
        function b:CollapsibleSection(id, title, height, defaultOpen)
            local saved = ctx.saved[id]
            if saved == nil then saved = defaultOpen == true end
            return section(self, id, title, height, saved)
        end
        function b:LazyCollapsibleSection(id, title, height, defaultOpen, build, opts)
            local body = self:CollapsibleSection(id, title, height, defaultOpen)
            local entry = body._msuf2CollapsibleEntry
            if opts and opts.shell then opts.shell(body, entry) end
            if entry.open then build(body, entry) end
            return body
        end
        return b
    end
    local config = S.Config("cooldownManager")
    config.c1_on, config.c1_kind, config.c1_name, config.ess_vertical = true, 1, "My burst", true
    NS.CDMPage.ui, NS.CDMPage.selected = nil, "ess"
    local ctx = { key = "suite_cooldownManager", width = 720, refreshers = {}, widgets = {}, sections = {},
        pageItems = {}, saved = { suite_cooldownManager_basics = false, suite_cooldownManager_layout = true } }
    F.SetCurrent(ctx)
    M.pages.suite_cooldownManager.build(ctx)
    for _, refresh in ipairs(ctx.refreshers) do refresh() end
    W.PageBuilder = eager
    local rows = {}
    for _, widget in ipairs(ctx.widgets) do
        local key = widget.meta and widget.meta.settingKey
        if key then rows[key:match("[^.]+$")] = widget.row end
    end
    assert(not rows.c1_anchor, "fixture: Basics was built although it is collapsed")
    local overflow, grow = assert(rows.c1_overflow, "Layout was not built"), rows.c1_grow
    local function Item(slot)
        for _, item in ipairs(overflow.values) do
            if item.value >= 2 and NS.CDMPage.BarName(slot) == item.text then return item end
        end
        error("the overflow list does not name " .. slot .. " (" .. NS.CDMPage.BarName(slot) .. ")")
    end
    assert(Item("c1"), "the renamed bar is missing")
    assert(Item("ess").disabled, "the selected bar is offered as its own overflow target")
    assert(Item("buf").disabled, "a buff bar is offered as an overflow target")
    assert(grow.values[1].text == "Right" and grow.values[2].text == "Left",
        "a vertical bar's grow list reads " .. grow.values[1].text .. " / " .. grow.values[2].text)
end

-- DataTexts "Choose observed seasonal stages": Blizzard's checkbox keeps the
-- menu open and redraws every tick from isSelected after a click
-- (Blizzard_Menu MenuTemplates.lua MenuResponse.Refresh, Menu.lua), so a
-- click shows at once and a second click takes the stage out again.
if not F.Suite.Client.isForever then
    local previous = { MenuUtil = MenuUtil, C_CurrencyInfo = C_CurrencyInfo, C_Item = C_Item }
    S.DataTextExtraSources = { CrestChoices = function()
        return { { order = 1, currencyID = 3008 }, { order = 2, currencyID = 3009 } }
    end }
    C_CurrencyInfo = { GetCurrencyInfo = function(id) return { name = id == 3008 and "Weathered" or "Carved" } end }
    C_Item = { GetItemInfo = function() return nil end }
    local generator
    MenuUtil = { CreateContextMenu = function(_, fn) generator = fn end }
    local function Open()
        local boxes, menu = {}, {}
        function menu:CreateButton() return { SetResponse = function() end } end
        function menu:CreateTitle() end
        function menu:CreateCheckbox(text, isSelected, setSelected)
            boxes[#boxes + 1] = { text = text, isSelected = isSelected, setSelected = setSelected }
            return {}
        end
        generator(nil, menu)
        return boxes
    end
    local ctx = Build("suite_dataTexts")
    ctx.dataTextWorkspace.choose("shared")
    local button = assert(F.registeredControls["menu2.suite_dataTexts.dataTexts.chooseSeasonStages"])
    assert(S.Set("dataTexts", "crestCurrencies", ""))
    button.scripts.OnClick(button)
    local stage = Open()[1]
    assert(not stage.isSelected(), "the stage shows checked before a click")
    stage.setSelected()
    assert(S.Config("dataTexts").crestCurrencies == "1", "the first click did not save the stage")
    assert(stage.isSelected(), "the clicked stage still shows unchecked")
    stage.setSelected()
    assert(S.Config("dataTexts").crestCurrencies == "", "the second click did not take the stage out")
    assert(not stage.isSelected(), "the stage taken out still shows checked")
    MenuUtil, C_CurrencyInfo, C_Item = previous.MenuUtil, previous.C_CurrencyInfo, previous.C_Item
    S.DataTextExtraSources = nil
end

-- DataTexts: an unnamed bar reads "Bar N" in its header, selector and preview.
do
    local NS = F.optionsNS
    assert(NS.Set("dataTexts", "bar1Name", ""), "fixture: the name field commits an empty name")
    local previews, build = {}, NS.DataTextsPreview.Build
    NS.DataTextsPreview.Build = function(...)
        local ui = build(...)
        previews[#previews + 1] = ui
        return ui
    end
    local ctx = Build("suite_dataTexts")
    NS.DataTextsPreview.Build = build
    local picker = assert(ctx.dataTextBarSelector)
    local choices = type(picker.values) == "function" and picker.values() or picker.values
    assert(choices[1].text == "Bar 1", "the bar's dropdown label is blank")
    local header = ctx.entry.sections.suite_dataTexts_bar1._msuf2CollapsibleEntry.label
    assert(header.text == "Bar 1", "the bar's header is blank")
    local preview
    for _, ui in ipairs(previews) do if ui.barId == 1 then preview = ui end end
    assert(preview and preview.status.text:find("^Bar 1"), "the bar's preview title is blank")
    assert(NS.Set("dataTexts", "bar1Name", "Raid Status"))
    assert(header.text == "Raid Status", "renaming the bar left its accordion title stale")
    assert(NS.Set("dataTexts", "bar1Name", "Bar 1"))
end

-- The fixed DataTexts controls share one picker with the old per-bar actions.
do
    local P, Suite = F.optionsNS, F.Suite
    local saved = S.Config("dataTexts")
    local config = Suite.CopyValue(saved)
    Suite.DB.suite.modules.dataTexts = config
    for key in pairs(config) do
        if type(key) == "string" and key:match("^bar%d+Enabled$") then config[key] = false end
    end
    config.barIds, config.bar1Enabled = "1,2,3,4,5,6,7,8,9,10", true
    P.DataTextPage.selectedBar = 1
    local ctx = Build("suite_dataTexts")
    local workspace = ctx.dataTextWorkspace
    assert(workspace.buttons.enabled.parent == workspace.navigation and workspace.buttons.add.parent == workspace.navigation
        and workspace.buttons.delete.parent == workspace.navigation, "the master switch and actions must be fixed together")
    assert(ctx.dataTextBarSelector.values()[1].value == 1, "the bar selector was replaced by tabs")
    workspace.buttons.add.scripts.OnClick(workspace.buttons.add)
    assert(workspace.deck.selected == "add", "fixed Add bar did not open presets")
    ctx.dataTextBarSelector.set(1)
    assert(workspace.deck.selected == 1, "the bar dropdown could not return from presets")
    local open, confirmDialog, set = P.OpenDeletePicker, P.Confirm, P.SetMany
    local picker, confirm, question, saves
    saves = 0
    P.OpenDeletePicker = function(...) picker = open(...) or picker end
    P.Confirm = function(_, text, accept) question, confirm = text, accept end
    P.SetMany = function(id, values)
        if id == "dataTexts" then saves = saves + 1 end
        return set(id, values)
    end
    workspace.buttons.delete.scripts.OnClick(workspace.buttons.delete)
    assert(picker and picker:IsShown() and #picker.rows == 8 and not picker.apply:IsEnabled(),
        "the shared picker did not start empty or materialized all ten bars")
    local first = picker.rows[1].toggle
    first.scripts.OnClick(first)
    picker.next.scripts.OnClick(picker.next)
    assert(picker.rows[1].toggle == first and picker.rows[1].item == 9 and not first:GetChecked(),
        "the second page did not reuse the checkbox or kept its prior check")
    first.scripts.OnClick(first)
    picker.previous.scripts.OnClick(picker.previous)
    assert(first:GetChecked() and picker.count == 2, "changing pages lost part of the selection")
    picker.apply.scripts.OnClick(picker.apply)
    assert(saves == 0 and confirm and question:find("#1", 1, true) and question:find("#9", 1, true),
        "DataTexts did not confirm the selected bars before editing the profile")
    confirm()
    assert(saves == 1 and config.barIds == "2,3,4,5,6,7,8,10" and config.bar1Enabled == false
        and P.DataTextPage.selectedBar == 2, "batch deletion did not choose the next bar in one write")
    local current = Build("suite_dataTexts").dataTextWorkspace
    current.buttons.delete.scripts.OnClick(current.buttons.delete)
    first.scripts.OnClick(first)
    picker.apply.scripts.OnClick(picker.apply)
    config.bar2Name = "Renamed while confirming"
    confirm()
    assert(saves == 1 and config.barIds:match("^2,"), "a stale confirmation deleted a renamed bar")
    current.buttons.delete.scripts.OnClick(current.buttons.delete)
    for _, row in ipairs(picker.rows) do row.toggle.scripts.OnClick(row.toggle) end
    picker.apply.scripts.OnClick(picker.apply)
    confirm()
    assert(saves == 2 and config.barIds == "0" and #Suite.DataTextBarIDs(config) == 0,
        "removing the last bars repopulated the default list")
    local emptyPage = Build("suite_dataTexts")
    assert(emptyPage.dataTextWorkspace.buttons.add:IsEnabled() and not emptyPage.dataTextWorkspace.buttons.delete:IsEnabled(),
        "empty DataTexts page blocked Add or still offered Delete")
    emptyPage.dataTextBarSelector.set("shared")
    assert(emptyPage.dataTextWorkspace.deck.selected == "shared", "All bars settings became inaccessible without a bar")
    P.OpenDeletePicker, P.Confirm, P.SetMany = open, confirmDialog, set
    Suite.DB.suite.modules.dataTexts = saved
    P.DataTextPage.selectedBar = 1
end

-- The bar editor moves complete slot records in one history action.
do
    local Suite, NS = F.Suite, F.optionsNS
    local source = Suite.DataTextSourceIndex
    assert(S.SetMany("dataTexts", { bar1Slot1 = source.gold, bar1Slot2 = source.none, bar1Slot3 = source.durability,
        bar1Slot4 = source.clock, bar1Slot5 = source.none, bar1Slot6 = source.none,
        bar1Slot1Scale = 125, bar1Slot1Background = "123456", bar1Vertical = false }))
    local ctx = Build("suite_dataTexts")
    local view = ctx.dataTextWorkspace.choose(1, "content", 1)
    local preview = view.preview
    preview.zoomOne:GetScript("OnClick")(preview.zoomOne)
    local first, third, fourth = preview.slots[1], preview.slots[3], preview.slots[4]
    local otherBar = S.Config("dataTexts").bar2Slot1
    local writes, runHistory = 0, M.RunWithHistory
    M.RunWithHistory = function(...)
        writes = writes + 1
        return runHistory(...)
    end
    local mouseTarget, inside = third, true
    preview.viewport.IsMouseOver = function() return inside end
    for _, button in ipairs(preview.slots) do
        button.IsMouseOver = function(self) return mouseTarget == self end
    end
    local function Begin(button, target)
        button:GetScript("OnMouseDown")(button, "LeftButton")
        button:GetScript("OnDragStart")(button)
        if target then target:GetScript("OnEnter")(target) end
    end
    local function Drop(button) button:GetScript("OnDragStop")(button) end
    Begin(first, third)
    assert(writes == 0 and first.alpha < 1, "starting a drag wrote settings or did not identify the source")
    assert(preview.dropMarker:IsShown() and preview.dropMarker.points[1][3] == "TOPRIGHT",
        "moving later did not indicate insertion after the target")
    assert(not preview.host:GetScript("OnUpdate") and not first:GetScript("OnUpdate"), "drag reorder polls")
    inside = false
    Drop(first)
    assert(writes == 0 and first.alpha == 1 and not preview.dropMarker:IsShown(), "dropping outside changed the bar")

    inside = true
    Begin(first, third)
    Drop(first)
    local config = S.Config("dataTexts")
    assert(writes == 1 and config.bar1Slot1 == source.none and config.bar1Slot2 == source.durability
        and config.bar1Slot3 == source.gold, "drop did not reorder the selected bar in one history step")
    assert(config.bar1Slot3Scale == 125 and config.bar1Slot3Background == "123456" and config.bar2Slot1 == otherBar,
        "drop did not move the complete slot record")
    assert(view.slotPicker.value == 3, "the inspector did not follow the moved data text")
    first:GetScript("OnClick")(first)
    assert(view.slotPicker.value == 3, "the drop also clicked the old slot")
    fourth:GetScript("OnMouseDown")(fourth, "LeftButton")
    fourth:GetScript("OnClick")(fourth)
    assert(view.slotPicker.value == 4 and writes == 1, "an ordinary click no longer only selects the slot")

    assert(S.Set("dataTexts", "bar1Vertical", true))
    preview:Refresh()
    mouseTarget = preview.slots[2]
    Begin(fourth, mouseTarget)
    assert(preview.dropMarker.points[1][3] == "TOPLEFT", "the vertical preview did not indicate insertion above")
    local profile = Suite.DB
    Suite.DB = {}
    Drop(fourth)
    Suite.DB = profile
    assert(writes == 1 and not preview.drag and not preview.dropMarker:IsShown(), "a stale drag wrote to a different profile")

    Begin(fourth, mouseTarget)
    local inCombat = InCombatLockdown
    InCombatLockdown = function() return true end
    Drop(fourth)
    InCombatLockdown = inCombat
    assert(writes == 1 and not preview.drag, "a drag that reached combat wrote settings")

    Begin(fourth, mouseTarget)
    config.bar1Slot6 = source.xp
    Drop(fourth)
    config.bar1Slot6 = source.none
    assert(writes == 1 and not preview.drag, "a drag overwrote a newer slot arrangement")

    Begin(fourth, mouseTarget)
    preview.host:GetScript("OnHide")(preview.host)
    Drop(fourth)
    assert(writes == 1 and not preview.drag and not preview.dropMarker:IsShown(), "a hidden preview kept a pending drop")

    Begin(fourth, mouseTarget)
    Drop(fourth)
    assert(writes == 2 and config.bar1Slot2 == source.clock and config.bar1Slot4 == source.gold
        and view.slotPicker.value == 2, "the vertical preview did not reorder earlier")
    M.RunWithHistory = runHistory

    local gallery = ctx.dataTextWorkspace.choose("add")
    local thumbnail = gallery.cards[2].preview
    assert(not thumbnail.slots[1]:GetScript("OnDragStart") and not thumbnail.viewport,
        "a preset thumbnail gained interactive controls")
end

-- Zoom and pan are view-only. A full-screen bar starts near actual size
-- with the selected data text visible, and Fit can show its entire extent.
do
    local Suite, NS = F.Suite, F.optionsNS
    local oldWidth = UIParent:GetWidth()
    UIParent:SetWidth(2560)
    assert(S.SetMany("dataTexts", { bar1FullScreen = true, bar1Vertical = false, bar1Layout = Suite.DataTextLayout.EQUAL,
        bar1Slot1 = Suite.DataTextSourceIndex.gold, bar1Slot12 = Suite.DataTextSourceIndex.clock }))
    local ctx = Build("suite_dataTexts")
    local view = ctx.dataTextWorkspace.choose(1, "content", 1)
    local ui = view.preview
    local source = ui.slots[1]
    assert(ui.host:GetHeight() >= 220 and ui.viewport and ui.stage:GetParent() == ui.viewport,
        "the editor did not build a taller, separate viewport")
    assert(ui.host.points[2][1] == "TOPRIGHT", "the preview does not follow the editor width")
    assert(ui.viewZoom == .85 and ui.panX > 0 and ui.zoomLabel.text == "85%",
        "a wide bar did not open at a readable scale near the selected slot")
    local paints, setText = 0, source.label.SetText
    source.label.SetText = function(self, ...)
        paints = paints + 1
        return setText(self, ...)
    end
    local writes, history = 0, M.RunWithHistory
    M.RunWithHistory = function(...)
        writes = writes + 1
        return history(...)
    end
    local function Click(button) button:GetScript("OnClick")(button) end
    Click(ui.zoomIn)
    assert(ui.viewZoom == 1 and ui.sample.scale == 1 and ui.panX > 0, "zoom in lost the visible part of the bar")

    local control, forward = IsControlKeyDown, M.ForwardMenuScrollWheel
    local wheelDelta
    M.ForwardMenuScrollWheel = function(delta) wheelDelta = delta end
    IsControlKeyDown = function() return false end
    ui.viewport:GetScript("OnMouseWheel")(ui.viewport, -1)
    assert(wheelDelta == -1 and ui.viewZoom == 1, "ordinary wheel scroll was swallowed by the preview")
    IsControlKeyDown = function() return true end
    source:GetScript("OnMouseWheel")(source, 1)
    assert(ui.viewZoom == 1.25 and wheelDelta == -1, "Ctrl + wheel over a data text did not zoom")
    M.ForwardMenuScrollWheel, IsControlKeyDown = forward, control

    Click(ui.zoomFit)
    assert(ui.sampleWidth * ui.fit <= ui.viewWidth + .001 and ui.panX == 0 and not ui.canPan,
        "Fit did not recenter the entire full-width bar")
    Click(ui.zoomOne)
    assert(ui.viewZoom == 1 and ui.sample.scale == 1, "1:1 did not restore native scale")
    local cursor, cursorX = GetCursorPosition, 200
    GetCursorPosition = function() return cursorX, 100 end
    ui.viewport:GetScript("OnDragStart")(ui.viewport)
    assert(ui.stage.moving and not ui.viewport:GetScript("OnUpdate"), "panning did not use native movement")
    cursorX = 5000
    ui.viewport:GetScript("OnDragStop")(ui.viewport)
    assert(not ui.stage.moving and ui.panX == (ui.sampleWidth - ui.viewWidth) / 2, "pan was not bounded at the bar edge")
    ui.viewport:GetScript("OnDragStart")(ui.viewport)
    ui.host:GetScript("OnHide")(ui.host)
    assert(not ui.stage.moving and not ui.panStartX, "a hidden preview kept moving")
    GetCursorPosition = cursor
    assert(paints == 0 and writes == 0, "camera input repainted data or wrote settings")
    view.select("content", 12)
    assert(ui.panX < 0, "selecting a clipped place did not reveal it")
    ui.host:GetScript("OnSizeChanged")(ui.host, 360, ui.height)
    assert(ui.viewWidth == 320 and ui.panX < 0 and ui.viewZoom == 1, "narrowing the menu reset zoom or lost the selected side")
    assert(ui.selection:GetWidth() == 194, "the preview footer did not fit the narrower viewport")
    local effectiveScale = ui.viewport.GetEffectiveScale
    ui.viewport.GetEffectiveScale = function() return .8 end
    ui:Refresh()
    assert(ui.sample.scale == 1.25 and ui.zoomLabel.text == "100%", "1:1 ignored the difference in menu and UI scales")
    ui.viewport.GetEffectiveScale = effectiveScale

    M.RunWithHistory = history
    assert(NS.Set("dataTexts", "bar1FullScreen", false))
    UIParent:SetWidth(oldWidth)
end

-- The launcher has an inline caption and both links go to exact controls
-- without writing either the skin or DataTexts profile.
do
    local Suite, NS = F.Suite, F.optionsNS
    local source = Suite.DataTextSourceIndex
    assert(S.SetMany("dataTexts", { bar1Slot1 = source.gold, bar1Slot1MenuLabel = "", bar1Enabled = true }))
    local ctx = Build("suite_dataTexts")
    local view = ctx.dataTextWorkspace.choose(1, "content", 1)
    local function CaptionInput()
        for _, widget in ipairs(ctx.widgets) do
            if widget.meta and widget.meta.settingKey == "msufsuite.dataTexts.bar1Slot1MenuLabel" then return widget end
        end
    end
    assert(not CaptionInput(), "an unrelated slot built the menu caption editor")
    local config = S.Config("dataTexts")
    assert(NS.Set("dataTexts", "bar1Slot1", source.microMenu))
    for _, refresh in ipairs(ctx.refreshers) do refresh() end
    local input = assert(CaptionInput(), "the selected menu slot did not reveal its caption editor")
    assert(input.maxBytes == 65 and input.meta.sectionId == "suite_dataTexts_bar1_slot1")
    input.set("Options")
    view.preview:Refresh()
    assert(config.bar1Slot1MenuLabel == "Options" and view.preview.slots[1].label.text:find("Options", 1, true),
        "the caption edit did not reach the preview")
    local skin = assert(F.registeredControls["menu2.suite_dataTexts.dataTexts.bar1Slot1.microSkin"])
    local bridge, routes = M.SearchBridge, {}
    M.SearchBridge = { OpenSearchTarget = function(page, _, _, _, _, exact)
        routes[#routes + 1] = exact
        assert(page == "suite_skin" or page == "suite_dataTexts")
        if page == "suite_dataTexts" then ctx.entry._msuf2ResolveMissingSection(exact.sectionId) end
        return true, true, true
    end }
    local barIds = config.barIds
    skin:GetScript("OnClick")(skin)
    NS.DataTextPage.MicroMenuPresetLink({ refreshers = {} }, CreateFrame("Frame", nil, UIParent), -18, 360)
    local presetLink = assert(F.registeredControls["menu2.suite_skin.skin.micro.dataTexts"])
    presetLink:GetScript("OnClick")(presetLink)
    assert(routes[1].sectionId == "suite_skin_micro" and routes[1].settingKey == "msufsuite.skin.skins.microMenu")
    assert(routes[2].sectionId == "suite_dataTexts_presets"
        and routes[2].controlId == "menu2.suite_dataTexts.dataTexts.preset.microMenu")
    assert(F.registeredControls[routes[2].controlId] and config.barIds == barIds and config.bar1Slot1MenuLabel == "Options",
        "the preset link did not materialize its card without editing the profile")
    M.SearchBridge = bridge
    ctx.dataTextWorkspace.choose(1, "content", 1)
    assert(NS.Set("dataTexts", "bar1Slot1", source.gold))
    for _, refresh in ipairs(ctx.refreshers) do refresh() end
    assert(not skin.parent:IsShown(), "switching sources left the menu-only controls showing")
end

-- DataTexts source picker: opened from the preview's "Add data" button, it
-- stays a child of the menu window (or UIParent), never of its anchor inside
-- the clipping preview host, and takes the menu's popup priority once placed.
do
    local NS = F.optionsNS
    local previews, build = {}, NS.DataTextsPreview.Build
    NS.DataTextsPreview.Build = function(...)
        local ui = build(...)
        previews[#previews + 1] = ui
        return ui
    end
    local panels, create = {}, M.CreateMenuPopupPanel
    M.CreateMenuPopupPanel = function(parent, opts)
        local panel = create(parent, opts)
        panel.createdUnder = parent
        function panel:SetParent(value) self.reparentedTo = value end
        panels[#panels + 1] = panel
        return panel
    end
    local prioritized, priority = {}, M.ApplyPopupFramePriority
    M.ApplyPopupFramePriority = function(frame) prioritized[frame] = #(frame.points or {}) end
    Build("suite_dataTexts")
    NS.DataTextsPreview.Build = build
    local preview
    for _, ui in ipairs(previews) do if ui.barId == 1 then preview = ui end end
    assert(preview and preview.host.clipsChildren, "fixture: the preview host clips its children")
    assert(NS.DataTextsSourcePicker.Open(preview.add, 1, 1), "the picker did not open")
    local picker = assert(panels[#panels], "the picker is no menu popup")
    assert(rawget(picker, "createdUnder") == (rawget(M, "frame") or UIParent), "the picker was created under its anchor")
    assert(rawget(picker, "reparentedTo") == nil, "the picker was moved under the clipping preview host")
    assert(prioritized[picker] and prioritized[picker] > 0, "the picker did not take the popup priority after placing")
    -- It still closes with its anchor's page.
    assert(picker:IsShown() and preview.add.scripts.OnHide, "fixture: the picker is open")
    preview.add.scripts.OnHide(preview.add)
    assert(not picker:IsShown(), "the picker stayed open after its anchor's page closed")
    M.CreateMenuPopupPanel, M.ApplyPopupFramePriority = create, priority
end

-- DataTexts bar headers build their "..." popup (a UIParent child that can
-- never be freed) when it first opens, not with every page build: the page
-- rebuilds whenever a bar is added, duplicated or removed.
do
    local popups, create = {}, M.CreateMenuPopupPanel
    M.CreateMenuPopupPanel = function(parent, opts)
        local panel = create(parent, opts)
        if parent == UIParent then popups[#popups + 1] = panel end
        return panel
    end
    local buttons, button = {}, F.T.Button
    F.T.Button = function(parent, text, ...)
        local made = button(parent, text, ...)
        buttons[#buttons + 1] = { parent = parent, text = text, button = made }
        return made
    end
    local ctx = Build("suite_dataTexts")
    assert(#popups == 0, #popups .. " bar popups were built with the page")
    local more = assert(F.registeredControls["menu2.suite_dataTexts.dataTexts.bar1.remove"], "bar 1 has no '...'")
    more.scripts.OnClick(more)
    local popup = assert(popups[1], "the bar's '...' opened no popup")
    local remove
    for _, made in ipairs(buttons) do
        if made.parent == popup and made.text == "Remove bar" then remove = made.button end
    end
    assert(remove and popup:GetHeight() == 114, "the bar popup lost its Remove bar action")
    local P, direct = F.optionsNS
    local body = ctx.entry.sections.suite_dataTexts_bar1
    for _, made in ipairs(buttons) do
        if made.parent == body and made.text == "Remove bar" then direct = made.button end
    end
    local open, count = P.OpenDeletePicker, 0
    P.OpenDeletePicker = function(anchor, rows)
        assert(anchor == more or anchor == direct, "legacy remove did not use its actual control as anchor")
        local selected
        for _, row in ipairs(rows) do
            if row.selected then
                assert(not selected, "legacy remove preselected more than one bar")
                selected = row.bar
            end
        end
        assert(selected == 1, "legacy remove did not preselect its bar")
        count = count + 1
    end
    remove.scripts.OnClick(remove)
    assert(direct, "bar settings lost their Remove bar action")
    direct.scripts.OnClick(direct)
    assert(count == 2, "a legacy remove action bypassed the shared picker")
    P.OpenDeletePicker = open
    M.CreateMenuPopupPanel, F.T.Button = create, button
end

-- Composed labels translate as one format text, so a language can order the
-- parts: a hidden bar in the action bar preview, an unavailable font or
-- texture, a feature's color shortcut (QoL card and search row) and the name
-- of a new cooldown bar. The stand-in translations put the parts in another
-- order than English.
do
    local L, NS = F.L, F.optionsNS
    local function Swap(key, text) rawset(L, key, text) end
    Swap("%s (hidden)", "[hidden] %s")
    Swap("Unavailable font: %s", "%s - font missing")
    Swap("Unavailable texture: %s", "%s - texture missing")
    Swap("%s Colors", "Colors of %s")
    Swap("Cooldowns %d", "No. %d cooldowns")
    local fonts, textures = NS.FontValues("Gone"), NS.TextureValues("Gone")
    assert(fonts[#fonts].text == "Gone - font missing", "the unavailable font reads " .. fonts[#fonts].text)
    assert(textures[#textures].text == "Gone - texture missing", "the unavailable texture reads " .. textures[#textures].text)
    assert(S.Set("actionbars", "bar3Visibility", 6))
    local bars = Build("suite_actionbars")
    Control(bars, "menu2.suite_actionbars.actionbars.editor.selected").set(3)
    local preview = bars._msufSuiteActionBarPreview
    bars._msufSuiteActionBarWorkspace.selected = "visibility"
    NS.ActionBarPreview.RefreshScope(preview)
    bars._msufSuiteActionBarWorkspace.selected = "shared"
    assert(preview.status.text:find("[hidden] ", 1, true), "the hidden bar reads " .. tostring(preview.status.text))
    local labels, register = {}, M.RegisterControlMetadata
    M.RegisterControlMetadata = function(widget, meta, label, ...)
        if meta and meta.controlId then labels[meta.controlId] = label end
        return register(widget, meta, label, ...)
    end
    local qol = Build("suite_qualityOfLife")
    -- Visit every lazy category and feature, so all color shortcuts are checked.
    for _, sectionId in ipairs(qol.qualityOfLifeFeatureOrder) do
        assert(qol.entry._msuf2ResolveMissingSection(sectionId), "feature route missing: " .. sectionId)
    end
    M.RegisterControlMetadata = register
    local cards = 0
    for id, label in pairs(labels) do
        if id:find("%.action%.colors%.") then
            cards = cards + 1
            assert(label:find("^Colors of "), "a color shortcut reads " .. label)
        end
    end
    assert(cards > 0, "fixture: no Quality of Life card has a color shortcut")
    local rows, pages = {}, {}
    for key in pairs(M.pages) do pages[key] = true end
    NS.AppendSearchActionRows(rows, pages)
    local searched = 0
    for _, row in ipairs(rows) do
        if row.controlId and row.controlId:find("%.action%.colors%.") then
            searched = searched + 1
            assert(row.label:find("^Colors of "), "a color search row reads " .. row.label)
        end
    end
    assert(searched > 0, "fixture: no color search row")
    local Page = NS.CDMPage
    assert(Page.AddBar(F.Suite.CDM.KIND.COOLDOWN), "no cooldown bar was added")
    local name = S.Config("cooldownManager")[Page.selected .. "_name"]
    assert(name == ("No. %d cooldowns"):format(tonumber(Page.selected:sub(2))), "the new bar is named " .. tostring(name))
    for _, key in ipairs({ "%s (hidden)", "Unavailable font: %s", "Unavailable texture: %s", "%s Colors", "Cooldowns %d" }) do
        rawset(L, key, nil)
    end
    assert(S.Set("actionbars", "bar3Visibility", 1))
end

print("options pages contract: ok")

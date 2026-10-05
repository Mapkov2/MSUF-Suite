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
do
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

-- DataTexts: a bar whose name the player cleared reads "Bar N" in its tab,
-- its header and its preview, as the layer overview and search show it.
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
    local tab = ctx.dataTextWorkspace.buttons[1]
    local label = rawget(tab, "_msuf2Label")
    assert(((label and label.text) or tab.text) == "Bar 1", "the bar's tab is blank")
    local header = ctx.entry.sections.suite_dataTexts_bar1._msuf2CollapsibleEntry.label
    assert(header.text == "Bar 1", "the bar's header is blank")
    local preview
    for _, ui in ipairs(previews) do if ui.barId == 1 then preview = ui end end
    assert(preview and preview.status.text:find("^Bar 1"), "the bar's preview title is blank")
    assert(NS.Set("dataTexts", "bar1Name", "Bar 1"))
end

print("options pages contract: ok")

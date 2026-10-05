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

-- Action bar preview without the action bar runtime and without Blizzard's
-- ActionButton1 slot: it reads the page from C_ActionBar. The global
-- GetActionBarPage exists only with Blizzard's deprecation fallbacks
-- (Blizzard_DeprecatedActionBar, loadDeprecationFallbacks).
do
    local saved = { page = GetActionBarPage, slot = S.ActionBarPreviewSlot, button = rawget(_G, "ActionButton1"),
        api = C_ActionBar.GetActionBarPage, has = C_ActionBar.HasAction }
    GetActionBarPage, S.ActionBarPreviewSlot, ActionButton1 = nil, nil, nil
    local read
    C_ActionBar.GetActionBarPage = function() return 3 end
    C_ActionBar.HasAction = function(slot) read = slot; return false end
    local tile = {}
    for _, part in ipairs({ "key", "count", "name", "cooldown", "chargeCooldown", "icon" }) do tile[part] = F.Widget(part) end
    F.optionsNS.ActionBarPreview.Read(tile, 1, 2, S.Config("actionbars"))
    assert(read == 26, "the preview read slot " .. tostring(read) .. " for page 3, button 2")
    GetActionBarPage, S.ActionBarPreviewSlot, ActionButton1 = saved.page, saved.slot, saved.button
    C_ActionBar.GetActionBarPage, C_ActionBar.HasAction = saved.api, saved.has
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
    Build("suite_dataTexts")
    assert(#popups == 0, #popups .. " bar popups were built with the page")
    local more = assert(F.registeredControls["menu2.suite_dataTexts.dataTexts.bar1.remove"], "bar 1 has no '...'")
    more.scripts.OnClick(more)
    local popup = assert(popups[1], "the bar's '...' opened no popup")
    local remove
    for _, made in ipairs(buttons) do
        if made.parent == popup and made.text == "Remove bar" then remove = made.button end
    end
    assert(remove and popup:GetHeight() == 114, "the bar popup lost its Remove bar action")
    M.CreateMenuPopupPanel, F.T.Button = create, button
end

print("options pages contract: ok")

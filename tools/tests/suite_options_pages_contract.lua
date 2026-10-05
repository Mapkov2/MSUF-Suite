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

print("options pages contract: ok")

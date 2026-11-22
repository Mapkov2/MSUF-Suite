local root = assert(arg[1], "Suite root required")
SUITE_OPTIONS_FIXTURE = true
local fixture = dofile(root .. "/tools/tests/suite_options_menu_contract.lua")
local options, suite = fixture.optionsNS, fixture.S

local ctx = { key = "suite_tooltips", width = 720, refreshers = {}, widgets = {}, sections = {}, pageItems = {},
    entry = { sections = {} } }
fixture.SetCurrent(ctx)
fixture.M.pages.suite_tooltips.build(ctx)
for _, refresh in ipairs(ctx.refreshers) do refresh() end
local key = "msufsuite.tooltipIDs.idModifier"
local setting = assert(options.ResolveTooltipMenuTarget("suite_tooltips", { settingKey = key }))
local control
for _, widget in ipairs(ctx.widgets) do
    if widget.meta and widget.meta.controlId == setting.controlId then control = widget end
end
assert(control and control.meta.sectionId == options.TooltipBasicsSection, "the shared detail key is missing from Basics")
assert(not suite.Config("tooltipIDs").enabled and control.enabled ~= false, "turning IDs off also locked the shared key")
control.set(2)
assert(suite.Config("tooltipIDs").idModifier == 2, "changing the detail key lost the saved setting identity")
assert(suite.Availability("tooltipIDs") and suite.Availability("itemCounts"), "the client's tooltip details are unavailable")
assert(options.catalog.tooltipVisibility.rules.inCombat.hidden and options.catalog.tooltipVisibility.rules.inInstances.hidden,
    "the Tooltip page offered a separate combat or instance switch")
local search = { searchRows = {} }
options.BuildTooltipSearchRows(search)
local result
for _, row in ipairs(search.searchRows) do
    if row.settingKey == key then result = row end
end
assert(result and result.suiteModuleId == "tooltipIDs" and result.sectionId == options.TooltipBasicsSection,
    "the cold search sent the detail key to Skinning")

local function Region(visible)
    return { visible = visible, shown = true, IsVisible = function(self) return self.visible end,
        IsShown = function(self) return self.shown end }
end

local text, chip, selector = Region(true), Region(true), Region(true)
chip.key = "healthText"
local preview = {
    handles = { healthText = text },
    layerButtons = { chip },
    sampleSelector = selector,
    card = { Setting = function() return "" end },
}

local opened, title, items, combat
options.Combat = function() return combat == true end
options.AnchoredContextMenu = function(owner, populate)
    opened, items = owner, {}
    populate(owner, {
        CreateTitle = function(_, label) title = label end,
        CreateButton = function(_, label)
            items[label] = true
            return { CreateRadio = function() end }
        end,
    })
end

local function CheckOwner(expected)
    opened = nil
    assert(options.OpenTooltipHealthTextMenu(preview), "Health text menu did not open")
    assert(opened == expected, "Health text menu chose a hidden or unrelated anchor")
    assert(title == options.Tr("Health text") and items[options.Tr("Format")]
        and items[options.Tr("Font")] and items[options.Tr("Font size")], "Health text options were lost")
end

CheckOwner(text)
text.shown, text.visible = false, false
CheckOwner(chip)
text.shown = true
text.visible = false
CheckOwner(chip)
chip.visible = false
CheckOwner(selector)
selector.visible = false
opened = nil
assert(not options.OpenTooltipHealthTextMenu(preview) and opened == nil, "Menu opened without a visible anchor")
selector.visible, combat = true, true
assert(not options.OpenTooltipHealthTextMenu(preview) and opened == nil, "Menu opened in combat")
print("suite tooltip health text menu contract passed")

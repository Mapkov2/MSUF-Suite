local root = assert(arg[1], "Suite root required")
SUITE_OPTIONS_FIXTURE = true
local options = dofile(root .. "/tools/tests/suite_options_menu_contract.lua").optionsNS

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

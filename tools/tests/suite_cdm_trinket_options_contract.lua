local root = assert(arg[1])
dofile(root .. "/tools/tests/suite_bh3_state_support.lua").Run("suite_cooldown_manager_options_contract.lua", [=[
do (function()
picker.set("ess")
assert(Page.AddEntry("ess", "e13", 1))
Control("maxIcons").set(1)
M.RequestRefresh()
local hit
for i = 1, ui.hitCount do if ui.hits[i].key == "e13" then hit = ui.hits[i] end end
assert(hit and hit.shown, "a tracked trinket past the live cap must have a clickable preview icon")
Fire(hit, "OnClick", "LeftButton")
assert(Page.popover.shown and Page.popover.key == "e13" and Page.popover.remove.shown,
    "the trinket's preview icon must open Remove from bar")
local before = Config().listsData
Fire(Page.popover.remove, "OnClick")
M.RequestRefresh()
assert(not Keys("ess"):find("e13", 1, true), "Remove from bar did not remove the selected trinket")
Page.RunUndo()
M.RequestRefresh()
assert(Config().listsData == before, "trinket popover removal must support Undo")
for i = 1, ui.hitCount do if ui.hits[i].key == "e13" then hit = ui.hits[i] end end
Fire(hit, "OnClick", "MiddleButton")
M.RequestRefresh()
assert(not Keys("ess"):find("e13", 1, true), "middle-click did not remove the selected trinket")
print("suite_cdm_trinket_options_contract: click removal and Undo passed")
end)() end
]=], "-- Basics holds the most used settings of the bar, the attachment complete.")

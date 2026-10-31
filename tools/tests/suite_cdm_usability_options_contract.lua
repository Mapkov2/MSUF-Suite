local root = assert(arg[1], "repository root required")
-- Selected-bar resets preserve on/off, and one section can be copied to
-- one compatible bar or all compatible bars through one undo transaction.
dofile(root .. "/tools/tests/suite_bh3_state_support.lua").Run("suite_cooldown_manager_options_contract.lua", [=[
do (function()
picker.set("c2")
Config().c2_on, Config().c2_size = true, 70
assert(ui.sections.basics._msufSuiteSectionReset(), "Basics reset wrote no settings")
assert(Config().c2_on == true and Config().c2_size == catalog.rules.c2_size.default,
    "Basics reset switched the edited custom bar off")
Config().c2_on, Config().c2_size = false, 70
assert(ui.sections.basics._msufSuiteSectionReset() and Config().c2_on == false,
    "Basics reset switched an off custom bar on")
Config().c2_name, Config().c3_name = "Source", "Destination"
Config().c2_kind, Config().c3_kind, Config().c3_on = 1, 1, false
Config().c2_zoom, Config().c3_zoom = 15, 3
Config().c3_x, Config().c3_y, Config().c3_anchor = 123, 456, 1
local look
for _, spec in ipairs(Page.SECTIONS) do if spec.id == "look" then look = spec end end
local copy = assert(ui.sections.look._msufSuiteSectionCopy, "section actions lack their copy spec")
assert(copy.source() == "c2" and copy.sourceLabel("c2") == "Source", "copy did not capture selected source identity")
local count = historyWrites
assert(copy.run("c2", "c3") and Config().c3_zoom == 15, "copy to one compatible bar")
assert(historyWrites == count + 1, "one section copy must be one history transaction")
assert(Config().c3_name == "Destination" and Config().c3_on == false and Config().c3_x == 123
    and Config().c3_y == 456 and Config().c3_anchor == 1, "section copy changed identity, visibility or placement")
Page.RunUndo()
assert(Config().c3_zoom == 3, "undo failed to restore destination section")
Config().uti_zoom, Config().ess_zoom = 2, 4
count = historyWrites
assert(copy.run("c2", "all") and Config().uti_zoom == 15 and Config().ess_zoom == 15,
    "copy to all compatible bars")
assert(historyWrites == count + 1, "all-bars copy created several history transactions")
Page.RunUndo()
assert(Config().uti_zoom == 2 and Config().ess_zoom == 4, "all-bars undo was incomplete")
Config().c3_kind = 2
assert(not copy.run("c2", "c3"), "copy accepted an incompatible bar type")
combat = true
assert(not copy.run("c2", "all"), "combat changed section settings")
combat = false
local effects, buffs
for _, spec in ipairs(Page.SECTIONS) do
    if spec.id == "effects" then effects = table.concat(spec.suffixes, ",") end
    if spec.id == "buffs" then buffs = table.concat(spec.suffixes, ",") end
end
assert(effects:find("glowColor,glowLines,glowThickness,glowSpeed", 1, true)
    and not buffs:find("glowLines", 1, true), "glow line controls are detached from glow style")
picker.set("bar")
Config().bar_pandemicStyle = 5
M.RequestRefresh()
assert(Control("glowLines").enabled, "aura timer bars lost their line styling")
print("suite_cdm_usability_options_contract: reset, copy transactions, undo, compatibility and glow placement passed")
end)() end
]=], "------------------------------------------------------------------ list edits")

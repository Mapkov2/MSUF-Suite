local root = assert(arg[1], "repository root required")
local support = dofile(root .. "/tools/tests/suite_test_support.lua")
local config, suite = support.CatalogDefaults(root, "actionbars", "ActionBars")
local catalog = suite.SuiteCatalog
local off = suite.ActionBarEnum.VISIBILITY.NEVER
local selected, combat, writes, status = 1, false, 0
local widgets, refreshers = {}, {}
local P = {
    Suite = suite, S = { Config = function() return config end }, catalog = catalog,
    M = {}, W = {}, HM = {}, Tr = function(text) return text end,
    Meta = function(_, _, key) return key end, StyleMenuControl = function() end,
    LazySection = function(_, _, _, open, spec) assert(open); spec.content({}) end,
    Get = function(_, key) return config[key] end,
    Set = function(_, key, text) writes = writes + 1; config[key] = text end,
    RuleEnabled = function() return not combat end,
    Description = function() return { GetStringHeight = function() return 14 end } end,
    Text = function() return { GetStringHeight = function() return 14 end } end,
    SetTranslatedText = function(_, text) status = text end,
    FinishBody = function() end,
}
P.M.TrackRefresh = function(_, refresh) refreshers[#refreshers + 1] = refresh end
P.M.BindDropdownAt = function(_, _, _, _, _, values, _, get, set, key)
    local widget = { values = values, get = get, set = set, SetValue = function(self, value) self.value = value end }
    widgets[key] = widget
    return widget
end
P.W.SetControlEnabled = function(widget, enabled) widget.enabled = enabled end
P.HM.GetSectionWidth = function() return 410 end

local function Refresh()
    for _, refresh in ipairs(refreshers) do refresh() end
end
local function Option(widget, page)
    for _, choice in ipairs(widget.values()) do if choice.value == page then return choice end end
end
assert(loadfile(root .. "/MSUF_Suite_Options/Pages/ActionBarsPaging.lua"))("MSUF_Suite_Options", P)
P.ActionBarPagingPage.Build({}, {}, function() return selected end)
local trigger, target = widgets["paging.trigger"], widgets["paging.destination"]
assert(trigger.get() == "[mod:shift]" and target.get() == 0 and target.enabled, "the empty bar should offer a guided setup")
assert(status == "No page switching rules set.", "empty state lacks a plain explanation")
assert(Option(target, 2).disabled and Option(target, 2).tooltip == "Page 2 belongs to action bar 9.",
    "an owned page must name its owner and refuse selection")
assert(Option(target, 7).text == "Page 7 (form page)", "form pages should be recognizable")
target.set(2)
assert(writes == 0, "a stale choice wrote an occupied page")

config.bar9Visibility, config.bar4Visibility = off, off
target.set(2)
assert(config.bar1Paging == "[mod:shift] 2", "guided page selection did not save a normal paging rule")
trigger.set("[@target,harm]")
assert(target.value == 0 and writes == 1, "browsing triggers must not write or show the prior trigger's page")
target.set(3)
Refresh()
assert(config.bar1Paging == "[mod:shift] 2; [@target,harm] 3", "a second rule must append in matching order")
assert(status:find("Hold Shift", 1, true) < status:find("Hostile target", 1, true), "rules are not shown in matching order")
assert(suite.ActionBarPaging(config, 1).driver == config.bar1Paging, "guided rules did not compile through the normal driver")

trigger.set("[mod:shift]")
target.set(7)
assert(config.bar1Paging == "[mod:shift] 7; [@target,harm] 3", "changing a destination reordered the rules")
target.set(0)
assert(config.bar1Paging == "[@target,harm] 3", "No rule removed another trigger")
trigger.set("[@target,harm]")
target.set(0)
assert(config.bar1Paging == "", "removing the final rule did not restore normal paging")

config.bar1Paging = "[MOD:Shift] 2; [combat] 3"
Refresh()
trigger.set("[mod:shift]")
assert(target.get() == 2 and target.enabled, "old simple rules should be editable without migration")
config.bar1Paging = "[mod:shift,combat] 2; 1"
Refresh()
local before = writes
target.set(7)
assert(writes == before and not target.enabled and config.bar1Paging == "[mod:shift,combat] 2; 1",
    "guided editing must never overwrite a complex legacy rule")
assert(status:find("Macro conditions", 1, true), "complex rules need a pointer to the manual editor")

selected = 2
Refresh()
assert(target.enabled and not Option(target, 7) and Option(target, 6).text == "Page 6 (normal page)",
    "the page picker did not follow the selected bar")
config.bar3Paging = "[combat] 2"
assert(Option(target, 2).disabled, "an existing rule on another bar must block the claimed page")
target.set(2)
assert(writes == before, "a claim reached the setter")
combat = true
Refresh()
target.set(6)
assert(writes == before and not target.enabled, "the guided setter accepted a combat edit")
combat, selected = false, 10
Refresh()
target.set(2)
assert(writes == before and not target.enabled and not Option(target, 2), "independent bars cannot use paging")

print("guided action bar paging holds")

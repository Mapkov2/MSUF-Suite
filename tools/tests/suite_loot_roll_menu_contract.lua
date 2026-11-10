local root = assert(arg[1], "repository root required")
SUITE_OPTIONS_FIXTURE = true
local fixture = dofile(root .. "/tools/tests/suite_options_menu_contract.lua")
SUITE_OPTIONS_FIXTURE = nil
local pages, options = fixture.M, fixture.optionsNS
local view = options.QoLView
local group = assert(view.FindFeature("lootRolls"), "loot roll feature missing")
assert(group.category == "lootMerchants" and group.tab == "loot", "loot roll feature is in the wrong group")
local config = fixture.S.Config("lootRolls")
assert(config.enabled == false and config.width == 380 and config.maxRows == 6, "loot rolls must be explicitly enabled")
assert(config.showCounts and config.showResults and not config.urgentTimer, "loot roll defaults drifted")
local context = { key = "suite_qualityOfLife", width = 1000, refreshers = {}, widgets = {},
    sections = {}, pageItems = {}, entry = { sections = {} } }
fixture.SetCurrent(context)
pages.pages.suite_qualityOfLife.build(context)
local ui = assert(context.entry.qualityOfLifeView)
assert(ui:SelectCategory("lootMerchants"))
local sectionID = view.FeatureSectionId(group)
local row = assert(ui.rows[sectionID], "loot roll option row missing")
row.toggle.set(true)
assert(config.enabled == true, "loot roll opt-in switch does not enable the feature")
row.toggle.set(false)
assert(config.enabled == false, "loot roll switch does not disable the feature")
assert(options.QualityOfLifeEditElements.lootRolls == "lootrolls", "loot roll mover is unreachable")
assert(options.HM.GetMissingSectionResolver(context.entry)(sectionID), "loot roll exact search cannot reveal its detail")
assert(not config.enabled, "search or preview enabled loot rolls")
print("PASS loot roll menu: opt-in, defaults, loot category, Edit Mode and exact navigation")

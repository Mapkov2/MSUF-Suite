local _, NS = ...
local B = NS.CatalogBuild.ForAddon("MSUF_Suite_AdventurePlanner")
B.Module("planningTools", {
    title = "Adventure planner",
    description = "Your character week, preparation, dungeon goals, saved runs and personal notes in one place.",
    optIn = true, defaultEnabled = false, page = "suite_planningTools",
})
B.Section("planningTools", "planning_tools", "Adventure planner", {
    B.Bool("weekly", "Remember weekly progress on visited characters", true),
    B.Bool("preparation", "Offer a personal preparation check on ready checks", true),
    B.Bool("loadouts", "Check saved loadouts for this instance", true),
    B.Bool("raidHistory", "Show the saved raid archive", true),
    B.Bool("entryNotes", "Remind me about notes for this instance", true),
    B.Number("keepAttempts", "Maximum saved raid attempts", 100, 20, 200, 10),
})

NS.SuiteCatalog.planningTools.controlAvailable = function(rule)
    return not NS.Client.isForever or rule.key ~= "loadouts"
end

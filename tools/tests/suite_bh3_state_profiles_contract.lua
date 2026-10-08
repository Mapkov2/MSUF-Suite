local root = assert(arg[1])
dofile(root .. "/tools/tests/suite_bh3_state_support.lua").Run("suite_profiles_contract.lua", [=[
BH3("CX6-01", function()
    assert(DB.Create("Stale", false))
    local held = DB.GetProfile("Stale")
    held.suite.modules.minimap.size = 321
    local ok = P.OnLifecycle("create", "Stale")
    assert(not ok and DB.GetProfile("Stale") == held and held.suite.modules.minimap.size == 321,
        "CX6-01: stale target was reported as a successful new profile")
    assert(not P.OnLifecycle("copy", "Default", "Stale"), "CX6-01: copy accepted stale target")
end)
BH3("S01-A1", function()
    local old = "Legacy" .. string.rep("x", 85)
    Suite.RootDB.profiles[old] = Suite.CopyValue(Suite.DB)
    assert(P.OnLifecycle("copy", old, "LegacyCopy"), "S01-A1: legacy source name prevented a valid copy")
end)
BH3("S01-A2", function()
    local state = { detachedButtons = { Test = { x = 42, y = 11 } }, transient = { dirty = true } }
    Suite.DB.suite.moduleState = { minimap = state }
    assert(P.SaveAs("LayoutCopy"))
    local copied = Suite.DB.suite.moduleState and Suite.DB.suite.moduleState.minimap
    assert(copied and copied.detachedButtons.Test.x == 42 and copied.detachedButtons ~= state.detachedButtons
        and copied.transient == nil, "S01-A2: Save as lost or aliased the local button layout")
end)
BH3("L08-A3", function()
    local config = Suite.DB.suite.modules.groupFinderDoubleClick
    config.note, config.exportNote = "do not export", false
    local text = assert(P.ExportModule("groupFinderDoubleClick"))
    config.note, config.exportNote = "keep my note", true
    assert(P.ImportModule(text))
    assert(config.note == "keep my note" and config.exportNote, "L08-A3: unmarked import erased personal settings")
    assert(P.ImportModuleIntoNew("PersonalCopy", text))
    config = Suite.DB.suite.modules.groupFinderDoubleClick
    assert(config.note == "keep my note" and config.exportNote, "L08-A3: module into new erased personal settings")
end)
BH3("L08-A4", function()
    Suite.DB.suite.modules.minimap.size = 277
    local before = Support.MigrationStep(root, "NS.MigrateMinimapSpecialization") - 1
    local text = "MSUFM2:" .. MSUF_EncodeCompactTable({ addon = "MSUF_Suite", format = 2, module = "mapQuickSwitch",
        revision = before, settings = { enabled = true, x = 13, size = 28 } }, "MSUF3")
    assert(P.ImportModuleIntoNew("OldHelper", text))
    assert(Suite.DB.suite.modules.minimap.size == 277 and Suite.DB.suite.modules.minimap.specX == 13,
        "L08-A4: helper import replaced unrelated minimap settings")
end)
BH3("L08-A1", function()
    assert(Suite.Suite.Reset("cooldownManager"))
    assert(Suite.Suite.Config("cooldownManager").defaultsVersion == Suite.CDM.DEFAULTS_VERSION,
        "L08-A1: reset left the destructive legacy version marker")
end)
BH3("S11-A1", function()
    local authored = Suite.CopyValue(Suite.DB)
    authored.suite.modules.cooldownManager.defaultsVersion = 0
    assert(P.InstallFactory("AuthoredBH3", "MSUF3:frames", authored))
    local c = Suite.DB.suite.modules.cooldownManager
    assert(c.defaultsVersion == Suite.CDM.DEFAULTS_VERSION and c.captured,
        "S11-A1: authored factory data remained eligible for destructive first-enable migration")
end)
]=], "do\n    -- Saved before the minimap specialization step")

-- The Suite's half of MSUF host API v2, in both directions, against the real
-- Classic host files (MidnightSimpleUnitFrames-Classic, arg 2):
--
-- Menu2 widget protocol (MSUF_Suite/Core/HostBridgeMenu.lua):
--   * new host + new Suite: on Menu2 with MSUF_Menu2_HostProtocol.lua the
--     adapter binds the host's own functions (the same function values);
--   * old host + new Suite: on a Menu2 without v2 (Retail today, older
--     Classic), or with v2 but a missing entry point, it keeps the Suite's
--     previous field writes;
--   * a scripted page build through the adapter leaves the same fields on
--     both hosts; the adapter is built once per Menu2 table.
-- Suite API (MSUF_Suite/Core/API.lua) through the host's Suite link
-- (Kernel/MSUF_SuiteLink.lua):
--   * MSUFSuite.API is version 1 with every documented entry point;
--   * new host + new Suite: the link answers through the API table;
--   * old host + new Suite: the paths older hosts read (the link's legacy
--     branch, with the API hidden) give the same answers and Suite calls, so
--     the Suite keeps everything an old host reaches by path.
local root = assert(arg[1], "Suite root required"):gsub("\\", "/")
local classic = assert(arg[2], "Classic host root required"):gsub("\\", "/")
local checks = 0
local function Check(value, message)
    assert(value, message)
    checks = checks + 1
end

local function Same(a, b)
    if type(a) ~= "table" or type(b) ~= "table" then return a == b end
    for key, value in pairs(a) do if not Same(value, b[key]) then return false end end
    for key in pairs(b) do if a[key] == nil then return false end end
    return true
end

local function Load(path, ...)
    return assert(loadfile(path))(...)
end

------------------------------------------------------------------ Menu2 protocol
local function Bridge()
    local suite = { HostBridge = {} }
    Load(root .. "/MSUF_Suite/Core/HostBridgeMenu.lua", "MSUF_Suite", suite)
    return suite.HostBridge
end

local function Theme()
    local home, gameplay = { 1, 1, 1 }, { 0.5, 0.5, 0.5 }
    return { navIconAtlasVersion = 2, navIconGrid = { home = { 0, 0 } },
        navIconColors = { home = home, gameplay = gameplay } }
end

local function NewHost()
    local M = { Theme = Theme(), HOST_API_VERSION = 1 }
    Load(classic .. "/MidnightSimpleUnitFrames_Options/Shell/Menu2/MSUF_Menu2_HostProtocol.lua",
        "MidnightSimpleUnitFrames", { MSUF2 = M })
    return M
end

local function OldHost() return { Theme = Theme() } end

local HostBridge = Bridge()
local newM = NewHost()
local newHM = HostBridge.Menu2(newM)
Check(newHM.mode == "host" and newM.HOST_API_VERSION == 2, "a v2 Menu2 must get the host adapter")
for _, name in ipairs(HostBridge.MENU_NAMES) do
    Check(newHM[name] == newM[name], "the adapter must bind the host's own " .. name)
end
Check(HostBridge.Menu2(newM) == newHM, "the adapter must be built once per Menu2 table")
local oldHM = HostBridge.Menu2(OldHost())
Check(HostBridge.Menu2(OldHost()) ~= oldHM, "each Menu2 table must get its own adapter")
Check(oldHM.mode == "legacy", "a Menu2 without v2 must keep the Suite's field writes")
do
    local partial = NewHost()
    partial.AddNavIcon = nil
    Check(HostBridge.Menu2(partial).mode == "legacy", "a v2 Menu2 missing an entry point must get the legacy adapter")
end
for _, name in ipairs(HostBridge.MENU_NAMES) do
    Check(type(oldHM[name]) == "function", "the legacy adapter lacks " .. name)
end

-- One scripted page build: the same fields on both hosts.
local function Build(HM, M)
    local prepare, ensure, refresh, resolve = function() end, function() end, function() end, function() end
    local action = { kind = "toggle" }
    local layouts = 0
    local out = {
        button = {}, toggle = {}, body = {}, details = {}, ctx = {}, shortcut = { _msuf2BoundColorShortcut = true },
        summaryEntry = { _msuf2UXSummary = true }, entry = { _msuf2ColorSwatchReserve = 26 }, more = {},
    }
    out.entry._msuf2RefreshLayout = function() layouts = layouts + 1 end
    out.body._msuf2CollapsibleEntry, out.body._msuf2Width = out.entry, 700
    HM.SkipHistoryCheckpoint(HM.AllowCombatClick(out.button))
    HM.SetSearchTargetPrepare(out.toggle, prepare)
    HM.SetSearchTargetPrepare(out.toggle, HM.GetSearchTargetPrepare(out.toggle))
    HM.SetCommandAction(out.toggle, action)
    HM.SetSectionCursor(out.body, math.min(HM.GetSectionWidth(out.body) and -80 or 0, -39))
    HM.SetFixedPreviewHeight(out.body, 310)
    HM.SetSectionEntry(out.details, HM.GetSectionEntry(out.body))
    HM.SetSectionWidth(out.details, 640)
    HM.MarkContextColorHost(out.details)
    HM.SetBuilderInsets(out.ctx, 0, 0)
    HM.SetSectionEnsureVisible(out.entry, ensure)
    HM.SetSectionRefreshState(out.entry, refresh)
    HM.SetMissingSectionResolver(out.entry, resolve)
    HM.ReserveSectionActions(out.entry, out.more, 34)
    HM.ReserveSectionActions(out.summaryEntry, out.more, 34)
    HM.RefreshSectionLayout(out.entry)
    HM.RefreshSectionLayout(out.summaryEntry)
    HM.SetSectionPopupGetter(out.more, prepare)
    HM.ReleaseColorShortcut(out.shortcut)
    HM.AddNavIcon("suite_one", { icon = { 2, 0 }, hdIcon = { 0, 3 }, accent = true })
    HM.AddNavIcon("suite_two", { icon = { 3, 0 } })
    out.entry._msuf2RefreshLayout = nil
    out.theme, out.layouts = M.Theme, layouts
    out.reads = { HM.GetSectionCursor(out.body), HM.GetSectionEnsureVisible(out.entry) == ensure,
        HM.GetSectionRefreshState(out.entry) == refresh, HM.GetMissingSectionResolver(out.entry) == resolve }
    -- Functions differ per run; compare the fields that hold them by presence.
    out.toggle._msuf2PrepareExactSearchTarget = out.toggle._msuf2PrepareExactSearchTarget == prepare
    out.entry._msuf2EnsureVisible = out.entry._msuf2EnsureVisible == ensure
    out.entry._msuf2RefreshState = out.entry._msuf2RefreshState == refresh
    out.entry._msuf2ResolveMissingSection = out.entry._msuf2ResolveMissingSection == resolve
    out.more._msuf2GetSectionPopup = out.more._msuf2GetSectionPopup == prepare
    out.entry._msuf2SectionActions = out.entry._msuf2SectionActions == out.more
    out.summaryEntry._msuf2SectionActions = out.summaryEntry._msuf2SectionActions == out.more
    out.details._msuf2CollapsibleEntry = out.details._msuf2CollapsibleEntry == out.entry
    out.body._msuf2CollapsibleEntry = true
    return out
end
local oldM = OldHost()
local newFields, oldFields = Build(newHM, newM), Build(HostBridge.Menu2(oldM), oldM)
Check(Same(newFields, oldFields), "a page build leaves different fields on a v2 and an older Menu2")
Check(newFields.button._msuf2SkipHistoryCheckpoint and newFields.button._msuf2AllowCombatClick
    and newFields.entry._msuf2ActionReserve == 34 and newFields.entry._msuf2ColorSwatchReserve == 60
    and newFields.summaryEntry._msuf2ColorSwatchReserve == nil and newFields.layouts == 1
    and newFields.theme.navIconGrid.suite_one[2] == 3
    and newFields.theme.navIconColors.suite_one == newFields.theme.navIconColors.home,
    "the page build did not leave the protocol fields MSUF reads")

------------------------------------------------------------------ Suite API
local log
local function Logger(name, result)
    return function(...)
        log[#log + 1] = name .. "(" .. tostring((...)) .. "," .. tostring((select(2, ...))) .. ")"
        return result
    end
end

-- The Suite namespace owners API.lua delegates to (the real files are covered
-- by their own contracts).
local function SuiteNamespace()
    local suite = {
        Database = { StageFactoryReset = Logger("StageFactoryReset", true) },
        GetOverview = Logger("GetOverview", { version = "1.0" }),
        Changelog = { entries = { { version = "1.0" } } },
        Installer = { Open = Logger("Open", true), MaybeShow = Logger("MaybeShow"),
            IsFirstRunPending = Logger("IsFirstRunPending", false), IsOpen = Logger("IsOpen", true) },
        OnMSUFProfileLifecycle = Logger("OnMSUFProfileLifecycle", false),
        OnMSUFProfileChanged = Logger("OnMSUFProfileChanged"),
        Suite = { ApplyGlobalFont = Logger("ApplyFonts") },
        CooldownManager = { GetAnchorFrame = Logger("GetAnchorFrame", "anchor") },
        Options = { BuildColorsCategory = Logger("BuildColorsCategory") },
        SuiteProfiles = { Available = Logger("Available", true), Export = Logger("Export", "MSUFS3:x"),
            ExportModule = Logger("ExportModule", "MSUFM2:y"), Import = Logger("Import", true),
            ImportModule = Logger("ImportModule", true), ImportModuleIntoNew = Logger("ImportModuleIntoNew", true) },
        SuiteOrder = { "minimap", "bags", "ghost" },
        SuiteCatalog = { minimap = { title = "Minimap" }, bags = { title = "Bags" } },
        Client = { AddOnEnabled = Logger("AddOnEnabled", true) },
    }
    Load(root .. "/MSUF_Suite/Core/API.lua", "MSUF_Suite", suite)
    -- FontBridge.lua publishes this global for older hosts.
    _G.MSUFSuite_ApplyFontsFromMSUF = suite.Suite.ApplyGlobalFont
    return suite
end

do
    local api = SuiteNamespace().API
    Check(type(api) == "table" and api.version == 1, "MSUFSuite.API must be version 1")
    for _, name in ipairs({ "StageFactoryReset", "GetOverview", "GetChangelog", "OpenInstaller",
        "MaybeShowInstaller", "IsInstallerPending", "IsInstallerOpen", "OnMSUFProfileChanged",
        "OnMSUFProfileLifecycle", "ApplyFontsFromMSUF", "HasCooldownAnchor", "GetCooldownAnchorFrame",
        "HasColorsCategory", "BuildColorsCategory", "GetProfileModules", "IsSkinAddOnEnabled" }) do
        Check(type(api[name]) == "function", "MSUFSuite.API lacks " .. name)
    end
    for _, name in ipairs({ "Available", "Export", "ExportModule", "Import", "ImportModule", "ImportModuleIntoNew" }) do
        Check(type(api.Profiles[name]) == "function", "MSUFSuite.API.Profiles lacks " .. name)
    end
end

local function Link(suite)
    _G.MSUFSuite = suite
    local ns = {}
    Load(classic .. "/MidnightSimpleUnitFrames/Kernel/MSUF_SuiteLink.lua", "MidnightSimpleUnitFrames", ns)
    return ns.SuiteLink
end

local function Drive(link)
    log = {}
    local answers = {}
    local function Note(name, ...) answers[#answers + 1] = name .. "=" .. tostring((...)) .. "," .. tostring((select(2, ...))) end
    Note("CanStageFactoryReset", link.CanStageFactoryReset())
    Note("StageFactoryReset", link.StageFactoryReset())
    Note("GetOverview", (link.GetOverview() or {}).version)
    Note("GetChangelog", link.GetChangelog().entries[1].version)
    Note("CanOpenInstaller", link.CanOpenInstaller())
    Note("OpenInstaller", link.OpenInstaller())
    Note("MaybeShowInstaller", link.MaybeShowInstaller())
    Note("InstallerBusy", link.InstallerBusy())
    Note("NotifyProfileLifecycle", link.NotifyProfileLifecycle("delete", "A", "B"))
    Note("NotifyProfileChanged", link.NotifyProfileChanged("A", "switch"))
    Note("ApplyFonts", link.ApplyFonts())
    Note("HasCooldownAnchor", link.HasCooldownAnchor())
    Note("GetCooldownAnchorFrame", link.GetCooldownAnchorFrame("EssentialCooldownViewer"))
    Note("HasColorsCategory", link.HasColorsCategory())
    Note("BuildColorsCategory", link.BuildColorsCategory("ctx", "builder"))
    local profiles = link.Profiles()
    Note("Available", profiles.Available())
    Note("Export", profiles.Export())
    Note("ExportModule", profiles.ExportModule("minimap"))
    Note("Import", profiles.Import("New", "MSUFS3:x"))
    Note("ImportModule", profiles.ImportModule("MSUFM2:y"))
    Note("ImportModuleIntoNew", profiles.ImportModuleIntoNew("New", "MSUFM2:y"))
    local modules = {}
    for _, module in ipairs(link.ProfileModules()) do modules[#modules + 1] = module.id .. ":" .. module.title end
    Note("ProfileModules", table.concat(modules, " "))
    Note("ModuleTitle", link.ModuleTitle("bags"), link.ModuleTitle("ghost"))
    Note("SkinAddOnEnabled", link.SkinAddOnEnabled())
    return table.concat(answers, "\n"), table.concat(log, " ")
end

-- New host + new Suite: the API table answers.
local suite = SuiteNamespace()
local apiAnswers, apiCalls = Drive(Link(suite))
-- Old host + new Suite: the host's by-path reads (the API hidden).
local hidden = SuiteNamespace()
hidden.API = nil
local pathAnswers, pathCalls = Drive(Link(hidden))
Check(apiAnswers == pathAnswers and apiCalls == pathCalls,
    "an old host's by-path reads and the Suite API answer differently:\n" .. apiAnswers .. "\n--\n" .. pathAnswers
    .. "\n" .. apiCalls .. "\n--\n" .. pathCalls)
Check(apiCalls:find("StageFactoryReset(nil,nil)", 1, true) and apiCalls:find("ApplyFonts(nil,nil)", 1, true)
    and apiCalls:find("GetAnchorFrame(EssentialCooldownViewer,nil)", 1, true)
    and apiCalls:find("OnMSUFProfileChanged(A,switch)", 1, true), "the Suite owners were not reached")
do
    -- The link prefers the API over the namespace paths.
    local preferred = SuiteNamespace()
    preferred.API.StageFactoryReset = function() return "api" end
    local link = Link(preferred)
    log = {}
    Check(link.StageFactoryReset() == "api" and #log == 0,
        "the host link must prefer MSUFSuite.API over the namespace paths")
end
-- The Suite keeps the namespace and the font global older hosts read.
do
    local function Source(rel)
        local handle = assert(io.open(root .. "/" .. rel, "rb"))
        local text = handle:read("*a")
        handle:close()
        return text
    end
    Check(Source("MSUF_Suite/Core/Startup.lua"):find("_G.MSUFSuite = Suite", 1, true)
        and Source("MSUF_Suite/Core/FontBridge.lua"):find("_G.MSUFSuite_ApplyFontsFromMSUF = S.ApplyGlobalFont", 1, true),
        "older hosts read MSUFSuite and MSUFSuite_ApplyFontsFromMSUF by name")
    local toc = Source("MSUF_Suite/MSUF_Suite_Mainline.toc")
    Check(toc:find("Core\\HostBridge.lua", 1, true) < toc:find("Core\\HostBridgeMenu.lua", 1, true)
        and toc:find("Core\\API.lua", 1, true) < toc:find("Core\\Startup.lua", 1, true),
        "HostBridgeMenu.lua must load after HostBridge.lua and API.lua before Startup.lua")
end
_G.MSUFSuite, _G.MSUFSuite_ApplyFontsFromMSUF = nil, nil
print(("suite_host_api_v2_contract: ok (%d checks)"):format(checks))

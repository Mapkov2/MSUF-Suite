-- Embedded Skinning uses MSUF's shared history; standalone editor keeps its
-- own small fallback stack when no MSUF menu is mounted.
local function Copy(value)
    if type(value) ~= "table" then return value end
    local result = {}
    for key, item in pairs(value) do result[key] = Copy(item) end
    return result
end
local root = { optionsUI = {}, activeProfile = "Default" }
local skin
skin = {
    DB = { color = 1 }, CopyValue = Copy,
    IsCombatLocked = function() return false end,
    Database = {
        GetRoot = function() return root end,
        GetActiveProfileName = function() return "Default" end,
        SetProfile = function(_, data) skin.DB = Copy(data); return true end,
        SetActiveProfile = function() return true end,
    },
    ReportError = function(_, message) error(message) end,
}
-- The client's securecallfunction reports an error and returns nothing.
local reported = {}
skin.Safety = { Dispatch = function(callback, ...)
    local results = { pcall(callback, ...) }
    if not results[1] then
        reported[#reported + 1] = tostring(results[2])
        return
    end
    return unpack(results, 2)
end }
local engineListener
skin.Registry = { AddListener = function(_, callback) engineListener = callback end }
-- Retail and Forever always have C_Timer; this stand-in repaints at once.
local function RunAtOnce(_, callback) callback() end
C_Timer = { After = RunAtOnce }
MapkoSkin = skin
local private = {}
assert(loadfile("MSUF_Suite_Skin_Options/MSKIN_OptionsBootstrap.lua"))("MSUF_Suite_Skin_Options", private)
local options = skin.Options
local calls = { begin = 0, commit = 0, undo = 0, redo = 0 }
MSUF2 = {
    GetHistoryState = function() return { undoLabel = "Skin color", redoLabel = nil } end,
    IsHistoryCapturing = function() return false end,
    BeginHistoryTransaction = function() calls.begin = calls.begin + 1; return true end,
    CommitHistoryTransaction = function() calls.commit = calls.commit + 1; return true end,
    Undo = function() calls.undo = calls.undo + 1; return true end,
    Redo = function() calls.redo = calls.redo + 1; return true end,
}
options.embeddedHost = { IsShown = function() return true end }
assert(options.BeginUserChange("Skin color"))
skin.DB.color = 2
assert(options.CommitUserChange("Skin color"))
assert(calls.begin == 1 and calls.commit == 1, "embedded change skipped shared history")
assert(options.GetHistoryState() == "Skin color", "embedded history label was not shared")
assert(options.Undo() and options.Redo() and calls.undo == 1 and calls.redo == 1,
    "Skinning undo/redo did not follow MSUF")
options.embeddedHost = { IsShown = function() return false end }
assert(options.BeginUserChange("Standalone color"))
skin.DB.color = 3
assert(options.CommitUserChange("Standalone color"))
assert(options.Undo() and skin.DB.color == 2, "standalone history fallback failed")
-- A restore that raises is reported and does not lock the history.
local setProfile = skin.Database.SetProfile
skin.Database.SetProfile = function() error("profile restore failed") end
assert(not options.Redo() and #reported == 1 and reported[1]:find("profile restore failed", 1, true),
    "a failing history restore was not reported")
skin.Database.SetProfile = setProfile
assert(options.BeginUserChange("After a failed restore"),
    "a failing history restore left the history locked")
options.CancelUserChange()
print("Suite Skinning history: embedded MSUF and standalone fallback passed")

-- Refreshers register once and belong to the page being built: a hidden page,
-- or a page whose host is hidden, costs nothing on a refresh.
local shellRuns, pageRuns, modeRuns = 0, 0, 0
local function ShellRefresher() shellRuns = shellRuns + 1 end
local function ModeListener() modeRuns = modeRuns + 1 end
local function Shown(shown) return { shown = shown, IsShown = function(self) return self.shown end } end
options.TrackRefresh(ShellRefresher)
options.TrackRefresh(ShellRefresher)
options.TrackMode(ModeListener)
options.TrackMode(ModeListener)
local page, pageHost = Shown(true), Shown(true)
options.BuildPage(page, pageHost, function()
    options.TrackRefresh(function() pageRuns = pageRuns + 1 end)
end)
options.RefreshAll()
assert(shellRuns == 1 and pageRuns == 1, "duplicate or missing refresher registration")
page.shown = false
options.RefreshAll()
assert(shellRuns == 2 and pageRuns == 1, "hidden page still refreshed")
page.shown, pageHost.shown = true, false
options.RefreshAll()
assert(pageRuns == 1, "page of a hidden host still refreshed")
pageHost.shown = true
assert(options.SetMode(options.GetMode() == "expert" and "guided" or "expert"))
assert(modeRuns == 1 and pageRuns == 2, "mode switch did not run listeners once and refresh the shown page")

-- Every Skinning options string resolves in the skin's English table (which
-- declares no key twice) and in the Suite's German pack.
local function ReadFile(path)
    local file = assert(io.open(path, "rb"))
    local text = file:read("*a"):gsub("\r\n", "\n")
    file:close()
    return text
end
local locales = {}
local Support = dofile("tools/tests/suite_test_support.lua")
local germanPack = Support.SuitePack(".", "deDE")
for _, locale in ipairs({ "enUS" }) do
    local source = ReadFile("MSUF_Suite_Skin/Locales/" .. locale .. ".lua")
    local seen = {}
    for line in source:gmatch("[^\n]+") do
        local key = line:match('^%s*%["(.-)"%]%s*=') or line:match("^%s*([%a_][%w_]*)%s*=")
        if key then
            assert(not seen[key], locale .. " declares a locale key twice: " .. key)
            seen[key] = true
        end
    end
    local captured
    assert(loadfile("MSUF_Suite_Skin/Locales/" .. locale .. ".lua"))("MSUF_Suite_Skin",
        { RegisterLocale = function(_, values) captured = values end })
    locales[locale] = assert(captured, locale .. " did not register")
end
local checked = 0
for line in ReadFile("MSUF_Suite_Skin_Options/MSUF_Suite_Skin_Options_Mainline.toc"):gmatch("[^\n]+") do
    if line:match("%.lua$") then
        local source = ReadFile("MSUF_Suite_Skin_Options/" .. line:gsub("\\", "/"))
        for raw in source:gmatch('%f[%w_]L%["([^"\n]*)"%]') do
            local key = raw:gsub("\\n", "\n")
            local text = locales.enUS[key]
            assert(text and (germanPack[text] or Support.SKIN_SAME_IN_GERMAN[text]),
                "Skinning string missing from the locale tables: " .. raw)
            checked = checked + 1
        end
    end
end
assert(checked > 300, "Skinning locale coverage check is vacuous")
-- The runtime contract texts describe what the engine really does: the
-- window corner drag uses a self-stopping OnUpdate, one-shot timers batch
-- work, and Suite-made indicators are reparented.
for _, path in ipairs({ "MSUF_Suite_Skin_Options/Pages/Advanced.lua", "MSUF_Suite_Skin_Options/Pages/Skins.lua" }) do
    local source = ReadFile(path)
    for _, stale in ipairs({ "No OnUpdate handlers", "No tickers or timers", "No frame reparenting",
        "No polling, ticker or idle OnUpdate" }) do
        assert(not source:find(stale, 1, true), path .. " still claims: " .. stale)
    end
end

-- Engine notifications arrive once per setting write (every slider tick and
-- color picker move); they repaint once on the next frame. A finished user
-- change repaints once, not again for its own notification.
local timers = {}
C_Timer = { After = function(_, callback) timers[#timers + 1] = callback end }
local repaints = 0
options.TrackRefresh(function() repaints = repaints + 1 end)
for _ = 1, 5 do engineListener(options, "color", "accent") end
assert(repaints == 0 and #timers == 1,
    "setting notifications repainted at once or scheduled several repaints")
timers[1]()
assert(repaints == 1, "the coalesced repaint did not run")
timers, repaints = {}, 0
assert(options.BeginUserChange("Click"))
skin.DB.color = 9
engineListener(options, "color", "accent")
options.CommitUserChange("Click")
for index = 1, #timers do timers[index]() end
assert(repaints == 1, "one click repainted the options " .. repaints .. " times")
C_Timer = { After = RunAtOnce }

-- Every search entry names a control that exists on the page it opens, and
-- no text points to a command the Suite does not ship.
local PAGE_FILES = {
    dashboard = "Dashboard", looks = "Looks", icons = "Icons", colors = "Colors",
    typography = "Typography", geometry = "Geometry", skins = "Skins", coverage = "Coverage",
    hud = "HUD", profiles = "Profiles", advanced = "Advanced",
}
local function PageSource(key)
    return ReadFile("MSUF_Suite_Skin_Options/Pages/" .. assert(PAGE_FILES[key], key) .. ".lua")
end
local searchSource = ReadFile("MSUF_Suite_Skin_Options/Shell/Search.lua")
local adapterSource = ReadFile("MSUF_Suite_Skin/Adapters/Blizzard.lua")
local entriesChecked = 0
for key, label in searchSource:gmatch('{ "(%w+)", (L%b[]),') do
    assert(PageSource(key):find(label, 1, true),
        "search entry names no control on its page: " .. key .. " / " .. label)
    entriesChecked = entriesChecked + 1
end
for key, name in searchSource:gmatch('{ "(%w+)", NS%.L%.([%w_]+),') do
    assert(PageSource(key):find("NS.L." .. name, 1, true)
        or key == "skins" and adapterSource:find('labelKey = "' .. name .. '"', 1, true),
        "search entry names no control on its page: " .. key .. " / " .. name)
    entriesChecked = entriesChecked + 1
end
assert(entriesChecked > 50, "search entry check is vacuous")

-- A result for a control Guided mode hides opens in Expert mode, like a
-- result on an Expert-only page.
-- The engine's look and palette catalogs (Defaults.lua) are loaded; no page
-- has registered yet (Window.lua), so results carry the page key.
local searchNS = {
    L = setmetatable({}, { __index = function(_, key) return key end }),
    Client = { isForever = false },
}
assert(loadfile("MSUF_Suite_Skin/Core/Defaults.lua"))("MSUF_Suite_Skin", searchNS)
assert(loadfile("MSUF_Suite_Skin/Core/DefaultsLooks.lua"))("MSUF_Suite_Skin", searchNS)
local searchOptions = { GetPageDefinition = function() return nil end }
assert(loadfile("MSUF_Suite_Skin_Options/Shell/Search.lua"))("MSUF_Suite_Skin_Options", {
    NS = searchNS,
    Options = searchOptions,
})
local function SearchRecord(label)
    local results = searchOptions.SearchSettings(label, 100)
    for index = 1, #results do
        if results[index].label == label then return results[index] end
    end
    error("search found no entry " .. label)
end
for _, label in ipairs({ "Shaded surfaces", "Light direction", "Shading strength", "Surface depth",
    "Outline opacity", "Bar background", "Bar and button shape", "Normal icon opacity",
    "Border thickness", "Surfaces", "Text", "Accents", "Borders", "Controls", "Blizzard" }) do
    assert(SearchRecord(label).expert == true,
        "a result for a control Guided mode hides does not switch to Expert: " .. label)
end
for _, label in ipairs({ "Style preset", "Window opacity", "Button style", "Micro Bar style",
    "Verified item icon borders", "Color palette (colors only)", "Find a color or UI element..." }) do
    assert(SearchRecord(label).expert == false, "a result for a Guided control switches to Expert: " .. label)
end
for line in ReadFile("MSUF_Suite_Skin_Options/MSUF_Suite_Skin_Options_Mainline.toc"):gmatch("[^\n]+") do
    if line:match("%.lua$") then
        assert(not ReadFile("MSUF_Suite_Skin_Options/" .. line:gsub("\\", "/")):find("/mskin", 1, true),
            line .. " points to the /mskin command, which the Suite does not ship")
    end
end

-- A profile operation the engine refuses (combat, bad input) keeps the undo
-- step; only a replaced profile drops it. A replaced profile repaints the
-- options once (through ClearHistory), a refused one not at all.
local cleared, profileRepaints = 0, 0
local pageBuilder
local captured = {}
local function Widget()
    return setmetatable({}, { __index = function(_, key)
        if type(key) == "string" and key:match("^%u") then return function() end end
    end })
end
CreateFrame = function() return Widget() end
local profileOptions = {
    CreateSectionTitle = function() end,
    CreatePanel = function() return Widget() end,
    CreateText = function() return Widget() end,
    SetTextColor = function() end,
    TrackRefresh = function() end,
    RefreshAll = function() profileRepaints = profileRepaints + 1 end,
    -- Like the real one, clearing the history repaints the options.
    ClearHistory = function()
        cleared = cleared + 1
        profileRepaints = profileRepaints + 1
    end,
    RegisterPage = function(_, _, builder) pageBuilder = builder end,
    -- The two-click confirmation (Shell/Widgets.lua) only arms on a taken
    -- import name, which these stand-in profile actions never report.
    CreateConfirmation = function()
        return { IsArmed = function() return false end, Arm = function() end, Disarm = function() end }
    end,
    CreateCycle = function(_, label, _, _, setter) captured[label] = setter; return Widget() end,
    CreateInput = function() return Widget() end,
}
local function Button(_, label, _, _, callback)
    captured[label] = callback
    return Widget()
end
profileOptions.CreateButton = Button
profileOptions.CreateSettingButton = Button
local refuse = true
local profileNS = {
    L = setmetatable({}, { __index = function(_, key) return key end }),
    Surface = { Attach = function() end },
    Database = {
        GetActiveProfileName = function() return "Default" end,
        GetProfileNames = function() return { "Default", "Raid" } end,
        NormalizeProfileName = function(name) return name end,
        CreateProfile = function(name) if refuse then return false, "combat" end; return true, name end,
        SetActiveProfile = function(name) if refuse then return false, "combat" end; return true, name end,
        DeleteProfile = function(name) if refuse then return false, "combat" end; return true, name end,
    },
    ProfileIO = {
        maxEncodedBytes = 100,
        ImportProfile = function() if refuse then return false, "combat" end; return true, "Raid" end,
        ImportAll = function() if refuse then return false, "combat" end; return true, "Default" end,
    },
}
assert(loadfile("MSUF_Suite_Skin_Options/Pages/Profiles.lua"))("MSUF_Suite_Skin_Options",
    { NS = profileNS, Options = profileOptions })
pageBuilder(Widget())
local PROFILE_ACTIONS = { "Active profile", "Create clean", "Copy current", "Delete active",
    "Import profile", "Import all" }
local function RunProfileAction(label)
    profileRepaints = 0
    captured[label]("Raid")
    return profileRepaints
end
for _, label in ipairs(PROFILE_ACTIONS) do
    assert(RunProfileAction(label) == 0, label .. ": a refused profile operation repainted the options")
end
assert(cleared == 0, "a refused profile operation dropped the undo step")
refuse = false
for _, label in ipairs(PROFILE_ACTIONS) do
    local repaints = RunProfileAction(label)
    assert(repaints == 1, label .. " repainted the options " .. repaints .. " times")
end
assert(cleared == #PROFILE_ACTIONS, "a replaced profile kept the undo step")
print("Suite Skinning options: refresher scoping and " .. checked .. " localized strings passed")

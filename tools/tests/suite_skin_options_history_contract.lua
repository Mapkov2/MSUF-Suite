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
    Registry = { AddListener = function() end },
    ReportError = function(_, message) error(message) end,
}
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

-- Every Skinning options string resolves in the English and German tables,
-- and neither table declares a key twice.
local function ReadFile(path)
    local file = assert(io.open(path, "rb"))
    local text = file:read("*a"):gsub("\r\n", "\n")
    file:close()
    return text
end
local locales = {}
for _, locale in ipairs({ "enUS", "deDE" }) do
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
            assert(locales.enUS[key] and locales.deDE[key], "Skinning string missing from the locale tables: " .. raw)
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
print("Suite Skinning options: refresher scoping and " .. checked .. " localized strings passed")

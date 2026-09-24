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

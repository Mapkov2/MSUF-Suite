local addonName, Private = ...
local NS = assert(_G.MapkoSkin, "Suite skin engine is required")

local O = NS.Options or {}
NS.Options = O
Private.NS = NS
Private.Options = O

O.addonName = addonName
O.pages = O.pages or {}
O.refreshers = O.refreshers or {}
O.widgetStates = O.widgetStates or setmetatable({}, { __mode = "k" })
O.textRoles = O.textRoles or setmetatable({}, { __mode = "k" })
O.modeListeners = O.modeListeners or {}

local root = NS.Database.GetRoot()
root.optionsUI = type(root.optionsUI) == "table" and root.optionsUI or {}
O.ui = root.optionsUI
O.ui.mode = O.ui.mode == "expert" and "expert" or "guided"
O.ui.colorGroup = type(O.ui.colorGroup) == "string" and O.ui.colorGroup or "surfaces"

local history = { active = nil, undo = nil, redo = nil, restoring = false }
O.history = history
local function NativeHistory()
    local host = O.embeddedHost
    local menu = _G.MSUF2
    if host and host.IsShown and host:IsShown() and type(menu) == "table"
        and type(menu.GetHistoryState) == "function" then return menu end
end

local function DeepEqual(left, right, seen)
    if left == right then return true end
    if type(left) ~= type(right) or type(left) ~= "table" then return false end
    seen = seen or {}
    if seen[left] == right then return true end
    seen[left] = right
    for key, value in pairs(left) do
        if not DeepEqual(value, right[key], seen) then return false end
    end
    for key in pairs(right) do
        if left[key] == nil then return false end
    end
    return true
end

function O.GetMode()
    return O.ui.mode
end

function O.SetMode(mode)
    mode = mode == "expert" and "expert" or "guided"
    if O.ui.mode == mode then return false end
    O.ui.mode = mode
    for index = 1, #O.modeListeners do
        local ok, message = pcall(O.modeListeners[index], mode)
        if not ok then NS.ReportError("options mode", message) end
    end
    O.RefreshAll()
    return true
end

function O.TrackMode(callback)
    if type(callback) == "function" then
        O.modeListeners[#O.modeListeners + 1] = callback
    end
    return callback
end

function O.BeginUserChange(label)
    if history.restoring or history.active or NS.IsCombatLocked() then return false end
    local menu = NativeHistory()
    if menu and menu.IsHistoryCapturing and menu.IsHistoryCapturing() then
        history.active = { nativeNested = true }
        return true
    end
    if menu and menu.BeginHistoryTransaction
        and menu.BeginHistoryTransaction(label, "suite:skin") == true then
        history.active = { native = true }
        return true
    end
    history.active = {
        label = tostring(label or "Setting"),
        profile = NS.Database.GetActiveProfileName(),
        data = NS.CopyValue(NS.DB),
    }
    return true
end

function O.IsUserChangeActive()
    return history.active ~= nil
end

function O.CancelUserChange()
    if history.active and history.active.native then
        local menu = NativeHistory()
        if menu and menu.CancelHistoryTransaction then menu.CancelHistoryTransaction() end
    end
    history.active = nil
end

function O.CommitUserChange(label)
    local change = history.active
    history.active = nil
    if change and change.native then
        local menu = NativeHistory()
        local result = menu and menu.CommitHistoryTransaction and menu.CommitHistoryTransaction() == true
        O.RefreshAll()
        return result
    end
    if change and change.nativeNested then O.RefreshAll(); return true end
    if not change or change.profile ~= NS.Database.GetActiveProfileName() then return false end
    if DeepEqual(change.data, NS.DB) then return false end
    change.label = tostring(label or change.label or "Setting")
    history.undo = change
    history.redo = nil
    O.RefreshAll()
    return true
end

function O.ClearHistory()
    history.active, history.undo, history.redo = nil, nil, nil
    O.RefreshAll()
end

local function RestoreHistory(sourceKey, destinationKey)
    if NS.IsCombatLocked() then return false end
    local item = history[sourceKey]
    local profile = NS.Database.GetActiveProfileName()
    if not item or item.profile ~= profile then return false end
    history.restoring = true
    history[destinationKey] = { label = item.label, profile = profile, data = NS.CopyValue(NS.DB) }
    history[sourceKey] = nil
    local ok = NS.Database.SetProfile(profile, item.data)
    if ok then ok = NS.Database.SetActiveProfile(profile) end
    history.restoring = false
    O.RefreshAll()
    return ok == true
end

function O.Undo()
    local menu = NativeHistory()
    if menu and menu.Undo then return menu.Undo() end
    return RestoreHistory("undo", "redo")
end

function O.Redo()
    local menu = NativeHistory()
    if menu and menu.Redo then return menu.Redo() end
    return RestoreHistory("redo", "undo")
end

function O.GetHistoryState()
    local menu = NativeHistory()
    if menu then
        local state = menu.GetHistoryState()
        return state.undoLabel, state.redoLabel
    end
    return history.undo and history.undo.label or nil, history.redo and history.redo.label or nil
end

function O.DiscardLastChange(label)
    if history.undo and history.undo.label == label then
        history.undo, history.redo = nil, nil
        O.RefreshAll()
        return true
    end
    return false
end

function O.TrackRefresh(callback)
    if type(callback) == "function" then
        O.refreshers[#O.refreshers + 1] = callback
    end
    return callback
end

function O.RefreshAll()
    for index = 1, #O.refreshers do
        local ok, message = pcall(O.refreshers[index])
        if not ok then
            NS.ReportError("options refresh", message)
        end
    end
end

NS.Registry.AddListener(O, function()
    O.RefreshAll()
end)

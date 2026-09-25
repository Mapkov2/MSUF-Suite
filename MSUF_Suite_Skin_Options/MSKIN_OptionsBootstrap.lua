local addonName, Private = ...
local NS = assert(_G.MapkoSkin, "Suite skin engine is required")

local O = NS.Options or {}
NS.Options = O
Private.NS = NS
Private.Options = O

O.addonName = addonName
O.widgetStates = O.widgetStates or setmetatable({}, { __mode = "k" })
O.textRoles = O.textRoles or setmetatable({}, { __mode = "k" })

local root = NS.Database.GetRoot()
root.optionsUI = type(root.optionsUI) == "table" and root.optionsUI or {}
O.ui = root.optionsUI
O.ui.mode = O.ui.mode == "expert" and "expert" or "guided"
O.ui.colorGroup = type(O.ui.colorGroup) == "string" and O.ui.colorGroup or "surfaces"

------------------------------------------------------------------ refreshers
-- Refreshers repaint option widgets after a setting, profile or mode change.
-- Shell refreshers (window chrome, text roles) always run. A refresher that
-- registers while a page is being built belongs to that page and runs only
-- while the page and its host are shown; showing a page or a host refreshes
-- it again, so hidden pages cost nothing on a slider tick. Registering the
-- same callback twice is a no-op.
local shellRefreshers = {}
local pageRefreshers = {}
local registered = {}
local buildingPage
local modeListeners = {}
local modeRegistered = {}

function O.TrackRefresh(callback)
    if type(callback) ~= "function" or registered[callback] then return callback end
    registered[callback] = true
    local list = buildingPage or shellRefreshers
    list[#list + 1] = callback
    return callback
end

-- Builds one page of a host (standalone window or embedded rail) and binds
-- the refreshers its widgets register to that page.
function O.BuildPage(page, host, builder)
    local entry = { page = page, host = host }
    pageRefreshers[#pageRefreshers + 1] = entry
    buildingPage = entry
    builder(page)
    buildingPage = nil
end

local function RunList(list)
    for index = 1, #list do
        list[index]()
    end
end

function O.RefreshAll()
    RunList(shellRefreshers)
    for index = 1, #pageRefreshers do
        local entry = pageRefreshers[index]
        if entry.page:IsShown() and entry.host:IsShown() then
            RunList(entry)
        end
    end
end

------------------------------------------------------------------ mode
function O.GetMode()
    return O.ui.mode
end

function O.SetMode(mode)
    mode = mode == "expert" and "expert" or "guided"
    if O.ui.mode == mode then return false end
    O.ui.mode = mode
    for index = 1, #modeListeners do
        modeListeners[index](mode)
    end
    O.RefreshAll()
    return true
end

-- Mode listeners run on every mode switch, also for hidden pages, because
-- they re-layout rows rather than repaint values.
function O.TrackMode(callback)
    if type(callback) == "function" and not modeRegistered[callback] then
        modeRegistered[callback] = true
        modeListeners[#modeListeners + 1] = callback
    end
    return callback
end

------------------------------------------------------------------ history
-- Embedded in the MSUF menu, changes join MSUF's shared history. The
-- standalone window keeps one small undo/redo step of its own.
local history = { active = nil, undo = nil, redo = nil, restoring = false }
O.history = history

local function NativeHistory()
    local host = O.embeddedHost
    local menu = _G.MSUF2
    if host and host.IsShown and host:IsShown() and type(menu) == "table"
        and type(menu.GetHistoryState) == "function" then
        return menu
    end
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

-- Ends the active change and repaints the options once, whether or not the
-- change produced a history entry.
function O.CommitUserChange(label)
    local change = history.active
    history.active = nil
    local committed = false
    if change and change.native then
        local menu = NativeHistory()
        committed = menu and menu.CommitHistoryTransaction and menu.CommitHistoryTransaction() == true or false
    elseif change and change.nativeNested then
        committed = true
    elseif change and change.profile == NS.Database.GetActiveProfileName()
        and not DeepEqual(change.data, NS.DB) then
        change.label = tostring(label or change.label or "Setting")
        history.undo = change
        history.redo = nil
        committed = true
    end
    O.RefreshAll()
    return committed
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

NS.Registry.AddListener(O, function()
    O.RefreshAll()
end)

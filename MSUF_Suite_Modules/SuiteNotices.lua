local _, Private = ...
local NS, S = Private.NS, Private.Suite
local Notices, Module = {}, {}
S.Notifications = Notices
local function Records()
    local data = S.CharacterData("notificationHistory")
    if not data then return end
    if type(data.entries) ~= "table" then data.entries = {} end
    local entries = data.entries
    for i = #entries, 1, -1 do
        local row = entries[i]
        if type(row) ~= "table" or not S.PublicText(row.key) or not S.PublicText(row.title)
            or not S.PublicText(row.detail) or not S.Finite(row.time) or not S.Finite(row.id)
            or not S.Finite(row.count) or row.count < 1 or #row.detail > 2048 or #row.title > 512 then table.remove(entries, i) end
    end
    local limit = math.max(10, math.min(100, Module.config.limit or 60))
    while #entries > limit do table.remove(entries) end
    return entries, data, limit
end
function Notices.Push(key, title, detail, module)
    if not Module.active or not S.PublicText(key) or #key > 400 or not S.PublicText(title)
        or not S.PublicText(detail) or #title > 512 or #detail > 2048 then return false end
    local entries, data, limit = Records()
    local now = GetServerTime()
    if not entries or not S.Finite(now) then return false end
    local found
    for i = 1, #entries do
        local row = entries[i]
        if row.key == key and now >= row.time and now - row.time <= Module.config.mergeSeconds then found = i break end
    end
    local row = found and table.remove(entries, found) or {}
    data.serial = (S.Finite(data.serial) and data.serial or 0) + 1
    row.id = row.id or data.serial
    row.key, row.title, row.detail, row.time = key, title, detail, now
    row.module = S.PublicText(module) and NS.SuiteCatalog[module] and module or nil
    row.count = math.min(9999, (S.Finite(row.count) and row.count or 0) + 1)
    row.read = false
    table.insert(entries, 1, row)
    while #entries > limit do table.remove(entries) end
    S.ToolListWindow.Refresh(Module)
    return true
end
local function Rows()
    local rows = {}
    for _, entry in ipairs(Records() or {}) do
        rows[#rows + 1] = { key = entry.id, entry = entry, checked = entry.read == true,
            label = S.Text("%s · %s (%d)"):format(date("%H:%M", entry.time), entry.title, entry.count),
            detail = entry.detail, search = entry.title .. " " .. entry.detail }
    end
    return rows
end
local function Clear()
    local profile = NS.DB
    S.Confirm("suite-notice-clear", { text = S.Text("Clear the saved Suite notices for this character?"), callback = function()
        if not Module.active or NS.InCombat() or NS.DB ~= profile then return end
        local _, data = Records()
        if data then data.entries = {} end
        S.ToolListWindow.Refresh(Module)
    end })
end
function Module:Open()
    return S.ToolListWindow.Open(self, { title = "Suite notice history",
        help = "Select a notice to mark it as read. Repeated notices are combined.",
        empty = "No saved notices yet. Enable the helpers you want to follow.", rows = Rows,
        onSelect = function(_, row) row.entry.read = true end,
        actions = {
            { label = "Open related settings", enabled = function(_, row) return row and row.entry.module ~= nil end,
                run = function(_, row) S.Open(row.entry.module) end },
            { label = "Clear history", run = Clear },
        } })
end
function Module:Enable() Records() end
function Module:Refresh() Records() S.ToolListWindow.Refresh(self) end
function Module:Disable() S.ToolListWindow.Close(self) end
S.Install("notificationHistory", Module)

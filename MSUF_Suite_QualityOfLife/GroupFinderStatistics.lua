local _, P = ...
local NS, S = P.NS, P.Suite
if NS.Client.isForever then return end
local Stats = { session = {}, applications = {}, serial = 0 }
P.GroupFinderStatistics = Stats
local KEYS = { "applied", "invited", "accepted", "declined", "cancelled", "expired" }
local OUTCOME = { invited = "invited", inviteaccepted = "accepted", declined = "declined", declined_full = "declined",
    invitedeclined = "cancelled", declined_delisted = "expired", failed = "expired", timedout = "expired", cancelled = "cancelled" }
local function Account()
    local root = NS.RootDB
    if type(root) ~= "table" then return end
    if type(root.suiteApplications) ~= "table" then root.suiteApplications = {} end
    return root.suiteApplications
end
function Stats.Data(scope)
    if scope == 1 then return Stats.session end
    if scope == 2 then return NS.CharacterData("applications") end
    return Account()
end
local function Increment(key)
    for scope = 1, 3 do
        local data = Stats.Data(scope)
        if data then
            local old = data[key]
            data[key] = math.min(1000000000, (S.Finite(old) and math.max(0, old) or 0) + 1)
        end
    end
end
local function Identity(id)
    local result = C_LFGList.GetSearchResultInfo(id)
    if not S.Public(result) or type(result) ~= "table" then return end
    local ids = result.activityIDs
    if not S.Public(ids) or type(ids) ~= "table" or not S.Finite(ids[1]) then return end
    local info = C_LFGList.GetActivityInfoTable(ids[1])
    if not S.Public(info) or type(info) ~= "table" then return end
    local mythic = info.isMythicPlusActivity
    if not S.Public(mythic) or mythic ~= true then return end
    return S.PublicText(result.partyGUID) or tostring(id)
end
local function New(id, identity)
    local oldest, oldestSerial, count
    count = 0
    for key, record in pairs(Stats.applications) do
        count = count + 1
        if not oldestSerial or record.serial < oldestSerial then oldest, oldestSerial = key, record.serial end
    end
    if count >= 128 then Stats.applications[oldest] = nil end
    Stats.serial = Stats.serial + 1
    local record = { identity = identity, serial = Stats.serial }
    Stats.applications[id] = record
    return record
end
function Stats.Changed(id, status, old)
    if not S.Finite(id) or not S.PublicText(status) or not S.PublicText(old) or status == old then return false end
    local record = Stats.applications[id]
    if status == "applied" then
        local identity = Identity(id)
        if not identity then return false end
        if record and record.identity == identity and record.status == status then return false end
        record = New(id, identity)
        record.status = status
        Increment("applied")
        return true
    end
    if not record or record.status == status or record.terminal then return false end
    local key = OUTCOME[status]
    record.status = status
    if not key then return false end
    if status ~= "invited" then record.terminal = true end
    if record[key] then return false end
    record[key] = true
    Increment(key)
    return true
end
function Stats.Start()
    for id in pairs(Stats.applications) do Stats.applications[id] = nil end
    local ids = C_LFGList.GetApplications()
    if not S.Public(ids) or type(ids) ~= "table" then return end
    for i = 1, math.min(#ids, 128) do
        local id = ids[i]
        if S.Finite(id) then
            local identity = Identity(id)
            if identity then
                local _, status = C_LFGList.GetApplicationInfo(id)
                if S.PublicText(status) then local record = New(id, identity)
                record.status = status end
            end
        end
    end
end
function Stats.Reset(scope)
    local data = Stats.Data(scope)
    if data then for _, key in ipairs(KEYS) do data[key] = nil end end
end
function Stats.Lines(scope)
    local data = Stats.Data(scope) or {}
    local values = {}
    for i, key in ipairs(KEYS) do values[i] = S.Finite(data[key]) and math.floor(math.max(0, data[key])) or 0 end
    return S.Text("Applied: %d"):format(values[1]) .. "\n" .. S.Text("Invited: %d"):format(values[2])
        .. "\n" .. S.Text("Accepted: %d"):format(values[3]) .. "\n" .. S.Text("Declined: %d"):format(values[4])
        .. "\n" .. S.Text("Cancelled: %d"):format(values[5]) .. "\n" .. S.Text("Expired: %d"):format(values[6])
end

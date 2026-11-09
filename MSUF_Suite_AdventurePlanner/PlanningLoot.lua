local _, P = ...
local NS, S, Plan = P.NS, P.Suite, P.PlanningTools
local Loot = {}
Plan.Loot = Loot
local LIMIT = 80

local function Item(link)
    link = Plan.Text(link, 1024)
    if not link then return end
    link = link:match("(|c%x%x%x%x%x%x%x%x|Hitem:[^|]+|h%[[^|]+%]|h|r)")
        or link:match("(|Hitem:[^|]+|h%[[^|]+%]|h)")
    if not link then return end
    local itemID, suffix, name = link:match("|Hitem:(%d+)([^|]*)|h%[([^|]+)%]|h")
    if suffix and suffix ~= "" and suffix:sub(1, 1) ~= ":" then return end
    itemID = tonumber(itemID)
    if itemID and itemID > 0 and itemID < 2 ^ 31 and name and #name <= 180 then return itemID, name, link end
end

function Loot.New(link, source)
    local id, name, clean = Item(link)
    if not id then return end
    return { id = id, name = name, link = clean, source = Plan.Name(source) }
end

function Loot.Save(entry)
    if not Plan.CanEdit() or not entry then return false end
    local entries = Plan.Bucket("loot")
    if not entries then return false end
    local key = tostring(entry.id)
    if not entries[key] and Plan.Count(entries) >= LIMIT then return false end
    entries[key] = entry
    Plan.Changed()
    return true
end

local function Status(entry)
    local api = C_Item and C_Item.IsEquippedItem
    if type(api) ~= "function" then return end
    local equipped = api(entry.id)
    if not S.Public(equipped) then return end
    if equipped == true then return S.Text("Item equipped (any version)"), true end
    if equipped == false then return S.Text("Not equipped"), false end
end

local function Lockout(entry, lockouts, now)
    if not entry.instance or not S.Finite(entry.difficulty) or not now then return end
    for _, lockout in ipairs(lockouts) do
        if lockout.name == entry.instance and lockout.difficulty == entry.difficulty
            and S.Finite(lockout.expires) and lockout.expires > now then
            return S.Text("Saved instance lockout until %s"):format(Plan.Date(lockout.expires))
        end
    end
end

local function CurrentLockouts()
    if not Plan.owner.config.weekly or not Plan.Weekly.lockoutsReady then return end
    local guid = S.PublicText(UnitGUID("player"))
    local account = Plan.Account()
    local entry = account and account.characters and guid and account.characters[guid]
    return entry and not entry.lockoutsPending and entry.lockouts or nil
end

local function Row(entry, status, lockout)
    local lines = { entry.link }
    if entry.source then lines[#lines + 1] = entry.source end
    if status then lines[#lines + 1] = status end
    if lockout then lines[#lines + 1] = lockout end
    return { key = tostring(entry.id), label = entry.name, detail = table.concat(lines, "\n"),
        search = table.concat({ entry.name, entry.source or "", status or "" }, " "), loot = entry }
end

function Loot.Rows(hideEquipped)
    if not Plan.CanEdit() then return {} end
    local rows, entries = {}, Plan.Bucket("loot")
    if not entries or not next(entries) then return rows end
    local lockouts, now = CurrentLockouts() or {}, Plan.Now()
    for _, entry in pairs(entries) do
        if type(entry) == "table" and S.Finite(entry.id) and Item(entry.link) == entry.id then
            local status, equipped = Status(entry)
            if not hideEquipped or not equipped then
                rows[#rows + 1] = Row(entry, status, Lockout(entry, lockouts, now))
            end
        end
    end
    table.sort(rows, Plan.SortNames)
    return rows
end

local function JournalSource(journal)
    local id = journal.instanceID
    if not S.Finite(id) then return end
    local name = Plan.Text(EJ_GetInstanceInfo(id), 120)
    local difficulty = EJ_GetDifficulty()
    return name, S.Finite(difficulty) and difficulty or nil
end

local function JournalEntry(info, index, instance, difficulty)
    if not S.Public(info) or type(info) ~= "table" then return end
    local entry = Loot.New(info.link)
    if not entry then return end
    local encounter = info.encounterID
    local count = EJ_GetNumEncountersForLootByIndex(index)
    local boss = S.Finite(encounter) and S.Finite(count) and count == 1 and Plan.Text(EJ_GetEncounterInfo(encounter), 120)
    local mode = difficulty and Plan.Text(GetDifficultyInfo(difficulty), 80)
    entry.source = instance
    if boss then entry.source = S.Text("%s — %s"):format(entry.source, boss) end
    if mode then entry.source = S.Text("%s — %s"):format(entry.source, mode) end
    entry.instance, entry.difficulty = instance, difficulty
    return entry
end

-- Only the visible instance/encounter Loot page owns these index-based reads.
-- Do not select an instance, encounter, difficulty or filter here.
function Loot.JournalRows()
    if not Plan.CanEdit() or NS.Client.isForever then return end
    local journal = EncounterJournal
    if not journal or not journal.LootContainer then return end
    local visible = journal.LootContainer:IsVisible()
    if not S.Public(visible) or visible ~= true then return end
    local instance, difficulty = JournalSource(journal)
    local count = instance and EJ_GetNumLoot()
    if not S.Finite(count) then return end
    local rows, seen = {}, {}
    for index = 1, math.min(count, 250) do
        local entry = JournalEntry(C_EncounterJournal.GetLootInfoByIndex(index), index, instance, difficulty)
        if entry and not seen[entry.id] then
            seen[entry.id] = true
            rows[#rows + 1] = Row(entry)
        end
    end
    return rows
end

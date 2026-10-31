local _, P = ...
local NS, S, Plan = P.NS, P.Suite, P.PlanningTools
local Matrix = { COLUMNS = 6, ROWS = 10, MAX_LOCKOUT_ROWS = 2048 }
Plan.Matrix = Matrix
-- One row per thing a character can have done; one column per character.
-- Weekly values read the snapshot's freshness: from this reset they are
-- shown, from an earlier known reset the character did nothing this week,
-- and without a known reset they stay "?".
local mapNames = {}

function Matrix.LockKey(lockout)
    return tostring(lockout.difficulty) .. "\031" .. lockout.name
end

-- Only a real name is cached; the map data can still be loading.
function Matrix.MapName(id)
    if mapNames[id] == nil then mapNames[id] = Plan.Text(C_ChallengeMode.GetMapUIInfo(id), 80) end
    return mapNames[id] or S.Text("Mythic+ dungeon")
end

function Matrix.GoldText(money)
    return BreakUpLargeNumbers(math.floor(money / 10000)) .. GOLD_AMOUNT_SYMBOL
end

local function Add(model, row)
    model.rows[#model.rows + 1] = row
end

-- key names the section for its saved folded state.
local function Section(model, label, key)
    Add(model, { kind = "section", label = label, key = key })
end

local function CharacterRows(model)
    Section(model, S.Text("Character"), "character")
    Add(model, { kind = "field", field = "level", label = S.Text("Level") })
    Add(model, { kind = "field", field = "ilvl", label = S.Text("Item level") })
    Add(model, { kind = "field", field = "money", label = S.Text("Gold") })
    Add(model, { kind = "summary", field = "seen", label = S.Text("Last seen") })
end

-- Dungeon rows are the season's maps any character has a record for.
local function MythicRows(model)
    if NS.Client.isForever then return end
    Section(model, S.Text("Mythic+"), "mythic")
    Add(model, { kind = "field", field = "rating", label = S.Text("Mythic+ rating"), season = model.season })
    Add(model, { kind = "summary", field = "key", label = S.Text("Keystone") })
    Add(model, { kind = "runs", label = S.Text("Runs this week") })
    local maps, known = {}, {}
    for _, character in ipairs(model.columns) do
        if model.season and character.snapshot.season == model.season then
            for _, best in ipairs(character.snapshot.dungeons or {}) do
                if S.Finite(best.id) and not known[best.id] then
                    known[best.id] = true
                    maps[#maps + 1] = { kind = "dungeon", map = best.id, label = Matrix.MapName(best.id), season = model.season }
                end
            end
        end
    end
    table.sort(maps, Plan.SortNames)
    for _, row in ipairs(maps) do Add(model, row) end
end

local function VaultRows(model)
    if NS.Client.isForever then return end
    Section(model, S.Text("Great Vault"), "vault")
    local kinds = Enum.WeeklyRewardChestThresholdType
    local order, known = { kinds.Activities, kinds.Raid, kinds.World }, {}
    for _, kind in ipairs(order) do known[kind] = true end
    for _, character in ipairs(model.columns) do
        for _, row in ipairs(character.snapshot.vault or {}) do
            if not known[row.kind] then
                known[row.kind] = true
                order[#order + 1] = row.kind
            end
        end
    end
    for _, kind in ipairs(order) do
        Add(model, { kind = "vault", rewardType = kind, slot = 0, label = Plan.Weekly.KindLabel(kind) })
    end
    Add(model, { kind = "summary", field = "reward", label = S.Text("Weekly reward available") })
end

local function Collect(model, now)
    local known, raids, dungeons = {}, {}, {}
    for _, character in ipairs(model.columns) do
        for _, lockout in ipairs(character.snapshot.lockouts or {}) do
            if S.Finite(lockout.expires) and lockout.expires > now then
                model.nextExpiry = math.min(model.nextExpiry or lockout.expires, lockout.expires)
                local key = Matrix.LockKey(lockout)
                if not known[key] then
                    if #raids + #dungeons < Matrix.MAX_LOCKOUT_ROWS then
                        known[key] = true
                        local list = lockout.raid and raids or dungeons
                        list[#list + 1] = { kind = "lockout", lockKey = key,
                            name = lockout.name,
                            difficulty = lockout.difficultyName or Plan.Text(GetDifficultyInfo(lockout.difficulty), 80)
                                or S.Text("Difficulty %d"):format(lockout.difficulty) }
                        local row = list[#list]
                        row.label = S.Text("%s (%s)"):format(row.name, row.difficulty)
                    else
                        model.truncated = true
                    end
                end
            end
        end
    end
    return raids, dungeons
end

local function LockoutRows(model, now)
    local raids, dungeons = Collect(model, now)
    for _, group in ipairs({ { raids, S.Text("Raid lockouts"), "raids" }, { dungeons, S.Text("Dungeon lockouts"), "dungeons" } }) do
        table.sort(group[1], Plan.SortNames)
        if #group[1] > 0 then Section(model, group[2], group[3]) end
        for _, row in ipairs(group[1]) do Add(model, row) end
    end
end

local function WorldBossRows(model, now)
    local rows, known = {}, {}
    for _, character in ipairs(model.columns) do
        for _, boss in ipairs(character.snapshot.worldBosses or {}) do
            if S.Finite(boss.expires) and boss.expires > now and not known[boss.name] then
                known[boss.name] = true
                model.nextExpiry = math.min(model.nextExpiry or boss.expires, boss.expires)
                rows[#rows + 1] = { kind = "worldboss", boss = boss.name, label = boss.name }
            end
        end
    end
    table.sort(rows, Plan.SortNames)
    if #rows > 0 then Section(model, S.Text("World bosses"), "worldbosses") end
    for _, row in ipairs(rows) do Add(model, row) end
end

function Matrix.Build(characters, now, reset)
    reset = reset or Plan.Weekly.Reset()
    local season = not NS.Client.isForever and C_MythicPlus.GetCurrentSeason() or nil
    local model = { columns = characters, rows = {}, truncated = false, season = S.Finite(season) and season or nil }
    for _, character in ipairs(characters) do
        character.matrixLockouts = nil
        if character.checked then
            character.week, character.lastWeek = "fresh", false
        else
            character.week, character.lastWeek = Plan.Weekly.Freshness(character.snapshot, reset)
        end
    end
    CharacterRows(model)
    MythicRows(model)
    VaultRows(model)
    LockoutRows(model, now)
    WorldBossRows(model, now)
    return model
end

local function Lockout(character, key)
    if not character.matrixLockouts then
        character.matrixLockouts = {}
        for _, lockout in ipairs(character.snapshot.lockouts or {}) do
            character.matrixLockouts[Matrix.LockKey(lockout)] = lockout
        end
    end
    return character.matrixLockouts[key]
end

Matrix.FindLockout = Lockout

local DONE_ICON = "|TInterface\\RaidFrame\\ReadyCheck-Ready:12:12|t"
local difficultyLabels

-- Short reward labels as the vault names them: keystone level, raid
-- difficulty (Blizzard's DifficultyUtil IDs) and world tier.
local function RaidLabel(level)
    if not difficultyLabels then
        local ids = DifficultyUtil.ID
        difficultyLabels = {}
        for key, label in pairs({ PrimaryRaidLFR = "LFR", PrimaryRaidNormal = "N", PrimaryRaidHeroic = "H", PrimaryRaidMythic = "M" }) do
            if ids[key] then difficultyLabels[ids[key]] = label end
        end
    end
    return difficultyLabels[level] or tostring(level)
end

function Matrix.SlotLabel(row)
    if not S.Finite(row.level) then return DONE_ICON end
    local kinds = Enum.WeeklyRewardChestThresholdType
    if row.kind == kinds.Raid then return RaidLabel(row.level) end
    if row.kind == kinds.World then return "T" .. row.level end
    if row.kind == kinds.Activities then return row.level > 0 and "+" .. row.level or "H" end
    return tostring(row.level)
end

local function Fraction(progress, threshold)
    return S.Text("%d / %d"):format(math.min(progress, threshold), threshold)
end

-- Unlocked slots show their reward level, the next slot its progress.
local function Vault(activity, character)
    local entry, week = character.snapshot, character.week
    if not week or week == "fresh" and entry.vault == nil then return "?", "muted" end
    local labels, slots, nextRow = {}, 0
    for _, row in ipairs(entry.vault or {}) do
        if row.kind == activity.rewardType and S.Finite(row.threshold) and row.threshold > 0 and S.Finite(row.progress) then
            local progress = week == "fresh" and row.progress or 0
            if activity.slot ~= 0 and row.index == activity.slot then
                return Fraction(progress, row.threshold), progress >= row.threshold and "ok" or week == "past" and "muted" or "text"
            end
            slots = slots + 1
            if progress >= row.threshold then
                labels[#labels + 1] = Matrix.SlotLabel(row)
            elseif not nextRow or row.threshold < nextRow.threshold then
                nextRow = row
            end
        end
    end
    if slots == 0 or activity.slot ~= 0 then return "—", "muted" end
    if not nextRow then return table.concat(labels, " "), "ok" end
    local progress = Fraction(week == "fresh" and nextRow.progress or 0, nextRow.threshold)
    if #labels == 0 then return progress, week == "past" and "muted" or "text" end
    return S.Text("%s (%s)"):format(table.concat(labels, " "), progress), "text"
end

local function Field(activity, character)
    local entry, field = character.snapshot, activity.field
    if field == "level" then return S.Finite(entry.level) and tostring(entry.level) or "?", S.Finite(entry.level) and "text" or "muted" end
    if field == "ilvl" then return S.Finite(entry.ilvl) and string.format("%.1f", entry.ilvl) or "?", S.Finite(entry.ilvl) and "text" or "muted" end
    if field == "money" then return S.Finite(entry.money) and Matrix.GoldText(entry.money) or "?", S.Finite(entry.money) and "text" or "muted" end
    if not activity.season or entry.season ~= activity.season or not S.Finite(entry.rating) then return "?", "muted" end
    local text = tostring(math.floor(entry.rating + .5))
    if entry.rating <= 0 then return text, "muted" end
    local color = C_ChallengeMode.GetDungeonScoreRarityColor(entry.rating)
    return color and color:WrapTextInColorCode(text) or text, "text"
end

local function Summary(activity, character)
    local entry, fresh = character.snapshot, character.week == "fresh"
    if activity.field == "seen" then return Plan.Date(entry.at), "muted" end
    if activity.field == "key" then
        if not fresh or entry.keyPending then return "?", "muted" end
        return entry.key and S.Text("%s (%s)"):format(entry.key.name, S.Text("+%d"):format(entry.key.level))
            or "—", entry.key and "text" or "muted"
    end
    local ready = Plan.Overview.RewardReady(entry, character.week, character.lastWeek)
    if ready == nil then return "?", "muted" end
    return ready and S.Text("Ready") or "—", ready and "ok" or "muted"
end

local function Runs(character)
    local entry, week = character.snapshot, character.week
    if week == "past" then return "0", "muted" end
    if week ~= "fresh" or type(entry.runs) ~= "table" then return "?", "muted" end
    if #entry.runs == 0 then return "0", "muted" end
    return string.format("%d (+%d)", entry.runCount or #entry.runs, entry.runHighest or entry.runs[1].level), "text"
end

-- Season bests stay valid between resets; a timed best is green.
local function Dungeon(activity, character)
    local entry = character.snapshot
    if not activity.season or entry.season ~= activity.season or type(entry.dungeons) ~= "table" then return "?", "muted" end
    for _, best in ipairs(entry.dungeons) do
        if best.id == activity.map then
            if not S.Finite(best.level) or best.level <= 0 then return "—", "muted" end
            return "+" .. best.level, best.timed and "ok" or "text"
        end
    end
    return "—", "muted"
end

-- Lockouts carry their own expiry, so an old snapshot still answers.
local function LockoutValue(activity, character, now)
    local entry = character.snapshot
    if entry.lockouts == nil or entry.lockoutsPending then return "?", "muted" end
    local lockout = Lockout(character, activity.lockKey)
    if not lockout or lockout.expires <= now then return "—", "muted" end
    if S.Finite(lockout.bosses) and lockout.bosses > 0 and S.Finite(lockout.defeated) then
        return S.Text("%d / %d"):format(lockout.defeated, lockout.bosses), lockout.defeated >= lockout.bosses and "ok" or "text"
    end
    return S.Text("Saved"), "text"
end

local function WorldBoss(activity, character, now)
    local bosses = character.snapshot.worldBosses
    if type(bosses) ~= "table" then return "?", "muted" end
    for _, boss in ipairs(bosses) do
        if boss.name == activity.boss and S.Finite(boss.expires) and boss.expires > now then return S.Text("Saved"), "ok" end
    end
    return "—", "muted"
end

function Matrix.Value(activity, character, now)
    local kind = activity.kind
    if kind == "section" then return "", "text" end
    if kind == "field" then return Field(activity, character) end
    if kind == "summary" then return Summary(activity, character) end
    if kind == "vault" then return Vault(activity, character) end
    if kind == "runs" then return Runs(character) end
    if kind == "dungeon" then return Dungeon(activity, character) end
    if kind == "lockout" then return LockoutValue(activity, character, now) end
    if kind == "worldboss" then return WorldBoss(activity, character, now) end
    return "?", "muted"
end

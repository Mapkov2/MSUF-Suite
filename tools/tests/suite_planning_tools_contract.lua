local root = arg[1] or "."
local checks = 0
local function equal(actual, expected, label)
    checks = checks + 1
    assert(actual == expected, label .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual))
end
local secret = setmetatable({}, { __tostring = function() error("secret string") end })
local function Fixture()
    local state = { combat = false, time = 1000, guid = "player-a", name = "Alice", realm = "Realm", reset = 900, region = "EU",
        instance = 100, kind = "party", roles = { false, false, true }, roleWrites = 0, requests = 0, notifications = 0,
        characters = {}, config = {}, equipment = 1, build = 7, loot = 8 }
    local NS = { RootDB = {}, DB = {}, Client = { isForever = false } }
    NS.InCombat = function() return state.combat end
    local S = { instances = {} }
    S.Public = function(v) return v ~= secret end
    S.PublicText = function(v) if v ~= secret and type(v) == "string" and v ~= "" then return v end end
    S.Finite = function(v) return v ~= secret and type(v) == "number" and v == v and v > -math.huge and v < math.huge end
    S.Text = function(v) return v end
    S.Print = function(v) state.printed = v end
    S.ClockText = function(v) return tostring(v) end
    S.CharacterData = function(key)
        state.characters[state.guid] = state.characters[state.guid] or {}
        local data = state.characters[state.guid]
        data[key] = data[key] or {}
        return data[key]
    end
    S.Config = function(key) return state.config[key] or {} end
    S.SetMany = function(key, values)
        if state.combat then return false end
        local c = S.Config(key)
        for k, v in pairs(values) do c[k] = v end
        state.config[key] = c
        return true
    end
    S.Notifications = { Push = function() state.notifications = state.notifications + 1 end }
    S.ToolListWindow = { Refresh = function() end, RefreshFonts = function() end, Close = function() state.closed = true end,
        IsEditing = function() return false end,
        Open = function(_, spec) state.window = spec return {} end,
        Edit = function(_, spec) state.editor = spec end }
    S.LoadoutSnapshot = function() return state.build, "Build", state.loot, "Loot" end
    S.ReadInfoSource = function() return .75 end
    S.PlanningReadiness = function() return {} end
    S.Raid = { AttemptProgress = function() end }
    S.Open = function(id) state.opened = id end
    S.InstanceKind = function() return state.kind end
    S.ContextMenu = function(_, callback)
        state.menu = {}
        callback(nil, { CreateTitle = function() end,
            CreateButton = function(_, _, action) state.menu[#state.menu + 1] = action end })
    end
    S.Install = function(id, m) S.instances[id] = m end
    _G.GetServerTime = function() return state.time end
    _G.GetTime = function() return state.time end
    _G.UnitGUID = function() return state.guid end
    _G.UnitName = function() return state.name end
    _G.UnitClass = function() return "Warrior", "WARRIOR" end
    _G.GetRealmName = function() return state.realm end
    _G.GetCurrentRegionName = function() return state.region end
    _G.GetInstanceInfo = function() return "Dungeon", state.kind, 8, nil, nil, nil, nil, state.instance end
    _G.GetNumSavedInstances = function() return state.lockoutCount or 1 end
    _G.GetDifficultyInfo = function(id) return "Difficulty " .. id end
    _G.GetSavedInstanceInfo = function() return "Raid", 1, 3600, 16, true, false, 0, true, 20, nil, state.bosses, state.defeated end
    _G.GetSavedInstanceEncounterInfo = function(_, index) return "Boss " .. index, nil, index <= (state.defeated or 0) end
    _G.GetNumSavedWorldBosses = function() return 1 end
    _G.GetSavedWorldBossInfo = function() return "World Boss", 1, 7200 end
    _G.UnitLevel = function() return 80 end
    _G.GetAverageItemLevel = function() return 715, 712.44 end
    _G.GetMoney = function() return state.money or 1234567 end
    _G.GetRealZoneText = function() return "Dornogal" end
    _G.BreakUpLargeNumbers = function(value) return tostring(value) end
    _G.GOLD_AMOUNT_SYMBOL = "g"
    _G.RequestRaidInfo = function() state.requests = state.requests + 1 end
    _G.GetLFGRoles = function() return false, unpack(state.roles) end
    _G.SetLFGRoles = function(_, tank, healer, damage) state.roles = { tank, healer, damage } state.roleWrites = state.roleWrites + 1 end
    _G.UnitGetAvailableRoles = function() return false, true, true end
    _G.date = os.date
    _G.C_DateAndTime = { GetWeeklyResetStartTime = function() return state.reset end }
    _G.Enum = { WeeklyRewardChestThresholdType = { Raid = 1, Activities = 2, World = 3 } }
    _G.DifficultyUtil = { ID = { PrimaryRaidLFR = 17, PrimaryRaidNormal = 14,
        PrimaryRaidHeroic = 15, PrimaryRaidMythic = 16 } }
    _G.C_WeeklyRewards = { GetActivities = function() return state.activities or { { type = 2, index = 1, progress = 2, threshold = 4 } } end,
        HasAvailableRewards = function() return state.reward or false end }
    _G.C_LFGList = { GetOwnedKeystoneActivityAndGroupAndLevel = function() return 1, 1, 10 end,
        GetActivityInfoTable = function() return { fullName = "Dungeon" } end,
        ApplyToGroup = function() error("protected application") end, AcceptInvite = function() error("protected invitation") end }
    _G.C_EquipmentSet = { GetEquipmentSetIDs = function() return { 1, 2 } end,
        GetEquipmentSetInfo = function(id) return "Set " .. id, nil, id, id == state.equipment end }
    _G.C_MythicPlus = { GetSeasonBestForMap = function() return state.best, state.overtime end,
        GetCurrentSeason = function() return 15 end, RequestMapInfo = function() state.mapRequests = (state.mapRequests or 0) + 1 end,
        GetRunHistory = function() return state.runs or {} end }
    _G.C_ChallengeMode = { GetMapTable = function() return { 1 } end, GetMapUIInfo = function() return "Dungeon" end,
        GetOverallDungeonScore = function() return 2450 end, GetDungeonScoreRarityColor = function() return nil end }
    local P = { NS = NS, Suite = S, GroupFinderFilters = { Eligible = function() return state.eligible end,
        Apply = function() state.applied = true return true end } }
    local names = { "PlanningTools", "PlanningHistory", "PlanningWeekly", "PlanningLoadouts", "PlanningNotes", "PlanningLFG",
        "PlanningWindow", "PlanningWindowHistory", "PlanningWindowActions", "PlanningController" }
    for _, name in ipairs(names) do
        assert(loadfile(root .. "/MSUF_Suite_AdventurePlanner/" .. name .. ".lua"))("test", P)
        if name == "PlanningTools" then
            P.PlanningTools.Board = { Open = S.ToolListWindow.Open,
                Refresh = S.ToolListWindow.Refresh, Restyle = function() end, Close = S.ToolListWindow.Close }
        end
    end
    local Plan, owner = P.PlanningTools, S.instances.planningTools
    owner.active = true
    owner.config = { weekly = true, raidHistory = true, keepAttempts = 20, loadouts = true, entryNotes = true, preparation = true }
    owner.context = { callbacks = {}, Event = function(self, event, callback) self.callbacks[event] = callback end,
        RemoveEvent = function(self, event) self.callbacks[event] = nil end,
        After = function(self, delay, callback)
            state.scheduled = (state.scheduled or 0) + 1
            state.pending = callback
        end,
        Cancel = function() state.pending = nil end }
    function state.Event(event, ...)
        if event == "PLAYER_REGEN_DISABLED" then state.combat = true
        elseif event == "PLAYER_REGEN_ENABLED" then state.combat = false end
        local callback = owner.context.callbacks[event]
        if callback then callback(owner, event, ...) return true end
        return false
    end
    function state.Flush()
        local callback = state.pending
        state.pending = nil
        if callback then callback(owner) return true end
        return false
    end
    Plan.owner = owner
    return state, NS, S, Plan, owner, P
end

if arg[2] == "--fixture" then return Fixture end

local function WeeklyChecks()
    local st, NS, S, Plan, owner = Fixture()
    equal(Plan.Weekly.Capture(), true, "weekly capture")
    local row = Plan.Weekly.Rows()[1]
    equal(row.checked, true, "same reset fresh")
    equal(row.detail:find("waiting for the server", 1, true) ~= nil, true, "lockout pending honest")
    Plan.Weekly.lockoutsReady = true
    Plan.Weekly.Capture()
    equal(Plan.Weekly.Rows()[1].detail:find("Raid (difficulty 16)", 1, true) ~= nil, true, "lockout captured")
    local known = NS.RootDB.suitePlanning.characters[st.guid].lockouts[1]
    Plan.Weekly.Request()
    Plan.Weekly.Capture()
    local pending = NS.RootDB.suitePlanning.characters[st.guid].lockouts
    equal(pending and pending[1] and pending[1].name, known.name, "pending request preserves known lockout")
    equal(pending and pending[1] and pending[1].expires, known.expires, "pending request preserves lockout expiry")
    st.lockoutCount, Plan.Weekly.lockoutsReady = 0, true
    Plan.Weekly.Capture()
    equal(#NS.RootDB.suitePlanning.characters[st.guid].lockouts, 0, "authoritative empty reply clears old lockouts")
    st.lockoutCount = nil
    st.reset = 1900
    equal(Plan.Weekly.Rows()[1].checked, false, "new reset stale")
    st.activities = secret
    Plan.Weekly.Capture()
    equal(NS.RootDB.suitePlanning.characters[st.guid].vault, nil, "secret vault unavailable")
    st.activities = { { type = 1, index = 1, progress = secret, threshold = 1 } }
    Plan.Weekly.Capture()
    equal(#NS.RootDB.suitePlanning.characters[st.guid].vault, 0, "secret progress skipped")
    for i = 1, 205 do st.guid = "p" .. i st.time = st.time + 1 Plan.Weekly.Capture() end
    equal(#Plan.Weekly.Rows(), 200, "all-character snapshot bound")
    st.combat = true
    equal(Plan.Weekly.Capture(), false, "combat snapshot blocked")
    st.combat = false owner.active = false
    equal(Plan.Weekly.Capture(), false, "disabled snapshot blocked")
    owner.active = true NS.Client.isForever = true st.activities = secret
    Plan.Weekly.Capture()
    equal(NS.RootDB.suitePlanning.characters[st.guid].vault, nil, "Forever has no vault")
end

-- A snapshot keeps the reset of the region it was taken in, and regions reset
-- their week at different times: another region's characters are not judged
-- (and marked "past") against this region's reset.
local function RegionChecks()
    local st, NS, S, Plan = Fixture()
    equal(Plan.Weekly.Capture(), true, "weekly capture")
    local characters = NS.RootDB.suitePlanning.characters
    equal(characters[st.guid].region, "EU", "snapshot records its region")
    characters["us-guid"] = { name = "Bob - Realm", at = st.time, reset = st.reset - 3600, region = "US" }
    characters["old-guid"] = { name = "Old - Realm", at = st.time, reset = st.reset }
    local labels = {}
    for _, row in ipairs(Plan.Weekly.Rows()) do labels[row.label] = row.checked end
    equal(labels["Bob - Realm"], nil, "another region's character stays out of the list")
    equal(labels["Alice - Realm"], true, "this region's character is listed")
    equal(labels["Old - Realm"], true, "a snapshot from before regions were recorded stays listed")
end

local function SnapshotChecks()
    local st, NS, S, Plan = Fixture()
    equal(Plan.Weekly.Capture(), true, "weekly capture")
    local entry = NS.RootDB.suitePlanning.characters[st.guid]
    equal(entry.level, 80, "character level captured")
    equal(entry.ilvl, 712.4, "equipped item level rounded to a tenth")
    equal(entry.money, 1234567, "gold captured")
    equal(entry.zone, "Dornogal", "location captured")
    equal(entry.dungeons, nil, "season bests wait for the Mythic+ map data")
    equal(entry.worldBosses, nil, "world bosses wait for the raid info reply")
    st.best, st.overtime = { level = 10, dungeonScore = 200 }, { level = 12, dungeonScore = 210 }
    st.runs = { { mapChallengeModeID = 1, level = 9, completed = true }, { mapChallengeModeID = 1, level = 14, completed = false },
        secret, { mapChallengeModeID = secret, level = 3 } }
    Plan.Weekly.seasonReady = true
    Plan.Weekly.Capture()
    entry = NS.RootDB.suitePlanning.characters[st.guid]
    equal(entry.season, 15, "season recorded with its bests")
    equal(entry.rating, 2450, "rating captured")
    equal(entry.dungeons[1].level, 12, "the better-scored season best wins")
    equal(entry.dungeons[1].timed, false, "an overtime best is marked")
    equal(#entry.runs, 2, "this week's readable runs captured, secrets skipped")
    equal(entry.runs[1].level, 14, "runs sorted highest first")
    Plan.Weekly.Request()
    Plan.Weekly.Capture()
    equal(NS.RootDB.suitePlanning.characters[st.guid].dungeons[1].level, 12, "a pending map request keeps known bests")
    equal(st.mapRequests, 1, "the refresh asks for Mythic+ map data")
    st.money = secret
    Plan.Weekly.Vitals()
    equal(NS.RootDB.suitePlanning.characters[st.guid].money, 1234567, "unreadable gold keeps the last value")
    st.money = 99
    equal(Plan.Weekly.Vitals(), true, "vitals refresh the current snapshot")
    equal(NS.RootDB.suitePlanning.characters[st.guid].money, 99, "vitals update gold")
    st.money = nil
    st.bosses, st.defeated = 3, 2
    Plan.Weekly.lockoutsReady = true
    Plan.Weekly.Capture()
    entry = NS.RootDB.suitePlanning.characters[st.guid]
    equal(#entry.worldBosses, 1, "world bosses captured")
    equal(#entry.lockouts[1].encounters, 3, "every boss of a lockout captured")
    equal(entry.lockouts[1].encounters[3].killed, false, "alive bosses stay marked")
end

local function KeystoneChecks()
    local st, NS, S, Plan, owner = Fixture()
    Plan.Weekly.Capture()
    local entry = NS.RootDB.suitePlanning.characters[st.guid]
    owner:Enable()
    st.Flush()
    entry = NS.RootDB.suitePlanning.characters[st.guid]
    local currentLevel, timewalking = 14, false
    C_LFGList.GetOwnedKeystoneActivityAndGroupAndLevel = function(alternate)
        if timewalking and not alternate then return nil end
        return 7, 1, currentLevel
    end
    C_LFGList.GetActivityInfoTable = function() return { fullName = "Another dungeon" } end
    local vault = entry.vault
    C_WeeklyRewards.GetActivities = function() error("key-only refresh must not reread vault") end
    owner.context.callbacks.BAG_UPDATE_DELAYED(owner, "BAG_UPDATE_DELAYED")
    st.Flush()
    entry = NS.RootDB.suitePlanning.characters[st.guid]
    equal(entry.key.name, "Another dungeon", "bag change refreshes owned key name")
    equal(entry.key.level, 14, "bag change refreshes owned key level")
    equal(entry.vault, vault, "bag refresh preserves weekly snapshot")
    local stable, before = entry.key, Plan.generation
    owner.context.callbacks.BAG_UPDATE_DELAYED(owner, "BAG_UPDATE_DELAYED")
    st.Flush()
    equal(entry.key, stable, "unchanged bag event keeps key table")
    equal(Plan.generation, before, "unchanged bag event does not invalidate planner")
    local info = C_LFGList.GetActivityInfoTable
    C_LFGList.GetActivityInfoTable = function() return nil end
    owner.context.callbacks.BAG_UPDATE_DELAYED(owner, "BAG_UPDATE_DELAYED")
    st.Flush()
    equal(entry.key, stable, "pending activity name preserves saved key")
    equal(entry.keyPending, true, "pending name is marked unknown rather than authoritative")
    C_LFGList.GetActivityInfoTable = info
    timewalking, currentLevel = true, 9
    owner.context.callbacks.BAG_UPDATE_DELAYED(owner, "BAG_UPDATE_DELAYED")
    st.Flush()
    equal(entry.key.level, 9, "timewalking key is captured")
    equal(entry.keyPending, nil, "readable key clears pending state")
    C_LFGList.GetOwnedKeystoneActivityAndGroupAndLevel = function() return nil end
    owner.context.callbacks.BAG_UPDATE_DELAYED(owner, "BAG_UPDATE_DELAYED")
    st.Flush()
    equal(entry.key, nil, "a removed key clears the character key")
    st.combat = true
    equal(Plan.Weekly.UpdateKeystone(), false, "combat key writes refused")
end

local function LoadoutChecks()
    local st, NS, S, Plan, owner = Fixture()
    equal(Plan.Loadouts.Save(), true, "context loadout saved")
    Plan.Loadouts.Check()
    equal(st.notifications, 0, "matching loadout silent")
    st.build = 9
    Plan.Loadouts.Check() Plan.Loadouts.Check()
    equal(st.notifications, 1, "mismatch deduplicated")
    st.build = 7 Plan.Loadouts.Check() st.equipment = 2 Plan.Loadouts.Check()
    equal(st.notifications, 2, "equipment mismatch")
    st.instance = 200 Plan.Loadouts.Check()
    equal(st.notifications, 2, "another instance no expectation")
    st.guid = "other"
    equal(#Plan.Loadouts.Rows(), 0, "character loadouts isolated")
    st.combat = true
    equal(Plan.Loadouts.Save(), false, "combat save blocked")
    st.combat = false owner.active = false
    equal(Plan.Loadouts.Save(), false, "disabled save blocked")
    owner.active = true NS.Client.isForever = true
    equal(Plan.Loadouts.Current(), nil, "Forever no retail talents")
end

local function HistoryChecks()
    local st, NS, S, Plan, owner = Fixture()
    S.CharacterData("runSummary").history = {
        { historyID = 2, subtitle = "Dungeon +12", level = 12, mapID = 1, time = 110, deaths = 3,
            recordedAt = 2, onTime = true, splits = { [3] = 100 } },
        { historyID = 1, subtitle = "Dungeon +10", level = 10, mapID = 1, time = 100, deaths = 1,
            recordedAt = 1, onTime = true, splits = { [3] = 80 } },
    }
    equal(#Plan.History.Runs("", 11), 1, "minimum level filter")
    equal(Plan.History.Runs("", 0, "time")[1].key, "1", "time sort")
    equal(#Plan.History.Runs("notfound"), 0, "text filter")
    equal(Plan.History.SaveRunNote("2", "Personal note"), true, "run note")
    equal(Plan.History.SaveRunNote("2", ""), true, "clear run note")
    equal(Plan.History.SaveRunNote("gone", "bad"), false, "orphan note rejected")
    local runs = Plan.History.Runs("")
    equal(Plan.History.Compare(runs[1].run, runs[2].run):find("Split 3: +20.0 s", 1, true) ~= nil, true, "pair splits")
    for i = 1, 25 do Plan.History.Attempt(1, "Boss", 16, 0, i, { remaining = 10 }) end
    equal(#Plan.History.Attempts(""), 20, "attempt bound")
    equal(Plan.History.Attempts("")[1].attempt.duration, 25, "chronology latest first")
    Plan.History.Attempt(secret, "Bad", 16, 0, 20)
    equal(#Plan.History.Attempts(""), 20, "secret outcome rejected")
    owner.active = false Plan.History.Attempt(1, "Disabled", 16, 0, 50)
    equal(Plan.History.Attempts("")[1].label, "Boss", "disabled history silent")
    owner.active = true
    equal(Plan.History.SaveGoal(1, "Dungeon", 15), true, "goal saved")
    equal(Plan.History.Goals("")[1].checked, false, "local best below goal")
    st.best = { level = 16 }
    equal(Plan.History.Goals("")[1].checked, true, "native timed best")
    equal(Plan.History.SaveGoal(1, "Dungeon", 2.5), false, "fractional goal rejected")
end

-- A run saved without a time must not make the "time" sort circular: timed
-- runs come first by time, the rest follow, and the order never depends on
-- the order the archive lists them in.
local function HistoryOrderChecks()
    local st, NS, S, Plan = Fixture()
    local function Run(id, recordedAt, time)
        return { historyID = id, subtitle = "Run " .. id, level = 10, mapID = 1, time = time, deaths = 0, recordedAt = recordedAt }
    end
    local a, b, c = Run(1, 1, 100), Run(2, 5, nil), Run(3, 9, 200)
    local function Order(sort, ...)
        S.CharacterData("runSummary").history = { ... }
        local keys = {}
        for _, row in ipairs(Plan.History.Runs("", 0, sort)) do keys[#keys + 1] = row.key end
        return table.concat(keys, ",")
    end
    equal(Order("time", a, b, c), "1,3,2", "timed runs first by time, the untimed run last")
    equal(Order("time", c, b, a), "1,3,2", "time order ignores the archive order")
    equal(Order("time", b, a, c), "1,3,2", "time order ignores the archive order again")
    equal(Order("date", a, b, c), "3,2,1", "date sort is newest first")
    equal(Order("level", a, b, c), "3,2,1", "equal levels fall back to newest first")
    local same = Run(4, 9, 200)
    equal(Order("time", c, same), "4,3", "equal runs keep a fixed order by id")
    equal(Order("time", same, c), "4,3", "equal runs keep a fixed order by id in any archive order")
end

local function WorkspaceChecks()
    local st, NS, S, Plan, owner = Fixture()
    st.config.groupFinderTools = { difficulty = 5, minimumRating = 2000, activities = "1,2", needsRole = true, hasTank = true, hasHealer = false }
    st.config.groupFinderDoubleClick = { note = "Hello" }
    S.instances.groupFinderTools = { active = true, config = { filters = true },
        CanApplyFilters = function() return st.eligible end, ApplyFilters = function() st.applied = true return true end }
    equal(Plan.LFG.Save("Push"), true, "workspace save")
    equal(Plan.LFG.Save("Push"), false, "duplicate name rejected")
    equal(Plan.LFG.Apply("Push"), false, "inactive native search rejects")
    equal(st.roleWrites, 0, "no side effects before eligibility")
    st.eligible = true
    equal(Plan.LFG.Apply("Push"), true, "explicit apply")
    equal(st.roleWrites, 1, "one manual role update")
    equal(st.applied, true, "existing filter engine used")
    st.combat = true
    equal(Plan.LFG.Apply("Push"), false, "combat apply denied")
    equal(st.roleWrites, 1, "no combat native writes")
    st.combat = false NS.Client.isForever = true
    equal(Plan.LFG.Save("Forever"), false, "Forever workspace disabled")
end

local function NotesAndWindowChecks()
    local st, NS, S, Plan, owner = Fixture()
    equal(Plan.Notes.Save("100", "Dungeon", "[ ] Flask\n[x] Food\nStrategy", 100), true, "note saved")
    equal(Plan.Notes.Toggle("100", 1), true, "manual task tick")
    equal(Plan.Notes.Rows()[1].note.text, "[x] Flask\n[x] Food\nStrategy", "line preservation")
    equal(Plan.Notes.Toggle("100", 3), false, "plain note not toggled")
    local searchable = Plan.Notes.Rows()[1].search:lower()
    equal(searchable:find("dungeon", 1, true) ~= nil, true, "the note title is searchable")
    equal(searchable:find("flask", 1, true) ~= nil, true, "the note text is searchable")
    Plan.Notes.Entry() Plan.Notes.Entry()
    equal(st.notifications, 1, "entry cue once")
    st.instance = 200
    equal(#Plan.Notes.Rows(true), 0, "context notes filter")
    equal(Plan.Window.Open("notes"), true, "normal window reachable")
    equal(#st.window.tabs, 7, "every visible tab reachable; Mythic+ goals stay hidden for now")
    st.window.selectTab(owner, "runs")
    equal(st.window.currentTab(), "runs", "tab change")
    equal(#st.window.actions, 5, "tab actions installed")
    st.combat = true
    equal(Plan.Notes.Toggle("100", 1), false, "combat checklist blocked")
    equal(Plan.Window.Open(), false, "combat window blocked")
    st.combat = false
    owner:Enable()
    equal(st.requests, 1, "single raid info request at enable")
    st.pending(owner)
    Plan.History.Attempt(9, "Saved boss", 16, 0, 30)
    local saved = Plan.History.Attempts("")[1].attempt
    equal(saved.duration, 30, "saved archive duration retained")
    equal(saved.remaining, nil, "no fabricated archive HP")
    equal(owner.context.callbacks.ENCOUNTER_START, nil, "planner registers no encounter-start work")
    equal(owner.context.callbacks.ENCOUNTER_END, nil, "planner registers no encounter-end work")
    st.Event("PLAYER_REGEN_DISABLED")
    st.Event("ENCOUNTER_START", 9, "Boss", 16)
    st.time = st.time + 30
    st.Event("ENCOUNTER_END", 9, "Boss", 16, 20, 0)
    st.Event("PLAYER_REGEN_ENABLED")
    st.Flush()
    equal(#Plan.History.Attempts(""), 1, "combat adds no automatic archive entry")
    equal(Plan.History.Attempts("")[1].attempt, saved, "legacy archive survives combat suspension")
    owner:Disable()
    equal(Plan.owner, nil, "owner released")
    equal(st.closed, true, "owned window closed")
end

-- A finished comparison replaces the details of the run it was made on until
-- the selection moves; it never outlives the window or the tab.
local function ComparisonChecks()
    local st, NS, S, Plan, owner = Fixture()
    S.CharacterData("runSummary").history = {
        { historyID = 2, subtitle = "Dungeon +12", level = 12, mapID = 1, time = 110, deaths = 3, recordedAt = 2 },
        { historyID = 1, subtitle = "Dungeon +10", level = 10, mapID = 1, time = 100, deaths = 1, recordedAt = 1 },
    }
    local compare = Plan.Window.RunActions()[1]
    local function Compare()
        local rows = st.window.rows()
        compare.run(owner, rows[1], { spec = st.window })
        compare.run(owner, rows[2], { spec = st.window })
        return rows[2].key
    end
    local function Shown(key)
        for _, row in ipairs(st.window.rows()) do
            if row.key == key then return row.detail:find("compared with", 1, true) ~= nil end
        end
    end
    equal(Plan.Window.Open("runs"), true, "runs tab opens")
    equal(type(st.window.onSelect), "function", "the window asks to hear selection changes")
    local key = Compare()
    equal(Shown(key), true, "the comparison fills the details of the compared run")
    st.window.onSelect(owner, { key = "other" })
    equal(Shown(key), false, "choosing another run clears the comparison")
    key = Compare()
    equal(Shown(key), true, "a new comparison shows")
    st.window.selectTab(owner, "notes")
    st.window.selectTab(owner, "runs")
    equal(Shown(key), false, "leaving the tab clears the comparison")
    key = Compare()
    equal(Plan.Window.Open("runs"), true, "reopened")
    equal(Shown(key), false, "a reopened planner starts without the old comparison")
end

local function StaleEditorChecks()
    local st, NS, S, Plan = Fixture()
    Plan.Notes.Save("100", "Dungeon", "Old", 100)
    Plan.Window.Remove("notes", Plan.Notes.Rows()[1])
    equal(st.editor.valid(), true, "current deletion permitted")
    Plan.Notes.Save("100", "Dungeon", "New", 100)
    equal(st.editor.valid(), false, "replacement prevents stale deletion")
    Plan.Window.Remove("notes", Plan.Notes.Rows()[1])
    Plan.Bucket("notes")["100"].text = "Changed checklist"
    equal(st.editor.valid(), false, "in-place edit prevents stale deletion")
    Plan.History.SaveGoal(1, "Dungeon", 10)
    Plan.Window.GoalActions()[2].run(nil, Plan.History.Goals("")[1])
    equal(st.editor.valid(), true, "current goal editor permitted")
    Plan.History.SaveGoal(1, "Dungeon", 15)
    equal(st.editor.valid(), false, "replacement prevents stale goal edit")
    Plan.Window.AddGoal(nil, nil, { actions = {} })
    local editor = st.editor
    NS.DB = {}
    st.menu[1]()
    equal(st.editor, editor, "old profile goal menu cannot open editor")
end

WeeklyChecks()
KeystoneChecks()
RegionChecks()
SnapshotChecks()
LoadoutChecks()
HistoryChecks()
HistoryOrderChecks()
WorkspaceChecks()
NotesAndWindowChecks()
ComparisonChecks()
StaleEditorChecks()
print("suite_planning_tools_contract: " .. checks .. " checks passed")

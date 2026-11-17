local root = assert(arg[1], "repository root required")
local function Noop() end
local function FontPath() return "font" end
local function Widget()
    return setmetatable({
        SetText = function(self, value) self.text = value end,
        GetWidth = function() return 300 end,
        CreateTexture = Widget,
        CreateFontString = Widget,
    }, { __index = function(_, key)
        if key:match("^Set") or key == "Hide" or key == "Show" or key == "ClearAllPoints" then return Noop end
    end })
end

local secret = setmetatable({}, {
    __lt = function() error("secret compared") end,
    __le = function() error("secret compared") end,
    __sub = function() error("secret subtracted") end,
    __div = function() error("secret divided") end,
})
local function Public(value) return value ~= secret end
local function Finite(value)
    return Public(value) and type(value) == "number" and value == value and math.abs(value) < math.huge
end

local elapsed, since, bossDone, completion, character, completionReads, criteriaReads
local S = {
    Public = Public, Finite = Finite, Text = function(value) return value end,
    PublicText = function(value) return type(value) == "string" and value or nil end,
    SetStyledFont = Noop, GlobalFontPath = FontPath,
    MythicPlusPull = { Sync = Noop, Stop = Noop, Update = Noop },
    CharacterData = function(id)
        assert(id == "objectives")
        return character
    end,
}
local NS = { Client = { isForever = false }, HUDTextArgs = Noop }
MSUFSuite = { Suite = S, Public = Public, Finite = Finite, GlobalFontPath = FontPath }
CreateFrame = Widget
assert(loadfile(root .. "/MSUF_Suite_Modules/Surfaces.lua"))("Suite", {})
Enum = { WorldElapsedTimerTypes = { ChallengeMode = 1 } }
GetWorldElapsedTimers = function() return 7 end
GetWorldElapsedTime = function(id)
    assert(id == 7, "the challenge timer ID must come from the client")
    return "Challenge", elapsed, Enum.WorldElapsedTimerTypes.ChallengeMode
end
C_Scenario = { GetStepInfo = function() return "Dungeon", "", 1 end }
C_ScenarioInfo = { GetCriteriaInfo = function()
    criteriaReads = criteriaReads + 1
    return { description = "Boss", completed = bossDone, elapsed = since, criteriaID = 42 }
end }
C_ChallengeMode = {
    GetActiveKeystoneInfo = function() return 10, {} end,
    GetMapUIInfo = function() return "Dungeon", nil, 1800 end,
    GetDeathCount = function() return 0, 0 end,
    GetChallengeCompletionInfo = function()
        completionReads = completionReads + 1
        return completion
    end,
}
local path = arg[2] or root .. "/MSUF_Suite_Modules/MythicPlus.lua"
assert(loadfile(path))("Suite", { NS = NS, Suite = S })
local H = assert(S.MythicPlus)

local function Start(timer, criterionElapsed, done, previous)
    elapsed, since, bossDone, completion = timer, criterionElapsed, done, nil
    character, completionReads, criteriaReads = previous or {}, 0, 0
    local owner = { config = { height = 400, bossPace = 2 }, context = { Cancel = Noop, Ticker = Noop },
        active = true, host = Widget(), content = Widget() }
    H.Start(owner, 500)
    return owner, owner.mplus
end

local function Result(time, practice, mapID)
    return { time = time, practiceRun = practice, mapChallengeModeID = mapID or 500, level = 10 }
end

local function Save(owner, time)
    completion = Result(time, false)
    H.Complete(owner)
    return assert(character.mythicSplits["500:10"])
end

local function HasRecords()
    return character.mythicSplits and next(character.mythicSplits) ~= nil
end

local function Reload()
    local owner, view = Start(0, 0, true)
    assert(view.splits["42"] == nil and view.bosses[1].time.text == "", "zero reload sample became a split")
    elapsed, since = 600, 200
    H.Tick(owner)
    assert(view.splits["42"] == 400 and view.bosses[1].time.text == "6:40", "first usable tick must recover the split")
    local reads = criteriaReads
    elapsed, since = 601, 201
    H.Tick(owner)
    assert(criteriaReads == reads, "steady timer ticks must not poll criteria")
    local record = Save(owner, 605000)
    assert(record.time == 605 and record.individual["42"] == 400 and record.run["42"] == 400)
    assert(character.mythicSplits["500:all"].individual["42"] == 400)

    owner, view = Start(100, 99.75, true)
    assert(view.splits["42"] == nil and view.bosses[1].time.text == "", "subsecond split renders as 0:00")
    since = 95
    H.UpdateObjectives(owner)
    assert(view.splits["42"] == 5, "a later valid criterion must fill the missing split")
end

local function Completion()
    local owner, view = Start(600, 200, true)
    H.Complete(owner)
    assert(not HasRecords() and not view.savedSplits, "missing completion info saved the last timer tick")
    for _, time in ipairs({ 0, 500, -1, 0 / 0, math.huge, secret }) do
        completion = Result(time, false)
        H.Complete(owner)
        assert(not HasRecords() and not view.savedSplits, "invalid completion time was persisted")
    end
    completion = Result(605000, false, 499)
    H.Complete(owner)
    assert(not HasRecords(), "the previous dungeon's completion became this run's result")
    completion = Result(605000, false)
    completion.level = 9
    H.Complete(owner)
    assert(not HasRecords(), "a completion at another level became this run's result")
    local reads = completionReads
    local record = Save(owner, 605000)
    assert(completionReads == reads + 1, "completion display and save must share one API snapshot")
    assert(record.time == 605 and record.run["42"] == 400 and view.lastElapsed == 605,
        "late authoritative time must reach the display and both historical buckets")
    assert(character.mythicSplits["500:all"].time == 605)
    local serial = character.mythicSplitSerial
    H.Complete(owner)
    assert(character.mythicSplitSerial == serial, "duplicate completion re-saved splits")

    owner, view = Start(600, nil, false)
    since, bossDone = 0, true
    H.Complete(owner)
    assert(view.splits["42"] == nil, "a newly completed boss was sampled from the provisional final clock")
    since = 5
    record = Save(owner, 605000)
    assert(record.run["42"] == 600, "final criteria must use the confirmed completion time")

    owner, view = Start(600, 200, true)
    for _, practice in ipairs({ true, secret }) do
        completion = Result(605000, practice)
        H.Complete(owner)
        assert(not HasRecords() and not view.savedSplits, "a practice or unreadable run was saved")
    end

    owner, view = Start(600, 200, true)
    character, completion = nil, Result(605000, false)
    H.Complete(owner)
    assert(not view.savedSplits, "completion without character data must stay retryable")
    character = {}
    assert(Save(owner, 605000).time == 605, "late character data lost the confirmed result")
end

local function OldRecords()
    local previous = { mythicSplits = { ["500:10"] = { time = 700,
        individual = { ["42"] = 0 }, run = { ["42"] = 0, otherBoss = 500 } } } }
    local owner, view = Start(600, 200, true, previous)
    assert(view.bosses[1].time.text == "6:40", "a saved 0:00 split is not a valid pace reference")
    owner.config.bossPace = 4
    H.UpdateObjectives(owner)
    assert(view.bosses[1].time.text == "6:40", "a saved 0:00 split is not a valid whole-run reference")
    local record = Save(owner, 750000)
    assert(record.individual["42"] == 400, "a real split must be able to replace a saved 0:00")
    assert(record.time == 700 and record.run.otherBoss == 500, "a slower run overwrote valid best-run history")
end

local cases = { reload = Reload, completion = Completion, old = OldRecords }
if arg[3] then
    assert(cases[arg[3]], "unknown test case")()
else
    Reload()
    Completion()
    OldRecords()
end
print("Mythic+ split persistence passed")

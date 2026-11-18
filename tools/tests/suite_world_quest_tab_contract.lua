local root = assert(arg[1])
local private, callbacks, events, timers = {}, {}, {}, {}
local calls = { tasks = 0, time = 0, reward = 0, requests = 0, map = 0, track = 0, focus = 0 }
local now, shown, combat, mapID = 100, false, false, 21
local secret, blocked = {}, setmetatable({}, { __index = function() error("inaccessible table indexed") end })
local ready = { [1] = true, [2] = true, [3] = true, [4] = true, [5] = true, [6] = false, [7] = true, [8] = true, [9] = true, [23] = true }
local remaining = { [1] = 3600, [2] = 30, [3] = 60, [4] = 90, [5] = 100, [6] = 150, [7] = 200, [8] = 300, [9] = 320, [23] = 120 }
local taskList = { [21] = {
    { questID = 1 }, { questID = 2 }, { questID = 3 }, { questID = 4 }, { questID = 5 }, { questID = 6 },
    { questID = 7 }, { questID = 8 }, { questID = 9 }, { questID = 2 }, { questID = 999 }, { questID = secret }, blocked,
}, [22] = { { questID = 23 } }, [24] = blocked }

local function Public(value) return value ~= secret end
local function Finite(value) return Public(value) and type(value) == "number" and math.abs(value) < math.huge end
local function Text(value) return Public(value) and type(value) == "string" and value ~= "" and value or nil end
local function Field(value, key)
    if not Public(value) or type(value) ~= "table" then return end
    local entry = value[key]
    return Public(entry) and entry or nil
end

local function Noop() end
local function Guard(key)
    assert(not combat, "unexpected " .. key .. " work in combat")
    calls[key] = calls[key] + 1
end
function canaccesstable(value) return value ~= blocked end
function GetTime() return now end
function HaveQuestRewardData(id) Guard("reward") return ready[id] end
function GetQuestLogRewardMoney(id) Guard("reward") return id == 1 and 12000 or 0 end
function GetMoneyString(amount) return tostring(amount) end
function BreakUpLargeNumbers(amount) return tostring(amount) end
function GetNumQuestLogRewards(id) Guard("reward") return (id == 4 or id == 5) and 1 or 0 end
function GetQuestLogRewardInfo(_, id)
    Guard("reward")
    if id == 4 then return "Sword", nil, 1, nil, nil, 55 end
    return "Herb", nil, 2, nil, nil, 67
end
function GetNumQuestLogChoices(id) Guard("reward") return id == 8 and 1 or 0 end
function GetQuestLogChoiceInfo() Guard("reward") return "Helm", nil, 1, nil, nil, 56 end

C_Map = { GetMapInfo = function(id) Guard("map") return { name = "Zone " .. id } end }
C_TaskQuest = {
    GetQuestsOnMap = function(id) Guard("tasks") return taskList[id] or {} end,
    GetQuestTimeLeftSeconds = function(id) Guard("time") return remaining[id] end,
    GetQuestInfoByQuestID = function(id) Guard("tasks") return "Quest " .. id, id == 9 and 12 end,
    RequestPreloadRewardData = function(id) Guard("requests") assert(id == 6 or id == 23) end,
    IsActive = function(id) Guard("tasks") return id ~= 5 end,
}
C_QuestLog = {
    IsWorldQuest = function(id) Guard("tasks") return id ~= 999 end,
    GetQuestRewardCurrencies = function(id)
        Guard("reward")
        if id == 2 then return { { currencyID = 12, totalRewardAmount = 3, name = "Crests" }, blocked } end
        if id == 7 then return { { currencyID = 13, totalRewardAmount = 4, name = "Mechagon" } } end
        if id == 5 then return blocked end
        return {}
    end,
    GetQuestLogMajorFactionReputationRewards = function(id)
        Guard("reward")
        return id == 3 and { { factionID = 10, rewardAmount = 100 } } or {}
    end,
    DoesQuestAwardReputationWithFaction = function(id, faction) Guard("reward") return id == 9 and faction == 12 end,
    GetQuestWatchType = function(id) Guard("tasks") return id == 8 and 2 or nil end,
}
C_CurrencyInfo = { GetFactionGrantedByCurrency = function(id) Guard("reward") return id == 13 and 11 or nil end }
C_MajorFactions = { GetMajorFactionData = function() Guard("reward") return { name = "Haranir" } end }
C_Reputation = { GetFactionDataByID = function() Guard("reward") return { name = "Wildhammer" } end }
C_Item = { GetItemInfoInstant = function(id) Guard("reward") return id, nil, nil, id ~= 67 and "INVTYPE_WEAPON" or "" end }
C_SuperTrack = { SetSuperTrackedQuestID = function(id) Guard("focus") calls.focused = id end }
Enum = { QuestWatchType = { Automatic = 1, Manual = 2 } }
QuestUtil = { TrackWorldQuest = function(id, kind) Guard("track") assert(id == 2 and kind == Enum.QuestWatchType.Automatic) end }
C_Timer = { NewTimer = function(delay, run)
    assert(not combat and delay == 0, "unexpected timer")
    local handle = { run = run, Cancel = function(self) self.cancelled = true end }
    timers[#timers + 1] = handle
    return handle
end }

local mapCallback, mapOwner
UIParent = {}
WorldMapFrame = {
    ScrollContainer = {}, BorderFrame = { GetFrameLevel = function() return 4 end },
    IsVisible = function() return shown end,
    GetMapID = function() Guard("map") return mapID end,
    RegisterCallback = function(_, event, fn, self)
        assert(event == "WorldQuestsUpdate" and not mapCallback and not combat)
        mapCallback, mapOwner = fn, self
    end,
    UnregisterCallback = function(_, event, self)
        assert(event == "WorldQuestsUpdate" and mapOwner == self)
        mapCallback, mapOwner = nil, nil
    end,
}

local function Tick()
    local pending = timers
    timers = {}
    for _, timer in ipairs(pending) do if not timer.cancelled then timer.run() end end
end

local module, window, button
local context = {}
function context:Event(name, fn) events[name] = fn end
function context:RemoveEvent(name) events[name] = nil end
function context:Callback(name, fn) callbacks[name] = fn end
function context:RemoveCallback(name) callbacks[name] = nil end
local function Emit(event, ...) if events[event] then events[event](module, event, ...) end end
local function Signal(event) if callbacks[event] then callbacks[event](module) end end

local function Frame(_, _, parent)
    assert(parent == UIParent, "the map button remains Suite-owned")
    button = {
        SetSize = Noop, SetText = Noop, ClearAllPoints = Noop, SetFrameStrata = Noop, SetFrameLevel = Noop,
        SetScript = function(self, _, fn) self.click = fn end,
        SetPoint = function(_, _, target) assert(target == WorldMapFrame.ScrollContainer) end,
        Show = function(self) self.shown = true end, Hide = function(self) self.shown = false end,
    }
    return button
end

local tools = {}
function tools.IsOpen(owner) return window and window.owner == owner end
function tools.Open(owner, spec)
    assert(spec.valid(owner))
    window = { owner = owner, spec = spec, SetStatus = function(self, status) self.status = status end }
    tools.Refresh(owner)
    return window
end
function tools.Refresh(owner)
    assert(window.owner == owner and not combat)
    window.rows = window.spec.rows(owner)
end
function tools.Close(owner)
    if not tools.IsOpen(owner) then return end
    local spec = window.spec
    window = nil
    spec.onHide(owner)
end

private.NS = { InCombat = function() return combat end, Safety = { IsForbidden = function() return false end } }
private.Suite = {
    ToolListWindow = tools, Public = Public, Finite = Finite, PublicText = Text, PublicField = Field,
    Text = function(value) return value end, ClockText = tostring,
    Dispatch = function(_, fn, ...) fn(...) return true end, CreateFrame = Frame,
    Install = function(id, owner) assert(id == "worldQuestTab") module = owner end,
    ShowPanel = function(name)
        assert(name == "worldMap" and not combat)
        shown = true
        Signal("WorldMapOnShow")
        return true
    end,
}

assert(loadfile(arg[2] or root .. "/MSUF_Suite_Modules/WorldQuestRewards.lua"))("Suite", private)
assert(loadfile(arg[3] or root .. "/MSUF_Suite_Modules/WorldQuestTab.lua"))("Suite", private)
module.context, module.active = context, true
module:Enable()
assert(not button and calls.tasks == 0 and calls.reward == 0)
shown = true
Signal("WorldMapOnShow")
assert(button.shown and calls.tasks == 0 and calls.reward == 0 and not mapCallback and not events.QUEST_LOG_UPDATE)
button.click()
assert(window and mapCallback and #window.rows == 9 and calls.requests == 1)
assert(window.rows[1].key == 2 and window.rows[9].key == 1, "sort by time and remove non-world and duplicate tasks")

local function Filter(key, wanted)
    local queryBefore = calls.tasks + calls.reward
    window.spec.selectTab(module, key)
    tools.Refresh(module)
    assert(#window.rows == #wanted, "incorrect " .. key .. " result count")
    for i, id in ipairs(wanted) do assert(window.rows[i].key == id, "incorrect " .. key .. " quest") end
    assert(queryBefore == calls.tasks + calls.reward, "filtering performs no collection calls")
end

Filter("gold", { 1 })
Filter("reputation", { 3, 7, 9 })
Filter("currency", { 2 })
assert(window.rows[1].search:find("Crests", 1, true), "reward names are searchable")
window.spec.activate(module, window.rows[1], window)
assert(calls.track == 1 and calls.focused == 2)
Filter("gear", { 4, 8 })
window.spec.activate(module, window.rows[2], window)
assert(calls.track == 1 and calls.focused == 8, "keep a manual native watch")
Filter("all", { 2, 3, 4, 5, 6, 7, 8, 9, 1 })
ready[6] = true
Emit("QUEST_DATA_LOAD_RESULT", 6, secret)
Emit("QUEST_DATA_LOAD_RESULT", 23, true)
assert(#timers == 0, "ignore unavailable or stale-map load results")
Emit("QUEST_DATA_LOAD_RESULT", 6, true)
Emit("QUEST_LOG_UPDATE")
assert(#timers == 1)
Tick()
assert(window.rows[5].key == 6 and window.rows[5].classes and calls.requests == 1)
local queryReads = calls.tasks + calls.reward
now = now + 31
mapCallback(mapOwner, 9)
Tick()
assert(window.rows[1].key == 3 and queryReads == calls.tasks + calls.reward,
    "native map callbacks repaint timers and expire rows without re-reading ready quest data")

local oldRow = window.rows[1]
mapID = 22
mapCallback(mapOwner)
window.spec.activate(module, oldRow, window)
assert(calls.focused == 8, "a stale row cannot track a quest from the last map")
Tick()
assert(#window.rows == 1 and window.rows[1].key == 23)

Emit("QUEST_POI_UPDATE")
local queued = timers[1]
local staleMap, staleOwner = mapCallback, mapOwner
combat = true
Emit("PLAYER_REGEN_DISABLED")
assert(not button.shown and not window and not mapCallback and queued.cancelled)
assert(not events.QUEST_LOG_UPDATE and not events.QUEST_POI_UPDATE and not events.QUEST_DATA_LOAD_RESULT)
assert(not callbacks.WorldMapOnShow and not callbacks.WorldMapOnHide)
Tick()
staleMap(staleOwner)
button.click()
Emit("QUEST_POI_UPDATE")
assert(#timers == 0)

combat = false
Emit("PLAYER_REGEN_ENABLED")
assert(button.shown and not window and not mapCallback)
mapID = 24
button.click()
assert(window and #window.rows == 0, "inaccessible map results are safe")
staleMap, staleOwner = mapCallback, mapOwner
module:Refresh()
assert(not window and not mapCallback and not events.QUEST_POI_UPDATE)
local mapReads = calls.map
staleMap(staleOwner)
assert(mapReads == calls.map, "an already closed view cannot read the map")
shown = false
Signal("WorldMapOnHide")
assert(not button.shown)
mapID = 22
module:Open()
assert(window and button.shown and #window.rows == 1, "settings action opens the displayed world map")
module:Disable()
assert(not window and not button.shown and not mapCallback)

local option, opened
local function Unchanged(_, _, _, _, y) return y end
local options = {
    S = { instances = { worldQuestTab = { active = true, Open = function() opened = true end } } },
    Suite = { Menu = {} }, QoLView = {}, HM = { GetSectionEntry = Noop }, M = { AddTooltip = Noop },
    catalog = { worldQuestTab = { page = "suite_qualityOfLife" } }, Tr = private.Suite.Text,
    SectionRules = function() return { { key = "enabled" } } end, Combat = function() return combat end,
    RegisterPage = Noop, Text = Noop, QoLHelpText = function() return "" end,
    BuildQoLIndicatorPreview = function(_, _, _, y) return y end, AttachRuleColors = Noop,
    BuildQoLComfortActions = Unchanged, BuildInventoryToolActions = Unchanged, BuildPlanningToolsActions = Unchanged,
    T = { colors = {} }, Meta = function(_, _, key) assert(key == "action.open") end,
    Button = function(_, _, label, _, _, _, click, enabled)
        assert(label == "Open world quests")
        option = { click = click, enabled = enabled }
    end,
}
local pages = root .. "/MSUF_Suite_Options/Pages/"
assert(loadfile(pages .. "EverydayTools.lua"))("Suite", options)
assert(loadfile(pages .. "ToolIntegration.lua"))("Suite", options)
assert(loadfile(arg[4] or pages .. "QualityOfLife.lua"))("Suite", options)
local group = { id = "worldQuestTab", title = "World quests", switch = "enabled", sections = { "world_quest_tab" } }
local sections, rules = options.QoLView.FeatureRules(group)
assert(#rules == 0 and options.QoLView.HasDetails(group, rules), "the action-only world quest group is revealable")
options.QoLView.BuildFeatureDetails({}, {}, group, "world_quest_tab", 320, sections, rules, {})
assert(option and option.enabled(), "Quality of Life must build the open action")
option.click()
assert(opened)
opened, combat = false, true
assert(not option.enabled())
option.click()
assert(not opened)
print("world quest list: rewards, filters, native focus, map transitions and combat suspension passed")

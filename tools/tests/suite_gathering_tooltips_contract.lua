local root = assert(arg[1], "repository root required")
local checks = 0
local function Check(value, message) assert(value, message); checks = checks + 1 end
local private = {}
local secret = setmetatable({}, { __index = function() error("secret table read") end })
local modules, callbacks, requests, items = {}, {}, {}, { [765] = "Silverleaf" }
local skill, reads, native, capture = 60, 0, 0, true
local S = {}
S.Public = function(value) return value ~= secret end
S.PublicText = function(value) return S.Public(value) and type(value) == "string" and value ~= "" and value or nil end
S.Finite = function(value) return S.Public(value) and type(value) == "number" and value == value end
S.Text = function(value) return value end
S.Dispatch = function(fn, ...) return fn(...) end
S.Install = function(id, module) modules[id] = module end
local NS = { Client = { isForever = true }, Safety = { IsForbidden = function() return false end } }
private.NS, private.Suite = NS, S
canaccesstable = function(value) return value ~= secret end
wipe = function(value) for key in pairs(value) do value[key] = nil end return value end
Enum = { TooltipDataType = { Object = 4, MinimapMouseover = 21 } }
TooltipDataProcessor = { AddTooltipPostCall = function(kind, fn)
    assert(not callbacks[kind], "duplicate permanent tooltip callback")
    callbacks[kind] = fn
end }
GameTooltip = { result = {} }
function GameTooltip:AddDoubleLine(label, value, _, _, _, r, g, b)
    native = native + 1
    if capture then self.result[#self.result + 1] = { label, value, r, g, b } end
end
C_SkillInfo = { GetSkillLineInfoByID = function(id)
    reads = reads + 1
    if id == 186 then return { rank = skill, modifier = 0, name = "Mining" } end
    if id == 182 then return { rank = 50, modifier = 0, name = "Herbalism" } end
end }
C_Item = {
    GetItemNameByID = function(id) return items[id] end,
    RequestLoadItemDataByID = function(id) requests[id] = (requests[id] or 0) + 1 end,
}
local function Load(path) assert(loadfile(root .. "/" .. path))("MSUF_Suite_QualityOfLife", private) end
Load("MSUF_Suite_QualityOfLife/TooltipLines.lua")
Load("MSUF_Suite_QualityOfLife/GatheringData.lua")
Load("MSUF_Suite_QualityOfLife/GatheringTooltips.lua")
local module = assert(modules.gatheringTooltips)
local events = {}
module.context = { Event = function(_, event, fn) events[event] = fn end,
    RemoveEvent = function(_, event) events[event] = nil end }
module.active = true
module.config = { worldTooltips = true, minimapTooltips = true, skillColors = true }
module:Enable()
Check(reads == 2, "skills are read once on activation")
Check(requests[2447] == 1 and requests[765] == nil, "only missing herb names request item data")
local object = { lines = { { leftText = "Tin Vein" }, { leftText = "Requires Mining" } } }
local function Paint(kind, data)
    wipe(GameTooltip.result)
    callbacks[kind](GameTooltip, data or object)
    return GameTooltip.result[1]
end
local row = Paint(4)
Check(#GameTooltip.result == 1 and row[1] == "Tin Vein (Mining)", "known ore adds exactly one identifiable own line")
Check(row[2] == "Required: 65 - Current: 60" and row[3] == 1 and row[4] == .2, "insufficient skill is red")
for _, case in ipairs({ { 65, 1, .5 }, { 90, 1, .85 }, { 115, .25, 1 }, { 165, .6, .6 } }) do
    skill = case[1]
    events.SKILL_LINES_CHANGED(module)
    row = Paint(4)
    Check(row[3] == case[2] and row[4] == case[3], "skill change invalidates color and text")
    Check(row[2]:find(tostring(skill), 1, true), "current skill updates")
end
module.config.worldTooltips = false
Check(Paint(4) == nil, "world and minimap switches are independent")
Check(Paint(21) ~= nil, "minimap remains active without world additions")
module.config.worldTooltips = true
Check(Paint(4, { lines = { { leftText = "Unknown Forever Herb" } } }) == nil, "unknown nodes stay untouched")
Check(Paint(4, { lines = secret }) == nil, "secret line collection is not traversed")
Check(Paint(4, { lines = { secret, { leftText = secret } } }) == nil, "secret lines and names are not read")
callbacks[4](GameTooltip, secret)
callbacks[4]({}, object)
Check(#GameTooltip.result == 0, "shared dispatcher rejects secret data and foreign tooltips")
Check(Paint(4, { lines = { { leftText = "Silverleaf" } } })[1] == "Silverleaf (Herbalism)", "herb names use the client cache")
items[2447] = "Peacebloom"
events.ITEM_DATA_LOAD_RESULT(module, "ITEM_DATA_LOAD_RESULT", 2447, true)
Check(Paint(4, { lines = { { leftText = "Peacebloom" } } }) ~= nil, "late item names join the lookup")
local multiple = { lines = { { leftText = "Tin Vein" }, { leftText = "Silverleaf" }, { leftText = "Unrelated" } } }
Paint(21, multiple)
Check(#GameTooltip.result == 2 and GameTooltip.result[1][1] == "Tin Vein (Mining)"
    and GameTooltip.result[2][1] == "Silverleaf (Herbalism)", "overlapping minimap nodes each retain their identity")
module.config.minimapTooltips = false
Check(Paint(21) == nil, "minimap additions can be disabled")
module.config.minimapTooltips = true
local beforeReads = reads
module:Refresh()
Check(requests[2449] == 1, "refresh does not duplicate outstanding name requests")
Check(reads == beforeReads + 2, "profile refresh reads current professions")
events.ITEM_DATA_LOAD_RESULT(module, "ITEM_DATA_LOAD_RESULT", 2449, false)
module:Refresh()
Check(requests[2449] == 2, "completed failed item loading can retry on a later refresh")
module.active = false
module:Disable()
Check(Paint(4) == nil and Paint(21) == nil, "permanent post-calls do nothing while disabled")
module.active = true
module:Enable()
Check(requests[2449] == 3, "re-enable retries names whose loading completed while disabled")
local itemEvent = events.ITEM_DATA_LOAD_RESULT
for item in pairs(private.GatheringData.herbs) do
    if not items[item] then
        items[item] = "Herb " .. item
        itemEvent(module, "ITEM_DATA_LOAD_RESULT", item, true)
    end
end
Check(events.ITEM_DATA_LOAD_RESULT == nil, "ready name cache unregisters the item data listener")

-- Real shared dispatcher and actual formatter: no profession API reads or
-- formatting allocations during a repeated native tooltip rebuild.
Paint(21)
capture = false
beforeReads = reads
local beforeNative = native
local function Rebuild() callbacks[21](GameTooltip, object) end
local function Allocation()
    collectgarbage("collect")
    collectgarbage("stop")
    local before = collectgarbage("count")
    for _ = 1, 1000 do Rebuild() end
    local delta = collectgarbage("count") - before
    collectgarbage("restart")
    return delta
end
local allocation = math.min(Allocation(), Allocation())
Check(allocation < 1, "warm tooltip rebuild allocates no Lua rows or strings")
Check(reads == beforeReads and native == beforeNative + 2000, "warm path does exactly one native line write per build")
local instructions = 0
debug.sethook(function() instructions = instructions + 1 end, "", 1)
Rebuild()
debug.sethook()
Check(instructions < 400, "single-node warm tooltip instruction budget")

capture = true
local skillAPI = C_SkillInfo
C_SkillInfo = nil
module:Refresh()
Check(Paint(4) == nil, "missing skill capability leaves native tooltips alone")
C_SkillInfo = skillAPI
module:Refresh()
Check(Paint(4) ~= nil, "restored skill capability resumes tooltip additions")

-- Both catalog entries are unavailable on Retail and retain opt-in defaults.
local specs, rules = {}, {}
NS.CatalogBuild = { ForAddon = function()
    return { Module = function(id, spec) specs[id] = spec end, Section = function(id, _, _, list) rules[id] = list end,
        Bool = function(key, _, default) return { key = key, default = default } end,
        Number = function(key, _, default) return { key = key, default = default } end }
end }
assert(loadfile(root .. "/MSUF_Suite/Core/Catalog/ForeverTools.lua"))("MSUF_Suite", NS)
for _, id in ipairs({ "gatheringTooltips", "foreverWorldMap" }) do
    Check(specs[id].available() == true and specs[id].defaultEnabled == false, "Forever feature is opt-in")
    NS.Client.isForever = false
    Check(specs[id].available() == false, "Retail cannot activate the Forever feature")
    NS.Client.isForever = true
end
print(string.format("Gathering tooltip contract: %d checks; warm %d VM, %.3f KB/1000, one native line/build",
    checks, instructions, allocation))

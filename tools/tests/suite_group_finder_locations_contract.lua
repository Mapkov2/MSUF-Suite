-- Native LFG data, pooled rows and the visible/outdoor lifetime of the in-row labels.
local root = assert(arg[1], "Suite root required")
local runtime = arg[2] or root .. "/MSUF_Suite_QualityOfLife/GroupFinderLocations.lua"
local Secrets = assert(loadfile(root .. "/../MidnightSimpleUnitFrames/tools/tests/classpower_secrets.lua"))()
local Support = dofile(root .. "/tools/tests/suite_test_support.lua")
Secrets.Install()
Secrets.GUARD_NAMES.falsy.Public, Secrets.GUARD_NAMES.falsy.Finite = true, true
local stopWatching = Secrets.Watch(runtime, { strict = true })
local checks, reads, textWrites, visibilityWrites, allocations = 0, 0, 0, 0, 0
local function Check(value, message)
    checks = checks + 1
    assert(value, message)
end
local function Noop() end
local function Frame(parent, native)
    local frame = { parent = parent, shown = true, hooks = {}, native = native }
    function frame:HookScript(event, fn)
        self.hooks[event] = self.hooks[event] or {}
        self.hooks[event][#self.hooks[event] + 1] = fn
    end
    function frame:Fire(event)
        for _, fn in ipairs(self.hooks[event] or {}) do fn(self) end
    end
    function frame:IsShown() return self.shown end
    function frame:IsVisible() return self.shown and (not self.parent or self.parent:IsVisible()) end
    function frame:GetParent() return self.parent end
    function frame:ClearAllPoints() self.points = {} end
    function frame:Show()
        visibilityWrites = visibilityWrites + 1
        if self.shown then return end
        self.shown = true
        self:Fire("OnShow")
    end
    function frame:Hide()
        visibilityWrites = visibilityWrites + 1
        if not self.shown then return end
        self.shown = false
        self:Fire("OnHide")
    end
    function frame:SetPoint(...)
        Check(not self.native, "native anchor changed")
        self.points = self.points or {}
        self.points[#self.points + 1] = { ... }
    end
    function frame:SetText(value)
        Check(not self.native and not Secrets.IsSecret(value), "native or secret text write")
        self.text = value
        textWrites = textWrites + 1
    end
    frame.SetWidth = Noop
    frame.SetJustifyH, frame.SetJustifyV, frame.SetWordWrap, frame.SetMaxLines = Noop, Noop, Noop, Noop
    return frame
end
local function Owned(parent)
    allocations = allocations + 1
    return Frame(parent)
end
local combat, kind, events, answers = false, "world", {}, {}
local context = {}
function context:Event(event, fn) events[event] = fn end
function context:RemoveEvent(event) events[event] = nil end
local function Emit(event, ...)
    if events[event] then events[event](nil, event, ...) end
end
local suite = {
    Public = function(value) return not Secrets.IsSecret(value) end,
    Finite = function(value)
        return not Secrets.IsSecret(value) and type(value) == "number" and value == value
            and value > -math.huge and value < math.huge
    end,
    PublicText = function(value)
        return not Secrets.IsSecret(value) and type(value) == "string" and value ~= "" and value or nil
    end,
    InstanceKind = function() return kind end,
    Dispatch = function(_, fn, ...) return fn(...) end,
    Text = function(text) return text end,
    SetFont = Noop,
    CreateFrame = function() error("LFG locations created a frame") end,
    CreateTexture = function() error("LFG locations created a texture") end,
    CreateFontString = Owned,
}
function suite.PublicField(info, key)
    if not suite.Public(info) or type(info) ~= "table" then return nil end
    local value = info[key]
    return suite.Public(value) and value or nil
end
local installed
function suite.Install(id, module)
    Check(id == "groupFinderLocations", "wrong owner")
    installed = module
    module.context, module.active = context, false
end
local ns = { Client = { isForever = false }, Finish = Noop }
function ns.InCombat(event)
    if event == "PLAYER_REGEN_DISABLED" then return true end
    if event == "PLAYER_REGEN_ENABLED" then return false end
    return combat
end
local hooks = 0
hooksecurefunc = function(name, fn)
    Check(name == "LFGBrowseSearchEntry_Update", "unexpected native hook")
    local original = _G[name]
    _G[name] = function(...)
        original(...)
        return fn(...)
    end
    hooks = hooks + 1
end
C_LFGList = { GetSearchResultLeaderInfo = function(id)
    Check(not Secrets.IsSecret(id), "secret search ID")
    reads = reads + 1
    return answers[id]
end }
C_Timer = setmetatable({}, { __index = function() error("LFG locations started a timer") end })
LFGBrowseFrame, LFGBrowseSearchEntry_Update = nil, nil
assert(loadfile(runtime))("MSUF_Suite_QualityOfLife", { NS = ns, Suite = suite })
Check(not installed and allocations == 0 and not next(events), "Retail acquired a runtime")
ns.Client.isForever = true
assert(loadfile(runtime))("MSUF_Suite_QualityOfLife", { NS = ns, Suite = suite })
Check(installed and allocations == 0 and not next(events), "disabled module did work")
local module = installed
module.active = true
module:Enable()
Check(events.ADDON_LOADED and allocations == 0, "cold enable did not wait for Blizzard")
Emit("ADDON_LOADED", "UnrelatedAddon")
Check(events.ADDON_LOADED and hooks == 0, "unrelated addon installed hooks")
local parent = Frame(nil, true)
local browser = Frame(parent, true)
browser.shown = false
local scroll = Frame(browser, true)
browser.ScrollBox = scroll
local first, second, hidden, divider, own = Frame(scroll, true), Frame(scroll, true), Frame(scroll, true),
    Frame(scroll, true), Frame(scroll, true)
first.resultID, second.resultID, hidden.resultID, own.resultID = 1, 2, 3, 4
first.isDelisted, second.isDelisted, own.isDelisted = false, false, false
own.hasSelf = true
hidden.shown = false
local rows = { first, second, hidden, divider, own }
function scroll:GetView() return true end
function scroll:ForEachFrame(fn) for _, row in ipairs(rows) do fn(row) end end
LFGBrowseFrame, LFGBrowseSearchEntry_Update = browser, Noop
answers[1], answers[2], answers[3] = { areaName = "Stormwind City" }, { areaName = "Westfall" }, { areaName = "Hidden" }
answers[4] = { areaName = "Elwynn Forest" }
Emit("ADDON_LOADED", "Blizzard_GroupFinder_VanillaStyle")
Check(not next(events) and hooks == 1 and allocations == 0, "closed browser retained work")
browser:Show()
Check(reads == 2 and not module.labels[divider] and not module.labels[hidden], "scanned hidden or category rows")
Check(not module.labels[own], "own listing received a location")
Check(module.labels[first].label.text == "Stormwind City" and module.labels[second].label.text == "Westfall",
    "visible rows did not show the native locations")
Check(events.PLAYER_ENTERING_WORLD and events.PLAYER_LEAVING_WORLD and events.ZONE_CHANGED_NEW_AREA
    and events.PLAYER_REGEN_DISABLED and events.PLAYER_REGEN_ENABLED, "visible transitions are not observed")
for _, row in ipairs({ first, second }) do
    local label = module.labels[row].label
    local point = label.points[1]
    Check(label.parent == row and #label.points == 1, "location is not a region of its native row")
    Check(point[1] == "BOTTOMRIGHT" and point[2] == row and point[3] == "BOTTOMRIGHT" and point[4] < 0 and point[5] > 0,
        "location is not inside the row's bottom-right corner")
end
local initialAllocations, initialWrites, initialVisibility, beforeReads = allocations, textWrites, visibilityWrites, reads
for _ = 1, 100 do LFGBrowseSearchEntry_Update(first) end
Check(reads == beforeReads + 100 and textWrites == initialWrites and visibilityWrites == initialVisibility,
    "unchanged native updates repeated writes or more than one data read")
Check(allocations == initialAllocations, "unchanged updates allocated widgets")
answers[1].areaName = "Redridge Mountains"
LFGBrowseSearchEntry_Update(first)
Check(module.labels[first].label.text == "Redridge Mountains", "location change did not refresh")
answers[1] = nil
LFGBrowseSearchEntry_Update(first)
Check(not module.labels[first].label:IsShown(), "missing leader info kept a stale location")
answers[1] = Secrets.New("table")
LFGBrowseSearchEntry_Update(first)
Check(not module.labels[first].label:IsShown(), "restricted info remained visible")
answers[1] = { areaName = Secrets.New("string") }
LFGBrowseSearchEntry_Update(first)
Check(not module.labels[first].label:IsShown(), "restricted area remained visible")
for _, area in ipairs({ "", false }) do
    answers[1] = { areaName = area }
    LFGBrowseSearchEntry_Update(first)
    Check(not module.labels[first].label:IsShown(), "empty or invalid area remained visible")
end
answers[1] = { areaName = "Duskwood" }
first.resultID = Secrets.New("number")
beforeReads = reads
LFGBrowseSearchEntry_Update(first)
Check(reads == beforeReads, "restricted row ID reached the API")
first.resultID, first.isDelisted = 1, Secrets.New("boolean")
LFGBrowseSearchEntry_Update(first)
Check(reads == beforeReads, "restricted delisted state reached the API")
first.isDelisted = true
LFGBrowseSearchEntry_Update(first)
Check(reads == beforeReads, "delisted row reached the API")
first.isDelisted, first.resultID = false, 2
LFGBrowseSearchEntry_Update(first)
Check(module.labels[first].label.text == "Westfall", "pooled row retained the previous player's area")
first.hasSelf = Secrets.New("boolean")
LFGBrowseSearchEntry_Update(first)
Check(not module.labels[first].label:IsShown(), "restricted own-listing state kept a location")
first.hasSelf = nil
LFGBrowseSearchEntry_Update(first)
Check(module.labels[first].label:IsShown(), "pooled row did not restore its location")
-- Groups: only the leader's area exists on Forever, so it carries the crown.
local CROWN = "|A:groupfinder-icon-leader:14:14|a "
second.PartyIcon = Frame(second, true)
LFGBrowseSearchEntry_Update(second)
Check(module.labels[second].label.text == CROWN .. "Westfall", "group row did not mark the leader's area")
second.PartyIcon.shown = false
LFGBrowseSearchEntry_Update(second)
Check(module.labels[second].label.text == "Westfall", "solo row kept the leader crown")
second.PartyIcon.shown = true
LFGBrowseSearchEntry_Update(second)
local groupWrites = textWrites
for _ = 1, 100 do LFGBrowseSearchEntry_Update(second) end
Check(textWrites == groupWrites, "unchanged group updates rewrote the crown text")
local function ExpectBlocked(event, expectedKind)
    kind = expectedKind
    beforeReads = reads
    Emit(event)
    LFGBrowseSearchEntry_Update(first)
    Check(not module.labels[first].label:IsShown() and reads == beforeReads,
        "inactive area still read or showed locations: " .. event)
end
ExpectBlocked("ZONE_CHANGED_NEW_AREA", "party")
ExpectBlocked("PLAYER_ENTERING_WORLD", "raid")
ExpectBlocked("ZONE_CHANGED_NEW_AREA", nil)
kind = "world"
Emit("PLAYER_ENTERING_WORLD")
Check(module.labels[first].label:IsShown(), "returning outdoors did not restore locations")
ExpectBlocked("PLAYER_LEAVING_WORLD", "world")
Emit("PLAYER_ENTERING_WORLD")
ExpectBlocked("PLAYER_REGEN_DISABLED", "world")
Check(not combat, "combat-edge fixture must fire before the combat API flips")
Emit("PLAYER_REGEN_ENABLED")
Check(module.labels[first].label:IsShown(), "combat end did not restore current areas")
local oldLabels = module.labels
browser:Hide()
beforeReads, initialVisibility = reads, visibilityWrites
Check(not next(events) and not module.labels[first].label:IsShown(), "closed browser retained events or labels")
for _ = 1, 100 do LFGBrowseSearchEntry_Update(first) end
Check(reads == beforeReads and visibilityWrites == initialVisibility, "hidden browser hook did work")
browser:Show()
module.active = false
module:Disable()
Check(not next(events) and not module.labels[first].label:IsShown(), "disable retained work")
beforeReads, initialVisibility = reads, visibilityWrites
for _ = 1, 100 do LFGBrowseSearchEntry_Update(first) end
Check(reads == beforeReads and visibilityWrites == initialVisibility, "disabled hook did work")
module.active = true
module:Enable()
Check(module.labels[first].label:IsShown() and module.labels == oldLabels and hooks == 1,
    "re-enable duplicated hooks or lost the view")
Check(#browser.hooks.OnShow == 1 and not first.hooks.OnHide, "re-enable duplicated frame hooks")
local violations = stopWatching()
Check(#violations == 0, "strict secret watcher: " .. table.concat(violations, "\n"))
-- Measure the warm update: one native read, no text/visibility writes or widgets.
-- Half the updates hit a group row, whose crown text is built only on change.
for _ = 1, 10 do LFGBrowseSearchEntry_Update(first) LFGBrowseSearchEntry_Update(second) end
Check(module.labels[second].label:IsShown(), "warm group row is not painted")
collectgarbage("collect")
collectgarbage("stop")
local kb = collectgarbage("count")
local instructions = 0
debug.sethook(function() instructions = instructions + 1 end, "", 1)
for _ = 1, 50 do LFGBrowseSearchEntry_Update(first) LFGBrowseSearchEntry_Update(second) end
debug.sethook()
local allocated = collectgarbage("count") - kb
collectgarbage("restart")
Check(instructions < 30000 and allocated < 2, "warm LFG update exceeded its instruction/allocation budget")
print(string.format("LFG locations: %d checks; warm update %.0f instructions, %.2f KiB / 100 updates",
    checks, instructions / 100, allocated))

-- Use the real catalog to check availability and the opt-in default after integration.
if not arg[2] then
    local catalogNS = { Client = { isForever = true }, Text = function(text) return text end }
    for _, file in ipairs({ "SuiteCatalog", "Catalog/QualityOfLife", "Catalog/QualityOfLifeGroup" }) do
        assert(loadfile(root .. "/MSUF_Suite/Core/" .. file .. ".lua"))("MSUF_Suite", catalogNS)
    end
    Check(catalogNS.SuiteCatalog.groupFinderLocations.rules.enabled.default == false, "new locations option must be opt-in")
    Check(catalogNS.SuiteCatalog.groupFinderLocations.available(), "Forever option unavailable")
    catalogNS.Client.isForever = false
    Check(not catalogNS.SuiteCatalog.groupFinderLocations.available(), "Retail option was advertised")
end

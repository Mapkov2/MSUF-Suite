-- Combat work depends on current collapse views, not every previously
-- visited hidden tree and its cached native rows.
local root = assert(arg[1])
arg[3] = "coverage"
local H = assert(loadfile(root .. "/tools/tests/suite_skin_menu_transitions_contract.lua"))()
local NS, Frame = H.NS, H.Frame
local eventFrame, event
for _, frame in ipairs(H.frames) do
    local callback = frame.scripts.OnEvent
    local source = callback and debug.getinfo(callback, "S").source:gsub("\\", "/")
    if source and source:find("/Adapters/AddonListMotion.lua", 1, true) then
        eventFrame, event = frame, callback
    end
end
assert(event, "the actual collapse combat handler is missing")
local function Combat() event(eventFrame, "PLAYER_REGEN_DISABLED") end
local function Regen() event(eventFrame, "PLAYER_REGEN_ENABLED") end
local native = 0
local function CountGroups()
    for _, group in ipairs(H.groups) do
        if not group.counted then
            local stop = group.Stop
            group.Stop = function(self) native = native + 1; return stop(self) end
            group.counted = true
        end
    end
end
local function Measure(callback)
    local result = { vm = 0, native = 0, kb = math.huge }
    for _ = 1, 2 do
        collectgarbage("collect")
        collectgarbage("stop")
        local vm = 0
        local function Instruction() vm = vm + 1 end
        local before = collectgarbage("count")
        native = 0
        debug.sethook(Instruction, "", 1)
        callback()
        debug.sethook()
        local kb = collectgarbage("count") - before
        collectgarbage("restart")
        result.vm = math.max(result.vm, vm)
        result.native = math.max(result.native, native)
        result.kb = math.min(result.kb, kb)
    end
    return result
end
local function Node(parent, size)
    local node = { parent = parent, size = size or 0, data = {} }
    function node:GetData() return self.data end
    function node:GetParent() return self.parent end
    function node:GetSize() return self.size end
    function node:IsCollapsed() return self.collapsed end
    return node
end
local function View(owner, deferred)
    local box = Frame(UIParent, true)
    box.provider, box.offset = {}, 0
    function box.provider:GetRootNode() return self end
    function box:GetDataProvider() return self.provider end
    function box:GetDerivedScrollOffset() return self.offset end
    function box:ForEachFrame(callback) for _, row in ipairs(self.rows) do callback(row) end end
    local parent = Node(nil, 1)
    local child, after = Node(parent), Node()
    local function Row(node, top)
        local row = Frame(box, true)
        row.node, row.top, row.height = node, top, 20
        function row:GetElementData() return self.node end
        row.label = row:CreateFontString()
        row.label.text = "Native row"
        return row
    end
    local header, row, following = Row(parent, 400), Row(child, 380), Row(after, 360)
    box.rows = { header, row, following }
    NS.GenericWindows.trackContent(box, owner)
    if deferred then
        assert(NS.AddonListMotion.Track(box, owner, box.provider), "cold collapse view could not register")
        return box, NS.AddonListMotion.scrollStates[box]
    end
    parent.collapsed = true
    box:TriggerEvent("released", row, child)
    box.rows, following.top = { header, following }, 380
    box:TriggerEvent("layout")
    local state = NS.AddonListMotion.scrollStates[box]
    assert(state.records[following].group:IsPlaying() and state.records[row].ghost.group:IsPlaying(),
        "fixture did not start real row and closing-copy animation")
    return box, state, following, row, parent, child, header
end

CountGroups()
Combat()
local smallCombat, smallRegen = Measure(Combat), Measure(Regen)
for index = 1, 40 do
    local owner = "historical-collapse-" .. index
    local box, state, following, row = View(owner)
    box:Hide()
    assert(not state.records[following].group:IsPlaying() and not state.records[row].ghost.group:IsPlaying(),
        "hiding the tree failed to cancel current native motion")
    if index % 2 == 0 then NS.GenericWindows.releaseContent(owner) end
end
CountGroups()
local largeCombat, largeRegen = Measure(Combat), Measure(Regen)
local budgets = { { "combat", smallCombat, largeCombat }, { "regen", smallRegen, largeRegen } }
for _, pair in ipairs(budgets) do
    local label, before, after = pair[1], pair[2], pair[3]
    print(("BUDGET collapse-%s historical0 vm=%d native=%d kb=%.3f; historical40 vm=%d native=%d kb=%.3f")
        :format(label, before.vm, before.native, before.kb, after.vm, after.native, after.kb))
end
for _, pair in ipairs(budgets) do
    local label, before, after = pair[1], pair[2], pair[3]
    assert(after.native == before.native, label .. " stopped cached motion in hidden or released lists")
    assert(after.vm <= before.vm + 64, label .. " scanned historical hidden collapse states")
    assert(after.kb <= before.kb + 0.125, label .. " allocated for historical hidden collapse states")
end

local box, state, following, row, parent, child, header = View("current-collapse")
Combat()
assert(not state.hadSnapshot and not state.records[following].group:IsPlaying()
    and not state.records[row].ghost.group:IsPlaying(), "combat did not clean the active collapse view")
Regen()
assert(state.hadSnapshot, "combat end did not rebuild the visible collapse snapshot")
parent.collapsed, following.top, box.rows = false, 360, { header, row, following }
row:Show()
box:TriggerEvent("layout")
assert(state.records[following].group:IsPlaying(), "visible collapse did not animate after combat cleanup")
box:Hide()
NS.Motion.combat = true
box:Show()
box:Fire("OnShow")
assert(not state.hadSnapshot, "showing in combat rebuilt native collapse state")
NS.Motion.combat = false
Regen()
assert(state.hadSnapshot, "a tree shown during combat could not rebuild after combat")
NS.GenericWindows.releaseContent("current-collapse")
for _, kind in ipairs({ "Track", "Attach", "TrackCollection" }) do
    local owner = "reactivate-collapse-" .. kind
    local cached, cachedState = View(owner)
    NS.GenericWindows.releaseContent(owner)
    assert(not cachedState.active and not cachedState.registered and cached:IsVisible(),
        "fixture did not release a still-visible cached collapse root")
    NS.Motion.combat = true
    local activated
    if kind == "Track" then activated = NS.AddonListMotion.Track(cached, owner, cached.provider)
    elseif kind == "Attach" then
        cached.ScrollBox = cached
        activated = NS.AddonListMotion.Attach(cached, owner)
    else
        activated = NS.AddonListMotion.TrackCollection(cached, owner, "tree",
            function(_, collect) for _, row in ipairs(cached.rows) do collect(row) end end,
            function(_, row) return row.node, row.node.collapsed, row.node.parent end)
    end
    assert(activated and not cachedState.hadSnapshot, "combat reactivation rebuilt collapse state")
    NS.Motion.combat = false
    Regen()
    assert(cachedState.hadSnapshot, kind .. ": a visible cached view re-enabled in combat stayed dormant")
    NS.AddonListMotion.DisableOwner(owner)
    cached:Hide()
end
NS.Motion.combat = true
local cold, coldState = View("cold-collapse", true)
assert(coldState and not coldState.hadSnapshot, "cold combat registration created a snapshot")
NS.Motion.combat = false
Regen()
assert(coldState.hadSnapshot, "a visible view first registered during combat stayed dormant")
cold:Hide()
NS.GenericWindows.releaseContent("cold-collapse")
print("Suite collapse historical-view budgets and combat lifecycle passed")

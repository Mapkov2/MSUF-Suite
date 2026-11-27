-- Actual discovery/safety code with public widget identities and recorded native calls.
-- This is an operation/lifecycle contract, not a renderer or live timing test.
local root = assert(arg[1], "Suite root required")
local flavor = arg[2] or "Mainline"
local checks, jobs, native, calls, tracked, listeners = 0, {}, {}, {}, {}, {}
local secret, combat = {}, false
local reportedErrors, dropDispatchResults = 0, false
local function Check(value, message) assert(value, message) checks = checks + 1 end
local function Noop() end
local function Count(name) native[name] = (native[name] or 0) + 1 end
wipe = function(values) for key in pairs(values) do values[key] = nil end end
local scalarChecks = 0
issecretvalue = function(value)
    scalarChecks = scalarChecks + 1
    return rawequal(value, secret)
end
local bulkChecks = 0
hasanysecretvalues = function(a, b, c, d, ...)
    bulkChecks = bulkChecks + 1
    if rawequal(a, secret) or rawequal(b, secret) or rawequal(c, secret) or rawequal(d, secret) then return true end
    for i = 1, select("#", ...) do if rawequal(select(i, ...), secret) then return true end end
    return false
end
InCombatLockdown = function() return combat end
securecallfunction = function(fn, ...)
    Count("Dispatch")
    local ok, first, second = pcall(fn, ...)
    if not ok then reportedErrors = reportedErrors + 1 return end
    if not dropDispatchResults then return first, second end
end
local function Track(frame, owner)
    Check(not frame.forbidden and not frame.protected, "provider received inaccessible frame")
    tracked[frame] = owner
    calls.target = (calls.target or 0) + 1
end
local watches = {}
local function Watch(frame, owner)
    if frame.rejectWatch and not frame.CreateAnimationGroup then return false end
    local watch = watches[frame] or { owners = {} }
    watches[frame] = watch
    local owners = watch.owners
    owners[owner], tracked[frame] = true, owner
    return true
end
local function UnwatchOwner(owner)
    for frame, watch in pairs(watches) do
        local owners = watch.owners
        owners[owner] = nil
        if tracked[frame] == owner then tracked[frame] = next(owners) end
    end
end
local function Untrack(owner)
    for frame, value in pairs(tracked) do if value == owner then tracked[frame] = nil end end
end
local NS = { Motion = { combat = false }, IsCombatLocked = InCombatLockdown,
    ContentMotion = { Watch = Watch, Play = Noop, UnwatchOwner = UnwatchOwner, watchers = watches },
    Registry = { QueueJob = function(fn) jobs[fn] = true end,
        CancelJob = function(fn) jobs[fn] = nil end,
        AddListener = function(owner, fn) listeners[owner] = fn end },
    ResultMotion = { Track = Track, ReleaseOwner = Untrack },
    ScrollMotion = { Track = Track, ReleaseOwner = Untrack },
    LegacyScrollMotion = { Track = Track, ReleaseOwner = Untrack },
    AddonListMotion = { DisableOwner = Noop, TrackCollection = Track }, CollapseCollectionRows = {},
    GenericWindows = { SetMenuMotionProvider = Noop, SetCollapseMotionProvider = Noop },
    Adapters = { SetMenuMotionProvider = Noop }, AdapterKit = { SetMotionProvider = Noop },
    Checkmarks = { SetSettingsMotionProvider = Noop }, PublicAPI = {}, SocialUISkin = { SetMotionProvider = Noop } }
local function Load(path)
    local override = os.getenv("SUITE_MENU_DISCOVERY_OVERRIDE")
    local file = override and path == "Rendering/MenuMotion.lua" and override
        or root .. "/MSUF_Suite_Skin/" .. path
    assert(loadfile(file))("MSUF_Suite_Skin", NS)
end
Load("../MSUF_Suite/Appearance/Safety.lua")
Load("Adapters/AdapterKit.lua")
Load("Rendering/CollapseCollections.lua")
local collectionTrack = NS.CollapseCollections.Track
NS.CollapseCollections.Track = function(frame, owner)
    calls.collections = (calls.collections or 0) + 1
    return collectionTrack(frame, owner)
end
local safetyCall = NS.Safety.Call
NS.Safety.Call = function(frame, name, ...)
    if name == "GetChildren" then calls.discovery = (calls.discovery or 0) + 1 end
    return safetyCall(frame, name, ...)
end
Load("Rendering/MenuMotion.lua")
local Menus = NS.MenuMotion
local function Frame(kind)
    local frame = { kind = kind or "Frame", hooks = {}, children = {}, visible = true }
    function frame:IsForbidden() Count("IsForbidden") return self.forbidden == true end
    function frame:IsProtected()
        Check(not self.forbidden, "protected read on forbidden widget")
        Count("IsProtected")
        return self.protected or self.secretProtection and secret or false, self.explicit or false
    end
    function frame:GetObjectType()
        Check(not self.forbidden, "type read on forbidden widget")
        Count("GetObjectType")
        return self.secretKind and secret or self.kind
    end
    function frame:HookScript(event, callback)
        local list = self.hooks[event] or {}
        self.hooks[event] = list
        list[#list + 1] = callback
    end
    function frame:HasScript() return true end
    function frame:GetChildren()
        Check(not self.forbidden, "children read on forbidden widget")
        Count("GetChildren")
        return unpack(self.children)
    end
    function frame:IsVisible() Count("IsVisible") return self.visible end
    return frame
end
local function Signal(frame, event)
    for _, fn in ipairs(frame.hooks[event] or {}) do fn(frame, 123, 456) end
end
local function Drain()
    local pending = jobs
    jobs = {}
    for fn in pairs(pending) do fn() end
end
local function Resize(frame) Signal(frame, "OnSizeChanged") Drain() end
local function Reset() wipe(native) wipe(calls) end
local reviewCase = os.getenv("SUITE_MENU_DISCOVERY_CASE")
local function ReviewCases()
    Drain()
    if not reviewCase or reviewCase == "watchloss" then
        local window, content, lease = Frame(), Frame(), {}
        window.Content = content
        Menus.Track(window, lease)
        -- AceGUI Released can remove this owner's content watch directly.
        UnwatchOwner(lease)
        Resize(window)
        Check(tracked[content] == lease, "foreign unwatch was not healed")
        Menus.Release(lease) Drain()
    end
    if not reviewCase or reviewCase == "emptyedges" then
        local window, lease = Frame(), {}
        for i = 1, 241 do window.children[i] = Frame() end
        Menus.Track(window, lease)
        Reset() Resize(window)
        Check(not calls.discovery, "nil-only children consumed edge budget")
        Menus.Release(lease) Drain()
    end
    if not reviewCase or reviewCase == "bodyrecovery" then
        local window, content, lease, target = Frame(), Frame(), {}, Frame()
        window.Content, window.children[1] = content, content
        Menus.Track(window, lease)
        content.protected = true
        Resize(window)
        content.protected = false
        content.children[1] = target
        target.GetDataProvider, target.RegisterCallback = Noop, Noop
        Signal(content, "OnShow") Drain()
        Check(tracked[target] ~= nil, "pruned body observer missed show")
        Menus.Release(lease) Drain()
    end
    if not reviewCase or reviewCase == "latebody" then
        local window, content, lease = Frame(), Frame(), {}
        window.Content, content.rejectWatch = content, true
        Menus.Track(window, lease)
        Reset() Resize(window)
        Check(not calls.discovery, "ineligible body prevented discovery reuse")
        content.CreateAnimationGroup = Noop
        Resize(window)
        Check(tracked[content] == lease, "late body animation capability was missed")
        Menus.Release(lease) Drain()
    end
    if not reviewCase or reviewCase == "voidboundary" then
        local window, lease = Frame(), {}
        Menus.Track(window, lease)
        dropDispatchResults = true
        Resize(window)
        Reset() Resize(window)
        Check(not calls.discovery, "void boundary disabled discovery reuse")
        dropDispatchResults = false
        Menus.Release(lease) Drain()
    end
end
if reviewCase and reviewCase ~= "ownership" then ReviewCases() return end
local function SharedOwner()
    local first, second, shared, body = Frame(), Frame(), {}, Frame()
    second.Content = body
    Menus.Track(first, shared)
    Menus.Track(second, shared)
    Menus.Release(shared, first)
    Resize(second)
    Check(tracked[body] == shared, "cross-root release lost body watch")
    if os.getenv("SUITE_MENU_DISCOVERY_CASE") ~= "ownership" and not os.getenv("SUITE_MENU_DISCOVERY_MEASURE") then
        Check(tracked[second] == shared, "cross-root release lost root watch")
    end
    Menus.Release(shared)
end
SharedOwner()
if os.getenv("SUITE_MENU_DISCOVERY_CASE") == "ownership" then return end
-- The Communities trace opened a 413-node tree; most nodes had neither
-- a named content body nor an animation/list binding. Keep late discovery.
local function ColdTreeBudget()
    local window, lease = Frame(), {}
    for i = 1, 4 do
        local page = Frame()
        window.children[i] = page
        for j = 1, 102 do
            local child = Frame()
            child.CreateAnimationGroup = Noop
            page.children[j] = child
        end
    end
    Reset()
    local scalar = scalarChecks
    collectgarbage("collect")
    collectgarbage("stop")
    local before = collectgarbage("count")
    Menus.Track(window, lease)
    local heap = collectgarbage("count") - before
    collectgarbage("restart")
    print(string.format("413-node discovery: %.1f KiB, %d scalar checks", heap, scalarChecks - scalar))
    Check(heap < 180, "plain nodes allocated empty discovery tables")
    Check(not calls.collections, "plain nodes entered collection provider")
    Check(scalarChecks - scalar < 6000, "plain nodes repeated provider guards")
    local list = window.children[4].children[102]
    list.GetDataProvider, list.RegisterCallback = Noop, Noop
    Resize(window)
    Check(tracked[list], "sparse cold records missed a late list")
    Menus.Release(lease) Drain()
end
ColdTreeBudget()
local owner, panel = {}, Frame()
for i = 1, 24 do panel.children[i] = Frame() end
Check(Menus.Track(panel, owner), "initial adoption failed")
local plain, scroll, boundaryList = Frame(), Frame("ScrollFrame"), Frame()
boundaryList.GetDataProvider, boundaryList.RegisterCallback = Noop, Noop
Check(select("#", Menus.TrackTarget(plain, owner)) == 0, "plain target return arity changed")
Check(select("#", Menus.TrackTarget(scroll, owner)) == 0, "scroll target return arity changed")
Check(select("#", Menus.TrackTarget(boundaryList, owner)) == 1, "list target return arity changed")
Check(Menus.TrackTarget(boundaryList, owner) == true, "list target boundary changed")
Reset()
-- A resize can replace a child with no change in count, so warm verification
-- deliberately retains GetChildren. It must avoid repeated target discovery.
local instructions = 0
local scalarBefore, bulkBefore = scalarChecks, bulkChecks
debug.sethook(function() instructions = instructions + 100 end, "", 100)
for i = 1, 219 do Resize(panel) end
debug.sethook()
print(string.format("resize-budget: discovery=%d forbidden=%d protection=%d type=%d children=%d scalar=%d bulk=%d vm~%d",
    calls.discovery or 0, native.IsForbidden or 0, native.IsProtected or 0,
    native.GetObjectType or 0, native.GetChildren or 0, scalarChecks - scalarBefore, bulkChecks - bulkBefore, instructions))
local measure = os.getenv("SUITE_MENU_DISCOVERY_MEASURE")
if not measure then
    Check((calls.discovery or 0) == 0, "unchanged tree repeated discovery")
    -- 2026-11-26: a recorded frame keeps its object type and HookScript, so a
    -- warm pass reads forbidden twice and protection once per record (before:
    -- 22,995 forbidden and 5,694 type reads, 40,515 scalar checks, ~3.78M VM).
    Check(native.IsForbidden <= 219 * 55, "resize repeated safety checks")
    Check((native.GetObjectType or 0) <= 219, "resize re-read the immutable object type of every record")
    Check(native.GetChildren == 219 * 25, "resize skipped exact child identity verification")
    -- With identical public/secret spies, 219 warm passes used 67,014 native
    -- secrecy checks and ~4.51M VM instructions before batching identity reads.
    Check(scalarChecks - scalarBefore + bulkChecks - bulkBefore < 32000, "resize secrecy-call budget regressed")
    Check(instructions < 3000000, "resize instruction budget regressed")
end

-- Reopening the same Blizzard panel and re-adopting its current owner still
-- verify child identities without running the provider-discovery walk again.
Reset()
instructions = 0
scalarBefore, bulkBefore = scalarChecks, bulkChecks
debug.sethook(function() instructions = instructions + 100 end, "", 100)
for i = 1, 60 do
    Signal(panel, "OnShow") Drain()
    Check(Menus.Track(panel, owner), "same owner could not re-adopt its panel")
end
debug.sethook()
print(string.format("warm-menu-budget: discovery=%d forbidden=%d protection=%d type=%d children=%d scalar=%d bulk=%d vm~%d",
    calls.discovery or 0, native.IsForbidden or 0, native.IsProtected or 0, native.GetObjectType or 0,
    native.GetChildren or 0, scalarChecks - scalarBefore, bulkChecks - bulkBefore, instructions))
if measure then return end
Check((calls.discovery or 0) == 0, "unchanged show/re-track repeated discovery")
Check(native.GetChildren == 120 * 25, "warm show/re-track missed a child identity check")
-- 2026-11-26 before: 3,180 type and 12,720 forbidden reads, ~2.09M VM.
Check((native.GetObjectType or 0) <= 180 and (native.GetObjectType or 0) < 120 * 25,
    "warm show/re-track re-read the immutable object type of every record")
Check(native.IsForbidden <= 120 * 56, "warm show/re-track repeated forbidden checks per record")
Check(scalarChecks - scalarBefore + bulkChecks - bulkBefore < 18000, "show/re-track secrecy-call budget regressed")
Check(instructions < 1700000, "warm show/re-track instruction budget regressed")
Check(bulkChecks > 0, "warm public field validation never used the native tuple secrecy check")

-- Equal count, different identities: discover the replacement including deeper children.
local replacement, list = Frame(), Frame()
list.GetDataProvider, list.RegisterCallback = Noop, Noop
replacement.children[1] = list
panel.children[12] = replacement
Reset()
Resize(panel)
Check(tracked[list] ~= nil, "same-count replacement was not discovered")
Check((calls.discovery or 0) > 0, "changed tree did not rebuild")
Reset()
Resize(panel)
Check((calls.target or 0) == 2, "existing list did not reconcile its native provider")
Check(not calls.discovery and calls.collections == 1, "stable tree rediscovered ordinary nodes around list")

-- Methods and collection pools can appear on an existing Frame without a child change.
local promoted = panel.children[2]
promoted.GetDataProvider, promoted.RegisterCallback = Noop, Noop
Resize(panel)
Check(tracked[promoted] ~= nil, "late list capabilities were not discovered")
local collection = panel.children[3]
collection.headerFramePool, collection.titleFramePool = {}, {}
Resize(panel)
Check(tracked[collection] ~= nil, "late collection capabilities were not discovered")

-- New Content with the same child list must be watched; denied bodies can recover.
local body = Frame()
panel.Content = body
Resize(panel)
Check(tracked[body] == owner, "late content body not watched")
body.protected = true
Resize(panel)
body.protected = false
Resize(panel)
Check(body.hooks.OnSizeChanged ~= nil, "unprotected body was not observed")
local oldBody = body
body = Frame()
panel.Content = body
Resize(panel)
Reset() Resize(oldBody)
Check(not native.GetChildren and not calls.discovery, "retired body kept invalidating menu")

local blocked = Frame()
blocked.protected = true
blocked.children[1] = Frame()
blocked.children[1].GetDataProvider, blocked.children[1].RegisterCallback = Noop, Noop
panel.children[7] = blocked
Resize(panel)
Check(not tracked[blocked.children[1]], "protected subtree was discovered")
blocked.protected = false
Resize(panel)
Check(tracked[blocked.children[1]] ~= nil, "protection recovery did not discover subtree")
blocked.forbidden = true
Resize(panel)
blocked.forbidden = false
Resize(panel)

-- Secret shape/children/protection results invalidate reuse, never compare as identities.
panel.Content = secret
Resize(panel)
Reset() Resize(panel)
Check((calls.discovery or 0) > 10, "secret content identity was cached")
panel.Content = body
panel.children[24] = secret
Resize(panel)
panel.children[24] = Frame()
panel.children[24].secretProtection = true
Resize(panel)
panel.children[24].secretProtection = false
Resize(panel)
panel.children[24].secretKind = true
Resize(panel)
panel.children[24].secretKind = false
Resize(panel)

-- A hidden/forbidden/tooltip root never touches descendants. Show always rechecks.
do
    local window, child, lease = Frame(), Frame(), {}
    window.Content = child
    Menus.Track(window, lease)
    Signal(child, "OnSizeChanged")
    Check(next(jobs) ~= nil, "visible content failed to schedule discovery")
    window.visible = false
    Signal(window, "OnHide")
    Check(not next(jobs), "last close left a menu discovery job pending")
    for i = 1, 100 do Signal(child, "OnSizeChanged") end
    Check(not next(jobs), "hidden descendants scheduled discovery")
    local nextChild = Frame()
    nextChild.GetDataProvider, nextChild.RegisterCallback = Noop, Noop
    window.children[1], window.visible = nextChild, true
    Signal(window, "OnShow")
    Drain()
    Check(tracked[nextChild] ~= nil, "reopening missed a new dynamic child after cancel")
    Menus.Release(lease) Drain()
end
-- Blizzard can notify a hidden body attached to an open root, and a pooled
-- body can move directly between two open windows before either resizes.
do
    local first, second, body, lease, secondLease = Frame(), Frame(), Frame(), {}, {}
    local parent = first
    function body:GetParent() return parent end
    first.Content = body
    Menus.Track(first, lease)
    Menus.Track(second, secondLease)
    first.visible = false
    Signal(first, "OnSizeChanged")
    Check(not next(jobs), "resize preceded the hidden root notification and queued work")
    first.visible = true
    body.visible = false
    Reset()
    for i = 1, 3 do Signal(body, "OnSizeChanged") end
    Check(not next(jobs) and not calls.discovery, "hidden content under an open menu scheduled a resize scan")
    body.visible = true
    first.Content, second.Content, parent = nil, body, second
    Check(Menus.OwnerFor(body) == secondLease, "pooled body retained its old menu owner")
    Signal(second, "OnSizeChanged") Drain()
    local pendingFirst, pendingSecond = Menus.states[first].scan, Menus.states[second].scan
    Signal(body, "OnSizeChanged")
    Check(not jobs[pendingFirst] and jobs[pendingSecond], "pooled body scheduled the wrong visible menu")
    Drain()
    first.visible = false
    Signal(first, "OnHide")
    body.visible = false
    Signal(body, "OnSizeChanged")
    Check(not next(jobs), "hidden pooled body woke its visible or its closed menu")
    body.visible = true
    Signal(body, "OnShow")
    Check(not jobs[pendingFirst] and jobs[pendingSecond], "shown pooled body did not refresh the current menu")
    Drain()
    Menus.Release(lease) Menus.Release(secondLease) Drain()
end
panel.visible = false
Reset()
for i = 1, 30 do Resize(panel) end
Check((native.GetChildren or 0) == 0 and not calls.target, "hidden root refreshed descendants")
local reopenedList = Frame()
reopenedList.GetDataProvider, reopenedList.RegisterCallback = Noop, Noop
panel.children[4] = reopenedList
panel.visible = true
Signal(panel, "OnShow") Drain()
Check((native.GetChildren or 0) > 0 and (calls.target or 0) > 0, "show did not verify children and reconcile targets")
Check(tracked[reopenedList] ~= nil, "show missed a same-count replacement made while hidden")
reopenedList.protected = true
Reset()
Signal(panel, "OnShow") Drain()
Check((calls.discovery or 0) > 0, "show retained a discovery snapshot after a protection change")
reopenedList.protected = false
local reopenedBody = Frame()
panel.Content = reopenedBody
Signal(panel, "OnShow") Drain()
Check(tracked[reopenedBody] == owner, "show missed a replaced content body")
panel.Content = body
Resize(panel)
panel.forbidden = true
Reset() Resize(panel)
Check(not native.GetChildren, "forbidden root refreshed descendants")
panel.forbidden = false
local tooltip = Frame("GameTooltip")
Check(not Menus.Track(tooltip, owner), "tooltip adopted")
local compositor = Frame()
compositor.AttachTexture, compositor.AttachFontString = Noop, Noop
compositor.AttachFrame, compositor.AttachTemplate = Noop, Noop
compositor.GetObjectType = function() error("compositor method inspected") end
Check(not Menus.Track(compositor, owner), "compositor adopted")
combat = true
local coldCombat = Frame()
Check(Menus.Track(coldCombat, "combat-discovery"), "safe new root refused in combat")
Menus.Release("combat-discovery", coldCombat)
coldCombat.protected = true
Check(not Menus.Track(coldCombat, "protected-combat"), "protected new root adopted in combat")
combat = false

-- A queued resize and show can share a verification. A same-count replacement
-- still invalidates that snapshot, and profile/owner transitions remain cold.
local shownList = Frame()
shownList.GetDataProvider, shownList.RegisterCallback = Noop, Noop
panel.children[5] = shownList
Reset()
Signal(panel, "OnSizeChanged") Signal(panel, "OnShow") Drain()
Check(tracked[shownList] ~= nil, "queued resize and show missed a replacement list")
Reset()
listeners[Menus](Menus, "profile") Drain()
Check((calls.discovery or 0) > 10, "profile change reused discovery")
local owner2 = {}
Menus.Track(panel, owner2)
Check(tracked[body] == owner2, "new owner missed content watch")
Menus.Release(owner2, panel) Drain()
Check(tracked[body] == owner, "release did not hand content back")
Menus.Release(owner, panel)
Reset() Resize(panel)
Check(not calls.discovery and not native.GetChildren, "released root kept work")
Menus.Track(panel, owner)
Check(tracked[body] == owner, "reacquire lost content")

local nestedRoot, nestedList, nestedOwner = Frame(), Frame(), {}
nestedList.GetDataProvider, nestedList.RegisterCallback = Noop, Noop
nestedRoot.children[1] = nestedList
nestedRoot.children[2] = Frame()
nestedRoot.children[2].GetDataProvider, nestedRoot.children[2].RegisterCallback = Noop, Noop
local normalTrack, nestedOnce = NS.ResultMotion.Track, false
NS.ResultMotion.Track = function(frame, lease)
    normalTrack(frame, lease)
    if not nestedOnce then nestedOnce = true Menus.Track(nestedRoot, nestedOwner) end
end
Menus.Track(nestedRoot, nestedOwner)
Drain()
NS.ResultMotion.Track = normalTrack
Reset() Resize(nestedRoot)
Check(calls.target == 4, "reentrant discovery duplicated target ownership")
Menus.Release(nestedOwner)

local releaseRoot, releaseOwner = Frame(), {}
local releaseList = Frame()
releaseList.GetDataProvider, releaseList.RegisterCallback = Noop, Noop
releaseRoot.children[1] = releaseList
NS.ResultMotion.Track = function(frame, lease)
    normalTrack(frame, lease)
    Menus.Release(releaseOwner, releaseRoot)
end
Menus.Track(releaseRoot, releaseOwner)
NS.ResultMotion.Track = normalTrack
Drain()
Check(not tracked[releaseList], "release during discovery retained a target")
Menus.Track(releaseRoot, releaseOwner)
Reset() Resize(releaseRoot)
Check(calls.target == 2, "release during discovery broke reacquisition")
Menus.Release(releaseOwner)

-- A provider error cannot leave a reusable partial snapshot.
local original = NS.ResultMotion.Track
NS.ResultMotion.Track = function() error("injected provider failure") end
local beforeErrors = reportedErrors
Menus.Track(panel, owner)
Check(reportedErrors == beforeErrors + 1, "provider failure was not exercised")
NS.ResultMotion.Track = original
Reset() Resize(panel)
Check((calls.discovery or 0) > 0, "failed discovery reused partial snapshot")

-- Over-budget discovery must stay bounded and must not trust a partial tree.
local large = Frame()
for i = 1, 520 do large.children[i] = Frame() end
Reset() Menus.Track(large, {})
Check((calls.discovery or 0) <= 480, "discovery exceeded node budget")
Reset() Resize(large)
Check((calls.discovery or 0) > 0 and calls.discovery <= 480, "partial budget reused tree")
local denied = Frame()
for i = 1, 480 do denied.children[i] = Frame() denied.children[i].protected = true end
Menus.Track(denied, {})
local late = denied.children[480]
late.protected, late.GetDataProvider, late.RegisterCallback = false, Noop, Noop
Resize(denied)
Check(tracked[late] ~= nil, "record-budget overflow hid a recovered child")
do
    local window, lease = Frame(), {}
    window.Content = secret
    Menus.Track(window, lease)
    local state = Menus.states[window]
    Check(not state.reusable and state.length == 0, "secret content identity was cached")
    Menus.Release(lease, window)
end
do
    -- A native secret may replace an existing public value. In Lua 5.1
    -- matching metatables let the fixture detect even attempting equality.
    local window, lease = Frame(), {}
    local identity = { __eq = function() error("native secret was compared") end }
    window.GetScrollChild = setmetatable({}, identity)
    Menus.Track(window, lease)
    local errors = reportedErrors
    setmetatable(secret, identity)
    window.GetScrollChild = secret
    Resize(window)
    setmetatable(secret, nil)
    Check(reportedErrors == errors, "warm snapshot compared a secret identity")
    Menus.Release(lease, window)
end
do
    local function CheckSecretSlot(slot)
        local window, lease = Frame(), {}
        local identity = { __eq = function() error("restricted identity comparison") end }
        local holder = slot == 7 and window.children or window
        if slot == 7 then for i = 1, 6 do holder[i] = Frame() end end
        holder[slot] = setmetatable(Frame(), identity)
        Menus.Track(window, lease)
        local errors = reportedErrors
        setmetatable(secret, identity)
        holder[slot] = secret
        Resize(window)
        setmetatable(secret, nil)
        Check(reportedErrors == errors and not Menus.states[window].reusable, "late secret slot escaped validation: " .. slot)
        Menus.Release(lease, window)
    end
    CheckSecretSlot("communityChannelButtonPool")
    CheckSecretSlot("PanelContainer")
    CheckSecretSlot(7)
end
do
    local window, child, lease = Frame(), Frame(), {}
    window.children[1] = child
    Menus.Track(window, lease)
    -- The final dynamic body field can change access before GetChildren.
    setmetatable(child, { __index = function(self, key)
        if key == "PanelContainer" then self.forbidden = true end
    end })
    local errors = reportedErrors
    Resize(window)
    Check(child.forbidden and reportedErrors == errors, "GetChildren ignored a fresh forbidden answer")
    Menus.Release(lease, window)
end
local deep, cursor = Frame()
cursor = deep
for i = 1, 8 do cursor.children[1] = Frame() cursor = cursor.children[1] end
cursor.children[1] = Frame()
cursor.children[1].GetDataProvider, cursor.children[1].RegisterCallback = Noop, Noop
Reset() Menus.Track(deep, {})
Check(native.GetChildren == 8, "depth boundary enumerated unused descendants")
Check(not tracked[cursor.children[1]], "depth boundary discovered an excluded target")
Reset() Resize(deep)
Check(native.GetChildren == 8 and not calls.discovery, "depth boundary invalidated stable tree")
local deepBody = Frame()
cursor.Content = deepBody
Resize(deep)
Check(tracked[deepBody] ~= nil, "depth boundary lost an eligible body")
Check(reportedErrors == 1, "unexpected provider error was swallowed")
do
    local window, first, last, lease = Frame(), Frame(), Frame(), {}
    local middle = Frame()
    function window:GetChildren() return first, middle, last end
    Menus.Track(window, lease)
    middle = nil
    Resize(window)
    Reset() Resize(window)
    Check(not calls.discovery, "an absent middle child stayed in a sparse snapshot")
    middle = Frame()
    middle.GetDataProvider, middle.RegisterCallback = Noop, Noop
    Resize(window)
    Check(tracked[middle], "replacement in a sparse tuple was missed")
    Menus.Release(lease) Drain()
end
do
    local window, pane, extra, lease, visibleList = Frame(), Frame(), Frame(), {}, Frame()
    visibleList.GetDataProvider, visibleList.RegisterCallback = Noop, Noop
    window.MemberList, window.children[1], window.children[2] = pane, pane, extra
    function pane:IsShown() return self.visible end
    function pane:GetParent() return window end
    pane.visible = false
    for i = 1, 205 do pane.children[i], extra.children[i] = Frame(), Frame() end
    extra.children[1] = visibleList
    local oldAdapter, oldClient, oldCommunities = NS.CommunitiesSkin, NS.Client, CommunitiesFrame
    CommunitiesFrame = window
    Load("Adapters/Communities.lua")
    local nativeList, alternateList = Frame(), Frame()
    pane.ScrollBox, extra.ScrollBox = nativeList, alternateList
    local oldResults = NS.ResultMotion.states
    NS.ResultMotion.states = { [nativeList] = { registered = true }, [alternateList] = { registered = true } }
    NS.CommunitiesSkin.activeState = { active = true, frame = window, scrollBoxes = { [nativeList] = {}, [alternateList] = {} } }
    NS.Client = { isForever = flavor == "Forever" }
    Reset()
    Menus.Track(window, lease)
    local first = native.GetChildren
    if NS.Client.isForever then
        Check(first == 206, "hidden authored Communities pane was traversed on first open")
        Check(not pane.hooks.OnSizeChanged, "closed Communities pane bound a resize observer")
        NS.ResultMotion.states[nativeList].registered = false
        Reset() Resize(window)
        Check(native.GetChildren >= 412, "unbound native Communities list was pruned")
        NS.ResultMotion.states[nativeList].registered = true
        Resize(window)
        local late = Frame()
        late.GetDataProvider, late.RegisterCallback = Noop, Noop
        pane.children[205] = late
        Reset()
        for i = 1, 20 do Resize(pane) end
        Check(not native.GetChildren and not calls.collections and not next(jobs), "hidden pane scheduled discovery")
        Check(tracked[visibleList] ~= nil and not tracked[late], "unknown menu branch skipped native provider discovery")
        local extraReads = 0
        local extraChildren = extra.GetChildren
        function extra:GetChildren() extraReads = extraReads + 1 return extraChildren(self) end
        window.visible = false
        Signal(window, "OnHide")
        window.visible, pane.visible = true, true
        Reset()
        Signal(pane, "OnShow")
        Check(tracked[late] ~= nil, "child-before-parent show missed the first visible list")
        Check(extraReads == 0 and native.GetChildren <= 205, "first pane show synchronously walked a sibling")
        Signal(window, "OnShow") Drain()
        pane.visible = false
        Resize(window)
        pane.visible = true
        extraReads = 0
        Reset()
        for index = 1, 5 do Signal(pane, "OnShow") end
        Check(not native.GetChildren and extraReads == 0, "warm pane shows walked the window synchronously")
        Drain()
        Check(not calls.discovery, "warm pane shows caused fresh root discovery")
        pane.visible = false
        Resize(window)
        local inner = Frame()
        inner.GetDataProvider, inner.RegisterCallback = Noop, Noop
        pane.children[205] = inner
        window.MemberList = extra
        Resize(window)
        Check(tracked[inner] ~= nil, "changed authored parentKey left an unknown branch deferred")
        -- A retained parentKey must not make a detached/reparented pane
        -- or a newly protected direct child schedule perpetual rebuilding.
        extra.visible = false
        function extra:IsShown() return self.visible end
        function extra:GetParent() return window end
        Resize(window)
        extra.protected = true
        Resize(window)
        Reset() Resize(window)
        Check(not calls.discovery, "inaccessible pane forced perpetual discovery")
        extra.protected = false
        Resize(window)
        window.children[2] = Frame()
        Resize(window)
        extra.visible = true
        Reset() Resize(window)
        Check(not calls.discovery, "detached pane invalidated an unchanged visible tree")
        Menus.Release(lease, window) Drain()
        Reset()
        Signal(pane, "OnShow")
        Check(not calls.discovery and not next(jobs), "released Communities pane scheduled work")
        print("Communities split discovery: " .. first .. " child queries on initial show, zero on 20 hidden resizes")
    else
        Check(first == 412, "Retail Communities generic discovery changed")
    end
    Menus.Release(lease) Drain()
    NS.ResultMotion.states = oldResults
    NS.CommunitiesSkin, NS.Client, CommunitiesFrame = oldAdapter, oldClient, oldCommunities
end
if flavor == "Forever" then
    local window, sibling, owner = Frame(), Frame(), {}
    local oldAdapter, oldClient, oldRoot = NS.CommunitiesSkin, NS.Client, CommunitiesFrame
    Load("Adapters/Communities.lua")
    NS.Client, CommunitiesFrame = { isForever = true }, window
    NS.CommunitiesSkin.activeState = { frame = window, active = true, scrollBoxes = {} }
    window.children[1] = sibling
    local siblingReads, getChildren = 0, sibling.GetChildren
    function sibling:GetChildren() siblingReads = siblingReads + 1 return getChildren(self) end
    local panes, lists = {}, {}
    for index, key in ipairs({ "InvitationFrame", "TicketFrame", "GuildNameChangeFrame" }) do
        local pane, list = Frame(), Frame()
        function pane:IsShown() return self.visible end
        function pane:GetParent() return window end
        list.GetDataProvider, list.RegisterCallback = Noop, Noop
        pane.visible, pane.children[1] = false, list
        window[key], window.children[index + 1], panes[index], lists[index] = pane, pane, pane, list
    end
    Menus.Track(window, owner)
    siblingReads = 0
    local nativeTrack = NS.ResultMotion.Track
    NS.ResultMotion.Track = function(target, lease)
        nativeTrack(target, lease)
        if target == lists[1] then
            panes[2].visible = true
            Signal(panes[2], "OnShow")
        end
    end
    Reset()
    panes[1].visible = true
    Signal(panes[1], "OnShow")
    panes[3].visible = true
    Signal(panes[3], "OnShow")
    NS.ResultMotion.Track = nativeTrack
    Check(tracked[lists[1]] and tracked[lists[2]] and tracked[lists[3]], "reentrant pane show lost a late native target")
    Check(siblingReads == 0 and native.GetChildren == 3, "three pane shows repeated root or sibling work")
    Reset()
    for _, pane in ipairs(panes) do Signal(pane, "OnShow") end
    local jobsBefore = 0
    for _ in pairs(jobs) do jobsBefore = jobsBefore + 1 end
    Check(jobsBefore == 1 and not calls.discovery and not native.GetChildren, "warm pane signals did not coalesce")
    Drain()
    Check(not calls.discovery and siblingReads == 1, "coalesced pane verification rebuilt the root")
    print("Three pane shows: 3 local subtree queries, 0 unrelated sibling queries; repeated shows: 1 coalesced verification")
    Menus.Release(owner, window) Drain()
    -- Neither the parent nor a named body fires a script for this change.
    local budgetRoot, first, second, lease = Frame(), Frame(), Frame(), {}
    CommunitiesFrame = budgetRoot
    NS.CommunitiesSkin.activeState = { frame = budgetRoot, active = true, scrollBoxes = {} }
    budgetRoot.InvitationFrame, budgetRoot.TicketFrame = first, second
    budgetRoot.children = { first, second }
    for _, pane in ipairs(budgetRoot.children) do
        function pane:GetParent() return budgetRoot end
        function pane:IsShown() return self.visible end
        for index = 1, 250 do pane.children[index] = Frame() end
    end
    second.visible = false
    Menus.Track(budgetRoot, lease)
    first.visible = false
    local later = Frame()
    later.GetDataProvider, later.RegisterCallback = Noop, Noop
    first.children[250] = later
    first.visible = true
    Reset()
    Signal(first, "OnShow")
    Check(not native.GetChildren, "initially visible pane synchronously scanned the window on its next show")
    Drain()
    Check(tracked[later], "initially visible pane missed a child inserted while hidden")
    first.visible, second.visible = false, true
    local last = second.children[250]
    last.GetDataProvider, last.RegisterCallback = Noop, Noop
    Reset()
    Signal(second, "OnShow")
    Check(not Menus.states[budgetRoot].reusable, "combined hidden and visible panes did not reach the aggregate budget")
    Resize(budgetRoot)
    Check(Menus.states[budgetRoot].reusable and tracked[last],
        "genuine root rebuild spent its budget on an already visited hidden pane")
    Reset() Resize(budgetRoot)
    Check(not calls.discovery, "alternating panes repeatedly exhausted the aggregate budget")
    print("Two 250-child panes: originally visible pane handles its next OnShow; cold rebuild recovers the full visible pane")
    Menus.Release(lease, budgetRoot) Drain()
    local function InterruptedPane(exhaustBudget)
        local root, page, other, lease = Frame(), Frame(), Frame(), {}
        CommunitiesFrame = root
        NS.CommunitiesSkin.activeState = { frame = root, active = true, scrollBoxes = {} }
        root.InvitationFrame, root.children[1], root.children[2] = page, page, other
        function page:GetParent() return root end
        function page:IsShown() return self.visible end
        page.visible = false
        for i = 1, 3 do
            local list = Frame()
            list.GetDataProvider, list.RegisterCallback = Noop, Noop
            page.children[i] = list
        end
        if exhaustBudget then
            for i = 1, 476 do
                local child = Frame()
                if exhaustBudget == "edges" then child.protected = true end
                other.children[i] = child
            end
        end
        Menus.Track(root, lease)
        local state = Menus.states[root]
        Check(state.reusable, "pane budget/error test did not begin with a complete snapshot")
        local visits, getter = 0, other.GetChildren
        function other:GetChildren() visits = visits + 1 return getter(self) end
        local errorsBefore = reportedErrors
        if not exhaustBudget then NS.ResultMotion.Track = function() error("pane provider failure") end end
        page.visible = true
        Signal(page, "OnShow")
        NS.ResultMotion.Track = nativeTrack
        Check(not state.reusable and not state.scanning and visits == 0,
            "incomplete pane append trusted partial data or synchronously rebuilt the root")
        if exhaustBudget then
            if exhaustBudget == "edges" then
                Check(state.edges > 480 and state.budget > 0, "pane append did not exercise a separate edge overflow")
            else
                Check(state.budget == 0 and not tracked[page.children[3]], "pane append exceeded its remaining node budget")
            end
            wipe(other.children)
        else
            Check(reportedErrors == errorsBefore + 1, "native pane provider error was not reported")
        end
        Resize(root)
        Check(state.reusable and tracked[page.children[3]] and visits == 1, "later root notification did not recover interrupted pane")
        Menus.Release(lease, root) Drain()
    end
    InterruptedPane("nodes")
    InterruptedPane("edges")
    InterruptedPane(false)
    NS.CommunitiesSkin, NS.Client, CommunitiesFrame = oldAdapter, oldClient, oldRoot
end
ReviewCases()
local ownerProbeRoot = Frame()
local ownerProbeWeak = setmetatable({}, { __mode = "v" })
local function OwnerProbe()
    local lease = {}
    ownerProbeWeak[1] = lease
    Menus.Track(ownerProbeRoot, lease)
    Menus.Release(lease, ownerProbeRoot)
end
OwnerProbe()
collectgarbage("collect")
Check(ownerProbeWeak[1] == nil, "released owner remained in discovery cache")
print(string.format("Menu discovery contract: %d checks (%s)", checks, flavor))

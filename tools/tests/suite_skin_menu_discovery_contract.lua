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
issecretvalue = function(value) return value == secret end
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
Load("Core/Safety.lua")
Load("Rendering/CollapseCollections.lua")
local collectionTrack = NS.CollapseCollections.Track
NS.CollapseCollections.Track = function(frame, owner)
    calls.discovery = (calls.discovery or 0) + 1
    return collectionTrack(frame, owner)
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
debug.sethook(function() instructions = instructions + 100 end, "", 100)
for i = 1, 219 do Resize(panel) end
debug.sethook()
print(string.format("resize-budget: discovery=%d forbidden=%d protection=%d type=%d children=%d vm~%d",
    calls.discovery or 0, native.IsForbidden or 0, native.IsProtected or 0,
    native.GetObjectType or 0, native.GetChildren or 0, instructions))
if os.getenv("SUITE_MENU_DISCOVERY_MEASURE") then return end
Check((calls.discovery or 0) == 0, "unchanged tree repeated discovery")
Check(native.IsForbidden <= 219 * 110, "resize repeated safety checks")
Check(native.GetChildren == 219 * 25, "resize skipped exact child identity verification")
-- Runtime instruction cap is filled from the immutable old-code comparison.
-- Immutable old code: 12,828,300 VM instructions including widget spies.
-- Accepted trade: ~23.2 KiB additional cold storage for this 25-node snapshot,
-- bounded to 480 nodes/edges, plus one error boundary per scan. Warm allocations
-- are unchanged in the two-run allocation probe. Native calls count separately.
Check(instructions < 6000000, "resize instruction budget regressed")

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
Check(calls.discovery == 1, "stable tree rediscovered ordinary nodes around list")

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
panel.visible = false
Reset()
for i = 1, 30 do Resize(panel) end
Check((native.GetChildren or 0) == 0 and not calls.target, "hidden root refreshed descendants")
panel.visible = true
Signal(panel, "OnShow") Drain()
Check((calls.discovery or 0) > 10, "show did not rediscover")
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
Check(not Menus.Track(Frame(), owner), "new root adopted in combat")
combat = false

-- Show beats an already queued resize; profile/adapter and owner transitions are cold.
Reset()
Signal(panel, "OnSizeChanged") Signal(panel, "OnShow") Drain()
Check((calls.discovery or 0) > 10, "queued resize swallowed show invalidation")
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

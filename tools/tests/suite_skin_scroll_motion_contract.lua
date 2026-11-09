-- Native ScrollController/ScrollUtil callback semantics, including thumb drag.
local root = assert(arg[1])
local checks, allocations, positions, scriptWrites = 0, 0, 0, 0
local function Check(value, message) checks = checks + 1 assert(value, message) end
local function Noop() end
local secret = {}
issecretvalue = function(value) return value == secret end
securecallfunction = function(callback, ...) return callback(...) end
local combat = false
InCombatLockdown = function() return combat end
local frames = {}
local function Frame()
    local frame = { hooks = {}, callbacks = {}, scripts = {}, events = {}, shown = true }
    frames[#frames + 1] = frame
    function frame:IsVisible() return self.shown end
    function frame:IsForbidden() return self.forbidden == true end
    function frame:IsProtected() return self.protected == true, self.protected == true end
    function frame:HookScript(event, callback)
        self.hooks[event] = self.hooks[event] or {}
        self.hooks[event][#self.hooks[event] + 1] = callback
    end
    function frame:SetScript(event, callback)
        if self.native then scriptWrites = scriptWrites + 1 end
        self.scripts[event] = callback
    end
    function frame:RegisterEvent(event) self.events[event] = true end
    function frame:Fire(event, ...)
        if event == "OnShow" then self.shown = true elseif event == "OnHide" then self.shown = false end
        if self.scripts[event] then self.scripts[event](self, ...) end
        for _, callback in ipairs(self.hooks[event] or {}) do callback(self, ...) end
    end
    function frame:RegisterCallback(event, callback, owner)
        self.callbacks[event] = self.callbacks[event] or {}
        self.callbacks[event][owner] = callback
    end
    function frame:UnregisterCallback(event, owner)
        if self.callbacks[event] then self.callbacks[event][owner] = nil end
    end
    function frame:Trigger(event, ...)
        -- CallbackRegistry passes the owner, then only the explicit payload.
        -- EventButton emits buttonName (and upInside on mouse up), no frame.
        for owner, callback in pairs(self.callbacks[event] or {}) do callback(owner, ...) end
    end
    return frame
end
CreateFrame = Frame
hooksecurefunc = function(target, method, callback)
    local original = target[method]
    target[method] = function(self, ...)
        original(self, ...)
        callback(self, ...)
    end
end
local listeners, providers = {}, {}
ScrollBoxListMixin = { Event = { OnLayout = "layout", OnScroll = "scroll" } }
local NS = { DB = { enabled = true, theme = {} }, Motion = { combat = false },
    IsCombatLocked = InCombatLockdown, Client = { isForever = arg[2] == "Forever" },
    Registry = { AddListener = function(owner, callback) listeners[owner] = callback end },
    GenericWindows = { SetScrollMotionProvider = function(track, release) providers.generic = { track, release } end },
    ScrollBarSkin = { SetScrollMotionProvider = function(track, release) providers.bar = { track, release } end } }
local function Load(file)
    local path = root .. "/MSUF_Suite_Skin/" .. file
    local override = os.getenv("SUITE_SCROLL_OVERRIDE_ROOT")
    if override then
        local candidate = override .. "/" .. file
        local handle = io.open(candidate, "rb")
        if handle then handle:close() path = candidate end
    end
    assert(loadfile(path))("MSUF_Suite_Skin", NS)
end
Load("Core/Safety.lua")
Load("Rendering/ScrollMotion.lua")
local Motion = NS.ScrollMotion
local function Changed(key)
    listeners[Motion](Motion, "motion", key or "smoothScrolling")
end
local function Controller(original, thumb)
    local controller = Frame()
    controller.native, controller.canInterpolateScroll, controller.position = true, original, 0
    function controller:CanInterpolateScroll() return self.canInterpolateScroll end
    function controller:SetInterpolateScroll(value) self.canInterpolateScroll = value end
    function controller:GetScrollPercentage() return self.position end
    function controller:GetScrollInterpolator()
        if not self.interpolator then
            allocations = allocations + 1
            local interpolator = { starts = 0, cancels = 0 }
            function interpolator:GetInterpolateTo() return self.destination end
            function interpolator:Cancel() self.destination = nil self.cancels = self.cancels + 1 end
            self.interpolator = interpolator
        end
        return self.interpolator
    end
    function controller:Interpolate(value)
        local interpolator = self:GetScrollInterpolator()
        interpolator.starts, interpolator.destination = interpolator.starts + 1, value
        -- The real Interpolator runs its setter once before scheduling ticks.
        self:SetScrollPercentageInternal(self.position + (value - self.position) * 0.1)
    end
    function controller:SetScrollPercentageInternal(value)
        positions = positions + 1
        self.position = value
        if self.legacy then self.legacy.offset = value * 1000 end
        if self.registeredScrollBar then self.registeredScrollBar:SetScrollPercentage(value, true)
        elseif self.registeredScrollBox then self.registeredScrollBox:SetScrollPercentage(value, true) end
    end
    function controller:SetScrollPercentage(value, immediate)
        if not self.thumb and self.position == value then return end
        if not immediate and self:CanInterpolateScroll() then
            self:Interpolate(value)
        else
            self:SetScrollPercentageInternal(value)
        end
    end
    if thumb then
        controller.thumb = Frame()
        function controller:GetThumb() return self.thumb end
        function controller:IsThumbMouseDown() return self.thumb.down == true end
    else
        function controller:GetView() return self.view end
        function controller:ScrollToOffset(offset, immediate) self:SetScrollPercentage(offset / 1000, immediate) end
        function controller:ScrollToBegin(immediate) self:SetScrollPercentage(0, immediate) end
        function controller:ScrollToEnd(immediate) self:SetScrollPercentage(1, immediate) end
    end
    return controller
end
local box, bar = Controller(nil), Controller(false, true)
box.registeredScrollBar, bar.registeredScrollBox = bar, box
Check(providers.generic[1](box, "addonList"), "native AddonList ScrollBox not adopted")
Check(box.canInterpolateScroll == true and bar.canInterpolateScroll == true, "native pair was not enabled coherently")
Check(allocations == 0 and scriptWrites == 0, "adoption allocated a cold interpolator or replaced native scripts")
box:SetScrollPercentage(0.6)
Check(box.position > 0 and box.position < 0.6 and box.interpolator.destination == 0.6,
    "scrolling snapped instead of using native interpolation")
box.position = 0.2 -- A native interpolation tick has progressed partway.
bar:SetScrollPercentage(0.7)
Check(box.interpolator.destination == nil and bar.interpolator.destination == 0.7,
    "wheel source switching left two interpolators driving the same pair")
bar.thumb.down = true
bar.thumb:Trigger("OnMouseDown", "LeftButton")
Check(not box.canInterpolateScroll and not bar.canInterpolateScroll
    and box.interpolator.destination == nil and bar.interpolator.destination == nil,
    "thumb down left an interpolator competing with direct dragging")
local starts = bar.interpolator.starts
bar:SetScrollPercentage(0.35) -- Native thumb OnUpdate does not pass forceImmediate.
Check(bar.position == 0.35 and bar.interpolator.starts == starts, "thumb dragging lagged behind the cursor")
bar.thumb.down = false
bar.thumb:Trigger("OnMouseUp", "LeftButton")
Check(box.canInterpolateScroll and bar.canInterpolateScroll, "thumb release failed to restore smooth wheel input")
bar.thumb:Trigger("OnMouseDown", "LeftButton")
bar:Fire("OnHide")
bar:Fire("OnShow")
Check(box.canInterpolateScroll and bar.canInterpolateScroll, "hide during a drag left the pair stuck in immediate mode")
box:SetScrollPercentage(0.9)
box:SetScrollPercentage(0.15, true) -- Native provider/layout correction.
box:Trigger("layout")
Check(box.interpolator.destination == nil and box.position == 0.15,
    "native layout correction retained an old target that could undo search/resize")
box:SetScrollPercentage(0.9)
box:ScrollToOffset(200, true)
Check(box.interpolator.destination == nil and box.position == 0.2,
    "explicit immediate jump kept a stale interpolation")
box:SetScrollPercentage(0.9)
box:ScrollToBegin(true)
Check(box.interpolator.destination == nil and box.position == 0, "scroll-to-begin resumed an old target")
box:SetScrollPercentage(0.9)
box:ScrollToEnd(true)
Check(box.interpolator.destination == nil and box.position == 1, "scroll-to-end resumed an old target")
bar:SetScrollPercentage(0.8)
NS.DB.theme.smoothScrolling = false
Changed()
Check(not box.canInterpolateScroll and not bar.canInterpolateScroll and bar.position == 0.8
    and bar.interpolator.destination == nil, "disabling in flight did not stop and settle the native target")
box:SetScrollPercentage(0.4)
Check(box.position == 0.4, "disabled scrolling did not stay immediate")
NS.DB.theme.smoothScrolling = nil
Changed()
Check(box.canInterpolateScroll and bar.canInterpolateScroll, "default smooth scrolling did not return")
NS.DB.theme.reduceMotion = true
Changed("reduceMotion")
Check(not box.canInterpolateScroll and not bar.canInterpolateScroll, "reduced motion did not disable smooth scrolling")
NS.DB.theme.reduceMotion = nil
NS.DB.theme.menuAnimations = false
Changed("reduceMotion")
Check(box.canInterpolateScroll and bar.canInterpolateScroll, "smooth scrolling incorrectly depends on decorative menu animations")
bar:SetScrollPercentage(0.9)
local before = positions
bar:Fire("OnHide")
Check(bar.interpolator.destination == nil and positions == before, "hidden scroller wrote position or continued moving")
bar:Fire("OnShow")
-- Paired source leases and owner leases may overlap without early restore.
Check(providers.bar[1](bar, "addonList"), "verified native scrollbar did not opt in")
Check(Motion.Track(box, "second"), "second owner could not share the scroll controller")
providers.generic[2]("addonList")
Check(box.canInterpolateScroll and bar.canInterpolateScroll, "one owner removed another owner's interpolation")
Motion.ReleaseOwner("second")
Check(box.canInterpolateScroll == nil and bar.canInterpolateScroll == false, "release lost exact nil/false native flags")
Check(not next(bar.thumb.callbacks.OnMouseDown) and not next(bar.thumb.callbacks.OnMouseUp), "thumb callbacks leaked after release")
Check(not next(box.callbacks.layout), "native layout callback leaked after release")
local hooked = #bar.hooks.OnHide
Motion.Track(bar, "addonList")
Motion.Release(bar, "addonList")
Motion.Track(bar, "addonList")
Check(#bar.hooks.OnHide == hooked, "re-enabling duplicated native hooks")
-- Same-value foreign writes transfer ownership too; equality is insufficient.
bar:SetInterpolateScroll(true)
Motion.ReleaseOwner("addonList")
Check(bar.canInterpolateScroll == true and box.canInterpolateScroll == true,
    "same-value foreign setter claim was overwritten on release")
Motion.Track(box, "addonList")
bar:SetInterpolateScroll(false)
listeners[Motion](Motion, "color", "accent")
Check(bar.canInterpolateScroll == false, "an unrelated color refresh reclaimed a foreign flag")
NS.DB.theme.smoothScrolling = true
Changed()
Check(bar.canInterpolateScroll == true, "explicit smooth-scroll enable did not reacquire native settings")
Motion.ReleaseOwner("addonList")
Check(bar.canInterpolateScroll == false, "reacquisition did not retain the foreign baseline")
-- Legacy ScrollFrame support comes from its verified modern scrollbar route.
local legacy = { offset = 0 }
local legacyBar = Controller(false, true)
legacyBar.legacy = legacy
Motion.Track(legacyBar, "legacy")
legacyBar.thumb:Trigger("OnMouseDown", "LeftButton")
legacyBar:SetScrollPercentage(0.25)
Check(legacy.offset == 250, "legacy ScrollFrame callback stopped following its scrollbar")
legacyBar.thumb:Trigger("OnMouseUp", "LeftButton")
legacyBar:SetScrollPercentage(0.6)
before = positions
NS.Motion.combat = true -- Event-derived combat edge precedes lockdown.
for _, frame in ipairs(frames) do
    if frame.events.PLAYER_REGEN_DISABLED then frame:Fire("OnEvent", "PLAYER_REGEN_DISABLED") end
end
Check(legacyBar.canInterpolateScroll and legacyBar.interpolator.destination == 0.6 and positions == before,
    "combat edge stopped safe motion or wrote a scroll position")
legacyBar.protected = true
for _, frame in ipairs(frames) do
    if frame.events.PLAYER_REGEN_DISABLED then frame:Fire("OnEvent", "PLAYER_REGEN_DISABLED") end
end
Check(legacyBar.interpolator.destination == nil and positions == before,
    "unsafe combat edge retained motion or wrote a scroll position")
legacyBar.protected = false
NS.Motion.combat = false
for _, frame in ipairs(frames) do
    if frame.events.PLAYER_REGEN_ENABLED then frame:Fire("OnEvent", "PLAYER_REGEN_ENABLED") end
end
Check(legacyBar.canInterpolateScroll, "combat end did not restore configured scrolling")
legacyBar:SetScrollPercentage(0.8)
legacyBar.interpolator.destination = secret
before = positions
NS.DB.theme.smoothScrolling = false
Changed()
Check(legacyBar.interpolator.destination == nil and positions == before, "secret scroll target was compared or forwarded")
NS.DB.theme.smoothScrolling = nil
Changed()
Motion.ReleaseOwner("legacy")
local cold = Controller(false)
before = allocations
Motion.Track(cold, "cold")
NS.DB.theme.smoothScrolling = false
Changed()
Motion.ReleaseOwner("cold")
Check(allocations == before, "cold disable/restore allocated an interpolator")
NS.DB.theme.smoothScrolling = nil
for _, property in ipairs({ "protected", "forbidden", "compositor" }) do
    local refused = Controller(false)
    if property == "compositor" then
        refused.AttachTexture, refused.AttachFontString, refused.AttachFrame, refused.AttachTemplate = Noop, Noop, Noop, Noop
    else refused[property] = true end
    Check(not Motion.Track(refused, property) and refused.canInterpolateScroll == false,
        property .. " controller was changed")
end
local pairedUnsafe, unsafe = Controller(false), Controller(false)
pairedUnsafe.registeredScrollBar, unsafe.protected = unsafe, true
Check(not Motion.Track(pairedUnsafe, "unsafePair") and not pairedUnsafe.canInterpolateScroll,
    "a safe controller took over an unsafe native pair")
local secretFlag = Controller(secret)
Check(not Motion.Track(secretFlag, "secret") and secretFlag.canInterpolateScroll == secret, "secret native flag was adopted")
Check(Motion.owners.secret == nil, "rejected secret controller retained a lease")
local incomplete = Controller(false)
incomplete.Interpolate = nil
Check(not Motion.Track(incomplete, "incomplete"), "partial native controller was adopted")
local deferred = Controller(false)
Motion.Track(deferred, "deferred")
deferred:SetScrollPercentage(0.75)
deferred.protected = true
deferred:Fire("OnHide")
before = positions
Motion.ReleaseOwner("deferred")
Check(Motion.states[deferred].pending and deferred.interpolator.destination == nil and positions == before,
    "newly protected release did not cancel and defer without position writes")
deferred.protected = false
for _, frame in ipairs(frames) do
    if frame.events.PLAYER_REGEN_ENABLED then frame:Fire("OnEvent", "PLAYER_REGEN_ENABLED") end
end
Check(deferred.canInterpolateScroll == false and not Motion.states[deferred].pending,
    "safe deferred release did not restore the exact native flag")
-- A new owner can reacquire before a previously unsafe restoration retries.
local reacquired = Controller(false)
Motion.Track(reacquired, "old-owner")
reacquired:Fire("OnHide")
reacquired.protected = true
Motion.ReleaseOwner("old-owner")
Check(Motion.states[reacquired].pending, "reacquire fixture did not defer restoration")
reacquired.protected = false
Check(Motion.Track(reacquired, "new-owner"), "new owner could not reacquire the safe controller")
for _, frame in ipairs(frames) do
    if frame.events.PLAYER_REGEN_ENABLED then frame:Fire("OnEvent", "PLAYER_REGEN_ENABLED") end
end
Check(Motion.states[reacquired].captured and not reacquired.canInterpolateScroll,
    "stale deferred restoration revoked a new active lease")
reacquired:Fire("OnShow")
Check(reacquired.canInterpolateScroll, "reacquired controller lost smooth scrolling")
Motion.ReleaseOwner("new-owner")
Check(reacquired.canInterpolateScroll == false, "reacquired controller lost its original native baseline")
-- Visible combat work reads the configuration once and asks
-- each controller IsForbidden twice (Safe), not again for its flag.
do
    local edge, reads = {}, 0
    for i = 1, 8 do
        local controller = Controller(false)
        function controller:IsForbidden() reads = reads + 1 return false end
        Check(Motion.Track(controller, "edge"), "a combat edge controller was refused")
        edge[i] = controller
    end
    local configurationReads = 0
    setmetatable(NS.DB.theme, { __index = function(_, key)
        if key == "smoothScrolling" then configurationReads = configurationReads + 1 end
    end })
    reads = 0
    for _, frame in ipairs(frames) do
        if frame.events.PLAYER_REGEN_ENABLED then frame:Fire("OnEvent", "PLAYER_REGEN_ENABLED") end
    end
    setmetatable(NS.DB.theme, nil)
    Check(configurationReads == 1, "a combat edge read the configuration once per controller")
    Check(reads == 2 * #edge, "a combat edge asked IsForbidden more than twice per controller")
    for i = 1, #edge do Check(edge[i].canInterpolateScroll == true, "a combat edge changed a controller's flag") end
    Motion.ReleaseOwner("edge")
end
-- A parent can scroll a still-hidden child before its OnShow fires in combat.
do
    local hidden = Controller(false)
    Check(Motion.Track(hidden, "combat-hidden"), "hidden combat fixture was refused")
    hidden:Fire("OnHide")
    NS.Motion.combat = true
    for _, frame in ipairs(frames) do
        if frame.events.PLAYER_REGEN_DISABLED then frame:Fire("OnEvent", "PLAYER_REGEN_DISABLED") end
    end
    hidden:SetScrollPercentage(0.8)
    hidden:Fire("OnShow")
    Check(hidden.position == 0.8 and hidden.canInterpolateScroll,
        "hidden controller missed its immediate row or safe combat resume")
    NS.Motion.combat = false
    Motion.ReleaseOwner("combat-hidden")
end
-- A controller unsafe on Hide can become safe again while still hidden.
do
    local late = Controller(false)
    Check(Motion.Track(late, "late-safe"), "late-safe fixture was refused")
    late.protected = true
    late:Fire("OnHide")
    Check(late.canInterpolateScroll, "unsafe hidden controller was written")
    late.protected = false
    NS.Motion.combat = true
    for _, frame in ipairs(frames) do
        if frame.events.PLAYER_REGEN_DISABLED then frame:Fire("OnEvent", "PLAYER_REGEN_DISABLED") end
    end
    late:SetScrollPercentage(0.8)
    Check(late.position == 0.8 and not late.canInterpolateScroll,
        "previously unsafe hidden controller interpolated in combat")
    NS.Motion.combat = false
    Motion.ReleaseOwner("late-safe")
end
-- Preserve cancellation when protection persists across the combat edge.
do
    local stuck = Controller(false)
    Check(Motion.Track(stuck, "still-unsafe"), "still-unsafe fixture was refused")
    stuck.protected = true
    stuck:Fire("OnHide")
    stuck:SetScrollPercentage(0.8)
    Check(stuck.interpolator.destination == 0.8, "fixture failed to restart native interpolation")
    NS.Motion.combat = true
    for _, frame in ipairs(frames) do
        if frame.events.PLAYER_REGEN_DISABLED then frame:Fire("OnEvent", "PLAYER_REGEN_DISABLED") end
    end
    Check(stuck.interpolator.destination == nil,
        "still-unsafe hidden controller retained interpolation across combat entry")
    NS.Motion.combat, stuck.protected = false, false
    Motion.ReleaseOwner("still-unsafe")
end
-- Hidden controllers must leave the combat working set and catch up on show.
do
    local initial = Controller(true)
    initial:Fire("OnHide")
    Check(Motion.Track(initial, "initial-hidden"), "initially hidden controller was refused")
    Check(not initial.canInterpolateScroll, "initially hidden controller was unnecessarily updated")
    initial:Fire("OnShow")
    Check(initial.canInterpolateScroll, "initially hidden controller failed to catch up on show")
    Motion.ReleaseOwner("initial-hidden")
    local hidden, reads, writes = {}, 0, 0
    for i = 1, 32 do
        local controller = Controller(false)
        function controller:IsForbidden() reads = reads + 1 return false end
        local setter = controller.SetInterpolateScroll
        function controller:SetInterpolateScroll(value) writes = writes + 1 setter(self, value) end
        Check(Motion.Track(controller, "hidden-budget"), "hidden fixture was refused")
        controller:Fire("OnHide")
        hidden[i] = controller
    end
    reads, writes = 0, 0
    for _, event in ipairs({ "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED" }) do
        NS.Motion.combat = event == "PLAYER_REGEN_DISABLED"
        for _, frame in ipairs(frames) do
            if frame.events[event] then frame:Fire("OnEvent", event) end
        end
    end
    Check(reads == 0 and writes == 0, "hidden controllers were probed or written at a combat edge")
    NS.Motion.combat = true
    hidden[1]:Fire("OnShow")
    Check(hidden[1].canInterpolateScroll, "safe show in combat lost smooth scrolling")
    NS.Motion.combat = false
    for _, frame in ipairs(frames) do
        if frame.events.PLAYER_REGEN_ENABLED then frame:Fire("OnEvent", "PLAYER_REGEN_ENABLED") end
    end
    Check(hidden[1].canInterpolateScroll, "visible controller missed combat-end recovery")
    hidden[1]:Fire("OnHide")
    NS.DB.theme.smoothScrolling = false
    Changed()
    hidden[2]:Fire("OnShow")
    Check(not hidden[2].canInterpolateScroll, "hidden configuration change was stale on show")
    NS.DB.theme.smoothScrolling = nil
    Changed()
    Motion.ReleaseOwner("hidden-budget")
end
-- LFG keeps all native controller fields and setters under Blizzard ownership.
-- Only its safe rendered child moves, including first registration in combat.
do
    local stops, probes = 0, 0
    local function LFG(owner, rootName)
        local rootFrame, controller, child = Frame(), Controller(false), Frame()
        function rootFrame:GetName() return rootName or "LFGListFrame" end
        function controller:GetParent() return rootFrame end
        function controller:GetHeight() return 300 end
        function controller:GetScrollTarget() return child end
        function controller:SetInterpolateScroll() error("LFG native interpolation ownership changed") end
        function controller:SetScrollPercentage() error("LFG native scroll position was written") end
        function controller:GetScrollInterpolator() error("LFG native interpolator was adopted") end
        function child:CreateAnimationGroup()
            local group = { scripts = {} }
            self.group = group
            function group:SetScript(event, callback) self.scripts[event] = callback end
            function group:Stop() stops = stops + 1 self.playing = false end
            function group:Play() self.playing = true end
            function group:Finish()
                self.playing = false
                if self.scripts.OnFinished then self.scripts.OnFinished(self) end
            end
            function group:CreateAnimation()
                local move = { SetDuration = Noop, SetSmoothing = Noop }
                function move:SetOffset(_, y) self.offset = y end
                self.move = move
                return move
            end
            return group
        end
        Check(Motion.Track(controller, owner), "safe LFG renderer registration failed")
        controller:Trigger("scroll", 0.1, 0.5)
        controller:Trigger("scroll", 0.2, 0.5)
        return controller, child
    end
    local function Edge()
        for _, frame in ipairs(frames) do
            if frame.events.PLAYER_REGEN_DISABLED then frame:Fire("OnEvent", "PLAYER_REGEN_DISABLED") end
        end
    end
    combat, NS.Motion.combat = true, true
    local cold, child = LFG("cold-lfg")
    Check(child.group and child.group.playing, "cold safe LFG scroll did not animate in combat")
    stops = 0
    Edge()
    Check(child.group.playing and stops == 0, "combat edge stopped safe LFG rendering")
    cold:Trigger("scroll", 0.3, 0.5)
    Check(child.group.playing and child.group.move.offset == -8, "combat LFG retarget lost bounded motion")
    child.protected = true
    Edge()
    Check(not child.group.playing, "protected LFG content retained animation")
    child.protected = false
    cold:Trigger("scroll", 0.4, 0.5)
    cold:Trigger("scroll", 0.5, 0.5)
    Check(child.group.playing, "safe LFG content could not resume after protection changed")
    child.group:Finish()
    local childForbidden = child.IsForbidden
    function child:IsForbidden() probes = probes + 1 return childForbidden(self) end
    stops, probes = 0, 0
    Edge()
    Check(stops == 0 and probes == 0, "completed LFG rendering retained combat cleanup work")
    child.IsForbidden = childForbidden
    cold:Fire("OnHide")
    Motion.ReleaseOwner("cold-lfg")
    combat, NS.Motion.combat = false, false
    -- Measure only the provider callbacks: a fixture frame inventory naturally grows.
    local events = {}
    for _, frame in ipairs(frames) do
        if frame.events.PLAYER_REGEN_DISABLED then events[#events + 1] = frame end
    end
    local function Steps()
        local steps = 0
        debug.sethook(function() steps = steps + 1 end, "", 1)
        for _, frame in ipairs(events) do frame:Fire("OnEvent", "PLAYER_REGEN_DISABLED") end
        debug.sethook()
        return steps
    end
    local base = Steps()
    for index = 1, 64 do
        local hidden, hiddenChild = LFG("hidden-lfg")
        hidden:Fire("OnHide")
        function hidden:IsForbidden() probes = probes + 1 return false end
        function hiddenChild:IsForbidden() probes = probes + 1 return false end
    end
    stops, probes = 0, 0
    local populated = Steps()
    Check(stops == 0 and probes == 0, "combat touched historical hidden LFG scrolls")
    Check(populated <= base + 32, "combat scanned historical hidden LFG scrolls")
    print("BUDGET LFG-scroll hidden64 native=0 VM " .. base .. " -> " .. populated)
    Motion.ReleaseOwner("hidden-lfg")
    -- Social lists call protected Battle.net readers from native events.
    -- Skin lifecycle must never seed their native controller/layout fields.
    for _, locked in ipairs({ false, true }) do
        combat, NS.Motion.combat = locked, locked
        local social, content = LFG("social", "SocialUIFrame")
        Check(content.group and content.group.playing, "social list lost visual scrolling")
        Check(Motion.states[social] == nil and social.canInterpolateScroll == false,
            "social list acquired addon-owned native interpolation state")
        social:Trigger("layout")
        Check(not content.group.playing, "social native layout kept a stale translation")
        social:Trigger("scroll", 0.4, 0.5)
        social:Trigger("scroll", 0.5, 0.5)
        Check(content.group.playing, "social list did not resume visual scrolling")
        social:Fire("OnHide")
        Check(not content.group.playing, "hidden social list kept its animation")
        social:Fire("OnShow")
        social:Trigger("scroll", 0.6, 0.5)
        social:Trigger("scroll", 0.7, 0.5)
        Check(content.group.playing, "reopened social list lost visual scrolling")
        NS.DB.theme.reduceMotion = true
        for owner, callback in pairs(listeners) do callback(owner, "motion", "reduceMotion") end
        Check(not content.group.playing, "social list ignored reduced motion")
        NS.DB.theme.reduceMotion = false
        Motion.ReleaseOwner("social")
        Check(next(social.callbacks.scroll) == nil and next(social.callbacks.layout) == nil,
            "social list retained callbacks after release")
    end
    combat, NS.Motion.combat = false, false
end
Check(scriptWrites == 0, "native wheel/update scripts were replaced")
for _, frame in ipairs(frames) do Check(frame.scripts.OnUpdate == nil, "Suite installed an idle update loop") end
do
    local now, step = 0, 0.05
    GetTime = function() return now end
    local function WheelBox()
        local wheelBox = Controller(nil)
        local child = Frame()
        local group = { animations = {}, plays = 0 }
        function group:CreateAnimation(kind)
            Check(kind == "Translation", "bounce was not a render translation")
            local anim = {}
            function anim:SetOrder(order) self.order = order end
            function anim:SetDuration(duration) self.duration = duration end
            function anim:SetSmoothing(smoothing) self.smoothing = smoothing end
            function anim:SetOffset(x, y) self.x, self.y = x, y end
            self.animations[#self.animations + 1] = anim
            return anim
        end
        group.SetScript = Noop
        function group:Play() self.plays, self.playing = self.plays + 1, true end
        function group:Stop() self.playing = false end
        function child:CreateAnimationGroup() return group end
        function wheelBox:GetScrollTarget() return child end
        function wheelBox:GetHeight() return 300 end
        function wheelBox:IsScrollAllowed() return not self.blocked end
        function wheelBox:HasScrollableExtent() return not self.short end
        function wheelBox:ScrollInDirection(amount, direction)
            if self:IsScrollAllowed() then
                self:SetScrollPercentage(math.max(0, math.min(1, self.position + amount * direction)))
            end
        end
        wheelBox.scripts.OnMouseWheel = function(self, delta)
            if self.capture then self.capture() return end
            self:ScrollInDirection(step, delta < 0 and 1 or -1)
        end
        return wheelBox, group
    end

    local addon, bounce = WheelBox()
    local bindings, bindingsVisual = WheelBox()
    local bindingsBar = Controller(false, true)
    local categories, categoriesVisual = WheelBox()
    local categoriesBar = Controller(false, true)
    local other = WheelBox()
    bindings.registeredScrollBar, bindingsBar.registeredScrollBox = bindingsBar, bindings
    categories.registeredScrollBar, categoriesBar.registeredScrollBox = categoriesBar, categories
    for _, controller in ipairs({ bindings, bindingsBar, categories, categoriesBar }) do
        function controller:SetInterpolateScroll()
            error("Settings native interpolation flag was written")
        end
        function controller:GetScrollInterpolator()
            error("Settings native interpolator was adopted")
        end
    end
    SettingsPanel = { Container = { SettingsList = { ScrollBox = bindings } }, CategoryList = { ScrollBox = categories } }
    AddonList = { ScrollBox = addon }
    EventRegistry = Frame()
    Check(providers.bar[1](bindingsBar, "settingsBar"), "Settings bar could not register first")
    Check(providers.generic[1](bindings, "settingsList"), "Settings list could not share its visual lease")
    Check(providers.generic[1](categories, "settingsCategories") and providers.bar[1](categoriesBar, "settingsCategories"),
        "Settings category selector could not register its visual lease")
    categories:Trigger("scroll", 0.1, 0.5)
    categories:Trigger("scroll", 0.2, 0.5)
    Check(categoriesVisual.playing, "Settings category selector lost visual smoothing")
    Motion.ReleaseOwner("settingsCategories")
    Check(not categoriesVisual.playing and not next(categories.callbacks.scroll),
        "Settings category selector retained visual work after release")
    Check(Motion.Track(addon, "adaptiveAddon") and Motion.Track(other, "other"),
        "adaptive list fixture was not tracked")
    Check(next(EventRegistry.callbacks) == nil and bindings.hooks.OnMouseWheel == nil,
        "Settings installed input hooks")
    Check(not next(bindingsBar.thumb.callbacks), "Settings changed native thumb callbacks")

    local function Wheel(target, interval, delta)
        now = now + interval
        local from = target.position
        target:Fire("OnMouseWheel", delta or -1)
        local tween = target.interpolator
        local destination = tween and tween.destination
        local travelled = (destination or target.position) - from
        if destination then target.position = destination; tween:Cancel() end
        return travelled
    end

    local function Near(value, expected)
        return math.abs(value - expected) < 0.00001
    end

    Wheel(addon, 0.25)
    Check(Near(Wheel(addon, 0.04), step), "legacy/default profile accelerated")
    NS.DB.theme.adaptiveScrolling = true
    Changed()
    addon.position = 0
    Check(Near(Wheel(addon, 0.25), step), "first notch did not preserve native distance")
    local previous = step
    for _ = 1, 5 do
        local distance = Wheel(addon, 0.04)
        Check(distance > previous and distance <= 3 * step, "burst gain did not grow toward a 3x ceiling")
        previous = distance
    end
    Check(Near(previous / step, 1 + 2 * math.log(2.9375) / math.log(3)), "gain is not logarithmic")
    Check(Near(Wheel(addon, 0.04, 1), -step), "direction change carried old gain")
    Check(Near(Wheel(addon, 0.18, 1), -step), "pause did not reset gain")
    Check(Near(Wheel(addon, 0.04, 1), -step * (1 + 2 * math.log(2) / math.log(3))),
        "the burst did not restart after a pause")
    addon:Trigger("layout")
    Check(Near(Wheel(addon, 0.04, 1), -step), "list layout retained the burst")
    addon:Fire("OnHide")
    addon:Fire("OnShow")
    Check(Near(Wheel(addon, 0.04, 1), -step), "reopened list retained the burst")

    Wheel(other, 0.25)
    Check(Near(Wheel(other, 0.04), step), "an unrelated Blizzard list accelerated")
    local originalWheel = bindings.scripts.OnMouseWheel
    local beforeSettingsScroll = positions
    Check(Near(Wheel(bindings, 0.25), step) and Near(Wheel(bindings, 0.04), step),
        "Settings wheel did not keep native distances")
    Check(positions - beforeSettingsScroll == 4 and not bindings.interpolator and not bindingsBar.interpolator,
        "Settings wrote extra positions or installed an interpolator")
    bindings:Trigger("scroll", 0.1, 0.5)
    bindings:Trigger("scroll", 0.2, 0.5)
    Check(bindingsVisual.playing and bindingsVisual.animations[1].y == -8,
        "Settings lost visual smoothing")
    local capture = 0
    bindings.capture = function() capture = capture + 1 end
    Check(Wheel(bindings, 0) == 0 and capture == 1 and bindingsVisual.plays == 1,
        "assigning MOUSEWHEELDOWN scrolled or animated")
    Check(bindings.scripts.OnMouseWheel == originalWheel, "Settings native wheel script changed")
    bindings.capture = nil
    Motion.ReleaseOwner("settingsBar")
    Check(bindingsVisual.playing, "releasing Settings bar stopped the remaining list lease")
    NS.DB.theme.smoothScrolling = false
    for owner, callback in pairs(listeners) do callback(owner, "motion", "smoothScrolling") end
    bindings:Trigger("scroll", 0.3, 0.5)
    Check(not bindingsVisual.playing and bindingsVisual.plays == 1, "Standard Settings scrolling animated")
    NS.DB.theme.smoothScrolling = nil
    for owner, callback in pairs(listeners) do callback(owner, "motion", "smoothScrolling") end
    bindings:Trigger("scroll", 0.4, 0.5)
    bindings:Trigger("scroll", 0.5, 0.5)
    Check(bindingsVisual.playing and bindingsVisual.plays == 2, "Settings visual smoothing did not resume")
    Motion.ReleaseOwner("settingsList")
    Check(not bindingsVisual.playing and not next(bindings.callbacks.scroll) and not next(bindings.callbacks.layout),
        "released Settings list retained motion or callbacks")

    addon.position = 0.3
    now = now + 0.25
    addon:Fire("OnMouseWheel", -1)
    local initial = addon.interpolator.destination
    now = now + 0.04
    addon:Fire("OnMouseWheel", -1)
    Check(addon.interpolator.destination > initial and addon.position < addon.interpolator.destination,
        "a burst did not advance the target of a running interpolation")
    local beforeReverse = addon.position
    now = now + 0.04
    addon:Fire("OnMouseWheel", 1)
    Check(Near(addon.interpolator.destination, beforeReverse - step), "reversal started from the old target")
    addon.interpolator:Cancel()

    addon.position = 0.98
    Wheel(addon, 0.25)
    Check(addon.position == 1 and bounce.plays == 0, "bounce played on arrival or crossed the scroll range")
    Wheel(addon, 0.04)
    Check(addon.position == 1 and bounce.plays == 1 and bounce.animations[1].y == 5
        and bounce.animations[2].y == -5, "bottom bounce changed the real offset or moved the wrong way")
    Wheel(addon, 0.04)
    Check(bounce.plays == 1, "continued wheel notches restarted the bounce")
    Check(Near(Wheel(addon, 0.04, 1), -step) and not bounce.playing,
        "inward wheel input did not stop the bounce immediately")
    addon.position = 0
    Wheel(addon, 0.04, 1)
    Check(addon.position == 0 and bounce.plays == 2 and bounce.animations[1].y == -5,
        "top bounce moved the wrong way or changed the real offset")
    NS.DB.theme.scrollEdgeBounce = false
    Changed("scrollEdgeBounce")
    Wheel(addon, 0.30, 1)
    Check(bounce.plays == 2 and not bounce.playing, "disabling bounce retained a running effect")
    addon.position = 0.3
    Wheel(addon, 0.04)
    Check(Wheel(addon, 0.04) > step, "disabling bounce also disabled acceleration")
    NS.DB.theme.scrollEdgeBounce = nil
    NS.DB.theme.reduceMotion = true
    Changed("reduceMotion")
    addon.position = 1
    Wheel(addon, 0.30)
    Check(bounce.plays == 2, "reduced motion permitted bounce")
    addon.position = 0.3
    Wheel(addon, 0.04)
    Check(Near(Wheel(addon, 0.04), step), "reduced motion permitted acceleration")
    NS.DB.theme.reduceMotion = nil
    Changed("reduceMotion")
    addon.position, addon.short = 1, true
    Wheel(addon, 0.30)
    Check(bounce.plays == 2, "unscrollable list bounced")
    addon.short, combat = false, true
    Wheel(addon, 0.30)
    Check(bounce.plays == 2, "combat allowed the adaptive bounce")
    combat = false
    Wheel(addon, 0.30)
    Check(bounce.playing, "adaptive wheel did not recover after combat")
    Motion.ReleaseOwner("adaptiveAddon")
    Wheel(addon, 0.30)
    Check(not bounce.playing and bounce.plays == 3, "released list retained adaptive motion")
    Check(scriptWrites == 0, "adaptive scrolling replaced native scripts")
end

print("Suite skin smooth and adaptive scrolling (" .. (arg[2] or "Mainline") .. "): " .. checks .. " checks passed")

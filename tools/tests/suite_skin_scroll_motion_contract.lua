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
ScrollBoxListMixin = { Event = { OnLayout = "layout" } }
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
Check(not legacyBar.canInterpolateScroll and legacyBar.interpolator.destination == nil and positions == before,
    "combat edge retained motion or wrote a scroll position")
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
    local isLocked, locked = NS.IsCombatLocked, 0
    NS.IsCombatLocked = function() locked = locked + 1 return isLocked() end
    reads = 0
    for _, frame in ipairs(frames) do
        if frame.events.PLAYER_REGEN_ENABLED then frame:Fire("OnEvent", "PLAYER_REGEN_ENABLED") end
    end
    NS.IsCombatLocked = isLocked
    Check(locked == 1, "a combat edge read the configuration once per controller")
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
    Check(hidden.position == 0.8 and not hidden.canInterpolateScroll,
        "hidden controller interpolated in combat instead of reaching the requested row")
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
    Check(not hidden[1].canInterpolateScroll, "show in combat retained smooth scrolling")
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
Check(scriptWrites == 0, "native wheel/update scripts were replaced")
for _, frame in ipairs(frames) do Check(frame.scripts.OnUpdate == nil, "Suite installed an idle update loop") end
print("Suite skin smooth scrolling (" .. (arg[2] or "Mainline") .. "): " .. checks .. " checks passed")

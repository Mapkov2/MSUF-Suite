-- Native ScrollController setters write Lua state even through securecallfunction.
-- LFG cosmetics must retain scroll easing without calling those setters.
local root = assert(arg[1])
local checks, writes, allocations = 0, 0, 0
local function Check(value, message) checks = checks + 1 assert(value, message) end
local function Noop() end
local secret = {}
issecretvalue = function(value) return value == secret end
securecallfunction = function(callback, ...) return callback(...) end
local combat, frames = false, {}
InCombatLockdown = function() return combat end
local function Frame(name, parent)
    local frame = { name = name, parent = parent, hooks = {}, callbacks = {}, events = {}, shown = true }
    frames[#frames + 1] = frame
    function frame:GetName() return self.name end
    function frame:GetParent() return self.parent end
    function frame:IsForbidden() return self.forbidden == true end
    function frame:IsProtected() return self.protected == true, self.protected == true end
    function frame:IsVisible() return self.shown end
    function frame:GetHeight() return 200 end
    function frame:HookScript(event, fn) self.hooks[event] = fn end
    function frame:SetScript(event, fn) self.hooks[event] = fn end
    function frame:RegisterEvent(event) self.events[event] = true end
    function frame:RegisterCallback(event, fn, owner)
        self.callbacks[event] = self.callbacks[event] or {}
        self.callbacks[event][owner] = fn
    end
    function frame:UnregisterCallback(event, owner) self.callbacks[event][owner] = nil end
    function frame:Fire(event, ...)
        for owner, fn in pairs(self.callbacks[event] or {}) do fn(owner, ...) end
        if self.hooks[event] then self.hooks[event](self, ...) end
    end
    function frame:CreateAnimationGroup()
        allocations = allocations + 1
        local group = { playing = false, plays = 0 }
        function group:Stop() self.playing = false end
        function group:Play(reverse) self.playing = true self.plays = self.plays + 1 self.reverse = reverse end
        function group:CreateAnimation()
            local move = {}
            function move:SetDuration(value) self.duration = value end
            function move:SetSmoothing(value) self.smoothing = value end
            function move:SetOffset(x, y) self.x, self.y = x, y end
            self.move = move
            return move
        end
        self.group = group
        return group
    end
    return frame
end
CreateFrame = function() return Frame() end
hooksecurefunc = function(target, method, fn)
    local original = target[method]
    target[method] = function(self, ...) original(self, ...) fn(self, ...) end
end
BaseScrollBoxEvents = { OnScroll = "scroll" }
ScrollBoxListMixin = { Event = { OnLayout = "layout", OnScroll = "scroll" } }
local listeners = {}
local NS = { DB = { enabled = true, theme = {} }, Motion = { combat = false },
    IsCombatLocked = InCombatLockdown, Registry = { AddListener = function(owner, fn) listeners[owner] = fn end },
    GenericWindows = { SetScrollMotionProvider = Noop }, ScrollBarSkin = { SetScrollMotionProvider = Noop } }
local function Load(path)
    local override = path == "Rendering/ScrollMotion.lua" and arg[2]
    assert(loadfile(override or root .. "/MSUF_Suite_Skin/" .. path))("MSUF_Suite_Skin", NS)
end
Load("Core/Safety.lua")
Load("Rendering/ScrollMotion.lua")
local function Controller(parent)
    local frame = Frame(nil, parent)
    frame.canInterpolateScroll, frame.scrollPercentage = false, 0
    function frame:CanInterpolateScroll() return self.canInterpolateScroll end
    function frame:SetInterpolateScroll(value) writes = writes + 1 self.canInterpolateScroll = value end
    function frame:SetScrollPercentage(value) writes = writes + 1 self.scrollPercentage = value end
    function frame:GetScrollInterpolator() error("LFG skin created a native Lua interpolator") end
    function frame:Interpolate() error("LFG skin started a native Lua interpolator") end
    return frame
end
local lfg = Frame("LFGListFrame")
local viewer = Frame(nil, lfg)
local box, bar = Controller(viewer), Controller(viewer)
local child = Frame(nil, box)
function box:GetScrollTarget() return child end
function bar:IsThumbMouseDown() return self.dragging == true end
box.registeredScrollBar, bar.registeredScrollBox = bar, box
Check(NS.ScrollMotion.Track(box, "window"), "LFG list was not adopted")
Check(writes == 0, "LFG list adoption wrote native ScrollController state")
Check(NS.ScrollMotion.Track(bar, "window"), "LFG bar route was not adopted")
Check(NS.ScrollMotion.Track(bar, "other"), "independent LFG owner was refused")
Check(NS.ScrollMotion.states[box] == nil and NS.ScrollMotion.states[bar] == nil,
    "LFG controllers entered native interpolation ownership")
box:Fire("scroll", 0, 0.25)
box:Fire("scroll", 0.01, 0.25)
Check(child.group and child.group.playing and child.group.reverse, "LFG scroll lost finite render easing")
Check(child.group.move.duration == 0.11 and child.group.move.x == 0 and child.group.move.y == -6,
    "LFG render displacement did not follow native scroll")
Check(writes == 0 and box.scrollPercentage == 0 and bar.scrollPercentage == 0,
    "render easing changed native scroll position")
box:Fire("scroll", 0.8, 0.25)
Check(math.abs(child.group.move.y) <= 8, "large native jump displaced recycled rows without a bound")
bar.dragging = true
box:Fire("scroll", 0.81, 0.25)
Check(not child.group.playing, "thumb dragging was eased")
bar.dragging = false
for _, payload in ipairs({ {secret, 0.25}, {0.1, secret}, {0.1, 0}, {0.1, 2} }) do
    box:Fire("scroll", unpack(payload))
    Check(not child.group.playing, "unreadable scroll payload started animation")
end
box:Fire("scroll", 0, 0.25)
box:Fire("scroll", 0.01, 0.25)
box:Fire("layout")
Check(not child.group.playing, "native layout retained stale render offset")
box:Fire("scroll", 0, 0.25)
box:Fire("scroll", 0.01, 0.25)
NS.Motion.combat = true
for _, frame in ipairs(frames) do
    if frame.events.PLAYER_REGEN_DISABLED then frame:Fire("OnEvent", "PLAYER_REGEN_DISABLED") end
end
Check(not child.group.playing, "combat edge retained the render animation")
NS.Motion.combat = false
for _, key in ipairs({ "smoothScrolling", "reduceMotion" }) do
    NS.DB.theme[key] = key == "reduceMotion"
    for owner, fn in pairs(listeners) do fn(owner, "motion", key) end
    box:Fire("scroll", 0, 0.25)
    box:Fire("scroll", 0.01, 0.25)
    Check(not child.group.playing, key .. " did not stop render easing")
    NS.DB.theme[key] = nil
end
NS.ScrollMotion.Release(box, "window")
Check(next(box.callbacks.scroll) ~= nil, "box release discarded the remaining scrollbar lease")
NS.ScrollMotion.ReleaseOwner("window")
Check(next(box.callbacks.scroll) ~= nil, "owner release discarded another owner's lease")
NS.ScrollMotion.ReleaseOwner("other")
Check(next(box.callbacks.scroll) == nil and not child.group.playing, "last owner retained callbacks or animation")
Check(writes == 0, "LFG lifecycle wrote native scroll state")
Check(NS.ScrollMotion.Track(box, "again"), "released LFG list could not be readopted")
box:Fire("scroll", 0.01, 0.25)
Check(not child.group.playing, "readoption reused a stale offset")
NS.ScrollMotion.ReleaseOwner("again")
-- Later protection, native preferences and hidden state are checked per gesture.
for _, object in ipairs({ box, bar, child }) do
    Check(NS.ScrollMotion.Track(box, "protection"), "protection fixture was refused")
    box:Fire("scroll", 0, 0.25)
    box:Fire("scroll", 0.01, 0.25)
    object.protected = true
    box:Fire("scroll", 0.02, 0.25)
    Check(not child.group.playing, "newly protected list component kept animating")
    object.protected = false
    NS.ScrollMotion.ReleaseOwner("protection")
end
Check(NS.ScrollMotion.Track(box, "native-preference"), "native preference fixture was refused")
box.canInterpolateScroll = true
local plays = child.group.plays
box:Fire("scroll", 0, 0.25)
box:Fire("scroll", 0.01, 0.25)
Check(child.group.plays == plays, "native interpolation received a second render animation")
NS.ScrollMotion.ReleaseOwner("native-preference")
Check(box.canInterpolateScroll, "skin changed an enabled native interpolation preference")
box.canInterpolateScroll = false
Check(NS.ScrollMotion.Track(box, "hide"), "hide fixture was refused")
box:Fire("scroll", 0, 0.25)
box:Fire("scroll", 0.01, 0.25)
box:Fire("OnHide")
Check(not child.group.playing, "hidden list kept animating")
box:Fire("scroll", 0, 0.25)
box:Fire("scroll", 0.01, 0.25)
local oldHeight = box.GetHeight
box.GetHeight = function() return secret end
box:Fire("scroll", 0.02, 0.25)
Check(not child.group.playing, "secret viewport height reached scroll arithmetic")
box.GetHeight = oldHeight
NS.ScrollMotion.ReleaseOwner("hide")
Check(writes == 0, "LFG safety checks wrote native scroll state")
local ordinary = Controller(Frame("OtherWindow"))
Check(NS.ScrollMotion.Track(ordinary, "ordinary") and ordinary.canInterpolateScroll,
    "ordinary window lost native smooth scrolling")
NS.ScrollMotion.ReleaseOwner("ordinary")
Check(not ordinary.canInterpolateScroll, "ordinary native preference did not restore")
print("Suite LFG native scroll-state isolation: " .. checks .. " checks passed")

-- The PvP scoreboard and results lists build TableBuilder rows while scrolling.
-- The skin must never write their native interpolation state or hook their
-- interpolator; render-only easing is the most it may add.
local root = assert(arg[1])
local checks, writes = 0, 0
local function Check(value, message) checks = checks + 1 assert(value, message) end
local function Noop() end
issecretvalue = function() return false end
securecallfunction = function(callback, ...) return callback(...) end
InCombatLockdown = function() return false end
local function Frame(name, parent)
    local frame = { name = name, parent = parent, hooks = {}, callbacks = {}, events = {}, shown = true }
    function frame:GetName() return self.name end
    function frame:GetParent() return self.parent end
    function frame:IsForbidden() return false end
    function frame:IsProtected() return false, false end
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
    end
    function frame:CreateAnimationGroup()
        local group = { playing = false }
        function group:SetScript() end
        function group:Stop() self.playing = false end
        function group:Play() self.playing = true end
        function group:CreateAnimation()
            local move = {}
            function move:SetDuration() end
            function move:SetSmoothing() end
            function move:SetOffset(x, y) self.x, self.y = x, y end
            return move
        end
        self.group = group
        return group
    end
    return frame
end
CreateFrame = function() return Frame() end
local hooked = {}
hooksecurefunc = function(target, method, fn)
    hooked[target] = hooked[target] or {}
    hooked[target][method] = true
    local original = target[method]
    target[method] = function(self, ...) original(self, ...) fn(self, ...) end
end
ScrollBoxListMixin = { Event = { OnLayout = "layout", OnScroll = "scroll" } }
local NS = { DB = { enabled = true, theme = {} }, Client = { isForever = false }, IsCombatLocked = InCombatLockdown,
    Registry = { AddListener = Noop },
    GenericWindows = { SetScrollMotionProvider = Noop }, ScrollBarSkin = { SetScrollMotionProvider = Noop } }
local function Load(path)
    assert(loadfile(root .. "/MSUF_Suite_Skin/" .. path))("MSUF_Suite_Skin", NS)
end
Load("../MSUF_Suite/Appearance/Safety.lua")
Load("Rendering/ScrollMotion.lua")

local function Controller(parent)
    local frame = Frame(nil, parent)
    frame.canInterpolateScroll = false
    function frame:CanInterpolateScroll() return self.canInterpolateScroll end
    function frame:SetInterpolateScroll(value) writes = writes + 1 self.canInterpolateScroll = value end
    function frame:SetScrollPercentage() writes = writes + 1 end
    function frame:GetScrollInterpolator() error("skin created a native interpolator for a PvP table") end
    function frame:Interpolate() error("skin started a native interpolator for a PvP table") end
    return frame
end

-- Blizzard_PVPMatch: <Window>.Content.ScrollBox / .ScrollBar.
local function PvPList(name)
    local window = Frame(name)
    local content = Frame(nil, window)
    local box, bar = Controller(content), Controller(content)
    local child = Frame(nil, box)
    function box:GetScrollTarget() return child end
    function bar:IsThumbMouseDown() return false end
    box.registeredScrollBar, bar.registeredScrollBox = bar, box
    return box, bar, child
end

for _, name in ipairs({ "PVPMatchScoreboard", "PVPMatchResults" }) do
    local box, bar, child = PvPList(name)
    Check(NS.ScrollMotion.Track(bar, name), name .. " scrollbar route was refused")
    Check(NS.ScrollMotion.Track(box, name), name .. " list was refused")
    Check(writes == 0 and not box.canInterpolateScroll and not bar.canInterpolateScroll,
        name .. " adoption wrote native interpolation state")
    Check(NS.ScrollMotion.states[box] == nil and NS.ScrollMotion.states[bar] == nil,
        name .. " controllers entered native interpolation ownership")
    Check(not (hooked[box] and hooked[box].Interpolate) and not (hooked[bar] and hooked[bar].Interpolate),
        name .. " interpolator was hooked")
    box:Fire("scroll", 0, 0.5)
    box:Fire("scroll", 0.02, 0.5)
    Check(child.group and child.group.playing, name .. " lost render-only easing")
    Check(writes == 0, name .. " render easing wrote native scroll state")
    NS.ScrollMotion.ReleaseOwner(name)
    Check(next(box.callbacks.scroll) == nil and not child.group.playing, name .. " release kept callbacks or animation")
    Check(writes == 0, name .. " release wrote native scroll state")
end

-- Ordinary windows keep Blizzard's native smooth scrolling.
local ordinary = Controller(Frame("OtherWindow"))
function ordinary:GetScrollTarget() return Frame(nil, ordinary) end
Check(NS.ScrollMotion.Track(ordinary, "ordinary") and ordinary.canInterpolateScroll,
    "ordinary window lost native smooth scrolling")
NS.ScrollMotion.ReleaseOwner("ordinary")
Check(not ordinary.canInterpolateScroll, "ordinary native preference did not restore")
print("Suite PvP match table scroll isolation: " .. checks .. " checks passed")

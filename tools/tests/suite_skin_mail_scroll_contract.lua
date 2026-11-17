-- Reuse the native controller fixture; assertions cover addon ownership,
-- not WoW taint propagation or live callback timing.
local root = assert(arg[1], "Suite root required")
local file = assert(io.open(root .. "/tools/tests/suite_skin_scroll_motion_contract.lua", "rb"))
local source = file:read("*a")
file:close()
local stop = assert(source:find("local box, bar = Controller(nil)", 1, true))
local body = [======[
wipe = function(values) for key in pairs(values) do values[key] = nil end end
for _, frame in ipairs(frames) do
    function frame:UnregisterEvent(event) self.events[event] = nil end
end
local create = CreateFrame
CreateFrame = function()
    local frame = create()
    function frame:UnregisterEvent(event) self.events[event] = nil end
    return frame
end
Load("Rendering/LegacyScrollMotion.lua")
local Legacy = NS.LegacyScrollMotion
local events = frames[#frames]
local function Child()
    local child = Frame()
    function child:CreateAnimationGroup()
        local group = { scripts = {}, playing = false }
        function group:CreateAnimation()
            local move = {}
            move.SetDuration, move.SetSmoothing = Noop, Noop
            function move:SetOffset(x, y) self.x, self.y = x, y end
            function move:GetSmoothProgress() return 0.5 end
            return move
        end
        function group:SetScript(event, callback) self.scripts[event] = callback end
        function group:Play() self.playing = true end
        function group:Stop() self.playing = false end
        function group:IsPlaying() return self.playing end
        return group
    end
    return child
end
local insideSkin, nativeWrites = false, 0
local function Skin(callback, ...)
    insideSkin = true
    local result = callback(...)
    insideSkin = false
    return result
end
local function Scroll(name, original, shown)
    local scroll, child, bar = Frame(), Child(), Controller(original, true)
    _G[name], scroll.ScrollBar, scroll.offset, bar.legacy = scroll, bar, 0, scroll
    scroll.shown, bar.shown = shown, shown
    function scroll:GetScrollChild() return child end
    function scroll:GetVerticalScroll() return self.offset end
    function bar:IsMouseOver() return self.mouseOver == true end
    local setFlag, setPosition = bar.SetInterpolateScroll, bar.SetScrollPercentageInternal
    function bar:SetInterpolateScroll(value)
        if insideSkin then nativeWrites = nativeWrites + 1 end
        setFlag(self, value)
    end
    function bar:SetScrollPercentageInternal(value)
        if insideSkin then nativeWrites = nativeWrites + 1 end
        setPosition(self, value)
        scroll:Fire("OnVerticalScroll", scroll.offset)
    end
    local interpolator = bar:GetScrollInterpolator()
    interpolator.destination = 0.6
    local cancel = interpolator.Cancel
    function interpolator:Cancel()
        if insideSkin then nativeWrites = nativeWrites + 1 end
        cancel(self)
    end
    return scroll, bar, interpolator
end
local function Playing(state) return state.current and state.current.group:IsPlaying() or false end
local scenarios = 0
NS.Client.isForever = true
for _, name in ipairs({ "SendMailScrollFrame", "OpenMailScrollFrame" }) do
    for _, baseline in ipairs({ {}, { value = false }, { value = true } }) do
        for _, shown in ipairs({ false, true }) do
            for _, locked in ipairs({ false, true }) do
                combat = locked
                scenarios = scenarios + 1
                local scroll, bar, interpolator = Scroll(name, baseline.value, shown)
                local flag, interpolate, begin = bar.SetInterpolateScroll, bar.Interpolate, bar.ScrollToBegin
                local before = nativeWrites
                Check(not Skin(providers.bar[1], bar, "mail-style"), "mail scrollbar acquired native motion")
                Check(not Skin(providers.generic[1], bar, "mail-menu"), "mail discovery acquired native motion")
                local partner = Controller(false)
                partner.registeredScrollBar = bar
                Check(not Skin(Motion.Track, partner, "mail-partner"), "partner bypassed native mailbox ownership")
                Check(Skin(Legacy.Track, scroll, "mail-content"), "mail visual scrolling was lost")
                Check(nativeWrites == before and bar.canInterpolateScroll == baseline.value
                    and interpolator.destination == 0.6 and not Motion.states[bar] and not Motion.states[partner],
                    "mail skin wrote a native flag, position or interpolator cache")
                scroll:Fire("OnShow")
                Skin(bar.Fire, bar, "OnShow")
                -- Native range/track refresh reads this cache, even on immediate updates.
                bar:SetScrollPercentage(0.25, true)
                Check(interpolator:GetInterpolateTo() == 0.6, "native range refresh inherited a canceled cache")
                local state = Legacy.states[scroll]
                Check(scroll.offset == 250 and state and Playing(state) == (baseline.value ~= true),
                    "mail scroll lost easing or stacked it on native interpolation")
                bar:SetScrollPercentage(0, true)
                Check(not Playing(state), "mail page reset retained old translated content")
                bar:SetScrollPercentage(0.2, true)
                bar:SetInterpolateScroll(true)
                bar:SetScrollPercentage(0.3, true)
                Check(not Playing(state) and scroll.offset == 300, "native mail smoothing did not stop the render animation")
                bar:SetInterpolateScroll(baseline.value)
                bar:SetScrollPercentage(0.4, true)
                bar.mouseOver = true
                Skin(events.Fire, events, "OnEvent", "GLOBAL_MOUSE_DOWN", "LeftButton")
                Check(state.dragging and not Playing(state), "mail thumb drag retained easing")
                Skin(events.Fire, events, "OnEvent", "GLOBAL_MOUSE_UP", "LeftButton")
                Check(not state.dragging, "mail thumb release retained drag state")
                NS.DB.theme.reduceMotion = true
                bar:SetScrollPercentage(0.5, true)
                Check(not Playing(state) and scroll.offset == 500, "reduced motion altered native mail scrolling")
                NS.DB.theme.reduceMotion = nil
                bar:SetScrollPercentage(0.55, true)
                NS.DB.theme.smoothScrolling = false
                Skin(listeners[Legacy], Legacy, "motion", "smoothScrolling")
                Check(not Playing(state) and scroll.offset == 550, "mail smooth-scroll disable retained render motion")
                NS.DB.theme.smoothScrolling = nil
                for _ = 1, 3 do
                    Skin(bar.Fire, bar, "OnHide")
                    Skin(scroll.Fire, scroll, "OnHide")
                    Skin(bar.Fire, bar, "OnShow")
                    Skin(scroll.Fire, scroll, "OnShow")
                    Skin(Changed)
                end
                Skin(Legacy.ReleaseOwner, "mail-content")
                Skin(providers.bar[2], bar, "mail-style")
                Check(nativeWrites == before and interpolator.destination == 0.6
                    and bar.canInterpolateScroll == baseline.value and not next(state.owners),
                    "mail reopen, settings or release changed native caches")
                Check(bar.SetInterpolateScroll == flag and bar.Interpolate == interpolate and bar.ScrollToBegin == begin
                    and scriptWrites == 0 and not bar.hooks.OnMouseDown and not bar.hooks.OnMouseUp,
                    "mail skin replaced native methods or installed mouse scripts")
                _G[name] = nil
            end
        end
    end
end
combat = false
-- Exact object identity and client scope: ordinary bars keep the native route.
local foreign = Controller(false, true)
function foreign:GetName() return "SendMailScrollFrameScrollBar" end
Check(Skin(Motion.Track, foreign, "foreign"), "same-named foreign bar lost motion")
Skin(Motion.ReleaseOwner, "foreign")
NS.Client.isForever = false
local scroll, bar = Scroll("SendMailScrollFrame", false, true)
Check(Skin(Motion.Track, bar, "mainline-mail") and bar.canInterpolateScroll,
    "Mainline mail changed its existing controller path")
Skin(Motion.ReleaseOwner, "mainline-mail")
SendMailScrollFrame = nil
NS.Client.isForever = true
Check(not Motion.IsMailScroll(secret) and not Motion.Track(secret, "secret"), "secret mailbox target was used")
SendMailScrollFrame = secret
Check(not Motion.IsMailScroll(foreign), "secret global mailbox was used")
SendMailScrollFrame = { ScrollBar = secret }
Check(not Motion.IsMailScroll(foreign), "secret mailbox scrollbar was compared")
SendMailScrollFrame = nil
foreign.registeredScrollBar = secret
Check(Motion.Track(foreign, "secret-partner"), "secret partner broke ordinary scroll adoption")
Motion.ReleaseOwner("secret-partner")
foreign.registeredScrollBar = nil
print("Suite mail scroll ownership: " .. checks .. " checks, " .. scenarios .. " scenarios passed")
]======]
assert(loadstring(source:sub(1, stop - 1) .. body, "@suite_skin_mail_scroll_fixture"))()

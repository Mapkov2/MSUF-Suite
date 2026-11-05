-- Quest pages use ScrollFrameTemplate, not ScrollBox. Their native
-- ScrollBarMixin:ScrollToBegin(forceImmediate) passes nil through unchanged
-- (Blizzard_SharedXML/Shared/Scroll/ScrollBar.lua, Mainline and Forever).
local root = assert(arg[1], "Suite root required")
local file = assert(io.open(root .. "/tools/tests/suite_skin_scroll_motion_contract.lua", "rb"))
local source = file:read("*a")
file:close()
local stop = assert(source:find("local box, bar = Controller(nil)", 1, true))
local body = [======[
wipe = function(values) for key in pairs(values) do values[key] = nil end end
IsMouseButtonDown = function() return false end
Load("Rendering/LegacyScrollMotion.lua")
local function AnimationTarget()
    local child = Frame()
    function child:CreateAnimationGroup()
        local group = { scripts = {}, playing = false }
        function group:CreateAnimation()
            local animation = {}
            animation.SetDuration, animation.SetSmoothing = Noop, Noop
            function animation:SetOffset(x, y) self.x, self.y = x, y end
            function animation:GetSmoothProgress() return 0.5 end
            return animation
        end
        function group:SetScript(event, callback) self.scripts[event] = callback end
        function group:Play() self.playing = true end
        function group:Stop() self.playing = false end
        function group:IsPlaying() return self.playing end
        return group
    end
    return child
end
local nativeFrame = CreateFrame
CreateFrame = function()
    local frame = nativeFrame()
    function frame:UnregisterEvent(event) self.events[event] = nil end
    return frame
end
-- Legacy's event frame was created before extending the fixture.
for _, frame in ipairs(frames) do
    function frame:UnregisterEvent(event) self.events[event] = nil end
end
local pages = { "QuestDetailScrollFrame", "QuestProgressScrollFrame", "QuestRewardScrollFrame",
    "QuestGreetingScrollFrame", "QuestLogPopupDetailFrameScrollFrame" }
for _, flavor in ipairs({ "Mainline", "Forever" }) do
    NS.Client.isForever = flavor == "Forever"
    for _, name in ipairs(pages) do
        local scroll, child = Frame(), AnimationTarget()
        local bar = Controller(false, true)
        scroll.ScrollBar, scroll.offset, bar.legacy = bar, 0, scroll
        _G[name] = scroll
        function scroll:GetScrollChild() return child end
        function scroll:GetVerticalScroll() return self.offset end
        local set = bar.SetScrollPercentageInternal
        function bar:SetScrollPercentageInternal(value)
            set(self, value)
            scroll:Fire("OnVerticalScroll", scroll.offset)
        end
        function bar:ScrollToBegin(forceImmediate) self:SetScrollPercentage(0, forceImmediate) end
        local reset, setter = bar.ScrollToBegin, bar.SetInterpolateScroll
        -- Both routes run in the real skin: scrollbar cosmetics and menu discovery.
        providers.bar[1](bar, "quest-skin")
        Check(bar.canInterpolateScroll == false and bar.SetInterpolateScroll == setter,
            flavor .. ": quest skin changed native controller state: " .. name)
        Check(NS.LegacyScrollMotion.Track(scroll, "quest-skin"), "quest visual scrolling was lost")
        Check(bar.canInterpolateScroll == false, "legacy discovery enabled native interpolation")
        bar:SetScrollPercentage(0.65)
        local state = NS.LegacyScrollMotion.states[scroll]
        Check(scroll.offset == 650 and state and state.current and state.current.group:IsPlaying(),
            "wheel scrolling must update native geometry immediately and ease only its rendering")
        -- Same call the native detail/progress/reward OnShow and QUEST_ITEM_UPDATE use.
        bar:ScrollToBegin()
        Check(scroll.offset == 0 and bar.position == 0 and bar.interpolator == nil,
            "new quest page/reward choices inherited an asynchronous scroll position")
        Check(not state.current.group:IsPlaying() and not NS.LegacyScrollMotion.active[state],
            "page reset left an old visual translation covering new quest content")
        Check(bar.ScrollToBegin == reset and scriptWrites == 0, "quest reset or native input scripts were replaced")
        bar:SetScrollPercentage(0.3)
        scroll:Fire("OnHide")
        Check(not state.current.group:IsPlaying(), "hidden quest content kept moving")
        scroll:Fire("OnShow")
        bar:ScrollToBegin()
        NS.DB.theme.reduceMotion = true
        bar:SetScrollPercentage(0.4)
        Check(not state.current.group:IsPlaying() and scroll.offset == 400, "reduced motion changed native scroll behavior")
        NS.DB.theme.reduceMotion = nil
        NS.LegacyScrollMotion.ReleaseOwner("quest-skin")
        providers.bar[2](bar, "quest-skin")
        Check(not next(state.owners) and bar.canInterpolateScroll == false, "quest release leaked ownership or changed native state")
        -- Idempotent re-enable must not create a second observer.
        local hooks = #scroll.hooks.OnVerticalScroll
        NS.LegacyScrollMotion.Track(scroll, "quest-skin")
        Check(#scroll.hooks.OnVerticalScroll == hooks, "re-enable duplicated quest scroll observers")
        NS.LegacyScrollMotion.ReleaseOwner("quest-skin")
        _G[name] = nil
    end
end
local foreign = Controller(false, true)
function foreign:GetName() return "QuestRewardScrollFrameScrollBar" end
Check(Motion.Track(foreign, "foreign") and foreign.canInterpolateScroll,
    "a same-named foreign scrollbar lost normal smoothing")
Motion.ReleaseOwner("foreign")
local Secrets = dofile(root .. "/../MidnightSimpleUnitFrames/tools/tests/classpower_secrets.lua")
Secrets.Install()
Secrets.GUARD_NAMES.falsy.Public = true
secret = Secrets.New("table")
local watched = root .. "/MSUF_Suite_Skin/Rendering/ScrollMotion.lua"
local override = os.getenv("SUITE_SCROLL_OVERRIDE_ROOT")
if override then
    local candidate = override .. "/Rendering/ScrollMotion.lua"
    local handle = io.open(candidate, "rb")
    if handle then handle:close() watched = candidate end
end
local stopWatch = Secrets.Watch(watched, { strict = true })
Check(not Motion.IsQuestScroll(secret) and not Motion.Track(secret, "secret"), "secret target was adopted")
QuestDetailScrollFrame = secret
Check(not Motion.IsQuestScroll(foreign), "secret native identity was compared")
QuestDetailScrollFrame = { ScrollBar = secret }
Check(not Motion.IsQuestScroll(foreign), "secret scrollbar identity was compared")
QuestDetailScrollFrame = nil
local violations = stopWatch()
Check(#violations == 0, "quest identity secret misuse: " .. table.concat(violations, "; "))
print("suite quest completion contract: " .. checks .. " checks passed")
]======]
assert(loadstring(source:sub(1, stop - 1) .. body, "@suite_quest_completion_contract"))()

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
Load("Adapters/AdapterKit.lua")
Load("Rendering/LegacyScrollMotion.lua")
local function AnimationTarget()
    local child = Frame()
    function child:CreateAnimationGroup()
        local group = { scripts = {}, playing = false }
        child.group = group
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
local function Attach(parent, key, frame)
    parent[key] = frame
    function frame:GetParent() return parent end
    return frame
end
WorldMapFrame = Frame()
QuestMapFrame = Attach(WorldMapFrame, "QuestLog", Frame())
local quests = Attach(QuestMapFrame, "QuestsFrame", Frame())
local campaign = Attach(quests, "CampaignOverview", Frame())
local legend = Attach(QuestMapFrame, "MapLegend", Frame())
local eventPage = Attach(QuestMapFrame, "EventsFrame", Frame())
local pages = { "QuestDetailScrollFrame", "QuestProgressScrollFrame", "QuestRewardScrollFrame",
    "QuestGreetingScrollFrame", "QuestLogPopupDetailFrameScrollFrame", "QuestMapDetailsScrollFrame" }
for _, flavor in ipairs({ "Mainline", "Forever" }) do
    NS.Client.isForever = flavor == "Forever"
    if NS.Client.isForever then
        pages[#pages + 1] = "CampaignOverview"
        pages[#pages + 1] = "MapLegendScrollFrame"
    end
    for _, name in ipairs(pages) do
        local scroll, child = Frame(), AnimationTarget()
        local bar = Controller(false, true)
        scroll.ScrollBar, scroll.offset, bar.legacy = bar, 0, scroll
        if name == "CampaignOverview" then
            Attach(campaign, "ScrollFrame", scroll)
        elseif name == "MapLegendScrollFrame" then
            Attach(legend, "ScrollFrame", scroll)
            _G[name] = scroll
        else
            _G[name] = scroll
        end
        Attach(scroll, "ScrollBar", bar)
        function scroll:GetScrollChild() return child end
        function scroll:GetVerticalScroll() return self.offset end
        local set = bar.SetScrollPercentageInternal
        function bar:SetScrollPercentageInternal(value)
            set(self, value)
            scroll:Fire("OnVerticalScroll", scroll.offset)
        end
        function bar:ScrollToBegin(forceImmediate) self:SetScrollPercentage(0, forceImmediate) end
        local original, writes = bar.SetInterpolateScroll, 0
        function bar:SetInterpolateScroll(value)
            writes = writes + 1
            original(self, value)
        end
        local reset, setter = bar.ScrollToBegin, bar.SetInterpolateScroll
        -- Both routes run in the real skin: scrollbar cosmetics and menu discovery.
        if name == "CampaignOverview" or name == "MapLegendScrollFrame" then
            bar:Fire("OnHide")
            providers.bar[1](bar, "hidden-page")
            providers.bar[2](bar, "hidden-page")
            Check(writes == 0, "releasing an unopened map page wrote the native interpolation flag: " .. name)
            bar:Fire("OnShow")
        end
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
        bar:Fire("OnHide")
        Check(not state.current.group:IsPlaying(), "hidden quest content kept moving")
        scroll:Fire("OnShow")
        bar:Fire("OnShow")
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
        Check(writes == 0, flavor .. ": quest skin wrote the native interpolation flag: " .. name)
        if name == "CampaignOverview" or name == "MapLegendScrollFrame" then
            local outside = Controller(false)
            outside.registeredScrollBar = bar
            providers.generic[1](outside, "outside")
            Changed()
            Motion.ReleaseOwner("outside")
            Check(writes == 0, "external controller took the map page's paired scrollbar: " .. name)
        end
        _G[name] = nil
    end
end
local function CheckEventList()
    local box = Attach(eventPage, "ScrollBox", Controller(false))
    local bar = Attach(eventPage, "ScrollBar", Controller(false, true))
    box.registeredScrollBar, bar.registeredScrollBox = bar, box
    local content = AnimationTarget()
    function box:GetScrollTarget() return content end
    function box:GetHeight() return 300 end
    local writes = 0
    for _, controller in ipairs({ bar, box }) do
        local set = controller.SetInterpolateScroll
        function controller:SetInterpolateScroll(value)
            writes = writes + 1
            set(self, value)
        end
    end
    bar:Fire("OnHide")
    box:Fire("OnHide")
    providers.bar[1](bar, "hidden-event")
    providers.bar[2](bar, "hidden-event")
    Check(writes == 0, "releasing unopened map events wrote a native interpolation flag")
    bar:Fire("OnShow")
    box:Fire("OnShow")
    for _ = 1, 2 do
        providers.bar[1](bar, "event-style")
        providers.generic[1](box, "event-motion")
        Check(writes == 0, "map event-list scroll discovery wrote native controller state")
        box:Trigger("scroll", 0.1, 0.5)
        box:Trigger("scroll", 0.2, 0.5)
        Check(content.group and content.group:IsPlaying(), "map event list lost render-only easing")
        box:Fire("OnHide")
        Check(not content.group:IsPlaying(), "hidden map event list kept moving")
        box:Fire("OnShow")
        Changed()
        providers.bar[2](bar, "event-style")
        providers.generic[2]("event-motion")
        Check(not next(box.callbacks.scroll) and writes == 0, "map event-list release touched native state or kept its observer")
    end
    NS.Client.isForever = false
    Check(Motion.Track(bar, "retail-event") and bar.canInterpolateScroll and box.canInterpolateScroll,
        "Retail map event list lost native interpolation")
    Motion.ReleaseOwner("retail-event")
    NS.Client.isForever = true
end
CheckEventList()
WorldMapFrame, QuestMapFrame = nil, nil
-- Forever's list next to the map has a native ScrollFrameTemplate bar.
-- Cosmetics and menu discovery may see it independently, in either combat state.
NS.Client.isForever = true
for _, inCombat in ipairs({ false, true }) do
    combat = inCombat
    for _, original in ipairs({ false, true }) do
        local scroll, child = Frame(), AnimationTarget()
        local listBar = Controller(original, true)
        scroll.ScrollBar, scroll.offset, listBar.legacy = listBar, 0, scroll
        QuestScrollFrame = scroll
        function scroll:GetScrollChild() return child end
        function scroll:GetVerticalScroll() return self.offset end
        local setter = listBar.SetInterpolateScroll
        local function Wheel(_, delta) listBar:SetScrollPercentage(listBar.position - delta * 0.5) end
        scroll:SetScript("OnMouseWheel", Wheel)
        Check(not providers.bar[1](listBar, "quest-map-style") and listBar.canInterpolateScroll == original,
            "Forever quest list styling acquired the native interpolator")
        Check(not NS.LegacyScrollMotion.Track(scroll, "quest-map-motion") and not scroll.hooks.OnVerticalScroll,
            "Forever quest list acquired a legacy render translation")
        Check(not providers.generic[1](listBar, "quest-map-motion"), "direct motion adopted the native quest bar")
        local other = Controller(false)
        other.registeredScrollBar = listBar
        Check(not providers.generic[1](other, "quest-map-partner"), "paired motion adopted the native quest bar")
        Changed()
        Check(listBar.canInterpolateScroll == original and listBar.SetInterpolateScroll == setter,
            "motion refresh changed Forever native scroll ownership")
        scroll:Fire("OnMouseWheel", -1)
        Check(scroll.scripts.OnMouseWheel == Wheel and scroll.offset > 0,
            "Forever native wheel no longer updates the quest list")
        if original then
            Check(listBar.interpolator and listBar.interpolator.destination == 0.5,
                "Forever's native interpolation was canceled")
        else
            Check(scroll.offset == 500 and not listBar.interpolator, "Suite delayed the native quest wheel step")
        end
        Check(not Motion.states[listBar] and not NS.LegacyScrollMotion.states[scroll],
            "Forever's quest list retained a Suite motion controller")
    end
end
combat = false
local foreign = Controller(false, true)
function foreign:GetName() return "QuestScrollFrame" end
Check(Motion.Track(foreign, "lookalike") and foreign.canInterpolateScroll,
    "a lookalike scrollbar lost normal smoothing")
Motion.ReleaseOwner("lookalike")
NS.Client.isForever = false
local retailBar = Controller(false, true)
QuestScrollFrame.ScrollBar = retailBar
Check(Motion.Track(retailBar, "mainline-map") and retailBar.canInterpolateScroll,
    "Mainline's quest list lost normal smoothing")
Motion.ReleaseOwner("mainline-map")
QuestScrollFrame = nil
function foreign:GetName() return "QuestRewardScrollFrameScrollBar" end
Check(Motion.Track(foreign, "foreign") and foreign.canInterpolateScroll,
    "a same-named foreign scrollbar lost normal smoothing")
Motion.ReleaseOwner("foreign")
local Secrets = dofile(root .. "/../MidnightSimpleUnitFrames-7.0/tools/tests/classpower_secrets.lua")
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
NS.Client.isForever = true
QuestScrollFrame = secret
Check(not Motion.IsQuestScroll(foreign), "secret map-side quest list identity was compared")
QuestScrollFrame = { ScrollBar = secret }
Check(not Motion.IsQuestScroll(foreign), "secret map-side quest scrollbar was compared")
QuestScrollFrame = nil
local violations = stopWatch()
Check(#violations == 0, "quest identity secret misuse: " .. table.concat(violations, "; "))
print("suite quest completion contract: " .. checks .. " checks passed")
]======]
assert(loadstring(source:sub(1, stop - 1) .. body, "@suite_quest_completion_contract"))()

local root = assert(arg[1], "repository root required")
local Support = dofile(root .. "/tools/tests/suite_test_support.lua")
local clock = Support.Clock()
local combat, created, reads = false, 0, 0
local secret = {}
InCombatLockdown = function() return combat end
local function Guard(frame)
    assert(not InCombatLockdown() or not frame.protected, "protected frame mutation during combat")
end
local function Widget(parent)
    created = created + 1
    local w = { parent = parent, shown = true }
    function w:CreateTexture() return Widget(self) end
    function w:CreateFontString() return Widget(self) end
    function w:CreateAnimationGroup()
        local group = Widget(self)
        function group:CreateAnimation() return Widget(self) end
        function group:Play() self.playing = true end
        function group:Stop() self.playing = false end
        return group
    end
    function w:SetSize() end
    function w:SetPoint(...) Guard(self); self.point = { ... } end
    function w:ClearAllPoints() end
    function w:SetFrameStrata() end
    function w:EnableMouse() end
    function w:SetJustifyH() end
    function w:SetWordWrap() end
    function w:SetFromAlpha() end
    function w:SetToAlpha() end
    function w:SetDuration() end
    function w:SetScript(key, fn) self[key] = fn end
    function w:SetColorTexture(...) self.color = { ... } end
    function w:SetTextColor(...) self.color = { ... } end
    function w:SetText(value) assert(self.font, "text before font"); self.text = value end
    function w:SetAlpha(value) self.alpha = value end
    function w:SetScale(value) self.scale = value end
    function w:Show() Guard(self); self.shown = true end
    function w:Hide() Guard(self); self.shown = false end
    function w:SetParent(parent) Guard(self); self.parent = parent end
    function w:IsShown() return self.shown end
    function w:IsProtected() return self.protected == true end
    return w
end
UIParent = Widget()
GetZoneText = function() return "Dornogal" end
GetSubZoneText = function() return "" end
C_ChallengeMode = { IsChallengeModeActive = function() return false end }
C_Scenario = { GetInfo = function() return "Scenario", 1, 2 end }
Enum = { EventToastEventType = { QuestTurnedIn = 1, Scenario = 2 } }
GetAchievementInfo = function(id)
    reads = reads + 1
    if id == 404 then return nil end
    if id == 405 then return id, secret end
    return id, "Achievement " .. id, 10, true
end
local S = { instances = {}, editMode = false }
S.Public = function(value) return value ~= secret end
S.Number = function(value) return S.Public(value) and type(value) == "number" and value == value end
S.PublicText = function(value)
    return S.Public(value) and type(value) == "string" and value ~= "" and value or nil
end
S.ReadText = function(fn, ...) return S.PublicText((fn(...))) end
S.Text = function(value) return value end
S.Dispatch = function(fn, ...) return fn(...) end
S.GlobalFontPath = function() return "font" end
S.ResolveFont = function() return "font" end
S.SetStyledFont = function(w) w.font = true end
S.RGB = function() return 1, 1, 1 end
S.CreateFrame = function(_, _, parent) return Widget(parent) end
S.CreateTexture = function(parent) return parent:CreateTexture() end
S.CreateFontString = function(parent) return parent:CreateFontString() end
S.Install = function(id, module) S.instances[id] = module end
local NS = { Safety = { IsForbidden = function() return false end },
    HUDTextArgs = function() end, Dispatch = S.Dispatch, Public = S.Public, Suite = S,
    IsCombatLocked = InCombatLockdown }
local Context = Support.ModuleTimers(root, S, NS)
local active, originalParents, nextProtected = {}, {}, false
AchievementAlertSystem = { alertFramePool = {} }
function AchievementAlertSystem.alertFramePool:EnumerateActive()
    local index = 0
    return function() index = index + 1; return active[index] end
end
function AchievementAlertSystem.setUpFunction(frame, id)
    frame.id = id -- AchievementAlertFrame_SetUp writes the scalar id.
end
function AchievementAlertSystem:ShowAlert(id)
    local frame = Widget(UIParent)
    frame.protected, nextProtected = nextProtected, false
    self.setUpFunction(frame, id)
    active = { frame }
    return frame
end
hooksecurefunc = function(object, key, hook)
    local old = object[key]
    object[key] = function(self, ...)
        local result = old(self, ...)
        hook(self, ...)
        return result
    end
end
assert(loadfile(arg[2] or root .. "/MSUF_Suite_Modules/Announcements.lua"))("MSUF_Suite_Modules", { Suite = S, NS = NS })
local banner = S.instances.announcements
local ctx = Context("announcements", banner, { events = {} })
function ctx:Event(event, callback, options)
    assert(options.inCombat, "announcement event deferred in combat")
    self.events[event] = callback
end
function ctx:Skin() end
function ctx:Mute(frame)
    if frame.protected then return false end
    originalParents[frame] = originalParents[frame] or frame.parent
    frame:SetParent(self)
    return true
end
function ctx:Unmute(frame)
    if originalParents[frame] then
        frame:SetParent(originalParents[frame])
        originalParents[frame] = nil
    end
end
banner.context = ctx
banner.config = { achievements = true, duration = 4, scale = 100, x = 0, y = -90 }
banner:Enable()
local first = AchievementAlertSystem:ShowAlert(11)
assert(banner.showing and banner.host.shown and banner.title.text == "Achievement 11",
    "native scalar achievement alert was hidden without a Suite announcement")
assert(banner.subtitle.text == "ACHIEVEMENT EARNED" and first.parent == ctx)
assert(banner.host.point[1] == "TOP" and banner.host.point[5] == -90, "achievement left the zone banner position")
assert(not ctx.events.ACHIEVEMENT_EARNED,
    "raw achievement events bypass Blizzard's account-repeat and pet-battle eligibility")
combat = true
local second = AchievementAlertSystem:ShowAlert(12)
assert(second.parent == ctx and #banner.queue == 1 and banner.queue[1].title == "Achievement 12",
    "combat achievement was lost")
nextProtected = true
local protected = AchievementAlertSystem:ShowAlert(13)
assert(protected.parent == UIParent and #banner.queue == 1, "protected native alert was converted in combat")
active = { second }
local before = created
for _ = 1, 1000 do banner:ApplyNative() end
assert(created == before and reads == 2 and #banner.queue == 1, "replay allocated frames or reread/duplicated accepted achievements")
local bad = AchievementAlertSystem:ShowAlert(404)
assert(bad.parent == UIParent and #banner.queue == 1, "missing data hid the native fallback")
local private = AchievementAlertSystem:ShowAlert(405)
assert(private.parent == UIParent and #banner.queue == 1, "secret text hid the native fallback")
local privateID = AchievementAlertSystem:ShowAlert(secret)
assert(privateID.parent == UIParent and #banner.queue == 1, "secret id reached the achievement reader")
-- The native pool can reuse a previously muted frame for data we cannot show.
active = { second }
AchievementAlertSystem.setUpFunction(second, 404)
banner:ApplyNative()
assert(second.parent == UIParent, "pooled unreadable achievement retained a previous mute")
local attempted = reads
banner:ApplyNative()
assert(reads == attempted, "native fallback was retried within the same pooled lifetime")
-- Eight pending achievements match native capacity (two showing, six queued).
for id = 13, 19 do AchievementAlertSystem:ShowAlert(id) end
assert(#banner.queue == 8, "achievement burst was truncated below Blizzard's capacity")
for i = 1, 20 do
    banner.config.quests = true
    C_QuestLog = { GetTitleForQuestID = function(id) return "Quest " .. id end }
    ctx.events.QUEST_ACCEPTED(banner, "QUEST_ACCEPTED", i)
end
assert(#banner.queue == 8 and banner.queue[1].title == "Achievement 12",
    "ordinary announcements evicted a pending achievement")
local overflow = AchievementAlertSystem:ShowAlert(20)
assert(#banner.queue == 8 and overflow.parent == UIParent, "full queue silently hid an achievement")
-- Only accepted entries are muted even when two native frames are active.
active = { first, overflow }
banner:ApplyNative()
assert(first.parent == ctx and overflow.parent == UIParent, "fallback was muted by an unrelated accepted alert")
-- A completed Suite banner must not replay while its native frame still lives.
for _ = 1, 9 do banner.leave.OnFinished() end
assert(not banner.showing and #banner.queue == 0)
banner:ApplyNative()
assert(not banner.showing and #banner.queue == 0, "completed native lifetime was replayed")
assert(overflow.parent == UIParent, "native fallback was stolen after capacity freed")
banner.config.achievements = false
banner:Refresh()
assert(first.parent == UIParent and not banner.showing and #banner.queue == 0,
    "off toggle retained an achievement or failed to restore native alerts")
local off = AchievementAlertSystem:ShowAlert(21)
assert(off.parent == UIParent and not banner.showing, "off toggle still replaced achievements")
banner.config.achievements = true
banner:Refresh()
assert(off.parent == ctx and banner.title.text == "Achievement 21", "enable did not adopt an active native achievement")
-- A deferred Blizzard alert is consumed when it actually shows, not before.
local waiting = 22
assert(#banner.queue == 0, "native deferred alert was fabricated early")
AchievementAlertSystem:ShowAlert(waiting)
assert(#banner.queue == 1 and banner.queue[1].title == "Achievement 22")
banner.leave.OnFinished()
assert(banner.title.text == "Achievement 22" and banner.host.shown, "combat queue did not advance")
-- Turning achievements off clears only that kind, preserving queued quests.
banner.config.quests = true
ctx.events.QUEST_ACCEPTED(banner, "QUEST_ACCEPTED", 42)
AchievementAlertSystem:ShowAlert(23)
banner.config.achievements = false
banner:Refresh()
assert(banner.current.kind == "quest" and banner.title.text == "Quest 42" and #banner.queue == 0,
    "off toggle retained achievements or discarded a different announcement kind")
combat = false
-- New unrelated alerts never acquire a per-frame polling loop.
for _, object in ipairs({ banner.host, first, second, overflow }) do assert(not object.OnUpdate) end
print("achievement scalar delivery, native fallback, combat queue, toggles and replay budget passed")

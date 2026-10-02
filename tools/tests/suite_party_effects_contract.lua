local root = assert(arg[1], "repository root required")
-- Offline contract for the party effects banner: own triggers only, the
-- moment named on the banner, one native animation set, timer cleanup.
local secret = setmetatable({}, { __index = function() error("secret value indexed") end })
local function Frame()
    local f = { shown = true, scripts = {} }
    function f:IsShown() return self.shown end
    function f:Show() self.shown = true end
    function f:Hide() self.shown = false end
    function f:SetText(text) self.text = text end
    function f:SetPoint(point, _, _, x, y) self.point, self.x, self.y = point, x, y end
    function f:SetScale(value) self.scale = value end
    function f:CreateAnimationGroup()
        local g = { plays = 0 }
        function g:SetLooping(value) self.looping = value end
        function g:Play() self.plays = self.plays + 1; self.playing = true end
        function g:Stop() self.playing = false end
        function g:CreateAnimation(kind)
            local a = { kind = kind }
            return setmetatable(a, { __index = function(_, key)
                if key:match("^Set") then return function() end end
            end })
        end
        return g
    end
    return setmetatable(f, { __index = function(_, key)
        if key:match("^Set") or key == "EnableMouse" or key == "ClearAllPoints" then return function() end end
    end })
end
UIParent = Frame()
local Support = dofile(root .. "/tools/tests/suite_test_support.lua")
local clock = Support.Clock()
-- The surprise interval draws from math.random; the test fixes the draw.
local draws = {}
math.random = function(low, high)
    draws[#draws + 1] = { low, high }
    return 100
end
local achievements = { [6] = "Stufe 10", [7] = "Gesammelt" }
GetAchievementInfo = function(id) return id, achievements[id] end
C_Spell = { GetSpellName = function(id)
    return ({ [264667] = "Urzorn", [2825] = "Kampfrausch", [80353] = "Zeitkrümmung" })[id]
end }
-- The Suite's own action bar headers as S.VisitPartyActionBars hands them out
-- (out of combat only); each records its animation groups.
local combat, groupsMade = false, 0
local function Header()
    local header = { groups = {} }
    function header:CreateAnimationGroup()
        groupsMade = groupsMade + 1
        local g = { plays = 0 }
        function g:SetLooping(value) self.looping = value end
        function g:Play() self.plays = self.plays + 1; self.playing = true end
        function g:Stop() self.playing = false end
        function g:CreateAnimation(kind)
            local a = { kind = kind }
            function a:SetDegrees(value) self.degrees = value end
            function a:SetOrigin(point) self.origin = point end
            function a:SetOrder() end
            function a:SetDuration(value) self.duration = value end
            g.animation = a
            return a
        end
        self.groups[#self.groups + 1] = g
        return g
    end
    return header
end
local headers = { Header(), Header() }
local S, module = {}, nil
S.Install = function(_, m) module = m end
S.CreateFrame, S.CreateTexture, S.CreateFontString = Frame, Frame, Frame
S.Text = function(text) return ({ ["Level %d"] = "Stufe %d", ["Celebrate!"] = "Feiern!" })[text] or text end
S.SetFont = function() end
S.Finite = function(v) return type(v) == "number" and v == v end
S.Public = function(v) return v ~= secret end
S.PublicText = function(v) return type(v) == "string" and v ~= "" and v or nil end
S.RegisterOwnedMover = function(id, element, spec) S.mover = { id = id, element = element, spec = spec } end
local NS = { Client = {}, IsCombatLocked = function() return combat end,
    Dispatch = function(callback, ...) return callback(...) end }
assert(loadfile(root .. "/MSUF_Suite_QualityOfLife/PartyEffects.lua"))("test", { NS = NS, Suite = S })
module.active = true
module.config = { onLevelUp = true, onAchievement = false, onLust = false, duration = 6, fontSize = 24, scale = 100,
    x = 0, y = 220 }
module.context = Support.ModuleTimers(root, S, NS)("partyEffects", module, { events = {}, units = {},
    Event = function(self, event, fn, _, units) self.events[event], self.units[event] = fn, units end,
    RemoveEvent = function(self, event) self.events[event], self.units[event] = nil, nil end })
local plays, play = 0, module.Play
module.Play = function(...)
    plays = plays + 1
    return play(...)
end
local function Fire(event, ...) assert(module.context.events[event], event)(module, event, ...) end
local function Playing()
    for _, group in ipairs(module.animations) do if not group.playing then return false end end
    return module.host.shown
end

module:Enable()
module:RegisterMovers() -- the controller registers movers after Enable
assert(S.mover.id == "partyEffects" and S.mover.spec.getFrame() == module.host, "the banner lacks its mover")
assert(module.context.events.PLAYER_LEVEL_UP and not module.context.events.ACHIEVEMENT_EARNED
    and not module.context.events.UNIT_SPELLCAST_SUCCEEDED, "only the level-up trigger is on by default")
assert(not module.host.shown, "the banner showed without a moment")
Fire("PLAYER_LEVEL_UP", 80, 1, 1, 0, 0, 1, 1)
assert(Playing() and module.title.text == "Stufe 80", "a level-up did not name the level reached")
clock.Advance(3)
Fire("PLAYER_LEVEL_UP", 81, 1, 1, 0, 0, 1, 1)
clock.Advance(4)
assert(Playing(), "a stale timer ended the newer banner")
clock.Advance(2.1)
assert(not module.host.shown and not module.animations[1].playing, "the duration did not end the banner")

-- Bloodlust-type spells count only for you and your pet.
module.config.onLust, module.config.onAchievement = true, true
module:Refresh()
local units = module.context.units.UNIT_SPELLCAST_SUCCEEDED
assert(type(units) == "table" and units[1] == "player" and units[2] == "pet" and #units == 2,
    "the cast trigger must listen to the player and pet only")
Fire("UNIT_SPELLCAST_SUCCEEDED", "player", secret, secret)
Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-1", 133)
assert(not module.host.shown, "a secret or unrelated spell started the banner")
Fire("UNIT_SPELLCAST_SUCCEEDED", "pet", "Cast-2", 264667)
assert(Playing() and module.title.text == "Urzorn", "the pet's Primal Rage did not start the banner")
for _, spell in ipairs({ 2825, 32182, 80353, 390386, 466904, 444257 }) do
    module:HideEditPreview()
    Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-3", spell)
    assert(module.host.shown, "haste spell " .. spell .. " did not start the banner")
end
assert(module.title.text == "Feiern!", "a haste spell without a client name lost the greeting")
module:HideEditPreview()
Fire("ACHIEVEMENT_EARNED", 7, true)
assert(not module.host.shown, "an achievement the account already had started the banner")
Fire("ACHIEVEMENT_EARNED", 6, false)
assert(Playing() and module.title.text == "Stufe 10", "a new achievement was not named")
module:HideEditPreview()
Fire("ACHIEVEMENT_EARNED", 6, nil)
assert(Playing(), "an achievement without the earlier flag was ignored")

-- A group member's Bloodlust reaches you as its buff.
module.config.onGroupLust = true
module:Refresh()
assert(module.context.units.UNIT_AURA == "player", "the buff trigger must listen to the player only")
Fire("UNIT_AURA", "player", { addedAuras = { { spellId = secret } } })
Fire("UNIT_AURA", "player", { isFullUpdate = true, addedAuras = { { spellId = 80353 } } })
Fire("UNIT_AURA", "player", { removedAuraInstanceIDs = { 4 } })
assert(not module.host.shown, "a secret, full or removal update started the banner")
Fire("UNIT_AURA", "player", { addedAuras = { { spellId = 774 }, { spellId = 80353 } } })
assert(Playing() and module.title.text == "Zeitkrümmung", "a Time Warp buff from the group was not celebrated")
-- Your own Bloodlust plays once: its cast starts the banner, its buff does not.
module:HideEditPreview()
Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-4", 2825)
local ownPlays = module.animations[1].plays
Fire("UNIT_AURA", "player", { addedAuras = { { spellId = 2825, isFromPlayerOrPlayerPet = true } } })
assert(module.animations[1].plays == ownPlays, "your own Bloodlust played its banner twice")
module:HideEditPreview()
Fire("UNIT_AURA", "player", { addedAuras = { { spellId = 2825, isFromPlayerOrPlayerPet = secret } } })
assert(Playing(), "a Bloodlust buff of unknown origin was not celebrated")
module:HideEditPreview()
module.config.onLust = false
Fire("UNIT_AURA", "player", { addedAuras = { { spellId = 2825, isFromPlayerOrPlayerPet = true } } })
assert(Playing(), "without the cast trigger your own Bloodlust buff stayed silent")
module.config.onLust = true
module.config.onGroupLust = false
module:Refresh()
assert(not module.context.events.UNIT_AURA, "a switched-off buff trigger kept listening")

-- Surprise celebrations at random times.
module.config.random, module.config.interval = true, 100
module:Refresh()
local draw = draws[#draws]
assert(draw and draw[1] == 80 and draw[2] == 120, "the surprise interval left 80-120 percent")
plays = 0
clock.Advance(99.9)
assert(plays == 0, "a surprise came early")
clock.Advance(.2)
assert(plays == 1 and Playing() and module.title.text == "Feiern!", "a surprise did not play")
clock.Advance(50)
module:Refresh()
clock.Advance(99.9)
assert(plays == 1, "a refresh kept the earlier surprise")
clock.Advance(.2)
assert(plays == 2, "a surprise did not schedule the next one")
module.config.random = false
module:Refresh()
clock.Advance(130)
assert(plays == 2, "switched-off surprises kept their timer")

-- Spinning the Suite action bars: only outside combat, stopped at the edge.
module.config.rotateActionBars = true
module:Refresh()
module:Play()
assert(module.host.shown and not module.spinning, "the banner needs no ActionBars addon to play")
S.VisitPartyActionBars = function(visitor, owner)
    assert(not combat, "the protected headers were asked to turn in combat")
    for _, header in ipairs(headers) do visitor(owner, header) end
end
module:Play()
local spinA, spinB = headers[1].groups[1], headers[2].groups[1]
assert(spinA and spinA.playing and spinB.playing and spinA.animation.kind == "Rotation"
    and spinA.animation.degrees == 360 and spinA.animation.duration == 6 and spinA.looping == "NONE",
    "the bars did not turn once over the effect duration")
assert(module.context.events.PLAYER_REGEN_DISABLED, "spinning bars did not watch the combat edge")
local made = groupsMade
module:Play()
assert(groupsMade == made and spinA.plays == 2, "a replay made new animation groups")
-- PLAYER_REGEN_DISABLED comes before the lockdown: the turn stops there.
Fire("PLAYER_REGEN_DISABLED")
combat = true
assert(not spinA.playing and not spinB.playing and not module.context.events.PLAYER_REGEN_DISABLED,
    "entering combat left the bars turning")
module:Play()
assert(not spinA.playing and module.host.shown, "bars started turning in combat")
combat = false
module:Play()
assert(spinA.playing, "bars did not turn again after combat")
clock.Advance(6.1)
assert(not spinA.playing and not module.context.events.PLAYER_REGEN_DISABLED, "the effect end left the bars turning")
module.config.duration = 9
module:Play()
assert(spinA.animation.duration == 9, "the spin ignored the effect duration")
module.config.rotateActionBars = false
module:Refresh()
assert(not spinA.playing, "switching the spin off left the bars turning")
module:Play()
assert(not spinA.playing, "a switched-off spin still turned the bars")
module.config.duration = 6

module.config.onLust, module.config.onLevelUp = false, false
module:Refresh()
assert(not module.context.events.UNIT_SPELLCAST_SUCCEEDED and not module.context.events.PLAYER_LEVEL_UP
    and not module.host.shown, "switched-off triggers kept listening or a banner")

-- Edit Mode shows the banner for placing it and nothing else.
S.editMode, module.config.random = true, true
module:Refresh()
assert(module.host.shown and module.title.text == "Feiern!"
    and not module.animations[1].playing, "the Edit Mode sample is missing or animated")
plays = 0
clock.Advance(130)
assert(plays == 0 and module.host.shown, "a surprise or a banner timeout ran in Edit Mode")
module.config.random = false
module:HideEditPreview()
S.editMode = false
module:Refresh()
assert(not module.host.shown, "the Edit Mode sample stayed")
module.config.onAchievement, module.config.random, module.config.rotateActionBars = true, true, true
module:Refresh()
Fire("ACHIEVEMENT_EARNED", 6, false)
assert(spinA.playing, "the disable case needs a turning bar")
-- As the controller stops a module: inactive, Disable, then Release.
module.active = false
module:Disable()
module.context:CancelTimers()
assert(not module.host.shown and not spinA.playing, "disable kept the banner or a turning bar")
plays = 0
module.host.shown = true
clock.Advance(130)
assert(plays == 0 and module.host.shown, "disable kept a surprise or a banner timeout")
module.host.shown = false
module:Play()
assert(not module.host.shown, "an inactive module played the banner")
print("Celebrations: own and group triggers, surprises, bar spin at combat edges, Edit Mode sample and cleanup passed")

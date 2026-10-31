local root = assert(arg[1], "repository root required")
local source = arg[2] or root .. "/MSUF_Suite_QualityOfLife/GroupDeathAlert.lua"
local selected = arg[3]
local Support = dofile(root .. "/tools/tests/suite_test_support.lua")
local SECRET = {}

local function World()
    local w = { combat = false, members = { party1 = false }, names = { party1 = "Alice" },
        ids = { party1 = "Alice-GUID" }, feigned = {}, lines = {}, sounds = 0, events = {}, frames = 0 }
    UIParent, RaidWarningFrame = {}, {}
    GameFontNormalHuge = {}
    ChatTypeInfo = { RAID_WARNING = { r = 1, g = .28, b = 0 } }
    SOUNDKIT = { RAID_WARNING = 1 }
    IsInGroup = function() return true end
    IsInRaid = function() return false end
    UnitExists = function(unit) return w.members[unit] ~= nil end
    UnitIsDeadOrGhost = function(unit) return w.members[unit] or false end
    UnitName = function(unit) return w.names[unit] end
    UnitGUID = function(unit) return w.ids[unit] end
    UnitIsFeignDeath = function(unit) return w.feigned[unit] == true end
    PlaySound = function() w.sounds = w.sounds + 1 end
    GetTime = function() return w.time or 10 end
    local context = {}
    function context:Event(event, callback, options, units)
        assert(options.inCombat, "death event routes must allow combat")
        w.events[event] = { callback = callback, units = units }
    end
    function context:RemoveEvent(event) w.events[event] = nil end
    local suite = {
        Public = function(value) return value ~= SECRET end,
        PublicText = function(value)
            return value ~= SECRET and type(value) == "string" and value ~= "" and value or nil
        end,
        Finite = function(value) return type(value) == "number" end,
        Text = function(text) return text end,
        Print = function(text) w.lines[#w.lines + 1] = text end,
        SetFont = function(frame, _, size, flags) frame.fontSize, frame.fontFlags = size, flags end,
        -- The QoL bootstrap's S.PlaceHost: the same anchor point of the frame and the screen.
        PlaceHost = function(frame, config) frame:SetPoint("CENTER", UIParent, "CENTER", config.x, config.y) end,
        Install = function(_, module) w.module = module end,
        CreateFrame = function(kind, _, parent)
            assert(kind == "MessageFrame" and parent == UIParent, "alerts must own their message frame")
            w.frames = w.frames + 1
            local f = { messages = {} }
            function f:SetSize(width, height) self.width, self.height = width, height end
            function f:SetPoint(...) self.point = { ... } end
            function f:SetFrameStrata(value) self.strata = value end
            function f:SetFrameLevel(value) self.level = value end
            function f:EnableMouse(value) self.mouse = value end
            function f:SetFontObject(value) self.font = value end
            function f:SetJustifyH(value) self.justify = value end
            function f:SetInsertMode(value) self.insert = value end
            function f:SetTimeVisible(value) self.visibleFor = value end
            function f:SetFadeDuration(value) self.fadeFor = value end
            function f:SetFading(value) self.fading = value end
            function f:SetShadowColor(...) self.shadow = { ... } end
            function f:SetShadowOffset(...) self.shadowOffset = { ... } end
            function f:SetSpacing(value) self.spacing = value end
            function f:Show() self.shown = true end
            function f:Hide() self.shown = false end
            function f:Clear() self.messages = {} end
            function f:AddMessage(...) self.messages[#self.messages + 1] = { ... } end
            w.screen = f
            return f
        end,
    }
    local ns = { IsSecret = function(value) return value == SECRET end }
    ns.InCombat = Support.InCombat(root, function() return w.combat end)
    assert(loadfile(source))("MSUF_Suite_QualityOfLife", { NS = ns, Suite = suite })
    w.module.active, w.module.context = true, context
    w.module.config = { screen = true, sound = true, chat = true, scale = 100, point = 5, x = 0, y = 55 }
    function w:Fire(event, ...)
        local route = assert(self.events[event], "missing route " .. event)
        route.callback(self.module, event, ...)
    end
    function w:Start()
        self.module:Enable()
        assert(not self.events.UNIT_HEALTH, "idle groups must not observe health")
        self:Fire("PLAYER_REGEN_DISABLED")
        self.combat = true
        assert(self.events.UNIT_DIED and self.events.UNIT_HEALTH and self.events.UNIT_FLAGS)
    end
    function w:Check(text, count)
        count = count or 1
        assert(#self.lines == count and self.lines[count] == text, "missing/duplicate chat death: " .. text)
        assert(#self.screen.messages == count, "missing/duplicate screen death")
        assert(self.screen.messages[count][1]:find(text, 1, true), "screen text lost the member")
    end
    return w
end

local cases = {}
function cases.visibility()
    local w = World()
    w:Start()
    w:Fire("UNIT_DIED", "Alice-GUID")
    w:Check("Alice died")
    local f, message = w.screen, w.screen.messages[1]
    -- The frame stands on the screen center, its top edge 160 above it as it always did.
    assert(f.point[2] == UIParent and f.point[3] == "CENTER" and f.point[5] + f.height / 2 == 160,
        "death alert follows the movable raid-warning anchor instead of screen center")
    assert(f.fontSize == 36 and f.fontFlags == "OUTLINE", "death alert needs large outlined text")
    assert(message[1]:find("UI-RaidTargetingIcon_8", 1, true) and message[2] == 1 and message[3] == .2,
        "death alert needs its skull and strong red warning")
    assert(f.fading and f.visibleFor == 6 and f.fadeFor == 1 and f.mouse == false,
        "death alert must fade natively and pass input through")
end
function cases.cached_name()
    local w = World()
    w.module:Enable() -- cache the public group identity before lockdown
    w.names.party1 = SECRET
    w:Fire("PLAYER_REGEN_DISABLED")
    w.combat = true
    w:Fire("UNIT_DIED", "Alice-GUID")
    w:Check("Alice died")
    assert(w.sounds == 1, "restricted names suppressed the configured sound")
end
function cases.unavailable_name()
    local w = World()
    w.names.party1 = nil
    w:Start()
    w:Fire("UNIT_DIED", "Alice-GUID")
    w:Check("A group member died")
    assert(w.sounds == 1, "an unavailable name suppressed all alerts")
end
function cases.restricted_name()
    local w = World()
    w.names.party1 = SECRET
    w:Start()
    w.members.party1 = true
    w:Fire("UNIT_HEALTH", "party1")
    w:Check("A group member died")
end
function cases.roster_transition()
    local w = World()
    w:Start()
    w.members.party1 = true
    w:Fire("GROUP_ROSTER_UPDATE")
    w:Fire("UNIT_DIED", "Alice-GUID")
    w:Fire("UNIT_FLAGS", "party1")
    w:Check("Alice died")
end
function cases.settings_transition()
    local w = World()
    w:Start()
    w.members.party1 = true
    w.module:Refresh()
    w:Fire("UNIT_DIED", "Alice-GUID")
    w:Check("Alice died")
end
function cases.stale_alive()
    local w = World()
    w:Start()
    w:Fire("UNIT_DIED", "Alice-GUID")
    w:Fire("UNIT_HEALTH", "party1") -- still alive immediately after UNIT_DIED
    w:Fire("UNIT_FLAGS", "party1")
    w:Fire("GROUP_ROSTER_UPDATE") -- must preserve the pending death too
    w:Fire("UNIT_DIED", "Alice-GUID")
    w:Check("Alice died")
    w.members.party1 = true
    w:Fire("UNIT_FLAGS", "party1")
    w:Check("Alice died")
    w.members.party1, w.time = false, 12
    w:Fire("UNIT_HEALTH", "party1") -- resurrection rearms a later death
    w:Fire("UNIT_DIED", "Alice-GUID")
    w:Check("Alice died", 2)
    assert(w.sounds == 2, "a later death did not rearm the sound")
end
function cases.feign_health()
    local w = World()
    w:Start()
    w.members.party1, w.feigned.party1 = true, true
    w:Fire("UNIT_HEALTH", "party1")
    w:Fire("UNIT_FLAGS", "party1")
    assert(#w.lines == 0 and #w.screen.messages == 0 and w.sounds == 0,
        "Feign Death must not announce through the health fallback")
    w.feigned.party1 = false
    w:Fire("UNIT_HEALTH", "party1")
    w:Check("Alice died")
end
function cases.token_reuse()
    local w = World()
    w:Start()
    w.members.party1, w.ids.party1 = nil, nil
    w:Fire("GROUP_ROSTER_UPDATE")
    w.members.party1, w.ids.party1, w.names.party1 = true, "Bob-GUID", SECRET
    w:Fire("GROUP_ROSTER_UPDATE") -- joining dead is a baseline, not a new death
    assert(#w.lines == 0, "a member joining dead was announced")
    w.members.party1 = false
    w:Fire("UNIT_HEALTH", "party1")
    w:Fire("UNIT_DIED", "Bob-GUID")
    w:Check("A group member died") -- never reuse Alice's cached name for Bob
end
function cases.channels()
    local w = World()
    w.module.config.chat, w.module.config.screen = false, false
    w:Start()
    w:Fire("UNIT_DIED", "Alice-GUID")
    assert(w.sounds == 1 and #w.lines == 0 and not w.screen, "configured output channels were changed")
end

local count = 0
for name, run in pairs(cases) do
    if not selected or selected == name then
        run()
        count = count + 1
    end
end
assert(count > 0, "unknown scenario")
print("Suite group death combat: " .. count .. " scenarios passed")

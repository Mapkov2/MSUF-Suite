-- Offline contract for the optional movement-start cue. Live combat/taint
-- behavior and Blizzard's secret restrictions still need in-client review.
local root = assert(arg[1], "repository root required")
local events, installed = {}, nil
local combat = false
local Support = dofile(root .. "/tools/tests/suite_test_support.lua")
local clock = Support.Clock(100)
local known, cooldown, usable, realCooldown = {}, {}, {}, {}
local cooldownBlocked = false
local calls = { known = 0, cooldown = 0, usable = 0 }

local function Region()
    local region = { shown = true }
    function region:SetSize() end
    function region:SetFrameStrata() end
    function region:EnableMouse() end
    function region:SetAllPoints() end
    function region:SetPoint() end
    function region:ClearAllPoints() end
    function region:SetScale() end
    function region:SetColorTexture() end
    function region:SetTextColor() end
    function region:SetWidth() end
    function region:SetJustifyH() end
    function region:SetTexture(value) self.texture = value end
    function region:SetText(value) self.text = value end
    function region:Show() self.shown = true end
    function region:Hide() self.shown = false end
    function region:IsShown() return self.shown end
    function region:SetScript() error("movement cue must not poll") end
    return region
end

UIParent = Region()
C_SpellBook = { IsSpellKnown = function(id)
    calls.known = calls.known + 1
    return known[id]
end }
C_Spell = {
    GetSpellCooldown = function(id)
        calls.cooldown = calls.cooldown + 1
        -- Restricted cooldowns come back secret (SecretWhenCooldownsRestricted); nothing raises.
        if cooldownBlocked then return "secret" end
        return cooldown[id]
    end,
    -- The cooldown without the global cooldown (ignoreGCD), as a duration.
    GetSpellCooldownDuration = function(id, ignoreGCD)
        assert(ignoreGCD == true, "the movement cue read the cooldown with the GCD")
        local running = realCooldown[id]
        if running == nil then return nil end
        return { HasSecretValues = function() return running == "secret" end,
            IsActive = function() return running end }
    end,
    IsSpellUsable = function(id)
        calls.usable = calls.usable + 1
        return usable[id]
    end,
    GetSpellName = function(id) return "Spell " .. id end,
    GetSpellTexture = function(id) return id + 1000 end,
}

local ns = { IsCombatLocked = function() return combat end,
    AnchorPoints = { [5] = "CENTER" }, Dispatch = function(callback, ...) return callback(...) end }
local suite = {}
local context = Support.ModuleTimers(root, suite, ns)("combatMovementCue", nil, {})
function context:Event(name, callback) events[name] = callback end
function context:RemoveEvent(name) events[name] = nil end
local config = { spellIDs = "invalid,0;101,101 102 10000000", combatOnly = true,
    point = 5, x = 0, y = -120, scale = 100 }
for key, value in pairs({
    Install = function(id, module)
        assert(id == "combatMovementCue")
        installed = module
        suite.instances[id] = module
        module.active, module.context, module.config = true, context, config
    end,
    CreateFrame = Region, CreateTexture = Region, CreateFontString = Region,
    SetFont = function() end, Text = function(value) return value end,
    Public = function(value) return value ~= "secret" end,
    PublicText = function(value)
        return type(value) == "string" and value ~= "secret" and value or nil
    end,
    Finite = function(value)
        return type(value) == "number" and value == value
            and value > -math.huge and value < math.huge
    end,
    RegisterOwnedMover = function(id) assert(id == "combatMovementCue") end,
    Config = function() return config end,
}) do suite[key] = value end

assert(loadfile(root .. "/tools/tests/suite_test_support.lua"))().QoLStyleFixture(root, suite)
local chunk = assert(loadfile(root .. "/MSUF_Suite_QualityOfLife/CombatMovementCue.lua"))
chunk("MSUF_Suite_QualityOfLife", { NS = ns, Suite = suite })
local cue = assert(installed)
cue:Enable()
assert(events.PLAYER_STARTED_MOVING and #cue.ids == 2
    and cue.ids[1] == 101 and cue.ids[2] == 102, "only unique public configured IDs")
assert(not cue.host:IsShown() and clock.Queued() == 0, "idle cue stays hidden")

known[101], known[102] = true, true
cooldown[101], cooldown[102] =
    { isActive = false, isEnabled = true }, { isActive = false, isEnabled = true }
usable[101], usable[102] = true, true
events.PLAYER_STARTED_MOVING(cue)
assert(not cue.host:IsShown() and calls.known == 0, "combat-only gate skips lookups")
combat = true
events.PLAYER_STARTED_MOVING(cue)
assert(cue.host:IsShown() and cue.icon.texture == 1101
    and cue.label.text == "Spell 101 ready for movement" and clock.Queued() == 1,
    "first ready configured ability appears on movement start")
clock.now = 101
events.PLAYER_STARTED_MOVING(cue)
assert(clock.Queued() == 1 and cue.icon.texture == 1101, "repeated movement is throttled")
-- The clock jumps past the first timeout without a frame: its wait fires
-- only on the next frame, after the newer cue restarted the timeout.
clock.now = 121
cooldown[101].isActive, realCooldown[101] = true, true
events.PLAYER_STARTED_MOVING(cue)
assert(cue.icon.texture == 1102, "active cooldown is skipped and next ready ability is chosen")
clock.Frame(0)
assert(cue.host:IsShown(), "stale timeout cannot hide newer cue")
clock.Advance(2.4)
assert(cue.host:IsShown(), "the newer cue hid before its timeout")
clock.Advance(.2)
assert(not cue.host:IsShown(), "cue expires without frame polling")

clock.now = 142
cooldown[101] = "secret"
usable[102] = "secret"
events.PLAYER_STARTED_MOVING(cue)
assert(not cue.host:IsShown() and clock.Queued() == 0,
    "secret cooldown result or usability fails silently")
clock.now, cooldownBlocked = 143, true
events.PLAYER_STARTED_MOVING(cue)
local blockedReads = calls.cooldown
clock.now = 143.2
events.PLAYER_STARTED_MOVING(cue)
assert(not cue.host:IsShown() and calls.cooldown == blockedReads,
    "restricted cooldown reads were not safely throttled")
cooldownBlocked = false
-- Only the global cooldown runs: the ability counts as ready.
clock.now = 170
cooldown[101], realCooldown[101] = { isActive = true, isEnabled = true }, nil
events.PLAYER_STARTED_MOVING(cue)
assert(cue.host:IsShown() and cue.icon.texture == 1101 and clock.Queued() == 1,
    "an ability waiting only for the global cooldown was not offered")
clock.Advance(2.6)
assert(not cue.host:IsShown(), "the cue did not expire")

config.spellIDs = ""
cue:Refresh()
assert(not events.PLAYER_STARTED_MOVING, "empty configuration removes movement listener")
config.spellIDs = "102"
usable[102] = true
cue:Refresh()
assert(events.PLAYER_STARTED_MOVING, "configured ability restores event listener")
suite.editMode = true
cue:Refresh()
assert(cue.host:IsShown() and cue.label.text == "Movement ability ready",
    "Edit Mode shows a placement sample")
clock.now = 200
events.PLAYER_STARTED_MOVING(cue)
clock.Advance(3)
assert(clock.Queued() == 0 and cue.host:IsShown() and cue.label.text == "Movement ability ready",
    "Edit Mode cannot show a live cue")
suite.editMode = false
cue:Disable()
assert(not cue.host:IsShown(), "disable hides placement sample")
print("Suite contextual movement cue lifecycle passed")

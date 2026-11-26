local root = assert(arg[1])
local function NewWidget()
    local w = { visible = false }
    function w:Show() self.visible = true end
    function w:Hide() self.visible = false end
    function w:SetShown(value) self.visible = value end
    function w:IsShown() return self.visible end
    function w:SetCooldown(start, duration) self.timer = { start, duration } end
    function w:Clear() self.timer = nil end
    function w:SetText(value) self.text = value end
    function w:Play() self.playing = true end
    function w:Stop() self.playing = false end
    function w:IsPlaying() return self.playing end
    w.CreateTexture, w.CreateFontString, w.CreateAnimationGroup, w.CreateAnimation = NewWidget, NewWidget, NewWidget, NewWidget
    return setmetatable(w, { __index = function(_, key)
        if key:sub(1, 3) == "Set" or key == "EnableMouse" or key == "ClearAllPoints" then return function() end end
    end })
end

local secret = {}
local stacks, restricted, sounds = 0, false, 0
local function Public(value) return value ~= secret end
local function Finite(value) return type(value) == "number" and math.abs(value) < math.huge end
local function Once()
    return function() end
end
canaccesstable = function(value) return value ~= secret end
wipe = function(data) for key in pairs(data) do data[key] = nil end end
GetTime = function() return 50 end
SOUNDKIT = { RAID_WARNING = 1 }
PlaySound = function() sounds = sounds + 1 end
C_Spell = { GetSpellName = function(id) return "Spell " .. id end, GetSpellTexture = function() return 3021 end }
C_Secrets = { ShouldSpellAuraBeSecret = function() return restricted end }
C_UnitAuras = { GetPlayerAuraBySpellID = function(id)
    assert(not restricted and id == 99, "restricted aura or wrong override")
    return { applications = stacks, expirationTime = 60, duration = 10 }
end }
local module
local S = {
    CreateFrame = NewWidget, SetFont = Once(), PlaceHost = Once(), RGB = function() return 1, .5, .3 end,
    Install = function(_, value) module = value end, Public = Public, Finite = Finite,
    PublicText = function(value) return Public(value) and type(value) == "string" and value or nil end,
    Text = function(value) return value end,
}
assert(loadfile(root .. "/MSUF_Suite_QualityOfLife/ProcAlerts.lua"))("QoL", { Suite = S, NS = {} })
local handlers = {}
module.context = {
    Event = function(_, event, callback) handlers[event] = callback end,
    RemoveEvent = function(_, event) handlers[event] = nil end,
}
module.config = { mode = 2, spells = "11", auraOverrides = "11:99", auraDetails = true,
    minimumStacks = 2, color = "ffffff", pulse = true, pulseSpeed = 440, sound = true }
local function Fire(event, value)
    local handler = handlers[event]
    if handler then handler(module, event, value) end
end
module:Enable()
assert(not handlers.UNIT_AURA, "no glow should leave the aura event dormant")
local show, hide = "SPELL_ACTIVATION_OVERLAY_GLOW_SHOW", "SPELL_ACTIVATION_OVERLAY_GLOW_HIDE"
Fire(show, secret)
Fire(show, 11)
assert(handlers.UNIT_AURA and module.shown == 0, "readable stacks below the threshold must be hidden")
stacks = 2
Fire("UNIT_AURA", "player")
assert(module.shown == 1 and sounds == 1)
assert(module.cues[1].cooldown.timer[2] == 10 and module.cues[1].stacks.text == 2)
Fire(show, 11)
assert(module.shown == 1 and sounds == 1, "duplicate native glow")
restricted = true
Fire("ADDON_RESTRICTION_STATE_CHANGED")
assert(module.shown == 1 and module.cues[1].cooldown.timer == nil,
    "a reliable glow remains, but the restricted aura timer is withdrawn")
Fire(hide, 11)
assert(module.shown == 0 and not handlers.UNIT_AURA)

Fire(show, 11)
S.editMode = true
module:Refresh()
assert(module.shown == 1 and module.cues[1].text.text == "Proc alert")
Fire(hide, 11)
assert(module.shown == 1, "native events cannot hide the edit sample")
S.editMode = false
module:Refresh()
assert(module.shown == 0)
module:Disable()
assert(not module.host.visible)
print("Proc alerts validated")

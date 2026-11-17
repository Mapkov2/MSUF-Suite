local root = assert(arg[1])
local secret = setmetatable({}, { __tostring = function() error("read restricted value") end })
local reads, writes, measures, hooks = 0, 0, 0, 0
local function Public(value) return not rawequal(value, secret) end
local private = { NS = {
    Public = Public,
    Finite = function(value) return Public(value) and type(value) == "number" and value > -math.huge and value < math.huge end,
    Safety = { IsForbidden = function(widget) return widget.forbidden end },
} }
assert(loadfile(root .. "/MSUF_Suite_Nameplates/CastAppearance.lua"))("MSUF_Suite_Nameplates", private)

local scenario = { name = "Éruption solaire", delay = 400, channel = "Canalisation" }
function UnitCastingInfo(unit)
    assert(unit == "nameplate1")
    reads = reads + 1
    return nil, scenario.name, nil, nil, nil, nil, nil, nil, nil, nil, scenario.delay
end

function UnitChannelInfo(unit)
    assert(unit == "nameplate1")
    reads = reads + 1
    return nil, scenario.channel
end

function hooksecurefunc(widget, key, callback)
    hooks = hooks + 1
    local original = assert(widget[key])
    widget[key] = function(self, ...)
        original(self, ...)
        callback(self, ...)
    end
end

local label = { value = scenario.name, available = true, left = 8 }
function label:CanBeAccessedInContext() return self.available end
function label:GetLeft() return self.left end
function label:GetUnboundedStringWidthForText(value)
    assert(Public(value) and self.available == true, "attempted measurement in a restricted context")
    measures = measures + 1
    local _, chars = value:gsub("[^\128-\191]", "")
    return chars
end
function label:SetText(value)
    assert(self.available == true, "attempted write on an inaccessible label")
    writes = writes + 1
    self.value, self.seconds = value, nil
end
function label:SetFormattedText(format, value, seconds)
    assert(self.available == true and format == "%s +%.1f" and rawequal(value, secret))
    writes = writes + 1
    self.value, self.seconds = value, seconds
end

local cast = { unit = "nameplate1", Text = label, right = 36, shown = true, casting = true }
function cast:CanBeAccessedInContext() return true end
function cast:GetRight() return self.right end
function cast:IsShown() return self.shown end
function cast:HandleCastStart(kind)
    self.casting, self.channeling, self.reverseChanneling = kind ~= "channel", kind == "channel", kind == "empower"
    label.value, label.seconds = (kind == "channel" or kind == "empower") and scenario.channel or scenario.name, nil
end
function cast:HandleCastDelayed() end

local path = os.getenv("SUITE_CAST_TEXT_STYLE_OVERRIDE") or root .. "/MSUF_Suite_Nameplates/CastTextStyle.lua"
assert(loadfile(path))("MSUF_Suite_Nameplates", private)
local Style = assert(private.CastTextStyle)
local settings = { shortenName = true, nameMax = 6, nameReserve = 0, showPushback = true }
assert(Style.Apply(cast, settings))
assert(label.value == "Érupti... +0.4", "late attachment split a UTF-8 character or dropped the pushback")
local beforeReads, beforeWrites = reads, writes
for _ = 1, 25 do assert(Style.Apply(cast, settings)) end
assert(reads == beforeReads and writes == beforeWrites and measures == 0 and hooks == 2)

scenario.delay = 800
cast:HandleCastDelayed()
assert(label.value == "Érupti... +0.8")
settings = { shortenName = true, nameMax = 15, nameReserve = 12, showPushback = true }
assert(Style.Apply(cast, settings) and label.value == "Éruption... +0.8" and measures > 0)
local publicMeasures = measures
scenario.name, scenario.delay = secret, 300
cast:HandleCastStart("cast")
assert(rawequal(label.value, secret) and label.seconds == .3 and measures == publicMeasures)
assert(Style.Restore(cast) and rawequal(label.value, secret) and label.seconds == nil)

settings = { shortenName = true, nameMax = 6, nameReserve = 12 }
scenario.delay = secret
assert(Style.Apply(cast, settings))
cast:HandleCastStart("cast")
assert(rawequal(label.value, secret) and measures == publicMeasures and hooks == 2)
cast:HandleCastStart("channel")
assert(label.value == "Canali..." and label.seconds == nil)
cast:HandleCastStart("empower")
assert(label.value == "Canali..." and label.seconds == nil)

scenario.name, scenario.delay = "An ordinary spell", 0
cast.right = secret
cast:HandleCastStart("cast")
assert(label.value == "An ord...", "secret layout must fall back to the character cap")
label.available = secret
assert(not Style.Restore(cast), "an inaccessible label did not request a retry")
label.available = true
assert(Style.Restore(cast) and label.value == scenario.name)
local afterRestore = writes
cast:HandleCastStart("cast")
assert(writes == afterRestore and label.value == scenario.name, "a released cast still receives formatting")

assert(Style.Apply(cast, settings))
cast.casting, label.value = nil, "Interrupted"
cast:HandleCastDelayed()
assert(Style.Apply(cast, { shortenName = true, nameMax = 2 }) and label.value == "Interrupted")
assert(Style.Restore(cast) and label.value == "Interrupted")
print("Native cast text: shared shortening, reserved width, pushback, restricted labels and release passed")

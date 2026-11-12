-- The clock the client writes (S.ElapsedClock, MSUF_Suite_Modules/Surfaces.lua, 2026-11-11).
-- A duration text binding shows the time since its duration's start as S.ClockText does, and the client
-- writes it: no Lua per second. The format rests on the numeric rule formatter's components, which the
-- client documents and no Blizzard file calls, so the product has the client format known times before it
-- hands the format out. This contract runs that proof against a client that does what the documentation
-- says (NumericRuleFormatterSharedDocumentation.lua, upstream/live 297d7aaa and forever 9dc84f0d) and
-- against clients that do not; whether the game client is one of the first kind only the game can say.
local root = assert(arg[1], "repository root required")
local secret = {}
local now = 5000

-- The numeric rule formatter as documented: the rule with the highest threshold not above the value; each
-- component divides (div), takes the remainder (mod), then rounds to its step; the format takes one number
-- per component.
local ROUNDING = { Nearest = 0, Up = 1, Down = 2 }
local function Step(value, step, rounding)
    if not step then return value end
    local scaled = value / step
    if rounding == ROUNDING.Down then return math.floor(scaled) * step end
    if rounding == ROUNDING.Up then return math.ceil(scaled) * step end
    return math.floor(scaled + .5) * step
end
local function FormatRule(formatter, value, quirk)
    local rule
    local picked = quirk == "picks the rule by the rounded value" and math.floor(value + .5) or value
    for _, candidate in ipairs(formatter.rules) do
        local reached = picked >= candidate.threshold
        if quirk == "takes a threshold as exclusive" then reached = picked > candidate.threshold end
        if reached and (not rule or candidate.threshold > rule.threshold) then rule = candidate end
    end
    if quirk == "first rule only" then rule = formatter.rules[1] end
    if not rule then return "" end
    if not rule.components or quirk == "no components" then return rule.format:format(value, value, value) end
    local numbers = {}
    for index, component in ipairs(rule.components) do
        local number = value
        if component.div then number = number / component.div end
        if component.mod then number = math.fmod(number, component.mod) end
        local nearest = quirk == "rounds to nearest" or quirk == "rounds the seconds to nearest" and not component.div
            or quirk == "rounds the hours to nearest" and component.div == 3600
        number = Step(number, component.step, nearest and ROUNDING.Nearest or component.rounding or ROUNDING.Nearest)
        -- A number the rule did not round is printed to the nearest whole one: the unkind reading of "%d".
        numbers[index] = math.floor(number + .5)
    end
    return rule.format:format(unpack(numbers))
end

-- One load of Surfaces.lua against a client with the given quirk (nil: as documented).
local function Client(quirk)
    local made = { formatters = 0, bindings = {}, frames = {} }
    local Suite = { Suite = {} }
    Suite.Public = function(value) return value ~= secret end
    Suite.Finite = function(value) return value ~= secret and type(value) == "number" and value == value end
    -- securecallfunction: a call that raises returns nothing.
    Suite.Dispatch = function(fn, ...)
        local results = { pcall(fn, ...) }
        if results[1] then return unpack(results, 2) end
        made.raised = true
    end
    Suite.Finish = function(fn, ...) return true, fn(...) end
    _G.MSUFSuite = Suite
    GetTime = function() return now end
    -- The proof makes no frame and no font string.
    CreateFrame = function() error("the proof made a frame") end
    Enum = { DurationTextBindingProperty = { RemainingDuration = 0, ElapsedDuration = 2, TotalDuration = 4 },
        NumericRuleFormatRounding = ROUNDING }
    if quirk == "no rounding enumeration" then Enum.NumericRuleFormatRounding = nil end
    C_StringUtil = { CreateNumericRuleFormatter = function()
        made.formatters = made.formatters + 1
        local formatter = { rules = {} }
        function formatter:AddBreakpoint(rule)
            if quirk == "raises" then error("bad argument #1 to 'AddBreakpoint'") end
            self.rules[#self.rules + 1] = rule
        end
        return formatter
    end }
    C_DurationUtil = {
        CreateDuration = function()
            local duration = {}
            function duration:SetTimeFromStart(start, span)
                -- Early after a boot a start before the clock's zero is not a time.
                assert(start >= 0, "a duration was started before the clock's zero")
                self.start, self.span = start, span
            end
            return duration
        end,
        CreateDurationTextBinding = function()
            local binding = { enabled = true }
            function binding:SetEnabled(value) self.enabled = value end
            function binding:SetFontString(value) self.fontString = value end
            function binding:SetTextFormat(format, components) self.format, self.components = format, components end
            function binding:SetDuration(value) self.duration = value end
            function binding:GetFormattedText()
                if quirk == "empty text" then return "" end
                if quirk == "secret text" then return secret end
                local index = 0
                return (self.format:gsub("{}", function()
                    index = index + 1
                    local component = self.components[index]
                    local property = Enum.DurationTextBindingProperty
                    assert(component.property == property.ElapsedDuration or component.property == property.TotalDuration)
                    local seconds = component.property == property.TotalDuration and self.duration.span or GetTime() - self.duration.start
                    return FormatRule(component.formatter, seconds, quirk)
                end))
            end
            made.bindings[#made.bindings + 1] = binding
            return binding
        end,
    }
    assert(loadfile(root .. "/MSUF_Suite_Modules/Surfaces.lua"))("MSUF_Suite_Modules", {})
    return Suite.Suite, made
end

-- 1. A client that formats as documented: the format is handed out, once proven.
local S, made = Client()
local format = S.ElapsedClock()
assert(type(format) == "table" and #format == 1 and format[1].property == 2 and format[1].formatter,
    "a client that formats as documented did not get the clock")
assert(S.ElapsedClock() == format and S.ElapsedClock() == format and made.formatters == 1 and #made.bindings == 1,
    "the proof ran more than once")
assert(not made.raised, "the proof raised on a client that formats as documented")
-- The probe is never enabled and writes to nothing.
assert(made.bindings[1].enabled == false and made.bindings[1].fontString == nil, "the proof left a live binding behind")
assert(S.CLOCK_SPAN >= 86400, "a clock would run out within a day")
-- The format reads as S.ClockText for every second of two hours and a quarter, at the start, the middle
-- and the end of the second.
for whole = 0, 8100 do
    for _, part in ipairs({ 0, .5, .999 }) do
        local seconds = whole + part
        local text = FormatRule(format[1].formatter, seconds)
        assert(text == S.ClockText(seconds), ("%.3f s reads '%s' on the client and '%s' in S.ClockText"):format(seconds, text, S.ClockText(seconds)))
    end
end

-- 2. A client that does anything else gets no clock, and its callers keep their tickers.
for _, quirk in ipairs({ "no components", "rounds to nearest", "rounds the seconds to nearest", "rounds the hours to nearest",
    "takes a threshold as exclusive", "picks the rule by the rounded value", "first rule only", "empty text", "secret text",
    "no rounding enumeration", "raises" }) do
    local other, record = Client(quirk)
    assert(other.ElapsedClock() == nil, "a client that " .. quirk .. " got the clock")
    assert(other.ElapsedClock() == nil and record.formatters <= 1, "a client that " .. quirk .. " was asked again")
    -- A missing part raises inside the proof; the raise stays there (the product's isolating call).
    assert((record.raised == true) == (quirk == "raises" or quirk == "no rounding enumeration"),
        "the proof raised on a client that " .. quirk)
end
-- 3. One minute after a boot the proof still passes: no time it asks about starts before the clock's zero.
now = 60
local early = Client()
assert(early.ElapsedClock() ~= nil, "a correct client one minute after its boot did not get the clock")
now = 5000
print("PASS elapsed clock: proven on a client that formats as documented, refused on every other")

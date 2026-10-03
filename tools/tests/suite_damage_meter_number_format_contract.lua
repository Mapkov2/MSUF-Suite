local root = assert(arg[1], "repository root required")
-- The Damage Meter formats every amount, plain or secret, through the one
-- native formatter (AbbreviateNumbers), as Blizzard's own meter formats all
-- its values with one native call (DamageMeterEntry.lua, GetEntryValueText).
-- Out of combat the values are plain, in combat secret: a plain value
-- formatted in Lua would change its look at every combat edge on a client
-- whose abbreviations are not English. "Use English K/M/B" decides the
-- format of both. Unchanged plain values reach no native call (the memo).

------------------------------------------------------------------ secrets
-- Strict secrets: comparison, arithmetic, concatenation, indexing and
-- tostring raise. The stand-in C sinks below read the hidden value.
local SecretMT = {}
local function Raise(what) return function() error("secret value used: " .. what, 2) end end
for _, key in ipairs({ "__add", "__sub", "__mul", "__div", "__mod", "__pow", "__unm", "__concat", "__lt", "__le",
    "__eq", "__call", "__len" }) do
    SecretMT[key] = Raise(key)
end
SecretMT.__index, SecretMT.__newindex, SecretMT.__tostring = Raise("index"), Raise("assignment"), Raise("tostring")
local hidden = setmetatable({}, { __mode = "k" })
local function Secret(value)
    local secret = setmetatable({}, SecretMT)
    hidden[secret] = value
    return secret
end
local function IsSecret(value) return getmetatable(value) == SecretMT end
local function Reveal(value) if IsSecret(value) then return hidden[value] end return value end
issecretvalue = IsSecret

------------------------------------------------------------------ native formatter
-- AbbreviateNumbers after its documented breakpoint rule
-- (LocalizationSharedDocumentation.lua): pairs at a named order with
-- fractionDivisor 10 and one order higher with fractionDivisor 1, so 1234 is
-- "1.2k" and 12345 "12k". Without options it uses the client's own
-- abbreviations; this client is German. A secret number gives a secret string.
local GERMAN = { { 1e10, " Mrd.", 1e9, 1 }, { 1e9, " Mrd.", 1e8, 10 }, { 1e7, " Mio.", 1e6, 1 },
    { 1e6, " Mio.", 1e5, 10 }, { 1e4, " Tsd.", 1e3, 1 }, { 1e3, " Tsd.", 1e2, 10 } }
local natives = 0
local function Format(value, points, comma)
    local number, suffix = tostring(value), ""
    for _, point in ipairs(points) do
        if value >= point[1] then
            number, suffix = tostring(math.floor(value / point[3]) / point[4]), point[2]
            break
        end
    end
    if comma then number = number:gsub("%.", ",") end
    return number .. suffix
end
AbbreviateNumbers = function(value, options)
    natives = natives + 1
    assert(type(Reveal(value)) == "number", "AbbreviateNumbers takes a number")
    local text
    if options then
        local points = {}
        for _, point in ipairs(assert(options.config, "options without the cached config").points) do
            assert(point.abbreviationIsGlobal == false, "the English config must use raw suffixes")
            points[#points + 1] = { point.breakpoint, point.abbreviation, point.significandDivisor, point.fractionDivisor }
        end
        text = Format(Reveal(value), points, false)
    else
        text = Format(Reveal(value), GERMAN, true)
    end
    return IsSecret(value) and Secret(text) or text
end
CreateAbbreviateConfig = function(points) return { points = points } end

------------------------------------------------------------------ client
Ambiguate = function(name) return name end
Enum = { DamageMeterType = { DamageDone = 0, Dps = 1, HealingDone = 2, Hps = 3, Absorbs = 4, Interrupts = 5,
    Dispels = 6, DamageTaken = 7, AvoidableDamageTaken = 8, Deaths = 9, EnemyDamageTaken = 10 } }
C_DamageMeter = {}
local NS = { IsSecret = IsSecret, DamageMeterVisibility = {}, DamageMeterSession = {}, DamageMeterIconStyle = {},
    DamageMeterRowBorder = {}, DamageMeterTextStyle = {},
    DamageMeterValueFormat = { RATE = 1, PRIMARY = 2, PARENTHESES = 3, BAR = 4, CUSTOM = 5 } }
local S = { Public = function(value) return not IsSecret(value) end,
    Finite = function(value) return not IsSecret(value) and type(value) == "number" and value == value end }
local P = { NS = NS, Suite = S }
for _, file in ipairs({ "Data.lua", "Rows.lua" }) do
    assert(loadfile(root .. "/MSUF_Suite_DamageMeter/" .. file))("MSUF_Suite_DamageMeter", P)
end
local D = P.DamageMeter
local FORMAT, TYPE = NS.DamageMeterValueFormat, Enum.DamageMeterType

-- A FontString: SetText and SetFormattedText are C sinks that accept secrets.
local function Row()
    local text = {}
    function text:SetText(value) self.shown = Reveal(value) end
    function text:SetFormattedText(pattern, ...)
        local args = { ... }
        for i = 1, select("#", ...) do args[i] = Reveal(args[i]) end
        self.shown = string.format(pattern, unpack(args, 1, select("#", ...)))
    end
    return { valueText = text }
end

local function Configure(english, style)
    D.M.config = { englishNumbers = english }
    D.M.style = style
    D.ConfigureAbbreviation()
end

-- The same fight read after combat (plain) and during it (secret).
local TOTAL, RATE, SHARE = 12345678, 123456, 24691356
local function Paint(meterType, secret)
    local row = Row()
    local total, rate = TOTAL, RATE
    if secret then total, rate = Secret(TOTAL), Secret(RATE) end
    D.SetValueText(row, meterType, total, rate, SHARE, false)
    return row.valueText.shown
end

local styles = {
    { numberFormat = FORMAT.PRIMARY },
    { numberFormat = FORMAT.RATE },
    { numberFormat = FORMAT.PARENTHESES },
    { numberFormat = FORMAT.BAR },
    { numberFormat = FORMAT.CUSTOM, valueOrder = 1, valueSeparator = 2 },
    { numberFormat = FORMAT.CUSTOM, valueOrder = 3, valueSeparator = 4 },
}
local expected = {
    [false] = { total = "12 Mio.", rate = "123 Tsd." },
    [true] = { total = "12M", rate = "123K" },
}
for _, english in ipairs({ false, true }) do
    for index, style in ipairs(styles) do
        Configure(english, style)
        for _, meterType in ipairs({ TYPE.DamageDone, TYPE.Dps, TYPE.Interrupts }) do
            local plain, secret = Paint(meterType, false), Paint(meterType, true)
            assert(plain == secret, ("format %d, meter %d, English %s: %q after combat, %q in combat"):format(
                index, meterType, tostring(english), tostring(plain), tostring(secret)))
        end
    end
    Configure(english, { numberFormat = FORMAT.PRIMARY })
    local words = expected[english]
    assert(Paint(TYPE.DamageDone, false) == words.total and Paint(TYPE.Dps, false) == words.rate,
        "English " .. tostring(english) .. " did not decide the plain format: " .. Paint(TYPE.DamageDone, false))
    -- A share needs plain values (a secret is never used in arithmetic); the
    -- amounts beside it keep the combat format.
    Configure(english, { numberFormat = FORMAT.PARENTHESES, percent = true })
    assert(Paint(TYPE.DamageDone, false) == Paint(TYPE.DamageDone, true) .. " 50%",
        "the plain share changed the amounts' format: " .. Paint(TYPE.DamageDone, false))
end

-- Native calls: one per shown amount when a plain value changed, none for an
-- unchanged repaint; secret values have no memo.
Configure(false, { numberFormat = FORMAT.PARENTHESES })
local row = Row()
natives = 0
D.SetValueText(row, TYPE.DamageDone, TOTAL, RATE, SHARE, false)
assert(natives == 2, "a changed plain row made " .. natives .. " native calls, not 2")
D.SetValueText(row, TYPE.DamageDone, TOTAL, RATE, SHARE, false)
assert(natives == 2, "an unchanged plain row reached the native formatter")
D.SetValueText(row, TYPE.DamageDone, TOTAL + 1, RATE, SHARE, false)
assert(natives == 4, "a changed plain total did not repaint both amounts")
D.SetValueText(row, TYPE.DamageDone, Secret(TOTAL), Secret(RATE), SHARE, false)
D.SetValueText(row, TYPE.DamageDone, Secret(TOTAL), Secret(RATE), SHARE, false)
assert(natives == 8 and row.valueText.shown == "12 Mio. (123 Tsd.)", "secret amounts must reach the native formatter")
Configure(false, { numberFormat = FORMAT.CUSTOM, valueOrder = 1, valueSeparator = 2 })
row, natives = Row(), 0
D.SetValueText(row, TYPE.DamageDone, TOTAL, RATE, SHARE, false)
D.SetValueText(row, TYPE.DamageDone, TOTAL, RATE, SHARE, false)
assert(natives == 2, "the custom layout made " .. natives .. " native calls for one changed plain row, not 2")
print("Damage meter number format: plain and secret amounts share the native format, English K/M/B for both, memo passed")

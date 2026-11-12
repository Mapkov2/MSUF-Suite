local _, Private = ...
local Suite = assert(_G.MSUFSuite, "MSUF_Suite is required")
local S = Suite.Suite
-- Classic MSUF exports its pixel layout helper; Main MSUF does not. Without it,
-- suite surfaces keep the client's native layout rounding.
local PixelLayoutRegion = _G.MSUF_PixelLayoutRegion or function(region, policy, ...)
    if type(policy) == "string" then return region[policy](region, ...) end
    return region
end

-- All constructors are configuration-time helpers. They mark only surfaces
-- created by this addon; native frames passed to modules remain native-owned.
function S.CreateFrame(...)
    return PixelLayoutRegion(CreateFrame(...))
end

function S.CreateTexture(parent, ...)
    return PixelLayoutRegion(parent:CreateTexture(...))
end

function S.CreateFontString(parent, ...)
    return PixelLayoutRegion(parent:CreateFontString(...))
end

-- Settings store colors as six hex digits (MSUF_Suite/Core/Platform.lua).
S.RGB = Suite.RGB

-- How usable an action or cooldown icon is, and the vertex color each state
-- takes: the one definition the cooldown manager and the action bars share.
-- Out of range is a state of its own, painted in the bar's own range color.
S.USABLE = { USABLE = 1, NO_POWER = 2, UNUSABLE = 3, OUT_OF_RANGE = 4 }
S.USABLE_TINT = {
    [S.USABLE.USABLE] = { 1, 1, 1 },
    [S.USABLE.NO_POWER] = { .5, .5, 1 },
    [S.USABLE.UNUSABLE] = { .4, .4, .4 },
}

-- Blizzard's client-localized global string, else the English text through
-- the suite locale. Shared by the damage meter and the minimap.
function S.BlizzardText(global, english)
    local value = global and _G[global]
    if type(value) == "string" and value ~= "" then return value end
    return S.Text(english)
end

-- Class colors come from NeverSecret class tokens only; unknown tokens return nil.
function S.ClassRGB(classFile)
    if type(classFile) ~= "string" or classFile == "" then return nil end
    local palette = _G.CUSTOM_CLASS_COLORS or _G.RAID_CLASS_COLORS
    local color = type(palette) == "table" and palette[classFile]
    if type(color) ~= "table" then return nil end
    return color.r, color.g, color.b
end

-- One field of a client info table (completion info, criteria) whose fields
-- may be secret: the readable value, or nil.
function S.PublicField(info, key)
    if not Suite.Public(info) or type(info) ~= "table" then return nil end
    local value = info[key]
    return Suite.Public(value) and value or nil
end

-- Seconds as m:ss or h:mm:ss, "--:--" while unknown. Countdowns round up
-- (a timer with 0.4 s left still shows 0:01).
function S.ClockText(seconds, roundUp)
    if not Suite.Finite(seconds) then return "--:--" end
    seconds = math.max(0, roundUp and math.ceil(seconds) or math.floor(seconds))
    if seconds >= 3600 then
        return string.format("%d:%02d:%02d", math.floor(seconds / 3600), math.floor(seconds / 60) % 60, seconds % 60)
    end
    return string.format("%d:%02d", math.floor(seconds / 60), seconds % 60)
end

-- The same clock written by the client. S.ElapsedClock() gives the text
-- format of a duration text binding that shows the time since its duration's
-- start as S.ClockText does (m:ss, h:mm:ss from an hour on). Bound to a font
-- string the client writes the text once a second: no Lua runs for a running
-- clock, where a 1 s ticker ran a paint.
-- The numeric rule formatter's components (div, mod, step) are documented on
-- Retail and Forever (NumericRuleFormatterSharedDocumentation.lua,
-- upstream/live 297d7aaa and forever 9dc84f0d) but no Blizzard file calls
-- them, so the documentation alone does not say what a client prints. The
-- first caller therefore has the client format known times and compares:
-- zero, which is a clock's first text; times three quarters into their
-- second, and past the half of their minute and of their hour, so a client
-- that rounds anywhere instead of cutting off prints another text; and one
-- just under the hour, for a client that picks the hour's rule early.
-- The long times are a duration's length (TotalDuration through the same
-- formatter), not a start in the past: early after a boot such a start
-- would lie before the clock's zero.
-- A client that prints anything else, lacks a part or raises gets nil here
-- for the session, and the caller keeps its own ticker.
local PROOF = { { 0, "0:00" }, { 59.75, "0:59" },
    { 155.75, "2:35", true }, { 3599.75, "59:59", true }, { 7175.75, "1:59:35", true } }
local clockFormat, clockAsked
-- The length of a clock's duration: a clock never runs out.
S.CLOCK_SPAN = 7 * 86400

local function ProveClock()
    local down = Enum.NumericRuleFormatRounding.Down
    local formatter = C_StringUtil.CreateNumericRuleFormatter()
    formatter:AddBreakpoint({ threshold = 0, format = "%d:%02d", components = {
        { div = 60, step = 1, rounding = down }, { mod = 60, step = 1, rounding = down } } })
    formatter:AddBreakpoint({ threshold = 3600, format = "%d:%02d:%02d", components = {
        { div = 3600, step = 1, rounding = down }, { div = 60, mod = 60, step = 1, rounding = down },
        { mod = 60, step = 1, rounding = down } } })
    local property = Enum.DurationTextBindingProperty
    local components = { { property = property.ElapsedDuration, formatter = formatter } }
    local length = { { property = property.TotalDuration, formatter = formatter } }
    -- A binding of its own, never enabled and without a font string: it is
    -- only asked for the text it would write.
    local duration, binding = C_DurationUtil.CreateDuration(), C_DurationUtil.CreateDurationTextBinding()
    binding:SetEnabled(false)
    local now = GetTime()
    for index = 1, #PROOF do
        local seconds, wanted, asLength = PROOF[index][1], PROOF[index][2], PROOF[index][3]
        if asLength then duration:SetTimeFromStart(now, seconds) else duration:SetTimeFromStart(now - seconds, S.CLOCK_SPAN) end
        binding:SetTextFormat("{}", asLength and length or components)
        binding:SetDuration(duration)
        local text = binding:GetFormattedText()
        if not Suite.Public(text) or text ~= wanted then return nil end
    end
    return components
end

function S.ElapsedClock()
    if not clockAsked then
        clockAsked = true
        -- Dispatch returns nothing when the proof raised.
        local finished, components = Suite.Dispatch(Suite.Finish, ProveClock)
        clockFormat = finished and components or nil
    end
    return clockFormat
end

-- The class color as six hex digits (the settings' color format), or nil.
function S.ClassHex(classFile)
    local r, g, b = S.ClassRGB(classFile)
    if not Suite.Finite(r) or not Suite.Finite(g) or not Suite.Finite(b) then return nil end
    return string.format("%02x%02x%02x", math.floor(r * 255 + .5), math.floor(g * 255 + .5),
        math.floor(b * 255 + .5))
end

-- Short key text shared by action bars and cooldown icons: SHIFT/CTRL/ALT/META
-- become S/C/A/M, mouse buttons M4, the wheel MwU/MwD, numpad N1 and N+.
-- Gamepad keys keep Blizzard's glyph markup.
local KEY_NAMES = {
    MOUSEWHEELUP = "MwU", MOUSEWHEELDOWN = "MwD", MIDDLEMOUSE = "M3", CAPSLOCK = "Caps",
    SPACE = "Spc", BACKSPACE = "Bs", INSERT = "Ins", DELETE = "Del", HOME = "Hm", END = "End",
    PAGEUP = "PU", PAGEDOWN = "PD", ESCAPE = "Esc", ENTER = "Ent", TAB = "Tab",
    NUMPADDECIMAL = "N.", NUMPADPLUS = "N+", NUMPADMINUS = "N-", NUMPADMULTIPLY = "N*", NUMPADDIVIDE = "N/",
    UP = "Up", DOWN = "Dn", LEFT = "Lt", RIGHT = "Rt",
}
local KEY_MODIFIERS = { SHIFT = "S", CTRL = "C", ALT = "A", META = "M" }
local keyTexts = {}

local function ShortKey(key)
    if key:find("PAD", 1, true) and not key:find("NUMPAD", 1, true) then
        return GetBindingText(key, true)
    end
    local modifiers, base = "", key
    while true do
        local modifier, rest = base:match("^(%u+)%-(.+)$")
        local short = modifier and KEY_MODIFIERS[modifier]
        if not short then break end
        modifiers, base = modifiers .. short, rest
    end
    local button = base:match("^BUTTON(%d+)$")
    local numpad = base:match("^NUMPAD(%d)$")
    return modifiers .. (KEY_NAMES[base] or button and "M" .. button or numpad and "N" .. numpad or base)
end

-- Binding keys are plain strings (never secret); "" for no key.
function S.KeyText(key)
    if type(key) ~= "string" or key == "" then return "" end
    local text = keyTexts[key]
    if not text then
        text = ShortKey(key)
        keyTexts[key] = text
    end
    return text
end

-- Money as "12g 3s 4c" (zero parts left out, "0c" for nothing), with the
-- client's own coin symbols (GOLD_, SILVER_ and COPPER_AMOUNT_SYMBOL, the ones
-- Blizzard's CoinPickupFrame shows). The caller adds any sign; amount is a
-- non-negative copper value.
function S.MoneyText(amount)
    local gold, silver, copper = math.floor(amount / 10000), math.floor(amount % 10000 / 100), amount % 100
    local text = gold > 0 and gold .. GOLD_AMOUNT_SYMBOL or nil
    if silver > 0 then
        text = text and text .. " " .. silver .. SILVER_AMOUNT_SYMBOL or silver .. SILVER_AMOUNT_SYMBOL
    end
    if copper > 0 or not text then
        text = text and text .. " " .. copper .. COPPER_AMOUNT_SYMBOL or copper .. COPPER_AMOUNT_SYMBOL
    end
    return text
end

-- One physical screen pixel in UI units at UIParent's scale; nil when the
-- client cannot tell (unreadable or zero sizes).
function S.PixelUnit()
    local _, height = GetPhysicalScreenSize()
    local scale = UIParent:GetEffectiveScale()
    if not Suite.Number(height) or not Suite.Number(scale) or height <= 0 or scale <= 0 then return nil end
    return 768 / height / scale
end

-- Four edge textures (set[1..4]) inside owner's rect; the side edges stop
-- short of the top and bottom ones so translucent colors do not double at
-- the corners. No width only hides them: points and color are written when
-- they show again. Shared by the action bars and the cooldown manager.
function S.PlaceEdges(set, owner, width, r, g, b, a)
    if not (width > 0) then
        for i = 1, 4 do set[i]:SetShown(false) end
        return
    end
    for i = 1, 4 do
        local edge = set[i]
        edge:ClearAllPoints()
        edge:SetColorTexture(r, g, b, a or 1)
        edge:SetShown(true)
    end
    set[1]:SetPoint("TOPLEFT", owner, "TOPLEFT")
    set[1]:SetPoint("TOPRIGHT", owner, "TOPRIGHT")
    set[1]:SetHeight(width)
    set[2]:SetPoint("BOTTOMLEFT", owner, "BOTTOMLEFT")
    set[2]:SetPoint("BOTTOMRIGHT", owner, "BOTTOMRIGHT")
    set[2]:SetHeight(width)
    set[3]:SetPoint("TOPLEFT", owner, "TOPLEFT", 0, -width)
    set[3]:SetPoint("BOTTOMLEFT", owner, "BOTTOMLEFT", 0, width)
    set[3]:SetWidth(width)
    set[4]:SetPoint("TOPRIGHT", owner, "TOPRIGHT", 0, -width)
    set[4]:SetPoint("BOTTOMRIGHT", owner, "BOTTOMRIGHT", 0, width)
    set[4]:SetWidth(width)
end

-- Font and texture keys of MSUF and SharedMedia (MSUF_Suite/Core/Platform.lua).
S.ResolveFont, S.ResolveTexture = Suite.ResolveFont, Suite.ResolveTexture
S.GlobalFontPath = Suite.GlobalFontPath

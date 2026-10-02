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

-- Money as "12g 3s 4c" (zero parts left out, "0c" for nothing). The caller
-- adds any sign; amount is a non-negative copper value.
function S.MoneyText(amount)
    local gold, silver, copper = math.floor(amount / 10000), math.floor(amount % 10000 / 100), amount % 100
    local text = gold > 0 and gold .. "g" or nil
    if silver > 0 then text = text and text .. " " .. silver .. "s" or silver .. "s" end
    if copper > 0 or not text then text = text and text .. " " .. copper .. "c" or copper .. "c" end
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

-- Blizzard builds its shared font objects at startup on every supported client.
local nativeFont
local function NativeFont()
    if not nativeFont then nativeFont = GameFontHighlightSmall:GetFont() end
    return nativeFont
end
S.NativeFontPath = NativeFont

-- Prefer the host's font setter. Older hosts use the native font fallback
-- below when an external font cannot be applied.
function S.SetFont(fontString, path, size, flags)
    path = path or S.GlobalFontPath()
    flags = flags or ""
    -- Classic may report false before its glyph metrics become ready. The
    -- host setter keeps the chosen face instead of treating this as failure.
    local checked = _G.MSUF_SetFontChecked
    if type(checked) == "function" then
        checked(fontString, path, size, flags)
        return flags
    end
    if fontString:SetFont(path, size, flags) == false then
        if fontString:SetFont(NativeFont(), size, flags) == false then
            -- Some clients or font files do not support optional rendering
            -- flags. Keep the text visible with the native font.
            fontString:SetFont(NativeFont(), size, "")
            return ""
        end
    end
    return flags
end

-- Text effects are shared by Suite-owned FontStrings. Slug renders its own
-- crisp edge; WoW does not combine it with thick outlines or drop shadows.
-- rendering is a "Font rendering" choice (NS.FontRendering).
local RENDERING = Suite.FontRendering
function S.FontFlags(outline, rendering)
    outline = outline or ""
    if rendering == RENDERING.SLUG then
        return outline == "" and "SLUG" or "OUTLINE,SLUG"
    end
    if rendering == RENDERING.SHARP and not outline:find("MONOCHROME", 1, true) then
        return outline == "" and "MONOCHROME" or outline .. ",MONOCHROME"
    end
    return outline
end

function S.SetStyledFont(fontString, path, size, outline, rendering, shadow, opacity, distance)
    local flags = S.SetFont(fontString, path, size, S.FontFlags(outline, rendering))
    local applyScaleMode = _G.MSUF_ApplyFontScaleAnimationMode
    if type(applyScaleMode) == "function" then applyScaleMode(fontString, flags) end
    local showShadow = shadow == true and rendering ~= RENDERING.SLUG
    fontString:SetShadowColor(0, 0, 0, showShadow and (opacity or 100) / 100 or 0)
    if showShadow then
        local offset = distance or 1
        fontString:SetShadowOffset(offset, -offset)
    else
        fontString:SetShadowOffset(0, 0)
    end
    return flags
end

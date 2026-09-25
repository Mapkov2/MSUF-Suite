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

-- Settings store colors as six hex digits (validated by the controller).
function S.RGB(hex)
    if type(hex) ~= "string" or #hex ~= 6 then return 1, 1, 1 end
    return (tonumber(hex:sub(1, 2), 16) or 255) / 255,
        (tonumber(hex:sub(3, 4), 16) or 255) / 255,
        (tonumber(hex:sub(5, 6), 16) or 255) / 255
end

-- Class colors come from NeverSecret class tokens only; unknown tokens return nil.
function S.ClassRGB(classFile)
    if type(classFile) ~= "string" or classFile == "" then return nil end
    local palette = _G.CUSTOM_CLASS_COLORS or _G.RAID_CLASS_COLORS
    local color = type(palette) == "table" and palette[classFile]
    if type(color) ~= "table" then return nil end
    return color.r, color.g, color.b
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
    if key:find("PAD", 1, true) and not key:find("NUMPAD", 1, true) and type(GetBindingText) == "function" then
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

local function LSM()
    local stub = _G.LibStub
    return type(stub) == "table" and type(stub.GetLibrary) == "function" and stub:GetLibrary("LibSharedMedia-3.0", true) or nil
end

-- Font keys are MSUF/SharedMedia font keys; "" means the native font.
function S.ResolveFont(key)
    if type(key) ~= "string" or key == "" then return nil end
    -- MSUF's font list may hand out file paths as selection values.
    if key:find("\\", 1, true) or key:find("/", 1, true) then return key end
    local resolve = _G.MSUF_ResolveFontKeyPath or _G.MSUF_GetFontPathForKey
    local path = type(resolve) == "function" and resolve(key) or nil
    if type(path) ~= "string" or path == "" then
        local media = LSM()
        path = media and media:Fetch("font", key, true) or nil
    end
    return type(path) == "string" and path ~= "" and path or nil
end

-- Texture keys are MSUF/SharedMedia statusbar keys; "" means the caller's default.
function S.ResolveTexture(key, fallback)
    if type(key) ~= "string" or key == "" then return fallback end
    local resolve = _G.MSUF_ResolveStatusbarTextureKey
    if type(resolve) == "function" then
        local path = resolve(key)
        if type(path) == "string" and path ~= "" then return path end
    end
    local media = LSM()
    local path = media and media:Fetch("statusbar", key, true) or nil
    return type(path) == "string" and path ~= "" and path or fallback
end

local nativeFont
local function NativeFont()
    if not nativeFont then
        local object = _G.GameFontHighlightSmall or _G.GameFontNormal
        nativeFont = object and object:GetFont() or _G.STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF"
    end
    return nativeFont
end
S.NativeFontPath = NativeFont

-- Applies a font with a guaranteed fallback: a missing external font must
-- never leave a string without any font.
function S.SetFont(fontString, path, size, flags)
    path = path or NativeFont()
    flags = flags or ""
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
function S.FontFlags(outline, rendering)
    outline = outline or ""
    if rendering == 3 then
        return outline == "" and "SLUG" or "OUTLINE,SLUG"
    end
    if rendering == 2 and not outline:find("MONOCHROME", 1, true) then
        return outline == "" and "MONOCHROME" or outline .. ",MONOCHROME"
    end
    return outline
end

function S.SetStyledFont(fontString, path, size, outline, rendering, shadow, opacity, distance)
    local flags = S.SetFont(fontString, path, size, S.FontFlags(outline, rendering))
    local applyScaleMode = _G.MSUF_ApplyFontScaleAnimationMode
    if type(applyScaleMode) == "function" then applyScaleMode(fontString, flags) end
    local showShadow = shadow == true and rendering ~= 3
    fontString:SetShadowColor(0, 0, 0, showShadow and (opacity or 100) / 100 or 0)
    if showShadow then
        local offset = distance or 1
        fontString:SetShadowOffset(offset, -offset)
    else
        fontString:SetShadowOffset(0, 0)
    end
    return flags
end

local _, NS = ...
local S = NS.Suite

-- MSUF's full font apply also covers cold-start font recovery. Every active
-- Suite module restyles its text while explicit module font choices stay
-- intact: most modules draw with the MSUF font without a font setting of
-- their own, so a hand-kept list of text modules cannot stay complete.
local lastPath, lastEpoch
S.FontRevision = 0
local function ApplyBlizzardFont()
    local skin = NS.Skin
    if not skin or not skin.enabled then return end
    local engine = _G.MapkoSkin
    if type(engine) ~= "table" or engine.addonName ~= "MSUF_Suite_Skin"
        or not engine.DB or engine.DB.enabled ~= true or not engine.DB.typography
        or engine.DB.typography.enabled ~= true or engine.DB.typography.followMSUF == false then
        return
    end
    local typography = engine.Typography
    if typography and type(typography.ApplyConfigured) == "function" then
        typography.ApplyConfigured()
    end
end
function S.ApplyGlobalFont()
    if not S.started then return end
    local path, epoch = NS.GlobalFontPath(), _G.MSUF_FontApplyEpoch
    if path == lastPath and epoch == lastEpoch then return end
    lastPath, lastEpoch = path, epoch
    S.FontRevision = S.FontRevision + 1
    ApplyBlizzardFont()
    local order = S.order
    for i = 1, #order do
        local id = order[i]
        if S.states[id].active then S.Apply(id) end
    end
end
_G.MSUFSuite_ApplyFontsFromMSUF = S.ApplyGlobalFont

-- One always-loaded painter owns runtime and cold preview font behavior.
S.GlobalFontPath = NS.GlobalFontPath
-- Blizzard builds its shared font objects at startup on every supported client.
local nativeFont
local function NativeFont()
    if not nativeFont then nativeFont = GameFontHighlightSmall:GetFont() end
    return nativeFont
end
S.NativeFontPath = NativeFont

-- Prefer the host's font setter; older hosts set the font natively. A font
-- the client refused falls back to the native font, so a missing external
-- font never leaves a string without any font.
function S.SetFont(fontString, path, size, flags)
    path = path or S.GlobalFontPath()
    flags = flags or ""
    -- MSUF's setter answers the client's own result on Retail and Forever
    -- (Kernel/MSUF_Libs.lua of the Classic host): false is a refused font,
    -- unless the string shows the requested file anyway (Platform.lua).
    local checked = _G.MSUF_SetFontChecked
    local applied
    if type(checked) == "function" then
        applied = checked(fontString, path, size, flags) ~= false or NS.FontFileApplied(fontString, path)
    else
        applied = fontString:SetFont(path, size, flags) ~= false
    end
    if not applied then
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
local RENDERING = NS.FontRendering
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

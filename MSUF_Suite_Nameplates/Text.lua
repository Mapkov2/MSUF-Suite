local _, private = ...
local NS, S = private.NS, private.Suite
local Style = NS.NameplateStyle
local originals = setmetatable({}, { __mode = "k" })
local Text = { originals = originals }
private.Text = Text

function Text.Bind(module) Text.module = module end

-- Nameplates are pooled: a region keeps one flat record for all its leases,
-- so a plate cycle allocates nothing (2026-10-02 raid trace). The record:
--   [1..3] native font, [4..7] native shadow color, [8..9] native shadow
--   offset, [10..13] native text color.
--   shadowState, offsetState, colorState: false = this lease holds no native
--   value (not read, withheld), 1 = native held and never written by the
--   Suite, 2 = native held and written: the release owes it back. A slot of
--   an earlier lease is never read, its state went false on that release.
--   fontSet, fontScale: the font this lease wrote and the scale it ran.
--   A value the Suite never wrote is still Blizzard's and is not written back
--   (2026-11-16 trace: 150 restore font/shadow pairs and 125 tints per 25 plates).
function Text.Invalidate(region)
    local original = originals[region]
    if original then original.appliedShadow, original.appliedColor = nil, false end
end

function Text.Restore(region)
    local original = originals[region]
    if not original or original.restored or NS.Safety.IsForbidden(region) then return end
    if original.fontSet then
        local scale = original.fontScale
        if scale then
            scale(region, original[3])
            -- The scale of this lease only: gone once it ran for its release.
            original.fontScale = false
        end
        region:SetFont(original[1], original[2], original[3])
        original.fontSet = false
    end
    if original.shadowState == 2 then region:SetShadowColor(original[4], original[5], original[6], original[7]) end
    if original.offsetState == 2 then region:SetShadowOffset(original[8], original[9]) end
    if original.colorState == 2 then region:SetTextColor(original[10], original[11], original[12], original[13]) end
    original.shadowState, original.offsetState, original.colorState = false, false, false
    -- No applied font: the next Apply is a new lease and reads its natives.
    original.appliedColor, original.appliedPath, original.restored = false, false, true
end

-- Text.Apply, snapshot: one snapshot path for a new record, a recycled lease
-- (no applied font) and a font swapped from outside: the font read is the
-- native one, and the shadow color and offset read with it are the region's
-- current ones, compared later instead of written. A withheld value keeps its
-- state: false in a new lease, this lease's earlier native in a running one.
-- Text.Apply, shadow: a shadow captured in the same call is the region's own
-- (the scale and font setters write neither): an equal one is left alone.
-- Without that read (invalidated, withheld, a retried font) it is written,
-- and owed back only where this lease holds the native value.

local function ApplyTint(region, original, color, Finite)
    if not color then
        if original.colorState == 2 then
            region:SetTextColor(original[10], original[11], original[12], original[13])
        end
        original.colorState, original.appliedColor = false, false
    elseif original.appliedColor ~= color then
        if original.colorState then
            -- A kept native color (invalidated or another tint): the
            -- current color is unknown and is written.
            region:SetTextColor(color.r, color.g, color.b, color.a)
            original.colorState, original.appliedColor = 2, color
        else
            -- A color read now is compared; a withheld one waits.
            local r, g, b, a = region:GetTextColor()
            if Finite(r) and Finite(g) and Finite(b) and Finite(a) then
                original[10], original[11], original[12], original[13] = r, g, b, a
                if r ~= color.r or g ~= color.g or b ~= color.b or a ~= (color.a or 1) then
                    region:SetTextColor(color.r, color.g, color.b, color.a)
                    original.colorState = 2
                else
                    original.colorState = 1
                end
                original.appliedColor = color
            end
        end
    end
end

local function ApplyShadowOffset(region, original, style, fontChanged, Finite)
    local held = original.offsetState
    local x, y
    if fontChanged or not held then
        x, y = region:GetShadowOffset()
        if Finite(x) and Finite(y) then
            original[8], original[9] = x, y
            original.offsetState = held or 1
        else
            x, y = nil, nil
        end
    end
    local targetX, targetY = 0, 0
    if style.shadow then targetX, targetY = style.shadowX or 1, style.shadowY or -1 end
    if x ~= targetX or y ~= targetY then
        region:SetShadowOffset(targetX, targetY)
        if original.offsetState then original.offsetState = 2 end
    end
end

function Text.Apply(region, style, size, tint)
    if not region or NS.Safety.IsForbidden(region) then return end
    if not style.enabled then
        Text.Restore(region)
        return true
    end
    local Finite, Public = S.Finite, S.Public
    local path, nativeSize, flags = region:GetFont()
    if not Public(path) or type(path) ~= "string" or path == ""
        or not Finite(nativeSize) or not Public(flags) then return end
    local original = originals[region]
    if not original then
        original = { false, false, false, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
            restored = true, fontSet = false, fontScale = false, shadowState = false, offsetState = false,
            colorState = false, appliedColor = false, appliedPath = false, appliedSize = false,
            appliedFlags = false, appliedShadow = false }
        originals[region] = original
    end
    local shadowRead, sr, sg, sb, sa
    local fontChanged = path ~= original.appliedPath or nativeSize ~= original.appliedSize or flags ~= original.appliedFlags
    if fontChanged then
        original[1], original[2], original[3] = path, nativeSize, flags or ""
        original.appliedPath, original.appliedSize, original.appliedFlags = path, nativeSize, flags
        original.appliedShadow, original.restored = nil, false
        sr, sg, sb, sa = region:GetShadowColor()
        if Finite(sr) and Finite(sg) and Finite(sb) and Finite(sa) then
            shadowRead = true
            original[4], original[5], original[6], original[7] = sr, sg, sb, sa
            if not original.shadowState then original.shadowState = 1 end
        end
    end
    if tint then ApplyTint(region, original, style.color, Finite) end
    local face, height, styleFlags = style.font or original[1], size > 0 and size or original[2], style.flags
    local shadowKey = style.shadowKey or style.shadow
    if path ~= face or nativeSize ~= height or flags ~= styleFlags then
        original.fontSet = true
        local scale = style.fontScale
        if scale then
            scale(region, styleFlags)
            original.fontScale = scale
        end
        S.SetFont(region, face, height, styleFlags)
        -- 2026-10-26 M+ trace: only a font write can change the values just read.
        local appliedPath, appliedSize, appliedFlags = region:GetFont()
        if Public(appliedPath) and Finite(appliedSize) and Public(appliedFlags) then
            original.appliedPath, original.appliedSize, original.appliedFlags = appliedPath, appliedSize, appliedFlags
        end
    elseif original.appliedShadow == shadowKey then
        return true
    end
    local alpha = style.shadow and (style.shadowAlpha or 1) or 0
    if not shadowRead or sr ~= 0 or sg ~= 0 or sb ~= 0 or sa ~= alpha then
        region:SetShadowColor(0, 0, 0, alpha)
        if original.shadowState then original.shadowState = 2 end
    end
    if style.shadow or original.offsetState then ApplyShadowOffset(region, original, style, fontChanged, Finite) end
    original.appliedShadow = shadowKey
    return true
end

local hiddenHealthFonts = setmetatable({}, { __mode = "k" })
local watchedHealth = setmetatable({}, { __mode = "k" })

local function PaintHealthFonts(health, style)
    local size = style.healthSize
    local center = Text.Apply(health.Text, style, size, true)
    local left = Text.Apply(health.LeftText, style, size, true)
    local right = Text.Apply(health.RightText, style, size, true)
    return center and left and right
end

local function OnHealthShown(health)
    local style = hiddenHealthFonts[health]
    if not style or NS.Safety.IsForbidden(health) then return end
    if PaintHealthFonts(health, style) then hiddenHealthFonts[health] = nil end
end

function Text.ApplyHealth(health, style, namesOnly)
    -- Native SetShowOnlyName hides the entire health bar on both clients.
    -- Keep the requested style for its next OnShow in the same unit lease.
    if style.enabled and S.Public(namesOnly) and namesOnly == true then
        hiddenHealthFonts[health] = style
        if not watchedHealth[health] then
            health:HookScript("OnShow", OnHealthShown)
            watchedHealth[health] = true
        end
        return
    end
    hiddenHealthFonts[health] = nil
    PaintHealthFonts(health, style)
end

function Text.CancelHealth(health)
    if S.Public(health) and health then hiddenHealthFonts[health] = nil end
end

function Text.RestoreHealth(health)
    hiddenHealthFonts[health] = nil
    Text.Restore(health.Text)
    Text.Restore(health.LeftText)
    Text.Restore(health.RightText)
end

-- Blizzard keeps these labels on its pooled castbar, including while it is
-- hidden. Bind the style on acquire and paint it only when a cast is shown.
local castFonts = setmetatable({}, { __mode = "k" })
local watchedCasts = setmetatable({}, { __mode = "k" })

local function PaintCastFonts(cast)
    local style = castFonts[cast]
    if not style or NS.Safety.IsForbidden(cast) then return end
    Text.Apply(cast.Text, style.spell or style, style.size, true)
    Text.Apply(cast.CastTargetNameText, style, style.size, true)
end

function Text.RestoreCast(cast)
    if not S.Public(cast) or not cast or not watchedCasts[cast] then return end
    castFonts[cast] = nil
    if NS.Safety.IsForbidden(cast) then return end
    Text.Restore(cast.Text)
    Text.Restore(cast.CastTargetNameText)
end

function Text.ApplyCast(cast, style)
    if not S.Public(cast) or not cast or NS.Safety.IsForbidden(cast) then return end
    if not style.enabled then
        Text.RestoreCast(cast)
        return
    end
    castFonts[cast] = style
    if not watchedCasts[cast] then
        cast:HookScript("OnShow", PaintCastFonts)
        watchedCasts[cast] = true
    end
    local shown = cast:IsShown()
    if not S.Public(shown) or shown then PaintCastFonts(cast) end
end

function Text.Configure(config, castStyle)
    local shared = NS.NameplateText.Shared(config)
    Text.shared = shared
    local result = {}
    for _, prefix in ipairs({ "enemy", "friendly", "enemyCast", "friendlyCast" }) do
        result[prefix] = NS.NameplateText.FontStyle(config, prefix, shared)
    end
    for _, prefix in ipairs({ "enemyCast", "friendlyCast" }) do
        local style = result[prefix]
        if style.enabled and castStyle and castStyle.textR and castStyle.textG and castStyle.textB then
            local spell = {}
            for key, value in pairs(style) do spell[key] = value end
            spell.color = { r = castStyle.textR, g = castStyle.textG, b = castStyle.textB, a = castStyle.textA }
            style.spell = spell
        end
        local size = config[prefix .. "TimeSize"] or 0
        if size > 0 then
            local timeStyle = {}
            if style.enabled then
                for key, value in pairs(style) do timeStyle[key] = value end
            else
                timeStyle.enabled, timeStyle.flags = true, "OUTLINE"
            end
            timeStyle.size = size
            style.time = timeStyle
        else
            style.time = style
        end
    end
    Text.styles = result
end

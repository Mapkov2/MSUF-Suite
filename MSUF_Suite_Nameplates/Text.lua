local _, private = ...
local NS, S = private.NS, private.Suite
local Style = NS.NameplateStyle
local Text = { originals = setmetatable({}, { __mode = "k" }) }
private.Text = Text

function Text.Bind(module) Text.module = module end

local function Capture(region, original, path, size, flags)
    original[1], original[2], original[3] = path, size, flags or ""
    original.appliedShadow = nil
    local r, g, b, a = region:GetShadowColor()
    if S.Finite(r) and S.Finite(g) and S.Finite(b) and S.Finite(a) then original.shadow = { r, g, b, a } end
    local x, y = region:GetShadowOffset()
    if S.Finite(x) and S.Finite(y) then original.offset = { x, y } end
end

-- Nameplates are pooled. Restore keeps a region's record (restored);
-- the next plate on that region captures into the record and its shadow
-- and offset tables, so a plate cycle allocates nothing (Capture 496 B and
-- Apply 350 B a call in the 2026-10-02 raid trace). What the last plate
-- read is forgotten first, exactly as a new record starts.
local function Recapture(region, original, path, size, flags)
    local shadow, offset = original.shadow, original.offset
    original.restored, original.shadow, original.offset = nil, nil, nil
    original.appliedPath, original.appliedSize, original.appliedFlags = nil, nil, nil
    original[1], original[2], original[3] = path, size, flags or ""
    original.appliedShadow = nil
    local r, g, b, a = region:GetShadowColor()
    if S.Finite(r) and S.Finite(g) and S.Finite(b) and S.Finite(a) then
        shadow = shadow or {}
        shadow[1], shadow[2], shadow[3], shadow[4] = r, g, b, a
        original.shadow = shadow
    end
    local x, y = region:GetShadowOffset()
    if S.Finite(x) and S.Finite(y) then
        offset = offset or {}
        offset[1], offset[2] = x, y
        original.offset = offset
    end
end

function Text.Invalidate(region)
    local original = Text.originals[region]
    if original then original.appliedShadow = nil end
end

function Text.Restore(region)
    local original = Text.originals[region]
    if not original or original.restored or NS.Safety.IsForbidden(region) then return end
    if original.fontScale then original.fontScale(region, original[3]) end
    region:SetFont(original[1], original[2], original[3])
    if original.shadow then region:SetShadowColor(unpack(original.shadow)) end
    if original.offset then region:SetShadowOffset(unpack(original.offset)) end
    original.restored = true
end

function Text.Apply(region, style, size)
    if not region or NS.Safety.IsForbidden(region) then return end
    if not style.enabled then
        Text.Restore(region)
        return
    end
    local path, nativeSize, flags = region:GetFont()
    if not S.Public(path) or type(path) ~= "string" or path == ""
        or not S.Finite(nativeSize) or not S.Public(flags) then return end
    local original = Text.originals[region]
    if not original then
        original = {}
        Capture(region, original, path, nativeSize, flags)
        Text.originals[region] = original
    elseif original.restored then
        Recapture(region, original, path, nativeSize, flags)
    elseif path ~= original.appliedPath or nativeSize ~= original.appliedSize or flags ~= original.appliedFlags then
        Capture(region, original, path, nativeSize, flags)
    end
    local face, height = style.font or original[1], size > 0 and size or original[2]
    local fontChanged = path ~= face or nativeSize ~= height or flags ~= style.flags
    -- 2026-10-26 M+ trace: only a font write can change the values just read.
    local appliedPath, appliedSize, appliedFlags = path, nativeSize, flags
    if fontChanged then
        if style.fontScale then style.fontScale(region, style.flags) original.fontScale = style.fontScale end
        S.SetFont(region, face, height, style.flags)
        appliedPath, appliedSize, appliedFlags = region:GetFont()
    end
    if S.Public(appliedPath) and S.Finite(appliedSize) and S.Public(appliedFlags) then
        original.appliedPath, original.appliedSize, original.appliedFlags = appliedPath, appliedSize, appliedFlags
    end
    local shadowKey = style.shadowKey or style.shadow
    if fontChanged or original.appliedShadow ~= shadowKey then
        region:SetShadowColor(0, 0, 0, style.shadow and (style.shadowAlpha or 1) or 0)
        region:SetShadowOffset(style.shadow and (style.shadowX or 1) or 0, style.shadow and (style.shadowY or -1) or 0)
        original.appliedShadow = shadowKey
    end
end

function Text.Configure(config)
    local shared = NS.NameplateText.Shared(config)
    Text.shared = shared
    local result = {}
    for _, prefix in ipairs({ "enemy", "friendly", "enemyCast", "friendlyCast" }) do
        result[prefix] = NS.NameplateText.FontStyle(config, prefix, shared)
    end
    Text.styles = result
end

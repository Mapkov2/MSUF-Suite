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

function Text.Invalidate(region)
    local original = Text.originals[region]
    if original then original.appliedShadow = nil end
end

function Text.Restore(region)
    local original = Text.originals[region]
    if not original or NS.Safety.IsForbidden(region) then return end
    region:SetFont(original[1], original[2], original[3])
    if original.shadow then region:SetShadowColor(unpack(original.shadow)) end
    if original.offset then region:SetShadowOffset(unpack(original.offset)) end
    Text.originals[region] = nil
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
    elseif path ~= original.appliedPath or nativeSize ~= original.appliedSize or flags ~= original.appliedFlags then
        Capture(region, original, path, nativeSize, flags)
    end
    local face, height = style.font or original[1], size > 0 and size or original[2]
    local fontChanged = path ~= face or nativeSize ~= height or flags ~= style.flags
    if fontChanged then S.SetFont(region, face, height, style.flags) end
    local appliedPath, appliedSize, appliedFlags = region:GetFont()
    if S.Public(appliedPath) and S.Finite(appliedSize) and S.Public(appliedFlags) then
        original.appliedPath, original.appliedSize, original.appliedFlags = appliedPath, appliedSize, appliedFlags
    end
    if fontChanged or original.appliedShadow ~= style.shadow then
        region:SetShadowColor(0, 0, 0, style.shadow and 1 or 0)
        region:SetShadowOffset(style.shadow and 1 or 0, style.shadow and -1 or 0)
        original.appliedShadow = style.shadow
    end
end

function Text.Configure(config)
    local result = {}
    for _, prefix in ipairs({ "enemy", "friendly", "enemyCast", "friendlyCast" }) do
        local cast = prefix:sub(-4) == "Cast"
        local key = prefix .. (cast and "Font" or "NameFont")
        local outline = config[prefix .. (cast and "Outline" or "TextOutline")]
        result[prefix] = {
            enabled = config[prefix .. "TextEnabled"] ~= false,
            font = config[prefix .. "CustomFont"] ~= false and Style.Font(config[key]) or nil,
            flags = Style.FontFlags(outline),
            shadow = config[prefix .. "TextShadow"] == true,
        }
    end
    Text.styles = result
end

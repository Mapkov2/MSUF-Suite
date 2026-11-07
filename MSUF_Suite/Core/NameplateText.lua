local _, NS = ...
local Text = {}
NS.NameplateText = Text
local MODE_FULL, MODE_CUT = "FULL", "CUT"
local MODES = { MODE_FULL, MODE_CUT, "ABBREV", "ABBREV_CUT" }
Text.Suffixes = { "NameFormat", "NameMaxChars", "NameClipSide", "NameNoEllipsis", "NameColorEnabled", "NameColor" }

Text.StyleSuffixes = { "TextEnabled", "CustomFont", "NameFont", "NameSize", "TextOutline", "TextShadow" }

function Text.Limited(value) return value == 2 or value == 4 end

function Text.Shared(config)
    local formatter = NS.HostBridge.NameFormatter()
    if formatter and formatter.Nameplates then return formatter.Nameplates({}) end
    if config.nameTextUseCustomSettings == true then return nil end
    if formatter and formatter.Shared then return formatter.Shared({}) end
end

function Text.Compile(config, prefix)
    local mode = MODES[config[prefix .. "NameFormat"] or 2] or MODE_FULL
    local provider = NS.HostBridge.NameFormatter()
    local nativeScope = provider and provider.Nameplates ~= nil
    local formatting = nativeScope or config.nameFormattingEnabled == true
    local formatter = formatting and provider or nil
    local color = not nativeScope and config[prefix .. "NameColorEnabled"] == true
    local r, g, b
    if color then r, g, b = NS.RGB(config[prefix .. "NameColor"] or "ffffff") end
    local shared = Text.Shared(config)
    local side, dots, maxChars = config[prefix .. "NameClipSide"] == 2 and "LEFT" or "RIGHT",
        config[prefix .. "NameNoEllipsis"] ~= true, config[prefix .. "NameMaxChars"] or 12
    if shared then
        mode = shared.nameFormat or (shared.nameShorten and "CUT" or MODE_FULL)
        side, dots, maxChars = shared.nameShortenSide, shared.nameShortenDots, shared.nameShortenMax
    end
    return { enabled = formatting and formatter ~= nil,
        displayName = nativeScope and shared and shared.characterNameParts and provider.DisplayName,
        formatter = formatter, formatID = mode, max = maxChars, side = side, dots = dots,
        customColor = color, r = r, g = g, b = b, shared = shared, colorPainter = shared and NS.HostBridge.NameFormatter() }
end

function Text.Format(state, value, look)
    if look.displayName and state.unit then value = look.displayName(value, state.unit) end
    if not look.enabled then return value end
    return look.formatter.Format(state, value, look.formatID, look.max, look.dots, look.side)
end

function Text.PaintColor(label, state, look, unit)
    if look.customColor then
        label:SetVertexColor(look.r, look.g, look.b, look.shared and look.shared.textColor.a or 1)
    elseif look.shared and look.colorPainter.NameColor then
        state.nameText, state.MSUFSpec, state.MSUFUnitKey = label, look.shared, unit
        state._msufPortraitSampleClass = unit == nil and "WARRIOR" or nil
        local r, g, b, a
        if unit == nil then
            r, g, b, a = look.colorPainter.SampleColor(state, state.sampleNPC and "enemy" or nil)
        else
            r, g, b, a = look.colorPainter.NameColor(state, unit)
        end
        if not NS.Finite(r) or not NS.Finite(g) or not NS.Finite(b) or not NS.Finite(a) then
            return false
        end
        label:SetVertexColor(r, g, b, a)
    end
    return look.customColor or look.shared ~= nil
end

function Text.Paint(label, state, value, look, unit)
    label:SetText(Text.Format(state, value, look))
    Text.PaintColor(label, state, look, unit)
end

function Text.Sample(prefix)
    if prefix == "enemy" then return "Ravenous Twilight Shadowcaster" end
    local value = NS.Client.isForever and "Alexandriana Brightwhisper" or "Alexandriana"
    local formatter = NS.HostBridge.NameFormatter()
    if formatter and formatter.Nameplates and formatter.DisplayName then return formatter.DisplayName(value, "player") end
    return value
end

-- Runtime and both menus compile the same typography. No live frame/profile
-- reads occur while the name posthook paints an already compiled style.
function Text.FontStyle(config, prefix, shared)
    local cast = prefix:sub(-4) == "Cast"
    local Style = NS.NameplateStyle
    local formatter = NS.HostBridge.NameFormatter()
    local style = { enabled = config[prefix .. "TextEnabled"] ~= false,
        font = config[prefix .. "CustomFont"] ~= false and Style.Font(config[prefix .. (cast and "Font" or "NameFont")]) or nil,
        flags = Style.FontFlags(config[prefix .. (cast and "Outline" or "TextOutline")]),
        shadow = config[prefix .. "TextShadow"] == true,
        size = config[prefix .. (cast and "Size" or "NameSize")] or 0,
        healthSize = prefix == "enemy" and config.enemyHealthTextSize or 0,
        fontScale = formatter and formatter.ApplyScale }
    if shared then
        style.enabled, style.font, style.flags = true, shared.font, shared.fontFlags
        style.size = cast and shared.fontSize or shared.nameFontSize
        style.healthSize = shared.fontSize
        style.shadow, style.shadowAlpha = shared.fontShadow, shared.fontShadowAlpha
        style.shadowX, style.shadowY = shared.fontShadowX, shared.fontShadowY
        style.shadowKey = tostring(shared.fontShadow) .. ":" .. shared.fontShadowAlpha
            .. ":" .. shared.fontShadowX .. ":" .. shared.fontShadowY
    end
    return style
end

function Text.PaintFont(label, config, prefix, nativeSize, nativeFont, painter)
    local style = Text.FontStyle(config, prefix, Text.Shared(config))
    local face = style.enabled and style.font or nativeFont
    local size = style.enabled and style.size > 0 and style.size or nativeSize
    local flags = style.enabled and style.flags or "OUTLINE"
    local shadow = style.enabled and style.shadow
    painter(label, face or nativeFont, size, flags, nil, shadow, (style.shadowAlpha or 1) * 100, style.shadowX or 1)
end

-- A disabled local control still shows its effective inherited value.
function Text.InheritedValue(config, key)
    local shared = Text.Shared(config)
    if not shared then return nil, false end
    local suffix = key:match("^enemyCast(.+)$") or key:match("^friendlyCast(.+)$")
        or key:match("^enemy(.+)$") or key:match("^friendly(.+)$")
    if suffix == "NameFormat" then
        for index, value in ipairs(MODES) do if value == shared.nameDisplayFormat then return index, true end end
    elseif suffix == "NameMaxChars" then
        return shared.nameDisplayMax > 0 and shared.nameDisplayMax or shared.nameShortenMax, true
    elseif suffix == "NameClipSide" then return shared.nameDisplaySide == "LEFT" and 2 or 1, true
    elseif suffix == "NameNoEllipsis" then return not shared.nameDisplayDots, true
    elseif suffix == "NameFont" or suffix == "Font" then return "", true
    elseif suffix == "NameSize" or suffix == "Size" then return shared.nameFontSize, true
    elseif suffix == "TextOutline" or suffix == "Outline" then return 7, true
    elseif suffix == "TextShadow" then return shared.fontShadow, true
    elseif suffix == "TextEnabled" or suffix == "CustomFont" then return true, true end
    return nil, false
end

function Text.Keys()
    local keys = { "nameFormattingEnabled", "nameTextUseCustomSettings" }
    for _, prefix in ipairs({ "enemy", "friendly" }) do
        for _, suffix in ipairs(Text.Suffixes) do keys[#keys + 1] = prefix .. suffix end
        for _, suffix in ipairs(Text.StyleSuffixes) do keys[#keys + 1] = prefix .. suffix end
    end
    return keys
end

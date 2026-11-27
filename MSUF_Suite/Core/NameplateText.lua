local _, NS = ...
local Text = {}
NS.NameplateText = Text
local MODE_FULL, MODE_CUT = "FULL", "CUT"
local MODES = { MODE_FULL, MODE_CUT, "ABBREV", "ABBREV_CUT" }
Text.Suffixes = { "NameFormat", "NameMaxChars", "NameClipSide", "NameNoEllipsis", "NameColorEnabled", "NameColor" }

Text.StyleSuffixes = { "TextEnabled", "CustomFont", "NameFont", "NameSize", "TextOutline", "TextShadow" }

-- 1 retains the native name layout. Other choices pin the label to the health bar.
function Text.NameAnchor(config, prefix)
    return NS.AnchorPoints[(config[prefix .. "NameRelativeAnchor"] or 1) - 1]
end

function Text.Limited(value) return value == 2 or value == 4 end

local function FontProvider(config)
    local formatter = NS.HostBridge.NameFormatter()
    return formatter and (formatter.Nameplates or config.nameTextUseCustomSettings ~= true and formatter.Shared)
end

function Text.UsesSharedFont(config)
    if config.look == 1 then return false end
    return FontProvider(config) ~= nil or NS.NameplatePortableText.Stored() ~= nil
end

function Text.Shared(config)
    if config.look == 1 then return end
    if NS.NameplatePortableText.Stored() then return NS.NameplatePortableText.Resolve() end
    local resolve = FontProvider(config)
    if resolve then return resolve({}) end
    return NS.NameplatePortableText.Resolve()
end

local SIZE_OVERRIDES = {
    enemyNameSize = "enemyNameSizeOverride",
    friendlyNameSize = "friendlyNameSizeOverride",
    enemyHealthTextSize = "enemyHealthTextSizeOverride",
    enemyCastSize = "enemyCastSizeOverride",
    friendlyCastSize = "friendlyCastSizeOverride",
}
Text.SizeOverrides = SIZE_OVERRIDES

function Text.ResolveSize(config, key, shared)
    if not shared then return config[key] or 0 end
    local override = config[SIZE_OVERRIDES[key]]
    if override and override > 0 then return override end
    return key:match("NameSize$") and shared.nameFontSize or shared.fontSize
end

function Text.Compile(config, prefix, scope)
    local mode = MODES[config[prefix .. "NameFormat"] or 2] or MODE_FULL
    local provider = NS.HostBridge.NameFormatter()
    local portable = NS.NameplatePortableText.Stored()
    if portable then provider = NS.NameplatePortableText end
    local nativeScope = config.look ~= 1 and provider and (provider.Nameplates ~= nil or portable ~= nil)
    local formatting = nativeScope or config.nameFormattingEnabled == true
    local colorScope = scope == "neutral" and scope or prefix
    local color = config[colorScope .. "NameColorEnabled"] == true
    local r, g, b
    if color then r, g, b = NS.RGB(config[colorScope .. "NameColor"] or "ffffff") end
    local shared = Text.Shared(config)
    local maxChars = config[prefix .. "NameMaxChars"] or 12
    if shared then
        mode = shared.nameDisplayFormat or shared.nameFormat or (shared.nameShorten and MODE_CUT or MODE_FULL)
        maxChars = shared.nameShortenMax or maxChars
        if shared.nameDisplayMax and shared.nameDisplayMax > 0 then maxChars = shared.nameDisplayMax end
    end
    -- Length-limited modes use the native nameplate width.
    return { enabled = formatting and (mode == MODE_CUT or mode == "ABBREV_CUT"),
        displayName = nativeScope and shared and shared.characterNameParts and provider.DisplayName,
        max = maxChars,
        customColor = color, r = r, g = g, b = b, shared = shared, colorPainter = shared and provider }
end

function Text.CustomNameColor(look)
    if not look then return end
    local shared = look.shared
    local color = look.customColor and look or shared and shared.text and shared.text.nameColor
    local portable = shared and shared.portable
    if not color and portable and portable.nameColorMode == "CUSTOM" then
        color = { r = portable.nameColorR or 1, g = portable.nameColorG or 1, b = portable.nameColorB or 1 }
    end
    if color and NS.Finite(color.r) and NS.Finite(color.g) and NS.Finite(color.b) then return color end
end

function Text.Format(state, value, look)
    if look.displayName and state.unit and not NS.IsSecret(value) then
        return look.displayName(value, state.unit)
    end
    return value
end

function Text.PaintColor(label, state, look, unit)
    if look.customColor then
        label:SetTextColor(look.r, look.g, look.b, look.shared and look.shared.textColor.a or 1)
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
        label:SetTextColor(r, g, b, a)
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
    local sizeKey = prefix .. (cast and "Size" or "NameSize")
    local style = { enabled = config[prefix .. "TextEnabled"] ~= false,
        font = config[prefix .. "CustomFont"] ~= false and Style.Font(config[prefix .. (cast and "Font" or "NameFont")]) or nil,
        flags = Style.FontFlags(config[prefix .. (cast and "Outline" or "TextOutline")]),
        shadow = config[prefix .. "TextShadow"] == true,
        size = Text.ResolveSize(config, sizeKey, shared),
        healthSize = config[prefix .. "HealthTextSize"] or 0,
        fontScale = formatter and formatter.ApplyScale }
    if shared then
        style.enabled, style.font, style.flags = true, shared.font, shared.fontFlags
        style.healthSize = prefix == "enemy" and Text.ResolveSize(config, "enemyHealthTextSize", shared)
            or (style.healthSize > 0 and style.healthSize or shared.fontSize)
        style.shadow, style.shadowAlpha = shared.fontShadow, shared.fontShadowAlpha
        style.color = shared.textColor
        style.shadowX, style.shadowY = shared.fontShadowX, shared.fontShadowY
        style.shadowKey = tostring(shared.fontShadow) .. ":" .. shared.fontShadowAlpha
            .. ":" .. shared.fontShadowX .. ":" .. shared.fontShadowY
    end
    return style
end

function Text.PaintFont(label, config, prefix, nativeSize, nativeFont, painter, health)
    local style = Text.FontStyle(config, prefix, Text.Shared(config))
    local face = style.enabled and style.font or nativeFont
    local requested = health and style.healthSize or style.size
    local size = style.enabled and requested > 0 and requested or nativeSize
    local flags = style.enabled and style.flags or "OUTLINE"
    local shadow = style.enabled and style.shadow
    painter(label, face or nativeFont, size, flags, nil, shadow, (style.shadowAlpha or 1) * 100, style.shadowX or 1)
    return size
end

-- A disabled local control still shows its effective inherited value.
function Text.InheritedValue(config, key)
    local shared = Text.Shared(config)
    if not shared then return nil, false end
    if SIZE_OVERRIDES[key] then return Text.ResolveSize(config, key, shared), true end
    local suffix = key:match("^enemyCast(.+)$") or key:match("^friendlyCast(.+)$")
        or key:match("^enemy(.+)$") or key:match("^friendly(.+)$")
    if suffix == "NameFormat" then
        for index, value in ipairs(MODES) do if value == shared.nameDisplayFormat then return index, true end end
    elseif suffix == "NameMaxChars" then
        return shared.nameDisplayMax > 0 and shared.nameDisplayMax or shared.nameShortenMax, true
    elseif suffix == "NameClipSide" then return shared.nameDisplaySide == "LEFT" and 2 or 1, true
    elseif suffix == "NameNoEllipsis" then return not shared.nameDisplayDots, true
    elseif suffix == "NameFont" or suffix == "Font" then return "", true
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

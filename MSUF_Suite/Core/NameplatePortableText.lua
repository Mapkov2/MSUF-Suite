local _, NS = ...
local Portable = {}
NS.NameplatePortableText = Portable
local savedSource, savedValue

function Portable.Stored()
    if NS.HostBridge.HasNameplateFontSettings() then return nil end
    local shared = NS.DB and NS.DB.nameplateShared
    if shared ~= savedSource then
        savedSource = shared
        local clean = NS.NameplateHostSettings.Normalize(shared)
        savedValue = clean and clean.nameplates
    end
    if savedValue and next(savedValue) and savedValue.fontOverride ~= false then return savedValue end
end

local function EffectiveTypography(value)
    local resolved = NS.HostBridge.ResolveNameplateTypography(value)
    if resolved then return resolved end
    local captured = NS.HostBridge.CaptureNameplateSettings()
    local merged = captured and captured.nameplates or {}
    for key, field in pairs(value) do merged[key] = field end
    if value.noOutline ~= nil or value.boldText ~= nil then
        merged.noOutline, merged.boldText = value.noOutline == true, value.noOutline ~= true and value.boldText == true
    end
    if value.fontColorR ~= nil then
        merged.fontColorG, merged.fontColorB = value.fontColorG or 1, value.fontColorB or 1
    end
    return merged
end

function Portable.Resolve()
    local value = Portable.Stored()
    if not value then return nil end
    value = EffectiveTypography(value)
    local flags = value.noOutline and "" or value.boldText and "THICKOUTLINE" or "OUTLINE"
    if value.fontMonochrome then flags = flags == "" and "MONOCHROME" or flags .. ",MONOCHROME" end
    if value.fontSlug then flags = value.noOutline and "SLUG" or "OUTLINE,SLUG" end
    local shadowAlpha, shadowDistance = value.fontShadowOpacity, value.fontShadowDistance
    if not shadowAlpha or not shadowDistance then
        local strength = value.fontShadowStrength
        shadowAlpha = shadowAlpha or (strength == "SOFT" and .55 or 1)
        shadowDistance = shadowDistance or (strength == "DEEP" and 2 or 1)
    end
    return {
        font = NS.ResolveFont(value.fontKey) or NS.GlobalFontPath(), fontFlags = flags,
        fontSize = value.fontSize or 12, nameFontSize = value.nameFontSize or value.fontSize or 12,
        fontShadow = value.textBackdrop == true and not value.fontSlug, fontShadowAlpha = shadowAlpha,
        fontShadowX = shadowDistance, fontShadowY = -shadowDistance,
        fontBaselineOffset = value.fontBaselineOffset or 0,
        nameFormat = value.nameFormat or "FULL", nameShorten = value.shortenNames == true,
        nameShortenSide = value.shortenNameClipSide or "LEFT", nameShortenDots = value.shortenNameShowDots ~= false,
        nameShortenMax = value.shortenNameMaxChars or 12, portable = value,
        nameDisplayFormat = value.nameFormat or "FULL", nameDisplayMax = value.shortenNameMaxChars or 12,
        nameDisplaySide = value.shortenNameClipSide or "LEFT", nameDisplayDots = value.shortenNameShowDots ~= false,
        textColor = { r = value.fontColorR or 1, g = value.fontColorG or 1, b = value.fontColorB or 1,
            a = value.fontTextAlpha or 1 },
    }
end

local function NextCharacter(value, index)
    local byte = value:byte(index)
    if byte < 128 then return index + 1 end
    if byte < 224 then return index + 2 end
    if byte < 240 then return index + 3 end
    return index + 4
end

local function Abbreviate(value)
    local first, last = value:find("%S+")
    if not first then return value end
    local nextFirst, nextLast = value:find("%S+", last + 1)
    if not nextFirst then return value end
    local result = ""
    while nextFirst do
        result = result .. value:sub(first, NextCharacter(value, first) - 1) .. ". "
        first, last = nextFirst, nextLast
        nextFirst, nextLast = value:find("%S+", last + 1)
    end
    return result .. value:sub(first, last)
end

local function Truncate(value, maximum, dots, side)
    local count, index = 0, 1
    while index <= #value do count, index = count + 1, NextCharacter(value, index) end
    if count <= maximum then return value end
    local suffix = dots and ".." or ""
    index = 1
    if side == "LEFT" then
        for _ = 1, count - maximum do index = NextCharacter(value, index) end
        return suffix .. value:sub(index)
    end
    for _ = 1, maximum do index = NextCharacter(value, index) end
    return value:sub(1, index - 1) .. suffix
end

function Portable.Format(state, value, mode, maximum, dots, side)
    if not NS.Public(value) or type(value) ~= "string" then return value end
    if state.portableInput == value and state.portableFormat == mode and state.portableMax == maximum
        and state.portableDots == dots and state.portableSide == side then return state.portableOutput end
    local output = value
    if mode == "ABBREV" or mode == "ABBREV_CUT" then output = Abbreviate(output) end
    if mode == "CUT" or mode == "ABBREV_CUT" then output = Truncate(output, maximum, dots, side) end
    state.portableInput, state.portableFormat, state.portableOutput = value, mode, output
    state.portableMax, state.portableDots, state.portableSide = maximum, dots, side
    return output
end

function Portable.NameColor(state, unit)
    local shared, value = state.MSUFSpec, state.MSUFSpec.portable
    local alpha = shared.textColor.a
    if value.nameColorMode == "CUSTOM" then
        return value.nameColorR or 1, value.nameColorG or 1, value.nameColorB or 1, alpha
    end
    local color = shared.textColor
    if not unit then return color.r, color.g, color.b, alpha end
    local player = UnitIsPlayer(unit)
    if not NS.Public(player) then return color.r, color.g, color.b, alpha end
    if player == true and (value.nameClassColor or value.nameColorMode == "CLASS")
        or player == false and value.nameNpcClassColor then
        local _, class = UnitClass(unit)
        if NS.Public(class) then
            local classColor = class and RAID_CLASS_COLORS[class]
            if classColor then return classColor.r, classColor.g, classColor.b, alpha end
        end
    end
    if player == false and (value.npcNameRed or value.nameNpcClassColor) then
        local r, g, b = NS.HostBridge.NPCNameColor(unit)
        if r then return r, g, b, alpha end
    end
    return color.r, color.g, color.b, alpha
end

function Portable.SampleColor(state)
    local shared, value = state.MSUFSpec, state.MSUFSpec.portable
    if value.nameColorMode ~= "CUSTOM" then
        local useClass = state.sampleNPC and value.nameNpcClassColor
            or not state.sampleNPC and (value.nameClassColor or value.nameColorMode == "CLASS")
        local class = state._msufPortraitSampleClass or "WARRIOR"
        local color = useClass and RAID_CLASS_COLORS[class]
        if color then return color.r, color.g, color.b, shared.textColor.a end
        if state.sampleNPC and (value.npcNameRed or value.nameNpcClassColor) then
            local r, g, b = NS.HostBridge.NPCNameColor("enemy")
            if r then return r, g, b, shared.textColor.a end
        end
    end
    return Portable.NameColor(state)
end

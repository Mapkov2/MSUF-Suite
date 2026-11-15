local _, P = ...
local Text, Bridge = P.Suite.NameplateText, P.Suite.HostBridge
local Fonts = {}
P.NameplateFonts = Fonts
local oldGate, RuleRow = P.Gates.nameplates, P.RuleRow
local function NativeScope()
    local provider = Bridge.NameFormatter()
    return provider and provider.Nameplates ~= nil
end
local function LegacyTextKey(key)
    if Text.SizeOverrides[key] then return false end
    if key == "nameFormattingEnabled" or key == "nameTextUseCustomSettings" then return true end
    for _, prefix in ipairs({ "enemy", "friendly", "enemyCast", "friendlyCast" }) do
        for _, suffix in ipairs(Text.Suffixes) do if key == prefix .. suffix then return true end end
        for _, suffix in ipairs(Text.StyleSuffixes) do
            if key == prefix .. suffix then return key ~= "enemyCastTextEnabled" and key ~= "friendlyCastTextEnabled" end
        end
    end
    return key == "enemyCastFont" or key == "friendlyCastFont"
        or key == "enemyCastOutline" or key == "friendlyCastOutline"
end
Fonts.IsTypography = LegacyTextKey
P.Gates.nameplates = function(rule, key)
    if NativeScope() and LegacyTextKey(key) then return false, "Configure this in Fonts > Nameplates." end
    if oldGate then return oldGate(rule, key) end
end
function P.RuleRow(page, id, rule, ...)
    local row = RuleRow(page, id, rule, ...)
    if id == "nameplates" and row then
        local stored = row.get
        local override = Text.SizeOverrides[rule.key]
        if override and Text.UsesSharedFont(P.S.Config(id)) then row.label = P.Tr("Font size") end
        row.get = function()
            if NativeScope() or override and Text.UsesSharedFont(P.S.Config(id)) then
                local value, resolved = Text.InheritedValue(P.S.Config(id), rule.key)
                if resolved then return value end
            end
            return stored()
        end
        if override then
            local set = row.set
            row.set = function(value)
                if Text.UsesSharedFont(P.S.Config(id)) then return P.Set(id, override, tonumber(value) or 0) end
                return set(value)
            end
        end
    end
    return row
end
local SHORTEN, COLORS = "fonts_name_shortening", "fonts_name_power_colors"

function Fonts.HasLinks()
    return Bridge.HasNameplateFontsMenu(P.M)
end

function Fonts.TargetForSetting(settingKey)
    local key = settingKey and settingKey:match("^msufsuite%.nameplates%.(.+)$")
    if not key or not LegacyTextKey(key) then return end
    if not Fonts.HasLinks() then
        local fallback = P.NameplatesHostOptions
        if fallback and fallback.registered then return "opt_fonts", { sectionId = "opt_fonts_nameplate_text" } end
        return
    end
    if key == "nameFormattingEnabled" or key == "nameTextUseCustomSettings" then
        return Bridge.NameplateFontsTarget(SHORTEN)
    end
    local suffix = key:match("^enemy(.+)$") or key:match("^friendly(.+)$")
    for _, name in ipairs(Text.Suffixes) do
        if suffix == name then
            local section = name:find("Color", 1, true) and COLORS or SHORTEN
            return Bridge.NameplateFontsTarget(section)
        end
    end
    local section = key:match("Font$") and "fonts_global_font" or "fonts_text_style"
    return Bridge.NameplateFontsTarget(section)
end

function Fonts.AddLinks(ctx, body, y, width, sectionId)
    if not Fonts.HasLinks() then
        local fallback = P.NameplatesHostOptions
        if not fallback or not fallback.registered then return y end
        P.Button(ctx, body, "Nameplate typography", 16, y, math.min(200, width), function()
            P.M.SelectPage("opt_fonts")
            local page = P.M.cache and P.M.cache.opt_fonts
            local target = page and page.sections and page.sections.opt_fonts_host_nameplates
            if target and P.W.FocusCollapsibleSection then P.W.FocusCollapsibleSection(target, { persist = true }) end
        end, nil, P.Meta("suite_nameplates", "nameplates", "action.fontTypography." .. sectionId, "action", sectionId))
        return y - 34
    end
    local buttonWidth = math.min(164, (width - 16) / 3)
    local function Button(label, x, section, key)
        P.Button(ctx, body, label, x, y, buttonWidth, function() Bridge.OpenNameplateFonts(P.M, section) end,
            nil, P.Meta("suite_nameplates", "nameplates", key .. "." .. sectionId, "action", sectionId))
    end
    Button("Nameplate font", 16, "fonts_global_font", "action.fontTypography")
    Button("Name format", 24 + buttonWidth, SHORTEN, "action.fontNameFormat")
    Button("Colors", 32 + 2 * buttonWidth, COLORS, "action.fontNameColors")
    return y - 34
end

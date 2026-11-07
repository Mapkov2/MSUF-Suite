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
        for _, suffix in ipairs(Text.StyleSuffixes) do if key == prefix .. suffix then return true end end
    end
    return key == "enemyCastFont" or key == "friendlyCastFont"
        or key == "enemyCastOutline" or key == "friendlyCastOutline"
end
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
    if not key or not Fonts.HasLinks() then return end
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
end

function Fonts.LinkSection(ctx, builder, sectionId, title)
    return P.LazySection(builder, sectionId, title, nil, {
        content = function(body)
            local width = math.max(240, (P.HM.GetSectionWidth(body) or builder.width or 720) - 32)
            local hint = P.Description(body, "Configure this in Fonts > Nameplates.", 16, -18, width, title)
            local y = -30 - math.max(14, math.ceil(hint:GetStringHeight() or 14))
            local buttonWidth = math.min(164, (width - 8) / 2)
            local function Button(label, x, section, key)
                P.Button(ctx, body, label, x, y, buttonWidth, function() Bridge.OpenNameplateFonts(P.M, section) end,
                    nil, P.Meta("suite_nameplates", "nameplates", key, "action", sectionId))
            end
            Button("Name format", 16, SHORTEN, "action.fontNameFormat")
            Button("Colors", 24 + buttonWidth, COLORS, "action.fontNameColors")
            return y - 34
        end,
        finish = function(body, y) P.FinishBody(builder, body, y) end,
    })
end

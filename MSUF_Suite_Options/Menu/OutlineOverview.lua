local _, P = ...
local Suite, S = P.Suite, P.S
local Kit = P.SkinPageKit
local detailedHost

-- Pair the catalog's width and color rules. Rendering and validation stay
-- with the original module. Only ring widths verified in screen pixels
-- participate in the pixel-only batch.
local SPECS = {
    { "minimap", "Minimap", "Border", "borderSize", "borderColor", true },
    { "minimap", "Minimap", "Outer border size", "outerBorderSize", "outerBorderColor", true },
    { "damageMeter", "Damage Meter", "Window outline", "borderSize", "borderColor" },
    { "damageMeter", "Damage Meter", "Row border", "rowBorderSize", "rowBorderColor" },
    { "damageMeter", "Damage Meter", "Icon border", "iconBorderSize", "iconBorderColor" },
    { "damageMeter", "Damage Meter", "Timer border thickness", "timerBorderSize", "timerBorderColor" },
    { "characterPanel", "Character Panel", "Window outline", "windowOutline", "windowOutlineColor", true, false, 1 },
    { "bags", "Bags", "Backpack", "backpackBorderWidth", "backpackBorderColor" },
    { "bags", "Bags", "Item slot border thickness", "slotBorderWidth" },
    { "bags", "Bags", "Empty slot border thickness", "emptySlotBorderWidth" },
    { "chat", "Chat", "Border", "borderSize", "borderColor" },
    { "chat", "Chat", "Tab border thickness", "tabBorderSize", "tabActiveBorder" },
    { "actionbars", "Action Bars", "Button border", "borderSize", "borderColor" },
    { "nameplates", "Nameplates", "Enemy", "enemyBorderSize", "enemyBorderColor" },
    { "nameplates", "Nameplates", "Friendly", "friendlyBorderSize", "friendlyBorderColor" },
    { "nameplates", "Nameplates", "Power bar", "enemyPowerBorderSize", "enemyPowerBorderColor" },
    { "xpBar", "Experience bar", "Border", "borderSize" },
    { "playerAuras", "Player Auras", "Border", "borderSize", "borderColor" },
    { "skyriding", "Skyriding", "Border", "borderSize", "borderColor" },
}

-- These controls are individual elements of the overview, outside the shared
-- thickness operation. Many use a different scale or control a transient rim.
local EXTRA_SPECS = {
    { "nameplates", "Nameplates", "Enemy and Neutral", "enemyOuterFrameSize", "enemyOuterFrameColor" },
    { "nameplates", "Nameplates", "Friendly and Friendly NPC", "friendlyOuterFrameSize", "friendlyOuterFrameColor" },
    { "nameplates", "Nameplates", "Highlight Borders", "highlightBorderSize" },
    { "nameplates", "Nameplates", "Target border", nil, "selectionTargetColor" },
    { "nameplates", "Nameplates", "Focus border", nil, "selectionFocusColor" },
    { "nameplates", "Nameplates", "Aggro border", nil, "highlightAggroColor" },
    { "nameplates", "Nameplates", "Mouseover border", nil, "highlightMouseoverColor" },
    { "nameplates", "Enemy and Neutral", "Icon border", "enemyCastIconBorderSize", "enemyCastIconBorderColor" },
    { "nameplates", "Friendly and Friendly NPC", "Icon border", "friendlyCastIconBorderSize", "friendlyCastIconBorderColor" },
    { "nameplates", "Auras", "Aura highlight thickness", "auraHighlightSize", "auraPandemicColor" },
    { "battleRes", "Battle resurrection", "Border", "borderThickness" },
    { "chat", "Chat tabs", "Inactive tab border", nil, "tabInactiveBorder" },
    { "chat", "Speech bubbles", "Bubble border color", nil, "bubbleBorder" },
}

local aliases = {
    nameplates = {
        enemyOutlineMode = "enemyBorderSize", friendlyOutlineMode = "friendlyBorderSize",
        enemyOuterFrame = "enemyOuterFrameSize", friendlyOuterFrame = "friendlyOuterFrameSize",
        selectionBorder = "selectionTargetColor", highlightTarget = "selectionTargetColor", highlightFocus = "selectionFocusColor",
        highlightAggro = "highlightAggroColor", highlightMouseover = "highlightMouseoverColor",
        enemyCastIconBorder = "enemyCastIconBorderSize", friendlyCastIconBorder = "friendlyCastIconBorderSize",
        auraDispelHighlight = "auraHighlightSize", auraEnrageHighlight = "auraHighlightSize",
        auraPandemicHighlight = "auraHighlightSize", castTargetHighlightStyle = "castTargetHighlightStyle",
    },
    skin = {
        ["theme.windowOutline"] = "windowOutline", ["theme.windowOutlineMatchTooltip"] = "windowOutline",
        ["color.windowOutline"] = "windowOutline", ["geometry.border"] = "geometry.border",
        ["theme.borderOpacity"] = "geometry.border", ["theme.tooltipLayout.borderWidth"] = "tooltipFrame",
        ["theme.tooltipLayout.borderMode"] = "tooltipFrame", ["theme.tooltipLayout.borderColor"] = "tooltipFrame",
    },
    bags = { backpackBorderStyle = "backpackBorderWidth", backpackBorderOpacity = "backpackBorderWidth" },
    minimap = { borderAlpha = "borderSize", outerBorderGap = "outerBorderSize" },
    damageMeter = { borderAlpha = "borderSize" },
    chat = { borderAlpha = "borderSize" },
}

local function Index(specs)
    for _, spec in ipairs(specs) do
        local module, width, color = spec[1], spec[4], spec[5]
        aliases[module] = aliases[module] or {}
        if width then
            aliases[module][width] = width
            local base = width:match("^(.*Border)Size$") or width:match("^(.*Border)Width$")
                or width:match("^(.*Border)Thickness$")
            if base then
                aliases[module][base] = aliases[module][base] or width
                for _, suffix in ipairs({ "Enabled", "Style", "Texture", "Alpha", "Opacity", "ClassColor" }) do
                    local key = base .. suffix
                    aliases[module][key] = aliases[module][key] or width
                end
            end
        end
        if color then aliases[module][color] = width or color end
    end
end
Index(SPECS)
Index(EXTRA_SPECS)

local SKIN_BORDER_COLORS = {
    { "rim", "Outer structural edge" }, { "border", "Strong outlines" }, { "borderSoft", "Subtle separators and panels" },
    { "buttonBorder", "Button outline" }, { "iconBorder", "Theme-colored icon outline" },
    { "microBarBorder", "Micro Bar shared outline" }, { "microButtonBorder", "Button borders" },
}
for _, entry in ipairs(SKIN_BORDER_COLORS) do aliases.skin["color." .. entry[1]] = "color." .. entry[1] end
for _, suffix in ipairs({ "Style", "Thickness", "Padding", "Opacity" }) do
    aliases.skin["theme.iconBorder" .. suffix] = "color.iconBorder"
end
for _, surface in ipairs({ { "barBorder", "microBarBorder" }, { "buttonBorder", "microButtonBorder" } }) do
    aliases.skin["micro." .. surface[1]] = "color." .. surface[2]
    aliases.skin["icons.microMenu." .. surface[1]] = "color." .. surface[2]
end

function P.OutlineFocus(module, key)
    if not key then return end
    local id = aliases[module] and aliases[module][key]
    if not id and module == "cooldownManager" then
        for _, slot in ipairs(Suite.CDM.SLOTS) do
            local keys = Suite.CDM.KEYS[slot.key]
            if key == keys.border or key == keys.borderColor or key == keys.borderClass then id = keys.border break end
        end
    elseif not id and module == "dataTexts" then
        local prefix = key:match("^(bar%d+)Border")
        if prefix then id = prefix .. "BorderSize"
        elseif key == "borderEnabled" or key == "borderAlpha" then id = "borderSize" end
    elseif not id and module == "actionbars" and key:match("^bar%d+BackgroundBorder$") then
        id = key
    elseif not id and module == "nameplates" and key:match("^aura.+Dispel$") then
        id = "auraHighlightSize"
    elseif not id and module == "chat" and key:match("^bubbleEdge") then
        id = key
    end
    return id and ("suite." .. module .. "." .. id)
end

local function Hex(r, g, b)
    return ("%02x%02x%02x"):format(math.floor(r * 255 + .5), math.floor(g * 255 + .5), math.floor(b * 255 + .5))
end

local function BorderValue(module, key)
    if module == "nameplates" then return P.NameplateBarTextures.OutlineValue(key) end
    return P.Get(module, key)
end

local function Add(rows, module, group, label, widthKey, colorKey, pixels, localizedLabel, choiceOffset, individual)
    local catalog = P.catalog[module]
    local rules = catalog and catalog.rules
    local width, color = rules and rules[widthKey], rules and rules[colorKey]
    if not ((width or color) and P.Available(module)) then return end
    local offset = choiceOffset or 0
    local minimum, maximum = width and width.min, width and width.max
    if choiceOffset then minimum, maximum = 1 - offset, #width.choices - offset end
    local row = {
        id = "suite." .. module .. "." .. (widthKey or colorKey),
        group = P.Tr(group), label = localizedLabel and label or P.Tr(label), localizedLabel = true,
        min = minimum, max = maximum, pixels = pixels,
        batchGroup = "suite." .. module, widthKey = widthKey, widthOffset = offset,
        setWidths = function(values) return P.SetMany(module, values) end,
    }
    local function HasVisibleBorder()
        return module ~= "minimap" or P.Get(module, "iconSkin") == "CUSTOM"
    end
    if minimum and maximum then
        row.getWidth = function() return BorderValue(module, widthKey) - offset end
        row.setWidth = function(value)
            local stored = value + offset
            if P.Get(module, widthKey) == stored then return true end
            return P.Set(module, widthKey, stored)
        end
        row.widthEnabled = function() return HasVisibleBorder() and P.RuleEnabled(module, width) end
        if not individual then row.batch = row.widthEnabled end
    end
    if color and color.color then
        row.getColor = function() return Suite.RGB(BorderValue(module, colorKey)) end
        row.colorEnabled = function() return HasVisibleBorder() and P.RuleEnabled(module, color) end
        row.setColor = function(r, g, b)
            local value = Hex(r, g, b)
            if P.Get(module, colorKey) == value then return true end
            return P.Set(module, colorKey, value)
        end
    end
    rows[#rows + 1] = row
end

local function AddSkinGeometry(rows, skin)
    rows[#rows + 1] = {
        id = "suite.skin.geometry.border", group = P.Tr("Skinning"), label = P.Tr("Outline thickness"), localizedLabel = true,
        min = 0, max = 2, pixels = true,
        getWidth = function() return skin.DB.geometry.border end,
        setWidth = function(value)
            return Kit.Change(skin, "Outline thickness", "geometry.border",
                function() return skin.Theme.SetGeometry("border", value) end)
        end,
    }
    for _, entry in ipairs(SKIN_BORDER_COLORS) do
        local key, label = entry[1], entry[2]
        local row = {
            id = "suite.skin.color." .. key, group = P.Tr("Skinning"), label = P.Tr(label), localizedLabel = true,
            getColor = function() return skin.Theme.GetColor(key) end,
            setColor = function(r, g, b)
                local _, _, _, a = skin.Theme.GetColor(key)
                return Kit.Change(skin, label, "color." .. key, function() return skin.Theme.SetColor(key, r, g, b, a) end)
            end,
        }
        if key == "iconBorder" then
            row.min, row.max = 1, 3
            row.getWidth = function() return skin.DB.theme.iconBorderThickness end
            row.setWidth = function(value)
                return Kit.Change(skin, "Item border thickness", "theme.iconBorderThickness",
                    function() return skin.Theme.SetAppearance("iconBorderThickness", value) end)
            end
        elseif skin.MicroMenuSkin and (key == "microBarBorder" or key == "microButtonBorder") then
            local setting = key == "microBarBorder" and "barBorder" or "buttonBorder"
            row.min, row.max = 0, 2
            row.getWidth = function() return skin.DB.icons.microMenu[setting] end
            row.setWidth = function(value)
                return Kit.Change(skin, label, "micro." .. setting, function() return skin.MicroMenuSkin.SetOption(setting, value) end)
            end
        end
        rows[#rows + 1] = row
    end
end

local function AddTooltipOutline(rows)
    local skin = Suite.TooltipAppearance.Engine()
    local card = skin and skin.ItemTooltipCard
    if not card then return end
    rows[#rows + 1] = {
        id = "suite.skin.tooltipFrame", group = P.Tr("Tooltips"), label = P.Tr("Tooltip frame"), localizedLabel = true,
        min = 1, max = 4,
        getWidth = function() return card.Setting("borderWidth") end,
        widthEnabled = function() return card.Setting("borderMode") ~= "native" end,
        setWidth = function(value)
            return Kit.Change(skin, "Tooltip frame thickness", "theme.tooltipLayout.borderWidth",
                function() return card.Set("borderWidth", value) end)
        end,
        getColor = card.BorderColor,
        setColor = function(r, g, b)
            local _, _, _, a = card.BorderColor()
            return Kit.Change(skin, "Tooltip frame color", "theme.tooltipLayout.borderColor",
                function() return card.SetBorderColor(r, g, b, a) end)
        end,
    }
end

local function AddSkinOutline(rows)
    local skin = Kit.Engine()
    if not skin then return end
    local function Enabled()
        return skin.DB.enabled ~= false and skin.DB.blizzardWindowsEnabled ~= false and skin.DB.skins.blizzardWindows ~= false
    end
    rows[#rows + 1] = {
        id = "suite.skin.windowOutline", group = P.Tr("Skinning"), label = P.Tr("Window outline"), localizedLabel = true,
        min = 0, max = 10, pixels = true,
        getWidth = function() return skin.DB.theme.windowOutline end,
        batch = function() return Enabled() and not skin.DB.theme.windowOutlineMatchTooltip end,
        getMatchTooltip = function() return skin.DB.theme.windowOutlineMatchTooltip == true end,
        setMatchTooltip = function(value)
            return Kit.Change(skin, "Match tooltip border", "theme.windowOutlineMatchTooltip",
                function() return skin.Theme.SetAppearance("windowOutlineMatchTooltip", value) end)
        end,
        setWidth = function(value)
            if skin.DB.theme.windowOutline == value then return true end
            return Kit.Change(skin, "Window outline", "theme.windowOutline",
                function() return skin.Theme.SetAppearance("windowOutline", value) end)
        end,
        getColor = function() return skin.Theme.GetColor("windowOutline") end,
        setColor = function(r, g, b)
            local _, _, _, alpha = skin.Theme.GetColor("windowOutline")
            return Kit.Change(skin, "Outline color", "color.windowOutline",
                function() return skin.Theme.SetColor("windowOutline", r, g, b, alpha) end)
        end,
    }
    if detailedHost then AddSkinGeometry(rows, skin) end
end

local function CollectAdditionalBorders(rows)
    for _, spec in ipairs(EXTRA_SPECS) do Add(rows, spec[1], spec[2], spec[3], spec[4], spec[5], nil, nil, nil, true) end
    local actionBars = P.catalog.actionbars
    for _, rule in ipairs(actionBars and actionBars.controls or {}) do
        local bar = rule.key:match("^bar(%d+)BackgroundBorder$")
        if bar then
            Add(rows, "actionbars", "Action Bars", P.Tr("Bar %d"):format(tonumber(bar)), rule.key, nil, nil, true, nil, true)
        end
    end
    for _, source in ipairs(Suite.ChatBubbleSources or {}) do
        Add(rows, "chat", "Speech bubbles", source.label, nil, "bubbleEdge" .. source.key)
    end
end

local function Collect(rows)
    AddSkinOutline(rows)
    for _, spec in ipairs(SPECS) do Add(rows, unpack(spec)) end
    if detailedHost then
        AddTooltipOutline(rows)
        CollectAdditionalBorders(rows)
    end
    for _, slot in ipairs(Suite.CDM.SLOTS) do
        local keys = Suite.CDM.KEYS[slot.key]
        if keys.border then Add(rows, "cooldownManager", "Cooldown Manager", slot.title, keys.border, keys.borderColor) end
    end
    Add(rows, "dataTexts", "DataTexts", "Shared", "borderSize", "borderColor")
    local config = S.Config("dataTexts")
    for _, id in ipairs(Suite.DataTextBarIDs(config)) do
        local prefix = "bar" .. id
        local name = config[prefix .. "Name"]
        if type(name) ~= "string" or name == "" then name = P.Tr("Bar %d"):format(id) end
        Add(rows, "dataTexts", "DataTexts", name, prefix .. "BorderSize", prefix .. "BorderColor", false, true)
    end
end

detailedHost = Suite.HostBridge.RegisterOutlineSettingResolver(P.M, "msufsuite", function(setting)
    local module, key = setting:match("^msufsuite%.([^.]+)%.(.+)$")
    return P.OutlineFocus(module, key)
end)
Suite.HostBridge.RegisterOutlineOverview(P.M, "suite", Collect)


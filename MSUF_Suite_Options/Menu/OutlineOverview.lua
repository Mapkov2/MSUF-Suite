local _, P = ...
local Suite, S = P.Suite, P.S
local Kit = P.SkinPageKit

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

local function Hex(r, g, b)
    return ("%02x%02x%02x"):format(math.floor(r * 255 + .5), math.floor(g * 255 + .5), math.floor(b * 255 + .5))
end

local function Add(rows, module, group, label, widthKey, colorKey, pixels, localizedLabel, choiceOffset)
    local catalog = P.catalog[module]
    local rules = catalog and catalog.rules
    local width = rules and rules[widthKey]
    if not (width and P.Available(module)) then return end
    local offset = choiceOffset or 0
    local minimum, maximum = width.min, width.max
    if choiceOffset then minimum, maximum = 1 - offset, #width.choices - offset end
    if not (minimum and maximum) then return end
    local row = {
        id = "suite." .. module .. "." .. widthKey,
        group = P.Tr(group), label = localizedLabel and label or P.Tr(label), localizedLabel = true,
        min = minimum, max = maximum, pixels = pixels,
        batchGroup = "suite." .. module, widthKey = widthKey, widthOffset = offset,
        setWidths = function(values) return P.SetMany(module, values) end,
        getWidth = function() return P.Get(module, widthKey) - offset end,
        setWidth = function(value)
            local stored = value + offset
            if P.Get(module, widthKey) == stored then return true end
            return P.Set(module, widthKey, stored)
        end,
    }
    local function HasVisibleBorder()
        return module ~= "minimap" or P.Get(module, "iconSkin") == "CUSTOM"
    end
    row.widthEnabled = function() return HasVisibleBorder() and P.RuleEnabled(module, width) end
    row.batch = row.widthEnabled
    local color = colorKey and rules[colorKey]
    if color and color.color then
        row.getColor = function() return Suite.RGB(P.Get(module, colorKey)) end
        row.colorEnabled = function() return HasVisibleBorder() and P.RuleEnabled(module, color) end
        row.setColor = function(r, g, b)
            local value = Hex(r, g, b)
            if P.Get(module, colorKey) == value then return true end
            return P.Set(module, colorKey, value)
        end
    end
    rows[#rows + 1] = row
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
end

local function Collect(rows)
    AddSkinOutline(rows)
    for _, spec in ipairs(SPECS) do Add(rows, unpack(spec)) end
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

Suite.HostBridge.RegisterOutlineOverview(P.M, "suite", Collect)


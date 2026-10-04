local _, P = ...
local Suite, Tr = P.Suite, P.Tr
local Data = {}
P.DataTextsPreviewData = Data

-- Deliberately static samples: opening the editor never activates a data
-- source, currency lookup, broker callback or background refresh.
local SAMPLES = {
    gold = { "Gold", "12458g" }, sessionGold = { "Session", "+245g" },
    bags = { "Bags", "38/96" }, durability = { "Durability", "100%" },
    clock = { "Time", "20:45" }, fps = { "FPS", "120" }, latency = { "World", "24 ms" },
    coordinates = { "Coords", "48.2, 61.7" }, location = { "Zone", "Location" },
    xp = { "XP", "64%" }, date = { "Date", "04/10" }, fpsLatency = { "FPS / World", "120 / 24 ms" },
    broker = { "Broker", "124" }, currency = { "Currency", "850" }, crests = { "Crests", "90 / 120" },
    itemLevel = { "Item level", "275.5" }, professions = { "Professions", "100 / 100" },
    specialization = { "Specialization", "Specialization" }, audio = { "Volume", "75%" },
    hearth = { "Hearthstone", "Ready" }, progress = { "XP", "64%" },
    portals = { "Dungeon portals", "Open" }, microMenu = { "Menu", "Open" },
    specLoot = { "Specialization / loot", "Specialization" }, travel = { "Travel cooldowns", "Ready" },
}
local WORD_VALUES = { location = "Location", specialization = "Specialization", hearth = "Ready",
    portals = "Open", microMenu = "Open" }

function Data.Sample(source, style, config, block)
    local sample = SAMPLES[source]
    if not sample then return "", "" end
    local name, value = Tr(sample[1]), sample[2]
    if WORD_VALUES[source] then value = Tr(WORD_VALUES[source]) end
    if source == "latency" then value = Tr("%d ms"):format(24) end
    if source == "fpsLatency" then value = "120 / " .. Tr("%d ms"):format(24) end
    if source == "specLoot" then value = Tr("%s / Loot: %s"):format(Tr("Specialization"), Tr("Default")) end
    if source == "travel" then value = Tr(Suite.Client.isForever and "Hearthstone" or "Hearthstone / portals") end
    if source == "bags" and style.bagsPercent then value = "60%" end
    if source == "itemLevel" then value = string.format("%." .. (config.itemLevelDecimals or 1) .. "f", 275.5) end
    if source == "broker" and config[block .. "Broker"] ~= "" then name = config[block .. "Broker"] or name end
    if source == "crests" then value = "90" .. (config.crestSeparator or " / ") .. "120" end
    local showName = style.showLabels and (source ~= "clock" or style.clockLabel)
    return showName and name or "", value
end

function Data.Text(source, style, config, block)
    local name, value = Data.Sample(source, style, config, block)
    local prefix = name ~= "" and ("|cff" .. style.labelColor .. name .. (style.labelColon and ": " or " ") .. "|r") or ""
    return prefix .. "|cff" .. style.valueColor .. value .. "|r"
end

function Data.Snap(value, pixel)
    return math.floor(value / pixel + .5) * pixel
end

local function Distribute(entries, first, last, left, right, gap)
    if last < first then return end
    local available = math.max(0, right - left - (last - first) * gap)
    local needed, fill = 0, nil
    for i = first, last do
        needed = needed + entries[i].length
        if not fill and entries[i].placement == Suite.DataTextPlacement.FILL then fill = i end
    end
    if needed > available then
        for i = first, last do entries[i].length = entries[i].length * available / math.max(1, needed) end
    elseif fill then
        local entry = entries[fill]
        entry.length = math.min(entry.limit or math.huge, entry.length + available - needed)
    end
    for i = first, last do
        entries[i].offset = left
        left = left + entries[i].length + gap
    end
end

-- Work with measured sample text, preserving the saved order and geometry.
-- The entries are preview-owned; config and style are never written here.
function Data.Layout(entries, config, bar, style, pixel, screenLength)
    local prefix, count = "bar" .. bar, #entries
    local vertical = config[prefix .. "Vertical"] == true
    local length = Data.Snap(config[prefix .. "FullScreen"] and screenLength or config[prefix .. "Width"], pixel)
    local thickness = Data.Snap(config[prefix .. "Height"], pixel)
    local inset = not vertical and style.bagBadge and Data.Snap(style.bagBadgeSize + 8, pixel) or 0
    local gap = Data.Snap(style.gap, pixel)
    local gaps = math.max(0, count - 1) * gap
    local fit, total = config[prefix .. "Layout"] == Suite.DataTextLayout.FIT, 0
    for _, entry in ipairs(entries) do
        entry.length = fit and math.max(44, math.ceil(entry.textWidth) + 2 * style.padding)
            or math.max(0, length - inset - gaps) / math.max(1, count)
        total = total + entry.length
    end
    if fit and not config[prefix .. "FullScreen"] then
        length = Data.Snap(math.min(900, math.max(length, total + inset + gaps)), pixel)
    end
    local ratio = math.max(0, length - inset - gaps) / math.max(1, total)
    local center
    for i, entry in ipairs(entries) do
        entry.length = math.min(entry.limit or math.huge, entry.length * ratio)
        if not center and entry.placement == Suite.DataTextPlacement.CENTER then center = i end
    end
    if center then
        local entry = entries[center]
        entry.length = math.min(entry.length, math.max(0, length - 2 * inset))
        entry.offset = (length - entry.length) / 2
        Distribute(entries, 1, center - 1, inset, entry.offset - gap, gap)
        Distribute(entries, center + 1, count, entry.offset + entry.length + gap, length, gap)
    else
        Distribute(entries, 1, count, inset, length, gap)
    end
    return vertical and thickness or length, vertical and length or thickness, inset
end

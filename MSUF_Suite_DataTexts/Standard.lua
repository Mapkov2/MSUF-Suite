local _, P = ...
local NS, S = P.NS, P.Suite
local GoldLedger = P.GoldLedger
local NO_VALUE = P.NO_VALUE
local Finite, MoneyText = S.Finite, S.MoneyText
local floor = math.floor

-- The built-in DataTexts: the shared data source each one reads, how often a
-- sampled one refreshes, the events that change them, their labels and the
-- Blizzard window a click opens. DataTexts.lua drives them; Sources.lua and
-- Actions.lua own the additional sources.
local Standard = {}
P.DataTextStandard = Standard

Standard.SOURCES = {
    gold = true, sessionGold = true, bags = true, durability = true, clock = true,
    fps = true, latency = true, coordinates = true, location = true, xp = true,
    date = true, fpsLatency = true,
}
Standard.SAMPLED = { clock = true, fps = true, latency = true, coordinates = true, date = true, fpsLatency = true }
Standard.INTERVAL = { fps = 2, latency = 5, coordinates = 0.5, fpsLatency = 2 }
-- Displays that read another shared data source.
Standard.READER = { clock = "clockTime", sessionGold = "gold" }
Standard.EVENT_SOURCES = {
    PLAYER_MONEY = { "gold", "sessionGold" },
    BAG_UPDATE_DELAYED = { "bags" },
    UPDATE_INVENTORY_DURABILITY = { "durability" },
    PLAYER_EQUIPMENT_CHANGED = { "durability" },
    ZONE_CHANGED = { "location", "coordinates" },
    ZONE_CHANGED_INDOORS = { "location", "coordinates" },
    ZONE_CHANGED_NEW_AREA = { "location", "coordinates" },
    PLAYER_XP_UPDATE = { "xp" },
    PLAYER_LEVEL_UP = { "xp" },
    UPDATE_EXHAUSTION = { "xp" },
}
local CLICK = {
    gold = "OpenAllBags", sessionGold = "OpenAllBags", bags = "OpenAllBags",
    coordinates = "ToggleWorldMap", location = "ToggleWorldMap", date = "ToggleCalendar",
}
local LABELS = {
    gold = S.Text("Gold"), sessionGold = S.Text("Session"), bags = S.Text("Bags"),
    durability = S.Text("Durability"), clock = S.Text("Time"), fps = S.Text("FPS"),
    latency = S.Text("World"), coordinates = S.Text("Coords"), location = S.Text("Zone"), xp = S.Text("XP"),
    date = S.Text("Date"), fpsLatency = S.Text("FPS / World"),
}
Standard.LABELS = LABELS
local TEXT = {
    current = S.Text("Current"),
    sinceLogin = S.Text("Since login"),
    homeWorld = S.Text("Home / World"),
    level = S.Text("Level %d"),
    knownTotal = S.Text("Known account gold"),
    moreCharacters = S.Text("%d more characters"),
    milliseconds = S.Text("%d ms"),
}

local function Milliseconds(value)
    return TEXT.milliseconds:format(floor(value + .5))
end

-- Losses use the typographic minus sign (U+2212).
local function SignedMoneyText(delta)
    return (delta > 0 and "+" or delta < 0 and "\226\136\146" or "") .. MoneyText(math.abs(delta))
end

-- This session's login gold, or nil: the one session baseline of the Bags
-- and DataTexts (MSUF_Suite/Core/Catalog/Bags.lua).
local SessionBaseline = NS.SessionGoldBaseline

-- Each formatter returns the display value (nil when unknown) and an
-- optional "bad" severity from the raw values of its shared data source.
local FORMATTERS = {
    gold = function(amount)
        if Finite(amount) then return floor(amount / 10000) .. "g" end
    end,
    sessionGold = function(amount)
        local baseline = SessionBaseline(amount)
        if Finite(amount) and Finite(baseline) then
            local delta = amount - baseline
            return SignedMoneyText(delta), delta < 0 and "bad" or nil
        end
    end,
    bags = function(free, total)
        if Finite(free) and Finite(total) then
            return free .. "/" .. total, nil,
                total > 0 and floor((total - free) / total * 100 + .5) .. "%" or NO_VALUE
        end
    end,
    durability = function(lowest)
        if Finite(lowest) then return floor(lowest * 100 + .5) .. "%", lowest <= .2 and "bad" or nil end
    end,
    clock = function(hour, minute)
        if Finite(hour) and Finite(minute) then return string.format("%02d:%02d", hour, minute) end
    end,
    fps = function(rate)
        if Finite(rate) then return tostring(floor(rate + .5)), rate < 30 and "bad" or nil end
    end,
    latency = function(_, world)
        if Finite(world) then return Milliseconds(world), world >= 200 and "bad" or nil end
    end,
    coordinates = function(x, y)
        if Finite(x) and Finite(y) then return string.format("%.1f, %.1f", x * 100, y * 100) end
    end,
    location = function(zone, subZone)
        if type(subZone) == "string" and subZone ~= "" then return subZone end
        if type(zone) == "string" and zone ~= "" then return zone end
    end,
    xp = function(_, current, maximum)
        if Finite(current) and Finite(maximum) and maximum > 0 then
            return string.format("%.1f%%", current * 100 / maximum)
        end
    end,
}

-- Label, display value, severity and alternate value of a built-in source.
function Standard.Format(key)
    if key == "date" then return LABELS[key], date("%d-%m-%Y") end
    if key == "fpsLatency" then
        local fps = S.ReadInfoSource("fps")
        local _, world = S.ReadInfoSource("latency")
        if Finite(fps) and Finite(world) then
            return LABELS[key], floor(fps + .5) .. " / " .. Milliseconds(world),
                (fps < 30 or world >= 200) and "bad" or nil
        end
        return LABELS[key], NO_VALUE
    end
    local value, severity, alternate = FORMATTERS[key](S.ReadInfoSource(Standard.READER[key] or key))
    return LABELS[key], value or NO_VALUE, severity, alternate
end

-- The detail lines of a built-in source below the tooltip title.
function Standard.TooltipLines(tooltip, button, config)
    local key = button.source
    if key == "gold" or key == "sessionGold" then
        local amount = S.ReadInfoSource("gold")
        if Finite(amount) then
            tooltip:AddDoubleLine(TEXT.current, MoneyText(amount))
            local baseline = SessionBaseline(amount)
            if baseline then tooltip:AddDoubleLine(TEXT.sinceLogin, SignedMoneyText(amount - baseline)) end
        end
        if config.trackAltGold then GoldLedger.AppendTooltip(tooltip, MoneyText, TEXT) end
        return true
    elseif key == "latency" or key == "fpsLatency" then
        local home, world = S.ReadInfoSource("latency")
        if Finite(home) and Finite(world) then
            tooltip:AddDoubleLine(TEXT.homeWorld, floor(home + .5) .. " / " .. Milliseconds(world))
        end
    elseif key == "xp" then
        local level, current, maximum = S.ReadInfoSource("xp")
        if Finite(level) and Finite(current) and Finite(maximum) then
            tooltip:AddDoubleLine(TEXT.level:format(level), current .. " / " .. maximum)
        end
    else
        tooltip:AddLine(button.text or NO_VALUE, 1, 1, 1)
    end
end

-- The Blizzard window of a built-in source. Callers run it out of combat.
-- Durability, Coordinates and Zone places normally carry the secure overlay
-- (Actions.lua), which clicks Blizzard's own button; this runs only when that
-- button is missing. ToggleCalendar loads Blizzard_Calendar and shows the
-- calendar through ShowUIPanel (Calendar_Toggle). OpenAllBags has no Blizzard
-- button with the same effect: the backpack button puts a held item into the
-- bag or toggles the backpack alone (BaseBagSlotButtonMixin:BagSlotOnClick).
function Standard.Click(button)
    local name = CLICK[button.source]
    if name then
        _G[name]()
    elseif button.source == "durability" then
        ToggleCharacter("PaperDollFrame")
    elseif button.source == "clock" then
        ToggleCalendar()
    end
end

local _, P = ...
local NS, S = P.NS, P.Suite
local MM = P.Minimap
local M = MM.M
local CLOCK, DATE, LATENCY = NS.MinimapClockSource, NS.MinimapDatePosition, NS.MinimapLatencySource
local TEXT_ANCHOR, BOX = NS.MinimapTextAnchor, NS.MinimapTextBox
-- Information texts on the map. One cancellable timer serves every sampled text
-- (clock, FPS, latency, coordinates); durability, location, weather, difficulty and the
-- calendar invite mark are event-driven. Hidden texts do no work and only
-- remember that they are stale; coordinates stop sampling while no position
-- exists and resume on the next zone change.
local keys = { "Clock", "FPS", "Latency", "Coordinates", "Durability", "Location", "Weather" }
local eventFields = { Durability = true, Location = true, Weather = true }
local DURABILITY_EVENTS = { "UPDATE_INVENTORY_DURABILITY", "PLAYER_EQUIPMENT_CHANGED" }
local ZONE_EVENTS = { "ZONE_CHANGED", "ZONE_CHANGED_INDOORS", "ZONE_CHANGED_NEW_AREA" }
local DIFFICULTY_EVENTS = { "PLAYER_DIFFICULTY_CHANGED", "GROUP_ROSTER_UPDATE", "INSTANCE_GROUP_SIZE_CHANGED",
    "CHALLENGE_MODE_START", "CHALLENGE_MODE_COMPLETED", "CHALLENGE_MODE_RESET" }
local INVITE_EVENT = "CALENDAR_UPDATE_PENDING_INVITES"
local zoneColors = {
    sanctuary = "69ccf0", arena = "ff1a1a", friendly = "1aff1a", hostile = "ff1a1a", contested = "ffb300",
}
local outlines = { "", "OUTLINE", "THICKOUTLINE", "MONOCHROME,OUTLINE" }
-- GetInstanceInfo difficulty IDs: tag and colour tier (1 normal, 2 heroic, 3
-- mythic, 4 raid finder/follower, 5 timewalking, 6 keystone). Bare tags carry
-- no group size. Unknown IDs fall back to GetDifficultyInfo's heroic/mythic flags.
local TAGS = {
    [1] = { "N", 1 },
    [2] = { "H", 2 },
    [23] = { "M", 3 },
    [14] = { "N", 1 },
    [15] = { "H", 2 },
    [16] = { "M", 3 },
    [233] = { "M", 3 },
    [3] = { "N", 1 },
    [4] = { "N", 1 },
    [5] = { "H", 2 },
    [6] = { "H", 2 },
    [9] = { "N", 1 },
    [148] = { "N", 1 },
    [173] = { "N", 1 },
    [174] = { "H", 2 },
    [242] = { "N", 1 },
    [243] = { "N", 1 },
    [7] = { "LFR", 4 },
    [17] = { "LFR", 4 },
    [205] = { "F", 4, true },
    [24] = { "TW", 5 },
    [33] = { "TW", 5 },
    [151] = { "TW", 5 },
    [18] = { "EVT", 1 },
    [19] = { "EVT", 1 },
    [30] = { "EVT", 1 },
    [25] = { "PvP", 1 },
    [29] = { "PvP", 1 },
    [32] = { "PvP", 1 },
    [34] = { "PvP", 1 },
    [45] = { "PvP", 1 },
    [12] = { "S", 1 },
    [38] = { "S", 1 },
    [11] = { "HS", 2 },
    [39] = { "HS", 2 },
    [40] = { "MS", 3 },
    [8] = { "M+", 6, true },
    [208] = { "D", 1, true },
}
local TIER_COLORS = { "e0a060", "4aa8ff", "b36bff", "a0a0a0", "40d8d8", "ff9a33" }
-- Flexible raids show the current group size instead of the maximum.
local FLEX = { [14] = true, [15] = true, [17] = true, [33] = true }

local Finite = S.Finite
-- 12.1.0 lacks C_Weather (12.1.5 and WoW Forever have it).
local GetCurrentWeather = C_Weather and C_Weather.GetCurrentWeather

-- Retail and WoW Forever have every other text's API.
function S.CanShowMinimapInfo(key)
    if key == "Weather" then return GetCurrentWeather ~= nil end
    return true
end

-- 12-hour times carry Blizzard's localized AM/PM words (TIMEMANAGER_AM/PM,
-- the calendar's own), before the digits where Blizzard's own 12-hour format
-- puts its word first (TIME_TWELVEHOURAM: "%d:%02d AM" on enUS).
local MERIDIEM_FIRST
do
    local word, digits = TIME_TWELVEHOURAM:find(TIMEMANAGER_AM, 1, true), TIME_TWELVEHOURAM:find("%", 1, true)
    MERIDIEM_FIRST = word ~= nil and digits ~= nil and word < digits
end
local function TwelveHour(digits, hour)
    local word = hour < 12 and TIMEMANAGER_AM or TIMEMANAGER_PM
    if MERIDIEM_FIRST then return word .. " " .. digits end
    return digits .. " " .. word
end

-- The realm clock; nil while the client has no game time.
local function ServerTime(c, second)
    local hour, minute = S.ReadInfoSource("clockTime")
    if not Finite(hour) or not Finite(minute) then return nil end
    local shown = hour
    if not c.infoClock24Hour then
        shown = hour % 12
        if shown == 0 then shown = 12 end
    end
    local digits = c.infoClockSeconds and second and string.format("%02d:%02d:%02d", shown, minute, second)
        or string.format("%02d:%02d", shown, minute)
    return c.infoClock24Hour and digits or TwelveHour(digits, hour)
end

-- The computer's clock (entry.clockFormat leaves the AM/PM word out).
local function LocalTime(entry, c, now)
    local digits = date(entry.clockFormat)
    if c.infoClock24Hour then return digits end
    return TwelveHour(digits, now.hour)
end

local function Clock(entry)
    local c = M.config
    local stamp = S.ReadInfoSource("clockStamp")
    local second = Finite(stamp) and math.floor(stamp) % 60 or nil
    local source = c.infoClockSource
    local now = (source ~= CLOCK.REALM and not c.infoClock24Hour or c.infoClockDate) and date("*t") or nil
    local server = source ~= CLOCK.LOCAL and ServerTime(c, second) or nil
    local localTime = source ~= CLOCK.REALM and LocalTime(entry, c, now) or nil
    local text = source == CLOCK.REALM and server or source == CLOCK.LOCAL and localTime
        or server and localTime and server .. " / " .. localTime
    if c.infoClockDate then
        -- Blizzard's localized short date (SHORTDATE through FormatShortDate).
        local calendarDate = FormatShortDate(now.day, now.month, now.year)
        if c.infoClockDatePosition == DATE.ABOVE then
            text = text and calendarDate .. "\n" .. text or calendarDate
        elseif c.infoClockDatePosition == DATE.BELOW then
            text = text and text .. "\n" .. calendarDate or calendarDate
        else
            text = text and text .. "  " .. calendarDate or calendarDate
        end
    end
    return text or "--", c.infoClockSeconds and 1 or second and 60 - second or 1
end

-- One latency unit for both values, as the DataTexts show it.
local FPS_TEXT, MS_TEXT = S.Text("%d FPS"), S.Text("%d ms")
local function FPS(entry)
    local value = S.ReadInfoSource("fps")
    if not Finite(value) or value < 0 then return "--", entry.interval end
    value = math.floor(value + .5)
    if value ~= entry.lastFPS then
        entry.lastFPS = value
        entry.fpsText = FPS_TEXT:format(value)
    end
    local severity = value < M.config.infoFPSWarning and 3 or value < M.config.infoFPSGood and 2 or 1
    return entry.fpsText, entry.interval, severity
end

local function Latency(entry)
    local home, world = S.ReadInfoSource("latency")
    local mode = M.config.infoLatencySource
    home = Finite(home) and home >= 0 and math.floor(home + .5) or nil
    world = Finite(world) and world >= 0 and math.floor(world + .5) or nil
    if mode ~= LATENCY.WORLD and not home or mode ~= LATENCY.HOME and not world then return "--", entry.interval end
    if home ~= entry.lastHome or world ~= entry.lastWorld or mode ~= entry.lastMode then
        entry.lastHome, entry.lastWorld, entry.lastMode = home, world, mode
        entry.latencyText = mode == LATENCY.HOME and MS_TEXT:format(home)
            or mode == LATENCY.WORLD and MS_TEXT:format(world)
            or home .. " / " .. MS_TEXT:format(world)
    end
    local value = mode == LATENCY.HOME and home or mode == LATENCY.WORLD and world or math.max(home, world)
    local severity = value >= M.config.infoLatencyBad and 3 or value >= M.config.infoLatencyWarning and 2 or 1
    return entry.latencyText, entry.interval, severity
end

-- A nil delay parks the text until a zone change re-arms it (instances and
-- loading screens report no position; polling them would only repeat "--").
local function Coordinates(entry)
    local x, y = S.ReadInfoSource("coordinates")
    if not Finite(x) or not Finite(y) or x < 0 or x > 1 or y < 0 or y > 1 then return "--" end
    local cx, cy = math.floor(x * entry.coordinateScale + .5), math.floor(y * entry.coordinateScale + .5)
    if cx ~= entry.lastX or cy ~= entry.lastY then
        entry.lastX, entry.lastY = cx, cy
        entry.coordinatesText = string.format(entry.coordinateFormat, cx / entry.decimalScale, cy / entry.decimalScale)
    end
    return entry.coordinatesText, entry.interval
end

local function Durability(entry)
    local lowest, currentTotal, maxTotal = S.ReadInfoSource("durability")
    if not lowest then return "--" end
    local value = math.floor((M.config.infoDurabilityMode == NS.MinimapDurabilityMode.COMBINED and currentTotal / maxTotal or lowest) * 100)
    if entry.lastDurability ~= value then
        entry.lastDurability = value
        entry.durabilityText = entry.iconPrefix .. value .. "%"
    end
    local severity = value <= M.config.infoDurabilityBad and 3 or value <= M.config.infoDurabilityWarning and 2 or 1
    return entry.durabilityText, nil, severity
end

local function Location(entry)
    local c = M.config
    local rawZone, rawSubzone = S.ReadInfoSource("location")
    local zone = c.infoLocationZone and (rawZone or "") or ""
    local subzone = c.infoLocationSubzone and (rawSubzone or "") or ""
    if subzone == zone then subzone = "" end
    if zone ~= entry.lastZone or subzone ~= entry.lastSubzone then
        entry.lastZone, entry.lastSubzone = zone, subzone
        entry.locationText = zone ~= "" and subzone ~= "" and zone .. entry.separator .. subzone
            or zone ~= "" and zone or subzone ~= "" and subzone or "--"
    end
    local color
    if entry.useZoneColor then
        local kind = C_PvP.GetZonePVPInfo()
        color = S.Public(kind) and type(kind) == "string" and zoneColors[kind] or "ffd100"
    end
    return entry.locationText, nil, nil, color
end
-- Runs only while S.CanShowMinimapInfo("Weather") allows the text (C_Weather).
local function Weather(entry)
    local info = GetCurrentWeather()
    local kind
    if S.Public(info) and type(info) == "table" and Finite(info.type) then kind = info.type end
    local text, label, texture = NS.MinimapStyle.WeatherContent(M.config, kind)
    entry.tooltipText, entry.weatherTexture = label, texture
    return text
end
local readers = {
    Clock = Clock, FPS = FPS, Latency = Latency, Coordinates = Coordinates,
    Durability = Durability, Location = Location, Weather = Weather,
}
local Color = S.RGB

-- The player's class color as six hex digits (texts store colors as hex).
local function ClassColor()
    local _, token = UnitClass("player")
    if not S.Public(token) then return end
    return S.ClassHex(token)
end

-- Group size and difficulty letter, e.g. "20M", "5H", "M+12", "25LFR".
local function DifficultyText()
    local _, kind, difficulty, _, maxPlayers, _, dynamic, _, groupSize = GetInstanceInfo()
    if not S.Public(kind) or kind == "none" or kind == "interior" or kind == "neighborhood"
        or not Finite(difficulty) then
        return ""
    end
    local tag, letter, tier = TAGS[difficulty], nil, 1
    if tag then
        letter, tier = tag[1], tag[2]
    else
        local _, _, heroic, _, displayHeroic, displayMythic = GetDifficultyInfo(difficulty)
        if S.Public(displayMythic) and displayMythic then
            letter, tier = "M", 3
        elseif S.Public(heroic) and S.Public(displayHeroic) and (heroic or displayHeroic) then
            letter, tier = "H", 2
        else
            letter = "N"
        end
    end
    if difficulty == 8 then
        local level = C_ChallengeMode.GetActiveKeystoneInfo()
        return Finite(level) and level > 0 and letter .. math.floor(level) or letter, tier
    end
    if tag and tag[3] then return letter, tier end
    local flexible = FLEX[difficulty] or (S.Public(dynamic) and dynamic == true)
    local size = flexible and Finite(groupSize) and groupSize > 0 and groupSize or maxPlayers
    return (Finite(size) and size > 0 and math.floor(size) or "") .. letter, tier
end

local function Invites()
    local count = C_Calendar.GetNumPendingInvites()
    return Finite(count) and count > 0
end

local function Cancel()
    if M.infoTimer then
        M.infoTimer:Cancel()
        M.infoTimer = nil
    end
    M.infoVisible = false
    MM.HideInfoTooltip()
end

local function Visible()
    local frame = M.infoFrame
    if not M.active or not M.infoActive or M.infoConfiguring or not frame or NS.Safety.IsForbidden(frame)
        or not frame:IsVisible() then
        return false
    end
    local alpha = frame:GetEffectiveAlpha()
    return Finite(alpha) and alpha > 0
end
MM.InfoVisible = Visible

-- The box and the invite mark follow the text's width, re-measured on change only.
local function Decorate(entry)
    local width = entry.contentWidth or entry.label:GetStringWidth()
    if not Finite(width) then width = 0 end
    if entry.box and entry.box:IsShown() then entry.box:SetWidth(math.max(entry.size, width + 8)) end
    local mark = entry.invite
    if mark and mark:IsShown() then
        mark:ClearAllPoints()
        if entry.justify == "RIGHT" then
            mark:SetPoint("RIGHT", entry.button, "RIGHT", -(width + 2), 0)
        elseif entry.justify == "LEFT" then
            mark:SetPoint("LEFT", entry.button, "LEFT", width + 2, 0)
        else
            mark:SetPoint("LEFT", entry.button, "CENTER", width / 2 + 2, 0)
        end
    end
end

local function Sample(entry, key)
    local previousTexture = entry.weatherTexture
    local text, delay, severity, overrideColor = readers[key](entry)
    if text ~= entry.text or previousTexture ~= entry.weatherTexture then
        if text ~= entry.text then
            entry.label:SetText(text)
            entry.text = text
        end
        if key == "Weather" then
            if previousTexture ~= entry.weatherTexture then entry.icon:SetTexture(entry.weatherTexture) end
            NS.MinimapStyle.LayoutWeather(entry, M.config, text)
        end
        Decorate(entry)
    end
    local color = overrideColor or entry.statusColors and severity and entry.statusColors[severity] or entry.color
    if color ~= entry.lastColor then
        entry.label:SetTextColor(Color(color))
        entry.lastColor = color
    end
    entry.dirty = false
    return delay
end

local function UpdateDifficulty()
    local label = M.difficultyLabel
    if not M.difficultyActive or not label then return end
    if not Visible() then
        M.difficultyDirty = true
        return
    end
    M.difficultyDirty = false
    local text, tier = DifficultyText()
    if text ~= M.difficultyText then
        label:SetText(text)
        M.difficultyText = text
    end
    local color = M.config.infoDifficultyColors and TIER_COLORS[tier] or "ffffff"
    if color ~= M.difficultyColor then
        label:SetTextColor(Color(color))
        M.difficultyColor = color
    end
end

local function UpdateInvite()
    local entry = M.infoEntries and M.infoEntries.Clock
    local mark = entry and entry.invite
    if not mark then return end
    mark:SetShown(M.inviteWanted and entry.active and Invites() or false)
    Decorate(entry)
end

local Tick
Tick = function()
    M.infoTimer = nil
    if not Visible() then return end
    local now, soonest = GetTime(), nil
    for _, key in ipairs(keys) do
        local entry = M.infoEntries[key]
        if entry and entry.active and entry.button:IsShown() then
            if eventFields[key] then
                if entry.dirty then Sample(entry, key) end
            else
                if entry.due == nil or (entry.due and entry.due <= now) then
                    local delay = Sample(entry, key)
                    entry.due = delay and now + delay or false
                end
                if entry.due and (not soonest or entry.due < soonest) then soonest = entry.due end
            end
        end
    end
    if M.difficultyDirty then UpdateDifficulty() end
    if soonest then M.infoTimer = S.ScheduleDataTick("minimap", math.max(.05, soonest - now), Tick) end
end

function MM.UpdateInfoVisibility()
    if not Visible() then
        Cancel()
        return
    end
    if not M.infoVisible then
        M.infoVisible = true
        for key in pairs(eventFields) do
            local entry = M.infoEntries[key]
            if entry then entry.dirty = true end
        end
        if M.difficultyActive then M.difficultyDirty = true end
    end
    if not M.infoTimer then Tick() end
end

-- Coordinates parked without a position sample again right away.
local function Rearm()
    local entry = M.infoEntries and M.infoEntries.Coordinates
    if not entry or not entry.active then return end
    entry.due = nil
    if M.infoTimer then
        M.infoTimer:Cancel()
        M.infoTimer = nil
    end
    if Visible() then Tick() end
end

local function EventField(key)
    local entry = M.infoEntries and M.infoEntries[key]
    if not entry or not entry.active then return end
    entry.dirty = true
    if Visible() then Sample(entry, key) end
end
local function DurabilityChanged()
    S.InvalidateSharedData("durability")
    EventField("Durability")
end
local function ZoneChanged()
    S.InvalidateSharedData("location")
    S.InvalidateSharedData("coordinates")
    EventField("Location")
    EventField("Weather")
    Rearm()
    UpdateDifficulty()
end
local function DifficultyChanged() UpdateDifficulty() end
local function WeatherChanged() EventField("Weather") end
local function WorldChanged()
    S.InvalidateSharedData("durability")
    EventField("Durability")
    ZoneChanged()
    UpdateInvite()
    local c = M.config
    if c.infoCoordinates and c.infoCoordinatesHideInstance then
        -- Entering or leaving an instance may show or hide the coordinates text.
        if NS.IsCombatLocked() then
            MM.Force("texts")
            S.Queue("minimap")
        else
            MM.RefreshTexts()
        end
    end
end

local function CreateEntry(key)
    local button = S.CreateFrame("Button", nil, M.infoFrame)
    button.infoKey = key
    button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    -- Clicks, tooltips and the secure window overlay: InfoInput.lua.
    for script, handler in pairs(MM.InfoScripts) do button:SetScript(script, handler) end
    local label = S.CreateFontString(button, nil, "OVERLAY", "GameFontNormalSmall")
    label:SetAllPoints(button)
    label:SetWordWrap(false)
    local icon = key == "Weather" and S.CreateTexture(button, nil, "ARTWORK") or nil
    return { button = button, label = label, icon = icon }
end

local function EnsureFrame()
    local host = MM.host
    if M.infoFrame and NS.Safety.IsForbidden(M.infoFrame) then M.infoFrame, M.infoEntries = nil, nil end
    if not M.infoFrame then
        M.infoFrame = S.CreateFrame("Frame", nil, host)
        M.infoFrame:EnableMouse(false)
        M.infoFrame:SetScript("OnShow", MM.UpdateInfoVisibility)
        M.infoFrame:SetScript("OnHide", Cancel)
        M.infoEntries = {}
    end
    M.infoFrame:ClearAllPoints()
    M.infoFrame:SetAllPoints(host)
    M.infoFrame:SetFrameLevel(MM.mapLevel + 13)
end

-- Anchors 1-9 sit inside the map; 10 and 11 above and below it (past the border).
local function Anchor(region, anchor, x, y)
    local host, border = MM.host, MM.BorderWidth()
    region:ClearAllPoints()
    if anchor == TEXT_ANCHOR.ABOVE then
        region:SetPoint("BOTTOM", host, "TOP", x, y + border)
        return "CENTER"
    end
    if anchor == TEXT_ANCHOR.BELOW then
        region:SetPoint("TOP", host, "BOTTOM", x, y - border)
        return "CENTER"
    end
    local point = MM.ANCHORS[anchor] or "CENTER"
    region:SetPoint(point, host, point, x, y)
    return point:find("LEFT", 1, true) and "LEFT" or point:find("RIGHT", 1, true) and "RIGHT" or "CENTER"
end

local function Style(entry, key, c, classColor, boxR, boxG, boxB)
    local prefix = "info" .. key
    entry.active, entry.due, entry.lastColor, entry.dirty = true, nil, nil, true
    entry.color = c[prefix .. "ClassColor"] and classColor or c[prefix .. "Color"]
    entry.statusColors = nil
    if (key == "FPS" or key == "Latency") and c.infoStatusColors and not (c[prefix .. "ClassColor"] and classColor) then
        entry.statusColors = { c.infoGoodColor, c.infoWarningColor, c.infoBadColor }
    elseif key == "Durability" and c.infoDurabilityStatusColors and not (c[prefix .. "ClassColor"] and classColor) then
        entry.statusColors = { c.infoDurabilityGoodColor, c.infoDurabilityWarningColor, c.infoDurabilityBadColor }
    end
    entry.interval = c[prefix .. "Interval"] or 1
    if key == "Clock" then
        entry.clockFormat = (c.infoClock24Hour and "%H:%M" or "%I:%M") .. (c.infoClockSeconds and ":%S" or "")
    elseif key == "Coordinates" then
        entry.decimalScale = 10 ^ c.infoCoordinatesDecimals
        entry.coordinateScale = entry.decimalScale * 100
        entry.coordinateFormat = "%." .. c.infoCoordinatesDecimals .. "f, %." .. c.infoCoordinatesDecimals .. "f"
        entry.lastX, entry.lastY = nil, nil
    elseif key == "Durability" then
        entry.lastDurability = nil
        entry.iconPrefix = c.infoDurabilityIcon
            and "|TInterface\\Durability\\UI-Durability-Icons:" .. c.infoDurabilitySize .. ":"
                .. math.floor(c.infoDurabilitySize * 18 / 22) .. ":0:0:128:128:0:18:0:22|t "
            or ""
    elseif key == "Location" then
        entry.lastZone, entry.lastSubzone = nil, nil
        entry.separator = c.infoLocationBelow and "\n" or " - "
        entry.useZoneColor = c.infoLocationZoneColor and not (c.infoLocationClassColor and classColor)
    end
    local size = c[prefix .. "Size"]
    S.SetStyledFont(entry.label, S.ResolveFont(c[prefix .. "Font"]), size,
        outlines[c[prefix .. "Outline"]], c[prefix .. "Rendering"],
        c[prefix .. "Shadow"], c[prefix .. "ShadowOpacity"], c[prefix .. "ShadowDistance"])
    local lines = key == "Location" and c.infoLocationBelow and c.infoLocationZone and c.infoLocationSubzone and 2
        or key == "Clock" and c.infoClockDate and c.infoClockDatePosition ~= DATE.BESIDE and 2 or 1
    local height = key == "Weather" and NS.MinimapStyle.WeatherHeight(c) or size * lines
    local width = c[prefix .. "Width"]
    local weather = NS.MinimapWeatherDisplay
    if key == "Weather" and c.infoWeatherDisplay ~= weather.TEXT then
        width = c.infoWeatherDisplay == weather.ICON and c.infoWeatherIconSize or math.max(width, c.infoWeatherIconSize + 8)
    end
    entry.size = key == "Weather" and height or size
    entry.button:SetSize(width, height + 8)
    entry.justify = Anchor(entry.button, c[prefix .. "Anchor"], c[prefix .. "X"], c[prefix .. "Y"])
    entry.label:SetJustifyH(entry.justify)
    local boxMode = c[prefix .. "Box"]
    if boxMode == BOX.BORDER or boxMode == BOX.CUSTOM then
        if not entry.box then entry.box = S.CreateTexture(entry.button, nil, "BACKGROUND") end
        local box = entry.box
        box:ClearAllPoints()
        if entry.justify == "LEFT" then
            box:SetPoint("LEFT", entry.button, "LEFT", -4, 0)
        elseif entry.justify == "RIGHT" then
            box:SetPoint("RIGHT", entry.button, "RIGHT", 4, 0)
        else
            box:SetPoint("CENTER", entry.button, "CENTER")
        end
        box:SetHeight(height + 4)
        if boxMode == BOX.CUSTOM then boxR, boxG, boxB = Color(c[prefix .. "BoxColor"]) end
        box:SetColorTexture(boxR, boxG, boxB, 1)
        box:Show()
    elseif entry.box then
        entry.box:Hide()
    end
    entry.text = nil
end

local function Listen(events, handler, wanted)
    for i = 1, #events do
        if wanted then MM.Listen(events[i], "info", handler) else MM.Unlisten(events[i], "info") end
    end
end

local function ListenOne(event, handler, wanted)
    if wanted then MM.Listen(event, "info", handler) else MM.Unlisten(event, "info") end
end

-- Coordinates can be set to hide inside instances.
local function CoordinatesHidden(c)
    if not (c.infoCoordinates and c.infoCoordinatesHideInstance) then return false end
    local inside = IsInInstance()
    return not S.Public(inside) or inside == true
end

local function TextWanted(c, key, hideCoordinates)
    return c["info" .. key] and not (key == "Coordinates" and hideCoordinates) and S.CanShowMinimapInfo(key)
end

-- Registers only the events the enabled texts need; returns whether the
-- difficulty label is wanted.
local function SyncTextEvents(c)
    local durability = c.infoDurability and S.CanShowMinimapInfo("Durability")
    local location = c.infoLocation and S.CanShowMinimapInfo("Location")
    local weather = c.infoWeather and S.CanShowMinimapInfo("Weather")
    local coordinates = c.infoCoordinates and S.CanShowMinimapInfo("Coordinates")
    local difficulty = c.infoDifficulty
    -- The mark stands in for Blizzard's calendar button while that is not shown.
    M.inviteWanted = c.infoClock and not (c.showCalendar and S.MinimapElementAvailable("Calendar"))
    Listen(DURABILITY_EVENTS, DurabilityChanged, durability)
    Listen(ZONE_EVENTS, ZoneChanged, location or coordinates or difficulty or weather)
    ListenOne("WEATHER_CHANGED", WeatherChanged, weather)
    Listen(DIFFICULTY_EVENTS, DifficultyChanged, difficulty)
    ListenOne(INVITE_EVENT, UpdateInvite, M.inviteWanted)
    ListenOne("PLAYER_ENTERING_WORLD", WorldChanged,
        durability or location or coordinates or weather or difficulty or M.inviteWanted)
    return difficulty
end

-- Styles and places every wanted text; returns how far texts reach above
-- and below the map.
local function LayoutEntries(c, hideCoordinates)
    local classColor
    for _, key in ipairs(keys) do
        if c["info" .. key] and c["info" .. key .. "ClassColor"] then
            classColor = ClassColor()
            break
        end
    end
    local boxR, boxG, boxB = MM.BorderRGB()
    local above, below = 0, 0
    for _, key in ipairs(keys) do
        local prefix, entry = "info" .. key, M.infoEntries[key]
        if TextWanted(c, key, hideCoordinates) then
            if not entry then
                entry = CreateEntry(key)
                M.infoEntries[key] = entry
            end
            Style(entry, key, c, classColor, boxR, boxG, boxB)
            local anchor = c[prefix .. "Anchor"]
            local lines = key == "Clock" and c.infoClockDate and c.infoClockDatePosition ~= DATE.BESIDE and 2
                or key == "Location" and c.infoLocationBelow and c.infoLocationZone and c.infoLocationSubzone and 2 or 1
            local height = (key == "Weather" and NS.MinimapStyle.WeatherHeight(c) or c[prefix .. "Size"] * lines) + 8
            if anchor == TEXT_ANCHOR.ABOVE then above = math.max(above, c[prefix .. "Y"] + height) end
            if anchor == TEXT_ANCHOR.BELOW then below = math.max(below, height - c[prefix .. "Y"]) end
            entry.button:SetShown(key ~= "Coordinates" or c.infoCoordinatesMode == NS.MinimapCoordinatesMode.ALWAYS or MM.Revealed())
        elseif entry then
            entry.active = false
            entry.button:Hide()
        end
    end
    return above, below
end

local function ApplyInviteMark(c)
    local clock = M.infoEntries.Clock
    if clock and M.inviteWanted and not clock.invite then
        clock.invite = S.CreateTexture(clock.button, nil, "ARTWORK")
        clock.invite:SetTexture("Interface\\Calendar\\EventNotification")
        clock.invite:SetTexCoord(0.03125, 0.6484375, 0.03125, 0.8671875)
    end
    if clock and clock.invite then clock.invite:SetSize(c.infoClockSize, c.infoClockSize) end
    UpdateInvite()
end

local function ApplyDifficultyLabel(c, difficulty)
    if not difficulty then
        if M.difficultyLabel then M.difficultyLabel:Hide() end
        return
    end
    if not M.difficultyLabel then
        M.difficultyLabel = S.CreateFontString(M.infoFrame, nil, "OVERLAY", "GameFontNormalSmall")
    end
    local label = M.difficultyLabel
    S.SetStyledFont(label, S.ResolveFont(c.infoDifficultyFont), c.infoDifficultySize,
        outlines[c.infoDifficultyOutline] or "OUTLINE", c.infoDifficultyRendering,
        c.infoDifficultyShadow, c.infoDifficultyShadowOpacity, c.infoDifficultyShadowDistance)
    label:SetJustifyH(Anchor(label, c.infoDifficultyAnchor, c.infoDifficultyX, c.infoDifficultyY))
    label:Show()
    M.difficultyText, M.difficultyColor, M.difficultyDirty = nil, nil, true
end

function MM.RefreshTexts()
    if NS.IsCombatLocked() then
        MM.Force("texts")
        S.Queue("minimap")
        return
    end
    Cancel()
    MM.DetachInfoOverlay()
    local c = M.config
    local hideCoordinates = CoordinatesHidden(c)
    local difficulty = SyncTextEvents(c)
    local any = difficulty
    for _, key in ipairs(keys) do
        if TextWanted(c, key, hideCoordinates) then
            any = true
            break
        end
    end
    M.difficultyActive = difficulty
    if not any or not MM.host then
        M.infoActive = false
        if M.infoFrame and not NS.Safety.IsForbidden(M.infoFrame) then M.infoFrame:Hide() end
        MM.SetExtent("texts", 0, 0, 0, 0)
        return
    end
    M.infoActive, M.infoConfiguring = true, true
    EnsureFrame()
    local above, below = LayoutEntries(c, hideCoordinates)
    ApplyInviteMark(c)
    ApplyDifficultyLabel(c, difficulty)
    local border = MM.BorderWidth()
    MM.SetExtent("texts", 0, 0, above > 0 and above + border or 0, below > 0 and below + border or 0)
    M.infoFrame:Show()
    M.infoConfiguring = false
    MM.UpdateInfoVisibility()
end

MM.OnHover(function(shown)
    local entry = M.infoEntries and M.infoEntries.Coordinates
    if not M.active or not entry or not entry.active or M.config.infoCoordinatesMode ~= NS.MinimapCoordinatesMode.MOUSEOVER then return end
    entry.button:SetShown(shown)
    if shown then Rearm() end
end)

function MM.ReleaseTexts()
    Cancel()
    MM.DetachInfoOverlay()
    M.infoActive, M.difficultyActive = false, false
    if M.infoFrame and not NS.Safety.IsForbidden(M.infoFrame) then M.infoFrame:Hide() end
end

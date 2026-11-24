local _, P = ...
local NS, S = P.NS, P.Suite
local MM = P.Minimap
local M = MM.M
local CLOCK, LATENCY = NS.MinimapClockSource, NS.MinimapLatencySource
local MinimapStyle = NS.MinimapStyle
local TEXT_ANCHOR, BOX = NS.MinimapTextAnchor, NS.MinimapTextBox
-- Information texts on the map. One cancellable timer serves every timed text
-- (clock, calendar day, coordinates); durability, location, weather, difficulty
-- and the calendar invite mark are event-driven. Hidden texts do no work and only
-- remember that they are stale; coordinates stop sampling while no position
-- exists and resume on the next zone change.
-- FPS and latency retain their last reading between player and pointer events.
-- The configured intervals bound automatic movement and combat samples.
local keys = { "CalendarDay", "Clock", "FPS", "Latency", "Coordinates", "Durability", "Location", "Weather" }
local timedEntries, eventEntries = {}, {}
local eventFields = { Durability = true, Location = true, Weather = true, FPS = true, Latency = true }
local TELEMETRY_EVENTS = { "PLAYER_ENTERING_WORLD", "ZONE_CHANGED_NEW_AREA", "PLAYER_REGEN_DISABLED",
    "PLAYER_REGEN_ENABLED", "PLAYER_STARTED_MOVING", "PLAYER_STOPPED_MOVING" }
local DURABILITY_EVENTS = { "UPDATE_INVENTORY_DURABILITY", "PLAYER_EQUIPMENT_CHANGED" }
local ZONE_EVENTS = { "ZONE_CHANGED", "ZONE_CHANGED_INDOORS", "ZONE_CHANGED_NEW_AREA" }
local DIFFICULTY_EVENTS = { "PLAYER_DIFFICULTY_CHANGED", "GROUP_ROSTER_UPDATE", "INSTANCE_GROUP_SIZE_CHANGED",
    "CHALLENGE_MODE_START", "CHALLENGE_MODE_COMPLETED", "CHALLENGE_MODE_RESET" }
local INVITE_EVENT = "CALENDAR_UPDATE_PENDING_INVITES"
local zoneColors = {
    sanctuary = "69ccf0", arena = "ff1a1a", friendly = "1aff1a", hostile = "ff1a1a", contested = "ffb300",
}
local outlines = { "", "OUTLINE", "THICKOUTLINE", "MONOCHROME,OUTLINE" }
local TIER_COLORS = NS.MinimapDifficultyColors
local REVEAL = NS.MinimapTextReveal
-- Each text shows always or on mouseover; the coordinates keep their own key.
local function RevealKey(key)
    return key == "Coordinates" and "infoCoordinatesMode" or "info" .. key .. "Reveal"
end
MM.InfoRevealKey = RevealKey
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
    return MinimapStyle.ClockContent(c, text, now), c.infoClockSeconds and 1 or second and 60 - second or 1
end

-- One latency unit for both values, as the DataTexts show it.
local FPS_TEXT, MS_TEXT = S.Text("%d FPS"), S.Text("%d ms")
local function FPS(entry)
    local value = S.ReadInfoSource("fps")
    if not Finite(value) or value < 0 then return "--" end
    value = math.floor(value + .5)
    if value ~= entry.lastFPS then
        entry.lastFPS = value
        entry.fpsText = FPS_TEXT:format(value)
    end
    local severity = value < M.config.infoFPSWarning and 3 or value < M.config.infoFPSGood and 2 or 1
    return entry.fpsText, nil, severity
end

local function Latency(entry)
    local home, world = S.ReadInfoSource("latency")
    local mode = M.config.infoLatencySource
    home = Finite(home) and home >= 0 and math.floor(home + .5) or nil
    world = Finite(world) and world >= 0 and math.floor(world + .5) or nil
    if mode ~= LATENCY.WORLD and not home or mode ~= LATENCY.HOME and not world then return "--" end
    if home ~= entry.lastHome or world ~= entry.lastWorld or mode ~= entry.lastMode then
        entry.lastHome, entry.lastWorld, entry.lastMode = home, world, mode
        entry.latencyText = mode == LATENCY.HOME and MS_TEXT:format(home)
            or mode == LATENCY.WORLD and MS_TEXT:format(world)
            or home .. " / " .. MS_TEXT:format(world)
    end
    local value = mode == LATENCY.HOME and home or mode == LATENCY.WORLD and world or math.max(home, world)
    local severity = value >= M.config.infoLatencyBad and 3 or value >= M.config.infoLatencyWarning and 2 or 1
    return entry.latencyText, nil, severity
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
    local zone, subzone, minimap = S.ReadInfoSource("location")
    if zone ~= entry.lastZone or subzone ~= entry.lastSubzone or minimap ~= entry.lastMinimap
        or not entry.locationText then
        entry.lastZone, entry.lastSubzone, entry.lastMinimap = zone, subzone, minimap
        entry.locationText = NS.MinimapStyle.LocationContent(c, zone, subzone, minimap)
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
    CalendarDay = function() return date("%d"), 60 end,
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

local previewListener
function S.SetMinimapPreviewListener(listener)
    previewListener = listener
end

-- The box, invite mark and hit rectangle follow the measured content width.
local function Decorate(entry)
    local width = entry.contentWidth or MinimapStyle.InfoTextWidth(entry)
    local padding = 2
    if entry.box and entry.box:IsShown() then
        local boxWidth = math.max(entry.size, width + 8)
        entry.box:SetWidth(boxWidth)
        padding = (boxWidth - width) / 2
    end
    local free = math.max(0, entry.width - width)
    local justify = entry.justify
    local left = justify == "LEFT" and 0 or justify == "RIGHT" and free or free / 2
    local right = free - left
    local mark = entry.invite
    if mark and mark:IsShown() then
        mark:ClearAllPoints()
        if justify == "RIGHT" then
            mark:SetPoint("RIGHT", entry.button, "RIGHT", -(width + 2), 0)
            left = left - entry.size - 2
        elseif justify == "LEFT" then
            mark:SetPoint("LEFT", entry.button, "LEFT", width + 2, 0)
            right = right - entry.size - 2
        else
            mark:SetPoint("LEFT", entry.button, "CENTER", width / 2 + 2, 0)
            right = right - entry.size - 2
        end
    end
    MM.SetInfoHitInsets(entry, math.max(0, left - padding), math.max(0, right - padding))
end

local function Sample(entry, key)
    local previousTexture = entry.weatherTexture
    local text, delay, severity, overrideColor = readers[key](entry)
    local changed = text ~= entry.text or previousTexture ~= entry.weatherTexture
    if changed then
        if text ~= entry.text then
            if entry.clockSecond then MinimapStyle.SetClockText(entry, text) else entry.label:SetText(text) end
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
        local r, g, b = Color(color)
        entry.label:SetTextColor(r, g, b)
        if entry.clockSecond then entry.clockSecond:SetTextColor(r, g, b) end
        entry.lastColor = color
        changed = true
    end
    entry.dirty = false
    if changed and previewListener then NS.Dispatch(previewListener, key) end
    return delay
end

-- The text's box hugs it like the other texts' boxes do, and rests while
-- there is no text (outside instances) or the text waits for the pointer.
local function FitDifficultyBox(label, text)
    local box, size = M.difficultyBox, M.difficultyBoxSize
    if not box then return end
    box:SetShown(size ~= nil and text ~= "" and label:IsShown())
    if size and text ~= "" then
        local width = label:GetStringWidth()
        box:SetWidth(math.max(size, (Finite(width) and width or 0) + 8))
    end
end

local function UpdateDifficulty()
    local label = M.difficultyLabel
    if not M.difficultyActive or not label then return end
    if not Visible() then
        M.difficultyDirty = true
        return
    end
    M.difficultyDirty = false
    local text, tier = MM.ReadDifficultyText()
    local changed = text ~= M.difficultyText
    if changed then
        label:SetText(text)
        M.difficultyText = text
        FitDifficultyBox(label, text)
    end
    local color = M.config.infoDifficultyColors and TIER_COLORS[tier] or M.config.infoDifficultyColor
    if color ~= M.difficultyColor then
        label:SetTextColor(Color(color))
        M.difficultyColor = color
        changed = true
    end
    if changed and previewListener then NS.Dispatch(previewListener, "Difficulty") end
end

-- The clock carries the invite mark; without it, the calendar day text does.
local INVITE_HOSTS = { "Clock", "CalendarDay" }
local function InviteEntry()
    local entries = M.infoEntries
    for i = 1, #INVITE_HOSTS do
        local entry = entries and entries[INVITE_HOSTS[i]]
        if entry and entry.active then return entry end
    end
end

local function UpdateInvite()
    local host = InviteEntry()
    for i = 1, #INVITE_HOSTS do
        local entry = M.infoEntries and M.infoEntries[INVITE_HOSTS[i]]
        local mark = entry and entry.invite
        if mark then
            mark:SetShown(entry == host and M.inviteWanted and Invites() or false)
            Decorate(entry)
            if previewListener and not M.infoConfiguring then NS.Dispatch(previewListener, INVITE_HOSTS[i]) end
        end
    end
end

local Tick
Tick = function()
    M.infoTimer = nil
    if not Visible() then return Cancel() end
    local now, soonest = GetTime(), nil
    for i = 1, #eventEntries do
        local entry = eventEntries[i]
        if entry.dirty and entry.button:IsShown() then Sample(entry, entry.button.infoKey) end
    end
    for i = 1, #timedEntries do
        local entry = timedEntries[i]
        if entry.button:IsShown() then
            if entry.due == nil or (entry.due and entry.due <= now) then
                local delay = Sample(entry, entry.button.infoKey)
                entry.due = delay and now + delay or false
            end
            if entry.due and (not soonest or entry.due < soonest) then soonest = entry.due end
        end
    end
    if M.difficultyDirty then UpdateDifficulty() end
    if soonest then M.infoTimer = S.ScheduleDataTick("minimap", math.max(.05, soonest - now), Tick) end
end

function MM.UpdateInfoVisibility()
    if not Visible() then
        local wasVisible = M.infoVisible
        Cancel()
        if wasVisible and previewListener then NS.Dispatch(previewListener) end
        return
    end
    if M.infoVisible then return end
    M.infoVisible = true
    for i = 1, #eventEntries do eventEntries[i].dirty = true end
    if M.difficultyActive then M.difficultyDirty = true end
    if not M.infoTimer then Tick() end
    if previewListener then NS.Dispatch(previewListener) end
end

-- Texts that just appeared (mouseover) sample on the next tick, which runs now.
local function Wake()
    if M.infoTimer then
        M.infoTimer:Cancel()
        M.infoTimer = nil
    end
    if Visible() then Tick() end
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
-- One handler for every event and pointer entry that reads FPS and latency.
-- The DataTexts read the same shared values (S.ReadInfoSource) on the same
-- events, so the two displays cost one client call per value.
local function ReadTelemetry(key, now, onDemand)
    local entry = M.infoEntries[key]
    if not entry or not entry.active then return end
    if not onDemand and entry.telemetryAt and now - entry.telemetryAt < entry.interval then return end
    entry.telemetryAt = now
    Sample(entry, key)
end

local function RefreshTelemetry(onDemand)
    if not M.infoTelemetry or not Visible() then return end
    local now = GetTime()
    ReadTelemetry("FPS", now, onDemand)
    ReadTelemetry("Latency", now, onDemand)
end

local function TelemetryChanged(_, event)
    RefreshTelemetry(event == "PLAYER_ENTERING_WORLD" or event == "ZONE_CHANGED_NEW_AREA")
end
local function DifficultyChanged() UpdateDifficulty() end
local function WeatherChanged() EventField("Weather") end
-- Coordinates can be set to hide inside instances.
local function CoordinatesHidden(c)
    if not (c.infoCoordinates and c.infoCoordinatesHideInstance) then return false end
    local inside = IsInInstance()
    return not S.Public(inside) or inside == true
end

local function WorldChanged()
    S.InvalidateSharedData("durability")
    EventField("Durability")
    ZoneChanged()
    UpdateInvite()
    local c = M.config
    if CoordinatesHidden(c) ~= M.infoHideCoordinates then
        -- Only a coordinate visibility transition requires another layout.
        if NS.IsCombatLocked() then
            MM.Force("texts")
            S.Queue("minimap")
        else
            MM.RefreshTexts()
        end
    end
end

-- The pointer on the FPS or latency text reads both before the tooltip
-- (InfoInput.lua) shows the text.
local function TelemetryEnter(button)
    RefreshTelemetry(true)
    MM.InfoScripts.OnEnter(button)
end

local function CreateEntry(key)
    local button = S.CreateFrame("Button", nil, M.infoFrame)
    button.infoKey = key
    button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    -- Clicks, tooltips and the secure window overlay: InfoInput.lua.
    for script, handler in pairs(MM.InfoScripts) do button:SetScript(script, handler) end
    if key == "FPS" or key == "Latency" then button:SetScript("OnEnter", TelemetryEnter) end
    local label = S.CreateFontString(button, nil, "OVERLAY", "GameFontNormalSmall")
    label:SetAllPoints(button)
    label:SetWordWrap(false)
    local icon = key == "Weather" and S.CreateTexture(button, nil, "ARTWORK") or nil
    local clockSecond
    if key == "Clock" then
        clockSecond = S.CreateFontString(button, nil, "OVERLAY", "GameFontNormalSmall")
        clockSecond:SetWordWrap(false)
        clockSecond:SetJustifyV("MIDDLE")
        clockSecond:Hide()
        label:SetJustifyV("MIDDLE")
    end
    return { button = button, label = label, icon = icon, clockSecond = clockSecond }
end

local parentAlphaHooked
local function EnsureFrame()
    local host = MM.host
    if M.infoFrame and NS.Safety.IsForbidden(M.infoFrame) then M.infoFrame, M.infoEntries = nil, nil end
    if not M.infoFrame then
        M.infoFrame = S.CreateFrame("Frame", nil, host)
        M.infoFrame:EnableMouse(false)
        M.infoFrame:SetScript("OnShow", MM.UpdateInfoVisibility)
        M.infoFrame:SetScript("OnHide", function()
            Cancel()
            if previewListener then NS.Dispatch(previewListener) end
        end)
        M.infoEntries = {}
    end
    -- Alpha-only fades (AFK) do not fire OnShow when UIParent returns.
    if not parentAlphaHooked then
        hooksecurefunc(UIParent, "SetAlpha", MM.UpdateInfoVisibility)
        parentAlphaHooked = true
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

-- A text's box starts on the side its text is justified to.
local function PlaceBox(box, owner, justify)
    box:ClearAllPoints()
    if justify == "LEFT" then
        box:SetPoint("LEFT", owner, "LEFT", -4, 0)
    elseif justify == "RIGHT" then
        box:SetPoint("RIGHT", owner, "RIGHT", 4, 0)
    else
        box:SetPoint("CENTER", owner, "CENTER")
    end
end

local function StyleInfoFont(label, c, prefix, size)
    S.SetStyledFont(label, S.ResolveFont(c[prefix .. "Font"]), size,
        outlines[c[prefix .. "Outline"]], c[prefix .. "Rendering"],
        c[prefix .. "Shadow"], c[prefix .. "ShadowOpacity"], c[prefix .. "ShadowDistance"])
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
    entry.mouseover = c[RevealKey(key)] == REVEAL.MOUSEOVER
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
        entry.lastZone, entry.lastSubzone, entry.lastMinimap, entry.locationText = nil, nil, nil, nil
        entry.useZoneColor = c.infoLocationZoneColor and not (c.infoLocationClassColor and classColor)
    end
    local size = c[prefix .. "Size"]
    StyleInfoFont(entry.label, c, prefix, size)
    local lines = key == "Location" and MinimapStyle.LocationLines(c)
        or key == "Clock" and MinimapStyle.ClockLines(c) or 1
    local height = key == "Weather" and NS.MinimapStyle.WeatherHeight(c) or size * lines
    local width = c[prefix .. "Width"]
    local weather = NS.MinimapWeatherDisplay
    if key == "Weather" and c.infoWeatherDisplay ~= weather.TEXT then
        width = c.infoWeatherDisplay == weather.ICON and c.infoWeatherIconSize or math.max(width, c.infoWeatherIconSize + 8)
    end
    entry.size, entry.width, entry.height = key == "Weather" and height or size, width, height + 8
    entry.button:SetSize(width, entry.height)
    entry.justify = Anchor(entry.button, c[prefix .. "Anchor"], c[prefix .. "X"], c[prefix .. "Y"])
    if entry.clockSecond then
        StyleInfoFont(entry.clockSecond, c, prefix, size)
        MinimapStyle.LayoutClock(entry, c, width, entry.justify, 1)
    else
        entry.label:SetJustifyH(entry.justify)
    end
    local boxMode = c[prefix .. "Box"]
    if boxMode == BOX.BORDER or boxMode == BOX.CUSTOM then
        if not entry.box then entry.box = S.CreateTexture(entry.button, nil, "BACKGROUND") end
        local box = entry.box
        PlaceBox(box, entry.button, entry.justify)
        box:SetHeight(height + 4)
        if boxMode == BOX.CUSTOM then boxR, boxG, boxB = Color(c[prefix .. "BoxColor"]) end
        box:SetColorTexture(boxR, boxG, boxB, 1)
        box:Show()
    elseif entry.box then
        entry.box:Hide()
    end
    entry.text = nil
end

local function Listen(events, handler, wanted, key)
    key = key or "info"
    for i = 1, #events do
        if wanted then MM.Listen(events[i], key, handler) else MM.Unlisten(events[i], key) end
    end
end

local function ListenOne(event, handler, wanted)
    if wanted then MM.Listen(event, "info", handler) else MM.Unlisten(event, "info") end
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
    -- The calendar day text replaces Blizzard's calendar button (Elements.lua).
    local calendarShown = c.showCalendar and not c.infoCalendarDay and S.MinimapElementAvailable("Calendar")
    M.inviteWanted = (c.infoClock or c.infoCalendarDay) and not calendarShown
    Listen(DURABILITY_EVENTS, DurabilityChanged, durability)
    Listen(ZONE_EVENTS, ZoneChanged, location or coordinates or difficulty or weather)
    ListenOne("WEATHER_CHANGED", WeatherChanged, weather)
    Listen(DIFFICULTY_EVENTS, DifficultyChanged, difficulty)
    M.infoTelemetry = c.infoFPS or c.infoLatency
    Listen(TELEMETRY_EVENTS, TelemetryChanged, M.infoTelemetry, "infoTelemetry")
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
            local active = eventFields[key] and eventEntries or timedEntries
            active[#active + 1] = entry
            local anchor = c[prefix .. "Anchor"]
            local height = entry.height
            if anchor == TEXT_ANCHOR.ABOVE then above = math.max(above, c[prefix .. "Y"] + height) end
            if anchor == TEXT_ANCHOR.BELOW then below = math.max(below, height - c[prefix .. "Y"]) end
            entry.button:SetShown(not entry.mouseover or MM.Revealed())
        elseif entry then
            entry.active = false
            entry.button:Hide()
        end
    end
    return above, below
end

local function ApplyInviteMark(c)
    local host = InviteEntry()
    if host and M.inviteWanted and not host.invite then
        host.invite = S.CreateTexture(host.button, nil, "ARTWORK")
        host.invite:SetTexture("Interface\\Calendar\\EventNotification")
        host.invite:SetTexCoord(0.03125, 0.6484375, 0.03125, 0.8671875)
    end
    if host and host.invite then
        local size = c["info" .. host.button.infoKey .. "Size"]
        host.invite:SetSize(size, size)
    end
    UpdateInvite()
end

-- The box is made when first wanted; its width follows the text (FitDifficultyBox).
local function ApplyDifficultyBox(c, label, justify)
    local mode = c.infoDifficultyBox
    if mode ~= BOX.BORDER and mode ~= BOX.CUSTOM then
        M.difficultyBoxSize = nil
        if M.difficultyBox then M.difficultyBox:Hide() end
        return
    end
    if not M.difficultyBox then M.difficultyBox = S.CreateTexture(M.infoFrame, nil, "BACKGROUND") end
    local box = M.difficultyBox
    PlaceBox(box, label, justify)
    box:SetHeight(c.infoDifficultySize + 4)
    local r, g, b = MM.BorderRGB()
    if mode == BOX.CUSTOM then r, g, b = Color(c.infoDifficultyBoxColor) end
    box:SetColorTexture(r, g, b, 1)
    M.difficultyBoxSize = c.infoDifficultySize
end

local function ApplyDifficultyLabel(c, difficulty)
    if not difficulty then
        if M.difficultyLabel then M.difficultyLabel:Hide() end
        if M.difficultyBox then M.difficultyBox:Hide() end
        return
    end
    if not M.difficultyLabel then
        M.difficultyLabel = S.CreateFontString(M.infoFrame, nil, "OVERLAY", "GameFontNormalSmall")
        M.difficultyLabel:SetWordWrap(false)
    end
    local label = M.difficultyLabel
    S.SetStyledFont(label, S.ResolveFont(c.infoDifficultyFont), c.infoDifficultySize,
        outlines[c.infoDifficultyOutline] or "OUTLINE", c.infoDifficultyRendering,
        c.infoDifficultyShadow, c.infoDifficultyShadowOpacity, c.infoDifficultyShadowDistance)
    label:SetWidth(c.infoDifficultyWidth)
    local justify = Anchor(label, c.infoDifficultyAnchor, c.infoDifficultyX, c.infoDifficultyY)
    label:SetJustifyH(justify)
    M.difficultyMouseover = c.infoDifficultyReveal == REVEAL.MOUSEOVER
    label:SetShown(not M.difficultyMouseover or MM.Revealed())
    ApplyDifficultyBox(c, label, justify)
    M.difficultyText, M.difficultyColor, M.difficultyDirty = nil, nil, true
end

function MM.RefreshTexts()
    if NS.IsCombatLocked() then
        MM.Force("texts")
        S.Queue("minimap")
        return
    end
    Cancel()
    for i = #timedEntries, 1, -1 do timedEntries[i] = nil end
    for i = #eventEntries, 1, -1 do eventEntries[i] = nil end
    MM.DetachInfoOverlay()
    local c = M.config
    local hideCoordinates = CoordinatesHidden(c)
    M.infoHideCoordinates = hideCoordinates
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
    if not M.active then return end
    if shown then RefreshTelemetry(true) end
    local entries, woken = M.infoEntries, false
    if entries then
        for _, key in ipairs(keys) do
            local entry = entries[key]
            if entry and entry.active and entry.mouseover then
                entry.button:SetShown(shown)
                if shown then
                    entry.due, entry.dirty, woken = nil, true, true
                end
            end
        end
    end
    local label = M.difficultyActive and M.difficultyMouseover and M.difficultyLabel
    if label then
        label:SetShown(shown)
        FitDifficultyBox(label, M.difficultyText or "")
    end
    if woken then Wake() end
    if previewListener then NS.Dispatch(previewListener) end
end)

function MM.ReleaseTexts()
    Cancel()
    MM.DetachInfoOverlay()
    M.infoActive, M.difficultyActive = false, false
    if M.infoFrame and not NS.Safety.IsForbidden(M.infoFrame) then M.infoFrame:Hide() end
end

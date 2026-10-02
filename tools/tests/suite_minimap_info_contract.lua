local root = assert(arg[1], "repository root required")
local H = dofile(root .. "/tools/tests/suite_minimap_harness.lua")
local function check(value, message) if not value then error(message, 2) end end

-- Forever weather uses the client weather event and zone transitions, without
-- adding a timer. Other clients keep the setting off when the API is absent.
do
    local kind, reads = 1, 0
    local W = H.New(root, "Forever", { beforeModules = function(W)
        W.G.C_Weather = { GetCurrentWeather = function()
            reads = reads + 1
            return { type = kind, intensity = 0.5 }
        end }
    end })
    local S = W.S
    check(W.config.infoWeather == true and S.CanShowMinimapInfo("Weather"), "Forever weather default or API gate")
    H.Enable(W, { captured = true, infoLocation = false, infoClock = false })
    W.Step()
    local entry = W.M.infoEntries.Weather
    check(entry and entry.label.text == "Rain" and entry.icon.shown and entry.icon.width == 24
        and entry.icon.texture == "Interface\\AddOns\\MSUF_Suite\\Media\\Weather\\Rain.tga"
        and W.config.infoWeatherDisplay == 3 and W.config.infoWeatherIconStyle == 2
        and W.M.context.frame.events.WEATHER_CHANGED,
        "Forever weather did not appear or subscribe")
    local setText = entry.label.SetText
    function entry.label:SetText(text)
        check(not text:find("|T", 1, true), "weather textures must never depend on font escape parsing")
        return setText(self, text)
    end
    assert(S.Set("minimap", "infoWeatherDisplay", 1))
    local initial = reads
    W.Advance(30)
    check(reads == initial and W.Pending() == 0, "weather polled without an event")
    kind = 2; W.Event("WEATHER_CHANGED")
    check(entry.label.text == "Snow" and reads == initial + 1, "weather event did not refresh")
    kind = 3; W.Event("ZONE_CHANGED_NEW_AREA")
    check(entry.label.text == "Sandstorm", "zone transition did not refresh weather")
    assert(S.Set("minimap", "visibility", 5))
    local hiddenReads = reads
    kind = 0; W.Event("WEATHER_CHANGED")
    check(reads == hiddenReads, "hidden weather still queried the client")
    assert(S.Set("minimap", "visibility", 1))
    check(entry.label.text == "Clear" and reads == hiddenReads + 1, "visible weather stayed stale")
    kind = 99; W.Event("WEATHER_CHANGED")
    check(entry.label.text == "--", "unknown weather was presented as known")

    -- Both artwork sets follow every known state, without extra timers. Icon-only
    -- entries keep a readable tooltip and reserve room for large icon sizes.
    assert(S.SetMany("minimap", { infoWeatherDisplay = 2, infoWeatherIconSize = 48, infoWeatherBox = 2 }))
    local native = { [0] = 535593, [1] = 132852, [2] = 135857, [3] = 463521 }
    local names = { [0] = "Clear", [1] = "Rain", [2] = "Snow", [3] = "Sandstorm" }
    for style = 1, 2 do
        assert(S.Set("minimap", "infoWeatherIconStyle", style))
        for value = 0, 3 do
            kind = value; W.Event("WEATHER_CHANGED")
            local path = style == 1 and native[value]
                or "Interface\\AddOns\\MSUF_Suite\\Media\\Weather\\" .. names[value] .. ".tga"
            check(entry.label.text == "" and not entry.label.shown and entry.icon.shown
                and entry.icon.texture == path and entry.icon.width == 48 and entry.icon.height == 48,
                "icon-only weather must use a native texture with no text")
            W.Fire(entry.button, "OnEnter")
            check(W.G.GameTooltip.lines[2] == names[value], "icon-only weather lost its tooltip name")
        end
    end
    check(entry.button.width == 48 and entry.button.height == 56 and entry.box.height == 52,
        "large weather icon was clipped by text-sized geometry")
    W.Step()
    check(W.MM.catcher.points[2][5] == -(56 - W.config.infoWeatherY + W.MM.BorderWidth()),
        "mouseover area did not cover the full weather icon below the map")
    check(not W.calls.weatherIcon, "weather artwork must not depend on unavailable pet battle records")
    -- With the weather unchanged, changing only the style must update the
    -- native texture even though the icon-only label stays empty.
    assert(S.Set("minimap", "infoWeatherIconStyle", 1))
    check(entry.icon.texture == native[3], "Blizzard style reused Forever artwork without pet battle data")
    assert(S.Set("minimap", "infoWeatherIconStyle", 2))
    check(entry.icon.texture == "Interface\\AddOns\\MSUF_Suite\\Media\\Weather\\Sandstorm.tga",
        "Forever style did not replace the native icon immediately")
    kind = 4; W.Event("WEATHER_CHANGED")
    check(entry.icon.texture:find("INV_Misc_QuestionMark", 1, true) and entry.tooltipText == "Other weather",
        "miscellaneous weather must retain a distinct fallback")
    for _, value in ipairs({ 99, "Rain", false, W.secret, math.huge }) do
        kind = value; W.Event("WEATHER_CHANGED")
        check(entry.label.text == "--" and entry.label.shown and not entry.icon.shown and entry.tooltipText == "--",
            "invalid weather reused a stale icon or tooltip")
    end
    kind = nil; W.Event("WEATHER_CHANGED")
    check(entry.label.text == "--", "missing weather must stay unknown")
    kind = 1; W.Event("WEATHER_CHANGED")
    local writes, iconReads = entry.label.textWrites, reads
    W.Event("WEATHER_CHANGED")
    check(entry.label.textWrites == writes and reads == iconReads + 1, "unchanged icon rewrote the font string")
    W.Advance(30)
    check(reads == iconReads + 1 and W.Pending() == 0, "weather icons introduced polling")
    assert(S.Set("minimap", "visibility", 5))
    local hiddenIconReads = reads
    kind = 2; W.Event("WEATHER_CHANGED")
    check(reads == hiddenIconReads, "hidden icon still queried the weather API")
    assert(S.Set("minimap", "visibility", 1))
    check(entry.icon.texture:find("Snow.tga", 1, true) and entry.icon.shown and entry.tooltipText == "Snow",
        "shown icon did not pick up the weather change")
    assert(S.Set("minimap", "infoWeatherDisplay", 3))
    check(entry.label.text == "Snow" and entry.label.shown and entry.icon.shown,
        "icon and text did not return after an icon-only switch")
    for _, anchor in ipairs({ 1, 2, 3 }) do
        assert(S.Set("minimap", "infoWeatherAnchor", anchor))
        local x = entry.icon.points[1][4]
        local expected = anchor == 1 and 0 or anchor == 3 and entry.button.width - entry.contentWidth
            or (entry.button.width - entry.contentWidth) / 2
        check(x == expected and entry.label.points[1][4] == x + 48 + 4,
            "native weather icon and text do not share the selected alignment")
    end
    for rendering = 1, 3 do
        assert(S.SetMany("minimap", { infoWeatherDisplay = 2, infoWeatherIconSize = 64, infoWeatherRendering = rendering }))
        check(entry.icon.width == 64 and entry.icon.shown and not entry.label.shown and entry.contentWidth == 64,
            "icon-only layout must be independent of Smooth, Sharp and Slug text rendering")
    end
    assert(S.Set("minimap", "infoWeatherDisplay", 1))
    check(entry.label.text == "Snow" and entry.label.shown and not entry.icon.shown
        and entry.button.height == 20 and entry.box.height == 16,
        "text-only mode did not restore the original text geometry")
    assert(S.Set("minimap", "infoWeather", false))
    check(not W.M.context.frame.events.WEATHER_CHANGED, "weather event remained after disabling")
    local retail = H.New(root, "Mainline")
    check(retail.config.infoWeather == false and retail.config.infoWeatherIconStyle == 1
        and not retail.S.CanShowMinimapInfo("Weather"),
        "non-Forever weather should stay off without the API")
    print("Minimap Forever weather: default, event updates, visibility and API gate passed")
end

-- Sampled texts share one timer, hidden texts do no work, coordinates park
-- without a position, and event-only texts never poll.
do
    local reads = { clock = 0, fps = 0, latency = 0, coordinates = 0, durability = 0, zone = 0 }
    local fps, home, world, mapID, x, y, inside = 80, 30, 50, 1, .5234, .4801, false
    local W = H.New(root, "Mainline", { beforeModules = function(W)
        local G = W.G
        G.GetServerTime = function() return 1700000000 + W.now end
        G.GetGameTime = function() reads.clock = reads.clock + 1; return 14, 3 end
        G.date = function(format)
            if format == "*t" then return { day = 26, month = 9, year = 2026, hour = 15, min = 3, sec = 20 } end
            return format:find("%%S") and "15:03:20" or "15:03"
        end
        -- A German client: the clock date is Blizzard's localized short date,
        -- and FPS and latency texts translate as format strings.
        G.FormatShortDate = function(day, month, year) return string.format("%02d.%02d.%d", day, month, year) end
        W.Suite.L["%d FPS"], W.Suite.L["%d ms"] = "%d BpS", "%d Ms"
        G.GetFramerate = function() reads.fps = reads.fps + 1; return fps end
        G.GetNetStats = function() reads.latency = reads.latency + 1; return 0, 0, home, world end
        G.C_Map = { GetBestMapForUnit = function() reads.map = (reads.map or 0) + 1; return mapID end, GetPlayerMapPosition = function()
            reads.coordinates = reads.coordinates + 1
            return { GetXY = function() return x, y end }
        end }
        G.IsInInstance = function() return inside end
    end })
    W.editModeReady = true
    local G, S = W.G, W.S
    local opened = 0
    G.ToggleWorldMap = function() opened = opened + 1 end
    H.Enable(W, { captured = true, infoLocation = false })
    W.Step()
    local M, MM, c = W.M, W.MM, W.config
    local frame = M.infoFrame
    check(frame and frame:GetParent() == MM.host and frame.level > W.map.level
        and not frame.mouse and MM.overlay == nil, "text layer leaves native map clicks free")
    local clock = M.infoEntries.Clock
    check(clock.label.text == "14:03" and W.Pending() == 1 and W.Pending(40) == 1, "clock scheduling")
    assert(S.Set("minimap", "infoClockDate", true))
    check(clock.label.text == "14:03  26.09.2026", "optional date on minimap clock")
    assert(S.Set("minimap", "infoClockDatePosition", 2))
    check(clock.label.text == "26.09.2026\n14:03" and clock.button.height == 32,
        "date above time must reserve two text lines")
    assert(S.Set("minimap", "infoClockDatePosition", 3))
    check(clock.label.text == "14:03\n26.09.2026", "date below time")
    assert(S.Set("minimap", "infoClockDate", false))
    check(clock.button.points[1][1] == "TOP" and clock.label.justify == "CENTER", "clock anchor")
    check(clock.label.font[1] == W.Suite.MSUFMedia.font and clock.label.font[2] == 12
        and clock.label.font[3] == "OUTLINE,SLUG", "MSUF Slug font")
    assert(S.SetMany("minimap", { infoClockOutline = 3, infoClockRendering = 2,
        infoClockShadow = true, infoClockShadowOpacity = 80, infoClockShadowDistance = 2 }))
    check(clock.label.font[3] == "THICKOUTLINE,MONOCHROME"
        and clock.label.shadowColor[4] == 0.8 and clock.label.shadowOffset[1] == 2,
        "clock text effects")
    assert(S.Set("minimap", "infoClockRendering", 3))
    check(clock.label.font[3] == "OUTLINE,SLUG" and clock.label.shadowColor[4] == 0,
        "Slug clock shadow")
    assert(S.SetMany("minimap", { infoFPS = true, infoLatency = true, infoCoordinates = true, infoStatusColors = true }))
    local entries = M.infoEntries
    check(entries.FPS.label.text == "80 BpS" and entries.Latency.label.text == "50 Ms", "fps/latency")
    check(entries.Coordinates.label.text == "52.3, 48.0" and W.Pending() == 1, "coordinates and one shared timer")
    check(entries.FPS.label.justify == "LEFT" and entries.Latency.label.justify == "RIGHT", "corner justification")
    local clockReads, fpsReads, latencyReads = reads.clock, reads.fps, reads.latency
    W.Advance(.5)
    check(reads.clock == clockReads and reads.fps == fpsReads and reads.latency == latencyReads, "independent intervals")
    local writes = entries.Coordinates.label.textWrites
    fps = 20
    W.Advance(.5)
    check(entries.FPS.label.text == "20 BpS" and entries.FPS.label.textColor[1] == 1, "status colour")
    check(entries.Coordinates.label.textWrites == writes, "unchanged coordinates rewritten")
    -- Hidden: nothing samples; visible again: sampling resumes.
    assert(S.Set("minimap", "visibility", 5))
    check(W.Pending() == 0, "hidden texts kept a timer")
    local coordinateReads = reads.coordinates
    W.Advance(10)
    check(reads.coordinates == coordinateReads, "hidden texts sampled")
    assert(S.Set("minimap", "visibility", 1))
    check(W.Pending() == 1 and reads.coordinates > coordinateReads, "texts did not resume")
    -- Coordinates park without a position and resume on the next zone change.
    mapID = nil
    W.Advance(1)
    check(entries.Coordinates.label.text == "--", "missing position")
    local mapReads = reads.map
    coordinateReads = reads.coordinates
    W.Advance(5)
    check(reads.coordinates == coordinateReads and reads.map == mapReads, "coordinates kept polling without a position")
    mapID = 1
    W.Event("ZONE_CHANGED_NEW_AREA")
    check(entries.Coordinates.label.text == "52.3, 48.0" and reads.coordinates == coordinateReads + 1, "zone change did not re-arm")
    x = W.secret
    W.Advance(1)
    check(entries.Coordinates.label.text == "--", "secret position")
    fps = W.secret
    W.Advance(1)
    check(entries.FPS.label.text == "--", "secret framerate")
    fps, x, y = 60, .5, .5
    -- Mouseover coordinates sample only while the map is hovered.
    assert(S.Set("minimap", "infoCoordinatesMode", 1))
    check(not entries.Coordinates.button.shown and MM.catcher.shown, "mouseover coordinates start hidden")
    coordinateReads = reads.coordinates
    W.Advance(3)
    check(reads.coordinates == coordinateReads, "hidden coordinates sampled")
    W.Fire(MM.catcher, "OnEnter")
    check(entries.Coordinates.button.shown and reads.coordinates == coordinateReads + 1, "hover did not sample coordinates")
    W.Fire(MM.catcher, "OnLeave"); W.Advance(.2)
    check(not entries.Coordinates.button.shown, "coordinates stayed after leave")
    assert(S.Set("minimap", "infoCoordinatesMode", 2))
    -- Formats and anchors: above/below the map sit outside the border.
    assert(S.SetMany("minimap", { infoClockSource = 3, infoClockSeconds = true, infoCoordinatesDecimals = 2, infoLatencySource = 3 }))
    check(clock.label.text:find(" / 15:03:20", 1, true) and entries.Latency.label.text == "30 / 50 Ms", "clock/latency formats")
    check(entries.Coordinates.label.text == "50.00, 50.00", "coordinate decimals")
    assert(S.SetMany("minimap", { infoClockAnchor = 10, infoClockY = 3, infoFPSAnchor = 11, borderSize = 2 }))
    local point = clock.button.points[1]
    check(point[1] == "BOTTOM" and point[2] == MM.host and point[3] == "TOP" and point[5] == 5 and clock.label.justify == "CENTER", "above anchor")
    point = entries.FPS.button.points[1]
    check(point[1] == "TOP" and point[3] == "BOTTOM" and point[5] == 2, "below anchor")
    W.Step()
    -- Above: offset 3 + height 20 + border 2; below: height 20 - offset 4 + border 2.
    check(MM.catcher.points[1][5] == 25 and MM.catcher.points[2][5] == -18, "catcher covers texts outside the map")
    -- Box behind the text, in the border colour.
    assert(S.SetMany("minimap", { infoClockBox = 2, borderColor = "336699" }))
    local box = clock.box
    check(box and box.shown and box.layer == "BACKGROUND" and math.abs(box.color[1] - 0x33 / 255) < 1e-6, "text box colour")
    check(box.width == #clock.label.text * 6 + 8 and box.points[1][1] == "CENTER", "text box follows the text")
    assert(S.SetMany("minimap", { infoClockBox = 3, infoClockBoxColor = "123456" }))
    check(box.shown and math.abs(box.color[1] - 0x12 / 255) < 1e-6
        and math.abs(box.color[2] - 0x34 / 255) < 1e-6 and math.abs(box.color[3] - 0x56 / 255) < 1e-6,
        "custom text background did not reach the live box")
    assert(S.Set("minimap", "borderColor", "ff0000"))
    check(math.abs(box.color[1] - 0x12 / 255) < 1e-6, "border color overwrote the custom text background")
    assert(S.Set("minimap", "infoClockBox", 2))
    check(box.color[1] == 1 and box.color[2] == 0, "legacy border-color box did not remain selectable")
    assert(S.Set("minimap", "infoClockBox", 1))
    check(not box.shown, "box not removed")
    -- Clicks never run in combat; the location click is optional.
    G.ToggleCharacter = function() end
    W.SetCombat(true); entries.Coordinates.button:Click(); W.SetCombat(false)
    check(opened == 0, "click in combat")
    entries.Coordinates.button:Click()
    check(opened == 1, "coordinates click")
    -- Hide in instances: entering one removes the coordinates text until leaving.
    assert(S.Set("minimap", "infoCoordinatesHideInstance", true))
    inside = true
    W.Event("PLAYER_ENTERING_WORLD")
    check(not entries.Coordinates.button.shown and not entries.Coordinates.active, "instance coordinates")
    inside = false
    W.Event("PLAYER_ENTERING_WORLD")
    check(entries.Coordinates.button.shown, "coordinates did not return")
    assert(S.Set("minimap", "enabled", false))
    check(W.Pending() == 0 and not frame.shown and not frame.scripts.OnUpdate, "disable left sampling work")
    print("Minimap information: shared scheduling, intervals, visibility, parking, mouseover, anchors, boxes, clicks and disable passed")
end

-- Event-only texts (durability, location), difficulty text and the invite mark.
do
    local durabilityReads, zoneReads, current, zone, subzone, pvp = 0, 0, 10, "Stormwind", "Trade District", "friendly"
    local instance = { "Test", "none", 0, "", 0, 0, false, 0, 0 }
    local keystone, invites = 12, 0
    local W = H.New(root, "Mainline", { beforeModules = function(W)
        local G = W.G
        -- Next-frame deferrals run immediately; the texts here never poll.
        W.timerAPI = G.C_Timer
        G.C_Timer = { After = function(_, callback) callback() end, NewTimer = W.timerAPI.NewTimer }
        G.GetInventoryItemDurability = function(slot)
            durabilityReads = durabilityReads + 1
            if slot == 1 then return current, 100 elseif slot == 5 then return 200, 200 end
        end
        G.GetZoneText = function() zoneReads = zoneReads + 1; return zone end
        G.GetSubZoneText = function() return subzone end
        G.C_PvP = { GetZonePVPInfo = function() return pvp end }
        G.GetInstanceInfo = function() return unpack(instance) end
        -- Every ID reports heroic flags: mapped IDs must not fall through to them.
        G.GetDifficultyInfo = function() return "Odd", "party", true, false, false, false end
        G.C_ChallengeMode = { GetActiveKeystoneInfo = function() return keystone end }
        G.C_Calendar = { GetNumPendingInvites = function() return invites end }
    end })
    W.editModeReady = true
    local G, S = W.G, W.S
    H.Enable(W, { captured = true, infoClock = false, infoDurability = true })
    local M, MM = W.M, W.MM
    -- Retail has every text's API except Forever's weather.
    check(S.CanShowMinimapInfo("Durability") and S.CanShowMinimapInfo("Location") and S.CanShowMinimapInfo("FPS")
        and not S.CanShowMinimapInfo("Weather"), "Retail text capabilities")
    check(W.Pending() == 0, "event-only texts started a timer")
    local durability, location = M.infoEntries.Durability, M.infoEntries.Location
    check(durability.text:find("10%", 1, true) and durability.text:find("|TInterface", 1, true) and durabilityReads == 19, "durability")
    check(location.text == "Stormwind" and location.label.textColor[1] == 1, "location")
    local count = durabilityReads
    W.now = W.now + 30
    check(durabilityReads == count, "durability polled")
    current = 40
    W.SetCombat(true)
    W.Event("UPDATE_INVENTORY_DURABILITY")
    check(durability.text:find("40%", 1, true) and durabilityReads == count + 19, "combat durability update")
    assert(not S.Set("minimap", "infoLocationSubzone", true))
    W.SetCombat(false)
    assert(S.Set("minimap", "infoLocationSubzone", true))
    check(location.text == "Stormwind - Trade District", "subzone")
    subzone = "Old Town"
    W.Event("ZONE_CHANGED")
    check(location.text == "Stormwind - Old Town", "zone event")
    assert(S.Set("minimap", "visibility", 5))
    count = durabilityReads
    current, subzone = 60, "Cathedral Square"
    W.Event("PLAYER_EQUIPMENT_CHANGED"); W.Event("ZONE_CHANGED_INDOORS")
    check(durabilityReads == count and location.text == "Stormwind - Old Town", "hidden texts updated")
    assert(S.Set("minimap", "visibility", 1))
    check(durabilityReads == count + 19 and location.text == "Stormwind - Cathedral Square", "stale texts not refreshed on show")
    assert(S.SetMany("minimap", { infoDurabilityMode = 2, infoDurabilityIcon = false, infoLocationBelow = true }))
    check(durability.text == "86%" and location.text == "Stormwind\nCathedral Square" and location.button.height == 32, "modes")
    assert(S.Set("minimap", "infoLocationClassColor", true))
    check(location.label.textColor[1] == .2, "class colour")
    -- Location click opens the world map only when allowed.
    local opened = 0
    G.ToggleWorldMap = function() opened = opened + 1 end
    location.button:Click()
    check(opened == 1, "location click")
    assert(S.Set("minimap", "infoLocationClick", false))
    location.button:Click()
    check(opened == 1, "location click must be optional")
    zone, subzone, pvp, current = W.secret, W.secret, W.secret, W.secret
    W.Event("PLAYER_ENTERING_WORLD")
    check(location.text == "--" and durability.text == "--", "secret zone/durability")
    zone, subzone, pvp, current = "Elwynn", "Goldshire", "contested", 100
    -- Difficulty as text: size + tag, coloured by tier; events only while enabled.
    check(not M.context.frame.events.PLAYER_DIFFICULTY_CHANGED, "difficulty events registered while off")
    assert(S.Set("minimap", "infoDifficulty", true))
    local label = M.difficultyLabel
    check(M.context.frame.events.PLAYER_DIFFICULTY_CHANGED and M.context.frame.events.CHALLENGE_MODE_START, "difficulty events")
    check(label.shown and label.text == "" and label.points[1][1] == "TOPLEFT" and label.points[1][4] == 4, "outside instances")
    instance = { "Raid", "raid", 16, "Mythic", 20, 0, false, 0, 20 }
    W.Event("PLAYER_DIFFICULTY_CHANGED")
    check(label.text == "20M" and math.abs(label.textColor[1] - 0xb3 / 255) < 1e-6, "mythic raid")
    instance = { "Raid", "raid", 14, "Normal", 30, 0, true, 0, 17 }
    W.Event("GROUP_ROSTER_UPDATE")
    check(label.text == "17N", "flexible raid uses the group size")
    instance = { "Dungeon", "party", 8, "Mythic Keystone", 5, 0, false, 0, 5 }
    W.Event("CHALLENGE_MODE_START")
    check(label.text == "M+12", "keystone level")
    instance = { "Dungeon", "party", 205, "Follower", 5, 0, false, 0, 5 }
    W.Event("ZONE_CHANGED_NEW_AREA")
    check(label.text == "F", "follower")
    instance = { "Molten Core", "raid", 242, "Normal", 20, 0, false, 0, 12 }
    W.Event("PLAYER_DIFFICULTY_CHANGED")
    check(label.text == "20N", "WoW Forever classic raid difficulty")
    instance = { "Odd", "party", 999, "Odd", 5, 0, false, 0, 5 }
    W.Event("PLAYER_DIFFICULTY_CHANGED")
    check(label.text == "5H", "unknown difficulty falls back to its flags")
    assert(S.Set("minimap", "infoDifficultyColors", false))
    check(label.textColor[1] == 1 and label.textColor[2] == 1, "plain colour")
    assert(S.Set("minimap", "infoDifficulty", false))
    check(not label.shown and not M.context.frame.events.PLAYER_DIFFICULTY_CHANGED, "difficulty off")
    -- Calendar invites mark the clock while Blizzard's calendar button is hidden.
    W.G.C_Timer = W.timerAPI
    W.G.GetGameTime = function() return 9, 5 end
    assert(S.SetMany("minimap", { infoClock = true, showCalendar = false }))
    local clock = M.infoEntries.Clock
    check(clock.invite and not clock.invite.shown, "invite mark created")
    invites = 2
    W.Event("CALENDAR_UPDATE_PENDING_INVITES")
    check(clock.invite.shown, "invite mark not shown")
    assert(S.Set("minimap", "showCalendar", true))
    check(not clock.invite.shown and not M.context.frame.events.CALENDAR_UPDATE_PENDING_INVITES, "invite mark with calendar button")
    assert(S.SetMany("minimap", { infoDurability = false, infoLocation = false, infoClock = false }))
    check(not M.context.frame.events.UPDATE_INVENTORY_DURABILITY and not M.context.frame.events.ZONE_CHANGED, "events retained")
    check(not M.context.frame.events.PLAYER_ENTERING_WORLD or M.context.callbacks.PLAYER_ENTERING_WORLD, "world event bookkeeping")
    check(not M.infoFrame.shown, "texts frame shown without texts")
    print("Minimap event texts: durability, location, click option, difficulty tags, invite mark and no polling passed")
end

-- Hover details subscribe and query only during an owned hover.
do
    local lockReads, requests, vaultReads = 0, 0, 0
    local activities = { { type = 1, index = 1, progress = 2, threshold = 2, level = 14, id = 100 },
        { type = 2, index = 1, progress = 1, threshold = 4, level = 0, id = 101 },
        { type = 4, index = 1, progress = 4, threshold = 4, level = 8, id = 102 },
        { type = 5, index = 1, progress = 1, threshold = 1, level = 1, id = 103 } }
    local itemLevel, vaultAvailable = 610, true
    local W = H.New(root, "Mainline", { beforeModules = function(W)
        local G = W.G
        G.GetGameTime = function() return 14, 3 end
        G.GetServerTime = function() return 1700000000 end
        G.GetNumSavedInstances = function() lockReads = lockReads + 1; return 2 end
        G.GetSavedInstanceInfo = function(index)
            if index == 1 then return "Test raid", 42, 3600, 14, true, false, 0, true, 20, "Normal", 6, 2 end
            return "Test dungeon", 43, 0, 1, false, false, 0, false, 5, "Normal", 4, 4
        end
        G.GetNumSavedWorldBosses = function() return 1 end
        G.GetSavedWorldBossInfo = function() return "World boss", 1, 7200 end
        G.RequestRaidInfo = function() requests = requests + 1 end
        G.Enum = { WeeklyRewardChestThresholdType = { Raid = 1, Activities = 2, RankedPvP = 3, World = 4, Concession = 5 } }
        G.C_AddOns = { IsAddOnLoaded = function() return false end, LoadAddOn = function() end,
            GetAddOnEnableState = function() return 2 end,
            DoesAddOnExist = function(name)
                return name == "MSUF_Suite_Minimap" or (name == "Blizzard_WeeklyRewards" and vaultAvailable)
            end }
        G.C_WeeklyRewards = { GetActivities = function() vaultReads = vaultReads + 1; return activities end,
            HasAvailableRewards = function() return true end, GetExampleRewardItemHyperlinks = function() return "item:1" end }
        G.C_Item = { GetDetailedItemLevelInfo = function() return itemLevel end }
        G.GetDifficultyInfo = function() return "Normal" end
        -- Lines with a name or number translate as whole format strings.
        W.Suite.L["%s (World boss)"], W.Suite.L["Tier %d"] = "%s (Weltboss)", "Stufe %d"
        W.Suite.L["%s / Item level %s"] = "%s / Gegenstandsstufe %s"
    end, float32Scale = true })
    W.editModeReady = true
    local G, S = W.G, W.S
    H.Enable(W, { captured = true, infoLocation = false, infoClockTooltip = 2 })
    W.Step()
    local M, tip = W.M, G.GameTooltip
    local button = M.infoEntries.Clock.button
    local events = M.context.frame.events
    local function Enter() W.Fire(button, "OnEnter") end
    local function Leave() W.Fire(button, "OnLeave") end
    check(lockReads == 0 and vaultReads == 0 and not events.UPDATE_INSTANCE_INFO, "idle tooltip work")
    Enter()
    check(requests == 1 and lockReads == 1 and #tip.lines == 3, "lockouts")
    check(tip.lines[3]:find("World boss (Weltboss) | ", 1, true) == 1, "world boss line: " .. tostring(tip.lines[3]))
    check(tip.lines[2]:find("2/6", 1, true) and tip.lines[2]:find("60 minutes", 1, true), "lockout row")
    check(events.UPDATE_INSTANCE_INFO, "lockout event")
    W.Event("UPDATE_INSTANCE_INFO")
    check(lockReads == 2 and requests == 1, "lockout refresh")
    Leave()
    check(not tip.shown and not events.UPDATE_INSTANCE_INFO, "leave released the event")
    W.Event("UPDATE_INSTANCE_INFO")
    check(lockReads == 2, "released event still drew")
    Enter(); Leave()
    check(requests == 1, "raid info requested on every hover")
    W.Advance(31); Enter(); Leave()
    check(requests == 2, "raid info never refreshed")
    assert(S.SetMany("minimap", { tooltipExpired = true, tooltipWorldBosses = false }))
    Enter()
    check(#tip.lines == 3 and tip.lines[3]:find("Expired", 1, true), "expired lockouts")
    Leave()
    assert(S.Set("minimap", "tooltipInstanceKind", 2)); Enter()
    check(#tip.lines == 2, "raid filter"); Leave()
    assert(S.Set("minimap", "infoClockTooltip", 3)); Enter()
    check(vaultReads == 1 and #tip.lines == 5 and tip.lines[3]:find("Gegenstandsstufe 610", 1, true)
        and tip.lines[5]:find("World activities 1 - Stufe 8", 1, true) == 1, "vault: " .. table.concat(tip.lines, " | "))
    check(events.WEEKLY_REWARDS_UPDATE and not events.GET_ITEM_INFO_RECEIVED, "vault events")
    itemLevel = nil
    W.Event("WEEKLY_REWARDS_UPDATE")
    check(events.GET_ITEM_INFO_RECEIVED, "item info wait")
    itemLevel = 620
    W.SetCombat(true); W.Event("GET_ITEM_INFO_RECEIVED"); W.SetCombat(false)
    check(tip.lines[3]:find("620", 1, true) and not events.GET_ITEM_INFO_RECEIVED, "item info update")
    Leave()
    check(not events.WEEKLY_REWARDS_UPDATE, "vault event leaked")
    vaultAvailable = false; Enter()
    check(tip.lines[2] == "Unavailable on this client.", "vault unavailable"); Leave()
    -- The options page offers the vault only where Blizzard's weekly rewards exist.
    check(S.CanShowMinimapTooltip(3) == false and S.CanShowMinimapTooltip(2) == true
        and S.CanShowMinimapTooltip(1) == true, "tooltip choices offered without their data")
    vaultAvailable = true
    check(S.CanShowMinimapTooltip(3) == true, "vault tooltip choice hidden although the data exists")
    -- The detail tooltip helpers are minimap internals, not Suite exports.
    check(S.ShowMinimapInfoTooltip == nil and S.HideMinimapInfoTooltip == nil and S.IsMinimapInfoVisible == nil
        and S.UpdateMinimapInfoVisibility == nil and W.MM.ShowInfoTooltip and W.MM.HideInfoTooltip
        and W.MM.InfoVisible and W.MM.UpdateInfoVisibility, "minimap tooltip internals leak into the Suite API")
    assert(S.Set("minimap", "infoClockTooltip", 4)); tip:Hide(); Enter()
    check(not tip.shown, "no tooltip")
    assert(S.Set("minimap", "infoClockTooltip", 1)); Enter()
    check(tip.shown and tip.lines[1] == "Clock", "plain tooltip"); Leave()
    -- The client reads a scale back as a 32-bit float (float32Scale above).
    assert(S.SetMany("minimap", { infoClockTooltip = 2, tooltipScale = 115 }))
    tip:SetScale(1); Enter()
    check(H.Near(tip:GetScale(), 1.15), "minimap tooltip did not scale")
    Leave()
    check(H.Near(tip:GetScale(), 1), "a 115% minimap tooltip scale stayed on GameTooltip after leave")
    assert(S.SetMany("minimap", { infoClockTooltip = 2, tooltipScale = 150 }))
    tip:SetScale(.8); Enter()
    check(math.abs(tip:GetScale() - 1.2) < .0001, "minimap tooltip did not scale from its previous scale")
    W.MM.ScaleTooltip(button)
    check(math.abs(tip:GetScale() - 1.2) < .0001, "repeated tooltip scaling compounded")
    Leave()
    check(H.Near(tip:GetScale(), .8), "tooltip scale did not restore on leave")
    Enter(); tip:SetOwner(G.UIParent)
    check(H.Near(tip:GetScale(), .8), "another tooltip owner inherited minimap scale")
    Leave(); Enter(); tip:SetScale(.9); Leave()
    check(H.Near(tip:GetScale(), .9), "minimap overwrote another owner's changed tooltip scale")
    Enter()
    assert(S.Set("minimap", "enabled", false))
    check(H.Near(tip:GetScale(), .9), "disable did not restore tooltip scale")
    check(not tip.shown and not next(events), "disable kept tooltip work")
    print("Minimap tooltips: lockouts, throttled raid info, weekly rewards, owned-hover events and disable passed")
end

-- Coordinates, Location and Durability open their windows from secure code:
-- while hovered out of combat they borrow a secure overlay in UIParent that
-- clicks Blizzard's own opener button; the combat start releases it.
do
    local opened, clicks = {}, {}
    local W = H.New(root, "Mainline", { clientSecurity = true, beforeModules = function(W)
        local G = W.G
        G.GetInventoryItemDurability = function(slot) if slot == 1 then return 50, 100 end end
        G.GetZoneText = function() return "Stormwind" end
        G.C_Map = { GetBestMapForUnit = function() return 1 end,
            GetPlayerMapPosition = function() return { GetXY = function() return .5, .5 end } end }
        local character = W.New("Button", "CharacterMicroButton", W.UIParent)
        for _, native in ipairs({ character, W.cluster.ZoneTextButton }) do
            native.scripts.OnClick = function(self) clicks[#clicks + 1] = { button = self, secure = W.secure } end
        end
        for _, name in ipairs({ "ToggleCharacter", "ToggleWorldMap" }) do
            G[name] = function() opened[#opened + 1] = { name = name, secure = W.secure } end
        end
    end })
    W.editModeReady = true
    local G, S = W.G, W.S
    H.Enable(W, { captured = true, infoClock = false, infoDurability = true, infoLocation = true,
        infoCoordinates = true })
    W.Step()
    local M, MM, tip = W.M, W.MM, G.GameTooltip
    local entries = M.infoEntries
    local function Hover(entry)
        entry.button.mouseOver = true
        W.Fire(entry.button, "OnEnter")
    end
    for _, case in ipairs({ { "Durability", G.CharacterMicroButton }, { "Coordinates", W.cluster.ZoneTextButton },
        { "Location", W.cluster.ZoneTextButton } }) do
        local entry, native = entries[case[1]], case[2]
        Hover(entry)
        local overlay = MM.infoOverlay
        check(overlay and overlay.protected and overlay.parent == W.UIParent and overlay.shown
            and overlay.points[1][2] == entry.button and overlay:GetAttribute("type") == "click"
            and overlay:GetAttribute("clickbutton") == native, case[1] .. " text lacks the secure window click")
        check(not entry.button:IsProtected(), case[1] .. " text became protected")
        -- The pointer moves onto the overlay: the text keeps its tooltip.
        overlay.mouseOver = true
        W.Fire(entry.button, "OnLeave")
        check(overlay.shown and tip.shown and tip.owner == entry.button, case[1] .. " lost its tooltip to the overlay")
        for _, mouse in ipairs({ "LeftButton", "RightButton" }) do
            local count = #clicks
            W.Click(overlay, mouse)
            check(#clicks == count + 1 and clicks[#clicks].button == native and clicks[#clicks].secure,
                case[1] .. " " .. mouse .. " did not click Blizzard's opener securely")
        end
        overlay.mouseOver, entry.button.mouseOver = false, false
        W.Fire(overlay, "OnLeave")
        check(not overlay.shown and #overlay.points == 0 and not tip.shown, case[1] .. " overlay or tooltip stayed")
    end
    check(#opened == 0, "an information text opened its window from the addon's code")
    local overlay = MM.infoOverlay
    -- The combat start releases the overlay before the lockdown; none in combat.
    Hover(entries.Durability)
    W.SetCombat(true)
    check(not overlay.shown and #overlay.points == 0 and overlay.owner == nil, "the overlay stayed over a text in combat")
    W.Fire(entries.Durability.button, "OnLeave")
    Hover(entries.Durability)
    W.Click(entries.Durability.button)
    check(not overlay.shown and #opened == 0, "a text attached the overlay or opened a window in combat")
    W.SetCombat(false)
    W.Fire(entries.Durability.button, "OnLeave")
    -- Location without its click option offers no overlay.
    assert(S.Set("minimap", "infoLocationClick", false))
    Hover(entries.Location)
    check(not overlay.shown, "Location offered a window click with its click option off")
    W.Fire(entries.Location.button, "OnLeave")
    -- Without a visible Blizzard button the text opens the window itself.
    W.cluster.ZoneTextButton.shown = false
    Hover(entries.Coordinates)
    check(not overlay.shown, "the overlay offered a click on a hidden Blizzard button")
    W.Click(entries.Coordinates.button)
    check(opened[#opened] and opened[#opened].name == "ToggleWorldMap", "Coordinates did not fall back to the world map")
    W.Fire(entries.Coordinates.button, "OnLeave")
    W.cluster.ZoneTextButton.shown = true
    Hover(entries.Coordinates)
    check(overlay.shown, "the overlay did not return with the Blizzard button")
    assert(S.Set("minimap", "enabled", false))
    check(not overlay.shown and #overlay.points == 0 and overlay.owner == nil, "disable kept the secure overlay")
    print("Minimap information: secure window clicks, tooltips, combat release, fallback and disable passed")
end

-- 12-hour clocks carry Blizzard's localized AM/PM word (TIMEMANAGER_AM/PM),
-- before the digits where Blizzard's own 12-hour format puts it first.
for _, case in ipairs({
    { words = { "AM", "PM", "%d:%02d AM" }, server = "02:03 PM", localTime = "09:03 AM" },
    { words = { "\236\152\164\236\160\132", "\236\152\164\237\155\132", "\236\152\164\236\160\132 %d:%02d" },
        server = "\236\152\164\237\155\132 02:03", localTime = "\236\152\164\236\160\132 09:03" },
}) do
    local W = H.New(root, "Mainline", { beforeModules = function(W)
        local G = W.G
        G.GetGameTime = function() return 14, 3 end
        G.TIMEMANAGER_AM, G.TIMEMANAGER_PM, G.TIME_TWELVEHOURAM = case.words[1], case.words[2], case.words[3]
        G.date = function(format)
            if format == "*t" then return { day = 26, month = 9, year = 2026, hour = 9, min = 3, sec = 20 } end
            assert(not format:find("%p", 1, true), "the local clock asked the C library for its AM/PM word")
            return "09:03"
        end
    end })
    W.editModeReady = true
    H.Enable(W, { captured = true, infoLocation = false, infoClock24Hour = false })
    W.Step()
    local clock = W.M.infoEntries.Clock
    check(clock.label.text == case.server, "12-hour realm clock: " .. tostring(clock.label.text))
    assert(W.S.Set("minimap", "infoClockSource", 2))
    check(clock.label.text == case.localTime, "12-hour local clock: " .. tostring(clock.label.text))
end
print("Minimap information: localized 12-hour clock words and their order passed")

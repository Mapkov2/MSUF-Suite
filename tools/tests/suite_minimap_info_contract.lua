local root = assert(arg[1], "repository root required")
local H = dofile(root .. "/tools/tests/suite_minimap_harness.lua")
local function check(value, message) if not value then error(message, 2) end end

-- Sampled texts share one timer, hidden texts do no work, coordinates park
-- without a position, and event-only texts never poll.
do
    local reads = { clock = 0, fps = 0, latency = 0, coordinates = 0, durability = 0, zone = 0 }
    local fps, home, world, mapID, x, y, inside = 80, 30, 50, 1, .5234, .4801, false
    local W = H.New(root, "Mainline", { beforeModules = function(W)
        local G = W.G
        G.GetServerTime = function() return 1700000000 + W.now end
        G.GetGameTime = function() reads.clock = reads.clock + 1; return 14, 3 end
        G.date = function(format) return format:find("%%S") and "15:03:20" or "15:03" end
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
    check(clock.button.points[1][1] == "TOP" and clock.label.justify == "CENTER", "clock anchor")
    check(clock.label.font[1] == "Fonts\\FRIZQT__.TTF" and clock.label.font[2] == 12 and clock.label.font[3] == "OUTLINE", "native font")
    assert(S.SetMany("minimap", { infoFPS = true, infoLatency = true, infoCoordinates = true, infoStatusColors = true }))
    local entries = M.infoEntries
    check(entries.FPS.label.text == "80 FPS" and entries.Latency.label.text == "50 ms", "fps/latency")
    check(entries.Coordinates.label.text == "52.3, 48.0" and W.Pending() == 1, "coordinates and one shared timer")
    check(entries.FPS.label.justify == "LEFT" and entries.Latency.label.justify == "RIGHT", "corner justification")
    local clockReads, fpsReads, latencyReads = reads.clock, reads.fps, reads.latency
    W.Advance(.5)
    check(reads.clock == clockReads and reads.fps == fpsReads and reads.latency == latencyReads, "independent intervals")
    local writes = entries.Coordinates.label.textWrites
    fps = 20
    W.Advance(.5)
    check(entries.FPS.label.text == "20 FPS" and entries.FPS.label.textColor[1] == 1, "status colour")
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
    check(clock.label.text:find(" / 15:03:20", 1, true) and entries.Latency.label.text == "30 / 50 ms", "clock/latency formats")
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
        -- A client without C_Timer.NewTimer: sampled texts are unavailable,
        -- next-frame deferrals run immediately.
        W.timerAPI = G.C_Timer
        G.C_Timer = { After = function(_, callback) callback() end }
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
    check(S.CanShowMinimapInfo("Durability") and S.CanShowMinimapInfo("Location") and not S.CanShowMinimapInfo("FPS"), "no-timer capabilities")
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
    print("Minimap event texts: durability, location, click option, difficulty tags, invite mark and no-timer clients passed")
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
        G.C_AddOns = { IsAddOnLoaded = function() return false end,
            DoesAddOnExist = function(name)
                return name == "MSUF_Suite_Minimap" or (name == "Blizzard_WeeklyRewards" and vaultAvailable)
            end }
        G.C_WeeklyRewards = { GetActivities = function() vaultReads = vaultReads + 1; return activities end,
            HasAvailableRewards = function() return true end, GetExampleRewardItemHyperlinks = function() return "item:1" end }
        G.C_Item = { GetDetailedItemLevelInfo = function() return itemLevel end }
        G.GetDifficultyInfo = function() return "Normal" end
    end })
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
    check(vaultReads == 1 and #tip.lines == 5 and tip.lines[3]:find("Item level 610", 1, true), "vault")
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
    check(tip.lines[2] == "Unavailable on this client.", "vault unavailable"); Leave(); vaultAvailable = true
    assert(S.Set("minimap", "infoClockTooltip", 4)); tip:Hide(); Enter()
    check(not tip.shown, "no tooltip")
    assert(S.Set("minimap", "infoClockTooltip", 1)); Enter()
    check(tip.shown and tip.lines[1] == "Clock", "plain tooltip"); Leave()
    assert(S.Set("minimap", "infoClockTooltip", 2)); Enter()
    assert(S.Set("minimap", "enabled", false))
    check(not tip.shown and not next(events), "disable kept tooltip work")
    print("Minimap tooltips: lockouts, throttled raid info, weekly rewards, owned-hover events and disable passed")
end

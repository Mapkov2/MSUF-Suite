local root = assert(arg[1], "repository root required")
local H = dofile(root .. "/tools/tests/suite_minimap_harness.lua")
local function check(value, message) if not value then error(message, 2) end end

-- Map visibility: pet battle and vehicle conditions join the state driver
-- ahead of the mode, a mouseover map asks them before it shows, instances
-- re-apply on zone changes, Edit Mode always shows the map.
do
    local W = H.New(root, "Mainline")
    local inside, kind, petBattle = false, "none", false
    W.G.IsInInstance = function() return inside, kind end
    W.G.SecureCmdOptionParse = function(value)
        if petBattle and value:find("[petbattle]", 1, true) then return "hide" end
        return "show"
    end
    H.Enable(W, { captured = true })
    W.Step()
    local S, MM = W.S, W.MM
    local host = MM.host
    check(host.stateDriver == nil and host.shown, "Always without conditions needs no driver")
    assert(S.Set("minimap", "hidePetBattle", true))
    check(host.stateDriver == "[petbattle] hide; show", "pet battle condition: " .. tostring(host.stateDriver))
    assert(S.Set("minimap", "hideVehicle", true))
    check(host.stateDriver == "[petbattle] hide; [@player,unithasvehicleui] hide; [vehicleui] hide; show",
        "vehicle condition")
    assert(S.Set("minimap", "visibility", 2))
    check(host.stateDriver == "[petbattle] hide; [@player,unithasvehicleui] hide; [vehicleui] hide; [combat] show; hide",
        "conditions before combat")
    S.SetEditMode(true)
    check(host.stateDriver == nil and host.shown, "Edit Mode must show the map without conditions")
    S.SetEditMode(false)
    assert(S.Set("minimap", "hideVehicle", false))
    -- A hidden mouseover map wakes only while no condition hides it.
    assert(S.Set("minimap", "visibility", 4))
    check(host.stateDriver == nil and not host.shown, "mouseover starts hidden")
    W.Fire(MM.catcher, "OnEnter")
    check(host.shown, "mouseover did not show the map")
    petBattle = true
    W.Event("PET_BATTLE_OPENING_START")
    check(not host.shown, "a pet battle did not hide the hovered map")
    petBattle = false
    W.Event("PET_BATTLE_CLOSE")
    check(host.shown, "the map did not return after the pet battle")
    assert(S.Set("minimap", "hidePetBattle", false))
    assert(S.Set("minimap", "visibility", 1))
    -- Instances: the zone change decides.
    assert(S.Set("minimap", "hideInstances", W.Suite.MinimapInstanceHide.RAIDS))
    inside, kind = true, "raid"
    W.Event("PLAYER_ENTERING_WORLD")
    check(not host.shown, "the map stayed in a raid")
    inside, kind = true, "party"
    W.Event("ZONE_CHANGED_NEW_AREA")
    check(host.shown, "a dungeon hid the map with the raid setting")
    assert(S.Set("minimap", "hideInstances", W.Suite.MinimapInstanceHide.BOTH))
    check(not host.shown, "the dungeon setting did not hide the map")
    inside, kind = false, "none"
    W.Event("ZONE_CHANGED_NEW_AREA")
    check(host.shown, "leaving the instance did not show the map")
    -- Zone changes during combat wait for its end.
    inside, kind = true, "party"
    W.SetCombat(true)
    W.Event("ZONE_CHANGED_NEW_AREA")
    check(host.shown, "the protected map changed in combat")
    W.SetCombat(false)
    W.Step()
    check(not host.shown, "the queued instance rule was not applied after combat")
    inside, kind = false, "none"
    assert(S.Set("minimap", "hideInstances", 1))
    check(host.shown, "Never did not restore the map")
    -- The key binding hides the map for the session, never in combat.
    W.SetCombat(true)
    check(not W.M:ToggleShown() and host.shown, "the shortcut acted in combat")
    W.SetCombat(false)
    check(W.M:ToggleShown() and not host.shown, "the shortcut did not hide the map")
    assert(S.Set("minimap", "visibility", 1))
    check(not host.shown, "a refresh forgot the session hide")
    check(W.M:ToggleShown() and host.shown, "the shortcut did not show the map again")
    print("Minimap visibility conditions (pet battle, vehicle, instances, Edit Mode, mouseover, key binding) passed")
end

-- The right click keeps Blizzard's ping until it gets an action.
do
    local W = H.New(root, "Mainline")
    local calendar, pings = 0, {}
    W.G.ToggleCalendar = function() calendar = calendar + 1 end
    W.map:SetScript("OnMouseUp", function(_, button) pings[button] = (pings[button] or 0) + 1 end)
    H.Enable(W, { captured = true })
    W.Step()
    local S, map = W.S, W.map
    local mouseUp = map:GetScript("OnMouseUp")
    mouseUp(map, "RightButton")
    check(pings.RightButton == 1 and calendar == 0, "the default right click must stay Blizzard's ping")
    assert(S.Set("minimap", "rightClick", 3))
    mouseUp(map, "RightButton")
    check(pings.RightButton == 1 and calendar == 1, "the right click did not open the calendar instead of pinging")
    W.SetCombat(true); mouseUp(map, "RightButton"); W.SetCombat(false)
    check(calendar == 1 and pings.RightButton == 1, "the right click acted in combat")
    mouseUp(map, "LeftButton")
    check(pings.LeftButton == 1, "the left click lost its ping")
    print("Minimap right-click action and Blizzard ping passed")
end

-- Information texts on mouseover: hidden until the pointer is over the map,
-- sampled again when they appear; the hover catcher runs for them.
do
    local W = H.New(root, "Mainline")
    -- Nothing else on mouseover: the text alone asks for the hover catcher.
    H.Enable(W, { captured = true, infoClock = true, infoClockReveal = 1, infoLocation = false, zoomButtons = 2,
        showLanding = 1 })
    W.Step()
    local MM = W.MM
    local clock = W.M.infoEntries.Clock
    check(clock.active and not clock.button.shown, "a mouseover clock showed without the pointer")
    check(MM.catcher.shown, "a mouseover text needs the hover catcher")
    W.Fire(MM.catcher, "OnEnter")
    check(clock.button.shown and clock.label.text ~= nil, "hovering did not show and fill the clock")
    W.Fire(MM.catcher, "OnLeave"); W.Advance(0.2)
    check(not clock.button.shown, "the clock stayed after the pointer left")
    assert(W.S.Set("minimap", "infoClockReveal", 2))
    check(clock.button.shown, "Always did not show the clock")
    check(not MM.catcher.shown, "the catcher stayed without a mouseover text")
    print("Minimap information texts on mouseover passed")
end

-- North marker: rides the map edge opposite the player's turn while the map
-- rotates; it stops following the heading while hidden.
do
    local W = H.New(root, "Mainline")
    local facing = 0
    W.G.GetPlayerFacing = function() return facing end
    H.Enable(W, { captured = true, rotate = 2, showNorth = true, size = 190, shape = 1 })
    W.Step()
    local MM = W.MM
    local north
    for _, child in ipairs(MM.host.children) do
        if child.label and child.label.text == "N" then north = child end
    end
    check(north and north.shown, "the north marker is missing while the map rotates")
    local function Point()
        local _, _, _, x, y = north:GetPoint(1)
        return x, y
    end
    local x, y = Point()
    check(H.Near(x, 0) and H.Near(y, 88), "facing north puts N at the top edge")
    facing = math.pi / 2 -- west
    W.Advance(0.06)
    x, y = Point()
    check(H.Near(x, 88) and H.Near(y, 0, 1e-4), "facing west puts N on the right edge")
    assert(W.S.Set("minimap", "rotate", 3))
    check(not north.shown, "north stays up: the marker must hide")
    print("Minimap north marker passed")
end

-- Drawer: opens on mouseover and closes after the pointer left; the timed
-- close; the key binding; hidden buttons wait in the park.
do
    local W = H.New(root, "Mainline")
    local map = W.map
    local function Icon(name)
        local button = W.Button(name, map, 31, 31)
        button.points = {}
        button:SetPoint("CENTER", map, "CENTER", 80, 10)
        return button
    end
    local alpha, beta, gamma = Icon("LibDBIcon10_Alpha"), Icon("LibDBIcon10_Beta"), Icon("LibDBIcon10_Gamma")
    H.Enable(W, { captured = true, drawerOpenOnHover = true })
    W.Step()
    local S, MM = W.S, W.MM
    local panel, toggle = MM.panel, nil
    for _, frame in ipairs(MM.host.children) do
        if frame.kind == "Button" and frame.minimapOffsetKey == "drawer" then toggle = frame end
    end
    check(toggle and toggle.shown and not panel.shown, "drawer toggle")
    W.Fire(toggle, "OnEnter")
    check(panel.shown, "hovering the drawer button did not open it")
    W.Fire(toggle, "OnLeave")
    panel.mouseOver = true
    W.Advance(0.5)
    check(panel.shown, "the drawer closed under the pointer")
    panel.mouseOver = false
    W.Advance(0.5)
    check(not panel.shown, "the drawer stayed after the pointer left")
    -- A timed close without mouseover opening.
    assert(S.Set("minimap", "drawerOpenOnHover", false))
    assert(S.Set("minimap", "drawerAutoClose", 3))
    W.Click(toggle)
    check(panel.shown, "a click did not open the drawer")
    W.Advance(2)
    check(panel.shown, "the drawer closed early")
    W.Advance(1.5)
    check(not panel.shown, "the drawer did not close after its seconds")
    assert(S.Set("minimap", "drawerAutoClose", 0))
    -- The key binding opens and closes it.
    check(W.M:ToggleDrawer() and panel.shown, "the drawer shortcut did not open the drawer")
    W.Advance(60)
    check(panel.shown, "0 seconds must keep the drawer open")
    check(W.M:ToggleDrawer() and not panel.shown, "the drawer shortcut did not close the drawer")
    -- Hidden buttons wait in the hidden park and come back.
    assert(S.Set("minimap", "drawerHide", "LibDBIcon10_Beta"))
    check(beta:GetParent() == MM.park and alpha:GetParent() == panel and gamma:GetParent() == panel,
        "a hidden button stayed in the drawer")
    assert(S.Set("minimap", "drawerHide", ""))
    check(beta:GetParent() == panel, "a button shown again did not return to the drawer")
    print("Minimap drawer mouseover opening, timed close, key binding and hidden buttons passed")
end

-- Group finder Automatic style follows the minimap look; the data bar preset
-- attaches below the map.
do
    local W = H.New(root, "Mainline")
    local Style, styles = W.Suite.MinimapStyle, W.Suite.MinimapGroupFinderStyle
    check(Style.GroupFinderStyle({ dungeonStyle = styles.DEFAULT }) == styles.DEFAULT, "explicit style changed")
    check(Style.GroupFinderStyle({ dungeonStyle = styles.AUTO, stylePreset = 9 }) == styles.MODERN_DARK,
        "Midnight Dark did not pick the dark button")
    check(Style.GroupFinderStyle({ dungeonStyle = styles.AUTO, stylePreset = 7 }) == styles.DEFAULT,
        "MSUF Forever did not keep the plain button")
    local values = W.Suite.DataTextPresetValues("minimap", 1, W.S.Config("dataTexts"))
    check(values.bar1MinimapDock == true and values.bar1Width == W.S.Config("minimap").size,
        "the Minimap companion preset is not attached below the map at its width")
    print("Minimap group finder Automatic style and companion data bar passed")
end

-- One place for addon launchers: with the drawer on, Blizzard's addon
-- compartment sits in the drawer; without addon buttons it stands alone on
-- the drawer's row; without the drawer it returns to its own slot, and
-- disabling the module gives it back to Blizzard.
do
    local W = H.New(root, "Mainline")
    local map, G = W.map, W.G
    local compartment = G.AddonCompartmentFrame
    local menuOpen = false
    function compartment:IsMenuOpen() return menuOpen end
    local button = W.Button("LibDBIcon10_Alpha", map, 31, 31)
    button.points = {}
    button:SetPoint("CENTER", map, "CENTER", 80, 10)
    H.Enable(W, { captured = true, showCompartment = true })
    W.Blizzard(function() compartment:Show() end)
    W.Step()
    local S, MM = W.S, W.MM
    local panel = MM.panel
    check(W.Suite.MinimapCompartmentInDrawer(S.Config("minimap")), "the compartment does not belong to the drawer")
    S.Apply("minimap")
    W.Step()
    check(compartment:GetParent() == panel and button:GetParent() == panel, "the compartment is not in the drawer")
    check(select(4, compartment:GetPoint(1)) * compartment.scale < select(4, button:GetPoint(1)) * button.scale,
        "the compartment does not come first in the drawer")
    -- Its menu opens outside the panel: a click there keeps the drawer.
    local toggle
    for _, frame in ipairs(MM.host.children) do
        if frame.kind == "Button" and frame.minimapOffsetKey == "drawer" then toggle = frame end
    end
    W.Click(toggle)
    menuOpen = true
    W.Event("GLOBAL_MOUSE_DOWN", "LeftButton")
    check(panel.shown, "clicking the compartment's menu closed the drawer")
    menuOpen = false
    W.Event("GLOBAL_MOUSE_DOWN", "LeftButton")
    check(not panel.shown, "a click away kept the drawer open")
    -- The list names it like the setting does.
    assert(S.Set("minimap", "drawerList", true))
    local named = false
    for _, label in ipairs(panel.listLabels or {}) do
        if label.shown and label.text == "Addon compartment" then named = true end
    end
    check(named, "the drawer list does not name the compartment")
    assert(S.Set("minimap", "drawerList", false))
    -- Without the drawer the compartment returns to its own row slot.
    assert(S.Set("minimap", "collectButtons", false))
    check(compartment:GetParent() ~= panel and compartment:GetParent():GetParent() == MM.host, "the compartment lost its slot")
    assert(S.Set("minimap", "collectButtons", true))
    check(compartment:GetParent() == panel, "the compartment did not return to the drawer")
    assert(S.Set("minimap", "enabled", false))
    check(compartment:GetParent() == W.cluster, "disabling the module kept Blizzard's compartment")
    print("Minimap addon compartment inside the addon button drawer passed")
end

-- The calendar day text replaces Blizzard's calendar button, and the invite
-- mark moves onto the text while the clock is off.
do
    local W = H.New(root, "Mainline")
    local invites = 0
    W.G.C_Calendar = { GetNumPendingInvites = function() return invites end }
    H.Enable(W, { captured = true, infoClock = false, infoLocation = false })
    W.Step()
    local S, MM, G = W.S, W.MM, W.G
    local calendar = G.GameTimeFrame
    check(calendar:GetParent() ~= MM.park, "the calendar button starts on the row")
    assert(S.Set("minimap", "infoCalendarDay", true))
    check(calendar:GetParent() == MM.park, "the calendar day text did not replace Blizzard's calendar button")
    local day = W.M.infoEntries.CalendarDay
    invites = 1
    W.Event("CALENDAR_UPDATE_PENDING_INVITES")
    check(day.invite and day.invite.shown, "the calendar day text does not carry the invite mark")
    assert(S.Set("minimap", "infoClock", true))
    check(not day.invite.shown and W.M.infoEntries.Clock.invite.shown, "the clock did not take the invite mark back")
    assert(S.Set("minimap", "infoCalendarDay", false))
    check(calendar:GetParent() ~= MM.park and not W.M.infoEntries.Clock.invite.shown,
        "Blizzard's calendar button did not come back with its own invite display")
    print("Minimap calendar day text replacing the calendar button passed")
end

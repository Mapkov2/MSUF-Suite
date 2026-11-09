local root = assert(arg[1], "repository root required")
local H = dofile(root .. "/tools/tests/suite_minimap_harness.lua")
local ID = "dataTexts"
local OWNER = "MSUFSuite.dataTexts"
local BAR = "bar42"

for _, client in ipairs({ "Mainline", "Forever" }) do
    local world = H.New(root, client, { beforeModules = function(w)
        w.G.GetFramerate = function() return 75 end
        w.G.PlayerHasToy = function() return false end
        w.G.C_Item = { GetItemCount = function() return 0 end }
    end })
    local G, S, Suite = world.G, world.S, world.Suite
    world.LoadAddon("MSUF_Suite_DataTexts")
    local config = S.Config(ID)
    config.enabled, config.bar1Enabled = false, false
    config.barIds = "0"
    S.Start()
    local first = Suite.DataTextBarCreationValues(config, 1, "microMenu")
    first.bar1Slot1 = Suite.DataTextSourceIndex.fps
    first.bar1Y = -50
    assert(S.SetMany(ID, first))
    local previousY = config.bar1Y
    local values = Suite.DataTextBarCreationValues(config, 42, "microMenu")
    values.bar42Slot1 = Suite.DataTextSourceIndex.fps
    assert(S.SetMany(ID, values))
    local bar = assert(S.instances[ID].bars[42])
    local function CheckPoint(point, x, y)
        local own, parent, relative, actualX, actualY = bar.frame:GetPoint()
        assert(own == point and parent == G.UIParent and relative == point and actualX == x and actualY == y,
            "unexpected bar position: " .. tostring(own) .. " " .. tostring(actualX) .. " " .. tostring(actualY))
    end
    CheckPoint("CENTER", 0, 0)

    local history, hidden = 0, 0
    G.MSUF2 = {
        Widgets = {}, Theme = {},
        frame = { Hide = function() hidden = hidden + 1 end },
        RunWithHistory = function(_, _, fn)
            history = history + 1
            return fn()
        end,
    }
    setfenv(assert(loadfile(root .. "/MSUF_Suite/Core/HostBridgeMenu.lua")), G)("MSUF_Suite", Suite)
    local options = {}
    setfenv(assert(loadfile(root .. "/MSUF_Suite_Options/Menu/Bridge.lua")), G)("MSUF_Suite_Options", options)
    options.Refresh = function() end
    options.historyRegistered = true
    local dock = Suite.DataTextDock
    assert(S.SetMany(ID, { bar42Dock = dock.LEFT, bar42Point = 9, bar42X = -20, bar42Y = 50 }))
    CheckPoint("LEFT", 0, 0)
    assert(options.Set(ID, BAR .. "Dock", dock.FREE))
    CheckPoint("CENTER", 0, 0)
    assert(history == 1 and config.bar1Y == previousY, "undocking must make one history entry for the selected bar")
    local mover = assert(world.movers[OWNER .. "/" .. BAR])
    assert(mover.movePosition({ state = mover.captureState(), deltaX = 30, deltaY = -21, phase = "commit" }))
    CheckPoint("CENTER", 30, -21)
    assert(options.Set(ID, BAR .. "Dock", dock.FREE))
    CheckPoint("CENTER", 30, -21)

    assert(S.Set(ID, BAR .. "Dock", dock.TOP))
    local companion = Suite.DataTextPresetValues("minimap", 42, config)
    assert(companion.bar42Point == 3 and companion.bar42X == -20 and companion.bar42Y == -220,
        "an explicitly positioned preset must keep its own position")
    local undocked = Suite.DataTextPresetValues("microMenu", 42, config)
    assert(S.SetMany(ID, undocked))
    CheckPoint("CENTER", 0, 0)
    assert(not mover.centerPopup, "the popup must use the host's normal placement")

    local api, entered, opened = G.MSUF_EditModeAPI, 0, 0
    api.EnterEditMode = function(owner, element)
        assert(owner == OWNER and element == BAR, "entered Edit Mode with the wrong bar")
        entered = entered + 1
        return true
    end
    api.OpenPopup = function(owner, element)
        assert(owner == OWNER and element == BAR and entered == 1, "popup must follow entry for the selected bar")
        opened = opened + 1
        return true
    end
    options.MoveOnScreen(ID, BAR, true)
    assert(entered == 1 and opened == 1 and hidden == 1, "the selected mover popup must replace the options menu")

    api.EnterEditMode = function(owner, element)
        assert(owner == OWNER and element == BAR, "missing selected bar must not fall back to another mover")
        return false
    end
    options.MoveOnScreen(ID, BAR, true)
    assert(opened == 1 and hidden == 1, "refused Edit Mode must leave the menu open")

    api.EnterEditMode = function() return true end
    api.OpenPopup = nil
    options.MoveOnScreen(ID, BAR, true)
    assert(hidden == 2, "a host without popup support must still open Edit Mode")

    world.combat = true
    api.EnterEditMode = function() error("Edit Mode entered in combat") end
    options.MoveOnScreen(ID, BAR, true)
    assert(hidden == 2, "combat refusal must leave the menu open")
    print("DataTexts free position and Edit Mode popup: " .. client .. " PASS")
end

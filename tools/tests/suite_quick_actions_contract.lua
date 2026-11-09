local root = assert(arg[1], "repository root required")
local Fixture = dofile(root .. "/tools/tests/suite_inventory_tools_fixture.lua")
function wipe(value) for key in pairs(value) do value[key] = nil end end
local function Check(expected, actual, description)
    assert(expected == actual, description .. " (expected " .. tostring(expected) .. ", got " .. tostring(actual) .. ")")
end

local function NewWorld(forever)
    local E = Fixture.New(root, forever)
    local NS, S = E.NS, E.S
    local calls = { loads = 0, panels = 0 }
    MSUFSuite, SlashCmdList = NS, {}
    NS.Text = S.Text
    NS.PublicText = S.PublicText
    S.started = true
    local create = S.QoLWindow
    S.QoLWindow = function(...)
        local frame = create(...)
        frame.EnableGamePadButton = function(self, enabled) self.padEnabled = enabled end
        return frame
    end
    S.GamepadUI = function() return E.gamepad == true end
    S.Dispatch = function(fn, ...) return fn(...) end
    NS.Finish = function(fn, ...) return fn(...) end
    Enum.GameRule = { CharacterPanelDisabled = 1, WorldMapDisabled = 2 }
    C_GameRules = { IsGameRuleActive = function() return E.disabled or false end }
    CharacterFrame = S.CreateFrame("Frame")
    WorldMapFrame = S.CreateFrame("Frame")
    CharacterFrame:Hide()
    WorldMapFrame:Hide()
    ShowUIPanel = function(panel)
        assert(not E.combat and not E.gamepad)
        calls.panels = calls.panels + 1
        panel:Show()
    end
    HideUIPanel = function() error("Quick Actions must open, never toggle, a native window") end

    E:Load("MSUF_Suite/Core/CharacterData.lua", true)
    S.CharacterData = NS.CharacterData
    C_AddOns = { LoadAddOn = function(addon)
        Check("MSUF_Suite_Modules", addon, "lazy runtime")
        calls.loads = calls.loads + 1
        E:Load("MSUF_Suite_Modules/MicroMenu.lua")
        E:Load("MSUF_Suite_Modules/QuickActions.lua")
        return true
    end }
    E:Load("MSUF_Suite/Core/QuickActionsCommand.lua", true)
    Check("/msufactions", SLASH_MSUFSUITEQUICKACTIONS1, "slash registered")
    Check(0, calls.loads, "no runtime loaded by the command file")
    return E, calls
end

local function FindWindow(E, owner)
    for _, frame in ipairs(E.frames) do
        if frame.owner == owner then return frame end
    end
end

local function Keyboard(window, script, value)
    window.search.scripts[script](window.search, value)
end

local function VerifyLaunch(forever)
    local E, calls = NewWorld(forever)
    local NS, S = E.NS, E.S
    local slash = SlashCmdList.MSUFSUITEQUICKACTIONS
    E.combat = true
    Check(false, slash(), "launcher blocks combat before LoD")
    Check(0, calls.loads, "no LoD in combat")
    E.combat = false

    local archive = E:Start("inventoryArchive", { characters = 5, tooltips = false })
    E:Item(0, 1, 123, 2)
    E:Item(0, 2, 999, 3)
    E:Flush()
    S.instances.characterPanel = { active = true, running = true }
    S.OpenCharacterPanelTab = function(tab)
        calls.tab = tab
        return true
    end
    S.Text = function(key) return key == "Reputation" and "Ruf" or key end

    Check(true, slash("Ruf"), "shortcut opens palette")
    Check(1, calls.loads, "runtime loads once")
    local owner = S.QuickActions
    local window = assert(FindWindow(E, owner))
    Check(620, window.width, "quick window is compact")
    Check("reputation", window:Selected().key, "localized action beats archive search")
    Keyboard(window, "OnArrowPressed", "DOWN")
    Check("itemSearch", window:Selected().key, "arrow selects next result")
    Keyboard(window, "OnArrowPressed", "UP")
    Check(true, window.padEnabled, "palette captures gamepad navigation while visible")
    local pad = window.scripts.OnGamePadButtonDown
    pad(window, "PADDDOWN")
    Check("itemSearch", window:Selected().key, "direction pad selects next result")
    pad(window, "PADDUP")
    window.actions[2]:Click()
    Check(true, owner.state.favorites.reputation, "favorite persists per character")
    pad(window, "PAD1")
    Check("reputation", calls.tab, "gamepad confirms the exact character tab")
    Check(false, window:IsShown(), "launcher closes after opening")
    Check(false, window.padEnabled, "closed palette releases the gamepad")
    Check(nil, window.scripts.OnGamePadButtonDown, "closed palette releases the handler")
    Check(nil, owner.state, "launcher releases closed state")

    Check(true, slash(), "reopen with saved state")
    window.tabs[2]:Click()
    Check("reputation", window:Selected().key, "favorites tab restores saved action")
    window.tabs[3]:Click()
    Check("reputation", window:Selected().key, "recents record successful actions")
    window.tabs[1]:Click()
    window.search:SetText("Item 123")
    Check("itemSearch", window:Selected().key, "item result delegates archive query")
    local scans = E.calls.scan
    Keyboard(window, "OnEnterPressed")
    local archiveWindow = assert(FindWindow(E, archive))
    Check(756, archiveWindow.width, "reused tool returns to regular size")
    Check("Item 123", archiveWindow.search:GetText(), "archive opens already filtered")
    Check(1, #archiveWindow.filtered, "archive returns exact matching record")
    Check(scans, E.calls.scan, "typed archive route never scans live bags")
    Check("inventoryArchive", S.CharacterData("quickActions").recent[1], "only action ID saved")
    Check(nil, owner.item.query, "user input is discarded when palette closes")

    Check(true, slash("world map"), "native result opens")
    window.actions[1]:Click()
    Check(1, calls.panels, "native result uses the shared panel owner")
    Check(true, WorldMapFrame:IsShown(), "map is shown")
    slash("world map")
    window.buttons[1].scripts.OnDoubleClick(window.buttons[1], "LeftButton")
    Check(1, calls.panels, "running same action never hides an open native panel")

    E.disabled = E.secret
    slash("world map")
    window.actions[1]:Click()
    Check(1, calls.panels, "unknown native game rule never opens the map")
    E.disabled = nil
    if forever then
        E.gamepad = true
        slash("world map")
        Check("itemSearch", window:Selected().key, "Forever gamepad excludes unsupported native launch")
        E.gamepad = false
    end

    slash("Ruf")
    local before = calls.tab
    E.combat = true
    Keyboard(window, "OnEnterPressed")
    Check(before, calls.tab, "combat blocks selected result")
    window.scripts.OnEvent(window, "PLAYER_REGEN_DISABLED")
    Check(false, window:IsShown(), "combat closes the launcher")
    E.combat = false
    slash("Ruf")
    NS.DB = {}
    Keyboard(window, "OnEnterPressed")
    Check(false, S.ToolListWindow.IsOpen(archive), "stale profile does not run the selected route")
    Keyboard(window, "OnEscapePressed")
    Check(false, window:IsShown(), "Escape closes the launcher")
    slash()
    window.scripts.OnGamePadButtonDown(window, "PAD2")
    Check(false, window:IsShown(), "gamepad cancel closes the launcher")
    Check(1, calls.loads, "no repeated runtime loads")
end

local function VerifyCharacterRoute(forever)
    local E, calls = NewWorld(forever)
    SlashCmdList.MSUFSUITEQUICKACTIONS()
    local S = E.S
    local visible
    local function Observe(root) visible = root end
    local function Pane()
        return { IsVisible = function() return CharacterFrame:IsShown() end }
    end
    CharacterFrame.IsVisible = CharacterFrame.IsShown
    CharacterFrame.activeSubframe = "ReputationFrame"
    CharacterFrame.HookScript = function() end
    PaperDollFrame, ReputationFrame = Pane(), Pane()
    hooksecurefunc = function() end
    local panel = {
        Host = { Client = E.NS.Client },
        Suite = S,
        Public = S.Public,
        String = S.PublicText,
        CanReplace = function() return not E.combat and not E.gamepad end,
    }
    assert(loadfile(root .. "/MSUF_Suite_CharacterPanel/Routing.lua"))("Test", panel)
    Check(false, S.OpenCharacterPanelTab("gear"), "native-only/basic mode does not route a custom tab")
    panel.Routing.Sync(Observe)
    Check(false, S.OpenCharacterPanelTab("arbitrary"), "unknown character destination refused")
    Check(false, S.OpenCharacterPanelTab(E.secret), "secret character destination refused")
    Check(true, S.OpenCharacterPanelTab("gear"), "read-only equipment target is routed from another native tab")
    Check(CharacterFrame, visible, "native visibility consumer notified")
    Check(1, calls.panels, "character route opens native panel once")
    local _, nativeTab, requested = panel.Routing.TakeTabRequest()
    Check("reputation", nativeTab, "native tab remains unchanged")
    Check("gear", requested, "coalesced consumer receives exact Suite destination")
    Check(nil, select(3, panel.Routing.TakeTabRequest()), "request is consumed once")
    E.combat = true
    Check(false, S.OpenCharacterPanelTab("reputation"), "combat blocks native route")
    Check(1, calls.panels, "combat attempted no native writes")
end

VerifyLaunch(false)
VerifyLaunch(true)
VerifyCharacterRoute(false)
VerifyCharacterRoute(true)
print("Suite Quick Actions contract passed for Retail and Forever")

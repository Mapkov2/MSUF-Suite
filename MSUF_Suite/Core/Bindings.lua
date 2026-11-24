local _, NS = ...
-- Labels for the key binding commands in Bindings.xml (loaded by the client
-- from the addon root). Suite bars 9/10 and the friendly NPC toggle need their
-- own commands; bars 1-8, stance and pet keep Blizzard's commands. The
-- Keybindings UI resolves these globals when it opens, so plain strings
-- from the always-loaded core are enough. Core/Catalog/ActionBars.lua loads
-- right before this file.
local Text = NS.Text

-- Friendly visibility belongs to Blizzard. Suite switches make deliberate
-- native changes; a normal skin refresh must not turn nameplates back on.
local FRIENDLY_SCOPES = {
    friendly = { key = "friendlySkinEnabled", cvar = "nameplateShowFriendlyPlayers" },
    friendlyNpc = { key = "friendlyNpcSkinEnabled", cvar = "nameplateShowFriendlyNpcs" },
}
local FRIENDLY_CVARS = {
    nameplateshowfriendlyplayers = "friendly", nameplateshowfriendlynpcs = "friendlyNpc",
}
local NPC_NAMES_ONLY = 4

-- World names stand in for friendly NPC plates with NPC Names only, and with
-- Name only while the module shows them in an instance: friendly plates there
-- are forbidden to addons (MSUF_Suite_Nameplates/CVars.lua NpcLock).
local function WorldNames(config, module)
    if config.friendlyNPCs == NPC_NAMES_ONLY then return true end
    module = module or NS.Suite.instances.nameplates
    return module ~= nil and module.active == true and module.friendlyNpcNamesOnly == true
end

local function FriendlyNativeValue(key)
    local value = C_CVar.GetCVar(key)
    if not NS.Public(value) or type(value) ~= "string" then return nil end
    local number = tonumber(value)
    if number then return number > 0 and "1" or "0" end
end

function NS.FriendlyNameplateShown(scope, config)
    if not NS.Public(scope) then return false end
    local spec = FRIENDLY_SCOPES[scope]
    if not spec then return false end
    config = config or NS.Suite.Config("nameplates")
    if config.enabled ~= true or config[spec.key] == false then return false end
    local key = scope == "friendlyNpc" and WorldNames(config) and "UnitNameNPC" or spec.cvar
    return FriendlyNativeValue(key) == "1"
end

function NS.CaptureFriendlyNameplates(module)
    if not module then return end
    local seen = module.friendlyVisibility or {}
    module.friendlyVisibility = seen
    for scope, spec in pairs(FRIENDLY_SCOPES) do
        local value = FriendlyNativeValue(spec.cvar)
        if value then seen[scope] = value end
    end
end

function NS.SetFriendlyNameplates(scope, on, values)
    if NS.InCombat() or not NS.Public(scope) or not NS.Public(on) then return false end
    local spec = FRIENDLY_SCOPES[scope]
    if not spec or type(on) ~= "boolean" or not FriendlyNativeValue(spec.cvar) then return false end
    if not NS.Public(values) or (values ~= nil and type(values) ~= "table") then return false end
    local settings = {}
    for key, value in pairs(values or {}) do settings[key] = value end
    settings[spec.key] = on
    local suite = NS.Suite
    if not NS.Public(settings.enabled) then return false end
    if suite.Config("nameplates").enabled ~= true and settings.enabled ~= true then return false end
    -- The native write belongs to the same change: the controller confirms it
    -- before the menu repaints. A module that does not run afterwards (it
    -- could not start, is unavailable or stopped after an error) or a value
    -- Blizzard refused restores the whole batch, so the profile never keeps a
    -- visibility it did not apply.
    return suite.SetMany("nameplates", settings, function()
        local module = suite.instances.nameplates
        if not module or not module.active then return false, suite.Status("nameplates") end
        local namesOnly = scope == "friendlyNpc" and WorldNames(suite.Config("nameplates"), module)
        local value = on and not namesOnly and "1" or "0"
        module.friendlyVisibility = module.friendlyVisibility or {}
        module.friendlyVisibility[scope] = value
        local committed = suite.CommitCVar("nameplates", spec.cvar, value)
        NS.CaptureFriendlyNameplates(module)
        return committed
    end)
end

local function FriendlySettings(settings, scope, value, module)
    settings[FRIENDLY_SCOPES[scope].key] = value == "1"
    -- Blizzard's explicit NPC On requests health bars instead of world names.
    if scope == "friendlyNpc" and value == "1" and WorldNames(module.config, module) then
        settings.friendlyNPCs = 2
    end
end

function NS.SyncFriendlyNameplates(module, event, key)
    if not module.active or module.friendlyVisibilityWriting or not NS.Public(key) then return false end
    local seen = module.friendlyVisibility
    if not seen then
        NS.CaptureFriendlyNameplates(module)
        return false
    end
    local pending = module.friendlyVisibilityPending
    if key ~= nil then
        if type(key) ~= "string" then return false end
        local scope = FRIENDLY_CVARS[key:lower()]
        if not scope then return false end
        local value = FriendlyNativeValue(FRIENDLY_SCOPES[scope].cvar)
        if not value or value == seen[scope] then return false end
        seen[scope] = value
        pending = pending or {}
        module.friendlyVisibilityPending = pending
        pending[scope] = value
    end
    if not pending or NS.InCombat(event) then return false end
    local settings, remaining = {}, nil
    for scope in pairs(pending) do
        local value = FriendlyNativeValue(FRIENDLY_SCOPES[scope].cvar)
        if value then
            seen[scope] = value
            FriendlySettings(settings, scope, value, module)
        else
            remaining = remaining or {}
            remaining[scope] = pending[scope]
        end
    end
    module.friendlyVisibilityPending = remaining
    if not next(settings) then return false end
    return NS.Suite.SetMany("nameplates", settings)
end

_G.BINDING_NAME_MSUFSUITE_TOGGLE_FRIENDLY_NPCS = Text("Toggle friendly NPC nameplates")
function NS.ToggleFriendlyNPCNameplates()
    if NS.InCombat() then return false end
    local config = NS.Suite.Config("nameplates")
    if not config.enabled then return false end
    return NS.SetFriendlyNameplates("friendlyNpc", not NS.FriendlyNameplateShown("friendlyNpc", config))
end

-- The action bar settings that switch bar `index` off or on (`on` nil flips
-- it); nil when the bar already is that way. Off keeps the bar's mode in its
-- hidden ResumeVisibility setting, on brings that mode back. Shared by the
-- toggle bindings (ActionBars/Visibility.lua) and the options page switches.
function NS.ActionBarSwitchValues(config, index, on)
    local key, resume = "bar" .. index .. "Visibility", "bar" .. index .. "ResumeVisibility"
    local NEVER = NS.ActionBarEnum.VISIBILITY.NEVER
    local mode = config[key]
    if on == nil then on = mode == NEVER end
    if on then return mode == NEVER and { [key] = config[resume] } or nil end
    return mode ~= NEVER and { [key] = NEVER, [resume] = mode } or nil
end

_G.BINDING_HEADER_MSUFSUITE = "MSUF Suite"
-- Headers inside the MSUF Suite category; the 12.x Keybindings UI draws
-- each as a spacer row (Blizzard_SettingsDefinitions_Frame/Keybindings.lua).
_G.BINDING_HEADER_MSUFSUITE_TOGGLES = Text("Action bars")
_G.BINDING_HEADER_MSUFSUITE_DAMAGEMETER = Text("Damage meter")
local toggleFormat = Text("Toggle %s")
for bar = 1, 12 do
    _G["BINDING_NAME_MSUFSUITE_TOGGLE_BAR" .. bar] = toggleFormat:format(Text(NS.ActionBarTitles[bar]))
end
_G.BINDING_NAME_MSUFSUITE_TOGGLE_DAMAGE_METER = Text("Toggle damage meter")
_G.BINDING_NAME_MSUFSUITE_RESET_DAMAGE_METER = Text("Reset damage meter")
_G.BINDING_NAME_MSUFSUITE_TOGGLE_FPS = Text("Toggle FPS display")
_G.BINDING_NAME_MSUFSUITE_QUICK_ACTIONS = Text("Quick actions")
_G.BINDING_NAME_MSUFSUITE_TOGGLE_MAP_OVERLAY = Text("Toggle map overlay")
_G.BINDING_HEADER_MSUFSUITE_MINIMAP = Text("Minimap")
_G.BINDING_NAME_MSUFSUITE_TOGGLE_MINIMAP = Text("Show or hide the minimap")
_G.BINDING_NAME_MSUFSUITE_TOGGLE_MINIMAP_DRAWER = Text("Open or close the addon button drawer")

-- The minimap is protected: both shortcuts refuse in combat. Hiding lasts
-- for this session; the Minimap page keeps the saved visibility.
local function MinimapShortcut(method)
    local suite = NS.Suite
    local map = suite.instances.minimap
    if map and map.active then
        if NS.InCombat() then return false end
        return map[method](map)
    end
    if not NS.InCombat() then suite.Print(Text("Enable the Suite minimap to use this shortcut.")) end
    return false
end
function NS.ToggleMinimap() return MinimapShortcut("ToggleShown") end
function NS.ToggleMinimapDrawer() return MinimapShortcut("ToggleDrawer") end
function NS.ToggleMapOverlay()
    local suite = NS.Suite
    local hud = suite.instances.navigationHUD
    if hud and hud.active then return hud:ToggleMap() end
    if not NS.InCombat() then suite.Print(Text("Enable Map overlay & compass in Suite to use this shortcut.")) end
    return false
end
_G["BINDING_NAME_CLICK MSUFSuiteQuestItem:LeftButton"] = Text("Use tracked quest item")
_G["BINDING_NAME_CLICK MSUFSuiteQuestContinue:LeftButton"] = Text("Advance NPC dialogue")
_G["BINDING_NAME_CLICK MSUFSuiteFishing:LeftButton"] = Text("Fishing")
_G["BINDING_NAME_CLICK MSUFSuiteFishingLure:LeftButton"] = Text("Apply fishing lure")
_G["BINDING_NAME_CLICK MSUFSuiteSelfBuff:LeftButton"] = Text("Cast next missing self-buff")
local buttonFormat = Text("%s button %d")
for bar = 9, 10 do
    local title = Text(NS.ActionBarTitles[bar])
    _G["BINDING_HEADER_MSUFSUITE_BAR" .. bar] = title
    for button = 1, 12 do
        _G["BINDING_NAME_MSUFSUITE_BAR" .. bar .. "_BUTTON" .. button] = buttonFormat:format(title, button)
    end
end

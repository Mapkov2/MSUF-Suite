local _, NS = ...
-- Labels for the key binding commands in Bindings.xml (loaded by the client
-- from the addon root). Suite bars 9/10 and the friendly NPC toggle need their
-- own commands; bars 1-8, stance and pet keep Blizzard's commands. The
-- Keybindings UI resolves these globals when it opens, so plain strings
-- from the always-loaded core are enough. Core/Catalog/ActionBars.lua loads
-- right before this file.
local Text = NS.Text

_G.BINDING_NAME_MSUFSUITE_TOGGLE_FRIENDLY_NPCS = Text("Toggle friendly NPC nameplates")
function NS.ToggleFriendlyNPCNameplates()
    if NS.IsCombatLocked() then return false end
    local suite = NS.Suite
    local config = suite.Config("nameplates")
    if not config.enabled then return false end
    local value = C_CVar.GetCVar("nameplateShowFriendlyNpcs")
    if not NS.Public(value) or type(value) ~= "string" or value == "" then return false end
    return suite.Set("nameplates", "friendlyNPCs", value == "1" and 3 or 2)
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
_G["BINDING_NAME_CLICK MSUFSuiteQuestItem:LeftButton"] = Text("Use tracked quest item")
local buttonFormat = Text("%s button %d")
for bar = 9, 10 do
    local title = Text(NS.ActionBarTitles[bar])
    _G["BINDING_HEADER_MSUFSUITE_BAR" .. bar] = title
    for button = 1, 12 do
        _G["BINDING_NAME_MSUFSUITE_BAR" .. bar .. "_BUTTON" .. button] = buttonFormat:format(title, button)
    end
end

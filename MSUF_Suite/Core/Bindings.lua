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

_G.BINDING_HEADER_MSUFSUITE = "MSUF Suite"
local buttonFormat = Text("%s button %d")
for bar = 9, 10 do
    local title = Text(NS.ActionBarTitles[bar])
    _G["BINDING_HEADER_MSUFSUITE_BAR" .. bar] = title
    for button = 1, 12 do
        _G["BINDING_NAME_MSUFSUITE_BAR" .. bar .. "_BUTTON" .. button] = buttonFormat:format(title, button)
    end
end

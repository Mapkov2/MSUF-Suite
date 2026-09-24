local _, NS = ...
-- Labels for the key binding commands in Bindings.xml (loaded by the client
-- from the addon root). Only the suite-only action bars 9 and 10 need their
-- own commands; bars 1-8, stance and pet keep Blizzard's commands. The
-- Keybindings UI resolves these globals when it opens, so plain strings
-- from the always-loaded core are enough.
local L = type(NS.L) == "table" and NS.L or {}
local function Text(english)
    local value = L[english]
    return type(value) == "string" and value ~= "" and value or english
end

local titles = NS.ActionBarTitles or {}
_G.BINDING_HEADER_MSUFSUITE = "MSUF Suite"
local buttonFormat = Text("%s button %d")
for bar = 9, 10 do
    local title = Text(titles[bar] or ("Action bar " .. bar))
    _G["BINDING_HEADER_MSUFSUITE_BAR" .. bar] = title
    for button = 1, 12 do
        _G["BINDING_NAME_MSUFSUITE_BAR" .. bar .. "_BUTTON" .. button] = buttonFormat:format(title, button)
    end
end

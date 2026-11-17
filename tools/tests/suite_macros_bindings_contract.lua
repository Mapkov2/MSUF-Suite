local root = assert(arg[1], "repository root required")
local secret = {}
local combat, editing, spec = false, false, 1
local modifiers, profile, writes = 0, {}, 0
local set, keys, saved, refuse = 1, {}, nil, false
local NS = { Macros = {}, InCombat = function() return combat end }
NS.Public = function(value) return value ~= secret end
NS.Finite = function(value) return NS.Public(value) and type(value) == "number" end
NS.PublicText = function(value) return NS.Public(value) and type(value) == "string" and value ~= "" and value or nil end
NS.Dispatch = function(fn, ...) return fn(...) end
NS.Finish = function(fn, ...) return true, fn(...) end

local types = { None = 0, Spell = 1, Macro = 2, Interaction = 3, PetAction = 4 }
Enum = { ClickBindingType = types, BindingSet = { Default = 0 }, ClickBindingInteraction = { Target = 1, OpenContextMenu = 2 } }
C_SpecializationInfo = { GetSpecialization = function() return spec end }
InClickBindingMode = function() return editing end
MakeModifiers = function() return modifiers end
GetStringFromModifiers = function() return modifiers > 0 and "Modifiers" or "" end
GetConvertedKeyOrButton = function(key) return key end
IsKeyPressIgnoredForBinding = function(key) return key == "LSHIFT" or key == "LCTRL" or key == "LALT" end
CreateKeyChordStringUsingMetaKeyState = function(key) return modifiers > 0 and "ALT-" .. key or key end
GetBindingText = function(key) return key end
GetCurrentBindingSet = function() return set end
GetBindingAction = function(key) return keys[key] or "" end
GetMacroInfo = function(index)
    if index == 3 then return "Another Heal" end
    if index == 2 then return "Heal" end
end
GetMacroIndexByName = function(name) return name == "Heal" and 2 or 0 end
SetBinding = function(key, action) keys[key] = action return true end
GetBindingKey = function(command)
    local found = {}
    for key, action in pairs(keys) do if action == command then found[#found + 1] = key end end
    return unpack(found)
end
SetBindingMacro = function(key, name)
    keys[key] = "MACRO " .. name
    return true
end
SaveBindings = function(bindingSet)
    if refuse then return false end
    saved = bindingSet
end
C_ClickBindings = {
    GetProfileInfo = function() return profile end,
    GetBindingType = function(button, modifier)
        if modifier == 0 and (button == "LeftButton" or button == "RightButton") then return types.Interaction end
        return types.None
    end,
    SetProfileByInfo = function(nextProfile)
        assert(not combat and nextProfile ~= profile, "changed the Blizzard-owned table or wrote during combat")
        writes = writes + 1
        if not refuse then profile = nextProfile end
    end,
}

assert(loadfile(root .. "/MSUF_Suite/Core/Macros/Native.lua"))("MSUF_Suite", NS)
local Native = NS.Macros.Native
local macro = { name = "Heal", index = 2 }
assert(not Native.BindingInput("Button32", true))
assert(not Native.BindingInput(secret, true))
assert(not Native.BindingInput("LSHIFT", false))
assert(not Native.BindingInput("BUTTON1", false))
assert(Native.BindingInput("Button1", true).button == "LeftButton")
assert(Native.BindingInput("Button2", true).button == "RightButton")
assert(Native.BindingInput("Button3", true).button == "MiddleButton")
assert(Native.BindingState(Native.BindingInput("LeftButton", true)).occupied, "default targeting was not detected")
assert(Native.BindingState(Native.BindingInput("RightButton", true)).occupied, "default menu was not detected")

local other = { button = "Button5", modifiers = 0, type = types.Spell, actionID = 99 }
profile = { other }
for i, button in ipairs({ "LeftButton", "RightButton", "MiddleButton", "Button4", "Button12", "Button31" }) do
    modifiers = i
    local input = assert(Native.BindingInput(button, true))
    assert(input.modifiers == i and Native.BindingLabel(input) == "Modifiers + " .. button)
    local expected = assert(Native.BindingState(input))
    assert(not expected.occupied and Native.ApplyBinding(input, expected, macro))
    assert(profile[1] == other, "binding replaced another click assignment")
    assert(profile[i + 1].button == button and profile[i + 1].modifiers == i and profile[i + 1].actionID == 2)
    assert(not Native.ApplyBinding(input, expected, macro), "stale input overwrote the profile")
end
assert(writes == 6)

modifiers = 0
local right = assert(Native.BindingInput("RightButton", true))
local legacy = { button = "Button2", modifiers = 0, type = types.Macro, actionID = 3 }
profile = { other, legacy }
local prior = assert(Native.BindingState(right))
assert(prior.name == "Another Heal" and prior.occupied)
assert(Native.IsReservedClick(right) and not Native.ApplyBinding(right, prior, macro) and profile[2] == legacy)
modifiers = 3
right = assert(Native.BindingInput("RightButton", true))
legacy.modifiers = modifiers
prior = assert(Native.BindingState(right))
spec = 2
assert(not Native.ApplyBinding(right, prior, macro) and profile[2] == legacy)
spec = 1
combat = true
assert(not Native.ApplyBinding(right, prior, macro) and profile[2] == legacy)
combat = false
editing = true
assert(not Native.ApplyBinding(right, prior, macro) and profile[2] == legacy)
editing = false
refuse = true
assert(not Native.ApplyBinding(right, prior, macro) and profile[2] == legacy, "silent refusal reported success")
refuse = false
assert(Native.ApplyBinding(right, prior, macro) and profile[2].actionID == 2 and #profile == 2)
assert(profile[1] == other and legacy.actionID == 3)

modifiers = 1
local keypad = assert(Native.BindingInput("NUMPAD7", false))
assert(keypad.key == "ALT-NUMPAD7" and not keypad.button)
keys[keypad.key] = "ACTIONBUTTON7"
prior = assert(Native.BindingState(keypad))
assert(prior.occupied)
set = 2
assert(not Native.ApplyBinding(keypad, prior, macro) and keys[keypad.key] == "ACTIONBUTTON7")
set = 1
refuse = true
assert(not Native.ApplyBinding(keypad, prior, macro) and keys[keypad.key] == "ACTIONBUTTON7", "failed save lost the old shortcut")
refuse = false
assert(Native.ApplyBinding(keypad, prior, macro) and keys[keypad.key] == "MACRO Heal" and saved == 1)
assert(writes == 8, "keypad assignment changed the click casting profile")

local plain = { button = "Button1", modifiers = 0, type = types.Macro, actionID = macro.index }
local modified = { button = "LeftButton", modifiers = 3, type = types.Macro, actionID = macro.index }
local menu = { button = "RightButton", modifiers = 0, type = types.Interaction, actionID = Enum.ClickBindingInteraction.OpenContextMenu }
profile = { other, plain, modified, menu }
assert(Native.RemoveBindings(macro, true))
assert(#profile == 4 and profile[1] == other and profile[2] == modified and profile[3] == menu)
assert(profile[4].type == types.Interaction and profile[4].actionID == Enum.ClickBindingInteraction.Target)
assert(keys[keypad.key] == "MACRO Heal", "restoring a plain click cleared a keyboard shortcut")
local restoredClicks = profile
profile = { other, menu }
saved = nil
refuse = true
assert(not Native.RemoveBindings(macro) and keys[keypad.key] == "MACRO Heal" and not saved,
    "failed keyboard cleanup lost the shortcut")
profile = restoredClicks
refuse = true
assert(not Native.RemoveBindings(macro) and profile[2] == modified)
refuse = false
assert(Native.RemoveBindings(macro) and #profile == 3 and not keys[keypad.key])
assert(profile[1] == other and profile[2] == menu and profile[3].button == "LeftButton")
local replacement = { button = "LeftButton", modifiers = 0, type = types.Spell, actionID = 11 }
profile = { replacement, menu }
assert(Native.RemoveBindings(nil, true) and #profile == 2 and profile[1] == replacement)
profile = { menu }
assert(Native.RemoveBindings(nil, true) and #profile == 2 and profile[2].button == "LeftButton")
local orphan = { button = "LeftButton", modifiers = 0, type = types.Macro, actionID = 42 }
profile = { orphan, menu }
assert(Native.RemoveBindings(nil, true) and #profile == 2 and profile[2].type == types.Interaction)

print("suite_macros_bindings_contract: passed")

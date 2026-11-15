local _, NS = ...
local Macros = NS.Macros
local Native = {}
Macros.Native = Native

local function Number(value)
    return NS.Finite(value) and value >= 0 and value == math.floor(value)
end

local function SameBody(a, b)
    return a:gsub("\r\n", "\n") == b:gsub("\r\n", "\n")
end

function Native.Character()
    return NS.PublicText(UnitGUID("player"))
end

local function Limits()
    local constants = Constants.MacroConsts
    local account, character = constants.MAX_ACCOUNT_MACROS, constants.MAX_CHARACTER_MACROS
    if not Number(account) or not Number(character) then return nil end
    return account, character
end

local function Read(index, accountLimit)
    local name, icon, body = GetMacroInfo(index)
    if not NS.PublicText(name) or NS.IsSecret(body) or type(body) ~= "string" then return nil end
    local selected = C_Macro.GetSelectedMacroIcon(index)
    if NS.Finite(selected) then icon = selected end
    return { index = index, name = name, icon = NS.Finite(icon) and icon or 134400, body = body,
        scope = index > accountLimit and "character" or "account" }
end

function Native.Scan()
    if NS.InCombat() then return {}, "Macro changes are unavailable in combat" end
    local accountLimit, characterLimit = Limits()
    if not accountLimit then return {}, "Macro storage is unavailable" end
    local account, character = GetNumMacros()
    if not Number(account) or not Number(character) or account > accountLimit or character > characterLimit then
        return {}, "Macro storage is unavailable"
    end
    local result = {}
    for index = 1, account do
        local entry = Read(index, accountLimit)
        if not entry then return {}, "Macro storage is unavailable" end
        result[#result + 1] = entry
    end
    for index = accountLimit + 1, accountLimit + character do
        local entry = Read(index, accountLimit)
        if not entry then return {}, "Macro storage is unavailable" end
        result[#result + 1] = entry
    end
    return result
end

local function Matches(entry, binding)
    return entry.scope == binding.scope and entry.name == binding.name and SameBody(entry.body, binding.body)
        and (binding.icon == nil or entry.icon == binding.icon)
end

function Native.Resolve(binding, entries)
    if type(binding) ~= "table" or not NS.PublicText(binding.name)
        or NS.IsSecret(binding.body) or type(binding.body) ~= "string" then
        return nil, "This draft has no saved WoW macro"
    end
    if binding.scope == "character" and binding.character ~= Native.Character() then
        return nil, "This macro belongs to another character"
    end
    local found
    for _, entry in ipairs(entries) do
        if Matches(entry, binding) then
            if found then return nil, "Several identical macros exist; import the intended one again" end
            found = entry
        end
    end
    if not found then return nil, "The WoW macro changed; import it again before replacing it" end
    return found
end

local function Capture(entry)
    return { index = entry.index, name = entry.name, body = entry.body, icon = entry.icon, scope = entry.scope,
        character = entry.scope == "character" and Native.Character() or nil }
end

function Native.Binding(index)
    local entries, errorText = Native.Scan()
    if errorText then return nil, errorText end
    for _, entry in ipairs(entries) do
        if entry.index == index then return Capture(entry), entry end
    end
    return nil, "The WoW macro is no longer available"
end

local function CanCreate(scope, entries)
    local accountLimit, characterLimit = Limits()
    local count = 0
    for _, entry in ipairs(entries) do if entry.scope == scope then count = count + 1 end end
    return count < (scope == "character" and characterLimit or accountLimit)
end

function Native.Publish(document, body, binding, replace)
    if NS.InCombat() then return nil, "Macro changes are unavailable in combat" end
    local entries, errorText = Native.Scan()
    if errorText then return nil, errorText end
    local current
    if replace then
        current, errorText = Native.Resolve(binding, entries)
        if not current then return nil, errorText end
        if current.scope ~= document.scope then return nil, "Save a new macro to change its storage scope" end
    elseif not CanCreate(document.scope, entries) then
        return nil, "The selected WoW macro storage is full"
    end
    for _, entry in ipairs(entries) do
        if entry.name:lower() == document.name:lower() and (not current or current.index ~= entry.index) then
            return nil, "That macro name already exists"
        end
    end
    if current and current.name == document.name and current.icon == document.icon
        and SameBody(current.body, body) then return Capture(current) end
    local ok, index
    if current then
        ok, index = NS.Dispatch(NS.Finish, EditMacro, current.index, document.name, document.icon, body)
        index = Number(index) and index or current.index
    else
        ok, index = NS.Dispatch(NS.Finish, CreateMacro, document.name, document.icon, body, document.scope == "character")
    end
    if not ok or not Number(index) or index < 1 then return nil, "WoW could not save the macro" end
    local accountLimit = Limits()
    local saved = Read(index, accountLimit)
    if not saved or saved.name ~= document.name or not SameBody(saved.body, body) then
        return nil, "WoW did not save the complete macro"
    end
    return Capture(saved)
end

function Native.Pickup(binding)
    if NS.InCombat() then return false, "Macro changes are unavailable in combat" end
    local entries, errorText = Native.Scan()
    if errorText then return false, errorText end
    local entry
    entry, errorText = Native.Resolve(binding, entries)
    if not entry then return false, errorText end
    if GetCursorInfo() ~= nil then return false, "Clear your cursor before picking up a macro" end
    PickupMacro(entry.index)
    return true
end

local function MouseButton(button)
    if not NS.Public(button) or type(button) ~= "string" then return nil end
    if button == "LeftButton" or button == "Button1" then return "LeftButton" end
    if button == "RightButton" or button == "Button2" then return "RightButton" end
    if button == "MiddleButton" or button == "Button3" then return "MiddleButton" end
    local number = tonumber(button:match("^Button(%d+)$"))
    -- Both Blizzard_ClickBindingUI branches label buttons through Button31.
    if number and number >= 4 and number <= 31 then return "Button" .. number end
end

function Native.BindingInput(raw, isMouse)
    if not NS.Public(raw) or type(raw) ~= "string" then return nil end
    if isMouse then
        local button = MouseButton(raw)
        if not button then return nil end
        local modifiers = MakeModifiers()
        if not Number(modifiers) then return nil end
        return { button = button, modifiers = modifiers }
    end
    local key = GetConvertedKeyOrButton(raw)
    if not NS.PublicText(key) or key:match("^BUTTON%d+$") or IsKeyPressIgnoredForBinding(key) then return nil end
    key = CreateKeyChordStringUsingMetaKeyState(key)
    if NS.PublicText(key) then return { key = key } end
end

function Native.IsReservedClick(input)
    return input.modifiers == 0 and (input.button == "LeftButton" or input.button == "RightButton")
end

function Native.BindingLabel(input)
    local key = input.key or GetConvertedKeyOrButton(input.button)
    local label = NS.PublicText(key) and NS.PublicText(GetBindingText(key)) or input.button or input.key
    if input.button then
        local modifiers = NS.PublicText(GetStringFromModifiers(input.modifiers))
        if modifiers then label = modifiers .. " + " .. label end
    end
    return label
end

local function ReadClickProfile()
    local profile = C_ClickBindings.GetProfileInfo()
    if not NS.Public(profile) or type(profile) ~= "table" then return nil end
    for _, binding in ipairs(profile) do
        if not NS.Public(binding) or type(binding) ~= "table" or not NS.Public(binding.modifiers)
            or not NS.Public(binding.type) or not NS.Public(binding.actionID) or not NS.Public(binding.button) then return nil end
    end
    return profile
end

local function ClickProfile(input)
    local profile = ReadClickProfile()
    if not profile then return nil end
    local found, slot
    for i, binding in ipairs(profile) do
        local button = MouseButton(binding.button)
        if button == input.button and binding.modifiers == input.modifiers then
            if found then return nil end
            found, slot = binding, i
        end
    end
    return profile, found, slot
end

local function ClickBinding(input)
    if InClickBindingMode() then return nil end
    local profile, found = ClickProfile(input)
    if not profile then return nil end
    local kind = found and found.type or C_ClickBindings.GetBindingType(input.button, input.modifiers)
    local spec = C_SpecializationInfo.GetSpecialization()
    if not Number(kind) or not NS.Public(spec) then return nil end
    local types = Enum.ClickBindingType
    local action = found and found.actionID
    local name
    if found and kind == types.Macro then name = NS.PublicText(GetMacroInfo(action)) end
    return { scope = spec, kind = kind, action = action, name = name, occupied = kind ~= types.None }
end

local function KeyBinding(input)
    local set, action = GetCurrentBindingSet(), GetBindingAction(input.key)
    if not Number(set) or set == Enum.BindingSet.Default or not NS.Public(action) or type(action) ~= "string" then return nil end
    return { scope = set, action = action, occupied = action ~= "" }
end

function Native.BindingState(input)
    if NS.InCombat() then return nil, "Macro changes are unavailable in combat" end
    local state = input.button and ClickBinding(input) or input.key and KeyBinding(input)
    if not state then return nil, "Macro bindings are unavailable right now." end
    return state
end

local function WriteClick(input, entry)
    local current, _, slot = ClickProfile(input)
    if not current then return false end
    local profile = { unpack(current) }
    local kind = Enum.ClickBindingType.Macro
    profile[slot or #profile + 1] = { type = kind, actionID = entry.index, button = input.button, modifiers = input.modifiers }
    if not NS.Dispatch(NS.Finish, C_ClickBindings.SetProfileByInfo, profile) then return false end
    local _, saved = ClickProfile(input)
    return saved and saved.type == kind and saved.actionID == entry.index
end

local function SaveKeyBindings(set)
    -- Blizzard's SaveBindings can complete without returning a value.
    local completed, result = NS.Dispatch(NS.Finish, SaveBindings, set)
    return completed == true and NS.Public(result) and result ~= false
end

local function WriteKey(input, state, entry)
    local index = GetMacroIndexByName(entry.name)
    if not Number(index) or index ~= entry.index then return false end
    local written = NS.Dispatch(SetBindingMacro, input.key, entry.name)
    if not NS.Public(written) or written ~= true then return false end
    if SaveKeyBindings(state.scope) then return true end
    NS.Dispatch(SetBinding, input.key, state.occupied and state.action or nil)
    return false
end

function Native.CheckBinding(input, expected)
    local state, errorText = Native.BindingState(input)
    if not state then return nil, errorText end
    -- Creating a macro can move indices. Compare the prior macro by name where available.
    local sameAction = state.name == expected.name and (expected.name ~= nil or state.action == expected.action)
    if state.scope ~= expected.scope or state.kind ~= expected.kind or not sameAction then
        return nil, "The binding changed. Choose the button again."
    end
    return state
end

function Native.ApplyBinding(input, expected, entry)
    if Native.IsReservedClick(input) then return false, "Hold Shift, Ctrl or Alt to bind left or right click." end
    local state, errorText = Native.CheckBinding(input, expected)
    if not state then return false, errorText end
    local applied
    if input.button then
        applied = state.kind == Enum.ClickBindingType.Macro and state.action == entry.index or WriteClick(input, entry)
    else
        applied = WriteKey(input, state, entry)
    end
    if not applied then return false, "The key binding could not be saved." end
    return true
end

local function RemoveMacroClicks(entry, reservedOnly)
    if InClickBindingMode() then return false end
    local current = ReadClickProfile()
    if not current then return false end
    local types, interactions = Enum.ClickBindingType, Enum.ClickBindingInteraction
    local profile, restore, present, occupied = {}, {}, {}, {}
    if reservedOnly then
        restore[interactions.Target] = "LeftButton"
        restore[interactions.OpenContextMenu] = "RightButton"
    end
    for _, row in ipairs(current) do
        local button = MouseButton(row.button)
        local reserved = Native.IsReservedClick({ button = button, modifiers = row.modifiers })
        local remove = row.type == types.Macro and entry and row.actionID == entry.index
        if reservedOnly and reserved and row.type == types.Macro and not remove then
            local name = GetMacroInfo(row.actionID)
            remove = NS.Public(name) and name == nil
        end
        if remove and (not reservedOnly or reserved) then
            if row.modifiers == 0 and button == "LeftButton" then restore[interactions.Target] = button end
            if row.modifiers == 0 and button == "RightButton" then restore[interactions.OpenContextMenu] = button end
        else
            profile[#profile + 1] = row
            if row.type == types.Interaction then present[row.actionID] = true end
            if reserved then occupied[button] = true end
        end
    end
    local changed = #profile ~= #current
    for action, button in pairs(restore) do
        if not present[action] and not occupied[button] then
            profile[#profile + 1] = { type = types.Interaction, actionID = action, button = button, modifiers = 0 }
            changed = true
        end
    end
    if not changed then return true end
    if not NS.Dispatch(NS.Finish, C_ClickBindings.SetProfileByInfo, profile) then return false end
    local saved = ReadClickProfile()
    if not saved then return false end
    for _, row in ipairs(saved) do
        if entry and row.type == types.Macro and row.actionID == entry.index
            and (not reservedOnly or Native.IsReservedClick({ button = MouseButton(row.button), modifiers = row.modifiers })) then
            return false
        end
    end
    for action, button in pairs(restore) do
        if not present[action] and not occupied[button] then
            local kind = C_ClickBindings.GetBindingType(button, 0)
            if not Number(kind) or kind ~= types.Interaction then return false end
        end
    end
    return true
end

local function RemoveMacroKeys(entry)
    local command = "MACRO " .. entry.name
    local keys = { GetBindingKey(command) }
    if #keys == 0 then return true end
    local set, removed = GetCurrentBindingSet(), {}
    if not Number(set) or set == Enum.BindingSet.Default then return false end
    for _, key in ipairs(keys) do
        if not NS.PublicText(key) then return false end
    end
    for _, key in ipairs(keys) do
        local action = GetBindingAction(key)
        if not NS.Public(action) or action ~= command then break end
        local ok = NS.Dispatch(SetBinding, key)
        if not NS.Public(ok) or ok ~= true then break end
        removed[#removed + 1] = key
    end
    if #removed == #keys and SaveKeyBindings(set) then return true end
    for _, key in ipairs(removed) do NS.Dispatch(SetBinding, key, command) end
    return false
end

function Native.RemoveBindings(entry, reservedOnly)
    if NS.InCombat() then return false, "Macro changes are unavailable in combat" end
    if not RemoveMacroClicks(entry, reservedOnly) or not reservedOnly and not RemoveMacroKeys(entry) then
        return false, "The key binding could not be saved."
    end
    return true
end

function Native.Delete(entry)
    local binding = Capture(entry)
    local entries, errorText = Native.Scan()
    if errorText then return false, errorText end
    local current
    current, errorText = Native.Resolve(binding, entries)
    if not current then return false, errorText end
    local ok
    ok, errorText = Native.RemoveBindings(current)
    if not ok then return false, errorText end
    local deleted = NS.Dispatch(NS.Finish, DeleteMacro, current.index)
    entries, errorText = Native.Scan()
    if errorText then return false, errorText end
    if not deleted or Native.Resolve(binding, entries) then
        return false, "WoW could not delete the macro."
    end
    return true
end

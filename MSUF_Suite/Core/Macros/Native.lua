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

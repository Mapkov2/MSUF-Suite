local _, NS = ...
local Macros = NS.Macros
local Store = {}
Macros.Store = Store
local MAX_DOCUMENTS = 200

local function Database(create)
    local root = NS.RootDB
    if type(root) ~= "table" then return nil end
    local data = root.macroWorkshop
    if data == nil and create then
        data = { version = 1, serial = 0, documents = {}, order = {}, bindings = {} }
        root.macroWorkshop = data
    end
    if type(data) ~= "table" or data.version ~= 1 or type(data.documents) ~= "table"
        or type(data.order) ~= "table" or type(data.bindings) ~= "table" or #data.order > MAX_DOCUMENTS then return nil end
    return data
end

local function Copy(document)
    local result, errorText = Macros.Model.Normalize(document)
    if not result then return nil, errorText end
    result.id = document.id
    return result
end

local function BindingKey(document)
    return document.scope == "account" and "account" or Macros.Native.Character()
end

local function Binding(data, document)
    local key = BindingKey(document)
    local bindings = key and data.bindings[key]
    return type(bindings) == "table" and bindings[document.id] or nil
end

local function Changed()
    if Store.OnChange then Store.OnChange() end
end

function Store.List()
    local data, result = Database(false), {}
    if not data then return result end
    for index = 1, math.min(#data.order, MAX_DOCUMENTS) do
        local source = data.documents[data.order[index]]
        if type(source) == "table" then
            local document = Copy(source)
            if document then
                document.published = Binding(data, source) ~= nil
                result[#result + 1] = document
            end
        end
    end
    return result
end

function Store.Get(id)
    local data = Database(false)
    local document = data and data.documents[id]
    if type(document) ~= "table" then return nil end
    local copy = Copy(document)
    if copy then copy.published = Binding(data, document) ~= nil end
    return copy
end

function Store.Save(document, id)
    if NS.InCombat() then return nil, "Macro changes are unavailable in combat" end
    local normalized, errorText = Macros.Model.Normalize(document)
    if not normalized then return nil, errorText end
    local data = Database(true)
    if not data then return nil, "Macro library is unavailable" end
    if id ~= nil and type(data.documents[id]) ~= "table" then return nil, "The macro draft is no longer available" end
    if id == nil then
        if #data.order >= MAX_DOCUMENTS then return nil, "The macro library is full" end
        local serial = data.serial
        if not NS.Finite(serial) or serial < 0 or serial > 100000000 or serial ~= math.floor(serial) then serial = 0 end
        repeat
            serial = serial + 1
            id = tostring(serial)
        until data.documents[id] == nil
        data.serial = serial
        data.order[#data.order + 1] = id
    end
    normalized.id = id
    data.documents[id] = normalized
    Changed()
    return id
end

function Store.Delete(id)
    if NS.InCombat() then return false, "Macro changes are unavailable in combat" end
    local data = Database(false)
    if not data or not data.documents[id] then return false, "The macro draft is no longer available" end
    data.documents[id] = nil
    for i = #data.order, 1, -1 do if data.order[i] == id then table.remove(data.order, i) end end
    for _, bindings in pairs(data.bindings) do
        if type(bindings) == "table" then bindings[id] = nil end
    end
    Changed()
    return true
end

function Store.Native()
    return Macros.Native.Scan()
end

function Store.Import(index)
    local binding, native = Macros.Native.Binding(index)
    if not binding then return nil, native end
    local id, errorText = Store.Save({ version = 1, name = native.name, scope = native.scope,
        icon = native.icon, mode = "raw", raw = native.body, showTooltip = false, steps = {} })
    if not id then return nil, errorText end
    local data = Database(false)
    local key = BindingKey(data.documents[id])
    if not key then return id end
    data.bindings[key] = data.bindings[key] or {}
    data.bindings[key][id] = binding
    return id
end

function Store.Preview(document)
    if NS.InCombat() then return nil, "Macro changes are unavailable in combat" end
    local resolver = Macros.Consumables and Macros.Consumables.Build
    return Macros.Compile(document, resolver)
end

local function Publish(id, replace, notify)
    if NS.InCombat() then return false, "Macro changes are unavailable in combat" end
    local data = Database(false)
    local source = data and data.documents[id]
    if type(source) ~= "table" then return false, "The macro draft is no longer available" end
    local document, invalid = Copy(source)
    if not document then return false, invalid end
    local nameLength = Macros.Model.Count(document.name)
    if not nameLength or nameLength < 1 or nameLength > 16 or not document.name:find("%S")
        or document.name:find("[%z\1-\31]") then
        return false, "Enter a macro name of up to 16 characters"
    end
    local body, errorText = Store.Preview(document)
    if not body then return false, errorText end
    local key = BindingKey(document)
    if not key then return false, "Character information is unavailable" end
    local saved
    saved, errorText = Macros.Native.Publish(document, body, Binding(data, document), replace)
    if not saved then return false, errorText end
    saved.document = Copy(document)
    data.bindings[key] = data.bindings[key] or {}
    data.bindings[key][id] = saved
    if notify then Changed() end
    return true, nil, saved.index
end

function Store.Publish(id, replace)
    return Publish(id, replace, true)
end

function Store.Pickup(id)
    if NS.InCombat() then return false, "Macro changes are unavailable in combat" end
    local data = Database(false)
    local document = data and data.documents[id]
    if not document then return false, "The macro draft is no longer available" end
    return Macros.Native.Pickup(Binding(data, document))
end

local function IsManaged(binding)
    local published = binding.document
    return type(published) == "table" and published.mode == "consumable"
        and type(published.consumable) == "table" and published.consumable.managed == true
end

-- Installed recipes own their storage scope. A draft can change scope or mode
-- without moving, disabling or otherwise changing the last published recipe.
local function VisitBindings(callback)
    local data = Database(false)
    if not data then return false end
    local character = Macros.Native.Character()
    for key, bindings in pairs(data.bindings) do
        if (key == "account" or key == character) and type(bindings) == "table" then
            for id, binding in pairs(bindings) do
                if data.documents[id] and type(binding) == "table" and IsManaged(binding) then
                    if callback(binding, bindings, id) then return true end
                end
            end
        end
    end
    return false
end

function Store.HasManaged()
    return VisitBindings(IsManaged)
end

local function RefreshBinding(binding, bindings, id)
    local published = binding.document
    local body, errorText = Store.Preview(published)
    local saved, nativeError
    if body then saved, nativeError = Macros.Native.Publish(published, body, binding, true) end
    if saved then
        saved.document = published
        bindings[id] = saved
    end
    Store.status = Store.status or {}
    Store.status[id] = not saved and (errorText or nativeError) or nil
end

function Store.RefreshManaged()
    if not NS.InCombat() then VisitBindings(RefreshBinding) end
end

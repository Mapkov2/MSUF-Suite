-- Offline catalog extraction. Errors abort the inventory; no partial snapshots.
local root, client = arg[1], arg[2]
local function permissive(name)
    return setmetatable({}, {
        __index = function(_, key) return permissive(name .. "." .. tostring(key)) end,
        __call = function() return nil end,
    })
end
setmetatable(_G, { __index = function(_, key) return permissive(key) end })
UnitClass = function() return "Warrior", "WARRIOR" end
C_ClassColor = { GetClassColor = function() return { r = 1, g = .5, b = .2 } end }
local ns = { Client = { isForever = client == "forever", isRetail = client == "retail" },
    Text = function(text) return text end, Defaults = {} }
setmetatable(ns, { __index = function(_, key) return permissive("NS." .. key) end })
local handle = assert(io.open(root .. "/MSUF_Suite/MSUF_Suite_Mainline.toc", "rb"))
local toc = handle:read("*a")
handle:close()
local started, finished = false, false
for line in toc:gmatch("[^\r\n]+") do
    local file = line:match("^(Core\\[%w_\\]+%.lua)$")
    if file then
        if file == "Core\\SuiteCatalog.lua" then started = true end
        if started then
            if file == "Core\\Suite.lua" then finished = true break end
            assert(loadfile(root .. "/MSUF_Suite/" .. file:gsub("\\", "/")))("MSUF_Suite", ns)
        end
    end
end
assert(started and finished, "catalog boundaries missing from TOC")
assert(type(rawget(ns, "FinalizeCatalog")) == "function", "missing catalog finalizer")
ns.FinalizeCatalog()

local function encode(value)
    local kind = type(value)
    if kind == "nil" then return "null" end
    if kind == "boolean" then return tostring(value) end
    if kind == "number" then
        -- JSON has no NaN or infinity; keep them distinguishable as text.
        if value ~= value or value == math.huge or value == -math.huge then return '"' .. tostring(value) .. '"' end
        return tostring(value)
    end
    if kind == "string" then
        return '"' .. value:gsub('[%z\1-\31\\"]', function(ch)
            if ch == '"' or ch == "\\" then return "\\" .. ch end
            return string.format("\\u%04x", string.byte(ch))
        end) .. '"'
    end
    assert(kind == "table" and getmetatable(value) == nil, "unsupported catalog value " .. kind)
    local entries = {}
    for i = 1, #value do entries[i] = encode(value[i]) end
    return "[" .. table.concat(entries, ",") .. "]"
end
local function emit(category, ...)
    print(encode({ category, ... }))
end

-- Behavior links that have no label of their own (what enables a control,
-- what hides it, which CVars and edit elements a module owns). Tables become
-- sorted key/value pair lists so the snapshot never depends on pairs() order.
local TYPE_ORDER = { number = 1, string = 2, boolean = 3 }
local function sortedKeys(value)
    local keys = {}
    for key in pairs(value) do keys[#keys + 1] = key end
    table.sort(keys, function(a, b)
        local ta, tb = TYPE_ORDER[type(a)] or 9, TYPE_ORDER[type(b)] or 9
        if ta ~= tb then return ta < tb end
        if ta == 3 then return tostring(a) < tostring(b) end
        return a < b
    end)
    return keys
end
local function canon(value, depth)
    local kind = type(value)
    if kind == "string" or kind == "number" or kind == "boolean" then return value end
    if kind ~= "table" then return "<" .. kind .. ">" end
    if getmetatable(value) ~= nil then return "<stub>" end
    if depth > 6 then return "<deep>" end
    local pairsList = {}
    for i, key in ipairs(sortedKeys(value)) do pairsList[i] = { key, canon(value[key], depth + 1) } end
    return pairsList
end
local SPEC_TRAITS = { "automation", "conflicts", "core", "cvars", "defaultEnabled", "description", "editElement",
    "optIn", "personalExport" }
local RULE_TRAITS = { "automation", "bar", "category", "choiceIcons", "defaultLabel", "disabledBy", "enableKey", "ids",
    "infoField", "infoTooltip", "items", "personal", "previewOnly", "requires", "requiresChoice", "slot", "spells",
    "suffix", "window" }
local function emitTraits(category, owner, source, fields)
    for _, field in ipairs(fields) do
        if source[field] ~= nil then emit(category, owner, field, canon(source[field], 0)) end
    end
end
-- A look carries the presets a player can pick, one row each.
local function emitLook(owner, look)
    if type(look) ~= "table" or getmetatable(look) ~= nil then return end
    for _, field in ipairs(sortedKeys(look)) do
        local value = look[field]
        if field == "presets" and type(value) == "table" and getmetatable(value) == nil then
            for _, index in ipairs(sortedKeys(value)) do
                emit("module_traits", owner, "look.presets." .. tostring(index), canon(value[index], 0))
            end
        else
            emit("module_traits", owner, "look." .. tostring(field), canon(value, 0))
        end
    end
end
local catalog, order = rawget(ns, "SuiteCatalog"), rawget(ns, "SuiteOrder")
assert(type(catalog) == "table" and #order > 0, "empty catalog")
for _, id in ipairs(order) do
    local spec = catalog[id]
    emit("modules", client .. ":" .. id)
    emit("labels", client .. ":" .. id, spec.title)
    emit("module_metadata", client .. ":" .. id, spec.page or "", spec.addon)
    emitTraits("module_traits", client .. ":" .. id, spec, SPEC_TRAITS)
    emitLook(client .. ":" .. id, spec.look)
    for _, rule in ipairs(spec.controls) do
        local key = client .. ":" .. id .. "." .. rule.key
        emit("rules", key)
        emit("defaults", key, type(rule.default), rule.default)
        emit("labels", key, rule.label or "")
        if rule.section then emit("sections", key, rule.section, rule.sectionTitle or "") end
        for index, choice in ipairs(rule.choices or {}) do emit("choices", key, index, choice) end
        local kind = rule.choices and "choice" or rule.color and "color" or rule.font and "font"
            or rule.texture and "texture" or type(rule.default)
        emit("rule_metadata", key, kind, rule.hidden == true, rule.min or "", rule.max or "",
            rule.step or "", rule.maxLength or "")
        emitTraits("rule_traits", key, rule, RULE_TRAITS)
    end
end
for key, value in pairs(_G) do
    if key:match("^BINDING_NAME_") or key:match("^BINDING_HEADER_") then
        emit("bindings", key)
        emit("labels", key, value)
    end
end
emit("constants", "ActionBarCount", ns.ActionBarCount)
emit("constants", "DataTextBarLimit", ns.DataTextBarLimit)
emit("constants", "DamageMeterMaxWindows", ns.DamageMeterMaxWindows)
local slots = {}
for i, slot in ipairs(ns.CDM.SLOTS) do slots[i] = slot.key end
emit("constants", "CDMSlots", slots)

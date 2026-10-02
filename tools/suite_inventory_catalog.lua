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
    if kind == "boolean" or kind == "number" then return tostring(value) end
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
local catalog, order = rawget(ns, "SuiteCatalog"), rawget(ns, "SuiteOrder")
assert(type(catalog) == "table" and #order > 0, "empty catalog")
for _, id in ipairs(order) do
    local spec = catalog[id]
    emit("modules", client .. ":" .. id)
    emit("labels", client .. ":" .. id, spec.title)
    emit("module_metadata", client .. ":" .. id, spec.page or "", spec.addon)
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

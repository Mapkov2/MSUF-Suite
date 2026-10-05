-- Cooldown manager "Copy to all specializations" (one entry, or a bar's whole
-- list) through the real catalog, list codec and list editing
-- (MSUF_Suite_Options/Pages/CooldownManagerLists.lua). A specialization whose
-- target bar is full keeps the entry where it already is: one home per entry
-- is kept by moving it, never by dropping it.
local root = assert(arg[1], "repository root required")
local function Copy(value)
    if type(value) ~= "table" then return value end
    local result = {}
    for key, item in pairs(value) do result[key] = Copy(item) end
    return result
end
-- MSUF's codec: a stored table comes back as an independent copy.
local blobs = {}
MSUF_EncodeCompactTable = function(value)
    blobs[#blobs + 1] = Copy(value)
    return "MSUF3:" .. #blobs
end
MSUF_TryDecodeCompactString = function(text) return Copy(blobs[tonumber(text:match("^MSUF3:(%d+)$"))]) end
UnitClass = function() return "Mage", "MAGE" end
C_ClassColor = { GetClassColor = function() return nil end }
-- Three specializations (SpecializationInfoDocumentation: index -> specId).
local specs = { 62, 63, 64 }
GetNumSpecializations = function() return #specs end
C_SpecializationInfo = {
    GetSpecialization = function() return 1 end,
    GetSpecializationInfo = function(index) return specs[index], "Mage spec", nil, 134400 end,
}
local Suite = { Client = { isForever = false, modernEquipment = true }, Defaults = {},
    Text = function(value) return value end, Public = function() return true end }
local function Load(file, namespace) return assert(loadfile(root .. "/" .. file))("MSUF_Suite", namespace) end
Load("MSUF_Suite/Core/SuiteCatalog.lua", Suite)
Load("MSUF_Suite/Core/Catalog/DataTexts.lua", Suite)
Load("MSUF_Suite/Core/Catalog/CooldownManager.lua", Suite)
local CDM = Suite.CDM
local config = {}
for key, rule in pairs(Suite.SuiteCatalog.cooldownManager.rules) do config[key] = rule.default end
local P = { Suite = Suite, S = { CooldownManagerBarEntries = function() return {} end }, T = {}, Gates = {},
    SearchPreparers = {}, Tr = function(value) return value end, catalog = Suite.SuiteCatalog,
    Combat = function() return false end, WithHistory = function(_, _, callback) return callback() end }
P.Get = function(id, key) assert(id == "cooldownManager"); return config[key] end
P.Set = function(id, key, value) assert(id == "cooldownManager"); config[key] = value; return true end
P.SetMany = function(id, values)
    for key, value in pairs(values) do P.Set(id, key, value) end
    return true
end
Load("MSUF_Suite_Options/Pages/CooldownManagerData.lua", P)
Load("MSUF_Suite_Options/Pages/CooldownManagerLists.lua", P)
local Page, key = P.CDMPage, "s1953"
assert(CDM.ValidEntryKey(key))

local function Contains(list, wanted)
    for _, value in ipairs(list or {}) do if value == wanted then return true end end
    return false
end
-- Arcane's custom bar 1 holds the entry. Fire's bar 1 is full and Fire has
-- the entry on bar 2; Frost's bar 1 has room.
for _, copy in ipairs({
    { "one entry", function() return Page.CopyToSpecs("c1", key) end },
    { "the whole list", function() return Page.CopyListToSpecs("c1") end },
}) do
    local full = {}
    for i = 1, CDM.LIMITS.entries do full[i] = "s" .. (100000 + i) end
    config.listsData = assert(CDM.Codec.EncodeLists({ v = 1,
        specs = { [62] = { c1 = { key } }, [63] = { c1 = full, c2 = { key } } }, hidden = {}, replace = {}, shared = {} }))
    local ok, copied = copy[2]()
    assert(ok and copied == 1, copy[1] .. ": the copy reported " .. tostring(copied))
    local saved = CDM.Codec.DecodeLists(config.listsData)
    assert(Contains(saved.specs[64].c1, key), copy[1] .. ": Frost did not get the entry")
    assert(not Contains(saved.specs[63].c1, key) and #saved.specs[63].c1 == CDM.LIMITS.entries,
        copy[1] .. ": Fire's full bar changed")
    assert(Contains(saved.specs[63].c2, key), copy[1] .. ": Fire lost the entry from its other bar")
end
print("cooldown manager copy to specializations contract: ok")

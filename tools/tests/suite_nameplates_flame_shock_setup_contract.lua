local root = assert(arg[1])
local D
local spec, class, combat = 1489, "SHAMAN", false
local initial = { [1489] = {}, [62] = { { id = 99, enabled = false } } }
local data, changed
local function Read()
    local copy = {}
    for id, rows in pairs(data or initial) do
        copy[id] = {}
        for i, row in ipairs(rows) do
            copy[id][i] = { id = row.id, ids = row.ids and { unpack(row.ids) } or nil, enabled = row.enabled, color = row.color }
        end
    end
    return copy
end
function UnitClass() return class, class end
local P = {
    Suite = { Client = { isForever = true }, Registry = { AddListener = function() end }, Public = function() return true end,
        HostBridge = { ForeverAuraAliases = function(id) assert(id == 8050); return { 8050, 8052, 8053 } end },
        NameplateAuraColors = {
        Spec = function() return spec end, Decode = Read, Encode = function(v) return v end, LIMIT = 6, DEFAULT_COLOR = "123456",
    } },
    Get = function(_, key) if key == "auraColorsData" then return data or "" end end,
    SetMany = function(id, values)
        assert(id == "nameplates")
        changed, data = values, values.auraColorsData
        return true
    end,
    Combat = function() return combat end,
}
assert(loadfile(root .. "/MSUF_Suite_Options/Pages/NameplatesAuraDraft.lua"))("Options", P)
D = P.NameplatesAuraDraft
assert(D.ShowsFlameShockSetup() and D.TrackFlameShock())
assert(changed.auraColorsEnabled and changed.auraColorsNoneEnabled)
assert(#data[spec] == 1 and data[spec][1].id == 8050 and #data[62] == 1)
assert(table.concat(data[spec][1].ids, ",") == "8050,8052,8053")
data[spec][1].color = "abcdef"
data[spec][2] = { id = 123, enabled = true }
assert(D.TrackFlameShock())
assert(#data[spec] == 2 and data[spec][1].color == "abcdef" and changed.auraColorsNoneEnabled == nil)
local previous = data
D.selected = 62
assert(not D.TrackFlameShock() and data == previous)
D.selected, combat = spec, true
assert(not D.TrackFlameShock() and data == previous)
combat, class = false, "WARRIOR"
assert(not D.TrackFlameShock() and data == previous)
print("suite_nameplates_flame_shock_setup_contract: OK")

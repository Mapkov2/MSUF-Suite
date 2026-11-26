local root = assert(arg[1])
local function Finite(value)
    return type(value) == "number" and value == value and math.abs(value) < math.huge
end
local combat, decode
local tag = 23
local catalog = {
    records = {
        [10] = { key = "c10", defaultCategory = 0 },
        [11] = { key = "c11", defaultCategory = 1 },
        [12] = { key = "c12", defaultCategory = -1 },
    },
    defaultOrderIDs = { 10, 11, 12 }, BAR_OF = { [0] = "ess", [1] = "uti" },
    pass = {}, specTag = 23,
    Ready = function() return true end,
    SpecTag = function() return tag end,
    DecodeBlizzardLayoutData = function(_, maximum)
        assert(maximum < 100000)
        if decode == "bad" then error("invalid CBOR") end
        return decode
    end,
    ReadActiveLayout = function(data, spec)
        assert(spec == tag)
        return data[spec]
    end,
    IsImportCategory = function(category) return category >= 0 and category <= 2 end,
}
catalog.Rebuild = function() catalog.specTag = tag end
local suite = {
    Finite = Finite, PublicText = function(value) return type(value) == "string" and value or nil end,
    Dispatch = function(fn, ...)
        local ok, completed, value = pcall(fn, ...)
        if ok then return completed, value end
    end,
}
local ns = { InCombat = function() return combat end, Finish = function(fn, ...) return true, fn(...) end }
local private = { NS = ns, Suite = suite, CDM = { Catalog = catalog, Cold = function() end, EMPTY = {} } }
assert(loadfile(root .. "/MSUF_Suite_CooldownManager/CatalogImport.lua"))("CDM", private)
local import = suite.CooldownManagerReadBlizzardString
local input = " 1|uGE= "
decode = { [23] = { { 11, 10, 12 }, { [0] = { 11, 12 }, [2] = { 10 } } } }
local bars, reason, count = import(input)
assert(not reason and count == 2 and table.concat(bars.ess, ",") == "c11,c12")
assert(#bars.uti == 0 and catalog.records[10].defaultCategory == 0, "paste mutated the current catalog")
decode[23][2][1] = { 12 }
assert(not import(input), "a duplicate move was accepted")
decode[23][2] = { [0] = { [1] = 11, [3] = 12 } }
assert(not import(input), "a sparse category was accepted")
decode[23][2] = { [88] = { 11 } }
assert(not import(input), "an unknown category was accepted")
decode = "bad"
assert(not import(input), "malformed CBOR reached the caller")
assert(not import("1|abcd:raw") and not import(string.rep("a", 16385)))
decode = { [23] = { { 11 } } }
tag = 24
assert(not import(input), "another specialization was used as a fallback")
tag, combat = 23, true
assert(not import(input), "paste ran during a combat edge")
print("Native layout paste validated")

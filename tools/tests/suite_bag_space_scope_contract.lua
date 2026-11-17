local root = assert(arg[1])
local now, reads, families = 0, {}, {}
GetTime = function() return now end
local NS = { Client = {} }
local S = {
    Dispatch = function(callback, ...) return callback(...) end,
    Finite = function(value) return type(value) == "number" end,
    Public = function() return true end,
}
NUM_BAG_SLOTS = 4
C_Container = {
    GetContainerNumSlots = function(bag)
        reads[#reads + 1] = bag
        return bag == 5 and 36 or 16
    end,
    GetContainerNumFreeSlots = function(bag) return bag == 5 and 20 or 3, families[bag] end,
}
assert(loadfile(root .. "/MSUF_Suite_Modules/DataSources.lua"))("MSUF_Suite_Modules", { Suite = S, NS = NS })
NUM_TOTAL_EQUIPPED_BAG_SLOTS = 5
local free, total = S.ReadInfoSource("bags")
assert(free == 35 and total == 116 and #reads == 6 and reads[6] == 5, "Retail reagent bag omitted")
NUM_TOTAL_EQUIPPED_BAG_SLOTS, now, reads = 4, 1, {}
free, total = S.ReadInfoSource("bags")
assert(free == 15 and total == 80 and #reads == 5, "Forever queried a nonexistent reagent slot")
NUM_TOTAL_EQUIPPED_BAG_SLOTS, now, reads = nil, 2, {}
free, total = S.ReadInfoSource("bags")
assert(free == 15 and total == 80 and #reads == 5, "legacy native bag count fallback changed")
NS.Client.isForever = true
NUM_TOTAL_EQUIPPED_BAG_SLOTS, now, reads = 5, 3, {}
families[2], families[5] = 32, 4
free, total = S.ReadInfoSource("bags")
assert(free == 12 and total == 64 and #reads == 6, "Forever counted herb or soul slots as general bag space")
families[2], families[5], now, reads = 0, 0, 4, {}
free, total = S.ReadInfoSource("bags")
assert(free == 35 and total == 116, "an unrestricted Forever slot was excluded")
print("Bag space: native equipped slots, Retail reagent bag and Forever totals passed")

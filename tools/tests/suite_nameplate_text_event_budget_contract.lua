local root = assert(arg[1])
local writes, reads = {}, {}
local function Count(counts, key) counts[key] = (counts[key] or 0) + 1 end
local function Label(id)
    return {
        SetText = function(_, value) Count(writes, id); writes.value = value end,
        SetFormattedText = function() Count(writes, id) end,
        Show = function() Count(writes, "shown") end,
        SetShown = function() Count(writes, "shown") end,
        Hide = function() end, ClearAllPoints = function() end, SetTextColor = function() end,
    }
end
UnitPower = function() Count(reads, "power"); return 77 end
UnitPowerMax = function() return 100 end
UnitGetTotalAbsorbs = function() Count(reads, "absorb"); return 80 end
UnitExists = function() return true end
UnitName = function() Count(reads, "name"); return "A target" end
UnitDetailedThreatSituation = function() Count(reads, "threat"); return false, nil, 37, nil, 50 end
C_Secrets = { ShouldUnitIdentityBeSecret = function() return false end }
GetGuildInfo = function() Count(reads, "guild"); return "A guild" end
local NS = { IsSecret = function() return false end, NameplateExtensions = { NPCTitleSource = 5, TextPoints = {
    [1] = { "CENTER", "health", "CENTER", 0, 0 },
} } }
local function Nop() end
local P = { NS = NS, Suite = { Finite = function(value) return type(value) == "number" end,
    SetFont = Nop, RGB = Nop }, Geometry = { Point = Nop }, Text = { styles = { enemy = { font = "font" } } } }
assert(loadfile(root .. "/MSUF_Suite_Nameplates/ExtensionText.lua"))("Nameplates", P)
local text = P.ExtensionText
local shape = { sources = {}, slots = {} }
local state = { unit = "nameplate1", interaction = shape, prefix = "enemy", labels = {} }
for _, source in ipairs({ 2, 4, 6, 8, 9 }) do
    shape.sources[source], state.labels[source] = true, Label(source)
    shape.slots[#shape.slots + 1] = { source = source, anchor = 1, x = 0, y = 0 }
end
if text.Configure then text.Configure({ enemy = shape }) end
text.Apply(state)
for _, source in ipairs({ 2, 4, 6, 8, 9 }) do assert(writes[source] == 1, "first event must bind every slot") end
writes, reads = {}, {}
for _ = 1, 100 do text.Apply(state, "UNIT_POWER_UPDATE") end
assert(writes[8] == 100 and writes.shown == 100 and reads.power == 100)
assert(writes[2] == nil and writes[4] == nil and writes[6] == nil and writes[9] == nil and reads.absorb == nil)
writes, reads = {}, {}
text.Apply(state, "UNIT_TARGET")
assert(writes[2] == 1 and writes[6] == 1 and writes.shown == 2 and reads.name == 1 and reads.threat == 1)
writes, reads = {}, {}
state.metadataReady = nil
text.Apply(state, "UNIT_NAME_UPDATE")
assert(writes[2] == 1 and writes[4] == 1 and writes.shown == 2 and reads.name == 1 and reads.guild == 1)
text.Invalidate(state)
writes = {}
text.Apply(state, "UNIT_ABSORB_AMOUNT_CHANGED")
assert(writes.shown == 5, "a rebind must repaint with fresh values")
print("Nameplate power work: 100 text sinks and 100 visibility writes for 100 events")

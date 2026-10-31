-- F02 through actual CDM events, spec layout persistence and Suite SetMany.
local root = assert(arg[1])
local file = assert(io.open(root .. "/tools/tests/suite_cooldown_manager_contract.lua", "rb"))
local source = file:read("*a"); file:close()
source = source:sub(1, assert(source:find("------------------------------------------------------------------ enable: capture", 1, true)) - 1)
local checks = [=[
assert(loadfile(root .. "/MSUF_Suite/Core/ProfileVariants.lua"))("MSUF_Suite", Suite)
local config = S.Config(ID)
module.config, module.context = config, S.NewContext(ID)
C_AddOns = { DoesAddOnExist = function() return true end, GetAddOnEnableState = function() return 2 end,
    IsAddOnLoaded = function(name) return name == "MSUF_Suite" or name == "MSUF_Suite_Modules" or name == ADDON end }
UnitGUID = function() return "Player-1-1" end
S.started = true
assert(S.Set(ID, "enabled", true))
S.Apply(ID)
local function Settle() Run(); Run() end
local function Spec(index)
    specIndex = index
    assert(Fire("ACTIVE_PLAYER_SPECIALIZATION_CHANGED"))
    Settle()
end
Settle()
local options = { Suite = Suite, S = S, T = {}, M = {}, W = {}, catalog = Suite.SuiteCatalog,
    Gates = {}, SearchPreparers = {}, Tr = function(text) return text end,
    Combat = function() return false end, Refresh = function() end,
    WithHistory = function(_, _, callback) return callback() end }
options.Get = function(id, key) return S.Config(id)[key] end
options.SetMany, options.Set = S.SetMany, S.Set
for _, name in ipairs({ "CooldownManagerData", "CooldownManagerLists", "CooldownManagerBars" }) do
    assert(loadfile(root .. "/MSUF_Suite_Options/Pages/" .. name .. ".lua"))("MSUF_Suite_Options", options)
end
local Page = options.CDMPage
Page.CommitFocus, Page.ClosePopups = function() end, function() end
assert(S.SetMany(ID, { c1_on = true, c1_name = "Previous", c1_x = 913, c1_y = 117, c1_size = 72,
    c2_x = 312, c2_y = 34 }))
Settle()
Spec(1)
assert(S.SetMany(ID, { c1_x = 0, c1_y = 0, c1_size = 36 }))
Settle()
local before = config.positionsData
assert(Codec.DecodePositions(before).specs[63].c1.x == 913)
assert(Page.DeleteBar("c1"))
Settle()
local cleaned = Codec.DecodePositions(config.positionsData)
assert(not cleaned.specs[63].c1 and cleaned.specs[63].c2.x == 312,
    "F02: runtime deletion must clear only the slot's saved layouts")
assert(Page.AddBar(1) and Page.selected == "c1")
Settle()
local freshX, freshY = config.c1_x, config.c1_y
Spec(2)
assert(config.c1_x == freshX and config.c1_y == freshY and config.c1_size == 36,
    "F02: a real specialization event revived deleted geometry")
Spec(1)
-- The existing stale-Undo guard deliberately rejects layout writes after a
-- spec switch. A separate deletion Undo restores its entire layout snapshot.
assert(S.SetMany(ID, { positionsData = before, c1_name = "Previous" }))
Settle()
assert(Page.DeleteBar("c1") and Page.undo)
Settle()
Page.RunUndo()
Settle()
assert(config.positionsData == before and config.c1_name == "Previous",
    "F02: Undo did not restore the other specialization's saved geometry")
Spec(2)
assert(config.c1_x == 913 and config.c1_y == 117 and config.c1_size == 72,
    "F02: restored layout did not return on a real specialization event")
-- An older build deleted a bar but left its layouts: off and unnamed, the
-- slot is "fresh", yet a new bar there must not recover them in another spec.
Spec(1)
assert(S.SetMany(ID, { c1_on = false, c1_name = "", positionsData = before }))
Settle()
assert(Page.AddBar(1) and Page.selected == "c1")
Settle()
assert(not Codec.DecodePositions(config.positionsData).specs[63].c1,
    "F02: a fresh slot kept the layouts an older build left behind")
local legacyX, legacyY = config.c1_x, config.c1_y
Spec(2)
assert(config.c1_x == legacyX and config.c1_y == legacyY,
    "F02: a new bar jumped to an old bar's geometry after a specialization switch")
module.active = false
module:Disable()
module.context:Release()
Run(5)
print("PKG2 F02 PASS: delete, reuse, real spec round trip and Undo restoring saved layouts")
]=]
assert(loadstring(source .. "\n" .. checks, "@cdm-runtime-layout-world"))()

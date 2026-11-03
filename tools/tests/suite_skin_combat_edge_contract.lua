-- Use the real shared combat accessor: native lockdown lags the entry event.
local root = assert(arg[1])
local locked, affecting, checks = false, false, 0
local callbacks, frames = 0, 0
MSUF_NS = { Client = { Flavor = "Mainline", IsForever = arg[2] == "Forever" }, LOCALE = "enUS" }
MSUFSuite = {}
InCombatLockdown = function() return locked end
UnitAffectingCombat = function(unit) assert(unit == "player"); return affecting end
CreateFrame = function() frames = frames + 1; error("combat accessor created a driver") end
C_Timer = { After = function() callbacks = callbacks + 1; error("combat accessor scheduled work") end }
securecallfunction = function(callback, ...) return callback(...) end
assert(loadfile(root .. "/MSUF_Suite/Core/Platform.lua"))("MSUF_Suite", MSUFSuite)
local NS = {}
assert(loadfile(root .. "/MSUF_Suite_Skin/Core/Bootstrap.lua"))("MSUF_Suite_Skin", NS)
local function Check(value, message) assert(value, message); checks = checks + 1 end
Check(not NS.IsCombatLocked(), "idle was marked combat")
Check(NS.IsCombatLocked("PLAYER_REGEN_DISABLED"), "entry event missed before lockdown")
affecting = true
Check(NS.IsCombatLocked(), "nested entry callback missed player's combat flag")
locked = true
Check(NS.IsCombatLocked(), "active lockdown was missed")
Check(not NS.IsCombatLocked("PLAYER_REGEN_ENABLED"), "exit event retained stale lockdown")
locked, affecting = false, false
Check(not NS.IsCombatLocked(), "combat state stuck after exit")
for index = 1, 1000 do NS.IsCombatLocked() end
Check(frames == 0 and callbacks == 0, "combat accessor added idle work")
print("Suite skin combat edge: " .. checks .. " checks passed (" .. (arg[2] or "Mainline") .. ")")

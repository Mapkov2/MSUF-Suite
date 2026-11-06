-- Runtime startup may follow the session's first PLAYER_ENTERING_WORLD.
local root = assert(arg[1])
MSUF_DM_FEATURE_TESTS = true
dofile(root .. "/tools/tests/suite_damage_meter_contract.lua")
local f = assert(MSUF_DM_FIXTURE)
local D, S, NS, M = f.D, f.S, f.NS, f.M
local TYPE = D.TYPE
C_SpecializationInfo = {
    GetSpecialization = function() return 1 end,
    GetSpecializationInfo = function() return 1, "Spec", "", 0, "HEALER" end,
}
C_ChallengeMode = { IsChallengeModeActive = function() return false end }
local function Enabled(on) assert(S.Set("damageMeter", "enabled", on)) end
Enabled(false)
assert(S.SetMany("damageMeter", { windowCount = 1, w1Type = TYPE.DamageDone + 1,
    w1RoleHealer = TYPE.HealingDone + 2, w1MythicType = 1 }))
NS.loginKind = "reload"
NS.startingModules = true
Enabled(true)
NS.startingModules = nil
f.RunAfters(0)
assert(D.windows[1].meterType == TYPE.DamageDone, "reload replaced the player's last meter pick")

Enabled(false)
NS.loginKind = "login"
Enabled(true)
f.RunAfters(0)
assert(D.windows[1].meterType == TYPE.DamageDone, "enabling later in a session overwrote that profile's pick")
Enabled(false)
NS.startingModules = true
Enabled(true)
NS.startingModules = nil
Enabled(false)
f.RunAfters(0)
assert(M.config.w1Type == TYPE.DamageDone + 1, "disabling before the login callback failed to cancel its writes")
Enabled(true)
assert(D.windows[1].meterType == TYPE.DamageDone, "a cancelled startup callback changed a later manual activation")
Enabled(false)
local enable, enableCalls = M.Enable, 0
M.Enable = function(self)
    enableCalls = enableCalls + 1
    return enable(self)
end
NS.startingModules = true
Enabled(true)
NS.startingModules = nil
assert(enableCalls == 1 and D.windows[1].meterType == TYPE.DamageDone,
    "login role selection re-entered Enable before activation completed")
f.RunAfters(0)
assert(enableCalls == 1, "applying login roles enabled the module a second time")
assert(D.windows[1].meterType == TYPE.HealingDone and M.config.w1Type == TYPE.HealingDone + 1,
    "late module startup lost the first world entry's role selection")
D.SetWindowType(D.windows[1], TYPE.Absorbs)
f.Event("PLAYER_ENTERING_WORLD", true, false)
assert(D.windows[1].meterType == TYPE.Absorbs, "a later world-entry delivery applied login roles twice")
Enabled(false)
Enabled(true)
f.RunAfters(0)
assert(D.windows[1].meterType == TYPE.Absorbs, "re-enabling in the same session overwrote a manual pick")
print("Damage meter late login: role applied once after missed world entry; reload and manual picks retained")

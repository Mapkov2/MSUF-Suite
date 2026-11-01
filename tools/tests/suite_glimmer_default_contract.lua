local root, flavor = assert(arg[1]), arg[2] or "Forever"
MSUF_NS = { Client = { Family="Mainline", Flavor="Mainline", IsRetail=true,
    IsForever=flavor=="Forever", SupportsEvent=function() return true end } }
SlashCmdList = {}
InCombatLockdown = function() return false end
securecallfunction = function(callback, ...) return callback(...) end
local Support = dofile(root .. "/tools/tests/suite_test_support.lua")
local Suite = Support.Load(root, "MSUF_Suite", {}, "Core/Suite.lua")
local S = Suite.Suite
local fresh={}
S.Normalize(fresh)
assert(fresh.suite.modules.glimmer.enabled == (flavor=="Forever"), "wrong fresh Glimmer default")
local previous={suite={schema=1,revision=S.MigrationRevision-1,modules={glimmer={enabled=false,style=5}}}}
S.Normalize(previous)
assert(previous.suite.modules.glimmer.enabled == (flavor=="Forever"), "old Forever Off not migrated")
assert(previous.suite.modules.glimmer.style==5, "migration reset the chosen look")
previous.suite.modules.glimmer.enabled=false
S.Normalize(previous)
assert(previous.suite.modules.glimmer.enabled==false, "normalization overwrote a later Off")
-- A profile normalized on Retail has not yet adopted the Forever default.
if flavor=="Mainline" then
    Suite.Client.isForever=true
    S.Normalize(fresh)
    assert(fresh.suite.modules.glimmer.enabled and fresh.suite.modules.glimmer.foreverDefaultApplied,
        "Retail-normalized profile skipped the Forever default")
    fresh.suite.modules.glimmer.enabled=false
    local imported=Suite.CopyValue(fresh)
    S.Normalize(imported)
    assert(imported.suite.modules.glimmer.enabled==false, "portable stamp did not preserve deliberate Off")
end
print("suite_glimmer_default_contract: ok " .. flavor)

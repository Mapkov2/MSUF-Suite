local root = assert(arg[1], "repository root required")
-- Cooldown bars mark the pandemic window on their icons' aura overlays
-- (owner request 2026-10-20, as Blizzard's Cooldown Manager does on its
-- items). The bar's switch rebuilds the overlays (their buttons get the
-- region when they are made); the region itself is checked against the
-- native aura button fakes in suite_cooldown_manager_auras_contract.lua.
-- Runs on the main cooldown manager contract's harness up to its first
-- activation.
dofile(root .. "/tools/tests/suite_bh3_state_support.lua").Run("suite_cooldown_manager_contract.lua", [=[
local CDM = Suite.CDM
local config = S.Config(ID)
module.config = config
module.context = S.NewContext(ID)
module.active = true
module:Enable()
Run()
for _, slot in ipairs(CDM.SLOTS) do
    local key = CDM.KEYS[slot.key].pandemic
    assert(key and S.catalog[ID].rules[key].default == true, slot.key .. " carries the pandemic switch, on by default")
end
assert(C.views.ess.pandemic == true and C.views.uti.pandemic == true, "cooldown bars read the switch")
-- A switch change on a cooldown bar syncs its overlays, on an aura bar its containers.
for _, slot in ipairs({ "ess", "def", "buf" }) do
    local key = CDM.KEYS[slot].pandemic
    C.Flush.Reset()
    config[key] = false
    C.Settings.ReadViews(config, false, false)
    assert(C.Flush.sync[slot] and C.views[slot].pandemic == false, slot .. ": the pandemic switch rebuilds the aura buttons")
    config[key] = true
    C.Settings.ReadViews(config, false, false)
end
C.Flush.Reset()
module.active = false; module:Disable(); module.context:Release(); Run(5)
print("suite_cdm_pandemic_overlay_contract: ok")
]=], "------------------------------------------------------------------ enable: capture")

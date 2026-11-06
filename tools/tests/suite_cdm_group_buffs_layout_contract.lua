local root = assert(arg[1])
dofile(root .. "/tools/tests/suite_bh3_state_support.lua").Run("suite_cooldown_manager_layout_contract.lua", [=[
do
    local view = {}
    for key, value in pairs(C.views.buf) do view[key] = value end
    view.keepSlots, view.showMissing, view.centerFirst = false, false, false
    local entries = { { unit = "group", ov = {} } }
    assert(L.FixedAuras(view, entries), "a group recipient needs its own fixed native cell")
    entries[1].unit = "player"
    assert(not L.FixedAuras(view, entries), "ordinary own buffs lost compact layout")
end
]=])
print("suite_cdm_group_buffs_layout_contract: ok")

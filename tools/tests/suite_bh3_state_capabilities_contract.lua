dofile(arg[1] .. "/tools/tests/suite_bh3_state_support.lua").Run("suite_profiles_contract.lua", [=[
BH3("S04-A1",function()
    local value=Suite.MinimapStyleTexture.PARCHMENT_SCROLL
    for _,key in ipairs({"styleColor","styleAlpha","styleScale","styleX","styleY","stylePlacement","styleBlend","styleRotation"}) do
        assert(Suite.SuiteCatalog.minimap.rules[key].requiresChoice.values[value],"S04-A1: parchment controls were disabled")
    end
end)
Suite.Client.isForever=true
Suite.Client.modernEquipment=false
for _,file in ipairs({"ActionBars","BuffReminders","DataTexts"}) do
    local names={ActionBars="actionbars",BuffReminders="buffReminders",DataTexts="dataTexts"}
    Suite.SuiteCatalog[names[file]]=nil
    assert(loadfile(root .. "/MSUF_Suite/Core/Catalog/" .. file .. ".lua"))("MSUF_Suite",Suite)
end
BH3("S12-A3",function()
    assert(Suite.SuiteCatalog.actionbars.rules.disableSkyridingPaging.hidden,"S12-A3: Forever offered nonexistent skyriding paging")
end)
BH3("CX8-03",function()
    assert(Suite.SuiteCatalog.buffReminders.rules.keystoneCover.hidden and Suite.SuiteCatalog.buffReminders.rules.keystoneMinutes.hidden,
        "CX8-03: Forever offered unsupported keystone controls")
end)
BH3("S04-A4",function()
    assert(Suite.SuiteCatalog.dataTexts.rules.itemLevelEquipped.hidden,"S04-A4: Forever offered unsupported item-level data")
end)
]=], "do\n    -- Saved before the minimap specialization step")

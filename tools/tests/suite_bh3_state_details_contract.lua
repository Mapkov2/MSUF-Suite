dofile(arg[1] .. "/tools/tests/suite_bh3_state_support.lua").Run("suite_character_wide_layout_contract.lua", [=[
NS.DB=NS.CopyValue(NS.Defaults)
local function Up(fn,key)
    for i=1,60 do local name,value=debug.getupvalue(fn,i);if not name then break end;if name==key then return value end end
    error("fixture: missing function "..key)
end
BH3("SV14-A1",function()
    NS.DB.characterDetails.enabled=false;NS.DB.characterDetails.view="modern"
    local enabled=Up(Details.Refresh,"Enabled")
    assert(not enabled({active=true,kind="inspect"}),"SV14-A1: Inspect details ignored the enabled toggle")
    assert(enabled({active=true,kind="character"}),"SV14-A1: inspect switch removed the separately selected character view")
end)
BH3("SV14-A2",function()
    NS.Client.modernEquipment=false
    local reloads=0;ReloadUI=function() reloads=reloads+1 end
    assert(not Details.SetView("list") and reloads==0,"SV14-A2: unsupported Forever view triggered a reload")
end)
]=], "-- The option setter reapplies")

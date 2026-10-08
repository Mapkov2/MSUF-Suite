dofile(arg[1] .. "/tools/tests/suite_bh3_state_support.lua").Run("suite_forever_character_contract.lua", [=[
BH3("S07-A2",function()
    character.width=646;ns.DB.theme.look="foreverGlass";assert(ns.CharacterPanel.Apply("blizzardWindows"))
    themeListener(nil,"profile",nil);NextFrame()
    assert(Parts(2).label.shown)
    ns.DB.theme.look="custom";themeListener(nil,"color","accent");NextFrame()
    assert(not Parts(2).label.shown and character.ModeTabs.points[1][3]=="TOPRIGHT",
        "S07-A2: color edit left Forever-owned tab geometry active after switching to Custom")
end)
]=])

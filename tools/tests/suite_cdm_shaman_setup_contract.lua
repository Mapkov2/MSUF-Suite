local root = assert(arg[1])
dofile(root .. "/tools/tests/suite_bh3_state_support.lua").Run("suite_cooldown_manager_options_contract.lua", [=[
do (function()
    P.Suite.Client.isForever = true
    UnitClass = function() return "Shaman", "SHAMAN", 7 end
    GetNumTotemSlots = function() return 4 end
    EARTH_TOTEM_SLOT, WATER_TOTEM_SLOT, AIR_TOTEM_SLOT = 2, 3, 4
    local accept, preview
    P.Confirm = function(_, text, callback) accept, preview = callback, text end
    local families = P.Suite.CDM.FAMILY
    S.CooldownManagerGroupKeys = function(plain, family, current)
        assert(not plain and current)
        if family == families.COOLDOWN then return { shamanCooldowns = { "b4", "s17364" } } end
        assert(family == families.AURA)
        return { shamanBuffs = { "a408505" }, shamanDebuffs = { "d8050" } }
    end
    S.CooldownManagerSlotLabel = function(key) return "Totem " .. key end
    local oldLists, oldSpells = P.Get(Page.ID, "listsData"), P.Get(Page.ID, "spellsData")
    Page.AddGroup("uti", { "b4" })
    oldLists, oldSpells = P.Get(Page.ID, "listsData"), P.Get(Page.ID, "spellsData")
    local preEssential, preUtility = Keys("ess"), Keys("uti")
    local oldMap, before = Page.SpellOverrides(), historyWrites
    Page.OpenShamanSetup()
    assert(accept and preview:find("Totem t3", 1, true), "setup must preview the new entries")
    assert(P.Get(Page.ID, "listsData") == oldLists and P.Get(Page.ID, "spellsData") == oldSpells,
        "opening or dismissing a preview writes settings")
    assert(not oldMap.e.t3, "preview mutated the decoded settings view")
    assert(Keys("ess") == preEssential and Keys("uti") == preUtility, "preview changes the bar")
    assert(historyWrites == before)
    assert(accept())
    assert(historyWrites == before + 1, "setup is one undoable edit")
    assert(Keys("ess"):find("s17364", 1, true) and Keys("uti"):find("b4", 1, true), "starter moved an existing spell")
    assert(Keys("uti"):find("t3", 1, true) and Page.SpellOverrides().e.t3.totemPulse)
    assert(Page.SpellOverrides().e.a408505.stackGlow == 5 and Keys("buf"):find("d8050", 1, true))
    Page.RunUndo()
    assert(P.Get(Page.ID, "listsData") == oldLists and P.Get(Page.ID, "spellsData") == oldSpells, "Undo restores both datasets")
    print("suite_cdm_shaman_setup_contract: OK")
end)() end
]=])

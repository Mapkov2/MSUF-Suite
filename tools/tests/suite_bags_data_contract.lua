-- Runtime data of the Bags module with the FULL Bags TOC loaded (client
-- model of suite_bags_harness.lua): what is kept, where, for whom and for
-- how long.
local root = assert(arg[1], "repository root required")
local H = dofile(root .. "/tools/tests/suite_bags_harness.lua")

---------------------------------------------------------------- sort direction
do
    local rootDB = {}
    local W = H.New(root, { rootDB = rootDB, config = { sortDirection = 2 } })
    W.sortRightToLeft = true
    W.Apply()
    assert(W.sortRightToLeft == false, "Fill from the top did not apply")
    -- /reload: a new UI session reads the same saved variables.
    W = H.New(root, { rootDB = rootDB, loginKind = "reload", config = { sortDirection = 2 } })
    W.sortRightToLeft = false
    W.Apply()
    assert(W.S.Set("bags", "sortDirection", 1))
    assert(W.sortRightToLeft == true, "Blizzard setting must restore the value from before the Suite, also after /reload")
    assert(rootDB.suiteBagSort == nil, "the restored record must be dropped")
    -- A module stop restores as well, per character.
    W = H.New(root, { rootDB = rootDB, config = { sortDirection = 3 } })
    W.sortRightToLeft = false
    W.Apply()
    assert(W.sortRightToLeft == true and rootDB.suiteBagSort["Player-1-0001"].before == false)
    W.guid = "Player-1-0002"
    W.S.Set("bags", "enabled", false)
    assert(W.sortRightToLeft == true and rootDB.suiteBagSort["Player-1-0001"],
        "another character must not restore this character's sort direction")
end

---------------------------------------------------------------- Suite windows
do
    local W = H.New(root)
    W.sizes[0] = 2
    W.Apply()
    W.OpenBags()
    W.Settle()
    W.P.InventoryEditor.Show()
    W.P.BagFinance.Show()
    for _, name in ipairs({ "MSUFSuiteBagCategories", "MSUFSuiteBagGoldHistory" }) do
        local frame, listed = _G[name], false
        for _, special in ipairs(UISpecialFrames) do if special == name then listed = true end end
        assert(frame and frame.shown and listed, name .. " must close with Escape (UISpecialFrames)")
        assert(frame:IsMovable() and frame.scripts.OnDragStart and frame.scripts.OnDragStop,
            name .. " must be movable by dragging")
    end
end

print("bag data: sort direction per character across /reload and Suite windows passed")

-- MSUF's profile lifecycle through the real Suite core
-- (suite_installer_harness.lua): the answers MSUF acts on. Classic MSUF
-- deletes a copy the Suite refuses (State/MSUF_Profiles.lua MSUF_CopyProfile).
local root = assert(arg[1], "repository root required")
local H = dofile(root .. "/tools/tests/suite_installer_harness.lua")

-- Without its store (corrupt SavedVariables refused at login) the Suite has
-- nothing to keep aligned, so no MSUF copy or rename is refused.
do
    local Suite = H.Setup({ root = root, forever = true })
    Suite.RootDB, Suite.DB = nil, nil
    for _, kind in ipairs({ "copy", "rename" }) do
        local ok, why = Suite.OnMSUFProfileLifecycle(kind, "Default", "Second")
        assert(ok == true, "MSUF's " .. kind .. " was refused without a Suite store: " .. tostring(why))
    end
    assert(#H.reported == 0, "a call raised: " .. tostring(H.reported[1]))
end

-- A module can use the shared context cleanup without a custom Disable.
do
    local Suite = H.Setup({ root = root, forever = true, addons = { MSUF_Suite_QualityOfLife = true } })
    local S, database = Suite.Suite, Suite.Database
    local runtime, hookRequests = {}, 0
    C_SpellBook = {}
    EventUtil = { ContinueOnAddOnLoaded = function(addon)
        assert(addon == "Blizzard_AuctionHouseUI")
        hookRequests = hookRequests + 1
    end }
    assert(loadfile(root .. "/MSUF_Suite_Modules/Runtime.lua"))("MSUF_Suite_Modules", runtime)
    assert(loadfile(root .. "/MSUF_Suite_Modules/EditMode.lua"))("MSUF_Suite_Modules", runtime)
    assert(loadfile(root .. "/MSUF_Suite_QualityOfLife/AuctionPriceTooltip.lua"))("MSUF_Suite_QualityOfLife", runtime)

    local id, off = "auctionPriceTooltip", "Tooltips off"
    for _, moduleID in ipairs(S.order) do S.Config(moduleID).enabled = false end
    assert(database.Create(off, true))
    MSUF_GlobalDB.profiles[off] = { general = {} }
    S.Config(id).enabled = true
    S.Start()
    assert(S.states[id].active and hookRequests == 1, "the first profile must start the price tooltip")
    assert(MSUF_SwitchProfile(off) and database.GetActiveProfileName() == off)
    assert(not S.states[id].active and not S.instances[id].active, "the new profile must stop the price tooltip")
    assert(#H.reported == 0, "switching profiles reported: " .. tostring(H.reported[1]))
    assert(MSUF_SwitchProfile("Default") and database.GetActiveProfileName() == "Default")
    assert(S.states[id].active and hookRequests == 1, "switching back must reuse the existing tooltip hook")
    assert(#H.reported == 0, "switching back reported: " .. tostring(H.reported[1]))
end

print("profile lifecycle contract: ok")

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

print("profile lifecycle contract: ok")

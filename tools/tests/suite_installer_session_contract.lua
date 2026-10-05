-- The installer across a session, through the real Suite core
-- (suite_installer_harness.lua): what an earlier session left behind in a
-- profile store or in the installer's own window.
local root = assert(arg[1], "repository root required")
local H = dofile(root .. "/tools/tests/suite_installer_harness.lua")

-- A skin profile can outlive its MSUF twin: a rename or delete while the skin
-- addon was disabled never reached the skin store. The factory install takes
-- the next free name instead of failing on every attempt.
do
    local stale = { enabled = true, stale = true }
    local skin = H.FakeSkin({ Default = { enabled = true }, ["MSUF Suite Forever"] = stale }, "Default")
    local Suite = H.Setup({ root = root, forever = true, addons = { MSUF_Suite_Skin = true } })
    assert(not MSUF_GlobalDB.profiles["MSUF Suite Forever"] and not Suite.Database.GetProfile("MSUF Suite Forever"))
    local frame = H.Install(Suite)
    assert(MSUF_ActiveProfile == "MSUF Suite Forever 2", "the install failed: " .. tostring(frame.status.text))
    assert(Suite.RootDB.installation.status == "complete", "the installation is still pending")
    assert(skin.Database.GetActiveProfileName() == "MSUF Suite Forever 2", "the new skin profile is not active")
    assert(skin.Database.GetProfile("MSUF Suite Forever") == stale, "the older skin profile was replaced")
    assert(#H.reported == 0, "a call raised: " .. tostring(H.reported[1]))
end

print("installer session contract: ok")

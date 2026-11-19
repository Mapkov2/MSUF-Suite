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

-- A compact Suite profile still owns its name even if its payload cannot
-- be decoded. Checking for an available name must not materialize it.
do
    MapkoSkin = nil
    local suite = H.Setup({ root = root, forever = true })
    local name, occupied = "MSUF Suite Forever", "MSUF3:invalid packed profile"
    local database = suite.Database
    suite.RootDB.profiles[name] = occupied
    local read = database.GetProfile
    database.GetProfile = function(target)
        assert(target ~= name, "setup decoded an inactive profile to allocate a name")
        return read(target)
    end
    local requested
    suite.SuiteProfiles.InstallFactory = function(target)
        requested = target
        return false, "test stops before profile install"
    end
    assert(suite.Installer.Open())
    local ok, reason = suite.Installer.Apply()
    assert(not ok and reason == "test stops before profile install" and requested == name .. " 2",
        "setup chose " .. tostring(requested) .. " for reserved name " .. name)
    assert(suite.RootDB.profiles[name] == occupied, "setup replaced an unreadable stored profile")
end

-- Setup reopened in the same session starts again at 100 percent: the slider
-- shows the scale the label shows and Install applies.
do
    local Suite = H.Setup({ root = root, forever = true })
    assert(Suite.Installer.Open())
    local f = _G.MSUFSuiteInstallFrame
    for _ = 1, 3 do f.next.scripts.OnClick() end
    f.scaleToggle.scripts.OnClick()
    f.presets[3].scripts.OnClick()
    assert(f.scaleSlider:GetValue() == 0.7 and f.scaleLabel:GetText() == "70%", "the Medium preset was not chosen")
    f.close.scripts.OnClick()
    assert(Suite.Installer.Open())
    for _ = 1, 3 do f.next.scripts.OnClick() end
    f.scaleToggle.scripts.OnClick()
    assert(f.scaleLabel:GetText() == "100%", "the reopened setup does not start at 100 percent")
    assert(f.scaleSlider:GetValue() == 1, "the slider still shows the previous session's "
        .. tostring(f.scaleSlider:GetValue()) .. " while the scale is 100 percent")
    f.next.scripts.OnClick()
    f.next.scripts.OnClick()
    local applied = H.appliedScales[#H.appliedScales]
    assert(applied and applied.global and applied.global.scale == 1, "Install applied another scale")
    assert(#H.reported == 0, "a call raised: " .. tostring(H.reported[1]))
end

-- /msufsuite in combat says why setup does not open.
do
    local Suite = H.Setup({ root = root, forever = true })
    H.combat = true
    SlashCmdList.MSUFSUITEINSTALL("")
    assert(not Suite.Installer.IsOpen(), "setup opened in combat")
    assert(H.chat[#H.chat] == "MSUF Suite: " .. Suite.Text("Finish combat first."),
        "/msufsuite in combat gave no feedback")
    H.combat = false
    SlashCmdList.MSUFSUITEINSTALL("")
    assert(Suite.Installer.IsOpen(), "setup did not open after combat")
end

print("installer session contract: ok")

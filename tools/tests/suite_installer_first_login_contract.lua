-- Actual host first-load lifecycle plus the real Suite installer window.
local root = assert(arg[1], "Suite root required")
local H = dofile(root .. "/tools/tests/suite_installer_harness.lua")
local checks = 0
local function Check(value, message)
    assert(value, message)
    checks = checks + 1
end

for _, host in ipairs({ "MidnightSimpleUnitFrames", "MidnightSimpleUnitFrames-7.0" }) do
    for _, forever in ipairs({ false, true }) do
        MSUF2, MSUF_UI, MSUF, MSUFSuiteInstallFrame = nil, nil, nil, nil
        local namespace = { Client = { Flavor = "Mainline", IsForever = forever,
            SupportsOnboardingScenes = not forever } }
        local suite = H.Setup({ root = root, forever = forever, msuf = namespace })
        -- The host settles clean SavedVariables before the dependent Suite.
        MSUF_GlobalDB, MSUF_DB, MSUF_ActiveProfile = nil, nil, nil
        local hostRoot = root .. "/../" .. host .. "/MidnightSimpleUnitFrames/"
        assert(loadfile(hostRoot .. "Kernel/MSUF_SuiteLink.lua"))("MidnightSimpleUnitFrames", namespace)
        assert(loadfile(hostRoot .. "State/MSUF_FirstLoad.lua"))("MidnightSimpleUnitFrames", namespace)
        local firstLoad = namespace.FirstLoad6
        Check(firstLoad:GetInstallKind() == "fresh", host .. ": fixture is not a fresh host")
        Check(firstLoad:IsFirstRunPending() == not forever, host .. ": wrong client onboarding policy")
        Check(suite.Host.build == "Classic", host .. ": modern host guard was bypassed")
        Check(suite.Installer.MaybeShow("login") == true,
            host .. ": unloaded Options prevented the automatic installer")
        Check(suite.Installer.IsOpen(), host .. ": real installer window did not open")
        Check(suite.RootDB.installation.status == "pending", "opening setup changed its receipt")
        Check(firstLoad:GetState().status == "pending", "Suite changed host onboarding state")
        Check(suite.Installer.MaybeShow("login") == false, "automatic setup opened twice")
        MSUFSuiteInstallFrame:Hide()

        MSUF2 = { frame = H.Widget("Frame") }
        MSUF2.frame:Hide()
        Check(suite.Installer.MaybeShow("login") == true,
            host .. ": loaded but hidden Options prevented automatic setup")
        MSUFSuiteInstallFrame:Hide()
        MSUF2.frame:Show()
        Check(suite.Installer.MaybeShow("login") == forever,
            host .. ": visible host onboarding lost its existing priority")
        if forever then MSUFSuiteInstallFrame:Hide() end
        if not forever then
            firstLoad:Start("guided_tour")
            Check(suite.Installer.MaybeShow("login") == false, "visible Quick Setup was interrupted")
            MSUF2.frame:Hide()
            Check(suite.Installer.MaybeShow("login") == true, "hidden Quick Setup blocked the installer")
            MSUFSuiteInstallFrame:Hide()
        end

        -- The host's explicit completion handoff still bypasses the login wait.
        MSUF2.frame:Show()
        Check(suite.Installer.MaybeShow() == true, "host handoff did not open the real installer")
        MSUFSuiteInstallFrame:Hide()
        MSUF2.frame:Hide()
        for _, status in ipairs({ "complete", "skipped" }) do
            suite.RootDB.installation = { revision = 3, status = status }
            Check(suite.Installer.MaybeShow("login") == false, status .. " installation reopened")
        end
        suite.RootDB.installation = nil
        Check(suite.Installer.MaybeShow("login") == true, "missing receipt did not recover setup")
        MSUFSuiteInstallFrame:Hide()
        suite.RootDB.installation = { revision = 3, status = "pending" }
        H.combat = true
        Check(suite.Installer.MaybeShow("login") == false, "setup opened during combat")
        H.combat = false
        Check(suite.Installer.MaybeShow("login") == true, "setup did not open after combat")
        Check(#H.reported == 0, "real installer raised: " .. tostring(H.reported[1]))
    end
end
print("Suite first login: " .. checks .. " checks passed across both hosts and clients")

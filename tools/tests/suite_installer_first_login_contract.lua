-- Actual host first-load lifecycle plus the real Suite installer window.
local root = assert(arg[1], "Suite root required")
local H = dofile(root .. "/tools/tests/suite_installer_harness.lua")
local checks = 0
local function Check(value, message)
    assert(value, message)
    checks = checks + 1
end

for _, host in ipairs({ "MidnightSimpleUnitFrames-7.0" }) do
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
            suite.Database.SetCharacterInstallationStatus(status)
            Check(suite.Installer.MaybeShow("login") == false, status .. " installation reopened")
        end
        suite.RootDB.installation = nil
        suite.RootDB.characterInstallations = nil
        Check(suite.Installer.MaybeShow("login") == true, "missing receipt did not recover setup")
        MSUFSuiteInstallFrame:Hide()
        suite.RootDB.installation = { revision = 3, status = "pending" }
        H.combat = true
        Check(suite.Installer.MaybeShow("login") == false, "setup opened during combat")
        H.combat = false
        Check(suite.Installer.MaybeShow("login") == true, "setup did not open after combat")
        MSUFSuiteInstallFrame:Hide()
        local coreOpens, fresh = 0, true
        namespace.HostAPI = { OpenUnitFrameSetup = function(freshOnly)
            coreOpens = coreOpens + 1
            return fresh or not freshOnly
        end }
        Check(suite.Installer.MaybeShow("login"), "fresh shared setup was refused")
        Check(coreOpens == 1 and not suite.Installer.IsOpen(), "Suite opened ahead of Core setup")
        fresh = false
        Check(suite.Installer.MaybeShow("login"), "configured Core did not open Suite setup")
        local window = MSUFSuiteInstallFrame
        Check(window:IsShown() and not window.back:IsShown(), "configured Core entered the shared continuation")
        for _ = 1, 3 do window.next.scripts.OnClick() end
        Check(window.keepFrames:IsShown() and window.keepFrames.caption:GetText():find(suite.Text("ON"), 1, true),
            "Suite first login must offer the full installer and default to keeping existing frames")
        window:Hide()
        Check(suite.Installer.Open(function() namespace.HostAPI.OpenUnitFrameSetup(false) end), "continuation failed to open")
        Check(window:IsShown() and window.back:IsShown(), "shared setup lost the return to Core")
        window.back.scripts.OnClick()
        Check(coreOpens == 3 and not window:IsShown(), "Back did not return to the shared setup")

        -- Opening an already loaded Core menu can succeed with no return value.
        -- The real host boundary must still claim the first-login handoff.
        firstLoad:Reset("fresh")
        namespace.Util = { InCombat = function() return false end }
        namespace.ExportPublic = function() end
        UnitAffectingCombat = function() return false end
        namespace.MSUF2 = { OpenUnitFrameSetup = function() coreOpens = coreOpens + 1 end }
        namespace.OpenOptionsFromLauncher = function(page, afterOpen)
            assert(page == "home")
            afterOpen()
        end
        assert(loadfile(hostRoot .. "Runtime/MSUF_HostAPI.lua"))("MidnightSimpleUnitFrames", namespace)
        Check(suite.Installer.MaybeShow("login"), "loaded Core could not claim the setup")
        Check(coreOpens == 4 and not window:IsShown(), "loaded Core opened both setups")

        Check(#H.reported == 0, "real installer raised: " .. tostring(H.reported[1]))
    end
end
print("Suite first login: " .. checks .. " checks passed across both hosts and clients")

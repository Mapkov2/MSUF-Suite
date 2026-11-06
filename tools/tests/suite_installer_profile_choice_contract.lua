local root = assert(arg[1], "Suite root required")
local H = dofile(root .. "/tools/tests/suite_installer_harness.lua")
local checks = 0
local function Check(value, message)
    assert(value, message)
    checks = checks + 1
end
local function Row(window, name)
    for _, row in ipairs(window.existingProfileRows) do
        if row:IsShown() and row.profileName == name then return row end
    end
    error("missing profile row: " .. name)
end

for _, forever in ipairs({ false, true }) do
    MapkoSkin = nil
    local skin = H.FakeSkin({ Default = { enabled = true }, Raid = { enabled = true, saved = "skin" } }, "Default")
    local suite = H.Setup({ root = root, forever = forever, addons = { MSUF_Suite_Skin = true } })
    local character = "Player-Choice"
    UnitGUID = function() return character end
    local DB, P, I = suite.Database, suite.SuiteProfiles, suite.Installer
    local receipt = { status = "complete", profile = "classic", frameProfileName = "Default" }
    suite.RootDB.installation = receipt
    suite.RootDB.characterInstallations = { ["Player-Other"] = "complete" }
    local function Add(name)
        MSUF_GlobalDB.profiles[name] = { general = {}, saved = name }
        suite.RootDB.profiles[name] = suite.CopyValue(suite.RootDB.profiles.Default)
        suite.RootDB.profiles[name].suite.modules.chat.enabled = false
    end
    Add("Raid")
    for index = 1, 12 do Add(("Profile %02d"):format(index)) end
    MSUF_GlobalDB.profiles["Frames only"] = { general = {} }
    suite.RootDB.profiles["Suite only"] = suite.CopyValue(suite.RootDB.profiles.Default)
    local preference, writes = "Raid", 0
    MSUF_GetDefaultProfileForNewCharacters = function() return preference end
    MSUF_SetDefaultProfileForNewCharacters = function(name) preference, writes = name, writes + 1; return true end
    Check(P.NewCharacterDefault() == nil and I.IsFirstRunPending(), "unapplied default suppressed setup")
    Check(MSUF_SwitchProfile("Raid"), "fixture cannot activate existing profile")
    Check(P.NewCharacterDefault() == "Raid" and not I.IsFirstRunPending(), "applied explicit default not recognized")
    Check(not I.MaybeShow("login") and DB.GetCharacterInstallationStatus() == "complete", "explicit default did not finish setup")
    Check(writes == 0 and suite.RootDB.installation == receipt, "explicit default changed account metadata")
    character = "Player-Unknown"
    local modules = suite.RootDB.profiles.Raid
    suite.RootDB.profiles.Raid = nil
    Check(P.NewCharacterDefault() == nil and I.IsFirstRunPending(), "missing Suite twin suppressed setup")
    suite.RootDB.profiles.Raid = modules
    local frames = MSUF_GlobalDB.profiles.Raid
    MSUF_GlobalDB.profiles.Raid = nil
    Check(P.NewCharacterDefault() == nil and I.IsFirstRunPending(), "missing frame profile suppressed setup")
    MSUF_GlobalDB.profiles.Raid = frames
    receipt.newCharacterProfileOwned, receipt.frameProfileName = true, "Raid"
    Check(P.NewCharacterDefault() == nil and I.IsFirstRunPending(), "old automatic Suite default counted as consent")
    Check(P.EnsureNewCharacterProfile() and preference == nil, "old automatic default was not retired")
    Check(I.Open(), "manual installer did not open")
    local window = MSUFSuiteInstallFrame
    Check(window.existingProfileButton:IsShown() and not window.existingProfiles:IsShown(), "welcome profile choice visibility")
    window.existingProfileButton.scripts.OnClick()
    Check(window.existingProfiles:IsShown() and window.existingProfiles:GetVerticalScrollRange() > 0,
        "existing profile list does not scroll")
    Check(not window.intro[1]:IsShown() and not window.next:IsShown(), "picker overlaps wizard controls")
    for _, row in ipairs(window.existingProfileRows) do
        Check(row.profileName ~= "Frames only" and row.profileName ~= "Suite only", "picker offered an incomplete profile")
        Check(row.caption:GetText() == suite.Text("Use profile: %s"):format(row.profileName), "profile row label lost its name")
    end
    local row = Row(window, "Raid")
    Check(MSUF_SwitchProfile("Default"), "fixture cannot restore starting profile")
    local beforeDefault, beforeRaid = suite.RootDB.profiles.Default, suite.RootDB.profiles.Raid
    local function Pending(message)
        Check(DB.GetCharacterInstallationStatus() == nil and I.IsFirstRunPending(), message)
        Check(MSUF_ActiveProfile == "Default" and DB.GetActiveProfileName() == "Default", "failed selection changed active profile")
        Check(suite.RootDB.installation == receipt, "selection changed account receipt")
    end
    H.combat = true
    row.scripts.OnClick(row)
    Pending("combat selection completed setup")
    H.combat = false
    character = nil
    row.scripts.OnClick(row)
    Pending("unknown identity completed setup")
    character = "Player-Unknown"
    MSUF_GlobalDB.profiles.Raid = nil
    row.scripts.OnClick(row)
    Pending("deleted profile completed setup")
    MSUF_GlobalDB.profiles.Raid = frames
    local switch = MSUF_SwitchProfile
    MSUF_SwitchProfile = function() return false, "refused" end
    row.scripts.OnClick(row)
    Pending("rejected profile switch completed setup")
    MSUF_SwitchProfile = switch
    row.scripts.OnClick(row)
    Check(DB.GetCharacterInstallationStatus() == "complete" and not I.IsFirstRunPending(), "successful retry did not finish setup")
    Check(MSUF_ActiveProfile == "Raid" and DB.GetActiveProfileName() == "Raid"
        and skin.Database.GetActiveProfileName() == "Raid", "reuse did not activate all profile owners")
    Check(suite.RootDB.profiles.Default == beforeDefault and suite.RootDB.profiles.Raid == beforeRaid
        and beforeRaid.suite.modules.chat.enabled == false, "reuse installed factory settings")
    Check(suite.RootDB.installation == receipt and suite.RootDB.characterInstallations["Player-Other"] == "complete",
        "reuse changed another character or account receipt")
    Check(#H.appliedScales == 0 and preference == nil and writes == 1, "reuse applied installer scaling or changed global default")
    Check(window.done[1]:IsShown() and window.next.caption:GetText() == suite.Text("Reload UI")
        and not window.existingProfiles:IsShown(), "reuse did not show completion")
    window:Hide()
    SlashCmdList.MSUFSUITEINSTALL("")
    Check(I.IsOpen() and not window.existingProfilesOpen and not window.existingProfiles:IsShown(), "manual reopen retained old picker")
    window.existingProfileButton.scripts.OnClick()
    window:Hide()
    Check(not window.existingProfilesOpen and not window.existingProfiles:IsShown(), "parent hide retained picker state")
    MSUF_GlobalDB.profiles.Raid = nil
    suite.RootDB.profiles.Raid = nil
    Add("Renamed")
    I.Open()
    window.existingProfileButton.scripts.OnClick()
    Check(Row(window, "Renamed") ~= nil, "reopened picker did not rescan profiles")
    for _, candidate in ipairs(window.existingProfileRows) do
        Check(not candidate:IsShown() or candidate.profileName ~= "Raid", "deleted profile remained selectable")
    end
    Check(#H.reported == 0, "profile choice raised: " .. tostring(H.reported[1]))
end
print("Suite installer profile choice: " .. checks .. " checks passed")

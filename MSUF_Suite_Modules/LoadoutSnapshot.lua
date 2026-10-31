local _, P = ...
local S = P.Suite

-- The chosen loadout. GetActiveConfigID() is the spec's base config, which
-- stays the same when the player switches loadouts; the talent frame reads
-- the selection from GetLastSelectedSavedConfigID(specID) and the starter
-- build from GetStarterBuildActive() (Blizzard_ClassTalentsFrame.lua:236,
-- :1549). Without a saved selection the base config stands for the build;
-- 0 is the starter build, which a saved expectation reads as "any".
local function SelectedBuild(specID)
    if C_ClassTalents.GetStarterBuildActive() == true then return 0, S.Text("Starter build") end
    local configID = C_ClassTalents.GetLastSelectedSavedConfigID(specID)
    if not S.Finite(configID) or configID <= 0 then configID = C_ClassTalents.GetActiveConfigID() end
    if not S.Finite(configID) or configID <= 0 then return 0, S.Text("Starter build") end
    local info = C_Traits.GetConfigInfo(configID)
    local buildName = S.Public(info) and type(info) == "table" and S.PublicText(info.name) or nil
    return configID, buildName or S.Text("Starter build")
end

function S.LoadoutSnapshot()
    local specIndex = C_SpecializationInfo.GetSpecialization()
    if not S.Finite(specIndex) or specIndex < 1 then return nil end
    local specID, specName = C_SpecializationInfo.GetSpecializationInfo(specIndex)
    if not S.Finite(specID) or not S.PublicText(specName) then return nil end

    local configID, buildName = SelectedBuild(specID)

    local lootID = GetLootSpecialization()
    if not S.Finite(lootID) or lootID < 0 then return nil end
    local lootName, effectiveLootID
    if lootID == 0 then
        lootName = S.Text("%s (current)"):format(specName)
        effectiveLootID = specID
    else
        local _, name = GetSpecializationInfoByID(lootID)
        lootName = S.PublicText(name)
        effectiveLootID = lootID
    end
    return configID, buildName, effectiveLootID, lootName
end

local _, P = ...
local S = P.Suite

-- The chosen loadout. GetActiveConfigID() is the spec's base config, which
-- stays the same when the player switches loadouts; the talent frame reads
-- the selection from GetLastSelectedSavedConfigID(specID) and the starter
-- build from GetStarterBuildActive() (Blizzard_ClassTalentsFrame.lua:236,
-- :1549). Without a saved selection the base config stands for the build;
-- 0 is the starter build, which a saved expectation reads as "any".
local function SelectedBuild(specID)
    local starter = C_ClassTalents.GetStarterBuildActive()
    if S.Public(starter) and starter == true then return 0, S.Text("Starter build"), "starter" end
    local selected = C_ClassTalents.GetLastSelectedSavedConfigID(specID)
    local hasSelection = S.Finite(selected) and selected > 0
    local selectionKnown = S.Public(starter) and S.Public(selected)
    local fallback = selectionKnown and "default" or nil
    local configID = hasSelection and selected or C_ClassTalents.GetActiveConfigID()
    if not S.Finite(configID) or configID <= 0 then return 0, S.Text("Starter build"), fallback end
    local info = C_Traits.GetConfigInfo(configID)
    local buildName = S.Public(info) and type(info) == "table" and S.PublicText(info.name) or nil
    if hasSelection then
        local key = selectionKnown and buildName and tostring(configID) or nil
        return configID, buildName or S.Text("Starter build"), key, buildName
    end
    return configID, buildName or S.Text("Starter build"), fallback
end

local function CurrentSpecialization()
    local index = C_SpecializationInfo.GetSpecialization()
    if not S.Finite(index) or index < 1 then return nil end
    local specID, name = C_SpecializationInfo.GetSpecializationInfo(index)
    if S.Finite(specID) then return specID, S.PublicText(name) end
end

-- The selection key is local to the current character and stable across
-- renames. An explicit custom name is available only for a saved loadout.
function S.CurrentTalentLoadout()
    local specID, specName = CurrentSpecialization()
    if not specID or specID <= 0 then return nil end
    local _, buildName, selection, customName = SelectedBuild(specID)
    return specID, customName or (selection == "starter" and buildName) or specName, selection, customName
end

function S.LoadoutSnapshot()
    local specID, specName = CurrentSpecialization()
    if not specID or not specName then return nil end

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
    return configID, buildName, effectiveLootID, lootName, specID, specName, lootID
end

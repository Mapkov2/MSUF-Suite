local _, P = ...
local S = P.Suite
local Field = S.PublicField
local DIFFICULTIES = { "Normal", "Heroic", "Mythic" }

local function TableField(record, key)
    local value = Field(record, key)
    if type(value) == "table" then return value end
end

local function PositiveInteger(value, maximum)
    return S.Finite(value) and value >= 1 and value <= maximum and value == math.floor(value)
end

local function BestDifficulty(groups, bossCount)
    local bestDifficulty, bestKills
    for i = 1, #groups do
        local group = Field(groups, i)
        local difficulty, kills = Field(group, "difficulty"), Field(group, "kills")
        if PositiveInteger(difficulty, #DIFFICULTIES) and PositiveInteger(kills, bossCount)
            and (not bestDifficulty or difficulty > bestDifficulty
                or difficulty == bestDifficulty and kills > bestKills) then
            bestDifficulty, bestKills = difficulty, kills
        end
    end
    return bestDifficulty, bestKills
end

local function AddRaid(rootDescription, record)
    if type(record) ~= "table" or Field(record, "current") ~= true then return false end
    -- PublicField maps false and restricted values to nil. This identity flag
    -- must explicitly identify the character, never an unknown/main record.
    local isMain = record.isMainProgress
    if not S.Public(isMain) or isMain ~= false then return false end
    local raid, groups = TableField(record, "raid"), TableField(record, "progress")
    local name = S.PublicText(Field(raid, "name"))
    local bossCount = Field(raid, "bossCount")
    if not name or not groups or not PositiveInteger(bossCount, 2147483647) then return false end
    local difficulty, kills = BestDifficulty(groups, bossCount)
    if not difficulty then return false end
    rootDescription:CreateTitle(string.format(S.Text("%s: %d/%d defeated (%s)"),
        name, kills, bossCount, S.Text(DIFFICULTIES[difficulty])))
    return true
end

local function AddProfile(rootDescription, profile)
    local raidProfile = TableField(profile, "raidProfile")
    if not raidProfile then return false end
    local outdated = raidProfile.outdated
    if not S.Public(outdated) or outdated ~= nil and (not S.Finite(outdated) or outdated < 0) then return false end
    local rows = TableField(raidProfile, "raidProgress")
    if not rows then return false end
    local shown = false
    for i = 1, #rows do
        if AddRaid(rootDescription, Field(rows, i)) then shown = true end
    end
    if shown and outdated ~= nil and outdated > 0 then
        rootDescription:CreateTitle(S.Text("Raider.IO data may be outdated"))
    end
    return shown
end

local function Populate(rootDescription, fullName)
    rootDescription:CreateDivider()
    rootDescription:CreateTitle(S.Text("Raid progress (Raider.IO)"))
    local getProfile = Field(Field(_G, "RaiderIO"), "GetProfile")
    if type(getProfile) ~= "function" then
        rootDescription:CreateTitle(S.Text("Raider.IO raid data unavailable"))
        return
    end
    local name = S.PublicText(fullName)
    -- Raider.IO owns its cache and missing-character bookkeeping. Read the
    -- public getter once per menu opening; retain only the formatted labels.
    local profile
    if name then profile = S.Dispatch(getProfile, name) end
    if not AddProfile(rootDescription, profile) then
        rootDescription:CreateTitle(S.Text("No current raid data available"))
    end
end

P.ApplicantRaidProgress = { Populate = Populate }

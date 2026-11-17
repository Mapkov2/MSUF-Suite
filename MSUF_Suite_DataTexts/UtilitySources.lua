local _, P = ...
local NS, S = P.NS, P.Suite
local Sources, NO_VALUE = P.DataTextSources, P.NO_VALUE
local Finite, Public, PublicText = S.Finite, S.Public, S.PublicText
local Text = S.Text

-- These scalar samples belong to the provider. Adding more places does not
-- repeat the native data reads. Lists and tooltip details are built on demand.
local Equipment = C_EquipmentSet
local Sets = { delay = .05 }
local equippedSet

local function SetIDs()
    local ids = Equipment.GetEquipmentSetIDs()
    if Public(ids) and type(ids) == "table" then return ids end
end

local function SetInfo(id)
    if not Finite(id) then return end
    local name, _, setID, equipped = Equipment.GetEquipmentSetInfo(id)
    if Finite(setID) and setID == id then return PublicText(name), Public(equipped) and equipped == true end
end

function Sets.Sample()
    equippedSet = nil
    local ids = SetIDs()
    if not ids then return end
    for i = 1, #ids do
        local name, equipped = SetInfo(ids[i])
        if name and equipped then
            equippedSet = name
            return
        end
    end
end

function Sets.Format()
    return Text("Equipment set"), equippedSet or NO_VALUE
end

local function EquipSet(id)
    if NS.InCombat() then return end
    local allowed = Equipment.CanUseEquipmentSets()
    if not Public(allowed) or allowed ~= true then return end
    local name, equipped = SetInfo(id)
    if name and not equipped then Equipment.UseEquipmentSet(id) end
end

local function SetSelected(id)
    local _, equipped = SetInfo(id)
    return equipped == true
end

function Sets.Click(button, mouse)
    if mouse ~= "LeftButton" or NS.InCombat() then return end
    S.ContextMenu(button, function(_, root)
        root:CreateTitle(Text("Equipment sets"))
        local ids = SetIDs()
        if not ids then return end
        for i = 1, #ids do
            local id = ids[i]
            local name = SetInfo(id)
            if name then root:CreateRadio(name, SetSelected, EquipSet, id) end
        end
    end)
end

Sources.Register("equipmentSet", Sets, { "EQUIPMENT_SETS_CHANGED", "EQUIPMENT_SWAP_FINISHED",
    "PLAYER_EQUIPMENT_CHANGED", "PLAYER_ENTERING_WORLD" })

local Talents = C_ClassTalents
local Builds = { delay = .05 }
local buildName
local function SpecID()
    local index = C_SpecializationInfo.GetSpecialization()
    if not Finite(index) then return end
    local id = C_SpecializationInfo.GetSpecializationInfo(index)
    if Finite(id) then return id end
end

local function ConfigName(id)
    if not Finite(id) then return end
    local info = C_Traits.GetConfigInfo(id)
    if Public(info) and type(info) == "table" then return PublicText(info.name) end
end

local function CurrentBuild(spec)
    return Talents.GetLastSelectedSavedConfigID(spec)
end

function Builds.Sample()
    local spec = SpecID()
    buildName = spec and ConfigName(CurrentBuild(spec)) or nil
    if not buildName then
        local starter = Talents.GetStarterBuildActive()
        if Public(starter) and starter == true then buildName = PublicText(STARTER_BUILD) end
    end
end

function Builds.Format()
    return Text("Talent loadout"), buildName or NO_VALUE
end

local function BuildSelected(entry)
    local spec = SpecID()
    if spec ~= entry.spec then return false end
    local id = CurrentBuild(spec)
    return Finite(id) and id == entry.id
end

local function SameBuildName(a, b)
    if not a or not b then return false end
    return strcmputf8i(a, b) == 0
end

local function UniqueBuild(ids, id, name)
    if not Public(ids) or type(ids) ~= "table" then return false end
    local found = false
    for i = 1, #ids do
        local candidate = ids[i]
        if Finite(candidate) then
            if candidate == id then
                found = SameBuildName(ConfigName(candidate), name)
            elseif SameBuildName(ConfigName(candidate), name) then
                return false
            end
        end
    end
    return found
end

local function SwitchBuild(entry)
    if NS.InCombat() or SpecID() ~= entry.spec or BuildSelected(entry) then return end
    if UniqueBuild(Talents.GetConfigIDsBySpecID(entry.spec), entry.id, entry.name) then
        Talents.SwitchToLoadoutByName(entry.name)
    end
end

function Builds.Click(button, mouse)
    if mouse ~= "LeftButton" or NS.InCombat() then return end
    local spec = SpecID()
    if not spec then return end
    S.ContextMenu(button, function(_, root)
        root:CreateTitle(Text("Talent loadouts"))
        local ids = Talents.GetConfigIDsBySpecID(spec)
        if not Public(ids) or type(ids) ~= "table" then return end
        for i = 1, #ids do
            local id = ids[i]
            local name = ConfigName(id)
            if name then
                local row = root:CreateRadio(name, BuildSelected, SwitchBuild, { id = id, name = name, spec = spec })
                row:SetEnabled(UniqueBuild(ids, id, name))
            end
        end
    end)
end

if not NS.Client.isForever then
    Sources.Register("talentLoadout", Builds, { "TRAIT_CONFIG_UPDATED", "TRAIT_CONFIG_LIST_UPDATED",
        "PLAYER_SPECIALIZATION_CHANGED", "PLAYER_ENTERING_WORLD" })
end

local Mail = {}
local hasMail

function Mail.Sample()
    local value = HasNewMail()
    hasMail = Public(value) and value == true
end

function Mail.Format()
    return Text("Mail"), hasMail and Text("New mail") or Text("No mail")
end

function Mail.Lines(tooltip)
    if not hasMail or NS.InCombat() then return end
    local first, second, third = GetLatestThreeSenders()
    first, second, third = PublicText(first), PublicText(second), PublicText(third)
    if first then tooltip:AddLine(first, 1, 1, 1) end
    if second then tooltip:AddLine(second, 1, 1, 1) end
    if third then tooltip:AddLine(third, 1, 1, 1) end
end

Sources.Register("mail", Mail, { "UPDATE_PENDING_MAIL", "PLAYER_ENTERING_WORLD" })

local Key = { delay = .1 }
local MythicPlus, Challenge = C_MythicPlus, C_ChallengeMode
local keyLevel, keyName
function Key.Sample()
    keyLevel, keyName = nil, nil
    local level = MythicPlus.GetOwnedKeystoneLevel()
    if not Finite(level) or level <= 0 then return end
    keyLevel = level
    local map = MythicPlus.GetOwnedKeystoneChallengeMapID()
    if Finite(map) and map > 0 then keyName = PublicText(Challenge.GetMapUIInfo(map)) end
end

function Key.Format()
    local label = Text("Mythic+ Keystone")
    if not keyLevel then return label, NO_VALUE end
    if keyName then return label, Text("+%d %s"):format(keyLevel, keyName) end
    return label, ("+%d"):format(keyLevel)
end

if not NS.Client.isForever then
    Sources.Register("keystone", Key, { "BAG_UPDATE_DELAYED", "CHALLENGE_MODE_COMPLETED", "PLAYER_ENTERING_WORLD" })
end

local Played = {}
local played, levelPlayed, sampledAt, requestedAt
local playedModule

local function PlayedTick()
    Sources.Refresh("timePlayed")
end

function Played.Rebind(module, active)
    if active then
        playedModule = module
        if played then module.context:Ticker(60, PlayedTick) end
    else
        module.context:Cancel(PlayedTick)
        playedModule = nil
    end
end

function Played.Disable()
    if playedModule then playedModule.context:Cancel(PlayedTick) end
    playedModule = nil
end

local function PlayedText(seconds)
    if not seconds then return NO_VALUE end
    local elapsed = math.floor(seconds + math.max(0, GetTime() - sampledAt))
    return SecondsToTime(elapsed, true, false, 2, true)
end

function Played.Format()
    return Text("Time played"), PlayedText(played)
end

local function QueryPlayed()
    if NS.InCombat() then return end
    local now = GetTime()
    if requestedAt and now - requestedAt < 5 then return end
    requestedAt = now
    RequestTimePlayed()
end

function Played.Event(event, total, level)
    if event == "TIME_PLAYED_MSG" then
        if not Finite(total) or total < 0 then return false end
        played, levelPlayed, sampledAt = total, Finite(level) and level >= 0 and level or nil, GetTime()
        requestedAt = nil
        if playedModule then playedModule.context:Ticker(60, PlayedTick) end
        return true
    end
    levelPlayed = nil
    return false
end

function Played.Lines(tooltip)
    if not played then
        tooltip:AddLine(Text("Click to request time played."), 1, 1, 1)
        return
    end
    tooltip:AddDoubleLine(Text("Total"), PlayedText(played))
    if levelPlayed then tooltip:AddDoubleLine(Text("This level"), PlayedText(levelPlayed)) end
end

function Played.Click(_, mouse)
    if mouse == "LeftButton" then QueryPlayed() end
end

Sources.Register("timePlayed", Played, { "TIME_PLAYED_MSG", "PLAYER_LEVEL_UP" })

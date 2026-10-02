local _, P = ...
local NS, S = P.NS, P.Suite

local M = {}
local INSTANCE_EVENTS = { "PLAYER_ENTERING_WORLD", "ZONE_CHANGED_NEW_AREA",
    "PLAYER_TALENT_UPDATE", "PLAYER_SPECIALIZATION_CHANGED", "SELECTED_LOADOUT_CHANGED" }
-- Events that change the build inside one instance, so they re-check it.
local BUILD_EVENTS = { PLAYER_TALENT_UPDATE = true, PLAYER_SPECIALIZATION_CHANGED = true,
    SELECTED_LOADOUT_CHANGED = true }

-- The reminder hides config.duration seconds after it last showed.
local function HideReminder(self)
    self.host:Hide()
end

local function CancelHide(self)
    self.context:Cancel(HideReminder)
end

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

local function Current()
    local specIndex = C_SpecializationInfo.GetSpecialization()
    if not S.Finite(specIndex) or specIndex < 1 then return nil end
    local specID, specName = C_SpecializationInfo.GetSpecializationInfo(specIndex)
    if not S.Finite(specID) or not S.PublicText(specName) then return nil end

    local configID, buildName = SelectedBuild(specID)

    local lootID = GetLootSpecialization()
    if not S.Finite(lootID) or lootID < 0 then return nil end
    local lootName, effectiveLootID
    if lootID == 0 then
        lootName = specName .. " (" .. S.Text("current") .. ")"
        effectiveLootID = specID
    else
        local _, name = GetSpecializationInfoByID(lootID)
        lootName = S.PublicText(name)
        effectiveLootID = lootID
    end
    return configID, buildName, effectiveLootID, lootName
end

local function Create(self)
    if self.host then return end
    local host = S.CreateFrame("Frame", nil, UIParent)
    host:SetSize(360, 70)
    host:SetFrameStrata("HIGH")
    host:EnableMouse(false)
    local background = S.CreateTexture(host, nil, "BACKGROUND")
    background:SetAllPoints()
    background:SetColorTexture(.05, .07, .09, .94)
    local border = S.CreateTexture(host, nil, "BORDER")
    border:SetPoint("TOPLEFT")
    border:SetPoint("BOTTOMLEFT")
    border:SetWidth(3)
    local title = S.CreateFontString(host, nil, "OVERLAY")
    title:SetPoint("TOPLEFT", 12, -8)
    title:SetPoint("TOPRIGHT", -12, -8)
    title:SetJustifyH("LEFT")
    S.SetFont(title, nil, 13, "OUTLINE")
    local detail = S.CreateFontString(host, nil, "OVERLAY")
    detail:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -7)
    detail:SetPoint("TOPRIGHT", title, "BOTTOMRIGHT", 0, -7)
    detail:SetJustifyH("LEFT")
    S.SetFont(detail, nil, 11, "")
    host:SetPoint("TOP", UIParent, "TOP", 0, -155)
    host:Hide()
    self.host, self.background, self.border, self.title, self.detail =
        host, background, border, title, detail
end

local function Paint(self, mismatch)
    local style = S.QoLStyle(self.config)
    S.QoLColor(self.background, style.background, .94)
    if mismatch then
        self.title:SetTextColor(1, .54, .42)
        self.border:SetColorTexture(1, .42, .28, 1)
    else
        self.title:SetTextColor(S.RGB(style.accent))
        S.QoLColor(self.border, style.accent)
    end
    self.detail:SetTextColor(S.RGB(style.text))
end

local function Show(self)
    if not self.active then return end
    local configID, buildName, lootID, lootName = Current()
    if not configID or not lootName then return end
    local characterGUID = S.PublicText(UnitGUID("player"))
    local sameCharacter = not self.config.expectedCharacterGUID
        or self.config.expectedCharacterGUID == ""
        or (characterGUID and self.config.expectedCharacterGUID == characterGUID)
    local expectedConfig = sameCharacter and (self.config.expectedConfigID or 0) or 0
    local expectedLoot = sameCharacter and (self.config.expectedLootSpecID or 0) or 0
    local mismatch = (expectedConfig > 0 and expectedConfig ~= configID)
        or (expectedLoot > 0 and expectedLoot ~= lootID)
    if self.config.onlyMismatch and not mismatch then
        CancelHide(self)
        if self.host then self.host:Hide() end
        return true, configID, lootID
    end
    Create(self)
    self.title:SetText(S.Text(mismatch and "Check your loadout" or "Current loadout"))
    self.lastMismatch = mismatch
    Paint(self, mismatch)
    self.detail:SetText(buildName .. "  |  " .. S.Text("Loot") .. ": " .. lootName)
    self.host:Show()
    self.context:After(self.config.duration, HideReminder)
    return true, configID, lootID
end

local function OnReady(self)
    if self.config.onReadyCheck then Show(self) end
end

local function OnProposal(self)
    if self.config.onLfgProposal then Show(self) end
end

local function OnZone(self, event)
    if not self.config.onInstanceEntry then return end
    local inInstance, kind = IsInInstance()
    if not S.Public(inInstance) or inInstance ~= true or not S.PublicText(kind)
        or kind == "none" then
        self.lastInstance, self.lastConfigID, self.lastLootID = nil, nil, nil
        return
    end
    local _, _, _, _, _, _, _, instanceID = GetInstanceInfo()
    if not S.Finite(instanceID) then return end
    if self.lastInstance == instanceID then
        if not BUILD_EVENTS[event] then return end
        local configID, _, lootID = Current()
        if not configID or (self.lastConfigID == configID and self.lastLootID == lootID) then return end
    end
    local shown, configID, lootID = Show(self)
    if shown then
        self.lastInstance, self.lastConfigID, self.lastLootID = instanceID, configID, lootID
    end
end

function M:SaveCurrent()
    local configID, _, lootID = Current()
    local guid = S.PublicText(UnitGUID("player"))
    if not configID or not guid then return false end
    return S.SetMany("loadoutReminder", {
        expectedConfigID = configID, expectedLootSpecID = lootID, expectedCharacterGUID = guid,
    })
end

function M:ClearSaved()
    return S.SetMany("loadoutReminder", {
        expectedConfigID = 0, expectedLootSpecID = 0, expectedCharacterGUID = "",
    })
end

local function SyncEvents(self)
    local context = self.context
    local watchInstance = self.config.onInstanceEntry
    local newlyWatching = watchInstance and self.watchingInstance == false
    self.watchingInstance = watchInstance
    if not watchInstance then
        self.lastInstance, self.lastConfigID, self.lastLootID = nil, nil, nil
    end
    if self.config.onReadyCheck then context:Event("READY_CHECK", OnReady, true)
    else context:RemoveEvent("READY_CHECK") end
    if self.config.onLfgProposal then context:Event("LFG_PROPOSAL_SHOW", OnProposal, true)
    else context:RemoveEvent("LFG_PROPOSAL_SHOW") end
    for _, event in ipairs(INSTANCE_EVENTS) do
        if watchInstance then context:Event(event, OnZone, true)
        else context:RemoveEvent(event) end
    end
    return newlyWatching
end

function M:Enable()
    SyncEvents(self)
    OnZone(self)
end

function M:Refresh()
    local newlyWatching = SyncEvents(self)
    if self.host then S.SetFont(self.title, nil, 13, "OUTLINE"); S.SetFont(self.detail, nil, 11, "") end
    if self.host then Paint(self, self.lastMismatch) end
    if not self.config.onReadyCheck and not self.config.onInstanceEntry and not self.config.onLfgProposal then
        CancelHide(self)
        if self.host then self.host:Hide() end
    end
    if newlyWatching then OnZone(self) end
end

function M:Disable()
    CancelHide(self)
    self.lastInstance = nil
    self.lastConfigID, self.lastLootID = nil, nil
    if self.host then self.host:Hide() end
end

S.LoadoutReminder = M
S.Install("loadoutReminder", M)

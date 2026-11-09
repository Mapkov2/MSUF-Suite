local _, P = ...
local NS, S = P.NS, P.Suite
local IN_COMBAT = { inCombat = true }

local M = {}
local ID = "loadoutReminder"
local CARD = { width = 360, height = 70, fill = { .05, .07, .09, .94 }, stripe = 3 }
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

local Current = S.LoadoutSnapshot
local MAX_DUNGEONS, MAX_ABILITIES = 32, 6

local function Dungeon()
    local _, kind, _, _, _, _, _, id = GetInstanceInfo()
    if S.PublicText(kind) == "party" and S.Finite(id) and id > 0 then return id end
end

local function AbilityData(self, guid)
    local raw = self.config.dungeonAbilities or ""
    if self.abilitySource ~= raw then
        self.abilitySource = raw
        self.abilityOwner, self.abilityRules = raw:match("^([%w%-]+);"), {}
        local count = 0
        for zone, list in raw:gmatch("(%d+):([%d,]+);") do
            if count >= MAX_DUNGEONS then break end
            local spells = {}
            for id in list:gmatch("%d+") do
                if #spells >= MAX_ABILITIES then break end
                id = tonumber(id)
                if id and id > 0 and id < 2147483648 then spells[#spells + 1] = id end
            end
            self.abilityRules[tonumber(zone)] = spells
            count = count + 1
        end
    end
    if guid and guid == self.abilityOwner then return self.abilityRules end
end

local function MissingAbilities(self, guid)
    if not self.config.dungeonAbilities or self.config.dungeonAbilities == "" or NS.InCombat() then return end
    local zone, rules = Dungeon(), AbilityData(self, guid)
    local spells = zone and rules and rules[zone]
    local known = C_SpellBook and C_SpellBook.IsSpellKnown
    if not spells or not known then return end
    local missing
    for i = 1, #spells do
        local id = spells[i]
        local learned = known(id)
        if S.Public(learned) and learned == false then
            local name = S.PublicText(C_Spell.GetSpellName(id))
            if name then missing = missing and (missing .. ", " .. name) or name end
        end
    end
    return missing
end

function M:CanSetDungeonAbilities()
    return self.active and not NS.InCombat() and Dungeon() ~= nil
end

function M:DungeonAbilityContext()
    if not self.active or NS.InCombat() then return end
    local zone, guid = Dungeon(), S.PublicText(UnitGUID("player"))
    if zone and guid then return zone, guid, self.config end
end

function M:SetDungeonAbilities(text, expectedZone, expectedGuid, expectedConfig)
    local zone, guid, config = self:DungeonAbilityContext()
    if not zone or type(text) ~= "string" then return false end
    if expectedZone and (zone ~= expectedZone or guid ~= expectedGuid or config ~= expectedConfig) then return false end
    local spells, seen = {}, {}
    if text:match("%S") and not text:match("^%s*0%s*$") then
        for token in text:gmatch("[^,]+") do
            token = token:match("^%s*(.-)%s*$")
            local id = tonumber(token) or C_Spell.GetSpellIDForSpellIdentifier(token)
            if not S.Finite(id) or id <= 0 or id >= 2147483648 or id % 1 ~= 0
                or not S.PublicText(C_Spell.GetSpellName(id)) then return false end
            if not seen[id] then spells[#spells + 1], seen[id] = id, true end
            if #spells > MAX_ABILITIES then return false end
        end
        if #spells == 0 then return false end
    end
    local others = AbilityData(self, guid) or {}
    local keys, parts = {}, { guid .. ";" }
    for id in pairs(others) do if id ~= zone then keys[#keys + 1] = id end end
    if #spells > 0 and #keys >= MAX_DUNGEONS then return false end
    table.sort(keys)
    for _, id in ipairs(keys) do parts[#parts + 1] = id .. ":" .. table.concat(others[id], ",") .. ";" end
    if #spells > 0 then parts[#parts + 1] = zone .. ":" .. table.concat(spells, ",") .. ";" end
    if #parts == 1 then parts[1] = "" end
    local ok = S.SetMany("loadoutReminder", { dungeonAbilities = table.concat(parts) })
    if ok then self:Test() end
    return ok
end

local function Place(self)
    S.PlaceHost(self.host, self.config)
end

local function Create(self)
    if self.host then return end
    local host, background, border = S.QoLCard(CARD)
    local title = S.CreateFontString(host, nil, "OVERLAY")
    title:SetPoint("TOPLEFT", 12, -8)
    title:SetPoint("TOPRIGHT", -12, -8)
    title:SetJustifyH("LEFT")
    S.SetFont(title, nil, 13, "OUTLINE")
    local detail = S.CreateFontString(host, nil, "OVERLAY")
    detail:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -7)
    detail:SetPoint("TOPRIGHT", title, "BOTTOMRIGHT", 0, -7)
    detail:SetJustifyH("LEFT")
    detail:SetWordWrap(true)
    detail:SetMaxLines(2)
    S.SetFont(detail, nil, 11, "")
    host:Hide()
    self.host, self.background, self.border, self.title, self.detail =
        host, background, border, title, detail
    Place(self)
end

local function Paint(self, mismatch)
    local style = S.PaintQoLCard(ID, self.config, self.background)
    if mismatch then
        self.title:SetTextColor(1, .54, .42)
        self.border:SetColorTexture(1, .42, .28, 1)
    else
        self.title:SetTextColor(S.RGB(style.accent))
        S.QoLColor(self.border, style.accent)
    end
    self.detail:SetTextColor(S.RGB(style.text))
end

-- Edit Mode shows a sample so the reminder can be placed.
local function Sample(self)
    Create(self)
    CancelHide(self)
    self.title:SetText(S.Text("Current loadout"))
    Paint(self, false)
    self.detail:SetText(S.Text("%s  |  Loot: %s"):format(S.Text("Sample build"), S.Text("Current specialization")))
    self.host:Show()
end

-- force: the "Show reminder now" test, which ignores the mismatch-only rule.
local function Show(self, force)
    if not self.active then return end
    local configID, buildName, lootID, lootName = Current()
    if not configID or not lootName then return end
    local characterGUID = S.PublicText(UnitGUID("player"))
    local sameCharacter = not self.config.expectedCharacterGUID
        or self.config.expectedCharacterGUID == ""
        or (characterGUID and self.config.expectedCharacterGUID == characterGUID)
    local expectedConfig = sameCharacter and (self.config.expectedConfigID or 0) or 0
    local expectedLoot = sameCharacter and (self.config.expectedLootSpecID or 0) or 0
    local missing = MissingAbilities(self, characterGUID)
    local mismatch = missing ~= nil or (expectedConfig > 0 and expectedConfig ~= configID)
        or (expectedLoot > 0 and expectedLoot ~= lootID)
    if self.config.onlyMismatch and not mismatch and not force then
        CancelHide(self)
        if self.host then self.host:Hide() end
        return true, configID, lootID
    end
    Create(self)
    self.title:SetText(S.Text(mismatch and "Check your loadout" or "Current loadout"))
    self.lastMismatch = mismatch
    Paint(self, mismatch)
    if missing then
        self.detail:SetText(S.Text("Missing abilities: %s"):format(missing))
    else
        self.detail:SetText(S.Text("%s  |  Loot: %s"):format(buildName, lootName))
    end
    self.host:Show()
    if self.config.sound then S.QoLWarningSound() end
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
        if not configID then return end
        local rules = self.config.dungeonAbilities and self.config.dungeonAbilities ~= ""
            and AbilityData(self, S.PublicText(UnitGUID("player")))
        if not (rules and rules[instanceID]) and self.lastConfigID == configID and self.lastLootID == lootID then return end
    end
    local shown, configID, lootID = Show(self)
    if shown then
        self.lastInstance, self.lastConfigID, self.lastLootID = instanceID, configID, lootID
    end
end

-- Shows the current loadout now, as a reminder would.
function M:Test()
    Show(self, true)
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
    if self.config.onReadyCheck then
        context:Event("READY_CHECK", OnReady, IN_COMBAT)
    else
        context:RemoveEvent("READY_CHECK")
    end
    if self.config.onLfgProposal then
        context:Event("LFG_PROPOSAL_SHOW", OnProposal, IN_COMBAT)
    else
        context:RemoveEvent("LFG_PROPOSAL_SHOW")
    end
    for _, event in ipairs(INSTANCE_EVENTS) do
        if watchInstance then
            context:Event(event, OnZone, IN_COMBAT)
        else
            context:RemoveEvent(event)
        end
    end
    return newlyWatching
end

function M:Enable()
    SyncEvents(self)
    OnZone(self)
end

function M:Refresh()
    local newlyWatching = SyncEvents(self)
    if self.host then
        S.SetFont(self.title, nil, 13, "OUTLINE")
        S.SetFont(self.detail, nil, 11, "")
        Place(self)
        Paint(self, self.lastMismatch)
    end
    if S.editMode then
        Sample(self)
    elseif not self.config.onReadyCheck and not self.config.onInstanceEntry and not self.config.onLfgProposal then
        CancelHide(self)
        if self.host then self.host:Hide() end
    end
    if newlyWatching then OnZone(self) end
end

function M:HideEditPreview()
    CancelHide(self)
    if self.host then self.host:Hide() end
end

function M:Disable()
    CancelHide(self)
    self.lastInstance = nil
    self.lastConfigID, self.lastLootID = nil, nil
    if self.host then self.host:Hide() end
end

-- Edit Mode builds the frame when it asks for it: the reminder makes none
-- before its first event.
function M:RegisterMovers()
    S.RegisterOwnedMover(ID, "reminder", {
        label = "Loadout reminder", order = 653,
        getFrame = function()
            Create(self)
            return self.host
        end,
        xKey = "x", yKey = "y", pointKey = "point",
        point = function() return NS.AnchorPoints[self.config.point] or "TOP" end,
        quickPosition = true, historyKeys = { "scale" },
        sizeKeys = { "scale" },
    })
end

M.Snapshot = Current
S.LoadoutReminder = M
S.Install(ID, M)

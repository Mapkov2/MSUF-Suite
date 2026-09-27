local _, private = ...
local NS, S = private.NS, private.Suite
local Roles = { quests = {}, pendingQuests = {} }
private.Roles = Roles

local function Read(api, ...)
    if type(api) ~= "function" then return nil end
    local value = api(...)
    if S.Public(value) then return value end
end

local function Level(unit)
    local level = Read(_G.UnitEffectiveLevel, unit)
    if not S.Finite(level) then level = Read(_G.UnitLevel, unit) end
    if S.Finite(level) then return level end
end

function Roles.Configure(config)
    Roles.config = config
    Roles.RefreshContext()
end

-- World/group changes are infrequent. Never rediscover this context per plate
-- health update. LFG scaling uses the same reference level as EQoL.
function Roles.RefreshContext()
    local _, instanceType = nil, "none"
    if type(_G.IsInInstance) == "function" then _, instanceType = _G.IsInInstance() end
    local public = S.Public(instanceType)
    Roles.inInstance = not public or instanceType ~= "none"
    Roles.instanced = public and (instanceType == "party" or instanceType == "raid" or instanceType == "scenario")
    local pvp = Read(_G.C_PvP and _G.C_PvP.GetZonePVPInfo)
    -- Zone PvP flags describe the outdoor zone and can remain "combat" while
    -- inside a party/raid/scenario instance. Instance type is authoritative.
    Roles.allowed = public and instanceType ~= "pvp" and instanceType ~= "arena"
        and (Roles.instanced or pvp ~= "arena" and pvp ~= "combat" and pvp ~= "ffapvp")
    local c = Roles.config
    Roles.allowed = Roles.allowed and ((Roles.instanced and c.enemyColorsInDungeons ~= false)
        or (not Roles.instanced and c.enemyColorsOutside ~= false))
    Roles.tank = Read(_G.PlayerUtil and _G.PlayerUtil.IsPlayerEffectivelyTank) == true
    Roles.grouped = Read(_G.UnitInParty, "player") == true or Read(_G.IsInRaid) == true
    Roles.reference = Level("player")
    if Roles.instanced and type(_G.GetInstanceInfo) == "function" then
        local _, _, _, _, _, _, _, _, _, lfg = _G.GetInstanceInfo()
        if S.Public(lfg) and lfg then
            local expansion = Read(_G.GetMaximumExpansionLevel)
            local maximum = expansion and Read(_G.GetMaxLevelForExpansionLevel, expansion)
            if S.Finite(maximum) then Roles.reference = maximum end
        end
    end
    Roles.lieutenantLevel = nil
end

function Roles.ClearQuest(unit)
    if unit then Roles.quests[unit], Roles.pendingQuests[unit] = nil, nil
    else
        for key in pairs(Roles.quests) do Roles.quests[key] = nil end
        for key in pairs(Roles.pendingQuests) do Roles.pendingQuests[key] = nil end
    end
end

local function PendingQuest(unit)
    Roles.pendingQuests[unit] = true
    return nil
end

function Roles.RetryQuests()
    if not next(Roles.pendingQuests) then return false end
    Roles.ClearQuest()
    return true
end

local function Incomplete(text)
    if not S.Public(text) or type(text) ~= "string" then return nil end
    local have, need = text:match("(%d+)%s*/%s*(%d+)")
    if have then return tonumber(have) < tonumber(need) end
    local percent = text:match("(%d+)%%")
    return not percent or tonumber(percent) < 100
end

function Roles.Quest(unit)
    -- EQoL scans world quest objectives only. No tooltip work in dungeons.
    if Roles.inInstance or Roles.pendingQuests[unit] then return nil end
    if Roles.quests[unit] ~= nil then return Roles.quests[unit] end
    local secrets = _G.C_Secrets
    if secrets and type(secrets.ShouldUnitIdentityBeSecret) == "function"
        and Read(secrets.ShouldUnitIdentityBeSecret, unit) ~= false then return PendingQuest(unit) end
    -- Direct API is a cheap negative gate. Tooltip lines distinguish our
    -- unfinished objectives from completed objectives and party quests.
    local related = Read(_G.C_QuestLog and _G.C_QuestLog.UnitIsRelatedToActiveQuest, unit)
    if related == false then Roles.quests[unit] = false; return false end
    local info = Read(_G.C_TooltipInfo and _G.C_TooltipInfo.GetUnit, unit)
    local types = _G.Enum and _G.Enum.TooltipDataLineType
    if type(info) ~= "table" or not types or not S.Public(info.lines) or type(info.lines) ~= "table" then
        if type(related) == "boolean" then Roles.quests[unit] = related; return related end
        return PendingQuest(unit) -- not a cached absent objective
    end
    local player, ours, found = Read(_G.UnitName, "player"), true, false
    for _, line in ipairs(info.lines) do
        if not S.Public(line) then return PendingQuest(unit) end
        if type(line) == "table" then
            if not S.Public(line.type) then return PendingQuest(unit) end
            if line.type == types.QuestTitle then ours = true
            elseif line.type == types.QuestPlayer then
                ours = S.Public(line.leftText) and player ~= nil and line.leftText == player
            elseif ours and line.type == types.QuestObjective then
                local incomplete = Incomplete(line.leftText)
                if incomplete == nil then return PendingQuest(unit) end
                if incomplete then found = true; break end
            end
        end
    end
    Roles.quests[unit] = found
    return found
end

local function OnThreatList(unit)
    return Read(_G.CompactUnitFrame_IsOnThreatListWithPlayer, unit) == true
end

-- Blizzard live CompactUnitFrame_GetThreatSituation: tanks use lead status
-- (0 = safe); damage/healers use regular status (3 = taking aggro).
local function Threat(uf, unit)
    if not Roles.grouped then return nil end
    local explicit = uf.explicitThreatSituation
    if S.Finite(explicit) and explicit > 0 then return explicit end
    local displayed = uf.displayedUnit
    if S.Public(displayed) and type(displayed) == "string" then unit = displayed end
    local options = uf.optionTable
    local usePlayer = S.Public(options) and type(options) == "table"
        and S.Public(options.usePlayerForAggroHighlightThreat)
        and options.usePlayerForAggroHighlightThreat == true
    local api = usePlayer and Roles.tank and _G.UnitThreatLeadSituation or _G.UnitThreatSituation
    if type(api) ~= "function" then return nil end
    local status
    if usePlayer then status = api("player", unit)
    else status = api(unit) end
    if not S.Public(status) then return nil end
    if S.Finite(status) and status > 0 then return status end
end

function Roles.Classify(unit, classification)
    if Read(_G.UnitIsBossMob, unit) == true or classification == "worldboss" then return "Boss" end
    if classification == "elite" or classification == "rare" or classification == "rareelite" then
        local level, reference = Level(unit), Roles.reference
        if Read(_G.UnitIsLieutenant, unit) == true or (level and reference and level == reference + 1) then
            Roles.lieutenantLevel = level
            return "Miniboss"
        end
        if level == -1 or (level and reference and level == reference + 2)
            or (level and Roles.lieutenantLevel and level == Roles.lieutenantLevel + 1) then return "Boss" end
        if not Roles.instanced then return "Miniboss" end
    end
    if classification == "trivial" or classification == "minus" or Read(_G.UnitIsTrivial, unit) == true then
        return "Trivial"
    end
    if classification ~= nil and classification ~= "normal" and classification ~= "elite"
        and classification ~= "rare" and classification ~= "rareelite" then return nil end
    local mana = _G.Enum and _G.Enum.PowerType and _G.Enum.PowerType.Mana or 0
    -- Match Platynator's Jundies classifier: mana capability takes precedence
    -- over the displayed power type, which can differ on NPCs.
    local usesMana = Read(_G.UnitHasPowerType, unit, mana)
    if type(usesMana) == "boolean" then return usesMana and "Caster" or "Melee" end
    local power, token
    if type(_G.UnitPowerType) == "function" then power, token = _G.UnitPowerType(unit) end
    -- These results can be restricted independently. Keep any public hint.
    if not S.Public(power) then power = nil end
    if not S.Public(token) then token = nil end
    if token == "MANA" or power == mana then return "Caster" end
    -- A restricted or absent power hint cannot identify a caster. EQoL's
    -- normal-NPC rule falls back to melee in this case as well.
    return "Melee"
end

function Roles.Get(unit, uf, classification, quest)
    local c = Roles.config
    if not Roles.allowed or not c.enemyRoleColors or not S.Public(uf.isFriend) or uf.isFriend ~= false
        or not S.Public(uf.isPlayer) or uf.isPlayer ~= false then return nil end
    if type(_G.UnitPlayerControlled) == "function" then
        local controlled = _G.UnitPlayerControlled(unit)
        if S.Public(controlled) and controlled == true then return nil end
    end
    if Read(_G.UnitIsDead, unit) == true or Read(_G.UnitIsConnected, unit) == false then return nil end
    if c.enemyFocusEnabled ~= false and Read(_G.UnitIsUnit, unit, "focus") == true then return "Focus" end
    -- A secret threat value only removes the threat override. It must not
    -- suppress the ordinary NPC role color.
    local threat = Threat(uf, unit)
    if c.enemyTankMode and Roles.tank and not threat and OnThreatList(unit) then return "TankMode" end
    if threat then
        local role = threat >= 3 and "ThreatLost" or "ThreatWarning"
        if c["enemy" .. role .. "Enabled"] ~= false then return role end
        return nil
    end
    if Read(_G.UnitIsTapDenied, unit) == true then
        return c.enemyTappedEnabled ~= false and "Tapped" or nil
    end
    if c.enemyQuestColors and c.enemyQuestEnabled ~= false and quest == true then return "Quest" end
    if Read(_G.UnitReaction, unit, "player") == 4 then
        return not OnThreatList(unit) and c.enemyNeutralEnabled ~= false and "Neutral" or nil
    end
    if Read(_G.UnitCanAttack, "player", unit) == false then return nil end
    local role = Roles.Classify(unit, classification)
    return role and c["enemy" .. role .. "Enabled"] ~= false and role or nil
end

function Roles.Marker(unit, classification)
    if classification == "worldboss" then return "boss" end
    if classification == "rare" then return "rare" end
    if classification ~= "elite" and classification ~= "rareelite" then return nil end
    local level = Level(unit)
    if level == -1 or (level and Roles.reference and level == Roles.reference + 2) then return "boss" end
    return "elite"
end

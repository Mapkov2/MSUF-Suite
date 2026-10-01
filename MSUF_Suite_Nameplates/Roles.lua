local _, private = ...
local NS, S = private.NS, private.Suite
-- lieutenants: the lieutenant levels seen in this context. Lieutenants of
-- one instance can differ in level, so it is a set; learnedLieutenant tells
-- the plate owner that a new level arrived (Roles.Classify).
local Roles = { quests = {}, pendingQuests = {}, lieutenants = {}, learnedLieutenant = false }
private.Roles = Roles

-- The first result of a unit query, or nil while it is restricted.
local function Read(api, ...)
    local value = api(...)
    if S.Public(value) then return value end
end

local function Level(unit)
    local level = Read(UnitEffectiveLevel, unit)
    if not S.Finite(level) then level = Read(UnitLevel, unit) end
    if S.Finite(level) then return level end
end

function Roles.Configure(config)
    Roles.config = config
    Roles.RefreshContext()
end

-- World/group changes are infrequent. Never rediscover this context per plate
-- health update. LFG scaling uses the same reference level as EQoL. Returns
-- true when a fact the plate colors depend on changed.
function Roles.RefreshContext()
    local known = Roles.contextKnown
    local wasAllowed, wasInstanced, wasTank, wasGrouped, wasReference =
        Roles.allowed, Roles.instanced, Roles.tank, Roles.grouped, Roles.reference
    local _, instanceType = IsInInstance()
    local public = S.Public(instanceType)
    Roles.inInstance = not public or instanceType ~= "none"
    Roles.instanced = public and (instanceType == "party" or instanceType == "raid" or instanceType == "scenario")
    local pvp = Read(C_PvP.GetZonePVPInfo)
    -- Zone PvP flags describe the outdoor zone and can remain "combat" while
    -- inside a party/raid/scenario instance. Instance type is authoritative.
    Roles.allowed = public and instanceType ~= "pvp" and instanceType ~= "arena"
        and (Roles.instanced or pvp ~= "arena" and pvp ~= "combat" and pvp ~= "ffapvp")
    local c = Roles.config
    Roles.allowed = Roles.allowed and ((Roles.instanced and c.enemyColorsInDungeons ~= false)
        or (not Roles.instanced and c.enemyColorsOutside ~= false))
    Roles.tank = Read(PlayerUtil.IsPlayerEffectivelyTank) == true
    Roles.grouped = Read(UnitInParty, "player") == true or Read(IsInRaid) == true
    Roles.reference = Level("player")
    if Roles.instanced then
        local _, _, _, _, _, _, _, _, _, lfg = GetInstanceInfo()
        if S.Public(lfg) and lfg then
            local expansion = Read(GetMaximumExpansionLevel)
            local maximum = expansion and Read(GetMaxLevelForExpansionLevel, expansion)
            if S.Finite(maximum) then Roles.reference = maximum end
        end
    end
    for level in pairs(Roles.lieutenants) do Roles.lieutenants[level] = nil end
    Roles.learnedLieutenant = false
    Roles.contextKnown = true
    return not known or wasAllowed ~= Roles.allowed or wasInstanced ~= Roles.instanced
        or wasTank ~= Roles.tank or wasGrouped ~= Roles.grouped or wasReference ~= Roles.reference
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

-- Tooltip lines distinguish our unfinished objectives from completed
-- objectives and party quests. nil while a line is restricted.
local function TooltipQuest(unit, info)
    local types = Enum.TooltipDataLineType
    local player, ours = Read(UnitName, "player"), true
    for _, line in ipairs(info.lines) do
        if not S.Public(line) then return nil end
        if type(line) == "table" then
            if not S.Public(line.type) then return nil end
            if line.type == types.QuestTitle then ours = true
            elseif line.type == types.QuestPlayer then
                ours = S.Public(line.leftText) and player ~= nil and line.leftText == player
            elseif ours and line.type == types.QuestObjective then
                local incomplete = Incomplete(line.leftText)
                if incomplete == nil then return nil end
                if incomplete then return true end
            end
        end
    end
    return false
end

function Roles.Quest(unit)
    -- EQoL scans world quest objectives only. No tooltip work in dungeons.
    if Roles.inInstance or Roles.pendingQuests[unit] then return nil end
    if Roles.quests[unit] ~= nil then return Roles.quests[unit] end
    if Read(C_Secrets.ShouldUnitIdentityBeSecret, unit) ~= false then return PendingQuest(unit) end
    -- Direct API is a cheap negative gate.
    local related = Read(C_QuestLog.UnitIsRelatedToActiveQuest, unit)
    if related == false then Roles.quests[unit] = false; return false end
    local info = Read(C_TooltipInfo.GetUnit, unit)
    if type(info) ~= "table" or not S.Public(info.lines) or type(info.lines) ~= "table" then
        if type(related) == "boolean" then Roles.quests[unit] = related; return related end
        return PendingQuest(unit) -- not a cached absent objective
    end
    local found = TooltipQuest(unit, info)
    if found == nil then return PendingQuest(unit) end
    Roles.quests[unit] = found
    return found
end

local function OnThreatList(unit)
    return Read(CompactUnitFrame_IsOnThreatListWithPlayer, unit) == true
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
    local status
    if usePlayer then
        status = (Roles.tank and UnitThreatLeadSituation or UnitThreatSituation)("player", unit)
    else
        status = UnitThreatSituation(unit)
    end
    if not S.Public(status) then return nil end
    if S.Finite(status) and status > 0 then return status end
end

-- The unit's type role (Boss, Miniboss, Trivial, Caster, Melee) or nil.
-- Level, classification and power display change it; threat never does.
-- An elite one level above a lieutenant seen in this context is a boss; a
-- newly seen lieutenant level sets learnedLieutenant, so the plates
-- classified before it are classified again.
function Roles.Classify(unit, classification)
    if Read(UnitIsBossMob, unit) == true or classification == "worldboss" then return "Boss" end
    if classification == "elite" or classification == "rare" or classification == "rareelite" then
        local level, reference = Level(unit), Roles.reference
        if Read(UnitIsLieutenant, unit) == true or (level and reference and level == reference + 1) then
            if level and not Roles.lieutenants[level] then
                Roles.lieutenants[level] = true
                Roles.learnedLieutenant = true
            end
            return "Miniboss"
        end
        if level == -1 or (level and reference and level == reference + 2)
            or (level and Roles.lieutenants[level - 1]) then return "Boss" end
        if not Roles.instanced then return "Miniboss" end
    end
    if classification == "trivial" or classification == "minus" or Read(UnitIsTrivial, unit) == true then
        return "Trivial"
    end
    if classification ~= nil and classification ~= "normal" and classification ~= "elite"
        and classification ~= "rare" and classification ~= "rareelite" then return nil end
    local mana = Enum.PowerType.Mana
    -- Match Platynator's Jundies classifier: mana capability takes precedence
    -- over the displayed power type, which can differ on NPCs.
    local usesMana = Read(UnitHasPowerType, unit, mana)
    if type(usesMana) == "boolean" then return usesMana and "Caster" or "Melee" end
    local power, token = UnitPowerType(unit)
    -- These results can be restricted independently. Keep any public hint.
    if not S.Public(power) then power = nil end
    if not S.Public(token) then token = nil end
    if token == "MANA" or power == mana then return "Caster" end
    -- A restricted or absent power hint cannot identify a caster. EQoL's
    -- normal-NPC rule falls back to melee in this case as well.
    return "Melee"
end

-- The parts of an enemy NPC's color role that threat cannot change, stored
-- in facts: eligible (the plate takes a role color at all), focus, neutral
-- (the reaction rule, whose threat-list part stays live) and rest (the role
-- below the threat rules: Tapped, Quest or the type role; false for none).
-- Read on plate setup and on flag, level, classification and quest changes.
function Roles.Base(facts, unit, uf)
    facts.eligible, facts.focus, facts.neutral, facts.rest = false, false, false, false
    local c = Roles.config
    if not Roles.allowed or not c.enemyRoleColors or not S.Public(uf.isFriend) or uf.isFriend ~= false
        or not S.Public(uf.isPlayer) or uf.isPlayer ~= false then return end
    local controlled = UnitPlayerControlled(unit)
    if S.Public(controlled) and controlled == true then return end
    if Read(UnitIsDead, unit) == true or Read(UnitIsConnected, unit) == false then return end
    facts.eligible = true
    if c.enemyFocusEnabled ~= false and Read(UnitIsUnit, unit, "focus") == true then
        facts.focus = true
    elseif Read(UnitIsTapDenied, unit) == true then
        facts.rest = c.enemyTappedEnabled ~= false and "Tapped"
    elseif c.enemyQuestColors and c.enemyQuestEnabled ~= false and facts.quest == true then
        facts.rest = "Quest"
    elseif Read(UnitReaction, unit, "player") == 4 then
        facts.neutral = true
    elseif Read(UnitCanAttack, "player", unit) ~= false then
        local role = facts.kind
        facts.rest = role and c["enemy" .. role .. "Enabled"] ~= false and role
    end
end

-- The color role of a plate from its facts and the current threat. Threat
-- events call only this.
function Roles.Get(facts, unit, uf)
    if not facts.eligible then return nil end
    if facts.focus then return "Focus" end
    local c = Roles.config
    -- A secret threat value only removes the threat override. It must not
    -- suppress the ordinary NPC role color.
    local threat = Threat(uf, unit)
    if c.enemyTankMode and Roles.tank and not threat and OnThreatList(unit) then return "TankMode" end
    if threat then
        local role = threat >= 3 and "ThreatLost" or "ThreatWarning"
        if c["enemy" .. role .. "Enabled"] ~= false then return role end
        return nil
    end
    if facts.neutral then
        return not OnThreatList(unit) and c.enemyNeutralEnabled ~= false and "Neutral" or nil
    end
    return facts.rest or nil
end

function Roles.Marker(unit, classification)
    if classification == "worldboss" then return "boss" end
    if classification == "rare" then return "rare" end
    if classification ~= "elite" and classification ~= "rareelite" then return nil end
    local level = Level(unit)
    if level == -1 or (level and Roles.reference and level == Roles.reference + 2) then return "boss" end
    return "elite"
end

local _, P = ...
local NS, S = P.NS, P.Suite
local Lines, Text = S.TooltipLines, P.TooltipDetailText
local UnitDetails = {}
P.TooltipUnitDetails = UnitDetails

local function Readable(value)
    return S.Public(value) and type(value) == "table" and canaccesstable(value)
end

-- Use an explicit GetUnit argument or the tooltip's own public GUID when
-- Blizzard did not expose a readable token on its name line.
function UnitDetails.Token(tooltip, data)
    local info = tooltip:GetProcessingTooltipInfo()
    if S.Public(info) and info == nil then info = tooltip:GetPrimaryTooltipInfo() end
    if Readable(info) and S.PublicText(info.getterName) == "GetUnit" and Readable(info.getterArgs) then
        local unit = S.PublicText(info.getterArgs[1])
        if unit then return unit end
    end
    local guid = S.PublicText(data.guid)
    if guid and UnitTokenFromGUID then return S.PublicText(UnitTokenFromGUID(guid)) end
end

local function Target(tooltip, unit, highlight)
    local target = unit .. "target"
    local exists = UnitExists(target)
    if S.Public(exists) and exists ~= true then return end
    local name = UnitName(target)
    if S.Public(name) then
        name = S.PublicText(name)
        if not name then return end
    end
    local own
    if highlight then own = UnitIsUnit(target, "player") end
    Text.Line(tooltip, "Target", name, nil, own)
end

local COMBAT_ICON = "|A:UI-HUD-UnitFrame-Player-CombatIcon:14:14|a"
local PVP_ICONS = { Alliance = "|TInterface\\TargetingFrame\\UI-PVP-Alliance:14:14|t",
    Horde = "|TInterface\\TargetingFrame\\UI-PVP-Horde:14:14|t" }
local RANKS = { elite = "Elite", rare = "Rare", rareelite = "Rare Elite", worldboss = "Boss" }

local function FactionAlreadyShown(data, faction)
    local rows = data.lines
    if not Readable(rows) then return false end
    for i = 2, #rows do
        local row = rows[i]
        if Readable(row) and S.PublicText(row.leftText) == faction then return true end
    end
    return false
end

local function Markers(tooltip, data, unit, config)
    local combat, classIcon, pvpIcon, pvpBadge, pvpSecret
    if config.unitCombatStatus then
        local fighting = UnitAffectingCombat(unit)
        if S.Public(fighting) and fighting == true then combat = COMBAT_ICON end
    end
    local faction, factionName
    if config.unitIdentityIcons or config.unitFaction and not config.hideFaction then
        faction, factionName = UnitFactionGroup(unit)
    end
    if config.unitIdentityIcons then
        local player = UnitIsPlayer(unit)
        if S.Public(player) and player == true then
            local _, class = UnitClass(unit)
            class = S.PublicText(class)
            if class then classIcon = "|A:classicon-" .. class:lower() .. ":14:14|a" end
            local factionIcon = PVP_ICONS[S.PublicText(faction)]
            if factionIcon then
                local pvp = UnitIsPVP(unit)
                if NS.IsSecret(pvp) then
                    pvpBadge, pvpSecret = factionIcon, pvp
                elseif pvp == true then
                    pvpIcon = factionIcon
                end
            end
        end
    end
    if combat or classIcon or pvpIcon or pvpBadge then
        local icons = (combat or "") .. (pvpIcon or "") .. (classIcon or "")
        if pvpBadge then Text.Line(tooltip, "Unit status", icons, nil, pvpSecret, pvpBadge)
        else Lines.Line(tooltip, "Unit status", icons) end
    end
    if config.unitFaction and not config.hideFaction then
        local name = S.PublicText(factionName) or S.PublicText(faction)
        if name and not FactionAlreadyShown(data, name) then Lines.Line(tooltip, "Faction", name) end
    end
    if config.unitClassification then
        local rank = RANKS[S.PublicText(UnitClassification(unit))]
        if rank then Lines.Line(tooltip, "Classification", S.Text(rank)) end
    end
end

local function Location(tooltip, unit)
    local own = UnitIsUnit(unit, "player")
    if S.Public(own) and own == true then
        local zone = S.PublicText(GetZoneText())
        local subzone = S.PublicText(GetSubZoneText())
        if zone then Lines.Line(tooltip, "Zone", zone) end
        if subzone and subzone ~= zone then Lines.Line(tooltip, "Subzone", subzone) end
        return
    end
    local party, raid = UnitInParty(unit), UnitInRaid(unit)
    if not (S.Public(party) and party == true or S.Finite(raid) and raid > 0) then return end
    local map = C_Map.GetBestMapForUnit(unit)
    local info = S.Finite(map) and C_Map.GetMapInfo(map)
    local zone = Readable(info) and S.PublicText(info.name)
    if zone then Lines.Line(tooltip, "Zone", zone) end
end

local function GuildRank(tooltip, unit)
    local _, rank, index = GetGuildInfo(unit)
    if NS.IsSecret(rank) then return Text.Line(tooltip, "Guild rank", rank) end
    rank = S.PublicText(rank)
    if not rank then return end
    if S.Finite(index) and index >= 0 then rank = ("%s (%d)"):format(rank, index + 1) end
    Text.Line(tooltip, "Guild rank", rank)
end

-- Forever's committed talent config has differently named groups per class.
-- Use the display order and spent currency used by its native talent frame.
function UnitDetails.OwnTalents()
    local spec, traits = C_SpecializationInfo, C_Traits
    if not spec or not spec.GetCombatConfigIDForSpecGroup or not traits or not traits.GetGroupCurrencyInfo then return end
    local active = spec.GetActiveSpecGroup()
    if not S.Finite(active) then return end
    local id = spec.GetCombatConfigIDForSpecGroup(active)
    if not S.Finite(id) then return end
    local config = traits.GetConfigInfo(id)
    local tree = Readable(config) and Readable(config.treeIDs) and config.treeIDs[1]
    if not S.Finite(tree) then return end
    local groups = traits.GetGroupDisplayInfoByTreeID(tree)
    if not Readable(groups) or #groups == 0 then return end
    local ids = {}
    for i = 1, #groups do
        local group = groups[i]
        if not Readable(group) or not S.Finite(group.groupID) then return end
        ids[i] = group.groupID
    end
    local currencies = traits.GetGroupCurrencyInfo(id, ids)
    if not Readable(currencies) then return end
    local spent = {}
    for i = 1, #currencies do
        local group = currencies[i]
        local currency = Readable(group) and Readable(group.currencyInfos) and group.currencyInfos[1]
        if Readable(currency) and S.Finite(currency.spent) and S.Finite(group.traitNodeGroupID) then
            spent[group.traitNodeGroupID] = currency.spent
        end
    end
    local points, bestCount, best = {}, 0
    for i = 1, #ids do
        local count = spent[ids[i]]
        if count == nil then return end
        points[i] = count
        if count > bestCount then
            bestCount, best = count, S.PublicText(groups[i].displayName)
        elseif count == bestCount then
            best = nil
        end
    end
    if bestCount == 0 then return end
    local allocation = table.concat(points, "/")
    return best and ("%s (%s)"):format(best, allocation) or allocation
end

local function NativeThreat(data)
    local rows = data.lines
    local kind = Enum.TooltipDataLineType.UnitThreat
    if not kind or not Readable(rows) then return false end
    for i = 2, #rows do
        local row = rows[i]
        if Readable(row) and S.Public(row.type) and row.type == kind then return true end
    end
    return false
end

local function Threat(tooltip, data, unit, config)
    local attackable = UnitCanAttack("player", unit)
    if not S.Public(attackable) or attackable ~= true then return end
    local status, percent
    if config.unitThreatPercent and not NativeThreat(data) then
        local _, detailedStatus, scaled = UnitDetailedThreatSituation("player", unit)
        status, percent = detailedStatus, scaled
    end
    if config.unitThreatStatus then
        if not S.Finite(status) then status = UnitThreatSituation("player", unit) end
        if S.Finite(status) then
            local r, g, b = GetThreatStatusColor(status)
            if S.Finite(r) and S.Finite(g) and S.Finite(b) then
                Lines.Line(tooltip, "Threat status", "!", r, g, b)
            end
        end
    end
    if NS.IsSecret(percent) or S.Finite(percent) then Text.Line(tooltip, "Threat", percent, "%.0f%%") end
end

local function SameTarget(source, unit)
    local result = UnitIsUnit(source .. "target", unit)
    if S.Public(result) then return result end
end

local function AddTargeter(source, unit, count, names)
    local result = SameTarget(source, unit)
    if result == nil then return end
    if not result then return count, names end
    count = count + 1
    if count <= 4 then
        local name = S.PublicText(UnitName(source))
        if name then
            names = names or {}
            names[#names + 1] = name
        end
    end
    return count, names
end

local function GroupTargeters(unit, count, names)
    local raid, size = IsInRaid(), GetNumGroupMembers()
    if not S.Public(raid) or not S.Finite(size) then return end
    if not raid then count, names = AddTargeter("player", unit, count, names) end
    for i = 1, raid and size or size - 1 do
        if count == nil then return end
        count, names = AddTargeter((raid and "raid" or "party") .. i, unit, count, names)
    end
    return count, names
end

local function NearbyTargeters(unit, count, names)
    local plates = C_NamePlate.GetNamePlates()
    if not Readable(plates) then return end
    for i = 1, #plates do
        local plate = plates[i]
        if not S.Public(plate) or not plate or NS.Safety.IsForbidden(plate) then return end
        local source = S.PublicText(plate.unitToken)
        if not source then return end
        count, names = AddTargeter(source, unit, count, names)
        if count == nil then return end
    end
    return count, names
end

local function TargetedBy(tooltip, unit, nearby)
    local example = nearby and "nameplate1target" or "party1target"
    local restricted = C_Secrets.ShouldUnitComparisonBeSecret(example, unit)
    if not S.Public(restricted) or restricted ~= false then return end
    local scan = nearby and NearbyTargeters or GroupTargeters
    local count, names = scan(unit, 0)
    if not count or count == 0 then return end
    local value = tostring(count)
    if names then value = value .. " · " .. table.concat(names, ", ") end
    if names and #names < count then value = value .. " …" end
    Lines.Line(tooltip, "Targeted by", value)
end

local function PaintGuild(tooltip, _, unit, config)
    if config.guildRank and not config.hideGuild then GuildRank(tooltip, unit) end
end

local function PaintTarget(tooltip, _, unit, config)
    if config.target then Target(tooltip, unit, config.selfTarget) end
end

local function PaintLocation(tooltip, _, unit, config)
    if config.unitLocation then Location(tooltip, unit) end
end

local function PaintThreat(tooltip, data, unit, config)
    if config.unitThreatStatus or config.unitThreatPercent then Threat(tooltip, data, unit, config) end
end

local function PaintTargeters(tooltip, _, unit, config)
    if config.unitTargeters and config.unitTargeters > 1 then TargetedBy(tooltip, unit, config.unitTargeters == 3) end
end

local painters = { guild = PaintGuild, target = PaintTarget, location = PaintLocation, threat = PaintThreat,
    watchers = PaintTargeters }
local DEFAULT_ORDER = { "guild", "target", "location", "threat", "watchers" }

function UnitDetails.Paint(tooltip, data, unit, config, order)
    if config.unitCombatStatus or config.unitIdentityIcons or config.unitFaction or config.unitClassification then
        Markers(tooltip, data, unit, config)
    end
    order = order or DEFAULT_ORDER
    for index = 1, #order do painters[order[index]](tooltip, data, unit, config) end
end

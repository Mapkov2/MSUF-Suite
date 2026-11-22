local _, private = ...
local NS, S = private.NS, private.Suite
local GROUP_NAMES_ONLY = private.Mode.GROUP_NAMES_ONLY
-- "Names only: party / raid" (Friendly player display): the names of friendly
-- players outside the group fade out. The module's friendlyNames table holds
-- each faded name's alpha from before; group and role changes filter again
-- (Skin.lua RefreshActive).
local Names = {}
private.FriendlyNames = Names
local M
local X = NS.NameplateExtensions
local onlyNames = setmetatable({}, { __mode = "k" })
local nameHooked, colorRevision = nil, 0
local visualFields = { "HealthBarsContainer", "CastBarsContainer", "AurasFrame", "RaidTargetFrame", "ClassificationFrame",
    "PlayerLevelDiffFrame", "WidgetContainer" }

function Names.Bind(module) M = module end

local function Safe(frame)
    return frame and not NS.Safety.IsForbidden(frame)
end

function Names.Restore(name)
    local alpha = name and M.friendlyNames[name]
    if alpha == nil then return end
    if Safe(name) then name:SetAlpha(alpha) end
    M.friendlyNames[name] = nil
end

function Names.Filter(uf, prefix)
    local name = uf.name
    if not Safe(name) then return end
    if M.config.friendlyNamesOnly ~= GROUP_NAMES_ONLY
        or prefix ~= "friendly" or not S.Public(uf.isPlayer) or uf.isPlayer ~= true then
        Names.Restore(name)
        return
    end
    local health = uf.HealthBarsContainer and uf.HealthBarsContainer.healthBar
    local unit = health and M.units[health]
    if not unit then
        Names.Restore(name)
        return
    end
    local party, raid = UnitInParty(unit), UnitInRaid(unit)
    if not S.Public(party) or not S.Public(raid) then
        Names.Restore(name)
        return
    end
    if party or raid then
        Names.Restore(name)
        return
    end
    if M.friendlyNames[name] == nil then
        local hover = private.Mouseover
        if hover.textInUse and not hover.ReleaseName(uf, name) then return end
        local alpha = name:GetAlpha()
        if not NS.Finite(alpha) then return end
        M.friendlyNames[name] = alpha
        -- Alpha survives Blizzard's ordinary name Show()/Hide() refreshes.
        name:SetAlpha(0)
    end
end

local function Writable(uf, region)
    if not Safe(region) then return false end
    if region.CanBeAccessedInContext then
        local accessible = region:CanBeAccessedInContext()
        if not S.Public(accessible) or accessible ~= true then
            if NS.InCombat() then M.pendingPlates[uf] = true end
            return false
        end
    end
    if NS.InCombat() then
        local protected = region:IsProtected()
        if not S.Public(protected) or protected ~= false then
            M.pendingPlates[uf] = true
            return false
        end
    end
    return true
end

-- Some native name FontStrings return RGB without the optional alpha. A
-- missing component is distinct from a restricted value on either client.
local function ReadNameColor(label)
    local r, g, b, a = label:GetVertexColor()
    if not (S.Finite(r) and S.Finite(g) and S.Finite(b)) then return end
    if not S.Finite(a) then
        if not S.Public(a) or a ~= nil then return end
        a = select(4, label:GetTextColor())
        -- With two RGB-only getters the setter takes its optional alpha
        -- as nil. The region's independent fade must stay on the region.
        if not S.Public(a) or a ~= nil and not S.Finite(a) then return end
    end
    return r, g, b, a
end

local function RestoreNameColor(uf, state)
    local label = state.label
    if not label then return true end
    if not Writable(uf, label) then return false end
    local r, g, b, a = ReadNameColor(label)
    if r and r == state.r and g == state.g and b == state.b and a == state.a then
        label:SetVertexColor(state.beforeR, state.beforeG, state.beforeB, state.beforeA)
    end
    state.label = nil
    return true
end

function Names.RestoreNameOnly(uf)
    local state = onlyNames[uf]
    if not state then return end
    if state.scope and private.Layout and private.Layout.InvalidateName then private.Layout.InvalidateName(uf) end
    local hadColor = state.colorR ~= nil
    state.scope, state.questText, state.colorR, state.retryColor, state.revision = nil, nil, nil, nil, nil
    local restored = RestoreNameColor(uf, state)
    if hadColor and private.NameText then private.NameText.ColorOwnerChanged(uf, false) end
    for region, alpha in pairs(state.alphas) do
        if Writable(uf, region) then
            local current = region:GetAlpha()
            if S.Finite(current) and current == 0 then region:SetAlpha(alpha) end
            state.alphas[region] = nil
        else
            restored = false
        end
    end
    if restored then onlyNames[uf] = nil end
end

local function HideRegion(uf, state, region)
    if not Writable(uf, region) then return end
    local alpha = region:GetAlpha()
    if S.Finite(alpha) and alpha ~= 0 then
        state.alphas[region] = alpha
        region:SetAlpha(0)
    end
end

local function ResolveDisplay(uf, unit)
    if Names.neutralNameOnly and S.Public(uf.isPlayer) and uf.isPlayer == false then
        local reaction = UnitReaction(unit, "player")
        if S.Public(reaction) and reaction == 4 then
            -- A neutral NPC can fight without changing its faction reaction.
            if not Names.neutralSplit then return "neutral" end
            local exists = UnitExists(unit)
            if not S.Public(exists) or exists ~= true then return end
            local attackable = UnitCanAttack("player", unit)
            if not S.Public(attackable) or not X.CustomNameOnly(M.config, "neutral", attackable) then return end
            if attackable == false then return "neutral", true end
            local fighting = UnitAffectingCombat(unit)
            if S.Public(fighting) and fighting == false then return "neutral" end
            return
        end
    end
    local scope = X.OpacityScope(X.PlateKind(uf, unit))
    if scope and X.CustomNameOnly(M.config, scope) then return scope end
end

local function NameOnlyRGB(uf, scope, unit, role)
    local config, player = M.config, uf.isPlayer
    if not S.Public(player) or player == nil then return nil, nil, nil, true end
    if player == true and scope == "enemy" and config.enemyPlateNameClassColor then
        local _, class = UnitClass(unit)
        local color = S.Public(class) and type(class) == "string" and RAID_CLASS_COLORS[class]
        if color then return color.r, color.g, color.b end
        return nil, nil, nil, true
    elseif player == false and config[scope .. "PlateNameTypeColor"] then
        return X.NameOnlyNPCColor(config, scope, role)
    end
end

local function ResolveNameColor(uf, state)
    local hadColor = state.colorR ~= nil
    state.colorR, state.colorG, state.colorB, state.retryColor = NameOnlyRGB(uf, state.scope, state.unit, state.role)
    if hadColor ~= (state.colorR ~= nil) and private.NameText then
        private.NameText.ColorOwnerChanged(uf, state.colorR ~= nil)
    end
end

-- Native updates may reset the same label to white, selection red or a
-- shared text color. Only inspect the vertex tint on plates we actually own.
local function ApplyNameColor(uf, state)
    local label = uf.name
    if not Writable(uf, label) then return end
    local r, g, b, a = ReadNameColor(label)
    if not r then return end
    if label == state.label and r == state.r and g == state.g and b == state.b then
        if a ~= state.a then state.beforeA, state.a = a, a end
        if state.appliedR == state.colorR and state.appliedG == state.colorG and state.appliedB == state.colorB then return end
    else
        state.label = label
        state.beforeR, state.beforeG, state.beforeB, state.beforeA = r, g, b, a
    end
    label:SetVertexColor(state.colorR, state.colorG, state.colorB, a)
    -- Native storage can round components. Compare against what it stored.
    state.r, state.g, state.b, state.a = ReadNameColor(label)
    if not state.r then state.label = nil end
    state.appliedR, state.appliedG, state.appliedB = state.colorR, state.colorG, state.colorB
end

function Names.ApplyNameOnly(uf, unit, role)
    local scope, questText
    if Names.nameOnlyEnabled and S.Public(unit) and type(unit) == "string" then scope, questText = ResolveDisplay(uf, unit) end
    if not scope then
        Names.RestoreNameOnly(uf)
        return false
    end
    local state = onlyNames[uf]
    if not state then
        state = { alphas = {} }
        onlyNames[uf] = state
    end
    if state.scope ~= scope and private.Layout and private.Layout.InvalidateName then private.Layout.InvalidateName(uf) end
    if state.scope ~= scope or state.unit ~= unit or state.role ~= role or state.revision ~= colorRevision or state.retryColor then
        state.scope, state.unit, state.role, state.revision = scope, unit, role, colorRevision
        ResolveNameColor(uf, state)
    end
    state.questText = questText
    for _, field in ipairs(visualFields) do HideRegion(uf, state, uf[field]) end
    if state.colorR then ApplyNameColor(uf, state) else RestoreNameColor(uf, state) end
    return true
end

function Names.NameOnlyScope(uf)
    local state = onlyNames[uf]
    return state and state.scope
end

function Names.IsNameOnly(uf) return Names.NameOnlyScope(uf) ~= nil end

function Names.KeepsQuestText(uf)
    local state = onlyNames[uf]
    return state and state.questText
end

function Names.NeutralDisplayChanged(uf, unit)
    local scope, questText = ResolveDisplay(uf, unit)
    local state = onlyNames[uf]
    return scope ~= (state and state.scope) or questText ~= (state and state.questText)
end

function Names.OwnsColor(uf)
    local state = onlyNames[uf]
    return state and state.colorR ~= nil
end

function Names.PaintNameOnly(uf)
    local state = onlyNames[uf]
    if state and state.colorR then ApplyNameColor(uf, state) end
end

function Names.ConfigureNameOnly()
    local config = M.config
    colorRevision = colorRevision + 1
    Names.neutralNameOnly = config.neutralPlateNameOnly == true
    Names.neutralSplit = X.NeutralNameSplit(config)
    Names.nameOnlyEnabled = config.enemyPlateNameOnly or Names.neutralNameOnly or X.CustomNameOnly(config, "friendlyNpc")
    Names.typeColorInUse = config.enemyPlateNameOnly and config.enemyPlateNameTypeColor
    if not Names.nameOnlyEnabled then
        for uf in pairs(onlyNames) do Names.RestoreNameOnly(uf) end
    elseif not nameHooked then
        hooksecurefunc("CompactUnitFrame_UpdateName", function(uf)
            local state = onlyNames[uf]
            if not M.active or not state then return end
            if state.retryColor then ResolveNameColor(uf, state) end
            if state.colorR then ApplyNameColor(uf, state) end
        end)
        nameHooked = true
    end
end

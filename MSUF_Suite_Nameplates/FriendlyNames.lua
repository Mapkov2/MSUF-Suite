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
        local alpha = name:GetAlpha()
        if not NS.Finite(alpha) then return end
        M.friendlyNames[name] = alpha
        -- Alpha survives Blizzard's ordinary name Show()/Hide() refreshes.
        name:SetAlpha(0)
    end
end

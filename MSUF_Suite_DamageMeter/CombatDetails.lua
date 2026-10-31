local _, P = ...
local D, S, NS = P.DamageMeter, P.Suite, P.NS
local M, Public, Finite = D.M, S.Public, S.Finite
local partyUnits = { "player", "party1", "party2", "party3", "party4" }
local identities, rosterClasses, rosterGUIDs = {}, {}, {}

function D.WantsGroupDetails()
    local _, kind = IsInInstance()
    return M.config.combatDetails and kind == "party"
end

function D.ClearIdentities()
    for key in pairs(identities) do identities[key] = nil end
    for key in pairs(rosterClasses) do rosterClasses[key] = nil end
    for key in pairs(rosterGUIDs) do rosterGUIDs[key] = nil end
end

-- Only a class represented by ONE current party member can bridge a secret
-- row. Spec-only uniqueness is insufficient: another same-class player may
-- first enter the native meter mid-pull. Raids and identity-restricted zones
-- stay on the ordinary plain-identity path.
local function ReadParty()
    if not D.WantsGroupDetails() then return false end
    for i = 1, #partyUnits do
        local unit = partyUnits[i]
        local guid, class = UnitGUID(unit), UnitClassBase(unit)
        if Public(guid) and type(guid) == "string" and Public(class) and type(class) == "string" then
            rosterGUIDs[guid] = class
            if rosterClasses[class] ~= nil then rosterClasses[class] = false else rosterClasses[class] = guid end
        end
    end
    return true
end

function D.SnapshotIdentities()
    if M.inCombat or NS.IsCombatLocked() then return end
    D.ClearIdentities()
    if not M.anyShown or not M.dataVisible or not ReadParty() then return end
    local session = C_DamageMeter.GetCombatSessionFromType(D.OVERALL, D.TYPE.DamageDone)
    local sources = session and session.combatSources
    for i = 1, D.Count(sources) do
        local source = sources[i]
        local guid, class, spec = source.sourceGUID, source.classFilename, source.specIconID
        if Public(class) and type(class) == "string" and Finite(spec) and spec > 0 then
            if identities[class] ~= nil then
                identities[class] = false
            elseif Public(guid) and type(guid) == "string"
                and rosterClasses[class] == guid and rosterGUIDs[guid] == class then
                identities[class] = { guid = guid, spec = spec }
            else
                identities[class] = false
            end
        end
    end
end

function D.GroupIdentity(source, win)
    -- The snapshot covers live damage sources only. A historical or healing
    -- row can refer to a departed player absent from that source set.
    if not win or win.sessionID or not D.damageTypes[win.meterType] or not M.config.combatDetails then return nil end
    local _, kind = IsInInstance()
    if kind ~= "party" then return nil end
    local class, spec = source.classFilename, source.specIconID
    if not Public(class) or type(class) ~= "string" or not Finite(spec) then return nil end
    local entry = identities[class]
    if entry and entry.spec == spec then return entry.guid end
end

function D.PositionTip(frame, win, row)
    frame:ClearAllPoints()
    local anchor = M.config.tooltipAnchor
    if anchor == 2 then frame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    elseif anchor == 3 then frame:SetPoint("TOPRIGHT", win.frame, "TOPLEFT", -4, 0)
    elseif anchor == 4 then frame:SetPoint("TOPLEFT", win.frame, "TOPRIGHT", 4, 0)
    else frame:SetPoint("BOTTOMLEFT", row, "TOPLEFT", 0, 4) end
end

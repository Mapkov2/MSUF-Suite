local _, P = ...
local D, S, NS = P.DamageMeter, P.Suite, P.NS
local M, Public, Finite = D.M, S.Public, S.Finite
local partyUnits = { "player", "party1", "party2", "party3", "party4" }
local identities, rosterClasses, rosterGUIDs = {}, {}, {}
local changedSpecs, inspectQueue = {}, {}
local inspectGUID, inspectAfter, issuingInspect, inspectHooked = nil, 0, false, false
local INSPECT_QUIET, INSPECT_TIMEOUT = 5, 10
local InspectNext

local function GroupUnit(guid)
    local unit = S.PublicText(UnitTokenFromGUID(guid))
    if not unit or S.PublicText(UnitGUID(unit)) ~= guid then return end
    local member = UnitInAnyGroup(unit)
    if Public(member) and member == true then return unit end
end

local function InspectAllowed()
    return M.remoteSpecs and not M.inCombat and not NS.IsCombatLocked()
end

local function ResumeSpecInspects()
    if InspectAllowed() and not inspectGUID and next(inspectQueue) then
        M.context:Coalesce(math.max(.1, inspectAfter - GetTime()), InspectNext):Request()
    end
end

local function NativeInspectBusy()
    local frame, spells = InspectFrame, PlayerSpellsFrame
    return frame and (frame:IsShown() or S.PublicText(frame.unit)) or spells and spells:IsInspecting()
end

-- The native Inspect buffer is shared. Give manual and other addon requests
-- priority, and discard our in-flight result if someone takes over the buffer.
local function InspectTraffic()
    if not M.watchRemoteSpecs then return end
    inspectAfter = GetTime() + INSPECT_QUIET
    if issuingInspect then return end
    if inspectGUID then
        inspectQueue[inspectGUID], inspectGUID = true, nil
        M.context:Cancel(InspectNext)
    end
    ResumeSpecInspects()
end

InspectNext = function()
    local expired = inspectGUID
    inspectGUID = nil
    if not InspectAllowed() then
        if expired then inspectQueue[expired] = true end
        return
    end
    if GetTime() < inspectAfter then
        ResumeSpecInspects()
        return
    end
    if NativeInspectBusy() then return end
    for guid in pairs(inspectQueue) do
        local unit = GroupUnit(guid)
        if unit then
            local allowed = CanInspect(unit, true)
            if Public(allowed) and allowed == true then
                inspectQueue[guid] = nil
                inspectGUID, issuingInspect = guid, true
                local sent = S.Dispatch(NS.Finish, NotifyInspect, unit)
                issuingInspect = false
                if sent then
                    M.context:Coalesce(INSPECT_TIMEOUT, InspectNext):Request()
                    return
                end
                inspectGUID = nil
            end
        end
    end
end

local function RepaintLiveSpecs()
    for i = 1, M.config.windowCount do
        local win = D.windows[i]
        if win and win.shown and not win.sessionID and win.meterType ~= D.THREAT then win.dirty = true end
    end
    D.RequestPaint()
end

function D.RemoteSpecChanged(unit)
    if not M.watchRemoteSpecs then return end
    local guid = S.PublicText(UnitGUID(unit))
    local own = S.PublicText(UnitGUID("player"))
    if not guid or not own or guid == own then return end
    local member = UnitInAnyGroup(unit)
    if not Public(member) or member ~= true then return end
    if not inspectHooked then
        hooksecurefunc("NotifyInspect", InspectTraffic)
        hooksecurefunc("ClearInspectPlayer", InspectTraffic)
        inspectHooked = true
    end
    -- Zero means the old specialization is invalid. Use the class until a
    -- matching inspect response supplies the new one.
    changedSpecs[guid], inspectQueue[guid], M.remoteSpecs = 0, true, changedSpecs
    D.UpdateEvents()
    RepaintLiveSpecs()
    ResumeSpecInspects()
end

function D.RemoteSpecReady(_, _, guid)
    if not Public(guid) or guid ~= inspectGUID then return end
    inspectGUID = nil
    M.context:Cancel(InspectNext)
    if not InspectAllowed() then
        if changedSpecs[guid] then inspectQueue[guid] = true end
        return
    end
    if changedSpecs[guid] and not inspectQueue[guid] then
        local unit = GroupUnit(guid)
        local id = unit and C_SpecializationInfo.GetInspectSpecialization(unit)
        if Finite(id) and id > 0 then
            local icon = select(4, GetSpecializationInfoByID(id))
            if Finite(icon) and icon > 0 then
                changedSpecs[guid] = icon
                RepaintLiveSpecs()
            end
        end
    end
    ResumeSpecInspects()
end

function D.ClearRemoteSpecs()
    if not M.remoteSpecs then return end
    M.remoteSpecs, inspectGUID = nil, nil
    for guid in pairs(changedSpecs) do changedSpecs[guid], inspectQueue[guid] = nil, nil end
    M.context:Cancel(InspectNext)
end

function D.PruneRemoteSpecs()
    if not InspectAllowed() then return end
    local changed = false
    for guid in pairs(changedSpecs) do
        if not GroupUnit(guid) then
            changedSpecs[guid], inspectQueue[guid], changed = nil, nil, true
            if inspectGUID == guid then
                inspectGUID = nil
                M.context:Cancel(InspectNext)
            end
        end
    end
    if not next(changedSpecs) then D.ClearRemoteSpecs() end
    if changed then
        RepaintLiveSpecs()
        D.UpdateEvents()
    end
    ResumeSpecInspects()
end

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

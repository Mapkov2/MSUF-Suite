local _, NS = ...
local Suite, Host, Public, Number = NS.Suite, NS.Host, NS.Public, NS.Number
local Mount = Host.UnitMount
local BASE_SPEED = Number(BASE_MOVEMENT_SPEED) or 7
local SPEED_INTERVAL = 0.25
local Travel = { row = { label = NS.Text("Speed") } }
NS.Travel = Travel

local summaryRows = { { label = NS.Text("Class") }, { label = NS.Text("Level") } }
local summary = { title = NS.Text("Inspect"), rows = summaryRows }

function Travel.Summary(class, level)
    summaryRows[1].value = class or "—"
    summaryRows[2].value = level or "—"
    summaryRows[3] = Travel.row.value ~= nil and Travel.row or nil
    return summary
end

local context, unit, guid, changed, identityLost
local mounted, mountInstance, speed, restrictionJob

local function PublicTable(value)
    return Public(value) and type(value) == "table" and canaccesstable(value)
end

local function CheckIdentity()
    if not context then return false end
    if NS.String(UnitGUID(unit)) == guid then return true end
    identityLost()
    return false
end

local function ReadSpeed()
    local current = Number((GetUnitSpeed(unit)))
    local percent = current and math.floor(current / BASE_SPEED * 100 + 0.5)
    if speed == percent then return false end
    speed = percent
    Travel.row.value = percent and string.format("%d%%", percent) or nil
    return true
end

local function Tick()
    if not mounted or not CheckIdentity() then return end
    local wasVisible = speed ~= nil
    if ReadSpeed() then changed(wasVisible ~= (speed ~= nil)) end
end

local function SetMount(name, instanceID, quiet)
    mountInstance = instanceID
    local isMounted = name ~= nil
    if mounted == isMounted then return end
    local wasVisible = speed ~= nil
    mounted = isMounted
    if mounted then
        ReadSpeed()
        context:Ticker(SPEED_INTERVAL, Tick)
    else
        context:Cancel(Tick)
        speed, Travel.row.value = nil, nil
    end
    if not quiet and wasVisible ~= (speed ~= nil) then changed(true) end
end

local function ReadMount(quiet)
    if not quiet and not CheckIdentity() then return end
    local name, _, instanceID = Suite.Dispatch(Mount.Read, unit)
    SetMount(name, instanceID, quiet)
end

local function TouchesMount(ids)
    if not Public(ids) then return true end
    if ids == nil then return false end
    if not PublicTable(ids) then return true end
    for i = 1, #ids do
        local id = Number(ids[i])
        if not id or not mountInstance or id == mountInstance then return true end
    end
    return false
end

local function AuraChanged(_, _, token, update)
    if not context or not Public(token) or token ~= unit or restrictionJob.pending then return end
    local restricted = C_Secrets.ShouldAurasBeSecret()
    if not Public(restricted) or restricted ~= false then
        if mounted and CheckIdentity() then SetMount() end
        return
    end
    if not PublicTable(update) then ReadMount() return end
    local full = update.isFullUpdate
    if not Public(full) or full then ReadMount() return end

    local added = update.addedAuras
    if not Public(added) or added ~= nil and not PublicTable(added) then ReadMount() return end
    if added then
        for i = 1, #added do
            local aura = added[i]
            if PublicTable(aura) then
                local helpful = aura.isHelpful
                if Public(helpful) and helpful == true then
                    local name, _, instanceID = Mount.FromAura(aura)
                    if name then
                        if CheckIdentity() then SetMount(name, instanceID) end
                        return
                    end
                end
            end
        end
    end
    if mounted and (TouchesMount(update.removedAuraInstanceIDs) or TouchesMount(update.updatedAuraInstanceIDs)) then
        ReadMount()
    end
end

local function RefreshAfterRestriction()
    ReadMount()
end

local function RestrictionChanged(_, _, _, state)
    if Public(state) and state == Enum.AddOnRestrictionState.Inactive then
        restrictionJob:Clear()
        ReadMount()
    elseif CheckIdentity() then
        -- Activation is dispatched before the new restriction takes effect.
        SetMount()
        restrictionJob:Request()
    end
end

function Travel.Stop()
    if not context then return end
    context:RemoveEvent("UNIT_AURA")
    context:RemoveEvent("ADDON_RESTRICTION_STATE_CHANGED")
    if mounted then context:Cancel(Tick) end
    restrictionJob:Clear()
    restrictionJob = nil
    context, unit, guid, changed, identityLost = nil, nil, nil, nil, nil
    mounted, mountInstance, speed, Travel.row.value = nil, nil, nil, nil
end

function Travel.Start(owner, token, identity, onChange, onIdentityLost)
    if context == owner and unit == token and guid == identity then return end
    Travel.Stop()
    context, unit, guid, changed, identityLost = owner, token, identity, onChange, onIdentityLost
    mounted = false
    restrictionJob = context:Coalesce(0, RefreshAfterRestriction)
    ReadMount(true)
    context:Event("UNIT_AURA", AuraChanged, nil, unit)
    context:Event("ADDON_RESTRICTION_STATE_CHANGED", RestrictionChanged)
end

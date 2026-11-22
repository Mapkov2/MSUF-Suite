local _, P = ...
local D, S = P.DamageMeter, P.Suite
local M = D.M
local NS = P.NS
local VISIBILITY, GROUP = D.VISIBILITY, NS.DamageMeterGroupCondition
local load = {}
M.load = load

local function HasTarget()
    local exists = UnitExists("target")
    return S.Public(exists) and exists == true
end

function D.LoadTargetChanged()
    return HasTarget() ~= load.hasTarget
end

function D.WindowVisibility(index)
    return NS.DamageMeterWindowVisibility(M.config, D.KEYS[index].LoadVisibility)
end

-- Reused between visibility transitions. Paints and hover changes consume
-- the event interest without rechecking game context.
function D.ReadLoadConditions()
    local c = M.config
    load.possible, load.combat, load.group, load.target = false, false, false, false
    for i = 1, c.windowCount do
        local keys, mode = D.KEYS[i], D.WindowVisibility(i)
        local group = c[keys.GroupCondition] or GROUP.ANY
        load[i] = mode
        if mode ~= VISIBILITY.NEVER then
            load.possible = true
            load.combat = load.combat or mode == VISIBILITY.COMBAT
            load.group = load.group or mode == VISIBILITY.GROUP or group ~= GROUP.ANY
            load.target = load.target or c[keys.RequireTarget] == true
        end
    end
    load.zone, load.grouped, load.hasTarget = nil, nil, false
    if not load.possible or M.forced or M.sessionHidden then return end
    load.zone = D.ZoneKey()
    if load.group then
        local grouped = IsInGroup()
        if S.Public(grouped) and type(grouped) == "boolean" then load.grouped = grouped end
    end
    if load.target then load.hasTarget = HasTarget() end
end

function D.WindowLoadState(index)
    if M.forced then return true, false end
    local c, keys, mode = M.config, D.KEYS[index], load[index]
    if M.sessionHidden or mode == VISIBILITY.NEVER then return false, false end
    if load.zone and c[keys[load.zone]] then return false, false end
    local group = c[keys.GroupCondition]
    if (mode == VISIBILITY.GROUP or group == GROUP.GROUP) and load.grouped ~= true then return false, false end
    if group == GROUP.SOLO and load.grouped ~= false then return false, false end
    if c[keys.RequireTarget] and not load.hasTarget then return false, false end
    if mode == VISIBILITY.COMBAT then
        return M.inCombat == true, not M.inCombat and M.available
    end
    return mode ~= VISIBILITY.OUT_OF_COMBAT or not M.inCombat, false
end

-- This owned, eventless child follows UIParent's effective visibility.
-- Native OnShow/OnHide propagation keeps visibility queries off paint paths.
local function VisibilityChanged(frame)
    if not M.active then return end
    local hidden = not frame:IsVisible()
    if hidden == M.uiHidden then return end
    M.uiHidden = hidden
    for i = 1, M.config.windowCount do
        local win = D.windows[i]
        if win and win.shown then D.ApplyHover(win, true) end
    end
    D.SyncWatch()
    D.UpdateEvents()
    D.CancelPaint()
    D.UpdateTimer()
    D.SyncClock()
    if hidden then
        D.timerJob:Clear()
        D.lateJob:Clear()
        if D.threatJob then D.threatJob:Clear() end
    else
        D.SnapshotIdentities()
        D.PaintDirty()
        D.SyncClock()
    end
end

function D.TrackUIVisibility()
    local frame = M.visibilityProbe
    if not frame then
        frame = S.CreateFrame("Frame", nil, UIParent)
        frame:EnableMouse(false)
        M.visibilityProbe = frame
    end
    frame:SetScript("OnShow", VisibilityChanged)
    frame:SetScript("OnHide", VisibilityChanged)
    M.uiHidden = not frame:IsVisible()
end

function D.UntrackUIVisibility()
    local frame = M.visibilityProbe
    if not frame then return end
    frame:SetScript("OnShow", nil)
    frame:SetScript("OnHide", nil)
end

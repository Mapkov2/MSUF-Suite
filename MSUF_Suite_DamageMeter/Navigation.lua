local _, P = ...
local D, S, NS = P.DamageMeter, P.Suite, P.NS
local M = D.M

function D.AutoCurrent(win)
    local value = M.config[D.KEYS[win.index].AutoCurrent]
    if value == 2 then return true end
    if value == 3 then return false end
    return M.config.autoCurrent
end

local function ChangeSession(win, value, sessionID, duration, writes)
    D.ApplySession(win, value, sessionID, duration)
    D.CloseBreakdown(win, true)
    win.offset, win.timerSecond, win.dirty = 0, false, true
    D.UpdateTitle(win)
    writes[D.KEYS[win.index].Session] = value
end

local function CommitSelection(writes)
    if D.PersistMany(writes) then return end
    -- Pins and combat picks change no saved style. Refresh only the headers
    -- whose meter type changed, then paint all selected windows in one pass.
    for i = 1, M.config.windowCount do
        if writes[D.KEYS[i].Type] ~= nil then D.StyleHeader(D.windows[i]) end
    end
    D.PaintDirty()
end

function D.SelectSession(win, value, sessionID, duration)
    local writes = {}
    local sync = win.meterType ~= D.THREAT and M.config[D.KEYS[win.index].SyncSession]
    for i = 1, M.config.windowCount do
        local other = D.windows[i]
        if other and (other == win or (sync and M.config[D.KEYS[i].SyncSession] and other.meterType ~= D.THREAT)) then
            ChangeSession(other, value, sessionID, duration, writes)
        end
    end
    CommitSelection(writes)
end

function D.MythicStart()
    if NS.Client.isForever then return end
    local writes = {}
    for i = 1, M.config.windowCount do
        local win, keys = D.windows[i], D.KEYS[i]
        if win then
            local meter = M.config[keys.MythicType]
            if meter > 1 then D.SetWindowType(win, meter - 2, writes) end
            if M.config[keys.MythicSwap] and win.meterType ~= D.THREAT then
                ChangeSession(win, D.SESSION.CURRENT, nil, nil, writes)
            end
        end
    end
    CommitSelection(writes)
end

function D.MythicEnd()
    if NS.Client.isForever then return end
    local writes = {}
    for i = 1, M.config.windowCount do
        local win = D.windows[i]
        if win and not win.sessionID and M.config[D.KEYS[i].MythicSwap] and win.meterType ~= D.THREAT then
            ChangeSession(win, D.SESSION.OVERALL, nil, nil, writes)
        end
    end
    CommitSelection(writes)
end

-- Meter per role: each window picks a meter (or Keep) for tank, healer and
-- damage dealer. The pick applies at the first world entry of a session and
-- when a specialization change brings another role. Mythic+ precedence: a
-- window with a Mythic+ meter (MythicType) belongs to that choice from the
-- key's start to its end, so a role pick skips it while a key runs (a login
-- in a running key). The key's start (D.MythicStart) applies after any role
-- pick and wins. A Mythic+ choice of Keep leaves the window to its role.
-- WoW Forever has no Mythic+ choices, so its roles always apply.
local ROLE_KEYS = { TANK = "RoleTank", HEALER = "RoleHealer", DAMAGER = "RoleDamager" }

-- The setting suffix of the current specialization's role, or nil.
local function PlayerRole()
    local index = C_SpecializationInfo.GetSpecialization()
    if not S.Finite(index) or index < 1 then return nil end
    local role = select(5, C_SpecializationInfo.GetSpecializationInfo(index))
    return S.Public(role) and ROLE_KEYS[role] or nil
end

local function KeyOwnsWindow(keys)
    return not NS.Client.isForever and M.config[keys.MythicType] > 1 and C_ChallengeMode.IsChallengeModeActive() == true
end

function D.ApplyRoleMeters()
    local role = PlayerRole()
    M.role = role
    if not role then return end
    local writes = {}
    for i = 1, M.config.windowCount do
        local win, keys = D.windows[i], D.KEYS[i]
        local meter = M.config[keys[role]]
        if meter > 1 and not KeyOwnsWindow(keys) then
            if win then D.SetWindowType(win, meter - 2, writes) else writes[keys.Type] = meter - 1 end
        end
    end
    if next(writes) then CommitSelection(writes) end
end

-- PLAYER_SPECIALIZATION_CHANGED: a change inside one role keeps a meter the
-- player picked by hand.
function D.RoleChanged()
    if PlayerRole() ~= M.role then D.ApplyRoleMeters() end
end

function D.WantsRoleMeters()
    for i = 1, M.config.windowCount do
        local keys = D.KEYS[i]
        if M.config[keys.RoleTank] > 1 or M.config[keys.RoleHealer] > 1 or M.config[keys.RoleDamager] > 1 then
            return true
        end
    end
    return false
end

function D.WantsMythicEvents()
    if NS.Client.isForever then return false end
    if M.config.mythicReset then return true end
    for i = 1, M.config.windowCount do
        local keys = D.KEYS[i]
        if M.config[keys.MythicSwap] or M.config[keys.MythicType] > 1 then return true end
    end
    return false
end

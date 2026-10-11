local _, private = ...
local NS, S = private.NS, private.Suite
-- Click-through for Blizzard's nameplate aura buttons. A protected button
-- refuses SetMouseClickEnabled in combat with ADDON_ACTION_BLOCKED, which is
-- not a Lua error, so such a change waits for the end of combat.
local Auras = {}
private.Auras = Auras
local M
-- Click-through is a property of a pooled button frame. Blizzard's pool
-- reset (Blizzard_NamePlateAuras.lua auraItemFrameResetCallback) and
-- RefreshAuras never touch its mouse state (live and forever), and a pool
-- makes a new button only when every button it has is active. Once a walk
-- left every active button click-through, peaks[pool] keeps that active
-- count: a later refresh with no more active buttons can only show buttons
-- that already are, so one GetNumActive replaces the walk. The 2026-10-07
-- raid trace ran 1,716 pool walks in 60 s (ApplyPool 11.5 ms self through
-- the secure pool proxy, SetClickthrough 7.3 ms) for 1,368 buttons.
-- Restore hands clicks back and forgets every peak; a button that could
-- not change (protected in combat) or read as secret leaves its pool
-- without a peak, so the next refresh walks again.
local peaks = setmetatable({}, { __mode = "k" })

function Auras.Bind(module) M = module end

local function Safe(frame)
    return frame and not NS.Safety.IsForbidden(frame)
end

-- IsProtected also reports implicit protection (a secure descendant).
local function CanChange(button)
    if not NS.IsCombatLocked() then return true end
    local protected = button:IsProtected()
    return S.Public(protected) and protected == false
end

local function OnCombatEnd(frame)
    if NS.IsCombatLocked() then return end
    frame:UnregisterEvent("PLAYER_REGEN_ENABLED")
    Auras.Restore()
end

function Auras.Restore()
    for pool in pairs(peaks) do peaks[pool] = nil end
    local waiting = false
    for button, enabled in pairs(M.auraButtons) do
        if not Safe(button) then
            M.auraButtons[button] = nil
        elseif CanChange(button) then
            button:SetMouseClickEnabled(enabled)
            M.auraButtons[button] = nil
        else
            waiting = true
        end
    end
    if not waiting then return end
    if not M.auraRestoreFrame then
        M.auraRestoreFrame = CreateFrame("Frame")
        M.auraRestoreFrame:SetScript("OnEvent", OnCombatEnd)
    end
    M.auraRestoreFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
end

-- True when the button needs nothing more: click-through now, or forbidden
-- (never touched).
local function SetClickthrough(button)
    if not Safe(button) then return true end
    local current = button:IsMouseClickEnabled()
    if not S.Public(current) then return false end
    if current ~= true then return true end
    if not CanChange(button) then
        M.needsRefresh = true
        return false
    end
    if M.auraButtons[button] == nil then M.auraButtons[button] = current end
    button:SetMouseClickEnabled(false)
    return true
end

-- GetNextActive (Blizzard_SharedXMLBase Pools.lua, both clients) visits the
-- active buttons without the iterator closure EnumerateActive allocates;
-- GetNumActive is on the same pool proxy (ObjectPoolProxyMixin, both clients).
local function ApplyPool(pool)
    if not M.active or not M.config.auraClickthrough or not pool then return end
    local count = pool:GetNumActive()
    if not S.Public(count) or type(count) ~= "number" then count = nil end
    local peak = peaks[pool]
    if count and peak and count <= peak then return end
    local done = count ~= nil
    local button = pool:GetNextActive()
    while button do
        if not SetClickthrough(button) then done = false end
        button = pool:GetNextActive(button)
    end
    peaks[pool] = done and count or nil
end

local function LossOfControlItem(auras)
    return auras.LossOfControlFrame and auras.LossOfControlFrame.AuraItemFrame
end

local function OnRefreshAuras(auras)
    ApplyPool(auras.auraItemFramePool)
end

local function OnRefreshLossOfControl(auras)
    if not M.active or not M.config.auraClickthrough then return end
    local item = LossOfControlItem(auras)
    if item then SetClickthrough(item) end
end

function Auras.Apply(uf)
    if not M.config.auraClickthrough then
        if next(M.auraButtons) then Auras.Restore() end
        return
    end
    local auras = uf.AurasFrame
    if not Safe(auras) then return end
    if not M.auraHooks[auras] then
        hooksecurefunc(auras, "RefreshAuras", OnRefreshAuras)
        hooksecurefunc(auras, "RefreshLossOfControl", OnRefreshLossOfControl)
        M.auraHooks[auras] = true
    end
    ApplyPool(auras.auraItemFramePool)
    local item = LossOfControlItem(auras)
    if item then SetClickthrough(item) end
end

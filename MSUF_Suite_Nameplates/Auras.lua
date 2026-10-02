local _, private = ...
local NS, S = private.NS, private.Suite
-- Click-through for Blizzard's nameplate aura buttons. A protected button
-- refuses SetMouseClickEnabled in combat with ADDON_ACTION_BLOCKED, which is
-- not a Lua error, so such a change waits for the end of combat.
local Auras = {}
private.Auras = Auras
local M

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

local function SetClickthrough(button)
    if not Safe(button) then return end
    local current = button:IsMouseClickEnabled()
    if not S.Public(current) or current ~= true then return end
    if not CanChange(button) then
        M.needsRefresh = true
        return
    end
    if M.auraButtons[button] == nil then M.auraButtons[button] = current end
    button:SetMouseClickEnabled(false)
end

-- GetNextActive (Blizzard_SharedXMLBase Pools.lua, both clients) visits the
-- active buttons without the iterator closure EnumerateActive allocates.
local function ApplyPool(pool)
    if not M.active or not M.config.auraClickthrough or not pool then return end
    local button = pool:GetNextActive()
    while button do
        SetClickthrough(button)
        button = pool:GetNextActive(button)
    end
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

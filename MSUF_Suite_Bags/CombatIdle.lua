local _, P = ...
local NS, S, M = P.NS, P.Suite, P.BagsModule
-- A visible bag or bank owns the slot and equipment observers. Pickup
-- counts may also observe slots between openings outside combat.
local Idle = { paused = false }
P.BagsIdle = Idle

local function BagShown()
    if M.frame and M.frame:IsVisible() or ContainerFrame6:IsVisible() then return true end
    if M.standaloneFrames then
        for _, frame in ipairs(M.standaloneFrames) do
            if frame:IsVisible() then return true end
        end
    end
    return false
end

local function OrganizedBankShown()
    return BankFrame.BankPanel:IsVisible() and M.config.bankView ~= NS.BagsBankView.TABS
        and not (NS.Client.isForever and S.GamepadUI())
end

local function WindowShown()
    return BagShown() or BankFrame:IsVisible()
end

-- Pickup totals deliberately observe changes between window openings. A
-- plain Recent list reads Blizzard's new-item flags when it is displayed.
function Idle.NeedsSlotEvents()
    return M.active and (BagShown() or OrganizedBankShown()
        or P.InventoryView.active and P.InventoryView.recentCountsActive and not NS.InCombat())
end

local function SyncSlotEvents()
    if Idle.NeedsSlotEvents() then P.SlotCache.Resume() else P.SlotCache.Pause() end
end

-- Character eligibility and upgrade arrows belong to Suite item lists.
-- A standalone reagent bag or the native Blizzard grid has no such rows.
local function SyncEquipment(force)
    local visible = M.frame and M.frame:IsVisible() and P.InventoryView.active
        or OrganizedBankShown()
        or false
    if visible == Idle.equipmentVisible and not (force and not visible) then return end
    Idle.equipmentVisible = visible
    if visible then
        P.PlayerGear.Resume()
        P.UpgradeMarker.Resume()
        P.InventoryDetails.Invalidate()
    else
        P.PlayerGear.Pause()
        P.UpgradeMarker.Pause()
    end
end

function Idle.Pause()
    if Idle.paused or not M.active or WindowShown() then return end
    Idle.paused = true
    P.SlotCache.Pause()
    P.InventoryView.Pause()
    P.BagFinance.Pause()
    M:WatchBackpackBindings(false)
    M:PauseItemInfo()
end

function Idle.Wake()
    if not Idle.paused then return end
    Idle.paused = false
    SyncSlotEvents()
    P.InventoryView.Resume()
    P.BagFinance.Resume()
    M:WatchBackpackBindings(true)
    if NS.Client.isForever then P.EquippedBags.RefreshBackpackBindings(M) end
    M:ResumeItemInfo()
end

local function OnEvent(_, event)
    if event == "PLAYER_REGEN_DISABLED" then Idle.Pause() else Idle.Wake() end
end

local function WindowOpened()
    if not M.active then return end
    Idle.Wake()
    SyncSlotEvents()
    SyncEquipment()
end

local function WindowHidden()
    if not M.active then return end
    SyncSlotEvents()
    SyncEquipment()
    if NS.InCombat() then Idle.Pause() end
end

local function WatchWindow(frame)
    frame:HookScript("OnShow", WindowOpened)
    frame:HookScript("OnHide", WindowHidden)
end

-- Runs after every other Bags refresh (Bags.lua SUBMODULES), which may have
-- restarted a paused listener.
function Idle.Refresh()
    if not Idle.events then
        Idle.events = S.CreateFrame("Frame")
        Idle.events:SetScript("OnEvent", OnEvent)
        for _, frame in ipairs({ M.frame, ContainerFrame6, BankFrame, BankFrame.BankPanel }) do WatchWindow(frame) end
        if M.standaloneFrames then
            for _, frame in ipairs(M.standaloneFrames) do WatchWindow(frame) end
        end
    end
    Idle.events:RegisterEvent("PLAYER_REGEN_DISABLED")
    Idle.events:RegisterEvent("PLAYER_REGEN_ENABLED")
    Idle.Wake()
    SyncSlotEvents()
    SyncEquipment(true)
    if NS.InCombat() then Idle.Pause() end
end

-- Every listener's own stop runs too; nothing is left to resume.
function Idle.Disable()
    if Idle.events then Idle.events:UnregisterAllEvents() end
    Idle.paused, Idle.equipmentVisible = false, nil
end

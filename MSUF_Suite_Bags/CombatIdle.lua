local _, P = ...
local NS, S, M = P.NS, P.Suite, P.BagsModule
-- In a fight with no bag window open (the combined bag, the reagent bag or
-- the bank), the Bags run no code for that fight's events. At
-- PLAYER_REGEN_DISABLED, or when the last window closes in combat, every
-- listener below pauses. Each one marks what it may have missed as stale
-- when it resumes: when a window opens in combat, or when the fight ends.
-- SlotCache also resumes by itself at its first read.
local Idle = { paused = false }
P.BagsIdle = Idle

local function WindowShown()
    return M.frame ~= nil and M.frame:IsShown() or ContainerFrame6:IsShown() or BankFrame:IsShown()
end

function Idle.Pause()
    if Idle.paused or not M.active or WindowShown() then return end
    Idle.paused = true
    P.SlotCache.Pause()
    P.InventoryView.Pause()
    P.PlayerGear.Pause()
    P.UpgradeMarker.Pause()
    P.BagFinance.Pause()
    M:PauseItemInfo()
    M:PauseGoldEvents()
end

function Idle.Wake()
    if not Idle.paused then return end
    Idle.paused = false
    P.SlotCache.Resume()
    P.InventoryView.Resume()
    P.PlayerGear.Resume()
    P.UpgradeMarker.Resume()
    P.BagFinance.Resume()
    M:ResumeItemInfo()
    M:ResumeGoldEvents()
end

local function OnEvent(_, event)
    if event == "PLAYER_REGEN_DISABLED" then Idle.Pause() else Idle.Wake() end
end

local function WindowHidden()
    if NS.InCombat() then Idle.Pause() end
end

-- Runs after every other Bags refresh (Bags.lua SUBMODULES), which may have
-- restarted a paused listener.
function Idle.Refresh()
    if not Idle.events then
        Idle.events = S.CreateFrame("Frame")
        Idle.events:SetScript("OnEvent", OnEvent)
        for _, frame in ipairs({ M.frame, ContainerFrame6, BankFrame }) do
            frame:HookScript("OnShow", Idle.Wake)
            frame:HookScript("OnHide", WindowHidden)
        end
    end
    Idle.events:RegisterEvent("PLAYER_REGEN_DISABLED")
    Idle.events:RegisterEvent("PLAYER_REGEN_ENABLED")
    Idle.Wake()
    if NS.InCombat() then Idle.Pause() end
end

-- Every listener's own stop runs too; nothing is left to resume.
function Idle.Disable()
    if Idle.events then Idle.events:UnregisterAllEvents() end
    Idle.paused = false
end

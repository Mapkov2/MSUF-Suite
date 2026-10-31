local _, P = ...
local NS, S = P.NS, P.Suite
local W, Sources = NS.WeeklyRewards, P.DataTextSources
local Vault = {}
P.VaultDataText = Vault
local events, owner, active
local function ItemEvents(wanted)
    if wanted then events:RegisterEvent("GET_ITEM_INFO_RECEIVED")
    else
        events:UnregisterEvent("GET_ITEM_INFO_RECEIVED")
    end
end
local function Leave()
    owner = nil
    if events then ItemEvents(false) end
end
function Vault.Leave(button)
    if not button or button == owner then Leave() end
end
local function Draw()
    if not owner or not owner:IsVisible() or NS.Safety.IsForbidden(GameTooltip) or GameTooltip:GetOwner() ~= owner then
        Leave()
        return
    end
    GameTooltip:ClearLines()
    GameTooltip:AddLine(S.Text("Great Vault"), 1, .82, .36)
    ItemEvents(W.AppendTooltip(GameTooltip, true))
    GameTooltip:Show()
end
local function Changed(_, event)
    if event ~= "GET_ITEM_INFO_RECEIVED" then
        W.Invalidate()
        Sources.Refresh("vault")
    end
    if owner then Draw() end
end
function Vault.Tooltip(button)
    if not active or not W.Available() then return end
    owner = button
    Draw()
end
function Vault.Disable()
    Leave()
    active = false
    if events then events:UnregisterAllEvents() end
end
function Vault.Rebind(_, wanted)
    if not wanted then
        Vault.Disable()
        return
    end
    if active then return end
    if not events then
        events = S.CreateFrame("Frame")
        events:SetScript("OnEvent", Changed)
        GameTooltip:HookScript("OnHide", Leave)
    end
    active = true
    W.Invalidate()
    events:RegisterEvent("WEEKLY_REWARDS_UPDATE")
    events:RegisterEvent("PLAYER_ENTERING_WORLD")
end
function Vault.Format()
    return S.Text("Great Vault"), W.Summary() or P.NO_VALUE
end
Sources.Register("vault", Vault, {})

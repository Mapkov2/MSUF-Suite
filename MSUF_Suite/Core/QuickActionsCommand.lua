local _, NS = ...
local S = NS.Suite

function NS.ToggleQuickActions(query)
    if not S.started or NS.InCombat() then
        NS.Print(NS.Text("Unavailable on this client or in combat."))
        return false
    end
    if not S.QuickActions then C_AddOns.LoadAddOn("MSUF_Suite_Modules") end
    if S.QuickActions then return S.QuickActions.Toggle(NS.PublicText(query)) end
    return false
end

SLASH_MSUFSUITEQUICKACTIONS1 = "/msufactions"
SlashCmdList.MSUFSUITEQUICKACTIONS = NS.ToggleQuickActions

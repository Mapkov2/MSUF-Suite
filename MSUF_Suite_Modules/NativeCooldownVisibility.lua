local _, P = ...
local S = P.Suite
local ID, CVAR = "nativeCooldownVisibility", "cooldownViewerEnabled"

-- The cooldown manager normally owns this CVar. While it is off, the
-- independent layout switch can keep the native rows out of the HUD.
local function Apply(self)
    if S.states.cooldownManager.active then
        S.RestoreCVar(ID, CVAR)
    else
        self.context:CVar(CVAR, "0")
    end
end

S.Install(ID, { Enable = Apply, Refresh = Apply })

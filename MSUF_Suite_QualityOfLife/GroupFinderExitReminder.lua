local _, P = ...
local S = P.Suite
local M = {}

local function OnFinderHidden()
    if not M.active then return end
    local _, active = C_LFGList.GetNumApplications()
    if S.Finite(active) and active > 0 then
        S.Print(string.format(S.Text("%d group applications are still active"), math.floor(active)))
    end
end

-- Group Finder loads with the Retail UI at startup; this module is Retail-only.
function M:Enable()
    if self.hooked then return end
    self.hooked = true
    LFGListFrame:HookScript("OnHide", OnFinderHidden)
end

-- The script hook cannot be removed; it does nothing while inactive.
function M:Disable() end

S.Install("groupFinderExitReminder", M)

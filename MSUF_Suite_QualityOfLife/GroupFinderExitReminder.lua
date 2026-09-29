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

local function TryHook(self)
    local frame = _G.LFGListFrame
    if self.hooked or not frame then return end
    frame:HookScript("OnHide", OnFinderHidden)
    self.hooked = true
    self.context:RemoveEvent("ADDON_LOADED")
end

local function OnAddon(self, _, name)
    if S.PublicText(name) and name == "Blizzard_GroupFinder" then TryHook(self) end
end

function M:Enable()
    if not self.hooked then
        self.context:Event("ADDON_LOADED", OnAddon, true)
        TryHook(self)
    end
end

function M:Disable()
    self.context:RemoveEvent("ADDON_LOADED")
end

S.Install("groupFinderExitReminder", M)

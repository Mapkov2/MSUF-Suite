local _, P = ...
local S = P.Suite
local M = {}

local function OnReset(self)
    if self.active then S.Print(S.Text("Keystone was reset")) end
end

function M:Enable()
    self.context:Event("CHALLENGE_MODE_RESET", OnReset, true)
end

function M:Disable()
    self.context:RemoveEvent("CHALLENGE_MODE_RESET")
end

S.Install("mythicResetReminder", M)

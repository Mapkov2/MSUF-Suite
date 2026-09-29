local _, P = ...
local S = P.Suite

local M = {}
local CLICK_WINDOW = .4

local function OnEntryClick(entry, button)
    if not M.active or not S.PublicText(button) or button ~= "LeftButton" then return end
    local panel = _G.LFGListFrame and _G.LFGListFrame.SearchPanel
    local resultID = entry and entry.resultID
    if not panel or not S.Finite(resultID) or not S.Finite(panel.selectedResult)
        or panel.selectedResult ~= resultID or not panel.SignUpButton then
        M.lastResult, M.lastAt = nil, nil
        return
    end
    local enabled, shown = panel.SignUpButton:IsEnabled(), panel:IsShown()
    if not S.Public(enabled) or enabled ~= true or not S.Public(shown) or shown ~= true then
        M.lastResult, M.lastAt = nil, nil
        return
    end
    local now = GetTime()
    if not S.Finite(now) then return end
    local doubleClick = M.lastResult == resultID and M.lastAt
        and now >= M.lastAt and now - M.lastAt <= CLICK_WINDOW
    M.lastResult, M.lastAt = resultID, now
    local dialog = _G.LFGListApplicationDialog
    local dialogShown = dialog and dialog:IsShown()
    if doubleClick and type(_G.LFGListSearchPanel_SignUp) == "function"
        and S.Public(dialogShown) and dialogShown ~= true then
        M.lastResult, M.lastAt = nil, nil
        -- The regular Blizzard dialog retains the role and note confirmation.
        if not pcall(LFGListSearchPanel_SignUp, panel) then
            S.Print(S.Text("Group finder dialog could not be opened by the client."))
        end
    end
end

local function TryInstall(self)
    if self.hooked or type(_G.LFGListSearchEntry_OnClick) ~= "function" then return end
    hooksecurefunc("LFGListSearchEntry_OnClick", OnEntryClick)
    self.hooked = true
    self.context:RemoveEvent("ADDON_LOADED")
end

local function OnAddon(self, _, name)
    if name == "Blizzard_GroupFinder" then TryInstall(self) end
end

function M:Enable()
    if not self.hooked then
        self.context:Event("ADDON_LOADED", OnAddon, true)
        TryInstall(self)
    end
end

function M:Disable()
    self.context:RemoveEvent("ADDON_LOADED")
    self.lastResult, self.lastAt = nil, nil
end

S.Install("groupFinderDoubleClick", M)

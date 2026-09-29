local _, P = ...
local NS, S = P.NS, P.Suite
local M = {}

local function TryChoose(self)
    if not self.active then return end
    local combatLocked = NS.IsCombatLocked()
    if not S.Public(combatLocked) or combatLocked == true then return end
    local activeDelve = C_DelvesUI.HasActiveDelve()
    if not S.Public(activeDelve) or activeDelve ~= true then return end
    local choice = C_PlayerChoice.GetCurrentPlayerChoiceInfo()
    if not S.Public(choice) or type(choice) ~= "table" then return end
    local choiceID, options = choice.choiceID, choice.options
    if not S.Finite(choiceID) or not S.Public(options) or type(options) ~= "table"
        or #options ~= 1 or self.lastChoiceID == choiceID then return end
    local option = options[1]
    if not S.Public(option) or type(option) ~= "table"
        or not S.Finite(option.spellID) or option.spellID < 1
        or not S.Public(option.disabledOption) or option.disabledOption ~= false then return end
    local buttons = option.buttons
    if not S.Public(buttons) or type(buttons) ~= "table" or #buttons ~= 1 then return end
    local button = buttons[1]
    if not S.Public(button) or type(button) ~= "table"
        or not S.Finite(button.id) or button.id < 1
        or not S.Public(button.disabled) or button.disabled ~= false
        or not S.Public(button.confirmation) or button.confirmation ~= nil then return end
    self.lastChoiceID = choiceID
    -- The native choice stays open for manual selection if its state changed
    -- between inspection and this one bounded response attempt.
    pcall(C_PlayerChoice.SendPlayerChoiceResponse, button.id)
end

local function OnClosed(self)
    self.lastChoiceID = nil
end

function M:Enable()
    self.context:Event("PLAYER_CHOICE_UPDATE", TryChoose, true)
    self.context:Event("PLAYER_CHOICE_CLOSE", OnClosed, true)
    TryChoose(self)
end

function M:Disable()
    self.context:RemoveEvent("PLAYER_CHOICE_UPDATE")
    self.context:RemoveEvent("PLAYER_CHOICE_CLOSE")
    self.lastChoiceID = nil
end

S.Install("delveSolePower", M)

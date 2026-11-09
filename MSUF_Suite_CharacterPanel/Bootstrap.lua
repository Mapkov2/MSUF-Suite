local _, NS = ...
local suite = assert(MSUFSuite, "MSUF_Suite is required")
NS.Host, NS.Suite = suite, suite.Suite
NS.Text, NS.Public, NS.String = suite.Text, suite.Public, suite.PublicText

function NS.Number(value)
    if suite.Finite(value) then return value end
end

function NS.CanOpenCharacter()
    if NS.Suite.GamepadUI() then return false end
    local disabled = C_GameRules.IsGameRuleActive(Enum.GameRule.CharacterPanelDisabled)
    return NS.Public(disabled) and disabled == false
end

function NS.CanReplace()
    return not suite.InCombat() and NS.CanOpenCharacter()
end

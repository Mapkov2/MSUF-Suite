local root = assert(arg[1], "repository root required")
local module, callbacks = nil, {}
local owner = { auraType = "TempEnchant", GetID = function() return 16 end }
local tooltip = { lines = {}, GetOwner = function() return owner end }
function tooltip:AddDoubleLine(label, value) self.lines[#self.lines + 1] = { label, value } end
function tooltip:IsShown() return false end
GameTooltip = tooltip
IsAltKeyDown = function() return true end
Enum = { TooltipDataType = { Item = 1, Spell = 2, Unit = 3, Quest = 4, Currency = 5 } }
TooltipDataProcessor = { AddTooltipPostCall = function(kind, callback) callbacks[kind] = callback end }
C_PaperDollInfo = { GetTemporaryEnchantmentInfo = function(slot)
    assert(slot == 16)
    return { enchantID = 6123 }
end }
local context = { events = {} }
function context:Event(event, callback) self.events[event] = callback end
function context:RemoveEvent(event) self.events[event] = nil end
local suite = {
    Install = function(_, value) module = value end,
    Public = function(value) return value ~= "secret" end,
    PublicText = function(value) return type(value) == "string" and value ~= "secret" and value or nil end,
    Finite = function(value) return type(value) == "number" and value == value end,
    Text = function(value) return value end,
}
local ns = { Safety = { IsForbidden = function() return false end } }
assert(loadfile(root .. "/MSUF_Suite_QualityOfLife/TooltipIDs.lua"))(
    "MSUF_Suite_QualityOfLife", { NS = ns, Suite = suite })
assert(module)
module.active, module.context, module.config = true, context, { showTempEnchant = true }
module:Enable()
assert(callbacks[Enum.TooltipDataType.Item], "item tooltip hook was not installed")
callbacks[Enum.TooltipDataType.Item](tooltip, { id = 123 })
assert(#tooltip.lines == 2 and tooltip.lines[2][1] == "Enchant ID"
    and tooltip.lines[2][2] == "6123", "temporary enchant ID was not shown on its buff tooltip")
tooltip.lines = {}
C_PaperDollInfo.GetTemporaryEnchantmentInfo = function() return { enchantID = "secret" } end
callbacks[Enum.TooltipDataType.Item](tooltip, { id = 123 })
assert(#tooltip.lines == 1, "secret enchant ID was displayed")
tooltip.lines = {}
module.config.showQuestCurrency, module.config.showAccountCurrency = true, true
C_CurrencyInfo = {
    IsAccountCharacterCurrencyDataReady = function() return true end,
    FetchCurrencyDataFromAccountCharacters = function(id)
        assert(id == 222)
        return { { fullCharacterName = "Alice-Realm", quantity = 7 },
            { fullCharacterName = "Bob-Realm", quantity = 3 },
            { fullCharacterName = "Private-Realm", quantity = "secret" } }
    end,
}
module:Refresh()
assert(context.events.ACCOUNT_CHARACTER_CURRENCY_DATA_RECEIVED,
    "account currency listener was not registered")
callbacks[Enum.TooltipDataType.Currency](tooltip, { id = 222 })
assert(#tooltip.lines == 4 and tooltip.lines[2][1] == "Known across characters"
    and tooltip.lines[2][2] == "10", "native account currency data was not shown safely")
tooltip.lines = {}
module.active = false
callbacks[Enum.TooltipDataType.Item](tooltip, { id = 123 })
assert(#tooltip.lines == 0, "disabled tooltip module still wrote lines")
print("Suite temporary enchant tooltip passed")

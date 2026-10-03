local root = assert(arg[1], "repository root required")
local Support = dofile(root .. "/tools/tests/suite_test_support.lua")
local module, reported = nil, {}
local owner = { auraType = "TempEnchant", GetID = function() return 16 end }
local tooltip = { lines = {}, GetOwner = function() return owner end }
function tooltip:AddDoubleLine(label, value) self.lines[#self.lines + 1] = { label, value } end
-- A shown tooltip: no helper may make it rebuild from addon code.
function tooltip:IsShown() return true end
function tooltip:RefreshDataNextUpdate() error("addon code wrote GameTooltip's update fields") end
GameTooltip = tooltip
local alt = true
IsAltKeyDown = function() return alt end
Enum = { TooltipDataType = { Item = 1, Spell = 2, Unit = 3, Quest = 4, Currency = 5 } }
C_PaperDollInfo = { GetTemporaryEnchantmentInfo = function(slot)
    assert(slot == 16)
    return { enchantID = 6123 }
end }
C_Spell = { GetSpellTexture = function() return 4321 end }
local context = { events = {} }
function context:Event(event, callback) self.events[event] = callback end
function context:RemoveEvent(event) self.events[event] = nil end
local suite = {
    Install = function(_, value) module = value end,
    Public = function(value) return value ~= "secret" end,
    PublicText = function(value) return type(value) == "string" and value ~= "secret" and value or nil end,
    Finite = function(value) return type(value) == "number" and value == value end,
    Text = function(value) return value end,
    Dispatch = Support.Dispatcher(reported),
}
local ns = { Safety = { IsForbidden = function() return false end } }
local tooltips = Support.TooltipFixture(root, suite, ns)
assert(loadfile(root .. "/MSUF_Suite_QualityOfLife/TooltipIDs.lua"))(
    "MSUF_Suite_QualityOfLife", { NS = ns, Suite = suite })
assert(module)
module.active, module.context, module.config = true, context, { showTempEnchant = true }
module:Enable()
module:Enable()
local Item, Currency = Enum.TooltipDataType.Item, Enum.TooltipDataType.Currency
-- Alt pressed over an open tooltip adds its IDs (no rebuild; the stub above
-- errors on one); no other event is heard while account currency is off.
local heard = 0
for _ in pairs(context.events) do heard = heard + 1 end
assert(#tooltips.post[Item] == 1 and not next(tooltips.pre) and context.events.MODIFIER_STATE_CHANGED and heard == 1,
    "tooltip IDs registered twice, used a line pre-call or listened for other events")
tooltips.Run(Item, tooltip, { id = 123 })
assert(#tooltip.lines == 2 and tooltip.lines[2][1] == "Enchant ID"
    and tooltip.lines[2][2] == "6123", "temporary enchant ID was not shown on its buff tooltip")
tooltip.lines = {}
C_PaperDollInfo.GetTemporaryEnchantmentInfo = function() return { enchantID = "secret" } end
tooltips.Run(Item, tooltip, { id = 123 })
assert(#tooltip.lines == 1, "secret enchant ID was displayed")
tooltip.lines = {}
alt = false
tooltips.Run(Item, tooltip, { id = 123 })
assert(#tooltip.lines == 0, "IDs appeared without Alt")
alt = true
module.config.showQuestCurrency, module.config.showAccountCurrency, module.config.showSpellIcon = true, true, true
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
-- The account data listener adds lines to an open tooltip; it never rebuilds.
heard = 0
for _ in pairs(context.events) do heard = heard + 1 end
assert(heard == 2 and context.events.ACCOUNT_CHARACTER_CURRENCY_DATA_RECEIVED,
    "a settings refresh did not listen for account currency data or listened for more")
tooltips.Run(Currency, tooltip, { id = 222 })
assert(#tooltip.lines == 4 and tooltip.lines[2][1] == "Known across characters"
    and tooltip.lines[2][2] == "10", "native account currency data was not shown safely")
-- The client loads the account data only on request: the first currency
-- tooltip with Alt held that finds it missing asks once, and the data's
-- arrival adds the lines to the open tooltip.
local ready, requests, fetch = false, 0, C_CurrencyInfo.FetchCurrencyDataFromAccountCharacters
C_CurrencyInfo.IsAccountCharacterCurrencyDataReady = function() return ready end
C_CurrencyInfo.RequestCurrencyDataForAccountCharacters = function() requests = requests + 1 end
C_CurrencyInfo.FetchCurrencyDataFromAccountCharacters = function(id)
    assert(ready, "account currency data was read before it was ready")
    return fetch(id)
end
alt = false
tooltip.lines = {}
tooltips.Run(Currency, tooltip, { id = 222 })
assert(requests == 0, "a currency tooltip without Alt requested account data")
alt = true
local open = { type = Currency, id = 222 }
tooltip.lines = {}
tooltips.Run(Currency, tooltip, open)
tooltips.Run(Currency, tooltip, open)
assert(requests == 1 and #tooltip.lines == 2, "missing account currency data was not requested exactly once")
function tooltip:GetPrimaryTooltipData() return open end
function tooltip:Show() self.grown = true end
ready = true
context.events.ACCOUNT_CHARACTER_CURRENCY_DATA_RECEIVED()
assert(#tooltip.lines == 5 and tooltip.lines[3][1] == "Known across characters" and tooltip.grown,
    "arriving account currency data did not reach the open tooltip")
ready = false
tooltip.lines = {}
tooltips.Run(Currency, tooltip, { id = 222 })
assert(requests == 2, "data that went missing again after it arrived was not requested again")
ready = true
tooltip.GetPrimaryTooltipData, tooltip.Show = nil, nil
tooltip.lines = {}
tooltips.Run(Enum.TooltipDataType.Spell, tooltip, { id = 10 })
assert(#tooltip.lines == 2 and tooltip.lines[2][2] == "4321", "spell icon ID missing")
tooltip.lines = {}
tooltips.Run(Enum.TooltipDataType.Unit, tooltip, { guid = "Creature-0-1-2-3-5678-0000ABCD12" })
assert(#tooltip.lines == 1 and tooltip.lines[1][2] == "5678", "creature ID missing")
tooltip.lines = {}
tooltips.Run(Item, {}, { id = 123 })
module.active = false
tooltips.Run(Item, tooltip, { id = 123 })
assert(#tooltip.lines == 0 and #reported == 0, "a foreign tooltip or the disabled module got lines")
print("Suite temporary enchant tooltip passed")

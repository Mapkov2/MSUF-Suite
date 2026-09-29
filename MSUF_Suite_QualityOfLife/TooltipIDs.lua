local _, P = ...
local NS, S = P.NS, P.Suite

local M = {}
local RefreshTooltip

local function AddID(tooltip, label, id)
    if not S.Finite(id) or id < 1 then return end
    tooltip:AddDoubleLine(S.Text(label), tostring(math.floor(id)), .65, .81, .87, 1, .88, .58)
end

local function Eligible(tooltip, data)
    if not M.active or tooltip ~= GameTooltip or NS.Safety.IsForbidden(tooltip)
        or not S.Public(data) or type(data) ~= "table" then return false end
    local alt = IsAltKeyDown()
    return S.Public(alt) and alt == true
end

local function Item(tooltip, data)
    if not Eligible(tooltip, data) then return end
    AddID(tooltip, "Item ID", data.id)
    if not M.config or not M.config.showTempEnchant or not tooltip.GetOwner then return end
    local owner = tooltip:GetOwner()
    if not owner or NS.Safety.IsForbidden(owner) or S.PublicText(owner.auraType) ~= "TempEnchant"
        or type(owner.GetID) ~= "function" or not C_PaperDollInfo
        or type(C_PaperDollInfo.GetTemporaryEnchantmentInfo) ~= "function" then return end
    local slot = owner:GetID()
    if not S.Finite(slot) then return end
    local info = C_PaperDollInfo.GetTemporaryEnchantmentInfo(slot)
    if S.Public(info) and type(info) == "table" then
        AddID(tooltip, "Enchant ID", info.enchantID)
    end
end

local function Spell(tooltip, data)
    if not Eligible(tooltip, data) then return end
    AddID(tooltip, "Spell ID", data.id)
    if M.config and M.config.showSpellIcon and C_Spell and type(C_Spell.GetSpellTexture) == "function"
        and S.Finite(data.id) then
        AddID(tooltip, "Spell icon ID", C_Spell.GetSpellTexture(data.id))
    end
end

local function Quest(tooltip, data)
    if Eligible(tooltip, data) and M.config and M.config.showQuestCurrency then AddID(tooltip, "Quest ID", data.id) end
end

local function Currency(tooltip, data)
    if not Eligible(tooltip, data) or not M.config then return end
    if M.config.showQuestCurrency then AddID(tooltip, "Currency ID", data.id) end
    if not M.config.showAccountCurrency or not S.Finite(data.id) or not C_CurrencyInfo
        or type(C_CurrencyInfo.IsAccountCharacterCurrencyDataReady) ~= "function"
        or type(C_CurrencyInfo.FetchCurrencyDataFromAccountCharacters) ~= "function" then return end
    local ready = C_CurrencyInfo.IsAccountCharacterCurrencyDataReady()
    if not S.Public(ready) or ready ~= true then return end
    local entries = C_CurrencyInfo.FetchCurrencyDataFromAccountCharacters(data.id)
    if not S.Public(entries) or type(entries) ~= "table" then return end
    local rows, total = {}, 0
    for i = 1, #entries do
        local entry = entries[i]
        if S.Public(entry) and type(entry) == "table" then
            local name = S.PublicText(entry.fullCharacterName) or S.PublicText(entry.characterName)
            local amount = entry.quantity
            if name and S.Finite(amount) and amount > 0 then
                rows[#rows + 1] = { name = name, amount = amount }
                total = total + amount
            end
        end
    end
    if #rows == 0 or not S.Finite(total) then return end
    table.sort(rows, function(a, b)
        return a.amount == b.amount and a.name < b.name or a.amount > b.amount
    end)
    tooltip:AddDoubleLine(S.Text("Known across characters"), tostring(math.floor(total)), .65, .81, .87, 1, .88, .58)
    for i = 1, math.min(#rows, 8) do
        tooltip:AddDoubleLine(rows[i].name, tostring(math.floor(rows[i].amount)), .7, .75, .8, 1, 1, 1)
    end
end

local function Unit(tooltip, data)
    if not Eligible(tooltip, data) then return end
    local guid = S.PublicText(data.guid)
    if not guid or not (guid:find("^Creature%-") or guid:find("^Vehicle%-")) then return end
    local npcText = select(6, strsplit("-", guid))
    local id = tonumber(npcText)
    AddID(tooltip, "Creature ID", id)
end

RefreshTooltip = function()
    local tooltip = _G.GameTooltip
    if tooltip and not NS.Safety.IsForbidden(tooltip) and tooltip:IsShown()
        and tooltip.RefreshDataNextUpdate then
        tooltip:RefreshDataNextUpdate()
    end
end

local function ModifierChanged(_, _, key)
    if not S.PublicText(key) or key ~= "LALT" and key ~= "RALT" then return end
    RefreshTooltip()
end

local function Install()
    if M.hooked or not TooltipDataProcessor or not Enum.TooltipDataType then return end
    local add, kinds = TooltipDataProcessor.AddTooltipPostCall, Enum.TooltipDataType
    if type(add) ~= "function" then return end
    add(kinds.Item, Item)
    add(kinds.Spell, Spell)
    add(kinds.Unit, Unit)
    if kinds.Quest then add(kinds.Quest, Quest) end
    if kinds.Currency then add(kinds.Currency, Currency) end
    M.hooked = true
    M.context:RemoveEvent("ADDON_LOADED")
end

local function OnAddon()
    Install()
end

function M:Enable()
    Install()
    if not self.hooked then self.context:Event("ADDON_LOADED", OnAddon) end
    self.context:Event("MODIFIER_STATE_CHANGED", ModifierChanged)
    if self.config and self.config.showAccountCurrency then
        self.context:Event("ACCOUNT_CHARACTER_CURRENCY_DATA_RECEIVED", RefreshTooltip)
    end
    RefreshTooltip()
end

function M:Refresh()
    if self.config and self.config.showAccountCurrency then
        self.context:Event("ACCOUNT_CHARACTER_CURRENCY_DATA_RECEIVED", RefreshTooltip)
    else
        self.context:RemoveEvent("ACCOUNT_CHARACTER_CURRENCY_DATA_RECEIVED")
    end
    RefreshTooltip()
end

function M:Disable()
    self.context:RemoveEvent("ACCOUNT_CHARACTER_CURRENCY_DATA_RECEIVED")
    RefreshTooltip()
end

S.Install("tooltipIDs", M)

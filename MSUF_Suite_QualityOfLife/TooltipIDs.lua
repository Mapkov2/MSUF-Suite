local _, P = ...
local NS, S = P.NS, P.Suite

-- Hold Alt to read IDs on the main tooltip. The lines join Blizzard's build
-- (TooltipLines.lua) when the tooltip opens with Alt held; pressing Alt over
-- an open tooltip, or account currency data arriving, adds them to it. Lines
-- cannot be taken out of a built tooltip, so releasing Alt leaves them until
-- the tooltip is built again.
local M = {}
local Line = S.TooltipLines.Line
local handlers = {}
-- The tooltip data that already carries the IDs, and the account lines.
local idsFor, accountFor

local function AddID(tooltip, label, id)
    if not S.Finite(id) or id < 1 then return end
    Line(tooltip, label, tostring(math.floor(id)))
end

local function AltHeld()
    local alt = IsAltKeyDown()
    return S.Public(alt) and alt == true
end

-- Blizzard's temporary weapon enchant buttons carry auraType "TempEnchant"
-- and their equipment slot as the button ID.
local function TempEnchant(tooltip)
    local owner = tooltip:GetOwner()
    if not owner or NS.Safety.IsForbidden(owner) or S.PublicText(owner.auraType) ~= "TempEnchant" then return end
    local slot = owner:GetID()
    if not S.Finite(slot) then return end
    local info = C_PaperDollInfo.GetTemporaryEnchantmentInfo(slot)
    if S.Public(info) and type(info) == "table" then AddID(tooltip, "Enchant ID", info.enchantID) end
end

local function Item(tooltip, data)
    if not AltHeld() then return end
    idsFor = data
    AddID(tooltip, "Item ID", data.id)
    if M.config.showTempEnchant then TempEnchant(tooltip) end
end

local function Spell(tooltip, data)
    if not AltHeld() then return end
    idsFor = data
    AddID(tooltip, "Spell ID", data.id)
    if M.config.showSpellIcon and S.Finite(data.id) then
        AddID(tooltip, "Spell icon ID", C_Spell.GetSpellTexture(data.id))
    end
end

local function Quest(tooltip, data)
    if not AltHeld() then return end
    idsFor = data
    if M.config.showQuestCurrency then AddID(tooltip, "Quest ID", data.id) end
end

local function SortByAmount(a, b)
    return a.amount == b.amount and a.name < b.name or a.amount > b.amount
end

-- Blizzard's account character currency data, when the client has it ready.
local function AccountCurrency(tooltip, id)
    local ready = C_CurrencyInfo.IsAccountCharacterCurrencyDataReady()
    if not S.Public(ready) or ready ~= true then return end
    local entries = C_CurrencyInfo.FetchCurrencyDataFromAccountCharacters(id)
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
    if #rows == 0 or not S.Finite(total) then return false end
    table.sort(rows, SortByAmount)
    Line(tooltip, "Known across characters", tostring(math.floor(total)))
    for i = 1, math.min(#rows, 8) do
        tooltip:AddDoubleLine(rows[i].name, tostring(math.floor(rows[i].amount)), .7, .75, .8, 1, 1, 1)
    end
    return true
end

local function AccountLines(tooltip, data)
    if M.config.showAccountCurrency and S.Finite(data.id) and AccountCurrency(tooltip, data.id) then
        accountFor = data
    end
end

local function Currency(tooltip, data)
    if not AltHeld() then return end
    idsFor = data
    if M.config.showQuestCurrency then AddID(tooltip, "Currency ID", data.id) end
    AccountLines(tooltip, data)
end

local function Unit(tooltip, data)
    if not AltHeld() then return end
    idsFor = data
    local guid = S.PublicText(data.guid)
    if not guid or not (guid:find("^Creature%-") or guid:find("^Vehicle%-")) then return end
    AddID(tooltip, "Creature ID", tonumber((select(6, strsplit("-", guid)))))
end

------------------------------------------------------------------ open tooltips
-- MODIFIER_STATE_CHANGED(key, down): Alt pressed over a tooltip that was
-- built without it adds the IDs to it.
local function AltPressed(_, _, key, down)
    if down ~= 1 or key ~= "LALT" and key ~= "RALT" then return end
    local tooltip, data = S.TooltipLines.Open()
    local handler = data and handlers[data.type]
    if not handler or data == idsFor then return end
    handler(tooltip, data)
    S.TooltipLines.Grow(tooltip)
end

-- Account character currency data that arrives while a currency tooltip is
-- open with Alt held adds the lines it waited for.
local function AccountArrived()
    local tooltip, data = S.TooltipLines.Open()
    if not data or data.type ~= Enum.TooltipDataType.Currency or data ~= idsFor or data == accountFor then return end
    AccountLines(tooltip, data)
    if accountFor == data then S.TooltipLines.Grow(tooltip) end
end

local function Listen(self)
    self.context:Event("MODIFIER_STATE_CHANGED", AltPressed)
    if self.config.showAccountCurrency then
        self.context:Event("ACCOUNT_CHARACTER_CURRENCY_DATA_RECEIVED", AccountArrived)
    else
        self.context:RemoveEvent("ACCOUNT_CHARACTER_CURRENCY_DATA_RECEIVED")
    end
end

function M:Enable()
    local lines, kinds = S.TooltipLines, Enum.TooltipDataType
    lines.Add(self, "Item", Item)
    lines.Add(self, "Spell", Spell)
    lines.Add(self, "Unit", Unit)
    lines.Add(self, "Quest", Quest)
    lines.Add(self, "Currency", Currency)
    handlers[kinds.Item], handlers[kinds.Spell], handlers[kinds.Unit] = Item, Spell, Unit
    handlers[kinds.Quest], handlers[kinds.Currency] = Quest, Currency
    Listen(self)
end

function M:Refresh() Listen(self) end

function M:Disable()
    idsFor, accountFor = nil, nil
end

S.Install("tooltipIDs", M)

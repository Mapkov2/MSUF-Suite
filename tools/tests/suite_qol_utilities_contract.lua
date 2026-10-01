local root = assert(arg[1], "repository root required")
local secret = {}
issecretvalue = function(value) return value == secret end

local function Context()
    local context = { events = {} }
    function context:Event(name, callback) self.events[name] = callback end
    function context:RemoveEvent(name) self.events[name] = nil end
    return context
end

local function Label()
    return {
        shown = true,
        SetPoint = function() end, SetWidth = function() end, SetJustifyH = function() end,
        SetTextColor = function() end, SetShadowOffset = function() end, SetShadowColor = function() end,
        SetText = function(self, value) self.text = value end,
        Show = function(self) self.shown = true end,
        Hide = function(self) self.shown = false end,
        IsShown = function(self) return self.shown end,
    }
end

local suite = { instances = {} }
suite.Public = function(value) return not issecretvalue(value) end
suite.Finite = function(value)
    return suite.Public(value) and type(value) == "number" and value == value
        and value > -math.huge and value < math.huge
end
suite.PublicText = function(value)
    return suite.Public(value) and type(value) == "string" and value ~= "" and value or nil
end
suite.Text = function(value) return value end
suite.CreateFontString = function() return Label() end
suite.SetFont = function() end
function suite.Install(id, module)
    assert(not suite.instances[id], "duplicate module")
    suite.instances[id] = module
end

local owner = { Safety = { IsForbidden = function() return false end }, IsCombatLocked = function() return false end }
local function Load(file)
    assert(loadfile(root .. "/MSUF_Suite_QualityOfLife/" .. file .. ".lua"))(
        "MSUF_Suite_QualityOfLife", { NS = owner, Suite = suite })
end
local function Fire(module, event, ...)
    local callback = assert(module.context.events[event], "missing event " .. event)
    callback(module, event, ...)
end

------------------------------------------------------------------ merchant
local links = { "item:1", "item:2", "item:3" }
local levels = { [1] = 510 }
local requests, merchantHook = {}, nil
local paintTimers, frames = {}, {}
C_Timer = { NewTimer = function(_, callback)
    local timer = { callback = callback }
    function timer:Cancel() self.canceled = true end
    paintTimers[#paintTimers + 1] = timer
    return timer
end, After = function(_, callback) frames[#frames + 1] = callback end }
local function RunFrame()
    local queue = frames
    frames = {}
    for _, callback in ipairs(queue) do callback() end
end
suite.Dispatch = function(callback, ...) return callback(...) end
MERCHANT_ITEMS_PER_PAGE = 2
MerchantFrame = { shown = true, selectedTab = 1, page = 1,
    IsShown = function(self) return self.shown end,
    HookScript = function(self, name, callback) self[name] = callback end }
MerchantItem1ItemButton, MerchantItem2ItemButton = {}, {}
GetMerchantNumItems = function() return 3 end
GetMerchantItemLink = function(index) return links[index] end
GetMerchantItemID = function(index) return index end
C_Item = {
    IsEquippableItem = function(link) return link ~= "item:3" end,
    GetDetailedItemLevelInfo = function(link)
        local id = tonumber(link:match("%d+"))
        return levels[id]
    end,
    RequestLoadItemDataByID = function(id) requests[#requests + 1] = id end,
}
hooksecurefunc = function(name, callback)
    assert(name == "MerchantFrame_Update" and not merchantHook)
    merchantHook = callback
end
MerchantFrame_Update = function() end
Load("MerchantWatch")
Load("MerchantItemLevel")
local merchant = assert(suite.instances.merchantLevel)
merchant.active, merchant.context = true, Context()
merchant:Enable()
assert(merchantHook and merchant.context.events.MERCHANT_SHOW, "merchant lifecycle was not attached")
Fire(merchant, "MERCHANT_SHOW")
assert(merchant.labels[1].shown and merchant.labels[1].text == 510,
    "cached equipment level was not shown")
assert(requests[1] == 2 and merchant.context.events.GET_ITEM_INFO_RECEIVED,
    "missing item data was not requested once")
merchantHook()
assert(#requests == 1, "merchant redraw requested the same item twice")
-- Blizzard's update runs on every bag and currency change at a merchant;
-- a burst on the same page repaints once, on the next frame.
local paints, paint = 0, merchant.Paint
merchant.Paint = function(...) paints = paints + 1 return paint(...) end
RunFrame()
for _ = 1, 4 do merchantHook() end
assert(paints == 0 and #frames == 1, "a burst of merchant updates was not coalesced")
RunFrame()
assert(paints == 1, "the coalesced merchant update did not repaint once")
merchant.Paint = paint
levels[2] = 490
Fire(merchant, "GET_ITEM_INFO_RECEIVED", 2)
assert(#paintTimers == 1 and merchant.paintTimer == paintTimers[1],
    "item-load event did not coalesce its merchant repaint")
paintTimers[1].callback()
assert(merchant.labels[2].shown and merchant.labels[2].text == 490
    and not merchant.context.events.GET_ITEM_INFO_RECEIVED,
    "loaded item level did not appear or its event remained active")
levels[1], levels[2], merchant.requested = nil, nil, {}
merchantHook()
RunFrame()
levels[1], levels[2] = 510, 490
Fire(merchant, "GET_ITEM_INFO_RECEIVED", 1)
Fire(merchant, "GET_ITEM_INFO_RECEIVED", 2)
assert(#paintTimers == 2 and merchant.paintTimer == paintTimers[2],
    "two item-load events scheduled more than one repaint")
paintTimers[2].callback()
assert(merchant.labels[1].shown and merchant.labels[2].shown
    and not merchant.context.events.GET_ITEM_INFO_RECEIVED,
    "batched item loads did not repaint both merchant labels")
levels[1], merchant.requested[1] = nil, nil
merchantHook()
RunFrame()
Fire(merchant, "GET_ITEM_INFO_RECEIVED", 1)
local stalePaint = paintTimers[#paintTimers]
Fire(merchant, "MERCHANT_CLOSED")
assert(stalePaint.canceled and not merchant.labels[1].shown,
    "closing the merchant retained an item repaint")
levels[1] = 510
stalePaint.callback()
assert(not merchant.labels[1].shown, "a canceled item repaint revived a closed merchant label")
Fire(merchant, "MERCHANT_SHOW")
MerchantFrame.page = 2
merchantHook()
assert(not merchant.labels[1].shown and not merchant.labels[2].shown,
    "page change kept stale item levels")
MerchantFrame.selectedTab = 2
merchantHook()
assert(not merchant.labels[1].shown, "buyback tab kept a merchant level")
MerchantFrame.selectedTab, MerchantFrame.page = 1, 1
merchantHook()
merchant.labels[1]:Hide()
MerchantFrame.OnHide()
merchantHook()
assert(merchant.labels[1].shown, "a reopened merchant window waited a frame for its levels")
Fire(merchant, "MERCHANT_CLOSED")
merchant.active = false
merchant:Disable()
merchantHook()
assert(not merchant.labels[1].shown, "disabled merchant hook repainted a label")

------------------------------------------------------------------ vault
local selected = 0
WeeklyRewardsFrame = {
    shown = false,
    IsShown = function(self) return self.shown end,
    HookScript = function(self, name, callback)
        assert(name == "OnShow" and not self.onShow)
        self.onShow = callback
    end,
}
GetLootSpecialization = function() return selected end
C_SpecializationInfo = {
    GetSpecialization = function() return 1 end,
    GetSpecializationInfo = function() return 10, "Arcane" end,
}
GetSpecializationInfoByID = function(id)
    assert(id == 20)
    return id, "Frost"
end
Load("VaultSpec")
local vault = assert(suite.instances.vaultSpec)
vault.active, vault.context = true, Context()
vault:Enable()
assert(vault.label and WeeklyRewardsFrame.onShow and not vault.label.shown,
    "vault hint did not attach lazily and start hidden")
WeeklyRewardsFrame.shown = true
WeeklyRewardsFrame.onShow()
assert(vault.label.shown and vault.label.text == "Loot specialization: Current (Arcane)",
    "vault did not show the current specialization")
selected = 20
Fire(vault, "PLAYER_LOOT_SPEC_UPDATED")
assert(vault.label.text == "Loot specialization: Frost",
    "vault did not update after a loot specialization change")
local english = suite.Text
local translations = { ["Loot specialization: %s"] = "Beute: %s",
    ["Loot specialization: Current (%s)"] = "Beute: aktuell (%s)" }
suite.Text = function(value) return translations[value] or value end
Fire(vault, "PLAYER_LOOT_SPEC_UPDATED")
assert(vault.label.text == "Beute: Frost", "the vault hint is not one translatable sentence")
selected = 0
Fire(vault, "PLAYER_LOOT_SPEC_UPDATED")
assert(vault.label.text == "Beute: aktuell (Arcane)", "the current-spec hint is not one translatable sentence")
suite.Text, selected = english, secret
Fire(vault, "PLAYER_LOOT_SPEC_UPDATED")
assert(not vault.label.shown, "unreadable loot specialization was displayed")
vault.active = false
vault:Disable()

------------------------------------------------------------------ tooltip
-- The lines join Blizzard's build through the shared post-calls of
-- TooltipLines.lua; nothing asks the tooltip to rebuild.
local alt = false
local callbacks = {}
Enum = { TooltipDataType = { Item = 1, Spell = 2, Unit = 3, Quest = 4, Currency = 5 } }
TooltipDataProcessor = {
    AddTooltipPostCall = function(kind, callback) callbacks[kind] = callback end,
}
canaccesstable = function() return true end
IsAltKeyDown = function() return alt end
strsplit = function(delimiter, value)
    local parts = {}
    for part in value:gmatch("[^" .. delimiter .. "]+") do parts[#parts + 1] = part end
    return unpack(parts)
end
GameTooltip = {
    shown = true, lines = {}, refreshes = 0,
    IsShown = function(self) return self.shown end,
    GetOwner = function() return nil end,
    AddDoubleLine = function(self, label, value) self.lines[#self.lines + 1] = { label, value } end,
    RefreshDataNextUpdate = function(self) self.refreshes = self.refreshes + 1 end,
    -- TooltipDataHandlerMixin: the data of the open tooltip's build.
    GetPrimaryTooltipData = function(self) return self.data end,
    Show = function(self) self.shows = (self.shows or 0) + 1 end,
}
assert(loadfile(root .. "/MSUF_Suite_QualityOfLife/TooltipLines.lua"))(
    "MSUF_Suite_QualityOfLife", { NS = owner, Suite = suite })
Load("TooltipIDs")
local tooltip = assert(suite.instances.tooltipIDs)
tooltip.active, tooltip.context = true, Context()
tooltip.config = { showQuestCurrency = true, showSpellIcon = false, showTempEnchant = true, showAccountCurrency = false }
tooltip:Enable()
GameTooltip.data = { id = 77, type = Enum.TooltipDataType.Item }
callbacks[Enum.TooltipDataType.Item](GameTooltip, GameTooltip.data)
assert(#GameTooltip.lines == 0, "tooltip ID appeared without Alt")
-- Alt pressed over that open tooltip adds its ID to it and lays it out
-- again; nothing asks Blizzard to rebuild it, and a second press adds nothing.
alt = true
Fire(tooltip, "MODIFIER_STATE_CHANGED", "LSHIFT", 1)
Fire(tooltip, "MODIFIER_STATE_CHANGED", "LALT", 1)
Fire(tooltip, "MODIFIER_STATE_CHANGED", "LALT", 0)
Fire(tooltip, "MODIFIER_STATE_CHANGED", "RALT", 1)
assert(#GameTooltip.lines == 1 and GameTooltip.lines[1][2] == "77" and GameTooltip.shows == 1
    and GameTooltip.refreshes == 0, "pressing Alt over an open tooltip did not add its ID once without a rebuild")
-- Account character currency data arriving while a currency tooltip with
-- its IDs is open adds the lines that waited for it, once.
local ready = false
C_CurrencyInfo = {
    IsAccountCharacterCurrencyDataReady = function() return ready end,
    FetchCurrencyDataFromAccountCharacters = function() return { { characterName = "Alt", quantity = 40 } } end,
}
tooltip.config.showAccountCurrency = true
tooltip:Refresh()
GameTooltip.lines, GameTooltip.shows = {}, 0
GameTooltip.data = { id = 3008, type = Enum.TooltipDataType.Currency }
callbacks[Enum.TooltipDataType.Currency](GameTooltip, GameTooltip.data)
assert(#GameTooltip.lines == 1 and GameTooltip.lines[1][2] == "3008", "the currency ID is missing")
ready = true
Fire(tooltip, "ACCOUNT_CHARACTER_CURRENCY_DATA_RECEIVED")
Fire(tooltip, "ACCOUNT_CHARACTER_CURRENCY_DATA_RECEIVED")
assert(#GameTooltip.lines == 3 and GameTooltip.lines[2][2] == "40" and GameTooltip.lines[3][1] == "Alt"
    and GameTooltip.shows == 1 and GameTooltip.refreshes == 0,
    "arriving account currency data did not join the open tooltip once")
tooltip.config.showAccountCurrency = false
tooltip:Refresh()
assert(not tooltip.context.events.ACCOUNT_CHARACTER_CURRENCY_DATA_RECEIVED, "the account data listener outlived its option")
GameTooltip.lines, GameTooltip.data = {}, nil
callbacks[Enum.TooltipDataType.Item](GameTooltip, { id = 123 })
callbacks[Enum.TooltipDataType.Spell](GameTooltip, { id = secret })
callbacks[Enum.TooltipDataType.Unit](GameTooltip,
    { guid = "Creature-0-1-2-3-98765-0000" })
assert(GameTooltip.refreshes == 0 and #GameTooltip.lines == 2
    and GameTooltip.lines[1][2] == "123" and GameTooltip.lines[2][2] == "98765",
    "Alt tooltip did not show only public item and creature IDs")
tooltip.active = false
tooltip:Disable()
callbacks[Enum.TooltipDataType.Item](GameTooltip, { id = 456 })
assert(#GameTooltip.lines == 2, "disabled tooltip callback added a line")

print("Suite QoL utilities: merchant, vault and tooltip lifecycle passed")

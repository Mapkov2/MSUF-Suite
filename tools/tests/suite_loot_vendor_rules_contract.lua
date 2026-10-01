local root = assert(arg[1], "repository root required")
local Support = dofile(root .. "/tools/tests/suite_test_support.lua")
local module, sold, popups, printed, reported = nil, {}, {}, {}, {}
local frames = Support.EventFrames()
local combat, cursor = false, false
local bagSlots = { [0] = {}, [1] = {}, [2] = {}, [3] = {}, [4] = {}, [5] = {} }

Enum = { BagIndex = { Backpack = 0, ReagentBag = 5 } }
ItemLocation = { CreateFromBagAndSlot = function(_, bag, slot) return { bag = bag, slot = slot } end }
local function Item(id, guid, quality, extras)
    local info = { itemID = id, quality = quality, hyperlink = "item-" .. id,
        hasNoValue = false, hasLoot = false, isLocked = false }
    for key, value in pairs(extras or {}) do info[key] = value end
    return { guid = guid, info = info, quest = { isQuestItem = false } }
end
bagSlots[0][1] = Item(100, "sale-one", 1)
bagSlots[0][2] = Item(100, "rare", 3)
bagSlots[0][3] = Item(100, "quest", 1)
bagSlots[0][3].quest = { isQuestItem = true, questID = 900 }
bagSlots[0][4] = Item(200, "gear", 2)
bagSlots[0][5] = Item(100, "box", 1, { hasLoot = true })
bagSlots[0][6] = Item(100, "no-value", 1, { hasNoValue = true })
bagSlots[1][1] = Item(100, "sale-two", 2)

C_Container = {
    GetContainerNumSlots = function(bag) return bag == 0 and 6 or bag == 1 and 1 or 0 end,
    GetContainerItemInfo = function(bag, slot)
        local item = bagSlots[bag][slot]
        return item and item.info or nil
    end,
    GetContainerItemQuestInfo = function(bag, slot)
        local item = bagSlots[bag][slot]
        return item and item.quest or nil
    end,
    UseContainerItem = function(bag, slot) sold[#sold + 1] = { bag, slot } end,
}
C_Item = {
    GetItemGUID = function(location)
        local item = bagSlots[location.bag][location.slot]
        return item and item.guid or nil
    end,
    IsEquippableItem = function(link) return link == "item-200" and true or false end,
}
CursorHasItem = function() return cursor end
StaticPopupDialogs = {}
StaticPopup_Show = function(key, count, _, data)
    popups[#popups + 1] = { key = key, count = count, data = data }
end
StaticPopup_Hide = function(key) popups.hidden = key end
GameTooltip_Hide = function() end
GameTooltip = {}
MerchantFrame = { shown = false, selectedTab = 1, GetFrameLevel = function() return 20 end }
function MerchantFrame:IsShown() return self.shown end

local buttonCount = 0
local S = {
    Dispatch = Support.Dispatcher(reported),
    Public = function(value) return value ~= "secret" end,
    Finite = function(value) return type(value) == "number" and value == value
        and value > -math.huge and value < math.huge end,
    -- A translation of the counted label, so the label must be one sentence.
    Text = function(value) return value == "Sell marked items (%d)" and "Verkaufen (%d)" or value end,
    BlizzardText = function(_, fallback) return fallback end,
    Install = function(id, instance) assert(id == "lootVendorRules"); module = instance end,
    CreateFrame = function(kind, _, _, template)
        if kind == "Frame" and not template then return frames.Create() end
        buttonCount = buttonCount + 1
        local button = { shown = false }
        function button:SetSize(w, h) self.width, self.height = w, h end
        function button:SetPoint(...) self.point = { ... } end
        function button:SetFrameLevel(value) self.level = value end
        function button:SetText(value) self.text = value end
        function button:SetScript(name, callback) self[name] = callback end
        function button:SetEnabled(value) self.enabled = value end
        function button:Show() self.shown = true end
        function button:Hide() self.shown = false end
        return button
    end,
}
local NS = {
    Safety = { IsForbidden = function() return false end },
    IsCombatLocked = function() return combat end,
    Print = function(value) printed[#printed + 1] = value end,
}
Support.QoLStyleFixture(root, S)
local context = { events = {} }
function context:Event(name, callback) self.events[name] = callback end
function context:RemoveEvent(name) self.events[name] = nil end

-- SharedItems.lua loads first in the TOC: the shared ID list, bag-item
-- GUID and item-data helpers.
assert(loadfile(root .. "/MSUF_Suite_QualityOfLife/SharedItems.lua"))(
    "MSUF_Suite_QualityOfLife", { NS = NS, Suite = S })
assert(loadfile(root .. "/MSUF_Suite_QualityOfLife/LootVendorRules.lua"))(
    "MSUF_Suite_QualityOfLife", { NS = NS, Suite = S })
module.config = { itemIDs = "100, 200; 100 bad", maxQuality = 2, includeGear = false }
module.context, module.active = context, true
module:Enable()
assert(buttonCount == 0 and context.events.MERCHANT_SHOW and not context.events.BAG_UPDATE_DELAYED,
    "vendor rule helper did work before a merchant opened")

MerchantFrame.shown = true
context.events.MERCHANT_SHOW(module, "MERCHANT_SHOW")
assert(buttonCount == 1 and module.button.shown and module.button.enabled
    and module.button.text == "Verkaufen (2)"
    and context.events.BAG_UPDATE_DELAYED,
    "the merchant button did not preview only eligible non-gear stacks")
module.button.OnClick(module.button)
assert(#popups == 1 and popups[1].count == 2 and #sold == 0,
    "click sold without an explicit confirmation or previewed the wrong count")

-- Replacing a slot after confirmation is shown must not sell the new item.
bagSlots[0][1] = Item(100, "replacement", 1)
StaticPopupDialogs[popups[1].key].OnAccept({}, popups[1].data)
assert(#sold == 1 and sold[1][1] == 1 and sold[1][2] == 1,
    "confirmation sold a changed slot or skipped its still-matching item")
assert(#printed == 1, "sale request was not reported")

combat = true
module:UpdateButton()
assert(not module.button.shown and context.events.PLAYER_REGEN_ENABLED,
    "combat did not hide the sale action")
combat = false
context.events.PLAYER_REGEN_ENABLED(module, "PLAYER_REGEN_ENABLED")
assert(module.button.shown and module.button.enabled,
    "merchant action did not return after combat")

module.config.includeGear, module.config.maxQuality = true, 3
module:Refresh()
assert(buttonCount == 1 and module.button.text == "Verkaufen (4)",
    "explicit gear opt-in and quality cap did not update the preview")
module.button.OnClick(module.button)
MerchantFrame.shown = false
context.events.MERCHANT_CLOSED(module, "MERCHANT_CLOSED")
StaticPopupDialogs[popups[2].key].OnAccept({}, popups[2].data)
assert(#sold == 1 and not module.button.shown and not context.events.BAG_UPDATE_DELAYED,
    "closing merchant allowed a stale confirmation to sell")

module.active = false
module:Disable()
assert(not context.events.MERCHANT_SHOW and not context.events.MERCHANT_CLOSED
    and not context.events.BAG_UPDATE_DELAYED and not module.button.shown,
    "disable left merchant handlers or its button")
module.active, MerchantFrame.shown = true, true
module:Enable()
-- A second item window beside the merchant keeps the sale manual.
MailFrame = { IsShown = function() return true end }
module.button.OnClick(module.button)
StaticPopupDialogs[popups[#popups].key].OnAccept({}, popups[#popups].data)
assert(#sold == 1, "a sale ran while another item window was open")
MailFrame = nil
module.button.OnClick(module.button)
-- The client refuses a restricted item use with ADDON_ACTION_BLOCKED, not
-- with a Lua error.
C_Container.UseContainerItem = function(bag, slot)
    frames.Fire("ADDON_ACTION_BLOCKED", "MSUF_Suite_QualityOfLife", "UseContainerItem()")
end
StaticPopupDialogs[popups[#popups].key].OnAccept({}, popups[#popups].data)
assert(#sold == 1 and #reported == 0 and printed[#printed]
    == "Marked item sale stopped; earlier items may already have been sold.",
    "a blocked merchant item use hid the partial-sale warning")
print("Suite marked vendor rules: preview, revalidation, combat, merchant close passed")

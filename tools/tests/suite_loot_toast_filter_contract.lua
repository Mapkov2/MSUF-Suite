local root = assert(arg[1], "repository root required")
local module, frames, shows = nil, {}, 0
local Support = dofile(root .. "/tools/tests/suite_test_support.lua")
local combat = false

local function Widget(parent)
    local widget = { parent = parent, shown = true }
    local noOp = function() end
    widget.SetSize, widget.SetPoint, widget.SetAllPoints = noOp, noOp, noOp
    widget.SetColorTexture, widget.SetWidth, widget.SetJustifyH = noOp, noOp, noOp
    widget.SetWordWrap, widget.EnableMouse, widget.SetTexture = noOp, noOp, noOp
    widget.SetTextColor = noOp
    function widget:Show() self.shown = true; shows = shows + 1 end
    function widget:Hide() self.shown = false end
    function widget:IsShown() return self.shown end
    function widget:SetScript(name, fn) self[name] = fn end
    function widget:CreateTexture() return Widget(self) end
    function widget:CreateFontString()
        local fs = Widget(self)
        function fs:SetFontObject(font) assert(font); self.font = font end
        function fs:SetText(text)
            assert(self.font, "SetText without a font")
            self.text = text
        end
        return fs
    end
    return widget
end

UIParent = Widget()
CreateFrame = function(_, _, parent)
    local frame = Widget(parent)
    frames[#frames + 1] = frame
    return frame
end
GameFontHighlightSmall, GameFontNormalSmall = {}, {}
GameTooltip = {
    SetOwner = function(self, owner) self.owner = owner end,
    IsOwned = function(self, frame) return self.owner == frame end,
    SetHyperlink = function(_, link) assert(link == "item:100") end,
    Show = function(self) self.shown = true end,
    Hide = function(self) self.shown = false end,
}
local clock = Support.Clock()
local items = {
    [100] = { "Epic item", 4, 1000 },
    [101] = { "Rare item", 3, 1001 },
    [102] = { "Mount item", 4, 1002 },
    [103] = { "Pet item", 4, 1003 },
}
C_MountJournal = { GetMountFromItem = function(itemID)
    if itemID == 102 then return 77 end
end }
C_PetJournal = { GetPetInfoByItemID = function(itemID)
    if itemID == 103 then return "Pet species" end
end }
C_Item = {
    GetItemInfoInstant = function(link)
        local itemID = tonumber(link:match("item:(%d+)"))
        return itemID, nil, nil, nil, nil, itemID == 103 and 17 or 15
    end,
    GetItemInfo = function(link)
        local item = items[tonumber(link:match("item:(%d+)"))]
        if item then return item[1], link, item[2], nil, nil, nil, nil, nil, nil, item[3] end
    end,
}
local S = {
    Public = function(value) return value ~= "secret" end,
    PublicText = function(value)
        return value ~= "secret" and type(value) == "string" and value ~= "" and value or nil
    end,
    Finite = function(value) return type(value) == "number" and value == value end,
    Install = function(id, instance) assert(id == "lootToastFilter"); module = instance end,
}
local NS = {
    Safety = { IsForbidden = function() return false end },
    IsCombatLocked = function() return combat end,
    Dispatch = function(callback, ...) return callback(...) end,
}
local context = Support.ModuleTimers(root, S, NS)("lootToastFilter", nil, { events = {} })
function context:Event(name, callback) self.events[name] = callback end
function context:RemoveEvent(name) self.events[name] = nil end

assert(loadfile(root .. "/tools/tests/suite_test_support.lua"))().QoLStyleFixture(root, S)
-- SharedItems.lua loads first in the TOC: the shared ID list, bag-item
-- GUID and item-data helpers.
assert(loadfile(root .. "/MSUF_Suite_QualityOfLife/SharedItems.lua"))(
    "MSUF_Suite_QualityOfLife", { NS = NS, Suite = S })
assert(loadfile(root .. "/MSUF_Suite_QualityOfLife/LootToastFilter.lua"))(
    "MSUF_Suite_QualityOfLife", { NS = NS, Suite = S })
module.context, module.active = context, true
S.instances.lootToastFilter = module
module.config = { minQuality = 4, itemIDs = "" }
module:Enable()
local function Toast(kind, link, quantity, personal)
    context.events.SHOW_LOOT_TOAST(module, "SHOW_LOOT_TOAST", kind, link, quantity,
        0, 0, personal)
end
Toast("item", "item:101", 1, true)
Toast("item", "item:100", 1, false)
Toast("currency", "item:100", 1, true)
Toast("item", "secret", 1, true)
assert(#frames == 0, "filter displayed other-player, non-item, low-quality or secret data")

-- Blizzard's own loot toasts show in combat; so does this notice.
combat = true
Toast("item", "item:100", 2, true)
combat = false
assert(#frames == 1 and frames[1]:IsShown() and frames[1].name.text == "Epic item"
    and frames[1].count.text == "x2", "personal epic toast was not rendered in combat")
frames[1].OnEnter(frames[1])
assert(GameTooltip.shown and GameTooltip.owner == frames[1], "the toast did not show its item")
GameTooltip.owner = "another frame"
frames[1].OnLeave(frames[1])
assert(GameTooltip.shown, "leaving the toast hid a tooltip another frame owns")
GameTooltip.owner = frames[1]
frames[1].OnLeave(frames[1])
assert(not GameTooltip.shown, "leaving the toast kept its tooltip")
clock.Advance(3)
Toast("item", "item:100", 1, true)
Toast("item", "item:100", 1, true)
Toast("item", "item:100", 1, true)
assert(#frames == 3, "toast pool exceeded three frames")
clock.Advance(2.5)
assert(frames[1]:IsShown() and frames[2].link ~= nil, "stale timer hid a reused toast")
clock.Advance(2.6)
assert(not frames[1]:IsShown() and not frames[1].link, "a toast outlived its five seconds")

module.config.itemIDs = "101"
module.config.minQuality = 3
module:Refresh()
Toast("item", "item:100", 1, true)
assert(frames[1].name.text == "Epic item", "item ID allowlist did not filter")
Toast("item", "item:101", 1, true)
assert(frames[2].name.text == "Rare item", "allowed item ID was hidden")

module.config.itemIDs, module.config.minQuality = "", 4
module.config.kindFilter = 2
module:Refresh()
local before = shows
Toast("item", "item:100", 1, true)
assert(shows == before, "mount-only filter showed a normal item")
Toast("item", "item:102", 1, true)
assert(shows == before + 1, "mount-only filter missed a mount item")
module.config.kindFilter = 3
module:Refresh()
before = shows
Toast("item", "item:102", 1, true)
assert(shows == before, "pet-only filter showed a mount item")
Toast("item", "item:103", 1, true)
assert(shows == before + 1, "pet-only filter missed a pet item")
module.config.kindFilter = 4
module:Refresh()
before = shows
Toast("item", "item:100", 1, true)
Toast("item", "item:103", 1, true)
assert(shows == before + 1, "mount-or-pet filter did not restrict ordinary items")

module.config.kindFilter = 1
module:Refresh()
-- A first-seen item has no data yet (GetItemInfo returns nothing): its toast
-- waits for GET_ITEM_INFO_RECEIVED of that item and is shown then.
local waitShows = shows
Toast("item", "item:104", 1, true)
assert(shows == waitShows and context.events.GET_ITEM_INFO_RECEIVED,
    "a loot toast for an uncached item was dropped instead of waiting for its data")
context.events.GET_ITEM_INFO_RECEIVED(module, "GET_ITEM_INFO_RECEIVED", 999, true)
assert(shows == waitShows, "another item's data showed the waiting toast")
items[104] = { "New mount item", 4, 1004 }
context.events.GET_ITEM_INFO_RECEIVED(module, "GET_ITEM_INFO_RECEIVED", 104, true)
local arrivedToast
for _, frame in ipairs(frames) do
    if frame:IsShown() and frame.name.text == "New mount item" then arrivedToast = frame end
end
assert(shows == waitShows + 1 and arrivedToast and not context.events.GET_ITEM_INFO_RECEIVED,
    "the loot toast did not show once its item data arrived")
Toast("item", "item:105", 1, true)
assert(context.events.GET_ITEM_INFO_RECEIVED, "the second uncached item did not wait")

module:Disable()
module.active = false
assert(not context.events.SHOW_LOOT_TOAST and not context.events.GET_ITEM_INFO_RECEIVED and not frames[1]:IsShown()
    and not frames[2]:IsShown() and not frames[3]:IsShown(),
    "disable left toasts or events active")
frames[2].shown = true
clock.Advance(6)
assert(frames[2]:IsShown(), "a cancelled toast timeout still ran after disable")
frames[2].shown = false
print("suite_loot_toast_filter_contract: ok")

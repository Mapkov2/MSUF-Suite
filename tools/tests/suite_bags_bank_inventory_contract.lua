local root = assert(arg[1])
local combat, timers, scans, actions = false, {}, {}, {}
local methods = {}
local function Widget()
    return setmetatable({ shown = true, scripts = {} }, { __index = methods })
end
function methods:SetPoint(...) self.point = { ... }; self.moves = (self.moves or 0) + 1 end
function methods:ClearAllPoints() self.point = nil end
function methods:Show() self.shown = true end
function methods:Hide()
    local wasShown = self.shown
    self.shown = false
    if wasShown and self.scripts.OnHide then self.scripts.OnHide(self) end
end
function methods:SetShown(value) if value then self:Show() else self:Hide() end end
function methods:IsShown() return self.shown end
function methods:SetText(value) self.text = value end
function methods:GetText() return self.text end
function methods:SetSize(w, h) self.width, self.height = w, h end
function methods:SetWidth(w) self.width = w end
function methods:SetHeight(h) self.height = h end
function methods:GetWidth() return self.width or 750 end
function methods:GetHeight() return self.height or 500 end
function methods:GetFrameLevel() return 10 end
function methods:SetScript(event, callback) self.scripts[event] = callback end
function methods:HookScript(event, callback) self.scripts[event] = callback end
function methods:SetEnabled(value) self.enabled = value end
function methods:SetScrollChild(value) self.child = value end
function methods:RegisterEvent(event) self.events = self.events or {}; self.events[event] = true end
function methods:RegisterUnitEvent(event, unit) self.events = self.events or {}; self.events[event] = unit end
function methods:UnregisterAllEvents() self.events = {} end
for _, name in ipairs({ "SetJustifyH", "SetAllPoints", "SetFrameLevel", "EnableMouse", "EnableMouseWheel", "SetColorTexture" }) do
    methods[name] = function() end
end
function methods:Init(kind, bag, slot)
    self.bankType, self.bankTabID, self.containerSlotID = kind, bag, slot
    self:Refresh()
end
function methods:Refresh() self.refreshes = (self.refreshes or 0) + 1 end
function methods:UpdateCooldown() self.cooldowns = (self.cooldowns or 0) + 1 end
UIParent, GameTooltip, StackSplitFrame = Widget(), Widget(), Widget()
GameTooltip.IsOwned = function() return false end
StackSplitFrame:Hide()
C_Timer = { After = function(_, callback) timers[#timers + 1] = callback end }
hooksecurefunc = function(owner, key, callback)
    local previous = owner[key]
    owner[key] = function(...) if previous then previous(...) end; callback(...) end
end
SetItemButtonDesaturated = function(button, value) button.desaturated = value end
Enum = { BankType = { Character = 1, Account = 2 }, TooltipDataType = { Item = 0 } }
-- Blizzard_SharedXMLGame defines the tooltip data processor at startup.
TooltipDataProcessor = { AddTooltipPostCall = function() end }
BankFrame = Widget()
BankFrame.BankPanel, BankFrame.TabIDToBankType = Widget(), { [4] = 1, [7] = 2 }
BankFrame.activeType = 1
function BankFrame:GetActiveBankType() return self.activeType end
-- Switching Blizzard's bank type from Suite code taints BankPanel.
function BankFrame:SetTab() error("Suite code drove BankFrame:SetTab") end
local accessible = { [1] = true, [2] = true }
C_Bank = {
    CanViewBank = function(kind) return accessible[kind] end,
    CanUseBank = function(kind) return accessible[kind] end,
    FetchPurchasedBankTabData = function(kind) return { { ID = kind == 1 and 12 or 13, name = "Tab " .. kind } } end,
}
local errors, cursor = {}, nil
UIErrorsFrame = { AddExternalErrorMessage = function(_, text) errors[#errors + 1] = text end }
IsModifiedClick = function() return false end
CursorHasItem = function() return cursor ~= nil end
C_Cursor = { GetCursorItem = function() return cursor end }
local info = { [12] = { itemID = 10, hyperlink = "item:10", stackCount = 5, quality = 1 },
    [13] = { itemID = 10, hyperlink = "item:10", stackCount = 7, quality = 1 } }
C_Container = {
    PickupContainerItem = function(bag, slot) actions[#actions + 1] = { bag, slot } end,
    GetBagName = function(bag) return "Tab " .. bag end,
    GetContainerNumSlots = function() return 2 end,
    GetContainerItemInfo = function(bag, slot) scans[bag] = (scans[bag] or 0) + 1; return slot == 1 and info[bag] or nil end,
    GetContainerItemQuestInfo = function() return { isQuestItem = false } end,
}
C_Item = {
    GetItemInfo = function(link) return "Potion", link, 1, 1, 1, "Consumable", "Potion", 20, "", nil, 1, 0, 1, 1, 10 end,
    RequestLoadItemDataByID = function() end,
}
local state = {}
local c = { font = "Suite", bankView = 4, itemCountSize = 12, itemLevelSize = 12,
    showBankTabs = true, customCategories = "", mergeStacks = true, compactGroups = true }
local M = { active = true, config = c, Refresh = function() end, Disable = function() end,
    HideBankLevels = function(self) self.hiddenNativeLabels = true end,
    UpdateBank = function(self) self.nativeUpdates = (self.nativeUpdates or 0) + 1 end }
local S = {
    CreateFrame = function(kind) local w = Widget(); if kind == "ItemButton" then w.Count = Widget() end; return w end,
    CreateTexture = Widget, CreateFontString = Widget, Text = function(v) return v end,
    SetFont = function() end, ResolveFont = function() return "Suite" end,
    Public = function() return true end, Finite = function(v) return type(v) == "number" end,
    PublicText = function(v) return type(v) == "string" and v ~= "" and v or nil end,
    ModuleState = function() return state end,
    Set = function(_, key, value) c[key] = value; M:Refresh() end,
}
local P = { Suite = S, NS = { IsCombatLocked = function() return combat end,
    Client = { SupportsEvent = function() return true end } }, BagsModule = M,
    StackSplitter = { OwnerHidden = function() end, OpenFor = function() end } }
UnitGUID = function() return "Player-1" end
for _, file in ipairs({ "SlotCache", "InventoryModel", "InventoryIndex", "GridView", "InventoryDetails", "BankIndex",
    "BankActions", "BankInventory" }) do
    assert(loadfile(root .. "/MSUF_Suite_Bags/" .. file .. ".lua"))("Bags", P)
end
local B = P.BankInventory
-- Bags.lua runs the bank view from its sub-module list after its own refresh and stop.
M.Refresh, M.Disable = function() B.Refresh() end, function() B.Disable() end
P.SlotCache.Start()
-- Every registered frame receives the event, the shared slot cache included.
local function Fire(event, ...)
    B.events.scripts.OnEvent(nil, event, ...)
    local cache = P.SlotCache.events
    if cache.events[event] then cache.scripts.OnEvent(cache, event, ...) end
end
local function Flush()
    assert(#timers == 1, "bank updates coalesce")
    table.remove(timers, 1)()
end
M:Refresh()
M:Refresh()
Flush()
assert(B.active and M.organizedBankActive and #B.index.items == 4, "shared categories include both banks and empty slots")
assert(B.model.rowCount == 4, "bank physical stacks must never merge")
local bank2
for _, button in ipairs(B.buttons) do if button.record.bankType == 2 then bank2 = button; break end end
assert(bank2)
-- A warband item moves only while Blizzard's Warband Bank tab is selected:
-- Blizzard's own bag clicks then confirm refundable swaps.
bank2.scripts.OnClick(bank2, "LeftButton")
assert(#actions == 0 and #errors == 1, "a warband item was picked up while Blizzard's Bank tab was selected")
BankFrame.activeType = 2
bank2.scripts.OnClick(bank2, "LeftButton")
assert(#actions == 1 and actions[1][1] == 13 and actions[1][2] == 1,
    "the Suite must pick bank items up with C_Container, never through BankFrame")
combat = true
cursor = {}
bank2.scripts.OnReceiveDrag(bank2)
assert(#actions == 1, "bank item actions defer in combat")
cursor = nil
local moves = bank2.moves
Fire("BAG_UPDATE", 13)
Flush()
assert(bank2.moves == moves, "combat update leaves layout alone")
combat = false
Fire("PLAYER_REGEN_ENABLED")
Flush()
local old12, old13 = scans[12], scans[13]
Fire("BAG_UPDATE", 13)
Fire("ITEM_LOCK_CHANGED", 13)
Flush()
assert(scans[12] == old12 and scans[13] == old13 + 2, "only changed bank tab is indexed")
-- Equipment locks send ITEM_LOCK_CHANGED(inventorySlot, nil); slots 6-16 share
-- the bank tab IDs and must not cause a bank pass.
old12, old13 = scans[12], scans[13]
Fire("ITEM_LOCK_CHANGED", 13)
assert(#timers == 0, "an equipment lock without a slot scheduled a bank pass")
Fire("ITEM_LOCK_CHANGED", 13, 1)
Flush()
assert(scans[12] == old12 and scans[13] == old13 + 1, "a locked bank slot must be read alone")
old12, old13 = scans[12], scans[13]
Fire("BAG_UPDATE_COOLDOWN")
Fire("INVENTORY_SEARCH_UPDATE")
assert(#timers == 0 and scans[12] == old12 and scans[13] == old13,
    "cooldowns and search update visible native widgets without reindexing bank contents")
assert(bank2.cooldowns == 1)
-- The bank view never reads isFiltered: a search leaves the cached bank tabs
-- valid, so the next bank pass reads only the tab that changed.
Fire("BAG_UPDATE", 13)
Flush()
assert(scans[12] == old12 and scans[13] == old13 + 2,
    "a search made the next bank pass read every bank tab again")
-- Quest changes of group members never reach the slot cache.
assert(P.SlotCache.events.events.UNIT_QUEST_LOG_CHANGED == "player",
    "the slot cache listens for every group member's quest log")
old12, old13 = scans[12], scans[13]
Fire("UNIT_QUEST_LOG_CHANGED", "player")
Fire("BAG_UPDATE", 13)
Flush()
assert(scans[12] == old12 + 2 and scans[13] == old13 + 2, "the player's quest change did not read every tab again")
B.selected = "tab:13"
accessible[2] = false
Fire("BANK_TABS_CHANGED")
Flush()
assert(#B.index.items == 2, "inaccessible warbank is excluded")
assert(B.selected == "all", "a lost bank tab cannot leave an empty selected view")
B.selected = "custom:99"
M:Refresh(); Flush()
assert(B.selected == "all", "deleted categories restore all items")
-- Without a module state (no profile loaded yet) the bank view waits.
local savedState = state
state = nil
M:Refresh(); Flush()
state = savedState
M:Refresh(); Flush()
assert(B.active and #B.index.items == 2, "the bank view returns once the module state exists")
c.bankView = 1
M:Refresh(); Flush()
assert(not B.active and not B.frame:IsShown() and M.nativeUpdates > 0, "native bank management restored")
BankFrame:Hide()
Fire("BAG_UPDATE", 12)
assert(#timers == 0, "closed bank performs no scan or render")
M:Disable()
assert(not B.modeButton:IsShown() and next(B.events.events) == nil, "disable releases owned controls and events")
print("bank scopes, native actions, physical slots, incremental updates and ownership passed")

local root = assert(arg[1], "repository root required")
local combat, timers, calls, state = false, {}, { scans = 0, fonts = 0 }, {}
local methods = {}
local function Widget()
    return setmetatable({ shown = true, scripts = {}, font = { "Native", 14, "" } }, { __index = methods })
end
function methods:SetPoint(...) self.point = { ... }; self.moves = (self.moves or 0) + 1 end
function methods:ClearAllPoints() self.point = nil end
function methods:Show() self.shown = true end
function methods:Hide() self.shown = false end
function methods:SetShown(value) self.shown = value end
function methods:IsShown() return self.shown end
function methods:SetText(value) self.text = value end
function methods:GetText() return self.text end
function methods:SetSize(width, height) self.width, self.height = width, height end
function methods:SetWidth(value) self.width = value end
function methods:SetHeight(value) self.height = value end
function methods:GetHeight() return self.height or 1080 end
function methods:GetWidth() return self.width or 0 end
function methods:GetEffectiveScale() return 1 end
-- The bag window stands at Blizzard's anchor, CONTAINER_OFFSET_Y above the
-- screen bottom; its money row is 24 units high.
function methods:GetBottom() return self.bottom end
function methods:GetTop() return self.top end
function methods:GetScale() return 1 end
function methods:GetFrameLevel() return 10 end
function methods:SetScript(event, callback) self.scripts[event] = callback end
function methods:HookScript(event, callback)
    local previous = self.scripts[event]
    self.scripts[event] = function(...) if previous then previous(...) end; callback(...) end
end
function methods:SetEnabled(value) self.enabled = value end
function methods:SetScrollChild(value) self.child = value end
function methods:EnableMouseWheel(value) self.mouseWheel = value end
function methods:IsMouseWheelEnabled() return self.mouseWheel == true end
function methods:SetFont(...) self.font = { ... }; calls.fonts = calls.fonts + 1 end
function methods:GetFont() return unpack(self.font) end
function methods:RegisterEvent(event) self.events = self.events or {}; self.events[event] = true end
function methods:UnregisterAllEvents() self.events = {} end
for _, name in ipairs({ "SetJustifyH", "SetAllPoints", "SetFrameLevel", "RegisterForClicks", "RegisterForDrag", "SetNormalTexture" }) do
    methods[name] = function() end
end
UIParent = Widget()
UIParent.top = 1080
-- Blizzard_FrameXML builds StackSplitFrame at startup on both clients.
StackSplitFrame = Widget()
StackSplitFrame:Hide()
CONTAINER_OFFSET_Y = 85
GetFormattedItemQuantity = function(quantity, maximum)
    if quantity > (maximum or 9999) then return "*" end
    return quantity
end
GameTooltip_Hide = function() end
C_Timer = { After = function(_, callback) timers[#timers + 1] = callback end }
local function Flush()
    assert(#timers == 1, "native update bursts must coalesce into one render")
    local callback = table.remove(timers, 1)
    callback()
end
hooksecurefunc = function(owner, key, callback)
    local previous = owner[key]
    owner[key] = function(...) if previous then previous(...) end; callback(...) end
end
SetItemButtonDesaturated = function(button, value) button.desaturated = value end
UpdateContainerFrameAnchors = function() end
GetCursorInfo = function() end
ClearCursor = function() end
local info = {
    { itemID = 10, hyperlink = "item:10", stackCount = 5, quality = 1 },
    { itemID = 10, hyperlink = "item:10", stackCount = 7, quality = 1 },
}
C_Container = {
    GetBagName = function() return "Backpack" end,
    GetContainerNumSlots = function(bag) return bag == 0 and 3 or 0 end,
    GetContainerItemInfo = function(_, slot) calls.scans = calls.scans + 1; return info[slot] end,
    GetContainerItemQuestInfo = function() return { isQuestItem = false } end,
}
C_Item = {
    GetItemInfo = function(link) return "Potion", link, 1, 1, 1, "Consumable", "Potion", 20, "", nil, 1, 0, 1, 1, 10 end,
    RequestLoadItemDataByID = function() end,
}
C_NewItems = { IsNewItem = function() return false end }
local frame, buttons = Widget(), {}
frame.bottom, frame.MoneyFrame = 85, Widget()
frame.MoneyFrame.top = 109
for i = 1, 3 do
    local button = Widget()
    button.Count = Widget()
    button.GetBagID = function() return 0 end
    button.GetID = function() return i end
    buttons[i] = button
end
function frame:EnumerateValidItems() return ipairs(buttons) end
function frame:UpdateItems()
    for i = 1, #buttons do buttons[i].Count:SetText(info[i] and info[i].stackCount or "") end
end
function frame:UpdateItemLayout()
    for i = 1, #buttons do buttons[i]:SetPoint("NATIVE", i) end
end
function frame:UpdateFrameSize() self:SetSize(420, 400) end
local c = { font = "Suite", inventoryColumns = 12, inventoryRows = 8, inventoryView = 1,
    itemCountSize = 12, mergeStacks = true, showPinned = true, showRecent = true,
    customCategories = "", hideEmptyCategories = true, compactGroups = true }
local module = { active = true, frame = frame, config = c, Refresh = function() end,
    RefreshWindowLayout = function() end, NativeAnchorPass = function() UpdateContainerFrameAnchors() end }
function module:Disable() self.active = false end
local S = {
    CreateFrame = Widget, CreateFontString = Widget, Text = function(value) return value end,
    SetFont = function(label, ...) label:SetFont(...) end,
    GlobalFontPath = function() return "Suite" end, ResolveFont = function() return "Suite" end,
    Public = function() return true end, Finite = function(v) return type(v) == "number" end,
    PublicText = function(v) return type(v) == "string" and v ~= "" and v or nil end,
    ModuleState = function() return state end,
    Set = function(_, key, value) c[key] = value; module:Refresh(); return true end,
}
local _, catalog = dofile(root .. "/tools/tests/suite_test_support.lua").CatalogDefaults(root, "bags")
local P = { Suite = S, NS = { IsCombatLocked = function() return combat end, BagsView = catalog.BagsView,
    InCombat = function(event)
        if event == "PLAYER_REGEN_DISABLED" then return true end
        if event == "PLAYER_REGEN_ENABLED" then return false end
        return combat
    end,
    Client = { SupportsEvent = function() return true end } }, BagsModule = module,
    BagFinance = { Refresh = function() end },
    InventoryEditor = { Show = function() end, Hide = function() end, ShowPinned = function() end } }
UnitGUID = function() return "Player-1" end
-- Recent items remember their arrival in server time.
GetServerTime = function() return 1000000 end
Enum = { TooltipDataType = { Item = 0 },
    ItemClass = { Consumable = 0, Container = 1, Weapon = 2, Gem = 3, Armor = 4, Reagent = 5, Projectile = 6,
        Tradegoods = 7, ItemEnhancement = 8, Recipe = 9, Quiver = 11, Questitem = 12, Key = 13, Miscellaneous = 15 },
    ItemQuality = { Poor = 0, Common = 1, Uncommon = 2, Rare = 3, Epic = 4, Legendary = 5 } }
-- Blizzard_SharedXMLGame defines the tooltip data processor at startup.
TooltipDataProcessor = { AddTooltipPostCall = function() end }
for _, file in ipairs({ "SlotCache", "InventoryModel", "InventoryIndex", "GridView", "InventoryDetails", "InventoryView" }) do
    assert(loadfile(root .. "/MSUF_Suite_Bags/" .. file .. ".lua"))("Bags", P)
end
-- Bags.lua runs the view from its sub-module list after its own refresh and stop.
function module:Refresh() P.InventoryView.Refresh() end
function module:Disable()
    self.active = false
    P.InventoryView.Disable()
end
module:Refresh()
frame:UpdateItems()
frame:UpdateItemLayout()
frame:UpdateFrameSize()
Flush()
assert(buttons[1].Count.text == "12" and not buttons[2].shown, "merged visual count retains one native slot")
assert(buttons[3].shown, "empty slot remains a native drop target")
local stableMoves, stableFonts = buttons[1].moves, calls.fonts
frame:UpdateItems()
Flush()
assert(buttons[1].moves == stableMoves and calls.fonts == stableFonts,
    "unchanged native item updates preserve anchors and font settings")
local moves = buttons[1].moves
combat = true
frame:UpdateItems()
Flush()
assert(buttons[1].moves == moves, "no layout mutation in combat")
combat = false
P.InventoryView.events.scripts.OnEvent(nil, "PLAYER_REGEN_ENABLED")
Flush()
BankFrame = Widget()
P.InventoryView.events.scripts.OnEvent(nil, "BANKFRAME_OPENED")
Flush()
assert(buttons[1].Count.text == "5" and buttons[2].Count.text == "7" and buttons[2].shown,
    "bank transaction exposes every physical stack")
frame:Hide()
local scans = calls.scans
frame:UpdateItems()
assert(#timers == 0 and scans == calls.scans, "hidden bags do not schedule scans")
frame:Show()
module:Disable()
assert(not P.InventoryView.chrome.shown and not frame.mouseWheel, "owned chrome and wheel relinquished")
for i = 1, #buttons do
    assert(buttons[i].shown and buttons[i].point[1] == "NATIVE", "native slots restored")
    assert(buttons[i].Count.font[1] == "Native" and buttons[i].Count.font[2] == 14, "native count fonts restored")
end
print("bag view coalescing, hidden/combat paths, physical transactions and restoration passed")

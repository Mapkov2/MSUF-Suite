local _, P = ...
local NS, S = P.NS, P.Suite
-- Delete cheapest item: a button on the open bag that deletes the stack a
-- vendor would pay least for, as players do when the bags are full and loot
-- waits. It works only while the backpack's window is open and out of combat.
--   * Where: in the Suite Bags views beside Filters (Bags makes that button
--     in its own look and hands it to M:Bind, MSUF_Suite_Bags/
--     InventoryControls.lua); otherwise on the title of Blizzard's backpack
--     or combined bag window, left of its close button or of the Suite Bags
--     caption (S.BagsTitleInset, MSUF_Suite_Bags/BagCaption.lua).
--   * Nothing runs in the background. The bags are read on demand (a hover,
--     a click, the list); only the cheapest few are checked further (quest
--     items, equipment sets, Never sell items, refunds). Its events are the
--     two combat edges while enabled and BAG_UPDATE_DELAYED only while the
--     pointer rests on a button. From PLAYER_REGEN_DISABLED to
--     PLAYER_REGEN_ENABLED the buttons are disabled and nothing of this file
--     runs but the window hook's combat test.
--   * Offered: priced stacks of the chosen quality or lower (Poor by
--     default, never above Uncommon), unlocked and not kept by the player.
--   * A delete reads the slot again, picks up exactly the offered stack and
--     deletes it in the same click: DeleteCursorItem is a restricted call
--     (GameCursorDocumentation.lua HasRestrictions, live and forever). A
--     stack above Poor always asks first; Poor asks while the setting is on.
local M = { tools = setmetatable({}, { __mode = "k" }), natives = setmetatable({}, { __mode = "k" }),
    marks = setmetatable({}, { __mode = "k" }), ranked = {}, keep = {} }
S.CheapestItem = M
local POOR = Enum.ItemQuality.Poor
local CHOICE = NS.CheapestItemQuality
local QUALITY = { [CHOICE.POOR] = POOR, [CHOICE.COMMON] = Enum.ItemQuality.Common,
    [CHOICE.UNCOMMON] = Enum.ItemQuality.Uncommon }
-- Blizzard's localized quality names (GlobalStrings), with the Suite text.
local QUALITY_NAMES = { [CHOICE.POOR] = { "ITEM_QUALITY0_DESC", "Poor" },
    [CHOICE.COMMON] = { "ITEM_QUALITY1_DESC", "Common" }, [CHOICE.UNCOMMON] = { "ITEM_QUALITY2_DESC", "Uncommon" } }
local BACKPACK, LAST_BAG = Enum.BagIndex.Backpack, Constants.InventoryConstants.NumBagSlots
local KEY, LIST, KEEP_LIMIT, KEEP_SCROLL = 1000, 10, 200, 400
local QUESTION = "suite-delete-cheapest-item"
local MARK = { 1, .32, .2 }
local EDGES = { { "TOPLEFT", "TOPRIGHT", true }, { "BOTTOMLEFT", "BOTTOMRIGHT", true },
    { "TOPLEFT", "BOTTOMLEFT" }, { "TOPRIGHT", "BOTTOMRIGHT" } }
local HINT = { .72, .78, .85 }
local pool, eligible, setSlots = {}, {}, {}
local hovered, asked, hooked, repaint, SyncNative

------------------------------------------------------------------ kept items
local function Sorted(ids)
    local list = {}
    for id in pairs(ids) do list[#list + 1] = id end
    table.sort(list)
    return list
end

-- Keeps an item type from being offered (keep), or offers it again.
function M:Keep(itemID, keep)
    if not self.active or NS.InCombat() or not S.Finite(itemID) then return false end
    local ids = S.QoLParseIDs(self.config.keep, KEEP_LIMIT + 1)
    ids[itemID] = keep or nil
    local list = Sorted(ids)
    if #list > KEEP_LIMIT then
        S.Print(string.format(S.Text("The never delete list holds at most %d items."), KEEP_LIMIT))
        return false
    end
    return S.Set(self.id, "keep", table.concat(list, " "))
end

------------------------------------------------------------------ candidates
-- The backpack's window: Blizzard's combined bag (also under Suite Bags) or
-- the backpack's own window.
local function BagWindow()
    return ContainerFrameUtil_GetShownFrameForID(BACKPACK)
end

function M:Usable(event)
    return self.active == true and not NS.InCombat(event) and BagWindow() ~= nil
end

-- A slot's stack when its own read allows it: priced, unlocked, of an
-- offered quality and not kept. Fills the pooled record at index.
local function Read(bag, slot, index, highest)
    local info = C_Container.GetContainerItemInfo(bag, slot)
    if not S.Public(info) or type(info) ~= "table" then return false end
    local id, link, quality, stack = info.itemID, S.PublicText(info.hyperlink), info.quality, info.stackCount
    if not (S.Finite(id) and link and S.Finite(quality) and S.Finite(stack)) or stack < 1 or quality > highest
        or M.keep[id] or not S.Public(info.hasNoValue) or info.hasNoValue ~= false
        or not S.Public(info.isLocked) or info.isLocked ~= false then return false end
    local price = select(11, C_Item.GetItemInfo(link))
    if not S.Finite(price) or price <= 0 then return false end
    local record = pool[index]
    if not record then
        record = {}
        pool[index] = record
    end
    record.bag, record.slot, record.itemID, record.link = bag, slot, id, link
    record.count, record.quality, record.value = stack, quality, price * stack
    eligible[index] = record
    return true
end

local function Collect(highest)
    local count = 0
    for bag = BACKPACK, LAST_BAG do
        local slots = C_Container.GetContainerNumSlots(bag)
        if S.Finite(slots) then
            for slot = 1, math.min(slots, KEY - 1) do
                if Read(bag, slot, count + 1, highest) then count = count + 1 end
            end
        end
    end
    for i = count + 1, #eligible do eligible[i] = nil end
    return count
end

-- Cheapest first: the stack's vendor value, then quality, then bag order.
local function Cheaper(a, b)
    if a.value ~= b.value then return a.value < b.value end
    if a.quality ~= b.quality then return a.quality < b.quality end
    return a.bag * KEY + a.slot < b.bag * KEY + b.slot
end

-- The bag slots of the equipment sets (C_EquipmentSet.GetItemLocations,
-- EquipmentManagerDocumentation.lua on live and forever; Suite Bags reads the
-- set names the same way). False while unreadable: no equippable stack then.
local function ReadSets()
    for key in pairs(setSlots) do setSlots[key] = nil end
    local ids = C_EquipmentSet.GetEquipmentSetIDs()
    if not S.Public(ids) or type(ids) ~= "table" then return false end
    for i = 1, #ids do
        local locations = C_EquipmentSet.GetItemLocations(ids[i])
        if not S.Public(locations) then return false end
        -- An empty set returns nothing; its slots may hold holes.
        if type(locations) == "table" then
            for _, location in pairs(locations) do
                local data = S.Finite(location) and location >= 0 and EquipmentManager_GetLocationData(location)
                if data and data.isBags and S.Finite(data.bag) and S.Finite(data.slot) then
                    setSlots[data.bag * KEY + data.slot] = true
                end
            end
        end
    end
    return true
end

-- A quest item or quest starter; an unreadable answer counts as one.
local function QuestItem(bag, slot)
    local quest = C_Container.GetContainerItemQuestInfo(bag, slot)
    if not S.Public(quest) or type(quest) ~= "table" then return true end
    local objective, questID = quest.isQuestItem, quest.questID
    return not S.Public(objective) or objective ~= false or not S.Public(questID) or questID ~= nil
end

-- The slower tests, for the cheapest few only. sets: ReadSets() succeeded.
local function Allowed(record, sets)
    if QuestItem(record.bag, record.slot) then return false end
    if sets then
        if setSlots[record.bag * KEY + record.slot] then return false end
    else
        local equippable = C_Item.IsEquippableItem(record.link)
        if not S.Public(equippable) or equippable ~= false then return false end
    end
    if S.InventoryProtection:IsProtected(record.itemID, record.bag, record.slot) then return false end
    return S.QoLRefundable(record.bag, record.slot, false) == false
end

-- At most limit offered stacks, cheapest first; pooled records, valid until
-- the next call.
function M:Candidates(limit)
    local ranked = self.ranked
    for i = #ranked, 1, -1 do ranked[i] = nil end
    if not self:Usable() then return ranked end
    local count, sets = Collect(self.highest), nil
    table.sort(eligible, Cheaper)
    for i = 1, count do
        if #ranked < limit then
            if sets == nil then sets = ReadSets() end
            if Allowed(eligible[i], sets) then ranked[#ranked + 1] = eligible[i] end
        end
        eligible[i] = nil
    end
    return ranked
end

-- What a question or a list entry holds on to: the records are reused.
local function Snapshot(record)
    return { bag = record.bag, slot = record.slot, itemID = record.itemID, link = record.link,
        count = record.count, quality = record.quality, value = record.value }
end

local function Label(record)
    if record.count > 1 then return string.format(S.Text("%s x%d"), record.link, record.count) end
    return record.link
end

------------------------------------------------------------------ deleting
-- The slot still holds the offered stack, unlocked.
local function Unchanged(item)
    local info = C_Container.GetContainerItemInfo(item.bag, item.slot)
    if not S.Public(info) or type(info) ~= "table" then return false end
    local id, link, count, locked = info.itemID, info.hyperlink, info.stackCount, info.isLocked
    return S.Public(id) and S.Public(link) and S.Public(count) and S.Public(locked)
        and id == item.itemID and link == item.link and count == item.count and locked == false
end

-- Runs in the click that asked for it (a button, a list entry or the
-- question's accept) and deletes only the stack that was offered.
function M:Delete(item)
    if not self:Usable() or self.keep[item.itemID] or item.quality > self.highest then return false end
    local cursor = GetCursorInfo()
    if not S.Public(cursor) or cursor ~= nil or not Unchanged(item) or not Allowed(item, ReadSets()) then return false end
    C_Container.PickupContainerItem(item.bag, item.slot)
    local kind, itemID = GetCursorInfo()
    if not (S.Public(kind) and S.Public(itemID) and kind == "item" and itemID == item.itemID) then
        ClearCursor()
        return false
    end
    DeleteCursorItem()
    S.Print(string.format(S.Text("Deleted %s (%s)."), Label(item), S.MoneyText(item.value)))
    return true
end

local function Asks(item)
    return item.quality > POOR or M.config.confirm == true
end

local function Forget()
    if not asked then return end
    asked = false
    S.HideQuestion(QUESTION)
end

-- item: a snapshot. Deletes now, or once the player confirms.
function M:Request(item)
    if not self:Usable() then return end
    if not Asks(item) then
        self:Delete(item)
        return
    end
    asked = true
    S.Confirm(QUESTION, {
        text = S.Text("Delete %s (%s)? This cannot be undone."), text_arg1 = Label(item),
        text_arg2 = S.MoneyText(item.value), showAlert = true,
        acceptText = S.BlizzardText("DELETE", "Delete"), cancelText = S.BlizzardText("CANCEL", "Cancel"),
        callback = function()
            asked = false
            M:Delete(item)
        end,
        cancelCallback = function() asked = false end,
    })
end

------------------------------------------------------------------ the mark
-- A warm frame on the offered stack's slot while the pointer rests on a
-- button: Suite textures on Blizzard's item button, which take no mouse and
-- follow it wherever the bag places it. Found through Blizzard's own lookup
-- (ContainerFrameUtil_GetItemButtonAndContainer, live and forever).
local function Decoration(button)
    local mark = M.marks[button]
    if mark then return mark end
    mark = { S.CreateTexture(button, nil, "OVERLAY", nil, 6) }
    mark[1]:SetAllPoints(button)
    mark[1]:SetColorTexture(MARK[1], MARK[2], MARK[3], .18)
    for i, edge in ipairs(EDGES) do
        local line = S.CreateTexture(button, nil, "OVERLAY", nil, 7)
        line:SetColorTexture(MARK[1], MARK[2], MARK[3], 1)
        line:SetPoint(edge[1])
        line:SetPoint(edge[2])
        if edge[3] then line:SetHeight(2) else line:SetWidth(2) end
        mark[i + 1] = line
    end
    M.marks[button] = mark
    return mark
end

local shownMark
-- record: a candidate, or nil to clear the mark.
function M:Mark(record)
    local button = record and ContainerFrameUtil_GetItemButtonAndContainer(record.bag, record.slot)
    if button and not button:IsVisible() then button = nil end
    if shownMark == button then return end
    local old = shownMark and self.marks[shownMark]
    if old then
        for i = 1, #old do old[i]:Hide() end
    end
    shownMark = button
    if not button then return end
    local mark = Decoration(button)
    for i = 1, #mark do mark[i]:Show() end
end

------------------------------------------------------------------ the buttons
local function Hint(text)
    GameTooltip:AddLine(text, HINT[1], HINT[2], HINT[3], true)
end

local function QualityName()
    local name = QUALITY_NAMES[M.config.quality] or QUALITY_NAMES[CHOICE.POOR]
    return S.BlizzardText(name[1], name[2])
end

local function Paint(button)
    GameTooltip:SetOwner(button, "ANCHOR_LEFT")
    GameTooltip:SetText(S.Text("Delete cheapest item"))
    local combat = NS.InCombat()
    local item = not combat and M:Candidates(1)[1]
    if combat then
        Hint(S.Text("Not available in combat."))
    elseif item then
        GameTooltip:AddDoubleLine(Label(item), S.MoneyText(item.value), 1, 1, 1, 1, 1, 1)
        Hint(Asks(item) and S.Text("Click to delete this stack after you confirm.") or S.Text("Click to delete this stack."))
    else
        Hint(S.Text("No item to delete."))
        Hint(string.format(S.Text("Offered: stacks up to %s quality that a vendor buys."), QualityName()))
        Hint(S.Text("Never offered: quest items, refundable items, items in equipment sets and items you keep."))
    end
    if not combat then Hint(S.Text("Right-click to choose another stack or to keep an item.")) end
    GameTooltip:Show()
    M:Mark(item or nil)
end

-- After a delete the bag repaints on its own events (Suite Bags one frame
-- later): paint after it.
local function Repaint()
    if hovered and hovered:IsVisible() then Paint(hovered) end
end

local function Changed()
    if hovered then repaint:Request() end
end

local function Enter(button)
    hovered = not NS.InCombat() and button or nil
    if hovered then M.context:Event("BAG_UPDATE_DELAYED", Changed) end
    Paint(button)
end

local function Leave(button)
    if hovered == button then hovered = nil end
    M.context:RemoveEvent("BAG_UPDATE_DELAYED")
    M:Mark(nil)
    if GameTooltip:IsOwned(button) then GameTooltip:Hide() end
end

-- The bag closed or the button went away: nothing waits for it.
local function Hidden(button)
    Leave(button)
    Forget()
end

local function Sync(button, icon, combat)
    button:SetEnabled(not combat)
    icon:SetDesaturated(combat)
    icon:SetAlpha(combat and .4 or 1)
end

-- The combat edges: disabled from PLAYER_REGEN_DISABLED, the moment before
-- the lockdown, until PLAYER_REGEN_ENABLED.
local function Combat(_, event)
    local combat = NS.InCombat(event)
    for button, icon in pairs(M.tools) do Sync(button, icon, combat) end
    if not combat then return SyncNative() end
    if hovered then Leave(hovered) end
    Forget()
end

local function Clicked(button, mouseButton)
    if not M:Usable() then return end
    if mouseButton == "RightButton" then
        Leave(button)
        S.ContextMenu(button, M.BuildMenu)
        return
    end
    local item = M:Candidates(1)[1]
    if item then M:Request(Snapshot(item)) end
end

-- Gives a button the tool's icon and handlers, once.
function M:Bind(button)
    if self.tools[button] then return button end
    local icon = S.CreateTexture(button, nil, "ARTWORK")
    icon:SetPoint("TOPLEFT", 3, -3)
    icon:SetPoint("BOTTOMRIGHT", -3, 3)
    icon:SetAtlas("common-icon-delete")
    self.tools[button] = icon
    button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    button:SetScript("OnClick", Clicked)
    button:HookScript("OnEnter", Enter)
    button:HookScript("OnLeave", Leave)
    button:HookScript("OnHide", Hidden)
    Sync(button, icon, NS.InCombat())
    return button
end

------------------------------------------------------------------ Blizzard's bag window
-- Suite Bags shows the tool beside Filters in its own views.
local function BagsHosting()
    local bags = S.instances.bags
    return bags ~= nil and bags.active == true and S.Config("bags").inventoryView ~= NS.BagsView.BLIZZARD_GRID
end

local function NativeTool(frame)
    local tool = M.natives[frame]
    if tool then return tool end
    -- Made without a parent and parented after (as Suite Bags' frames are):
    -- WoW Forever's SmartNavigation would rescan the open bag in this call.
    tool = S.CreateFrame("Button")
    tool:SetParent(frame)
    tool:SetSize(20, 20)
    local light = S.CreateTexture(tool, nil, "HIGHLIGHT")
    light:SetAllPoints(tool)
    light:SetColorTexture(1, 1, 1, .16)
    M.natives[frame] = tool
    return M:Bind(tool)
end

-- On the window's title, left of its close button or of the Suite caption.
local function Place(tool, frame)
    local close = frame.CloseButton
    local inset = S.BagsTitleInset and S.BagsTitleInset(frame)
    if not inset then
        local width = close and close:IsShown() and close:GetWidth()
        inset = S.Finite(width) and width or 4
    end
    tool:ClearAllPoints()
    tool:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -inset - 2, -2)
    tool:SetFrameLevel(math.max(close and close:GetFrameLevel() or 0, frame:GetFrameLevel()) + 2)
end

-- After Blizzard laid its bag windows out (UpdateContainerFrameAnchors, run
-- when one opens or closes). In combat nothing changes until its end.
SyncNative = function()
    if NS.InCombat() then return end
    local frame = M.active and not BagsHosting() and BagWindow() or nil
    for host, tool in pairs(M.natives) do
        if host ~= frame then tool:Hide() end
    end
    if not frame then return end
    local tool = NativeTool(frame)
    Place(tool, frame)
    tool:Show()
end

------------------------------------------------------------------ the list
local function ItemName(itemID)
    return S.PublicText((C_Item.GetItemInfo(itemID))) or string.format(S.Text("Item %d"), itemID)
end

local function AddKept(root)
    local ids = Sorted(M.keep)
    if #ids == 0 then return end
    root:CreateDivider()
    local kept = root:CreateButton(string.format(S.Text("Never deleted (%d)"), #ids))
    kept:SetScrollMode(KEEP_SCROLL)
    for i = 1, #ids do
        local id = ids[i]
        kept:CreateButton(ItemName(id), function() M:Keep(id, false) end)
    end
    kept:CreateButton(S.Text("Allow deleting all of them"), function()
        if M.active and not NS.InCombat() then S.Set(M.id, "keep", "") end
    end)
end

-- The right-click list: the ten cheapest stacks, each to delete or keep,
-- and the kept item types, each to offer again.
function M.BuildMenu(_, root)
    root:CreateTitle(S.Text("Cheapest items"))
    local list = M:Candidates(LIST)
    if #list == 0 then root:CreateTitle(S.Text("No item to delete.")) end
    for i = 1, #list do
        local item = Snapshot(list[i])
        local entry = root:CreateButton(string.format(S.Text("%s - %s"), Label(item), S.MoneyText(item.value)))
        entry:SetTooltip(function(tooltip) tooltip:SetBagItem(item.bag, item.slot) end)
        entry:CreateButton(S.BlizzardText("DELETE", "Delete"), function() M:Request(item) end)
        entry:CreateButton(S.Text("Never delete this item"), function() M:Keep(item.itemID, true) end)
    end
    AddKept(root)
end

------------------------------------------------------------------ module
function M:Enable()
    if not hooked then
        hooksecurefunc("UpdateContainerFrameAnchors", SyncNative)
        hooked = true
    end
    self.context:Event("PLAYER_REGEN_DISABLED", Combat)
    self.context:Event("PLAYER_REGEN_ENABLED", Combat)
    self:Refresh()
end

function M:Refresh()
    if not self.active then return end
    self.keep = S.QoLParseIDs(self.config.keep, KEEP_LIMIT)
    self.highest = QUALITY[self.config.quality] or POOR
    repaint = self.context:Coalesce(.1, Repaint)
    SyncNative()
    -- Suite Bags lays its search row out again, with or without the tool.
    if S.BagsToolsChanged then S.BagsToolsChanged() end
end

function M:Disable()
    for _, tool in pairs(self.natives) do tool:Hide() end
    if hovered then Leave(hovered) end
    Forget()
    self.keep = {}
    if S.BagsToolsChanged then S.BagsToolsChanged() end
end

S.Install("cheapestItem", M)

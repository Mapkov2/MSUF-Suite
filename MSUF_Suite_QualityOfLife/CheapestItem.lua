local _, P = ...
local NS, S = P.NS, P.Suite
-- Delete cheapest item shows vendor-priced stacks from the bag button or
-- when loot cannot fit. Only a click on a delete action can destroy a stack.
--   * Where: in the Suite Bags views beside Filters (Bags makes that button
--     in its own look and hands it to M:Bind, MSUF_Suite_Bags/
--     InventoryControls.lua); otherwise on the title of Blizzard's backpack
--     or combined bag window, left of its close button or of the Suite Bags
--     caption (S.BagsTitleInset, MSUF_Suite_Bags/BagCaption.lua).
--   * Bag updates are watched only while a button is hovered or the list
--     window is shown. The inventory-full error is watched outside combat.
--     Only the cheapest stacks are checked for quest items, sets, refunds and
--     Never sell items.
--   * Offered: priced stacks of the chosen quality or lower (Poor by
--     default, never above Uncommon), unlocked and not kept by the player.
--   * A delete reads the slot again, picks up exactly the offered stack and
--     deletes it in the same click: DeleteCursorItem is a restricted call
--     (GameCursorDocumentation.lua HasRestrictions, live and forever). A
--     stack above Poor always asks first; Poor asks while the setting is on.
--     The three-stack action always asks once, with the exact stacks listed.
local M = { tools = setmetatable({}, { __mode = "k" }), natives = setmetatable({}, { __mode = "k" }),
    marks = setmetatable({}, { __mode = "k" }), ranked = {}, keep = {} }
S.CheapestItem = M
local POOR = Enum.ItemQuality.Poor
-- Class 7 subclass 12 identifies enchanting materials (dust, essences and shards).
local ENCHANTING_MATERIALS = 12
local CHOICE = NS.CheapestItemQuality
local QUALITY = { [CHOICE.POOR] = POOR, [CHOICE.COMMON] = Enum.ItemQuality.Common,
    [CHOICE.UNCOMMON] = Enum.ItemQuality.Uncommon }
-- Blizzard's localized quality names (GlobalStrings), with the Suite text.
local QUALITY_NAMES = { [CHOICE.POOR] = { "ITEM_QUALITY0_DESC", "Poor" },
    [CHOICE.COMMON] = { "ITEM_QUALITY1_DESC", "Common" }, [CHOICE.UNCOMMON] = { "ITEM_QUALITY2_DESC", "Uncommon" } }
local BACKPACK, LAST_BAG = Enum.BagIndex.Backpack, Constants.InventoryConstants.NumBagSlots
local KEY, LIST, KEEP_LIMIT, KEEP_SCROLL = 1000, 10, 200, 400
local BATCH_SIZE = 3
local WINDOW_NAME, WIDTH, ROW_HEIGHT = "MSUFSuiteCheapestItems", 500, 30
local QUESTION = "suite-delete-cheapest-item"
local FALLBACK_ICON = 134400
local DELETE_ATLAS = "common-icon-delete"
local PASS_TEXTURE = "Interface\\Buttons\\UI-GroupLoot-Pass-Up"
local MARK = { 1, .32, .2 }
local EDGES = { { "TOPLEFT", "TOPRIGHT", true }, { "BOTTOMLEFT", "BOTTOMRIGHT", true },
    { "TOPLEFT", "BOTTOMLEFT" }, { "TOPRIGHT", "BOTTOMRIGHT" } }
local HINT = { .72, .78, .85 }
local pool, eligible, setSlots = {}, {}, {}
local hovered, asked, hooked, repaint, SyncNative
local window, RefreshWindow, WatchLootErrors
local lootOffered = false

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

function M:Usable()
    return self.active == true and not NS.InCombat() and BagWindow() ~= nil
end

local function CanUse(fromWindow)
    if not fromWindow then return M:Usable() end
    return M.active == true and not NS.InCombat() and window and window:IsVisible()
        and window.profile == NS.DB and (window.fromLoot or BagWindow() ~= nil)
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
    if NS.Client.isForever and M.config.keepEnchanting ~= false then
        local _, _, _, _, _, class, subclass = C_Item.GetItemInfoInstant(record.itemID)
        if not S.Finite(class) or (class == Enum.ItemClass.Tradegoods
            and (not S.Finite(subclass) or subclass == ENCHANTING_MATERIALS)) then return false end
    end
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
function M:Candidates(limit, fromWindow)
    local ranked = self.ranked
    for i = #ranked, 1, -1 do ranked[i] = nil end
    if not CanUse(fromWindow) then return ranked end
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

local function CanDelete(item, fromWindow)
    if not CanUse(fromWindow) or M.keep[item.itemID] or item.quality > M.highest then return false end
    local cursor, targeting = GetCursorInfo(), SpellIsTargeting()
    return S.Public(cursor) and cursor == nil and S.Public(targeting) and targeting == false
        and Unchanged(item) and Allowed(item, ReadSets())
end

-- Runs synchronously in the list entry or the confirmation's click.
function M:Delete(item, fromWindow)
    if not CanDelete(item, fromWindow) then return false end
    C_Container.PickupContainerItem(item.bag, item.slot)
    local kind, itemID = GetCursorInfo()
    if not (S.Public(kind) and S.Public(itemID) and kind == "item" and itemID == item.itemID) then
        ClearCursor()
        return false
    end
    DeleteCursorItem()
    local remaining, remainingID = GetCursorInfo()
    if not S.Public(remaining) then return false end
    if remaining ~= nil then
        if remaining == "item" and S.Public(remainingID) and remainingID == item.itemID then ClearCursor() end
        return false
    end
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

local function Ask(data, accept)
    Forget()
    asked = data
    data.showAlert = true
    data.acceptText, data.cancelText = S.BlizzardText("DELETE", "Delete"), S.BlizzardText("CANCEL", "Cancel")
    data.callback = function()
        if asked ~= data then return end
        asked = false
        accept()
    end
    data.cancelCallback = function()
        if asked == data then asked = false end
    end
    S.Confirm(QUESTION, data)
end

-- item: a snapshot. Deletes now, or once the player confirms.
local function DeleteOne(item, fromWindow)
    local deleted = M:Delete(item, fromWindow)
    if fromWindow and window:IsShown() then
        if deleted and window.fromLoot then window.heading:SetText(S.Text("Cheapest stacks by vendor value")) end
        repaint:Request()
    end
end

function M:Request(item, fromWindow)
    if not CanUse(fromWindow) then return end
    if not Asks(item) then
        Forget()
        return DeleteOne(item, fromWindow)
    end
    Ask({
        text = S.Text("Delete %s (%s)? This cannot be undone."), text_arg1 = Label(item),
        text_arg2 = S.MoneyText(item.value),
    }, function() DeleteOne(item, fromWindow) end)
end

local function CanDeleteBatch(items)
    for i = 1, BATCH_SIZE do
        if not CanDelete(items[i], true) then return false end
    end
    return true
end

local function RequestBatch(items)
    if #items < BATCH_SIZE or not CanDeleteBatch(items) then return end
    local lines = {}
    for i = 1, BATCH_SIZE do
        local item = items[i]
        lines[i] = string.format(S.Text("%s - %s"), Label(item), S.MoneyText(item.value))
    end
    Ask({ text = S.Text("Destroy these three stacks? This cannot be undone.%s"),
        text_arg1 = "\n\n" .. table.concat(lines, "\n") }, function()
        if CanDeleteBatch(items) then
            for i = 1, BATCH_SIZE do
                if not M:Delete(items[i], true) then break end
            end
        end
        repaint:Request()
    end)
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
    else
        Hint(S.Text("No item to delete."))
        Hint(string.format(S.Text("Offered: stacks up to %s quality that a vendor buys."), QualityName()))
        Hint(S.Text("Never offered: quest items, refundable items, items in equipment sets and items you keep."))
    end
    if not combat then
        Hint(S.Text("Left-click to open the deletion window."))
        Hint(S.Text("Right-click to choose a stack or protect an item from deletion."))
    end
    GameTooltip:Show()
    M:Mark(item or nil)
end

-- After a delete the bag repaints on its own events (Suite Bags one frame
-- later): paint after it.
local function Repaint()
    if hovered and hovered:IsVisible() then Paint(hovered) end
    if window and window:IsShown() then RefreshWindow() end
end

local function Changed()
    repaint:Request()
end

local function WatchBagChanges()
    if hovered or window and window:IsVisible() then
        M.context:Event("BAG_UPDATE_DELAYED", Changed)
    else
        M.context:RemoveEvent("BAG_UPDATE_DELAYED")
        repaint:Cancel()
    end
end

local function Enter(button)
    hovered = not NS.InCombat() and button or nil
    WatchBagChanges()
    Paint(button)
end

local function Leave(button)
    if hovered == button then hovered = nil end
    WatchBagChanges()
    M:Mark(nil)
    if GameTooltip:IsOwned(button) then GameTooltip:Hide() end
end

local function Hidden(button)
    Leave(button)
    if window and window.fromLoot then return end
    if window then window:Hide() end
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
    WatchLootErrors(not combat)
    if not combat then return SyncNative() end
    if hovered then Leave(hovered) end
    if window then window:Hide() end
    Forget()
end

local function Clicked(button, mouseButton)
    if not M:Usable() then return end
    Leave(button)
    if mouseButton == "RightButton" then
        S.ContextMenu(button, M.BuildMenu)
    else
        M:OpenCandidates()
    end
end

-- Gives a button the tool's icon and handlers, once.
function M:Bind(button)
    if self.tools[button] then return button end
    local icon = S.CreateTexture(button, nil, "OVERLAY")
    icon:SetPoint("TOPLEFT", 3, -3)
    icon:SetPoint("BOTTOMRIGHT", -3, 3)
    -- The house finder uses the delete atlas on Retail. Both clients ship the group loot texture.
    if not NS.Client.isForever and C_Texture.GetAtlasInfo(DELETE_ATLAS) then
        icon:SetAtlas(DELETE_ATLAS)
    else
        icon:SetTexture(PASS_TEXTURE)
    end
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
    if window and window:IsShown() and not window.fromLoot and not CanUse(true) then window:Hide() end
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

function M.BuildMenu(_, root)
    root:CreateTitle(S.Text("Cheapest items to destroy"))
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

------------------------------------------------------------------ deletion window
local function WindowButton(parent, text, width, action)
    local bridge = NS.HostBridge
    local button = bridge and bridge.MenuButton(parent, width, 24)
        or S.CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    button:SetSize(width, 24)
    button:SetText(text)
    button:SetScript("OnClick", action)
    return button
end

local function SameOffer(a, b)
    return a.bag == b.bag and a.slot == b.slot and a.link == b.link and a.itemID == b.itemID
        and a.count == b.count and a.quality == b.quality and a.value == b.value
end

-- A bag update can change the row between mouse-down and the click.
local function RowPressed(button, mouse)
    if mouse == "LeftButton" then button.pressedItem = button:GetParent().item end
end

local function RowDelete(button)
    local item, pressed = button:GetParent().item, button.pressedItem
    button.pressedItem = nil
    if item and (not pressed or SameOffer(item, pressed)) then
        M:Request(item, true)
    end
end

local function RowLeave(row)
    if GameTooltip:IsOwned(row) then GameTooltip:Hide() end
end

local function RowEnter(row)
    local item = row.item
    if not item or not CanUse(true) then return end
    GameTooltip:SetOwner(row, "ANCHOR_LEFT")
    GameTooltip:SetHyperlink(item.link)
    Hint(S.Text("Right-click to protect this item from deletion."))
    GameTooltip:Show()
end

local function RowKeep(row)
    local item = row.item
    if not item or not CanUse(true) then return end
    S.ContextMenu(row, function(_, root)
        root:CreateButton(S.Text("Never delete this item"), function()
            if CanUse(true) then M:Keep(item.itemID, true) end
        end)
    end)
end

local function CreateRow(parent, index)
    local row = S.CreateFrame("Button", nil, parent)
    row:SetSize(WIDTH - 28, ROW_HEIGHT)
    row:SetPoint("TOPLEFT", 14, -66 - (index - 1) * ROW_HEIGHT)
    row:RegisterForClicks("RightButtonUp")
    row:SetScript("OnClick", RowKeep)
    row:SetScript("OnEnter", RowEnter)
    row:SetScript("OnLeave", RowLeave)
    row.icon = S.CreateTexture(row, nil, "ARTWORK")
    row.icon:SetSize(22, 22)
    row.icon:SetPoint("LEFT", 2, 0)
    row.label = S.QoLLabel(row, "")
    row.label:SetPoint("LEFT", row.icon, "RIGHT", 8, 0)
    row.label:SetWidth(259)
    row.label:SetWordWrap(false)
    row.label:SetJustifyH("LEFT")
    row.value = S.QoLLabel(row, "")
    row.value:SetPoint("RIGHT", -98, 0)
    row.delete = WindowButton(row, S.BlizzardText("DELETE", "Delete"), 86, RowDelete)
    row.delete:SetPoint("RIGHT")
    row.delete:RegisterForClicks("LeftButtonUp")
    row.delete:HookScript("OnMouseDown", RowPressed)
    return row
end

local function WindowHidden()
    window.profile, window.fromLoot = nil, nil
    if window:IsShown() then window:Hide() end
    for _, row in ipairs(window.rows) do
        row.item, row.delete.pressedItem = nil, nil
        RowLeave(row)
    end
    Forget()
    WatchBagChanges()
end

local function WindowBatch()
    if not CanUse(true) then return end
    local batch = {}
    for i = 1, BATCH_SIZE do batch[i] = window.rows[i].item end
    RequestBatch(batch)
end

local function CreateWindow()
    local bridge = NS.HostBridge
    if bridge then bridge.EnsureMenuTheme() end
    window = S.QoLWindow(WIDTH, 150, "Delete cheapest item", 15, true, WINDOW_NAME)
    window:Hide()
    window:SetScript("OnHide", WindowHidden)
    UISpecialFrames[#UISpecialFrames + 1] = WINDOW_NAME
    window.heading = S.QoLLabel(window, "")
    window.heading:SetPoint("TOPLEFT", 16, -44)
    window.empty = S.QoLLabel(window, "No item to delete.")
    window.empty:SetPoint("TOP", 0, -82)
    window.batch = WindowButton(window, S.Text("Destroy the three cheapest stacks"), 280, WindowBatch)
    window.batch:SetPoint("BOTTOMLEFT", 14, 10)
    window.rows = {}
    for i = 1, LIST do window.rows[i] = CreateRow(window, i) end
end

RefreshWindow = function()
    if not CanUse(true) then
        window:Hide()
        return
    end
    local list = M:Candidates(LIST, true)
    for i, row in ipairs(window.rows) do
        local item = list[i]
        if row.item and (not item or row.item.link ~= item.link) then RowLeave(row) end
        row.item = item and Snapshot(item) or nil
        if item then
            local icon = C_Item.GetItemIconByID(item.itemID)
            row.icon:SetTexture(S.Finite(icon) and icon or FALLBACK_ICON)
            row.label:SetText(Label(item))
            row.value:SetText(S.MoneyText(item.value))
        end
        row:SetShown(item ~= nil)
    end
    window.empty:SetShown(#list == 0)
    window.batch:SetShown(not window.fromLoot)
    window.batch:SetEnabled(#list >= BATCH_SIZE)
    window:SetHeight(76 + math.max(1, #list) * ROW_HEIGHT + (window.fromLoot and 0 or 32))
end

local function ShowWindow(fromLoot)
    if not window then CreateWindow() end
    Forget()
    window.profile, window.fromLoot = NS.DB, fromLoot
    window.heading:SetText(fromLoot and S.Text("Your bags are full. Choose a stack to delete.")
        or S.Text("Cheapest stacks by vendor value"))
    window:Show()
    RefreshWindow()
    WatchBagChanges()
end

function M:OpenCandidates()
    if not self:Usable() then return false end
    ShowWindow(false)
    return true
end

------------------------------------------------------------------ loot
-- Forever's LootFrame matches the same localized error. A pending loot slot
-- also covers Quick Loot, which can report the error during LOOT_READY.
local function LootClosed()
    M.context:RemoveEvent("LOOT_CLOSED")
    lootOffered = false
    if window and window.fromLoot then window:Hide() end
end

local function LootFull(_, _, _, message)
    if lootOffered or NS.InCombat() or not S.Public(message) or message ~= ERR_INV_FULL then return end
    local count = GetNumLootItems()
    if not S.Finite(count) or count < 1 then return end
    lootOffered = true
    M.context:Event("LOOT_CLOSED", LootClosed)
    if not window or not window:IsShown() then ShowWindow(true) end
end

WatchLootErrors = function(enabled)
    if enabled then
        M.context:Event("UI_ERROR_MESSAGE", LootFull)
    else
        M.context:RemoveEvent("UI_ERROR_MESSAGE")
        LootClosed()
    end
end

------------------------------------------------------------------ module
function M:Enable()
    if not hooked then
        hooksecurefunc("UpdateContainerFrameAnchors", SyncNative)
        hooked = true
    end
    self.context:Event("PLAYER_REGEN_DISABLED", Combat)
    self.context:Event("PLAYER_REGEN_ENABLED", Combat)
    WatchLootErrors(not NS.InCombat())
    self:Refresh()
end

function M:Refresh()
    if not self.active then return end
    self.keep = S.QoLParseIDs(self.config.keep, KEEP_LIMIT)
    self.highest = QUALITY[self.config.quality] or POOR
    repaint = self.context:Coalesce(.1, Repaint)
    SyncNative()
    if window and window:IsShown() then RefreshWindow() end
    -- Suite Bags lays its search row out again, with or without the tool.
    if S.BagsToolsChanged then S.BagsToolsChanged() end
end

function M:Disable()
    WatchLootErrors(false)
    if window then window:Hide() end
    for _, tool in pairs(self.natives) do tool:Hide() end
    if hovered then Leave(hovered) end
    Forget()
    self.keep = {}
    if S.BagsToolsChanged then S.BagsToolsChanged() end
end

S.Install("cheapestItem", M)

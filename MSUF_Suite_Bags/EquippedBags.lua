local _, P = ...
local NS, S = P.NS, P.Suite
local Equipped = { buttons = {} }
P.EquippedBags = Equipped
local BAG_SLOTS = Constants.InventoryConstants.NumBagSlots
local TOTAL = BAG_SLOTS + Constants.InventoryConstants.NumReagentBagSlots
local EMPTY = "Interface\\PaperDoll\\UI-PaperDoll-Slot-Bag"

local function CanChange()
    return P.BagsModule.active and not NS.InCombat()
end

local function Enter(button)
    GameTooltip:SetOwner(button, "ANCHOR_TOP")
    if not GameTooltip:SetInventoryItem("player", button.inventoryID) then
        GameTooltip:SetText(S.Text(button.bagID > BAG_SLOTS and "Reagent bag" or "Empty bag slot"))
    end
    GameTooltip:AddLine(S.Text("Drop a bag here to equip it. Drag an equipped bag to replace it."), .72, .78, .85, true)
    GameTooltip:Show()
end

local function Drag(button)
    if CanChange() then PickupBagFromSlot(button.inventoryID) end
end

local function Receive(button)
    if CanChange() then PutItemInBag(button.inventoryID) end
end

local function Click(button)
    if not CanChange() then return end
    local kind = GetCursorInfo()
    if not S.Public(kind) then return end
    if kind == "item" then
        PutItemInBag(button.inventoryID)
    elseif kind == nil and IsModifiedClick("PICKUPITEM") then
        PickupBagFromSlot(button.inventoryID)
    end
end

local function CreateButton(parent, bag)
    -- BaseBagSlotButtonTemplate registers with Blizzard's manager at OnLoad.
    -- ItemButton is an intrinsic type and needs no inherited template node.
    local button = P.ChildFrame("ItemButton", parent)
    button:SetSize(34, 34)
    button.icon:SetAllPoints(button)
    button.bagID = bag
    button.inventoryID = C_Container.ContainerIDToInventoryID(bag)
    button:SetPoint("LEFT", 12 + (bag - 1) * 42, 0)
    button:RegisterForDrag("LeftButton")
    button:RegisterForClicks("LeftButtonUp")
    button:SetScript("OnClick", Click)
    button:SetScript("OnDragStart", Drag)
    button:SetScript("OnReceiveDrag", Receive)
    button:SetScript("OnEnter", Enter)
    button:SetScript("OnLeave", GameTooltip_Hide)
    return button
end

function Equipped.Create(parent)
    if Equipped.frame then return Equipped.frame end
    local frame = P.ChildFrame("Frame", parent)
    frame:SetPoint("TOPLEFT", 12, -118)
    frame:SetPoint("TOPRIGHT", -12, -118)
    frame:SetHeight(46)
    frame:Hide()
    for bag = 1, TOTAL do Equipped.buttons[bag] = CreateButton(frame, bag) end
    local hint = P.GridView.Font(frame, 11)
    hint:SetPoint("LEFT", Equipped.buttons[TOTAL], "RIGHT", 14, 0)
    hint:SetPoint("RIGHT", -8, 0)
    hint:SetText(S.Text("Drop a bag here to equip it. Drag an equipped bag to replace it."))
    Equipped.hint = hint
    Equipped.frame = frame
    return frame
end

-- Runs only while the drawer is visible, on a bag change or its first open.
function Equipped.Refresh()
    if not Equipped.frame or not Equipped.frame:IsShown() then return end
    for i = 1, #Equipped.buttons do
        local button = Equipped.buttons[i]
        local texture = GetInventoryItemTexture("player", button.inventoryID)
        if not S.Public(texture) then texture = nil end
        SetItemButtonTexture(button, texture or EMPTY)
        local free, total = C_Container.GetContainerNumFreeSlots(i), C_Container.GetContainerNumSlots(i)
        if S.Finite(free) and S.Finite(total) then
            button.Count:SetText(total > 0 and tostring(free) or "")
            button.Count:SetShown(total > 0)
        end
    end
end

function Equipped.Toggle()
    if NS.InCombat() or not Equipped.frame then return end
    Equipped.frame:SetShown(not Equipped.frame:IsShown())
    Equipped.Refresh()
    P.BagsModule:RefreshWindowLayout()
    P.InventoryView.Request()
end

function Equipped.Layout(panel)
    for i = 1, #Equipped.buttons do
        local button = Equipped.buttons[i]
        button:ClearAllPoints()
        button:SetPoint("LEFT", (panel and 4 or 12) + (i - 1) * (panel and 36 or 42), 0)
        button:SetSize(panel and 32 or 34, panel and 32 or 34)
    end
    Equipped.hint:SetShown(not panel)
end

function Equipped.Close()
    if Equipped.frame then Equipped.frame:Hide() end
end

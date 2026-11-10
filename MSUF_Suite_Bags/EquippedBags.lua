local _, P = ...
local NS, S = P.NS, P.Suite
local Equipped = { buttons = {} }
P.EquippedBags = Equipped
local BAG_SLOTS = Constants.InventoryConstants.NumBagSlots
local TOTAL = BAG_SLOTS + Constants.InventoryConstants.NumReagentBagSlots
local EMPTY = "Interface\\PaperDoll\\UI-PaperDoll-Slot-Bag"
local keyringClick

-- Leave the native bag's protection and the keyring's item actions with
-- Blizzard. A separate secure button covers the icon only while hovered.
local function DetachKeyring()
    if not keyringClick or not keyringClick.owner then return end
    if GameTooltip:IsOwned(keyringClick) then GameTooltip_Hide() end
    if NS.IsCombatLocked() then return end
    keyringClick.owner = nil
    keyringClick:Hide()
    keyringClick:ClearAllPoints()
end

local function KeyringTooltip(button)
    GameTooltip:SetOwner(button, "ANCHOR_TOP")
    GameTooltip:SetText(KEYRING)
    GameTooltip:Show()
end

local function KeyringLeave(button)
    if keyringClick and keyringClick.owner == button and keyringClick:IsMouseOver() then return end
    DetachKeyring()
end

local function KeyringClick()
    if keyringClick then return keyringClick end
    local button = S.CreateFrame("Button", nil, UIParent, "SecureActionButtonTemplate")
    button:RegisterForClicks("LeftButtonUp")
    button:SetAttribute("useOnKeyDown", false)
    button:SetAttribute("type", "click")
    button:SetScript("OnEnter", KeyringTooltip)
    button:SetScript("OnLeave", DetachKeyring)
    button:SetScript("OnEvent", DetachKeyring)
    button:RegisterEvent("PLAYER_REGEN_DISABLED")
    button:RegisterEvent("PLAYER_REGEN_ENABLED")
    button:Hide()
    RegisterStateDriver(button, "visibility", "[combat] hide")
    keyringClick = button
    return button
end

local function NativeKeyring()
    -- The Gamepad UI provides the keyring in the combined bag itself.
    if S.GamepadUI() then return end
    local button = _G.KeyRingButton
    if not button or NS.Safety.IsForbidden(button) or not C_ActionBar.ShouldShowKeyring() then return end
    if not GetCVarBool("showKeyring") then return end
    local enabled = button:IsEnabled()
    if S.Public(enabled) and enabled == true then return button end
end

local function KeyringEnter(button)
    if not P.BagsModule.active or S.editMode or NS.InCombat() then return end
    local target = NativeKeyring()
    if not target then return end
    local click = KeyringClick()
    click.owner = button
    click:SetAttribute("clickbutton", target)
    click:SetFrameStrata(button:GetFrameStrata())
    click:SetFrameLevel(button:GetFrameLevel() + 5)
    click:SetAllPoints(button)
    click:Show()
    KeyringTooltip(click)
end

local function CreateKeyring(parent)
    local button = P.GridView.Button(parent, "", 34, nil, 34)
    P.BagAppearance.Tool(button, KEYRING, nil, "UI-HUD-ActionBar-Keyring-Small", true)
    button.bagTool = nil
    button:HookScript("OnEnter", KeyringEnter)
    button:HookScript("OnLeave", KeyringLeave)
    button:HookScript("OnHide", DetachKeyring)
    button:Hide()
    return button
end

local function CanChange()
    return P.BagsModule.active and not NS.InCombat()
end

local function Enter(button)
    GameTooltip:SetOwner(button, "ANCHOR_TOP")
    if not GameTooltip:SetInventoryItem("player", button.inventoryID) then
        GameTooltip:SetText(S.Text(button.bagID > BAG_SLOTS and "Reagent bag" or "Empty bag slot"))
    end
    P.BagHover.Tooltip(button)
    GameTooltip:AddLine(S.Text("Drop a bag here to equip it. Drag an equipped bag to replace it."), .72, .78, .85, true)
    GameTooltip:Show()
    P.BagHover.Enter(button)
end

local function Leave(button)
    P.BagHover.Leave(button)
    if GameTooltip:IsOwned(button) then GameTooltip_Hide() end
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
    button:SetScript("OnLeave", Leave)
    button:SetScript("OnHide", P.BagHover.Leave)
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
    if NS.Client.isForever and C_ActionBar.ShouldShowKeyring then
        Equipped.keyring = CreateKeyring(frame)
    end
    Equipped.frame = frame
    return frame
end

-- Runs only while the drawer is visible, on a bag change or its first open.
function Equipped.Refresh()
    if not Equipped.frame or not Equipped.frame:IsShown() then return end
    if Equipped.keyring then
        local shown = NativeKeyring() ~= nil
        if Equipped.keyring:IsShown() ~= shown then
            Equipped.keyring:SetShown(shown)
            Equipped.hint:SetPoint("LEFT", shown and Equipped.keyring or Equipped.buttons[TOTAL], "RIGHT", 14, 0)
        end
    end
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
        if P.BagHover.IsOwner(button) and GameTooltip:IsOwned(button) and GameTooltip:IsShown() then Enter(button) end
    end
end

function Equipped.Toggle()
    if NS.InCombat() or not Equipped.frame then return end
    if Equipped.frame:IsShown() then
        Equipped.Close()
    else
        Equipped.frame:Show()
        Equipped.Refresh()
    end
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
    if Equipped.keyring then
        Equipped.keyring:ClearAllPoints()
        Equipped.keyring:SetPoint("LEFT", Equipped.buttons[TOTAL], "RIGHT", panel and 4 or 8, 0)
        Equipped.keyring:SetSize(panel and 32 or 34, panel and 32 or 34)
    end
    Equipped.hint:SetShown(not panel)
end

function Equipped.Close()
    P.BagHover.Clear()
    DetachKeyring()
    if Equipped.frame then Equipped.frame:Hide() end
end

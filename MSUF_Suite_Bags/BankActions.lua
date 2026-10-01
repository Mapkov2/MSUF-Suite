local _, P = ...
local NS, S = P.NS, P.Suite
if NS.Client.isForever then return end
-- Item clicks of the Suite bank view (BankInventory.lua). Blizzard's
-- BankPanelItemButtonMixin decides refund confirmations from BankFrame's
-- active bank type; switching that type from Suite code (BankFrame:SetTab)
-- would taint BankPanel, whose state bank tab purchases read. The Suite
-- makes the same container calls itself and never drives BankFrame:
--  * a refundable item entering the warband bank asks first (END_REFUND);
--  * a warband item is picked up only while Blizzard's Warband Bank tab is
--    selected, so Blizzard's own bag clicks still confirm refundable swaps;
--    a click on one switches that tab first through a secure overlay;
--  * stacks split in the Suite panel (StackSplitter.lua).
local A = {}
P.BankActions = A
local ACCOUNT = Enum.BankType.Account

local function Usable(button)
    local record = button.record
    if not record or NS.IsCombatLocked() or not BankFrame:IsShown() or not C_Bank.CanUseBank(record.bankType) then
        return nil
    end
    return record
end

local function ConfirmButton(frame, text, x, callback)
    local button = S.CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    button:SetSize(100, 22)
    button:SetPoint("BOTTOM", x, 12)
    button:SetText(text)
    button:SetScript("OnClick", callback)
    return button
end

local confirm
local function Accept()
    local record, guid = confirm.record, confirm.guid
    confirm:Hide()
    local location = C_Cursor.GetCursorItem()
    -- The cursor still holds the item the player was asked about.
    if not record or not location or C_Item.GetItemGUID(location) ~= guid or not BankFrame:IsShown()
        or NS.IsCombatLocked() or not C_Bank.CanUseBank(ACCOUNT) then
        return
    end
    C_Container.PickupContainerItem(record.bag, record.slot)
end

local function Cancel()
    confirm:Hide()
    ClearCursor()
end

local function Confirm(record, location)
    if not confirm then
        confirm = S.CreateFrame("Frame", nil, UIParent)
        confirm:SetFrameStrata("DIALOG")
        confirm:SetSize(320, 96)
        confirm:SetPoint("CENTER", 0, 120)
        confirm:EnableMouse(true)
        local background = S.CreateTexture(confirm, nil, "BACKGROUND")
        background:SetAllPoints(confirm)
        background:SetColorTexture(0.06, 0.07, 0.08, 0.96)
        confirm.text = P.GridView.Font(confirm, 12)
        confirm.text:SetPoint("TOP", 0, -14)
        confirm.text:SetWidth(290)
        confirm.text:SetJustifyH("CENTER")
        ConfirmButton(confirm, OKAY, -54, Accept)
        ConfirmButton(confirm, CANCEL, 54, Cancel)
    end
    confirm.text:SetText(END_REFUND)
    confirm.record, confirm.guid = record, C_Item.GetItemGUID(location)
    confirm:Show()
end
-- The bank closed: the refund question and the warband tab overlay go.
A.Cancel = function()
    if confirm and confirm:IsShown() then Cancel() end
    A.TabDetach()
end

local function Place(record)
    local location = C_Cursor.GetCursorItem()
    if record.bankType == ACCOUNT and location and C_Item.CanBeRefunded(location) == true then
        Confirm(record, location)
        return
    end
    C_Container.PickupContainerItem(record.bag, record.slot)
end

local function PickUp(record)
    if record.itemID and record.bankType == ACCOUNT and BankFrame:GetActiveBankType() ~= ACCOUNT then
        UIErrorsFrame:AddExternalErrorMessage(S.Text("Select Blizzard's Warband Bank tab to move warband items."))
        return
    end
    C_Container.PickupContainerItem(record.bag, record.slot)
end

------------------------------------------------------------------ warband tab
-- A click on a warband item while Blizzard's Bank tab is selected switches
-- to the Warband Bank tab first, as the player's own tab click would: one
-- secure overlay in UIParent covers the hovered item out of combat and its
-- SecureActionButtonTemplate "click" clicks Blizzard's Warband Bank tab
-- button, so Blizzard switches the tab from its own secure code; PostClick
-- then runs the item click. The Suite never calls BankFrame:SetTab. Leaving
-- the item, the bank closing and PLAYER_REGEN_DISABLED (before the lockdown)
-- release the overlay; a "[combat] hide" state driver backs that up.
local tab
local function TabDetach()
    if not tab or NS.IsCombatLocked() then return end
    tab.owner = nil
    tab:Hide()
    tab:ClearAllPoints()
end
A.TabDetach = TabDetach

local function Forward(owner, script)
    local handler = owner and owner:GetScript(script)
    if handler then handler(owner) end
end

local function TabOverlay()
    if tab then return tab end
    tab = S.CreateFrame("Button", nil, UIParent, "SecureActionButtonTemplate")
    tab:RegisterForClicks("AnyUp")
    tab:RegisterForDrag("LeftButton")
    -- SecureActionButton_OnClick acts on the press while ActionButtonUseKeyDown
    -- is on; the overlay registers the release, which must be the click.
    tab:SetAttribute("useOnKeyDown", false)
    -- Unmodified left clicks only: modified and right clicks need no tab.
    tab:SetAttribute("type1", "click")
    tab:SetScript("OnEnter", function(self) Forward(self.owner, "OnEnter") end)
    tab:SetScript("OnLeave", function(self)
        local owner = self.owner
        TabDetach()
        Forward(owner, "OnLeave")
    end)
    tab:SetScript("PostClick", function(self, mouseButton)
        local owner = self.owner
        TabDetach()
        if owner then A.Click(owner, mouseButton) end
    end)
    tab:SetScript("OnDragStart", function(self) if self.owner then A.Drag(self.owner) end end)
    tab:SetScript("OnReceiveDrag", function(self) if self.owner then A.Receive(self.owner) end end)
    tab:SetScript("OnEvent", TabDetach)
    tab:RegisterEvent("PLAYER_REGEN_DISABLED")
    tab:Hide()
    RegisterStateDriver(tab, "visibility", "[combat] hide")
    A.tabOverlay = tab
    return tab
end

-- A Suite bank item gained the pointer.
function A.Enter(button)
    local record = button.record
    if NS.IsCombatLocked() or not record or not record.itemID or record.bankType ~= ACCOUNT
        or not BankFrame:IsShown() or BankFrame:GetActiveBankType() == ACCOUNT or not C_Bank.CanUseBank(ACCOUNT) then
        return
    end
    local target = BankFrame.accountBankTabID and BankFrame:GetTabButton(BankFrame.accountBankTabID)
    if not target then return end
    local overlay = TabOverlay()
    if overlay.owner == button and overlay:IsShown() then return end
    overlay.owner = button
    overlay:SetAttribute("clickbutton1", target)
    overlay:SetFrameStrata(button:GetFrameStrata())
    overlay:SetFrameLevel(button:GetFrameLevel() + 5)
    overlay:ClearAllPoints()
    overlay:SetAllPoints(button)
    overlay:Show()
end

-- A pooled item button left the page.
function A.Hidden(button)
    if tab and tab.owner == button then TabDetach() end
end

local function ModifiedClick(button, record)
    if HandleModifiedItemClick(C_Container.GetContainerItemLink(record.bag, record.slot),
        ItemLocation:CreateFromBagAndSlot(record.bag, record.slot)) then
        return
    end
    if not CursorHasItem() and IsModifiedClick("SPLITSTACK") and not record.locked and (record.count or 0) > 1 then
        P.StackSplitter.OpenFor(button, record.count)
    end
end

function A.Click(button, mouseButton)
    local record = Usable(button)
    if not record then return end
    if IsModifiedClick() then
        ModifiedClick(button, record)
    elseif mouseButton ~= "LeftButton" then
        -- Like Blizzard's right click: the item moves into the bags.
        C_Container.UseContainerItem(record.bag, record.slot)
    elseif CursorHasItem() then
        Place(record)
    else
        PickUp(record)
    end
end

function A.Drag(button)
    local record = Usable(button)
    if not record then return end
    if CursorHasItem() then Place(record) else PickUp(record) end
end

function A.Receive(button)
    local record = Usable(button)
    if record and CursorHasItem() then Place(record) end
end

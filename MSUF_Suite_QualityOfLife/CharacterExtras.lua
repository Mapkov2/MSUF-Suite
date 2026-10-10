local _, P = ...
local NS, S = P.NS, P.Suite

-- Additions to the character sheet. A summary beside PaperDollFrame (so it
-- leaves with the Character tab) lists gear with gem sockets, the total
-- durability and the PvP item level and has Great Vault and expansion page
-- buttons; the total durability can also sit on the character model; gear
-- slot icons can be cropped on the character and Inspect sheets; equipment
-- choices show item levels and the slot arrows can be hidden. The summary
-- listens to gear and item data only while the sheet is open and repaints at
-- most once per frame.
local M = { rows = {}, flyoutLabels = setmetatable({}, { __mode = "k" }) }
local FIRST_SLOT, LAST_SLOT = 1, 19 -- INVSLOT_FIRST_EQUIPPED .. INVSLOT_LAST_EQUIPPED
local MAX_ROWS, ROW_HEIGHT, BUTTON_HEIGHT = 12, 18, 22
local GEAR_EVENTS = { "PLAYER_EQUIPMENT_CHANGED", "UPDATE_INVENTORY_DURABILITY",
    "GET_ITEM_INFO_RECEIVED", "SOCKET_INFO_UPDATE" }
-- Gear slot buttons of PaperDollFrame.xml and InspectPaperDollFrame.xml.
local SLOTS = { "Head", "Neck", "Shoulder", "Back", "Chest", "Shirt", "Tabard", "Wrist", "Hands", "Waist",
    "Legs", "Feet", "Finger0", "Finger1", "Trinket0", "Trinket1", "MainHand", "SecondaryHand" }

local function Text(parent)
    local text = S.CreateFontString(parent, nil, "OVERLAY")
    S.SetFont(text, nil, M.config.summaryFontSize, "OUTLINE")
    text:SetJustifyH("LEFT")
    return text
end

local function RowClick(row)
    if M.active and row.slot and not NS.IsCombatLocked() then SocketInventoryItem(row.slot) end
end

local function RowEnter(row)
    if not row.slot then return end
    GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
    GameTooltip:SetInventoryItem("player", row.slot)
    GameTooltip:Show()
end

------------------------------------------------------------------ shortcuts
-- Blizzard_WeeklyRewards' bootstrap (loaded at login) opens the vault; the
-- minimap's expansion button knows which landing page is current. Its Lua
-- runs through Dispatch, so an error there stays Blizzard's.
local function OpenVault()
    if M.active and not NS.IsCombatLocked() then S.Dispatch(NS.Finish, WeeklyRewards_ShowUI) end
end

-- Blizzard_Minimap creates the button; it is shown once an expansion page
-- is available to the character.
local function LandingButton()
    local native = _G.ExpansionLandingPageMinimapButton
    if native and native:IsShown() then return native end
end

local function OpenExpansion()
    local native = LandingButton()
    if M.active and native and not NS.IsCombatLocked() then S.Dispatch(NS.Finish, native.ToggleLandingPage, native) end
end

local function Shortcut(panel, label, click)
    local button = S.CreateFrame("Button", nil, panel)
    button:SetSize(194, BUTTON_HEIGHT - 2)
    local background = S.CreateTexture(button, nil, "BACKGROUND")
    background:SetAllPoints()
    background:SetColorTexture(.1, .14, .19, 1)
    local highlight = S.CreateTexture(button, nil, "HIGHLIGHT")
    highlight:SetAllPoints()
    highlight:SetColorTexture(1, 1, 1, .08)
    button.label = Text(button)
    button.label:SetPoint("CENTER")
    button.label:SetText(S.Text(label))
    button:SetScript("OnClick", click)
    return button
end

-- The summary sits in the character window, a panel of Blizzard's frame
-- controls manager on WoW Forever's Gamepad UI. Its SmartNavigation
-- post-hooks CreateFrame and rescans the panel of the new frame's parent in
-- the caller's execution (Blizzard_GamepadSmartNavigation/SmartNavigation.lua
-- SetupFrameHooks, UpdateParent): the summary and its rows are built without
-- a parent and the summary joins PaperDollFrame last.
local function Build(self)
    if self.panel then return self.panel end
    local panel = S.CreateFrame("Frame")
    panel:SetSize(210, 80)
    panel:SetPoint("TOPLEFT", CharacterFrame, "TOPRIGHT", 5, -30)
    local background = S.CreateTexture(panel, nil, "BACKGROUND")
    background:SetAllPoints()
    background:SetColorTexture(.04, .07, .1, .95)
    panel.title = Text(panel)
    panel.title:SetPoint("TOPLEFT", panel, "TOPLEFT", 8, -8)
    panel.title:SetText(S.Text("Gear summary"))
    panel.durability, panel.pvp, panel.sockets = Text(panel), Text(panel), Text(panel)
    for index = 1, MAX_ROWS do
        local row = S.CreateFrame("Button", nil, panel)
        row:SetSize(194, ROW_HEIGHT)
        row.text = Text(row)
        row.text:SetPoint("LEFT", row, "LEFT", 0, 0)
        row:SetScript("OnClick", RowClick)
        row:SetScript("OnEnter", RowEnter)
        row:SetScript("OnLeave", function(button)
            if GameTooltip:IsOwned(button) then GameTooltip:Hide() end
        end)
        self.rows[index] = row
    end
    panel.vault = Shortcut(panel, "Great Vault", OpenVault)
    panel.expansion = Shortcut(panel, "Expansion page", OpenExpansion)
    panel:SetParent(PaperDollFrame)
    self.panel = panel
    return panel
end

local function Restyle(self)
    local path, size = S.GlobalFontPath(), self.config.summaryFontSize
    if self.fontPath == path and self.fontSize == size then return end
    self.fontPath, self.fontSize = path, size
    local panel = self.panel
    for _, text in ipairs({ panel.title, panel.durability, panel.pvp, panel.sockets,
        panel.vault.label, panel.expansion.label }) do
        S.SetFont(text, path, size, "OUTLINE")
    end
    for _, row in ipairs(self.rows) do S.SetFont(row.text, path, size, "OUTLINE") end
    for _, label in pairs(self.flyoutLabels) do S.SetFont(label, path, size, "OUTLINE") end
    if self.modelText then S.SetFont(self.modelText, path, size, "OUTLINE") end
end

------------------------------------------------------------------ summary
-- Sockets of one equipped item: total from its stats, filled from its gems.
local function Sockets(link)
    local stats = C_Item.GetItemStats(link)
    local total = 0
    if S.Public(stats) and type(stats) == "table" then
        for key, value in pairs(stats) do
            if S.PublicText(key) and key:find("^EMPTY_SOCKET_") and S.Finite(value) then total = total + value end
        end
    end
    local filled = 0
    for index = 1, math.min(4, total) do
        if S.PublicText(C_Item.GetItemGem(link, index)) then filled = filled + 1 end
    end
    return filled, total
end

-- Equipped gear with gem sockets, in slot order: open ones in amber, filled
-- ones in green. Returns the row count.
local function FillSocketRows(self)
    local count = 0
    for slot = FIRST_SLOT, LAST_SLOT do
        local link = S.PublicText(GetInventoryItemLink("player", slot))
        if link and count < MAX_ROWS then
            local filled, total = Sockets(link)
            if total > 0 then
                count = count + 1
                local row = self.rows[count]
                row.slot = slot
                row.text:SetText(string.format(S.Text("%s: %d of %d sockets filled"),
                    S.PublicText(C_Item.GetItemInfo(link)) or tostring(slot), filled, total))
                local open = filled < total
                row.text:SetTextColor(open and 1 or .62, open and .78 or .86, open and .35 or .62)
            end
        end
    end
    return count
end

local function DurabilityPercent()
    local current, maximum = 0, 0
    for slot = FIRST_SLOT, LAST_SLOT do
        local value, max = GetInventoryItemDurability(slot)
        if S.Finite(value) and S.Finite(max) and max > 0 then
            current, maximum = current + value, maximum + max
        end
    end
    if maximum > 0 then return math.floor(current * 100 / maximum + .5) end
end

-- Lines stack from the title down; empty lines take no room.
local function Stack(panel, region, shown, y, height)
    region:ClearAllPoints()
    region:SetShown(shown)
    if not shown then return y end
    region:SetPoint("TOPLEFT", panel, "TOPLEFT", 8, y)
    return y - (height or ROW_HEIGHT)
end

-- The total durability on the character model, at the saved offsets.
local function ModelDurability(self, durability)
    local c = self.config
    local shown = self.active and c.modelDurability and durability ~= nil
    if not shown then
        if self.modelText then self.modelText:Hide() end
        return
    end
    local text = self.modelText
    if not text then
        text = S.CreateFontString(CharacterModelScene, nil, "OVERLAY")
        S.SetFont(text, nil, c.summaryFontSize, "OUTLINE")
        self.modelText = text
    end
    text:ClearAllPoints()
    text:SetPoint("CENTER", CharacterModelScene, "CENTER", c.modelDurabilityX, c.modelDurabilityY)
    text:SetText(string.format(S.Text("Durability %d%%"), durability))
    text:Show()
end

local function PaintSummary(self, panel, durability)
    local c = self.config
    panel.durability:SetText(durability and c.summaryDurability and string.format(S.Text("Durability %d%%"), durability) or "")
    local _, _, pvp = GetAverageItemLevel()
    local showPvP = c.summaryPvP and S.Finite(pvp)
    panel.pvp:SetText(showPvP and string.format(S.Text("PvP item level %d"), math.floor(pvp)) or "")
    local rows = c.summarySockets and FillSocketRows(self) or 0
    panel.sockets:SetText(S.Text(rows > 0 and "Gem sockets" or "No gear with gem sockets"))
    local y = Stack(panel, panel.durability, c.summaryDurability and durability ~= nil, -8 - ROW_HEIGHT)
    y = Stack(panel, panel.pvp, showPvP, y)
    y = Stack(panel, panel.sockets, c.summarySockets, y)
    for index, row in ipairs(self.rows) do
        if index > rows then row.slot = nil end
        y = Stack(panel, row, index <= rows, y)
    end
    y = Stack(panel, panel.vault, c.shortcutVault, y - 4, BUTTON_HEIGHT)
    y = Stack(panel, panel.expansion, c.shortcutExpansion and LandingButton() ~= nil, y, BUTTON_HEIGHT)
    panel:SetHeight(-y + 8)
    panel:Show()
end

-- A direct repaint consumes a repaint still due (self.repaint).
function M:Update()
    self.repaint:Clear()
    local open = self.active and PaperDollFrame:IsVisible()
    local durability = open and DurabilityPercent()
    ModelDurability(self, durability or nil)
    if not open or not self.config.summaryPanel then
        if self.panel then self.panel:Hide() end
        return
    end
    local panel = Build(self)
    Restyle(self)
    PaintSummary(self, panel, durability or nil)
end

-- Item data and gear events arrive in bursts: each requests the one repaint
-- of the next frame.
local function SheetShown()
    if not M.active then return end
    for _, event in ipairs(GEAR_EVENTS) do M.context:Event(event, M.repaint) end
    M:Update()
end

local function SheetHidden()
    for _, event in ipairs(GEAR_EVENTS) do M.context:RemoveEvent(event) end
    M.repaint:Clear()
end

------------------------------------------------------------------ gear slots
-- Crops the slot icons of one sheet ("Character" or "Inspect"). Blizzard sets
-- slot icons with SetTexture, which keeps texture coordinates; the context
-- hands the original coordinates back.
local function CropIcons(self, sheet)
    local crop = self.active and self.config.slotIconCrop / 100 or 0
    local far = 1 - crop
    for _, name in ipairs(SLOTS) do
        local slot = _G[sheet .. name .. "Slot"]
        local icon = slot and slot.icon
        if icon and crop > 0 then
            self.context:Tuple(icon, "GetTexCoord", "SetTexCoord", crop, crop, crop, far, far, crop, far, far)
        elseif icon then
            self.context:RestoreTuple(icon, "SetTexCoord")
        end
    end
end

-- The arrows beside the gear slots fade out and stop taking the mouse; the
-- equipment choice modifier (Alt by default) still opens a slot's choices.
local function SlotArrows(self)
    local hidden = self.active and self.config.slotArrowsHidden
    for _, name in ipairs(SLOTS) do
        local slot = _G["Character" .. name .. "Slot"]
        if slot and slot.popoutButton then self.context:HideControl(slot.popoutButton, hidden) end
    end
end

-- Blizzard_InspectUI loads on demand; its sheet is cropped when it opens.
local function InspectShown()
    if M.active then CropIcons(M, "Inspect") end
end

local function HookInspect(self)
    if self.inspectHooked or not _G.InspectFrame then return end
    InspectFrame:HookScript("OnShow", InspectShown)
    self.inspectHooked = true
    self.context:RemoveEvent("ADDON_LOADED")
end

local function AddonLoaded(self, _, addon)
    if addon == "Blizzard_InspectUI" then HookInspect(self) end
end

------------------------------------------------------------------ flyouts
-- EquipmentFlyout_UpdateItems sets button.location on every update: an
-- ItemLocation where the flyout uses item locations (item upgrade, item
-- interaction, runeforge), else a packed location (the character sheet).
-- GetItemLocation() is not used: the pooled button keeps the location an
-- earlier item-location flyout gave it.
local function FlyoutLevel(button)
    local packed = button.location
    if type(packed) == "table" then
        local level = C_Item.DoesItemExist(packed) and C_Item.GetCurrentItemLevel(packed)
        return S.Finite(level) and level or nil
    end
    if not S.Finite(packed) or packed < 0 or packed >= EQUIPMENTFLYOUT_FIRST_SPECIAL_LOCATION then return end
    local data = EquipmentManager_GetLocationData(packed)
    local link = data.isBags and C_Container.GetContainerItemLink(data.bag, data.slot)
        or GetInventoryItemLink("player", data.slot)
    link = S.PublicText(link)
    return link and C_Item.GetDetailedItemLevelInfo(link)
end

-- EquipmentFlyout.lua calls EquipmentFlyout_UpdateItems by name.
local function Flyout()
    local on = M.active and M.config.choiceItemLevels
    for _, button in ipairs(EquipmentFlyoutFrame.buttons) do
        local level = on and button:IsShown() and FlyoutLevel(button)
        local label = M.flyoutLabels[button]
        if S.Finite(level) and level > 0 then
            if not label then
                label = S.CreateFontString(button, nil, "OVERLAY")
                S.SetFont(label, nil, M.config.summaryFontSize, "OUTLINE")
                label:SetPoint("TOPLEFT", button, "TOPLEFT", 2, -2)
                M.flyoutLabels[button] = label
            end
            label:SetText(math.floor(level))
            label:Show()
        elseif label then
            label:Hide()
        end
    end
end

------------------------------------------------------------------ lifecycle
-- Blizzard_UIPanels_Game builds the character sheet before any addon loads.
-- Script hooks cannot be removed; they do nothing while the module is off.
local function Install(self)
    if self.hooked then return end
    PaperDollFrame:HookScript("OnShow", SheetShown)
    PaperDollFrame:HookScript("OnHide", SheetHidden)
    hooksecurefunc("EquipmentFlyout_UpdateItems", Flyout)
    self.hooked = true
end

local function Slots(self)
    CropIcons(self, "Character")
    if _G.InspectFrame then CropIcons(self, "Inspect") end
    SlotArrows(self)
    if self.active and self.config.slotIconCrop > 0 and not self.inspectHooked then
        if _G.InspectFrame then HookInspect(self) else self.context:Event("ADDON_LOADED", AddonLoaded) end
    end
end

function M:Enable()
    self.repaint = self.context:Coalesce(0, M.Update)
    Install(self)
    Slots(self)
    if PaperDollFrame:IsVisible() then SheetShown() end
end

function M:Refresh()
    Slots(self)
    self:Update()
    if EquipmentFlyoutFrame:IsShown() then Flyout() end
end

function M:Disable()
    SheetHidden()
    Slots(self)
    self.context:RemoveEvent("ADDON_LOADED")
    if self.panel then self.panel:Hide() end
    if self.modelText then self.modelText:Hide() end
    for _, label in pairs(self.flyoutLabels) do label:Hide() end
end

S.Install("characterExtras", M)

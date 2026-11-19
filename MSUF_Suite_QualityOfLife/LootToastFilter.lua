local _, P = ...
local NS, S = P.NS, P.Suite

-- Supplemental alerts from the client's personal loot messages on Forever
-- and Blizzard's personal item-loot-toast event on Retail.
local ID = "lootToastFilter"
local M = { toasts = {}, ids = {}, waiting = {}, waitingCount = 0 }
local MAX_TOASTS = 3
-- The toasts stack down from the top right corner of one host, which MSUF
-- Edit Mode moves and scales.
local TOAST_WIDTH, TOAST_HEIGHT, TOAST_STEP = 258, 48, 53
local SAMPLE_ICON = "Interface\\Icons\\INV_Misc_QuestionMark"
local POPUP_SECONDS = 5
local BATTLE_PET_CLASS = 17 -- upstream/live Enum.ItemClass.Battlepet
-- kindFilter (MSUF_Suite/Core/Catalog/QualityOfLife.lua).
local ALL_ITEMS, MOUNTS_ONLY, PETS_ONLY, MOUNTS_AND_PETS = 1, 2, 3, 4

-- At most this many item IDs of the chosen list count (itemIDs).
local MAX_IDS = 100

-- OnLeave hides the shared tooltip only while this frame still owns it.
local function LeaveTooltip(frame)
    if GameTooltip:IsOwned(frame) then GameTooltip:Hide() end
end

local function MakeToast(host, index)
    local frame = CreateFrame("Frame", nil, host)
    frame:SetSize(TOAST_WIDTH, TOAST_HEIGHT)
    frame:SetPoint("TOPRIGHT", host, "TOPRIGHT", 0, -(index - 1) * TOAST_STEP)
    frame:EnableMouse(true)
    local bg = frame:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0.055, 0.065, 0.08, 0.94)
    local accent = frame:CreateTexture(nil, "ARTWORK")
    accent:SetSize(3, 48)
    accent:SetPoint("LEFT", 0, 0)
    accent:SetColorTexture(0.9, 0.71, 0.24, 1)
    local icon = frame:CreateTexture(nil, "ARTWORK")
    icon:SetSize(36, 36)
    icon:SetPoint("LEFT", 8, 0)
    frame.icon, frame.bg, frame.accent = icon, bg, accent
    local name = frame:CreateFontString(nil, "OVERLAY")
    name:SetFontObject(GameFontHighlightSmall)
    name:SetPoint("LEFT", icon, "RIGHT", 8, 0)
    name:SetWidth(182)
    name:SetJustifyH("LEFT")
    name:SetWordWrap(false)
    frame.name = name
    local count = frame:CreateFontString(nil, "OVERLAY")
    count:SetFontObject(GameFontNormalSmall)
    count:SetPoint("BOTTOMRIGHT", -7, 5)
    frame.count = count
    frame:SetScript("OnEnter", function(self)
        if not self.link or NS.Safety.IsForbidden(_G.GameTooltip) then return end
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:SetHyperlink(self.link)
        GameTooltip:Show()
    end)
    frame:SetScript("OnLeave", LeaveTooltip)
    frame:Hide()
    return frame
end

local ItemArrived

-- An item the client has no data for yet: its toast waits for
-- GET_ITEM_INFO_RECEIVED of that item and is filtered and shown then, once.
local function Wait(self, itemLink, quantity)
    local itemID = C_Item.GetItemInfoInstant(itemLink)
    if not S.Finite(itemID) then return end
    local bucket = self.waiting[itemID]
    if bucket then
        for _, pending in ipairs(bucket) do
            if pending.link == itemLink then
                pending.quantity = pending.quantity + quantity
                return
            end
        end
    end
    if self.waitingCount >= MAX_TOASTS then return end
    if not bucket then
        bucket = {}
        self.waiting[itemID] = bucket
    end
    bucket[#bucket + 1] = { link = itemLink, quantity = quantity }
    self.waitingCount = self.waitingCount + 1
    if self.waitingCount == 1 then self.context:Event("GET_ITEM_INFO_RECEIVED", ItemArrived) end
end

local function StopWaiting(self)
    for itemID in pairs(self.waiting) do self.waiting[itemID] = nil end
    self.waitingCount = 0
    self.context:RemoveEvent("GET_ITEM_INFO_RECEIVED")
end

local function PaintToast(frame, style)
    S.QoLColor(frame.bg, style.background, .94)
    S.QoLColor(frame.accent, style.accent)
    frame.name:SetTextColor(S.RGB(style.text))
    frame.count:SetTextColor(S.RGB(style.muted))
end

-- The toast of a slot, made on first use. Each slot hides on its own
-- deadline, restarted when it is reused; one callback per slot, made with it.
local function Slot(self, index)
    local frame = self.toasts[index]
    if not frame then
        frame = MakeToast(self.host, index)
        frame.expire = function()
            frame:Hide()
            frame.link, frame.quantity = nil, nil
        end
        self.toasts[index] = frame
    end
    return frame
end

local function SetQuantity(frame, quantity)
    frame.quantity = quantity
    frame.count:SetText(quantity > 1 and "x" .. quantity or "")
end

local function MergeToast(self, itemLink, quantity)
    for _, frame in ipairs(self.toasts) do
        if frame.link == itemLink and frame.quantity then
            SetQuantity(frame, frame.quantity + quantity)
            self.context:After(POPUP_SECONDS, frame.expire)
            return true
        end
    end
    return false
end

local function ShowToast(self, itemLink, quantity, arrived)
    if MergeToast(self, itemLink, quantity) then return end
    local name, _, quality, _, _, _, _, _, _, icon = C_Item.GetItemInfo(itemLink)
    if not arrived and S.Public(name) and name == nil then return Wait(self, itemLink, quantity) end
    local minQuality = self.config.minQuality
    if not S.Finite(minQuality) then minQuality = 4 end
    if not S.PublicText(name) or not S.Finite(quality)
        or quality < minQuality or not S.Finite(icon) then return end
    local itemID, _, _, _, _, classID = C_Item.GetItemInfoInstant(itemLink)
    if not S.Finite(itemID) or (next(self.ids) and not self.ids[itemID]) then return end
    local filter = self.config.kindFilter or ALL_ITEMS
    if filter ~= ALL_ITEMS then
        local mount, pet = false, false
        if filter ~= PETS_ONLY then
            local mountID = C_MountJournal.GetMountFromItem(itemID)
            mount = S.Finite(mountID) and mountID > 0
        end
        if filter ~= MOUNTS_ONLY then
            pet = S.Finite(classID) and classID == BATTLE_PET_CLASS
            if not pet then
                local species = C_PetJournal.GetPetInfoByItemID(itemID)
                pet = S.Public(species) and species ~= nil and species ~= false
            end
        end
        if (filter == MOUNTS_ONLY and not mount) or (filter == PETS_ONLY and not pet)
            or (filter == MOUNTS_AND_PETS and not (mount or pet)) then return end
    end
    self.nextIndex = (self.nextIndex or 0) % MAX_TOASTS + 1
    local frame = Slot(self, self.nextIndex)
    PaintToast(frame, S.QoLStyle(self.config))
    frame.link = itemLink
    frame.icon:SetTexture(icon)
    frame.name:SetText(name)
    SetQuantity(frame, quantity)
    frame:Show()
    self.context:After(POPUP_SECONDS, frame.expire)
end

ItemArrived = function(self, _, itemID, success)
    local bucket = S.Finite(itemID) and self.waiting[itemID]
    if not bucket then return end
    self.waiting[itemID] = nil
    self.waitingCount = self.waitingCount - #bucket
    if self.waitingCount == 0 then self.context:RemoveEvent("GET_ITEM_INFO_RECEIVED") end
    if not S.Public(success) or success ~= true then return end
    for _, pending in ipairs(bucket) do
        ShowToast(self, pending.link, pending.quantity, true)
    end
end

local function HideAll(self)
    for _, frame in ipairs(self.toasts) do
        self.context:Cancel(frame.expire)
        frame.link, frame.quantity = nil, nil
        frame:Hide()
    end
end

-- MSUF Edit Mode shows every slot with a sample, to place and scale the stack.
local function ShowSamples(self)
    local style = S.QoLStyle(self.config)
    for index = 1, MAX_TOASTS do
        local frame = Slot(self, index)
        PaintToast(frame, style)
        frame.icon:SetTexture(SAMPLE_ICON)
        frame.name:SetText(S.Text("Filtered loot notice"))
        frame.count:SetText("")
        frame:Show()
    end
end

local function LootToast(self, _, kind, itemLink, quantity, _, _, personal)
    if not self.active or not S.Public(kind) or kind ~= "item"
        or not S.Public(personal) or personal ~= true
        or not S.PublicText(itemLink) or not S.Finite(quantity)
        or quantity < 1 then return end
    ShowToast(self, itemLink, quantity)
end

local function Escape(text)
    return (text:gsub("([%%%^%$%(%)%.%[%]%*%+%-%?])", "%%%1"))
end

-- The localized stack message may put its quantity before the hyperlink.
local function LootPattern(format)
    if not S.PublicText(format) then return end
    local parts = { "^" }
    local cursor, fields, linkIndex = 1, 0, nil
    while true do
        local first, last, kind = format:find("%%%d*%$?([sd])", cursor)
        if not first then break end
        fields = fields + 1
        parts[#parts + 1] = Escape(format:sub(cursor, first - 1))
        parts[#parts + 1] = kind == "s" and "(.+)" or "(%d+)"
        if kind == "s" then linkIndex = fields end
        cursor = last + 1
    end
    parts[#parts + 1] = Escape(format:sub(cursor)) .. "$"
    if linkIndex and fields <= 2 then return table.concat(parts), linkIndex end
end

local function ChatLoot(self, _, message)
    if not self.active or not S.PublicText(message) or not message:find("|Hitem:", 1, true) then return end
    local link, count
    if self.lootMultiple then
        local first, second = message:match(self.lootMultiple)
        if self.lootLinkIndex == 1 then link, count = first, tonumber(second)
        else
            link, count = second, tonumber(first)
        end
    end
    if not link and self.lootSingle then link, count = message:match(self.lootSingle), 1 end
    if link and count and count > 0 then ShowToast(self, link, count) end
end

function M:Enable()
    self.host = self.host or CreateFrame("Frame", nil, UIParent)
    self.host:SetSize(TOAST_WIDTH, (MAX_TOASTS - 1) * TOAST_STEP + TOAST_HEIGHT)
    S.PlaceHost(self.host, self.config)
    self.ids = S.QoLParseIDs(self.config.itemIDs, MAX_IDS)
    if NS.Client.isForever then
        self.lootSingle = LootPattern(LOOT_ITEM_SELF)
        self.lootMultiple, self.lootLinkIndex = LootPattern(LOOT_ITEM_SELF_MULTIPLE)
        self.context:Event("CHAT_MSG_LOOT", ChatLoot)
    else
        self.context:Event("SHOW_LOOT_TOAST", LootToast)
    end
    if S.editMode then ShowSamples(self) end
end

function M:Refresh()
    self.ids = S.QoLParseIDs(self.config.itemIDs, MAX_IDS)
    S.PlaceHost(self.host, self.config)
    local style = S.QoLStyle(self.config)
    for _, frame in ipairs(self.toasts) do PaintToast(frame, style) end
    HideAll(self)
    StopWaiting(self)
    if S.editMode then ShowSamples(self) end
end

function M:HideEditPreview()
    HideAll(self)
end

function M:Disable()
    self.context:RemoveEvent(NS.Client.isForever and "CHAT_MSG_LOOT" or "SHOW_LOOT_TOAST")
    HideAll(self)
    StopWaiting(self)
    self.ids = {}
end

function M:RegisterMovers()
    S.RegisterOwnedMover(ID, "notices", {
        label = "Filtered loot notice", order = 652,
        getFrame = function() return self.host end,
        xKey = "x", yKey = "y", pointKey = "point",
        point = function() return NS.AnchorPoints[self.config.point] or "TOPRIGHT" end,
        quickPosition = true, historyKeys = { "scale" },
        sizeKeys = { "scale" },
    })
end

S.Install(ID, M)

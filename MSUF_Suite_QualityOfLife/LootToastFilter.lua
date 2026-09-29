local _, P = ...
local NS, S = P.NS, P.Suite

-- Supplemental alerts for Blizzard's personal item-loot-toast event. Ordinary
-- bag gains have no equivalent public payload, so they are not inferred here.
local M = { toasts = {}, ids = {} }
local MAX_TOASTS = 3
local POPUP_SECONDS = 5
local BATTLE_PET_CLASS = 17 -- upstream/live Enum.ItemClass.Battlepet

local function ParseIDs(value)
    local ids = {}
    if type(value) ~= "string" then return ids end
    local count = 0
    for token in value:gmatch("[^,%s;]+") do
        local id = tonumber(token)
        if S.Finite(id) and id > 0 and id == math.floor(id) and id < 10000000
            and not ids[id] then
            ids[id] = true
            count = count + 1
            if count >= 100 then break end
        end
    end
    return ids
end

local function MakeToast(index)
    local frame = CreateFrame("Frame", nil, UIParent)
    frame:SetSize(258, 48)
    frame:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", -24, -162 - (index - 1) * 53)
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
    frame:SetScript("OnLeave", function() GameTooltip:Hide() end)
    frame:Hide()
    return frame
end

local function ShowToast(self, itemLink, quantity)
    local name, _, quality, _, _, _, _, _, _, icon = C_Item.GetItemInfo(itemLink)
    local minQuality = self.config.minQuality
    if not S.Finite(minQuality) then minQuality = 4 end
    if not S.PublicText(name) or not S.Finite(quality)
        or quality < minQuality or not S.Finite(icon) then return end
    local itemID, _, _, _, _, classID = C_Item.GetItemInfoInstant(itemLink)
    if not S.Finite(itemID) or (next(self.ids) and not self.ids[itemID]) then return end
    local filter = self.config.kindFilter or 1
    if filter ~= 1 then
        local mount, pet = false, false
        if filter ~= 3 and C_MountJournal and type(C_MountJournal.GetMountFromItem) == "function" then
            local mountID = C_MountJournal.GetMountFromItem(itemID)
            mount = S.Finite(mountID) and mountID > 0
        end
        if filter ~= 2 then
            pet = S.Finite(classID) and classID == BATTLE_PET_CLASS
            if not pet and C_PetJournal and type(C_PetJournal.GetPetInfoByItemID) == "function" then
                local species = C_PetJournal.GetPetInfoByItemID(itemID)
                pet = S.Public(species) and species ~= nil and species ~= false
            end
        end
        if (filter == 2 and not mount) or (filter == 3 and not pet)
            or (filter == 4 and not (mount or pet)) then return end
    end
    self.nextIndex = (self.nextIndex or 0) % MAX_TOASTS + 1
    local frame = self.toasts[self.nextIndex]
    if not frame then
        frame = MakeToast(self.nextIndex)
        self.toasts[self.nextIndex] = frame
    end
    local style = S.QoLStyle(self.config)
    S.QoLColor(frame.bg, style.background, .94)
    S.QoLColor(frame.accent, style.accent)
    frame.name:SetTextColor(S.RGB(style.text))
    frame.count:SetTextColor(S.RGB(style.muted))
    frame.token = (frame.token or 0) + 1
    frame.link = itemLink
    frame.icon:SetTexture(icon)
    frame.name:SetText(name)
    frame.count:SetText(quantity > 1 and "x" .. quantity or "")
    frame:Show()
    local token, generation = frame.token, self.generation
    C_Timer.After(POPUP_SECONDS, function()
        if self.active and self.generation == generation and frame.token == token then
            frame:Hide()
            frame.link = nil
        end
    end)
end

local function HideAll(self)
    for _, frame in ipairs(self.toasts) do
        frame.token = (frame.token or 0) + 1
        frame.link = nil
        frame:Hide()
    end
end

local function LootToast(self, _, kind, itemLink, quantity, _, _, personal)
    if not self.active or NS.IsCombatLocked()
        or not S.Public(kind) or kind ~= "item"
        or not S.Public(personal) or personal ~= true
        or not S.PublicText(itemLink) or not S.Finite(quantity)
        or quantity < 1 then return end
    ShowToast(self, itemLink, quantity)
end

function M:Enable()
    self.generation = (self.generation or 0) + 1
    self.ids = ParseIDs(self.config.itemIDs)
    self.context:Event("SHOW_LOOT_TOAST", LootToast)
end

function M:Refresh()
    self.ids = ParseIDs(self.config.itemIDs)
    local style = S.QoLStyle(self.config)
    for _, frame in ipairs(self.toasts) do
        S.QoLColor(frame.bg, style.background, .94)
        S.QoLColor(frame.accent, style.accent)
        frame.name:SetTextColor(S.RGB(style.text))
        frame.count:SetTextColor(S.RGB(style.muted))
    end
    HideAll(self)
end

function M:Disable()
    self.generation = (self.generation or 0) + 1
    self.context:RemoveEvent("SHOW_LOOT_TOAST")
    HideAll(self)
    self.ids = {}
end

S.Install("lootToastFilter", M)

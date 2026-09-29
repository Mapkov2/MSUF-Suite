local _, P = ...
local NS, S = P.NS, P.Suite

-- The socket API validates a gem only after it is proposed in a socket.
-- This panel lists carried gems without guessing which ones will fit.
local M = {}
local FIRST_BAG, LAST_BAG = 0, 5 -- upstream/live BagIndexConstantsDocumentation.lua
local MAX_ROWS = 6

local function CarriedGems()
    local gems = {}
    local gemClass = Enum.ItemClass.Gem
    if not S.Finite(gemClass) then return gems end
    for bag = FIRST_BAG, LAST_BAG do
        local slots = C_Container.GetContainerNumSlots(bag)
        if S.Finite(slots) and slots >= 0 and slots <= 200 and slots == math.floor(slots) then
            for slot = 1, slots do
                local item = C_Container.GetContainerItemInfo(bag, slot)
                if S.Public(item) and type(item) == "table"
                    and S.Public(item.hyperlink) and type(item.hyperlink) == "string"
                    and S.Finite(item.itemID) and item.itemID > 0
                    and S.Finite(item.stackCount) and item.stackCount > 0
                    and S.Finite(item.iconFileID) and item.iconFileID > 0 then
                    local _, _, _, _, _, classID = C_Item.GetItemInfoInstant(item.hyperlink)
                    if S.Public(classID) and classID == gemClass then
                        local gem = gems[item.itemID]
                        if not gem then
                            local name = item.itemName
                            if not S.Public(name) or type(name) ~= "string" then name = tostring(item.itemID) end
                            gem = { id = item.itemID, name = name, icon = item.iconFileID,
                                count = 0, bag = bag, slot = slot }
                            gems[item.itemID] = gem
                        end
                        gem.count = gem.count + item.stackCount
                    end
                end
            end
        end
    end
    local list = {}
    for _, gem in pairs(gems) do list[#list + 1] = gem end
    table.sort(list, function(a, b)
        if a.name == b.name then return a.id < b.id end
        return a.name < b.name
    end)
    return list
end

local function CreatePanel(owner)
    local panel = CreateFrame("Frame", nil, owner)
    panel:SetSize(194, 215)
    panel:SetPoint("TOPLEFT", owner, "TOPRIGHT", 8, -28)
    local bg = panel:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0.055, 0.065, 0.08, 0.94)
    local title = panel:CreateFontString(nil, "OVERLAY")
    title:SetFontObject(GameFontNormalSmall)
    title:SetPoint("TOPLEFT", 9, -9)
    title:SetText(S.Text("Gems in bags"))
    local note = panel:CreateFontString(nil, "OVERLAY")
    note:SetFontObject(GameFontDisableSmall)
    note:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -3)
    note:SetText(S.Text("Check the native socket before applying"))
    note:SetWidth(176)
    note:SetJustifyH("LEFT")
    panel.rows = {}
    for i = 1, MAX_ROWS do
        local row = CreateFrame("Frame", nil, panel)
        row:SetSize(176, 22)
        row:SetPoint("TOPLEFT", 9, -48 - (i - 1) * 23)
        row:EnableMouse(true)
        local hover = row:CreateTexture(nil, "BACKGROUND")
        hover:SetAllPoints()
        hover:SetColorTexture(0.8, 0.63, 0.21, 0.14)
        hover:Hide()
        row.hover = hover
        local icon = row:CreateTexture(nil, "ARTWORK")
        icon:SetSize(20, 20)
        icon:SetPoint("LEFT", 1, 0)
        row.icon = icon
        local name = row:CreateFontString(nil, "OVERLAY")
        name:SetFontObject(GameFontHighlightSmall)
        name:SetPoint("LEFT", icon, "RIGHT", 5, 0)
        name:SetWidth(121)
        name:SetJustifyH("LEFT")
        name:SetWordWrap(false)
        row.name = name
        local count = row:CreateFontString(nil, "OVERLAY")
        count:SetFontObject(GameFontNormalSmall)
        count:SetPoint("RIGHT", -1, 0)
        row.count = count
        row:SetScript("OnEnter", function(self)
            local gem = self.gem
            if not gem or NS.Safety.IsForbidden(_G.GameTooltip) then return end
            local item = C_Container.GetContainerItemInfo(gem.bag, gem.slot)
            if not S.Public(item) or type(item) ~= "table"
                or not S.Finite(item.itemID) or item.itemID ~= gem.id then return end
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetBagItem(gem.bag, gem.slot)
            GameTooltip:Show()
            self.hover:Show()
        end)
        row:SetScript("OnLeave", function(self)
            self.hover:Hide()
            GameTooltip:Hide()
        end)
        panel.rows[i] = row
    end
    local more = panel:CreateFontString(nil, "OVERLAY")
    more:SetFontObject(GameFontDisableSmall)
    more:SetPoint("BOTTOMLEFT", 9, 7)
    panel.more = more
    return panel
end

local function Refresh(self)
    if not self.active then return end
    local owner = _G.ItemSocketingFrame
    if not owner or NS.Safety.IsForbidden(owner) or not owner:IsShown() then
        if self.panel then self.panel:Hide() end
        return
    end
    if NS.IsCombatLocked() then
        if self.panel then self.panel:Hide() end
        self.context:Event("PLAYER_REGEN_ENABLED", Refresh)
        return
    end
    self.context:RemoveEvent("PLAYER_REGEN_ENABLED")
    local gems = CarriedGems()
    if #gems == 0 then
        if self.panel then self.panel:Hide() end
        return
    end
    if not self.panel or self.panel:GetParent() ~= owner then self.panel = CreatePanel(owner) end
    for i, row in ipairs(self.panel.rows) do
        local gem = gems[i]
        row.gem = gem
        if gem then
            row.icon:SetTexture(gem.icon)
            row.name:SetText(gem.name)
            row.count:SetText(gem.count > 1 and tostring(gem.count) or "")
            row:Show()
        else
            row:Hide()
        end
    end
    if #gems > MAX_ROWS then
        self.panel.more:SetText(S.Text("More gems in your bags") .. " (" .. (#gems - MAX_ROWS) .. ")")
        self.panel.more:Show()
    else
        self.panel.more:Hide()
    end
    self.panel:Show()
end

local function SocketUpdated(self)
    local generation = self.generation
    -- Blizzard loads/shows its frame during this event. Refresh afterward.
    C_Timer.After(0, function()
        if self.active and self.generation == generation then Refresh(self) end
    end)
end

function M:Enable()
    self.generation = (self.generation or 0) + 1
    self.context:Event("SOCKET_INFO_UPDATE", SocketUpdated)
    self.context:Event("BAG_UPDATE_DELAYED", Refresh)
    Refresh(self)
end

function M:Disable()
    self.generation = (self.generation or 0) + 1
    self.context:RemoveEvent("SOCKET_INFO_UPDATE")
    self.context:RemoveEvent("BAG_UPDATE_DELAYED")
    self.context:RemoveEvent("PLAYER_REGEN_ENABLED")
    if self.panel then self.panel:Hide() end
end

S.Install("socketGemSuggestions", M)

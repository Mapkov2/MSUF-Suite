local _, P = ...
local NS, S = P.NS, P.Suite
local Search = {}
P.BuybackSearch = Search

local edit, rows, hooked, filtered
local query, rightInset

local function Filter(term)
    if not term and not filtered then return end
    local context = P.BagsModule.context
    local count = term and GetNumBuybackItems()
    if not NS.Finite(count) then count = 0 end
    filtered = term ~= nil
    for i, row in ipairs(rows) do
        local name = i <= count and NS.PublicText(GetBuybackItemInfo(i))
        local dim = name and not name:lower():find(term, 1, true)
        for _, region in ipairs(row) do
            if dim then
                context:Alpha(region, .22)
            else
                context:RestoreProperty(region, "SetAlpha")
            end
        end
    end
end

local function TextChanged(box)
    local text = NS.PublicText(box:GetText())
    query = text and NS.PublicText(text:match("^%s*(.-)%s*$"):lower())
    if box:IsVisible() then Filter(query) end
end

local function Build(frame)
    rows = {}
    for i = 1, BUYBACK_ITEMS_PER_PAGE do
        local prefix = "MerchantItem" .. i
        -- The scrollable merchant list owns alpha on the row itself.
        rows[i] = { _G[prefix .. "ItemButton"], _G[prefix .. "Name"], _G[prefix .. "MoneyFrame"] }
    end
    edit = P.ChildFrame("EditBox", frame, "SearchBoxTemplate")
    edit:Hide()
    edit:SetHeight(20)
    edit:SetMaxBytes(128)
    edit:SetFrameLevel(frame:GetFrameLevel() + 10)
    edit:HookScript("OnTextChanged", TextChanged)
end

local function Leave()
    if not edit or not edit:IsShown() then return end
    edit:ClearFocus()
    edit:Hide()
    Filter(nil)
end

local function Closed()
    Leave()
    if edit then edit:SetText("") end
end

function Search.Refresh()
    if not P.BagsModule.active then return end
    local frame = MerchantFrame
    if not hooked then
        -- Blizzard_UIPanels_Game loads the merchant window on both clients.
        hooked = true
        hooksecurefunc("MerchantFrame_Update", Search.Refresh)
        frame:HookScript("OnHide", Closed)
    end
    if not frame:IsShown() or frame.selectedTab ~= 2 then
        Leave()
        return
    end
    -- The portrait is to the left. The native 152 px filter may still show on the right.
    local inset = frame.FilterDropdown:IsShown() and 171 or 14
    if inset ~= rightInset then
        if NS.IsCombatLocked() then
            S.Queue("bags")
            return
        end
        if not edit then Build(frame) end
        edit:ClearAllPoints()
        edit:SetPoint("TOPLEFT", frame, "TOPLEFT", 73, -32)
        edit:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -inset, -32)
        rightInset = inset
    end
    edit:Show()
    Filter(query)
end

Search.Disable = Closed

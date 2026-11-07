local root, flavor = assert(arg[1]), arg[2] or "Mainline"
local secret = {}
local H = dofile(root .. "/tools/tests/suite_bags_harness.lua")
local W = H.New(root, { client = flavor, isSecret = function(value) return value == secret end })
local vendor = MerchantFrame
local items = { "Coarse Stone", "Medium Leather", "Schematic: E.Z. Throw", secret }
local rows, reads = {}, 0
BUYBACK_ITEMS_PER_PAGE = 12
GetNumBuybackItems = function() return #items end
GetBuybackItemInfo = function(i)
    reads = reads + 1
    return items[i]
end
vendor.FilterDropdown = CreateFrame("Button", nil, vendor)
vendor.FilterDropdown:SetShown(flavor == "Mainline")
for i = 1, BUYBACK_ITEMS_PER_PAGE do
    local prefix = "MerchantItem" .. i
    local row = CreateFrame("Frame", prefix, vendor)
    row.icon = CreateFrame("Button", prefix .. "ItemButton", row)
    row.icon:SetID(i)
    row.name = row:CreateFontString(prefix .. "Name")
    row.price = CreateFrame("Frame", prefix .. "MoneyFrame", row)
    rows[i] = row
end
rows[2].name:SetAlpha(.8)

local search
W.templates.SearchBoxTemplate = function(box)
    assert(box:GetParent() == nil, "search box created inside the native gamepad panel")
    box:SetScript("OnTextChanged", function(self) self.nativeTextChanged = true end)
    search = box
end
local function Tab(index)
    W.Native(function()
        vendor.selectedTab = index
        MerchantFrame_Update()
    end)
end
local function Type(text)
    search.nativeTextChanged = nil
    search:SetText(text)
    search:GetScript("OnTextChanged")(search)
    assert(search.nativeTextChanged, "native search template handler was replaced")
end
local function CheckDim(index, dim)
    local row = rows[index]
    local alpha = dim and .22 or 1
    local nameAlpha = not dim and index == 2 and .8 or alpha
    assert(row.icon:GetAlpha() == alpha and row.price:GetAlpha() == alpha and row.name:GetAlpha() == nameAlpha,
        "unexpected buyback row opacity at index " .. index)
    assert(row.icon:IsShown() and row.icon:GetID() == index, "native buyback button was modified")
end

W.Apply()
vendor:Show()
Tab(1)
assert(not search and reads == 0, "vendor tab created or ran buyback search")
Tab(2)
assert(search:IsVisible() and reads == 0, "buyback search was not built lazily")
local _, _, _, inset = search:GetPoint(2)
assert(inset == (flavor == "Mainline" and -171 or -14), "search overlaps the vendor dropdown")
Type("  lEaTh  ")
CheckDim(1, true)
CheckDim(2, false)
CheckDim(3, true)
CheckDim(4, false)
CheckDim(12, false)
Type(".")
CheckDim(1, true)
CheckDim(3, false)
Type("stone")
Tab(1)
assert(not search:IsShown(), "search leaked onto the vendor tab")
CheckDim(2, false)
Tab(2)
CheckDim(2, true)
table.remove(items, 1)
Tab(2)
CheckDim(1, true)
CheckDim(3, false)
Type("")
CheckDim(1, false)
CheckDim(2, false)
Type("missing")
vendor:Hide()
assert(not search:IsShown() and search:GetText() == "", "closing the merchant kept a stale search")
CheckDim(1, false)
vendor:Show()
Tab(2)
Type("missing")
assert(W.S.Set("bags", "enabled", false))
CheckDim(1, false)
Tab(2)
assert(not search:IsShown(), "disabled Bags module repainted buyback search")
assert(#W.errors == 0 and #W.taint == 0 and #W.combatLayout == 0, "modeled native/combat failure")
print("Suite buyback search: native rows, tab changes, merchant updates and cleanup passed")

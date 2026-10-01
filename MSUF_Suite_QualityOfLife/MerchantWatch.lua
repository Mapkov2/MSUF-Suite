local _, P = ...
local S = P.Suite

-- One post-hook on MerchantFrame_Update for the modules that decorate the
-- merchant window. Blizzard runs that update on every bag, currency and
-- inventory change at a merchant (MerchantFrame_OnEvent), so such a burst
-- reaches each module once, on the next frame. A newly opened window, page or
-- tab reaches them at once, so a decoration never sits on the items of the
-- previous page for a frame.
local watchers = {}
local hooked, pending, tab, page = false, false, nil, nil

local function Run()
    pending = false
    tab, page = MerchantFrame.selectedTab, MerchantFrame.page
    for module, paint in pairs(watchers) do
        if module.active then S.Dispatch(paint, module) end
    end
end

local function Deferred()
    if pending then Run() end
end

local function Schedule()
    if pending then return end
    pending = true
    C_Timer.After(0, Deferred)
end

local function Updated()
    if not next(watchers) then return end
    if MerchantFrame.selectedTab ~= tab or MerchantFrame.page ~= page then
        Run()
    else
        Schedule()
    end
end

local function Closed()
    tab, page = nil, nil
end

-- paint(module) runs after Blizzard's merchant update while module.active.
-- Blizzard_UIPanels_Game builds the merchant window before any addon loads;
-- hooks cannot be removed, so they do nothing without watchers.
function S.WatchMerchant(module, paint)
    watchers[module] = paint
    if hooked then return end
    hooked = true
    hooksecurefunc("MerchantFrame_Update", Updated)
    MerchantFrame:HookScript("OnHide", Closed)
end

function S.UnwatchMerchant(module)
    watchers[module] = nil
end

-- Repaints every watcher on the next frame, for example after a setting
-- that one watcher shows on the other's surface changed.
function S.RepaintMerchant()
    if next(watchers) and MerchantFrame:IsShown() then Schedule() end
end

-- Item level of a merchant offer's link: the level, false while the client
-- still loads an equippable item's data, nil when no level applies.
function S.MerchantOfferLevel(link)
    local equippable = C_Item.IsEquippableItem(link)
    if not S.Public(equippable) or equippable ~= true then return nil end
    local level = C_Item.GetDetailedItemLevelInfo(link)
    if S.Finite(level) and level > 0 then return math.floor(level) end
    return false
end

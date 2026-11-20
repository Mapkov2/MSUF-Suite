local _, NS = ...

local ShopMotion = {}
NS.CatalogShopMotion = ShopMotion
local Safety, Motion = NS.Safety, NS.WindowMotion
local VISIBILITY_EVENT = "CatalogShopFrame.VisibilityUpdated"
local owners = {}

local function CurrentShop()
    local frame = Safety.Field(_G, "CatalogShopFrame")
    if Safety.Public(frame) then return frame end
end

local function VisibilityChanged(_, shown)
    if not Safety.Public(shown) or type(shown) ~= "boolean" then return end
    local frame = CurrentShop()
    if not frame then return end
    for _, target in pairs(owners) do
        if frame == target then
            Motion.ShopVisibility(frame, shown)
            return
        end
    end
end

function ShopMotion.Apply(frame, owner)
    if not Safety.Public(frame) or not frame or frame ~= CurrentShop()
        or not Safety.Public(owner) or owner == nil then return false end

    local previous = owners[owner]
    if previous == frame then return true end
    if not Motion.WatchShop(frame, owner) then return false end
    if not next(owners) then
        -- CatalogShop_Outbound publishes this observation in the global
        -- environment. We never subscribe to the native Shop's scripts.
        EventRegistry:RegisterCallback(VISIBILITY_EVENT, VisibilityChanged, ShopMotion)
    end
    if previous then Motion.Unwatch(previous, owner) end
    owners[owner] = frame
    return true
end

function ShopMotion.Disable(owner)
    if not Safety.Public(owner) then return end
    local frame = owners[owner]
    if not frame then return end
    owners[owner] = nil
    Motion.Unwatch(frame, owner)
    if not next(owners) then
        EventRegistry:UnregisterCallback(VISIBILITY_EVENT, ShopMotion)
    end
end

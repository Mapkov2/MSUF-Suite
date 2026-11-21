local _, NS = ...

-- Keep the entry points used by loaded skin adapters while retiring the
-- detached accent artwork. ContentMotion handles window opening fades.
local function Inactive()
    return false
end

NS.WindowMotion = {
    Watch = Inactive,
    WatchShop = Inactive,
    ShopVisibility = Inactive,
    WatchPreview = Inactive,
    Unwatch = Inactive,
}

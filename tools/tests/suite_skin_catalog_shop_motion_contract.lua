-- The Shop publishes visibility across its secure boundary. The adapter
-- subscribes there once, with no native frame hooks or changes.
local root = assert(arg[1], "Suite root required")
local adapter = arg[2] or root .. "/MSUF_Suite_Skin/Adapters/CatalogShopMotion.lua"
local event = "CatalogShopFrame.VisibilityUpdated"
local secret = {}
issecretvalue = function(value) return value == secret end

local registers, unregisters = 0, 0
local callback, callbackOwner
EventRegistry = {}
function EventRegistry:RegisterCallback(name, handler, owner)
    assert(name == event and not callback, "incorrect or duplicate subscription to Shop visibility")
    registers = registers + 1
    callback, callbackOwner = handler, owner
end
function EventRegistry:UnregisterCallback(name, owner)
    assert(name == event and callback and owner == callbackOwner, "incorrect Shop unsubscription")
    unregisters = unregisters + 1
    callback, callbackOwner = nil, nil
end

local function NativeShop()
    return setmetatable({}, {
        __index = function(_, key) error("Shop adapter touched native method " .. key) end,
        __newindex = function(_, key) error("Shop adapter wrote native field " .. key) end,
    })
end

local observed, active, watches = {}, {}, 0
local ns = {
    WindowMotion = {
        WatchShop = function(frame, owner)
            local owners = active[frame] or {}
            assert(frame == CatalogShopFrame and not owners[owner], "invalid or duplicate Shop registration")
            watches = watches + 1
            if owner == "blocked" then return false end
            owners[owner], active[frame] = true, owners
            return true
        end,
        Unwatch = function(frame, owner)
            local owners = active[frame]
            assert(owners and owners[owner], "wrong Shop root or owner released")
            owners[owner] = nil
        end,
        ShopVisibility = function(frame, shown)
            assert(frame == CatalogShopFrame and type(shown) == "boolean", "invalid visibility dispatch")
            observed[#observed + 1] = shown
        end,
    },
}
assert(loadfile(root .. "/MSUF_Suite_Skin/Core/Safety.lua"))("MSUF_Suite_Skin", ns)
assert(loadfile(adapter))("MSUF_Suite_Skin", ns)
local shop = ns.CatalogShopMotion
local frame = NativeShop()
CatalogShopFrame = frame
assert(not shop.Apply(NativeShop(), "foreign") and not shop.Apply(frame, secret))
assert(not shop.Apply(frame, "blocked") and registers == 0)
assert(shop.Apply(frame, "one") and shop.Apply(frame, "one"))
assert(shop.Apply(frame, "two") and registers == 1 and watches == 3)
callback(callbackOwner, secret)
callback(callbackOwner, "true")
CatalogShopFrame = NativeShop()
callback(callbackOwner, true)
CatalogShopFrame = secret
callback(callbackOwner, false)
assert(#observed == 0, "invalid native visibility reached the renderer")
CatalogShopFrame = frame
callback(callbackOwner, true)
callback(callbackOwner, false)
assert(#observed == 2 and observed[1] == true and observed[2] == false)

local replacement = NativeShop()
CatalogShopFrame = replacement
assert(shop.Apply(replacement, "one") and not active[frame].one and watches == 4)
shop.Disable("two")
assert(unregisters == 0 and not active[frame].two)
shop.Disable("one")
shop.Disable("one")
assert(unregisters == 1 and not active[replacement].one and not callback)
assert(shop.Apply(replacement, "one") and registers == 2)
shop.Disable("one")
assert(unregisters == 2)
print("Catalog Shop visibility subscription contract passed")

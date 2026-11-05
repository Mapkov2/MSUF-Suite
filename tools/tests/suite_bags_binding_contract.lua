-- Real bag overlays and inventory search must share the current item's binding,
-- including Warbound-until-equipped items whose generic bind enum is OnEquip.
local root = assert(arg[1], "repository root required")
local H = dofile(root .. "/tools/tests/suite_bags_harness.lua")
local secret = {}
local W = H.New(root, { config = { inventoryView = 4, showBindBadge = true },
    isSecret = function(value) return value == secret end })
W.sizes[0] = 1
local index = W.P.InventoryIndex.New()
local rules = W.NS.InventoryRules
local queries = {}
for _, name in ipairs({ "boe", "wue", "warbound" }) do queries[name] = assert(rules.Compile("is:" .. name)) end

local function Check(bind, bound, wue, expected, label)
    local id = 500 + bind
    W.Define(id, { name = "Binding test", equipLoc = "INVTYPE_CHEST", level = 610, bind = bind })
    W.Put(0, 1, id, 1, { bound = bound, wue = wue })
    W.BagChanged(0)
    W.Settle()
    local button = W.CF.Items[1]
    local badge = W.M.overlays[button] and W.M.overlays[button].bindBadge
    assert((expected and badge and badge.shown and badge.text == expected)
        or (not expected and (not badge or not badge.shown)), label .. ": wrong badge")
    local info, quest, version = W.P.SlotCache.Get(0, 1)
    index.items = {}
    local calls = W.calls.binding
    local item = W.P.InventoryIndex.ReadButton(index, button, info, quest, version, 0, 1)
    if wue ~= secret then assert(W.calls.binding == calls, label .. ": badge and search read binding twice") end
    for name, query in pairs(queries) do
        local text = ({ boe = "BoE", wue = "WuE", warbound = "WB" })[name]
        assert(rules.Matches(query, item) == (expected == text), label .. ": wrong " .. name .. " search")
    end
    return button
end

W.Define(501, { name = "Binding test", equipLoc = "INVTYPE_CHEST", level = 610, bind = 2 })
W.Put(0, 1, 501, 1, { bound = true, wue = true })
W.Apply()
W.OpenBags()
W.Settle()
Check(2, true, true, "WuE", "Warbound item with OnEquip enum and bound flag")
Check(9, true, true, "WuE", "Warbound item with account-until-equipped enum")
Check(8, true, true, "WuE", "current instance takes priority over account enum")
Check(2, true, false, nil, "same-link item after equipping")
Check(9, true, false, nil, "equipped item with stale until-equipped enum")
Check(9, false, false, nil, "instance rejects generic until-equipped enum")
Check(2, false, false, "BoE", "ordinary unbound BoE")
Check(2, true, false, nil, "ordinary bound BoE")
for _, bind in ipairs({ 7, 8 }) do
    Check(bind, false, false, "WB", "permanent Warbound unbound flag")
    Check(bind, true, false, "WB", "permanent Warbound bound flag")
end
Check(2, false, secret, nil, "unreadable binding must not become BoE")
Check(8, true, secret, nil, "unreadable binding must not become permanent WB")
Check(9, true, true, "WuE", "binding recovers after unreadable state")
local calls = W.calls.binding
W.Native(function() W.CF:UpdateItems() end)
W.Settle()
assert(W.calls.binding == calls, "unchanged slot re-read its binding")
-- An unreadable result can recover without a BAG_UPDATE/version change.
Check(2, false, secret, nil, "temporarily unreadable instance")
W.Item(0, 1).wue = true
W.Native(function() W.CF:UpdateItems() end)
W.Settle()
local info, quest, version = W.P.SlotCache.Get(0, 1)
local recovered = W.P.InventoryIndex.ReadButton(index, W.CF.Items[1], info, quest, version, 0, 1)
assert(rules.Matches(queries.wue, recovered), "same-version binding did not recover with its badge")
-- Metadata can arrive after the slot read without changing its version.
W.Define(601, { name = "Delayed binding", equipLoc = "INVTYPE_CHEST", level = 610, bind = 2, cached = false })
W.Put(0, 1, 601, 1, { bound = true, wue = true })
W.BagChanged(0)
W.Settle()
local info, quest, version = W.P.SlotCache.Get(0, 1)
index.items = {}
local delayed = W.P.InventoryIndex.ReadButton(index, W.CF.Items[1], info, quest, version, 0, 1)
assert(not delayed.loaded and not rules.Matches(queries.wue, delayed), "uncached item guessed its binding")
W.data[601].cached = true
assert(W.P.InventoryIndex.ItemDataReceived(index, 601, true))
assert(W.P.InventoryIndex.Refresh(index, 601))
assert(delayed.loaded and rules.Matches(queries.wue, delayed), "arriving metadata did not refresh binding")
local unchanged = W.P.InventoryIndex.ReadButton(index, W.CF.Items[1], info, quest, version, 0, 1)
assert(rules.Matches(queries.wue, unchanged), "same-version item lost its refreshed binding")
W.EnterCombat()
Check(2, true, false, nil, "binding change in combat")
W.LeaveCombat()
assert(#W.taint == 0 and #W.combatLayout == 0, "binding updates wrote to protected frames")
-- Older API surfaces retain the existing generic-enum fallback.
local readInstanceBinding = C_Item.IsBoundToAccountUntilEquip
C_Item.IsBoundToAccountUntilEquip = nil
Check(2, false, false, "BoE", "missing API unbound BoE fallback")
Check(2, true, false, nil, "missing API bound BoE fallback")
Check(9, false, false, "WuE", "missing API until-equipped fallback")
Check(8, true, false, "WB", "missing API permanent WB fallback")
C_Item.IsBoundToAccountUntilEquip = readInstanceBinding
-- Identical item links in different slots may have different instance bindings.
W.sizes[0] = 2
W.Put(0, 1, 502, 1, { bound = true, wue = true })
W.Put(0, 2, 502, 1, { bound = true, wue = false })
W.OpenBags()
W.BagChanged(0)
W.Settle()
for _, button in ipairs(W.CF.Items) do
    local slot = button:GetID()
    local overlay = W.M.overlays[button]
    if slot == 1 then
        assert(overlay.bindBadge.shown and overlay.bindBadge.text == "WuE", "same-link WuE instance lost badge")
    elseif slot == 2 then
        assert(not overlay.bindBadge or not overlay.bindBadge.shown, "same-link soulbound instance inherited badge")
    end
end
-- A merchant sale can empty a slot between the shared read and the view's
-- binding lookup. The native binding API rejects that stale ItemLocation.
local slots = W.P.SlotCache
for _, bind in ipairs({ 0, 2, 9 }) do
    W.Define(700 + bind, { name = "Sold item", equipLoc = "INVTYPE_WAIST", bind = bind })
    W.Put(0, 1, 700 + bind, 1)
    slots.MarkSlot(0, 1)
    slots.Sync(0)
    local cached, quest, version = slots.Get(0, 1)
    assert(cached, "sale fixture did not cache the item")
    W.items[0][1] = nil -- native sale, before BAG_UPDATE reaches the cache
    local calls = W.calls.binding
    local sold = W.P.InventoryIndex.ReadButton(index, W.CF.Items[1], cached, quest, version, 0, 1)
    assert(sold.binding == false and sold.version == nil, "sold item cached a guessed binding")
    assert(W.calls.binding == calls, "sold slot reached the native binding API")
    assert(slots.dirtySlots[1], "sold slot was not scheduled for a fresh container read")
    slots.Sync(0)
    assert(slots.Get(0, 1) == nil, "next sync retained the sold item")
    W.Put(0, 1, 502, 1, { bound = true, wue = true })
    slots.MarkSlot(0, 1)
    slots.Sync(0)
    assert(slots.Binding(0, 1, 2) == 9, "reused sold slot did not recover its instance binding")
    local existsCalls, bindingCalls = W.calls.itemExists, W.calls.binding
    assert(slots.Binding(0, 1, 2) == 9, "cached recovered binding changed")
    assert(W.calls.itemExists == existsCalls and W.calls.binding == bindingCalls,
        "cached binding repeated native existence or binding queries")
end
-- Unknown existence stays retryable, just like unknown instance binding.
local itemExists = C_Item.DoesItemExist
local Secrets = dofile(root .. "/../MidnightSimpleUnitFrames/tools/tests/classpower_secrets.lua")
Secrets.Install()
Secrets.GUARD_NAMES.falsy.Public = true
secret = Secrets.New("boolean")
local stopWatch = Secrets.Watch(root .. "/MSUF_Suite_Bags/SlotCache.lua", { strict = true })
for _, result in ipairs({ secret, false }) do
    slots.MarkSlot(0, 1)
    slots.Sync(0)
    C_Item.DoesItemExist = function() return result end
    local calls = W.calls.binding
    assert(slots.Binding(0, 1, 2) == nil and slots.dirtySlots[1], "unknown existence was cached as bound")
    assert(W.calls.binding == calls, "unknown existence reached the native binding API")
    C_Item.DoesItemExist = itemExists
    assert(slots.Binding(0, 1, 2) == 9, "existence recovery required a cache reset")
end
local violations = stopWatch()
assert(#violations == 0, "binding existence secret misuse: " .. table.concat(violations, "; "))
print("bag binding: per-instance badges/search, merchant sale, slot reuse, secrets and cache passed")

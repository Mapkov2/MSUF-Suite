-- Repeatable full-TOC client model, with the same 164 slots / 81 items
-- before and after the Bags rebuild. Counts modeled native widget method
-- invocations (including the fixture's SetShown -> Show); not elapsed time.
-- Frozen pre-change totals: All 1000, Categories 996. Maximum +2%.
local root = assert(arg[1])
local H = dofile(root .. "/tools/tests/suite_bags_harness.lua")
local methods = { "Show", "Hide", "SetShown", "ClearAllPoints", "SetPoint", "SetSize", "SetText", "SetWidth", "SetHeight",
    "SetColorTexture", "SetAlpha", "SetEnabled", "IsShown", "GetWidth", "GetHeight", "GetScale", "GetEffectiveScale" }
for _, view in ipairs({ 1, 3 }) do
    local W = H.New(root, { config = { inventoryView = view, showPinned = false, showRecent = false } })
    W.sizes[0] = 20
    for bag = 1, 4 do W.sizes[bag] = 36 end
    for id = 1, 81 do
        W.Define(id, { name = "Item " .. id, class = id < 31 and 4 or id < 61 and 0 or 7,
            equipLoc = id < 31 and "INVTYPE_CHEST" or "", maxStack = 200 })
        local bag = id <= 20 and 0 or 1 + math.floor((id - 21) / 36)
        W.Put(bag, id <= 20 and id or (id - 21) % 36 + 1, id, 2)
    end
    W.Apply()
    W.OpenBags()
    W.Settle()
    W.Native(function() W.CF:UpdateItems() end)
    W.Settle()
    local counts, widget = {}, getmetatable(W.CF)
    for _, name in ipairs(methods) do
        local original = widget[name]
        assert(type(original) == "function", name)
        widget[name] = function(...)
            counts[name] = (counts[name] or 0) + 1
            return original(...)
        end
    end
    W.Native(function() W.CF:UpdateItems() end)
    W.Settle()
    local total = 0
    for _, count in pairs(counts) do total = total + count end
    local budget = view == 1 and 1020 or 1016
    assert(total <= budget, "native widget call budget exceeded: " .. total .. " > " .. budget)
    print("view", view, "modeled native method calls", total)
end

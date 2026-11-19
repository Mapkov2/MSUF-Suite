local root = assert(arg[1])
local H = dofile(root .. "/tools/tests/suite_bags_harness.lua")
local W = H.New(root, { config = { inventoryView = 3, inventoryColumns = 8, inventoryRows = 4,
 compactGroups = false, groupEquipmentSlots = false, groupEquipmentSets = false,
 showPinned = false, showRecent = false, hideEmptySlots = true } })
W.sizes[0] = 20
W.Define(101, { name = "Sword", equipLoc = "INVTYPE_WEAPON" })
W.Define(102, { name = "Potion", class = 0 })
W.Put(0, 1, 101, 1)
 W.Put(0, 2, 102, 1)
for i = 3, 20 do W.Define(100+i, { name = "Cloth "..i, class = 7 })
 W.Put(0, i, 100+i, 1) end
W.Apply()
 W.OpenBags()
 W.Settle()
local V = W.P.InventoryView
local label = assert(V.labels[1], "no header to repaint")
local headerWrites = 0
for _, method in ipairs({ "ClearAllPoints", "SetPoint", "SetWidth", "SetText" }) do
 local original = label[method]
 label[method] = function(self, ...)
  headerWrites = headerWrites + 1
  return original(self, ...)
 end
end
V.MoveScroll(0)
assert(headerWrites == 0, "unchanged header was reanchored or rewritten")
local width = label:GetWidth()
W.M.config.inventoryColumns = 6
V.MoveScroll(0)
assert(label:GetWidth() < width, "reused header kept the old viewport width")
W.M.config.inventoryColumns = 8
V.MoveScroll(0)
assert(label:GetWidth() == width, "viewport width did not return after resizing")
W.CloseBags()
W.config.enabled = false
W.Apply()
W.config.enabled = true
W.Apply()
W.OpenBags()
W.Settle()
assert(V.labels[1] == label and label:IsVisible() and label:GetWidth() == width,
 "re-enabling the inventory did not restore the reused section header")
for scroll = 0, 4 do
 V.scroll = scroll
 V.MoveScroll(0)
 local viewportBottom = -122 - V.visibleRows * 40
 for i = 1, V.labelCount do
  local p = V.labels[i].plate
  assert(p.y + 4 - p.height >= viewportBottom, "section plate paints into footer below its viewport")
 end
end
print("independent section viewport geometry passed")

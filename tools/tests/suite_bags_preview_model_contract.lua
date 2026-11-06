local root = assert(arg[1])
local H = dofile(root .. "/tools/tests/suite_bags_harness.lua")
local W = H.New(root)
local S, Model = W.S, W.P.InventoryModel
local sample = S.BagsNewPreview()
assert(#sample.items == 12 and #sample.model.groups == 0, "preview construction is isolated data")
for view = 1, 4 do
    W.config.inventoryView = view
    local layout = S.BagsPreviewLayout(sample, W.config, false)
    local reference = Model.New()
    Model.Build(reference, sample.items, sample.config, sample.state)
    local expected = Model.Layout(reference, W.config.inventoryColumns, W.config.compactGroups)
    assert(#layout == #expected, "preview uses the actual layout model")
    for i = 1, #layout do
        local a, b = layout[i], expected[i]
        assert(a.line == b.line and a.column == b.column and a.group.key == b.group.key,
            "preview category placement must match runtime")
    end
end
assert(not W.M.active and not W.CF:IsShown(), "preview never starts the module or opens bags")
print("Bags preview uses the runtime category and packing model")

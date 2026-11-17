local root = assert(arg[1])
local H = dofile(root .. "/tools/tests/suite_bags_harness.lua")
for _, view in ipairs({1,4}) do
    local W=H.New(root,{config={inventoryView=view,showItemLevel=false,showBindBadge=false,
        slotBorderWidth=1,emptySlotBorderWidth=3}})
    W.sizes[0]=8
    W.Define(101,{name="Rare item",quality=3})
    W.Define(102,{name="Epic item",quality=4})
    W.Put(0,1,101)
    W.Apply(); W.OpenBags(); W.Settle()
    local button=W.P.InventoryView.index.buttons[1]
    if view==4 then
        for _, candidate in W.CF:EnumerateValidItems() do if candidate:GetID()==1 then button=candidate end end
    end
    local filled=assert(W.M.overlays[button])
    local empty
    for _, record in pairs(W.M.overlays) do if record.slotEmpty then empty=record; break end end
    assert(filled.strokeQuality==3,"quality border disappeared without item labels")
    assert(button.NormalTexture:GetAlpha()==0 and button.IconBorder:GetAlpha()==0,"duplicate native border is still drawn")
    assert(filled.slotEdges[1]:GetHeight()==1 and empty.slotEdges[1]:GetHeight()==3,"independent widths ignored")
    W.Put(0,1,102); W.BagChanged(0); W.Settle()
    assert(filled.strokeQuality==4,"reused occupied slot kept its old quality border")
    W.config.slotBorderWidth=0
    W.config.emptySlotBorderWidth=0
    W.Apply(); W.Settle()
    for _, record in pairs(W.M.overlays) do
        if record.slotEdges then
            for _, edge in ipairs(record.slotEdges) do assert(not edge:IsShown(),"zero width still draws an edge") end
        end
        assert(not record.slotInner:IsShown(),"empty slot still draws an inset line")
    end
    W.config.enabled=false; W.Apply()
    assert(button.NormalTexture:GetAlpha()==1 and button.IconBorder:GetAlpha()==1,"disable did not restore native borders")
    assert(#W.errors==0 and #W.taint==0,table.concat(W.errors,";")..table.concat(W.taint,";"))
end
print("slot borders: independent widths, zero, quality changes without labels and restore passed")

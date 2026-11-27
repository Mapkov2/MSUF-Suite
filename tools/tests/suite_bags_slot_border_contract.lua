local root = assert(arg[1])
local H = dofile(root .. "/tools/tests/suite_bags_harness.lua")
local function CheckReassignedSlot()
    local W = H.New(root, { client = arg[2], config = { inventoryView = 4, showItemLevel = false, showBindBadge = false } })
    W.sizes[0], W.sizes[1] = 1, 1
    W.Define(101, { name = "Rare PvP item", quality = 3 })
    W.Define(102, { name = "Epic PvP item", quality = 4 })
    W.Put(0, 1, 101)
    W.Put(1, 1, 102)
    W.Apply()
    W.OpenBags()
    W.Settle()
    local reused = W.CF.Items[1]
    local record = assert(W.M.overlays[reused])
    assert(reused:GetBagID() == 1 and record.strokeQuality == 4, "expected an epic equipped-bag slot")

    W.CloseBags()
    W.sizes[1] = 0
    W.OpenBags()
    W.Settle()
    assert(W.CF.Items[1] == reused and reused:GetBagID() == 0 and reused:HasItem(), "expected occupied slot reassignment")
    assert(record.strokeQuality == 3, "reassigned native button kept the old bag slot's quality")
end

CheckReassignedSlot()

local function CheckWarmSlotWrites()
    local W = H.New(root, { client = arg[2], config = { inventoryView = 1, showItemLevel = false, showBindBadge = false } })
    W.sizes[0] = 8
    W.Define(101, { name = "Rare item", quality = 3 })
    W.Put(0, 1, 101)
    local color = { r = .1, g = .4, b = .8 }
    ColorManager.GetColorDataForBagItemQuality = function() return color end
    W.Apply()
    W.OpenBags()
    W.Settle()
    local writes, paints = 0, 0
    local paintSlot = W.P.BagSlotAppearance.Paint
    W.P.BagSlotAppearance.Paint = function(...)
        paints = paints + 1
        return paintSlot(...)
    end
    for _, button in W.CF:EnumerateValidItems() do
        local record = assert(W.M.overlays[button])
        for _, region in ipairs({record.slotOuter, record.slotInner, unpack(record.slotEdges)}) do
            for _, method in ipairs({"SetColorTexture", "SetHeight", "SetWidth", "SetShown", "Hide"}) do
                local original = region[method]
                region[method] = function(widget, ...)
                    writes = writes + 1
                    return original(widget, ...)
                end
            end
        end
    end
    W.CloseBags()
    W.OpenBags()
    W.Settle()
    -- A layout pass never changes a slot: a plain reopen asks nothing again.
    assert(paints == 0, "a plain reopen consulted the slot palette again: " .. paints)
    assert(writes == 0, "unchanged native slot decorations rewritten on reopen: " .. writes)
    -- Blizzard's accessibility palette (ColorManager.OnColorDataUpdated):
    -- an open bag repaints at once, a closed one on its next show.
    local filled = W.M.overlays[W.P.InventoryView.index.buttons[1]]
    color.g = .7
    EventRegistry:TriggerEvent("ColorManager.OnColorDataUpdated")
    assert(filled.slotEdges[1].color[2] == .7, "an open bag missed Blizzard's revised quality color")
    W.CloseBags()
    color.g = .55
    EventRegistry:TriggerEvent("ColorManager.OnColorDataUpdated")
    W.OpenBags()
    W.Settle()
    assert(filled.slotEdges[1].color[2] == .55, "reopen missed Blizzard's revised quality color")
    W.config.enabled = false
    W.Apply()
    W.config.enabled = true
    W.Apply()
    W.Settle()
    assert(filled.slotEdges[1]:IsShown() and not filled.slotInner:IsShown(), "reactivation lost slot styling")
end

CheckWarmSlotWrites()

-- Blizzard's pool hands its buttons out in hash order (Pools.lua), so a few
-- move on each open. Only a moved button is styled again (once over both of
-- the open's passes) and repainted, with the quality of its new slot. Here
-- the reversed buttons trade 6 (rare) with 9 (epic) and 7 with 8 (empty),
-- so HasItem, stale until UpdateItems, already fits at the show.
local function CheckReshuffledSlots()
    local W = H.New(root, { client = arg[2], config = { inventoryView = 1, showItemLevel = false, showBindBadge = false } })
    W.sizes[0] = 9
    W.Define(101, { name = "Rare item", quality = 3 })
    W.Define(102, { name = "Epic item", quality = 4 })
    W.Put(0, 1, 101)
    W.Put(0, 3, 102)
    W.Put(0, 6, 101)
    W.Put(0, 9, 102)
    W.Apply()
    W.OpenBags()
    W.Settle()
    local before = {}
    for _, button in W.CF:EnumerateValidItems() do before[button] = button:GetBagID() * 1000 + button:GetID() end
    W.CloseBags()
    W.Settle()
    local Slots = W.P.BagSlotAppearance
    local native, paint, styled, painted = Slots.Native, Slots.Paint, {}, {}
    Slots.Native = function(module, button, ...)
        styled[button] = (styled[button] or 0) + 1
        return native(module, button, ...)
    end
    Slots.Paint = function(record, frame, ...)
        painted[frame] = (painted[frame] or 0) + 1
        return paint(record, frame, ...)
    end
    W.reversePool = 4
    W.OpenBags()
    W.Settle()
    W.reversePool = nil
    Slots.Native, Slots.Paint = native, paint
    local moved = 0
    for _, button in W.CF:EnumerateValidItems() do
        local bag, slot = button:GetBagID(), button:GetID()
        local item = W.Item(bag, slot)
        local quality = item and W.data[item.id].quality or nil
        if bag * 1000 + slot ~= before[button] then
            moved = moved + 1
            assert(styled[button] == 1, "a moved slot was styled " .. tostring(styled[button]) .. " times")
            assert(painted[button] == (quality and 1 or nil), "a moved slot's stroke was painted " .. tostring(painted[button]) .. " times")
        else
            -- A filled slot reads its cache version again after the closed
            -- bag's pause (CombatIdle.lua); that check paints nothing.
            assert(not styled[button] or item and styled[button] == 1,
                "an unmoved slot was styled " .. tostring(styled[button]) .. " times")
            assert(not painted[button], "an unmoved slot was repainted")
        end
        -- The slot cache keeps an empty slot as false.
        assert((W.M.overlays[button].strokeQuality or nil) == quality, "a moved slot kept its old slot's quality stroke")
    end
    assert(moved == 4, "the reversed pool moved " .. moved .. " buttons")
    assert(#W.errors == 0 and #W.taint == 0, table.concat(W.errors, ";") .. table.concat(W.taint, ";"))
end

CheckReshuffledSlots()

for _, view in ipairs({1,4}) do
    local W=H.New(root,{client=arg[2],config={inventoryView=view,showItemLevel=false,showBindBadge=false,
        slotBorderWidth=1,emptySlotBorderWidth=3}})
    local rare, epic = { r = .10, g = .42, b = .96 }, { r = .61, g = .20, b = .93 }
    ColorManager = { GetColorDataForBagItemQuality = function(quality) return quality == 3 and rare or epic end }
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
    local color = filled.slotEdges[1].color
    assert(color[1] == rare.r and color[2] == rare.g and color[3] == rare.b, "rare border ignored Blizzard's bag palette")
    assert(button.NormalTexture:GetAlpha()==0 and button.IconBorder:GetAlpha()==0,"duplicate native border is still drawn")
    assert(filled.slotEdges[1]:GetHeight()==1 and empty.slotEdges[1]:GetHeight()==3,"independent widths ignored")
    W.Put(0,1,102); W.BagChanged(0); W.Settle()
    assert(filled.strokeQuality==4,"reused occupied slot kept its old quality border")
    color = filled.slotEdges[1].color
    assert(color[1] == epic.r and color[2] == epic.g and color[3] == epic.b, "epic border ignored Blizzard's bag palette")
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

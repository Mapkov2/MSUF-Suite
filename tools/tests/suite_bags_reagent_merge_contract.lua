local root = assert(arg[1])
local H = dofile(root .. "/tools/tests/suite_bags_harness.lua")
local function Ready(protected, combine)
    local W = H.New(root, {client=arg[2] or "Mainline", unprotectedBags=not protected,
        config={combineReagentBag=combine,showRecent=false,showPinned=false}})
    W.sizes[0], W.sizes[5] = 8, 4
    W.Define(101, {name="Potion",quality=2})
    W.Define(102, {name="Cloth",class=7,quality=3})
    W.Put(0,1,101)
    W.Put(5,1,102,20)
    W.Put(5,2,102,5)
    W.Apply()
    return W
end
local function World(protected)
    local W = Ready(protected, true)
    W.OpenBags()
    W.Settle()
    return W
end
local function Clean(W)
    assert(#W.errors==0 and #W.taint==0 and #W.combatLayout==0,
        table.concat(W.errors,";") .. table.concat(W.taint,";") .. table.concat(W.combatLayout,";"))
end
local function Merged(W)
    local view, reagent = W.P.InventoryView, W.P.ReagentInventory
    assert(reagent.active and W.Reagent:GetAlpha()==0 and not W.Reagent:IsMouseEnabled(),"separate shell remains active")
    local group = assert(view.model.groupsByKey.reagentBag,"missing reagent section")
    assert(view.model.groups[#view.model.groups]==group,"reagent section is not at the end")
    assert(#view.index.items==12 and view.freeSlots.regular==7 and view.freeSlots.reagent==2,"slot counts are wrong")
    for _, button in W.Reagent:EnumerateValidItems() do
        assert(button:GetParent()==W.CF and button:GetBagID()==5,"native identity or parent changed incorrectly")
        assert(button:IsVisible(),"reagent slot is unreachable")
    end
end
for _, view in ipairs({1,2,3}) do
    local W = World(false)
    W.config.inventoryView=view
    W.Apply(); W.Settle(); Merged(W)
    local button=W.Reagent.Items[1]
    W.Define(103,{name="Epic cloth",class=7,quality=4})
    W.Put(5,1,103,20)
    W.BagChanged(5)
    W.Native(function() W.Reagent:UpdateItems() end)
    W.Settle()
    assert(W.M.overlays[button].strokeQuality==4,"reagent quality border remained stale")
    W.Native(function() button.scripts.OnClick(button,"RightButton") end)
    local used=W.calls.uses[#W.calls.uses]
    assert(used[1]==5 and used[2]==1,"reagent item action reached a different slot")
    local nativeX=button.points[1][4]
    W.Search(function(item) return item.id==101 end); W.Settle()
    W.Native(function() W.Reagent:UpdateItemLayout() end); W.Settle()
    W.Search(nil); W.Settle()
    assert(button:GetParent()==W.CF and button.points[1][2]==W.CF and button.points[1][4]==nativeX,
        "native layout during search poisoned cached reagent positions")
    W.config.combineReagentBag=false
    W.Apply(); W.Settle()
    assert(not W.P.ReagentInventory.active and #W.P.InventoryView.index.items==8,"toggle off left reagent slots in backpack")
    assert(button:GetParent()==W.Reagent and W.Reagent:GetAlpha()==1,"native reagent window did not return")
    assert(W.Reagent.NineSlice:GetAlpha()==0 and W.Reagent.PortraitContainer:GetAlpha()==0,
        "integration restored Blizzard chrome underneath Suite skin")
    W.config.combineReagentBag=true
    W.Apply(); W.Settle(); Merged(W)
    W.EnterCombat(); W.Settle(); Merged(W)
    W.LeaveCombat(); W.Settle()
    W.config.inventoryView=4
    W.Apply(); W.Settle()
    assert(not W.P.ReagentInventory.active and button:GetParent()==W.Reagent,"Blizzard grid retained integrated slots")
    Clean(W)
end
do
    local W=World(false)
    W.sizes[5]=2
    W.Native(function() W.Reagent:UpdateItemSlots(); W.Reagent:UpdateItemLayout() end)
    W.BagChanged(5); W.Settle()
    assert(#W.P.InventoryView.index.items==10,"replacing reagent bag kept old slots")
    W.sizes[5]=4
    W.Native(function() W.Reagent:UpdateItemSlots(); W.Reagent:UpdateItemLayout() end)
    W.BagChanged(5); W.Settle()
    for _,button in W.Reagent:EnumerateValidItems() do
        assert(button:GetAlpha()==1 and not W.P.ReagentInventory.controls[button],"reused reagent pool slot remained muted")
    end
    W.sizes[5]=0
    W.Native(function() W.Reagent:UpdateItemSlots(); W.Reagent:UpdateItemLayout() end)
    W.BagChanged(5); W.Settle()
    assert(not W.P.ReagentInventory.active and #W.P.InventoryView.index.items==8,"unequipped reagent bag kept its slots")
    Clean(W)
end
do
    local W=World(true)
    W.CloseBags(); W.Settle()
    W.EnterCombat(); W.OpenBags(); W.Settle()
    assert(not W.P.ReagentInventory.active,"protected combat opening changed native parents")
    W.LeaveCombat(); W.Settle(); Merged(W)
    Clean(W)
end
-- Blizzard opens the combined backpack before its separate reagent container.
local function CombatOpenAll(W)
    W.EnterCombat()
    W.OpenBags()
    W.Native(OpenBag, Enum.BagIndex.ReagentBag)
end

local function Separate(W)
    local view, reagent = W.P.InventoryView, W.P.ReagentInventory
    assert(not reagent.active and #view.index.items == 8, "separate reagent slots entered the backpack")
    assert(W.Reagent:IsShown() and W.Reagent:GetAlpha() == 1, "separate reagent window was hidden")
    for _, button in W.Reagent:EnumerateValidItems() do
        assert(button:GetParent() == W.Reagent and button:IsVisible(), "separate reagent slot was moved or hidden")
    end
    Clean(W)
end

do
    local W = Ready(false, true)
    CombatOpenAll(W)
    W.Settle()
    Merged(W)
    local button = W.Reagent.Items[1]
    W.Native(button:GetScript("OnClick"), button, "RightButton")
    local use = assert(W.calls.uses[#W.calls.uses], "merged reagent slot lost its native combat action")
    assert(use[1] == Enum.BagIndex.ReagentBag and use[2] == 1, "merged reagent action changed its native bag or slot")
    W.CloseBags()
    W.Native(function() W.Reagent:Hide() end)
    W.Settle()
    assert(not button:IsVisible(), "merged reagent slot stayed visible after Close All Bags")
    W.OpenBags()
    W.Native(OpenBag, Enum.BagIndex.ReagentBag)
    W.Settle()
    Merged(W)
    Clean(W)
end

do
    local W = Ready(false, false)
    CombatOpenAll(W)
    W.Settle()
    Separate(W)
end

for _, protected in ipairs({ "frame", "slot" }) do
    local W = Ready(false, true)
    CombatOpenAll(W)
    local target = protected == "frame" and W.Reagent or W.Reagent.Items[1]
    target.protection, target.guarded = true, true
    W.Settle()
    Separate(W)
    W.LeaveCombat()
    W.Settle()
    Merged(W)
    Clean(W)
end

do
    local W = Ready(false, true)
    local openBag = OpenBag
    OpenBag = function(bag)
        assert(W.secure or not W.combat, "backpack-only combat opening called OpenBag from Suite")
        openBag(bag)
    end
    W.EnterCombat()
    W.OpenBags()
    W.Settle()
    assert(not W.Reagent:IsShown() and not W.P.ReagentInventory.active,
        "backpack-only combat opening activated the unopened reagent bag")
    assert(#W.P.InventoryView.index.items == 8, "backpack-only combat opening exposed reagent slots")
    Clean(W)

    W.Native(OpenBag, Enum.BagIndex.ReagentBag)
    W.Settle()
    Merged(W)
    Clean(W)
end

do
    local W = Ready(false, true)
    W.EnterCombat()
    W.Native(OpenBag, Enum.BagIndex.ReagentBag)
    local button = W.Reagent.Items[1]
    W.modified = "SPLITSTACK"
    W.Native(button:GetScript("OnClick"), button, "LeftButton")
    W.modified = nil
    assert(W.StackSplitFrame:IsShown() and W.StackSplitFrame.owner == button, "native reagent split setup failed")
    W.Search(function(item) return item.id == 101 end)
    W.OpenBags()
    W.Settle()
    assert(W.StackSplitFrame:IsShown() and W.StackSplitFrame.owner == button, "combat merge closed the native reagent split")
    Separate(W)

    W.LeaveCombat()
    W.Settle()
    assert(W.StackSplitFrame:IsShown() and W.StackSplitFrame.owner == button, "combat end closed the native reagent split")
    Separate(W)

    W.Search(nil)
    W.Settle()
    Separate(W)
    W.Native(W.StackSplitFrame.Hide, W.StackSplitFrame)
    W.Settle()
    Merged(W)
    Clean(W)
end

print("reagent integration: native slots, views, search, counts, replacement, restore and combat passed")

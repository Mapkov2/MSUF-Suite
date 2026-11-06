local root,client=assert(arg[1]),arg[2] or "Mainline"
local H=dofile(root.."/tools/tests/suite_bags_harness.lua")
local secret={}
local function World(class)
    local W=H.New(root,{client=client,catalogPresentation=true,unprotectedBags=true,
        isSecret=function(v) return v==secret end,config={inventoryView=3,showRecent=false}})
    UnitClass=function() return "Class","CLASS",class end
    local gear={
        {101,4,1,"INVTYPE_CHEST"},{102,4,4,"INVTYPE_CHEST"},{103,4,2,"INVTYPE_CHEST"},
        {104,2,7,"INVTYPE_WEAPON"},{105,2,10,"INVTYPE_2HWEAPON"},{106,4,6,"INVTYPE_SHIELD"},
        {107,4,0,"INVTYPE_NECK"},{108,4,1,"INVTYPE_CLOAK"},{109,0,0,""},
        {110,4,5,"INVTYPE_CHEST"},{111,4,1,"INVTYPE_HEAD"},{112,4,0,"INVTYPE_BODY"},
        {113,15,0,"INVTYPE_TRINKET"},
    }
    W.sizes[0]=20
    for i,g in ipairs(gear) do W.Define(g[1],{name="Gear "..g[1],class=g[2],subclass=g[3],equipLoc=g[4],level=100});W.Put(0,i,g[1],1) end
    W.useQueries,W.trained,W.level=0,true,1
    C_PlayerInfo.CanUseItem=function(id)
        W.useQueries=W.useQueries+1
        if id==111 then return W.level>=50 end
        if id==105 then return class==5 and W.trained end
        if id==104 or id==106 then return class==2 end
        return true
    end
    W.Apply();W.OpenBags();W.Settle()
    return W
end
local function IDs(W)
    local group=assert(W.P.InventoryView.model.groupsByKey.myArmorSlot,"My Armor Slot category missing")
    local ids={};for _,row in ipairs(group.rows) do ids[row.item.itemID]=true end
    return ids,group
end
for _,class in ipairs({5,2}) do
    local W=World(class);local ids,group=IDs(W)
    assert(W.S.catalog.bags.rules.category_myArmorSlot.default==true,"new category not available by default")
    assert(ids[107] and ids[108] and ids[112],"wearable accessories/cloak/shirt omitted")
    assert(not ids[109] and not ids[110] and not ids[111] and not ids[113],"consumable/cosmetic/level-restricted item included")
    if class==5 then assert(ids[101] and ids[105] and not ids[102] and not ids[103] and not ids[104] and not ids[106],"priest armor/weapon eligibility")
    else assert(ids[102] and ids[104] and ids[106] and not ids[101] and not ids[103] and not ids[105],"paladin armor/weapon eligibility") end
    assert(#group.displayRows==0,"new filter duplicates native items in All")
    local queries=W.useQueries
    W.Fire("BAG_UPDATE_DELAYED");W.Settle()
    assert(W.useQueries==queries,"unchanged gear repeatedly queries client usability")
    local V=W.P.InventoryView;local parents={}
    for _,item in ipairs(V.index.items) do parents[item.button]=item.button:GetParent() end
    V.selected="myArmorSlot";V.Request();W.Settle()
    for button in pairs(V.visibleButtons) do
        local item=V.slotState[button].row.item
        assert(ids[item.itemID] and button:GetParent()==parents[button],"filter changes native item ownership/content")
    end
    W.S.Set("bags","showUpgradeMarker",true);W.Settle()
    for _,item in ipairs(V.index.items) do
        if item.itemID==113 then assert(item.beatsEquipped,"shared category predicate removes legacy upgrade eligibility") end
    end
    queries=W.useQueries;W.Fire("BAG_UPDATE_DELAYED");W.Settle()
    assert(W.useQueries==queries,"upgrade marker bypasses shared gear cache")
    W.S.Set("bags","showUpgradeMarker",false);W.Settle()
    W.S.Set("bags","category_myArmorSlot",false);W.Settle()
    assert(not V.model.groupsByKey.myArmorSlot,"category switch ignored")
    assert(not W.P.PlayerGear.listening,"disabled matching retains eligibility events")
    W.S.Set("bags","category_myArmorSlot",true);W.Settle()
    assert(V.model.groupsByKey.myArmorSlot,"reenable loses category")
    assert(#W.errors==0 and #W.taint==0 and #W.combatLayout==0,"gear category native error")
end
do
    local W=World(5)
    W.trained=false;W.Fire("SKILL_LINES_CHANGED");W.Settle();local ids=IDs(W)
    assert(not ids[105],"unlearned weapon remains eligible")
    W.trained=true;W.Fire("SPELLS_CHANGED");W.Settle();ids=IDs(W)
    assert(ids[105],"trained weapon not refreshed while upgrade marker is off")
    W.trained=false;W.Fire("PLAYER_EQUIPMENT_CHANGED",16);W.Settle();ids=IDs(W)
    assert(not ids[105],"equipment-granted proficiency not refreshed")
    W.trained=true;W.Fire("PLAYER_SPECIALIZATION_CHANGED","player");W.Settle();ids=IDs(W)
    assert(ids[105],"specialization eligibility not refreshed")
    local revision=W.P.PlayerGear.revision
    W.Fire("PLAYER_SPECIALIZATION_CHANGED","party1");W.Settle()
    assert(W.P.PlayerGear.revision==revision,"unrelated specialization invalidates local gear")
    W.level=50;W.Fire("PLAYER_LEVEL_UP",50);W.Settle();ids=IDs(W)
    assert(ids[111],"level requirement not refreshed")
    C_PlayerInfo.CanUseItem=function() return secret end
    W.Fire("UPDATE_FACTION");W.Settle()
    assert(not W.P.InventoryView.model.groupsByKey.myArmorSlot,"secret usability accepted")
    W.S.Set("bags","enabled",false);W.Settle()
    assert(not W.P.PlayerGear.listening,"disable retains player gear events")
end
do
    local W=World(5);W.S.Set("bags","showUpgradeMarker",true);W.Settle()
    local item={itemID=101,link="item:101",equipLoc="INVTYPE_CHEST",classID=4,subclassID=1,itemLevel=100,loaded=false}
    W.P.UpgradeMarker.Read(item)
    assert(not item.beatsEquipped,"unloaded gear claimed as an upgrade")
    item.loaded=true;W.P.UpgradeMarker.Read(item)
    assert(item.beatsEquipped,"loaded metadata retains cached unknown eligibility")
end
print("Character armor/weapon eligibility, alias projection and cache passed: "..client)

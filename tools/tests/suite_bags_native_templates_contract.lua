local root = assert(arg[1])
local H = dofile(root .. "/tools/tests/suite_bags_harness.lua")
local flavor = arg[2] or "Mainline"
KEYRING_CONTAINER, KEYRING = -2, "Schlüsselbund"
C_ActionBar = { ShouldShowKeyring = function() return true end }
local W = H.New(root, {client=flavor,catalogPresentation=true,config={desaturateInactiveQuestItems=false}})
W.sizes[0], W.sizes[1], W.sizes[5] = 8, 4, 8
W.Define(101, { name = "Inactive quest item", class = Enum.ItemClass.Questitem })
W.Put(0,1,101,1)
local unlocked, nativeClicks = false, 0
GetKeyRingSize = function() return W.sizes[KEYRING_CONTAINER] or 0 end
local containerSize = C_Container.GetContainerNumSlots
C_Container.GetContainerNumSlots = function(bag)
    if bag == KEYRING_CONTAINER then return 0 end
    return containerSize(bag)
end
GetCVarBool = function(name) return name == "showKeyring" and unlocked end
local nativeBar = W.NewWidget("Frame", nil, W.UIParent, true)
nativeBar:Hide()
local nativeKeyring = W.NewWidget("Button", "KeyRingButton", nativeBar, true)
nativeKeyring:SetScript("OnClick", function()
    W.Taint("keyring opened through insecure input")
    nativeClicks = nativeClicks + 1
end)
W.Apply()
W.OpenBags()
W.Settle()
local E = W.P.EquippedBags
E.Toggle()
W.Settle()
assert(E.frame:IsVisible() and #E.buttons==5, "intrinsic equipped slots missing")
for _, button in ipairs(E.buttons) do
    assert(button.kind=="ItemButton" and button.icon and button.Count and button.Count:GetFont(), "intrinsic item fields/font missing")
end
if flavor == "Forever" then
    local keyring = assert(E.keyring, "Forever drawer is missing its keyring icon")
    assert(not keyring:IsShown(), "locked keyring is visible")
    unlocked = true
    local nativeSlots = #W.CF.Items
    W.sizes[KEYRING_CONTAINER] = 2
    W.Define(201, { name = "Ancient key" })
    W.Put(KEYRING_CONTAINER, 1, 201)
    W.Fire("BAG_UPDATE_DELAYED")
    W.Settle()
    assert(keyring:IsVisible() and not nativeKeyring:IsVisible(), "keyring is inaccessible with Blizzard's bar hidden")
    local view = W.P.InventoryView
    local mouseGroup = assert(view.model.groupsByKey.keyring, "mouse keyring did not appear in the Suite view")
    local item = mouseGroup.rows[1].item
    local mouseButton = item.button
    assert(mouseGroup.label == KEYRING and #mouseGroup.rows == 2 and #W.CF.Items == nativeSlots,
        "mouse keyring changed the native bag list or lost physical slots")
    assert(mouseButton:IsVisible() and item.itemID == 201 and mouseButton:GetAttribute("bagid") == KEYRING_CONTAINER
        and mouseButton:GetID() == 1 and mouseButton:HasItem(), "mouse key lost its native button identity")
    assert(view.index.free == 11, "mouse keyring inflated regular free slots")
    W.Native(mouseButton:GetScript("OnClick"), mouseButton, "LeftButton")
    assert(W.calls.pickups[#W.calls.pickups][1] == KEYRING_CONTAINER and W.calls.pickups[#W.calls.pickups][2] == 1,
        "native keyring click used the wrong bag slot")
    W.Native(C_Container.PickupContainerItem, KEYRING_CONTAINER, 1)
    W.Fire("BAG_UPDATE", KEYRING_CONTAINER)
    W.Fire("BAG_UPDATE_DELAYED")
    W.Settle()
    local reads = W.calls.info
    view.Request()
    W.Settle()
    assert(W.calls.info == reads, "an unchanged keyring reread its slots")
    W.Item(KEYRING_CONTAINER, 1).locked = true
    W.Fire("ITEM_LOCK_CHANGED", KEYRING_CONTAINER, 1)
    W.Settle()
    assert(mouseButton.desaturatedState and W.calls.info == reads + 1, "keyring lock did not refresh exactly one cached slot")
    W.Fire("ITEM_LOCK_CHANGED", 0, 1)
    W.Settle()
    assert(W.calls.info == reads + 1, "ordinary locks caused a repaint with quest desaturation off")
    W.Item(KEYRING_CONTAINER, 1).locked = false
    W.Fire("ITEM_LOCK_CHANGED", KEYRING_CONTAINER, 1)
    W.Settle()
    local search = view.smartSearch
    search:SetText("Ancient key")
    search:GetScript("OnTextChanged")(search)
    W.Settle()
    assert(#view.model.groupsByKey.keyring.rows == 1, "smart search did not filter the keyring")
    search:SetText("")
    search:GetScript("OnTextChanged")(search)
    W.Settle()
    W.RunScript(keyring, "OnEnter")
    local delegate
    for _, frame in ipairs(W.frames) do
        if frame:GetAttribute("clickbutton") == nativeKeyring then delegate = frame end
    end
    assert(delegate and delegate:IsShown() and delegate:GetParent() == W.UIParent, "secure keyring delegate is missing")
    assert(GameTooltip.lines[1] == KEYRING, "keyring tooltip must use the client's label")
    W.SecureClick(delegate)
    assert(nativeClicks == 1, "keyring click did not go to Blizzard")
    E.Toggle()
    assert(not delegate:IsShown(), "keyring delegate survived closing the drawer")
    E.Toggle()
    W.Settle()
    W.RunScript(keyring, "OnEnter")
    assert(delegate:IsShown(), "keyring delegate did not reopen")
    W.EnterCombat()
    assert(not delegate:IsShown() and delegate:GetNumPoints() == 0, "keyring delegate survived the combat transition")
    assert(not mouseButton:IsShown(), "owned keyring slots survived the protected combat transition")
    W.LeaveCombat()
    W.Settle()

    -- Gamepad's combined container already owns native keyring buttons.
    W.S.GamepadUI = function() return true end
    E.Toggle()
    W.Settle()
    assert(not keyring:IsShown(), "gamepad has its own keyring in the combined container")
    local first, second = W.CF.Items[1], W.CF.Items[2]
    first:Initialize(W.CF, KEYRING_CONTAINER, 2)
    second:Initialize(W.CF, KEYRING_CONTAINER, 1)
    W.sizes[KEYRING_CONTAINER] = 2
    W.Put(KEYRING_CONTAINER, 1, 201)
    W.Native(W.CF.UpdateItems, W.CF)
    W.Native(W.CF.UpdateItemLayout, W.CF)
    W.Settle()
    assert(not mouseButton:IsShown(), "gamepad duplicated an owned mouse keyring slot")
    local group = assert(view.model.groupsByKey.keyring, "native keyring slots did not get their own section")
    assert(group.label == KEYRING and #group.rows == 2, "keyring section is missing its native slots")
    assert(group.rows[1].item.button == second and group.rows[1].item.bag == KEYRING_CONTAINER, "keyring lost its slot identity")
    assert(view.index.free == 9, "keyring inflated the normal bag free space")
else
    assert(not E.keyring and not W.P.KeyringInventory, "keyring support must stay exclusive to Forever")
end
local ok, message = pcall(CreateFrame, "ItemButton", nil, nil, "ItemButtonTemplate")
assert(not ok and message:find("couldn't find inherited node",1,true), "fixture silently accepts invented template")
W.P.InventoryEditor.Show()
assert(W.P.InventoryEditor.frame:IsShown(), "category editor template path failed")
W.P.InventoryEditor.Hide()
W.P.BagFinance.Show()
assert(W.P.BagFinance.window:IsShown(), "gold window template path failed")
W.P.BagFinance.window:Hide()
W.S.Set("bags","enabled",false)
W.Settle()
assert(#W.errors==0 and #W.taint==0 and #W.combatLayout==0, "template startup error/taint")
print("Strict client templates and intrinsic ItemButton boot/drawer/tools passed: "..(arg[2] or "Mainline"))

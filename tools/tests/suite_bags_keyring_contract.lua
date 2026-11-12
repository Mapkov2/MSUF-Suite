-- WoW Forever's mouse keyring in the Suite bag: the Suite's own
-- ContainerFrameItemButtonTemplate buttons must not glow as new store items
-- (the template shows BattlepayItemTexture until UpdateNewItem runs), must
-- end a key's new state when the bag closes, and must stay visible in combat
-- without taking clicks that would reach item use with the Suite's taint.
local root = assert(arg[1])
local H = dofile(root .. "/tools/tests/suite_bags_harness.lua")
local BAG = -2

local function World(unprotected)
    KEYRING_CONTAINER = BAG
    local W = H.New(root, { client = "Forever", catalogPresentation = true, unprotectedBags = unprotected,
        config = { desaturateInactiveQuestItems = false } })
    KEYRING = "Keyring"
    C_ActionBar.ShouldShowKeyring = function() return true end
    GetCVarBool = function(name) return name == "showKeyring" end
    GetKeyRingSize = function() return W.sizes[BAG] or 0 end
    local containerSize = C_Container.GetContainerNumSlots
    C_Container.GetContainerNumSlots = function(bag)
        if bag == BAG then return 0 end
        return containerSize(bag)
    end
    W.sizes[0], W.sizes[BAG] = 8, 3
    W.Define(201, { name = "Old key" })
    W.Define(202, { name = "New key" })
    W.Define(203, { name = "Combat key" })
    W.Put(BAG, 1, 201)
    W.Apply()
    W.OpenBags()
    W.Settle()
    return W
end

local function Keys(W)
    local group = assert(W.P.InventoryView.model.groupsByKey.keyring, "keyring section is missing")
    local buttons = {}
    for i = 1, #group.rows do buttons[group.rows[i].item.slot] = group.rows[i].item.button end
    return buttons, group
end

local function Glows(button)
    return button.BattlepayItemTexture:IsShown()
        or button.NewItemTexture:IsShown() and button.newitemglowAnim:IsPlaying()
end

-- A hardware click reaches OnClick only for a registered button.
local function HardwareClick(W, button, mouseButton)
    for _, registered in ipairs(button.clicks or {}) do
        if registered == mouseButton .. "Up" or registered == "AnyUp" then
            W.Native(button:GetScript("OnClick"), button, mouseButton)
            return true
        end
    end
    return false
end

local function Clickable(button)
    local clicks, drag = button.clicks or {}, button.drag or {}
    return clicks[1] == "LeftButtonUp" and clicks[2] == "RightButtonUp" and drag[1] == "LeftButton"
end

local function Unclickable(button)
    return #(button.clicks or {}) == 0 and #(button.drag or {}) == 0
end

local function AssertClean(W, label)
    assert(#W.errors == 0 and #W.taint == 0 and #W.combatLayout == 0,
        label .. ": " .. table.concat(W.errors, "; ") .. table.concat(W.taint, "; ")
        .. table.concat(W.combatLayout, "; "))
end

---------------------------------------------------------------- new-item state
do
    local W = World(true)
    local keys = Keys(W)
    assert(keys[1] and keys[2] and keys[3], "keyring slots are missing")
    for slot = 1, 3 do
        assert(keys[slot]:IsVisible(), "keyring slot " .. slot .. " is hidden")
        assert(not Glows(keys[slot]), "keyring slot " .. slot .. " glows as a new item")
    end

    -- A key that arrives with the bag open glows like Blizzard's own slots.
    W.newItems[BAG * 1000 + 2] = true
    W.Put(BAG, 2, 202)
    W.BagChanged(BAG)
    W.Settle()
    keys = Keys(W)
    assert(Glows(keys[2]) and keys[2].NewItemTexture:IsShown(), "a new key does not glow")
    assert(not keys[2].BattlepayItemTexture:IsShown(), "a new key glows as a store item")
    assert(not Glows(keys[1]) and not Glows(keys[3]), "old keys glow with the new one")

    -- Closing the bag ends the new state, as Blizzard's UpdateNewItemList.
    W.CloseBags()
    W.Settle()
    assert(not C_NewItems.IsNewItem(BAG, 2), "closing the bag kept the key new")
    W.OpenBags()
    W.Settle()
    keys = Keys(W)
    for slot = 1, 3 do
        assert(keys[slot]:IsVisible() and not Glows(keys[slot]), "reopened keyring slot " .. slot .. " still glows")
    end

    -- A hover ends it too, without a repaint.
    W.newItems[BAG * 1000 + 3] = true
    W.Put(BAG, 3, 203)
    W.BagChanged(BAG)
    W.Settle()
    keys = Keys(W)
    assert(Glows(keys[3]), "a second new key does not glow")
    W.Hover(keys[3])
    assert(not Glows(keys[3]) and not C_NewItems.IsNewItem(BAG, 3), "hovering kept the key new")
    AssertClean(W, "new-item state")
end

---------------------------------------------------------------- combat (stock, unprotected bags)
do
    local W = World(true)
    local keys = Keys(W)
    local key = keys[1]
    assert(Clickable(key), "keys take no clicks out of combat")
    W.EnterCombat()
    W.Settle()
    local view = W.P.InventoryView
    assert(view.layout == "suite", "combat left the Suite grid")
    keys = Keys(W)
    assert(keys[1] == key and key:IsVisible() and keys[2]:IsVisible() and keys[3]:IsVisible(),
        "keys are hidden in combat")
    for slot = 1, 3 do assert(Unclickable(keys[slot]), "keyring slot " .. slot .. " takes clicks in combat") end
    local uses, pickups = #W.calls.uses, #W.calls.pickups
    assert(not HardwareClick(W, key, "RightButton") and not HardwareClick(W, key, "LeftButton"),
        "a combat click reached a Suite key button")
    assert(#W.calls.uses == uses and #W.calls.pickups == pickups, "a combat click used or picked up a key")
    W.Hover(key)
    assert(W.GameTooltip:GetOwner() == key, "keys lost their tooltip in combat")

    -- A key looted during combat lockdown appears at once.
    W.Put(BAG, 2, 203)
    W.BagChanged(BAG)
    W.Settle()
    keys = Keys(W)
    assert(keys[2]:IsVisible() and keys[2]:HasItem() and Unclickable(keys[2]), "a key looted in combat is missing")

    W.LeaveCombat()
    W.Settle()
    keys = Keys(W)
    for slot = 1, 3 do assert(Clickable(keys[slot]), "keyring slot " .. slot .. " stays unclickable after combat") end
    assert(HardwareClick(W, key, "RightButton"), "a key click after combat did not reach Blizzard")
    local use = W.calls.uses[#W.calls.uses]
    assert(#W.calls.uses == uses + 1 and use[1] == BAG and use[2] == 1, "a key click after combat used the wrong slot")

    -- A bag first opened in combat shows the keyring too.
    W.CloseBags()
    W.Settle()
    W.EnterCombat()
    W.OpenBags()
    W.Settle()
    keys = Keys(W)
    assert(keys[1]:IsVisible() and Unclickable(keys[1]), "a bag opened in combat lost its keys")
    W.LeaveCombat()
    W.Settle()
    assert(Clickable(Keys(W)[1]), "keys opened in combat stay unclickable")
    AssertClean(W, "stock combat")
end

---------------------------------------------------------------- combat (protected bags: fallback layout)
do
    local W = World(false)
    local key = Keys(W)[1]
    W.EnterCombat()
    W.Settle()
    assert(W.P.InventoryView.layout == "combat", "protected bags did not use the combat layout")
    assert(key:IsVisible() and key:GetNumPoints() > 0 and Unclickable(key), "the combat layout lost the keys")
    W.BagChanged(BAG)
    W.Settle()
    W.LeaveCombat()
    W.Settle()
    assert(W.P.InventoryView.layout == "suite" and Clickable(key), "keys did not return after combat")
    AssertClean(W, "protected combat")
end

print("Forever keyring new-item state and combat visibility passed")

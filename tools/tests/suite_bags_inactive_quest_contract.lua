local root = assert(arg[1], "repository root required")
local Harness = dofile(root .. "/tools/tests/suite_bags_harness.lua")

local function Check(client)
    local secret = {}
    local W = Harness.New(root, { client = client, isSecret = function(value) return value == secret end,
        config = { showRecent = false, showItemLevel = false, showBindBadge = false, desaturateJunk = true } })
    local class, bind = Enum.ItemClass, Enum.ItemBind
    local view = W.NS.BagsView
    local states = {
        { isQuestItem = false, isActive = false },
        { isQuestItem = true, isActive = false },
        { isQuestItem = false, isActive = false, questID = 101 },
        { isQuestItem = false, isActive = false },
        { isQuestItem = false, isActive = false, questID = secret },
        { isQuestItem = false, isActive = false },
        { isQuestItem = false, isActive = false },
        { isQuestItem = false, isActive = false },
    }
    C_Container.GetContainerItemQuestInfo = function(_, slot)
        W.calls.quest = W.calls.quest + 1
        return states[slot]
    end
    W.sizes[0] = #states
    W.Define(1, { class = class.Questitem })
    W.Define(2, { class = class.Questitem })
    W.Define(3, { class = class.Questitem })
    W.Define(4, { class = class.Consumable })
    W.Define(5, { class = class.Questitem })
    W.Define(6, { bind = bind.Quest })
    W.Define(7, { class = class.Questitem, cached = false })
    W.Define(8, { quality = Enum.ItemQuality.Poor })
    for slot = 1, #states do W.Put(0, slot, slot) end

    local function Button(slot)
        for _, button in W.CF:EnumerateValidItems() do
            if button:GetID() == slot then return button end
        end
        error("missing slot " .. slot)
    end

    local function Gray(slot, expected, reason)
        assert((Button(slot).desaturatedState == true) == expected, client .. ": " .. reason)
    end

    W.Apply()
    W.OpenBags()
    W.Settle()
    Gray(1, true, "inactive quest item must be gray by default")
    Gray(2, false, "active objective without a starter ID must stay colored")
    Gray(3, false, "quest starter must stay colored")
    Gray(4, false, "ordinary item must stay colored")
    Gray(5, false, "unreadable quest ID must stay colored")
    Gray(6, true, "quest binding must work outside the quest item class")
    Gray(7, false, "uncached quest item must stay colored until its metadata arrives")

    local reads = W.calls.quest
    W.data[7].cached = true
    W.Fire("GET_ITEM_INFO_RECEIVED", 7, true)
    W.Settle()
    Gray(7, true, "item metadata must repaint the slot")
    assert(W.calls.quest == reads, "item metadata refresh reread quest state")

    states[2].isQuestItem = false
    W.Fire("QUEST_REMOVED", 101)
    W.Settle()
    Gray(2, true, "abandoning a quest must repaint without a bag update")
    states[2].isQuestItem = true
    W.Fire("QUEST_ACCEPTED", 101)
    W.Native(function() W.CF:UpdateItems() end)
    W.Settle()
    Gray(2, false, "accepting the quest again must restore the color")

    -- Blizzard's lock-only refresh clears the icon tint independently of UpdateItems.
    SetItemButtonDesaturated(Button(1), false)
    W.Fire("ITEM_LOCK_CHANGED", 0, 1)
    W.Settle()
    Gray(1, true, "unlocking an inactive quest item must preserve its tint")

    assert(W.S.Set("bags", "inventoryView", view.BY_BAG))
    W.Settle()
    Gray(1, true, "By bag must use the same tint")
    assert(W.S.Set("bags", "inventoryView", view.CATEGORIES))
    W.Settle()
    Gray(1, true, "Categories must use the same tint")
    W.Item(0, 4).locked = true
    W.BagChanged(0)
    W.Settle()
    assert(W.S.Set("bags", "desaturateInactiveQuestItems", false))
    W.Settle()
    local events = W.P.InventoryView.events
    assert(not events:IsEventRegistered("QUEST_REMOVED") and not events:IsEventRegistered("ITEM_LOCK_CHANGED"),
        "disabling the tint must unregister its view events")
    Gray(1, false, "turning off the option must clear the tint immediately")
    Gray(4, true, "a locked slot must remain gray")
    Gray(8, true, "the separate junk setting must remain in effect")
    assert(W.S.Set("bags", "desaturateInactiveQuestItems", true))
    W.Settle()
    Gray(1, true, "turning the option back on must restore the tint")
    assert(W.S.Set("bags", "inventoryView", view.BLIZZARD_GRID))
    W.Settle()
    Gray(1, false, "handing the grid back to Blizzard must restore its tint")
end

Check("Mainline")
Check("Forever")
print("inactive quest items passed on Mainline and Forever")

-- A fight with every bag window closed costs the Bags nothing: no Bags code
-- runs for the events of that fight (CombatIdle.lua). Measured with a line
-- hook over every MSUF_Suite_Bags source, with all listening features on,
-- in the stock (unprotected) and the protected bag model. What changed
-- during the pause shows once a window opens, in combat or after it: bag and
-- keyring contents, the gold history and the session gold.
local root, client = assert(arg[1]), arg[2] or "Mainline"
local H = dofile(root .. "/tools/tests/suite_bags_harness.lua")
local forever = client == "Forever"
local KEYRING = -2

local STREAM = {
    { "BAG_UPDATE", 0 }, { "BAG_UPDATE_DELAYED" }, { "ITEM_LOCK_CHANGED", 0, 1 }, { "ITEM_LOCK_CHANGED", KEYRING, 1 },
    { "BAG_UPDATE_COOLDOWN" }, { "GET_ITEM_INFO_RECEIVED", 101, true }, { "ITEM_DATA_LOAD_RESULT", 101, true },
    { "PLAYER_MONEY" }, { "CURRENCY_DISPLAY_UPDATE" }, { "PLAYER_EQUIPMENT_CHANGED", 16 },
    { "UNIT_QUEST_LOG_CHANGED", "player" }, { "QUEST_ACCEPTED" }, { "QUEST_REMOVED" }, { "CURSOR_CHANGED" },
    { "INVENTORY_SEARCH_UPDATE" }, { "BAG_CONTAINER_UPDATE" }, { "SPELLS_CHANGED" }, { "SKILL_LINES_CHANGED" },
    { "UPDATE_FACTION" }, { "PLAYER_LEVEL_UP" }, { "EQUIPMENT_SETS_CHANGED" }, { "UNIT_INVENTORY_CHANGED", "player" },
}

local function S_MONEY(amount) return _G.MSUFSuite.Suite.MoneyText(amount) end

local function World(unprotected)
    if forever then KEYRING_CONTAINER = KEYRING end
    local W = H.New(root, { client = client, catalogPresentation = true, unprotectedBags = unprotected,
        config = { inventoryView = 3, showUpgradeMarker = true, category_myArmorSlot = true, showGoldHistory = true,
            showSessionGold = true, showItemLevel = true, showBindBadge = true } })
    if forever then
        _G.KEYRING = "Keyring"
        C_ActionBar.ShouldShowKeyring = function() return true end
        GetCVarBool = function(name) return name == "showKeyring" end
        GetKeyRingSize = function() return W.sizes[KEYRING] or 0 end
        local containerSize = C_Container.GetContainerNumSlots
        C_Container.GetContainerNumSlots = function(bag)
            if bag == KEYRING then return 0 end
            return containerSize(bag)
        end
        W.sizes[KEYRING] = 4
    end
    W.sizes[0], W.sizes[1] = 16, 20
    for i = 1, 30 do W.Define(100 + i, { name = "Item " .. i, maxStack = 20 }) end
    for i = 1, 16 do W.Put(0, i, 100 + i, 5) end
    for i = 1, 10 do W.Put(1, i, 116 + i, 5) end
    W.Define(900, { name = "Old key" })
    W.Define(901, { name = "Combat key" })
    W.Define(950, { name = "Combat loot" })
    -- Equipment makes the upgrade marker answer (and settle) before the
    -- fight; a late item keeps an item level badge waiting for its data.
    W.Define(940, { name = "Worn-out chest", equipLoc = "INVTYPE_CHEST", level = 500, class = 4 })
    W.Define(960, { name = "Late chest", equipLoc = "INVTYPE_CHEST", level = 510, class = 4, cached = false })
    W.Put(1, 15, 940, 1)
    W.Put(1, 16, 960, 1)
    if forever then W.Put(KEYRING, 1, 900) end
    W.Apply()
    W.OpenBags()
    W.Settle()
    W.CloseBags()
    W.Settle()
    return W
end

-- Lines executed in MSUF_Suite_Bags files while fn runs.
local function BagsLines(fn)
    local lines, files = 0, {}
    debug.sethook(function()
        local source = debug.getinfo(2, "S").source
        if source:find("MSUF_Suite_Bags", 1, true) then
            lines = lines + 1
            files[source:match("MSUF_Suite_Bags[/\\]([^/\\]+)$") or source] = true
        end
    end, "l")
    fn()
    debug.sethook()
    local names = {}
    for name in pairs(files) do names[#names + 1] = name end
    table.sort(names)
    return lines, table.concat(names, ", ")
end

local function Fight(W)
    for i = 1, #STREAM do W.Fire(unpack(STREAM[i])) end
    W.Settle()
end

local function Shows(W, itemID)
    local items = W.P.InventoryView.index.items
    for i = 1, #items do
        if items[i].itemID == itemID and items[i].button:IsVisible() then return true end
    end
    return false
end

local function TodayEarned(W)
    local record = W.NS.GoldLedger.Characters()[UnitGUID("player")]
    local days = record and record.days
    return days and days[#days] and days[#days].earned or 0
end

-- Every frame registered for an event, as "event frame" keys.
local function Registrations(W)
    local set = {}
    for event, frames in pairs(W.events) do
        for i = 1, #frames do set[event .. " " .. tostring(frames[i])] = true end
    end
    return set
end

local function SameRegistrations(before, after)
    for key in pairs(before) do if not after[key] then return false, "lost " .. key end end
    for key in pairs(after) do if not before[key] then return false, "gained " .. key end end
    return true
end

local function AssertClean(W, label)
    assert(#W.errors == 0 and #W.taint == 0 and #W.combatLayout == 0, label .. ": "
        .. table.concat(W.errors, "; ") .. table.concat(W.taint, "; ") .. table.concat(W.combatLayout, "; "))
end

for _, unprotected in ipairs({ true, false }) do
    local label = (unprotected and "stock" or "protected") .. " bags, " .. client
    local W = World(unprotected)
    assert(not W.P.UpgradeMarker.dirty, label .. ": the upgrade marker never settled before the fight")
    assert(forever or W.M.pending[960], label .. ": no item level badge waits for item data")
    local registered = Registrations(W)
    local gearRevision = W.P.PlayerGear.revision
    local goldBefore = W.M.windows[W.CF].goldLabel:GetText()
    W.EnterCombat()
    W.Settle()
    assert(W.P.BagsIdle.paused, label .. ": a fight with the bags closed did not pause them")

    -- The fight itself: loot, money, equipment, quests, reputation.
    local earned = TodayEarned(W)
    W.money = W.money + 4321
    W.Put(1, 11, 950, 3)
    if forever then W.Put(KEYRING, 2, 901) end
    W.data[960].cached = true
    local lines, files = BagsLines(function()
        Fight(W)
        W.Fire("GET_ITEM_INFO_RECEIVED", 960, true)
        W.Settle()
    end)
    assert(lines == 0, label .. ": closed bags ran " .. lines .. " lines in combat (" .. files .. ")")

    W.LeaveCombat()
    W.Settle()
    assert(not W.P.BagsIdle.paused, label .. ": the fight's end did not wake the bags")
    local same, change = SameRegistrations(registered, Registrations(W))
    assert(same, label .. ": waking did not restore the event registrations: " .. tostring(change))
    assert(TodayEarned(W) == earned + 4321, label .. ": the gold history lost the fight's income")
    local gold = W.M.windows[W.CF].goldLabel:GetText()
    assert(gold ~= goldBefore and gold:find(S_MONEY(4321), 1, true), label .. ": session gold not repainted: "
        .. tostring(goldBefore) .. " -> " .. tostring(gold))
    assert(W.P.PlayerGear.revision > gearRevision and W.P.UpgradeMarker.dirty,
        label .. ": equipment answers from before the fight were kept")
    W.OpenBags()
    W.Settle()
    assert(Shows(W, 950), label .. ": loot from the fight is missing")
    assert(not W.M.pending[960], label .. ": a badge still waits for data that arrived in the fight")
    if forever then assert(Shows(W, 901), label .. ": a key from the fight is missing") end

    -- Awake again: an open bag follows its events, also in combat.
    W.CloseBags()
    W.Settle()
    W.EnterCombat()
    W.Settle()
    W.Put(1, 12, 101, 1)
    W.BagChanged(1)
    W.OpenBags()
    W.Settle()
    assert(not W.P.BagsIdle.paused, label .. ": opening the bag in combat left it paused")
    if unprotected then
        assert(Shows(W, 101) and W.Item(1, 12), label .. ": a bag opened in combat shows stale contents")
        W.Put(1, 13, 102, 1)
        W.BagChanged(1)
        W.Settle()
        assert(Shows(W, 102), label .. ": an open bag stopped following its contents in combat")
    end
    W.CloseBags()
    W.Settle()
    assert(W.P.BagsIdle.paused, label .. ": closing the last window in combat did not pause")
    lines, files = BagsLines(function() Fight(W) end)
    assert(lines == 0, label .. ": closed bags ran " .. lines .. " lines after a reopen (" .. files .. ")")
    -- Any read while paused resumes the slot cache with every container stale.
    W.Put(1, 14, 103, 1)
    local Slots = W.P.SlotCache
    Slots.Sync(1)
    local info = Slots.Get(1, 14)
    assert(not Slots.paused and info and info.itemID == 103, label .. ": a read while paused returned stale slots")

    -- An open bank keeps the Bags awake.
    W.LeaveCombat()
    W.Settle()
    W.OpenBank()
    W.EnterCombat()
    W.Settle()
    assert(not W.P.BagsIdle.paused, label .. ": an open bank window was paused")
    W.CloseBank()
    W.Settle()
    assert(W.P.BagsIdle.paused, label .. ": closing the bank in combat did not pause")
    W.LeaveCombat()
    W.Settle()
    AssertClean(W, label)
end

print("Bags run no code in a fight with every window closed, and catch up afterwards: " .. client)

-- Delete cheapest item (MSUF_Suite_QualityOfLife/CheapestItem.lua) in the
-- client model of suite_bags_harness.lua, with the FULL Bags TOC loaded and
-- the Quality of Life files the module uses:
--   * which stacks are offered and in which order (vendor value of the whole
--     stack; quality limit, quest, lock, price, kept, equipment set, Never
--     sell items, refund);
--   * a delete takes exactly the offered stack, asks first above Poor or when
--     asked to, and refuses a changed slot, a busy cursor or a closed bag;
--   * where the button is: beside Filters in the Suite Bags views (which give
--     it the search box's room back when the module stops), on the title of
--     Blizzard's bag window otherwise, left of the Suite caption under the
--     Suite Bags Blizzard grid;
--   * no line of CheapestItem.lua runs during combat or an ordinary bag
--     refresh: only the combat edges and the player's own hover and clicks.
local root, flavor = assert(arg[1]), arg[2] or "Mainline"
local Harness = dofile(root .. "/tools/tests/suite_bags_harness.lua")
local SOURCE = "CheapestItem.lua"
local QUESTION = "suite-delete-cheapest-item"

-- Item IDs: Poor 5c, Poor 3c x4 (12c), Poor 9c, Common 1c, then the stacks
-- that must never be offered.
local FANG, CLOTH, BONE, LINEN = 401, 402, 403, 404
local NO_PRICE, QUEST, KEPT, SET, REFUND, RARE, LOCKED, GUARDED = 405, 406, 407, 408, 409, 410, 411, 412

local function Items(W)
    W.sizes[0], W.sizes[1] = 12, 8
    W.Define(FANG, { name = "Broken Fang", quality = 0, sellPrice = 5, maxStack = 20 })
    W.Define(CLOTH, { name = "Torn Cloth", quality = 0, sellPrice = 3, maxStack = 20 })
    W.Define(BONE, { name = "Cracked Bone", quality = 0, sellPrice = 9 })
    W.Define(LINEN, { name = "Linen Scrap", quality = 1, sellPrice = 1, maxStack = 200 })
    W.Define(NO_PRICE, { name = "Hearthstone", quality = 1, sellPrice = 0 })
    W.Define(QUEST, { name = "Quest Rag", quality = 0, sellPrice = 1 })
    W.Define(KEPT, { name = "Lucky Pebble", quality = 0, sellPrice = 1 })
    W.Define(SET, { name = "Fishing Hat", quality = 0, sellPrice = 1, equipLoc = "INVTYPE_HEAD" })
    W.Define(REFUND, { name = "Fresh Purchase", quality = 0, sellPrice = 1 })
    W.Define(RARE, { name = "Shiny Ring", quality = 3, sellPrice = 1, equipLoc = "INVTYPE_FINGER" })
    W.Define(LOCKED, { name = "Traded Rag", quality = 0, sellPrice = 1 })
    W.Define(GUARDED, { name = "Old Coin", quality = 0, sellPrice = 1 })
    W.Put(0, 1, FANG, 1)
    W.Put(0, 2, CLOTH, 4)
    W.Put(1, 3, BONE, 1)
    W.Put(0, 4, LINEN, 1)
    W.Put(0, 5, NO_PRICE, 1)
    W.Put(0, 6, QUEST, 1, { quest = true })
    W.Put(0, 7, KEPT, 1)
    W.Put(0, 8, SET, 1)
    W.Put(0, 9, REFUND, 1, { refundable = true })
    W.Put(1, 1, RARE, 1)
    W.Put(1, 2, LOCKED, 1, { locked = true })
    W.Put(1, 4, GUARDED, 1)
    W.equipmentSets[1] = { name = "Fishing", locations = { 7001 } }
    W.locations[7001] = { isBags = true, bag = 0, slot = 8 }
end

-- Blizzard's side the module reads (ContainerFrame.lua, live and forever)
-- and the Suite dialogs, chat and the client's delete: recorded.
local function Client(W)
    ContainerFrameUtil_GetShownFrameForID = function(id)
        if W.CF.shown and (id == nil or id >= 0 and id <= 4) then return W.CF end
    end
    ContainerFrameUtil_GetItemButtonAndContainer = function(bag, slot)
        local container = ContainerFrameUtil_GetShownFrameForID(bag)
        if not container then return nil end
        for _, button in container:EnumerateValidItems() do
            if button:GetBagID() == bag and button:GetID() == slot then return button, container end
        end
    end
    C_Container.GetContainerItemPurchaseInfo = function(bag, slot)
        local item = W.Item(bag, slot)
        if item and item.refundable then return { refundSeconds = 3600, money = 500, itemCount = 0, currencyCount = 0 } end
    end
    W.questions, W.hidden, W.prints, W.deleted, W.menus = {}, {}, {}, {}, {}
    W.S.Confirm = function(key, data) W.questions[#W.questions + 1] = { key = key, data = data } end
    W.S.HideQuestion = function(key) W.hidden[#W.hidden + 1] = key end
    W.S.Print = function(text) W.prints[#W.prints + 1] = text end
    W.S.ContextMenu = function(owner, generator) W.menus[#W.menus + 1] = { owner = owner, generator = generator } end
    DeleteCursorItem = function()
        assert(not W.combat, "an item was deleted in combat lockdown")
        W.deleted[#W.deleted + 1] = W.cursor
        W.cursor = nil
    end
end

-- The Quality of Life files the module needs, and the controller's start.
local function QualityOfLife(W, config)
    assert(loadfile(root .. "/MSUF_Suite/Core/Catalog/InventoryTools.lua"))("MSUF_Suite", W.NS)
    local private = { NS = W.NS, Suite = W.S }
    for _, file in ipairs({ "SharedItems", "InventoryProtection", "CheapestItem" }) do
        W.Insecure(assert(loadfile(root .. "/MSUF_Suite_QualityOfLife/" .. file .. ".lua")), "MSUF_Suite_QualityOfLife", private)
    end
    -- Never sell items (Quality of Life) protects the Old Coin.
    local protection = W.S.InventoryProtection
    protection.active, protection.items = true, { [GUARDED] = 1 }
    local M = assert(W.S.CheapestItem, "CheapestItem.lua did not export its module")
    assert(W.S.instances.cheapestItem == M, "the module is not installed")
    M.config = { enabled = true, quality = W.NS.CheapestItemQuality.POOR, confirm = true, keep = tostring(KEPT) }
    for key, value in pairs(config or {}) do M.config[key] = value end
    local set = W.S.Set
    W.S.Set = function(id, key, value)
        if id ~= "cheapestItem" then return set(id, key, value) end
        if W.combat then return false end
        M.config[key] = value
        if M.active then M:Refresh() end
        return true
    end
    function W.StartTool()
        M.context = M.context or W.S.NewContext("cheapestItem")
        M.active = true
        W.Insecure(M.Enable, M)
    end
    function W.StopTool()
        M.active = false
        W.Insecure(M.Disable, M)
        M.context:Release()
    end
    return M
end

-- options.bags: the Bags settings (enabled = false: Blizzard's own bag);
-- options.tool: the module's settings; options.late: start it after the bag opened.
local function World(options)
    options = options or {}
    local W = Harness.New(root, { client = flavor, config = options.bags, unprotectedBags = options.unprotectedBags })
    Items(W)
    Client(W)
    W.C = QualityOfLife(W, options.tool)
    if not options.late then W.StartTool() end
    W.Apply()
    W.OpenBags()
    W.Settle()
    if options.late then
        W.StartTool()
        W.Settle()
    end
    W.V = W.P.InventoryView
    return W
end

local function IDs(list)
    local ids = {}
    for i = 1, #list do ids[i] = list[i].itemID end
    return table.concat(ids, ",")
end

local function Run(W, button, script, ...)
    W.Insecure(assert(button:GetScript(script), script), button, ...)
end

local function Listens(W, event)
    for _, frame in ipairs(W.events[event] or {}) do
        if frame.module == W.C then return true end
    end
    return false
end

-- Counts the lines of CheapestItem.lua that run inside fn.
local function LinesRun(fn)
    local count = 0
    debug.sethook(function()
        local info = debug.getinfo(2, "S")
        if info and info.source:find(SOURCE, 1, true) then count = count + 1 end
    end, "l")
    fn()
    debug.sethook()
    return count
end

-- A menu description that records what the generator builds.
local function MenuRoot()
    local methods = {}
    local function Add(parent, kind, text, callback)
        local child = setmetatable({ kind = kind, text = text, callback = callback, children = {} }, { __index = methods })
        parent.children[#parent.children + 1] = child
        return child
    end
    function methods:CreateTitle(text) return Add(self, "title", text) end
    function methods:CreateDivider() return Add(self, "divider") end
    function methods:CreateButton(text, callback) return Add(self, "button", text, callback) end
    function methods:SetTooltip(fn) self.tooltip = fn end
    function methods:SetScrollMode(extent) self.scroll = extent end
    return setmetatable({ children = {} }, { __index = methods })
end

local function OpenMenu(W, button)
    Run(W, button, "OnClick", "RightButton")
    local menu = assert(W.menus[#W.menus], "right-click opened no list")
    local list = MenuRoot()
    W.Insecure(menu.generator, menu.owner, list)
    return list
end

local function Find(node, text)
    for _, child in ipairs(node.children) do
        if child.text and child.text:find(text, 1, true) then return child end
    end
end

------------------------------------------------------------------ offer rules and Suite Bags placement
do
    local W = World()
    local C, V = W.C, W.V
    local tool = assert(V.cheapest, "Suite Bags did not show the tool beside Filters")
    assert(tool:IsShown() and C:Usable(), "the tool is missing from the open bag")
    local _, _, _, searchRight = V.smartSearch:GetPoint(2)
    local _, _, _, toolRight = tool:GetPoint(1)
    assert(searchRight == -132 and toolRight == -100, "the tool does not sit between search and Filters")
    for frame, native in pairs(C.natives) do
        assert(not native:IsShown(), "a title button showed beside the Suite view on " .. tostring(frame.name))
    end
    assert(IDs(C:Candidates(10)) == FANG .. "," .. BONE .. "," .. CLOTH,
        "Poor stacks by stack value, nothing protected: " .. IDs(C:Candidates(10)))
    W.S.Set("cheapestItem", "quality", W.NS.CheapestItemQuality.COMMON)
    assert(IDs(C:Candidates(10)) == LINEN .. "," .. FANG .. "," .. BONE .. "," .. CLOTH,
        "Common did not join the offer: " .. IDs(C:Candidates(10)))
    W.S.Set("cheapestItem", "quality", W.NS.CheapestItemQuality.UNCOMMON)
    assert(not IDs(C:Candidates(10)):find(tostring(RARE)), "a Rare item was offered")
    W.S.Set("cheapestItem", "quality", W.NS.CheapestItemQuality.POOR)
    assert(#C:Candidates(1) == 1 and C:Candidates(1)[1].itemID == FANG, "the limit was not kept")

    -- Kept item types leave the offer and come back.
    assert(C:Keep(FANG, true) and C.config.keep == FANG .. " " .. KEPT, "keeping an item type was not saved")
    assert(C:Candidates(1)[1].itemID == BONE, "a kept item type was still offered")
    assert(C:Keep(FANG, false) and C.config.keep == tostring(KEPT), "offering an item again failed")
    assert(C:Candidates(1)[1].itemID == FANG, "an item type offered again stayed away")

    -- Stopped: Suite Bags gives the search box its room back; nothing listens.
    W.StopTool()
    W.Settle()
    _, _, _, searchRight = V.smartSearch:GetPoint(2)
    assert(not tool:IsShown() and searchRight == -104, "the search box did not take the tool's room back")
    assert(not Listens(W, "PLAYER_REGEN_DISABLED") and not C:Usable(), "a stopped module still listened")
    W.StartTool()
    W.Settle()
    _, _, _, searchRight = V.smartSearch:GetPoint(2)
    assert(tool:IsShown() and searchRight == -132, "the tool did not come back")
    assert(Listens(W, "PLAYER_REGEN_DISABLED") and Listens(W, "PLAYER_REGEN_ENABLED"), "the combat edges are not watched")
    assert(not Listens(W, "BAG_UPDATE_DELAYED") and not Listens(W, "BAG_UPDATE"), "the module watches the bags unasked")
    assert(#W.taint == 0 and #W.errors == 0, "modeled native failure: " .. table.concat(W.taint, ", "))
end

------------------------------------------------------------------ hover, mark and deleting
do
    local W = World({ tool = { confirm = false } })
    local C, tool = W.C, W.V.cheapest
    Run(W, tool, "OnEnter")
    assert(W.GameTooltip:Has("Delete cheapest item") and W.GameTooltip:Has("item:" .. FANG), "the tooltip lacks the offer")
    assert(W.GameTooltip:Has("5c"), "the tooltip lacks the vendor value")
    local fangButton = ContainerFrameUtil_GetItemButtonAndContainer(0, 1)
    local mark = assert(C.marks[fangButton], "the offered slot is not marked")
    assert(mark[1]:IsShown() and #mark == 5, "the mark is incomplete")
    assert(Listens(W, "BAG_UPDATE_DELAYED"), "a hover does not follow bag changes")

    -- A plain click deletes the cheapest Poor stack at once.
    Run(W, tool, "OnClick", "LeftButton")
    assert(#W.questions == 0, "a Poor stack asked although asking is off")
    assert(#W.deleted == 1 and W.deleted[1].id == FANG and not W.Item(0, 1), "the cheapest stack was not deleted")
    assert(W.prints[1] and W.prints[1]:find("5c", 1, true), "the delete was not reported")
    W.Settle()
    W.Advance(.2)
    assert(W.GameTooltip:Has("item:" .. BONE), "the hover did not move on to the next stack")
    assert(not mark[1]:IsShown(), "the deleted slot kept its mark")
    Run(W, tool, "OnLeave")
    assert(not Listens(W, "BAG_UPDATE_DELAYED"), "leaving the button kept the bag watch")

    -- Above Poor the module always asks, and accepts only the unchanged stack.
    W.S.Set("cheapestItem", "quality", W.NS.CheapestItemQuality.COMMON)
    Run(W, tool, "OnClick", "LeftButton")
    local question = assert(W.questions[1], "a Common stack was deleted without asking")
    assert(question.key == QUESTION and question.data.text_arg1 == "item:" .. LINEN, "the question names the wrong stack")
    W.Put(0, 4, LINEN, 2)
    W.BagChanged(0)
    W.Settle()
    W.Insecure(question.data.callback)
    assert(#W.deleted == 1 and W.Item(0, 4).count == 2, "a stack that changed after the question was deleted")
    Run(W, tool, "OnClick", "LeftButton")
    W.Insecure(W.questions[2].data.callback)
    assert(#W.deleted == 2 and W.deleted[2].id == LINEN and W.deleted[2].count == 2, "the confirmed stack was not deleted")

    -- A busy cursor or a closed bag: nothing is deleted, nothing is picked up.
    local pickups = #W.calls.pickups
    W.cursor = { id = 999, link = "item:999", count = 1 }
    Run(W, tool, "OnClick", "LeftButton")
    assert(#W.deleted == 2 and #W.calls.pickups == pickups, "a delete ran with an item on the cursor")
    W.cursor = nil
    W.S.Set("cheapestItem", "confirm", true)
    Run(W, tool, "OnClick", "LeftButton")
    local pending = assert(W.questions[#W.questions], "no question for the next stack")
    W.CloseBags()
    W.Insecure(pending.data.callback)
    assert(#W.deleted == 2 and #W.calls.pickups == pickups, "a question deleted after the bag closed")
    assert(not C:Usable() and #C:Candidates(10) == 0, "the module offered stacks with the bag closed")
    assert(#W.taint == 0 and #W.errors == 0, "modeled native failure: " .. table.concat(W.taint, ", "))
end

------------------------------------------------------------------ the list
do
    local W = World()
    local C, tool = W.C, W.V.cheapest
    local menu = OpenMenu(W, tool)
    local entries = {}
    for _, child in ipairs(menu.children) do
        if child.kind == "button" and child.text:find("item:", 1, true) then entries[#entries + 1] = child end
    end
    assert(menu.children[1].kind == "title" and #entries == 3, "the list should hold the three Poor stacks, has " .. #entries)
    assert(entries[1].text:find("item:" .. FANG, 1, true) and entries[3].text:find("item:" .. CLOTH .. " x4", 1, true),
        "the list is not cheapest first")
    entries[1].tooltip(W.GameTooltip)
    assert(W.GameTooltip:Has("Broken Fang"), "a list entry shows no item tooltip")
    local kept = assert(Find(menu, "Never deleted (1)"), "the kept item types are missing")
    assert(kept.scroll and Find(kept, "Lucky Pebble"), "the kept list neither scrolls nor names its items")
    W.Insecure(Find(entries[2], "Never delete this item").callback)
    assert(C.config.keep == BONE .. " " .. KEPT, "keeping from the list failed: " .. C.config.keep)
    W.Insecure(Find(entries[1], "Delete").callback)
    W.Insecure(assert(W.questions[1], "asking is on, yet no question").data.callback)
    assert(#W.deleted == 1 and W.deleted[1].id == FANG, "deleting from the list failed")
    menu = OpenMenu(W, tool)
    W.Insecure(Find(Find(menu, "Never deleted (2)"), "Allow deleting all of them").callback)
    assert(C.config.keep == "" and IDs(C:Candidates(10)) == KEPT .. "," .. BONE .. "," .. CLOTH,
        "allowing all kept items failed: " .. IDs(C:Candidates(10)))
    assert(#W.taint == 0 and #W.errors == 0, "modeled native failure: " .. table.concat(W.taint, ", "))
end

------------------------------------------------------------------ Blizzard's bag window
do
    -- Without Suite Bags: on the title, left of Blizzard's close button.
    local W = World({ bags = { enabled = false } })
    local C = W.C
    local native = assert(C.natives[W.CF], "no button on Blizzard's bag window")
    local point, relative, _, x = native:GetPoint(1)
    assert(native:IsShown() and point == "TOPRIGHT" and relative == W.CF and x == -W.CF.CloseButton:GetWidth() - 2,
        "the title button is not left of the close button")
    assert(native:GetFrameLevel() > W.CF.CloseButton:GetFrameLevel(), "the title button sits below the window's art")
    assert(native:GetParent() == W.CF, "the title button is not in the bag window")
    Run(W, native, "OnEnter")
    assert(W.GameTooltip:Has("item:" .. FANG) and C.marks[ContainerFrameUtil_GetItemButtonAndContainer(0, 1)],
        "Blizzard's bag offers or marks nothing")
    Run(W, native, "OnLeave")
    W.CloseBags()
    assert(not native:IsShown() and not C:Usable(), "the title button stayed with the bag closed")
    W.OpenBags()
    assert(native:IsShown(), "the title button did not come back with the bag")
    W.StopTool()
    assert(not native:IsShown(), "a stopped module left its title button")
    assert(#W.taint == 0 and #W.errors == 0, "modeled native failure: " .. table.concat(W.taint, ", "))

    -- Suite Bags with Blizzard's grid: left of the Suite caption.
    local grid = World({ bags = { inventoryView = 4 } })
    native = assert(grid.C.natives[grid.CF], "no button on the Suite Bags Blizzard grid")
    point, relative, _, x = native:GetPoint(1)
    assert(native:IsShown() and x == -grid.S.BagsTitleInset(grid.CF) - 2 and x < -80,
        "the title button is not left of the Suite caption")
    assert(grid.C:Usable() and grid.C:Candidates(1)[1].itemID == FANG, "the Blizzard grid offers nothing")

    -- Started after the bag opened: Suite Bags lays its search row out again.
    local late = World({ late = true })
    assert(late.V.cheapest and late.V.cheapest:IsShown(), "a late start did not reach the Suite view")
    local _, _, _, searchRight = late.V.smartSearch:GetPoint(2)
    assert(searchRight == -132, "a late start left the search row as it was")
end

------------------------------------------------------------------ cost: background and combat
do
    -- Stock bags stay unprotected: the Suite layout and the button remain in combat.
    local W = World({ unprotectedBags = true })
    local C, tool = W.C, W.V.cheapest
    local idle = LinesRun(function()
        for _ = 1, 5 do
            W.Put(1, 5, LINEN, 1)
            W.BagChanged(1)
            W.Settle()
        end
    end)
    assert(idle == 0, "bag refreshes ran " .. idle .. " lines of the module without a hover")

    Run(W, tool, "OnEnter")
    Run(W, tool, "OnClick", "LeftButton")
    assert(W.questions[1], "no question before combat")
    W.EnterCombat()
    assert(not tool:IsEnabled() and W.hidden[#W.hidden] == QUESTION, "combat left the button usable or its question open")
    assert(not Listens(W, "BAG_UPDATE_DELAYED") and not W.GameTooltip.shown, "combat kept the hover alive")
    local fighting = LinesRun(function()
        for slot = 5, 8 do
            W.Put(1, slot, CLOTH, slot)
            W.BagChanged(1)
            W.Settle()
            W.Advance(1)
        end
    end)
    assert(fighting == 0, "combat ran " .. fighting .. " lines of the module")
    -- Opening and closing the bag in combat reaches the window hook's combat test only.
    local reopened = LinesRun(function()
        W.CloseBags()
        W.OpenBags()
        W.Settle()
    end)
    assert(reopened <= 4, "reopening the bag in combat ran " .. reopened .. " lines of the module")
    -- A stale question accepted in combat (its dialog was closed at the edge),
    -- and the player's own clicks: nothing happens.
    W.Insecure(W.questions[1].data.callback)
    Run(W, tool, "OnClick", "LeftButton")
    Run(W, tool, "OnClick", "RightButton")
    assert(#W.deleted == 0 and #W.menus == 0, "the module acted in combat")
    W.LeaveCombat()
    W.Settle()
    assert(tool:IsEnabled() and C:Usable(), "the button did not return after combat")
    assert(#W.taint == 0 and #W.combatLayout == 0, "modeled combat failure: " .. table.concat(W.combatLayout, ", "))
end

print("delete cheapest item: offer rules, delete safety, list, placements and zero combat cost passed (" .. flavor .. ")")

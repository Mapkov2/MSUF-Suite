local _, P = ...
local NS, S = P.NS, P.Suite
local Slots, Loads = P.SlotCache, P.ItemLoads
local Index = {}
P.InventoryIndex = Index
local KEY = Slots.KEY

function Index.New()
    return { items = {}, records = setmetatable({}, { __mode = "k" }), metadata = {},
        loads = Loads.New(2048), pending = {}, bagNames = {}, freshItems = {}, count = 0, revision = 0,
        buttons = {}, order = {}, filtered = 0 }
end

local function Metadata(index, link, itemID)
    local data = index.metadata[link]
    if data then return data end
    local name, _, _, _, _, _, subclassName, maxStack, equipLoc, _, _, classID, subclassID, _, expansion = C_Item.GetItemInfo(link)
    if not S.Public(name) or type(name) ~= "string" then
        -- At most 2048 items are asked for at once (ItemLoads.lua).
        if Loads.Request(index.loads, itemID) then index.pending[itemID] = true end
        return nil
    end
    data = { name = name, search = name:lower(), maxStack = S.Finite(maxStack) and maxStack or 1,
        classID = S.Finite(classID) and classID or nil,
        subclassID = S.Finite(subclassID) and subclassID or nil,
        subclassName = S.Public(subclassName) and subclassName or nil,
        equipLoc = S.Public(equipLoc) and equipLoc or nil,
        expansion = S.Finite(expansion) and expansion or nil }
    if data.equipLoc then data.slotName = _G[data.equipLoc] or data.equipLoc end
    if data.expansion then data.expansionName = _G["EXPANSION_NAME" .. data.expansion] end
    -- Cache only while the module is enabled; bounded even during long sessions.
    index.count = index.count + 1
    if index.count > 2048 then
        for key in pairs(index.metadata) do index.metadata[key] = nil end
        index.count = 1
    end
    index.metadata[link] = data
    return data
end

local METADATA = { "name", "search", "maxStack", "classID", "subclassID", "subclassName", "equipLoc",
    "slotName", "expansion", "expansionName" }

local function ApplyMetadata(index, item)
    local data = Metadata(index, item.link, item.itemID)
    if data then
        for i = 1, #METADATA do item[METADATA[i]] = data[METADATA[i]] end
        item.loaded = true
    else
        item.name, item.search, item.loaded = tostring(item.itemID), tostring(item.itemID), false
    end
end

------------------------------------------------------------------ recent items
-- Recent items belong to one character: RootDB.suiteBagRecent[guid], never a
-- profile, kept across reloads and logins. Each item type remembers when it
-- arrived (server time) and leaves the list once it is older than the
-- recentHours setting, so the list cannot grow into the categories for good;
-- Clear recent items empties it at once. Lists of other characters that only
-- hold expired items are dropped at load. Before the first world entry the
-- list lives in memory only.
local HOUR, DEFAULT_HOURS = 3600, 24
local session

local function Hours()
    local module = P.BagsModule
    local hours = module and module.config and module.config.recentHours
    return S.Finite(hours) and hours >= 1 and hours or DEFAULT_HOURS
end

local function Valid(record)
    return type(record) == "table" and type(record.items) == "table" and type(record.order) == "table"
        and type(record.dismissed) == "table"
end

-- Drops the item types that arrived before now - hours. order is the
-- arrival order, so only its front can expire.
function Index.ExpireRecent(recent, now, hours)
    local order, items = recent.order, recent.items
    local oldest = now - (hours or Hours()) * HOUR
    local first = 1
    for i = 1, #order do
        local arrived = items[order[i]]
        if not S.Finite(arrived) or arrived >= oldest then break end
        items[order[i]] = nil
        first = i + 1
    end
    if first == 1 then return end
    local count = #order
    for i = first, count do order[i - first + 1] = order[i] end
    for i = count - first + 2, count do order[i] = nil end
end

-- Older builds kept one session list: { guid, items, order, dismissed }.
local function Characters(root, now)
    local saved = root.suiteBagRecent
    if type(saved) ~= "table" then saved = {} end
    if type(saved.guid) == "string" and Valid(saved) then
        -- Its items carry no arrival time: they count from now.
        local guid = saved.guid
        saved.guid = nil
        for itemID in pairs(saved.items) do saved.items[itemID] = now end
        saved = { [guid] = saved }
    end
    root.suiteBagRecent = saved
    for guid, record in pairs(saved) do
        if not Valid(record) then
            saved[guid] = nil
        else
            Index.ExpireRecent(record, now)
            if #record.order == 0 then saved[guid] = nil end
        end
    end
    return saved
end

function Index.Recent()
    if session then return session end
    local guid, root = S.PublicText(UnitGUID("player")), NS.RootDB
    if not guid or not NS.loginKind or type(root) ~= "table" then
        return { items = {}, order = {}, dismissed = {} }
    end
    local characters = Characters(root, GetServerTime())
    local saved = characters[guid]
    if not Valid(saved) then
        saved = { items = {}, order = {}, dismissed = {} }
        characters[guid] = saved
    end
    session = saved
    return session
end

local function Remember(recent, itemID, now)
    if recent.items[itemID] then return end
    local order = recent.order
    if #order >= 200 then
        recent.items[order[1]] = nil
        table.remove(order, 1)
    end
    order[#order + 1], recent.items[itemID] = itemID, now
end

-- The view state: pinned items from the profile's module state, recent items
-- of this character. Older builds kept recent items in the profile.
function Index.State(state, view)
    state.pinned = type(state.pinned) == "table" and state.pinned or {}
    state.recent, state.recentOrder, state.dismissedRecent = nil, nil, nil
    view = view or {}
    view.pinned, view.recent = state.pinned, Index.Recent().items
    return view
end

------------------------------------------------------------------ reading slots
-- One record per native or Suite button; a slot whose cached read did not
-- change keeps its record without any client call.
function Index.ReadButton(index, button, info, quest, version, bag, slot, bankType)
    local item = index.records[button]
    if not item then
        item = {}
        index.records[button] = item
    end
    if item.version == version and item.bag == bag and item.slot == slot and item.bankType == bankType then
        index.items[#index.items + 1] = item
        if item.filtered then index.filtered = index.filtered + 1 end
        return item
    end
    local valid = S.Public(info) and type(info) == "table" and S.Finite(info.itemID)
        and S.Public(info.hyperlink) and type(info.hyperlink) == "string"
    local link = valid and info.hyperlink or nil
    -- The same item in the same place keeps its record: what was derived from
    -- the link (metadata, upgrade track, item level) and its shuffle key stay.
    -- Every field read from info is written again below.
    if item.link ~= link or item.bag ~= bag or item.slot ~= slot or item.bankType ~= bankType then
        for key in pairs(item) do item[key] = nil end
    end
    item.link, item.bag, item.slot, item.version = link, bag, slot, version
    item.button, item.bankType, item.key = button, bankType, bag * KEY + slot
    if valid then
        item.itemID = info.itemID
        item.count = S.Finite(info.stackCount) and info.stackCount or 1
        item.quality = S.Finite(info.quality) and info.quality or nil
        item.locked = not S.Public(info.isLocked) or info.isLocked == true
        item.bound = S.Public(info.isBound) and info.isBound == true
        item.filtered = S.Public(info.isFiltered) and info.isFiltered == true
        item.quest = quest == true
        -- Full link, binding state and location type: different bonus IDs,
        -- upgrade ranks, qualities and bank scopes never share a stack.
        item.mergeKey = link .. (item.bound and "\031b\031" or "\031u\031") .. (bankType or "bags")
        if not item.loaded then ApplyMetadata(index, item) end
    end
    index.items[#index.items + 1] = item
    if item.filtered then index.filtered = index.filtered + 1 end
    return item
end

local function BagName(index, bag)
    local name = index.bagNames[bag]
    if name == nil then
        name = C_Container.GetBagName(bag)
        name = S.Public(name) and type(name) == "string" and name or false
        index.bagNames[bag] = name
    end
    return name or nil
end

local function SortButtons(index, frame)
    local buttons, order = index.buttons, index.order
    for key in pairs(buttons) do buttons[key] = nil end
    for i = #order, 1, -1 do order[i] = nil end
    for _, button in frame:EnumerateValidItems() do
        local bag, slot = button:GetBagID(), button:GetID()
        if S.Finite(bag) and S.Finite(slot) and slot > 0 and slot < KEY then
            local key = bag * KEY + slot
            buttons[key], order[#order + 1] = button, key
        end
    end
    table.sort(order)
    index.ordered = true
end

-- Whether the client flags a slot's item as new. An item is flagged when it
-- arrives, which changes the slot's cached read (SlotCache version); a hover
-- only clears the flag (ContainerFrame.lua RemoveNewItem). So the client is
-- asked again only for a changed slot or one that was new at the last read.
local function Fresh(item, bag, slot)
    local fresh = item.fresh
    if fresh or item.freshVersion ~= item.version then
        fresh = C_NewItems.IsNewItem(bag, slot)
        if S.Public(fresh) then
            fresh = fresh == true
            item.fresh, item.freshVersion = fresh, item.version
        else
            fresh, item.fresh, item.freshVersion = false, nil, nil
        end
    end
    return fresh
end

-- Blizzard fills its combined bag from bag 4 down to 0 and slot N down to 1
-- (upstream/live ContainerFrame.lua UpdateItemSlots); the index always lists
-- slots physically: bag 0 slot 1 first. Call Index.Invalidate after Blizzard
-- rebuilt its item buttons.
function Index.ReadContainer(index, frame, recent)
    if not index.ordered then SortButtons(index, frame) end
    local items, order = index.items, index.order
    for i = #items, 1, -1 do items[i] = nil end
    for itemID in pairs(index.freshItems) do index.freshItems[itemID] = nil end
    index.filtered = 0
    local now = GetServerTime()
    Index.ExpireRecent(recent, now)
    local synced
    for i = 1, #order do
        local key = order[i]
        local bag, slot = math.floor(key / KEY), key % KEY
        if bag ~= synced then
            Slots.Sync(bag)
            synced = bag
        end
        local info, quest, version = Slots.Get(bag, slot)
        local item = Index.ReadButton(index, index.buttons[key], info, quest, version, bag, slot)
        item.bagName = BagName(index, bag)
        if item.itemID and Fresh(item, bag, slot) then
            index.freshItems[item.itemID] = true
            if not recent.dismissed[item.itemID] then Remember(recent, item.itemID, now) end
        end
    end
    -- A second, older physical stack must not revive a dismissed item type.
    -- Prune once after the whole visible inventory, keeping this set bounded
    -- by current new items instead of every item ever dismissed.
    for itemID in pairs(recent.dismissed) do
        if not index.freshItems[itemID] then recent.dismissed[itemID] = nil end
    end
    index.revision = index.revision + 1
    return items
end

function Index.Invalidate(index)
    index.ordered = false
    for bag in pairs(index.bagNames) do index.bagNames[bag] = nil end
end

-- GET_ITEM_INFO_RECEIVED: returns true when this index waited for the item.
function Index.ItemDataReceived(index, itemID, success)
    if not S.Finite(itemID) or not index.pending[itemID] then return false end
    index.pending[itemID] = nil
    Loads.Received(index.loads, itemID, success ~= false)
    return true
end

-- Copies arriving item data into the waiting records; nothing is read again.
function Index.Refresh(index, itemID)
    local changed = false
    for i = 1, #index.items do
        local item = index.items[i]
        if item.itemID == itemID and not item.loaded then
            ApplyMetadata(index, item)
            changed = changed or item.loaded
        end
    end
    return changed
end

function Index.Retry(index)
    -- Retry failed requests only on the next explicit window opening. A
    -- failure event must not cause an immediate request/failure loop.
    Loads.Retry(index.loads)
end

function Index.Reset(index)
    Loads.Reset(index.loads)
    for _, key in ipairs({ "items", "records", "metadata", "pending", "bagNames", "freshItems",
        "buttons", "order" }) do
        for entry in pairs(index[key]) do index[key][entry] = nil end
    end
    index.count, index.ordered, index.filtered = 0, false, 0
end

function Index.ClearRecent(recent)
    for itemID in pairs(recent.items) do
        recent.dismissed[itemID], recent.items[itemID] = true, nil
    end
    for i = #recent.order, 1, -1 do recent.order[i] = nil end
end

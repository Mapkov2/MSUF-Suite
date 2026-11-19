local _, P = ...
local NS, S, M = P.NS, P.Suite, P.BagsModule
local Loads, Grid, Model = P.ItemLoads, P.GridView, P.InventoryModel
local VIEW = NS.BagsView
-- The offline view of the bag window: another character's recorded bags or
-- bank, or the warband bank (Retail), from Quality of Life's Inventory
-- archive (MSUF_Suite_QualityOfLife/InventoryArchive.lua). The archive keeps
-- item counts only; this file reads them through its read-only calls and
-- keeps nothing beyond display records of the shown snapshot (one per item
-- type, reused while the snapshot is unchanged). The view only shows: no row
-- takes a click, a drag or an item action, and Blizzard's item buttons stay
-- hidden while it shows. A fight, closing the bags or a disabled archive
-- returns to the live bags.
local Offline = { records = {}, items = {}, loads = Loads.New(2048), pending = {}, view = {}, recordCount = 0,
    context = { transactions = true, searching = false, hasKeyring = false, physicalSlots = false } }
P.BagOffline = Offline
local SCOPES = { bags = "Bags", bank = "Bank", warband = "Warband bank" }
local MAX_RECORDS, MAX_CHARACTERS = 4096, 40
local EMPTY = {}

local function Archive()
    local archive = S.InventoryArchive
    if archive and archive.active and archive.VisitRecorded and archive.RecordedAt and archive.RecordedCharacters then
        return archive
    end
    return nil
end

function Offline.Available()
    return Archive() ~= nil
end

function Offline.Active()
    return Offline.current ~= nil
end

-- By bag has no bags offline: All items stands in. Empty slots are not recorded.
Offline.config = setmetatable({}, { __index = function(_, key)
    local config = M.config
    if key == "inventoryView" and config.inventoryView == VIEW.BY_BAG then return VIEW.ALL end
    if key == "mergeStacks" then return false end
    return config[key]
end })

------------------------------------------------------------------ records
local function Icon(itemID, icon)
    if S.Finite(icon) then return icon end
    local instant = C_Item.GetItemIconByID(itemID)
    return S.Finite(instant) and instant or nil
end

-- Item type data from the client; an item it has not cached is asked for and
-- shows its number until GET_ITEM_INFO_RECEIVED (InventoryView.lua).
local function Apply(record)
    local id = record.itemID
    local name, _, quality, level, _, className, subclassName, maxStack, equipLoc, icon, sellPrice, classID,
        subclassID, bindType, expansion = C_Item.GetItemInfo(id)
    if not S.Public(name) or type(name) ~= "string" then
        record.loaded, record.name = false, S.Text("Item %d"):format(id)
        record.search, record.icon = record.name:lower(), record.icon or Icon(id)
        if Loads.Request(Offline.loads, id) then Offline.pending[id] = true end
        return
    end
    record.name, record.search, record.loaded = name, name:lower(), true
    record.quality = S.Finite(quality) and quality or nil
    record.itemLevel = S.Finite(level) and level or nil
    record.className, record.subclassName = S.PublicText(className), S.PublicText(subclassName)
    record.maxStack = S.Finite(maxStack) and maxStack or 1
    record.equipLoc = S.PublicText(equipLoc)
    record.slotName = record.equipLoc and (_G[record.equipLoc] or record.equipLoc) or nil
    record.sellPrice = S.Finite(sellPrice) and sellPrice or nil
    record.classID = S.Finite(classID) and classID or nil
    record.subclassID = S.Finite(subclassID) and subclassID or nil
    record.bindType = S.Finite(bindType) and bindType or nil
    record.expansion = S.Finite(expansion) and expansion or nil
    record.expansionName = record.expansion and _G["EXPANSION_NAME" .. record.expansion] or nil
    record.icon = Icon(id, icon)
end

local function Record(id)
    local record = Offline.records[id]
    if record then return record end
    if Offline.recordCount >= MAX_RECORDS then
        for key in pairs(Offline.records) do Offline.records[key] = nil end
        Offline.recordCount = 0
    end
    record = { itemID = id, offline = true, bag = 0 }
    Offline.records[id], Offline.recordCount = record, Offline.recordCount + 1
    return record
end

local function ByID(a, b) return a.itemID < b.itemID end

local function Read(archive, current)
    local items = Offline.items
    for i = #items, 1, -1 do items[i] = nil end
    local at = archive:VisitRecorded(current.guid, current.scope, function(id, count)
        local record = Record(id)
        record.count = count
        items[#items + 1] = record
    end)
    table.sort(items, ByID)
    for i = 1, #items do
        local record = items[i]
        record.slot, record.key = i, i
        if not record.loaded then Apply(record) end
    end
    return at
end

-- The display records of the shown snapshot, or nil while the live bags
-- show. A snapshot read again only when its recording time changed.
function Offline.Items()
    local current = Offline.current
    if not current then return nil end
    local archive = Archive()
    local at = archive and archive:RecordedAt(current.guid, current.scope)
    if not at then
        Offline.current = nil
        return nil
    end
    local key = tostring(current.guid) .. "\031" .. current.scope .. "\031" .. at
    if Offline.key ~= key then
        current.at = Read(archive, current) or at
        Offline.key = key
    end
    return Offline.items
end

-- GET_ITEM_INFO_RECEIVED: true when the offline view waited for the item.
function Offline.ItemDataReceived(itemID, success)
    if not S.Finite(itemID) or not Offline.pending[itemID] then return false end
    Offline.pending[itemID] = nil
    Loads.Received(Offline.loads, itemID, S.Public(success) and success == true)
    local record = Offline.records[itemID]
    if record and not record.loaded then Apply(record) end
    return Offline.current ~= nil
end

------------------------------------------------------------------ the view
-- Builds the bag view's model from the shown snapshot: pinned items and
-- collapsed groups of the profile apply, recent items belong to the live
-- character. Returns the selection that was built.
function Offline.Build(view, state, items)
    local shown = Offline.view
    shown.pinned, shown.recent, shown.collapsed = state.pinned, EMPTY, state.collapsed
    local context = Offline.context
    context.query = view.smartQuery
    return Grid.Build(Model, view.model, items, Offline.config, shown, context, view.selected)
end

-- The band's line: whose snapshot, which place and when it was recorded.
function Offline.Status()
    local current = Offline.current
    if not current or not current.at then return nil end
    local owner = current.scope == "warband" and S.Text("Warband") or current.address
    return S.Text("%s - %s - recorded %s (view only)"):format(owner, S.Text(SCOPES[current.scope]),
        date("%Y-%m-%d %H:%M", current.at))
end

-- The tooltip line under an offline item.
function Offline.Note()
    local current = Offline.current
    if not current or not current.at then return nil end
    return S.Text("Recorded %s"):format(date("%Y-%m-%d %H:%M", current.at))
end

local function Reset(view)
    view.scroll, view.selected = 0, "all"
    view.categoryTransitionPending = true
    if view.active then view.Request() end
end

-- Shows a snapshot in the bag window. Refused in combat: the live item
-- buttons must stay reachable there.
function Offline.Enter(guid, scope, address)
    local view, archive = P.InventoryView, Archive()
    if NS.InCombat() or not view.active or not archive or not SCOPES[scope] then return false end
    if scope == "warband" and NS.Client.isForever then return false end
    if not archive:RecordedAt(guid, scope) then return false end
    Offline.current, Offline.key = { guid = guid, scope = scope, address = address }, nil
    P.EquippedBags.Close()
    Reset(view)
    return true
end

-- Back to the live bags; also at the combat edge (no layout here, the
-- caller's pass lays the live bags out).
function Offline.Leave(quiet)
    if not Offline.current then return end
    Offline.current, Offline.key = nil, nil
    for i = #Offline.items, 1, -1 do Offline.items[i] = nil end
    if quiet == true then
        P.InventoryView.scroll, P.InventoryView.selected = 0, "all"
        return
    end
    Reset(P.InventoryView)
end

-- Drops what the view remembers: the module stopped.
function Offline.Reset()
    Offline.Leave(true)
    for key in pairs(Offline.records) do Offline.records[key] = nil end
    for key in pairs(Offline.pending) do Offline.pending[key] = nil end
    Offline.recordCount = 0
    Loads.Reset(Offline.loads)
end

------------------------------------------------------------------ the Filters menu
local function Choice(scope, at)
    return S.Text("%s (%s)"):format(S.Text(SCOPES[scope]), date("%Y-%m-%d %H:%M", at))
end

local function Enter(guid, scope, address)
    local profile = NS.DB
    return function()
        if NS.DB == profile then Offline.Enter(guid, scope, address) end
    end
end

local function AddCharacter(menu, character)
    if not character.bags and not character.bank then return false end
    menu:CreateTitle(character.address)
    if character.bags then menu:CreateButton(Choice("bags", character.bags), Enter(character.guid, "bags", character.address)) end
    if character.bank then menu:CreateButton(Choice("bank", character.bank), Enter(character.guid, "bank", character.address)) end
    return true
end

-- The recorded inventories the bag window can show. Returns whether it added
-- anything.
function Offline.AddMenu(menu)
    local archive = Archive()
    if not archive or NS.InCombat() then return false end
    local characters, warband = archive:RecordedCharacters()
    if NS.Client.isForever then warband = nil end
    if #characters == 0 and not warband and not Offline.current then return false end
    menu:CreateTitle(S.Text("Recorded inventories (view only)"))
    if Offline.current then menu:CreateButton(S.Text("Back to live items"), function() Offline.Leave() end) end
    local shown = 0
    for i = 1, #characters do
        if shown >= MAX_CHARACTERS then break end
        if AddCharacter(menu, characters[i]) then shown = shown + 1 end
    end
    if warband then
        menu:CreateTitle(S.Text("Warband"))
        menu:CreateButton(Choice("warband", warband), Enter(nil, "warband", S.Text("Warband")))
    end
    return true
end

local function ChooseInventory(button)
    if NS.InCombat() or not Archive() then return end
    P.BagFilterMenu.Show(button, function(_, menu)
        if not Offline.AddMenu(menu) then
            menu:CreateButton(S.Text("Inventory archive"), function()
                local archive = Archive()
                if archive and not NS.InCombat() then archive:Browse("bags") end
            end)
        end
    end)
end

function Offline.ToolbarButton(view)
    local button = view.archiveButton
    if not Archive() then
        if button then button:Hide() end
        return
    end
    if not button then
        button = Grid.Button(view.chrome, "", 22, ChooseInventory)
        P.BagAppearance.Tool(button, "Choose character", "Interface\\Icons\\INV_Misc_Book_09", nil, true)
        view.archiveButton = button
    end
    button:Show()
    return button
end

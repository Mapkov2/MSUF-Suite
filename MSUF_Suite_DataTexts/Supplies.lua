local _, P = ...
local NS, S = P.NS, P.Suite
local Sources = P.DataTextSources
local Supplies = {}
P.SuppliesDataText = Supplies
local LIMIT = 32
local module, events, job, active, config, dirty, discover
local lastItems, lastLearn, lastSaved
local ids, seen, rows, pieces, requested = {}, {}, {}, {}, {}
local value, ammoSlot, ammoID
local attempted, known, customIDs, customSeen = {}, {}, {}, {}
local savedState
local function Add(id)
    if not S.Finite(id) or id <= 0 or id >= 2147483647 or id % 1 ~= 0 or seen[id] or #ids >= LIMIT then return end
    seen[id], ids[#ids + 1] = true, id
end
local function Learn(saved)
    if #saved >= LIMIT then return end
    for id in pairs(known) do known[id] = nil end
    for i = 1, math.min(#saved, LIMIT) do if S.Finite(saved[i]) then known[saved[i]] = true end end
    for bag = 0, NUM_BAG_SLOTS do
        local count = C_Container.GetContainerNumSlots(bag)
        if S.Finite(count) then
            for slot = 1, math.min(count, 100) do
                local id = C_Container.GetContainerItemID(bag, slot)
                if S.Finite(id) and not known[id] and #saved < LIMIT then
                    local _, _, _, _, _, class, subclass = C_Item.GetItemInfoInstant(id)
                    if S.Finite(class) and S.Finite(subclass) and (class == Enum.ItemClass.Reagent
                        and subclass == Enum.ItemReagentSubclass.Reagent or class == Enum.ItemClass.Miscellaneous
                        and subclass == Enum.ItemMiscellaneousSubclass.Reagent) then
                        saved[#saved + 1], known[id] = id, true
                    end
                end
            end
        end
    end
end
local function List()
    for i = #ids, 1, -1 do ids[i] = nil end
    for id in pairs(seen) do seen[id] = nil end
    -- Ammunition is prioritized ahead of custom entries at the fixed cap.
    if not ammoSlot then ammoSlot = C_PaperDollInfo.GetInventorySlotInfo("AmmoSlot") end
    ammoID = S.Finite(ammoSlot) and GetInventoryItemID("player", ammoSlot) or nil
    if S.Finite(ammoID) then Add(ammoID)
    else
        ammoID = nil
    end
    for i = 1, #customIDs do Add(customIDs[i]) end
    if module.config.suppliesLearn then
        local saved = savedState
        if saved then
            if type(saved.items) ~= "table" then saved.items = {} end
            if discover then Learn(saved.items) end
            for i = 1, math.min(#saved.items, LIMIT) do Add(saved.items[i]) end
        end
    end
    discover = false
end
local function Read()
    if not dirty then return end
    dirty = false
    List()
    for id in pairs(attempted) do if not seen[id] then attempted[id] = nil end end
    for id in pairs(requested) do if not seen[id] then requested[id] = nil end end
    local used = 0
    for i = #pieces, 1, -1 do pieces[i] = nil end
    for i = 1, #ids do
        local id = ids[i]
        local name, _, _, _, _, _, _, _, _, icon = C_Item.GetItemInfo(id)
        local count = id == ammoID and GetInventoryItemCount("player", ammoSlot)
            or C_Item.GetItemCount(id, false, false, false, false)
        if S.PublicText(name) and S.Finite(count) then
            used = used + 1
            local row = rows[used] or {}
            rows[used] = row
            row.id, row.name, row.count = id, name, count
            row.icon = S.Finite(icon) and icon or 134400
            pieces[used] = tostring(count)
        elseif not attempted[id] then
            attempted[id], requested[id] = true, true
            events:RegisterEvent("GET_ITEM_INFO_RECEIVED")
            C_Item.RequestLoadItemDataByID(id)
        end
    end
    if next(requested) then events:RegisterEvent("GET_ITEM_INFO_RECEIVED")
    else
        events:UnregisterEvent("GET_ITEM_INFO_RECEIVED")
    end
    for i = #rows, used + 1, -1 do rows[i] = nil end
    value = used > 0 and table.concat(pieces, " / ") or P.NO_VALUE
end
local function Flush()
    if active then Sources.Refresh("supplies") end
end
local function Changed(_, event, id)
    if event == "GET_ITEM_INFO_RECEIVED" then
        if not S.Finite(id) or not requested[id] then return end
        requested[id] = nil
        if not next(requested) then events:UnregisterEvent(event) end
    else
        discover = true
    end
    dirty = true
    if not job.pending then job:Request() end
end
function Supplies.Disable()
    active = false
    if events then events:UnregisterAllEvents() end
    if job then job:Cancel() end
end
function Supplies.Rebind(owner, wanted)
    module = owner
    if not wanted or not NS.Client.isForever then
        Supplies.Disable()
        return
    end
    local saved = NS.CharacterData("supplies")
    savedState = saved
    local currentSaved = saved and saved.items
    local changed = lastSaved ~= currentSaved or config ~= owner.config or lastItems ~= owner.config.suppliesItems
        or lastLearn ~= owner.config.suppliesLearn
    if lastItems ~= owner.config.suppliesItems then
        for i = #customIDs, 1, -1 do customIDs[i] = nil end
        for id in pairs(customSeen) do customSeen[id] = nil end
        for token in (owner.config.suppliesItems or ""):sub(1, 400):gmatch("%d+") do
            local id = tonumber(token)
            if id > 0 and id < 2147483647 and not customSeen[id] and #customIDs < LIMIT then
                customSeen[id], customIDs[#customIDs + 1] = true, id
            end
        end
    end
    lastItems, lastLearn = owner.config.suppliesItems, owner.config.suppliesLearn
    config, lastSaved = owner.config, currentSaved
    if active and not changed then return end
    if not events then
        events = S.CreateFrame("Frame")
        events:SetScript("OnEvent", Changed)
    end
    job = owner.context:Coalesce(.05, Flush)
    active, dirty, discover = true, true, true
    events:RegisterEvent("BAG_UPDATE_DELAYED")
    events:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
    events:RegisterEvent("PLAYER_ENTERING_WORLD")
end
function Supplies.Format(binding)
    if not NS.Client.isForever then return S.Text("Supplies"), P.NO_VALUE end
    Read()
    for i = 1, #rows do binding.icons[#binding.icons + 1] = rows[i].icon end
    return S.Text("Supplies"), value
end
function Supplies.Tooltip(tooltip)
    Read()
    for i = 1, #rows do tooltip:AddDoubleLine(rows[i].name, tostring(rows[i].count), 1, 1, 1, 1, 1, 1) end
    if #rows == 0 then tooltip:AddLine(S.Text("Carry reagents or add supply item IDs in DataTexts settings."), 1, 1, 1, true) end
end
Sources.Register("supplies", Supplies, {})

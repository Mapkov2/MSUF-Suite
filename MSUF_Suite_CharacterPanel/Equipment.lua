local _, NS = ...
local Text, Number, String = NS.Text, NS.Number, NS.String
local Gear = {}
NS.Gear = Gear

-- The order is the Character Panel's visual order. GetInventorySlotInfo
-- supplies the native slot identifier and empty-slot icon on this client.
local LEFT = { "HeadSlot", "NeckSlot", "ShoulderSlot", "BackSlot", "ChestSlot", "ShirtSlot", "TabardSlot", "WristSlot" }
local RIGHT = { "HandsSlot", "WaistSlot", "LegsSlot", "FeetSlot", "Finger0Slot", "Finger1Slot", "Trinket0Slot", "Trinket1Slot" }
local WEAPONS = { "MainHandSlot", "SecondaryHandSlot" }
local FOREVER_WEAPONS = { "MainHandSlot", "SecondaryHandSlot", "RangedSlot" }

local function AddSlots(model, output, names)
    for i = 1, #names do
        local token = names[i]
        local id, texture = GetInventorySlotInfo(token)
        id = Number(id)
        if id then
            local label = _G[token:upper()]
            local row = {
                slot = id, token = token, label = String(label) or Text("Slot"),
                emptyIcon = NS.Public(texture) and texture or nil, audit = {},
            }
            output[#output + 1], model.rows[#model.rows + 1], model.bySlot[id] = row, row, row
        end
    end
end

function Gear.New()
    local model = { left = {}, right = {}, weapons = {}, rows = {}, bySlot = {}, pending = {} }
    AddSlots(model, model.left, LEFT)
    AddSlots(model, model.right, RIGHT)
    AddSlots(model, model.weapons, NS.Host.Client.isForever and FOREVER_WEAPONS or WEAPONS)
    return model
end

local function ReadRow(reader, model, row, unit, identity, level)
    local slot = row.slot
    local rawLink = GetInventoryItemLink(unit, slot)
    local link = String(rawLink)
    local icon = GetInventoryItemTexture(unit, slot)
    local publicIcon = NS.Public(icon)
    if not publicIcon then icon = nil end
    local audit = reader.Read(link, unit, slot, row.audit, identity)
    if not NS.Host.Client.isForever then reader.Check(audit, level) end
    if link then row.pendingItemID = nil
    elseif icon then reader.RequestMissingLink(unit, slot, row, model.pending)
    else row.pendingItemID = nil end
    row.link, row.icon, row.quality = link, icon or row.emptyIcon, audit.quality
    row.missingLink = not link and (icon ~= nil or not publicIcon or not NS.Public(rawLink))
    row.name = audit.name or Text((link or icon) and "Loading item…" or "Empty slot")
    row.level = audit.itemLevel
end

local function Summarize(reader, model)
    wipe(model.pending)
    local enchants, sockets, unknown, total, count, missingLinks = 0, 0, 0, 0, 0, false
    for i = 1, #model.rows do
        local row = model.rows[i]
        local missing, _, empty, unverified = reader.Summarize(row.audit, model.pending, row.pendingItemID)
        enchants, sockets, unknown = enchants + missing, sockets + empty, unknown + unverified
        if row.level and row.level > 0 then total, count = total + row.level, count + 1 end
        if row.missingLink then missingLinks = true end
    end
    model.missingEnchants, model.emptySockets, model.unverified = enchants, sockets, unknown
    model.visibleAverage = count > 0 and total / count or nil
    model.missingLinks = missingLinks
end

function Gear.Read(reader, model, unit, identity, level, slot)
    local affected = model.bySlot[slot]
    if model.identity ~= identity then
        reader.ClearPending(model.rows, model.pending)
        model.identity, affected = identity, nil
    end
    if affected then
        ReadRow(reader, model, affected, unit, identity, level)
    else
        for i = 1, #model.rows do ReadRow(reader, model, model.rows[i], unit, identity, level) end
    end
    Summarize(reader, model)
end

local function Loaded(audit, ids)
    if ids[audit.itemID] then return true end
    for i = 1, #audit.gemInfo do
        if ids[audit.gemInfo[i].id] then return true end
    end
    return false
end

-- Native Inspect clears the unit cache when it closes. Pending items can
-- still resolve from their captured links without a second Inspect request.
function Gear.UpdateSnapshot(reader, model, ids, level)
    for i = 1, #model.rows do
        local row = model.rows[i]
        if row.link and not row.audit.settled and Loaded(row.audit, ids) then
            local audit = reader.Read(row.link, nil, row.slot, row.audit, model.identity)
            if not NS.Host.Client.isForever then reader.Check(audit, level) end
            row.level, row.quality = audit.itemLevel, audit.quality
            if audit.name then row.name = audit.name end
        end
    end
    Summarize(reader, model)
end

function Gear.Close(reader, model)
    reader.ClearPending(model.rows, model.pending)
    model.identity = nil
    if model.auditFocus then Gear.Mark(model, nil) end
end

function Gear.Durability(model)
    local currentTotal, maximumTotal, wornSlots = 0, 0, 0
    for i = 1, #model.rows do
        local row = model.rows[i]
        local current, maximum = GetInventoryItemDurability(row.slot)
        current, maximum = Number(current), Number(maximum)
        row.durability, row.worn = nil, nil
        if current and maximum and maximum > 0 then
            row.durability = math.floor(current * 100 / maximum + .5)
            row.worn = current < maximum
            if row.worn then wornSlots = wornSlots + 1 end
            currentTotal, maximumTotal = currentTotal + current, maximumTotal + maximum
        end
    end
    model.durability = maximumTotal > 0 and math.floor(currentTotal * 100 / maximumTotal + .5) or nil
    model.wornSlots = wornSlots
end

local function MatchesAudit(row, focus)
    if focus == "durability" then return row.worn end
    if focus == "enchants" then return row.audit.missingEnchant end
    if focus == "sockets" then return (row.audit.emptySockets or 0) > 0 end
end

function Gear.Mark(model, focus)
    local marked = false
    for i = 1, #model.rows do
        local row = model.rows[i]
        row.marked = MatchesAudit(row, focus) == true
        marked = marked or row.marked
    end
    model.auditFocus = marked and focus or nil
end

local function ItemLevel(row)
    return row and row.level and string.format("%.0f", row.level) or "—"
end

function Gear.EquipmentList(groups, model)
    local group = model.equipmentList
    if not group then
        group = { title = Text("Your equipment"), rows = {} }
        model.equipmentList = group
    end
    wipe(group.rows)
    for i = 1, #model.rows do
        local item = model.rows[i]
        if item.name and (not model.auditFocus or item.marked) then
            local row = item.listRow
            if not row then
                row = { label = item.label, action = item.slot }
                item.listRow = row
            end
            row.value = item.name
            group.rows[#group.rows + 1] = row
        end
    end
    if #group.rows > 0 then groups[#groups + 1] = group end
end

function Gear.Compare(groups, own, inspect)
    local group = inspect.comparison
    if not group then
        group = { title = Text("Your equipment") .. " → " .. Text("Inspected equipment"), rows = {} }
        inspect.comparison = group
    end
    for i = 1, #inspect.rows do
        local row = inspect.rows[i]
        local ownRow = own.bySlot[row.slot]
        local ownLevel, inspectLevel = ownRow and ownRow.level, row.level
        local comparison = group.rows[i]
        if not comparison then
            comparison = { label = row.label }
            group.rows[i] = comparison
        end
        if not comparison.value or comparison.own ~= ownLevel or comparison.inspect ~= inspectLevel then
            local value = ItemLevel(ownRow) .. " → " .. ItemLevel(row)
            if ownLevel and inspectLevel then value = value .. string.format(" · %+.0f", inspectLevel - ownLevel) end
            comparison.own, comparison.inspect, comparison.value = ownLevel, inspectLevel, value
        end
    end
    groups[#groups + 1] = group
end

function Gear.Details(groups, model, slot, inspect)
    local row = model.bySlot[slot]
    if not row then return end
    local audit = row.audit
    local rows = { { label = Text("Slot"), value = row.label }, { label = Text("Item Level"), value = ItemLevel(row) } }
    if audit.upgradeText then
        local upgrade = audit.upgradeTrack and audit.upgradeTrack .. " " .. audit.upgradeText or audit.upgradeText
        rows[#rows + 1] = { label = Text("Upgrade"), value = upgrade }
    end
    if audit.enchantLabel and audit.enchantLabel ~= "" then
        rows[#rows + 1] = { label = Text("Enchantment"), value = audit.enchantLabel }
    end
    if audit.sockets and audit.sockets > 0 then
        rows[#rows + 1] = { label = Text("Sockets"), value = string.format("%d / %d", audit.gems or 0, audit.sockets) }
    end
    if not inspect and row.durability then
        rows[#rows + 1] = { label = Text("Durability"), value = string.format("%d%%", row.durability) }
    end
    groups[1] = { title = row.name, rows = rows }
end

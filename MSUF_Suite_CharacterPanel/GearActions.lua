local _, NS = ...
local Suite, Text = NS.Suite, NS.Text
local Number, String, Public = NS.Number, NS.String, NS.Public
local Equipment = C_EquipmentSet
local Actions = {}
NS.GearActions = Actions

local QUESTION = "character-equipment-set"
local DEFAULT_ICON = 134400
local NAME_LIMIT = 16
local NO_SPEC = 0

local function EquipmentSetIDs()
    local ids = Equipment.GetEquipmentSetIDs()
    if Public(ids) and type(ids) == "table" then return ids end
end

local function SetInfo(id)
    id = Number(id)
    if not id then return end
    local name, icon, setID, equipped = Equipment.GetEquipmentSetInfo(id)
    if Number(setID) == id then
        return String(name), Public(equipped) and equipped == true, id, Number(icon)
    end
end

function Actions.ActiveName()
    local ids = EquipmentSetIDs()
    if ids then
        for i = 1, #ids do
            local name, equipped = SetInfo(ids[i])
            if name and equipped then return name end
        end
    end
    return false
end

function Actions.SetLabel(name)
    return name and Text("Equipment set: %s"):format(name) or Text("Equipment sets")
end

local function CanUse(entry)
    if not entry.canUse() then return false end
    local allowed = Equipment.CanUseEquipmentSets()
    return Public(allowed) and allowed == true and (entry.id == nil or SetInfo(entry.id) == entry.name)
end

local function Equip(entry)
    if not CanUse(entry) then return end
    local _, equipped = SetInfo(entry.id)
    if not equipped then EquipmentManager_EquipSet(entry.id) end
end

local function IsEquipped(entry)
    return entry.equipped
end

local function Pickup(entry)
    if not CanUse(entry) then return end
    local held = GetCursorInfo()
    if Public(held) and held == nil then Equipment.PickupEquipmentSet(entry.id) end
end

local function SlotIgnored(slot)
    local value = Equipment.IsSlotIgnoredForSave(slot)
    return Public(value) and value == true
end

local function SetIgnored(slot, ignored)
    if ignored then Equipment.IgnoreSlotForSave(slot) else Equipment.UnignoreSlotForSave(slot) end
end

local function Save(entry, name)
    if not CanUse(entry) then return end
    local changed = {}
    for _, row in ipairs(entry.slots) do
        local slot = row.slot
        local previous, desired = SlotIgnored(slot), entry.ignored[slot] == true
        if previous ~= desired then
            changed[slot] = previous
            SetIgnored(slot, desired)
        end
    end
    if entry.id then
        Suite.Dispatch(Equipment.SaveEquipmentSet, entry.id, nil)
    else
        Suite.Dispatch(Equipment.CreateEquipmentSet, name, tostring(DEFAULT_ICON))
    end
    for slot, previous in pairs(changed) do SetIgnored(slot, previous) end
end

local function Prompt(entry, title, initial, maxLetters, accept)
    if not CanUse(entry) then return end
    local dialog = Suite.AskText(QUESTION, { text = title, maxLetters = maxLetters, callback = function(input)
        input = String(input)
        if input and CanUse(entry) then accept(entry, input) end
    end })
    if initial and dialog then
        local edit = dialog:GetEditBox()
        edit:SetText(initial)
        edit:HighlightText()
    end
end

local function SaveName(entry, name)
    name = name:gsub("[%z\1-\31\127|]", ""):match("^%s*(.-)%s*$")
    if name == "" then return end
    local found = Equipment.GetEquipmentSetID(name)
    if not Public(found) then return end
    if found ~= nil and found ~= entry.id then
        Suite.Print(String(EQUIPMENT_SETS_CANT_RENAME) or Text("An equipment set already uses that name."))
    elseif entry.id then
        if name ~= entry.name then Equipment.ModifyEquipmentSet(entry.id, name, entry.icon and tostring(entry.icon)) end
    else
        local count, limit = Number(Equipment.GetNumEquipmentSets()), Number(MAX_EQUIPMENT_SETS_PER_PLAYER)
        if count and limit and count >= limit then
            Suite.Print(String(EQUIPMENT_SETS_TOO_MANY) or Text("You have reached the equipment set limit."))
        else
            Save(entry, name)
        end
    end
end

local function AskName(entry)
    Prompt(entry, Text("Equipment set name"), entry.name, NAME_LIMIT, SaveName)
end

local function AskSave(entry)
    if not CanUse(entry) then return end
    Suite.Confirm(QUESTION, {
        text = Text("Save current equipment to %s?"), text_arg1 = entry.name,
        callback = function() Save(entry) end,
    })
end

local function AskDelete(entry)
    if not CanUse(entry) then return end
    Suite.Confirm(QUESTION, {
        text = Text("Delete equipment set %s?"), text_arg1 = entry.name,
        callback = function()
            if CanUse(entry) then Equipment.DeleteEquipmentSet(entry.id) end
        end,
    })
end

local function ChangeIcon(entry, value)
    local icon = tonumber(value)
    if icon and icon >= 1 and icon < 2147483648 and icon % 1 == 0 then
        Equipment.ModifyEquipmentSet(entry.id, entry.name, tostring(icon))
    end
end

local function IconMenu(menu, entry)
    local icons = menu:CreateButton(Text("Set icon"))
    icons:CreateButton(Text("Icon file ID (Enter)"), function()
        Prompt(entry, Text("Icon file ID (Enter)"), entry.icon and tostring(entry.icon), 10, ChangeIcon)
    end)
    for _, icon in ipairs(entry.icons) do
        icons:CreateButton(icon.label, function()
            if CanUse(entry) then ChangeIcon(entry, icon.id) end
        end)
    end
end

local function SpecNames()
    local names = {}
    local count = Number(GetNumSpecializations(false, false)) or 0
    for index = 1, count do
        local _, name = C_SpecializationInfo.GetSpecializationInfo(index)
        name = String(name)
        if name then names[#names + 1] = { index = index, name = name } end
    end
    return names
end

local function SpecMenu(menu, entry, names)
    local assigned = Number(Equipment.GetEquipmentSetAssignedSpec(entry.id)) or NO_SPEC
    local specs = menu:CreateButton(String(EQUIPMENT_SET_ASSIGN_TO_SPEC) or Text("Assign specialization"))
    local function Selected(index) return index == assigned end
    local function Assign(index)
        if not CanUse(entry) then return end
        if index == NO_SPEC then Equipment.UnassignEquipmentSetSpec(entry.id)
        else Equipment.AssignSpecToEquipmentSet(entry.id, index) end
    end
    specs:CreateRadio(String(NONE) or Text("None"), Selected, Assign, NO_SPEC)
    for _, spec in ipairs(names) do specs:CreateRadio(spec.name, Selected, Assign, spec.index) end
end

local function SlotMenu(menu, entry)
    local slots = menu:CreateButton(Text("Ignored equipment slots"))
    for _, row in ipairs(entry.slots) do
        slots:CreateCheckbox(row.label, function(slot) return entry.ignored[slot] == true end, function(slot)
            entry.ignored[slot] = not entry.ignored[slot]
        end, row.slot)
    end
end

local function SaveOptions(menu, entry, label, action)
    local save = menu:CreateButton(label)
    save:CreateButton(label, action, entry)
    SlotMenu(save, entry)
end

local function AddSet(menu, entry, specs)
    local set = menu:CreateButton(entry.name)
    set:CreateButton(Text("Pick up for action bar"), Pickup, entry)
    set:CreateButton(String(RENAME) or Text("Rename"), AskName, entry)
    IconMenu(set, entry)
    SpecMenu(set, entry, specs)
    SaveOptions(set, entry, Text("Save current equipment"), AskSave)
    set:CreateButton(String(DELETE) or Text("Delete"), AskDelete, entry)
end

local function ReadIgnored(entry)
    local result = {}
    local ignored = Equipment.GetIgnoredSlots(entry.id)
    if Public(ignored) and type(ignored) == "table" then
        for _, row in ipairs(entry.slots) do
            local value = ignored[row.slot]
            if Public(value) and value == true then result[row.slot] = true end
        end
    end
    return result
end

local function SetMenu(_, root, session)
    if not CanUse(session.new) then return end
    local ids, sets = EquipmentSetIDs(), {}
    for i = 1, ids and #ids or 0 do
        local name, equipped, id, icon = SetInfo(ids[i])
        if name then
            local entry = session.entries[id]
            if not entry or entry.name ~= name then
                entry = { id = id, name = name, canUse = session.new.canUse, slots = session.new.slots, icons = session.icons }
                entry.ignored = ReadIgnored(entry)
                session.entries[id] = entry
            end
            entry.equipped, entry.icon = equipped, icon
            root:CreateRadio(name, IsEquipped, Equip, entry)
            sets[#sets + 1] = entry
        end
    end
    if #sets == 0 then root:CreateTitle(Text("No saved equipment sets")) end
    SaveOptions(root, session.new, String(PAPERDOLL_NEWEQUIPMENTSET) or Text("New equipment set"), AskName)
    if #sets == 0 then return end
    local manage = root:CreateButton(Text("Manage equipment sets"))
    local names = SpecNames()
    for _, entry in ipairs(sets) do AddSet(manage, entry, names) end
end

function Actions.OpenSets(owner, canUse, slots)
    local entry = { canUse = canUse, slots = slots, ignored = {} }
    if not CanUse(entry) then return end
    local icons, seen = {}, {}
    for _, row in ipairs(slots) do
        if row.token == "ShirtSlot" or row.token == "TabardSlot" then entry.ignored[row.slot] = true end
        local icon = Number(GetInventoryItemTexture("player", row.slot))
        if icon and not seen[icon] then
            icons[#icons + 1] = { id = icon, label = ("|T%d:16|t %s"):format(icon, row.label) }
            seen[icon] = true
        end
    end
    Suite.ContextMenu(owner, SetMenu, { new = entry, entries = {}, icons = icons })
end

function Actions.OpenLootGoals()
    if NS.Host.InCombat() then return false end
    local planner = Suite.PlanningTools
    if planner and planner.Active() then return planner.Window.Open("loot") end
    return Suite.Open("planningTools")
end

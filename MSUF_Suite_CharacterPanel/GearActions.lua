local _, NS = ...
local Suite, Text = NS.Suite, NS.Text
local Number, String, Public = NS.Number, NS.String, NS.Public
local Equipment = C_EquipmentSet
local Actions = { BagEvents = { "BAG_UPDATE_DELAYED" } }
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
    local name, icon, setID, equipped, _, _, _, missing = Equipment.GetEquipmentSetInfo(id)
    if Number(setID) == id then
        return String(name), Public(equipped) and equipped == true, id, Number(icon), Number(missing)
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

local function Available()
    local allowed = Equipment.CanUseEquipmentSets()
    return Public(allowed) and allowed == true
end

local function CanUse(entry)
    return not entry.closed and entry.canUse() and Available() and (entry.id == nil or SetInfo(entry.id) == entry.name)
end

local function Equip(entry)
    if not CanUse(entry) then return end
    local _, equipped = SetInfo(entry.id)
    if equipped then return end
    local locked, casting = Equipment.EquipmentSetContainsLockedItems(entry.id), UnitCastingInfo("player")
    if not Public(locked) or not Public(casting) then return end
    if locked or casting ~= nil then
        local reason = String(ERR_CLIENT_LOCKED_OUT)
        if reason then Suite.Print(reason) end
        return
    end
    Suite.Dispatch(Equipment.UseEquipmentSet, entry.id)
end

local function Pickup(entry)
    if not CanUse(entry) then return end
    local held = GetCursorInfo()
    if Public(held) and held == nil then Equipment.PickupEquipmentSet(entry.id) end
end

local function SlotIgnored(slot)
    local value = Equipment.IsSlotIgnoredForSave(slot)
    if Public(value) then return value == true end
end

local function SetIgnored(slot, ignored)
    local setter = ignored and Equipment.IgnoreSlotForSave or Equipment.UnignoreSlotForSave
    Suite.Dispatch(setter, slot)
end

local function ReadIgnored(entry)
    local ignored = Equipment.GetIgnoredSlots(entry.id)
    if not Public(ignored) then return end
    local result = {}
    if type(ignored) == "table" then
        for _, row in ipairs(entry.slots) do
            local value = ignored[row.slot]
            if not Public(value) then return end
            if value == true then result[row.slot] = true end
        end
    end
    if entry.slotChanges then
        for slot, value in pairs(entry.slotChanges) do result[slot] = value end
    end
    return result
end

local function Save(entry, name, icon)
    if not CanUse(entry) then return end
    local mask = entry.ignored
    if entry.slotChanges then mask = ReadIgnored(entry) end
    if not mask then return end
    local previous = {}
    for _, row in ipairs(entry.slots) do
        local ignored = SlotIgnored(row.slot)
        if ignored == nil then return end
        previous[row.slot] = ignored
    end
    -- The native save mask belongs to the client. Stage it only for the API call.
    local staged = true
    for slot, ignored in pairs(previous) do
        local desired = mask[slot] == true
        if ignored ~= desired then
            SetIgnored(slot, desired)
            if SlotIgnored(slot) ~= desired then
                staged = false
                break
            end
        end
    end
    if staged and entry.id then
        Suite.Dispatch(Equipment.SaveEquipmentSet, entry.id, nil)
    elseif staged then
        if entry.manager then entry.manager.pendingName = name end
        Suite.Dispatch(Equipment.CreateEquipmentSet, name, tostring(icon or entry.icon or DEFAULT_ICON))
    end
    for slot, ignored in pairs(previous) do
        if SlotIgnored(slot) ~= ignored then SetIgnored(slot, ignored) end
    end
    return staged
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

function Actions.EditorName(input)
    local name = String(input)
    if not name then return end
    name = name:gsub("[%z\1-\31\127|]", ""):match("^%s*(.-)%s*$")
    if name ~= "" then return name end
end

function Actions.SubmitEditor(entry, input, icon)
    local name = Actions.EditorName(input)
    if not name then return false end
    if not CanUse(entry) then return false, String(ERR_CLIENT_LOCKED_OUT) end
    icon = Number(icon) or entry.icon
    local found = Equipment.GetEquipmentSetID(name)
    if not Public(found) then return false end
    if found ~= nil and found ~= entry.id then
        return false, String(EQUIPMENT_SETS_CANT_RENAME) or Text("An equipment set already uses that name.")
    end
    if entry.id then
        if name ~= entry.name or icon ~= entry.icon then
            Equipment.ModifyEquipmentSet(entry.id, name, icon and tostring(icon))
        end
        return true
    end
    local count, limit = Number(Equipment.GetNumEquipmentSets()), Number(MAX_EQUIPMENT_SETS_PER_PLAYER)
    if count and limit and count >= limit then
        return false, String(EQUIPMENT_SETS_TOO_MANY) or Text("You have reached the equipment set limit.")
    end
    return Save(entry, name, icon), String(ERR_CLIENT_LOCKED_OUT)
end

local function AskName(entry)
    Prompt(entry, Text("Equipment set name"), entry.name, NAME_LIMIT, function(draft, input)
        local saved, reason = Actions.SubmitEditor(draft, input, draft.icon)
        if not saved and reason then Suite.Print(reason) end
    end)
end

local function AskSave(entry)
    if not entry.ignored or not CanUse(entry) then return end
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
        if entry.id then Equipment.ModifyEquipmentSet(entry.id, entry.name, tostring(icon))
        else entry.icon = icon end
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

local function AddSlotChoices(slots, entry)
    for _, row in ipairs(entry.slots) do
        slots:CreateCheckbox(row.label, function(slot) return entry.ignored[slot] == true end, function(slot)
            local ignored = not entry.ignored[slot]
            entry.ignored[slot] = ignored
            if entry.slotChanges then entry.slotChanges[slot] = ignored end
        end, row.slot)
    end
end

local function SlotChoices(_, root, entry)
    root:CreateTitle(Text("Ignored equipment slots"))
    AddSlotChoices(root, entry)
    if entry.id then root:CreateButton(String(SAVE) or Text("Save current equipment"), AskSave, entry) end
end

local function NewEntry(canUse, slots)
    local entry = { canUse = canUse, slots = slots, ignored = {} }
    for _, row in ipairs(slots) do
        if row.token == "ShirtSlot" or row.token == "TabardSlot" then entry.ignored[row.slot] = true end
    end
    return entry
end

local function ItemIcons(slots)
    local icons, seen = {}, {}
    for _, row in ipairs(slots) do
        local icon = Number(GetInventoryItemTexture("player", row.slot))
        if icon and not seen[icon] then
            icons[#icons + 1] = { id = icon, label = ("|T%d:16|t %s"):format(icon, row.label) }
            seen[icon] = true
        end
    end
    return icons
end

function Actions.Present(state, combat)
    state.view.setManager = not combat and state.setManager or nil
    if combat or state.setManager or state.kind ~= "character" then return false end
    if state.tab == "overview" then return state.showSets end
    return state.tab == "gear"
end

local function NameOrder(first, second)
    if first.name == second.name then return first.id < second.id end
    return first.name < second.name
end

local function ReadManager(session)
    local rows, ids = session.rows, EquipmentSetIDs()
    local count, active, selected, created = 0
    local revision = session.revision + 1
    for i = 1, ids and #ids or 0 do
        local name, equipped, id, icon, missing = SetInfo(ids[i])
        if name then
            count = count + 1
            local row = rows[count] or {}
            row.name, row.equipped, row.id, row.icon, row.missing = name, equipped, id, icon, missing
            rows[count] = row
            local draft = session.drafts[id]
            if draft and draft.name == name then draft.revision = revision end
            if id == session.selectedID then selected = row end
            if name == session.pendingName then created = row end
            if equipped and (not active or NameOrder(row, active)) then active = row end
        end
    end
    for i = count + 1, #rows do rows[i] = nil end
    for id, draft in pairs(session.drafts) do
        if draft.revision ~= revision then session.drafts[id] = nil end
    end
    table.sort(rows, NameOrder)
    selected = created or selected or active or rows[1]
    session.selected = selected
    session.selectedID = selected and selected.id
    session.pendingName = nil
    local limit = Number(MAX_EQUIPMENT_SETS_PER_PLAYER)
    session.canCreate = not limit or count < limit
    session.revision = revision
    return active and active.name or false
end

function Actions.Refresh(state)
    if state.setName == nil or NS.Host.InCombat() then return false end
    local manager, previous = state.setManager, state.setName
    if manager then state.setName = ReadManager(manager) else state.setName = Actions.ActiveName() end
    local changed = previous ~= state.setName
    if changed and not manager and state.tab == "gear" then state.view:SetContextAction(Actions.SetLabel(state.setName)) end
    return manager ~= nil or changed
end

function Actions.CloseManager(state)
    if not state.setManager then return end
    state.setManager, state.view.setManager = nil, nil
    Suite.HideQuestion(QUESTION)
end

function Actions.OpenManager(state)
    local view = state.view
    if state.setManager or state.kind ~= "character" or NS.Host.InCombat() or view:IsMinimized() or not Available() then return end
    local session = { rows = {}, drafts = {}, revision = 0, slots = state.gear.rows }
    session.canUse = function()
        return state.setManager == session and not NS.Host.InCombat() and view.frame:IsShown() and not view:IsMinimized()
    end
    state.setManager, state.slot = session, nil
    state.setName = ReadManager(session)
    return true
end

function Actions.Sync(state)
    local tab, custom = state.tab, state.custom
    local wantsSets = tab == "gear" or tab == "overview" and state.showSets or custom and custom.sets
    if not wantsSets then
        state.wantsSetManager = nil
        Actions.CloseManager(state)
    end
    if not wantsSets or NS.Host.InCombat() then
        state.setName = nil
        return false
    end
    if state.wantsSetManager then Actions.OpenManager(state) end
    if not state.setManager then state.setName = Actions.ActiveName() end
    return true
end

function Actions.Select(session, row)
    session.selectedID, session.selected = row.id, row
end

local function EntryFor(session, row)
    return { id = row.id, name = row.name, icon = row.icon, canUse = session.canUse, slots = session.slots }
end

function Actions.Equip(session, row)
    Equip(EntryFor(session, row))
end

function Actions.Pickup(session, row)
    Pickup(EntryFor(session, row))
end

local function EditEntry(session, row)
    local entry = EntryFor(session, row)
    if not CanUse(entry) then return end
    local draft = session.drafts[row.id]
    if not draft then
        draft = { name = row.name, slots = {} }
        session.drafts[row.id] = draft
    end
    entry.slotChanges = draft.slots
    entry.ignored = ReadIgnored(entry)
    return entry
end

function Actions.Save(session, row)
    local entry = EditEntry(session, row)
    if entry then AskSave(entry) end
end

function Actions.BeginEditor(session, row)
    local entry
    if row then
        entry = EntryFor(session, row)
    elseif session.canCreate then
        entry = NewEntry(session.canUse, session.slots)
        entry.manager = session
    end
    if not entry or not CanUse(entry) then return end
    entry.icons = ItemIcons(entry.slots)
    return entry
end

function Actions.ReleaseEditor(entry)
    entry.closed = true
end

function Actions.NewSlots(owner, entry)
    if entry.ignored and CanUse(entry) then Suite.ContextMenu(owner, SlotChoices, entry) end
end

function Actions.EditSlots(owner, session, row)
    local entry = EditEntry(session, row)
    if entry and entry.ignored then Suite.ContextMenu(owner, SlotChoices, entry) end
end

local function ManageSet(_, root, entry)
    root:CreateTitle(entry.name)
    root:CreateButton(String(RENAME) or Text("Rename"), AskName, entry)
    IconMenu(root, entry)
    SpecMenu(root, entry, SpecNames())
    root:CreateButton(Text("Pick up for action bar"), Pickup, entry)
    root:CreateButton(String(DELETE) or Text("Delete"), AskDelete, entry)
end

function Actions.Manage(owner, session, row)
    local entry = EntryFor(session, row)
    if not CanUse(entry) then return end
    entry.icons = ItemIcons(entry.slots)
    Suite.ContextMenu(owner, ManageSet, entry)
end

function Actions.OpenLootGoals()
    if NS.Host.InCombat() then return false end
    local planner = Suite.PlanningTools
    if planner and planner.Active() then return planner.Window.Open("loot") end
    return Suite.Open("planningTools")
end

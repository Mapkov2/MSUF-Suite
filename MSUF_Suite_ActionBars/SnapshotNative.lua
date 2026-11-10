local _, P = ...
local NS, S = P.NS, P.Suite
local AB = P.ActionBars
local Native = {}
AB.SnapshotNative = Native

-- Main pages and the four ordinary form pages share the first ten blocks.
-- The extra native multibars have their own blocks after the special pages.
local slots, commands = {}, {}
for slot = 1, 10 * AB.BUTTONS do slots[slot] = true end
for bar = AB.ENUM.BAR.FIRST_NATIVE, AB.ENUM.BAR.LAST_NATIVE do
    local first = AB.FIRST_SLOT[bar]
    for slot = first, first + AB.BUTTONS - 1 do slots[slot] = true end
end
for bar = AB.ENUM.BAR.MAIN, AB.ENUM.BAR.LAST_ACTION do
    for button = 1, AB.BUTTONS do commands[AB.COMMANDS[bar] .. button] = true end
end

local function PositiveInteger(value)
    return S.Finite(value) and value > 0 and value == math.floor(value)
end

function Native.AllowedSlot(slot)
    return PositiveInteger(slot) and slots[slot] == true
end

function Native.AllowedIndependentSlot(index)
    return PositiveInteger(index) and index <= AB.BUTTONS
end

function Native.AllowedCommand(command)
    return S.PublicText(command) and commands[command] == true
end

function Native.ValidKey(key)
    if not S.PublicText(key) or key == "" or #key > 40 or key:find("[%s%c]") then return false end
    -- WoW binding names use raw keys, including punctuation and localized keys.
    -- Gamepad keys have a PAD prefix, possibly after keyboard modifiers.
    local upper = key:upper()
    return not upper:match("^PAD") and not upper:match("%-PAD")
end

function Native.AllowedGroup(group)
    return NS.Client.isForever and S.Finite(group) and (group == 1 or group == 2)
end

function Native.Identity()
    local guid = S.PublicText(UnitGUID("player"))
    local name = S.PublicText(UnitName("player"))
    local realm = S.PublicText(GetRealmName())
    local className, token = UnitClass("player")
    local class = S.PublicText(token)
    if not (guid and name and realm and class) then return nil end
    local spec, label, selection, loadout = S.CurrentTalentLoadout()
    local group, setup
    if NS.Client.isForever then
        -- Forever uses two combat config groups for the same class spec.
        group = C_SpecializationInfo.GetActiveSpecGroup()
        if not Native.AllowedGroup(group) then return nil end
        setup = "group:" .. group
        label = S.PublicText(group == 1 and DUAL_SPEC_PRIMARY or DUAL_SPEC_SECONDARY) or label
    else
        if spec and not selection then return nil end
        setup = tostring(spec or 0) .. ":" .. (selection or "default")
    end
    return { guid = guid, name = name, realm = realm, class = class, spec = spec, group = group,
        setup = setup, setupLabel = label or S.PublicText(className) or class, loadout = loadout }
end

local function CursorEmpty()
    local kind = GetCursorInfo()
    return S.Public(kind) and kind == nil
end

function Native.Blocked()
    if NS.InCombat() then return "combat" end
    if NS.Client.isForever then
        local readMode = InputUtil.IsGamepadUIEnabled
        if not readMode then return "unavailable" end
        local gamepad = readMode()
        if not S.Public(gamepad) or type(gamepad) ~= "boolean" then return "unavailable" end
        if gamepad then return "gamepad" end
    end
    if not CursorEmpty() then return "cursor" end
end

function Native.BindingScope()
    -- Both native editors stage binding changes before saving. Saving ours
    -- during an edit would commit those pending changes as well.
    local quick = AB.Frame("QuickKeybindFrame")
    local settings = AB.Frame("SettingsPanel")
    if (quick and quick:IsShown()) or (settings and settings:IsShown()) then return nil end
    local set = GetCurrentBindingSet()
    if not S.Finite(set) then return nil end
    if set == Enum.BindingSet.Account then return "account", set end
    if set == Enum.BindingSet.Character then return "character", set end
end

-- False is a known empty slot. Nil is an occupied unsupported slot or an
-- unreadable result. It must never be used as permission to overwrite.
local function ReadSlot(slot)
    local has = C_ActionBar.HasAction(slot)
    if not S.Public(has) then return nil end
    if has == false then return false end
    if has ~= true then return nil end
    local kind, id, subtype = GetActionInfo(slot)
    if not S.Public(kind) or kind ~= "spell" or not PositiveInteger(id) or not S.Public(subtype) then return nil end
    -- The assisted-combat action can present a spell ID without storing an
    -- ordinary spell. It has no reversible representation in this format.
    if subtype == nil or subtype == "" or subtype == "spell" then return id end
end

local nativeSlots = { field = "slots", allowed = Native.AllowedSlot, read = ReadSlot }
local independentSlots = {
    field = "independentSlots", allowed = Native.AllowedIndependentSlot, read = AB.Virtual.SnapshotSpell,
}

local function BindingContext(command)
    if not Native.AllowedCommand(command) then return nil end
    local context = C_KeyBindings.GetBindingContextForAction(command)
    if S.Finite(context) then return context end
end

local function ReadKey(key, context)
    local command = GetBindingAction(key, false, context)
    if not S.Public(command) or type(command) ~= "string" then return nil end
    if command == "" then return false end
    return command
end

local function KnownSpell(spell)
    local index, bank = C_SpellBook.FindSpellBookSlotForSpell(spell, true, false)
    if not PositiveInteger(index) or not S.Public(bank) or bank ~= Enum.SpellBookSpellBank.Player then return false end
    local kind, action, id = C_SpellBook.GetSpellBookItemType(index, bank)
    if not S.Public(kind) or kind ~= Enum.SpellBookItemType.Spell then return false end
    if PositiveInteger(id) then return id == spell end
    return S.Public(id) and id == nil and PositiveInteger(action) and action == spell
end

local function CaptureKeys(output, command, context, ...)
    for index = 1, select("#", ...) do
        local key = select(index, ...)
        if Native.ValidKey(key) and ReadKey(key, context) == command then output[key] = command end
    end
end

local function CaptureSpell(record, output, slot, spell)
    if spell and KnownSpell(spell) then
        output[slot] = spell
    elseif spell ~= false then
        record.unsupportedSlots = record.unsupportedSlots + 1
    end
end

function Native.Capture()
    local blocked = Native.Blocked()
    if blocked then return nil, blocked end
    local scope = Native.BindingScope()
    if not scope then return nil, "unavailable" end
    local record = { slots = {}, keys = {}, scope = scope, unsupportedSlots = 0 }
    for slot in pairs(slots) do CaptureSpell(record, record.slots, slot, ReadSlot(slot)) end
    local independent = {}
    for index = 1, AB.BUTTONS do CaptureSpell(record, independent, index, independentSlots.read(index)) end
    if next(independent) then record.independentSlots = independent end
    for command in pairs(commands) do
        local context = BindingContext(command)
        if context then CaptureKeys(record.keys, command, context, GetBindingKey(command, nil, context)) end
    end
    return record
end

local function PlanSlots(plan, record, source)
    local incoming = record[source.field]
    if not incoming then return end
    local backup = plan.backup[source.field]
    for slot, spell in pairs(incoming) do
        if source.allowed(slot) and PositiveInteger(spell) then
            local before = source.read(slot)
            if before == nil or not KnownSpell(spell) then
                plan.skippedSlots = plan.skippedSlots + 1
            elseif before ~= spell then
                -- A replaced spell must also be pickable for the undo path.
                if before and not KnownSpell(before) then
                    plan.skippedSlots = plan.skippedSlots + 1
                else
                    backup[slot] = { before = before, after = spell }
                end
            end
        else
            plan.skippedSlots = plan.skippedSlots + 1
        end
    end
end

local function PlanKeys(plan, incoming, sameScope)
    for key, command in pairs(incoming) do
        local context = sameScope and BindingContext(command)
        if context and Native.ValidKey(key) then
            local before = ReadKey(key, context)
            if before == false then
                plan.backup.keys[key] = { before = false, after = command }
            elseif before ~= command then
                plan.skippedKeys = plan.skippedKeys + 1
            end
        else
            plan.skippedKeys = plan.skippedKeys + 1
        end
    end
end

function Native.Plan(record, applySlots, applyKeys)
    local blocked = Native.Blocked()
    if blocked then return nil, blocked end
    local identity = Native.Identity()
    if not identity then return nil, "unavailable" end
    local plan = { identity = identity, skippedSlots = 0, skippedKeys = 0,
        backup = { slots = {}, independentSlots = {}, keys = {}, scope = record.scope } }
    if applySlots then
        PlanSlots(plan, record, nativeSlots)
        PlanSlots(plan, record, independentSlots)
    end
    if applyKeys then PlanKeys(plan, record.keys, Native.BindingScope() == record.scope) end
    return plan
end

local function CursorSpell()
    local kind, _, _, spell = GetCursorInfo()
    if S.Public(kind) and kind == "spell" and PositiveInteger(spell) then return spell end
end

local function PlaceSpell(slot, before, spell)
    S.Dispatch(C_Spell.PickupSpell, spell)
    local held = CursorSpell()
    if NS.InCombat() then return false end
    if held ~= spell or ReadSlot(slot) ~= before then
        -- Pickup started from an empty cursor. A readable spell here is the
        -- payload of that pickup, even if the client substituted its rank.
        if held then S.Dispatch(ClearCursor) end
        return false
    end
    S.Dispatch(PlaceAction, slot)
    local actual = ReadSlot(slot)
    held = CursorSpell()
    if not NS.InCombat() and (held == spell or (held == before and actual == spell)) then
        S.Dispatch(ClearCursor)
        actual = ReadSlot(slot)
    end
    return actual == spell
end

local function ClearSpell(slot, spell)
    S.Dispatch(PickupAction, slot)
    local actual = ReadSlot(slot)
    if actual == false and CursorSpell() == spell and not NS.InCombat() then
        S.Dispatch(ClearCursor)
        actual = ReadSlot(slot)
    end
    return actual == false
end

function nativeSlots.write(slot, before, after)
    if after == false then return ClearSpell(slot, before) end
    return PlaceSpell(slot, before, after)
end

independentSlots.write = AB.Virtual.SetSnapshotSpell

local function NewReport(skippedSlots, skippedKeys, scope)
    return { slots = 0, keys = 0, skippedSlots = skippedSlots, skippedKeys = skippedKeys,
        backup = { slots = {}, independentSlots = {}, keys = {}, scope = scope } }
end

local function Values(change, restore)
    if restore then return change.after, change.before end
    return change.before, change.after
end

local function ApplySlots(report, backup, restore, source)
    local changes = backup[source.field]
    if not changes then return end
    local retained = report.backup[source.field]
    for slot, change in pairs(changes) do
        local blocked = Native.Blocked()
        local before, after = Values(change, restore)
        local applied = false
        if not blocked and source.allowed(slot) and before ~= nil and source.read(slot) == before then
            if after == false then
                applied = PositiveInteger(before) and source.write(slot, before, after)
            elseif PositiveInteger(after) and KnownSpell(after) and (restore or before == false or KnownSpell(before)) then
                applied = source.write(slot, before, after)
            end
        end
        if applied then
            report.slots = report.slots + 1
            if not restore then retained[slot] = change end
        else
            report.skippedSlots = report.skippedSlots + 1
            if restore and blocked then retained[slot] = change end
            report.reason = report.reason or blocked
        end
    end
end

local function ApplyKeys(report, changes, scope, restore)
    for key, change in pairs(changes) do
        local blocked = Native.Blocked()
        local before, after = Values(change, restore)
        local sameScope = scope ~= nil and Native.BindingScope() == scope
        local context = sameScope and BindingContext(restore and before or after)
        local applied = false
        if not blocked and context and Native.ValidKey(key) and before ~= nil and ReadKey(key, context) == before
            and (after == false or BindingContext(after) == context) then
            S.Dispatch(SetBinding, key, after or nil, context)
            applied = ReadKey(key, context) == after
        end
        if applied then
            report.keys = report.keys + 1
            if not restore then report.backup.keys[key] = change end
        else
            report.skippedKeys = report.skippedKeys + 1
            if restore and (blocked or not sameScope) then report.backup.keys[key] = change end
            report.reason = report.reason or blocked
        end
    end
    if report.keys > 0 then
        local currentScope, set = Native.BindingScope()
        if currentScope == scope and not NS.InCombat() then
            S.Dispatch(SaveBindings, set)
        else
            report.reason = report.reason or (NS.InCombat() and "combat" or "unavailable")
        end
    end
end

local function Execute(backup, report, restore)
    ApplySlots(report, backup, restore, nativeSlots)
    ApplySlots(report, backup, restore, independentSlots)
    ApplyKeys(report, backup.keys, backup.scope, restore)
    local retained = report.backup
    if not next(retained.independentSlots) then retained.independentSlots = nil end
    if not next(retained.slots) and not retained.independentSlots and not next(retained.keys) then report.backup = nil end
    report.reason = report.reason or Native.Blocked()
    return report
end

function Native.Apply(plan)
    local blocked = Native.Blocked()
    if blocked then return nil, blocked end
    local now = Native.Identity()
    if not now or now.guid ~= plan.identity.guid or now.setup ~= plan.identity.setup then return nil, "stale" end
    local backup = plan.backup
    return Execute(backup, NewReport(plan.skippedSlots, plan.skippedKeys, backup.scope), false)
end

function Native.Restore(backup)
    local blocked = Native.Blocked()
    if blocked then return nil, blocked end
    return Execute(backup, NewReport(0, 0, backup.scope), true)
end

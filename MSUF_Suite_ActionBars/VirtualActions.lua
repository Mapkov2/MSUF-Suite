local _, P = ...
local NS, S = P.NS, P.Suite
local AB = P.ActionBars
local BAR = AB.ENUM.BAR
local Virtual = {}
AB.Virtual = Virtual

-- Bar 10's assignments belong to the character and spec, like native
-- action pages. Open SavedVariables on enable, after the LoD addon's load.
-- The old page 10 belongs to forms and is never read or written here.
local assignments, activeSpec, pending, specEvent
local ATTRIBUTE = {
    spell = "spell", item = "item", macro = "macro", flyout = "spell",
    toy = "toy", equipmentset = "equipmentset", outfit = "outfit-index",
    mount = "spell", battlepet = "macrotext",
}

local function ValidID(id)
    return S.Finite(id) and id >= 1 and id % 1 == 0
end

local function ValidAction(action)
    if not S.Public(action) or type(action) ~= "table" then return end
    local kind, id = action.kind, action.id
    if not S.Public(kind) or not S.Public(id) or type(kind) ~= "string" or not ATTRIBUTE[kind] then return end
    if kind == "macro" then
        return type(id) == "string" and #id > 0 and #id <= 64 and action or nil
    elseif kind == "battlepet" then
        return type(id) == "string" and #id <= 64 and id:match("^BattlePet%-%x[%x%-]+$") and action or nil
    elseif kind == "outfit" and id == 0 then
        return action
    end
    return ValidID(id) and action or nil
end

local function SpecKey()
    if NS.Client.isForever then
        local group = C_SpecializationInfo.GetActiveSpecGroup()
        if ValidID(group) then return group end
        return
    end
    local index = C_SpecializationInfo.GetSpecialization()
    if not ValidID(index) then return 0 end
    local spec = C_SpecializationInfo.GetSpecializationInfo(index)
    if ValidID(spec) then return spec end
end

local function CurrentAssignments(spec)
    local saved = _G.MSUFSuiteIndependentBar
    if type(saved) ~= "table" then
        saved = {}
        _G.MSUFSuiteIndependentBar = saved
    end
    local slots = saved[spec]
    if type(slots) ~= "table" then
        slots = {}
        saved[spec] = slots
    end
    return slots
end

local function SecureAction(action)
    if not action then return end
    local kind, id = action.kind, action.id
    if kind == "item" then return kind, ATTRIBUTE[kind], "item:" .. id end
    if kind == "macro" then
        local index = GetMacroIndexByName(id)
        if ValidID(index) then return kind, ATTRIBUTE[kind], index end
    elseif kind == "equipmentset" then
        local name = C_EquipmentSet.GetEquipmentSetInfo(id)
        if S.Public(name) and type(name) == "string" then return kind, ATTRIBUTE[kind], name end
    elseif kind == "mount" then
        local _, spell = C_MountJournal.GetMountInfoByID(id)
        if ValidID(spell) then return "spell", ATTRIBUTE[kind], spell end
    elseif kind == "battlepet" then
        local slash = _G.SLASH_SUMMON_BATTLE_PET1
        if slash then return "macro", ATTRIBUTE[kind], slash .. " " .. id end
    elseif kind == "outfit" then
        if id == 0 then return kind, "action", "clear" end
        local info = C_TransmogOutfitInfo.GetOutfitInfo(id)
        if S.Public(info) and type(info) == "table" and ValidID(info.playerFacingOutfitIndex) then
            return kind, ATTRIBUTE[kind], info.playerFacingOutfitIndex
        end
    else
        return kind, ATTRIBUTE[kind], id
    end
end

local function Apply(rec, action)
    local kind, attribute, value = SecureAction(action)
    local button = rec.button
    if rec.virtualAttribute and rec.virtualAttribute ~= attribute then
        button:SetAttribute(rec.virtualAttribute, nil)
    end
    if attribute and button:GetAttribute(attribute) ~= value then button:SetAttribute(attribute, value) end
    if button:GetAttribute("type") ~= kind then button:SetAttribute("type", kind) end
    local filled = action ~= nil
    if button:GetAttribute("independentfilled") ~= filled then button:SetAttribute("independentfilled", filled) end
    rec.virtualAttribute, rec.virtualAction = attribute, action
end

local function Repaint(bar)
    AB.Execute(bar.header, AB.SNIPPET.GRID)
    AB.MarkBar(bar)
    AB.VirtualPaint.SyncEvents(AB.M.context)
    EventRegistry:TriggerEvent("MSUFSuite.ActionBars.ActionsChanged")
end

function Virtual.Sync(force)
    if NS.InCombat() then
        pending = true
        return
    end
    local spec = SpecKey()
    if spec == nil or (spec == activeSpec and not force) then return end
    local bar = AB.bars[BAR.INDEPENDENT]
    local changed = activeSpec ~= spec
    activeSpec, assignments = spec, CurrentAssignments(spec)
    pending = nil
    for i = 1, #bar.buttons do Apply(bar.buttons[i], ValidAction(assignments[i])) end
    Repaint(bar)
    if changed and AB.snapshotSetupChanged then AB.snapshotSetupChanged() end
end

function Virtual.Resume()
    if pending then Virtual.Sync(true) end
end

local function SpecChanged(_, event, unit)
    if event == "ACTIVE_COMBAT_CONFIG_CHANGED" or unit == "player" then Virtual.Sync() end
end

local function MacroChanged()
    Virtual.Sync(true)
end

local IN_COMBAT = { inCombat = true }
function Virtual.Start(context)
    specEvent = NS.Client.isForever and "ACTIVE_COMBAT_CONFIG_CHANGED" or "PLAYER_SPECIALIZATION_CHANGED"
    context:Event(specEvent, SpecChanged, IN_COMBAT)
    context:Event("UPDATE_MACROS", MacroChanged, IN_COMBAT)
    Virtual.Sync()
end

function Virtual.Stop(context)
    if specEvent then context:RemoveEvent(specEvent) end
    context:RemoveEvent("UPDATE_MACROS")
    assignments, activeSpec, pending, specEvent = nil, nil, nil, nil
end

local function CursorAction()
    local kind, id, detail, spellID = GetCursorInfo()
    if not S.Public(kind) or not S.Public(id) or not S.Public(detail) or not S.Public(spellID) then return end
    if kind == "spell" then
        id = spellID
    elseif kind == "macro" and ValidID(id) then
        local name = GetMacroInfo(id)
        if not S.Public(name) or type(name) ~= "string" or GetMacroIndexByName(name) ~= id then return end
        id = name
    elseif kind == "equipmentset" and type(id) == "string" then
        id = C_EquipmentSet.GetEquipmentSetID(id)
    elseif kind == "flyout" and ValidID(spellID) then
        local info = C_SpellBook.GetSpellBookItemInfo(spellID, Enum.SpellBookSpellBank.Player)
        if not S.Public(info) or type(info) ~= "table" then return end
        id = info.actionID
    elseif kind == "item" and ValidID(id) and PlayerHasToy(id) then
        kind = "toy"
    end
    return ValidAction({ kind = kind, id = id })
end

local function FlyoutPickup(id)
    local bank = Enum.SpellBookSpellBank.Player
    for line = 1, C_SpellBook.GetNumSpellBookSkillLines() do
        local info = C_SpellBook.GetSpellBookSkillLineInfo(line)
        if info then
            local offset = info.itemIndexOffset
            for slot = offset + 1, offset + info.numSpellBookItems do
                local entry = C_SpellBook.GetSpellBookItemInfo(slot, bank)
                if entry and entry.itemType == Enum.SpellBookItemType.Flyout and entry.actionID == id then
                    C_SpellBook.PickupSpellBookItem(slot, bank)
                    return
                end
            end
        end
    end
end

local function PickupMount(id)
    -- Pickup accepts a visible journal row, while the cursor carries a mount ID.
    for index = 1, C_MountJournal.GetNumDisplayedMounts() do
        local mountID = select(12, C_MountJournal.GetDisplayedMountInfo(index))
        if S.Public(mountID) and mountID == id then
            C_MountJournal.Pickup(index)
            return
        end
    end
end

local function PickupNative(action)
    local kind, id = action.kind, action.id
    if kind == "spell" then
        C_Spell.PickupSpell(id)
    elseif kind == "item" then
        C_Item.PickupItem(id)
    elseif kind == "macro" then
        local index = GetMacroIndexByName(id)
        if ValidID(index) then PickupMacro(index) end
    elseif kind == "flyout" then
        FlyoutPickup(id)
    elseif kind == "equipmentset" then
        C_EquipmentSet.PickupEquipmentSet(id)
    elseif kind == "toy" then
        C_ToyBox.PickupToyBoxItem(id)
    elseif kind == "mount" then
        PickupMount(id)
    elseif kind == "battlepet" then
        C_PetJournal.PickupPet(id)
    elseif kind == "outfit" then
        C_TransmogOutfitInfo.PickupOutfit(id)
    end
end

local function Pickup(action)
    S.Dispatch(PickupNative, action)
    local cursor = CursorAction()
    return cursor and cursor.kind == action.kind and cursor.id == action.id
end

local function Editable(button)
    local rec = AB.records[button]
    if not AB.M.active or NS.InCombat() or not assignments or activeSpec ~= SpecKey() then return end
    return rec
end

local function Set(rec, action)
    assignments[rec.index] = action
    Apply(rec, action)
    Repaint(rec.bar)
    if AB.snapshotChanged then AB.snapshotChanged() end
end

function Virtual.SnapshotSpell(index)
    if not assignments or activeSpec ~= SpecKey() then return end
    local action = assignments[index]
    if action == nil then return false end
    action = ValidAction(action)
    if action and action.kind == "spell" then return action.id end
end

function Virtual.SetSnapshotSpell(index, before, after)
    if not ValidID(index) or index > AB.BUTTONS or NS.InCombat() or before == nil
        or Virtual.SnapshotSpell(index) ~= before then return false end
    if after ~= false and not ValidID(after) then return false end
    local rec = AB.bars[BAR.INDEPENDENT].buttons[index]
    Set(rec, after and { kind = "spell", id = after } or nil)
    return true
end

local function Drag(button)
    local rec = Editable(button)
    if not rec or not rec.virtualAction then return end
    local held = GetCursorInfo()
    if not S.Public(held) or held then return end
    if not (AB.grid:GetAttribute("unlocked") or IsModifiedClick("PICKUPACTION")) then return end
    if Pickup(rec.virtualAction) then Set(rec, nil) end
end

local function Drop(button)
    local rec = Editable(button)
    if not rec then return end
    local action = CursorAction()
    if not action or not SecureAction(action) then return end
    local previous = rec.virtualAction
    if previous then
        -- Native pickup can decline, e.g. a mount hidden by journal filters.
        -- Keep the slot until the old action is safely on the cursor.
        if previous.kind == action.kind and previous.id == action.id then return end
        if not Pickup(previous) then
            local held = GetCursorInfo()
            if S.Public(held) and held == nil then Pickup(action) end
            return
        end
        Set(rec, action)
    else
        Set(rec, action)
        ClearCursor()
    end
end

-- A click while holding an action places it, just like a release-drag.
-- Suppress the direct secure cast for this click while the cursor is busy.
local CLICK = [[
if self:GetAttribute("independentdrop") then return false end
]] .. AB.SNIPPET.CLICK
local function BeforeClick(button, mouse, down)
    if mouse == "Keybind" or down or not Editable(button) then return end
    local held = GetCursorInfo()
    if S.Public(held) and held then
        button:SetAttribute("independentdrop", true)
        Drop(button)
    end
end

local function AfterClick(button)
    if button:GetAttribute("independentdrop") and not NS.InCombat() then
        button:SetAttribute("independentdrop", nil)
    end
end

local GRID = [[
local bar=self:GetParent()
local show=(self:GetAttribute("index") or 1)<=(bar:GetAttribute("count") or 12)
if show and not self:GetAttribute("independentfilled") and not bar:GetAttribute("showempty")
    and (bar:GetAttribute("gridmask") or 0)<2 then show=false end
if show then self:Show() else self:Hide() end
]]
function Virtual.Setup(rec)
    local button = rec.button
    button:SetAttribute("_childupdate-grid", GRID)
    button:SetScript("PreClick", BeforeClick)
    button:SetScript("PostClick", AfterClick)
    SecureHandlerWrapScript(button, "OnClick", AB.grid, CLICK)
    button:SetScript("OnDragStart", Drag)
    button:SetScript("OnReceiveDrag", Drop)
end

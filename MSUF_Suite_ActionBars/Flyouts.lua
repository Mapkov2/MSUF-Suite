local _, P = ...
local NS, S = P.NS, P.Suite
-- Action bar flyouts, data side (FlyoutFrames.lua is the secure side). A
-- flyout is a list of spells, items, toys, mounts and macros; one account-wide
-- WoW macro per flyout ("/click MSUFSuiteFlyouts <id>") goes onto any Suite
-- action button and opens it, also in combat. Saved per account and per WoW
-- version (MSUFSuiteFlyoutsDB[retail|forever]), outside the Suite profiles.
-- All work happens out of combat: the listener unregisters its bag, slot,
-- macro and spell events at PLAYER_REGEN_DISABLED (before the lockdown) and
-- catches up once at PLAYER_REGEN_ENABLED. Without a flyout nothing is
-- created and nothing listens.
local AB = P.ActionBars
local Frames = AB.FlyoutFrames
local Data = NS.ActionBarFlyouts
local Flyouts = {}
AB.Flyouts = Flyouts

local Public, Finite, PublicText = S.Public, S.Finite, S.PublicText
local CLIENT = Data.Client()
local MARKER = "/click " .. Frames.OPENER .. " "
local UNKNOWN_ICON = 134400
local MAX_SLOT = 180
-- Consumable / Food & Drink (Enum.ItemClass, Enum.ItemConsumableSubclass).
local FOOD_CLASS, FOOD_SUBCLASS = 0, 5
local LAST_BAG = NUM_TOTAL_EQUIPPED_BAG_SLOTS or NUM_BAG_SLOTS or 4
local CHANGED = "MSUFSuite.ActionBars.FlyoutsChanged"
-- Listened to only out of combat and only while a flyout exists.
local QUIET = { "BAG_UPDATE_DELAYED", "ACTIONBAR_SLOT_CHANGED", "UPDATE_MACROS", "SPELLS_CHANGED", "NEW_TOY_ADDED",
    "NEW_MOUNT_ADDED", "PLAYER_LEVEL_UP" }

local store, active, pending, scheduled, built, listener, quiet
local macroOf, flyoutOfMacro, flyoutOfName = {}, {}, {}
local slotFlyout, indexFlyout, shownCount = {}, {}, {}

------------------------------------------------------------------ store
local function Store()
    if store then return store end
    local saved = MSUFSuiteFlyoutsDB
    if type(saved) ~= "table" then
        saved = {}
        MSUFSuiteFlyoutsDB = saved
    end
    store = Data.CleanStore(saved[CLIENT])
    saved[CLIENT] = store
    return store
end

local function Find(id)
    for position, flyout in ipairs(Store().list) do
        if flyout.id == id then return flyout, position end
    end
end

------------------------------------------------------------------ macros
-- Which account or character macro opens which flyout, by its body.
local function ReadMacro(index)
    local name, _, body = GetMacroInfo(index)
    if not PublicText(name) or not PublicText(body) or body:sub(1, #MARKER) ~= MARKER then return end
    local id = tonumber(body:sub(#MARKER + 1):match("^(%d+)%s*$"))
    if not id or macroOf[id] or not Find(id) then return end
    macroOf[id], flyoutOfMacro[index] = index, id
    flyoutOfName[name] = flyoutOfName[name] == nil and id or false
end

local function ScanMacros()
    wipe(macroOf)
    wipe(flyoutOfMacro)
    wipe(flyoutOfName)
    local limit = Constants.MacroConsts.MAX_ACCOUNT_MACROS
    local account, character = GetNumMacros()
    if not Finite(limit) or not Finite(account) or not Finite(character) then return end
    for index = 1, account do ReadMacro(index) end
    for index = limit + 1, limit + character do ReadMacro(index) end
end

-- The flyout a slot's macro opens. A macro without a spell or item reports
-- its index; the macro name covers any other answer.
local function SlotOwner(slot)
    local kind, id, sub = GetActionInfo(slot)
    if not Public(kind) or kind ~= "macro" or not Public(id) or not Public(sub) then return nil end
    if flyoutOfMacro[id] then return flyoutOfMacro[id] end
    if sub == "spell" or sub == "item" then return nil end
    local name = GetActionText(slot)
    return PublicText(name) and flyoutOfName[name] or nil
end

local function MapSlot(slot)
    local id = SlotOwner(slot)
    if slotFlyout[slot] == id then return end
    slotFlyout[slot] = id
    Frames.SetSlot(slot, id)
end

-- Slots for the paged and reused buttons; macro indices for bar 10, whose
-- buttons hold a macro directly (VirtualActions.lua).
local function MapAll()
    for slot = 1, MAX_SLOT do MapSlot(slot) end
    for index, id in pairs(indexFlyout) do
        if flyoutOfMacro[index] ~= id then
            indexFlyout[index] = nil
            Frames.SetMacro(index, nil)
        end
    end
    for index, id in pairs(flyoutOfMacro) do
        if indexFlyout[index] ~= id then
            indexFlyout[index] = id
            Frames.SetMacro(index, id)
        end
    end
end

------------------------------------------------------------------ entries
local function ItemEntry(id, kind)
    local toy = kind == "toy"
    local icon, name = C_Item.GetItemIconByID(id), C_Item.GetItemNameByID(id)
    return { kind = kind, id = id, item = id, type = toy and "toy" or "item", attribute = toy and "toy" or "item",
        value = toy and id or "item:" .. id, icon = Public(icon) and icon or nil, name = PublicText(name) or nil }
end

local function SpellEntry(kind, id, spell, icon, name)
    icon = icon or C_Spell.GetSpellTexture(spell)
    name = name or C_Spell.GetSpellName(spell)
    return { kind = kind, id = id, spell = spell, type = "spell", attribute = "spell", value = spell,
        icon = Public(icon) and icon or nil, name = PublicText(name) or nil }
end

local function Yes(value)
    return Public(value) and value == true
end

local function Carried(id)
    local count = C_Item.GetItemCount(id)
    return Finite(count) and count > 0
end

-- A saved entry as a secure action; nil when it cannot act now, or when the
-- flyout shows only what the character carries or knows.
local function Resolve(saved, owned)
    local kind, id = saved.kind, saved.id
    if kind == "item" then
        if owned and not Carried(id) then return nil end
        return ItemEntry(id, kind)
    elseif kind == "toy" then
        if owned and not Yes(PlayerHasToy(id)) then return nil end
        return ItemEntry(id, kind)
    elseif kind == "spell" then
        if owned and not Yes(IsPlayerSpell(id)) then return nil end
        return SpellEntry(kind, id, id)
    elseif kind == "mount" then
        local name, spell, icon, _, _, _, _, _, _, _, collected = C_MountJournal.GetMountInfoByID(id)
        if not Finite(spell) or owned and not Yes(collected) then return nil end
        return SpellEntry(kind, id, spell, icon, name)
    elseif kind == "macro" then
        local index = GetMacroIndexByName(id)
        if not Finite(index) or index < 1 then return nil end
        local _, icon = GetMacroInfo(index)
        return { kind = kind, id = id, type = "macro", attribute = "macro", value = index,
            icon = Public(icon) and icon or nil, name = id }
    end
end

-- Usable Food & Drink items in the bags, highest required level first.
local function FoodRank(id)
    local _, _, _, level, minimum = C_Item.GetItemInfo(id)
    return (Finite(minimum) and minimum or 0) * 10000 + (Finite(level) and level or 0)
end

local function IsFood(id)
    local _, _, _, _, _, class, subclass = C_Item.GetItemInfoInstant(id)
    return class == FOOD_CLASS and subclass == FOOD_SUBCLASS and Yes((C_Item.IsUsableItem(id)))
end

local function BagFood()
    local found, seen, rank = {}, {}, {}
    for bag = 0, LAST_BAG do
        local slots = C_Container.GetContainerNumSlots(bag)
        for slot = 1, Finite(slots) and slots or 0 do
            local id = C_Container.GetContainerItemID(bag, slot)
            if Finite(id) and not seen[id] then
                seen[id] = true
                if IsFood(id) then
                    found[#found + 1], rank[id] = id, FoodRank(id)
                end
            end
        end
    end
    table.sort(found, function(a, b)
        if rank[a] ~= rank[b] then return rank[a] > rank[b] end
        return a > b
    end)
    return found
end

local function Add(list, seen, entry)
    if not entry or #list >= Data.MAX_SHOWN then return end
    local key = entry.type .. ":" .. tostring(entry.value)
    if seen[key] then return end
    seen[key] = true
    list[#list + 1] = entry
end

-- What a flyout shows now, in its order.
local function Shown(flyout)
    local list, seen = {}, {}
    for _, saved in ipairs(flyout.entries) do
        if saved.kind == "bag" then
            for _, id in ipairs(BagFood()) do Add(list, seen, ItemEntry(id, "item")) end
        else
            Add(list, seen, Resolve(saved, flyout.owned))
        end
    end
    return list
end

------------------------------------------------------------------ sync
local function ApplyAll()
    local current = {}
    for _, flyout in ipairs(Store().list) do
        local list = Shown(flyout)
        Frames.Apply(flyout.id, list)
        shownCount[flyout.id], current[flyout.id] = #list, true
    end
    for id in pairs(shownCount) do
        if not current[id] then
            Frames.Remove(id)
            shownCount[id] = nil
        end
    end
end

local function Quiet(on)
    if quiet == on then return end
    quiet = on
    for _, event in ipairs(QUIET) do
        if NS.Client.SupportsEvent(event) then
            if on then listener:RegisterEvent(event) else listener:UnregisterEvent(event) end
        end
    end
end

local Sync
local function Schedule()
    if scheduled then return end
    scheduled = true
    C_Timer.After(0, function() Sync() end)
end

local function OnEvent(_, event, slot)
    if event == "PLAYER_REGEN_DISABLED" then
        Quiet(false)
        Frames.CloseAll()
    elseif event == "PLAYER_REGEN_ENABLED" then
        Quiet(true)
        Sync()
    elseif event == "ACTIONBAR_SLOT_CHANGED" and Finite(slot) and slot >= 1 and slot <= MAX_SLOT then
        MapSlot(slot)
    else
        Schedule()
    end
end

-- Combat transitions only while a flyout exists; the quiet events only
-- outside combat.
local function SyncEvents()
    local wanted = active and #Store().list > 0
    if not wanted and not listener then return end
    if not listener then
        listener = S.CreateFrame("Frame")
        listener:SetScript("OnEvent", OnEvent)
    end
    if wanted then
        listener:RegisterEvent("PLAYER_REGEN_DISABLED")
        listener:RegisterEvent("PLAYER_REGEN_ENABLED")
        Quiet(not NS.InCombat())
    else
        listener:UnregisterAllEvents()
        quiet = false
    end
end

function Sync()
    scheduled = nil
    if not active then return end
    if NS.IsCombatLocked() then
        pending = true
        return
    end
    pending = nil
    if not built then
        if #Store().list == 0 then return SyncEvents() end
        built = true
        Frames.Candidates(AB.owned)
    end
    Frames.SetEnabled(true)
    ScanMacros()
    ApplyAll()
    MapAll()
    SyncEvents()
end
Flyouts.Sync = Sync

-- ActionBars Controller: Enable and Disable run out of combat.
function Flyouts.Start()
    active = true
    Sync()
end

function Flyouts.Stop()
    active, pending = false, nil
    if not NS.IsCombatLocked() then Frames.SetEnabled(false) end
    if listener then
        listener:UnregisterAllEvents()
        quiet = false
    end
end

------------------------------------------------------------------ editing
local function Changed()
    Sync()
    EventRegistry:TriggerEvent(CHANGED)
    return true
end

local function MacroIcon(flyout)
    if flyout.icon then return flyout.icon end
    local first = Shown(flyout)[1]
    return first and first.icon or UNKNOWN_ICON
end

-- Creates or updates the flyout's account-wide macro; its index or nil, error.
local function WriteMacro(flyout)
    ScanMacros()
    local index, body, icon = macroOf[flyout.id], MARKER .. flyout.id, MacroIcon(flyout)
    if index then
        local name, current = GetMacroInfo(index)
        if name ~= flyout.name or current ~= icon then EditMacro(index, flyout.name, icon, body) end
    else
        local account = GetNumMacros()
        if not Finite(account) or account >= Constants.MacroConsts.MAX_ACCOUNT_MACROS then
            return nil, "Your account-wide macros are full. Delete one to place this flyout."
        end
        CreateMacro(flyout.name, icon, body, false)
    end
    ScanMacros()
    MapAll()
    index = macroOf[flyout.id]
    if not index then return nil, "The flyout macro could not be created." end
    return index
end

local function Editable(id)
    if not active then return nil, "Turn on the Suite action bars to use flyouts." end
    if NS.InCombat() then return nil, "Flyouts can be edited out of combat." end
    if id == nil then return true end
    local flyout, position = Find(id)
    if not flyout then return nil, "This flyout no longer exists." end
    return flyout, position
end

local function NewFlyout(name, entries, icon, preset)
    local data = Store()
    if #data.list >= Data.MAX_FLYOUTS then return nil, "You have reached the maximum number of flyouts." end
    local flyout = Data.CleanFlyout({ id = data.nextID, name = name, entries = entries, icon = icon, preset = preset })
    if not flyout then return nil, "Enter a name for the flyout." end
    data.nextID = data.nextID + 1
    data.list[#data.list + 1] = flyout
    Changed()
    return flyout.id
end

local function CursorEntry()
    local kind, id, _, spell = GetCursorInfo()
    if not Public(kind) or not Public(id) or not Public(spell) then return nil end
    if kind == "spell" and Finite(spell) then return { kind = "spell", id = spell } end
    if kind == "item" and Finite(id) then return { kind = Yes(PlayerHasToy(id)) and "toy" or "item", id = id } end
    if kind == "mount" and Finite(id) then return { kind = "mount", id = id } end
    if kind == "macro" and Finite(id) then
        local name, _, body = GetMacroInfo(id)
        if PublicText(body) and body:sub(1, #MARKER) == MARKER then return nil, "A flyout cannot hold another flyout." end
        return PublicText(name) and { kind = "macro", id = name } or nil
    end
    return nil
end

-- Shared with FlyoutAPI.lua.
Flyouts.Store, Flyouts.Find, Flyouts.Shown, Flyouts.Changed = Store, Find, Shown, Changed
Flyouts.WriteMacro, Flyouts.Editable, Flyouts.NewFlyout, Flyouts.CursorEntry = WriteMacro, Editable, NewFlyout, CursorEntry
Flyouts.MapSlot, Flyouts.ScanMacros, Flyouts.macroOf, Flyouts.shownCount = MapSlot, ScanMacros, macroOf, shownCount
Flyouts.MARKER = MARKER

-- Read-only views for the contract tests; nothing in the addon calls them.
AB.Diagnostics.FlyoutData = {
    SlotFlyout = slotFlyout, IndexFlyout = indexFlyout,
    Listener = function() return listener end, Quiet = function() return quiet end,
}

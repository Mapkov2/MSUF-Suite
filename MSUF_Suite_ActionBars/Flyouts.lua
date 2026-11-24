local _, P = ...
local NS, S = P.NS, P.Suite
-- Action bar flyouts, data side (FlyoutFrames.lua is the secure side). A
-- flyout is a list of spells, items, toys, mounts and macros; one account-wide
-- WoW macro per flyout ("/click MSUFSuiteFlyouts <id>") goes onto any Suite
-- action button and opens it, also in combat. Saved per account and per WoW
-- version (MSUFSuiteFlyoutsDB[retail|forever]), outside the Suite profiles.
-- Closed flyouts subscribe to no events. The opener prepares one flyout out
-- of combat. A combat click uses the secure snapshot from startup or the
-- last preparation. Macro changes refresh the secure launcher and macro entries.
local AB = P.ActionBars
local Frames = AB.FlyoutFrames
local Data = NS.ActionBarFlyouts
local Flyouts = {}
AB.Flyouts = Flyouts

local Public, Finite, PublicText = S.Public, S.Finite, S.PublicText
local CLIENT = Data.Client()
local MARKER = "/click " .. Frames.OPENER .. " "
local UNKNOWN_ICON = 134400
-- Consumable / Food & Drink (Enum.ItemClass, Enum.ItemConsumableSubclass).
local FOOD_CLASS, FOOD_SUBCLASS = 0, 5
local LAST_BAG = NUM_TOTAL_EQUIPPED_BAG_SLOTS or NUM_BAG_SLOTS or 4
local CHANGED = "MSUFSuite.ActionBars.FlyoutsChanged"
local BAG_UPDATE = "BAG_UPDATE_DELAYED"
local OPEN_EVENTS = { "SPELLS_CHANGED", "NEW_TOY_ADDED", "NEW_MOUNT_ADDED", "PLAYER_LEVEL_UP" }

local store, active, scheduled, built, listener, openID, listeningBags
local pendingFull, pendingBags
local pendingMacros
local macroOf, flyoutOfMacro, flyoutOfName = {}, {}, {}
local indexFlyout, shownCount, bagDependencies = {}, {}, {}

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

local function HasMarker(kind, index, subtype)
    if not Public(kind) then return end
    if kind ~= "macro" then return false end
    if not Public(index) or not Public(subtype) then return end
    return subtype ~= "spell" and subtype ~= "item" and Finite(index) and flyoutOfMacro[index] ~= nil
end

local function PaintMarker(rec, shown)
    if shown == nil then
        AB.flyoutMarkerPending = true
    else
        Frames.Marker(rec, shown)
    end
end

function Flyouts.SlotMarkers(records, kind, index, subtype)
    local shown = HasMarker(kind, index, subtype)
    for i = 1, #records do
        local rec = records[i]
        if rec.bar.owned and not rec.virtual then PaintMarker(rec, shown) end
    end
end

function Flyouts.BarMarkers(bar)
    if not bar.owned then return end
    for _, rec in ipairs(bar.buttons) do
        local shown = false
        if AB.flyoutMarkers then
            if rec.virtual then
                shown = HasMarker(rec.button:GetAttribute("type"), rec.button:GetAttribute("macro"))
            elseif rec.slot then
                shown = HasMarker(GetActionInfo(rec.slot))
            end
        end
        PaintMarker(rec, shown)
    end
end

local function UpdateMarkers(enabled)
    if not enabled and not AB.flyoutMarkers then return end
    AB.flyoutMarkers = enabled and true or nil
    for _, bar in pairs(AB.bars) do Flyouts.BarMarkers(bar) end
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

function Flyouts.RefreshMarkers()
    UpdateMarkers(true)
end

local function MarkersEnabled()
    return AB.M.config.flyoutArrow ~= false and #Store().list > 0
end

function Flyouts.RefreshMarkerAppearance()
    if not active then return end
    local enabled = MarkersEnabled()
    if enabled and not AB.flyoutMarkers then ScanMacros() end
    UpdateMarkers(enabled)
end

-- The flyout a slot's macro opens. A macro without a spell or item reports
-- its index; the macro name covers any other answer.
local function SlotOwner(slot)
    local kind, id, sub = GetActionInfo(slot)
    if not Public(kind) or kind ~= "macro" or not Public(id) or not Public(sub) then return nil end
    if sub == "spell" or sub == "item" then return nil end
    if flyoutOfMacro[id] then return flyoutOfMacro[id] end
    local name = GetActionText(slot)
    return PublicText(name) and flyoutOfName[name] or nil
end

-- The opener samples the live action slot on the click, so there is no slot-event cache.
local function MapMacros()
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
        return { kind = kind, id = id, type = "macro", attribute = "macro", value = id,
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

local function Add(list, seen, entry, saved, position)
    if not entry or #list >= Data.MAX_SHOWN then return end
    local key = entry.type .. ":" .. tostring(entry.value)
    if seen[key] then return end
    seen[key] = true
    entry.source, entry.position = saved, position
    list[#list + 1] = entry
end

-- What a flyout shows now, in its order.
local function Shown(flyout)
    local list, seen = {}, {}
    local excluded = flyout.excludedFood
    local tracksBags = false
    for position, saved in ipairs(flyout.entries) do
        if saved.kind == "bag" then
            tracksBags = true
            for _, id in ipairs(BagFood()) do
                if not (excluded and excluded[id]) then Add(list, seen, ItemEntry(id, "item"), saved, position) end
            end
        else
            if flyout.owned and saved.kind == "item" then tracksBags = true end
            Add(list, seen, Resolve(saved, flyout.owned), saved, position)
        end
    end
    return list, tracksBags
end

------------------------------------------------------------------ sync
local function Apply(flyout)
    local id = flyout.id
    local entries, tracksBags = Shown(flyout)
    shownCount[id], bagDependencies[id] = #entries, tracksBags or nil
    Frames.Apply(id, entries)
end

local function ApplyAll()
    local current = {}
    for _, flyout in ipairs(Store().list) do
        Apply(flyout)
        current[flyout.id] = true
    end
    for id in pairs(shownCount) do
        if not current[id] then
            Frames.Remove(id)
            shownCount[id], bagDependencies[id] = nil, nil
        end
    end
end

-- Active only on startup, an explicit edit, or when opening out of combat.
function Flyouts.Prepare(id)
    if not active or NS.InCombat() then return end
    local flyout = Find(id)
    if not flyout then return end
    ScanMacros()
    MapMacros()
    Apply(flyout)
end

local function RefreshMacroEntries(list)
    for _, flyout in ipairs(list) do
        for _, entry in ipairs(flyout.entries) do
            if entry.kind == "macro" then
                Apply(flyout)
                break
            end
        end
    end
end

-- VirtualActions already owns UPDATE_MACROS for the separate action bar.
-- Refresh the opener's index map even when launcher arrows are disabled.
-- Secure entry actions use macro names so an old snapshot cannot run a
-- different macro that took the old index.
function Flyouts.MacrosChanged()
    if not active or not built then return end
    local list = Store().list
    if #list == 0 then return end
    if NS.InCombat() then
        pendingMacros = true
        return
    end
    pendingMacros = nil
    ScanMacros()
    MapMacros()
    RefreshMacroEntries(list)
    UpdateMarkers(MarkersEnabled())
end

function Flyouts.ResumeMacros()
    if pendingMacros then Flyouts.MacrosChanged() end
end

local function FlushOpen()
    scheduled = nil
    local full, bags = pendingFull, pendingBags
    pendingFull, pendingBags = nil, nil
    local id = openID
    if not id or NS.InCombat() then return end
    if full then
        Flyouts.Prepare(id)
    elseif bags then
        if bagDependencies[id] then
            local flyout = Find(id)
            if flyout then Apply(flyout) end
        else
            Frames.RefreshBagCounts()
        end
    end
end

local function StopWatching()
    if not openID then return end
    openID, listeningBags, pendingFull, pendingBags = nil, nil, nil, nil
    listener:UnregisterAllEvents()
    if scheduled then scheduled:Cancel() scheduled = nil end
end

local function OnEvent(_, event)
    if event == "PLAYER_REGEN_DISABLED" then
        StopWatching()
        Frames.CloseAll()
        return
    end
    if event == BAG_UPDATE then pendingBags = true else pendingFull = true end
    if not scheduled then scheduled = C_Timer.NewTimer(0, FlushOpen) end
end

function Flyouts.WatchOpen(id, hasItems)
    if not id then return StopWatching() end
    if not active or NS.InCombat() then return end
    if openID ~= id then
        StopWatching()
        if not listener then
            listener = S.CreateFrame("Frame")
            listener:SetScript("OnEvent", OnEvent)
        end
        openID = id
        listener:RegisterEvent("PLAYER_REGEN_DISABLED")
        for _, event in ipairs(OPEN_EVENTS) do
            if NS.Client.SupportsEvent(event) then listener:RegisterEvent(event) end
        end
    end
    local wanted = (hasItems or bagDependencies[id] == true) and NS.Client.SupportsEvent(BAG_UPDATE)
    if listeningBags == wanted then return end
    listeningBags = wanted
    if wanted then listener:RegisterEvent(BAG_UPDATE) else listener:UnregisterEvent(BAG_UPDATE) end
end

local function Sync()
    if not active or NS.IsCombatLocked() then return end
    if not built then
        if #Store().list == 0 then return end
        built = true
        Frames.Candidates(AB.owned)
    end
    Frames.SetEnabled(true)
    ScanMacros()
    MapMacros()
    ApplyAll()
    UpdateMarkers(MarkersEnabled())
end
Flyouts.Sync = Sync

-- ActionBars Controller: Enable and Disable run out of combat.
function Flyouts.Start()
    active = true
    Sync()
end

function Flyouts.Stop()
    active = false
    StopWatching()
    UpdateMarkers(false)
    pendingMacros, AB.flyoutMarkerPending = nil, nil
    if not NS.IsCombatLocked() then Frames.SetEnabled(false) end
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
    local named = GetMacroIndexByName(flyout.name)
    if not Finite(named) or (named > 0 and named ~= index) then
        return nil, S.Text("A macro already uses this name.")
    end
    if index then
        local name, current = GetMacroInfo(index)
        if PublicText(name) == flyout.name and Public(current) and current == icon then return index end
        EditMacro(index, flyout.name, icon, body)
    else
        local account = GetNumMacros()
        if not Finite(account) or account >= Constants.MacroConsts.MAX_ACCOUNT_MACROS then
            return nil, S.Text("Your account-wide macros are full. Delete one to place this flyout.")
        end
        CreateMacro(flyout.name, icon, body, false)
    end
    ScanMacros()
    index = macroOf[flyout.id]
    if not index then return nil, S.Text("The flyout macro could not be created.") end
    return index
end

local function Editable(id)
    if not active then return nil, S.Text("Turn on the Suite action bars to use flyouts.") end
    if NS.InCombat() then return nil, S.Text("Flyouts can be edited out of combat.") end
    if id == nil then return true end
    local flyout, position = Find(id)
    if not flyout then return nil, S.Text("This flyout no longer exists.") end
    return flyout, position
end

local function NewFlyout(name, entries, icon, preset, place)
    local data = Store()
    if #data.list >= Data.MAX_FLYOUTS then return nil, S.Text("You have reached the maximum number of flyouts.") end
    local flyout = Data.CleanFlyout({ id = data.nextID, name = name, entries = entries, icon = icon, preset = preset })
    if not flyout then return nil, S.Text("Enter a name for the flyout.") end
    data.list[#data.list + 1] = flyout
    if place then
        local ok, problem = place(flyout)
        if not ok then
            local macro = macroOf[flyout.id]
            if macro then DeleteMacro(macro) end
            data.list[#data.list] = nil
            ScanMacros()
            return nil, problem
        end
    end
    data.nextID = data.nextID + 1
    Changed()
    return flyout.id
end

local function CursorEntry()
    local kind, id, _, spell = GetCursorInfo()
    if not Public(kind) or not Public(id) or not Public(spell) then return nil end
    if kind == "spell" and Finite(spell) then return { kind = "spell", id = spell } end
    if kind == "item" and Finite(id) then return { kind = Yes(PlayerHasToy(id)) and "toy" or "item", id = id } end
    if (kind == "mount" or kind == "toy") and Finite(id) then return { kind = kind, id = id } end
    if kind == "macro" and Finite(id) then
        local name, _, body = GetMacroInfo(id)
        if PublicText(body) and body:sub(1, #MARKER) == MARKER then return nil, S.Text("A flyout cannot hold another flyout.") end
        if PublicText(name) and GetMacroIndexByName(name) == id then return { kind = "macro", id = name } end
    end
    return nil
end

function Flyouts.IsFlyoutMacro(index)
    local _, _, body = GetMacroInfo(index)
    body = PublicText(body)
    return body and body:sub(1, #MARKER) == MARKER or false
end

-- Shared with FlyoutAPI.lua.
Flyouts.Store, Flyouts.Find, Flyouts.Shown, Flyouts.Changed = Store, Find, Shown, Changed
Flyouts.WriteMacro, Flyouts.Editable, Flyouts.NewFlyout, Flyouts.CursorEntry = WriteMacro, Editable, NewFlyout, CursorEntry
Flyouts.ScanMacros, Flyouts.macroOf, Flyouts.shownCount = ScanMacros, macroOf, shownCount
Flyouts.SlotOwner, Flyouts.flyoutOfMacro = SlotOwner, flyoutOfMacro
Flyouts.MARKER = MARKER

-- Read-only views for the contract tests; nothing in the addon calls them.
AB.Diagnostics.FlyoutData = {
    Listener = function() return listener end,
    Open = function() return openID end,
}

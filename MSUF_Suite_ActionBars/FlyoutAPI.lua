local _, P = ...
local NS, S = P.NS, P.Suite
-- The options page's access to the action bar flyouts (Flyouts.lua). Reads
-- return plain tables; every change runs out of combat and returns true, or
-- nil and an English message the page translates.
local AB = P.ActionBars
local F = AB.Flyouts
local Data = NS.ActionBarFlyouts
local Public, Finite, PublicText = S.Public, S.Finite, S.PublicText
local API = {}
S.ActionBarFlyouts = API

local BAG_ICON_ITEM = 4540
local NOT_FOUND = "This flyout no longer exists."

local function Yes(value)
    return Public(value) and value == true
end

local function Icon(value)
    return Finite(value) and value or nil
end

local function PresetIcon(preset)
    if preset.iconItem then return Icon(C_Item.GetItemIconByID(preset.iconItem)) end
    if preset.iconSpell then return Icon(C_Spell.GetSpellTexture(preset.iconSpell)) end
    return preset.icon
end

local function PresetText(preset, requireAvailable)
    if requireAvailable and preset.class then
        local _, class = UnitClass("player")
        if not Public(class) or class ~= preset.class then return end
    end
    local title, macroName, description = preset.Text()
    if preset.nativeBook then
        local name, _, _, known = GetFlyoutInfo(preset.nativeBook)
        if requireAvailable and not Yes(known) then return end
        title = PublicText(name)
    end
    return title, macroName, description
end

-- Name and icon of a saved entry for the editor list.
local function Describe(entry)
    local kind, id = entry.kind, entry.id
    if kind == "item" or kind == "toy" then
        local name = PublicText(C_Item.GetItemNameByID(id))
        if not name then C_Item.RequestLoadItemDataByID(id) end
        return name or S.Text("Item %d"):format(id), Icon(C_Item.GetItemIconByID(id))
    elseif kind == "spell" then
        return PublicText(C_Spell.GetSpellName(id)) or S.Text("Spell %d"):format(id), Icon(C_Spell.GetSpellTexture(id))
    elseif kind == "mount" then
        local name, _, icon = C_MountJournal.GetMountInfoByID(id)
        return PublicText(name) or S.Text("Mount %d"):format(id), Icon(icon)
    elseif kind == "macro" then
        local index, icon = GetMacroIndexByName(id), nil
        if Finite(index) and index > 0 then icon = select(2, GetMacroInfo(index)) end
        return id, Icon(icon)
    elseif kind == "bag" and id == "food" then
        return S.Text("All food and drink in your bags"), Icon(C_Item.GetItemIconByID(BAG_ICON_ITEM))
    end
    for _, preset in ipairs(Data.Presets()) do
        if Data.SameEntry(preset.entries[1], entry) then return PresetText(preset), PresetIcon(preset) end
    end
    return S.Text("Unknown")
end
API.Describe = Describe

local function Copy(entries)
    local list = {}
    for i, entry in ipairs(entries) do list[i] = { kind = entry.kind, id = entry.id } end
    return list
end

-- The macro icon follows the first entry unless the flyout has its own.
local function Saved(flyout)
    if not flyout.icon and F.macroOf[flyout.id] then F.WriteMacro(flyout) end
    return F.Changed()
end

------------------------------------------------------------------ reads
function API.Ready()
    local ok, problem = F.Editable()
    return ok == true, problem
end

function API.Presets()
    local rows = {}
    for _, preset in ipairs(Data.Presets()) do
        local label, macroName, description = PresetText(preset, true)
        if label then
            rows[#rows + 1] = { key = preset.key, label = label, flyoutName = macroName,
                category = preset.category, description = description }
        end
    end
    return rows
end

function API.List()
    local rows = {}
    for _, flyout in ipairs(F.Store().list) do
        local icon = flyout.icon
        if not icon and flyout.entries[1] then icon = select(2, Describe(flyout.entries[1])) end
        rows[#rows + 1] = { id = flyout.id, name = flyout.name, owned = flyout.owned, entries = #flyout.entries,
            shown = F.shownCount[flyout.id] or 0, placed = F.macroOf[flyout.id] ~= nil,
            icon = icon, preset = flyout.preset }
    end
    return rows
end

-- The saved entries in order; `active` marks the ones the flyout shows now.
function API.Entries(id)
    local flyout = F.Find(id)
    if not flyout then return {} end
    local showing = {}
    for _, entry in ipairs(F.Shown(flyout)) do showing[entry.kind .. ":" .. tostring(entry.id)] = true end
    local rows = {}
    for position, entry in ipairs(flyout.entries) do
        local name, icon = Describe(entry)
        rows[position] = { kind = entry.kind, id = entry.id, name = name, icon = icon,
            active = Data.ExclusionField(entry) ~= nil or showing[entry.kind .. ":" .. tostring(entry.id)] == true }
    end
    return rows
end

-- Action bars 1 to 9 that are switched on (bar 10 takes a flyout by drag).
function API.Bars()
    local bars = {}
    for index = 1, AB.ENUM.BAR.INDEPENDENT - 1 do
        if AB.bars[index] and AB.Available(index)
            and NS.ActionBarVisibilityMode(AB.M.config, index) ~= AB.ENUM.VISIBILITY.NEVER then
            bars[#bars + 1] = index
        end
    end
    return bars
end

------------------------------------------------------------------ flyouts
function API.AddPreset(key, name)
    local ok, problem = F.Editable()
    if not ok then return nil, problem end
    local preset = Data.Preset(key)
    if not preset then return nil, S.Text(NOT_FOUND) end
    local label, macroName = PresetText(preset, true)
    if not label then return nil, S.Text(NOT_FOUND) end
    return F.NewFlyout(name or macroName, Copy(preset.entries), PresetIcon(preset), preset.key)
end

function API.Create(name)
    local ok, problem = F.Editable()
    if not ok then return nil, problem end
    return F.NewFlyout(name, {})
end

function API.Delete(id)
    local flyout, position = F.Editable(id)
    if not flyout then return nil, position end
    F.ScanMacros()
    local index = F.macroOf[id]
    if index then
        local name = PublicText(GetMacroInfo(index))
        local update = name and GetMacroIndexByName(name) == index
        DeleteMacro(index)
        if update and AB.Virtual then AB.Virtual.UpdateFlyoutName(name, nil) end
    end
    table.remove(F.Store().list, position)
    return F.Changed()
end

function API.Rename(id, name)
    local flyout, problem = F.Editable(id)
    if not flyout then return nil, problem end
    name = Data.CleanName(name)
    if not name then return nil, S.Text("Enter a name for the flyout.") end
    F.ScanMacros()
    local oldName = flyout.name
    local oldMacro = F.macroOf[id]
    local oldMacroName = oldMacro and PublicText(GetMacroInfo(oldMacro))
    local update = oldMacroName and GetMacroIndexByName(oldMacroName) == oldMacro
    flyout.name = name
    if oldMacro then
        local index, failure = F.WriteMacro(flyout)
        if not index then
            flyout.name = oldName
            return nil, failure
        end
        if update and AB.Virtual and name ~= oldMacroName then AB.Virtual.UpdateFlyoutName(oldMacroName, name) end
    end
    return F.Changed()
end

function API.SetOwned(id, on)
    local flyout, problem = F.Editable(id)
    if not flyout then return nil, problem end
    flyout.owned = on == true
    return F.Changed()
end

------------------------------------------------------------------ entries
local function ExcludeGenerated(flyout, entry)
    for _, saved in ipairs(flyout.entries) do
        if (entry.kind == "item" and saved.kind == "bag") or (entry.kind == "spell" and saved.kind == "spellbook") then
            local field = Data.ExclusionField(saved)
            flyout[field] = flyout[field] or {}
            flyout[field][entry.id] = true
        end
    end
end

function API.AddEntry(id, entry, before)
    local flyout, problem = F.Editable(id)
    if not flyout then return nil, problem end
    entry = Data.CleanEntry(entry)
    if not entry then return nil, S.Text("This cannot go into a flyout.") end
    for _, kept in ipairs(flyout.entries) do
        if Data.SameEntry(kept, entry) then return nil, S.Text("This flyout already holds it.") end
    end
    if #flyout.entries >= Data.MAX_ENTRIES then return nil, S.Text("This flyout is full.") end
    local position = before and flyout.entries[before.position] == before.source and before.position or #flyout.entries + 1
    table.insert(flyout.entries, position, entry)
    ExcludeGenerated(flyout, entry)
    return Saved(flyout)
end

-- What the cursor holds: a spell, item, toy, mount or macro.
function API.AddCursor(id, before)
    local entry, problem = F.CursorEntry()
    if not entry then return nil, problem or S.Text("Pick up a spell, item, toy, mount or macro first.") end
    local ok, failure = API.AddEntry(id, entry, before)
    if ok then ClearCursor() end
    return ok, failure
end

function API.PickupEntry(id, entry)
    local flyout, problem = F.Editable(id)
    if not flyout then return nil, problem end
    if not entry or flyout.entries[entry.position] ~= entry.source then return nil, S.Text(NOT_FOUND) end
    local held = GetCursorInfo()
    if not Public(held) or held ~= nil then return end
    S.Dispatch(AB.Virtual.PickupNative, entry)
    local picked = F.CursorEntry()
    if not picked or not Data.SameEntry(picked, entry) then return end
    ExcludeGenerated(flyout, entry)
    if not Data.ExclusionField(entry.source) then table.remove(flyout.entries, entry.position) end
    return Saved(flyout)
end

-- "item:4540", "spell:8690", "toy:…", "mount:…" or a bare number (an item
-- when the client knows one, else a spell).
function API.AddText(id, text)
    if type(text) ~= "string" then return nil, S.Text("Enter an item or spell ID, for example item:4540.") end
    local kind, number = text:lower():match("^%s*(%a+)%s*:%s*(%d+)%s*$")
    number = tonumber(number or text:match("^%s*(%d+)%s*$"))
    if not number then return nil, S.Text("Enter an item or spell ID, for example item:4540.") end
    if not kind then
        kind = Finite((C_Item.GetItemInfoInstant(number))) and "item" or "spell"
        if kind == "item" and Yes(PlayerHasToy(number)) then kind = "toy" end
    end
    if kind == "spell" and not PublicText(C_Spell.GetSpellName(number)) then return nil, S.Text("No spell has this ID.") end
    return API.AddEntry(id, { kind = kind, id = number })
end

function API.RemoveEntry(id, position)
    local flyout, problem = F.Editable(id)
    if not flyout then return nil, problem end
    if not flyout.entries[position] then return nil, S.Text(NOT_FOUND) end
    table.remove(flyout.entries, position)
    return Saved(flyout)
end

function API.MoveEntry(id, position, delta)
    local flyout, problem = F.Editable(id)
    if not flyout then return nil, problem end
    local target = position + delta
    local entries = flyout.entries
    if not entries[position] or not entries[target] then return nil, S.Text(NOT_FOUND) end
    table.insert(entries, target, table.remove(entries, position))
    return Saved(flyout)
end

------------------------------------------------------------------ placing
-- Puts the flyout's macro on the cursor, ready to drop on any action button.
function API.Pickup(id)
    local flyout, problem = F.Editable(id)
    if not flyout then return nil, problem end
    local index, failure = F.WriteMacro(flyout)
    if not index then return nil, failure end
    ClearCursor()
    PickupMacro(index)
    return F.Changed()
end

local function NativeSlot(rec)
    local slot = rec.button:GetAttribute("action")
    if Finite(slot) and slot >= 1 and slot <= 180 and slot % 1 == 0 then return slot end
end

function API.ButtonFlyout(rec)
    if rec.virtual then
        local index = rec.button:GetAttribute("macro")
        return Finite(index) and F.flyoutOfMacro[index] or nil
    end
    local slot = NativeSlot(rec)
    return slot and F.SlotOwner(slot) or nil
end

local function ButtonEntry(rec)
    if rec.virtual then
        local entry = rec.virtualAction
        return Data.CleanEntry(entry), entry ~= nil
    end
    local slot = NativeSlot(rec)
    if not slot then return nil, true end
    local filled = HasAction(slot)
    if not Public(filled) then return nil, true end
    if not filled then return nil, false end
    local kind, id, sub = GetActionInfo(slot)
    if not Public(kind) or not Public(id) or not Public(sub) then return nil, true end
    if kind == "macro" then
        if sub == "spell" or sub == "item" then
            id = PublicText(GetActionText(slot))
        else
            local name = Finite(id) and PublicText(GetMacroInfo(id))
            id = name and GetMacroIndexByName(name) == id and name or nil
        end
    elseif kind == "item" and Finite(id) and Yes(PlayerHasToy(id)) then
        kind = "toy"
    end
    return Data.CleanEntry({ kind = kind, id = id }), true
end

local function PlaceOnButton(rec, flyout, cursor)
    local slot = not rec.virtual and NativeSlot(rec)
    if not slot and not rec.virtual then return nil, S.Text("The flyout could not be placed on this button.") end
    local index, problem = F.WriteMacro(flyout)
    if not index then return nil, problem end
    if rec.virtual then
        if AB.Virtual.SetFlyout(rec, flyout.name) then
            if cursor then ClearCursor() end
            return true
        end
    else
        if cursor then ClearCursor() end
        PickupMacro(index)
        local kind, picked = GetCursorInfo()
        if Public(kind) and Public(picked) and kind == "macro" and picked == index then PlaceAction(slot) end
        if F.SlotOwner(slot) == flyout.id then
            ClearCursor()
            return true
        end
        ClearCursor()
        if cursor then S.Dispatch(AB.Virtual.PickupNative, cursor) end
    end
    return nil, S.Text("The flyout could not be placed on this button.")
end

local function AutoName()
    local id = F.Store().nextID
    local name = Data.CleanName(S.Text("Flyout %d"):format(id))
    local index = name and GetMacroIndexByName(name)
    if Finite(index) and index == 0 then return name end
    for suffix = 1, Constants.MacroConsts.MAX_ACCOUNT_MACROS + Constants.MacroConsts.MAX_CHARACTER_MACROS do
        name = ("MSUF%d-%d"):format(id, suffix)
        index = GetMacroIndexByName(name)
        if Finite(index) and index == 0 then return name end
    end
end

function API.DropOnButton(rec)
    local ok, problem = F.Editable()
    if not ok then return nil, problem end
    F.ScanMacros()
    local id = API.ButtonFlyout(rec)
    if id then
        ok, problem = API.AddCursor(id)
        if ok then return id end
        return nil, problem
    end
    local cursor
    cursor, problem = F.CursorEntry()
    if not cursor then return nil, problem or S.Text("Pick up a spell, item, toy, mount or macro first.") end
    local old, filled = ButtonEntry(rec)
    if filled and not old then return nil, S.Text("Choose an empty button or a spell, item or macro button.") end
    local entries = old and { old, cursor } or { cursor }
    return F.NewFlyout(AutoName(), entries, nil, nil, function(flyout)
        return PlaceOnButton(rec, flyout, cursor)
    end)
end

-- Places the flyout on the first empty button of an action bar (1 to 9);
-- true and the button number.
function API.Place(id, index)
    local flyout, problem = F.Editable(id)
    if not flyout then return nil, problem end
    local bar = AB.bars[index]
    if not bar or index >= AB.ENUM.BAR.INDEPENDENT then return nil, "Choose action bar 1 to 9." end
    local slot, number
    for i = 1, math.min(bar.count or AB.BUTTONS, #bar.buttons) do
        local base = bar.buttons[i].base
        local filled = base and HasAction(base)
        if base and Public(filled) and not filled then
            slot, number = base, i
            break
        end
    end
    if not slot then return nil, "This bar has no empty button. Drag the flyout onto a button instead." end
    local macro, failure = F.WriteMacro(flyout)
    if not macro then return nil, failure end
    ClearCursor()
    PickupMacro(macro)
    PlaceAction(slot)
    ClearCursor()
    F.Changed()
    return true, number
end

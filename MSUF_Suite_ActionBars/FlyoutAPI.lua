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
    end
    return S.Text("All food and drink in your bags"), Icon(C_Item.GetItemIconByID(BAG_ICON_ITEM))
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
    return Data.Presets()
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
            active = entry.kind == "bag" or showing[entry.kind .. ":" .. tostring(entry.id)] == true }
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
    if not preset then return nil, NOT_FOUND end
    return F.NewFlyout(name or preset.flyoutName, Copy(preset.entries), Icon(C_Item.GetItemIconByID(preset.iconItem)), preset.key)
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
    if index then DeleteMacro(index) end
    table.remove(F.Store().list, position)
    return F.Changed()
end

function API.Rename(id, name)
    local flyout, problem = F.Editable(id)
    if not flyout then return nil, problem end
    name = Data.CleanName(name)
    if not name then return nil, "Enter a name for the flyout." end
    flyout.name = name
    if F.macroOf[id] then
        local index, failure = F.WriteMacro(flyout)
        if not index then return nil, failure end
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
function API.AddEntry(id, entry)
    local flyout, problem = F.Editable(id)
    if not flyout then return nil, problem end
    entry = Data.CleanEntry(entry)
    if not entry then return nil, "This cannot go into a flyout." end
    for _, kept in ipairs(flyout.entries) do
        if Data.SameEntry(kept, entry) then return nil, "This flyout already holds it." end
    end
    if #flyout.entries >= Data.MAX_ENTRIES then return nil, "This flyout is full." end
    flyout.entries[#flyout.entries + 1] = entry
    return Saved(flyout)
end

-- What the cursor holds: a spell, item, toy, mount or macro.
function API.AddCursor(id)
    local entry, problem = F.CursorEntry()
    if not entry then return nil, problem or "Pick up a spell, item, toy, mount or macro first." end
    local ok, failure = API.AddEntry(id, entry)
    if ok then ClearCursor() end
    return ok, failure
end

-- "item:4540", "spell:8690", "toy:…", "mount:…" or a bare number (an item
-- when the client knows one, else a spell).
function API.AddText(id, text)
    if type(text) ~= "string" then return nil, "Enter an item or spell ID, for example item:4540." end
    local kind, number = text:lower():match("^%s*(%a+)%s*:%s*(%d+)%s*$")
    number = tonumber(number or text:match("^%s*(%d+)%s*$"))
    if not number then return nil, "Enter an item or spell ID, for example item:4540." end
    if not kind then
        kind = Finite((C_Item.GetItemInfoInstant(number))) and "item" or "spell"
        if kind == "item" and Yes(PlayerHasToy(number)) then kind = "toy" end
    end
    if kind == "spell" and not PublicText(C_Spell.GetSpellName(number)) then return nil, "No spell has this ID." end
    return API.AddEntry(id, { kind = kind, id = number })
end

function API.RemoveEntry(id, position)
    local flyout, problem = F.Editable(id)
    if not flyout then return nil, problem end
    if not flyout.entries[position] then return nil, NOT_FOUND end
    table.remove(flyout.entries, position)
    return Saved(flyout)
end

function API.MoveEntry(id, position, delta)
    local flyout, problem = F.Editable(id)
    if not flyout then return nil, problem end
    local target = position + delta
    local entries = flyout.entries
    if not entries[position] or not entries[target] then return nil, NOT_FOUND end
    entries[position], entries[target] = entries[target], entries[position]
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
    EventRegistry:TriggerEvent("MSUFSuite.ActionBars.FlyoutsChanged")
    return true
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
    F.MapSlot(slot)
    EventRegistry:TriggerEvent("MSUFSuite.ActionBars.FlyoutsChanged")
    return true, number
end

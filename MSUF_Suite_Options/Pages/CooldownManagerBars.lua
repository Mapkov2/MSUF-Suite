local _, P = ...
-- Cooldown manager page, bar edits: the note line with its Undo, adding,
-- reusing, deleting, copying and resetting bars, and the add-bar and
-- bar-action menus. Builds on the page state of CooldownManagerData.lua and
-- the list edits of CooldownManagerLists.lua, which load first.
local Page = P.CDMPage
local S, M, W, Tr = P.S, P.M, P.W, P.Tr
local CDM = P.Suite.CDM
local ID = Page.ID
local RULES, SLOTS, KEYS = P.catalog[ID].rules, CDM.SLOTS, CDM.KEYS
local format = string.format
local Prune, KIND_NAMES = Page.PruneLists, Page.KIND_NAMES

------------------------------------------------------------------ notes and undo
-- One short line under the spell tiles; it clears itself after 8 seconds
-- through Menu2's cancellable timer (nothing is scheduled in combat).
function Page.ClearNote()
    local task = Page.noteTask
    Page.noteTask, Page.note, Page.undo = nil, nil, nil
    if task and task.Cancel then task:Cancel() end
    if Page.ui and Page.ui.PaintNote then Page.ui.PaintNote() end
end
function Page.Note(text, undo, isError)
    local task = Page.noteTask
    Page.noteTask = nil
    if task and task.Cancel then task:Cancel() end
    Page.note, Page.undo, Page.noteError = text, undo, isError == true
    local timer = M.MenuTimer
    if text and timer and timer.After then Page.noteTask = timer.After(8, Page.ClearNote) end
    if Page.ui and Page.ui.PaintNote then Page.ui.PaintNote() end
end
function Page.Fail(reason) Page.Note(Tr(reason or "That did not work."), nil, true) end

-- A gesture that can drop data, with an 8 s Undo line. keys: the settings it
-- may change. The Undo puts them back as one history entry, and only while
-- nothing changed them since. Returns what `run` returned.
local LIST_KEYS = { "listsData" }
Page.LIST_KEYS = LIST_KEYS
local function Snapshot(keys)
    local out = {}
    for i = 1, #keys do out[keys[i]] = P.Get(ID, keys[i]) end
    return out
end
local function Restore(before, after)
    if P.Combat() then return false end
    local values = {}
    for key, value in pairs(after) do
        if P.Get(ID, key) ~= value then
            Page.Fail("That changed since, so it cannot be undone.")
            return false
        end
        if before[key] ~= value then values[key] = before[key] end
    end
    local restored
    P.WithHistory("Undo", "suite:cooldownManager.undo", function()
        -- Turning the module back on applies the suite look first; the other
        -- values follow it, so they come back exactly.
        if values.enabled == true then
            values.enabled = nil
            if not P.Set(ID, "enabled", true) then return false end
        end
        restored = P.SetMany(ID, values)
        return restored
    end)
    return restored
end
-- text: the note, or a function of run's extra results that returns it.
function Page.WithUndo(text, keys, run)
    local before = Snapshot(keys)
    local ok, reason, extra = run()
    if not ok then return false, reason end
    local after = Snapshot(keys)
    for key, value in pairs(after) do
        if before[key] ~= value then
            if type(text) == "function" then text = text(reason, extra) end
            Page.Note(text, function() return Restore(before, after) end)
            break
        end
    end
    return ok, reason, extra
end
-- Keys of one bar (plus its spell lists) for Page.WithUndo.
function Page.SlotKeys(slot, withLists)
    local keys = {}
    for _, key in pairs(KEYS[slot]) do keys[#keys + 1] = key end
    if withLists then keys[#keys + 1] = "listsData" end
    -- The Essential bar's x/y may count from Blizzard's bar.
    if slot == "ess" and RULES.essOnViewer then keys[#keys + 1] = "essOnViewer" end
    return keys
end

function Page.RemoveWithUndo(slot, key, name)
    local ok, reason = Page.WithUndo(format(Tr("Removed %s."), name or key), LIST_KEYS,
        function() return Page.RemoveEntry(slot, key) end)
    if not ok then Page.Fail(reason) end
    return ok
end
-- The Spell list's list-wide actions, each with its Undo line.
function Page.ClearWithUndo(slot)
    local label = Page.ClearLabel(slot)
    local text = label == "Remove all spells" and format(Tr("Removed every spell from %s."), Page.BarName(slot))
        or label == "Restore default spells" and format(Tr("%s is back to its default spells."), Page.BarName(slot))
        or label == "Restore raid essentials" and format(Tr("%s is back to its raid essentials."), Page.BarName(slot))
        or label == "Restore spec defaults" and format(Tr("%s is back to its spec defaults."), Page.BarName(slot))
        or format(Tr("%s follows Blizzard's list again."), Page.BarName(slot))
    local ok, reason = Page.WithUndo(text, LIST_KEYS, function() return Page.ClearList(slot) end)
    if not ok then Page.Fail(reason) end
    return ok
end
function Page.ImportBlizzardWithUndo()
    local ok, reason = Page.WithUndo(Tr("Imported Blizzard's cooldown layout for this specialization."), LIST_KEYS,
        Page.ImportBlizzard)
    if not ok then Page.Fail(reason) end
    return ok
end
function Page.RestoreWithUndo()
    local count = Page.HiddenCount()
    local ok, reason = Page.WithUndo(format(Tr("Brought back the removed spells (%d)."), count), LIST_KEYS, Page.RestoreHidden)
    if not ok then Page.Fail(reason) end
    return ok
end
local function CopiedText(added, specs)
    return format(Tr("Copied %d entries to %d other specializations."), added, specs)
end
function Page.CopyListWithUndo(slot)
    local ok, added = Page.WithUndo(CopiedText, LIST_KEYS, function() return Page.CopyListToSpecs(slot) end)
    if not ok then
        Page.Fail(added)
        return false
    end
    if added == 0 then Page.Note(Tr("Your other specializations have them already.")) end
    return true
end
function Page.RunUndo()
    local undo = Page.undo
    Page.ClearNote()
    if undo then undo() end
end

------------------------------------------------------------------ bars
function Page.Select(slot)
    if type(slot) ~= "string" or not CDM.SLOT_INDEX[slot] then return false end
    if Page.selected ~= slot then
        Page.CommitFocus()
        Page.selected = slot
        Page.ClosePopups()
    end
    P.Refresh()
    return true
end
-- New bars prefer a custom slot that was never named; a used slot that is off
-- is reused only when no fresh one is left (second result true).
function Page.FreeCustom()
    local reuse
    for i = 1, #SLOTS do
        local info = SLOTS[i]
        if info.custom and not Page.IsOn(info.key) then
            if P.Get(ID, KEYS[info.key].name) == "" then return info.key, false end
            reuse = reuse or info.key
        end
    end
    return reuse, reuse ~= nil
end
local DEFAULT_NAMES = { "Cooldowns", "Buffs", "Timers" }
-- A free bar that would sit exactly on another shown free bar moves down a
-- step, so several new bars never stack on one spot.
local function Occupied(slot, x, y)
    for i = 1, #SLOTS do
        local other = SLOTS[i].key
        local k = KEYS[other]
        if other ~= slot and Page.IsOn(other) and P.Get(ID, k.anchor) == 1
            and P.Get(ID, k.x) == x and P.Get(ID, k.y) == y then return true end
    end
    return false
end
local function FreeSpot(slot, x, y)
    local low = RULES[KEYS[slot].y].min
    for _ = 1, #SLOTS do
        if not Occupied(slot, x, y) or y - 48 < low then break end
        y = y - 48
    end
    return x, y
end
-- A custom slot used before starts over as a new bar: settings back to
-- their defaults and its spells dropped from every specialization.
local function ResetSlot(slot, values)
    for _, key in pairs(KEYS[slot]) do
        local default = RULES[key].default
        if P.Get(ID, key) ~= default then values[key] = default end
    end
    local lists = CDM.Codec.DecodeLists(P.Get(ID, "listsData"))
    local changed = false
    if lists.shared and lists.shared[slot] then lists.shared[slot] = nil; changed = true end
    for spec, slots in pairs(lists.specs) do
        if slots[slot] then
            slots[slot] = nil
            changed = true
            Prune(lists, spec)
        end
    end
    if changed then values.listsData = CDM.Codec.EncodeLists(lists) end
end
local function NewBarValues(slot, kind, reused)
    local keys = KEYS[slot]
    local values = {}
    if reused then ResetSlot(slot, values) end
    values[keys.on], values[keys.kind] = true, kind
    local name = Tr(DEFAULT_NAMES[kind]) .. " " .. slot:sub(2)
    if #name > RULES[keys.name].maxLength then name = "Bar " .. slot:sub(2) end
    values[keys.name] = name
    local anchor = values[keys.anchor] or P.Get(ID, keys.anchor)
    if anchor == 1 then
        local x, y = values[keys.x] or P.Get(ID, keys.x), values[keys.y] or P.Get(ID, keys.y)
        local nx, ny = FreeSpot(slot, x, y)
        if nx ~= x or ny ~= y then values[keys.x], values[keys.y] = nx, ny end
    end
    return values
end
-- A reused slot starts over; its old settings and spells come back with Undo.
function Page.AddBar(kind)
    if P.Combat() then return false end
    local slot, reused = Page.FreeCustom()
    if not slot then
        Page.Fail("All six custom bars are in use.")
        return false
    end
    kind = (kind == 2 or kind == 3) and kind or 1
    Page.CommitFocus()
    local ok
    if reused then
        ok = Page.WithUndo(format(Tr("%s was reset for the new bar."), Page.BarName(slot)), Page.SlotKeys(slot, true),
            function() return P.SetMany(ID, NewBarValues(slot, kind, true)) end)
    else
        ok = P.SetMany(ID, NewBarValues(slot, kind, false))
    end
    if ok then
        Page.selected = slot
        Page.ClosePopups()
        P.Refresh()
        Page.FocusName()
    end
    return ok
end
-- The name input of the selected custom bar takes the keyboard (a new or
-- renamed bar); Basics comes into view first.
function Page.FocusName()
    local input = Page.ui and Page.ui.nameInput
    if P.Combat() or not (input and input.SetFocus) or not Page.SlotInfo(Page.selected).custom then return false end
    Page.FocusSection("bars")
    input:SetFocus()
    if input.HighlightText then input:HighlightText() end
    return true
end
-- A custom bar goes back to a free slot: default settings, no name, off, and
-- its spells gone from every specialization. One history entry, with Undo.
function Page.DeleteBar(slot)
    if P.Combat() or not Page.SlotInfo(slot).custom then return false end
    Page.CommitFocus()
    local ok, reason = Page.WithUndo(format(Tr("Deleted %s."), Page.BarName(slot)), Page.SlotKeys(slot, true), function()
        local values = {}
        ResetSlot(slot, values)
        if next(values) == nil then return true end
        return P.SetMany(ID, values)
    end)
    if not ok then
        Page.Fail(reason)
        return false
    end
    if Page.selected == slot then
        local first = "ess"
        for i = 1, #SLOTS do
            if Page.IsOn(SLOTS[i].key) then
                first = SLOTS[i].key
                break
            end
        end
        Page.Select(first)
    end
    return true
end
-- Settings that make a bar what it is and where it sits never copy: name,
-- type, attachment, position and how it grows.
local COPY_SKIP = { on = true, name = true, kind = true, anchor = true, side = true, gap = true, x = true, y = true,
    vertical = true, grow = true, align = true }
function Page.CopyBarSettings(from, to)
    if P.Combat() or from == to or not (KEYS[from] and KEYS[to]) then return false end
    local values, keys = {}, {}
    for suffix, key in pairs(KEYS[to]) do
        local source = KEYS[from][suffix]
        if source and not COPY_SKIP[suffix] and Page.Relevant(to, suffix) and Page.Relevant(from, suffix) then
            local value = P.Get(ID, source)
            if P.Get(ID, key) ~= value then values[key], keys[#keys + 1] = value, key end
        end
    end
    if #keys == 0 then
        Page.Note(format(Tr("%s already looks like %s."), Page.BarName(to), Page.BarName(from)))
        return true
    end
    local ok, reason = Page.WithUndo(format(Tr("%s now uses the settings of %s."), Page.BarName(to), Page.BarName(from)),
        keys, function() return P.SetMany(ID, values) end)
    if not ok then Page.Fail(reason) end
    return ok
end
-- Kept by "Reset this bar's settings": identity, bar type and position.
local RESET_KEEP = { on = true, name = true, kind = true, x = true, y = true }
function Page.ResetBar(slot)
    if P.Combat() then return false end
    local k = KEYS[slot]
    local ok, reason = Page.WithUndo(format(Tr("Reset the settings of %s."), Page.BarName(slot)), Page.SlotKeys(slot),
        function()
            local values = {}
            for suffix, key in pairs(k) do
                if not RESET_KEEP[suffix] then values[key] = RULES[key].default end
            end
            -- x/y follow the attachment: an attached bar goes back flush on
            -- its anchor, a bar that becomes free keeps its place on screen.
            local anchor = RULES[k.anchor].default
            if anchor ~= 1 or P.Get(ID, k.anchor) ~= 1 then
                -- The conversion comes with the cooldown manager addon.
                local moved = S.CooldownManagerConvertAnchor and S.CooldownManagerConvertAnchor(slot, anchor)
                if type(moved) == "table" then for key, value in pairs(moved) do values[key] = value end end
            end
            return P.SetMany(ID, values)
        end)
    if not ok then Page.Fail(reason) end
    return ok
end
-- Everything of the module: settings, every specialization's spell lists
-- and every spell's options. One history entry, and an Undo line.
function Page.ResetModule()
    if P.Combat() then return false end
    local keys = {}
    for key in pairs(RULES) do keys[#keys + 1] = key end
    return Page.WithUndo(Tr("The cooldown manager was reset: settings, spell lists and spell options."), keys, function()
        local done
        P.WithHistory("Reset cooldown manager", "suite:cooldownManager.reset", function()
            done = S.Reset(ID)
            return done
        end)
        return done == true
    end)
end
function Page.EnableBar(slot)
    if P.Combat() or not Page.SlotInfo(slot).custom then return false end
    Page.CommitFocus()
    local ok = P.Set(ID, KEYS[slot].on, true)
    if ok then
        Page.selected = slot
        Page.ClosePopups()
        P.Refresh()
    end
    return ok
end
-- New bars by type, then custom bars that are off but were named before.
local addValues = {}
local function AddValue(n, value, text, header)
    local item = addValues[n] or {}
    addValues[n] = item
    item.value, item.text, item.header, item.translate, item.tooltip = value, text, header, nil, nil
    -- Bar names are already translated (or typed by the player).
    if not header and type(value) == "string" then item.translate = false end
    return n
end
local function AddPicked(value)
    if type(value) == "string" then Page.EnableBar(value) else Page.AddBar(tonumber(value) or 1) end
end
function Page.OpenAddBar(owner)
    if P.Combat() then return false end
    local free, reused = Page.FreeCustom()
    if not free then
        Page.Fail("All six custom bars are in use.")
        return false
    end
    if not (W.OpenDropdown and owner) then return Page.AddBar(1) end
    -- Every slot was used: a new bar starts one of them over, and says which.
    local old = reused and Page.BarName(free) or nil
    local n = 0
    for kind = 1, #KIND_NAMES do
        n = AddValue(n + 1, kind, KIND_NAMES[kind])
        if old then
            local item = addValues[n]
            item.text, item.translate = format(Tr("%s (replaces %s)"), Tr(KIND_NAMES[kind]), old), false
            item.tooltip = format(Tr("All six custom bars were used before. The new bar starts %s over: its settings, and its spells in every specialization. You can undo it."), old)
        end
    end
    local headed = false
    for i = 1, #SLOTS do
        local slot = SLOTS[i].key
        if SLOTS[i].custom and not Page.IsOn(slot) and P.Get(ID, KEYS[slot].name) ~= "" then
            if not headed then
                n = AddValue(n + 1, "header", "Turn a bar back on", true)
                headed = true
            end
            n = AddValue(n + 1, slot, Page.BarName(slot))
        end
    end
    for i = n + 1, #addValues do addValues[i] = nil end
    Page.dropdownOpen = true
    return W.OpenDropdown(owner, addValues, nil, AddPicked)
end

-- Bar actions: right-click on a bar chip, or "Bar actions" in Basics.
-- One flat list (Menu2 lists do not nest): the actions, then the bars whose
-- settings can be copied onto this one.
local barMenu, COPY_VALUE, COPY_FROM = {}, {}, {}
for i = 1, #SLOTS do
    local key = SLOTS[i].key
    COPY_VALUE[key] = "copy:" .. key
    COPY_FROM[COPY_VALUE[key]] = key
end
local function MenuItem(n, value, text)
    local item = barMenu[n] or {}
    barMenu[n] = item
    item.value, item.text, item.header, item.translate, item.disabled, item.tooltip = value, text, nil, nil, nil, nil
    return item
end
local function BarPicked(value)
    local slot = Page.menuSlot
    if P.Combat() or not (slot and KEYS[slot]) then return end
    local from = COPY_FROM[value]
    if from then
        Page.CopyBarSettings(from, slot)
    elseif value == "show" then
        if Page.SlotInfo(slot).custom then Page.EnableBar(slot) else P.Set(ID, KEYS[slot].on, true) end
    elseif value == "hide" then
        P.Set(ID, KEYS[slot].on, false)
    elseif value == "rename" then
        Page.Select(slot)
        Page.FocusName()
    elseif value == "move" then
        P.MoveOnScreen(ID, slot)
    elseif value == "reset" then
        Page.ResetBar(slot)
    elseif value == "delete" then
        Page.DeleteBar(slot)
    end
end
function Page.OpenBarMenu(owner, slot)
    slot = slot or Page.selected
    if P.Combat() or not (W.OpenDropdown and owner and KEYS[slot]) then return false end
    local custom, on = Page.SlotInfo(slot).custom, Page.IsOn(slot)
    local n = 1
    MenuItem(n, on and "hide" or "show", on and "Hide this bar" or "Show this bar")
    if custom then
        n = n + 1
        MenuItem(n, "rename", "Rename this bar")
    end
    n = n + 1
    local move = MenuItem(n, "move", "Move on screen")
    move.disabled = not (on and Page.Movable(slot) and P.Get(ID, "enabled"))
    if move.disabled then move.tooltip = Tr(on and "This bar cannot be moved on its own right now." or "Show this bar first.") end
    n = n + 1
    MenuItem(n, "reset", "Reset this bar's settings").tooltip = Tr("Keeps its name, type and position. You can undo it.")
    if custom then
        n = n + 1
        MenuItem(n, "delete", "Delete this bar").tooltip =
            Tr("Frees this custom bar: its settings, and its spells in every specialization. You can undo it.")
    end
    n = n + 1
    local header = MenuItem(n, "copy", "Copy settings from")
    header.header = true
    header.tooltip = Tr("Look, size, text, effects and visibility. The name, type and position stay.")
    for i = 1, #SLOTS do
        local other = SLOTS[i].key
        if other ~= slot and Page.Listed(other) then
            n = n + 1
            local item = MenuItem(n, COPY_VALUE[other], Page.BarName(other))
            item.translate = false
        end
    end
    for i = n + 1, #barMenu do barMenu[i] = nil end
    Page.menuSlot = slot
    Page.dropdownOpen = true
    return W.OpenDropdown(owner, barMenu, nil, BarPicked)
end
function Page.FocusSection(id)
    local body = Page.ui and Page.ui.sections and Page.ui.sections[id]
    if body and W.FocusCollapsibleSection then W.FocusCollapsibleSection(body, { persist = true, flash = true }) end
end
-- Blizzard_CooldownViewer loads at startup on 12.1.0, 12.1.5 and WoW Forever.
function Page.CanOpenBlizzardSettings()
    return not P.Combat()
end
-- Blizzard's panel sits below the MSUF window, so the menu steps aside.
function Page.OpenBlizzardSettings()
    if not Page.CanOpenBlizzardSettings() then return false end
    if M.frame and M.frame.Hide then M.frame:Hide() end
    CooldownViewerSettings:TogglePanel()
    return true
end

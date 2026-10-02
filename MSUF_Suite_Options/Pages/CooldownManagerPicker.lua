local _, P = ...
-- Cooldown manager page, spell picker: Blizzard's cooldowns or buffs for the
-- selected bar, trinket slots and custom spell, item and aura IDs. A pooled
-- popup (CooldownManagerWidgets.lua) that stays open for several picks.
local Page = P.CDMPage
local Tr = P.Tr
local CDM = P.Suite.CDM
local FAMILY = CDM.FAMILY
local EMPTY = {}
local QUESTION = Page.QUESTION
local CROP_MIN, CROP_MAX = Page.CROP_MIN, Page.CROP_MAX
local floor, max, min, format = math.floor, math.max, math.min, string.format
local Public, Plain, EntryKey, SetIcon = Page.Public, Page.Plain, Page.EntryKey, Page.SetIcon
local Accent, TextColor, MutedColor, SetRaw = Page.Accent, Page.TextColor, Page.MutedColor, Page.SetRaw
local Button, Label, ShowTip, HideTip = Page.Button, Page.Label, Page.ShowTip, Page.HideTip

local PICK_W, PICK_H = 340, 470
local picker

-- Suggestions for buffs received from another player. These are aura IDs,
-- not the caster's cooldown entries: the player AuraContainer accepts every
-- caster. Only selected IDs become live aura groups; this list is options-only.
local RECEIVED_BUFFS = {
    10060,  -- Power Infusion
    29166,  -- Innervate
    6940,   -- Blessing of Sacrifice
    1022,   -- Blessing of Protection
    1044,   -- Blessing of Freedom
    33206,  -- Pain Suppression
    47788,  -- Guardian Spirit
    102342, -- Ironbark
    116849, -- Life Cocoon
}

local function SortCatalog(a, b)
    if a.rank ~= b.rank then return a.rank < b.rank end
    if a.known ~= b.known then return a.known end
    return a.sortName < b.sortName
end
local function Item(n, kind, text, key, texture, known, slot, family, spell, override, tooltip)
    local items = picker.items
    local item = items[n]
    if not item then
        item = {}
        items[n] = item
    end
    item.kind, item.text, item.key, item.texture = kind, text, key, texture
    item.known, item.slot, item.family = known ~= false, slot, family
    item.search = kind == "entry" and Page.SearchText(text, key, spell, override, tooltip) or nil
    return item
end
-- An equipped trinket slot (13 or 14); row is the runtime's catalog entry of
-- that slot, if any.
local function TrinketItem(n, trinket, row)
    local key = "e" .. trinket
    local texture = GetInventoryItemTexture("player", trinket)
    if not Public(texture) or texture == nil then texture = row and Plain(row.texture) or nil end
    local itemID = GetInventoryItemID("player", trinket)
    local name = Public(itemID) and type(itemID) == "number" and C_Item.GetItemNameByID(itemID) or nil
    local label = format(Tr("Trinket slot %d"), trinket - 12)
    if Public(name) and type(name) == "string" then label = label .. ": " .. name end
    -- The runtime knows where the slot lives even without an explicit list.
    local home = row and Plain(row.slot) or Page.WhereIs(key)
    Item(n, "entry", label, key, texture, true, home, 1)
end
-- Spell IDs of a catalog row, when the runtime provides them.
local function RowSpell(value)
    value = Plain(value)
    if type(value) == "number" and value > 0 then return value end
end
local function ResolveSpell(text)
    if text == "" then return nil end
    local id = tonumber(text)
    if not id then
        id = C_Spell.GetSpellIDForSpellIdentifier(text)
        if not Public(id) then id = nil end
    end
    if type(id) ~= "number" or id < 1 or id >= 2147483648 or id ~= floor(id) then return nil end
    local name = C_Spell.GetSpellName(id)
    if not Public(name) or type(name) ~= "string" then return nil end
    local texture = C_Spell.GetSpellTexture(id)
    return id, name, Public(texture) and texture or nil
end
local function ResolveItem(text)
    local id = tonumber(text)
    if type(id) ~= "number" or id < 1 or id >= 2147483648 or id ~= floor(id) then return nil end
    local name, texture = C_Item.GetItemNameByID(id), C_Item.GetItemIconByID(id)
    if not Public(name) then name = nil end
    if not Public(texture) then texture = nil end
    if name == nil then C_Item.RequestLoadItemDataByID(id) end
    if name == nil and texture == nil then return nil end
    return id, type(name) == "string" and name or format(Tr("Item %d"), id), texture
end

local function PickerRowEnter(self)
    self.hover:Show()
    local item = self.item
    if item and item.kind == "entry" then
        local first = not item.known and Tr("Not learned right now. You can add it anyway.") or nil
        local second = item.slot and item.slot ~= Page.selected and format(Tr("Picking it moves it from %s."), Page.BarName(item.slot)) or nil
        ShowTip(self, Public(item.text) and item.text or item.key, first, second)
    end
end
local function PickerRowLeave(self)
    self.hover:Hide()
    HideTip(self)
end
local function PickerRowClick(self)
    local item = self.item
    if not item or item.kind ~= "entry" or P.Combat() then return end
    Page.PickItem(item)
end
local function PickerRow(index)
    local row = picker.rows[index]
    if row then return row end
    row = CreateFrame("Button", nil, picker.content)
    row:SetSize(PICK_W - 40, 24)
    row:RegisterForClicks("LeftButtonUp")
    row.hover = row:CreateTexture(nil, "BACKGROUND")
    row.hover:SetAllPoints(row)
    row.hover:SetColorTexture(1, 1, 1, 0.06)
    row.hover:Hide()
    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(20, 20)
    row.icon:SetPoint("LEFT", row, "LEFT", 2, 0)
    row.icon:SetTexCoord(CROP_MIN, CROP_MAX, CROP_MIN, CROP_MAX)
    row.text = Label(row, "GameFontHighlightSmall", "")
    row.text:SetPoint("LEFT", row, "LEFT", 28, 0)
    row.text:SetWidth(PICK_W - 170)
    row.status = Label(row, "GameFontDisableSmall", "", "muted")
    row.status:SetPoint("RIGHT", row, "RIGHT", -4, 0)
    row.status:SetWidth(112)
    row.status:SetJustifyH("RIGHT")
    row:SetScript("OnClick", PickerRowClick)
    row:SetScript("OnEnter", PickerRowEnter)
    row:SetScript("OnLeave", PickerRowLeave)
    picker.rows[index] = row
    return row
end
local function PaintPickerRow(row, item)
    row.item = item
    local r, g, b = TextColor()
    if item.kind == "header" then
        r, g, b = Accent()
        row.icon:Hide()
        row.text:ClearAllPoints()
        row.text:SetPoint("LEFT", row, "LEFT", 2, 0)
        row.text:SetText(item.text)
        row.status:SetText("")
        row:SetAlpha(1)
    else
        row.icon:Show()
        SetIcon(row.icon, item.texture)
        row.icon:SetDesaturated(not item.known)
        row.text:ClearAllPoints()
        row.text:SetPoint("LEFT", row, "LEFT", 28, 0)
        SetRaw(row.text, Public(item.text) and item.text or item.key)
        local status, alpha = "", 1
        if item.slot == Page.selected then
            status, alpha = Tr("On this bar"), 0.45
        elseif item.slot then
            status = format(Tr("On %s"), Page.BarName(item.slot))
        elseif picker.removed[item.key] then
            status = Tr("Removed")
        elseif not item.known then
            status = Tr("Not learned")
        end
        SetRaw(row.status, status)
        row:SetAlpha(item.known and alpha or min(alpha, 0.55))
    end
    row.text:SetTextColor(r, g, b)
end

function Page.FilterPicker()
    if not picker then return end
    local query = Page.Query(picker.search)
    local spec = Page.Spec()
    picker.removed = spec and Page.ListsView().hidden[spec] or EMPTY
    local items, count = picker.items, picker.count
    local any, section = false, nil
    for i = 1, count do
        local item = items[i]
        if item.kind == "header" then
            section = item
            item.match = false
        else
            item.match = query == "" or (item.search ~= nil and item.search:find(query, 1, true) ~= nil)
            if item.match and section then
                section.match = true
                any = true
            end
        end
    end
    local shown = 0
    for i = 1, count do
        local item = items[i]
        if item.match then
            shown = shown + 1
            local row = PickerRow(shown)
            PaintPickerRow(row, item)
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", picker.content, "TOPLEFT", 0, -(shown - 1) * 24)
            row:Show()
        end
    end
    for i = shown + 1, #picker.rows do
        picker.rows[i].item = nil
        picker.rows[i]:Hide()
    end
    picker.shown = shown
    picker.content:SetHeight(max(1, shown * 24))
    SetRaw(picker.empty, any and "" or Tr("Nothing matches. Try a spell ID below."))
    picker.empty:SetShown(not any)
end

-- Blizzard's catalog entries for the bar's family, sorted for the picker
-- (pooled records); equipment slots go to equip for the trinket section.
local function CollectCatalog(slot, family)
    local sorted, bySpell, equip = picker.sorted, picker.bySpell, picker.equip
    for i = #sorted, 1, -1 do sorted[i] = nil end
    for id in pairs(bySpell) do bySpell[id] = nil end
    equip[13], equip[14] = nil, nil
    local catalog = Page.Catalog(family) or EMPTY
    for i = 1, #catalog do
        local entry = catalog[i]
        local key = EntryKey(entry)
        if key and CDM.EntryKind(key) == "e" then
            -- Equipment slots belong to the trinket section below.
            equip[CDM.EntryID(key)] = entry
        elseif key then
            local record = picker.pool[i]
            if not record then
                record = {}
                picker.pool[i] = record
            end
            record.entry, record.key, record.slot = entry, key, Plain(entry.slot)
            record.rank = record.slot == nil and 0 or record.slot == slot and 2 or 1
            record.known = Plain(entry.known) ~= false
            record.sortName = Public(entry.name) and type(entry.name) == "string" and entry.name:lower() or key
            record.spell, record.override = RowSpell(entry.spell), RowSpell(entry.override)
            record.tooltip = RowSpell(entry.tooltip)
            sorted[#sorted + 1] = record
        end
    end
    table.sort(sorted, SortCatalog)
    return sorted, bySpell, equip
end

-- Buffs other players cast on you (Power Infusion, Innervate, ...), after
-- the catalog; n is the last row so far, the result the new last row.
local function AddReceivedBuffs(n)
    local headerAdded = false
    for i = 1, #RECEIVED_BUFFS do
        local id = RECEIVED_BUFFS[i]
        local name = C_Spell.GetSpellName(id)
        if Public(name) and type(name) == "string" then
            if not headerAdded then
                n = n + 1
                Item(n, "header", Tr("Received buffs (any caster)"))
                headerAdded = true
            end
            local texture = C_Spell.GetSpellTexture(id)
            n = n + 1
            Item(n, "entry", name, "a" .. id, Public(texture) and texture or nil,
                true, Page.WhereIs("a" .. id), 2, id)
        end
    end
    return n
end

-- The two trinket slots, after the catalog.
local function AddTrinkets(n, equip)
    n = n + 1
    Item(n, "header", Tr("Trinkets and items"))
    for trinket = 13, 14 do
        n = n + 1
        TrinketItem(n, trinket, equip[trinket])
    end
    return n
end

function Page.RebuildPicker()
    local slot = Page.selected
    local family = Page.Family(slot)
    SetRaw(picker.title, format(Tr("Add to %s"), Page.BarName(slot)))
    local n = 1
    Item(n, "header", Tr(family == FAMILY.COOLDOWN and "Blizzard cooldowns" or "Blizzard buffs"))
    local sorted, bySpell, equip = CollectCatalog(slot, family)
    for i = 1, #sorted do
        local record = sorted[i]
        n = n + 1
        local item = Item(n, "entry", record.entry.name, record.key, record.entry.texture, record.known, record.slot,
            family, record.spell, record.override, record.tooltip)
        if record.spell and not bySpell[record.spell] then bySpell[record.spell] = item end
        if record.override and not bySpell[record.override] then bySpell[record.override] = item end
    end
    if family == FAMILY.AURA then n = AddReceivedBuffs(n) end
    if family == FAMILY.COOLDOWN then n = AddTrinkets(n, equip) end
    picker.count = n
    picker.family = family
    SetRaw(picker.idTitle, Tr(family == FAMILY.COOLDOWN and "Custom spell or item ID" or "Custom aura ID"))
    picker.addA:SetText(family == FAMILY.COOLDOWN and "Add spell" or "Buff on me")
    picker.addB:SetText(family == FAMILY.COOLDOWN and "Add item" or "Debuff on target")
    Page.EchoCustom()
    Page.FilterPicker()
end

function Page.PickItem(item)
    if item.slot == Page.selected then return false end
    local name = Public(item.text) and item.text or item.key
    local from = item.slot
    local ok, reason = Page.AddEntry(Page.selected, item.key, item.family)
    if ok then
        item.slot = Page.selected
        local text = from and format(Tr("Moved %s from %s."), name, Page.BarName(from)) or format(Tr("Added %s."), name)
        SetRaw(picker.note, text)
        Page.Note(text)
    else
        SetRaw(picker.note, Tr(reason or "That did not work."))
    end
    Page.FilterPicker()
    return ok
end

function Page.EchoCustom()
    local text = (picker.idBox:GetText() or ""):gsub("^%s+", ""):gsub("%s+$", "")
    local spellID, spellName, spellIcon = ResolveSpell(text)
    local itemID, itemName, itemIcon
    if picker.family == FAMILY.COOLDOWN then itemID, itemName, itemIcon = ResolveItem(text) end
    -- Cooldowns reuse Blizzard's entry. A received buff must keep its own
    -- a<spellID> key: Blizzard's entry can be unlearned or caster-filtered.
    local blizzard = picker.family == FAMILY.COOLDOWN and spellID and picker.bySpell[spellID] or nil
    picker.customSpell, picker.customItem, picker.customBlizzard = spellID, itemID, blizzard
    local r, g, b = MutedColor()
    if text == "" then
        SetRaw(picker.echo, Tr("Type an ID or a spell name."))
    elseif spellID or itemID then
        r, g, b = 0.35, 0.95, 0.45
        local parts = spellID and format(Tr("Spell %d"), spellID) .. ": " .. spellName or ""
        if blizzard then parts = parts .. " (" .. Tr("Blizzard's entry") .. ")" end
        if itemID then parts = parts .. (parts ~= "" and "  |  " or "") .. format(Tr("Item %d"), itemID) .. ": " .. itemName end
        SetRaw(picker.echo, parts)
    else
        r, g, b = 1, 0.35, 0.3
        SetRaw(picker.echo, Tr("No spell or item with this ID."))
    end
    picker.echo:SetTextColor(r, g, b)
    picker.echoIcon:SetTexture(spellIcon or itemIcon or QUESTION)
    picker.echoIcon:SetShown((spellID or itemID) ~= nil)
    picker.addA:SetEnabled(spellID ~= nil)
    picker.addB:SetEnabled(picker.family == FAMILY.COOLDOWN and itemID ~= nil or picker.family ~= FAMILY.COOLDOWN and spellID ~= nil)
end
local function AddCustom(prefix)
    if P.Combat() then return end
    local id = prefix == "i" and picker.customItem or picker.customSpell
    if not id then return end
    local blizzard = prefix ~= "i" and picker.customBlizzard or nil
    if blizzard then
        if blizzard.slot == Page.selected then
            SetRaw(picker.note, Tr("Blizzard's entry for this spell is already on this bar."))
        elseif Page.PickItem(blizzard) then
            picker.idBox:SetText("")
        end
        return
    end
    local key = prefix .. id
    local from = Page.WhereIs(key)
    local ok, reason = Page.AddEntry(Page.selected, key, (prefix == "a" or prefix == "d") and 2 or 1)
    if ok then
        local text = from and from ~= Page.selected and format(Tr("Moved %s from %s."), Page.Identity(key), Page.BarName(from))
            or format(Tr("Added %s."), Page.Identity(key))
        SetRaw(picker.note, text)
        Page.Note(text)
        picker.idBox:SetText("")
    else
        SetRaw(picker.note, Tr(reason or "That did not work."))
    end
end

local function EnsurePicker()
    if picker then return picker end
    picker = Page.NewPopup(PICK_W, PICK_H)
    Page.picker = picker
    picker.items, picker.rows, picker.sorted, picker.pool, picker.count = {}, {}, {}, {}, 0
    picker.bySpell, picker.equip = {}, {}
    picker.title = Label(picker, "GameFontNormal", "")
    picker.title:SetPoint("TOPLEFT", picker, "TOPLEFT", 12, -12)
    picker.title:SetWidth(PICK_W - 60)
    picker.close = Button(picker, "x", 22, 20, function() picker:Hide() end)
    picker.close:SetPoint("TOPRIGHT", picker, "TOPRIGHT", -8, -8)
    picker.search = Page.SearchBox(picker, PICK_W - 28, Tr("Type a name or ID to filter"), Page.FilterPicker)
    picker.search:SetPoint("TOPLEFT", picker, "TOPLEFT", 14, -36)
    picker.scroll, picker.content = Page.ScrollArea(picker, PICK_W - 40)
    picker.scroll:SetPoint("TOPLEFT", picker, "TOPLEFT", 12, -66)
    picker.scroll:SetPoint("BOTTOMRIGHT", picker, "BOTTOMRIGHT", -26, 132)
    picker.empty = Label(picker, "GameFontHighlightSmall", "", "muted")
    picker.empty:SetPoint("TOPLEFT", picker, "TOPLEFT", 16, -72)
    picker.idTitle = Label(picker, "GameFontHighlightSmall", "", "muted")
    picker.idTitle:SetPoint("BOTTOMLEFT", picker, "BOTTOMLEFT", 14, 112)
    picker.idBox = Page.SearchBox(picker, 120, Tr("ID or name"), Page.EchoCustom)
    picker.idBox:SetPoint("BOTTOMLEFT", picker, "BOTTOMLEFT", 16, 82)
    picker.addA = Button(picker, "", 90, 22, function() AddCustom(picker.family == FAMILY.COOLDOWN and "s" or "a") end)
    picker.addA:SetPoint("LEFT", picker.idBox, "RIGHT", 8, 0)
    picker.addB = Button(picker, "", 100, 22, function() AddCustom(picker.family == FAMILY.COOLDOWN and "i" or "d") end)
    picker.addB:SetPoint("LEFT", picker.addA, "RIGHT", 6, 0)
    picker.echoIcon = picker:CreateTexture(nil, "ARTWORK")
    picker.echoIcon:SetSize(16, 16)
    picker.echoIcon:SetPoint("BOTTOMLEFT", picker, "BOTTOMLEFT", 14, 56)
    picker.echoIcon:SetTexCoord(CROP_MIN, CROP_MAX, CROP_MIN, CROP_MAX)
    picker.echo = Label(picker, "GameFontHighlightSmall", "")
    picker.echo:SetPoint("LEFT", picker.echoIcon, "RIGHT", 6, 0)
    picker.echo:SetWidth(PICK_W - 50)
    picker.note = Label(picker, "GameFontHighlightSmall", "", "muted")
    picker.note:SetPoint("BOTTOMLEFT", picker, "BOTTOMLEFT", 14, 16)
    picker.note:SetWidth(PICK_W - 28)
    picker.hint = Label(picker, "GameFontDisableSmall", "Picks stay open so you can add several.", "muted")
    picker.hint:SetPoint("BOTTOMLEFT", picker, "BOTTOMLEFT", 14, 34)
    picker.OnClosed = function(self)
        self.search:ClearFocus()
        self.idBox:ClearFocus()
    end
    return picker
end

function Page.TogglePicker(anchor)
    if picker and picker:IsShown() and picker.anchor == anchor then
        picker:Hide()
        return false
    end
    if P.Combat() or Page.EditorBlocked() then return false end
    EnsurePicker()
    Page.ClosePopups(picker)
    Page.PlacePopup(picker, anchor)
    picker.note:SetText("")
    picker.search:SetText("")
    picker.idBox:SetText("")
    picker.scroll:SetVerticalScroll(0)
    Page.RebuildPicker()
    picker:Show()
    return true
end

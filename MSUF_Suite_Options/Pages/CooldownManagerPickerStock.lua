local _, P = ...
local Page, Tr = P.CDMPage, P.Tr
local COOLDOWN = P.Suite.CDM.FAMILY.COOLDOWN
local Stock = {}
Page.PickerStock = Stock

local Plain = Page.Plain
local EMPTY = {}

local function ItemID(value)
    value = Plain(value)
    if type(value) == "number" and value > 0 then return value end
end

function Stock.EachBagItem(visit)
    local seen = {}
    for bag = 0, NUM_BAG_SLOTS do
        local slots = Plain(C_Container.GetContainerNumSlots(bag))
        if type(slots) == "number" then
            for slot = 1, math.min(slots, 100) do
                local id = ItemID(C_Container.GetContainerItemID(bag, slot))
                if id and not seen[id] then
                    seen[id] = true
                    visit(id)
                end
            end
        end
    end
end

local function KnownRacial(id)
    local known = C_SpellBook and C_SpellBook.IsSpellKnownOrInSpellBook or IsPlayerSpell
    return known and Plain(known(id)) == true
end

local function EachCatalogItem(lists, visit)
    for _, list in ipairs(lists or EMPTY) do
        for _, id in ipairs(list) do visit(id) end
    end
end

function Stock.Add(n, picker, row, request, native)
    local catalog = P.S.CooldownManagerConsumableCatalog
    if not catalog then return n end
    local potions, racials = catalog()
    local index, seen, entries = n + 1, {}, {}
    row(index, "header", Tr("Potions and racials"))
    local function AddPotion(id, listed)
        if seen[id] then return end
        local count = Plain(C_Item.GetItemCount(id, false, false))
        if not picker.allStock and (type(count) ~= "number" or count <= 0) then return end
        if not listed then
            local _, _, _, _, _, class, subclass = C_Item.GetItemInfoInstant(id)
            class, subclass = Plain(class), Plain(subclass)
            if class == nil then request(id) end
            if class ~= Enum.ItemClass.Consumable or subclass ~= Enum.ItemConsumableSubclass.Potion then return end
        end
        seen[id] = true
        local name = Plain(C_Item.GetItemNameByID(id))
        if type(name) ~= "string" then
            request(id)
            name = Tr("Item %d"):format(id)
        end
        local key = "i" .. id
        index = index + 1
        local item = row(index, "entry", name, key,
            Plain(C_Item.GetItemIconByID(id)), true, Page.WhereIs(key), COOLDOWN)
        item.stock = type(count) == "number" and count or nil
        entries[key] = item
    end
    EachCatalogItem(potions, function(id) AddPotion(id, true) end)
    Stock.EachBagItem(AddPotion)
    local bySpell = {}
    for _, record in ipairs(native) do
        local spell, override = record.spell, record.override
        if spell and not bySpell[spell] then bySpell[spell] = record.key end
        if override and not bySpell[override] then bySpell[override] = record.key end
    end
    EachCatalogItem(racials, function(id)
        local key = bySpell[id] or "s" .. id
        if entries[key] then return end
        local known = KnownRacial(id) == true
        if not picker.allStock and not known then return end
        local name = Plain(C_Spell.GetSpellName(id))
        if type(name) ~= "string" then name = Tr("Spell %d"):format(id) end
        index = index + 1
        entries[key] = row(index, "entry", name, key,
            Plain(C_Spell.GetSpellTexture(id)), known, Page.WhereIs(key), COOLDOWN, id)
    end)
    return index == n + 1 and n or index, entries
end

function Stock.CreateControls(picker)
    local function Choose(all)
        if P.Combat() then return end
        picker.allStock = all
        picker.scroll:SetVerticalScroll(0)
        Page.RebuildPicker()
    end
    picker.inBags = Page.Button(picker, "In bags", 100, 21, function() Choose(false) end)
    picker.inBags:SetPoint("TOPLEFT", picker.search, "BOTTOMLEFT", 0, -5)
    picker.allItems = Page.Button(picker, "All items", 100, 21, function() Choose(true) end)
    picker.allItems:SetPoint("LEFT", picker.inBags, "RIGHT", 5, 0)
end

function Stock.PlaceControls(picker, shown)
    if picker.stockControlsShown == shown then
        if not shown then return end
    else
        picker.stockControlsShown = shown
        picker.inBags:SetShown(shown)
        picker.allItems:SetShown(shown)
        local y = shown and -91 or -66
        picker.scroll:ClearAllPoints()
        picker.scroll:SetPoint("TOPLEFT", picker, "TOPLEFT", 12, y)
        picker.scroll:SetPoint("BOTTOMRIGHT", picker, "BOTTOMRIGHT", -26, 132)
        picker.empty:ClearAllPoints()
        picker.empty:SetPoint("TOPLEFT", picker, "TOPLEFT", 16, y - 6)
    end
    picker.inBags:SetEnabled(picker.allStock == true)
    picker.allItems:SetEnabled(picker.allStock ~= true)
end

local _, P = ...
local NS = P.NS
local Macros = NS.Macros
local Consumables = {}
Macros.Consumables = Consumables
local Data = Macros.ConsumableData

local function Known(value)
    return not NS.IsSecret(value)
end

local function Usable(id)
    local usable = C_Item.IsUsableItem(id)
    return Known(usable) and usable == true
end

local function Remaining(bag, slot)
    local start, duration, enabled = C_Container.GetContainerItemCooldown(bag, slot)
    if not NS.Finite(start) or not NS.Finite(duration) or not NS.Finite(enabled) then return math.huge end
    if enabled ~= 1 then return math.huge end
    if start == 0 or duration == 0 then return 0 end
    local now = GetTime()
    return NS.Finite(now) and math.max(0, start + duration - now) or math.huge
end

local function Strength(definition, kind, health, mana, fallback)
    if not definition or definition.power == nil then return fallback end
    local resource = (kind == "mana" or kind == "drink") and mana or health
    local strength = definition.power + (definition.percent or 0) * resource
    return strength > 0 and strength or fallback
end

local function BuffFood(id, subclass)
    if subclass ~= 5 then return false end
    if NS.Client.isForever then return Data.foreverBuffFood[id] == true end
    local _, spellID = C_Item.GetItemSpell(id)
    return NS.Finite(spellID) and Data.foodSpells[spellID] == true
end

local function Kind(subclass, definition, buffFood)
    if definition then return definition.kind end
    if buffFood then return "food" end
    return Data.subclasses[subclass] or "other"
end

local function Item(id, count, health, mana, bag, slot)
    local name, _, quality, level, required, _, _, _, _, icon, _, class, subclass = C_Item.GetItemInfo(id)
    if not NS.PublicText(name) then return nil, "pending" end
    if not Known(class) or class ~= 0 then return nil end
    if not Known(subclass) or not Usable(id) then return nil end
    local definition = Data.Get(id)
    local buffFood = BuffFood(id, subclass)
    local kind = Kind(subclass, definition, buffFood)
    if not NS.Finite(level) then level = 0 end
    if not NS.Finite(required) then required = 0 end
    if not NS.Finite(quality) then quality = 0 end
    local rank = required * 100000 + level * 100 + (definition and definition.rank or quality)
    return { id = id, name = name, icon = Known(icon) and icon or 134400, kind = kind, count = count,
        score = Strength(definition, kind, health, mana, rank),
        stat = definition and definition.stat, conjured = definition and definition.conjured == true,
        recovery = definition and definition.recovery == true, buffFood = buffFood, cooldown = Remaining(bag, slot) }
end

local function AddBag(result, seen, bag, health, mana)
    local slots = C_Container.GetContainerNumSlots(bag)
    if not NS.Finite(slots) or slots < 0 or slots > 1000 then return end
    for slot = 1, slots do
        local info = C_Container.GetContainerItemInfo(bag, slot)
        if Known(info) and type(info) == "table" then
            local id, count = info.itemID, info.stackCount
            if NS.Finite(id) and id > 0 and NS.Finite(count) and count > 0 then
                if seen[id] then
                    seen[id].count = seen[id].count + count
                else
                    local entry, reason = Item(id, count, health, mana, bag, slot)
                    if entry then
                        result[#result + 1], seen[id] = entry, entry
                    elseif reason == "pending" then
                        C_Item.RequestLoadItemDataByID(id)
                    end
                end
            end
        end
    end
end

local function Sort(a, b)
    if a.cooldown ~= b.cooldown then return a.cooldown < b.cooldown end
    if a.score ~= b.score then return a.score > b.score end
    return a.id < b.id
end

function Consumables.Scan()
    if NS.InCombat() then return {}, "Macro changes are unavailable in combat" end
    local result, seen = {}, {}
    local health = UnitHealthMax("player")
    local mana = UnitPowerMax("player", 0)
    if not NS.Finite(health) then health = 0 end
    if not NS.Finite(mana) then mana = 0 end
    local last = NS.Client.isForever and 4 or 5
    for bag = 0, last do AddBag(result, seen, bag, health, mana) end
    table.sort(result, Sort)
    return result
end

local function FindByID(entries, id)
    id = tonumber(id)
    for _, entry in ipairs(entries) do if entry.id == id then return entry end end
end

local function Pool(options, entries)
    if not options.items or #options.items == 0 then return entries end
    local pool = {}
    for _, id in ipairs(options.items) do
        local item = FindByID(entries, id)
        if item then pool[#pool + 1] = item end
    end
    return pool
end

local function Accepts(entry, kind, options)
    if kind == "bufffood" then return entry.buffFood end
    if kind == "recoveryfood" then return not entry.buffFood and (entry.kind == "food" or entry.recovery) end
    if kind == "drink" and entry.buffFood then return false end
    if entry.kind ~= kind then return false end
    if kind == "flask" and options.stat and options.stat ~= "any" and entry.stat ~= options.stat then return false end
    return true
end

local function Best(entries, kind, options)
    local best
    for _, entry in ipairs(entries) do
        if Accepts(entry, kind, options) then
            if not best or options.preferConjured and entry.conjured and not best.conjured
                and entry.cooldown <= best.cooldown then best = entry end
            if best == entry and options.items and #options.items > 0 then return best end
        end
    end
    return best
end

local function Token(item)
    return item and "item:" .. item.id
end

local function Spell(id)
    local identifier = tonumber(id) or id
    local info = C_Spell.GetSpellInfo(identifier)
    if not Known(info) or type(info) ~= "table" then return nil end
    local spellID = info.spellID
    if not NS.Finite(spellID) then return nil end
    local known = C_SpellBook.IsSpellInSpellBook(spellID)
    if not Known(known) or not known then return nil end
    local name = NS.PublicText(info.name)
    if name and not name:find("[\r\n;,%%[%]]") then return name end
end

local function Reset(options)
    local reset, values = options.reset or {}, {}
    if reset.target then values[#values + 1] = "target" end
    if reset.combat then values[#values + 1] = "combat" end
    if reset.mod == "shift" or reset.mod == "ctrl" or reset.mod == "alt" then values[#values + 1] = reset.mod end
    if NS.Finite(reset.seconds) and reset.seconds >= 1 and reset.seconds <= 600 then
        values[#values + 1] = tostring(math.floor(reset.seconds))
    end
    return #values > 0 and "reset=" .. table.concat(values, "/") .. " " or ""
end

local function Health(options, entries, lines)
    local sequence, seen = {}, {}
    local priorities = options.priorities or { "stone", "potion", "spell" }
    for _, kind in ipairs(priorities) do
        if kind == "spell" then
            for _, id in ipairs(options.spells or {}) do
                local name = Spell(id)
                if name and not seen[name] then sequence[#sequence + 1], seen[name] = name, true end
            end
        else
            local item = Best(entries, kind, options)
            local token = Token(item)
            if token and not seen[token] then sequence[#sequence + 1], seen[token] = token, true end
        end
    end
    if #sequence == 0 and options.items and #options.items > 0 then
        for _, item in ipairs(entries) do sequence[#sequence + 1] = Token(item) end
    end
    if #sequence == 0 then return false end
    if options.stopCasting then lines[#lines + 1] = "/stopcasting" end
    lines[#lines + 1] = "/castsequence " .. Reset(options) .. table.concat(sequence, ",")
    return true
end

local function Recovery(options, entries, lines)
    local drink = Best(entries, "drink", options)
    local food
    if options.includeFood then food = Best(entries, "recoveryfood", options) end
    if not drink and not food and options.items and #options.items > 0 then drink = entries[1] end
    if options.combatMana then
        local mana = Best(entries, "mana", options)
        if mana then lines[#lines + 1] = "/use [combat] " .. Token(mana) end
    end
    if drink and drink.recovery then food = nil end
    if food then lines[#lines + 1] = "/use [nocombat] " .. Token(food) end
    if drink and (not food or drink.id ~= food.id) then lines[#lines + 1] = "/use [nocombat] " .. Token(drink) end
    return drink ~= nil or food ~= nil
end

function Consumables.Build(document)
    if NS.InCombat() then return nil, "Macro changes are unavailable in combat" end
    local options = document.consumable or {}
    local entries = Pool(options, Consumables.Scan())
    local lines = document.showTooltip == false and {} or { "#showtooltip" }
    local available
    if options.kind == "health" then
        available = Health(options, entries, lines)
    elseif options.kind == "drink" then
        available = Recovery(options, entries, lines)
    else
        local kind = options.kind == "food" and "bufffood" or options.kind
        local item = Best(entries, kind, options)
        if not item and options.items and #options.items > 0 then item = entries[1] end
        if item then
            local condition = options.kind == "bandage" and "[nochanneling] " or "[nocombat] "
            lines[#lines + 1] = "/use " .. condition .. Token(item)
            available = true
        end
    end
    if not available then return nil, "No matching consumables are available in your bags" end
    return table.concat(lines, "\n")
end

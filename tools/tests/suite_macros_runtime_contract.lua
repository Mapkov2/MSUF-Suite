local root = assert(arg[1], "repository root required")
local checks = 0
local function Check(value, message)
    checks = checks + 1
    assert(value, message)
end

local function Run(flavor)
    local combat, combatEdge, cursor = false, false, nil
    local macros, items, bag, timers, frames = {}, {}, {}, {}, {}
    local creates, edits, scans, pickups, reported, now, callbacks = 0, 0, 0, 0, 0, 0, 0
    local accountLimit, characterLimit = 120, 30
    local cooldowns = {}
    local failCreate = false
    local NS = { RootDB = {}, Client = { isForever = flavor == "Forever", SupportsEvent = function() return true end } }
    local secret = {}
    NS.IsSecret = function(value) return value == secret end
    NS.Finite = function(value)
        return value ~= secret and type(value) == "number" and value == value and math.abs(value) < math.huge
    end
    NS.PublicText = function(value) return value ~= secret and type(value) == "string" and value ~= "" and value end
    NS.InCombat = function() return combat or combatEdge end
    NS.Finish = function(callback, ...) return true, callback(...) end
    NS.Dispatch = function(callback, ...)
        local result = { pcall(callback, ...) }
        if not result[1] then reported = reported + 1 return end
        return unpack(result, 2)
    end
    UnitGUID = function() return "Player-1-123" end
    UnitHealthMax = function() return 200000 end
    UnitPowerMax = function() return 100000 end
    Constants = { MacroConsts = { MAX_ACCOUNT_MACROS = accountLimit, MAX_CHARACTER_MACROS = characterLimit } }
    GetNumMacros = function()
        local account, character = 0, 0
        for index in pairs(macros) do
            if index <= accountLimit then account = account + 1 else character = character + 1 end
        end
        return account, character
    end
    GetMacroInfo = function(index)
        local row = macros[index]
        if row then return row.name, row.icon, row.body end
    end
    C_Macro = { GetSelectedMacroIcon = function(index)
        local row = macros[index]
        return row and row.icon
    end }
    CreateMacro = function(name, icon, body, perCharacter)
        Check(not NS.InCombat(), "CreateMacro ran in combat")
        if failCreate then error("native create refused") end
        local a, c = GetNumMacros()
        local index = perCharacter and accountLimit + c + 1 or a + 1
        macros[index] = { name = name, icon = icon, body = body }
        creates = creates + 1
        return index
    end
    EditMacro = function(index, name, icon, body)
        Check(not NS.InCombat(), "EditMacro ran in combat")
        Check(macros[index] ~= nil, "EditMacro overwrote an unknown slot")
        macros[index] = { name = name, icon = icon, body = body }
        edits = edits + 1
        return index
    end
    GetCursorInfo = function() return cursor end
    PickupMacro = function() pickups = pickups + 1 end
    C_Container = {
        GetContainerNumSlots = function(id) scans = scans + 1 return id == 0 and #bag or 0 end,
        GetContainerItemInfo = function(_, slot)
            local id = bag[slot]
            return id and { itemID = id, stackCount = 3 }
        end,
        GetContainerItemCooldown = function(_, slot) return 1, cooldowns[bag[slot]] or 0, 1 end,
    }
    C_Item = {
        GetItemInfo = function(id)
            local item = items[id]
            if not item then return nil end
            return item.name, "item:" .. id, 1, item.level or 1, item.required or 1,
                "Consumable", "", 20, "", 134400, 1, item.class or 0, item.subclass or 1
        end,
        IsUsableItem = function(id) return items[id] and items[id].usable ~= false end,
        GetItemSpell = function(id)
            if id == 888888 then return "Refreshment", 1232481 end
        end,
        RequestLoadItemDataByID = function() end,
    }
    GetTime = function() return 1 end
    C_Spell = { GetSpellInfo = function(id)
        if id == 123 or id == "Heal" then return { name = "Heal", spellID = 123 } end
    end }
    C_SpellBook = { IsSpellInSpellBook = function(id) return id == 123 end }
    C_Timer = { NewTimer = function(_, callback)
        local timer = { callback = callback, cancelled = false }
        function timer:Cancel() self.cancelled = true end
        timers[#timers + 1] = timer
        return timer
    end }
    local function Tick()
        local pending = timers
        timers = {}
        now = now + 1
        for _, timer in ipairs(pending) do if not timer.cancelled then timer.callback() end end
    end
    local function Frame()
        local frame = { events = {}, scripts = {} }
        function frame:RegisterEvent(event) self.events[event] = true end
        function frame:UnregisterAllEvents() self.events = {} end
        function frame:SetScript(name, callback) self.scripts[name] = callback end
        frames[#frames + 1] = frame
        return frame
    end
    local function Event(event)
        for _, frame in ipairs(frames) do
            if frame.events[event] then
                callbacks = callbacks + 1
                frame.scripts.OnEvent(frame, event)
            end
        end
    end
    local S = { CreateFrame = Frame }
    local module
    S.Install = function(id, instance) Check(id == "macroBuilder", "module id changed") module = instance end
    NS.Menu = { Open = function(page) return page == "suite_macros" end }
    for _, file in ipairs({ "Model", "Compile", "Templates", "Native", "Store" }) do
        assert(loadfile(root .. "/MSUF_Suite/Core/Macros/" .. file .. ".lua"))("MSUF_Suite", NS)
    end
    for _, file in ipairs({ "MacroConsumableData", "MacroConsumables", "MacroBuilder" }) do
        assert(loadfile(root .. "/MSUF_Suite_QualityOfLife/" .. file .. ".lua"))("QoL", { NS = NS, Suite = S })
    end
    Check(next(NS.RootDB) == nil and scans == 0 and #frames == 0, "load time touched profile or allocated runtime")
    local Store, Model = NS.Macros.Store, NS.Macros.Model
    local doc = Model.New()
    doc.name, doc.mode, doc.raw = "Test", "raw", "/say hello"
    local id = assert(Store.Save(doc))
    Check(Store.Get(id).raw == "/say hello", "draft roundtrip failed")
    doc.raw = "/say changed"
    Check(Store.Get(id).raw == "/say hello", "draft retained caller table")
    local ok, reason, index = Store.Publish(id)
    Check(ok and index == 121 and creates == 1, reason or "publish failed")
    Check(Store.Get(id).published, "published flag missing")
    Check(not Store.Publish(id), "duplicate creation was allowed")
    local copy = Store.Get(id)
    copy.raw = "/say revised"
    assert(Store.Save(copy, id))
    Check(Store.Publish(id, true) and edits == 1, "known macro did not update")
    macros[index].body = "/say external"
    copy.raw = "/say overwrite"
    assert(Store.Save(copy, id))
    Check(not Store.Publish(id, true) and macros[index].body == "/say external", "external edit was overwritten")
    local imported = assert(Store.Import(index))
    local importedDoc = Store.Get(imported)
    importedDoc.raw = "/say imported"
    assert(Store.Save(importedDoc, imported))
    Check(Store.Publish(imported, true), "explicit reimport did not accept current fingerprint")
    macros[index].icon = 9876
    Check(not Store.Publish(imported, true), "external icon edit was overwritten")
    macros[index].icon = 134400
    cursor = "item"
    Check(not Store.Pickup(imported) and pickups == 0, "occupied cursor was overwritten")
    cursor = nil
    Check(Store.Pickup(imported) and pickups == 1, "macro was not picked up")
    Check(Store.Delete(imported) and macros[index] ~= nil, "deleting a draft deleted its native macro")
    local emptyIndex = 122
    macros[emptyIndex] = { name = "Empty", icon = 134400, body = "" }
    Check(#Store.Native() == 2, "empty native macro was omitted")
    local emptyDraft = assert(Store.Import(emptyIndex))
    local emptyDocument = Store.Get(emptyDraft)
    emptyDocument.raw = "/say filled"
    assert(Store.Save(emptyDocument, emptyDraft))
    Check(Store.Publish(emptyDraft, true) and macros[emptyIndex].body == "/say filled",
        "blank native macro could not be edited after import")
    local account = Store.Get(id)
    account.name, account.scope = "Account", "account"
    local accountID = assert(Store.Save(account))
    Check(Store.Publish(accountID), "account macro creation failed")
    for slot = 2, 120 do macros[slot] = { name = "Used" .. slot, icon = 134400, body = "" } end
    account.name = "Full"
    local fullID = assert(Store.Save(account))
    Check(not Store.Publish(fullID), "full native account storage accepted a macro")
    for slot = 1, 120 do macros[slot] = nil end
    failCreate = true
    copy.name = "Failure"
    local failureID = assert(Store.Save(copy))
    Check(not Store.Publish(failureID) and reported == 1, "native errors were swallowed")
    failCreate = false
    combatEdge = true
    Check(not Store.Save(copy) and not Store.Publish(id, true), "combat edge allowed writes")
    Check(#Store.Native() == 0 and not Store.Import(121), "combat edge allowed macro reads")
    combatEdge = false

    items[5512] = { name = "Healthstone", level = 1 }
    items[118] = { name = "Potion", level = 1 }
    items[858] = { name = "Better potion", level = 2 }
    items[159] = { name = "Water", level = 1, subclass = 5 }
    items[113509] = { name = "Mage food", level = 1, subclass = 5 }
    items[1251] = { name = "Bandage", level = 1, subclass = 7 }
    items[241325] = { name = "Haste flask", level = 1, subclass = 3 }
    items[241322] = { name = "Mastery flask", level = 1, subclass = 3 }
    bag = { 5512, 118, 858, 159, 113509, 1251, 241325, 241322 }
    local health = { version = 1, name = "Recovery", scope = "character", mode = "consumable", showTooltip = true,
        consumable = { kind = "health", managed = true, priorities = { "stone", "potion", "spell" },
            spells = { 123 }, items = {}, reset = { combat = true } } }
    local body = assert(Store.Preview(health))
    Check(body:find("item:5512,item:858,Heal", 1, true), "health order or best available selection failed")
    cooldowns[858] = 30
    body = assert(Store.Preview(health))
    Check(body:find("item:5512,item:118,Heal", 1, true), "unready potion displaced a ready one")
    cooldowns[858] = nil
    local healthID = assert(Store.Save(health))
    Check(Store.Publish(healthID), "managed macro failed to publish")
    Check(Store.HasManaged(), "managed binding missing")
    local scopeDraft = Store.Get(healthID)
    scopeDraft.scope = "account"
    assert(Store.Save(scopeDraft, healthID))
    Check(Store.HasManaged(), "unpublished scope edit disabled the installed managed recipe")
    bag = { 5512, 118, 159, 113509, 1251, 241325, 241322 }
    Store.RefreshManaged()
    Check(macros[123].body:find("item:118", 1, true), "old published scope stopped refreshing")
    scopeDraft.scope = "character"
    assert(Store.Save(scopeDraft, healthID))
    bag = { 5512, 118, 858, 159, 113509, 1251, 241325, 241322 }
    module.active = true
    module:Enable()
    Tick()
    Check(#frames == 1 and frames[1].events.BAG_UPDATE_DELAYED, "managed preparation events missing")
    local priorScans = scans
    Event("BAG_UPDATE_DELAYED")
    Event("BAG_UPDATE_DELAYED")
    Check(#timers == 1, "bag events were not coalesced")
    combatEdge = true
    Event("PLAYER_REGEN_DISABLED")
    combat, combatEdge = true, false
    local registrations = 0
    for event in pairs(frames[1].events) do
        registrations = registrations + 1
        Check(event == "PLAYER_REGEN_ENABLED", "combat retained an ordinary event")
    end
    Check(registrations == 1, "combat did not retain exactly the resume event")
    local combatCallbacks, combatEdits = callbacks, edits
    Tick()
    for burst = 1, 10 do
        for _, event in ipairs({ "BAG_UPDATE_DELAYED", "BAG_UPDATE_COOLDOWN", "SPELLS_CHANGED",
            "PLAYER_LEVEL_UP", "SKILL_LINES_CHANGED", "PLAYER_EQUIPMENT_CHANGED", "ITEM_DATA_LOAD_RESULT" }) do Event(event) end
        Tick()
    end
    Check(scans == priorScans and not module.pending, "combat did inventory work or retained a timer")
    Check(callbacks == combatCallbacks and edits == combatEdits, "combat dispatched work or changed a macro")
    combat = false
    Event("PLAYER_REGEN_ENABLED")
    Tick()
    Check(scans > priorScans, "combat exit did not resume preparation")
    local savedHealth = Store.Get(healthID)
    savedHealth.consumable.priorities = { "potion" }
    assert(Store.Save(savedHealth, healthID))
    Tick()
    local _, _, healthBody = GetMacroInfo(123)
    Check(healthBody:find("item:5512", 1, true), "saving a draft republished its unconfirmed recipe")
    module.active = false
    module:Disable()
    Check(next(frames[1].events) == nil and not module.pending, "disable retained work")
    Check(GetMacroInfo(123) == "Recovery", "disabling removed native macro")

    local drink = { version = 1, mode = "consumable", consumable = { kind = "drink", preferConjured = true,
        includeFood = true, items = {} } }
    body = assert(Store.Preview(drink))
    Check(body:find("item:113509", 1, true), "conjured food preference failed")
    Check(not body:find("item:159", 1, true), "combined recovery emitted a second drink")
    drink.consumable.kind, drink.consumable.items = "bandage", {}
    body = assert(Store.Preview(drink))
    Check(body:find("/use [nochanneling] item:1251", 1, true), "bandage channel guard missing")
    drink.consumable.kind, drink.consumable.stat = "flask", "mastery"
    body = assert(Store.Preview(drink))
    Check(body:find("item:241322", 1, true) and not body:find("item:241325", 1, true), "flask stat ignored")
    drink.consumable.kind, drink.consumable.items = "food", { "159" }
    body = assert(Store.Preview(drink))
    Check(body:find("item:159", 1, true), "explicit item selection failed")
    items[194684] = { name = "Azure Leywine", level = 50, subclass = 5 }
    items[999999] = { name = "Unclassified solid food", level = 100, subclass = 5 }
    bag = { 194684, 999999 }
    drink.consumable.kind, drink.consumable.items, drink.consumable.includeFood = "drink", {}, false
    if flavor == "Mainline" then
        body = assert(Store.Preview(drink))
        Check(body:find("item:194684", 1, true), "current drink was not recognized with food disabled")
    end
    bag = { 999999 }
    Check(Store.Preview(drink) == nil, "unknown solid food was used as a drink")
    drink.consumable.includeFood = true
    Check(Store.Preview(drink) == nil, "unknown food was automatically accepted")
    local buffFoodID = flavor == "Forever" and 6290 or 888888
    items[buffFoodID] = { name = "Verified buff food", level = 80, subclass = 5 }
    bag = { buffFoodID }
    drink.consumable.kind = "food"
    body = assert(Store.Preview(drink))
    Check(body:find("item:" .. buffFoodID, 1, true), "verified client buff food was not classified as food")
    items[1113] = { name = "Conjured bread", level = 1, subclass = 5 }
    bag = { 1113, buffFoodID }
    body = assert(Store.Preview(drink))
    Check(body:find("item:" .. buffFoodID, 1, true) and not body:find("item:1113", 1, true),
        "buff food chose ordinary conjured bread")
    bag = { 1113 }
    Check(Store.Preview(drink) == nil, "ordinary bread was accepted as automatic buff food")
    bag = { 1113, 159, buffFoodID }
    drink.consumable.kind = "drink"
    body = assert(Store.Preview(drink))
    Check(body:find("item:1113", 1, true) and not body:find("item:" .. buffFoodID, 1, true),
        "recovery consumed stat food instead of ordinary food")
    return now
end

Run("Mainline")
Run("Forever")
print("suite_macros_runtime_contract: " .. checks .. " checks passed")

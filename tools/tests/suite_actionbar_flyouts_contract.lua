-- Action bar flyouts (MSUF_Suite_ActionBars/Flyouts.lua, FlyoutFrames.lua,
-- FlyoutAPI.lua; MSUF_Suite/Core/Catalog/ActionBarFlyouts.lua) against a
-- small client model, once for Retail and once for WoW Forever:
--  * presets per WoW version, data cleaning and UTF-8 safe names;
--  * nothing is created or listened to without a flyout;
--  * an account macro "/click MSUFSuiteFlyouts <id>" per flyout, placed on
--    the first empty button, and the slot and macro maps the opener reads;
--  * the opener's restricted handler, run as written: the button under the
--    mouse wins, else the first visible holder; toggle, size, the four
--    directions, the combat wait, closing after use;
--  * in combat nothing listens but the combat end: zero handler calls;
--  * "only what I carry", the bag food group and cursor drops.
local root = assert(arg[1], "repository root required")

local failures = {}
local function Check(ok, message)
    if not ok then failures[#failures + 1] = message end
end

------------------------------------------------------------------ client model
local World

local Frame = {}
Frame.__index = Frame
local function Sink()
    return setmetatable({}, { __index = function(t, key)
        local method = function(self, ...) rawset(self, "last" .. key, { ... }) end
        rawset(t, key, method)
        return method
    end })
end

local function NewFrame(kind, name, parent, template)
    local frame = setmetatable({ kind = kind, name = name, parent = parent, template = template or "", attrs = {},
        shown = true, points = {}, scripts = {}, hooks = {}, refs = {}, width = 0, height = 0, events = {},
        wraps = {}, mouse = false }, Frame)
    if name then _G[name] = frame end
    World.frames[#World.frames + 1] = frame
    return frame
end
function Frame:SetSize(w, h) self.width, self.height = w, h end
function Frame:SetWidth(w) self.width = w end
function Frame:SetHeight(h) self.height = h end
function Frame:GetWidth() return self.width end
function Frame:GetHeight() return self.height end
function Frame:SetPoint(...) self.points[#self.points + 1] = { ... } end
function Frame:ClearAllPoints() self.points = {} end
function Frame:GetPoint(i) local p = self.points[i or 1] if p then return unpack(p) end end
function Frame:SetAllPoints() end
local function Run(frame, script, ...)
    for _, hook in ipairs(frame.hooks[script] or {}) do hook(frame, ...) end
end
function Frame:Show()
    if self.shown then return end
    self.shown = true
    Run(self, "OnShow")
end
function Frame:Hide()
    if not self.shown then return end
    self.shown = false
    self.autoHide = nil
    Run(self, "OnHide")
end
function Frame:IsShown() return self.shown end
function Frame:IsVisible() return self.shown and (not self.parent or self.parent == UIParent or self.parent:IsVisible()) end
function Frame:SetAttribute(name, value)
    assert(not World.lockdown or self.restricted, "protected attribute write in combat: " .. tostring(name))
    self.attrs[name] = value
end
function Frame:GetAttribute(name) return self.attrs[name] end
function Frame:GetFrameRef(name) return self.refs[name] end
function Frame:HookScript(script, fn)
    self.hooks[script] = self.hooks[script] or {}
    table.insert(self.hooks[script], fn)
end
function Frame:SetScript(script, fn) self.scripts[script] = fn end
function Frame:GetScript(script) return self.scripts[script] end
function Frame:RegisterEvent(event) self.events[event] = true end
function Frame:UnregisterEvent(event) self.events[event] = nil end
function Frame:UnregisterAllEvents() self.events = {} end
function Frame:IsMouseOver() return self.mouse end
-- Restricted handles have no IsMouseOver; the secure snippet uses IsUnderMouse.
Frame.IsUnderMouse = Frame.IsMouseOver
function Frame:GetName() return self.name end
function Frame:GetParent() return self.parent end
function Frame:RegisterAutoHide(delay) self.autoHide = delay end
function Frame:UnregisterAutoHide() self.autoHide = nil end
function Frame:AddToAutoHide(other) self.autoHideWith = other end
for _, name in ipairs({ "RegisterForClicks", "EnableMouse", "SetFrameStrata", "SetClampedToScreen", "SetHighlightTexture",
    "SetPushedTexture", "SetSwipeColor", "SetHideCountdownNumbers", "SetCooldown", "Clear", "SetCooldownFromDurationObject",
    "SetOwner", "SetItemByID", "SetSpellByID", "SetToyByItemID", "SetText" }) do
    Frame[name] = function(self, ...) self["last" .. name] = { ... } end
end
function Frame:CreateTexture() return Sink() end
function Frame:CreateFontString() return Sink() end

local function Fire(event, ...)
    local calls = 0
    for _, frame in ipairs(World.frames) do
        if frame.events[event] and frame.scripts.OnEvent then
            calls = calls + 1
            frame.scripts.OnEvent(frame, event, ...)
        end
    end
    World.handlerCalls = World.handlerCalls + calls
    return calls
end

local function RunTimers()
    while #World.timers > 0 do table.remove(World.timers, 1)() end
end

-- The restricted environment the snippets need, over the plain frames.
local function Snippet(body, env)
    local chunk = assert(loadstring(body))
    env.floor, env.tonumber = math.floor, tonumber
    env.SecureCmdOptionParse = function(text)
        assert(text == "[combat] 1; 0", "unexpected option text")
        return World.combat and "1" or "0"
    end
    setfenv(chunk, env)
    World.restricted = true
    local a, b = chunk()
    World.restricted = false
    return a, b
end

local function Click(name, button)
    local frame = _G[name]
    assert(frame, "no frame " .. name)
    for _, f in ipairs(World.frames) do f.restricted = true end
    Snippet(frame.attrs._onclick, { self = frame, button = button, down = false })
    for _, f in ipairs(World.frames) do f.restricted = nil end
end

local function UseEntry(entry)
    local wrap = entry.wraps.OnClick
    for _, f in ipairs(World.frames) do f.restricted = true end
    local _, message = Snippet(wrap.pre, { self = entry, control = wrap.header })
    if message ~= nil then Snippet(wrap.post, { self = entry, control = wrap.header }) end
    for _, f in ipairs(World.frames) do f.restricted = nil end
end

local function NewWorld(forever)
    for _, frame in ipairs(World and World.frames or {}) do
        if frame.name then _G[frame.name] = nil end
    end
    World = { frames = {}, timers = {}, events = {}, handlerCalls = 0, combat = false, lockdown = false,
        bags = { [0] = {}, [1] = {}, [2] = {}, [3] = {}, [4] = {} }, items = {}, spells = {}, toys = {}, mounts = {},
        macros = {}, charMacros = {}, actions = {}, cursor = nil, triggered = {} }
    _G.MSUFSuiteFlyoutsDB = nil
    UIParent = NewFrame("Frame", "UIParent")
    GameTooltip = NewFrame("GameTooltip", "GameTooltip")
    function GameTooltip:IsOwned() return false end
    STANDARD_TEXT_FONT, NUM_BAG_SLOTS, NUM_TOTAL_EQUIPPED_BAG_SLOTS = "font", 4, nil
    Constants = { MacroConsts = { MAX_ACCOUNT_MACROS = 120, MAX_CHARACTER_MACROS = 30 } }
    function wipe(t) for key in pairs(t) do t[key] = nil end return t end
    C_Timer = { After = function(_, fn) World.timers[#World.timers + 1] = fn end }
    EventRegistry = { TriggerEvent = function(_, event) World.triggered[event] = (World.triggered[event] or 0) + 1 end }
    function SecureHandlerSetFrameRef(frame, name, ref) frame.refs[name] = ref end
    function SecureHandlerWrapScript(frame, script, header, pre, post)
        frame.wraps[script] = { header = header, pre = pre, post = post }
    end
    return forever
end

------------------------------------------------------------------ item, spell, macro and action model
local function InstallClient()
    local W = World
    local function Count(id)
        local n = 0
        for bag = 0, 4 do for _, stack in pairs(W.bags[bag]) do if stack.id == id then n = n + stack.count end end end
        return n
    end
    C_Item = {
        GetItemCount = function(id) return Count(id) end,
        GetItemIconByID = function(id) return 1000000 + id end,
        GetItemNameByID = function(id) return "Item" .. id end,
        GetItemInfoInstant = function(id)
            local info = W.items[id]
            if not info then return nil end
            return id, "", "", "", 1000000 + id, info.class or 0, info.sub or 5
        end,
        GetItemInfo = function(id)
            local info = W.items[id] or {}
            return "Item" .. id, "link", 1, info.level or 1, info.minimum or 1
        end,
        IsUsableItem = function(id) return (W.items[id] or {}).usable ~= false end,
        GetItemCooldown = function() return 0, 0, 1 end,
        RequestLoadItemDataByID = function() end,
    }
    C_Container = {
        GetContainerNumSlots = function(bag) return W.bags[bag] and 20 or 0 end,
        GetContainerItemID = function(bag, slot) local s = W.bags[bag] and W.bags[bag][slot] return s and s.id end,
    }
    C_Spell = {
        GetSpellTexture = function(id) return 2000000 + id end,
        GetSpellName = function(id) return W.spells[id] and ("Spell" .. id) or nil end,
        GetSpellCooldownDuration = function() return nil end,
    }
    function IsPlayerSpell(id) return W.spells[id] == true end
    function PlayerHasToy(id) return W.toys[id] == true end
    C_MountJournal = { GetMountInfoByID = function(id)
        local m = W.mounts[id]
        if not m then return nil end
        return "Mount" .. id, m.spell, 3000000 + id, false, true, 0, false, false, 0, false, m.collected
    end }
    local function All()
        local list = {}
        for i, m in ipairs(W.macros) do list[i] = m end
        return list
    end
    local function IndexOf(macro)
        for i, m in ipairs(W.macros) do if m == macro then return i end end
        for i, m in ipairs(W.charMacros) do if m == macro then return 120 + i end end
    end
    local function ByIndex(index)
        if index > 120 then return W.charMacros[index - 120] end
        return W.macros[index]
    end
    local function Sort() table.sort(W.macros, function(a, b) return a.name < b.name end) end
    function GetNumMacros() return #W.macros, #W.charMacros end
    function GetMacroInfo(index)
        local m = ByIndex(index)
        if m then return m.name, m.icon, m.body end
    end
    function GetMacroIndexByName(name)
        for _, m in ipairs(All()) do if m.name == name then return IndexOf(m) end end
        return 0
    end
    function CreateMacro(name, icon, body, perCharacter)
        assert(not W.lockdown, "CreateMacro in combat")
        assert(not perCharacter, "flyout macros are account-wide")
        local macro = { name = name, icon = icon, body = body }
        table.insert(W.macros, macro)
        Sort()
        W.created = (W.created or 0) + 1
        return IndexOf(macro)
    end
    function EditMacro(index, name, icon, body)
        local m = ByIndex(index)
        m.name, m.icon, m.body = name or m.name, icon or m.icon, body or m.body
        Sort()
        return IndexOf(m)
    end
    function DeleteMacro(index)
        local m = ByIndex(index)
        for slot, action in pairs(W.actions) do if action.macro == m then W.actions[slot] = nil end end
        for i, candidate in ipairs(W.macros) do if candidate == m then table.remove(W.macros, i) end end
    end
    function GetActionInfo(slot)
        local action = W.actions[slot]
        if not action then return nil end
        if action.macro then return "macro", IndexOf(action.macro), "" end
        return action.kind, action.id, ""
    end
    function GetActionText(slot)
        local action = W.actions[slot]
        return action and action.macro and action.macro.name or nil
    end
    function HasAction(slot) return W.actions[slot] ~= nil end
    function PickupMacro(index) W.cursor = { kind = "macro", macro = ByIndex(index) } end
    function PlaceAction(slot)
        assert(not W.lockdown, "PlaceAction in combat")
        W.actions[slot], W.cursor = W.cursor, nil
    end
    function ClearCursor() W.cursor = nil end
    function GetCursorInfo()
        local c = W.cursor
        if not c then return nil end
        if c.kind == "macro" then return "macro", IndexOf(c.macro) end
        if c.kind == "spell" then return "spell", 1, "spell", c.id end
        return c.kind, c.id
    end
end

------------------------------------------------------------------ the Suite around the module
local function Load(forever)
    NewWorld(forever)
    InstallClient()
    local Suite = { Client = { isForever = forever, SupportsEvent = function() return true end } }
    function Suite.IsCombatLocked() return World.lockdown end
    function Suite.InCombat() return World.combat end
    function Suite.ActionBarVisibilityMode(config, index) return config["bar" .. index .. "Visibility"] or 1 end
    assert(loadfile(root .. "/MSUF_Suite/Core/Catalog/ActionBarFlyouts.lua"))("MSUF_Suite", Suite)
    local S = {}
    S.Public = function() return true end
    S.Finite = function(v) return type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge end
    S.PublicText = function(v) return type(v) == "string" and v ~= "" and v or nil end
    S.Text = function(text) return text end
    S.CreateFrame = function(kind, name, parent, template) return NewFrame(kind, name, parent, template) end
    S.CreateTexture = function() return Sink() end
    S.CreateFontString = function() return Sink() end
    S.PlaceEdges, S.SetStyledFont = function() end, function() end
    S.Dispatch = function(fn, ...) return fn(...) end
    local AB = {
        ENUM = { TOOLTIP = { ALWAYS = 1, OUT_OF_COMBAT = 2, NEVER = 3 }, BAR = { INDEPENDENT = 10 },
            VISIBILITY = { NEVER = 6 } },
        Diagnostics = {}, records = {}, bars = {}, owned = {}, M = { config = { cooldownNumbers = true } }, styleGen = 1,
        BUTTONS = 12,
    }
    function AB.BuildStyle()
        AB.style = { sr = 0, sg = 0, sb = 0, slotAlpha = .5, br = 1, bg = 1, bb = 1, ir = 1, ig = 1, ib = 1, cr = 1, cg = 1,
            cb = 1, wr = 0, wg = 0, wb = 0, swipeAlpha = .8, border = 1, zoom = .06, texts = {} }
        return AB.style
    end
    function AB.Available() return true end
    local first = { 1, 61, 49, 25, 37, 145, 157, 169, 13 }
    for index = 1, 10 do
        local bar = { index = index, buttons = {}, count = 12, key = { Tooltip = "bar" .. index .. "Tooltip" }, owned = true }
        bar.header = NewFrame("Frame", "Bar" .. index, UIParent)
        AB.bars[index] = bar
        for i = 1, 12 do
            local button = NewFrame("CheckButton", "Bar" .. index .. "Button" .. i, bar.header)
            button.width = 40
            local rec = { button = button, bar = bar, index = i, virtual = index == 10 }
            if first[index] then
                rec.slot, rec.base = first[index] + i - 1, first[index] + i - 1
                button.attrs.action = rec.slot
            end
            button.attrs.flyoutDirection = index == 4 and "LEFT" or "UP"
            bar.buttons[i], AB.records[button] = rec, rec
            AB.owned[#AB.owned + 1] = rec
        end
    end
    local P = { NS = Suite, Suite = S, ActionBars = AB }
    for _, file in ipairs({ "FlyoutFrames", "Flyouts", "FlyoutAPI" }) do
        assert(loadfile(root .. "/MSUF_Suite_ActionBars/" .. file .. ".lua"))("MSUF_Suite_ActionBars", P)
    end
    return Suite, S, AB
end

local function EnterCombat()
    World.combat = true
    Fire("PLAYER_REGEN_DISABLED")
    World.lockdown = true
end
local function LeaveCombat()
    World.lockdown = false
    World.combat = false
    Fire("PLAYER_REGEN_ENABLED")
end
local function Stack(bag, slot, id, count) World.bags[bag][slot] = { id = id, count = count } end

------------------------------------------------------------------ data
local function DataCases(Suite, forever)
    local Data = Suite.ActionBarFlyouts
    local keys = {}
    for _, preset in ipairs(Data.Presets()) do keys[#keys + 1] = preset.key end
    if forever then
        Check(table.concat(keys, ",") == "vendorFood,vendorDrinks,cooking,bagFood", "Forever presets: " .. table.concat(keys, ","))
        local cooking = Data.Preset("cooking")
        Check(#cooking.entries == #Suite.ForeverCookedFood and #cooking.entries == 100, "Cooking preset lost entries")
        Check(Data.Preset("vendorFood").entries[1].id == 8932, "vendor food is not best first")
    else
        Check(table.concat(keys, ",") == "bagFood", "Retail presets: " .. table.concat(keys, ","))
    end
    for _, preset in ipairs(Data.Presets()) do
        Check(Data.CleanName(preset.flyoutName) == preset.flyoutName, preset.key .. ": preset name is not a valid macro name")
    end
    Check(Data.CleanName("  Essen\nund Trinken mit Käse  ") == "Essen und Trinke", "names are not cut to 16 characters")
    Check(Data.CleanName("äöüäöüäöüäöüäöüäöü") == "äöüäöüäöüäöüäöüä", "a cut name broke a UTF-8 character")
    Check(Data.CleanName("   ") == nil and Data.CleanName(5) == nil, "empty names were accepted")
    local store = Data.CleanStore({ nextID = 2, list = {
        { id = 1, name = "A", entries = { { kind = "item", id = 5 }, { kind = "item", id = 5 }, { kind = "nope", id = 1 },
            { kind = "bag", id = "food" }, { kind = "bag", id = "gold" }, { kind = "macro", id = "" } } },
        { id = 1, name = "Duplicate" }, { id = 7, name = "" }, { id = 9, name = "B", owned = false } } })
    Check(#store.list == 2 and store.nextID == 10, "store cleaning kept invalid flyouts or lost the next id")
    Check(#store.list[1].entries == 2 and store.list[1].owned == true and store.list[2].owned == false,
        "entry cleaning kept invalid or duplicate entries")
end

------------------------------------------------------------------ runtime
local function Listening()
    local events = {}
    for _, frame in ipairs(World.frames) do
        for event in pairs(frame.events) do events[#events + 1] = event end
    end
    table.sort(events)
    return events
end

local function NoFlyout(AB, client, other)
    AB.Flyouts.Start()
    local saved = rawget(_G, "MSUFSuiteFlyoutsDB")
    Check(type(saved) == "table" and type(saved[client]) == "table", "the saved table was not opened")
    Check(saved and saved[client] and #saved[client].list == 0, "a fresh account has flyouts")
    Check(saved and saved[other] == nil, "the other WoW version's list was touched")
    Check(rawget(_G, AB.FlyoutFrames.OPENER) == nil, "the opener exists without a flyout")
    Check(#Listening() == 0, "something listens without a flyout: " .. table.concat(Listening(), ","))
end

-- A food flyout: only carried items, best first; placed on bar 2's first
-- empty button; opens there, above the button, at its size.
local function FoodFlyout(S, AB, forever)
    local API = S.ActionBarFlyouts
    Stack(0, 1, 4540, 5)
    Stack(1, 3, 8950, 2)
    Stack(2, 1, 6948, 1)
    World.items[4540], World.items[8950] = { minimum = 1, level = 5 }, { minimum = 45, level = 55 }
    World.items[6948] = { class = 15, sub = 0 }
    local key = forever and "vendorFood" or "bagFood"
    local id = API.AddPreset(key, "Food")
    Check(id == 1, "the preset did not create flyout 1")
    local box = AB.Diagnostics.Flyouts.Box(1)
    Check(box and box.attrs.count == 2, "the food flyout does not show the two carried foods")
    local first, second = box.refs.e1, box.refs.e2
    Check(first and first.attrs.type == "item" and first.attrs.item == "item:8950", "the best food is not first")
    Check(second and second.attrs.item == "item:4540", "the second food is wrong")
    Check(#Listening() > 0, "nothing listens with a flyout")
    World.actions[61] = { kind = "spell", id = 1 }
    local ok, number = API.Place(1, 2)
    Check(ok == true and number == 2, "the flyout did not go onto bar 2's first empty button")
    local macro = World.actions[62] and World.actions[62].macro
    Check(macro and macro.body == "/click MSUFSuiteFlyouts 1" and macro.name == "Food", "the macro body or name is wrong")
    Check(macro and macro.icon == 1000000 + 4540, "the macro icon is not the preset's")
    Check(World.cursor == nil, "placing left something on the cursor")
    local opener = rawget(_G, "MSUFSuiteFlyouts")
    Check(opener and opener.attrs.s62 == 1 and opener.attrs.enabled == true, "the opener does not know slot 62")
    return id, box
end

local function OpenCases(AB, box)
    local opener = rawget(_G, "MSUFSuiteFlyouts")
    local holder = AB.bars[2].buttons[2].button
    Click("MSUFSuiteFlyouts", "1")
    Check(box.shown and opener.attrs.openid == 1, "the flyout did not open")
    local point = box.points[1]
    Check(point and point[1] == "BOTTOMLEFT" and point[2] == holder and point[3] == "TOPLEFT", "not opened above its button")
    Check(box.refs.e1.width == 40 and box.width == 46 and box.height == 90, "entries do not take the button size")
    Check(box.refs.e2.points[1][5] == 47, "the second entry is not stacked upward")
    Check(box.autoHide == nil, "out of combat the flyout waits for the mouse")
    Click("MSUFSuiteFlyouts", "1")
    Check(not box.shown, "a second press did not close the flyout")
    -- A second holder on bar 4 (opens to the left): the one under the mouse wins.
    World.actions[25] = World.actions[62]
    AB.Flyouts.MapSlot(25)
    local left = AB.bars[4].buttons[1].button
    left.mouse = true
    Click("MSUFSuiteFlyouts", "1")
    point = box.points[1]
    Check(point and point[2] == left and point[1] == "TOPRIGHT", "the button under the mouse did not anchor the flyout")
    Check(box.width == 90 and box.height == 46, "a left flyout is not one row")
    left.mouse = false
    UseEntry(box.refs.e1)
    Check(not box.shown, "using an entry did not close the flyout")
    -- Hidden holder: the next visible one anchors.
    AB.bars[2].header.shown = false
    Click("MSUFSuiteFlyouts", "1")
    Check(box.points[1][2] == left, "a hidden holder anchored the flyout")
    Click("MSUFSuiteFlyouts", "1")
    AB.bars[2].header.shown = true
    Click("MSUFSuiteFlyouts", "99")
    Check(opener.attrs.openid == nil, "an unknown flyout opened")
end

-- Combat: one handler call at each edge, none in between; the flyout opens
-- with the combat wait; a bag change catches up after combat.
local function CombatCases(AB, box)
    World.handlerCalls = 0
    Click("MSUFSuiteFlyouts", "1")
    EnterCombat()
    Check(not box.shown, "combat start did not close the open flyout")
    local events = Listening()
    Check(table.concat(events, ",") == "PLAYER_REGEN_DISABLED,PLAYER_REGEN_ENABLED",
        "events in combat: " .. table.concat(events, ","))
    local before = World.handlerCalls
    Stack(3, 1, 8950, 3)
    for _ = 1, 50 do
        Fire("BAG_UPDATE_DELAYED")
        Fire("ACTIONBAR_SLOT_CHANGED", 62)
        Fire("UPDATE_MACROS")
        Fire("SPELLS_CHANGED")
    end
    RunTimers()
    Check(World.handlerCalls == before, "flyout code ran in combat: " .. (World.handlerCalls - before) .. " calls")
    Click("MSUFSuiteFlyouts", "1")
    Check(box.shown and box.autoHide == 4 and box.autoHideWith == AB.bars[2].buttons[2].button,
        "in combat the flyout does not wait for the mouse next to its button")
    Click("MSUFSuiteFlyouts", "1")
    LeaveCombat()
    RunTimers()
    Check(#Listening() > 2, "the quiet events did not come back after combat")
end

local function EditCases(S, AB, id)
    local API = S.ActionBarFlyouts
    Check(API.SetOwned(id, false), "show-all could not be set")
    local box = AB.Diagnostics.Flyouts.Box(id)
    local total = World.client == "forever" and math.min(#API.Entries(id), 24) or 2
    Check(box.attrs.count == total, "show-all does not list every entry")
    API.SetOwned(id, true)
    World.cursor = { kind = "spell", id = 8690 }
    World.spells[8690] = true
    Check(API.AddCursor(id) and World.cursor == nil, "a dropped spell was refused")
    local rows = API.Entries(id)
    Check(rows[#rows].kind == "spell" and rows[#rows].id == 8690 and rows[#rows].active, "the spell is not the last entry")
    World.cursor = { kind = "macro", macro = World.actions[62].macro }
    local ok, problem = API.AddCursor(id)
    Check(not ok and problem == "A flyout cannot hold another flyout.", "a flyout macro went into a flyout")
    World.cursor = nil
    Check(API.AddText(id, "item:6948") and not API.AddText(id, "6948"), "item text or duplicate handling is wrong")
    Check(not API.AddText(id, "spell:1"), "an unknown spell ID was accepted")
    Check(API.MoveEntry(id, #API.Entries(id), -1), "moving an entry failed")
    Check(API.Rename(id, "Snacks") and World.actions[62].macro.name == "Snacks", "renaming did not rename the macro")
    EnterCombat()
    ok, problem = API.Rename(id, "Late")
    Check(not ok and problem == "Flyouts can be edited out of combat.", "an edit went through in combat")
    LeaveCombat()
    RunTimers()
end

local function DeleteCases(S, AB, id)
    local API = S.ActionBarFlyouts
    local second = API.Create("Hearth")
    Check(second == 2 and AB.Diagnostics.Flyouts.Box(2).attrs.count == 0, "an empty flyout was not created")
    Check(API.Delete(id), "delete failed")
    Check(World.actions[62] == nil and World.actions[25] == nil, "deleting kept the macro on the bars")
    Check(#World.macros == 0, "deleting kept the macro")
    local opener = rawget(_G, "MSUFSuiteFlyouts")
    Check(opener.attrs.s62 == nil and opener.attrs.s25 == nil, "deleting kept the slot owners")
    Check(AB.Diagnostics.Flyouts.Box(id).attrs.count == 0, "a deleted flyout can still open")
    AB.Flyouts.Stop()
    Check(opener.attrs.enabled == false and #Listening() == 0, "disable left the opener on or listeners")
end

for _, forever in ipairs({ false, true }) do
    local client = forever and "forever" or "retail"
    local Suite, S, AB = Load(forever)
    World.client = client
    DataCases(Suite, forever)
    NoFlyout(AB, client, forever and "retail" or "forever")
    local id, box = FoodFlyout(S, AB, forever)
    if box then
        OpenCases(AB, box)
        CombatCases(AB, box)
        EditCases(S, AB, id)
        DeleteCases(S, AB, id)
    end
end

if #failures > 0 then
    io.stderr:write(table.concat(failures, "\n") .. "\n")
    os.exit(1)
end
print("action bar flyouts: ok")

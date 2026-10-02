local root = assert(arg[1])
local function eq(a, b, label) assert(a == b, (label or "value") .. ": " .. tostring(a) .. " ~= " .. tostring(b)) end
-- What a DataText shows without a value: U+2014 EM DASH as UTF-8 bytes.
local DASH = "\226\128\148"
local NS = { Client = { modernEquipment = true }, IsCombatLocked = function() return false end }
-- The catalog's choice values (MSUF_Suite/Core/Catalog/DataTexts.lua).
local _, catalog = dofile(root .. "/tools/tests/suite_test_support.lua").CatalogDefaults(root, "dataTexts")
NS.DataTextCrestMode = catalog.DataTextCrestMode
local config = { audioChannel = 1, itemLevelEquipped = true, itemLevelDecimals = 1, hearthItems = "6948,42",
    randomHearth = true }
local S = { Text = function(v) return v end, Public = function(v) return v ~= "secret" end,
    Finite = function(v) return type(v) == "number" and v == v end, MoneyText = tostring,
    RGB = function() return 1, 1, 1 end, Config = function() return config end }
NS.Suite = S
-- The addon's own Bootstrap.lua fills the shared private table.
local function Load(file, package)
    MSUFSuite = NS
    assert(loadfile(root .. "/MSUF_Suite_DataTexts/" .. file .. ".lua"))("MSUF_Suite_DataTexts", package)
end
local P = {}
Load("Bootstrap", P)
eq(P.NO_VALUE, DASH, "placeholder bytes")
local objects = { One = { label = "One", text = "first", icon = 12 }, Two = { label = "Two", text = "second", icon = 13 } }
local lib = { callbacks = {} }
function lib:GetDataObjectByName(name) return objects[name] end
function lib:DataObjectIterator() return pairs(objects) end
function lib.RegisterCallback(target, event, callback) lib.callbacks[event] = { target = target, callback = callback } end
function lib.UnregisterAllCallbacks() lib.callbacks = {} end
LibStub = { GetLibrary = function() return lib end }
local volume = .5
C_CVar = { GetCVar = function() return tostring(volume) end, SetCVar = function(_, value) volume = value end }
local currencyQuantity = 9
C_CurrencyInfo = { GetCurrencyInfo = function(id)
    return id == 10 and { name = "Currency", quantity = currencyQuantity, discovered = true, iconFileID = 44 } or nil
end }
GetAverageItemLevel = function() return 600, 590 end
GetMaxPlayerLevel = function() return 80 end
local level = 70
UnitLevel = function() return level end
UnitXP = function() return 50 end
UnitXPMax = function() return 100 end
C_Reputation = { GetWatchedFactionData = function()
    return { name = "Faction", currentStanding = 50, currentReactionThreshold = 0, nextReactionThreshold = 200 }
end }
PlayerHasToy = function(id) return id == 42 end
local itemQuantity = 1
C_Item = { GetItemCount = function(id) return id == 6948 and itemQuantity or 0 end,
    GetItemInfo = function(id) return tostring(id), nil, nil, nil, nil, nil, nil, nil, nil, 123 end }
-- Only the deprecation fallbacks would define these; the source must not use them.
GetSpecialization, GetSpecializationInfo = nil, nil
local specIndex = 2
C_SpecializationInfo = {
    GetSpecialization = function() return specIndex end,
    GetSpecializationInfo = function(index) if index == 2 then return 63, "Fire", "", 135810 end end,
}
local registered = {}
local M = { active = true, activeSources = {}, config = config, updates = {}, values = {}, due = {}, bars = {} }
function M:UpdateSource(key) self.updates[#self.updates + 1] = key end
M.context = { Event = function(_, event) registered[event] = (registered[event] or 0) + 1 end,
    RemoveEvent = function(_, event) registered[event] = nil end }
Load("Sources", P)
Load("Actions", P)
local X, A = P.DataTextSources, P.DataTextActions
function M:Rebind()
    X.Rebind(self)
    self.wanted = {}
    X.WantedEvents(self.activeSources, self.wanted)
    self.rebinds = (self.rebinds or 0) + 1
end
local function Button()
    local button = { written = {} }
    function button:SetAttribute(key, value) self.written[#self.written + 1] = key end
    return button
end
local a, b = Button(), Button()
local c = { bar1Slot1Broker = "One", bar1Slot2Broker = "Two", bar1Slot3Currency = 10 }
local one = X.Bind(a, c, 1, 1, "broker")
local two = X.Bind(b, c, 1, 2, "broker")
M.activeSources[one], M.activeSources[two] = true, true
X.Rebind(M)
local _, first = X.Format(one)
eq(first, "first", "first plugin")
eq(X.bindings[one].icons[1], 12, "plugin icon")
local _, second = X.Format(two)
eq(second, "second", "second plugin")
objects.One.text = "changed"
lib.callbacks.LibDataBroker_AttributeChanged.callback("LibDataBroker_AttributeChanged", "One", "text", "changed", objects.One)
eq(#M.updates, 1, "one callback updates exactly its plugin")
eq(M.updates[1], one, "callback argument order")
eq(select(2, X.Format(two)), "second", "other plugin stable")
local progress = X.Bind(Button(), c, 1, 4, "progress")
M.activeSources[progress] = true
local wanted = { PLAYER_XP_UPDATE = true }
X.WantedEvents(M.activeSources, wanted)
eq(wanted.PLAYER_XP_UPDATE, true, "shared xp/progress event merged")
eq(next(registered), nil, "source lane never overwrites Context event callback")
eq(select(2, X.Format(progress)), "50%", "leveling XP")
level = 80
eq(select(2, X.Format(progress)), "25%", "maxlevel switches to reputation")
local currency = X.Bind(Button(), c, 1, 3, "currency")
eq(select(2, X.Format(currency)), "9", "native discovered currency")
-- Specialization reads C_SpecializationInfo (the globals are deprecation shims).
local spec = X.Bind(Button(), c, 1, 5, "specialization")
local specLabel, specName = X.Format(spec)
eq(specLabel .. "/" .. specName, "Specialization/Fire", "specialization through C_SpecializationInfo")
eq(X.bindings[spec].icons[1], 135810, "specialization icon")
specIndex = 0
eq(select(2, X.Format(spec)), DASH, "no specialization shows the placeholder")
local crests = X.Bind(Button(), c, 2, 1, "crests")
M.activeSources[crests] = true
eq(select(2, X.Format(crests)), DASH, "season metadata is unavailable before observing an upgrade item")
M.config.crestMode = 2
M.config.crestCurrencyIDs = "10,10"
M.config.crestSeparator = " | "
X.Rebind(M)
eq(select(2, X.Format(crests)), "9 | 9", "persisted manual currencies work before any upgrade observation")
eq(X.seasonCosts, nil, "manual selection does not require upgrade metadata")
eq(X.bindings[crests].icons[1], 44, "manual selection shows native icon")
M.config.crestCurrencyIDs = "999,10"
eq(select(2, X.Format(crests)), "9", "missing manual currency is skipped safely")
M.config.crestCurrencyIDs = ""
eq(select(2, X.Format(crests)), DASH, "empty manual selection never falls back to observed costs")
M.config.crestMode = 1
M.config.crestSeparator = nil
C_ItemUpgrade = { GetItemUpgradeItemInfo = function() return { name = "Observed item", upgradeCostTypesForSeason = {
    { currencyID = 10, orderIndex = 2 }, { itemID = 6948, orderIndex = 1 } } } end }
X.Changed(M, "ITEM_UPGRADE_MASTER_SET_ITEM")
eq(X.CrestChoices()[1].order, 1, "native seasonal order")
eq(select(2, X.Format(crests)), "1 / 9", "native item and currency seasonal costs")
assert(M.wanted.BAG_UPDATE_DELAYED and M.rebinds == 1, "newly observed item stage immediately reconciles event subscription")
local beforeBag = #M.updates
itemQuantity = 3
X.Changed(M, "BAG_UPDATE_DELAYED")
eq(#M.updates, beforeBag + 1, "bag event refreshes only active crest binding")
eq(select(2, X.Format(crests)), "3 / 9", "bag event reads changed item quantity")
itemQuantity = 1
M.config.crestCurrencies = "2"
M:Rebind()
assert(not M.wanted.BAG_UPDATE_DELAYED, "currency-only observed selection releases bag event")
M.config.crestMode = 2
M.config.crestCurrencyIDs = "10"
M:Rebind()
assert(not M.wanted.BAG_UPDATE_DELAYED, "manual currency mode needs no bag subscription")
local beforeManual = #M.updates
X.Changed(M, "BAG_UPDATE_DELAYED")
eq(#M.updates, beforeManual, "manual mode ignores bag events")
M.config.crestMode = 1
M.config.crestCurrencies = ""
M:Rebind()
assert(M.wanted.BAG_UPDATE_DELAYED)
M.activeSources[crests] = nil
M:Rebind()
assert(not M.wanted.BAG_UPDATE_DELAYED, "crest source removal releases bag event")
M.activeSources[crests] = true
M:Rebind()
assert(M.wanted.BAG_UPDATE_DELAYED, "reactivation restores item subscriber")

M.config.crestCurrencies = "2,1"
M.config.crestSeparator = " + "
eq(select(2, X.Format(crests)), "9 + 1", "selected native stages and explicit order")
M.config.crestCurrencies = "2,2,1"
X.Rebind(M)
eq(select(2, X.Format(crests)), "9 + 9 + 1", "duplicates remain in configured order")
local pieces = X.bindings[crests].pieces
currencyQuantity = 14
X.Changed(M, "CURRENCY_DISPLAY_UPDATE")
eq(select(2, X.Format(crests)), "14 + 14 + 1", "currency event reads fresh amounts with cached selection")
eq(X.bindings[crests].pieces, pieces, "output buffer reused")
M.config.crestCurrencies = string.rep("2,", 200)
X.Rebind(M)
X.Format(crests)
eq(#X.bindings[crests].pieces, 128, "imported selection token count bounded")
M.config.crestCurrencies = 23
X.Rebind(M)
eq(select(2, X.Format(crests)), "1 + 14", "invalid nonstring input uses default order")
M.config.crestCurrencies = "2,1"
C_ItemUpgrade.GetItemUpgradeItemInfo = function() return { name = "New item", upgradeCostTypesForSeason = {
    { currencyID = 10, orderIndex = 1 }, { itemID = 6948, orderIndex = 2 } } } end
X.Changed(M, "ITEM_UPGRADE_MASTER_SET_ITEM")
eq(select(2, X.Format(crests)), "1 + 14", "new native metadata invalidates selected cost references")
M.config.crestCurrencies = ""
eq(select(2, X.Format(crests)), "14 + 1", "empty selection follows new native order")
M.config.crestCurrencies = "999"
eq(select(2, X.Format(crests)), DASH, "unrelated currencies must never masquerade as seasonal stages")
C_ItemUpgrade.GetItemUpgradeItemInfo = function() return nil end
X.ObserveSeasonCosts()
eq(#X.CrestChoices(), 2, "last observed list remains available only this login")
local audio = X.Bind(Button(), c, 1, 5, "audio")
A.Wheel(X.bindings[audio].button, 1)
eq(volume, .55, "chosen native volume")
-- Broker plugins own their interactions (LibDataBroker-1.1 fields are all
-- optional): OnTooltipShow fills the Suite's GameTooltip below the source
-- name and the place's text, an OnEnter plugin shows its own tooltip with no
-- Suite tooltip beside it, and clicks reach OnClick also in combat.
local calls = {}
GameTooltip = { lines = {} }
function GameTooltip:SetOwner(owner) self.owner, self.lines = owner, {} end
function GameTooltip:ClearLines() self.lines = {} end
function GameTooltip:AddLine(text) self.lines[#self.lines + 1] = text end
function GameTooltip:AddDoubleLine(left, right) self.lines[#self.lines + 1] = left .. " | " .. right end
function GameTooltip:Show() self.shown = true end
S.Dispatch = function(callback, ...) return callback(...) end
-- Platform.lua: Finish marks a completed foreign call; plugin callbacks use it.
local finished = 0
NS.Finish = function(callback, ...) finished = finished + 1; return true, callback(...) end
objects.Tip = { label = "Tip", text = "t", OnTooltipShow = function(tip) tip:AddLine("plugin line") end,
    OnClick = function(_, mouse) calls[#calls + 1] = "click:" .. mouse end }
objects.Hover = { label = "Hover", text = "h", OnEnter = function() calls[#calls + 1] = "enter" end,
    OnLeave = function() calls[#calls + 1] = "leave" end }
c.bar3Slot1Broker, c.bar3Slot2Broker = "Tip", "Hover"
local tipButton, hoverButton, plainButton = Button(), Button(), Button()
X.Bind(tipButton, c, 3, 1, "broker")
X.Bind(hoverButton, c, 3, 2, "broker")
X.Bind(plainButton, c, 3, 4, "broker")
tipButton.text = "Tip: t"
A.Tooltip(tipButton, "Broker plugin")
assert(GameTooltip.owner == tipButton and #GameTooltip.lines == 3 and GameTooltip.lines[1] == "Broker plugin"
    and GameTooltip.lines[2] == tipButton.text and GameTooltip.lines[3] == "plugin line",
    "an OnTooltipShow plugin tooltip lost its source heading or its own lines")
GameTooltip.owner, GameTooltip.lines = nil, {}
A.Tooltip(hoverButton, "Broker plugin")
assert(GameTooltip.owner == nil and calls[#calls] == "enter", "an OnEnter plugin got a second Suite tooltip")
assert(finished == 2, "broker plugin callbacks must run through Dispatch(Finish, ...)")
A.Leave(hoverButton)
eq(calls[#calls], "leave", "plugin OnLeave")
plainButton.text = "Plain: " .. DASH
A.Tooltip(plainButton, "Broker plugin")
assert(GameTooltip.owner == plainButton and GameTooltip.lines[1] == "Broker plugin" and GameTooltip.lines[2] == plainButton.text,
    "a plugin without handlers lost the Suite tooltip")
NS.IsCombatLocked = function() return true end
A.Click(tipButton, "RightButton")
eq(calls[#calls], "click:RightButton", "plugin clicks work in combat")
NS.IsCombatLocked = function() return false end
-- Professions loads Blizzard's load-on-demand book and toggles it once it exists.
local opened = {}
C_AddOns = { LoadAddOn = function(name) opened[#opened + 1] = name end }
ToggleFrame = function(frame) opened[#opened + 1] = frame end
local book = Button()
X.Bind(book, c, 3, 3, "professions")
A.Click(book, "LeftButton")
assert(#opened == 1 and opened[1] == "Blizzard_ProfessionsBook", "a missing professions book was toggled")
C_AddOns.LoadAddOn = function(name)
    opened[#opened + 1] = name
    ProfessionsBookFrame = ProfessionsBookFrame or {}
end
A.Click(book, "LeftButton")
assert(opened[2] == "Blizzard_ProfessionsBook" and opened[3] == ProfessionsBookFrame, "the professions book did not open")
-- Hearthstone places choose an owned item or toy; the secure button
-- (Actions.lua, suite_datatexts_security_contract) uses it.
local stone = Button()
local hearth = X.Bind(stone, c, 1, 6, "hearth")
M.activeSources[hearth] = true
X.PrepareHearths()
local chosen = X.bindings[hearth].hearth
assert(chosen and (chosen.id == 6948 and not chosen.toy or chosen.id == 42 and chosen.toy), "owned hearth choice")
NS.IsCombatLocked = function() return true end
X.PrepareHearths()
assert(X.bindings[hearth].hearth and #stone.written == 0, "a hearth choice never writes attributes on a place")
NS.IsCombatLocked = function() return false end
-- A loot that leaves the owned Hearthstones unchanged keeps the choice:
-- nothing is chosen or built again, and a random variant stays until it is
-- used (Actions.lua) or lost.
local rolls, random = 0, math.random
math.random = function(...) rolls = rolls + 1; return random(...) end
X.PrepareHearths()
chosen, rolls = X.bindings[hearth].hearth, 0
for _ = 1, 5 do X.Changed(M, "BAG_UPDATE_DELAYED"); X.Changed(M, "TOYS_UPDATED") end
assert(X.bindings[hearth].hearth == chosen and rolls == 0, "a loot without a Hearthstone change chose again")
itemQuantity = 0
X.Changed(M, "BAG_UPDATE_DELAYED")
local toy = X.bindings[hearth].hearth
assert(toy and toy.id == 42 and toy.toy and rolls == 0, "a lost Hearthstone stayed the place's choice")
itemQuantity = 1
X.Changed(M, "BAG_UPDATE_DELAYED")
assert(rolls == 1 and X.bindings[hearth].hearth ~= toy, "a regained Hearthstone was not offered again")
math.random = random
M.values, M.due = {}, {}
local recycled = Button()
local dynamicSources = {}
local hidden = X.Bind(Button(), c, 999, 1, "crests")
local hiddenButton = X.bindings[hidden].button
for cycle = 1, 200 do
    local old = X.Bind(recycled, c, 1000 + cycle, 1, "broker")
    M.activeSources = { [old] = true }
    M.values[old], M.due[old], dynamicSources[old] = {}, 1, true
    X.Rebind(M)
    local current = X.Bind(recycled, c, 1000 + cycle, 1, "crests")
    M.activeSources = { [current] = true }
    dynamicSources[current] = true
    X.Prune(M, { [current] = true, [hidden] = true }, dynamicSources)
    X.Rebind(M)
    local count = 0
    for _ in pairs(X.bindings) do count = count + 1 end
    eq(count, 2, "recycled/deleted/profile bindings remain bounded")
    eq(X.Has(old), false, "old slot kind removed")
    eq(M.values[old], nil, "old display removed")
    eq(M.due[old], nil, "old deadline removed")
    eq(dynamicSources[old], nil, "dynamic source registry removed")
    local updates = #M.updates
    if lib.callbacks.LibDataBroker_AttributeChanged then
        lib.callbacks.LibDataBroker_AttributeChanged.callback("LibDataBroker_AttributeChanged", "One")
    end
    eq(#M.updates, updates, "old broker never paints recycled button")
    eq(recycled.extra, X.bindings[current], "cleanup preserves current button owner")
    X.Changed(M, "CURRENCY_DISPLAY_UPDATE")
    eq(M.updates[#M.updates], current, "current source still updates")
end
eq(hiddenButton.extra, X.bindings[hidden], "configured hidden source retained")
M.activeSources = { [hidden] = true }
X.Rebind(M)
local before = #M.updates
X.Changed(M, "CURRENCY_DISPLAY_UPDATE")
eq(#M.updates, before + 1, "hidden source reactivates without rebind of slot")
eq(M.updates[#M.updates], hidden, "reactivated source updates its original binding")
X.Disable()
eq(next(lib.callbacks), nil, "broker subscription released")
-- Without LibDataBroker (no addon loaded LibStub) a broker place lists no
-- plugins, subscribes to nothing and shows its configured name.
LibStub = nil
local bare = {}
Load("Bootstrap", bare)
Load("Sources", bare)
Load("Actions", bare)
local Y = bare.DataTextSources
local lonely = Y.Bind(Button(), c, 1, 1, "broker")
local module = { active = true, activeSources = { [lonely] = true }, config = config, values = {}, due = {} }
Y.Rebind(module)
eq(Y.brokerRegistered, nil, "no library registers no callbacks")
local label, value = Y.Format(lonely)
eq(label .. "/" .. value, "One/" .. DASH, "no library shows the configured plugin name and the placeholder")
print("datatext sources PASS")

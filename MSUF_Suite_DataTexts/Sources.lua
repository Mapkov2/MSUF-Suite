local _, P = ...
local NS, S = P.NS, P.Suite
local NO_VALUE = P.NO_VALUE
local CREST = NS.DataTextCrestMode

-- The additional DataText sources: one binding per configured place
-- ("kind:bar:place"), their values and the events that change them.
-- Actions.lua owns what their clicks and tooltips do.
local Sources = { bindings = {} }
P.DataTextSources = Sources
S.DataTextExtraSources = Sources
local broker, owner
local SeasonSelection
Sources.AUDIO = { "Sound_MasterVolume", "Sound_SFXVolume", "Sound_MusicVolume", "Sound_AmbienceVolume", "Sound_DialogVolume" }
local EVENTS = {
    CURRENCY_DISPLAY_UPDATE = { currency = true, crests = true },
    PLAYER_AVG_ITEM_LEVEL_UPDATE = { itemLevel = true },
    PLAYER_EQUIPMENT_CHANGED = { itemLevel = true },
    SKILL_LINES_CHANGED = { professions = true },
    PLAYER_SPECIALIZATION_CHANGED = { specialization = true },
    PLAYER_LEVEL_UP = { progress = true },
    UPDATE_FACTION = { progress = true },
    PLAYER_XP_UPDATE = { progress = true },
    UPDATE_EXHAUSTION = { progress = true },
    CVAR_UPDATE = { audio = true },
    BAG_UPDATE_DELAYED = { hearth = true },
    TOYS_UPDATED = { hearth = true },
    SPELLS_CHANGED = { specialization = true, portals = true },
    ITEM_UPGRADE_MASTER_SET_ITEM = { crests = true },
}
Sources.kinds = {
    broker = true, currency = true, crests = true, itemLevel = true, professions = true, specialization = true,
    audio = true, hearth = true, progress = true, portals = true, microMenu = true,
}
-- Places whose click runs a protected action through a secure button
-- (Actions.lua). Their bars release it when combat starts.
Sources.secureKinds = { hearth = true, specialization = true, portals = true, microMenu = true }

local function Text(value)
    return S.Public(value) and type(value) == "string" and value or nil
end

local function Number(value)
    return S.Finite(value) and value or nil
end

local function AddIcon(binding, texture)
    local icon = Number(texture) or Text(texture)
    if icon then binding.icons[#binding.icons + 1] = icon end
end

-- LibDataBroker-1.1 through LibStub when another addon loaded it; the Suite
-- bundles neither.
local function Broker()
    if not broker and _G.LibStub then broker = LibStub:GetLibrary("LibDataBroker-1.1", true) end
    return broker
end

-- The broker data object of a binding, or nil.
function Sources.BrokerObject(binding)
    local lib = Broker()
    return lib and lib:GetDataObjectByName(binding.broker) or nil
end

function Sources.Bind(button, config, index, slot, kind)
    local prefix = "bar" .. index .. "Slot" .. slot
    local key = kind .. ":" .. index .. ":" .. slot
    local binding = Sources.bindings[key] or { icons = {} }
    binding.kind, binding.button, binding.prefix = kind, button, prefix
    binding.broker = config[prefix .. "Broker"] or ""
    binding.currency = tonumber(config[prefix .. "Currency"]) or 0
    binding.maxWidth = config[prefix .. "MaxWidth"] or 180
    binding.padding = config[prefix .. "Padding"] or 5
    binding.iconR, binding.iconG, binding.iconB = S.RGB(config[prefix .. "IconColor"] or "ffffff")
    Sources.bindings[key] = binding
    button.source, button.extra = key, binding
    return key
end

function Sources.Has(key)
    return Sources.bindings[key] ~= nil
end

local function Currency(id)
    local info = id > 0 and C_CurrencyInfo.GetCurrencyInfo(id)
    if type(info) ~= "table" or not Text(info.name) or not Number(info.quantity) then return end
    if info.discovered == false then return end
    return info
end

------------------------------------------------------------------ seasonal crests
-- Native season metadata exists only while an upgrade item is selected.
-- Keep the last observed list for this login; never invent a season or
-- replace it with unrelated currency IDs when the API has no item.
function Sources.ObserveSeasonCosts()
    -- Forever has no C_ItemUpgrade and no modern equipment upgrades.
    if not NS.Client.modernEquipment or not C_ItemUpgrade then return end
    local info = C_ItemUpgrade.GetItemUpgradeItemInfo()
    local costs = type(info) == "table" and info.upgradeCostTypesForSeason
    if type(costs) ~= "table" or #costs == 0 then return end
    local observed = {}
    for i = 1, math.min(#costs, 32) do
        local cost = costs[i]
        if type(cost) == "table" and Number(cost.orderIndex) and (Number(cost.currencyID) or Number(cost.itemID)) then
            observed[#observed + 1] = {
                currencyID = Number(cost.currencyID), itemID = Number(cost.itemID),
                order = cost.orderIndex, source = Text(cost.sourceString),
            }
        end
    end
    table.sort(observed, function(a, b) return a.order < b.order end)
    Sources.seasonCosts = #observed > 0 and observed or nil
    Sources.seasonItem = Text(info.name)
    if owner then SeasonSelection(owner.config) end
end

function Sources.CrestChoices()
    return Sources.seasonCosts or {}
end

local selectionText, selectionCosts, selectionMode, selectedCosts
SeasonSelection = function(config)
    local mode = config.crestMode == CREST.SELECTED and CREST.SELECTED or CREST.OBSERVED
    local text = Text(mode == CREST.SELECTED and config.crestCurrencyIDs or config.crestCurrencies) or ""
    if selectedCosts and selectionText == text and selectionCosts == Sources.seasonCosts and selectionMode == mode then
        return selectedCosts
    end
    selectionText, selectionCosts, selectionMode = text, Sources.seasonCosts, mode
    selectedCosts = {}
    local costs = Sources.seasonCosts or {}
    local byOrder = {}
    for _, cost in ipairs(costs) do
        if not byOrder[cost.order] then byOrder[cost.order] = cost end
    end
    local count = 0
    -- Imported configuration is bounded independently of its string length.
    for id in text:sub(1, 4096):gmatch("%d+") do
        count = count + 1
        local number = tonumber(id)
        local cost
        if mode == CREST.SELECTED then
            cost = Number(number) and number > 0 and number < 2147483647 and { currencyID = number, order = count } or nil
        else
            cost = byOrder[number]
        end
        if cost then selectedCosts[#selectedCosts + 1] = cost end
        if count == 128 then break end
    end
    if count == 0 and mode == CREST.OBSERVED then
        for _, cost in ipairs(costs) do selectedCosts[#selectedCosts + 1] = byOrder[cost.order] end
    end
    return selectedCosts
end
Sources.SeasonSelection = function() return SeasonSelection(owner.config) end

-- Name, amount and icon of one seasonal cost, or nothing while unknown.
function Sources.SeasonValue(cost)
    if cost.currencyID then
        local info = Currency(cost.currencyID)
        if info then return info.name, info.quantity, info.iconFileID end
    elseif cost.itemID then
        local name, _, _, _, _, _, _, _, _, icon = C_Item.GetItemInfo(cost.itemID)
        local count = C_Item.GetItemCount(cost.itemID, false, false, false)
        if Text(name) and Number(count) then return name, count, icon end
    end
end

------------------------------------------------------------------ values
local FORMAT = {}

FORMAT.broker = function(binding)
    local object = Sources.BrokerObject(binding)
    if not object then return binding.broker ~= "" and binding.broker or S.Text("Broker"), NO_VALUE end
    AddIcon(binding, object.icon)
    return Text(object.label) or binding.broker, Text(object.text) or Text(object.value) or NO_VALUE
end

FORMAT.currency = function(binding)
    local info = Currency(binding.currency)
    if not info then return S.Text("Currency"), NO_VALUE end
    AddIcon(binding, info.iconFileID)
    return info.name, tostring(info.quantity)
end

FORMAT.itemLevel = function(_, c)
    if not NS.Client.modernEquipment then return S.Text("Item level"), NO_VALUE end
    local overall, equipped = GetAverageItemLevel()
    local value = c.itemLevelEquipped ~= false and equipped or overall
    if not Number(value) then return S.Text("Item level"), NO_VALUE end
    return S.Text("Item level"), string.format("%." .. (c.itemLevelDecimals or 1) .. "f", value)
end

FORMAT.professions = function(binding)
    local first, second = GetProfessions()
    local pieces = binding.pieces
    for i = #pieces, 1, -1 do pieces[i] = nil end
    for _, id in ipairs({ first or false, second or false }) do
        if id then
            local name, texture, rank, maximum = GetProfessionInfo(id)
            if Text(name) and Number(rank) and Number(maximum) then
                pieces[#pieces + 1] = name .. " " .. rank .. "/" .. maximum
                binding.icons[#binding.icons + 1] = Number(texture) or 134400
            end
        end
    end
    return S.Text("Professions"), #pieces > 0 and table.concat(pieces, " / ") or NO_VALUE
end

FORMAT.specialization = function(binding)
    local api = C_SpecializationInfo
    local index = api.GetSpecialization()
    if not Number(index) or index <= 0 then return S.Text("Specialization"), NO_VALUE end
    local _, name, _, texture = api.GetSpecializationInfo(index)
    if not Text(name) then return S.Text("Specialization"), NO_VALUE end
    AddIcon(binding, texture)
    return S.Text("Specialization"), name
end

FORMAT.audio = function(_, c)
    local value = tonumber(C_CVar.GetCVar(Sources.AUDIO[c.audioChannel or 1]))
    return S.Text("Volume"), Number(value) and math.floor(value * 100 + .5) .. "%" or NO_VALUE
end

FORMAT.hearth = function(binding)
    local item = binding.hearth
    if not item then return S.Text("Hearthstone"), NO_VALUE end
    local name, _, _, _, _, _, _, _, _, texture = C_Item.GetItemInfo(item.id)
    AddIcon(binding, texture)
    return S.Text("Hearthstone"), Text(name) or tostring(item.id)
end

FORMAT.progress = function()
    local maximum = GetMaxPlayerLevel()
    local level = UnitLevel("player")
    if Number(level) and Number(maximum) and level < maximum then
        local xp, limit = UnitXP("player"), UnitXPMax("player")
        local done = Number(xp) and Number(limit) and limit > 0
        return S.Text("XP"), done and math.floor(xp / limit * 100 + .5) .. "%" or NO_VALUE
    end
    local info = C_Reputation.GetWatchedFactionData()
    if type(info) == "table" and Text(info.name) and Number(info.currentStanding)
        and Number(info.currentReactionThreshold) and Number(info.nextReactionThreshold)
        and info.nextReactionThreshold > info.currentReactionThreshold then
        local span = info.nextReactionThreshold - info.currentReactionThreshold
        return info.name, math.floor((info.currentStanding - info.currentReactionThreshold) / span * 100 + .5) .. "%"
    end
    return S.Text("Reputation"), NO_VALUE
end

FORMAT.crests = function(binding, c)
    local pieces = binding.pieces
    for i = #pieces, 1, -1 do pieces[i] = nil end
    for _, cost in ipairs(SeasonSelection(c)) do
        local name, quantity, icon = Sources.SeasonValue(cost)
        if name then
            pieces[#pieces + 1] = tostring(quantity)
            binding.icons[#binding.icons + 1] = Number(icon) or 134400
        end
    end
    return S.Text("Crests"), #pieces > 0 and table.concat(pieces, c.crestSeparator or " / ") or NO_VALUE
end

FORMAT.portals = function()
    return S.Text("Dungeon portals"), S.Text("Open")
end

FORMAT.microMenu = function()
    return S.Text("Menu"), S.Text("Open")
end

-- Label and value of a bound place; its icons land in binding.icons.
function Sources.Format(key)
    local binding = Sources.bindings[key]
    if not binding then return end
    local icons = binding.icons
    for i = #icons, 1, -1 do icons[i] = nil end
    binding.pieces = binding.pieces or {}
    return FORMAT[binding.kind](binding, owner.config)
end

------------------------------------------------------------------ events
local function Refresh(kind)
    if not owner or not owner.active then return end
    for key in pairs(owner.activeSources or {}) do
        local binding = Sources.bindings[key]
        if binding and binding.kind == kind then owner:UpdateSource(key, true) end
    end
end

local function BrokerChanged(_, name)
    if not owner or not owner.active then return end
    for key in pairs(owner.activeSources or {}) do
        local binding = Sources.bindings[key]
        if binding and binding.kind == "broker" and binding.broker == name then owner:UpdateSource(key, true) end
    end
end

local function ActiveKind(kind)
    if not owner or not owner.active then return false end
    for key in pairs(owner.activeSources or {}) do
        local binding = Sources.bindings[key]
        if binding and binding.kind == kind then return true end
    end
    return false
end

local function WantsCrestItems()
    if not ActiveKind("crests") or owner.config.crestMode == CREST.SELECTED then return false end
    for _, cost in ipairs(SeasonSelection(owner.config)) do
        if cost.itemID then return true end
    end
    return false
end

function Sources.Changed(_, event)
    if event == "ITEM_UPGRADE_MASTER_SET_ITEM" then
        local previous = WantsCrestItems()
        Sources.ObserveSeasonCosts()
        -- Native metadata can first introduce/remove item stages after login.
        -- Reuse the owner's source/event reconciliation only on that transition.
        if previous ~= WantsCrestItems() and owner then owner:Rebind() end
    end
    local kinds = EVENTS[event]
    if kinds then
        for kind in pairs(kinds) do Refresh(kind) end
    end
    if event == "BAG_UPDATE_DELAYED" and WantsCrestItems() then Refresh("crests") end
    if event == "BAG_UPDATE_DELAYED" or event == "TOYS_UPDATED" then Sources.HearthsMayHaveChanged() end
end

function Sources.WantedEvents(active, wanted)
    if WantsCrestItems() then wanted.BAG_UPDATE_DELAYED = true end
    for key in pairs(active) do
        local binding = Sources.bindings[key]
        if binding then
            for event, kinds in pairs(EVENTS) do
                if kinds[binding.kind] then wanted[event] = true end
            end
            -- PLAYER_REGEN_DISABLED runs before lockdown: the secure button of
            -- these places is released there and offered again after combat.
            if Sources.secureKinds[binding.kind] then
                wanted.PLAYER_REGEN_DISABLED, wanted.PLAYER_REGEN_ENABLED = true, true
            end
        end
    end
end

-- Called only after the complete bar/slot rebuild; hidden configured slots
-- remain bound so their visibility changes can reactivate them.
function Sources.Prune(module, configured, sources)
    for key, binding in pairs(Sources.bindings) do
        if not configured[key] or binding.button.extra ~= binding or binding.button.source ~= key then
            local button = binding.button
            if button.extra == binding then button.extra = nil end
            if button.source == key then button.source = nil end
            binding.button = nil
            Sources.bindings[key] = nil
            module.values[key], module.due[key] = nil, nil
            if sources then sources[key] = nil end
        end
    end
end

local configuredSources = {}
function Sources.PruneConfigured(module, sources)
    for key in pairs(configuredSources) do configuredSources[key] = nil end
    for _, bar in pairs(module.bars) do
        if module.config[bar.enabledKey] then
            for slot = 1, #bar.slots do
                local key = bar.slots[slot].source
                if key then configuredSources[key] = true end
            end
        end
    end
    Sources.Prune(module, configuredSources, sources)
end

local wantedKinds = {}
function Sources.Rebind(module)
    owner = module
    for kind in pairs(wantedKinds) do wantedKinds[kind] = nil end
    for key in pairs(module.activeSources or {}) do
        local binding = Sources.bindings[key]
        if binding then wantedKinds[binding.kind] = true end
    end
    if wantedKinds.crests then
        if module.config.crestMode ~= CREST.SELECTED and not Sources.seasonCosts then Sources.ObserveSeasonCosts() end
        SeasonSelection(module.config)
    end
    local lib = Broker()
    if wantedKinds.broker and lib and not Sources.brokerRegistered then
        lib.RegisterCallback(Sources, "LibDataBroker_AttributeChanged", BrokerChanged)
        lib.RegisterCallback(Sources, "LibDataBroker_DataObjectCreated", BrokerChanged)
        Sources.brokerRegistered = true
    elseif not wantedKinds.broker and lib and Sources.brokerRegistered then
        lib.UnregisterAllCallbacks(Sources)
        Sources.brokerRegistered = nil
    end
    local active = module.activeSources
    if module.config.showTokenPrice and NS.Client.modernEquipment and (active.gold or active.sessionGold)
        and not Sources.tokenQueried then
        -- The price arrives with TOKEN_MARKET_PRICE_UPDATED; tooltips read it then.
        if C_WowTokenPublic.GetCommerceSystemStatus() then
            C_WowTokenPublic.UpdateMarketPrice()
            Sources.tokenQueried = true
        end
    end
end

------------------------------------------------------------------ hearthstones
-- The configured Hearthstone IDs, parsed once per setting text, and which of
-- them the player owned (as an item or a toy) when the places last chose.
local HEARTH_CHOICES = 100
local hearthText, hearthIDs, hearthOwned, hearthToys = nil, {}, {}, {}

local function HearthIDs()
    local text = owner.config.hearthItems or "6948"
    if text == hearthText then return hearthIDs end
    hearthText = text
    for i = #hearthIDs, 1, -1 do hearthIDs[i], hearthOwned[i], hearthToys[i] = nil, nil, nil end
    for value in text:gmatch("%d+") do hearthIDs[#hearthIDs + 1] = tonumber(value) end
    return hearthIDs
end

-- Reads which configured Hearthstones the player owns; true when that
-- differs from the last read.
local function ReadHearths()
    local ids, changed = HearthIDs(), false
    for i = 1, #ids do
        local id = ids[i]
        local toy = PlayerHasToy(id) == true
        local count = C_Item.GetItemCount(id, false, false, false)
        local owned = toy or Number(count) and count > 0 or false
        if hearthOwned[i] ~= owned or hearthToys[i] ~= toy then
            hearthOwned[i], hearthToys[i], changed = owned, toy, true
        end
    end
    return changed
end

-- Chooses the Hearthstone each Hearthstone place uses next (data only;
-- Actions.lua hands it to the secure button out of combat). In combat the
-- overlay is hidden: only mark the choice stale; DataTexts.lua checks it
-- again at PLAYER_REGEN_ENABLED.
function Sources.PrepareHearths()
    if not ActiveKind("hearth") then return end
    if NS.IsCombatLocked() then
        Sources.hearthDirty = true
        return
    end
    ReadHearths()
    local choices = {}
    for i = 1, #hearthIDs do
        if hearthOwned[i] then choices[#choices + 1] = { id = hearthIDs[i], toy = hearthToys[i] } end
        if #choices == HEARTH_CHOICES then break end
    end
    for key in pairs(owner.activeSources or {}) do
        local binding = Sources.bindings[key]
        if binding and binding.kind == "hearth" and binding.button.extra == binding then
            local pick = owner.config.randomHearth and #choices > 1 and math.random(#choices) or 1
            binding.hearth = choices[pick]
        end
    end
    Refresh("hearth")
    P.DataTextActions.Refresh()
end

-- Bag and toy updates choose again only when the owned Hearthstones changed:
-- a random variant stays until it is used (Actions.lua OverlayPostClick) or
-- lost, and an unrelated loot builds nothing. The overlay is hidden in
-- combat, so a combat update only marks the choice for PLAYER_REGEN_ENABLED.
function Sources.HearthsMayHaveChanged()
    if not ActiveKind("hearth") then return end
    if NS.IsCombatLocked() then
        Sources.hearthDirty = true
        return
    end
    if ReadHearths() then Sources.PrepareHearths() end
end

------------------------------------------------------------------ icons
local function IconTexture(button, index)
    local icons = button.dataIcons
    if not icons then
        icons = {}
        button.dataIcons = icons
    end
    local icon = icons[index]
    if not icon then
        icon = S.CreateTexture(button, nil, "ARTWORK")
        icon:SetSize(14, 14)
        icons[index] = icon
    end
    return icon
end

-- The icons of a place left of its text. Textures change only with their
-- file, anchors only with the icon count or padding, or after a relayout
-- (Geometry.lua anchored the label anew).
function Sources.Paint(button, relayout)
    local binding = button.extra
    local count = binding and math.min(#binding.icons, 32) or 0
    local shown = button.iconCount or 0
    if count == 0 and shown == 0 then return end
    for i = 1, count do
        local icon = IconTexture(button, i)
        local texture = binding.icons[i]
        if relayout or icon.file ~= texture then
            icon:SetTexture(texture)
            icon:SetVertexColor(binding.iconR, binding.iconG, binding.iconB, 1)
            icon.file = texture
        end
        icon:Show()
    end
    for i = count + 1, shown do button.dataIcons[i]:Hide() end
    local padding = binding and binding.padding or 0
    if count > 0 and (relayout or count ~= shown or button.iconPadding ~= padding) then
        local previous
        for i = 1, count do
            local icon = button.dataIcons[i]
            icon:ClearAllPoints()
            if previous then
                icon:SetPoint("LEFT", previous, "RIGHT", 2, 0)
            else
                icon:SetPoint("LEFT", button, "LEFT", padding, 0)
            end
            previous = icon
        end
        button.label:ClearAllPoints()
        button.label:SetPoint("LEFT", previous, "RIGHT", 4, 0)
        button.label:SetPoint("RIGHT", button, "RIGHT", -padding, 0)
    elseif count == 0 and shown > 0 and not relayout and button.labelInset then
        -- Icons disappeared: the label goes back to its layout inset.
        button.label:ClearAllPoints()
        button.label:SetPoint("LEFT", button, "LEFT", button.labelInset, 0)
        button.label:SetPoint("RIGHT", button, "RIGHT", -button.labelInset, 0)
    end
    button.iconCount, button.iconPadding = count, padding
end

function Sources.Disable()
    if broker and Sources.brokerRegistered then broker.UnregisterAllCallbacks(Sources) end
    Sources.brokerRegistered = nil
    owner = nil
end

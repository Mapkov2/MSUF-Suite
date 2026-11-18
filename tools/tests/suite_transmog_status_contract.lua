local root = assert(arg[1])
local SECRET = {}
local APPEARANCE_UNKNOWN = "You haven't collected this appearance"
local MISSING = "Transmog appearance not collected"
local ALTERNATE = "Transmog appearance collected from another source"
local COLLECTED = "Transmog source collected"

function canaccesstable(value) return value ~= SECRET end
function wipe(values) for key in pairs(values) do values[key] = nil end end

local function Load(client)
    local state = { reads = 0, appearances = 0, tooltipLinkReads = 0, paints = 0, requests = 0,
        nativePostCalls = 0, lines = {}, links = {}, appearancesBySource = {}, knownItem = {}, events = {}, badges = {} }
    local module = { active = true, config = { showTransmogBadges = true }, context = {
        Event = function() error("transmog must preserve the Bags context's events") end,
        RemoveEvent = function() error("transmog must preserve the Bags context's events") end,
    } }
    C_Timer = { NewTimer = function(delay, callback)
        assert(delay == 0 and not state.pending)
        state.pending, state.requests = true, state.requests + 1
        state.runJob = function()
            if state.pending then
                state.pending = false
                callback()
            end
        end
        return { Cancel = function() state.pending = false end }
    end }
    local function Public(value) return value ~= SECRET end
    local S = {
        Public = Public, Text = function(value) return value end,
        PublicText = function(value) return type(value) == "string" and value ~= "" and value or nil end,
        Finite = function(value) return type(value) == "number" and value == value
            and value > -math.huge and value < math.huge end,
        CreateFrame = function()
            assert(not state.ownsFrame)
            state.ownsFrame = true
            return { RegisterEvent = function(_, event) state.events[event] = true end,
                UnregisterEvent = function(_, event) state.events[event] = nil end,
                UnregisterAllEvents = function() wipe(state.events) end,
                SetScript = function(_, kind, script) assert(kind == "OnEvent"); state.event = script end }
        end,
        SetFont = function() end,
    }
    local NS = { BagsSort = {}, Client = { isForever = client == "Forever" },
        InCombat = function() return state.combat end,
        Safety = { IsForbidden = function() return state.forbidden end } }
    local function Visible() return true end
    state.bag = { layout = "suite", frame = { IsVisible = Visible }, visibleButtons = {}, slotState = {} }
    state.bank = { frame = { IsVisible = Visible }, buttons = {} }
    local P = { NS = NS, Suite = S, BagsModule = module, SlotCache = { KEY = 1000 },
        InventoryView = state.bag, BankInventory = state.bank }
    function module.OverlayText(button)
        local badge = { SetText = function(self, text) self.text = text end, SetTextColor = function() end,
            IsShown = function(self) return self.shown end,
            Show = function(self) self.shown = true; state.paints = state.paints + 1 end,
            Hide = function(self) self.shown = false; state.paints = state.paints + 1 end }
        state.badges[button] = badge
        return badge
    end
    C_Item = {
        GetItemLinkByGUID = function(guid)
            assert(guid == "Item-7")
            state.tooltipLinkReads = state.tooltipLinkReads + 1
            return "item:7:missing"
        end,
        IsItemDataCachedByID = function(link) return state.knownItem[link] == true end,
    }
    C_TransmogCollection = {
        GetItemInfo = function(link)
            assert(Public(link) and not state.combat)
            state.reads = state.reads + 1
            return 1, state.links[link]
        end,
        GetAppearanceInfoBySource = function(id)
            assert(Public(id) and not state.combat)
            state.appearances = state.appearances + 1
            return state.appearancesBySource[id]
        end,
    }
    Enum = { TooltipDataType = { Item = 0 } }
    TooltipDataProcessor = { AddTooltipPostCall = function(kind, callback)
        assert(kind == Enum.TooltipDataType.Item)
        state.nativePostCalls, state.post = state.nativePostCalls + 1, callback
    end }
    GameTooltip = { GetOwner = function() return nil end,
        GetPrimaryTooltipData = function() return state.primary end,
        AddLine = function(_, line) state.lines[#state.lines + 1] = line end }
    TRANSMOGRIFY_TOOLTIP_APPEARANCE_UNKNOWN = APPEARANCE_UNKNOWN
    for _, file in ipairs({ "InventoryDetails", "TransmogStatus" }) do
        assert(loadfile(root .. "/MSUF_Suite_Bags/" .. file .. ".lua"))("MSUF_Suite_Bags", P)
    end
    state.transmog, state.details, state.config = P.BagTransmog, P.InventoryDetails, module.config
    return state
end

local function Tooltip(s, data)
    wipe(s.lines)
    local item = type(data) == "string" and { hyperlink = data, lines = {} } or data
    s.primary = item
    s.post(GameTooltip, item)
    return s.lines[1]
end

local function Fire(s, event)
    if s.events[event] then s.event(nil, event) end
end

local function Appearance(visual, source)
    return { appearanceIsCollected = visual, sourceIsCollected = source }
end

local function CheckInteraction(s)
    local missing, alternate, collected = "item:7:missing", "item:7:alternate", "item:7:collected"
    s.links[missing], s.links[alternate], s.links[collected] = 1, 2, 3
    s.appearancesBySource[1], s.appearancesBySource[2], s.appearancesBySource[3] =
        Appearance(false, false), Appearance(true, false), Appearance(true, true)
    local button = {}
    local basePainter = s.details.Paint
    s.transmog.Refresh()
    assert(not Tooltip(s, missing) and not s.ownsFrame, "transmog is off until enabled")
    assert(s.nativePostCalls == 1 and s.reads == 0 and s.details.Paint == basePainter)
    s.config.showTransmogStatus = true
    s.transmog.Refresh()
    assert(s.details.Paint ~= basePainter and s.events.TRANSMOG_COLLECTION_UPDATED and s.events.TRANSMOG_COLLECTION_ITEM_UPDATE)
    s.details.Paint(button, { link = missing, equipLoc = "HEAD" })
    assert(s.badges[button].text == "!" and s.badges[button].shown)
    assert(Tooltip(s, missing) == MISSING and s.reads == 1 and s.appearances == 1, "badge and tooltip share a status")
    assert(Tooltip(s, { guid = "Item-7", lines = {} }) == MISSING and s.tooltipLinkReads == 1)
    assert(not Tooltip(s, { hyperlink = missing, lines = { { leftText = APPEARANCE_UNKNOWN } } }))
    assert(not Tooltip(s, { hyperlink = SECRET, guid = SECRET, lines = {} }))
    s.primary = { hyperlink = alternate, lines = {} }
    s.post(GameTooltip, { hyperlink = alternate, lines = {} })
    assert(#s.lines == 0 and s.reads == 1, "appended item blocks and unreadable data are ignored")
    assert(Tooltip(s, alternate) == ALTERNATE and Tooltip(s, collected) == COLLECTED)
    s.details.Paint(button, { link = alternate, equipLoc = "HEAD" })
    assert(s.badges[button].text == "+" and s.badges[button].shown)
    s.details.Paint(button, { link = collected, equipLoc = "HEAD" })
    assert(not s.badges[button].shown, "reused slots clear their previous mark")
    local bank = {}
    s.details.Paint(bank, { link = alternate, equipLoc = "HEAD", bankType = 1 })
    s.details.Paint(button, { link = missing, equipLoc = "HEAD" })
    s.transmog.HideBadges(true)
    assert(not s.badges[button].shown and s.badges[bank].shown, "bag release does not hide open bank badges")
    assert(s.reads == 3, "same itemID with different link variants resolves independent sources")
    return basePainter
end

local function CheckCombat(s, basePainter)
    local missing, alternate = "item:7:missing", "item:7:alternate"
    Fire(s, "TRANSMOG_COLLECTION_UPDATED")
    assert(s.requests == 0, "closed inventory windows never schedule a repaint")
    assert(Tooltip(s, missing) == MISSING)

    local function Visible() assert(not s.combat); return true end
    local itemMissing, itemAlternate = { link = missing, equipLoc = "HEAD" },
        { link = alternate, equipLoc = "HEAD", bankType = 1 }
    local bagButton, bankButton = { IsVisible = Visible }, { IsVisible = Visible, record = itemAlternate }
    local hiddenButton = { IsVisible = function() assert(not s.combat); return false end }
    s.bag.active, s.bank.active = true, true
    s.bag.visibleButtons[bagButton], s.bag.visibleButtons[hiddenButton] = true, true
    s.bag.slotState[bagButton] = { row = { item = itemMissing } }
    s.bag.slotState[hiddenButton] = { row = { item = { link = "item:10001", equipLoc = "HEAD" } } }
    s.bank.buttons[1] = bankButton
    s.details.Paint(bagButton, itemMissing)
    s.details.Paint(bankButton, itemAlternate)
    assert(s.badges[bagButton].shown and s.badges[bankButton].text == "+")

    local reads = s.reads
    Fire(s, "TRANSMOG_COLLECTION_UPDATED")
    Fire(s, "TRANSMOG_COLLECTION_ITEM_UPDATE")
    assert(s.requests == 1 and s.pending, "collection events coalesce into one focused repaint")
    s.bag.slotState[bagButton].row.item = { link = "item:7:collected", equipLoc = "HEAD" }
    s.appearancesBySource[2] = Appearance(false, false)
    s.runJob()
    assert(not s.badges[bagButton].shown and s.badges[bankButton].text == "!" and s.reads == reads + 2,
        "repaint reads current reused live slots and skips hidden slots")
    Fire(s, "TRANSMOG_COLLECTION_UPDATED")
    assert(s.requests == 2 and s.pending)
    Fire(s, "PLAYER_REGEN_DISABLED")
    assert(not s.combat and s.details.Paint == basePainter and not s.pending,
        "combat edge cancels the repaint and detaches before lockdown reports true")
    assert(not s.events.TRANSMOG_COLLECTION_UPDATED and not s.events.TRANSMOG_COLLECTION_ITEM_UPDATE)
    local appearances, paints, requests = s.appearances, s.paints, s.requests
    reads = s.reads
    s.combat = true
    Fire(s, "TRANSMOG_COLLECTION_UPDATED")
    s.runJob()
    s.appearancesBySource[1] = Appearance(true, true)
    s.appearancesBySource[2] = Appearance(true, false)
    s.details.Paint({}, { link = missing, equipLoc = "HEAD" })
    assert(not Tooltip(s, missing) and not Tooltip(s, { guid = "Item-7", lines = {} }))
    assert(s.tooltipLinkReads == 1 and s.reads == reads and s.appearances == appearances
        and s.paints == paints and s.requests == requests, "no transmog dispatch, repaint, refresh, or C reads in combat")
    s.combat = false
    Fire(s, "PLAYER_REGEN_ENABLED")
    assert(Tooltip(s, missing) == COLLECTED and s.events.TRANSMOG_COLLECTION_UPDATED,
        "next out-of-combat read sees collection updates missed in combat")
    s.config.showTransmogBadges = false
    s.transmog.Refresh()
    assert(s.details.Paint == basePainter and Tooltip(s, alternate) == ALTERNATE, "tooltip-only mode")
    Fire(s, "TRANSMOG_COLLECTION_ITEM_UPDATE")
    assert(s.requests == requests, "tooltip-only mode does not schedule inventory refreshes")
end

local function CheckDeferred(s, basePainter)
    local link = "item:10:loading"
    assert(not Tooltip(s, link), "item not loaded")
    s.links[link] = SECRET
    assert(not Tooltip(s, link), "source ID not public")
    s.links[link] = 10
    s.appearancesBySource[10] = Appearance(true, SECRET)
    assert(not Tooltip(s, link), "secret source flag")
    s.appearancesBySource[10] = Appearance(true, true)
    assert(Tooltip(s, link) == COLLECTED, "incomplete data never poisons the cache")
    local notEquipment = "item:20"
    s.knownItem[notEquipment] = true
    assert(not Tooltip(s, notEquipment))
    local reads = s.reads
    assert(not Tooltip(s, notEquipment) and s.reads == reads, "loaded non-transmog items use negative cache")
    for i = 101, 613 do
        local many = "item:" .. i
        s.links[many] = 1
        assert(Tooltip(s, many) == COLLECTED)
    end
    reads = s.reads
    assert(Tooltip(s, link) == COLLECTED and s.reads == reads + 1, "item-link cache is bounded")
    s.config.showTransmogStatus = false
    s.transmog.Refresh()
    assert(next(s.events) == nil and s.details.Paint == basePainter and s.nativePostCalls == 1)
    assert(not Tooltip(s, link), "disable releases all new dispatch")
end

for _, client in ipairs({ "Retail", "Forever" }) do
    local state = Load(client)
    local painter = CheckInteraction(state)
    CheckCombat(state, painter)
    CheckDeferred(state, painter)
end
print("suite_transmog_status_contract: Retail and Forever variants, cache, native tooltip and combat suspension passed")

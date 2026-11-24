local _, P = ...
local NS, S = P.NS, P.Suite
local View = P.LootWindowView
-- The minimal loot window and its loot feed. Blizzard's LootFrame keeps
-- running while it is muted (Runtime.lua Context:Mute: a shown host with
-- alpha zero and a scale without hit area), so LOOT_OPENED, Escape, the bind
-- confirmation, sounds and CloseLoot on hide stay Blizzard's; this window
-- only mirrors the slots and loots the one the player clicks. The decision
-- to own a loot session falls on LOOT_READY, before Blizzard's LOOT_OPENED
-- places its window: gamepad mode, master loot, an unreadable slot or a
-- failed mute leave that session to Blizzard's window. The feed shows what reached the bags,
-- measured by item, currency and money counts, so loot another player takes
-- from a shared corpse never appears as yours.
local ID = "lootWindow"
local IN_COMBAT = { inCombat = true }
local CURSOR, GROW_UP = 1, 2
local MAX_SLOTS, MAX_FEED = 64, 24
-- Auto loot (and the Suite's fast loot) clear most slots within a few
-- frames; the window then shows only what is left after this wait.
local REVEAL_DELAY = .3
-- A cleared slot waits this long for its count to rise before it is dropped.
local CONFIRM_DELAY, CONFIRM_LIMIT = .2, 4
local M = { entries = {}, bySlot = {}, expected = {}, feedEntries = {} }

------------------------------------------------------------------ native window
local function Native()
    local frame = LootFrame
    if frame and not NS.Safety.IsForbidden(frame) then return frame end
end

local function MuteNative(self)
    if self.muted then return true end
    local frame = Native()
    if frame and self.context:Mute(frame) then self.muted = frame end
    return self.muted ~= nil
end

local function ReleaseNative(self)
    if not self.muted then return end
    self.context:Unmute(self.muted)
    self.muted = nil
end

local function Wanted(self)
    return self.config.window == true and not S.GamepadUI()
end

-- Master loot (WoW Forever, Retail 12.1.7) assigns the slot Blizzard's own
-- loot rows recorded on their click, which this window never writes: such a
-- session stays Blizzard's.
local function MasterLoot()
    local method = C_PartyInfo.GetLootMethod()
    return S.Public(method) and method == Enum.LootMethod.Masterlooter
end

------------------------------------------------------------------ slot reading
local function SlotKind(slot)
    local kind = GetLootSlotType(slot)
    if not S.Finite(kind) then return nil end
    local types = Enum.LootSlotType
    if kind == types.Money then return "money" end
    if kind == types.Currency then return "currency" end
    if kind == types.Item then return "item" end
    return "none"
end

-- Readable text stays text; a secret only ever reaches SetText.
local function Label(value)
    if not S.Public(value) then return value end
    return type(value) == "string" and value or ""
end

-- Blizzard's coin text of a money slot holds one line per coin.
local function CoinText(value)
    local text = S.PublicText(value)
    if not text then return S.Public(value) and "" or value end
    return (text:gsub("\n", " "))
end

local function ReadItem(entry, slot, quantity, isQuestItem, questID, isActive)
    local quest = S.Public(isQuestItem) and isQuestItem == true
    local questItem = S.Finite(questID) and questID > 0
    entry.quest = quest or questItem
    entry.questBang = questItem and S.Public(isActive) and isActive == false
    entry.subtitle = entry.quest and ITEM_BIND_QUEST or View.QualityName(entry.quality)
    if S.Finite(quantity) and quantity > 1 then entry.amount = tostring(quantity) end
    local link = S.PublicText(GetLootSlotLink(slot))
    entry.link = link
    if link and entry.kind == "item" then
        local itemID = C_Item.GetItemInfoInstant(link)
        entry.itemID = S.Finite(itemID) and itemID or nil
    end
end

-- One slot as a plain record, nil for an empty slot, false when the client
-- keeps its kind from addons.
local function ReadSlot(slot)
    local kind = SlotKind(slot)
    if kind == nil then return false end
    if kind == "none" then return nil end
    local texture, item, quantity, currencyID, quality, locked, isQuestItem, questID, isActive = GetLootSlotInfo(slot)
    local currency = kind == "currency" and S.Finite(currencyID) and currencyID or nil
    if currency then
        item, texture, quantity, quality = CurrencyContainerUtil.GetCurrencyContainerInfo(currency, quantity, item, texture, quality)
    end
    local entry = { slot = slot, kind = kind, currencyID = currency }
    entry.icon = S.Public(texture) and (texture or View.FallbackIcon) or texture
    entry.locked = S.Public(locked) and locked == true
    if kind == "money" then
        entry.name, entry.amount = MONEY, CoinText(item)
        return entry
    end
    entry.name = Label(item)
    entry.quality = S.Finite(quality) and quality or nil
    ReadItem(entry, slot, quantity, isQuestItem, questID, isActive)
    return entry
end

-- Every slot, in Blizzard's slot order. False keeps the previous records
-- (and the session with Blizzard's window when it is the first read).
local function ReadLoot(self)
    local count = GetNumLootItems()
    if not S.Finite(count) or count < 0 or count > MAX_SLOTS or count ~= math.floor(count) then return false end
    local entries, bySlot = {}, {}
    for slot = 1, count do
        local entry = ReadSlot(slot)
        if entry == false then return false end
        if entry then
            entries[#entries + 1] = entry
            bySlot[slot] = entry
        end
    end
    self.entries, self.bySlot = entries, bySlot
    self.window.entries = entries
    return true
end

------------------------------------------------------------------ feed counts
local function ItemCount(itemID)
    local count = C_Item.GetItemCount(itemID)
    return S.Finite(count) and count or nil
end

local function CurrencyCount(currencyID)
    local info = C_CurrencyInfo.GetCurrencyInfo(currencyID)
    if not S.Public(info) or type(info) ~= "table" then return nil end
    return S.Finite(info.quantity) and info.quantity or nil
end

local function Money()
    local money = GetMoney()
    return S.Finite(money) and money or nil
end

-- What each looted thing counted when the session began (or when its slot
-- first appeared); a gain is measured against it and then moves it.
local function Track(self, entry)
    local base = self.baseline
    if not base then return end
    if entry.itemID and base.items[entry.itemID] == nil then
        base.items[entry.itemID] = ItemCount(entry.itemID) or false
    elseif entry.currencyID and base.currencies[entry.currencyID] == nil then
        base.currencies[entry.currencyID] = CurrencyCount(entry.currencyID) or false
    end
end

-- A new session counts afresh, except what an earlier session still waits
-- for: looting the next corpse at once must not swallow the last gains.
local function Baseline(self)
    local old, base = self.baseline, { items = {}, currencies = {}, money = Money() }
    for _, wait in ipairs(old and self.expected or {}) do
        local entry = wait.entry
        if entry.kind == "money" then
            base.money = old.money
        elseif entry.currencyID then
            base.currencies[entry.currencyID] = old.currencies[entry.currencyID]
        else
            base.items[entry.itemID] = old.items[entry.itemID]
        end
    end
    self.baseline = base
    for _, entry in ipairs(self.entries) do Track(self, entry) end
end

local function Rise(list, key, now)
    local before = list[key]
    if not now or not before or now <= before then return nil end
    list[key] = now
    return now - before
end

local function Gained(self, entry)
    local base = self.baseline
    if entry.kind == "money" then
        local now = Money()
        if not now or not base.money or now <= base.money then return nil end
        local gain = now - base.money
        base.money = now
        return gain
    end
    if entry.currencyID then return Rise(base.currencies, entry.currencyID, CurrencyCount(entry.currencyID)) end
    if entry.itemID then return Rise(base.items, entry.itemID, ItemCount(entry.itemID)) end
end

------------------------------------------------------------------ feed
local function FeedAllows(config, entry)
    if entry.kind == "money" then return config.feedMoney ~= false end
    return entry.quest or not entry.quality or entry.quality >= config.feedQuality
end

local function FeedKey(entry)
    if entry.kind == "money" then return "money" end
    if entry.currencyID then return "currency:" .. entry.currencyID end
    return "item:" .. entry.itemID
end

local function FeedAmount(entry, total)
    if entry.kind == "money" then return C_CurrencyInfo.GetCoinTextureString(total) end
    return total > 1 and tostring(total) or nil
end

local Expire

local function PaintFeed(self, animate)
    local feed = self.feedView
    feed.entries = self.feedEntries
    if animate and #feed.entries == 0 and self.config.feedFadeOut > 0 then
        View.Hide(feed, self.config.feedFadeOut)
    else
        View.Paint(feed, animate and self.config.feedFadeIn)
    end
end

local function NextExpiry(self)
    local soonest
    for _, record in ipairs(self.feedEntries) do
        if not soonest or record.expires < soonest then soonest = record.expires end
    end
    if soonest then
        self.context:After(math.max(0, soonest - GetTime()), Expire)
    else
        self.context:Cancel(Expire)
    end
end

Expire = function(self)
    local now, list = GetTime(), self.feedEntries
    for index = #list, 1, -1 do
        if list[index].expires <= now then table.remove(list, index) end
    end
    PaintFeed(self, true)
    NextExpiry(self)
end

local function FindFeed(list, key)
    for index, record in ipairs(list) do
        if record.key == key then return record, index end
    end
end

-- Newest first; the same item, currency or money again adds to its entry.
local function AddFeed(self, entry, gain)
    if not FeedAllows(self.config, entry) then return end
    local list, key = self.feedEntries, FeedKey(entry)
    local record, index = FindFeed(list, key)
    if record then
        table.remove(list, index)
        record.total = record.total + gain
    else
        record = { key = key, kind = entry.kind, total = gain, name = entry.name, icon = entry.icon,
            quality = entry.quality, subtitle = entry.subtitle, quest = entry.quest, questBang = entry.questBang }
    end
    record.amount = FeedAmount(entry, record.total)
    record.expires = GetTime() + self.config.feedSeconds
    table.insert(list, 1, record)
    for drop = #list, MAX_FEED + 1, -1 do list[drop] = nil end
    PaintFeed(self, true)
    NextExpiry(self)
end

-- In clearing order, so the last thing looted ends up newest.
local function Confirm(self)
    local waiting, now = {}, GetTime()
    for _, wait in ipairs(self.expected) do
        local gain = self.baseline and Gained(self, wait.entry)
        if gain then
            AddFeed(self, wait.entry, gain)
        elseif now - wait.at <= CONFIRM_LIMIT then
            waiting[#waiting + 1] = wait
        end
    end
    self.expected = waiting
    if #waiting > 0 then
        self.confirmJob:Request()
    else
        self.context:RemoveEvent("BAG_UPDATE_DELAYED")
        self.context:RemoveEvent("PLAYER_MONEY")
        self.context:RemoveEvent("CURRENCY_DISPLAY_UPDATE")
    end
end

local function Expect(self, entry)
    if not self.config.feed or not (entry.kind == "money" or entry.itemID or entry.currencyID) then return end
    self.expected[#self.expected + 1] = { entry = entry, at = GetTime() }
    self.context:Event("BAG_UPDATE_DELAYED", self.confirmJob, IN_COMBAT)
    self.context:Event("PLAYER_MONEY", self.confirmJob, IN_COMBAT)
    self.context:Event("CURRENCY_DISPLAY_UPDATE", self.confirmJob, IN_COMBAT)
    self.confirmJob:Request()
end

------------------------------------------------------------------ window
local function PlaceFixed(host, config, pointKey, xKey, yKey)
    local point = NS.AnchorPoints[config[pointKey]] or "CENTER"
    host:ClearAllPoints()
    host:SetScale(config.scale / 100)
    host:SetPoint(point, UIParent, point, config[xKey], config[yKey])
end

-- At the cursor, the first row sits under the pointer like Blizzard's
-- loot-under-mouse window; Clamp keeps the list on screen.
local function PlaceWindow(self)
    local window, config = self.window, self.config
    PlaceFixed(window.host, config, "point", "x", "y")
    if config.position ~= CURSOR then return end
    local x, y = GetCursorPosition()
    local scale = window.host:GetEffectiveScale()
    if not S.Finite(x) or not S.Finite(y) or not S.Finite(scale) or scale <= 0 then return end
    local up, half = config.growth == GROW_UP, window.metrics.height / 2
    window.host:ClearAllPoints()
    window.host:SetPoint(up and "BOTTOMLEFT" or "TOPLEFT", UIParent, "BOTTOMLEFT",
        x / scale - 16, y / scale + (up and -half or half))
end

local function Reveal(self, immediate)
    if not self.session or not self.own or #self.entries == 0 then return end
    self.revealed = true
    self.window.entries, self.window.first = self.entries, 0
    PlaceWindow(self)
    View.Paint(self.window, not immediate and self.config.fadeIn)
end

local function HideWindow(self)
    local animate = self.revealed or self.window.fadingOut
    self.revealed = false
    self.context:Cancel(Reveal)
    self.window.entries = self.entries
    View.Hide(self.window, animate and self.config.fadeOut)
end

local function Repaint(self)
    if not self.revealed then return end
    self.window.entries = self.entries
    if #self.entries == 0 then HideWindow(self) else View.Paint(self.window) end
end

local function FastLoot()
    local loot = S.instances.loot
    return loot ~= nil and loot.active == true and S.Config("loot").quickLoot == true
end

------------------------------------------------------------------ sessions
-- LOOT_READY comes before Blizzard places its window on LOOT_OPENED: the
-- session is decided here. A later READY of the same session (fast loot
-- reads again) only refreshes the slots.
local function Begin(self, autoLoot)
    if autoLoot then self.autoLoot = true end
    local readable = ReadLoot(self)
    if self.session then return end
    self.session = true
    Baseline(self)
    self.own = readable and Wanted(self) and not MasterLoot() and MuteNative(self)
    if not self.own then ReleaseNative(self) end
end

local function Ready(self, _, autoLoot)
    Begin(self, S.Public(autoLoot) and autoLoot == true)
end

local function Opened(self, _, autoLoot)
    Begin(self, S.Public(autoLoot) and autoLoot == true)
    if not self.own then return end
    ReadLoot(self)
    if self.autoLoot or FastLoot() then
        self.context:After(REVEAL_DELAY, Reveal)
    else
        Reveal(self)
    end
end

local function Cleared(self, _, slot)
    if not S.Finite(slot) then return end
    local entry = self.bySlot[slot]
    if not entry then return end
    self.bySlot[slot] = nil
    for index, other in ipairs(self.entries) do
        if other == entry then
            table.remove(self.entries, index)
            break
        end
    end
    Expect(self, entry)
    Repaint(self)
end

local function Changed(self, _, slot)
    if not S.Finite(slot) or not self.bySlot[slot] then return end
    if not ReadLoot(self) then return end
    for _, entry in ipairs(self.entries) do Track(self, entry) end
    Repaint(self)
end

local ShowSamples

-- The session ends; Blizzard's window (shown when this one did not own the
-- session) is muted again once it is hidden, for the next loot.
local function Closed(self)
    self.session, self.own, self.autoLoot = false, false, false
    self.entries, self.bySlot = {}, {}
    HideWindow(self)
    if Wanted(self) then
        MuteNative(self)
    else
        ReleaseNative(self)
    end
    if S.editMode then ShowSamples(self) end
end

------------------------------------------------------------------ row input
local Rows = {}

function Rows.click(row)
    local self, entry = M, row.entry
    if not self.active or not self.revealed or not self.own or not entry or self.bySlot[entry.slot] ~= entry then return end
    if IsModifiedClick() then
        local link = S.PublicText(GetLootSlotLink(entry.slot))
        if link then HandleModifiedItemClick(link) end
        return
    end
    LootSlot(entry.slot)
end

function Rows.enter(row)
    local self, entry = M, row.entry
    if not self.revealed or not self.own or not entry or entry.kind == "money" or NS.Safety.IsForbidden(GameTooltip) then return end
    GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
    if entry.kind == "currency" then
        GameTooltip:SetLootCurrency(entry.slot)
    else
        GameTooltip:SetLootItem(entry.slot)
    end
    GameTooltip:Show()
end

function Rows.leave(row)
    if not NS.Safety.IsForbidden(GameTooltip) and GameTooltip:IsOwned(row) then GameTooltip:Hide() end
end

function Rows.wheel(_, delta)
    if M.revealed then View.Scroll(M.window, delta) end
end

------------------------------------------------------------------ Edit Mode
-- Sample rows to place the fixed window and the feed; a live session or
-- feed entry wins over them.
ShowSamples = function(self)
    local samples = View.Samples()
    local config = self.config
    if not self.session and config.window and config.position ~= CURSOR then
        self.window.entries, self.window.first = samples, 0
        PlaceFixed(self.window.host, config, "point", "x", "y")
        View.Paint(self.window)
    end
    if config.feed and #self.feedEntries == 0 then
        self.feedView.entries = samples
        View.Paint(self.feedView)
    end
end

local function HideSamples(self)
    if not self.revealed then View.Hide(self.window) end
    if #self.feedEntries == 0 then View.Hide(self.feedView) end
end

function M:HideEditPreview()
    HideSamples(self)
end

------------------------------------------------------------------ lifecycle
local function Views(self)
    self.window = self.window or { handlers = Rows }
    self.feedView = self.feedView or { feed = true, entries = self.feedEntries }
    for _, owner in ipairs({ self.window, self.feedView }) do
        owner.config = self.config
        View.Layout(owner)
    end
    self.window.host:EnableMouseWheel(not self.window.inputSuspended)
    self.window.host:SetScript("OnMouseWheel", Rows.wheel)
    PlaceFixed(self.feedView.host, self.config, "feedPoint", "feedX", "feedY")
end

local LOOT_EVENTS = { LOOT_READY = Ready, LOOT_OPENED = Opened, LOOT_SLOT_CLEARED = Cleared,
    LOOT_SLOT_CHANGED = Changed, LOOT_CLOSED = Closed }

function M:Enable()
    self.entries, self.bySlot, self.expected = {}, {}, {}
    self.session, self.own, self.revealed = false, false, false
    self.confirmJob = self.context:Coalesce(CONFIRM_DELAY, Confirm)
    Views(self)
    for event, callback in pairs(LOOT_EVENTS) do self.context:Event(event, callback, IN_COMBAT) end
    -- An open loot window stays Blizzard's until it closes.
    local native = Native()
    if Wanted(self) and not (native and native:IsShown()) then MuteNative(self) end
    if S.editMode then ShowSamples(self) end
end

function M:Refresh()
    Views(self)
    if not Wanted(self) and not self.own then ReleaseNative(self) end
    if Wanted(self) and not self.session then MuteNative(self) end
    if not self.config.feed then
        self.feedEntries, self.expected = {}, {}
        self.feedView.entries = self.feedEntries
    end
    HideSamples(self)
    if self.revealed then Reveal(self, true) end
    PaintFeed(self)
    NextExpiry(self)
    if S.editMode then ShowSamples(self) end
end

-- Turning the module off during a loot session closes that loot: Blizzard's
-- window returns with the release and would keep the muted position.
function M:Disable()
    if self.own and self.session then CloseLoot() end
    self.feedEntries, self.expected = {}, {}
    if self.window then
        self.window.entries = nil
        View.Hide(self.window)
    end
    if self.feedView then
        self.feedView.entries = self.feedEntries
        View.Hide(self.feedView)
    end
    self.session, self.own, self.revealed, self.muted = false, false, false, nil
end

function M:RegisterMovers()
    S.RegisterOwnedMover(ID, "lootwindow", {
        label = "Loot window", order = 630,
        getFrame = function() return self.window and self.window.host end,
        xKey = "x", yKey = "y", pointKey = "point",
        point = function() return NS.AnchorPoints[self.config.point] or "CENTER" end,
        visible = function() return self.config.window == true and self.config.position ~= CURSOR end,
        quickPosition = true, historyKeys = { "width", "rowHeight", "scale" },
        sizeKeys = { "width", "rowHeight", "scale" },
    })
    S.RegisterOwnedMover(ID, "lootfeed", {
        label = "Loot feed", order = 631,
        getFrame = function() return self.feedView and self.feedView.host end,
        xKey = "feedX", yKey = "feedY", pointKey = "feedPoint",
        point = function() return NS.AnchorPoints[self.config.feedPoint] or "CENTER" end,
        visible = function() return self.config.feed == true end,
        quickPosition = true, historyKeys = { "scale" }, sizeKeys = { "scale" },
    })
end

------------------------------------------------------------------ options preview
-- The interactive preview of the options page draws the sample rows with
-- the profile's settings, also while the module is off.
function S.DrawLootWindowPreview(parent, config, _, viewport)
    local view = parent.suiteLootWindowPreview
    if not view then
        view = { previewParent = parent, entries = View.Samples() }
        parent.suiteLootWindowPreview = view
    end
    view.config, view.previewViewport = config, viewport
    View.Layout(view)
    view.host:Show()
    return view.host
end

function S.MoveLootWindowPreviewLayer(view, key, x, y)
    View.PlaceLayer(view, key, x, y)
end

function S.HideLootWindowPreview(parent)
    local view = parent.suiteLootWindowPreview
    if view and view.host then view.host:Hide() end
end

S.Install(ID, M)

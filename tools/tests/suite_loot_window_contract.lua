-- Minimal loot window (MSUF_Suite_QualityOfLife/LootWindow.lua and
-- LootWindowView.lua): the catalog with its preview layers, the session
-- decision on LOOT_READY (own window, gamepad, master loot, unreadable slots), Blizzard's
-- window muted only while hidden or owned, rows from every slot kind, a
-- player click as the only LootSlot, modified clicks and tooltips, the feed
-- from counts that actually rose (not slots another player cleared), feed
-- merging, filters and expiry, Edit Mode samples, disable during a session,
-- and the options preview's layer moves.
local root = assert(arg[1], "repository root required")
local Support = dofile(root .. "/tools/tests/suite_test_support.lua")
local checks = 0
local function Check(value, message)
    assert(value, message)
    checks = checks + 1
end

------------------------------------------------------------------ widgets
local Widget = {}
Widget.__index = Widget
local function New(kind, parent)
    return setmetatable({ kind = kind, parent = parent, shown = true, points = {}, scripts = {}, alpha = 1,
        scale = 1, mouse = false, text = "", width = 0, height = 0 }, Widget)
end
function Widget:Show() self.shown = true end
function Widget:Hide()
    if self.shown and self.scripts.OnHide then self.scripts.OnHide(self) end
    self.shown = false
end
function Widget:SetShown(value) if value then self:Show() else self:Hide() end end
function Widget:CreateAnimationGroup()
    local animation = {}
    function animation:SetFromAlpha(value) self.from = value end
    function animation:SetToAlpha(value) self.to = value end
    function animation:SetDuration(value) self.duration = value end
    function animation:GetProgress() return self.progress or 0 end
    local group = { animation = animation, plays = 0 }
    function group:CreateAnimation(kind)
        assert(kind == "Alpha")
        return animation
    end
    function group:SetScript(event, callback)
        assert(event == "OnFinished")
        self.finish = callback
    end
    function group:Play()
        self.playing, self.plays, animation.progress = true, self.plays + 1, 0
    end
    function group:IsPlaying() return self.playing end
    function group:Stop() self.playing = false end
    function group:Finish()
        assert(self.playing)
        self.playing = false
        self.finish()
    end
    self.group = group
    return group
end
function Widget:IsShown() return self.shown end
function Widget:IsVisible() return self.shown and (not self.parent or self.parent:IsVisible()) end
function Widget:GetParent() return self.parent end
function Widget:SetParent(parent) self.parent = parent end
function Widget:IsProtected() return false end
function Widget:IsForbidden() return false end
function Widget:ClearAllPoints() self.points = {} end
function Widget:SetPoint(...) self.points[#self.points + 1] = { ... } end
function Widget:SetAllPoints(region) self.points = { { "ALL", region } } end
function Widget:SetSize(width, height) self.width, self.height = width, height end
function Widget:SetWidth(width) self.width = width end
function Widget:SetHeight(height) self.height = height end
function Widget:GetHeight() return self.height end
function Widget:GetWidth() return self.width end
function Widget:SetScale(scale) self.scale = scale end
function Widget:GetScale() return self.scale end
function Widget:GetEffectiveScale() return self.scale * (self.parent and self.parent:GetEffectiveScale() or 1) end
function Widget:EnableMouse(value) self.mouse = value end
function Widget:EnableMouseWheel(value) self.wheel = value end
function Widget:RegisterForClicks(...) self.clicks = { ... } end
function Widget:SetScript(event, callback) self.scripts[event] = callback end
function Widget:SetFrameStrata(strata) self.strata = strata end
function Widget:SetClampedToScreen(value) self.clamped = value end
function Widget:SetColorTexture(r, g, b, a) self.color = { r, g, b, a } end
function Widget:SetTexture(texture) self.texture = texture end
function Widget:SetTexCoord() end
function Widget:SetVertexColor(r, g, b) self.vertex = { r, g, b } end
function Widget:SetText(text) self.text = text end
function Widget:GetText() return self.text end
function Widget:GetStringWidth() return type(self.text) == "string" and #self.text * 6 or 0 end
function Widget:SetTextColor(r, g, b) self.textColor = { r, g, b } end
function Widget:SetJustifyH(value) self.justify = value end
function Widget:SetWordWrap() end

UIParent = New("Frame")
local muteHost
local S = { editMode = false, instances = {}, configs = {}, movers = {}, pad = false }
S.Public = function(value) return not (type(value) == "table" and value.secret) end
S.Finite = function(value)
    return S.Public(value) and type(value) == "number" and value == value and math.abs(value) < math.huge
end
S.PublicText = function(value)
    return S.Public(value) and type(value) == "string" and value ~= "" and value or nil
end
S.Text = function(text) return text end
S.CreateFrame = function(kind, _, parent) return New(kind, parent) end
S.CreateTexture = function(parent) return New("Texture", parent) end
S.CreateFontString = function(parent) return New("FontString", parent) end
S.PlaceEdges = function(set, owner, width, r, g, b)
    for _, edge in ipairs(set) do
        edge.shown, edge.color = width > 0, { r, g, b }
    end
end
S.QoLStyle = function() return { background = "000000", text = "ffffff", muted = "aaaaaa" } end
S.RGB = function(hex) return tonumber(hex:sub(1, 2), 16) / 255, tonumber(hex:sub(3, 4), 16) / 255, 1 end
S.ResolveFont = function() return nil end
S.GlobalFontPath = function() return "font" end
S.QoLStyleText = function(fontString, _, font, size) fontString.font, fontString.size = font, size end
S.GamepadUI = function() return S.pad end
S.Config = function(id) return S.configs[id] or {} end
S.RegisterOwnedMover = function(id, element, spec) S.movers[element] = spec end
S.Install = function(id, module) module.id = id S.instances[id] = module end
local NS = { AnchorPoints = { "TOPLEFT", "TOP", "TOPRIGHT", "LEFT", "CENTER" },
    Safety = { IsForbidden = function(frame) return frame.forbidden == true end } }
NS.Dispatch = function(fn, ...) return fn(...) end
NS.Finish = function(fn, ...) return fn(...) end
local clock = Support.Clock(100)
local NewContext = Support.ModuleTimers(root, S, NS)

------------------------------------------------------------------ client
local secret = { secret = true }
local slots, money, counts, currencies, calls = {}, 1000, {}, {}, { loot = {}, close = 0, links = {}, tips = {} }
local modified = false
Enum = { LootSlotType = { None = 0, Item = 1, Money = 2, Currency = 3 } }
ITEM_QUALITY_COLORS = { [1] = { r = 1, g = 1, b = 1 }, [3] = { r = 0, g = .4, b = 1 } }
for quality = 0, 7 do _G["ITEM_QUALITY" .. quality .. "_DESC"] = "Quality " .. quality end
ITEM_BIND_QUEST, MONEY = "Quest Item", "Money"
-- Retail and Forever expose the formatter through C_CurrencyInfo.
GetCoinTextureString = nil
local formattedCoins = {}
GetCursorPosition = function() return 500, 400 end
GetNumLootItems = function() return #slots end
GetLootSlotType = function(slot)
    local record = slots[slot]
    if not record then return Enum.LootSlotType.None end
    return record.kindSecret and secret or Enum.LootSlotType[record.kind]
end
GetLootSlotInfo = function(slot)
    local r = slots[slot]
    return r.icon, r.name, r.quantity or 1, r.currencyID, r.quality, r.locked, r.questItem, r.questID, r.active
end
GetLootSlotLink = function(slot) return slots[slot] and slots[slot].link end
CurrencyContainerUtil = { GetCurrencyContainerInfo = function(_, quantity, name, texture, quality)
    return name .. " (currency)", texture, quantity, quality
end }
C_Item = { GetItemInfoInstant = function(link) return tonumber(link:match("item:(%d+)")) end,
    GetItemCount = function(itemID) return counts[itemID] or 0 end }
C_CurrencyInfo = {
    GetCurrencyInfo = function(id) return { quantity = currencies[id] or 0 } end,
    GetCoinTextureString = function(copper)
        formattedCoins[#formattedCoins + 1] = copper
        return copper .. "c"
    end,
}
local lootMethod = 0
Enum.LootMethod = { Freeforall = 0, Masterlooter = 2 }
C_PartyInfo = { GetLootMethod = function() return lootMethod end }
GetMoney = function() return money end
LootSlot = function(slot) calls.loot[#calls.loot + 1] = slot end
CloseLoot = function() calls.close = calls.close + 1 end
IsModifiedClick = function() return modified end
HandleModifiedItemClick = function(link) calls.links[#calls.links + 1] = link end
GameTooltip = New("Frame")
function GameTooltip:SetOwner(owner) self.owner = owner end
function GameTooltip:IsOwned(owner) return self.owner == owner end
function GameTooltip:SetLootItem(slot) calls.tips[#calls.tips + 1] = "item" .. slot end
function GameTooltip:SetLootCurrency(slot) calls.tips[#calls.tips + 1] = "currency" .. slot end
LootFrame = New("Frame", UIParent)
LootFrame.shown = false

------------------------------------------------------------------ catalog
local catalogNS = { Client = { isForever = false }, Text = function(text) return text end }
for _, file in ipairs({ "SuiteCatalog", "Catalog/QualityOfLife", "Catalog/QualityOfLifeIndicators", "Catalog/LootWindow" }) do
    assert(loadfile(root .. "/MSUF_Suite/Core/" .. file .. ".lua"))("MSUF_Suite", catalogNS)
end
local spec = catalogNS.SuiteCatalog.lootWindow
local battle = catalogNS.SuiteCatalog.battleRes
Check(spec.optIn and spec.defaultEnabled == false and spec.page == "suite_qualityOfLife" and spec.editElement == "lootfeed",
    "the loot window must be an opt-in Quality of Life module with an Edit Mode feed")
Check(spec.conflicts[1] == "XLoot_Frame" and spec.conflicts[2] == "Butsu", "the loot window must yield to other loot frames")
Check(#spec.layers == 5 and spec.layers[1].section == "loot_window_background", "the loot window lost a preview layer")
Check(spec.rules.backgroundShown.default == false and not spec.rules.backgroundX and spec.rules.iconX.min == -120,
    "the background must start hidden and fixed; the other layers move")
Check(battle.rules.iconShown.default and battle.rules.iconX.max == 160 and battle.rules.iconY.min == -120
    and battle.layers[1].section == "battle_res_background", "the shared layer builder changed battle resurrection")
Check(spec.rules.feedRows.enableKey == "feed" and spec.rules.width.enableKey == "window" and spec.rules.x.hidden,
    "feed and window settings must follow their switches; positions belong to Edit Mode")
local config = {}
for key, rule in pairs(spec.rules) do config[key] = rule.default end
for key, owner in pairs({ fadeIn = "window", fadeOut = "window", feedFadeIn = "feed", feedFadeOut = "feed" }) do
    local rule = spec.rules[key]
    Check(rule and rule.enableKey == owner and rule.min == 0 and rule.max == 2 and rule.default > 0,
        "each fade must be configurable, with zero off")
    config[key] = 0
end
S.configs.lootWindow = config
S.configs.loot = { quickLoot = false }

------------------------------------------------------------------ module
local muted = {}
local context = NewContext("lootWindow", nil, { callbacks = {} })
function context:Event(event, callback) self.callbacks[event] = Support.EventCallback(callback) end
function context:RemoveEvent(event) self.callbacks[event] = nil end
function context:Mute(frame)
    muteHost = muteHost or New("Frame", UIParent)
    muted[frame], frame.parent = frame.parent, muteHost
    return true
end
function context:Unmute(frame)
    if muted[frame] then frame.parent, muted[frame] = muted[frame], nil end
end
local P = { NS = NS, Suite = S }
for _, file in ipairs({ "LootWindowView", "LootWindow" }) do
    assert(loadfile(root .. "/MSUF_Suite_QualityOfLife/" .. file .. ".lua"))("MSUF_Suite_QualityOfLife", P)
end
local M = S.instances.lootWindow
NewContext("lootWindow", M, context)
M.config, M.context, M.active = config, context, true
local function Emit(event, ...)
    local callback = context.callbacks[event]
    if callback then callback(M, event, ...) end
end
local function IsMuted() return LootFrame.parent == muteHost end
local function Rows(owner)
    local rows = {}
    for _, row in ipairs(owner.rows) do
        if row.shown then rows[#rows + 1] = row end
    end
    return rows
end

M:Enable()
Check(IsMuted() and M.window.host.strata == "HIGH" and M.window.host.clamped, "a hidden Blizzard window was not muted")
for _, event in ipairs({ "LOOT_READY", "LOOT_OPENED", "LOOT_SLOT_CLEARED", "LOOT_SLOT_CHANGED", "LOOT_CLOSED" }) do
    Check(context.callbacks[event], "missing " .. event)
end

-- A session with every kind of slot.
slots = {
    { kind = "Item", name = "Daggerspine Scale", icon = 1, quality = 1, questItem = true, link = "item:11" },
    { kind = "Money", name = "61 Copper", icon = 2 },
    { kind = "Item", name = "Linen Cloth", icon = 3, quality = 1, quantity = 3, link = "item:12" },
    { kind = "Currency", name = "Crest", icon = 4, quality = 3, currencyID = 7, quantity = 5, link = "currency:7" },
    { kind = "Item", name = secret, icon = secret, quality = secret, locked = true, link = "item:13", questID = 5, active = false },
}
Emit("LOOT_READY", false)
Emit("LOOT_OPENED", false)
local rows = Rows(M.window)
Check(M.own and IsMuted() and M.window.host.shown and #rows == 5, "the loot window did not show every slot")
Check(rows[1].subtitle.text == "Quest Item" and rows[1].subtitle.textColor[1] == 1 and rows[1].twoLines,
    "a quest item lost its quest line")
Check(rows[2].name.text == "Money" and rows[2].count.text == "61 Copper" and not rows[2].twoLines,
    "money must read as Money with its coins")
Check(#formattedCoins == 0, "the live window should reuse the loot slot's coin text")
Check(rows[3].count.text == "3" and rows[3].subtitle.text == "Quality 1", "a stack lost its amount or quality")
Check(rows[4].name.text == "Crest (currency)" and rows[4].count.text == "5", "currency was not resolved")
Check(rows[5].name.text == secret and rows[5].icon.texture == secret and rows[5].quest.shown
    and rows[5].icon.vertex[2] < .5, "a secret name or icon must reach only the setters; quest starts and locks show")
Check(M.window.host.points[1][1] == "TOPLEFT" and M.window.host.points[1][4] == 500 - 16,
    "the window did not open at the cursor")

-- Only a click loots; a modified click links, hovering shows the slot.
rows[3].scripts.OnClick(rows[3], "LeftButton")
modified = true
rows[1].scripts.OnClick(rows[1], "LeftButton")
modified = false
rows[4].scripts.OnEnter(rows[4])
rows[2].scripts.OnEnter(rows[2])
Check(#calls.loot == 1 and calls.loot[1] == 3 and calls.links[1] == "item:11", "a click must loot only its own slot")
Check(#calls.tips == 1 and calls.tips[1] == "currency4" and GameTooltip.owner == rows[4], "loot tooltips wrong")
rows[4].scripts.OnLeave(rows[4])

-- The feed shows only what reached the bags.
counts[12] = 3
Emit("LOOT_SLOT_CLEARED", 3)
Emit("LOOT_SLOT_CLEARED", 1)
money = money + 61
Emit("LOOT_SLOT_CLEARED", 2)
clock.Advance(.3)
local feed = Rows(M.feedView)
Check(#Rows(M.window) == 2, "cleared slots stayed in the window")
Check(#feed == 2 and feed[1].name.text == "Money" and feed[1].count.text == "61c" and feed[2].count.text == "3",
    "the feed must list what arrived, newest first")
Check(#formattedCoins == 1 and formattedCoins[1] == 61, "a confirmed money gain should be formatted once")
clock.Advance(5)
Check(#M.expected == 0 and #Rows(M.feedView) == 2, "an item another player took must expire unseen")
currencies[7] = 5
Emit("LOOT_SLOT_CLEARED", 4)
clock.Advance(.3)
Check(#Rows(M.feedView) == 3 and Rows(M.feedView)[1].name.text == "Crest (currency)", "currency gain missing")
Emit("LOOT_CLOSED")
Check(not M.window.host.shown and IsMuted() and not M.session, "closing must hide the window and keep Blizzard muted")
-- The next corpse at once: the last corpse's gain still counts.
slots = { { kind = "Item", name = "Silk Cloth", icon = 6, quality = 1, link = "item:16" } }
Emit("LOOT_READY", true)
Emit("LOOT_OPENED", true)
Emit("LOOT_SLOT_CLEARED", 1)
Emit("LOOT_CLOSED")
slots = { { kind = "Item", name = "Silk Cloth", icon = 6, quality = 1, link = "item:16" } }
Emit("LOOT_READY", true)
counts[16] = 2
clock.Advance(.3)
Check(Rows(M.feedView)[1].name.text == "Silk Cloth" and Rows(M.feedView)[1].count.text == "2",
    "looting the next corpse at once lost the previous gain")
Emit("LOOT_CLOSED")
clock.Advance(config.feedSeconds)
Check(not M.feedView.host.shown and #M.feedEntries == 0, "feed entries must expire")

-- The same item again adds to its feed entry; filters apply.
config.feedQuality = 1
config.feedMoney = false
M:Refresh()
slots = { { kind = "Item", name = "Linen Cloth", icon = 3, quality = 1, quantity = 2, link = "item:12" },
    { kind = "Item", name = "Linen Cloth", icon = 3, quality = 1, quantity = 2, link = "item:12" },
    { kind = "Item", name = "Grey", icon = 5, quality = 0, link = "item:14" }, { kind = "Money", name = "1 Silver" } }
Emit("LOOT_READY", true)
Emit("LOOT_OPENED", true)
Check(not M.window.host.shown, "auto loot must wait before showing the window")
counts[12], counts[14], money = 7, 1, money + 100
for slot = 1, 4 do Emit("LOOT_SLOT_CLEARED", slot) end
clock.Advance(.4)
feed = Rows(M.feedView)
Check(#feed == 1 and feed[1].count.text == "4" and not M.window.host.shown,
    "two stacks must merge; poor quality and money stay out when filtered")
Check(#formattedCoins == 1, "filtered money should not be formatted")
Emit("LOOT_CLOSED")

-- Gamepad mode and unreadable slots stay with Blizzard's window.
S.pad = true
slots = { { kind = "Item", name = "Thing", icon = 1, quality = 1, link = "item:15" } }
Emit("LOOT_READY", false)
Check(not M.own and not IsMuted(), "gamepad mode must release Blizzard's window before it opens")
Emit("LOOT_OPENED", false)
Check(not M.window.host.shown, "the window showed beside Blizzard's")
Emit("LOOT_CLOSED")
S.pad = false
M:Refresh()
Check(IsMuted(), "Blizzard's window was not muted again after the session")
lootMethod = 2
Emit("LOOT_READY", false)
Check(not M.own and not IsMuted(), "master loot must stay with Blizzard's window, which records the clicked slot")
Emit("LOOT_CLOSED")
lootMethod = 0
Check(IsMuted(), "Blizzard's window was not muted again after master loot")
slots[1].kindSecret = true
Emit("LOOT_READY", false)
Check(not M.own and not IsMuted(), "an unreadable slot must leave the session to Blizzard")
Emit("LOOT_CLOSED")
slots[1].kindSecret = nil
config.window = false
M:Refresh()
Check(not IsMuted(), "switching the window off must give Blizzard's window back")
config.window = true
M:Refresh()

-- Edit Mode samples for a fixed window and the feed.
clock.Advance(config.feedSeconds + 1)
Check(#M.feedEntries == 0 and not M.feedView.host.shown, "the merged feed entry did not expire")
config.position, config.feedMoney = 2, true
S.editMode = true
M:Refresh()
Check(M.window.host.shown and #Rows(M.window) == 4 and M.feedView.host.shown, "Edit Mode samples missing")
rows = Rows(M.window)
Check(rows[4].count.text == "12361c" and #formattedCoins == 2, "Edit Mode should share the formatted sample coins")
rows[1].scripts.OnClick(rows[1], "LeftButton")
Check(#calls.loot == 1, "a sample row looted")
M:HideEditPreview()
S.editMode = false
Check(not M.window.host.shown and not M.feedView.host.shown, "samples stayed after Edit Mode")
M:RegisterMovers()
Check(S.movers.lootwindow.visible() and S.movers.lootfeed.xKey == "feedX", "movers missing")
config.position = 1
Check(not S.movers.lootwindow.visible(), "the cursor window offered a mover")

-- Disabling during an owned session closes that loot.
slots = { { kind = "Item", name = "Thing", icon = 1, quality = 1, link = "item:15" } }
Emit("LOOT_READY", false)
Emit("LOOT_OPENED", false)
M:Disable()
Check(calls.close == 1 and not M.window.host.shown, "disable left an owned loot session open")

-- The options preview draws samples and moves one element in every row.
local stage = New("Frame", UIParent)
local host = S.DrawLootWindowPreview(stage, config, nil, { width = 300, height = 200, scale = 1 })
local view = stage.suiteLootWindowPreview
Check(host == view.host and host.parent == stage and #Rows(view) == 4 and view.bounds.icon.shown,
    "the preview did not draw its rows")
Check(Rows(view)[4].count.text == "12361c" and #formattedCoins == 3, "the options preview lost its formatted sample coins")
S.MoveLootWindowPreviewLayer(view, "icon", 10, -2)
for _, row in ipairs(Rows(view)) do
    Check(row.icon.points[1][4] == 14 and row.icon.points[1][5] == -2, "a drag must move the icon in every row")
end
config.backgroundShown = true
S.DrawLootWindowPreview(stage, config, nil, { width = 300, height = 200, scale = 1 })
Check(view.panel.shown and view.panel.color[4] == config.backgroundOpacity / 100, "the background layer did not show")
Check(#formattedCoins == 3, "layout changes should reuse the options preview's formatted sample coins")
S.HideLootWindowPreview(stage)
Check(not view.host.shown, "the preview stayed after hiding")

-- Native animations run only on a visibility transition. A departing list
-- keeps its artwork until the animation ends and gives its click area back immediately.
Check(not M.window.host.group and not M.feedView.host.group and not host.group,
    "disabled fades and the editor should never allocate animations")
config.fadeIn, config.fadeOut, config.feedFadeIn, config.feedFadeOut = .4, .7, .3, .6
M:Enable()
Check(not M.window.host.shown, "enabling must not bring back loot from the last session")
slots = { { kind = "Item", name = "Silk Cloth", icon = 6, quality = 1, link = "item:16" } }
Emit("LOOT_READY", false)
Emit("LOOT_OPENED", false)
local window = M.window.host.group
local liveRow = Rows(M.window)[1]
Check(window and window.plays == 1 and window.animation.from == 0 and window.animation.to == 1
    and window.animation.duration == .4 and liveRow.mouse, "live loot must fade in immediately with active input")
Emit("LOOT_SLOT_CHANGED", 1)
Check(window.plays == 1, "slot updates must not restart the fade")
liveRow.scripts.OnEnter(liveRow)
Check(GameTooltip:IsShown() and GameTooltip:IsOwned(liveRow), "the test loot row must have an open tooltip")
window.animation.progress = .5
Emit("LOOT_CLOSED")
Check(window.plays == 2 and window.animation.from == .5 and window.animation.to == 0
    and window.animation.duration == .7 and liveRow.shown and not liveRow.mouse and not liveRow.wheel
    and not M.window.host.wheel and not GameTooltip:IsShown(), "closing must immediately release input and reverse the fade")
window.animation.progress = .5
Emit("LOOT_READY", false)
Emit("LOOT_OPENED", false)
Check(window.plays == 3 and window.animation.from == .25 and window.animation.to == 1
    and liveRow.mouse and liveRow.wheel and M.window.host.wheel, "a new session must reverse a departure and restore input")
window:Finish()
counts[16] = counts[16] + 1
Emit("LOOT_SLOT_CLEARED", 1)
Emit("LOOT_CLOSED")
Check(window.plays == 4 and window.animation.duration == .7 and M.window.host.shown,
    "clearing the last slot and closing should start just one departure")
window:Finish()
Check(not M.window.host.shown, "the window must hide when its fade out finishes")
clock.Advance(.3)
local feedFade = M.feedView.host.group
Check(feedFade and feedFade.plays == 1 and feedFade.animation.duration == .3 and feedFade.animation.to == 1,
    "the confirmed loot feed must use its own fade-in duration")
feedFade:Finish()
clock.Advance(config.feedSeconds)
Check(feedFade.plays == 2 and feedFade.animation.duration == .6 and feedFade.animation.to == 0
    and M.feedView.host.shown and #Rows(M.feedView) == 1, "feed expiry must retain the last row during its fade")
feedFade:Finish()
Check(not M.feedView.host.shown and #M.feedEntries == 0, "the expired feed must hide after the fade")
Emit("LOOT_READY", false)
Emit("LOOT_OPENED", false)
M:Disable()
Check(not window:IsPlaying() and not M.window.host.shown, "disabling the module must stop its fade immediately")
print("suite_loot_window_contract: ok (" .. checks .. " checks)")

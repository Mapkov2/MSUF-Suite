local root = assert(arg[1], "repository root required")
local checks = 0
local function Check(value, message) assert(value, message); checks = checks + 1 end

local function Region()
    local r = { shown = true, alpha = 1, points = {} }
    function r:SetAllPoints() end
    function r:SetPoint(...) self.points[#self.points + 1] = { ... } end
    function r:ClearAllPoints() self.points = {} end
    function r:GetPoint(index) return unpack(self.points[index or 1] or {}) end
    function r:GetNumPoints() return #self.points end
    function r:SetSize(w, h) self.width, self.height = w, h end
    function r:SetWidth(w) self.width = w end
    function r:SetHeight(h) self.height = h; self.heightWrites = (self.heightWrites or 0) + 1 end
    function r:GetHeight() return self.height end
    function r:GetAlpha() return self.alpha end
    function r:SetAlpha(value) self.alpha = value end
    function r:SetColorTexture(...) self.color = { ... } end
    function r:SetTextColor(...) self.textColor = { ... } end
    function r:SetText(value) self.text = value end
    function r:SetFont(...) self.font = { ... } end
    function r:GetFont() return unpack(self.font) end
    function r:Show() self.shown = true end
    function r:Hide() self.shown = false end
    function r:IsShown() return self.shown end
    function r:EnableMouse() end
    function r:SetFrameLevel(level) self.level = level end
    function r:GetFrameLevel() return 5 end
    function r:SetBackdrop(value) self.backdrop = value end
    function r:SetBackdropColor() end
    function r:SetBackdropBorderColor() end
    return r
end

local function ScriptFrame()
    local frame = Region()
    frame.shown, frame.scripts = false, {}
    function frame:HookScript(name, callback)
        local old = self.scripts[name]
        self.scripts[name] = function(...) if old then old(...) end; callback(...) end
    end
    function frame:Show()
        local was = self.shown
        self.shown = true
        if not was and self.scripts.OnShow then self.scripts.OnShow(self) end
    end
    function frame:Hide()
        local was = self.shown
        self.shown = false
        if was and self.scripts.OnHide then self.scripts.OnHide(self) end
    end
    function frame:IsProtected() return false end
    return frame
end

hooksecurefunc = function(owner, key, callback)
    if type(owner) == "string" then
        local original = _G[owner]
        _G[owner] = function(...) original(...); key(...) end
        return
    end
    local original = owner[key]
    owner[key] = function(...) original(...); callback(...) end
end

UIParent = Region()
GetAppropriateTopLevelParent = function() return UIParent end
local sounds = {}
PlaySound = function(kit) sounds[#sounds + 1] = kit end
SOUNDKIT = { READY_CHECK = 8960 }

-- StaticPopup1-4 as Blizzard_StaticPopup builds them: StaticPopup_Show places
-- the shown chain (StaticPopup_SetUpPosition), shows the dialog and then sizes
-- it (GameDialogMixin:Resize).
local shown = {}
for index = 1, 4 do
    local dialog = ScriptFrame()
    dialog.index, dialog.height = index, 72
    dialog.Text = Region()
    dialog.Text.font = { "Fonts\\FRIZQT__.TTF", 12, "" }
    dialog.BG = Region()
    dialog.Button1 = Region()
    function dialog:GetButton1() return self.Button1 end
    -- GameDialogMixin:Resize lays the dialog out and sets its height again.
    function dialog:Resize() self.height = self.lines and 72 + self.lines * 14 or 72 end
    dialog:HookScript("OnHide", function(self)
        for i = #shown, 1, -1 do if shown[i] == self then table.remove(shown, i) end end
    end)
    _G["StaticPopup" .. index] = dialog
end
local function SetUpPosition()
    local previous
    for _, dialog in ipairs(shown) do
        dialog:ClearAllPoints()
        if previous then
            dialog:SetPoint("TOP", previous, "BOTTOM", 0, 0)
        else
            dialog:SetPoint("TOP", UIParent, "TOP", 0, dialog.topOffset or -135)
        end
        previous = dialog
    end
end
local function ShowPopup(which, lines)
    for index = 1, 4 do
        local dialog = _G["StaticPopup" .. index]
        if not dialog:IsShown() then
            dialog.which, dialog.lines = which, lines
            shown[#shown + 1] = dialog
            SetUpPosition()
            dialog:Show()
            dialog:Resize()
            return dialog
        end
    end
end

-- Loot toasts: AlertFrameSystems.lua handed the setup function to the queued
-- loot system at load; the queue calls that reference. Bonus rolls call the
-- global by name.
LootWonAlertFrame_SetUp = function(frame, link) frame.hyperlink = link end
LootAlertSystem = { setUpFunction = LootWonAlertFrame_SetUp }
function LootAlertSystem:ShowAlert(...)
    local frame = ScriptFrame()
    frame:Show()
    self.setUpFunction(frame, ...)
    return frame
end
BonusRollLootWonFrame = ScriptFrame()
MoneyWonAlertFrame_SetUp = function(frame, amount) frame.amount = amount end
MoneyWonAlertSystem = { setUpFunction = MoneyWonAlertFrame_SetUp }
function MoneyWonAlertSystem:ShowAlert(...)
    local frame = ScriptFrame()
    frame:Show()
    self.setUpFunction(frame, ...)
    return frame
end
BonusRollMoneyWonFrame = ScriptFrame()
ITEM_QUALITY4_DESC, ITEM_QUALITY3_DESC = "Epic", "Rare"
ITEM_QUALITY_COLORS = { [3] = { r = 0, g = .44, b = .87 }, [4] = { r = .64, g = .21, b = .93 } }
-- "late" is an item the client has no data for until lateCached: GetItemInfo
-- returns nothing, GetItemInfoInstant always knows the item ID.
local lateCached = false
local ITEM_IDS = { epic = 10, rare = 11, late = 12 }
C_Item = { GetItemInfo = function(link)
    if link == "epic" then return "Epic thing", link, 4 end
    if link == "rare" then return "Rare thing", link, 3 end
    if link == "late" and lateCached then return "Late thing", link, 4 end
end, GetItemInfoInstant = function(link) return ITEM_IDS[link] end }

local S, movers, modules = {}, {}, {}
S.Public = function(value) return value ~= "secret" end
S.PublicText = function(value) return S.Public(value) and type(value) == "string" and value ~= "" and value or nil end
S.Finite = function(value) return S.Public(value) and type(value) == "number" and value == value end
S.Text = function(value) return value end
S.SetFont = function(region, ...) region:SetFont(...) end
-- Suite-created regions remember their parent, so a test can see whether
-- the module reached a Blizzard frame at all.
local created = {}
local function Created(parent)
    local region = Region()
    region.parent = parent
    created[#created + 1] = region
    return region
end
local function RegionsOn(frame)
    local count = 0
    for _, region in ipairs(created) do if region.parent == frame then count = count + 1 end end
    return count
end
S.CreateFrame = function(_, _, parent) return Created(parent) end
S.CreateTexture = function(parent) return Created(parent) end
S.CreateFontString = S.CreateTexture
S.RegisterOwnedMover = function(id, element, spec) movers[id] = { element = element, spec = spec } return true end
S.Install = function(id, module) modules[id] = module end
local combat = false
local NS = { Safety = { IsForbidden = function() return false end }, IsCombatLocked = function() return combat end }
assert(loadfile(root .. "/MSUF_Suite_QualityOfLife/PopupAttention.lua"))("test", { NS = NS, Suite = S })
local popup = modules.popupAttention
popup.active = true
popup.context = { events = {}, Event = function(self, event, fn) self.events[event] = fn end,
    RemoveEvent = function(self, event) self.events[event] = nil end }
popup.config = { skin = false, dialogFont = false, fontSize = 16, minHeight = 0, move = false, x = 50, y = 80,
    reviveCue = 2, reviveButton = true, lootQualityName = true, moneyToastFrame = true }
popup:Enable()
popup:Enable()
popup:RegisterMovers() -- the controller registers movers after Enable

-- Loot toasts.
local toast = LootAlertSystem:ShowAlert("epic", 1)
Check(RegionsOn(toast) > 0, "a queued loot toast never reached the module")
local label = popup.qualityLabels[toast]
Check(label and label.shown and label.text == "Epic" and label.textColor[1] == .64,
    "a queued loot toast did not name its quality")
local currency = LootAlertSystem:ShowAlert("epic", 1, nil, nil, nil, true)
Check(not popup.qualityLabels[currency] or not popup.qualityLabels[currency].shown, "a currency toast got a quality name")
LootWonAlertFrame_SetUp(BonusRollLootWonFrame, "rare", 1)
Check(popup.qualityLabels[BonusRollLootWonFrame].text == "Rare", "the bonus roll toast did not name its quality")
-- An item without client data yet names its quality once the data arrives.
local late = LootAlertSystem:ShowAlert("late", 1)
local arrived = popup.context.events.GET_ITEM_INFO_RECEIVED
Check(arrived and not (popup.qualityLabels[late] and popup.qualityLabels[late].shown),
    "a toast for an uncached item did not wait for its data")
arrived(popup, "GET_ITEM_INFO_RECEIVED", 99, true)
Check(popup.context.events.GET_ITEM_INFO_RECEIVED, "another item's data ended the wait")
lateCached = true
arrived(popup, "GET_ITEM_INFO_RECEIVED", 12, true)
Check(popup.qualityLabels[late] and popup.qualityLabels[late].shown and popup.qualityLabels[late].text == "Epic"
    and not popup.context.events.GET_ITEM_INFO_RECEIVED, "the quality of an uncached item was dropped")
lateCached = false
local gone = LootAlertSystem:ShowAlert("late", 1)
gone:Hide()
popup.context.events.GET_ITEM_INFO_RECEIVED(popup, "GET_ITEM_INFO_RECEIVED", 12, true)
Check(not popup.context.events.GET_ITEM_INFO_RECEIVED and not popup.qualityLabels[gone],
    "a hidden toast kept waiting or was labelled")
popup.config.lootQualityName = false
popup:Refresh()
Check(not label.shown, "turning the quality name off kept a visible label")
local quiet = LootAlertSystem:ShowAlert("epic", 1)
Check(not popup.qualityLabels[quiet], "a toast got a label while the option was off")
popup.config.lootQualityName = true

-- Money toasts, queued and from a bonus roll.
local money = MoneyWonAlertSystem:ShowAlert(12345)
Check(popup.moneyFrames[money] and popup.moneyFrames[money].shown and money.amount == 12345,
    "a queued money toast got no gold frame")
MoneyWonAlertFrame_SetUp(BonusRollMoneyWonFrame, 500)
Check(popup.moneyFrames[BonusRollMoneyWonFrame].shown, "the bonus roll money toast got no gold frame")
popup.config.moneyToastFrame = false
popup:Refresh()
Check(not popup.moneyFrames[money].shown, "turning the money frame off kept it")
local plainMoney = MoneyWonAlertSystem:ShowAlert(1)
Check(not popup.moneyFrames[plainMoney], "a money toast got a frame while the option was off")
popup.config.moneyToastFrame = true

-- Dialog look and font, each only with its option; Blizzard's otherwise stay.
local plain = ShowPopup("CONFIRM_SOMETHING", 1)
Check(plain.Text.font[2] == 12 and plain.BG.alpha == 1, "dialogs were restyled with the Suite look off")
plain:Hide()
popup.config.skin = true
popup:Refresh()
local panelOnly = ShowPopup("CONFIRM_SOMETHING", 1)
Check(panelOnly.Text.font[2] == 12 and panelOnly.BG.alpha == 0 and popup.looks[panelOnly].panel.shown,
    "the Suite look did not leave the font alone")
panelOnly:Hide()
popup.config.skin, popup.config.dialogFont = false, true
popup:Refresh()
local fontOnly = ShowPopup("CONFIRM_SOMETHING", 1)
Check(fontOnly.Text.font[2] == 16 and fontOnly.Text.font[3] == "OUTLINE" and fontOnly.BG.alpha == 1
    and not popup.looks[fontOnly].panel.shown, "the Suite font did not work without the look")
fontOnly:Hide()
popup.config.skin = true
popup:Refresh()
local styled = ShowPopup("CONFIRM_SOMETHING", 1)
Check(styled.Text.font[2] == 16 and styled.BG.alpha == 0 and popup.looks[styled].panel.shown,
    "the Suite dialog look and font were not applied together")
styled:Hide()
Check(styled.Text.font[2] == 12 and styled.BG.alpha == 1 and not popup.looks[styled].panel.shown,
    "a hidden dialog kept the Suite look")
popup.config.skin, popup.config.dialogFont = false, false
popup:Refresh()

-- Minimum height, applied after Blizzard's Resize and handed back.
popup.config.minHeight = 200
popup:Refresh()
local tall = ShowPopup("CONFIRM_SOMETHING", 1)
Check(tall.height == 200, "the minimum height did not survive Blizzard's Resize")
for _ = 1, 5 do tall:Resize() end
Check(tall.height == 200, "a countdown Resize lost the minimum height")
local long = ShowPopup("LONG", 12)
Check(long.height == 72 + 12 * 14, "a dialog taller than the minimum was shortened")
long:Hide()
popup.config.minHeight = 0
popup:Refresh()
Check(tall.height == 86, "turning the minimum height off did not hand Blizzard's height back")
local heightWrites = tall.heightWrites
for _ = 1, 5 do tall:Resize() end
Check(tall.heightWrites == heightWrites, "a dialog was resized without a minimum height")
tall:Hide()

-- Resurrection offers.
local revive = ShowPopup("RESURRECT", 1)
Check(popup.cues[revive] and popup.cues[revive].shown and #sounds == 0, "a resurrection offer was not framed")
Check(popup.buttonCues[revive.Button1] and popup.buttonCues[revive.Button1].shown, "the accept button was not framed")
revive:Hide()
Check(not popup.cues[revive].shown and not popup.buttonCues[revive.Button1].shown,
    "the resurrection frames outlived their dialog")
popup.config.reviveButton = false
revive = ShowPopup("RESURRECT", 1)
Check(popup.cues[revive].shown and not popup.buttonCues[revive.Button1].shown, "the accept button was framed with its option off")
revive:Hide()
popup.config.reviveButton = true
popup.config.reviveCue = 3
revive = ShowPopup("RESURRECT_NO_SICKNESS", 1)
Check(popup.cues[revive].shown and sounds[1] == 8960, "the resurrection sound did not play")
revive:Hide()
popup.config.reviveCue = 1
revive = ShowPopup("RESURRECT", 1)
Check(not popup.cues[revive].shown and #sounds == 1, "No mark still marked a resurrection offer")
revive:Hide()
local other = ShowPopup("CONFIRM_SOMETHING", 1)
Check((not popup.cues[other] or not popup.cues[other].shown)
    and (not popup.buttonCues[other.Button1] or not popup.buttonCues[other.Button1].shown), "another dialog was framed")
other:Hide()
popup.config.reviveCue = 2

-- Position: the chain's first dialog is placed after Blizzard sized it.
popup.config.move = true
popup:Refresh()
local first = ShowPopup("FIRST", 2)
local second = ShowPopup("SECOND", 1)
local point, relative, relativePoint, x, y = first:GetPoint(1)
Check(point == "CENTER" and relative == UIParent and x == 50 and y == 80, "the first dialog was not placed")
Check(select(2, second:GetPoint(1)) == first, "the second dialog lost Blizzard's chain")
-- Blizzard resizes a counting-down dialog every frame (StaticPopup_OnUpdate):
-- a placed head is neither moved again nor searched for from its own Resize,
-- and a chained dialog's Resize does not move it either.
local writes, scans = 0, 0
local clear, set = first.ClearAllPoints, first.SetPoint
first.ClearAllPoints = function(self) writes = writes + 1; return clear(self) end
first.SetPoint = function(self, ...) writes = writes + 1; return set(self, ...) end
local isShown = {}
for index = 1, 4 do
    local dialog = _G["StaticPopup" .. index]
    isShown[dialog] = dialog.IsShown
    dialog.IsShown = function(self) scans = scans + 1; return isShown[self](self) end
end
for _ = 1, 30 do first:Resize() end
Check(writes == 0 and scans == 0, "a placed dialog's own Resize scanned the chain or moved it again")
for _ = 1, 30 do second:Resize() end
Check(writes == 0, "a chained dialog's Resize moved the placed head again")
-- A new custom position still moves the placed head on the next Resize.
popup.config.x = 60
first:Resize()
point, relative, relativePoint, x, y = first:GetPoint(1)
Check(writes == 2 and point == "CENTER" and x == 60 and y == 80, "a changed position did not move the placed head")
popup.config.x = 50
first:Resize()
first.ClearAllPoints, first.SetPoint = clear, set
for dialog, original in pairs(isShown) do dialog.IsShown = original end
first:Hide()
local third = ShowPopup("THIRD", 3)
Check(third == StaticPopup1, "the fixture did not reuse the first dialog")
point, relative, relativePoint, x, y = second:GetPoint(1)
Check(point == "CENTER" and relative == UIParent and x == 50 and y == 80,
    "a dialog that now leads the chain was not placed at the custom position")
popup.config.move = false
popup:Refresh()
point, relative, relativePoint, x, y = second:GetPoint(1)
Check(point == "TOP" and relative == UIParent and relativePoint == "TOP" and y == -135,
    "turning the custom position off left the dialog there")
second:Hide(); third:Hide()

-- Edit Mode sample and mover.
S.editMode = true
popup:Refresh()
local spec = movers.popupAttention.spec
Check(popup.preview and popup.preview.shown and spec.getFrame() == popup.preview and spec.moveValues.move == true
    and spec.sizeKeys and spec.sizeKeys[1] == "minHeight" and popup.preview.height == 72,
    "the dialog position and height have no own Edit Mode sample")
popup.config.minHeight = 150
popup:Refresh()
Check(popup.preview.height == 150, "the sample ignored the minimum height")
popup.config.minHeight = 0
point, relative, relativePoint, x, y = popup.preview:GetPoint(1)
Check(point == "CENTER" and x == 50 and y == 80, "the sample ignored the saved position")
S.editMode = false
popup:Refresh()
Check(not popup.preview.shown, "the sample leaked outside Edit Mode")

-- Disable hands everything back.
popup.config.skin, popup.config.dialogFont, popup.config.move, popup.config.minHeight = true, true, true, 240
popup:Refresh()
local open = ShowPopup("RESURRECT", 1)
Check(open.height == 240, "the minimum height was not applied before disable")
popup.active = false
popup:Disable()
Check(open.Text.font[2] == 12 and open.BG.alpha == 1 and not popup.cues[open].shown
    and not popup.buttonCues[open.Button1].shown and open.height == 86
    and select(1, open:GetPoint(1)) == "TOP", "disable did not hand the dialog back")
open:Hide()
toast = LootAlertSystem:ShowAlert("epic", 1)
Check(not popup.qualityLabels[toast], "the disabled module labelled a toast")
local lateMoney = MoneyWonAlertSystem:ShowAlert(5)
Check(not popup.moneyFrames[lateMoney], "the disabled module framed a money toast")
print("Popup attention: " .. checks .. " checks passed")

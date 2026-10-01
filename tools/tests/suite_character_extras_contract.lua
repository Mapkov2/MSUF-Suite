local root = assert(arg[1], "repository root required")
local checks = 0
local function Check(value, message) assert(value, message); checks = checks + 1 end

-- Frames as the client runs them: OnShow and OnHide also reach shown
-- children when an ancestor's visibility changes.
local function Notify(frame, script)
    if frame.scripts[script] then frame.scripts[script](frame) end
    for _, child in ipairs(frame.children) do
        if child.shown then Notify(child, script) end
    end
end
local function Widget(parent)
    local w = { parent = parent, shown = true, points = {}, scripts = {}, children = {}, alpha = 1, mouse = true,
        coords = { 0, 0, 0, 1, 1, 0, 1, 1 } }
    if parent then parent.children[#parent.children + 1] = w end
    function w:SetScript(name, callback) self.scripts[name] = callback end
    function w:HookScript(name, callback)
        local old = self.scripts[name]
        self.scripts[name] = function(...) if old then old(...) end; callback(...) end
    end
    function w:Show()
        local was = self:IsVisible()
        self.shown = true
        if not was and self:IsVisible() then Notify(self, "OnShow") end
    end
    function w:Hide()
        local was = self:IsVisible()
        self.shown = false
        if was then Notify(self, "OnHide") end
    end
    function w:SetShown(value) if value then self:Show() else self:Hide() end end
    function w:IsShown() return self.shown end
    function w:IsVisible() return self.shown and (not self.parent or self.parent:IsVisible()) end
    function w:SetSize(x, y) self.width, self.height = x, y end
    function w:SetHeight(h) self.height = h end
    function w:SetPoint(...) self.points[#self.points + 1] = { ... } end
    function w:ClearAllPoints() self.points = {} end
    function w:SetAllPoints() end
    function w:SetColorTexture() end
    function w:SetJustifyH() end
    function w:SetText(value) self.text = value end
    function w:SetTextColor(...) self.textColor = { ... } end
    function w:SetFont(...) self.font = { ... } end
    function w:GetAlpha() return self.alpha end
    function w:SetAlpha(value) self.alpha = value end
    function w:IsMouseEnabled() return self.mouse end
    function w:EnableMouse(value) self.mouse = value end
    function w:GetTexCoord() return unpack(self.coords) end
    function w:SetTexCoord(...) self.coords = { ... } end
    return w
end

-- Blizzard_UIPanels_Game: the character sheet's Character tab is PaperDollFrame
-- inside CharacterFrame; 12.1 has no CharacterModelFrame (the model is
-- CharacterModelScene). Gear slots carry their icon and arrow.
UIParent = Widget()
CharacterFrame = Widget(UIParent)
CharacterFrame.shown = false
PaperDollFrame = Widget(CharacterFrame)
CharacterModelScene = Widget(PaperDollFrame)
CharacterModelFrame = nil
local SLOT_NAMES = { "Head", "Neck", "Shoulder", "Back", "Chest", "Shirt", "Tabard", "Wrist", "Hands", "Waist",
    "Legs", "Feet", "Finger0", "Finger1", "Trinket0", "Trinket1", "MainHand", "SecondaryHand" }
local function Slots(sheet, parent)
    for _, name in ipairs(SLOT_NAMES) do
        local slot = Widget(parent)
        slot.icon = Widget(slot)
        if sheet == "Character" then slot.popoutButton = Widget(slot) end
        _G[sheet .. name .. "Slot"] = slot
    end
end
Slots("Character", PaperDollFrame)
local function ChildOfSheet(frame)
    local node = frame.parent
    while node do
        if node == PaperDollFrame then return true end
        node = node.parent
    end
    return false
end

-- Hooks as the client runs them.
hooksecurefunc = function(name, callback)
    local original = _G[name]
    _G[name] = function(...) original(...); callback(...) end
end
local deferred = {}
C_Timer = { After = function(_, callback) deferred[#deferred + 1] = callback end }
local function RunFrame()
    local queue = deferred
    deferred = {}
    for _, callback in ipairs(queue) do callback() end
end

-- Gear: a helmet with one of two sockets filled, a necklace without sockets.
local socketed = 1
local statReads = 0
GetInventoryItemLink = function(_, slot) if slot == 1 then return "helmet" elseif slot == 2 then return "neck" end end
GetInventoryItemDurability = function(slot) if slot == 1 then return 25, 50 elseif slot == 2 then return 100, 100 end end
GetAverageItemLevel = function() return 600, 610, 620 end
C_Item = {
    GetItemStats = function(link) statReads = statReads + 1 return link == "helmet" and { EMPTY_SOCKET_PRISMATIC = 2 } or {} end,
    GetItemGem = function(_, index) if index <= socketed then return "Gem", "gem" end end,
    GetItemInfo = function(link) return link == "helmet" and "Helmet" or "Necklace" end,
    GetCurrentItemLevel = function() return 144 end,
    GetDetailedItemLevelInfo = function() return 155 end,
}
local socketedSlot
SocketInventoryItem = function(slot) socketedSlot = slot end
GameTooltip = { SetOwner = function() end, SetInventoryItem = function() end, Show = function() end }
GameTooltip_Hide = function() end
C_Container = { GetContainerItemLink = function() return "bagitem" end }
EquipmentManager_GetLocationData = function() return { isBags = true, bag = 0, slot = 1 } end
EQUIPMENTFLYOUT_FIRST_SPECIAL_LOCATION = 999
local flyoutButton = Widget()
flyoutButton.GetItemLocation = function(self) return self.locationObject end
EquipmentFlyoutFrame = Widget()
EquipmentFlyoutFrame.buttons = { flyoutButton }
EquipmentFlyout_UpdateItems = function() end
-- Season pages: Blizzard_WeeklyRewards' opener and the minimap's expansion button.
local vaults, landings = 0, 0
WeeklyRewards_ShowUI = function() vaults = vaults + 1 end
ExpansionLandingPageMinimapButton = Widget(UIParent)
function ExpansionLandingPageMinimapButton:ToggleLandingPage() landings = landings + 1 end

local S, modules = {}, {}
S.Public = function(value) return value ~= "secret" end
S.PublicText = function(value) return S.Public(value) and type(value) == "string" and value ~= "" and value or nil end
S.Finite = function(value) return S.Public(value) and type(value) == "number" and value == value end
S.Text = function(value) return value end
S.SetFont = function(w, ...) w:SetFont(...) end
S.GlobalFontPath = function() return "global" end
S.CreateFrame = function(_, _, parent) return Widget(parent) end
S.CreateTexture = function(parent) return Widget(parent) end
S.CreateFontString = S.CreateTexture
S.Dispatch = function(callback, ...) return callback(...) end
S.Install = function(id, module) modules[id] = module end
local combat = false
local NS = { Safety = { IsForbidden = function() return false end }, IsCombatLocked = function() return combat end,
    Finish = function(callback, ...) return true, callback(...) end }
assert(loadfile(root .. "/MSUF_Suite_QualityOfLife/CharacterExtras.lua"))("test", { NS = NS, Suite = S })
local m = modules.characterExtras
m.active, m.events = true, {}
-- Context:Tuple and Context:HideControl as MSUF_Suite_Modules/Runtime.lua runs
-- them: the first value is kept and handed back, only alpha and mouse change.
local tuples, controls = {}, {}
m.context = { Event = function(_, event, callback) m.events[event] = callback end,
    RemoveEvent = function(_, event) m.events[event] = nil end }
function m.context:Tuple(frame, getter, setter, ...)
    tuples[frame] = tuples[frame] or { frame[getter](frame) }
    frame[setter](frame, ...)
end
function m.context:RestoreTuple(frame, setter)
    if tuples[frame] then frame[setter](frame, unpack(tuples[frame])) end
    tuples[frame] = nil
end
function m.context:HideControl(frame, hidden)
    if hidden then
        controls[frame] = controls[frame] or { frame.alpha, frame.mouse }
        frame.alpha, frame.mouse = 0, false
    elseif controls[frame] then
        frame.alpha, frame.mouse = controls[frame][1], controls[frame][2]
        controls[frame] = nil
    end
end
m.config = { summaryPanel = true, summarySockets = true, summaryDurability = true, summaryPvP = false,
    shortcutVault = true, shortcutExpansion = true, summaryFontSize = 11, choiceItemLevels = true,
    modelDurability = false, modelDurabilityX = 0, modelDurabilityY = -150, slotIconCrop = 0, slotArrowsHidden = false }
m:Enable()
Check(not next(m.events), "the summary listened to gear events while the sheet was closed")

CharacterFrame:Show()
local panel = m.panel
Check(panel and ChildOfSheet(panel) and panel.shown, "the summary is not part of the Character tab")
Check(m.events.PLAYER_EQUIPMENT_CHANGED and m.events.GET_ITEM_INFO_RECEIVED, "the open sheet did not listen to gear changes")
local row = m.rows[1]
Check(row.shown and row.text.text == "Helmet: 1 of 2 sockets filled" and row.text.textColor[1] == 1 and not m.rows[2].shown,
    "gear with an open socket is not listed in amber")
row.scripts.OnClick(row)
Check(socketedSlot == 1, "clicking a line did not open socketing for its slot")
Check(panel.durability.text == "Durability 83%" and not panel.pvp.shown, "durability or the PvP default is wrong")
m.config.summaryPvP = true
m:Refresh()
Check(panel.pvp.shown and panel.pvp.text == "PvP item level 620", "the PvP item level is missing")

-- Bursts of item and gear events repaint once per frame.
local reads = statReads
for _ = 1, 5 do m.events.GET_ITEM_INFO_RECEIVED(m, "GET_ITEM_INFO_RECEIVED", 123) end
m.events.PLAYER_EQUIPMENT_CHANGED(m, "PLAYER_EQUIPMENT_CHANGED", 1)
Check(statReads == reads and #deferred == 1, "gear events were not coalesced")
socketed = 2
RunFrame()
Check(statReads > reads and m.rows[1].shown and m.rows[1].text.text == "Helmet: 2 of 2 sockets filled"
    and m.rows[1].text.textColor[1] == .62 and panel.sockets.text == "Gem sockets",
    "fully socketed gear left the list or kept the open-socket color")
socketed = 1

-- Season shortcuts.
Check(panel.vault.shown and panel.expansion.shown, "the Great Vault or expansion button is missing")
panel.vault.scripts.OnClick(panel.vault)
panel.expansion.scripts.OnClick(panel.expansion)
Check(vaults == 1 and landings == 1, "the shortcuts did not open the Great Vault and the expansion page")
combat = true
panel.vault.scripts.OnClick(panel.vault)
combat = false
Check(vaults == 1, "the Great Vault opened in combat")
ExpansionLandingPageMinimapButton:Hide()
m.config.shortcutVault = false
m:Refresh()
Check(not panel.vault.shown and not panel.expansion.shown, "a shortcut stayed without its option or its expansion page")
ExpansionLandingPageMinimapButton:Show()
m.config.shortcutVault = true

-- Durability on the character model.
Check(not m.modelText or not m.modelText.shown, "durability on the model showed without its option")
m.config.modelDurability, m.config.modelDurabilityX, m.config.modelDurabilityY = true, 12, -90
m:Refresh()
local model = m.modelText
local point, relative, _, x, y = unpack(model.points[1])
Check(model.shown and model.parent == CharacterModelScene and model.text == "Durability 83%" and point == "CENTER"
    and relative == CharacterModelScene and x == 12 and y == -90, "durability is not on the model at its offsets")

-- Slot icons and arrows.
m.config.slotIconCrop, m.config.slotArrowsHidden = 10, true
m:Refresh()
local icon, arrow = CharacterHeadSlot.icon, CharacterHeadSlot.popoutButton
Check(icon.coords[1] == .1 and icon.coords[7] == .9 and arrow.alpha == 0 and not arrow.mouse and arrow.shown,
    "slot icons were not cropped or the arrows were hidden instead of faded")
Check(m.events.ADDON_LOADED, "the Inspect sheet is not waited for")
InspectFrame = Widget(UIParent)
InspectFrame.shown = false
Slots("Inspect", InspectFrame)
m.events.ADDON_LOADED(m, "ADDON_LOADED", "Blizzard_InspectUI")
InspectFrame:Show()
Check(InspectHeadSlot.icon.coords[1] == .1 and not m.events.ADDON_LOADED, "the Inspect sheet icons were not cropped")
m.config.slotIconCrop, m.config.slotArrowsHidden = 0, false
m:Refresh()
Check(icon.coords[1] == 0 and InspectHeadSlot.icon.coords[1] == 0 and arrow.alpha == 1 and arrow.mouse,
    "turning the crop or the arrows off did not hand them back")

-- Another tab of the sheet: the summary and its listeners leave with it.
PaperDollFrame:Hide()
Check(not panel:IsVisible() and not model:IsVisible() and not m.events.PLAYER_EQUIPMENT_CHANGED,
    "the summary stayed visible or listening on another tab")
PaperDollFrame:Show()
Check(panel:IsVisible() and m.events.PLAYER_EQUIPMENT_CHANGED and m.rows[1].shown, "the summary did not come back with its tab")
m.config.summaryPanel = false
m:Refresh()
Check(not panel.shown and model.shown, "turning the summary off kept it or took the model durability along")
m.config.summaryPanel = true
m:Refresh()

-- Item levels on equipment choices, from both location forms.
flyoutButton.locationObject = {}
EquipmentFlyout_UpdateItems()
Check(m.flyoutLabels[flyoutButton].text == 144, "the item location's level is missing")
flyoutButton.locationObject, flyoutButton.location = nil, 4
EquipmentFlyout_UpdateItems()
Check(m.flyoutLabels[flyoutButton].text == 155, "the packed location's level is missing")
flyoutButton.location = 1000
EquipmentFlyout_UpdateItems()
Check(not m.flyoutLabels[flyoutButton].shown, "a special flyout entry kept an item level")
flyoutButton.location = 4
m.config.choiceItemLevels = false
EquipmentFlyout_UpdateItems()
Check(not m.flyoutLabels[flyoutButton].shown, "turning flyout levels off kept a label")
m.config.choiceItemLevels = true
EquipmentFlyout_UpdateItems()

m.config.summaryFontSize = 16
m:Refresh()
Check(panel.title.font[2] == 16 and m.flyoutLabels[flyoutButton].font[2] == 16 and model.font[2] == 16,
    "a text size change was ignored")
m.config.slotIconCrop, m.config.slotArrowsHidden = 15, true
m:Refresh()
m.active = false
m:Disable()
Check(not panel.shown and not model.shown and not m.flyoutLabels[flyoutButton].shown and not next(m.events)
    and icon.coords[1] == 0 and arrow.alpha == 1, "disable left the summary, a label, a crop, an arrow or a listener")
CharacterFrame:Hide()
CharacterFrame:Show()
Check(not panel.shown, "the disabled module came back with the sheet")
print("Character sheet additions: " .. checks .. " checks passed")

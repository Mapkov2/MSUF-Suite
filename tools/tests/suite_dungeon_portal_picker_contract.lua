-- The Dungeon portals set picker (MSUF_Suite_Options/Pages/ComfortPickers.lua):
-- a menu-themed Suite popup, the writes it makes and the ones it refuses.
local root = assert(arg[1], "repository root required")
local combat, open, loaded = false, true, 0
local config, writes = { portalSet = 1, customPortals = "" }, {}
local NOOP = function() end

local Methods = {}
local function Widget(kind, parent)
    local widget = { kind = kind, parent = parent, shown = true, scripts = {}, hooks = {}, events = {}, text = "" }
    return setmetatable(widget, { __index = function(_, key) return Methods[key] or NOOP end })
end
local function Run(widget, script, ...)
    if widget.scripts[script] then widget.scripts[script](widget, ...) end
    for _, hook in ipairs(widget.hooks[script] or {}) do hook(widget, ...) end
end
function Methods:Show()
    local was = self.shown
    self.shown = true
    if not was then Run(self, "OnShow") end
end
function Methods:Hide()
    local was = self.shown
    self.shown = false
    if was then Run(self, "OnHide") end
end
function Methods:SetShown(value) if value then self:Show() else self:Hide() end end
function Methods:IsShown() return self.shown end
function Methods:IsVisible()
    local parent = rawget(self, "parent")
    return self.shown and (not parent or parent:IsVisible())
end
function Methods:SetScript(script, handler) self.scripts[script] = handler end
function Methods:HookScript(script, handler)
    self.hooks[script] = self.hooks[script] or {}
    table.insert(self.hooks[script], handler)
end
function Methods:SetText(text)
    self.text = text
    if self.kind == "EditBox" then Run(self, "OnTextChanged") end
end
function Methods:GetText() return self.text end
function Methods:SetActive(value) self.active = value end
function Methods:SetEnabled(value) self.enabled = value end
function Methods:CreateTexture() return Widget("Texture", self) end
function Methods:GetStringHeight() return 28 end
function Methods:IsMouseOver() return self.mouseOver == true end
function Methods:RegisterEvent(event) self.events[event] = true end
function Methods:UnregisterAllEvents() self.events = {} end
function Methods:GetVerticalScrollRange() return 0 end
function Methods:GetVerticalScroll() return 0 end
function Methods:SetVerticalScroll(value) self.scroll = value end

UIParent = Widget("Frame")
function CreateFrame(kind, _, parent) return Widget(kind, parent) end
local tooltip = { owner = nil }
GameTooltip = { SetOwner = function(_, owner) tooltip.owner = owner end, Show = NOOP,
    SetSpellByID = function(_, id) tooltip.spell = id end, IsOwned = function(_, owner) return tooltip.owner == owner end,
    Hide = function() tooltip.owner = nil end }

local listeners = {}
local P = { S = {}, Tr = function(text) return text end,
    Suite = { DungeonPortalSet = { ALL = 1, SEASON = 2, CUSTOM = 3 }, Finite = function(v) return type(v) == "number" end,
        Safety = { IsForbidden = function() return false end },
        Registry = { AddListener = function(owner, callback) listeners[owner] = callback end } },
    catalog = { dungeonPortals = { rules = { portalSet = { choices = { "All learned portals", "Current season", "Custom set" } } } } },
    T = { colors = { text = {} }, SkinEditBox = NOOP, StyleScrollFrame = NOOP,
        Button = function(parent, text) local button = Widget("Button", parent); button.text = text; return button end },
    M = { ApplyPopupFramePriority = NOOP },
    HM = { SkipHistoryCheckpoint = NOOP } }
function P.Text(parent, text) local label = Widget("FontString", parent); label.text = text; return label end
function P.SetTranslatedText(label, text) label.text = text end
function P.SetButtonText(button, text) button.text = text end
function P.Combat() return combat end
function P.Get(id, key)
    assert(id == "dungeonPortals")
    return config[key]
end
function P.SetMany(id, values)
    assert(id == "dungeonPortals")
    writes[#writes + 1] = values
    for key, value in pairs(values) do config[key] = value end
    return true
end
function P.Set(id, key, value) return P.SetMany(id, { [key] = value }) end
-- The real guard also notices a profile switch; `open` stands for it.
function P.ProfileGuard() return function() return open and not combat end end

local function Choice(id, label, learned, season, start)
    return { id = id, label = label, learned = learned, season = season, seasonStart = start, icon = 42 }
end
local seasonKnown, emptySeason = true, false
local function Groups()
    local groups = { season = { Choice(1254557, "Skyreach (B)", true, true, true),
        Choice(159898, "Skyreach (A)", true, true, false), Choice(1254400, "Windrunner Spire", false, true, true) },
        learned = { Choice(445269, "The Stonevault", true) }, later = { Choice(1286801, "The Blinding Vale", false) } }
    if emptySeason then groups.season = {} end
    return groups, seasonKnown
end
C_AddOns = { LoadAddOn = function(name)
    assert(name == "MSUF_Suite_QualityOfLife")
    loaded = loaded + 1
    P.S.DungeonPortalChoices = Groups
end }
local panels = {}
function P.M.CreateMenuPopupPanel(parent)
    panels[#panels + 1] = Widget("Frame", parent)
    return panels[#panels]
end
-- The shared menu popup (P.MenuPopupPanel) comes from the data source picker.
assert(loadfile(root .. "/MSUF_Suite_Options/Pages/DataTextsSourcePicker.lua"))("MSUF_Suite_Options", P)
assert(loadfile(root .. "/MSUF_Suite_Options/Pages/ComfortPickers.lua"))("MSUF_Suite_Options", P)

local anchor = Widget("Button")
-- The popup is the parent of the mode and action buttons; rows sit in its scroll content.
local popup
local function Popup() return popup end
local function Visible(kind)
    local list = {}
    for _, item in ipairs(kind == "row" and popup.rows or popup.titles) do
        if item.shown then list[#list + 1] = item end
    end
    return list
end
local function Row(label)
    for _, row in ipairs(Visible("row")) do
        if row.text:find(label, 1, true) then return row end
    end
    error("no row " .. label)
end
local function Click(widget) widget.scripts.OnClick(widget) end

-- In combat the picker neither loads the runtime nor opens.
combat = true
P.DungeonPortalMenu(anchor)
assert(loaded == 0, "the picker loaded its runtime in combat")
combat = false
P.DungeonPortalMenu(anchor)
assert(loaded == 1, "the picker did not load its runtime once")
popup = assert(panels[1], "the picker did not use the shared menu popup")
assert(listeners[popup], "the popup did not watch profile changes")
assert(Popup().shown and popup.anchor == anchor and popup.events.GLOBAL_MOUSE_DOWN and popup.events.PLAYER_REGEN_DISABLED)
assert(#Visible("row") == 5 and #Visible("title") == 3 and not popup.note.shown, "groups or rows are missing")
assert(Visible("title")[1].text == "Current season" and Visible("title")[3].text == "Not learned yet")
local grey = Row("Windrunner Spire")
assert(grey.text:find("|cff8c8c8c", 1, true) and grey.text:find("|T42:18|t", 1, true), "an unlearned portal is not grey")
Run(grey, "OnEnter")
assert(tooltip.spell == 1254400 and tooltip.owner == grey, "the portal tooltip shows another spell")
Run(grey, "OnLeave")
assert(tooltip.owner == nil)
assert(popup.modes[1].active and not popup.modes[2].active, "the saved mode is not shown")

-- A mode button writes the mode.
Click(popup.modes[2])
assert(config.portalSet == 2 and popup.modes[2].active and not popup.modes[1].active)
-- A portal row switches to the custom set and toggles its spell.
local stonevault = Row("The Stonevault")
Click(stonevault)
assert(config.portalSet == 3 and config.customPortals == "445269" and stonevault.active, "choosing a portal")
assert(popup.modes[3].active and not popup.modes[2].active)
Click(stonevault)
assert(config.customPortals == "" and not stonevault.active, "removing a portal")
-- The search filters rows and their group titles.
popup.search:SetText("sky")
assert(#Visible("row") == 2 and #Visible("title") == 1, "the search did not filter")
popup.search:SetText("nothing")
assert(#Visible("row") == 0 and popup.empty.shown, "an empty search shows no notice")
popup.search:SetText("")
assert(#Visible("row") == 5 and not popup.empty.shown)
-- The season start takes one portal per season dungeon, sorted.
assert(popup.start.enabled == true)
Click(popup.start)
assert(config.portalSet == 3 and config.customPortals == "1254400,1254557", "the season start chose other portals")
assert(Row("Skyreach (B)").active and not Row("Skyreach (A)").active)
-- Clearing keeps the chosen mode.
config.portalSet = 2
Click(popup.clear)
assert(config.portalSet == 2 and config.customPortals == "", "clearing changed the mode")
-- At most 100 portals; removing still works at the limit.
local full = {}
for i = 1, 100 do full[i] = tostring(i) end
config.customPortals = table.concat(full, ",")
local count = #writes
Click(stonevault)
assert(#writes == count, "a 101st portal was saved")
full[100] = "445269"
config.customPortals = table.concat(full, ",")
Click(stonevault)
assert(#writes == count + 1 and not config.customPortals:find("445269", 1, true), "removing at the limit")
-- After a profile switch (or in combat) the open popup writes nothing.
open, count = false, #writes
Click(stonevault)
Click(popup.modes[1])
Click(popup.start)
Click(popup.clear)
assert(#writes == count, "a stale popup wrote into another profile")
open = true

-- It closes on a click elsewhere, not on its own; in combat; again on its
-- anchor; with its anchor's page; and on a profile change.
popup.mouseOver = true
popup.scripts.OnEvent(popup, "GLOBAL_MOUSE_DOWN")
assert(popup.shown, "a click inside closed the popup")
popup.mouseOver = false
popup.scripts.OnEvent(popup, "GLOBAL_MOUSE_DOWN")
assert(not popup.shown and not popup.events.GLOBAL_MOUSE_DOWN, "a click elsewhere kept the popup")
P.DungeonPortalMenu(anchor)
popup.scripts.OnEvent(popup, "PLAYER_REGEN_DISABLED")
assert(not popup.shown, "combat kept the popup")
P.DungeonPortalMenu(anchor)
P.DungeonPortalMenu(anchor)
assert(not popup.shown, "a second click on the anchor kept the popup")
P.DungeonPortalMenu(anchor)
Run(anchor, "OnHide")
assert(not popup.shown, "the popup outlived its page")
P.DungeonPortalMenu(anchor)
listeners[popup](nil, "profile")
assert(not popup.shown, "a profile change kept the popup")
combat = true
P.DungeonPortalMenu(anchor)
assert(not popup.shown, "the popup opened in combat")
combat = false

-- An unknown season shows its note; without season portals the start is off.
seasonKnown, emptySeason = false, true
P.DungeonPortalMenu(anchor)
assert(loaded == 1, "the runtime was loaded again")
assert(popup.shown and popup.note.shown and popup.start.enabled == false)
assert(#Visible("title") == 2 and Visible("title")[1].text == "Other learned portals", "an empty season kept its title")
print("Dungeon portal picker: themed popup, combat refusal, modes, custom set writes, search, season start, cap, stale guard and closing passed")

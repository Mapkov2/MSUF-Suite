-- Tooltip additions of the Quality of Life addon: the specialization of a
-- hovered player, the tooltip scale, the key that shows hidden tooltips, the
-- border color, Mythic+ forces and hidden unit lines. Secrets stay out, the
-- shared GameTooltip is never hooked by method, and the border is painted by
-- whoever draws it (the Suite skin's edge, else Blizzard's NineSlice).
local root = assert(arg[1], "repository root required")
local Support = dofile(root .. "/tools/tests/suite_test_support.lua")
local checks = 0
local function Check(value, message) assert(value, message); checks = checks + 1 end

-- A restricted value: it passes through the module only as itself. Any
-- compare other than identity, arithmetic, key or method use raises.
local secret = setmetatable({}, { __tostring = function() return "<secret>" end })
local reported, modules = {}, {}
local S = {
    Public = function(value) return value ~= secret end,
    Text = function(value) return value end,
    Dispatch = Support.Dispatcher(reported),
    Install = function(id, module) modules[id] = module end,
    SetFont = function() end,
}
S.PublicText = function(value) return S.Public(value) and type(value) == "string" and value ~= "" and value or nil end
S.Finite = function(value) return S.Public(value) and type(value) == "number" and value == value end
local function Widget()
    local w = {}
    function w:SetSize() end
    function w:EnableMouse() end
    function w:SetAllPoints() end
    function w:SetColorTexture() end
    function w:SetPoint() end
    function w:ClearAllPoints() end
    function w:SetText() end
    function w:SetShown() end
    function w:Hide() end
    return w
end
S.CreateFrame, S.CreateTexture, S.CreateFontString = Widget, Widget, Widget

local combat = false
local skinTints = {}
local NS = {
    Safety = { IsForbidden = function(frame) return frame.forbidden == true end },
    IsCombatLocked = function() return combat end,
    InCombat = function(event)
        if event == "PLAYER_REGEN_DISABLED" then return true end
        if event == "PLAYER_REGEN_ENABLED" then return false end
        return combat
    end,
    Finish = function(callback, ...) return true, callback(...) end,
    Skin = { TintEdge = function() return false end },
}
NS.Dispatch = S.Dispatch

------------------------------------------------------------------ client
-- hooksecurefunc as the client runs it. The shared tooltip is never hooked by
-- method (AGENTS.md, owner decision 2026-10-06).
hooksecurefunc = function(owner, key, callback)
    assert(owner ~= GameTooltip, "shared tooltip method hook is forbidden")
    if type(owner) == "string" then
        local original = _G[owner]
        _G[owner] = function(...) local a, b, c = original(...); key(...) return a, b, c end
        return
    end
    local original = owner[key]
    owner[key] = function(...) original(...); callback(...) end
end
UIParent = Widget()
canaccesstable = function(value) return not (type(value) == "table" and value.blocked) end
Enum = {
    TooltipDataType = { Item = 0, Spell = 1, Unit = 2, Mount = 10 },
    TooltipDataLineType = { None = 0, UnitName = 2, UnitCriteriaProgress = 50 },
}
IsInInstance = function() return false end
local mods = {}
IsShiftKeyDown = function() return mods.shift end
IsControlKeyDown = function() return mods.ctrl end
IsAltKeyDown = function() return mods.alt end

-- GameTooltip as addon code meets it. SetScale and the NineSlice border
-- are the only writes the additions make to it.
local nativeBorder = { .8, .7, .6, 1 }
local tooltip = { shown = false, lines = {}, scripts = {}, alpha = 1, scale = 1 }
tooltip.NineSlice = { color = nativeBorder }
function tooltip.NineSlice:GetBorderColor() return unpack(self.color) end
function tooltip.NineSlice:SetBorderColor(r, g, b, a) self.color = { r, g, b, a or 1 } end
function tooltip:AddDoubleLine(left, right) self.lines[#self.lines + 1] = { left, right } end
function tooltip:IsShown() return self.shown end
function tooltip:GetOwner() end
function tooltip:GetAlpha() return self.alpha end
function tooltip:SetAlpha(value) self.alpha = value end
function tooltip:GetScale() return self.scale end
function tooltip:SetScale(value) self.scale = value end
function tooltip:IsTooltipType(kind) return self.tooltipType == kind end
function tooltip:Show()
    local was = self.shown
    self.shown = true
    if not was and self.scripts.OnShow then self.scripts.OnShow(self) end
end
function tooltip:Hide()
    local was = self.shown
    self.shown = false
    if was and self.scripts.OnHide then self.scripts.OnHide(self) end
end
function tooltip:Clear()
    if self.scripts.OnTooltipCleared then self.scripts.OnTooltipCleared(self) end
end
function tooltip:HookScript(name, callback)
    local old = self.scripts[name]
    self.scripts[name] = function(...) if old then old(...) end; callback(...) end
end
function tooltip:SetOwner() end
function tooltip:SetAnchorType() end
function tooltip:ClearAllPoints() end
function tooltip:SetPoint() end
function tooltip:GetProcessingTooltipInfo() end
GameTooltip = tooltip
GameTooltip_SetDefaultAnchor = function() end
NotifyInspect, ClearInspectPlayer = function() end, function() end
local function Line(index)
    local line = { text = "line" .. index }
    function line:SetText(value) self.text = value end
    function line:SetTextColor() end
    return line
end
for index = 1, 6 do _G["GameTooltipTextLeft" .. index] = Line(index) end
local function LineValue(label)
    for _, line in ipairs(tooltip.lines) do if line[1] == label then return line[2] end end
end

-- Units, inspection, specialization.
local identitySecret = false
local guids = {}
C_Secrets = { ShouldUnitIdentityBeSecret = function() return identitySecret end }
UnitGUID = function(unit) return guids[unit] or ("GUID-" .. unit) end
UnitIsUnit = function(a, b) return a == b end
local npcs = { enemy = true, enemy2 = true, friendly = true }
UnitIsPlayer = function(unit) return not npcs[unit] end
UnitCanAttack = function(_, unit) return unit == "enemy" or unit == "enemy2" end
UnitName = function(unit)
    if unit == "far" then return "Far", "OtherRealm" end
    return "Plain"
end
UnitClass = function() return "Mage", "MAGE" end
UnitReaction = function(unit) return unit == "enemy" and 2 or 5 end
GetGuildInfo = function() return "Guild", "Officer" end
UnitFactionGroup = function() return "Horde", "Horde" end
PVP = "PvP"
UnitSex = function() return 2 end
RAID_CLASS_COLORS = setmetatable({ MAGE = { r = .25, g = .78, b = .92 } }, {
    __index = function(_, key) assert(key ~= secret, "a restricted class was used as a table key") end })
FACTION_BAR_COLORS = { [2] = { r = .8, g = .1, b = .1 }, [5] = { r = .1, g = .8, b = .1 } }
local now, requests, inspectLevel = 1000, 0, 180
GetTime = function() return now end
CanInspect = function() return true end
UnitIsDeadOrGhost = function() return false end
NotifyInspect = function() requests = requests + 1 end
C_PaperDollInfo = { GetInspectItemLevel = function() return inspectLevel end }
GetAverageItemLevel = function() return 600, 610, 620 end
local specCalls, inspectedSpec, specName = 0, 62, "Arcane"
C_SpecializationInfo = {
    GetInspectSpecialization = function() specCalls = specCalls + 1 return inspectedSpec end,
    GetSpecialization = function() return 2 end,
    GetSpecializationInfo = function(index) return 100 + index, "Frost" end,
}
GetSpecializationInfoByID = function(id) return id, specName end
C_Item = {
    GetItemInfo = function() return "item", "link", 4, 100, nil, nil, nil, 200, nil, 1234 end,
    GetItemQualityByID = function(link) return link == "|Hitem:epic|h" and 4 or nil end,
    GetItemQualityColor = function(quality) assert(quality == 4); return .64, .21, .93 end,
}
C_Spell = { GetSpellTexture = function() return 1 end }
C_Timer = { After = function() end }
local keystone, criteriaCalls, criteria = false, 0, { 12, 1.25 }
C_ChallengeMode = { IsChallengeModeActive = function() return keystone end }
C_ScenarioInfo = {
    GetUnitCriteriaProgressValues = function() criteriaCalls = criteriaCalls + 1 return criteria[1], criteria[2] end,
}

------------------------------------------------------------------ modules
local fixture = Support.TooltipFixture(root, S, NS)
-- The tooltip's scale belongs to the Suite core's owner (TooltipScale.lua).
ApproximatelyEqual = function(a, b) return math.abs(a - b) < .000001 end
NS.Finite = S.Finite
assert(loadfile(root .. "/MSUF_Suite/Core/TooltipScale.lua"))("MSUF_Suite", NS)
local function Load(file)
    assert(loadfile(root .. "/MSUF_Suite_QualityOfLife/" .. file))("MSUF_Suite_QualityOfLife", { NS = NS, Suite = S })
end
Load("TooltipBorder.lua")
Load("TooltipHiddenLines.lua")
Load("TooltipDetails.lua")
Load("TooltipVisibility.lua")
local details, visibility = modules.tooltipDetails, modules.tooltipVisibility
local detailEvents, visibilityEvents = {}, {}
details.active, visibility.active = true, true
details.config = { titles = true, itemLevel = true, inspectHovered = true, spec = true, mythicForces = true,
    borderColor = 1, anchor = 1, growth = 1, fixedX = -24, fixedY = 24 }
visibility.config = { inCombat = false, inInstances = false, hideItems = false, hideSpells = false,
    hideUnits = false, revealModifier = 1, scale = 100 }
details.context = Support.ModuleTimers(root, S, NS)("tooltipDetails", details, {
    Event = function(_, event, callback) detailEvents[event] = callback end,
    RemoveEvent = function(_, event) detailEvents[event] = nil end })
visibility.context = {
    Event = function(_, event, callback) visibilityEvents[event] = callback end,
    RemoveEvent = function(_, event) visibilityEvents[event] = nil end }
details:Enable()
visibility:Enable()

local function ReadOnly(row)
    return setmetatable({}, { __index = row, __newindex = function(_, key)
        error("tooltip line data was written: " .. tostring(key))
    end })
end
local function Row(index, text) return ReadOnly({ type = Enum.TooltipDataLineType.None, lineIndex = index, leftText = text }) end
-- Blizzard's data of a unit tooltip: the name line first, then `rows`.
local function UnitData(unit, rows, name)
    local lines = { ReadOnly({ type = Enum.TooltipDataLineType.UnitName, unitToken = unit, lineIndex = 1,
        leftText = name or "Plain" }) }
    for _, row in ipairs(rows or {}) do lines[#lines + 1] = row end
    return { lines = lines }
end
local function Build(unit, rows, name)
    tooltip.lines, tooltip.tooltipType = {}, Enum.TooltipDataType.Unit
    tooltip:Clear()
    fixture.Run(Enum.TooltipDataType.Unit, tooltip, UnitData(unit, rows, name))
    tooltip:Show()
end
local function BuildItem(link)
    tooltip.lines, tooltip.tooltipType = {}, Enum.TooltipDataType.Item
    tooltip:Clear()
    fixture.Run(Enum.TooltipDataType.Item, tooltip, { id = 4, hyperlink = link })
    tooltip:Show()
end

------------------------------------------------------------------ specialization
-- One hover asks the server once; the answer fills the cache with the item
-- level and the specialization, and later builds read the cache.
now = 1010
Build("party1")
Check(requests == 1 and not LineValue("Specialization"), "the hover did not request exactly once")
detailEvents.INSPECT_READY(details, "INSPECT_READY", "GUID-party1")
Check(requests == 1 and specCalls == 1, "the specialization needed another inspect request or call")
Check(LineValue("Item level") == "180" and LineValue("Specialization") == "Arcane",
    "the completed hover lacks its item level or specialization")
Build("party1")
Check(requests == 1 and specCalls == 1 and LineValue("Specialization") == "Arcane",
    "the cached specialization was read again or lost")
tooltip:Hide()
Build("player")
Check(LineValue("Item level") == "610" and LineValue("Specialization") == "Frost" and specCalls == 1 and requests == 1,
    "your own specialization needs no inspect call")
tooltip:Hide()
-- Restricted answers never reach the line; the item level stays.
now = 1030
inspectedSpec = secret
Build("party2")
detailEvents.INSPECT_READY(details, "INSPECT_READY", "GUID-party2")
Check(LineValue("Item level") == "180" and not LineValue("Specialization"), "a restricted specialization was shown")
tooltip:Hide()
now = 1050
inspectedSpec, specName = 62, secret
Build("party3")
detailEvents.INSPECT_READY(details, "INSPECT_READY", "GUID-party3")
Check(not LineValue("Specialization"), "a restricted specialization name was shown")
tooltip:Hide()
-- Off: no line and no call.
now = 1070
specName, details.config.spec = "Arcane", false
details:Refresh()
local before = specCalls
Build("party4")
detailEvents.INSPECT_READY(details, "INSPECT_READY", "GUID-party4")
Check(LineValue("Item level") == "180" and not LineValue("Specialization") and specCalls == before,
    "the specialization switch did not act alone")
tooltip:Hide()
Build("player")
Check(not LineValue("Specialization"), "your own specialization ignored its switch")
tooltip:Hide()
details.config.spec, details.config.inspectHovered = true, false
details:Refresh()

------------------------------------------------------------------ border color
-- Item quality, class or reaction, both; the color goes back when the tooltip
-- clears or hides. The skin owns the border when it draws one.
local function Border() return { tooltip.NineSlice:GetBorderColor() } end
local function Same(a, b) return a[1] == b[1] and a[2] == b[2] and a[3] == b[3] end
local EPIC, MAGE, ENEMY = { .64, .21, .93 }, { .25, .78, .92 }, { .8, .1, .1 }
BuildItem("|Hitem:epic|h")
Check(Same(Border(), nativeBorder), "the Keep choice colored the border")
details.config.borderColor = 2
BuildItem("|Hitem:epic|h")
Check(Same(Border(), EPIC), "an item tooltip did not take its quality color")
tooltip:Hide()
Check(Same(Border(), nativeBorder), "the border color stayed after the tooltip hid")
Build("party1")
Check(Same(Border(), nativeBorder), "the item choice colored a unit tooltip")
tooltip:Hide()
details.config.borderColor = 3
BuildItem("|Hitem:epic|h")
Check(Same(Border(), nativeBorder), "the unit choice colored an item tooltip")
Build("party1")
Check(Same(Border(), MAGE), "a player tooltip did not take its class color")
Build("enemy")
Check(Same(Border(), ENEMY), "an enemy tooltip did not take its reaction color")
tooltip:Clear()
Check(Same(Border(), nativeBorder), "clearing the tooltip kept the old color for the next content")
Build("friendly")
tooltip:Hide()
details.config.borderColor = 4
BuildItem("|Hitem:epic|h")
Check(Same(Border(), EPIC), "both: an item tooltip lost its quality color")
Build("party1")
Check(Same(Border(), MAGE), "both: a player tooltip lost its class color")
-- Unreadable data never colors: a secret link, quality or class.
tooltip:Hide()
BuildItem(secret)
Check(Same(Border(), nativeBorder), "a secret item link colored the border")
BuildItem("|Hitem:common|h")
Check(Same(Border(), nativeBorder), "an item without a known quality colored the border")
UnitClass = function() return "Mage", secret end
Build("party1")
Check(Same(Border(), nativeBorder), "a secret class colored the border")
UnitClass = function() return "Mage", "MAGE" end
-- Settings changes and the disabled module give the border back too.
Build("party1")
Check(Same(Border(), MAGE), "the class color is missing before the settings change")
details.config.borderColor = 1
details:Refresh()
Check(Same(Border(), nativeBorder), "a settings change kept the old border color")
details.config.borderColor = 4
Build("party1")
details.active = false
details:Disable()
Check(Same(Border(), nativeBorder), "disabling the module kept the border color")
tooltip:Hide()
details.active = true
details:Enable()
-- The skin draws the tooltip's border: the color goes to its edge, not around it.
NS.Skin.TintEdge = function(frame, r, g, b)
    assert(frame == tooltip)
    skinTints[#skinTints + 1] = r and { r, g, b } or "theme"
    return true
end
Build("party1")
Check(#skinTints == 1 and Same(skinTints[1], MAGE) and Same(Border(), nativeBorder),
    "the skin's tooltip edge was not colored through the skin")
tooltip:Hide()
Check(skinTints[2] == "theme" and Same(Border(), nativeBorder), "the skin's edge kept the color after hide")
NS.Skin.TintEdge = function() return false end
details.config.borderColor = 1

------------------------------------------------------------------ Mythic+ forces
tooltip:Hide()
Build("enemy")
Check(not LineValue("Forces") and criteriaCalls == 0, "forces appeared, or were read, outside a keystone")
keystone = true
Build("enemy")
Check(LineValue("Forces") == "+1.25%" and criteriaCalls == 1, "an enemy in a keystone lacks its forces")
Build("enemy")
Check(criteriaCalls == 1, "a public identity read its forces again on a rebuild")
guids.enemy2 = "GUID-enemy2"
criteria = { 12, 3.5 }
Build("enemy2")
Check(LineValue("Forces") == "+3.50%" and criteriaCalls == 2, "another enemy reused the cached forces")
tooltip:Hide()
-- A restricted identity is never cached: every build reads again.
identitySecret = true
Build("enemy")
Build("enemy")
Check(LineValue("Forces") == "+3.50%" and criteriaCalls == 4, "a restricted identity was cached")
criteria = { secret, secret }
Build("enemy")
Check(criteriaCalls == 5 and not LineValue("Forces"), "a secret forces value was formatted")
identitySecret = false
criteria = { 12, 1.25 }
tooltip:Hide()
Build("friendly")
Check(not LineValue("Forces"), "a friendly unit showed forces")
Build("party1")
Check(not LineValue("Forces"), "a player showed forces")
criteria = { nil, nil }
Build("enemy")
Check(not LineValue("Forces"), "an enemy that adds nothing showed forces")
criteria = { 0, 0 }
tooltip:Hide()
Build("enemy")
Check(not LineValue("Forces"), "an enemy worth nothing showed forces")
criteria = { 12, 1.25 }
tooltip:Hide()
before = criteriaCalls
tooltip.lines, tooltip.tooltipType = {}, Enum.TooltipDataType.Unit
fixture.Run(Enum.TooltipDataType.Unit, tooltip, UnitData("enemy", { Row(2, "Forces 1%") }))
Check(LineValue("Forces") == "+1.25%", "a plain row blocked the forces")
tooltip.lines = {}
local native = ReadOnly({ type = Enum.TooltipDataLineType.UnitCriteriaProgress, lineIndex = 2, leftText = "Enemy forces: 1%" })
fixture.Run(Enum.TooltipDataType.Unit, tooltip, UnitData("enemy", { native }))
Check(not LineValue("Forces") and criteriaCalls == before + 1, "a second forces line joined Blizzard's own")
tooltip:Hide()
details.config.mythicForces = false
Build("enemy2")
Check(not LineValue("Forces"), "the forces switch did not turn the line off")
details.config.mythicForces = true
keystone = false

------------------------------------------------------------------ hidden lines
local function Rows()
    -- The level line mentions the guild's name: only the guild line goes.
    return { Row(2, "<Guild>"), Row(3, "Level 80 Orc Guild"), Row(4, "Horde"), Row(5, "PvP") }
end
local function Reset() for index = 1, 6 do _G["GameTooltipTextLeft" .. index].text = "line" .. index end end
local function BuildHidden(unit, rows, name) Reset(); Build(unit, rows, name); tooltip:Hide() end
BuildHidden("party1", Rows())
Check(GameTooltipTextLeft2.text == "line2" and GameTooltipTextLeft4.text == "line4" and GameTooltipTextLeft5.text == "line5",
    "lines were hidden without a choice")
details.config.hideGuild = true
BuildHidden("party1", Rows())
Check(GameTooltipTextLeft2.text == "" and GameTooltipTextLeft3.text == "line3" and GameTooltipTextLeft4.text == "line4"
    and GameTooltipTextLeft5.text == "line5", "the guild choice hid another line or not the guild")
details.config.hideGuild, details.config.hideFaction = false, true
BuildHidden("party1", Rows())
Check(GameTooltipTextLeft4.text == "" and GameTooltipTextLeft2.text == "line2" and GameTooltipTextLeft5.text == "line5",
    "the faction choice acted on other lines")
details.config.hideFaction, details.config.hidePvP = false, true
BuildHidden("party1", Rows())
Check(GameTooltipTextLeft5.text == "" and GameTooltipTextLeft4.text == "line4", "the PvP choice acted on other lines")
details.config.hideGuild, details.config.hideFaction = true, true
BuildHidden("party1", Rows())
Check(GameTooltipTextLeft2.text == "" and GameTooltipTextLeft4.text == "" and GameTooltipTextLeft5.text == ""
    and GameTooltipTextLeft3.text == "line3", "the choices do not combine")
-- Rows the game keeps private are never touched: not a secret text, not an
-- unreadable row, not a restricted choice source.
local hidden = { Row(2, secret), ReadOnly({ blocked = true }), Row(4, "Horde"), Row(5, secret) }
BuildHidden("party1", hidden)
Check(GameTooltipTextLeft2.text == "line2" and GameTooltipTextLeft5.text == "line5" and GameTooltipTextLeft4.text == "",
    "a secret or unreadable row was touched")
GetGuildInfo = function() return secret end
UnitFactionGroup = function() return "Horde", secret end
PVP = secret
BuildHidden("party1", Rows())
Check(GameTooltipTextLeft2.text == "line2" and GameTooltipTextLeft4.text == "line4" and GameTooltipTextLeft5.text == "line5",
    "a secret choice source hid lines")
GetGuildInfo = function() return "Guild", "Officer" end
UnitFactionGroup = function() return "Horde", "Horde" end
PVP = "PvP"
details.config.hideGuild, details.config.hideFaction, details.config.hidePvP = false, false, false
-- The realm of a name, with titles and without.
Reset()
Build("far", nil, "Title Far - OtherRealm")
Check(GameTooltipTextLeft1.text == "line1", "the realm was hidden without a choice")
details.config.hideRealm = true
Build("far", nil, "Title Far - OtherRealm")
Check(GameTooltipTextLeft1.text == "Title Far", "the realm stayed in the name line")
Build("far", nil, "Title Far-OtherRealm")
Check(GameTooltipTextLeft1.text == "Title Far", "a hyphen without spaces kept the realm")
Reset()
Build("far", nil, "Title Far - Elsewhere")
Check(GameTooltipTextLeft1.text == "line1", "a name that does not end in the realm was changed")
Build("far", nil, secret)
Check(GameTooltipTextLeft1.text == "line1", "a secret name line was changed")
details.config.titles = false
Build("far", nil, "Title Far - OtherRealm")
Check(GameTooltipTextLeft1.text == "Far", "a name without titles kept the hidden realm")
details.config.hideRealm = false
Build("far", nil, "Title Far - OtherRealm")
Check(GameTooltipTextLeft1.text == "Far-OtherRealm", "a name without titles lost its realm without the choice")
details.config.titles = true
tooltip:Hide()

------------------------------------------------------------------ scale and reveal key
-- The OnShow hook scales relative to Blizzard's scale and OnHide gives it back.
visibility.config.scale = 150
tooltip:Show()
Check(tooltip.scale == 1.5, "the tooltip was not scaled on show")
tooltip:Hide()
Check(tooltip.scale == 1, "the scale stayed after the tooltip hid")
tooltip.scale = .8
tooltip:Show()
Check(math.abs(tooltip.scale - 1.2) < 1e-9, "the scale ignored Blizzard's own scale")
visibility.config.scale = 50
visibility:Refresh()
Check(math.abs(tooltip.scale - .4) < 1e-9, "a scale change did not reach the shown tooltip")
visibility.config.scale = 100
visibility:Refresh()
Check(tooltip.scale == .8, "the default scale did not give Blizzard's back")
tooltip:Hide()
visibility.config.scale = 120
tooltip:Show()
visibility.active = false
visibility:Disable()
Check(tooltip.scale == .8, "disabling the module kept the scale")
tooltip:Hide()
visibility.active = true
tooltip.scale = 1
tooltip:Show()
Check(math.abs(tooltip.scale - 1.2) < 1e-9, "re-enabled module did not scale")
tooltip:Hide()
visibility.config.scale = 100

-- The reveal key is watched only while the rules hide a tooltip.
visibility.config.inCombat, visibility.config.revealModifier = true, 2
visibility:Refresh()
Check(not visibilityEvents.MODIFIER_STATE_CHANGED, "the reveal key was watched with nothing hidden")
tooltip:Show()
Check(tooltip.alpha == 1 and not visibilityEvents.MODIFIER_STATE_CHANGED, "a tooltip outside combat was watched")
visibilityEvents.PLAYER_REGEN_DISABLED(visibility, "PLAYER_REGEN_DISABLED")
combat = true
Check(tooltip.alpha == 0 and visibilityEvents.MODIFIER_STATE_CHANGED, "a hidden tooltip does not watch the reveal key")
mods.shift = true
visibilityEvents.MODIFIER_STATE_CHANGED(visibility, "MODIFIER_STATE_CHANGED", "LSHIFT", 1)
Check(tooltip.alpha == 1 and visibilityEvents.MODIFIER_STATE_CHANGED, "the held key did not show the hidden tooltip")
mods.shift = false
visibilityEvents.MODIFIER_STATE_CHANGED(visibility, "MODIFIER_STATE_CHANGED", "LSHIFT", 0)
Check(tooltip.alpha == 0, "releasing the key did not hide the tooltip again")
mods.ctrl = true
visibilityEvents.MODIFIER_STATE_CHANGED(visibility, "MODIFIER_STATE_CHANGED", "LCTRL", 1)
Check(tooltip.alpha == 0, "another key showed the hidden tooltip")
mods.ctrl, mods.shift = false, secret
visibilityEvents.MODIFIER_STATE_CHANGED(visibility, "MODIFIER_STATE_CHANGED", "LSHIFT", 1)
Check(tooltip.alpha == 0, "a restricted key state showed the hidden tooltip")
mods.shift = false
tooltip:Hide()
Check(tooltip.alpha == 1 and not visibilityEvents.MODIFIER_STATE_CHANGED,
    "the reveal key was still watched after the tooltip hid")
-- A key held while the tooltip appears shows it at once.
mods.shift = true
combat = true
tooltip:Show()
Check(tooltip.alpha == 1 and visibilityEvents.MODIFIER_STATE_CHANGED, "a tooltip shown with the key held was hidden")
mods.shift = false
combat = false
visibilityEvents.PLAYER_REGEN_ENABLED(visibility, "PLAYER_REGEN_ENABLED")
Check(tooltip.alpha == 1 and not visibilityEvents.MODIFIER_STATE_CHANGED, "the key was watched after the rules ended")
tooltip:Hide()
-- None never watches the key.
visibility.config.revealModifier = 1
visibility:Refresh()
combat = true
tooltip:Show()
visibilityEvents.PLAYER_REGEN_DISABLED(visibility, "PLAYER_REGEN_DISABLED")
Check(tooltip.alpha == 0 and not visibilityEvents.MODIFIER_STATE_CHANGED, "the None choice watched the key")
mods.shift = true
tooltip:Hide()
combat = false
mods.shift = false
-- Every choice has its key.
for choice, key in pairs({ [3] = "ctrl", [4] = "alt" }) do
    visibility.config.revealModifier = choice
    visibility:Refresh()
    combat = true
    tooltip:Show()
    Check(tooltip.alpha == 0, "choice " .. choice .. " did not hide in combat")
    mods[key] = true
    visibilityEvents.MODIFIER_STATE_CHANGED(visibility, "MODIFIER_STATE_CHANGED")
    Check(tooltip.alpha == 1, "choice " .. choice .. " did not use its key")
    mods[key] = false
    tooltip:Hide()
    combat = false
end

------------------------------------------------------------------ owner chain
-- The real skin bridge and surface: a surface with an edge takes the color
-- and gives the theme's border back; a frame without one is left alone, so
-- the border falls to Blizzard's NineSlice.
do
    local surfaces = {}
    local theme = { .1, .2, .3, .8 }
    local skinNS = {
        Geometry = { ConfigureShape = function() end },
        BlizzardYellow = {},
        Registry = { AddListener = function() end, GetSurface = function(target) return surfaces[target] end },
        Theme = {
            GetMaterial = function() return { border = "border" } end,
            GetColor = function() return theme[1], theme[2], theme[3], theme[4] end,
            GetBorderOpacity = function() return .5 end,
        },
    }
    assert(loadfile(root .. "/MSUF_Suite_Skin/Rendering/Surface.lua"))("MSUF_Suite_Skin", skinNS)
    local edge = { shown = true, color = { .1, .2, .3, .4 } }
    function edge:IsShown() return self.shown end
    function edge:GetVertexColor() return unpack(self.color) end
    function edge:SetVertexColor(r, g, b, a) self.color = { r, g, b, a } end
    local suite = { IsCombatLocked = function() return false end }
    suite.Suite = { started = false }
    assert(loadfile(root .. "/MSUF_Suite/Integrations/MapkoSkin.lua"))("MSUF_Suite", suite)
    -- Surface.lua publishes itself as NS.Surface; the engine is the skin's namespace.
    MapkoSkin = { addonName = "MSUF_Suite_Skin", Surface = skinNS.Surface }
    local frame = {}
    Check(not suite.Skin.TintEdge(frame, 1, 0, 0), "a frame without a skin surface took a skin color")
    surfaces[frame] = { edge = edge, spec = { role = "popup" } }
    Check(suite.Skin.TintEdge(frame, 1, 0, 0) and edge.color[1] == 1 and edge.color[2] == 0 and edge.color[4] == .4,
        "the skin edge did not take the color and keep its alpha")
    Check(suite.Skin.TintEdge(frame) and edge.color[1] == .1 and edge.color[4] == .8 * .5,
        "the skin edge did not get the theme border back")
    edge.shown = false
    Check(not suite.Skin.TintEdge(frame, 1, 0, 0), "a hidden skin edge took a color")
    MapkoSkin = nil
    Check(not suite.Skin.TintEdge(frame, 1, 0, 0), "an absent skin engine took a color")
end

------------------------------------------------------------------ rules
-- No Tooltip file hooks a method of the shared tooltip, no method assigned
-- over it, and no error was reported.
local addon = "MSUF_Suite_QualityOfLife"
local scanned = 0
for _, file in ipairs(Support.TocFiles(root, addon)) do
    if file:match("^Tooltip.*%.lua$") then
        local handle = assert(io.open(root .. "/" .. addon .. "/" .. file, "rb"))
        local code = handle:read("*a"):gsub("%-%-%[(=*)%[.-%]%1%]", ""):gsub("%-%-[^\n]*", "")
        handle:close()
        Check(not code:find("hooksecurefunc%s*%(%s*_?G?%.?GameTooltip%s*,"), file .. " hooks a GameTooltip method")
        Check(not code:find("GameTooltip%.[%w_]+%s*=%s*function"), file .. " replaces a GameTooltip method")
        scanned = scanned + 1
    end
end
Check(scanned >= 9, "only " .. scanned .. " Tooltip files were scanned")
Check(#reported == 0, "an error was reported: " .. tostring(reported[1]))
print("Tooltip additions: " .. checks .. " checks passed")

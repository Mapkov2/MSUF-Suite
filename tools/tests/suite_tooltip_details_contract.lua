local root = assert(arg[1], "repository root required")
local Support = dofile(root .. "/tools/tests/suite_test_support.lua")
local checks = 0
local function Check(value, message) assert(value, message); checks = checks + 1 end

-- Widgets for the module's own Edit Mode sample.
local function Widget()
    local w = { shown = true, points = {} }
    function w:SetSize(x, y) self.width, self.height = x, y end
    function w:EnableMouse() end
    function w:SetAllPoints() end
    function w:SetColorTexture() end
    function w:SetPoint(...) self.points[#self.points + 1] = { ... } end
    function w:ClearAllPoints() self.points = {} end
    function w:SetText(value) self.text = value end
    function w:SetFont(...) self.font = { ... } end
    function w:Show() self.shown = true end
    function w:Hide() self.shown = false end
    function w:SetShown(value) self.shown = value == true end
    function w:IsShown() return self.shown end
    return w
end

local reported, movers = {}, {}
local S = {
    Public = function(value) return value ~= "secret" end,
    Text = function(value) return value end,
    Dispatch = Support.Dispatcher(reported),
    SetFont = function(w, ...) w:SetFont(...) end,
    RegisterOwnedMover = function(id, element, spec) movers[id] = { element = element, spec = spec } return true end,
}
S.PublicText = function(value) return S.Public(value) and type(value) == "string" and value ~= "" and value or nil end
S.Finite = function(value) return S.Public(value) and type(value) == "number" and value == value end
S.CreateFrame, S.CreateTexture, S.CreateFontString = Widget, Widget, Widget
local modules = {}
S.Install = function(id, m) modules[id] = m end
local combat = false
local NS = { Safety = { IsForbidden = function(frame) return frame.forbidden == true end },
    IsCombatLocked = function() return combat end, Finish = function(callback, ...) return true, callback(...) end }

-- hooksecurefunc as the client runs it: the global or table field becomes a
-- wrapper; holders of the original keep the original.
hooksecurefunc = function(owner, key, callback)
    if type(owner) == "string" then
        local original = _G[owner]
        _G[owner] = function(...) local a, b, c = original(...); key(...) return a, b, c end
        return
    end
    local original = owner[key]
    owner[key] = function(...) original(...); callback(...) end
end

-- GameTooltip as addon code meets it.
UIParent = Widget()
Enum = { TooltipDataType = { Item = 0, Spell = 1, Unit = 2 }, TooltipDataLineType = { UnitName = 2 } }
local tooltip = { shown = false, lines = {}, scripts = {}, shows = 0, points = {} }
function tooltip:AddDoubleLine(left, right, ...) self.lines[#self.lines + 1] = { left, right, ... } end
function tooltip:IsShown() return self.shown end
function tooltip:Show()
    self.shows = self.shows + 1
    local was = self.shown
    self.shown = true
    if not was and self.scripts.OnShow then self.scripts.OnShow(self) end
end
function tooltip:Hide()
    local was = self.shown
    self.shown = false
    if was and self.scripts.OnHide then self.scripts.OnHide(self) end
end
function tooltip:HookScript(name, callback)
    local old = self.scripts[name]
    self.scripts[name] = function(...) if old then old(...) end; callback(...) end
end
function tooltip:IsTooltipType(kind) return self.tooltipType == kind end
function tooltip:SetOwner(owner, anchor, x, y) self.owner, self.anchor, self.anchorX, self.anchorY = owner, anchor, x, y end
function tooltip:ClearAllPoints() self.points = {} end
function tooltip:SetPoint(...) self.points[#self.points + 1] = { ... } end
function tooltip:RefreshDataNextUpdate() error("addon code wrote GameTooltip's update fields") end
function tooltip:GetUnit() error("GetUnit tests the tooltip GUID, which can be secret") end
function tooltip:SetMountBySpellID() end
GameTooltip = tooltip
local health = { alpha = 1 }
function health:GetAlpha() return self.alpha end
function health:SetAlpha(value) self.alpha = value end
GameTooltipStatusBar = health
local nameText = {}
function nameText:SetText(value) self.text = value end
GameTooltipTextLeft1 = nameText
GameTooltip_SetDefaultAnchor = function(t, parent) t:SetOwner(parent, "ANCHOR_NONE") end

-- Units, auras, inspect.
local guids = { player = "GUID-player", party1 = "GUID-party1", party1target = "GUID-me" }
local secretIdentity, secretAuras, secretSlot = false, false, false
UnitGUID = function(unit) return guids[unit] or ("GUID-" .. unit) end
C_Secrets = {
    ShouldUnitIdentityBeSecret = function() return secretIdentity end,
    ShouldAurasBeSecret = function() return secretAuras end,
    ShouldUnitAuraSlotBeSecret = function() return secretSlot end,
}
canaccesstable = function(value) return not (type(value) == "table" and value.blocked) end
local auras, auraReads = {}, 0
C_UnitAuras = {
    GetAuraSlots = function(_, filter, batch, continuation)
        assert(filter == "HELPFUL" and batch == 32, "mount scan used another filter or page size")
        local first, slots = (continuation or 0) + 1, {}
        for index = first, math.min(#auras, first + batch - 1) do slots[#slots + 1] = index end
        local last = first + #slots - 1
        return last < #auras and last or nil, unpack(slots)
    end,
    GetAuraDataBySlot = function(_, slot) auraReads = auraReads + 1 return auras[slot] end,
}
local mountName, collectedValue = "Hovered mount", false
C_MountJournal = {
    GetMountFromSpell = function(spell) return spell == 321 and 7 or spell == 99 and 9 or nil end,
    GetMountInfoByID = function() return mountName, 321, 1, false, true, 1, false, false, nil, false, collectedValue end,
}
local inspectRequests, now = 0, 1000
local timers = {}
C_Timer = { After = function(delay, callback) timers[#timers + 1] = { delay = delay, callback = callback } end }
GetTime = function() return now end
local inspectable = true
CanInspect = function() return inspectable end
UnitIsDeadOrGhost = function() return false end
local inspectRaises = false
NotifyInspect = function()
    if inspectRaises then error("NotifyInspect raised") end
    inspectRequests = inspectRequests + 1
end
-- Another addon or the Inspect window asking the server, through the same API.
local function Foreign(unit)
    NotifyInspect(unit)
    inspectRequests = inspectRequests - 1
end
ClearInspectPlayer = function() end
local inspectLevel = 180
C_PaperDollInfo = { GetInspectItemLevel = function() return inspectLevel end }
GetAverageItemLevel = function() return 600, 610, 620 end
GetGuildInfo = function() return "guild", "Officer" end
UnitIsUnit = function(a, b) return a == b or a == "party1target" and b == "player" end
UnitIsPlayer = function() return true end
UnitName = function(unit)
    if unit == "party1target" then return "My player" end
    if unit == "party2" then return "Far", "OtherRealm" end
    return "Plain name"
end
UnitExists = function(unit) return unit:find("target$") ~= nil end
C_Item = { GetItemInfo = function() return "item", "link", 4, 100, nil, nil, nil, 200, nil, 1234 end }
C_Spell = { GetSpellTexture = function() return 4321 end }

local tooltips = Support.TooltipFixture(root, S, NS)
assert(loadfile(root .. "/MSUF_Suite_QualityOfLife/TooltipDetails.lua"))("test", { NS = NS, Suite = S })
local m = modules.tooltipDetails
m.active, m.events = true, {}
m.config = { guildRank = true, target = true, selfTarget = true, itemLevel = true, inspectHovered = false,
    hideHealth = true, maxStack = true, iconID = true, ownedMount = true, titles = true, unitMount = false,
    unitMountOwned = false, anchor = 2, cursorX = 19, cursorY = 23, growth = 3, fixedX = -24, fixedY = 24 }
NS.Dispatch = S.Dispatch
m.context = Support.ModuleTimers(root, S, NS)("tooltipDetails", m, {
    Event = function(_, event, callback) m.events[event] = callback end,
    RemoveEvent = function(_, event) m.events[event] = nil end })
m:Enable()
m:Enable()
Check(#tooltips.post[Enum.TooltipDataType.Unit] == 1 and #tooltips.post[Enum.TooltipDataType.Item] == 1
    and not next(tooltips.pre), "tooltip details registered twice or used a line pre-call")

-- One native unit build: Blizzard's name line first, then the post-calls,
-- then Show(). Blizzard's line data is read only.
local function Data(unit)
    local line = { type = Enum.TooltipDataLineType.UnitName, unitToken = unit, lineIndex = 1, leftText = "Title Name" }
    return { lines = { setmetatable({}, { __index = line, __newindex = function(_, key)
        error("tooltip line data was written: " .. tostring(key))
    end }) } }
end
local function Build(unit)
    tooltip.lines, tooltip.tooltipType = {}, Enum.TooltipDataType.Unit
    tooltips.Run(Enum.TooltipDataType.Unit, tooltip, Data(unit))
    tooltip:Show()
end
local function Leave() tooltip:Hide() end
local function LineValue(label)
    for _, line in ipairs(tooltip.lines) do if line[1] == label then return line[2], line end end
end

-- Guild rank, target and the plain item level paths send no request.
Build("party1")
Check(LineValue("Guild rank") == "Officer" and LineValue("Target") == "My player" and health.alpha == 0,
    "guild rank, target or hidden health bar missing")
local _, targetLine = LineValue("Target")
Check(targetLine[8] == .2, "a target that is you was not highlighted")
Check(inspectRequests == 0 and not LineValue("Item level"),
    "item level of another player sent an inspect request without the opt-in")
Leave()
Check(health.alpha == 1, "the health bar did not come back when the tooltip hid")
Build("player")
Check(LineValue("Item level") == "610", "own item level missing")
Leave()
-- The Inspect window loads on demand; its unit's level follows INSPECT_READY.
InspectFrame = { shown = true, unit = "party1" }
function InspectFrame:IsShown() return self.shown end
Build("party1")
Check(not LineValue("Item level"), "the Inspect window's level showed before INSPECT_READY")
m.events.INSPECT_READY(m, "INSPECT_READY", "GUID-other")
Leave(); Build("party1")
Check(not LineValue("Item level"), "another GUID completed the Inspect window's level")
m.events.INSPECT_READY(m, "INSPECT_READY", "GUID-party1")
Leave(); Build("party1")
Check(LineValue("Item level") == "180" and inspectRequests == 0, "the Inspect window's level missing")
Foreign("party1")
Leave(); Build("party1")
Check(not LineValue("Item level"), "a new inspect request kept the old readiness")
m.events.INSPECT_READY(m, "INSPECT_READY", "GUID-party1")
combat = true
Leave(); Build("party1")
Check(not LineValue("Item level"), "combat displayed an inspected level")
combat = false
Leave()
InspectFrame.shown, InspectFrame.unit = false, nil

-- Hovered players' item levels are a separate opt-in that sends requests.
m.config.inspectHovered = true
now = 1010
Build("party2")
Check(inspectRequests == 1 and m.pendingInspect.guid == "GUID-party2", "an eligible hover did not request once")
tooltips.Run(Enum.TooltipDataType.Unit, tooltip, Data("party2"))
Check(inspectRequests == 1, "a rebuild duplicated the request")
m.events.INSPECT_READY(m, "INSPECT_READY", "GUID-other")
Check(m.pendingInspect, "an unrelated completion consumed the pending hover")
local shows = tooltip.shows
m.events.INSPECT_READY(m, "INSPECT_READY", "GUID-party2")
Check(LineValue("Item level") == "180" and not m.pendingInspect and tooltip.shows == shows + 1,
    "the hover completion did not paint and size its level")
Build("party2")
Check(inspectRequests == 1 and LineValue("Item level") == "180", "the completed hover was not cached")
Leave()
-- A token that now names another unit: the next build is for that unit.
now = 1020
Build("swapA")
Check(inspectRequests == 2, "a second identity was not inspected")
Leave(); Build("swapB")
m.events.INSPECT_READY(m, "INSPECT_READY", "GUID-swapA")
Check(not LineValue("Item level") or LineValue("Item level") ~= "180", "a stale unit's level reached another unit")
Leave()
-- Quiet period after any request: one delayed attempt, cancelled by others.
now = 1022
Build("delayed")
-- The module's waits are context timers (ctx:After keeps one handle per
-- function); the retry is the one After handle.
local function RetryHandle()
    for _, handle in pairs(m.context.timers) do
        if handle.Start and handle.Pending then return handle end
    end
end
-- Every native wait in flight runs once time reached it; a context wait
-- that a restart moved arms again for the rest.
local function RunDue()
    local queued = timers
    timers = {}
    for _, entry in ipairs(queued) do entry.callback() end
end
local retry = RetryHandle()
Check(retry and retry:Pending() and retry.due == now + 3 and inspectRequests == 2,
    "a hover inside the quiet period did not wait once")
Build("delayed")
Check(retry.due == 1025, "the same hover scheduled a second retry")
now = 1025
RunDue()
Check(inspectRequests == 3 and m.pendingInspect.guid == "GUID-delayed", "the delayed attempt did not request")
Foreign("external")
Check(not m.pendingInspect, "a foreign request did not take over the inspect buffer")
Leave()
now = 1027
Build("quiet")
retry = RetryHandle()
Check(retry:Pending(), "the quiet hover did not wait")
ClearInspectPlayer()
Check(not retry:Pending(), "a foreign clear did not cancel the delayed hover")
Leave()
-- Native or foreign inspect activity, combat and restrictions suppress requests.
now = 1100
InspectFrame.shown = true
Build("native")
Check(inspectRequests == 3, "the open Inspect window did not suppress requests")
InspectFrame.shown = false
Leave()
PlayerSpellsFrame = { IsInspecting = function() return true end }
Build("talents")
Check(inspectRequests == 3, "the inspected talent window did not suppress requests")
PlayerSpellsFrame = nil
Leave()
combat = true
Build("fighter")
Check(inspectRequests == 3, "combat issued an inspect request")
combat = false
Leave()
inspectable = false
Build("far")
Check(inspectRequests == 3, "an uninspectable unit was inspected")
inspectable = true
Leave()
secretIdentity = true
Build("hidden")
Check(inspectRequests == 3, "a restricted identity was inspected")
secretIdentity = false
Leave()
-- Restricted values, timeouts and the bounded cache.
Build("restricted")
inspectLevel = "secret"
m.events.INSPECT_READY(m, "INSPECT_READY", "GUID-restricted")
Check(not LineValue("Item level"), "a restricted inspected value was displayed")
inspectLevel = 180
Leave()
now = 1200
Build("timeout")
now = 1211
m.events.INSPECT_READY(m, "INSPECT_READY", "GUID-timeout")
Check(not LineValue("Item level") and not m.pendingInspect, "an expired response was accepted")
Leave()
for i = 1, 17 do
    now = 1300 + i * 6
    Build("bounded" .. i)
    m.events.INSPECT_READY(m, "INSPECT_READY", "GUID-bounded" .. i)
    Leave()
end
local before = inspectRequests
now = 1410
Build("bounded1")
Check(inspectRequests == before + 1, "the cache kept an evicted identity")
Leave()
-- One real attempt per continuous hover, even without a response.
now = 1500
Build("silent")
local attempts = inspectRequests
for _, t in ipairs({ 1511, 1530, 1560 }) do now = t; tooltips.Run(Enum.TooltipDataType.Unit, tooltip, Data("silent")) end
Check(inspectRequests == attempts, "a continuous hover requested again")
Leave()
now = 1566
Build("silent")
Check(inspectRequests == attempts + 1, "a fresh hover could not request again")
Leave()
-- A NotifyInspect that raises is reported and leaves neither its request
-- nor the own-request mark behind: a later request of the same unit by
-- another addon still takes over the shared buffer.
now = 1700
local errors = #reported
inspectRaises = true
Build("broken")
inspectRaises = false
Check(#reported == errors + 1 and m.issuingInspect == nil and not m.pendingInspect,
    "a raising inspect request kept its own-request mark or its request")
m.inspectAttempted = nil
Foreign("broken")
Check(m.inspectAttempted, "a foreign request after a raising one was taken for the Suite's own")
Leave()
reported[#reported] = nil
m.config.inspectHovered = false

-- Names without titles: the name line's text, never the line data.
m.config.titles = false
Build("party2")
Check(nameText.text == "Far-OtherRealm", "a name without titles lost its realm")
Leave()
UnitName = function() return "secret" end
nameText.text = nil
Build("party3")
Check(nameText.text == nil, "a secret name reached the tooltip")
UnitName = function(unit) return unit == "party1target" and "My player" or "Plain name" end
Leave()
m.config.titles = true

-- Mounts: read once per hovered identity, out of combat, without UNIT_AURA.
m.config.guildRank, m.config.target, m.config.itemLevel = false, false, false
m.config.unitMount, m.config.unitMountOwned = true, true
auras = { { spellId = 21 }, { spellId = 321 }, { spellId = 999 } }
auraReads = 0
Build("mouseover")
Check(auraReads == 2 and LineValue("Mount") == "Hovered mount" and LineValue("Mount collection") == "Not collected"
    and not m.events.UNIT_AURA, "the hovered mount or its collection state is wrong")
Build("mouseover")
Check(auraReads == 2 and #tooltip.lines == 2, "a rebuild rescanned the unit or duplicated lines")
guids.mouseover = "GUID-other-mount"
auras = {}
Build("mouseover")
Check(auraReads == 2 and #tooltip.lines == 0, "a new identity kept another unit's mount")
guids.mouseover = nil
Leave()
auras = { { spellId = 321 } }
collectedValue = true
Build("mouseover")
Check(auraReads == 3 and LineValue("Mount collection") == "Collected", "a new hover did not read once")
Leave()
for _, value in ipairs({ "secret", "invalid", nil }) do
    collectedValue = value
    Build("mouseover")
    Check(#tooltip.lines == 1, "an unknown collection state was shown as not collected")
    Leave()
end
collectedValue = false
m.config.unitMountOwned = false
Build("mouseover")
Check(#tooltip.lines == 1 and LineValue("Mount"), "the mount name switch did not act alone")
Leave()
m.config.unitMount, m.config.unitMountOwned = false, true
Build("mouseover")
Check(#tooltip.lines == 1 and LineValue("Mount collection"), "the collection switch did not act alone")
Leave()
m.config.unitMount = true
before = auraReads
combat = true
Build("mouseover")
Check(auraReads == before and #tooltip.lines == 0, "combat scanned or displayed a hovered mount")
combat = false
Leave()
secretIdentity = true
Build("mouseover")
Check(auraReads == before and #tooltip.lines == 0, "a restricted identity reached the aura scan")
secretIdentity = false
Leave()
secretAuras = true
Build("mouseover")
Check(auraReads == before and #tooltip.lines == 0, "the aura secrecy predicate did not stop the scan")
secretAuras = false
Leave()
secretSlot = true
Build("mouseover")
Check(auraReads == before and #tooltip.lines == 0, "slot secrecy did not stop the scan")
secretSlot = false
Leave()
auras = { { spellId = "secret" } }
Build("mouseover")
Check(#tooltip.lines == 0, "a secret spell ID reached the mount journal")
Leave()
auras = { { blocked = true } }
Build("mouseover")
Check(#tooltip.lines == 0, "an inaccessible aura table was used")
Leave()
auras = {}
for i = 1, 129 do auras[i] = { spellId = 21 } end
auras[129] = { spellId = 321 }
before = auraReads
Build("mouseover")
Check(auraReads == before + 129 and #tooltip.lines == 2, "a mount behind the first pages was missed")
Leave()
local slots = C_UnitAuras.GetAuraSlots
C_UnitAuras.GetAuraSlots = function() return 1, 1 end
auras = { { spellId = 21 } }
before = auraReads
Build("mouseover")
Check(auraReads == before + 2 and #tooltip.lines == 0, "a page that does not progress was scanned forever")
C_UnitAuras.GetAuraSlots = slots
Leave()
local getSlot = C_UnitAuras.GetAuraDataBySlot
C_UnitAuras.GetAuraDataBySlot = function() error("aura access refused") end
auras = { { spellId = 321 } }
Build("mouseover")
Build("mouseover")
Check(#tooltip.lines == 0 and #reported == 1, "a raising aura read was swallowed or repeated")
C_UnitAuras.GetAuraDataBySlot = getSlot
Leave()
reported = {}
S.Dispatch = Support.Dispatcher(reported)
mountName = "secret"
Build("mouseover")
Check(#tooltip.lines == 0, "a secret mount name was displayed")
mountName = "Hovered mount"
Leave()
Build("mouseover")
before = auraReads
m:Refresh()
Build("mouseover")
Check(auraReads == before + 1, "a settings refresh kept the hover cache")
Leave()

-- Item, spell and mount journal tooltips.
tooltip.lines = {}
tooltips.Run(Enum.TooltipDataType.Item, tooltip, { id = 4 })
Check(LineValue("Maximum stack") == "200" and LineValue("Item icon ID") == "1234", "item details missing")
tooltips.Run(Enum.TooltipDataType.Spell, tooltip, { id = 10 })
Check(LineValue("Spell icon ID") == "4321", "spell icon ID missing")
tooltip.lines = {}
tooltips.Run(Enum.TooltipDataType.Item, tooltip, { id = "secret" })
Check(#tooltip.lines == 0, "restricted item data was displayed")
shows = tooltip.shows
tooltip:SetMountBySpellID(99)
Check(LineValue("Mount collection") and tooltip.shows == shows + 1,
    "the mount journal marker was added without sizing the tooltip again")

-- Anchors: cursor offsets need ANCHOR_CURSOR_RIGHT; corners keep inward offsets.
GameTooltip_SetDefaultAnchor(tooltip, UIParent)
Check(tooltip.anchor == "ANCHOR_CURSOR_RIGHT" and tooltip.anchorX == 19 and tooltip.anchorY == 23,
    "cursor anchor offsets missing")
m.config.anchor = 3
GameTooltip_SetDefaultAnchor(tooltip, UIParent)
local point = tooltip.points[1]
Check(point[1] == "TOPRIGHT" and point[4] == -24 and point[5] == -24, "a top corner placed the tooltip off screen")
m.config.growth = 2
GameTooltip_SetDefaultAnchor(tooltip, UIParent)
point = tooltip.points[1]
Check(point[1] == "BOTTOMLEFT" and point[4] == 24 and point[5] == 24, "a left corner placed the tooltip off screen")
tooltip._msufUnitTooltipOwner = {}
tooltip.points = {}
GameTooltip_SetDefaultAnchor(tooltip, UIParent)
Check(tooltip.anchor == "ANCHOR_NONE" and not tooltip.points[1], "the general anchor took over an MSUF unit tooltip")
tooltip._msufUnitTooltipOwner = nil
S.editMode = true
m:Refresh()
local spec = movers.tooltipDetails.spec
Check(m.preview:IsShown() and spec.getFrame() == m.preview and spec.isEnabled() and spec.point() == "BOTTOMLEFT",
    "the fixed corner lacks its own Edit Mode sample")
point = m.preview.points[1]
Check(point[1] == "BOTTOMLEFT" and point[4] == 24 and point[5] == 24, "the sample ignored the inward corner offsets")
local origin = { fixedX = -24, fixedY = 24 }
spec.capture(origin)
Check(origin.fixedX == 24 and origin.fixedY == 24, "a drag did not start from the shown offsets")
Check(spec.place(40, 30) and m.preview.points[1][4] == 40, "the drag preview ignored its offsets")
m.config.anchor = 2
m:Refresh()
Check(not m.preview:IsShown() and not spec.isEnabled(), "the cursor anchor kept the fixed corner mover")
S.editMode = false
m.active = false
m:Disable()
Build("party1")
Check(#tooltip.lines == 0 and health.alpha == 1 and #reported == 0, "the disabled module kept adding lines")
print("Tooltip details: " .. checks .. " checks passed")

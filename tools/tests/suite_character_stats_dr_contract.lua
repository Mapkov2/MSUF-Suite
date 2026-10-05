local root = assert(arg[1], "repository root required")
local skin = root .. "/MSUF_Suite_Skin/Adapters/"

-- Blizzard's callback isolation: an error is reported and the caller goes on.
local reported = {}
securecallfunction = function(callback, ...)
    local results = { pcall(callback, ...) }
    if not results[1] then
        reported[#reported + 1] = tostring(results[2])
        return
    end
    return unpack(results, 2, table.maxn(results))
end

-- hooksecurefunc post-hooks: the original runs first, then the hook.
function hooksecurefunc(target, method, callback)
    local original = target[method]
    assert(type(original) == "function", "hook target missing: " .. tostring(method))
    target[method] = function(...)
        original(...)
        callback(...)
    end
end

-- The contract drives EnhanceQoL's hooks itself; its load continuation never fires.
EventUtil = { ContinueOnAddOnLoaded = function() end }
-- The shared tooltip, owned by nothing in this contract.
GameTooltip = {
    IsOwned = function() return false end,
    Hide = function() end,
    SetOwner = function() end,
    SetText = function() end,
    Show = function() end,
}

local locales = {}
local NS = {
    Safety = assert(loadfile(root .. "/MSUF_Suite_Skin/Core/Safety.lua"))("MSUF_Suite_Skin", {}),
    Registry = { AddListener = function() end },
    IsCombatLocked = function() return false end,
    RegisterLocale = function(locale, values) locales[locale] = values end,
    -- Retail: the dossier and its modern equipment rows are available.
    Client = { modernEquipment = true, IsGamepadUI = function() return false end },
}
assert(loadfile(root .. "/MSUF_Suite_Skin/Locales/enUS.lua"))("MSUF_Suite_Skin", NS)
NS.L = locales.enUS
-- German through the Suite's pack, as the skin reads it (Localization.lua).
local German = dofile(root .. "/tools/tests/suite_test_support.lua").SkinLocale(root, "deDE")
assert(loadfile(skin .. "AdapterKit.lua"))("MSUF_Suite_Skin", NS)
assert(loadfile(skin .. "SharedChrome.lua"))("MSUF_Suite_Skin", NS)
assert(loadfile(skin .. "CharacterStats.lua"))("MSUF_Suite_Skin", NS)
local stats = assert(NS.CharacterStats)

local ratings = { 350, 120, 410, 0 }
local curveCalls = 0
local function Curve(id, value)
    assert(id == 21024)
    curveCalls = curveCalls + 1
    if value <= 30 then return value end
    if value <= 40 then return 30 + (value - 30) * .9 end
    return 39 + (value - 40) * .8
end
GetCombatRating = function(index) return ratings[index] end
GetCombatRatingBonus = function(index) return Curve(21024, ratings[index] * .1) end
GetCombatRatingBonusForCombatRatingValue = function(_, value) return value * .1 end
C_CurveUtil = { EvaluateGameCurve = Curve }
PlayerIsTimerunning = function() return false end
issecretvalue = function() return false end

local crit = stats.ReadRating(1, {})
assert(math.abs(crit.penalty - 10) < .001)
assert(math.abs(crit.inDR - 50) < .1 and math.abs(crit.lostRating - 5) < .001,
    "rating in DR and rating lost to DR were conflated")
assert(stats.DRBadge(crit) == "(10% DR, +50)")
assert(stats.DRBadge({ penalty = 20, inDR = 1240 }) == "(20% DR, +1.2k)")
local afterDiscovery = curveCalls
local mastery = stats.ReadRating(3, {})
assert(math.abs(mastery.inDR - 110) < .1 and math.abs(mastery.lostRating - 12) < .001)
assert(curveCalls - afterDiscovery < 8, "the first DR breakpoint was rediscovered for each stat")
local haste = stats.ReadRating(2, {})
assert(haste.penalty == 0 and haste.inDR == 0 and haste.lostRating == 0)
assert(stats.DRBadge(haste) == "(0% DR)", "zero DR should be visible in parentheses")

NS.L = German
assert(stats.DRBadge(crit) == "(10% DR, +50)")
assert(string.format(NS.L.STATS_DR_AMOUNT, crit.inDR, crit.lostRating):find("Wertung", 1, true))
assert(stats.DRBadge({}) == "(DR ?)", "unknown data was rendered as verified zero DR")

local bonus = GetCombatRatingBonus
GetCombatRatingBonus = function() return 999 end
local unknown = stats.ReadRating(1, {})
assert(unknown.penalty == nil and unknown.inDR == nil and unknown.lostRating == nil)
GetCombatRatingBonus = bonus
PlayerIsTimerunning = function() return true end
unknown = stats.ReadRating(1, {})
assert(unknown.penalty == nil and unknown.inDR == nil)
PlayerIsTimerunning = function() return false end
NS.L = locales.enUS

-- A client without the rating curve raises from EvaluateGameCurve. The curve
-- is probed once, the failure is reported, and the DR details fail closed.
local function Fresh(file)
    local copy = setmetatable({}, { __index = NS })
    assert(loadfile(skin .. file))("MSUF_Suite_Skin", copy)
    return copy
end
local brokenCalls = 0
C_CurveUtil = { EvaluateGameCurve = function()
    brokenCalls = brokenCalls + 1
    error("contract: unknown curve")
end }
local freshStats = Fresh("CharacterStats.lua").CharacterStats
local before = #reported
local firstRead, first = pcall(freshStats.ReadRating, 1, {})
local secondRead, second = pcall(freshStats.ReadRating, 3, {})
assert(firstRead and secondRead and first.rating == 350 and first.penalty == nil
    and second.penalty == nil, "a missing rating curve raised or produced DR data")
assert(brokenCalls == 1 and #reported == before + 1,
    "the missing rating curve was not probed exactly once and reported")
C_CurveUtil = { EvaluateGameCurve = Curve }

-- Widgets for the stat pane and the dossier: plain objects with the few
-- methods the adapters call.
local NOOP = function() end
local combatLocked = false
local NOOP_METHODS = {
    "SetSize", "SetPoint", "ClearAllPoints", "SetAllPoints", "EnableMouse", "SetFrameLevel",
    "SetFont", "SetJustifyH", "SetWordWrap", "SetWidth", "SetColorTexture", "SetTexture",
    "SetTexCoord", "SetClampedToScreen", "SetFontObject", "SetFrameStrata", "SetParent",
}
local function Object(fields)
    local object = fields or {}
    object.scripts, object.events = {}, {}
    if object.shown == nil then object.shown = true end
    object.height = object.height or 20
    for index = 1, #NOOP_METHODS do
        object[NOOP_METHODS[index]] = object[NOOP_METHODS[index]] or NOOP
    end
    function object:SetScript(name, callback) self.scripts[name] = callback end
    function object:HookScript(name, callback) self.scripts[name] = callback end
    function object:RegisterEvent(event) self.events[event] = true end
    function object:UnregisterEvent(event) self.events[event] = nil end
    function object:Show()
        local wasShown = self.shown
        self.shown = true
        if not wasShown and self.scripts.OnShow then self.scripts.OnShow(self) end
    end
    function object:Hide()
        local wasShown = self.shown
        self.shown = false
        if wasShown and self.scripts.OnHide then self.scripts.OnHide(self) end
    end
    function object:SetShown(shown) if shown then self:Show() else self:Hide() end end
    function object:IsShown() return self.shown end
    function object:IsVisible() return self.shown end
    function object:GetHeight() return self.height end
    function object:SetHeight(height)
        assert(not combatLocked, "native stat height changed during lockdown")
        self.height = height
    end
    function object:GetWidth() return self.width or 100 end
    function object:GetFrameLevel() return 1 end
    function object:GetName() return nil end
    function object:GetNumPoints() return 0 end
    function object:GetText() return self.text end
    function object:SetText(text) self.text = text end
    function object:GetFont() return "Fonts\\FRIZQT__.TTF", 12, "" end
    function object:GetTextColor() return 1, 1, 1, 1 end
    function object:SetTextColor() end
    function object:CreateFontString() return Object() end
    function object:CreateTexture() return Object() end
    return object
end
CreateFrame = function() return Object() end
-- Blizzard_Fonts_Shared loads at startup on every client; the adapters read
-- its font without a check.
GameFontNormal = Object()
NS.CombatGate = {
    RunOrDefer = function(_, callback)
        if NS.IsCombatLocked() then return false end
        callback()
        return true
    end,
    Cancel = NOOP,
}
NS.Surface = { Attach = function() return {} end, Ensure = function() return {} end,
    SkinOwnedButton = NOOP, SetVisible = NOOP }
NS.Theme = { GetColor = function() return 0.9, 0.9, 0.9, 1 end }
NS.GenericWindows = { IsCategoryEnabled = function() return true end }
-- The dossier (CharacterDetails.lua) always loads first; here it is modern.
NS.CharacterDetails = { IsModern = function() return true end }
NS.GearAnnotations = {
    IsWide = function() return false end,
    ApplyLayout = NOOP, RestoreLayout = NOOP, Paint = NOOP, Update = NOOP,
    UpdateSummary = NOOP, Hide = NOOP,
}
NS.WindowActionSkin = { Apply = function() return nil end, DisableOwner = NOOP, Disable = NOOP }
NS.DB = {
    enabled = true,
    skins = {},
    characterStats = { enabled = true, diminishingReturns = true },
    characterDetails = { enabled = true, expanded = true },
}
NS.IsCombatLocked = function() return combatLocked end

-- PLAYER_REGEN_DISABLED fires before the lockdown starts. A stat pane shown
-- at the pull keeps its layout (no jump back to Blizzard's rows); a refresh
-- asked for during combat waits for PLAYER_REGEN_ENABLED.
local enumerations = 0
local statRow = Object({ Label = Object(), Value = Object() })
local pane = Object({
    ItemLevelCategory = Object({ Title = Object() }),
    AttributesCategory = Object({ Title = Object() }),
    EnhancementsCategory = Object({ Title = Object() }),
    height = 400,
    statsFramePool = { EnumerateActive = function()
        enumerations = enumerations + 1
        local done = false
        return function()
            if done then return nil end
            done = true
            return statRow
        end
    end },
})
stats.Apply(pane, "stats")
local view = assert(stats.views[pane], "the stat pane was not styled")
local host = view.host
local rebuilt, laidOut = enumerations, statRow.height
assert(laidOut ~= 20 and view.heights[statRow], "the reproduction did not start with a laid-out row")
host.scripts.OnEvent(host, "PLAYER_REGEN_DISABLED")
assert(enumerations == rebuilt and host.events.PLAYER_REGEN_ENABLED,
    "combat start rebuilt the stat rows")
assert(statRow.height == laidOut and view.heights[statRow],
    "a stat pane shown at the pull jumped back to Blizzard's row heights")
combatLocked = true
stats.Refresh(view)
assert(statRow.height == laidOut and enumerations == rebuilt,
    "combat refresh resized or enumerated the native pool")
combatLocked = false
host.scripts.OnEvent(host, "PLAYER_REGEN_ENABLED")
assert(enumerations == rebuilt + 1 and not host.events.PLAYER_REGEN_ENABLED,
    "the stat rows were not refreshed after combat")

-- PaperDoll releases and reacquires its pool without resetting frame heights.
-- A close before combat must prepare even the retained, currently hidden rows.
local normalCreate, gateFrame = CreateFrame
CreateFrame = function(...)
    gateFrame = normalCreate(...)
    return gateFrame
end
assert(loadfile(root .. "/MSUF_Suite_Skin/Core/CombatGate.lua"))("MSUF_Suite_Skin", NS)
CreateFrame = normalCreate
STAT_CRITICAL_STRIKE, STAT_HASTE, STAT_MASTERY, STAT_VERSATILITY = "Crit", "Haste", "Mastery", "Versatility"
CR_CRIT_MELEE, CR_HASTE_MELEE, CR_MASTERY, CR_VERSATILITY_DAMAGE_DONE = 1, 2, 3, 4
local nativeRows = {}
for index, label in ipairs({"Crit", "Haste", "Mastery", "Versatility", "Agility", "Stamina", "Armor", "Leech", "Speed"}) do
    nativeRows[index] = Object({ Label = Object({text = label .. ":"}), Value = Object() })
end
local nativePane = Object({
    ItemLevelCategory = Object({Title = Object()}),
    ItemLevelFrame = Object({Value = Object()}),
    AttributesCategory = Object({Title = Object()}),
    EnhancementsCategory = Object({Title = Object()}),
    height = 400,
    statsFramePool = {EnumerateActive = function()
        local index = 0
        return function() index = index + 1; return nativeRows[index] end
    end},
})
NS.GearAnnotations.IsWide = function() return true end
stats.Apply(nativePane, "reopen")
local reopen = assert(stats.views[nativePane])
assert(nativeRows[1].height > 20 and reopen.rows[nativeRows[1]].meta:IsShown(),
    "the reproduction did not start with expanded DR rows")
nativeRows[9]:SetHeight(27) -- A later foreign geometry change must be preserved.
reopen.host:Hide()
for index = 1, 8 do assert(nativeRows[index].height == 20, "close retained expanded pooled geometry") end
assert(nativeRows[9].height == 27, "close overwrote newer foreign geometry")
assert(next(reopen.fonts) == nil and next(reopen.heights) == nil, "native snapshots not cleared")
combatLocked = true
-- Native pool reuse changes the meaning and order of existing frames.
nativeRows[1].Label:SetText("Agility:")
nativeRows[5].Label:SetText("Crit:")
reopen.host:Show()
stats.Apply(nativePane, "reopen")
-- The reopen's native stats update; CharacterPanel calls SyncDetails after
-- every update during combat (suite_forever_character_contract). Rows
-- restored on close show no details.
stats.SyncDetails(nativePane)
local occupied = nativePane.ItemLevelFrame.height
    + nativePane.ItemLevelCategory.height + nativePane.AttributesCategory.height
    + nativePane.EnhancementsCategory.height + 8
for _, row in ipairs(nativeRows) do
    occupied = occupied + row.height
    assert(not reopen.rows[row].meta:IsShown(), "combat reopen showed stale DR details")
end
assert(occupied <= nativePane.height, "combat reopen overflowed native stat pane")
combatLocked = false
gateFrame.scripts.OnEvent(gateFrame, "PLAYER_REGEN_ENABLED")
assert(reopen.rows[nativeRows[5]].meta:IsShown(), "post-combat refresh did not resolve reused row identity")

-- A pane shown at the pull keeps its rows and details. During combat every
-- native stats update reassigns the pooled rows; the layout waits (a resize
-- would trip the lockdown assertion in SetHeight), but a row that now shows
-- another stat loses its details at once, and the refresh after combat lays
-- the rows out for their new stats.
local function Details(index) return reopen.rows[nativeRows[index]].meta:IsShown() end
local heights = {}
for index, row in ipairs(nativeRows) do heights[index] = row.height end
reopen.host.scripts.OnEvent(reopen.host, "PLAYER_REGEN_DISABLED")
combatLocked = true
for index, row in ipairs(nativeRows) do
    assert(row.height == heights[index], "a stat pane shown at the pull jumped back to Blizzard's layout")
end
assert(Details(5) and Details(2) and nativeRows[5].height > nativeRows[6].height,
    "a stat pane shown at the pull lost its details")
nativeRows[5].Label:SetText("Stamina:")
nativeRows[6].Label:SetText("Crit:")
stats.SyncDetails(nativePane)
assert(not Details(5) and not Details(6) and Details(2),
    "a combat stats update left details on a row that shows another stat")
nativeRows[5].Label:SetText("Crit:")
nativeRows[6].Label:SetText("Stamina:")
stats.SyncDetails(nativePane)
assert(Details(5) and not Details(6), "a row that shows its stat again did not get its details back")
nativeRows[5].Label:SetText("Stamina:")
nativeRows[6].Label:SetText("Crit:")
stats.SyncDetails(nativePane)
combatLocked = false
reopen.host.scripts.OnEvent(reopen.host, "PLAYER_REGEN_ENABLED")
assert(Details(6) and not Details(5) and nativeRows[6].height > nativeRows[5].height,
    "the refresh after combat did not lay the reassigned rows out")

-- Closed and reopened in the same fight: the rows keep their details and
-- the refresh runs once after combat.
combatLocked = true
reopen.host:Hide()
reopen.host:Show()
assert(Details(6) and not Details(5), "a close and reopen in one fight changed the row details")
combatLocked = false
assert(not reopen.host.events.PLAYER_REGEN_ENABLED and NS.CombatGate.GetPendingCount() == 1,
    "combat reopen did not queue the refresh after its host event was unregistered")
gateFrame.scripts.OnEvent(gateFrame, "PLAYER_REGEN_ENABLED")
assert(Details(6), "combat close/reopen failed to resume detail rows")
assert(NS.CombatGate.GetPendingCount() == 0 and not gateFrame.events.PLAYER_REGEN_ENABLED,
    "combat reopen left a pending refresh or event listener")

-- Closed during combat: the rows get Blizzard's geometry back once combat
-- ends, so a later reopen starts from native dimensions.
combatLocked = true
nativePane:Hide()
reopen.host:Hide()
combatLocked = false
assert(NS.CombatGate.GetPendingCount() == 1, "a close during combat did not queue the restore")
gateFrame.scripts.OnEvent(gateFrame, "PLAYER_REGEN_ENABLED")
for index = 1, 8 do
    assert(nativeRows[index].height == 20, "a stat pane closed during combat kept expanded rows after it")
end
assert(next(reopen.heights) == nil and next(reopen.fonts) == nil and not Details(6),
    "a stat pane closed during combat kept its snapshots or details after combat")
nativePane:Show()
reopen.host:Show()
assert(Details(6) and nativeRows[6].height > 20, "the reopen after combat did not lay the rows out")

NS.GearAnnotations.IsWide = function() return false end

-- The dossier collects a burst of item events into one next-frame refresh.
local timers = {}
C_Timer = { After = function(_, callback) timers[#timers + 1] = callback end }
local reads = 0
NS.EquipmentInfo = {
    Read = function(_, _, _, result)
        reads = reads + 1
        result = result or { gemInfo = {} }
        result.itemLevel, result.link = 600, "item:1:0:"
        return result
    end,
    Check = NOOP,
    Invalidate = NOOP,
}
GetInventoryItemLink = function() return "item:1:0:" end
-- No specialization chosen and no inspect data.
C_SpecializationInfo = {
    GetSpecialization = function() return nil end,
    GetInspectSpecialization = function() return 0 end,
}
C_PaperDollInfo = { GetInspectItemLevel = function() return nil end }
GetInventoryItemDurability = function() return 50, 100 end
GetAverageItemLevel = function() return 600, 600 end
UnitGUID = function() return "Player-1" end
UnitName = function() return "Contract" end
UnitClass = function() return "Warrior" end
UnitLevel = function() return 90 end
PaperDollFrame = Object()
local details = Fresh("CharacterDetails.lua").CharacterDetails
local characterFrame = Object()
details.Apply(characterFrame, "character", "details")
local dossier = assert(details.views[characterFrame], "the dossier was not created")
assert(reads == 16, "the dossier did not read every slot when it opened")
local dossierHost = dossier.host
reads = 0
dossierHost.scripts.OnEvent(dossierHost, "PLAYER_EQUIPMENT_CHANGED", 5)
dossierHost.scripts.OnEvent(dossierHost, "UNIT_INVENTORY_CHANGED", "player")
dossierHost.scripts.OnEvent(dossierHost, "PLAYER_AVG_ITEM_LEVEL_UPDATE")
dossierHost.scripts.OnEvent(dossierHost, "PLAYER_EQUIPMENT_CHANGED", 6)
assert(reads == 0 and #timers == 1,
    "item events refreshed the dossier once per event instead of once per frame")
table.remove(timers, 1)()
assert(reads == 16, "the coalesced refresh did not read every slot exactly once")
dossierHost.scripts.OnEvent(dossierHost, "PLAYER_EQUIPMENT_CHANGED", 5)
dossierHost.scripts.OnEvent(dossierHost, "PLAYER_EQUIPMENT_CHANGED", 6)
assert(#timers == 1, "a gear swap scheduled more than one refresh")
table.remove(timers, 1)()
assert(reads == 18, "a gear swap re-read slots that did not change")
-- A slot request raised while the refresh runs, for a slot it has already
-- read, is kept for the next frame.
local readEquipment = NS.EquipmentInfo.Read
local slotReads, raisedDuringRefresh = {}, false
NS.EquipmentInfo.Read = function(link, unit, slot, ...)
    slotReads[slot] = (slotReads[slot] or 0) + 1
    if slot == 7 and not raisedDuringRefresh then
        raisedDuringRefresh = true
        dossierHost.scripts.OnEvent(dossierHost, "PLAYER_EQUIPMENT_CHANGED", 5)
    end
    return readEquipment(link, unit, slot, ...)
end
dossierHost.scripts.OnEvent(dossierHost, "PLAYER_EQUIPMENT_CHANGED", 7)
table.remove(timers, 1)()
assert(raisedDuringRefresh and #timers == 1, "a request raised during the refresh was not scheduled")
table.remove(timers, 1)()
NS.EquipmentInfo.Read = readEquipment
assert(slotReads[5] == 1 and slotReads[7] == 1, "a slot request raised during the refresh was dropped")
C_Timer = nil

-- Wide equipment geometry reads back with float noise: our own applied
-- values must never be taken for Blizzard's, so the native layout returns.
local NOISE = 0.00002
local function Geometry(width, height, point)
    local frame = Object({ width = width, height = height, scale = 1, points = { point } })
    function frame:GetWidth() return self.width + NOISE end
    function frame:SetWidth(value) self.width = value end
    function frame:GetHeight() return self.height + NOISE end
    function frame:SetHeight(value) self.height = value end
    function frame:GetScale() return self.scale + NOISE / 100 end
    function frame:SetScale(value) self.scale = value end
    function frame:GetNumPoints() return #self.points end
    function frame:GetPoint(index)
        local anchor = self.points[index]
        return anchor[1], anchor[2], anchor[3], anchor[4] + NOISE, anchor[5] + NOISE
    end
    function frame:ClearAllPoints() self.points = {} end
    function frame:SetPoint(...) self.points[#self.points + 1] = { ... } end
    return frame
end
-- UIParent's panel manager re-anchors a resized Character window.
local panelRepositions = 0
UpdateUIPanelPositions = function() panelRepositions = panelRepositions + 1 end
local gear = Fresh("GearAnnotations.lua").GearAnnotations
local characterRoot = Geometry(338, 424, { "TOPLEFT", nil, "TOPLEFT", 16, -116 })
characterRoot.activeSubframe = "PaperDollFrame"
characterRoot.UpdateSize = NOOP
local insetRight = Geometry(200, 400, { "TOPLEFT", characterRoot, "TOPRIGHT", 1, -60 })
characterRoot.InsetRight = insetRight
CharacterModelScene = Geometry(231, 320, { "TOPLEFT", characterRoot, "TOPLEFT", 52, -66 })
NS.DB.characterDetails = { enabled = true, inlineGear = true, wideLayout = true }
local wide = { kind = "character", active = true, host = Object(), root = characterRoot,
    panel = Object(), rows = {} }
gear.ApplyLayout(wide)
gear.ApplyLayout(wide)
assert(math.abs(characterRoot.width - 704) < 0.001, "the wide layout was not applied")
assert(panelRepositions == 1, "the resized Character window was not re-anchored exactly once")
gear.RestoreLayout(wide)
assert(panelRepositions == 2, "the restored Character window was not re-anchored")
assert(math.abs(characterRoot.width - 338) < 0.001
    and math.abs(CharacterModelScene.width - 231) < 0.001,
    "restoring the wide layout kept a size it had applied itself")
assert(#insetRight.points == 1 and math.abs(insetRight.points[1][4] - 1) < 0.001
    and insetRight.points[1][3] == "TOPRIGHT",
    "restoring the wide layout kept anchors it had applied itself")

-- EnhanceQoL's display callbacks: a raising layout pass is reported and never
-- reaches EnhanceQoL's caller.
local display = { Apply = NOOP, Clear = NOOP }
EnhanceQoL = { ItemEnchantDisplay = display, variables = { itemSlots = {} }, functions = {} }
local raiseView = false
local eqolNS = setmetatable({ CharacterDetails = {
    GetView = function()
        if raiseView then error("contract: EnhanceQoL layout raised") end
        return nil
    end,
    RefreshEQoL = NOOP,
} }, { __index = NS })
assert(loadfile(skin .. "EQoLCharacter.lua"))("MSUF_Suite_Skin", eqolNS)
local compat = eqolNS.EQoLCharacter
compat.Apply("eqol")
local element = Object()
raiseView = true
before = #reported
local finished = pcall(display.Apply, element)
raiseView = false
assert(finished and #reported == before + 1,
    "a raising EnhanceQoL layout pass escaped into EnhanceQoL's caller")
compat.Disable("eqol")

-- A provider label anchored to a secret region: its native anchor cannot be
-- restored, so disable never re-anchors it relative to its parent instead.
local SECRET = {}
local isSecret = issecretvalue
issecretvalue = function(value) return value == SECRET end
local headSlot = Object()
local label = Object()
label.points = { { "TOPLEFT", SECRET, "TOPLEFT", 2, -3 } }
function label:GetNumPoints() return #self.points end
function label:GetPoint(index) return unpack(self.points[index], 1, 5) end
function label:ClearAllPoints() self.points = {} end
function label:SetPoint(...) self.points[#self.points + 1] = { ... } end
function label:CanWordWrap() return false end
function label:GetJustifyH() return "LEFT" end
headSlot.enchant = label
CharacterHeadSlot = headSlot
EnhanceQoL = { ItemEnchantDisplay = { Apply = NOOP, Clear = NOOP },
    variables = { itemSlots = { [1] = headSlot } }, functions = {} }
local secretNS = setmetatable({ CharacterDetails = { GetView = function() return nil end, RefreshEQoL = NOOP } },
    { __index = NS })
assert(loadfile(skin .. "EQoLCharacter.lua"))("MSUF_Suite_Skin", secretNS)
secretNS.EQoLCharacter.Apply("eqol-secret")
assert(label.points[1] and label.points[1][2] == headSlot, "the provider label was not laid out")
secretNS.EQoLCharacter.Disable("eqol-secret")
issecretvalue = isSecret
for _, point in ipairs(label.points) do
    assert(point[2] ~= nil, "a label anchored to a secret region was restored relative to its parent")
end

-- Equipment snapshots call Retail's and Forever's item and tooltip APIs
-- directly. Item data that has not loaded yet (no tooltip lines, no gem
-- link) keeps the snapshot pending until a later read.
do
    local enum, item, tooltipInfo, tooltip = Enum, C_Item, C_TooltipInfo, GameTooltip
    Enum = { TooltipDataLineType = { GemSocket = 3, ItemEnchantmentPermanent = 15, ItemUpgradeLevel = 32 } }
    local tooltipLines, gemLink
    C_Item = {
        GetItemInfo = function()
            return "Contract Helm", nil, 4, nil, nil, nil, nil, nil, "INVTYPE_HEAD", 1234, nil, 4, 2, nil, 11
        end,
        GetItemGemID = function(_, index) return index == 1 and 555 or nil end,
        GetItemGem = function() return "Contract Gem", gemLink end,
        GetItemIconByID = function() return 99 end,
        GetItemUpgradeInfo = function() return { currentLevel = 3, maxLevel = 6, trackString = "Hero" } end,
        GetDetailedItemLevelInfo = function() return 639 end,
        GetItemNumSockets = function() return 2 end,
        GetItemStats = function() return { ITEM_MOD_CRIT_RATING_SHORT = 120 } end,
    }
    C_TooltipInfo = { GetInventoryItem = function()
        return tooltipLines and { lines = tooltipLines } or nil
    end }
    local added, wraps = {}, {}
    GameTooltip = { AddLine = function(_, text, _, _, _, wrap)
        added[#added + 1] = text
        wraps[#added] = wrap
    end }
    local info = Fresh("EquipmentInfo.lua").EquipmentInfo
    local snapshot = info.Read("item:1:0:", "player", 1, nil, "Player-1")
    assert(snapshot.name == "Contract Helm" and snapshot.itemLevel == 639 and snapshot.sockets == 2
        and snapshot.gems == 1 and snapshot.gemSlotsKnown and snapshot.upgradeText == "3/6"
        and snapshot.stats.ITEM_MOD_CRIT_RATING_SHORT == 120,
        "an equipment snapshot did not read the item APIs")
    assert(snapshot.pending and not snapshot.settled,
        "a snapshot without tooltip lines or gem link was settled")
    tooltipLines = {
        { type = 15, leftText = "|cffffffffContract Enchant|r" },
        { type = 3, gemIcon = 99 },
        { type = 3 },
    }
    gemLink = "item:555"
    snapshot = info.Read("item:1:0:", "player", 1, snapshot, "Player-1")
    assert(not snapshot.pending and snapshot.settled and snapshot.enchantText == "Contract Enchant"
        and snapshot.emptySockets == 1, "a loaded equipment snapshot stayed pending or lost its tooltip data")
    info.AddTooltip(info.Check(snapshot, 90))
    assert(#added > 0 and added[2] == NS.L.GEAR_TOOLTIP_TITLE, "the equipment tooltip lines were not added")
    -- Theme.GetColor returns r, g, b, a; AddLine's fifth argument is wrap.
    assert(wraps[2] == nil, "the theme colour's alpha reached AddLine as the title's wrap flag")
    Enum, C_Item, C_TooltipInfo, GameTooltip = enum, item, tooltipInfo, tooltip
end

print("Character stats and dossier: DR data, curve probe, combat rows, coalesced refresh, wide geometry and EnhanceQoL hooks passed")

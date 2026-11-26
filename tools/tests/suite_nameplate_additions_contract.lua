local root = assert(arg[1])
local secret = setmetatable({}, { __tostring = function() error("read secret text") end })
local function Public(value) return value ~= secret end
local function Finite(value) return Public(value) and type(value) == "number" and value == value end
local function Module(path, ...)
    return assert(loadfile(root .. "/" .. path))("suite", ...)
end

local NS = { Client = { isForever = false }, Public = Public, Finite = Finite,
    IsSecret = function(value) return not Public(value) end, Safety = { IsForbidden = function() return false end } }
local private = { NS = NS, Suite = NS, Geometry = {}, ExtensionLayout = {}, Mode = { LOOK_BLIZZARD = 2 } }
local writes, combat, selected, instance = 0, false, false, "none"
NS.IsCombatLocked = function() return combat end
NS.InCombat = NS.IsCombatLocked
NS.Client.AuraBuildBlocked = function() return false end
NS.Client.RealAurasOnly = function() end
NS.ResolveTexture = function(key) return key end
NS.NameplatePortableText = { Format = function(_, text) return text:sub(1, 4) end }
private.ExtensionLayout.Mutable = function() return not combat end

local function Region()
    local data = { alpha = .65, height = 13, level = 3, shown = false, texture = "native" }
    local function Count() writes = writes + 1 end
    function data:IsProtected() return combat end
    function data:IsShown() return self.shown end
    function data:GetFrameLevel() return self.level end
    function data:SetFrameLevel(level) Count() self.level = level end
    function data:SetPoint() Count() end
    function data:ClearAllPoints() Count() end
    function data:SetSize() Count() end
    function data:SetAllPoints() Count() end
    function data:SetAlpha(value) Count() self.alpha = value end
    function data:GetAlpha() return self.alpha end
    function data:SetAlphaFromBoolean(value) Count() self.alphaArgument = value end
    function data:SetParent(value) Count() self.parent = value end
    function data:SetText(text) Count() self.text = text end
    function data:SetTextColor() Count() end
    function data:SetTextHeight() Count() end
    function data:SetTexture(value) Count() self.texture = value end
    function data:GetTexture() return self.texture end
    function data:GetAtlas() return self.atlas end
    function data:SetAtlas(value) Count() self.atlas = value end
    function data:GetHeight() return self.height end
    function data:SetHeight(value) Count() self.height = value end
    function data:SetDrawEdge() Count() end
    function data:SetBlendMode() Count() end
    function data:SetEnabled(value) Count() self.enabled = value end
    function data:SetCooldown(start, duration) Count() self.timer = { start, duration } end
    function data:Show() Count() self.shown = true end
    function data:Hide() Count() self.shown = false end
    function data:CreateTexture() return Region() end
    function data:CreateFontString() return Region() end
    function data:RegisterEvent(event) Count() self.events = self.events or {} self.events[event] = true end
    function data:UnregisterEvent(event) Count() if self.events then self.events[event] = nil end end
    function data:SetScript(_, callback) Count() self.trigger = callback end
    return data
end

CreateFrame = function(_, _, parent) local frame = Region() frame.parent = parent return frame end
local time = 240
GetTime = function() return time end
local npcName, guid = "Ember Ward", "Creature-0-1-2-3-19722-ABC"
UnitName = function() return npcName end
UnitGUID = function() return guid end
local ownTotem = false
UnitIsOwnerOrControllerOfUnit = function(owner, unit)
    assert(owner == "player" and (unit == "nameplate1" or unit == "nameplate2"))
    return ownTotem
end
UnitIsUnit = function(_, unit) if unit == "arena2" then return secret end return unit == "target" and selected end
IsInInstance = function() return instance ~= "none", instance end
UnitPvpClassification = function() return 4 end
Enum = { PvPUnitClassification = { FlagCarrierHorde = 4 } }
GetArenaOpponentSpec = function(slot) return slot == 2 and secret or nil end
C_Spell = { GetSpellName = function() return "Ember Ward" end, GetSpellTexture = function() return 887 end }

Module("MSUF_Suite_Nameplates/UnitMarkers.lua", private)
local marks = private.UnitMarkers
for _, forever in ipairs({ false, true }) do
    NS.Client.isForever = forever
    assert(marks.Compile({}) == nil, "default options retained a marker plan")
    time = 240
    local state = { uf = Region(), plate = Region(), unit = "nameplate1", kind = "enemyNpc", prefix = "enemy" }
    local rules = marks.Compile({ nameplateNpcDimList = "19722", nameplateNpcIconList = "Ember Ward",
        nameplateTotemIcons = true, nameplateTotemList = "2484:15", nameplateTotemIconOnly = true })
    marks.Context(rules)
    marks.Paint(state, rules)
    assert(state.markerOpacity == 0 and state.unitMarker.frame.parent == state.plate, "replacement icon did not survive plate alpha")
    assert(state.unitMarker.icon.texture == 887 and state.unitMarker.glow.shown, "totem art was not selected")
    assert(state.unitMarker.cooldown.timer[1] == 240 and state.unitMarker.cooldown.timer[2] == 15, "totem timer was not armed")
    selected = true
    marks.Paint(state, rules)
    assert(state.markerOpacity == nil, "rules hid the selected unit")
    selected, npcName, guid = false, secret, secret
    marks.Invalidate(state)
    marks.Paint(state, rules)
    assert(state.markerOpacity == nil and not state.unitMarker.frame.shown, "restricted identity inherited an old marker")
    npcName, guid = "Ember Ward", "Creature-0-1-2-3-19722-ABC"
    marks.Release(state)
    assert(not state.unitMarker.frame.shown and not state.unitMarker.cooldown.shown, "pooled marker survived release")
    time = 245
    marks.Paint(state, rules)
    assert(state.unitMarker.cooldown.timer[1] == 240, "a returning plate reset the totem's first sighting")
    local originalGUID = guid
    local other = { uf = Region(), plate = Region(), unit = "nameplate2", kind = "enemyNpc", prefix = "enemy" }
    time = 246
    for i = 1, 128 do
        guid = originalGUID .. (forever and "F" or "R") .. i
        marks.Invalidate(other)
        marks.Paint(other, rules)
    end
    guid = originalGUID
    marks.Invalidate(state)
    marks.Paint(state, rules)
    assert(state.totemStart == 240, "cache eviction restarted the clock of a visible totem")
    local onlyTotems = marks.Compile({ nameplateTotemIcons = true, nameplateTotemList = "2484:15" })
    ownTotem = true
    marks.Paint(state, onlyTotems)
    assert(not state.totemRule and not state.unitMarker.frame.shown, "own Shaman totem was painted on the foreign-unit path")
    marks.Invalidate(state)
    ownTotem = secret
    marks.Paint(state, onlyTotems)
    assert(not state.totemRule, "restricted owner was treated as a foreign totem")
    ownTotem = false
    marks.Release(other)
    marks.Release(state)

    local arena = marks.Compile({ nameplateArenaNumbers = true, nameplateArenaSpecs = true, nameplateObjectives = true })
    state.kind, instance = "enemyPlayer", "arena"
    marks.Context(arena)
    marks.Paint(state, arena)
    assert(state.unitMarker.labels[2].text == "2" and state.unitMarker.labels[2].alphaArgument == secret,
        "arena labels did not paint a restricted comparison through an alpha sink")
    instance = "pvp"
    marks.Context(arena)
    state.uf.ClassificationFrame = Region()
    marks.Paint(state, arena)
    assert(state.unitMarker.objective.shown and not state.unitMarker.labels[2].shown, "arena label leaked into the battleground")
    state.uf.ClassificationFrame:Show()
    local before = writes
    combat = true
    marks.Paint(state, arena)
    combat = false
    assert(before == writes, "the marker wrote while its parent was protected")
    marks.Paint(state, arena)
    assert(not state.unitMarker.frame.shown, "native objective icon was duplicated")
    instance = "none"
end

Module("MSUF_Suite/Core/NameplateAuraDisplay.lua", NS)
local emphasis = NS.NameplateAuraEmphasis
local model = NS.NameplateAuraDisplay
local client = model.Client
local rule = emphasis.Compile({ ["auraLargeSpells" .. client] = "19", ["auraGlowSpells" .. client] = "19",
    ["auraPandemicSpells" .. client] = "20" }, model)
local aura = { width = 12, height = 12, groupCount = 5, anyCount = 0, filter = "HARMFUL",
    groupCandidate = { includeSpellIDs = { [19] = true, [20] = true, [21] = true } } }
local groups = emphasis.Groups(aura, rule)
local count, large, pandemic, normal = 0
for _, group in ipairs(groups) do
    count = count + group.count
    if group.candidate.includeSpellIDs[19] and group.appearance then large = group end
    if group.candidate.includeSpellIDs[20] and group.appearance then pandemic = group end
    if not group.appearance then normal = group end
end
assert(large.appearance.spellGlow and large.appearance.width > 12, "size and glow did not compose for one spell")
assert(pandemic.appearance.spellPandemic and pandemic.appearance.width == 12, "pandemic leaked to another spell")
assert(normal.candidate.excludeSpellIDs[19] and normal.candidate.excludeSpellIDs[20] and normal.count == 5 and count == 7,
    "emphasis duplicated spells or reserved ordinary icon capacity")
aura.groupCount = 1
local capped = emphasis.Groups(aura, { [19] = 2, [20] = 2, [21] = 2 })
local emphasized, ordinary = capped[1], capped[2]
assert(emphasized.count == 1 and emphasized.candidate.includeSpellIDs[19]
    and not emphasized.candidate.includeSpellIDs[20] and ordinary.candidate.excludeSpellIDs[19]
    and ordinary.candidate.includeSpellIDs[20] and not ordinary.candidate.excludeSpellIDs[20],
    "a spell past the emphasis budget was excluded from the ordinary group")

Module("MSUF_Suite_Nameplates/ExtensionLayout.lua", private)
local health = Region()
health.myHealPrediction, health.otherHealPrediction, health.totalAbsorb = Region(), Region(), Region()
local records = {}
private.ExtensionLayout.IncomingHeals(records, health, 0)
assert(health.myHealPrediction.alpha == 0 and health.otherHealPrediction.alpha == 0 and health.totalAbsorb.alpha == .65)
private.ExtensionLayout.IncomingHeals(records, health, 1)
assert(health.myHealPrediction.alpha == .65 and health.otherHealPrediction.alpha == .65 and not next(records),
    "the original prediction alpha was not restored")

local function Bar()
    local bar, texture = Region(), Region()
    function bar:GetStatusBarTexture() return texture end
    function bar:SetStatusBarTexture(file) texture:SetTexture(file) end
    return bar
end
local prd = Region()
prd.PowerBar, prd.HealthBarsContainer = Bar(), Region()
prd.HealthBarsContainer.healthBar = Bar()
PersonalResourceDisplayFrame = prd
Module("MSUF_Suite_Nameplates/PersonalDisplay.lua", private)
local module = { active = true, config = { look = 3 } }
local personal = private.PersonalDisplay
local before = writes
personal.Configure(module)
assert(before == writes, "inactive personal display wrote native state")
module.config.nameplatePersonalStyle = 3
personal.Configure(module)
assert(prd.HealthBarsContainer.height == 10 and prd.PowerBar.height == 5, "compact personal bars were not applied")
personal.Disable()
assert(prd.HealthBarsContainer.height == 13 and prd.PowerBar.height == 13
    and prd.PowerBar:GetStatusBarTexture().texture == "native", "personal bars did not restore their native appearance")

NS.NameplateExtensions = {}
local options = { Suite = NS, Gates = {}, Get = function() return 2 end, Tr = function(value) return value end }
Module("MSUF_Suite_Options/Pages/NameplatesExtensions.lua", options)
local sections, byKey = {}, {}
options.NameplatesExtensions.Append(sections)
for _, section in ipairs(sections) do byKey[section.key] = section end
local scopes = {
    plateNameDisplay = "enemy", plateHealthDisplay = "friendlyNpc", platePvpMarkers = "enemy",
    plateNpcMarkers = "neutral", auraSpellEmphasis = "enemy", platePersonalDisplay = "friendly",
}
for key, scope in pairs(scopes) do
    local section = assert(byKey[key], key .. " did not reach the nameplate workspace")
    assert(section.catalog == key and type(section.scopes[scope]) == "number",
        key .. " had no scope after workspace arrangement")
    assert(not options.Gates.nameplates({ section = key }, ""), key .. " offered edits with the Blizzard look")
end

print("Nameplate additions: runtime ownership, public and secret units, aura emphasis, healing, personal styling and options passed")

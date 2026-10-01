local root = assert(arg[1])
local support = dofile(root .. "/tools/tests/suite_test_support.lua")
local toc = support.TocFiles(root, "MSUF_Suite_Nameplates")
assert(table.concat(toc, ",") == "Bootstrap.lua,Geometry.lua,Layout.lua,Roles.lua,Text.lua,Power.lua,Threat.lua,"
    .. "Level.lua,CastTime.lua,CVars.lua,Auras.lua,Skin.lua",
    "nameplate runtime must stay in its own optional addon")
local installed, events = nil, {}
local scans = 0
local combat = false
local hasMana = false
local classification, isBoss = "normal", false
local instanceType, unitLevel = "none", 90
local focusUnit, targetUnit, questUnit, tappedUnit = nil, nil, false, false
local threatStatus = nil
local threatCalls = {}
local isTank, grouped, onThreatList = false, false, false
PlayerUtil = { IsPlayerEffectivelyTank = function() return isTank end }
UnitInParty = function() return grouped end
CompactUnitFrame_IsOnThreatListWithPlayer = function() return onThreatList end
UnitIsUnit = function(unit, other)
    assert(unit == "nameplate1")
    return (other == "focus" and focusUnit == unit) or (other == "target" and targetUnit == unit)
end
UnitIsTapDenied = function() return tappedUnit end
C_QuestLog = { UnitIsRelatedToActiveQuest = function() return questUnit end }
IsInInstance = function() return instanceType ~= "none", instanceType end
UnitLevel = function(unit) return unit == "player" and 90 or unitLevel end
UnitHasPowerType = function(unit, powerType)
    assert(unit == "nameplate1" and powerType == 0)
    return hasMana
end
UnitPowerType = function(unit)
    assert(unit == "nameplate1")
    if hasMana == "secret" then return "secret", "secret" end
    return hasMana and 0 or 3, hasMana and "MANA" or "ENERGY"
end
UnitClassification = function() return classification end
UnitIsBossMob = function() return isBoss end
UnitThreatSituation = function(...)
    threatCalls[#threatCalls + 1] = { "situation", ... }
    return threatStatus
end
UnitThreatLeadSituation = function(...)
    threatCalls[#threatCalls + 1] = { "lead", ... }
    return threatStatus
end
-- The remaining unit and context APIs of both clients. Defaults model a
-- hostile, attackable NPC in the open world; blocks below override them.
local function PlayerControlled() return false end
UnitPlayerControlled = PlayerControlled
UnitIsDead = function() return false end
UnitIsConnected = function() return true end
UnitReaction = function() return 2 end
UnitCanAttack = function() return true end
UnitIsTrivial = function() return false end
UnitIsLieutenant = function() return false end
UnitEffectiveLevel = function(unit) return UnitLevel(unit) end
UnitName = function() return "Player" end
UnitInRaid = function() return nil end
-- Forever's level badge rule (Camelot NameplateLevelFrameMixin:ShouldDisplay).
local badgeUnit = { object = false, friend = false, player = false, namesOnly = false }
-- A friendly player under the names-only CVar has no badge; Blizzard also
-- shows only that plate's name (UpdateShowOnlyName).
local function NamesOnlyUnit(on)
    badgeUnit.friend, badgeUnit.player, badgeUnit.namesOnly = on, on, on
end
UnitIsGameObject = function() return badgeUnit.object end
UnitIsFriend = function() return badgeUnit.friend end
UnitIsPlayer = function() return badgeUnit.player end
IsInRaid = function() return false end
C_PvP = { GetZonePVPInfo = function() return nil end }
GetInstanceInfo = function() return nil, instanceType, 0, nil, nil, nil, nil, nil, nil, false end
GetMaximumExpansionLevel = function() return 11 end
GetMaxLevelForExpansionLevel = function() return 90 end
C_Secrets = { ShouldUnitIdentityBeSecret = function() return false end }
-- C_TooltipInfo.GetUnit may return nothing; quest blocks supply lines.
C_TooltipInfo = { GetUnit = function() return nil end }
Enum = {
    PowerType = { Mana = 0 },
    TooltipDataLineType = { QuestTitle = 1, QuestPlayer = 2, QuestObjective = 3 },
    SecondsFormatterInterval = { Seconds = 1 },
    SecondsFormatterAbbreviation = { OneLetter = 2 },
}
PixelUtil = { SetPoint = function(region, ...) region:SetPoint(...) end }
NamePlateConstants = { DEBUFF_PADDING_CVAR = "nameplateDebuffPadding", NAMEPLATE_WIDTH = 230,
    CLASSIC_NAMEPLATE_WIDTH = 152 }
local debuffPadding = 0
GetCVarNumberOrDefault = function(key)
    assert(key == "nameplateDebuffPadding"); return debuffPadding
end
local queuedTimers = {}
C_Timer = { NewTimer = function(_, callback)
    local timer = { callback = callback }
    function timer:Cancel() self.cancelled = true end
    queuedTimers[#queuedTimers + 1] = timer
    return timer
end }

local nativeAnchor = {}
local function Region()
    local r = { shown = true }
    r.points = { { "CENTER", nativeAnchor, "CENTER", 0, 0 } }
    function r:SetTexture(value) self.texture, self.atlas = value, nil end
    function r:GetTexture() return self.texture end
    function r:SetAtlas(value) self.atlas, self.texture = value, "atlas-file" end
    function r:GetAtlas() return self.atlas end
    function r:SetTexCoord(...)
        local coords = { ... }
        if #coords == 4 then
            local l, r, t, b = unpack(coords)
            coords = { l, t, l, b, r, t, r, b }
        end
        self.coords = coords
    end
    function r:GetTexCoord() return unpack(self.coords or { 0, 0, 0, 1, 1, 0, 1, 1 }) end
    function r:AddMaskTexture(mask) self.mask = mask end
    function r:RemoveMaskTexture(mask) if self.mask == mask then self.mask = nil end end
    function r:SetColorTexture(...) self.color = { ... } end
    function r:SetVertexColor(...)
        self.vertexColor = { ... }
        self.vertexColorWrites = (self.vertexColorWrites or 0) + 1
    end
    function r:GetVertexColor() return unpack(self.vertexColor or { 1, 1, 1, 1 }) end
    function r:SetAllPoints(target) self.allPoints = target end
    function r:SetPoint(point, ...)
        for i, old in ipairs(self.points) do
            if old[1] == point then self.points[i] = { point, ... }; return end
        end
        self.points[#self.points + 1] = { point, ... }
    end
    function r:ClearAllPoints() self.points = {} end
    function r:GetNumPoints() return #self.points end
    function r:GetPoint() error("Can't measure restricted regions") end
    function r:SetPointsOffset(x, y)
        self.offsetX, self.offsetY = x, y
        self.offsetWrites = (self.offsetWrites or 0) + 1
    end
    function r:SetHeight(value) self.height = value end
    function r:SetWidth(value) self.width = value end
    function r:SetSize(width, height) self.width, self.height = width, height end
    function r:Show() self.shown = true end
    function r:SetScript(name, callback) self.scripts = self.scripts or {}; self.scripts[name] = callback end
    function r:RegisterEvent(event) self.events = self.events or {}; self.events[event] = true end
    function r:UnregisterEvent(event) if self.events then self.events[event] = nil end end
    function r:IsProtected() return self.protected == true, false end
    function r:Hide() self.shown = false end
    function r:SetShown(value) self.shown = value end
    function r:IsShown() return self.shown end
    function r:SetAlpha(value) self.alpha = value end
    function r:GetAlpha() return self.alpha or 1 end
    function r:SetFrameLevel(value) self.level = value end
    function r:GetFrameLevel() return self.level or 1 end
    function r:EnableMouse(value) self.mouse = value end
    function r:CreateLine() return Region() end
    function r:SetStartPoint(...) self.startPoint = { ... } end
    function r:SetEndPoint(...) self.endPoint = { ... } end
    function r:SetThickness(value) self.thickness = value end
    function r:SetRotation(value) self.rotation = value end
    function r:CreateTexture(_, layer, _, sublevel)
        self.created = (self.created or 0) + 1
        local texture = Region()
        texture.layer, texture.sublevel = layer, sublevel or 0
        self.textures = self.textures or {}
        self.textures[#self.textures + 1] = texture
        return texture
    end
    function r:CreateMaskTexture()
        self.masksCreated = (self.masksCreated or 0) + 1
        return Region()
    end
    function r:CreateFontString() local font = Region(); font.parent = self; return font end
    function r:SetFont(path, size, flags) self.font, self.fontSize, self.flags = path, size, flags or ""; return true end
    function r:GetFont()
        self.fontReads = (self.fontReads or 0) + 1
        return self.font, self.fontSize, self.flags or ""
    end
    function r:GetShadowColor() return 0, 0, 0, 0.6 end
    function r:GetShadowOffset() return 1, -1 end
    function r:SetShadowColor(...) self.shadow = { ... }; self.shadowColorWrites = (self.shadowColorWrites or 0) + 1 end
    function r:SetShadowOffset(...) self.shadowOffset = { ... }; self.shadowOffsetWrites = (self.shadowOffsetWrites or 0) + 1 end
    function r:SetText(value) self.text = value end
    function r:SetTextHeight(value) self.textHeight = value end
    function r:SetTextColor(...) self.textColor = { ... } end
    function r:SetJustifyH(value) self.justify = value end
    return r
end

CreateFrame = function(_, _, parent) local frame = Region(); frame.parent = parent; return frame end
MSUF_NS = {}
assert(loadfile(root .. "/../MidnightSimpleUnitFrames-Classic/MidnightSimpleUnitFrames/UnitFrames/Engine/Elements/MSUF_UF_BossTargetIndicator.lua"))("MidnightSimpleUnitFrames", MSUF_NS)

local bar, cast, name, aura = Region(), Region(), Region(), Region()
local raidFrame, raidIcon = Region(), Region()
raidIcon:SetAlpha(0.8)
raidFrame.RaidTargetIcon = raidIcon
NamePlateSetupOptions = { unitNameAnchorStyle = 1, useClassicCastBar = false,
    spellNameInsideCastBar = false, castBarToHealthBarSpacing = 2, healthBarHeight = 13 }
-- Inspect the mock's anchor plus displacement directly. The production code
-- must never invoke GetPoint, which raises the reported FrameMeasurement error.
local function Placed(region, index, axis)
    return region.points[index][axis] + (axis == 4 and (region.offsetX or 0) or (region.offsetY or 0))
end
local auraButton = Region()
function auraButton:IsMouseClickEnabled() return self.mouseClickEnabled ~= false end
function auraButton:SetMouseClickEnabled(value)
    self.mouseClickEnabled = value
    self.mouseWrites = (self.mouseWrites or 0) + 1
end
aura.auraItemFramePool = {
    GetNextActive = function(_, current) if current == nil then return auraButton end end,
    EnumerateActive = function() error("EnumerateActive allocates an iterator per refresh") end,
}
function aura:RefreshAuras() end
function aura:RefreshLossOfControl() end
name:SetFont("native-font", 10)
function bar:SetStatusBarColor(r, g, b)
    self.barColor = { r, g, b }
    if self.colorHook then self.colorHook(self) end
end
bar.barTexture = Region()
bar.barTexture:SetTexture("native-health")
bar.barColor = { 0.5, 0.5, 0.5 }
bar.Text = Region()
function bar:GetStatusBarTexture()
    self.textureReads = (self.textureReads or 0) + 1
    return self.barTexture
end
cast.statusTexture = Region()
cast.Text = Region()
cast.Text:SetFont("native-cast-font", 10, "")
function cast:SetCastTimeTextShown() error("do not activate Blizzard's secret-unsafe cast time path") end
function cast:UpdateCastTimeText() error("do not run Blizzard's secret-unsafe cast time formatter") end
function cast:GetMinMaxValues() error("do not read secret cast progress") end
local castDuration, channelDuration
UnitCastingDuration = function(unit) assert(unit == "nameplate1"); return castDuration end
UnitChannelDuration = function(unit) assert(unit == "nameplate1"); return channelDuration end
C_StringUtil = { CreateSecondsFormatter = function()
    return { SetMillisecondsThreshold = function(self, threshold) self.threshold = threshold end,
        SetMaxInterval = function(self, interval) self.interval = interval end,
        SetDefaultAbbreviation = function(self, abbreviation) self.abbreviation = abbreviation end }
end }
C_DurationUtil = { CreateDurationTextBinding = function()
    local binding = {}
    function binding:SetFontString(label) self.label = label end
    function binding:SetFormatter(formatter) self.formatter = formatter end
    function binding:SetUpdateInterval(interval) self.interval = interval end
    function binding:SetZeroDurationText(text) self.zero = text end
    function binding:SetExpiredText(text) self.expired = text end
    function binding:SetDuration(duration)
        assert(duration ~= nil, "no active cast duration")
        assert(duration ~= "secret", "addon code passed a secret duration to the binding")
        self.duration = duration
    end
    function binding:Disable() self.enabled = false end
    function binding:Enable()
        assert(self.duration, "duration binding enabled without a cast")
        self.enabled = true
        self.label:SetText("2.3s")
    end
    return binding
end }
cast.statusTexture:SetTexture("native-cast")
cast.Background = Region()
cast.Background:SetAlpha(.8)
-- Native cast rendering is exclusively Blizzard's, even with old skin keys.
function cast:GetStatusBarTexture() error("do not inspect native cast fill") end
function cast:SetStatusBarTexture() error("do not replace native cast fill") end
function cast:GetStatusBarColor() error("do not inspect native cast color") end
function cast:SetStatusBarColor() error("do not replace native cast color") end
function cast:CreateTexture() error("do not create cast overlays") end
function cast:UpdateBarFillTexture() error("do not invoke native cast logic") end
local healthContainer = Region()
healthContainer.healthBar = bar
local uf = {
    unit = "nameplate1", isFriend = false, isPlayer = false, name = name, AurasFrame = aura,
    RaidTargetFrame = raidFrame, LevelFrame = Region(),
    HealthBarsContainer = healthContainer, CastBarsContainer = { castBar = cast },
}
uf.CreateTexture, uf.CreateFontString = bar.CreateTexture, bar.CreateFontString
function uf:UpdateAnchors()
    error("nameplate skin must not reenter native layout")
end
local plate = { UnitFrame = uf, unitToken = "nameplate1" }
function plate:ApplyFrameOptions()
    error("nameplate skin must not replay CompactUnitFrame setup or unit data")
end
CompactUnitFrame_UpdateHealthColor = function()
    error("nameplate skin must not manually recalculate Blizzard health color")
end

C_NamePlate = {
    GetNamePlates = function() scans = scans + 1; return { plate } end,
    GetNamePlateForUnit = function(unit)
        return (unit == "nameplate1" or (unit == "target" and targetUnit == "nameplate1") or (unit == "focus" and focusUnit == "nameplate1")) and plate or nil
    end,
}
local liveCVars = {
    nameplateSimplifiedTypes = string.char(1, 79), -- four simplified types
    nameplateInfoDisplay = string.char(1, 68), -- rarity icon only
    nameplateCastBarDisplay = string.char(1, 96), -- future sixth flag must survive
}
C_CVar = { GetCVar = function(key) return liveCVars[key] end,
    GetCVarBool = function(key)
        assert(key == "nameplateShowOnlyNameForFriendlyPlayerUnits")
        return badgeUnit.namesOnly
    end }
NamePlateUnitFrameMixin = { ApplyFrameOptions = function() error("do not invoke native setup") end,
    UpdateAggroHighlight = function() end }
-- Client contract: the template copies the mixin's methods into each unit
-- frame it creates, and the driver pools those frames for the session. uf
-- was created before the Suite loaded, so it holds the unhooked methods.
uf.ApplyFrameOptions = NamePlateUnitFrameMixin.ApplyFrameOptions
uf.UpdateAggroHighlight = NamePlateUnitFrameMixin.UpdateAggroHighlight
local layoutHook, fontHook, powerHook, threatColorHook
local instanceHooks = {}
local function SecureWrap(owner, method, callback)
    local original = owner[method]
    owner[method] = function(...)
        original(...)
        callback(...)
    end
end
local layoutCallbacks = {}
MSUF_UpdateCastbarVisuals = function() end
hooksecurefunc = function(frame, method, callback)
    if type(frame) == "string" then error("do not install cast media hooks") end
    if frame == NamePlateUnitFrameMixin and method == "ApplyFrameOptions" then
        fontHook = callback
        SecureWrap(frame, method, callback)
        return
    end
    if frame == NamePlateUnitFrameMixin and method == "UpdateAggroHighlight" then
        threatColorHook = callback
        SecureWrap(frame, method, callback)
        return
    end
    if method == "ApplyFrameOptions" or method == "UpdateAggroHighlight" then
        assert(frame.UnitFrame == nil and frame.HealthBarsContainer, "a plate method hook missed the unit frame")
        instanceHooks[method] = (instanceHooks[method] or 0) + 1
        SecureWrap(frame, method, callback)
        return
    end
    if frame == NamePlateDriverFrame and method == "SetupClassNameplateBars" then powerHook = callback; return end
    if frame == cast then error("do not hook native cast logic") end
    if frame == uf and method == "UpdateAnchors" then
        layoutCallbacks[#layoutCallbacks + 1] = callback
        layoutHook = function(frame) for _, fn in ipairs(layoutCallbacks) do fn(frame) end end
        return
    end
    assert(frame == aura and (method == "RefreshAuras" or method == "RefreshLossOfControl"),
        "nameplate skin must not hook native layout")
end

local NS = {
    Safety = { IsForbidden = function() return false end },
    IsCombatLocked = function() return combat end,
    Client = { IsAddOnLoaded = function() return true end },
    MSUFMedia = { barTexture = "fallback-msuf-texture" },
}
local cvars, restored = {}, {}
local S = {
    Public = function(value) return value ~= "secret" end,
    Finite = function(value) return type(value) == "number" and value == value end,
    RGB = function(hex)
        return tonumber(hex:sub(1, 2), 16) / 255,
            tonumber(hex:sub(3, 4), 16) / 255,
            tonumber(hex:sub(5, 6), 16) / 255
    end,
    SetFont = function(region, path, size, flags) region:SetFont(path or "fallback-font", size, flags) end,
    ResolveFont = function(key) return key ~= "" and key or nil end,
    RestoreCVar = function(_, key)
        restored[key] = true
        if key == "nameplateInfoDisplay" then liveCVars[key] = string.char(1, 68) end
    end,
    Install = function(_, module) installed = module end,
}
local context = {
    Event = function(_, event, callback) events[event] = callback end,
    CVar = function(_, key, value) cvars[key] = value; liveCVars[key] = value end,
}
NS.Suite = S
NS.RGB, NS.Public, NS.Finite, NS.ResolveFont = S.RGB, S.Public, S.Finite, S.ResolveFont
assert(loadfile(root .. "/MSUF_Suite/Core/SuiteCatalog.lua"))("MSUF_Suite", NS)
assert(loadfile(root .. "/MSUF_Suite/Core/NameplateStyle.lua"))("MSUF_Suite", NS)
local private = { NS = NS, Suite = S }
-- No runtime file needs a protected call: every API both clients have is
-- called directly, and restricted answers are checked as values.
for _, file in ipairs(toc) do
    local handle = assert(io.open(root .. "/MSUF_Suite_Nameplates/" .. file, "rb"))
    local code = handle:read("*a"):gsub("%-%-[^\n]*", "")
    handle:close()
    assert(not code:find("pcall", 1, true), file .. " uses pcall or xpcall")
end
-- Production load order; Bootstrap.lua only links the core namespace.
for _, file in ipairs(toc) do
    if file ~= "Bootstrap.lua" then
        assert(loadfile(root .. "/MSUF_Suite_Nameplates/" .. file))("MSUF_Suite_Nameplates", private)
    end
end
local module = assert(installed)
module.context = context
module.config = {
    look = 1, enemy = true, friendly = true,
    nativeStyle = 2, nativeSize = 3, levelAppearance = 1, enemyTextMode = 4,
    enemyRarityIcon = 1, enemyRaidIcon = true,
    enemyRoleColors = true, enemyMeleeColor = "be301d", enemyCasterColor = "00bfff",
    enemyMinibossColor = "9370db", enemyBossColor = "ff00ff",
    enemyQuestColors = true, enemyQuestColor = "ff7e00", enemyTappedColor = "6e6e6e",
    enemyFocusColor = "ff00ff", enemyTargetColor = "ffffff", enemyTargetMarker = true,
    enemyTargetMarkerSize = 16, enemyColorsInDungeons = true, enemyColorsOutside = true,
    enemyTargetOffsetX = 0, enemyTargetOffsetY = 0,
    enemyEliteMarker = true, enemyEliteMarkerSize = 14, enemyEliteOffsetX = -13,
    enemyEliteOffsetY = 0, enemyQuestMarker = true, enemyQuestMarkerSize = 15,
    enemyQuestOffsetX = 0, enemyQuestOffsetY = 17,
    enemyTankMode = false, enemyThreatLostColor = "ff4d32",
    enemyThreatWarningColor = "ffbd38", enemyTrivialColor = "777777",
    enemyNeutralColor = "e5bd45",
    enemyBackdropColor = "080b10", friendlyBackdropColor = "080b10",
    enemyBorderColor = "111418", friendlyBorderColor = "111418",
    enemyBorderSize = 1, friendlyBorderSize = 1,
    enemyNameSize = 12, friendlyNameSize = 14,
    enemyCastSize = 11, enemyHealthTextSize = 11, enemyCastFont = "",
    enemyCastEnabled = 2, enemyCastDisplay = 2,
    enemyCastSpellName = true, enemyCastSpellIcon = false,
    enemyCastSpellTarget = false, enemyCastImportant = true, enemyCastTargetHighlight = true,
    -- Legacy settings must not reactivate cast rendering or media hooks.
    enemyCastSkin = true, enemyCastFollowMSUF = true, enemyCastBorderSize = 1,
    enemyCastBorderColor = "000000", enemyCastBackdropColor = "171a1e",
    enemyCastBackdropAlpha = 85, enemyCastFillColor = "f2c34e", enemyCastFillAlpha = 35,
    enemyCastTexture = "legacy-custom-cast",
    enemyNameFont = "", friendlyNameFont = "",
    friendlyCastTextEnabled = false,
    friendlyNamesOnly = 2, classColors = 1, friendlyNameClassColor = 2, friendlyRealm = 1,
    personalAuras = 1,
    auraClickthrough = false,
}
module.active = true
MSUF_GetCastbarTexture = function() error("do not link nameplate cast textures") end
MSUF_GetCastbarBackgroundTexture = function() error("do not link nameplate cast backgrounds") end
MSUF_GetCastbarBackgroundColor = function() return 0.1, 0.2, 0.3, 0.8 end
module:Enable()
assert(scans == 1)
assert(instanceHooks.ApplyFrameOptions == 1 and not instanceHooks.UpdateAggroHighlight,
    "a unit frame created before the Suite missed the font-reset hook")
assert(not layoutHook, "factory layout installed an unnecessary native layout hook")
assert(bar.barTexture.texture == "native-health")
assert(cast.statusTexture.texture == "native-cast" and not cast.created and cast.Background:GetAlpha() == .8,
    "nameplate skin changed the native cast fill/background")
assert(module.visuals[bar].borderColor == "111418"
    and module.visuals[bar].fill.color[1] == 0xbe / 255
    and module.visuals[bar].fill.allPoints == bar.barTexture and bar.barColor[1] == 0.5,
    "melee overlay must follow Blizzard's fill without recoloring its StatusBar")
assert(module.visuals[bar].fill.layer == "ARTWORK" and module.visuals[bar].fill.sublevel == 3,
    "role tint must remain above a native StatusBar texture reapplied after setup")
do
    local nameWrites, castWrites = name.shadowColorWrites, cast.Text.shadowColorWrites
    events.UNIT_FLAGS(module, "UNIT_FLAGS", "nameplate1")
    assert(name.shadowColorWrites == nameWrites and cast.Text.shadowColorWrites == castWrites,
        "unchanged unit metadata repainted native font shadows")
end
module.config.enemyColorsOutside = false
events.ZONE_CHANGED_NEW_AREA(module, "ZONE_CHANGED_NEW_AREA")
assert(not module.visuals[bar].fill:IsShown(), "outdoor color scope did not disable its overlay")
module.config.enemyColorsOutside = true
events.ZONE_CHANGED_NEW_AREA(module, "ZONE_CHANGED_NEW_AREA")
assert(module.visuals[bar].fill:IsShown(), "outdoor color scope did not restore its overlay")
-- Jundies/Platynator detects mana capability, not just the currently displayed
-- power. Exercise the real two-result API as well as the capability fallback.
do
    local nativePowerType, nativeHasPower = UnitPowerType, UnitHasPowerType
    local power, token, powerReads = nil, nil, 0
    UnitPowerType = function() powerReads = powerReads + 1; return power, token end
    local function Check(mana, currentPower, currentToken, expected)
        hasMana, power, token = mana, currentPower, currentToken
        local before = powerReads
        events.UNIT_DISPLAYPOWER(module, "UNIT_DISPLAYPOWER", "nameplate1")
        assert(module.roles[bar] == expected, "mana-capable caster or public power result lost its role")
        if type(mana) == "boolean" then assert(powerReads == before, "public mana capability performed a redundant power query") end
        local fill = module.visuals[bar].fill
        if expected then
            local r, g, b = S.RGB(module.config["enemy" .. expected .. "Color"])
            assert(fill:IsShown() and fill.color[1] == r and fill.color[2] == g and fill.color[3] == b,
                "role classification did not recolor the full health fill")
        else assert(not fill:IsShown(), "unknown role retained a previous NPC tint") end
    end
    Check(true, 3, "ENERGY", "Caster")
    Check(false, 0, "MANA", "Melee")
    classification, instanceType = "elite", "party"
    events.ZONE_CHANGED_NEW_AREA(module, "ZONE_CHANGED_NEW_AREA")
    Check(true, 3, "ENERGY", "Caster")
    Check(false, 0, "MANA", "Melee")
    Check("secret", "secret", "MANA", "Caster")
    Check("secret", 0, "secret", "Caster")
    Check("secret", 3, "secret", "Melee")
    Check("secret", "secret", "secret", "Melee")
    Check(nil, nil, "MANA", "Caster")
    Check(nil, nil, nil, "Melee")
    UnitPowerType, UnitHasPowerType, hasMana = nativePowerType, nativeHasPower, false
    classification, instanceType = "normal", "none"
    events.ZONE_CHANGED_NEW_AREA(module, "ZONE_CHANGED_NEW_AREA")
    assert(scans == 1, "role refresh scanned all plates")
end
do
    -- Settings reach live plates through Refresh; UNIT_FLAGS only re-reads
    -- the flag-dependent color role and leaves the skin layers alone. These
    -- settings passes stay out of the event scan count checked below.
    local visual, settingsScans = module.visuals[bar], scans
    module.config.enemyBackdropEnabled, module.config.enemyBorderEnabled = false, false
    events.UNIT_FLAGS(module, "UNIT_FLAGS", "nameplate1")
    assert(visual.back:IsShown() and visual.borderSize == 1,
        "a unit flag event repainted the whole skin")
    module:Refresh()
    assert(not visual.back:IsShown() and visual.borderSize == 0
        and not visual.edges[1]:IsShown(), "skin backdrop/border switches did not hide the live layers")
    module.config.enemyBackdropEnabled, module.config.enemyBorderEnabled = true, true
    module:Refresh()
    assert(visual.back:IsShown() and visual.borderSize == 1 and visual.edges[1]:IsShown(),
        "skin backdrop/border switches did not restore the live layers")
    scans = settingsScans
end
do
    local previousPvp = C_PvP
    C_PvP = { GetZonePVPInfo = function() return "combat" end }
    classification, instanceType, hasMana = "normal", "party", true
    events.ZONE_CHANGED_NEW_AREA(module, "ZONE_CHANGED_NEW_AREA")
    assert(module.roles[bar] == "Caster" and module.visuals[bar].fill:IsShown(),
        "an outdoor PvP zone flag suppressed caster color inside a party instance")
    classification = nil
    events.UNIT_CLASSIFICATION_CHANGED(module, "UNIT_CLASSIFICATION_CHANGED", "nameplate1")
    assert(module.roles[bar] == "Caster", "public mana hint lost caster color when classification was unavailable")
    instanceType, hasMana, classification = "none", false, "normal"
    events.ZONE_CHANGED_NEW_AREA(module, "ZONE_CHANGED_NEW_AREA")
    assert(module.roles[bar] == nil, "outdoor PvP zone inherited dungeon role colors")
    C_PvP = previousPvp
    events.ZONE_CHANGED_NEW_AREA(module, "ZONE_CHANGED_NEW_AREA")
end
do
    local nativeTimer, nativeClassification, nativeQuestLog = C_Timer, UnitClassification, C_QuestLog
    local timerCount, classificationReads, questReads, queued = 0, 0, 0, {}
    C_QuestLog = { UnitIsRelatedToActiveQuest = function(unit)
        questReads = questReads + 1
        return nativeQuestLog.UnitIsRelatedToActiveQuest(unit)
    end }
    C_Timer = { NewTimer = function(delay, callback)
        assert(delay == 1)
        timerCount = timerCount + 1
        local timer = { callback = callback }
        function timer:Cancel() self.cancelled = true end
        queued[#queued + 1] = timer
        return timer
    end }
    UnitClassification = function(unit)
        classificationReads = classificationReads + 1
        return nativeClassification(unit)
    end
    local active = module.activeUnits.nameplate1
    module.activeUnits.nameplate1 = nil
    events.QUEST_LOG_UPDATE(module, "QUEST_LOG_UPDATE")
    assert(timerCount == 0, "quest update scheduled work without visible plates")
    module.activeUnits.nameplate1 = active
    events.QUEST_LOG_UPDATE(module, "QUEST_LOG_UPDATE")
    events.QUEST_LOG_UPDATE(module, "QUEST_LOG_UPDATE")
    assert(timerCount == 1 and classificationReads == 0,
        "quest updates performed repeated immediate plate classifications")
    -- The deferred pass re-reads only quest facts: classification, markers
    -- and the type role stay cached, and an unchanged plate keeps its skin.
    local textureReads = bar.textureReads
    queued[1].callback()
    assert(questReads == 1, "coalesced quest update missed the active plate")
    assert(classificationReads == 0, "quest log refresh re-read unit classification")
    assert(bar.textureReads == textureReads, "unchanged quest state repainted the health skin")
    questUnit = true
    events.QUEST_LOG_UPDATE(module, "QUEST_LOG_UPDATE")
    queued[#queued].callback()
    assert(module.roles[bar] == "Quest" and bar.textureReads > textureReads and classificationReads == 0,
        "new quest objective did not reach the color role without reclassification")
    questUnit = false
    events.QUEST_LOG_UPDATE(module, "QUEST_LOG_UPDATE")
    queued[#queued].callback()
    assert(module.roles[bar] ~= "Quest", "completed quest kept its quest color")
    timerCount, queued = 1, { queued[1] }
    instanceType = "party"
    events.ZONE_CHANGED_NEW_AREA(module, "ZONE_CHANGED_NEW_AREA")
    classificationReads = 0
    events.QUEST_LOG_UPDATE(module, "QUEST_LOG_UPDATE")
    assert(timerCount == 1 and classificationReads == 0,
        "quest update scheduled work inside a dungeon")
    instanceType = "none"
    events.ZONE_CHANGED_NEW_AREA(module, "ZONE_CHANGED_NEW_AREA")
    events.QUEST_LOG_UPDATE(module, "QUEST_LOG_UPDATE")
    assert(timerCount == 2 and not queued[2].cancelled)
    instanceType = "party"
    events.ZONE_CHANGED_NEW_AREA(module, "ZONE_CHANGED_NEW_AREA")
    assert(queued[2].cancelled and module.questTimer == nil,
        "context change left stale quest work scheduled")
    instanceType = "none"
    events.ZONE_CHANGED_NEW_AREA(module, "ZONE_CHANGED_NEW_AREA")
    C_Timer, UnitClassification, C_QuestLog = nativeTimer, nativeClassification, nativeQuestLog
end
assert(name.fontSize == 12 and name.points[1][1] == "CENTER"
    and cast.points[1][1] == "CENTER" and aura.points[1][1] == "CENTER",
    "native anchors changed")
assert(cvars.nameplateShowOnlyNameForFriendlyPlayerUnits == "1"
    and cvars.nameplateUseClassColorForFriendlyPlayerUnitNames == "1")
assert(cvars.nameplateStyle == "0" and cvars.nameplateSize == "2"
    and cvars.nameplateForceShowUnitName == "1"
    and cvars.nameplateSimplifiedTypes == string.char(1, 76)
    and cvars.nameplateInfoDisplay == string.char(1, 71),
    "Jundies defaults did not request Blizzard's full enemy text and medium inside-bar layout")
assert(cvars.nameplateCastBarDisplay == string.char(1, 121),
    "Blizzard castbar display bits were not enabled")
assert(cvars.nameplateShowCastBars == "1",
    "Blizzard's native nameplate castbar was never enabled")
assert(restored.ShowClassColorInNameplate and restored.nameplateShowClassColor
    and restored.nameplateShowAllPersonalAuras)

events.PLAYER_REGEN_ENABLED(module, "PLAYER_REGEN_ENABLED")
assert(scans == 1, "combat exit scanned plates without deferred work")
combat = true
module:Refresh()
assert(not module.needsRefresh and scans == 2, "safe font/texture styling should work in combat")
combat = false
events.PLAYER_REGEN_ENABLED(module, "PLAYER_REGEN_ENABLED")
assert(not module.needsRefresh and scans == 2, "combat exit should not redo cosmetic work")

events.NAME_PLATE_UNIT_ADDED(module, "NAME_PLATE_UNIT_ADDED", "nameplate1")
assert(scans == 2 and name.points[1][1] == "CENTER", "event performed a scan or changed native anchors")
-- Budget: Lua VM instructions of one NAME_PLATE_UNIT_ADDED of a styled plate
-- (deterministic on Lua 5.1, this harness included). 2026-10-01: 1800
-- before existing unit frames were covered by the plate hooks, 1817 after;
-- the budget is the old baseline +2 %.
do
    local PLATE_ADDED_BUDGET = 1836
    local count = 0
    debug.sethook(function() count = count + 1 end, "", 1)
    events.NAME_PLATE_UNIT_ADDED(module, "NAME_PLATE_UNIT_ADDED", "nameplate1")
    debug.sethook()
    print("nameplate added: " .. count .. " instructions")
    assert(count <= PLATE_ADDED_BUDGET, "a plate add cost " .. count .. " instructions (budget " .. PLATE_ADDED_BUDGET .. ")")
end
hasMana = true
events.NAME_PLATE_UNIT_ADDED(module, "NAME_PLATE_UNIT_ADDED", "nameplate1")
assert(module.visuals[bar].fill.color[2] == 0xbf / 255, "caster health fill missing")
classification = "rareelite"
events.NAME_PLATE_UNIT_ADDED(module, "NAME_PLATE_UNIT_ADDED", "nameplate1")
assert(module.visuals[bar].fill.color[1] == 0x93 / 255, "rare health fill missing")
local elite = module.visuals[bar].elite
assert(elite:IsShown() and elite.atlas == "UI-HUD-UnitFrame-Target-PortraitOn-Boss-Rare-Star"
    and elite.text == nil and elite.points[1][3] == "LEFT"
    and elite.points[1][4] == -13 and elite.width == 14,
    "elite marker must use a texture outside the name, never a font glyph inside the bar")
module.config.enemyEliteMarker = false
module:Refresh()
assert(not elite:IsShown(), "disabled elite marker retained a fragment over the name")
module.config.enemyEliteMarker = true
module.config.enemyEliteMarkerSize = 20
module.config.enemyEliteOffsetX = -20
module:Refresh()
assert(elite:IsShown() and elite.width == 20 and elite.points[1][4] == -20,
    "elite marker size/offset did not refresh after changing the setting")
isBoss = true
events.NAME_PLATE_UNIT_ADDED(module, "NAME_PLATE_UNIT_ADDED", "nameplate1")
assert(module.visuals[bar].fill.color[1] == 1, "boss health fill missing")
isBoss, classification, instanceType, unitLevel = false, "elite", "party", 91
events.NAME_PLATE_UNIT_ADDED(module, "NAME_PLATE_UNIT_ADDED", "nameplate1")
assert(module.visuals[bar].fill.color[1] == 0x93 / 255, "lieutenant health fill missing")
unitLevel = 92
events.NAME_PLATE_UNIT_ADDED(module, "NAME_PLATE_UNIT_ADDED", "nameplate1")
assert(module.visuals[bar].fill.color[1] == 1, "level-based boss health fill missing")
unitLevel, instanceType = 90, "none"
questUnit = true
events.NAME_PLATE_UNIT_ADDED(module, "NAME_PLATE_UNIT_ADDED", "nameplate1")
assert(module.visuals[bar].fill.color[1] == 1 and module.visuals[bar].fill.color[2] == 0x7e / 255,
    "quest objective health color missing")
assert(module.visuals[bar].quest:IsShown() and module.visuals[bar].quest.atlas == "QuestNormal"
    and module.visuals[bar].quest.text == nil, "quest marker must use a texture, not a font glyph")
questUnit, tappedUnit = false, true
events.NAME_PLATE_UNIT_ADDED(module, "NAME_PLATE_UNIT_ADDED", "nameplate1")
assert(module.visuals[bar].fill.color[1] == 0x6e / 255, "tapped health color missing")
tappedUnit, focusUnit = false, "nameplate1"
events.NAME_PLATE_UNIT_ADDED(module, "NAME_PLATE_UNIT_ADDED", "nameplate1")
assert(module.visuals[bar].fill.color[1] == 1 and module.visuals[bar].fill.color[2] == 0,
    "focus health color missing")
focusUnit, targetUnit = nil, "nameplate1"
events.PLAYER_FOCUS_CHANGED(module, "PLAYER_FOCUS_CHANGED")
local targetFontReads = name.fontReads
events.PLAYER_TARGET_CHANGED(module, "PLAYER_TARGET_CHANGED")
assert(name.fontReads == targetFontReads, "target change repainted nameplate typography")
local marker = module.visuals[bar].targetHost._msufBossTargetIndicator
assert(marker:IsShown() and marker.mirror:IsShown() and marker.width == 16
    and #marker.lines == 4 and marker._style == "DOUBLE_ARROW",
    "target arrows missing")
local initialTarget = NS.NameplateStyle.TargetConfig(module.config)
assert(marker.offsetX == initialTarget.bossTargetX and marker.offsetY == initialTarget.bossTargetY
    and marker.mirror.offsetX == -initialTarget.bossTargetX,
    "fresh target arrows ignored saved offsets while applying level clearance")
module.config.enemyTargetOffsetX = 9
module.config.enemyTargetOffsetY = -4
module:Refresh()
assert(marker.points[1][4] == -10
    and marker.points[1][5] == -4 and marker.offsetX == -10 and marker.offsetY == -4,
    "dragged target marker offsets did not reach the live skin")
local freshTargetVisual = {}
local freshTargetConfig = NS.NameplateStyle.TargetConfig(module.config)
local freshTarget = NS.NameplateStyle.PaintTarget(freshTargetVisual, bar, true, freshTargetConfig, uf, 0, 0)
assert(freshTarget.offsetX == freshTargetConfig.bossTargetX
    and freshTarget.offsetY == freshTargetConfig.bossTargetY
    and freshTarget.mirror.offsetX == -freshTargetConfig.bossTargetX,
    "fresh target renderer lost saved arrow position after reload")
targetUnit = nil
targetFontReads = name.fontReads
events.PLAYER_TARGET_CHANGED(module, "PLAYER_TARGET_CHANGED")
assert(not module.visuals[bar].targetHost:IsShown() and name.fontReads == targetFontReads,
    "target change repainted unrelated visuals or left arrows visible")
module.config.enemyTankMode = true
isTank, grouped, onThreatList = true, true, true
private.Roles.RefreshContext()
threatStatus = 3
local threatFontReads = name.fontReads
events.UNIT_THREAT_SITUATION_UPDATE(module, "UNIT_THREAT_SITUATION_UPDATE", "nameplate1")
assert(module.visuals[bar].fill.color[1] == 1 and module.visuals[bar].fill.color[2] == 0x4d / 255,
    "tank lost-threat color missing")
assert(name.fontReads == threatFontReads, "threat color update repainted nameplate typography")
threatStatus = 2
events.UNIT_THREAT_SITUATION_UPDATE(module, "UNIT_THREAT_SITUATION_UPDATE", "nameplate1")
assert(module.visuals[bar].fill.color[2] == 0xbd / 255, "tank warning color missing")
local unchangedTextureReads = bar.textureReads
events.UNIT_THREAT_SITUATION_UPDATE(module, "UNIT_THREAT_SITUATION_UPDATE", "nameplate1")
assert(bar.textureReads == unchangedTextureReads,
    "unchanged threat role repainted the health skin")
module.config.enemyTankMode, threatStatus = false, nil
instanceType = "none"
isBoss, classification, hasMana, questUnit, tappedUnit = false, "secret", "secret", "secret", "secret"
events.NAME_PLATE_UNIT_ADDED(module, "NAME_PLATE_UNIT_ADDED", "nameplate1")
assert(module.visuals[bar].borderColor == "111418" and not module.visuals[bar].fill:IsShown(),
    "secret role must leave Blizzard's health fill and the plain border")
uf.isFriend = true
events.NAME_PLATE_UNIT_ADDED(module, "NAME_PLATE_UNIT_ADDED", "nameplate1")
assert(name.fontSize == 14 and bar.barTexture.texture == "native-health"
    and cast.statusTexture.texture == "native-cast", "friend style not applied or native texture changed")
uf.isFriend = "secret"
events.NAME_PLATE_UNIT_ADDED(module, "NAME_PLATE_UNIT_ADDED", "nameplate1")
assert(not module.visuals[bar].back:IsShown(), "unknown faction retained a stale visual")
events.NAME_PLATE_UNIT_REMOVED(module, "NAME_PLATE_UNIT_REMOVED", "nameplate1")
assert(not module.visuals[bar].fill:IsShown() and module.activeUnits.nameplate1 == nil,
    "removed plate retained a role overlay")
uf.isFriend = false
events.NAME_PLATE_UNIT_ADDED(module, "NAME_PLATE_UNIT_ADDED", "nameplate1")
assert(module.activeUnits.nameplate1 == uf)
module.config.auraClickthrough = true
events.NAME_PLATE_UNIT_ADDED(module, "NAME_PLATE_UNIT_ADDED", "nameplate1")
assert(auraButton.mouseClickEnabled == false, "aura clickthrough did not reach pooled button")
local auraWrites = auraButton.mouseWrites
local pool=aura.auraItemFramePool
local enumerator, nextActive=pool.EnumerateActive, pool.GetNextActive
pool.GetNextActive=function(_,previous) if not previous then return auraButton end end
pool.EnumerateActive=function() error("GetNextActive allocated an iterator") end
events.NAME_PLATE_UNIT_ADDED(module, "NAME_PLATE_UNIT_ADDED", "nameplate1")
assert(auraButton.mouseWrites == auraWrites, "unchanged aura clickthrough repeated a protected setter")
pool.EnumerateActive, pool.GetNextActive = enumerator, nextActive
module.config.auraClickthrough = false
events.NAME_PLATE_UNIT_ADDED(module, "NAME_PLATE_UNIT_ADDED", "nameplate1")
assert(auraButton.mouseClickEnabled == true, "aura clickthrough did not restore native clicks")
do
    -- The combat-end refresh below is not part of the scan count checked later.
    local auraScans = scans
    auraButton.protected = true
    module.config.auraClickthrough = true
    combat = true
    local writes = auraButton.mouseWrites
    events.NAME_PLATE_UNIT_ADDED(module, "NAME_PLATE_UNIT_ADDED", "nameplate1")
    assert(auraButton.mouseWrites == writes and auraButton.mouseClickEnabled == true and module.needsRefresh,
        "protected aura button changed its clicks in combat")
    combat = false
    events.PLAYER_REGEN_ENABLED(module, "PLAYER_REGEN_ENABLED")
    assert(auraButton.mouseClickEnabled == false, "protected aura button stayed clickable after combat")
    combat = true
    module.config.auraClickthrough = false
    events.NAME_PLATE_UNIT_ADDED(module, "NAME_PLATE_UNIT_ADDED", "nameplate1")
    assert(auraButton.mouseClickEnabled == false, "protected aura button restored its clicks in combat")
    local restore = assert(module.auraRestoreFrame, "no deferred aura restore after combat")
    assert(restore.events.PLAYER_REGEN_ENABLED, "deferred aura restore waits for no event")
    combat = false
    restore.scripts.OnEvent(restore, "PLAYER_REGEN_ENABLED")
    assert(auraButton.mouseClickEnabled == true and not restore.events.PLAYER_REGEN_ENABLED,
        "deferred aura restore did not hand the clicks back")
    -- An unprotected button follows the setting in combat.
    auraButton.protected = false
    module.config.auraClickthrough = true
    combat = true
    events.NAME_PLATE_UNIT_ADDED(module, "NAME_PLATE_UNIT_ADDED", "nameplate1")
    assert(auraButton.mouseClickEnabled == false, "unprotected aura button waited for combat end")
    module.config.auraClickthrough = false
    events.NAME_PLATE_UNIT_ADDED(module, "NAME_PLATE_UNIT_ADDED", "nameplate1")
    combat = false
    assert(auraButton.mouseClickEnabled == true, "unprotected aura button kept click-through")
    module.needsRefresh = false
    scans = auraScans
end
module.config.enemyRaidIcon = false
events.NAME_PLATE_UNIT_ADDED(module, "NAME_PLATE_UNIT_ADDED", "nameplate1")
assert(raidIcon:GetAlpha() == 0, "native raid icon was not hidden on an existing enemy plate")
module.active = false
module:Disable()
assert(raidIcon:GetAlpha() == 0.8, "disabling the module did not restore Blizzard's raid icon")
module.config.enemyRaidIcon = true
assert(scans == 5 and bar.barTexture.texture == "native-health"
    and not module.visuals[bar].back:IsShown(), "native frame was not restored")
assert(not module.visuals[bar].fill:IsShown() and name.font == "native-font" and name.fontSize == 10,
    "Jundies overlay or font remained after disabling")
assert(cast.statusTexture.texture == "native-cast" and cast.Background:GetAlpha() == .8,
    "disabling nameplates changed native cast rendering")
assert(events.NAME_PLATE_UNIT_ADDED and events.NAME_PLATE_UNIT_REMOVED and events.PLAYER_REGEN_ENABLED)
module.active = true
module.config.enemyRarityIcon = 3
module.config.enemyRaidIcon = false
module:Refresh()
assert(cvars.nameplateInfoDisplay == string.char(1, 67)
    and raidIcon:GetAlpha() == 0, "enemy icon switches did not hide native icons")
module.config.enemyRarityIcon = 2
module:Refresh()
assert(cvars.nameplateInfoDisplay == string.char(1, 71), "rarity icon switch lost health text flags")
module.config.enemyRarityIcon = 1
module.config.enemyRaidIcon = true
module:Refresh()
assert(cvars.nameplateInfoDisplay == string.char(1, 71) and raidIcon:GetAlpha() == 0.8,
    "native icon switches did not restore their prior state")
module.config.enemyTextMode, module.config.enemyRarityIcon = 1, 3
module:Refresh()
assert(cvars.nameplateInfoDisplay == string.char(1),
    "hiding the rarity icon while keeping Blizzard health text did not restore the original text flags")
module.config.enemyTextMode, module.config.enemyRarityIcon = 4, 1
module:Refresh()
assert(cvars.nameplateInfoDisplay == string.char(1, 71),
    "reverting the rarity switch did not restore the native icon with Jundies health text")
module.config.enemyNameOffsetX, module.config.enemyNameOffsetY = 22, -6
module.config.enemyCastOffsetX, module.config.enemyCastOffsetY = 0, -10
module:Refresh()
assert(layoutHook and Placed(name, 1, 4) == 22 and Placed(name, 1, 5) == -6
    and Placed(cast, 1, 5) == -10, "preview layout offsets did not reach Blizzard's regions")
layoutHook(uf)
assert(Placed(name, 1, 4) == 22, "layout post-hook accumulated an offset")
-- Emulate Blizzard rebuilding its anchors; the addon only receives the hook.
name:ClearAllPoints()
name:SetPoint("CENTER", nativeAnchor, "CENTER", 4, 2)
layoutHook(uf)
assert(Placed(name, 1, 4) == 26 and Placed(name, 1, 5) == -4, "native reanchor lost the custom offset")
combat = true
module.config.enemyNameOffsetX = 40
module:Refresh()
assert(Placed(name, 1, 4) == 26, "layout moved a native region in combat")
combat = false
events.PLAYER_REGEN_ENABLED(module, "PLAYER_REGEN_ENABLED")
assert(Placed(name, 1, 4) == 44, "deferred layout change did not apply after combat")
-- A combat-time native layout can reset displacement before the deferred pass.
combat = true
name.offsetX, name.offsetY = 0, 0
layoutHook(uf)
assert(name.offsetX == 0, "layout post-hook wrote during combat")
combat = false
events.PLAYER_REGEN_ENABLED(module, "PLAYER_REGEN_ENABLED")
assert(Placed(name, 1, 4) == 44, "native combat reset bypassed the offset cache on resume")
local layoutWrites = name.offsetWrites
events.UNIT_FLAGS(module, "UNIT_FLAGS", "nameplate1")
assert(name.offsetWrites == layoutWrites, "unit data events rewrote unchanged geometry")
module.config.enemyNameOffsetX, module.config.enemyNameOffsetY = 0, 0
module.config.enemyCastOffsetY = 0
module:Refresh()
assert(Placed(name, 1, 4) == 4 and Placed(name, 1, 5) == 2 and Placed(cast, 1, 5) == 0,
    "reset did not restore the latest Blizzard anchors")
module.active = false
module:Disable()
-- New plates, cast skins and fonts must work on first appearance IN combat.
module.active, combat = true, true
classification, hasMana, isBoss, questUnit, tappedUnit, threatStatus = "normal", false, false, false, false, nil
isTank, grouped, onThreatList = false, false, false
module.config.enemyTankMode = false
module.visuals[bar] = nil
module:Refresh()
assert(module.visuals[bar].fill:IsShown(),
    "first combat appearance deferred the health skin until combat ended")
assert(name.fontSize == 12 and cvars.nameplateShowCastBars == "1")
combat = false

-- Focus disabled falls back to base type; tapped is independent of quest colors.
focusUnit = "nameplate1"
module.config.enemyFocusEnabled = false
module:Refresh()
assert(module.roles[bar] == "Melee", "disabled focus rule swallowed the base role")
focusUnit, tappedUnit = nil, true
module.config.enemyQuestColors = false
events.UNIT_FLAGS(module, "UNIT_FLAGS", "nameplate1")
assert(module.roles[bar] == "Tapped", "tapped color incorrectly required quest colors")
tappedUnit = false

-- EQoL uses lead threat for tanks: zero is safe, not lost. Warnings also work for damage/healers.
isTank, grouped, onThreatList = true, true, true
uf.optionTable = { usePlayerForAggroHighlightThreat = true }
module.config.enemyTankMode, module.config.enemyTankModeColor = true, "26d9ff"
events.GROUP_ROSTER_UPDATE(module, "GROUP_ROSTER_UPDATE")
threatStatus = 0
events.UNIT_THREAT_LIST_UPDATE(module, "UNIT_THREAT_LIST_UPDATE", "nameplate1")
assert(module.roles[bar] == "TankMode", "safe tank aggro did not use the separate tank color")
assert(threatCalls[#threatCalls][1] == "lead" and threatCalls[#threatCalls][2] == "player"
    and threatCalls[#threatCalls][3] == "nameplate1", "tank threat did not follow Blizzard's nameplate API")
onThreatList = false
events.UNIT_THREAT_LIST_UPDATE(module, "UNIT_THREAT_LIST_UPDATE", "nameplate1")
assert(module.roles[bar] == "Melee", "unengaged mob was colored as safe tank aggro")
isTank, threatStatus = false, 3
events.PLAYER_ROLES_ASSIGNED(module, "PLAYER_ROLES_ASSIGNED")
assert(module.roles[bar] == "ThreatLost", "damage/healer taking aggro was not highlighted")
assert(threatCalls[#threatCalls][1] == "situation" and threatCalls[#threatCalls][2] == "player"
    and threatCalls[#threatCalls][3] == "nameplate1", "damage threat did not follow Blizzard's nameplate API")
module.config.enemyThreatLostEnabled = false
events.UNIT_THREAT_SITUATION_UPDATE(module, "UNIT_THREAT_SITUATION_UPDATE", "nameplate1")
assert(module.roles[bar] == nil, "disabled threat override concealed Blizzard's active threat color")
threatStatus = "secret"
events.UNIT_THREAT_SITUATION_UPDATE(module, "UNIT_THREAT_SITUATION_UPDATE", "nameplate1")
assert(module.roles[bar] == "Melee" and module.visuals[bar].fill:IsShown()
    and module.visuals[bar].fill.color[1] == 0xbe / 255,
    "secret threat suppressed the ordinary NPC color")
uf.optionTable = nil
events.UNIT_THREAT_SITUATION_UPDATE(module, "UNIT_THREAT_SITUATION_UPDATE", "nameplate1")
assert(threatCalls[#threatCalls][1] == "situation" and threatCalls[#threatCalls][2] == "nameplate1"
    and threatCalls[#threatCalls][3] == nil,
    "default threat mode used the player-pair API without Blizzard's nameplate option")
threatStatus, grouped, instanceType = nil, false, "arena"
events.ZONE_CHANGED_NEW_AREA(module, "ZONE_CHANGED_NEW_AREA")
assert(module.roles[bar] == nil, "PvP inherited NPC role colors")
instanceType = "none"
events.ZONE_CHANGED_NEW_AREA(module, "ZONE_CHANGED_NEW_AREA")
UnitPlayerControlled = function() return true end
events.UNIT_FACTION(module, "UNIT_FACTION", "nameplate1")
assert(module.roles[bar] == nil, "player-controlled pet received an NPC type color")
UnitPlayerControlled = function() return "secret" end
events.UNIT_FACTION(module, "UNIT_FACTION", "nameplate1")
assert(module.roles[bar] == "Melee", "secret player-control hint suppressed an NPC role")
UnitPlayerControlled = PlayerControlled

-- Role tint is an owned overlay; no user texture may replace Blizzard's fill.
module.config.enemyRoleColors = false
module:Refresh()
assert(bar.barTexture.texture == "native-health" and not module.visuals[bar].fill:IsShown())
focusUnit = "nameplate1"
events.PLAYER_FOCUS_CHANGED(module, "PLAYER_FOCUS_CHANGED")
assert(bar.barTexture.texture == "native-health", "focus changed Blizzard's native texture")
module.config.enemyRoleColors = true
module.config.enemyFocusEnabled = true
module:Refresh()
assert(module.roles[bar] == "Focus" and module.visuals[bar].fill:IsShown(),
    "focus role overlay was not restored")
module.config.enemyRoleColors = false
module.config.enemyFocusEnabled = false

bar.barTexture:SetAtlas("new-native-atlas")
layoutHook(uf)
assert(bar.barTexture.atlas == "new-native-atlas", "layout altered Blizzard's native texture")
focusUnit = nil
events.PLAYER_FOCUS_CHANGED(module, "PLAYER_FOCUS_CHANGED")
assert(bar.barTexture.atlas == "new-native-atlas", "former focus altered Blizzard's native texture")
module:Refresh()
assert(bar.barTexture.atlas == "new-native-atlas", "texture reset lost the latest native atlas")

-- Friendly target marker is attached to UnitFrame, also usable with a hidden health bar.
uf.isFriend, targetUnit = true, "nameplate1"
module.config.enemyTargetHideFriendly = false
events.NAME_PLATE_UNIT_ADDED(module, "NAME_PLATE_UNIT_ADDED", "nameplate1")
assert(module.visuals[bar].targetHost:IsShown(), "friendly target marker option does nothing")
module.config.enemyTargetHideFriendly = true
module:Refresh()
assert(not module.visuals[bar].targetHost:IsShown())
uf.isFriend, targetUnit = false, nil

-- Font override off keeps Blizzard's locale face while SLUG/size/shadow still apply.
module.config.enemyCustomFont, module.config.enemyTextOutline, module.config.enemyTextShadow = false, 4, true
name:SetFont("locale-font", 10, "")
module:Refresh()
assert(name.font == "locale-font" and name.flags == "OUTLINE,SLUG" and name.shadow[4] == 1)
name:SetFont("updated-native-font", 14, "")
fontHook(uf)
assert(name.font == "updated-native-font" and name.fontSize == 12 and name.flags == "OUTLINE,SLUG")
name:SetShadowColor(0, 0, 0, 0.6)
fontHook(uf)
assert(name.shadow[4] == 1, "native frame-options reset left the cached shadow stale")
module.config.enemyTextEnabled = false
module:Refresh()
assert(name.font == "updated-native-font" and name.fontSize == 14 and name.flags == ""
    and name.shadow[4] == 0.6, "disabling typography did not restore Blizzard's latest font/shadow")

-- Marker anchors and size are functional, not just catalog entries.
module.config.enemyEliteMarkerAnchor, module.config.enemyEliteMarkerSize = 4, 48
classification, unitLevel = "worldboss", -1
module:Refresh()
assert(module.visuals[bar].elite.points[1][3] == "TOPRIGHT" and module.visuals[bar].elite.width == 48
    and module.visuals[bar].elite.atlas == "worldquest-icon-boss")

-- Quest cache distinguishes completed, party and unknown objectives without polling.
local tooltipReads = 0
local lines = { { type = 1 }, { type = 3, leftText = "5/5" } }
C_TooltipInfo = { GetUnit = function() tooltipReads = tooltipReads + 1; return { lines = lines } end }
questUnit = true
private.Roles.ClearQuest()
assert(private.Roles.Quest("nameplate1") == false and private.Roles.Quest("nameplate1") == false and tooltipReads == 1)
lines = { { type = 1 }, { type = 2, leftText = "Party Member" }, { type = 3, leftText = "0/5" } }
private.Roles.ClearQuest()
assert(private.Roles.Quest("nameplate1") == false, "party quest was treated as our objective")
lines = { { type = 1 }, { type = 3, leftText = "4/5" } }
private.Roles.ClearQuest()
assert(private.Roles.Quest("nameplate1") == true)
lines = { { type = 1 }, { type = 3, leftText = "secret" } }
private.Roles.ClearQuest()
assert(private.Roles.Quest("nameplate1") == nil and private.Roles.quests.nameplate1 == nil,
    "inaccessible quest text was cached as a completed objective")
local beforeScans = scans
events.UNIT_THREAT_LIST_UPDATE(module, "UNIT_THREAT_LIST_UPDATE", "party1")
assert(scans == beforeScans and not events.UNIT_HEALTH, "unit metadata event triggered a global scan or health polling")
module:Disable()
assert(not module.visuals[bar].elite:IsShown())
-- Cast start/reuse is entirely native, including a plate created without a fill.
module.active = true
uf.isPlayer, uf.isFriend = false, false
cast.statusTexture = nil
module:Refresh()
assert(cast.statusTexture == nil and not cast.created)
combat = true
cast.statusTexture = Region()
cast.statusTexture:SetTexture("first-native-cast")
events.NAME_PLATE_UNIT_ADDED(module, "NAME_PLATE_UNIT_ADDED", "nameplate1")
assert(cast.statusTexture.texture == "first-native-cast")
cast.statusTexture = Region()
cast.statusTexture:SetTexture("next-native-cast")
events.UNIT_DISPLAYPOWER(module, "UNIT_DISPLAYPOWER", "nameplate1")
events.NAME_PLATE_UNIT_REMOVED(module, "NAME_PLATE_UNIT_REMOVED", "nameplate1")
assert(cast.statusTexture.texture == "next-native-cast" and not cast.created,
    "pooled cast was modified by the nameplate skin")
combat = false

-- Group name filtering is roster/event driven and restores the original alpha.
uf.isFriend, uf.isPlayer, grouped = true, true, false
name:SetAlpha(.7)
module.config.friendlyNamesOnly = 3
module:Refresh()
assert(name:GetAlpha() == 0 and cvars.nameplateShowOnlyNameForFriendlyPlayerUnits == "1")
local groupScans = scans
grouped = true
events.GROUP_ROSTER_UPDATE(module, "GROUP_ROSTER_UPDATE")
assert(name:GetAlpha() == .7 and scans == groupScans)
grouped = false
UnitInRaid = function() return 2 end
events.GROUP_ROSTER_UPDATE(module, "GROUP_ROSTER_UPDATE")
assert(name:GetAlpha() == .7, "raid member name hidden")
UnitInRaid = function() return "secret" end
events.GROUP_ROSTER_UPDATE(module, "GROUP_ROSTER_UPDATE")
assert(name:GetAlpha() == .7, "secret membership was used for filtering")
UnitInRaid = function() return nil end
    events.GROUP_ROSTER_UPDATE(module, "GROUP_ROSTER_UPDATE")
    assert(name:GetAlpha() == 0)
    module.config.friendlyNamesOnly = 4
    module:Refresh()
    assert(name:GetAlpha() == .7 and cvars.nameplateShowOnlyNameForFriendlyPlayerUnits == "0",
        "switching from group names to health bars did not restore the name and native bar")
    module.config.friendlyNamesOnly = 3
    module:Refresh()
    assert(name:GetAlpha() == 0 and cvars.nameplateShowOnlyNameForFriendlyPlayerUnits == "1")
    module:Disable()
assert(name:GetAlpha() == .7, "group filter not restored on disable")

-- The native classification texture is independently movable and reversible.
module.active, uf.isPlayer, uf.isFriend = true, false, false
module.config.enemyHealthOffsetX, module.config.enemyHealthOffsetY = 13, -4
module:Refresh()
assert(healthContainer.offsetX == 13 and healthContainer.offsetY == -4,
    "health drag did not move Blizzard's health container")
layoutHook(uf)
assert(healthContainer.offsetX == 13 and healthContainer.offsetY == -4,
    "Blizzard anchor rebuild lost the health position")
module.config.enemyHealthOffsetX, module.config.enemyHealthOffsetY = 0, 0
module:Refresh()
assert(healthContainer.offsetX == 0 and healthContainer.offsetY == 0,
    "reset did not restore Blizzard's health container")
local function HealthLeft()
    for _, point in ipairs(healthContainer.points) do
        if point[1] == "BOTTOMLEFT" then return point end
    end
end
module.config.enemyHealthWidthDelta, module.config.enemyHealthHeightDelta = 73, 7
module:Refresh()
assert(HealthLeft()[4] == -73 and healthContainer.height == 20,
    "enemy health width and height did not reach Blizzard's anchored bar")
layoutHook(uf)
assert(HealthLeft()[4] == -73 and healthContainer.height == 20,
    "Blizzard anchor rebuild lost enemy health dimensions")
module.config.look = 2
module:Refresh()
assert(HealthLeft()[4] == 0 and healthContainer.height == 13,
    "Blizzard look retained the custom enemy health dimensions")
module.config.look = 1
module:Refresh()
assert(HealthLeft()[4] == -73 and healthContainer.height == 20,
    "Jundies did not restore its enemy health dimensions")
uf.isFriend = true
module:Refresh()
assert(HealthLeft()[4] == 0 and healthContainer.height == 13,
    "enemy health dimensions leaked onto a friendly nameplate")
module.config.friendlyHealthWidthDelta, module.config.friendlyHealthHeightDelta = 28, 4
module:Refresh()
assert(HealthLeft()[4] == -28 and healthContainer.height == 17,
    "friendly health dimensions did not reach Blizzard's anchored bar")
layoutHook(uf)
assert(HealthLeft()[4] == -28 and healthContainer.height == 17,
    "Blizzard anchor rebuild lost friendly health dimensions")
module.config.friendlyHealthWidthDelta, module.config.friendlyHealthHeightDelta = 0, 0
module:Refresh()
assert(HealthLeft()[4] == 0 and healthContainer.height == 13,
    "friendly health dimensions did not restore the native anchors and height")
uf.isFriend = false
module:Refresh()
module.config.enemyHealthWidthDelta, module.config.enemyHealthHeightDelta = 0, 0
module:Refresh()
assert(HealthLeft()[4] == 0 and healthContainer.height == 13,
    "enemy health dimensions did not restore the native anchors and height")
local nativeElite = Region()
uf.ClassificationFrame = { classificationIndicator = nativeElite }
module.config.enemyClassificationOffsetX, module.config.enemyClassificationOffsetY = 17, -5
module:Refresh()
assert(Placed(nativeElite, 1, 4) == 17 and Placed(nativeElite, 1, 5) == -5)
layoutHook(uf)
assert(Placed(nativeElite, 1, 4) == 17)
module.config.enemyClassificationOffsetX, module.config.enemyClassificationOffsetY = 0, 0
module:Refresh()
assert(Placed(nativeElite, 1, 4) == 0 and Placed(nativeElite, 1, 5) == 0)

-- Modern Blizzard anchors the bar and spell name to the icon, while
-- Classic anchors the icon to the bar. Both must move as one cast group,
-- and an icon-only offset must not drag the progress bar along with it.
cast.Icon, cast.BorderShield, cast.CastTargetNameText, cast.Border = Region(), Region(), Region(), Region()
local function NativeCastAnchors(classic)
    NamePlateSetupOptions.useClassicCastBar = classic
    cast:ClearAllPoints(); cast.Icon:ClearAllPoints(); cast.Text:ClearAllPoints()
    cast.BorderShield:ClearAllPoints(); cast.CastTargetNameText:ClearAllPoints(); cast.Border:ClearAllPoints()
    cast.Border:SetPoint("CENTER", nativeAnchor, "CENTER", 0, 0)
    if classic then
        cast:SetPoint("TOPLEFT", nativeAnchor, "TOPLEFT", 0, 0)
        cast.Icon:SetPoint("LEFT", cast.Border, "LEFT", 0, 0)
        cast.Text:SetPoint("LEFT", cast, "LEFT", 2, 0)
        cast.BorderShield:SetPoint("RIGHT", cast, "RIGHT", 0, 0)
        cast.CastTargetNameText:SetPoint("TOPRIGHT", cast, "BOTTOMRIGHT", 0, 0)
    else
        cast:SetPoint("BOTTOM", cast.Icon, "TOP", 0, 0)
        cast:SetPoint("LEFT", nativeAnchor, "BOTTOMLEFT", 0, 0)
        cast:SetPoint("RIGHT", nativeAnchor, "BOTTOMRIGHT", 0, 0)
        cast.Icon:SetPoint("BOTTOMLEFT", nativeAnchor, "BOTTOMLEFT", 0, 0)
        cast.Text:SetPoint("LEFT", cast.Icon, "RIGHT", 2, 0)
        cast.BorderShield:SetPoint("RIGHT", cast.Icon, "RIGHT", 0, 0)
        cast.CastTargetNameText:SetPoint("LEFT", cast.Text, "RIGHT", 2, 0)
        cast.CastTargetNameText:SetPoint("RIGHT", cast, "RIGHT", -4, 0)
    end
end
NativeCastAnchors(false)
module.config.enemyCastOffsetX, module.config.enemyCastOffsetY = 20, -10
module.config.enemyCastIconOffsetX, module.config.enemyCastIconOffsetY = 9, -4
module.config.enemyCastTextOffsetX, module.config.enemyCastTextOffsetY = 5, 2
module:Refresh()
assert(Placed(cast, 1, 4) == -9 and Placed(cast, 1, 5) == 4
    and Placed(cast, 2, 4) == 20 and Placed(cast, 2, 5) == -10)
assert(Placed(cast.Icon, 1, 4) == 29 and Placed(cast.Icon, 1, 5) == -14)
assert(Placed(cast.Text, 1, 4) == -2 and Placed(cast.Text, 1, 5) == 6)
assert(Placed(cast.CastTargetNameText, 1, 4) == -3 and Placed(cast.CastTargetNameText, 1, 5) == -2)
layoutHook(uf)
assert(Placed(cast.Icon, 1, 4) == 29, "cast group drifted on repeated layout")
NativeCastAnchors(true)
layoutHook(uf)
assert(Placed(cast, 1, 4) == 20 and Placed(cast, 1, 5) == -10
    and Placed(cast.Icon, 1, 4) == 9 and Placed(cast.Icon, 1, 5) == -4,
    "Classic cast anchor direction compounded the drag offset")
module.config.enemyCastOffsetX, module.config.enemyCastOffsetY = 0, 0
module.config.enemyCastIconOffsetX, module.config.enemyCastIconOffsetY = 0, 0
module.config.enemyCastTextOffsetX, module.config.enemyCastTextOffsetY = 0, 0
module:Refresh()
assert(Placed(cast, 1, 4) == 0 and Placed(cast.Icon, 1, 4) == 0 and Placed(cast.Text, 1, 4) == 2)

-- Modern with spell name inside uses the opposite Icon -> bar dependency.
NamePlateSetupOptions.useClassicCastBar, NamePlateSetupOptions.spellNameInsideCastBar = false, true
cast:ClearAllPoints(); cast.Icon:ClearAllPoints(); cast.Text:ClearAllPoints()
cast.CastTargetNameText:ClearAllPoints()
cast:SetPoint("TOPLEFT", nativeAnchor, "TOPLEFT", 0, 0)
cast:SetPoint("BOTTOMRIGHT", nativeAnchor, "BOTTOMRIGHT", 0, 0)
cast.Icon:SetPoint("LEFT", cast, "LEFT", 0, 0)
cast.Text:SetPoint("LEFT", cast.Icon, "RIGHT", 2, 0)
cast.CastTargetNameText:SetPoint("LEFT", cast.Text, "RIGHT", 2, 0)
cast.CastTargetNameText:SetPoint("RIGHT", cast, "RIGHT", -4, 0)
layoutHook(uf)
module.config.enemyCastOffsetX, module.config.enemyCastOffsetY = 20, -10
module.config.enemyCastIconOffsetX, module.config.enemyCastIconOffsetY = 9, -4
module.config.enemyCastTextOffsetX, module.config.enemyCastTextOffsetY = 5, 2
module:Refresh()
assert(#cast.points == 2 and cast.offsetX == 20 and cast.offsetY == -10)
assert(cast.Icon.offsetX == 9 and cast.Icon.offsetY == -4)
assert(cast.Text.offsetX == -4 and cast.Text.offsetY == 6)
assert(Placed(cast.CastTargetNameText, 1, 4) == -3 and Placed(cast.CastTargetNameText, 2, 4) == -4,
    "moving the spell name dragged/stretched the spell target text")
module:Disable()
assert(cast.offsetX == 0 and cast.Icon.offsetX == 0 and cast.Text.offsetX == 0
    and cast.CastTargetNameText.points[1][4] == 2, "disable did not restore cast links/displacement")
module.active = true
module.config.enemyCastOffsetX, module.config.enemyCastOffsetY = 0, 0
module.config.enemyCastIconOffsetX, module.config.enemyCastIconOffsetY = 0, 0
module.config.enemyCastTextOffsetX, module.config.enemyCastTextOffsetY = 0, 0

-- The name, raid icon and classification must have independent offsets,
-- including a recycled enemy plate becoming a friendly names-only plate.
uf.RaidTargetFrame = Region()
uf.showOnlyName, uf.isFriend = true, true
module.config.friendlyNameOffsetX, module.config.friendlyNameOffsetY = 16, 3
module.config.friendlyRaidIconOffsetX, module.config.friendlyRaidIconOffsetY = 4, -6
module.config.friendlyClassificationOffsetX, module.config.friendlyClassificationOffsetY = 7, 2
module:Refresh()
assert(name.offsetX == 16 and name.offsetY == 3)
assert(uf.RaidTargetFrame.offsetX == -12 and uf.RaidTargetFrame.offsetY == -9)
assert(nativeElite.offsetX == 3 and nativeElite.offsetY == 8)
uf.isFriend = false
events.NAME_PLATE_UNIT_ADDED(module, "NAME_PLATE_UNIT_ADDED", "nameplate1")
assert(name.offsetX == 0 and uf.RaidTargetFrame.offsetX == 0 and nativeElite.offsetX == 0,
    "recycled plate retained the friendly drag layout")
uf.showOnlyName = false

-- Moving health text must not pull the name's right edge; moving an above-bar
-- name must not pull the debuff list's bottom anchor along with it.
NamePlateSetupOptions.unitNameAnchorStyle = 2
debuffPadding = 6
bar.LeftText = Region()
aura.DebuffListFrame = Region()
name:ClearAllPoints()
name:SetPoint("BOTTOMLEFT", nativeAnchor, "TOPLEFT", 4, 2)
name:SetPoint("BOTTOMRIGHT", bar.Text, "BOTTOMLEFT", -2, 0)
aura.DebuffListFrame:ClearAllPoints()
aura.DebuffListFrame:SetPoint("LEFT", nativeAnchor, "LEFT", 0, 0)
aura.DebuffListFrame:SetPoint("BOTTOM", name, "TOP", 0, 6)
layoutHook(uf)
module.config.enemyNameOffsetX, module.config.enemyNameOffsetY = 15, -3
module.config.enemyHealthTextOffsetX, module.config.enemyHealthTextOffsetY = -12, 5
module.config.enemyAurasOffsetX, module.config.enemyAurasOffsetY = 2, 8
module:Refresh()
assert(Placed(name, 2, 4) == 25 and Placed(name, 2, 5) == -8)
assert(bar.LeftText.offsetX == -12 and bar.LeftText.offsetY == 5)
assert(Placed(aura.DebuffListFrame, 1, 4) == 2 and Placed(aura.DebuffListFrame, 2, 4) == -13
    and Placed(aura.DebuffListFrame, 2, 5) == 17)
assert(aura.DebuffListFrame.offsetX == nil and aura.DebuffListFrame.offsetY == nil,
    "debuff positioning must preserve both native anchor bases")
module:Disable()
assert(name.points[2][4] == -2 and name.points[2][5] == 0 and name.offsetX == 0
    and aura.DebuffListFrame.points[2][4] == 0 and aura.DebuffListFrame.points[2][5] == 6)
module.active = true
module.config.enemyNameOffsetX, module.config.enemyNameOffsetY = 0, 0
module.config.enemyHealthTextOffsetX, module.config.enemyHealthTextOffsetY = 0, 0
module.config.enemyAurasOffsetX, module.config.enemyAurasOffsetY = 0, 0

-- Forever uses RIGHT (not BOTTOMRIGHT) above the bar. A shown level frame
-- owns that dynamic endpoint; it must never be replaced with a guessed link.
NamePlateSetupOptions.nameJustificationWhenAboveHealthBar = "LEFT"
uf.PlayerLevelDiffFrame = Region()
name:ClearAllPoints()
name:SetPoint("BOTTOMLEFT", nativeAnchor, "TOPLEFT", 0, 2)
name:SetPoint("RIGHT", uf.PlayerLevelDiffFrame, "RIGHT", 0, 0)
module.config.enemyHealthTextOffsetX = 10
module:Refresh()
assert(#name.points == 2 and name.points[2][2] == uf.PlayerLevelDiffFrame)
uf.PlayerLevelDiffFrame:Hide()
name:ClearAllPoints()
name:SetPoint("BOTTOMLEFT", nativeAnchor, "TOPLEFT", 0, 2)
name:SetPoint("RIGHT", bar.Text, "LEFT", -2, 0)
layoutHook(uf)
assert(#name.points == 2 and name.points[2][1] == "RIGHT" and name.points[2][4] == -12)
module:Disable()
assert(name.points[2][1] == "RIGHT" and name.points[2][4] == -2)
NamePlateSetupOptions.nameJustificationWhenAboveHealthBar = nil
module.config.enemyHealthTextOffsetX = 0
module.active = true

-- Shape/layout/anchor/direction use the actual MSUF boss renderer.
targetUnit = "nameplate1"
module.config.enemyTargetStyle, module.config.enemyTargetLayout = 11, 3
module:Refresh()
marker = module.visuals[bar].targetHost._msufBossTargetIndicator
assert(marker._style == "TRIPLE_ARROW" and #marker.lines == 6 and marker._layout == "BOTH_OUT")
module.config.enemyTargetStyle, module.config.enemyTargetLayout = 12, 1
module.config.enemyTargetAnchor, module.config.enemyTargetDirection = 2, 3
module:Refresh()
assert(marker._style == "DIAMOND" and marker._anchor == "TOP" and marker._direction == "UP"
    and not marker.mirror:IsShown() and not marker.lines[5]:IsShown())
module.config.enemyTargetStyle = 2
module:Refresh()
assert(marker._suiteAtlas:IsShown() and not marker.lines[1]:IsShown())
module.config.enemyTargetStyle = 12
module:Refresh()
assert(not marker._suiteAtlas:IsShown() and marker.lines[1]:IsShown() and not marker.lines[5]:IsShown())
module.config.enemyTargetStyle = 9
module:Refresh()
assert(not marker:IsShown() and module.visuals[bar].targetBorder.edges[1]:IsShown())
module:Disable()

do
    module.active, uf.isFriend, uf.isPlayer = true, false, false
    module.config.look = 3
    module.config.enemyRoleColors, module.config.enemyQuestColors = true, false
    classification, unitLevel, targetUnit, focusUnit = "normal", 90, nil, nil
    local nativeTexture = bar.barTexture.texture
    module:Refresh()
    assert(bar.barTexture.texture == nativeTexture and module.visuals[bar].fill:IsShown(),
        "role skin replaced Blizzard's health texture")
    uf.isFriend = true
end

-- Friendly NPC markers and cast text have their own live settings and restore.
do
    local c = module.config
    c.friendlyEliteMarker, c.friendlyQuestMarker, questUnit = true, true, true
    c.friendlyEliteOffsetX, c.friendlyEliteOffsetY, c.friendlyEliteMarkerSize = 23, 8, 19
    c.friendlyQuestOffsetX, c.friendlyQuestOffsetY = -30, 12
    c.friendlyCastTextEnabled, c.friendlyCastCustomFont, c.friendlyCastTextShadow = true, true, true
    c.friendlyCastFont, c.friendlyCastSize, c.friendlyCastOutline = "friendly-font", 18, 5
    classification, instanceType, focusUnit = "rareelite", "none", nil
    C_TooltipInfo = { GetUnit = function() return nil end }
    C_Secrets = { ShouldUnitIdentityBeSecret = function() return false end }
    cast.Text:SetFont("friendly-native", 10, "")
    cast.CastTargetNameText:SetFont("friendly-target-native", 9, "")
    private.Roles.ClearQuest()
    module:Refresh()
    local visual = module.visuals[bar]
    assert(visual.elite:IsShown() and visual.elite.points[1][4] == 23 and visual.elite.width == 19
        and visual.quest:IsShown() and visual.quest.points[1][4] == -30, "friendly marker positions were not applied")
    assert(cast.Text.font == "friendly-font" and cast.Text.fontSize == 18 and cast.Text.flags == "THICKOUTLINE,SLUG"
        and cast.Text.shadow[4] == 1 and cast.CastTargetNameText.font == "friendly-font")
    c.friendlyCastTextEnabled = false
    c.friendlyEliteMarker, c.friendlyQuestMarker = false, false
    module:Refresh()
    assert(cast.Text.font == "friendly-native" and cast.CastTargetNameText.font == "friendly-target-native"
        and not visual.elite:IsShown() and not visual.quest:IsShown(), "friendly customizations were not reversible")
    c.friendlyNPCs, c.playerGuildNames, c.playerTitles = 3, 2, 3
    module:Refresh()
    assert(cvars.nameplateShowFriendlyNpcs == "0" and cvars.UnitNamePlayerGuild == "1" and cvars.UnitNamePlayerPVPTitle == "0")
    c.friendlyNPCs, c.playerGuildNames, c.playerTitles = 1, 1, 1
    module:Refresh()
    assert(restored.nameplateShowFriendlyNpcs and restored.UnitNamePlayerGuild and restored.UnitNamePlayerPVPTitle)
    c.enemyTargetStyle, c.enemyTargetMarker = 15, true
    uf.isFriend, targetUnit = false, "nameplate1"
    module:Refresh()
    assert(NS.NameplateStyle.TargetConfig(c).atlas[1] == "pvptalents-selectedarrow"
        and visual.targetHost._msufBossTargetIndicator._suiteAtlas.atlas == "pvptalents-selectedarrow")
end
-- New Blizzard-owned controls preserve unrelated bits and add no unit scans.
do
    local c = module.config
    c.classColors = 2
    module:Refresh()
    assert(cvars.nameplateShowClassColor == "1"
        and cvars.nameplateShowFriendlyClassColor == "1",
        "player class colors missed Forever's friendly health bar CVar")
    c.classColors = 3
    module:Refresh()
    assert(cvars.nameplateShowClassColor == "0"
        and cvars.nameplateShowFriendlyClassColor == "0",
        "turning off class colors did not reach both Forever plate types")
    restored.nameplateShowClassColor, restored.nameplateShowFriendlyClassColor = nil, nil
    c.classColors = 1
    module:Refresh()
    assert(restored.nameplateShowClassColor and restored.nameplateShowFriendlyClassColor,
        "class color CVars were not released back to Blizzard")
    liveCVars.nameplateEnemyNpcAuraDisplay = string.char(1, 64)
    liveCVars.nameplateEnemyPlayerAuraDisplay = string.char(1, 64)
    liveCVars.nameplateFriendlyPlayerAuraDisplay = string.char(1, 64)
    liveCVars.nameplateThreatDisplay = string.char(1, 68) -- native health color bit
    c.enemyNpcAuraMode, c.enemyNpcBuffs, c.enemyNpcDebuffs, c.enemyNpcControl = 2, false, true, true
    c.enemyPlayerAuraMode, c.enemyPlayerBuffs, c.enemyPlayerDebuffs, c.enemyPlayerControl = 2, true, false, true
    c.friendlyPlayerAuraMode = 2
    c.friendlyPlayerBuffs, c.friendlyPlayerDebuffs, c.friendlyPlayerControl = false, true, false
    c.friendlyNpcDebuffs, c.auraScaleMode, c.auraScalePercent = 3, 2, 120
    c.threatSignalMode, c.threatFlash, c.threatHighlight = 2, true, false
    c.softTargetEnemy, c.softTargetFriend, c.softTargetInteract = 2, 3, 2
    c.softTargetIconGate = 2
    module:Refresh()
    assert(cvars.nameplateEnemyNpcAuraDisplay == string.char(1, 70)
        and cvars.nameplateEnemyPlayerAuraDisplay == string.char(1, 69)
        and cvars.nameplateFriendlyPlayerAuraDisplay == string.char(1, 66),
        "Blizzard aura category bits were not applied")
    assert(cvars.nameplateThreatDisplay == string.char(1, 70),
        "aggro signals overwrote Blizzard's health-color bit")
    assert(cvars.nameplateShowDebuffsOnFriendly == "0" and cvars.nameplateAuraScale == "1.2"
        and cvars.SoftTargetIconEnemy == "1" and cvars.SoftTargetIconFriend == "0"
        and cvars.SoftTargetIconInteract == "1" and cvars.SoftTargetNameplateSize == "1",
        "native aura/soft-target CVars were not applied")
    c.enemyNpcAuraMode, c.enemyPlayerAuraMode, c.friendlyPlayerAuraMode = 1, 1, 1
    c.friendlyNpcDebuffs, c.auraScaleMode, c.threatSignalMode = 1, 1, 1
    c.softTargetEnemy, c.softTargetFriend, c.softTargetInteract = 1, 1, 1
    c.softTargetIconGate = 1
    module:Refresh()
    for _, key in ipairs({ "nameplateEnemyNpcAuraDisplay", "nameplateEnemyPlayerAuraDisplay",
        "nameplateFriendlyPlayerAuraDisplay", "nameplateShowDebuffsOnFriendly", "nameplateAuraScale",
        "nameplateThreatDisplay", "SoftTargetIconEnemy", "SoftTargetIconFriend", "SoftTargetIconInteract",
        "SoftTargetNameplateSize" }) do
        assert(restored[key], "Blizzard CVar was not released: " .. key)
    end
end

-- Custom warning colors tint Blizzard's existing textures and restore their
-- previous colors. The progressive pieces must be repainted after Blizzard.
do
    local c = module.config
    private.Threat.Enable(module)
    uf.isFriend = false
    uf.aggroFlash, uf.aggroHighlight = Region(), Region()
    uf.aggroHighlightBase, uf.aggroHighlightAdditive = Region(), Region()
    uf.aggroFlash:SetVertexColor(1, 1, 0, 1)
    uf.aggroHighlight:SetVertexColor(1, .45, 0, 1)
    c.threatFlashColorEnabled, c.threatFlashColor = true, "00ff00"
    c.threatHighlightColorEnabled, c.threatHighlightColor = true, "0000ff"
    module:Refresh()
    assert(instanceHooks.UpdateAggroHighlight == 1 and instanceHooks.ApplyFrameOptions == 1,
        "the threat hook missed an existing unit frame or a frame was hooked twice")
    assert(threatColorHook and uf.aggroFlash.vertexColor[2] == 1
        and uf.aggroHighlightBase.vertexColor[3] == 1
        and uf.aggroHighlightAdditive.vertexColor[3] == 1,
        "native threat textures did not receive the configured colors")
    local flashWrites = uf.aggroFlash.vertexColorWrites
    local highlightWrites = uf.aggroHighlightBase.vertexColorWrites
    module:Refresh()
    assert(uf.aggroFlash.vertexColorWrites == flashWrites
        and uf.aggroHighlightBase.vertexColorWrites == highlightWrites,
        "unchanged nameplates repainted native threat textures")
    uf.aggroHighlightBase:SetVertexColor(1, .45, 0)
    uf:UpdateAggroHighlight()
    assert(uf.aggroHighlightBase.vertexColor[3] == 1,
        "Blizzard's threat update on an existing unit frame replaced the custom progressive color")
    module:Refresh()
    assert(instanceHooks.UpdateAggroHighlight == 1, "a refresh hooked an existing unit frame again")
    c.threatFlashColorEnabled, c.threatHighlightColorEnabled = false, false
    module:Refresh()
    assert(uf.aggroFlash.vertexColor[1] == 1 and uf.aggroFlash.vertexColor[2] == 1
        and uf.aggroFlash.vertexColor[3] == 0 and uf.aggroHighlightBase.vertexColor[2] == .45,
        "native threat texture colors did not restore")
end

-- Move each native aura category and the soft-target frame independently.
do
    uf.isFriend = false
    aura.BuffListFrame, aura.CrowdControlListFrame, aura.LossOfControlFrame = Region(), Region(), Region()
    aura.BuffListFrame:ClearAllPoints()
    aura.BuffListFrame:SetPoint("RIGHT", uf.ClassificationFrame, "LEFT", -5, 0)
    aura.CrowdControlListFrame:ClearAllPoints()
    aura.CrowdControlListFrame:SetPoint("LEFT", uf.HealthBarsContainer, "RIGHT", 5, 0)
    aura.LossOfControlFrame:ClearAllPoints()
    aura.LossOfControlFrame:SetPoint("LEFT", uf.HealthBarsContainer, "RIGHT", 5, 0)
    uf.SoftTargetFrame = Region()
    module.config.enemyAurasOffsetX = -320
    module.config.enemyBuffsOffsetX, module.config.enemyControlAuraOffsetY = 340, -360
    module.config.enemySoftTargetOffsetX = -11
    module:Refresh()
    assert(aura.DebuffListFrame.points[1][4] == -320
        and aura.BuffListFrame.points[1][4] == 335
        and aura.CrowdControlListFrame.points[1][4] == 5
        and aura.CrowdControlListFrame.points[1][5] == -360
        and aura.LossOfControlFrame.points[1][4] == 5
        and aura.LossOfControlFrame.points[1][5] == -360
        and uf.SoftTargetFrame.offsetX == -11,
        "native aura positions lost their Blizzard anchor spacing")
    layoutHook(uf)
    assert(aura.BuffListFrame.points[1][4] == 335
        and aura.CrowdControlListFrame.points[1][5] == -360,
        "Blizzard anchor rebuild lost the saved aura positions")
    module.needsRefresh = false
    combat = true
    layoutHook(uf)
    assert(module.needsRefresh and aura.BuffListFrame.points[1][4] == 335,
        "aura anchor rebuild attempted a protected edit in combat")
    combat = false
    events.PLAYER_REGEN_ENABLED(module)
    assert(aura.BuffListFrame.points[1][4] == 335,
        "deferred aura positions did not recover after combat")
    module.config.enemyAurasOffsetX = 0
    module.config.enemyBuffsOffsetX, module.config.enemyControlAuraOffsetY = 0, 0
    module.config.enemySoftTargetOffsetX = 0
    private.Layout.Configure(module.config)
    aura.DebuffListFrame:SetPoint("BOTTOM", name, "TOP", 0, 6)
    layoutHook(uf)
    module:Refresh()
    assert(aura.DebuffListFrame.points[1][4] == 0 and aura.BuffListFrame.points[1][4] == -5
        and aura.CrowdControlListFrame.points[1][4] == 5
        and aura.CrowdControlListFrame.points[1][5] == 0
        and aura.LossOfControlFrame.points[1][4] == 5
        and aura.LossOfControlFrame.points[1][5] == 0 and uf.SoftTargetFrame.offsetX == 0,
        "native aura spacing did not restore")
end

do
    module.config.enemyLevelEnabled = true
    module.config.enemyLevelOffsetX = -8
    module:Refresh()
    local label = assert(module.levelLabels[uf], "modern nameplate level label was not created")
    assert(label.text == 90 and label:IsShown() and label.offsetX == -8,
        "modern level or its preview offset did not reach the nameplate")
    module.config.enemyLevelSize = 18
    module:Refresh()
    assert(label.textHeight == 18 and label.width == 36,
        "selected Jundies level font size did not reach Retail runtime")
    module.config.enemyLevelSize = 0
    module:Refresh()
    unitLevel = 72
    events.UNIT_LEVEL(module, "UNIT_LEVEL", "nameplate1")
    assert(label.text == 72, "UNIT_LEVEL did not refresh the displayed level")
    unitLevel = -1
    events.UNIT_LEVEL(module, "UNIT_LEVEL", "nameplate1")
    assert(label.text == "??", "unknown unit level was shown as a negative number")
    unitLevel = "secret"
    events.UNIT_LEVEL(module, "UNIT_LEVEL", "nameplate1")
    assert(label.text == "secret" and label:IsShown(),
        "secret level was compared or hidden instead of passed to SetText")
    unitLevel = 90
    targetUnit = "nameplate1"
    module.config.enemyTargetLayout, module.config.enemyTargetAnchor = 2, 4
    NamePlateSetupOptions.playerLevelDiffWidth = 18
    uf.PlayerLevelDiffFrame:Show()
    module:Refresh()
    assert(not label:IsShown() and uf.PlayerLevelDiffFrame.offsetX == -8,
        "Retail player level indicator was duplicated or ignored the level offset")
    local target = module.visuals[bar].targetHost._msufBossTargetIndicator
    local targetX = NS.NameplateStyle.TargetConfig(module.config).bossTargetX
    assert(target.offsetX == targetX - 22 and target.mirror.offsetX == -targetX,
        "Retail's left level indicator overlapped the paired target arrow")
    module.config.enemyTargetLayout, module.config.enemyTargetAnchor = 1, 4
    module:Refresh()
    targetX = NS.NameplateStyle.TargetConfig(module.config).bossTargetX
    assert(target.offsetX == targetX - 22 and not target.mirror:IsShown(),
        "single left target arrow overlapped Retail's player level indicator")
    module.config.enemyTargetLayout, module.config.enemyTargetAnchor = 2, 4
    uf.PlayerLevelDiffFrame:Hide()
    module:Refresh()
    targetX = NS.NameplateStyle.TargetConfig(module.config).bossTargetX
    assert(label:IsShown() and uf.PlayerLevelDiffFrame.offsetX == 0 and target.offsetX == targetX,
        "Retail NPC level did not return after the player indicator disappeared")
    -- A level change that brings or removes Blizzard's indicator moves the
    -- target arrows at once, without waiting for the next repaint.
    uf.PlayerLevelDiffFrame:Show()
    events.UNIT_LEVEL(module, "UNIT_LEVEL", "nameplate1")
    assert(target.offsetX == targetX - 22, "UNIT_LEVEL left the target arrow over the player level indicator")
    uf.PlayerLevelDiffFrame:Hide()
    events.UNIT_LEVEL(module, "UNIT_LEVEL", "nameplate1")
    assert(target.offsetX == targetX, "UNIT_LEVEL kept the target arrow gap of a hidden level indicator")
    NamePlateSetupOptions.levelIconWidth = 15
    NamePlateSetupOptions.useClassicHealthBar = true
    module:Refresh()
    assert(not label:IsShown() and uf.LevelFrame.offsetX == -8,
        "Retail Classic style duplicated the native level or lost its drag offset")
    assert(target.mirror.offsetX == -targetX + 19,
        "Retail Classic level plaque overlapped the mirrored target arrow")
    module.config.enemyTargetLayout, module.config.enemyTargetAnchor = 1, 6
    module:Refresh()
    targetX = NS.NameplateStyle.TargetConfig(module.config).bossTargetX
    assert(target.offsetX == targetX + 19 and not target.mirror:IsShown(),
        "single right target arrow overlapped Classic's level plaque")
    module.config.enemyTargetLayout, module.config.enemyTargetAnchor = 2, 4
    NamePlateSetupOptions.useClassicHealthBar = false
    module:Refresh()
    assert(label:IsShown() and uf.LevelFrame.offsetX == 0,
        "switching back to Retail Modern left the native Classic level displaced")
    targetX = NS.NameplateStyle.TargetConfig(module.config).bossTargetX
    assert(target.mirror.offsetX == -targetX,
        "switching back to Retail Modern left the mirrored arrow displaced")
    targetUnit = nil
    module.config.enemyLevelEnabled = false
    module.config.enemyLevelOffsetX = 0
    module:Refresh()
    assert(not label:IsShown() and label.offsetX == 0,
        "disabling level left a visible or displaced custom label")
    uf.isFriend = true
    module.config.friendlyLevelEnabled = true
    module:Refresh()
    assert(label:IsShown() and label.text == 90,
        "friendly nameplates did not display their enabled level")
    module.config.friendlyLevelEnabled = false
    uf.isFriend = false
    module:Refresh()
end

-- Forever's CC lists must keep the native badge reservation when moved,
-- including after Blizzard rebuilds anchors for a different unit or scale.
do
    private.Layout.Restore(uf)
    local savedConfig, savedForever = module.config, NS.Client.isForever
    local savedWidth = NamePlateSetupOptions.playerLevelDiffWidth
    local badge = uf.PlayerLevelDiffFrame
    local savedShown = badge:IsShown()
    local display = true
    local config = {}
    for key, value in pairs(savedConfig) do config[key] = value end
    for _, prefix in ipairs({ "enemy", "friendly" }) do
        for _, element in ipairs(NS.NameplateStyle.Elements) do
            config[prefix .. element.key .. "OffsetX"] = 0
            config[prefix .. element.key .. "OffsetY"] = 0
        end
    end
    config.enemyControlAuraOffsetX, config.enemyControlAuraOffsetY = 13, -7
    module.config, NS.Client.isForever = config, true
    NamesOnlyUnit(false)
    badge.ShouldDisplay = function() error("Blizzard's ShouldDisplay ran in addon code") end
    badge:Hide() -- Camelot's display rule, not transient visibility, owns the reservation.
    NamePlateSetupOptions.playerLevelDiffWidth = 28
    private.Layout.Configure(config)
    local function NativeAnchors()
        local x = 5 + (display and NamePlateSetupOptions.playerLevelDiffWidth + 5 or 0)
        aura.CrowdControlListFrame:SetPoint("LEFT", uf.HealthBarsContainer, "RIGHT", x, 0)
        aura.LossOfControlFrame:SetPoint("LEFT", uf.HealthBarsContainer, "RIGHT", x, 0)
    end
    local function Check(x, y, message)
        for _, region in ipairs({ aura.CrowdControlListFrame, aura.LossOfControlFrame }) do
            assert(region.points[1][4] == x and region.points[1][5] == y, message)
        end
    end
    NativeAnchors()
    private.Layout.Apply(uf, "enemy", config, true)
    Check(51, -7, "Forever moved CC auras into the native level badge")
    private.Layout.Restore(uf)
    Check(38, 0, "Forever CC reset discarded the native level reservation")
    private.Layout.Apply(uf, "enemy", config, true)
    NamePlateSetupOptions.playerLevelDiffWidth = 40
    NativeAnchors()
    layoutHook(uf)
    Check(63, -7, "Forever CC layout ignored the updated badge width")
    display = false
    NamesOnlyUnit(true)
    NativeAnchors()
    layoutHook(uf)
    Check(18, -7, "Forever CC layout reserved a badge for a names-only unit")
    display = true
    NamesOnlyUnit(false)
    NamePlateSetupOptions.playerLevelDiffWidth = 32
    NativeAnchors()
    combat, module.needsRefresh = true, false
    layoutHook(uf)
    Check(42, 0, "Forever CC hook changed protected anchors in combat")
    assert(module.needsRefresh, "Forever CC combat refresh was not deferred")
    combat = false
    private.Layout.Apply(uf, "enemy", config, true)
    Check(55, -7, "Forever CC layout did not recover after combat")
    -- Removing the offset during a native rebuild must keep its new base.
    config.enemyControlAuraOffsetX, config.enemyControlAuraOffsetY = 0, 0
    private.Layout.Configure(config)
    display = false
    NamesOnlyUnit(true)
    NativeAnchors()
    layoutHook(uf)
    Check(5, 0, "Forever CC reset restored a stale badge reservation")
    private.Layout.Restore(uf)
    module.config, NS.Client.isForever = savedConfig, savedForever
    NamePlateSetupOptions.playerLevelDiffWidth = savedWidth
    NamesOnlyUnit(false)
    badge.ShouldDisplay = nil
    badge:SetShown(savedShown)
    module:Refresh()
end

-- Forever reserves a right badge slot, but Jundies uses the same plain number
-- as Retail. The native Camelot badge remains an explicit appearance choice.
do
    NS.Client.isForever = true
    NamePlateSetupOptions.playerLevelDiffWidth = 28
    uf.PlayerLevelDiffFrame:Show()
    module.config.enemyLevelEnabled = true
    module.config.enemyLevelOffsetX = 6
    module.config.levelAppearance = 1
    targetUnit = "nameplate1"
    module:Refresh()
    local label = assert(module.levelLabels[uf])
    local target = module.visuals[bar].targetHost._msufBossTargetIndicator
    local targetX = NS.NameplateStyle.TargetConfig(module.config).bossTargetX
    assert(label:IsShown() and label.offsetX == 6 and uf.PlayerLevelDiffFrame:GetAlpha() == 0
        and target.offsetX == targetX - 28 and target.mirror.offsetX == -targetX,
        "Forever Jundies did not use Retail's plain level number")
    module.config.enemyLevelSize = 20
    module:Refresh()
    assert(label.textHeight == 20 and label.width == 40 and target.offsetX == targetX - 44,
        "selected Jundies level size did not reach Forever runtime and arrow gap")
    module.config.enemyLevelSize = 0
    module:Refresh()
    local originalEffectiveLevel = UnitEffectiveLevel
    UnitEffectiveLevel = function() return 13 end
    module:Refresh()
    assert(label.text == 13, "Forever Jundies ignored Blizzard's effective unit level")
    UnitEffectiveLevel = originalEffectiveLevel
    module.config.enemyLevelEnabled = false
    module:Refresh()
    assert(uf.PlayerLevelDiffFrame:GetAlpha() == 0 and not label:IsShown(),
        "Forever level switch did not hide the native badge")
    module.config.enemyLevelEnabled = true
    module.config.levelAppearance = 2
    module:Refresh()
    assert(uf.PlayerLevelDiffFrame:GetAlpha() == 1 and not label:IsShown()
        and uf.PlayerLevelDiffFrame.offsetX == 6 and target.offsetX == targetX
        and target.mirror.offsetX == -targetX + 33,
        "Forever Blizzard badge option did not restore Camelot's level layout")
    NamePlateSetupOptions.useClassicHealthBar = true
    module:Refresh()
    assert(uf.PlayerLevelDiffFrame:GetAlpha() == 1 and uf.LevelFrame:GetAlpha() == 0
        and uf.PlayerLevelDiffFrame.offsetX == 6,
        "Forever Classic style duplicated Camelot's badge with the legacy level frame")
    NamePlateSetupOptions.useClassicHealthBar = false
    module:Refresh()
    module.config.look = 2
    module:Refresh()
    assert(uf.PlayerLevelDiffFrame:GetAlpha() == 1 and uf.LevelFrame:GetAlpha() == 1,
        "Blizzard look did not restore both native level frames")
    module.config.look = 1
    module:Refresh()
    uf.PlayerLevelDiffFrame:Hide()
    module:Refresh()
    assert(not label:IsShown() and uf.PlayerLevelDiffFrame.offsetX == 6
        and target.mirror.offsetX == -targetX + 33,
        "Forever drew a second level while Camelot's native badge was temporarily hidden")
    uf.showOnlyName = true
    NamesOnlyUnit(true)
    module:Refresh()
    assert(not label:IsShown() and target.mirror.offsetX == -targetX,
        "Forever names-only plate gained a custom level or reserved an empty badge")
    uf.showOnlyName = false
    NamesOnlyUnit(false)
    NamePlateSetupOptions.unitNameAnchorStyle = 2
    NamePlateSetupOptions.nameJustificationWhenAboveHealthBar = "CENTER"
    module.config.enemyHealthTextOffsetX = 10
    name:ClearAllPoints()
    name:SetPoint("BOTTOMLEFT", nativeAnchor, "TOPLEFT", 0, 2)
    name:SetPoint("RIGHT", uf.PlayerLevelDiffFrame, "RIGHT", 0, 0)
    module:Refresh()
    assert(name.points[2][2] == uf.PlayerLevelDiffFrame,
        "Forever preview offsets replaced Camelot's future level-frame name anchor")
    NamePlateSetupOptions.unitNameAnchorStyle = 1
    NamePlateSetupOptions.nameJustificationWhenAboveHealthBar = nil
    module.config.enemyHealthTextOffsetX = 0
    targetUnit = nil
    module.config.enemyLevelEnabled = false
    module.config.enemyLevelOffsetX = 0
    module.config.levelAppearance = 1
    NS.Client.isForever = false
    module:Refresh()
end

do
    module.active = true
    uf.isFriend, uf.isPlayer = false, false
    module.config.look, module.config.enemy, module.config.enemyRoleColors = 1, true, true
    classification, isBoss, tappedUnit, questUnit, focusUnit = "elite", false, false, false, nil
    module:Refresh()
    local reads = 0
    local nativeClassification, nativeBoss, nativeLevel = UnitClassification, UnitIsBossMob, UnitLevel
    UnitClassification = function(unit) reads = reads + 1; return nativeClassification(unit) end
    UnitIsBossMob = function(unit) reads = reads + 1; return nativeBoss(unit) end
    UnitLevel = function(unit)
        if unit ~= "player" then reads = reads + 1 end
        return nativeLevel(unit)
    end
    local fontReads = name.fontReads
    for _ = 1, 3 do
        events.UNIT_THREAT_LIST_UPDATE(module, "UNIT_THREAT_LIST_UPDATE", "nameplate1")
        events.UNIT_THREAT_SITUATION_UPDATE(module, "UNIT_THREAT_SITUATION_UPDATE", "nameplate1")
    end
    assert(reads == 0, "threat events re-read classification, boss or level facts")
    events.UNIT_FLAGS(module, "UNIT_FLAGS", "nameplate1")
    assert(reads == 0 and name.fontReads == fontReads, "a unit flag event re-classified or repainted the plate")
    tappedUnit = true
    events.UNIT_FLAGS(module, "UNIT_FLAGS", "nameplate1")
    assert(module.roles[bar] == "Tapped" and reads == 0, "a flag change did not reach the cached role")
    tappedUnit = false
    events.UNIT_FLAGS(module, "UNIT_FLAGS", "nameplate1")
    assert(module.roles[bar] ~= "Tapped", "an untapped unit kept its tapped color")
    events.UNIT_CLASSIFICATION_CHANGED(module, "UNIT_CLASSIFICATION_CHANGED", "nameplate1")
    assert(reads > 0, "a classification change kept stale unit facts")
    reads = 0
    events.ZONE_CHANGED(module, "ZONE_CHANGED")
    assert(reads == 0 and name.fontReads == fontReads, "an unchanged subzone context re-classified the plates")
    instanceType = "party"
    events.ZONE_CHANGED(module, "ZONE_CHANGED")
    assert(reads > 0, "a subzone step into an instance kept the outdoor plate facts")
    instanceType = "none"
    events.ZONE_CHANGED_NEW_AREA(module, "ZONE_CHANGED_NEW_AREA")
    UnitClassification, UnitIsBossMob, UnitLevel = nativeClassification, nativeBoss, nativeLevel
    classification = "normal"
    module:Refresh()
end

-- Personal mana and alternate power remain Blizzard StatusBars. Skin only
-- their static border and offset, then reapply after native anchoring.
do
    local mana, alternate = Region(), Region()
    local nativeMana = Region()
    nativeMana:SetTexture("native-mana")
    function mana:GetStatusBarTexture() return nativeMana end
    function alternate:GetStatusBarTexture() return Region() end
    NamePlateDriverFrame = {
        GetClassNameplateManaBar = function() return mana end,
        GetClassNameplateAlternatePowerBar = function() return alternate end,
        SetupClassNameplateBars = function() end,
    }
    local c = module.config
    c.personalPowerSkin, c.personalPowerBorderSize = true, 1
    c.personalPowerBorderColor = "000000"
    c.personalPowerOffsetX, c.personalPowerOffsetY = 12, -3
    private.Power.Enable(module)
    assert(powerHook and mana.created == 4 and alternate.created == 4
        and mana.offsetX == 12 and mana.offsetY == -3 and alternate.offsetX == nil
        and nativeMana.texture == "native-mana",
        "personal bars were not skinned without replacing native fill")
    mana:Hide()
    private.Power.Refresh(true)
    assert(alternate.offsetX == 12 and alternate.offsetY == -3,
        "alternate power did not move when Blizzard attached it directly to health")
    mana:Show()
    private.Power.Refresh(true)
    assert(alternate.offsetX == 0 and alternate.offsetY == 0,
        "alternate power retained a second offset when attached to mana")
    local created = mana.created
    powerHook()
    assert(mana.created == created and mana.offsetX == 12, "native power reanchor created duplicate skin")
    c.personalPowerSkin, c.personalPowerOffsetX, c.personalPowerOffsetY = false, 0, 0
    private.Power.Refresh()
    assert(mana.offsetX == 0 and mana.offsetY == 0 and not mana.textures[1]:IsShown()
        and nativeMana.texture == "native-mana", "personal power state was not restored")
end
do
    module.config.look, module.config.enemy, module.config.enemyCastTimeEnabled = 1, true, true
    uf.isFriend = false
    module.active = true
    module:Refresh()
    local state = assert(module.castTimes[cast], "duration text binding was not created")
    local label = state.label
    assert(cast.CastTimeText == nil and label.parent == cast and not label:IsShown(),
        "Suite tainted Blizzard's native CastTimeText field")
    -- The duration object is opaque: only the engine binding reads it. A
    -- secret result ("secret") never reaches the binding from addon code.
    local opaqueCast = setmetatable({}, { __sub = function() error("secret cast arithmetic") end })
    castDuration = opaqueCast
    events.UNIT_SPELLCAST_START(module, "UNIT_SPELLCAST_START", "nameplate1")
    assert(state.binding.duration == castDuration and state.binding.enabled and label:IsShown()
        and label.text == "2.3s" and cast.CastTimeText == nil,
        "cast duration did not reach the engine text binding")
    castDuration = "secret"
    events.UNIT_SPELLCAST_NOT_INTERRUPTIBLE(module, "UNIT_SPELLCAST_NOT_INTERRUPTIBLE", "nameplate1")
    assert(state.binding.duration == opaqueCast and state.binding.enabled and label:IsShown(),
        "interruptibility change hid a valid cast time while duration was unavailable")
    castDuration = opaqueCast
    events.UNIT_SPELLCAST_STOP(module, "UNIT_SPELLCAST_STOP", "nameplate1")
    assert(not state.binding.enabled and not label:IsShown(), "cast stop left a stale time")
    castDuration = "secret"
    events.UNIT_SPELLCAST_START(module, "UNIT_SPELLCAST_START", "nameplate1")
    assert(not state.binding.enabled and not label:IsShown() and cast.CastTimeText == nil,
        "secret duration reactivated the unsafe timer")
    castDuration = opaqueCast
    events.UNIT_SPELLCAST_NOT_INTERRUPTIBLE(module, "UNIT_SPELLCAST_NOT_INTERRUPTIBLE", "nameplate1")
    assert(state.binding.duration == castDuration and state.binding.enabled and label:IsShown(),
        "a non-interruptible cast did not recover its duration after cast start")
    events.UNIT_SPELLCAST_STOP(module, "UNIT_SPELLCAST_STOP", "nameplate1")
    castDuration = nil
    channelDuration = setmetatable({}, { __sub = function() error("secret channel arithmetic") end })
    events.UNIT_SPELLCAST_CHANNEL_START(module, "UNIT_SPELLCAST_CHANNEL_START", "nameplate1")
    assert(state.binding.duration == channelDuration and label:IsShown(), "channel duration was not bound")
    events.UNIT_SPELLCAST_NOT_INTERRUPTIBLE(module, "UNIT_SPELLCAST_NOT_INTERRUPTIBLE", "nameplate1")
    assert(state.binding.duration == channelDuration and state.binding.enabled and label:IsShown(),
        "a non-interruptible channel lost its duration text")
    module.config.enemyCastTimeEnabled = false
    module:Refresh()
    assert(cast.CastTimeText == nil and not label:IsShown() and not state.binding.enabled,
        "cast time toggle did not disable the binding")
    module.config.enemyCastTimeEnabled = true
    module:Refresh()
    assert(module.castTimes[cast] == state, "pooled cast created another duration binding")
    module.config.look = 2
    module:Refresh()
    assert(cast.CastTimeText == nil and not label:IsShown(), "Blizzard look retained Suite's time region")
    module.config.look = 1
    module:Refresh()
    assert(module.castTimes[cast] == state, "returning from Blizzard look created another binding")
end
module:Disable()
assert(cast.CastTimeText == nil and not module.castTimes[cast].binding.enabled,
    "disabled Suite left its cast duration binding active")
local disabledFontReads = name.fontReads
fontHook(uf)
assert(name.fontReads == disabledFontReads, "disabled nameplate hook still inspected plate fonts")
print("Suite nameplates: native lifecycle, cast customization, masks, friendly features, layout and restoration passed")

-- Keybinding is a manual Suite setting change, with no work in combat/off.
do
    NS.Text = function(value) return value end
    NS.ActionBarTitles = {}
    for bar = 1, 12 do NS.ActionBarTitles[bar] = "Action bar " .. bar end
    local writes = 0
    S.Config = function(id) assert(id == "nameplates"); return module.config end
    S.Set = function(id, key, value)
        assert(id == "nameplates" and key == "friendlyNPCs")
        writes = writes + 1
        module.config[key] = value
        return true
    end
    assert(loadfile(root .. "/MSUF_Suite/Core/Bindings.lua"))("MSUF_Suite", NS)
    module.config.enabled = true
    liveCVars.nameplateShowFriendlyNpcs = "0"
    assert(NS.ToggleFriendlyNPCNameplates() and module.config.friendlyNPCs == 2)
    liveCVars.nameplateShowFriendlyNpcs = "1"
    assert(NS.ToggleFriendlyNPCNameplates() and module.config.friendlyNPCs == 3)
    combat = true
    assert(not NS.ToggleFriendlyNPCNameplates())
    combat, module.config.enabled = false, false
    assert(not NS.ToggleFriendlyNPCNameplates())
    module.config.enabled, liveCVars.nameplateShowFriendlyNpcs = true, "secret"
    assert(not NS.ToggleFriendlyNPCNameplates() and writes == 2)
end

-- Nameplate looks: the mouseover highlight, which repaints only the plate that
-- lost the mouse and the one that gained it (Mouseover.lua); the level
-- difficulty color (Level.lua); the friendly castbar sizes and time format
-- (Geometry.lua, CastTime.lua); the friendly health text outline (Skin.lua
-- PaintFonts); the threshold line width; the position resets of Blizzard
-- auras and the soft target (Pages/Nameplates.lua); and the module conflicts.
-- Every default keeps today's look: nothing new is made, registered or read.
-- The real Skin.lua runs the plate lifecycle, and a restricted level answer
-- reaches native sinks only (a strict secret Watch). Bar textures and Suite
-- cast colors stay retired (suite_nameplates_parity_contract.lua).
local root = assert(arg[1], "repository root required")
local classic = root .. "/../MidnightSimpleUnitFrames/MidnightSimpleUnitFrames"
local support = dofile(root .. "/tools/tests/suite_test_support.lua")

------------------------------------------------------------------ secrets
local Secrets = assert(loadfile(classic .. "/../tools/tests/classpower_secrets.lua"))()
Secrets.Install()
Secrets.GUARD_NAMES.falsy.Public = true
local revealed = setmetatable({}, { __mode = "k" })
local function Secret(value)
    local box = Secrets.New(type(value))
    revealed[box] = value
    return box
end
local function Reveal(value)
    if issecretvalue(value) then return revealed[value] end
    return value
end

------------------------------------------------------------------ regions
local function RGB(hex)
    if type(hex) ~= "string" or #hex ~= 6 then return 1, 1, 1 end
    return tonumber(hex:sub(1, 2), 16) / 255, tonumber(hex:sub(3, 4), 16) / 255, tonumber(hex:sub(5, 6), 16) / 255
end
local function Hex(r, g, b)
    return string.format("%02x%02x%02x", math.floor(r * 255 + .5), math.floor(g * 255 + .5), math.floor(b * 255 + .5))
end

local function NativeBoolean(value)
    assert(type(value) == "boolean" or issecretvalue(value), "a native boolean sink needs a boolean")
end

local function Region(kind, parent)
    local r = { kind = kind, parent = parent, shown = true, points = {}, writes = 0, children = {},
        font = "native-font", size = 10, flags = "" }
    local function Write(self) self.writes = self.writes + 1 end
    function r:Show() Write(self); self.shown = true end
    function r:Hide() Write(self); self.shown = false end
    function r:SetShown(shown) Write(self); self.shown = shown and true or false end
    function r:IsShown() return self.shown end
    function r:ClearAllPoints() Write(self); self.points = {} end
    function r:SetPoint(...) Write(self); self.points[#self.points + 1] = { ... } end
    function r:SetAllPoints(target) Write(self); self.allPoints = target end
    function r:SetSize(width, height) Write(self); self.width, self.height = width, height end
    function r:SetWidth(width) Write(self); self.width = width end
    function r:SetHeight(height) Write(self); self.height = height end
    function r:SetAlpha(alpha) Write(self); self.alpha, self.alphaSecret = alpha, false end
    function r:GetAlpha() return self.alpha or 1 end
    function r:SetAlphaFromBoolean(value, ifTrue, ifFalse)
        NativeBoolean(value)
        Write(self)
        if Reveal(value) then self.alpha = ifTrue else self.alpha = ifFalse end
        self.alphaSecret = issecretvalue(value)
    end
    function r:SetTexture(path) Write(self); self.texture, self.color = path, nil end
    function r:SetColorTexture(red, green, blue, alpha) Write(self); self.color, self.texture = { red, green, blue, alpha }, nil end
    function r:SetVertexColor(red, green, blue, alpha) Write(self); self.vertex = { red, green, blue, alpha } end
    function r:SetVertexColorFromBoolean(value, ifTrue, ifFalse)
        NativeBoolean(value)
        assert(ifTrue and ifFalse, "a native boolean sink needs two colors")
        Write(self)
        if Reveal(value) then self.vertex = ifTrue else self.vertex = ifFalse end
        self.vertexSecret = issecretvalue(value)
    end
    function r:SetBlendMode(mode) Write(self); self.blend = mode end
    function r:SetAtlas(atlas) Write(self); self.atlas = atlas end
    function r:SetScale() end
    function r:SetRotation() end
    function r:EnableMouse() end
    function r:HookScript() end
    function r:IsProtected() return false end
    function r:GetEffectiveScale() return 1 end
    function r:CreateTexture(_, layer, _, sublevel)
        local texture = Region("Texture", self)
        texture.layer, texture.sublevel = layer, sublevel
        self.children[#self.children + 1] = texture
        return texture
    end
    function r:CreateFontString()
        local font = Region("FontString", self)
        self.children[#self.children + 1] = font
        return font
    end
    function r:GetFont() return self.font, self.size, self.flags end
    function r:SetFont(path, size, flags) Write(self); self.font, self.size, self.flags = path, size, flags or "" end
    function r:GetShadowColor() return 0, 0, 0, .6 end
    function r:GetShadowOffset() return 1, -1 end
    function r:SetShadowColor(_, _, _, alpha) self.shadow = alpha end
    function r:SetShadowOffset() end
    function r:SetText(text) Write(self); self.text = text end
    function r:SetTextHeight(height) self.textHeight = height end
    function r:SetJustifyH() end
    function r:SetTextColor(red, green, blue)
        Write(self)
        self.textColor, self.textColorWrites = Hex(red, green, blue), (self.textColorWrites or 0) + 1
    end
    return r
end

local function StatusBar(parent)
    local bar = Region("StatusBar", parent)
    bar.fill = Region("Texture", bar)
    function bar:GetStatusBarTexture() return self.fill end
    function bar:SetStatusBarTexture() end
    function bar:SetMinMaxValues() end
    function bar:SetValue(value) self.value = value end
    return bar
end

local function Child(owner, test)
    for _, child in ipairs(owner.children) do
        if test(child) then return child end
    end
end
local function HighlightOf(health) return Child(health, function(texture) return texture.blend == "ADD" end) end
-- Every write on a health bar and the regions the Suite made on it.
local function Touched(health)
    local count = health.writes + 1000 * #health.children
    for _, child in ipairs(health.children) do count = count + child.writes end
    return count
end

------------------------------------------------------------------ client
local clock = support.Clock(100)
local combat = false
local casts, attackable, difficulty = {}, {}, {}
local difficultyReads, levelValue = 0, 70
local function Duration() return { GetStartTime = function() return 0 end, GetEndTime = function() return 1 end } end
UnitCastingDuration = function(unit) if casts[unit] and casts[unit].kind == "cast" then return Duration() end end
UnitChannelDuration = function(unit) if casts[unit] and casts[unit].kind == "channel" then return Duration() end end
UnitEmpoweredChannelDuration = function() return nil end
UnitCanAttack = function(_, unit)
    local value = attackable[unit]
    if value == nil then return false end
    return value
end
C_PlayerInfo = { GetContentDifficultyCreatureForPlayer = function(unit)
    difficultyReads = difficultyReads + 1
    return difficulty[unit]
end }
local DIFFICULTY = { [0] = { r = .5, g = .5, b = .5 }, [2] = { r = 1, g = .82, b = 0 }, [4] = { r = 1, g = .1, b = .1 } }
GetDifficultyColor = function(value) return DIFFICULTY[value] end
UnitLevel = function() return levelValue end
UnitEffectiveLevel = UnitLevel
UnitIsUnit = function() return false end
UnitClassification = function() return "normal" end
Enum = { SecondsFormatterInterval = { Seconds = 1 }, SecondsFormatterAbbreviation = { OneLetter = 2 },
    DurationTextBindingProperty = { ElapsedDuration = 2, TotalDuration = 4 } }
C_StringUtil = {
    CreateSecondsFormatter = function()
        return { SetMaxInterval = function() end, SetDefaultAbbreviation = function() end,
            SetMillisecondsThreshold = function() end }
    end,
    CreateNumericRuleFormatter = function() return { AddBreakpoint = function() end } end,
}
C_DurationUtil = { CreateDurationTextBinding = function()
    local binding = {}
    function binding:SetFontString(label) self.label = label end
    function binding:SetFormatter(formatter) self.formatter, self.format = formatter, nil end
    function binding:SetTextFormat(format) self.format = format end
    function binding:SetDuration(duration) self.duration = duration end
    function binding:Disable() self.enabled = false end
    function binding:Enable() self.enabled = true end
    binding.SetUpdateInterval, binding.SetZeroDurationText, binding.SetExpiredText = function() end, function() end, function() end
    return binding
end }
NamePlateSetupOptions = { useClassicHealthBar = false, spellNameInsideCastBar = false, levelFontHeight = 10,
    insetWidth = 12, castBarToHealthBarSpacing = 2, healthBarHeight = 10, castBarHeight = 10,
    castIconWidth = 12, castIconHeight = 12, horizontalScale = 1, verticalScale = 1 }
NamePlateConstants = { NAMEPLATE_WIDTH = 230, CLASSIC_NAMEPLATE_WIDTH = 152 }
NamePlateUnitFrameMixin = { ApplyFrameOptions = function() end }
hooksecurefunc = function() end
PixelUtil = { SetPoint = function(region, ...) region:SetPoint(...) end,
    GetNearestPixelSize = function(size) return size end }
local cvars = { nameplateStyle = "0" }
C_CVar = { GetCVar = function(key) return cvars[key] end }
EditModeManagerFrame = { IsEditModeActive = function() return false end }
local plates, mouseover, scans = {}, nil, 0
C_NamePlate = {
    GetNamePlates = function() scans = scans + 1; return plates end,
    GetNamePlateForUnit = function(unit)
        if unit == "mouseover" then return mouseover end
        for _, plate in ipairs(plates) do if plate.unitToken == unit then return plate end end
    end,
}

------------------------------------------------------------------ Suite
local NS = {
    Client = { isForever = false, isMainline = true }, Text = function(value) return value end,
    Public = function(value) return not issecretvalue(value) end, IsSecret = issecretvalue, RGB = RGB,
    Finite = function(value) return not issecretvalue(value) and type(value) == "number" and value == value end,
    IsCombatLocked = function() return combat end, InCombat = function() return combat end,
    Safety = { IsForbidden = function(region) return region.forbidden == true end },
    ResolveFont = function(key) if key ~= "" then return key end end,
    Dispatch = function(callback, ...) return callback(...) end,
    -- MSUF without the interrupt-ready engine: KickReady.lua stays idle.
    HostBridge = { KickReady = function() return nil end },
}
for _, file in ipairs({ "SuiteCatalog", "NameplateStyle", "Catalog/Nameplates" }) do
    assert(loadfile(root .. "/MSUF_Suite/Core/" .. file .. ".lua"))("MSUF_Suite", NS)
end
local spec, Style = NS.SuiteCatalog.nameplates, NS.NameplateStyle
local function Defaults()
    local config = {}
    for key, rule in pairs(spec.rules) do config[key] = rule.default end
    return config
end

------------------------------------------------------------------ catalog
-- Every new setting starts on today's look, in no look preset of its own.
local TODAY = { mouseoverHighlight = false, mouseoverHighlightColor = "ffffff", enemyLevelColor = false,
    enemyThresholdWidth = 1, friendlyCastHeight = 0, friendlyCastIconSize = 0, friendlyCastTimeFormat = 1 }
for key, value in pairs(TODAY) do
    local rule = assert(spec.rules[key], key .. " is missing from the catalog")
    assert(rule.default == value, key .. " does not start on today's look")
    for _, preset in pairs(spec.look.presets) do
        assert(preset[key] == nil or preset[key] == value, "a look preset changes " .. key)
    end
end
assert(spec.rules.friendlyCastHeight.requiresChoice.key == "barGeometry"
    and spec.rules.friendlyCastTimeFormat.enableKey == "friendlyCastTimeEnabled", "friendly cast controls are not gated")
local conflicts = {}
for _, name in ipairs(spec.conflicts) do conflicts[name] = true end
for _, name in ipairs({ "Plater", "Platynator", "ElvUI", "EllesmereUINameplates", "Kui_Nameplates",
    "TidyPlates_ThreatPlates", "TidyPlatesContinued", "BetterBlizzPlates" }) do
    assert(conflicts[name], "nameplate addon missing from the conflicts: " .. name)
end
-- The health threshold line takes its width from the setting (NameplateStyle.lua Threshold).
CreateFrame = function(kind, _, parent)
    if kind == "StatusBar" then return StatusBar(parent) end
    return Region(kind, parent)
end
do
    local config = Defaults()
    config.enemyThresholdEnabled = true
    local state = { parent = Region("Frame"), health = StatusBar() }
    Style.Decor.Paint(state, Style.Decor.Plan(config, "enemy"), false, false, false)
    assert(state.threshold.width == 1, "the threshold line is not 1 px by default")
    config.enemyThresholdWidth = 3
    Style.Decor.Paint(state, Style.Decor.Plan(config, "enemy"), false, false, false)
    assert(state.threshold.width == 3, "the threshold line width setting did not apply")
end

------------------------------------------------------------------ the skin
local module
local S = { Public = NS.Public, Finite = NS.Finite, RGB = RGB,
    SetFont = function(region, path, size, flags) region:SetFont(path, size, flags) end,
    Install = function(_, owner) module = owner end }
NS.Suite = S
local private = { NS = NS, Suite = S }
local function Component(name, methods)
    local component = {}
    for method in methods:gmatch("%S+") do component[method] = function() end end
    private[name] = component
end
local function Load(file) assert(loadfile(root .. "/MSUF_Suite_Nameplates/" .. file .. ".lua"))("MSUF_Suite_Nameplates", private) end
Load("Modes")
Load("Geometry")
Component("Layout", "Bind Configure Apply Restore RestoreAll")
Component("Roles", "Configure Marker Quest Classify Base Get ClearQuest RefreshContext RetryQuests")
Component("Power", "Enable Refresh Reapply Disable")
Component("Threat", "Enable Apply Restore Disable Refresh")
Component("CVars", "Apply")
Component("Auras", "Bind Apply Restore")
Component("Selection", "Apply Restore Configure RestoreAll")
Component("AuraColors", "Bind Configure Apply Restore SetEditMode")
for _, file in ipairs({ "Text", "Level", "CastTime", "KickReady", "Mouseover", "FriendlyNames", "Decor", "Skin" }) do
    Load(file)
end
local stopWatch = Secrets.Watch(root .. "/MSUF_Suite_Nameplates/Level.lua", { strict = true })

local events = {}
module.context = support.ModuleTimers(root, S, NS)("nameplates", module, {
    Event = function(_, event, callback, options)
        assert(support.InCombatOption(options), event .. " would wait for the end of combat")
        events[event] = callback
    end,
    RemoveEvent = function(_, event) events[event] = nil end,
    Callback = function() end,
})
local function Fire(event, unit) events[event](module, event, unit) end

local function Plate(unit, friendly)
    local uf = Region("Button")
    uf.isFriend, uf.isPlayer = friendly, false
    uf.name = Region("FontString", uf)
    local health, cast = StatusBar(uf), StatusBar(uf)
    health.Text, health.LeftText, health.RightText = Region("FontString"), Region("FontString"), Region("FontString")
    cast.Text, cast.CastTargetNameText, cast.Icon = Region("FontString"), Region("FontString"), Region("Texture")
    uf.HealthBarsContainer, uf.CastBarsContainer = Region("Frame", uf), Region("Frame", uf)
    uf.HealthBarsContainer.healthBar, uf.CastBarsContainer.castBar = health, cast
    return { UnitFrame = uf, unitToken = unit }, uf, health, cast
end
local plateA, ufA, healthA, castA = Plate("nameplate1", false)
local plateB, _, healthB, castB = Plate("nameplate2", false)
local plateC, _, healthC = Plate("nameplate3", false)
local plateF, ufF, healthF, castF = Plate("nameplate4", true)
plates[1], plates[2], plates[3], plates[4] = plateA, plateB, plateC, plateF
local c = Defaults()
module.config, module.active = c, true
module:Enable()

------------------------------------------------------------------ defaults keep today's look
for _, cast in ipairs({ castA, castB, castF }) do
    assert(not Child(cast, function(region) return region.kind == "Texture" end), "a default plate decorated Blizzard's castbar")
end
for _, health in ipairs({ healthA, healthB, healthC, healthF }) do
    assert(not Child(health, function(texture) return texture.blend ~= nil end), "a default plate got a bar texture or highlight")
end
local back = module.visuals[healthA].back
assert(back.color and back.texture == nil, "the default backdrop is not flat")
assert(events.UPDATE_MOUSEOVER_UNIT == nil, "the mouseover event listens while the highlight is off")
assert(difficultyReads == 0, "a default plate read level details")

------------------------------------------------------------------ the friendly health text outline
local friendlyStyle = private.Text.styles.friendly
assert(healthF.Text.font == friendlyStyle.font and healthF.Text.flags == friendlyStyle.flags
    and healthF.LeftText.flags == friendlyStyle.flags and healthF.RightText.font == friendlyStyle.font,
    "friendly health text does not follow Name and health text outline")
assert(healthF.Text.size == 10 and healthA.Text.size == c.enemyHealthTextSize,
    "friendly health text took a size, or enemy health text lost its own")

------------------------------------------------------------------ mouseover highlight
c.mouseoverHighlight = true
module:Refresh()
assert(events.UPDATE_MOUSEOVER_UNIT, "the highlight did not listen to the mouseover")
local function Hover(plate)
    mouseover = plate
    local scansBefore = scans
    Fire("UPDATE_MOUSEOVER_UNIT")
    assert(scans == scansBefore, "the mouseover scanned every plate")
end
Hover(plateA)
local highlightA = HighlightOf(healthA)
assert(highlightA and highlightA.shown and highlightA.allPoints == healthA and highlightA.color[4] == .25,
    "the plate under the mouse is not highlighted")
assert(not HighlightOf(healthB) and not HighlightOf(healthC), "a plate away from the mouse got a highlight")
local quiet = Touched(healthC) + Touched(healthF)
Hover(plateB)
assert(not highlightA.shown and HighlightOf(healthB).shown, "the highlight did not move with the mouse")
assert(Touched(healthC) + Touched(healthF) == quiet, "the mouseover repainted a plate it never touched")
Hover(nil)
assert(not HighlightOf(healthB).shown, "the highlight stayed after the mouse left")
c.friendly = false
module:Refresh()
Hover(plateF)
assert(not HighlightOf(healthF), "a plate the skin leaves alone got a highlight")
c.friendly, c.mouseoverHighlightColor = true, "ff0000"
module:Refresh()
Hover(plateA)
assert(highlightA.shown and highlightA.color[1] == 1 and highlightA.color[2] == 0, "the highlight color did not apply")
Fire("NAME_PLATE_UNIT_REMOVED", "nameplate1")
assert(not highlightA.shown, "a removed plate kept its highlight")
module:Refresh()
c.mouseoverHighlight = false
module:Refresh()
assert(events.UPDATE_MOUSEOVER_UNIT == nil and not highlightA.shown, "the highlight stayed registered or shown when off")

------------------------------------------------------------------ level color
c.enemyLevelEnabled, c.friendlyLevelEnabled = true, true
attackable.nameplate1, difficulty.nameplate1 = true, 2
module:Refresh()
local label = module.levelLabels[ufA]
assert(label and label.shown and label.textColor == "ffffff" and difficultyReads == 0, "the level color is not off by default")
c.enemyLevelColor = true
module:Refresh()
assert(label.textColor == Hex(1, .82, 0), "the level number lost its difficulty color")
difficulty.nameplate1 = 4
Fire("UNIT_LEVEL", "nameplate1")
assert(label.textColor == Hex(1, .1, .1), "UNIT_LEVEL did not recolor the level")
local colorWrites = label.textColorWrites
Fire("UNIT_LEVEL", "nameplate1")
assert(label.textColorWrites == colorWrites, "an unchanged difficulty rewrote the level color")
for _, case in ipairs({ { false, 4 }, { Secret(true), 4 }, { true, Secret(4) } }) do
    attackable.nameplate1, difficulty.nameplate1 = case[1], case[2]
    Fire("UNIT_LEVEL", "nameplate1")
    assert(label.textColor == "ffffff", "a unit the player cannot attack, or a restricted answer, is not white")
end
attackable.nameplate1, difficulty.nameplate1, levelValue = true, 0, Secret(70)
Fire("UNIT_LEVEL", "nameplate1")
assert(issecretvalue(label.text) and label.textColor == Hex(.5, .5, .5), "a restricted level lost its number or color")
levelValue, attackable.nameplate4, difficulty.nameplate4 = 70, true, 4
module:Refresh()
assert(module.levelLabels[ufF].textColor == "ffffff", "a friendly level took a difficulty color")
c.enemyLevelEnabled, c.friendlyLevelEnabled, c.enemyLevelColor = false, false, false

------------------------------------------------------------------ friendly castbars
casts.nameplate4 = { kind = "cast", locked = false, spellID = 300 }
c.friendlyCastTimeFormat = 2
module:Refresh()
local times = module.castTimes[castF]
assert(times and times.binding.format == "{}/{}", "the friendly cast time format was ignored")
c.friendlyCastTimeFormat = 1
module:Refresh()
assert(times.binding.format == nil and times.binding.formatter, "the friendly cast time did not return to remaining time")
do
    local _, uf, _, cast = Plate("nameplate9", true)
    local config = Defaults()
    config.barGeometry, config.friendlyCastHeight, config.friendlyCastIconSize, config.enemyCastHeight = 2, 28, 40, 30
    local state = {}
    assert(private.Geometry.Apply(state, uf, NamePlateSetupOptions, config, true, "friendly"))
    assert(cast.height == 28 and cast.Icon.width == 40 and cast.Icon.height == 40, "friendly cast dimensions were ignored")
    config.friendlyCastHeight, config.friendlyCastIconSize = 0, 0
    private.Geometry.Apply(state, uf, NamePlateSetupOptions, config, false, "friendly")
    assert(cast.height == 10 and cast.Icon.width == 12, "the automatic friendly cast dimensions changed")
end

local violations = stopWatch()
assert(#violations == 0, "a level read compares or tests a secret:\n" .. table.concat(violations, "\n"))

------------------------------------------------------------------ position resets
-- The Blizzard auras and soft target handles' offsets sit in the enemy and
-- friendly catalog sections; their own sections' resets restore them.
local P = { Gates = {}, SearchPreparers = {}, catalog = { nameplates = spec }, Suite = { NameplateStyle = Style, HostBridge = {} } }
P.Tr = function(text) return text end
P.Help = function(summary, details) return { summary = summary, details = details } end
P.HM = { GetSectionEntry = function() return nil end, SetSectionEnsureVisible = function() end }
P.W, P.M, P.T = { PageBuilder = function() return {} end }, {}, {}
P.S = { Config = function() return {} end }
P.Suite.RGB, P.Suite.Registry = RGB, { AddListener = function() end }
P.BuildNameplatesPreview, P.BuildNameplatesAuraColors = function() end, function() end
local page
P.RegisterPage = function(registered) page = registered end
assert(loadfile(root .. "/MSUF_Suite_Options/Menu/Controls.lua"))("MSUF_Suite_Options", P)
P.ModuleCard = function() end
local resets = {}
P.RuleSection = function(_, _, _, _, sectionId, _, _, opts) resets[sectionId] = opts.resetKeys; return {} end
assert(loadfile(root .. "/MSUF_Suite_Options/Pages/NameplatesWorkspace.lua"))("MSUF_Suite_Options", P)
assert(loadfile(root .. "/MSUF_Suite_Options/Pages/Nameplates.lua"))("MSUF_Suite_Options", P)
page.build({})
local function Lists(keys, key)
    for _, listed in ipairs(keys or {}) do if listed == key then return true end end
end
local auras, signals = resets.suite_nameplates_auras, resets.suite_nameplates_signals
for _, side in ipairs({ "enemy", "friendly" }) do
    for _, axis in ipairs({ "X", "Y" }) do
        for _, element in ipairs({ "Auras", "Buffs", "ControlAura" }) do
            local key = side .. element .. "Offset" .. axis
            assert(spec.rules[key] and Lists(auras, key), "the Blizzard auras reset keeps " .. key)
        end
        assert(Lists(signals, side .. "SoftTargetOffset" .. axis), "the Blizzard indicators reset keeps the soft target")
    end
end
local written
P.S.ResetKeys = function(_, values) written = values; return true end
P.Combat, P.Get = function() return false end, function(_, key) if key == "look" then return 4 end end
P.WithHistory, P.Refresh = function(_, _, fn) return fn() end, function() end
assert(P.ResetRules("nameplates", {}, nil, auras), "the Blizzard auras reset wrote nothing")
assert(written.enemyAurasOffsetX == spec.look.presets[4].enemyAurasOffsetX and written.friendlyBuffsOffsetY == 0
    and written.enemyControlAuraOffsetY == spec.look.presets[4].enemyControlAuraOffsetY,
    "the Blizzard auras reset did not restore the dragged aura positions")

print("Suite nameplate looks: mouseover, level color, friendly castbars and health text, threshold width,"
    .. " position resets and conflicts passed")

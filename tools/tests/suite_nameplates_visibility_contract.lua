-- Nameplates: Blizzard visibility options (CVars.lua Flags / Visibility),
-- CVar writes held back for combat, the target / focus border and non-target
-- dimming (Selection.lua), the catalog's greying dependencies, the area
-- header and Quick Setup (Options NameplatesWorkspace.lua) and a section
-- reset under a preset look (Options Menu/Controls.lua P.ResetRules).
local root = assert(arg[1])

------------------------------------------------------------------ catalog
local NS = { Client = { isForever = false, isMainline = true }, Text = function(value) return value end }
NS.Public = function(value) return value ~= "secret" end
NS.Finite = function(value) return type(value) == "number" and value == value end
NS.RGB = function(hex)
    return tonumber(hex:sub(1, 2), 16) / 255, tonumber(hex:sub(3, 4), 16) / 255, tonumber(hex:sub(5, 6), 16) / 255
end
NS.Safety = { IsForbidden = function(frame) return frame.forbidden == true end }
local combat = false
NS.InCombat = function() return combat end
NS.IsCombatLocked = NS.InCombat
local live = {}
C_CVar = { GetCVar = function(key) return live[key] end }
assert(loadfile(root .. "/MSUF_Suite/Core/SuiteCatalog.lua"))("MSUF_Suite", NS)
assert(loadfile(root .. "/MSUF_Suite/Core/NameplateStyle.lua"))("MSUF_Suite", NS)
assert(loadfile(root .. "/MSUF_Suite/Core/NameplateExtensions.lua"))("MSUF_Suite", NS)
assert(loadfile(root .. "/MSUF_Suite/Core/Catalog/Nameplates.lua"))("MSUF_Suite", NS)
local spec = NS.SuiteCatalog.nameplates
local rules = spec.rules

-- Every dependency names a rule; chains end within P.RuleEnabled's four steps.
local gated = 0
for key, rule in pairs(rules) do
    local current, steps = rule, 0
    while current.enableKey do
        assert(rules[current.enableKey], key .. " depends on a missing rule " .. current.enableKey)
        current, steps = rules[current.enableKey], steps + 1
        assert(steps <= 4, key .. " has an enable chain longer than four")
    end
    if rule.requiresChoice then
        local choice = rules[rule.requiresChoice.key]
        assert(choice and choice.choices, key .. " requires a choice that does not exist")
        for value in pairs(rule.requiresChoice.values) do
            assert(choice.choices[value], key .. " requires a value its choice does not offer")
        end
    end
    if rule.enableKey or rule.requiresChoice then gated = gated + 1 end
end
assert(gated >= 60, "inert nameplate controls lost their dependencies (" .. gated .. ")")
for _, key in ipairs({ "plateShowAll", "plateStackEnemy", "plateSimpleFriendlyNpc", "plateOffscreen" }) do
    assert(rules[key].section == "visibility" and rules[key].default == 1, key .. " must keep Blizzard's value by default")
    assert(not spec.look.visualKeys[key], key .. " is a Blizzard option, not part of a look")
end
assert(not rules.personalResource and not spec.cvars.nameplateShowSelf)
for _, key in ipairs({ "selectionBorder", "selectionDim", "selectionDimPercent", "selectionTargetColor" }) do
    assert(rules[key].section == "signals" and spec.look.visualKeys[key], key .. " must belong to the looks")
end
for _, cvar in ipairs({ "nameplateShowAll", "nameplateShowEnemyMinions", "nameplateShowEnemyMinus",
    "nameplateShowFriendlyPlayerMinions", "nameplateShowOffscreen", "nameplateStackingTypes" }) do
    assert(spec.cvars[cvar], cvar .. " is written without being declared (Runtime.lua OwnsCVar)")
end
assert(rules.enemyOtherTankEnabled.enableKey == "enemyTankMode" and rules.enemyOtherTankColor.enableKey == "enemyOtherTankEnabled",
    "the other-tank color must follow tank mode")

local function Config(overrides)
    local config = {}
    for key, rule in pairs(rules) do config[key] = rule.default end
    for key, value in pairs(overrides or {}) do config[key] = value end
    return config
end

------------------------------------------------------------------ CVars
local writes, restored = {}, {}
local S = { RestoreCVar = function(_, key) restored[key] = true end, ForgetCVar = function() end }
NS.Suite = S
NS.ActionBarTitles = {}
for bar = 1, 12 do NS.ActionBarTitles[bar] = "Action bar " .. bar end
assert(loadfile(root .. "/MSUF_Suite/Core/Bindings.lua"))("MSUF_Suite", NS)
local private = { NS = NS, Suite = S, Roles = {} }
assert(loadfile(root .. "/MSUF_Suite_Nameplates/Modes.lua"))("MSUF_Suite_Nameplates", private)
assert(loadfile(root .. "/MSUF_Suite_Nameplates/CVars.lua"))("MSUF_Suite_Nameplates", private)
local CVars = private.CVars
local module = { context = { CVar = function(_, key, value) writes[key], live[key] = value, value end } }
local function Apply(overrides)
    for key in pairs(writes) do writes[key] = nil end
    for key in pairs(restored) do restored[key] = nil end
    module.config = Config(overrides)
    CVars.Apply(module)
end
-- Blizzard drops the data byte of an empty mask (CvarUtil SetCVarBitfieldMask).
local function Flags(value) return (value:byte(2) or 64) - 64 end
local KEEP_TEXT = { enemyTextMode = 1, enemyRarityIcon = 1, friendlyNamesOnly = 1 }
local function Reset()
    for key in pairs(live) do live[key] = nil end
    live.nameplateStackingTypes = string.char(1, 64 + 2)    -- friendly plates stack
    live.nameplateSimplifiedTypes = string.char(1, 64 + 15) -- every type simplified
    live.nameplateInfoDisplay, live.nameplateCastBarDisplay = string.char(1, 64 + 3), string.char(1, 64)
    live.nameplateThreatDisplay = string.char(1, 64 + 3)
    for _, group in ipairs(NS.NameplateStyle.AuraGroups) do live[group.cvar] = string.char(1, 64 + 7) end
    module.flagsBefore = nil
end

Reset()
Apply(KEEP_TEXT)
assert(restored.nameplateStackingTypes and restored.nameplateSimplifiedTypes and restored.nameplateShowAll
    and not writes.nameplateStackingTypes and not writes.nameplateShowOffscreen,
    "Keep Blizzard setting changed a visibility CVar")

local merged = { plateStackEnemy = 2 }
for key, value in pairs(KEEP_TEXT) do merged[key] = value end
Apply(merged)
assert(Flags(writes.nameplateStackingTypes) == 3, "stack enemy plates lost the kept friendly flag")
merged.plateStackEnemy, merged.plateStackFriendly = 1, 3
Apply(merged)
assert(Flags(writes.nameplateStackingTypes) == 0, "overlap friendly plates kept their flag")
merged.plateStackFriendly = 1
Apply(merged)
assert(restored.nameplateStackingTypes and module.flagsBefore.nameplateStackingTypes == nil,
    "all stacking choices on Keep must give Blizzard's value back")

-- Forced enemy names need full minion and minor plates; friendly types keep
-- theirs, and an explicit choice wins over the forced one.
Reset()
Apply({ enemyTextMode = 4, friendlyNamesOnly = 1 })
assert(Flags(writes.nameplateSimplifiedTypes) == 12, "forced names kept simplified enemy minion or minor plates")
Apply({ enemyTextMode = 4, friendlyNamesOnly = 1, plateSimpleMinion = 2, plateSimpleFriendlyNpc = 3 })
assert(Flags(writes.nameplateSimplifiedTypes) == 5, "explicit simplified choices lost against the forced names")

-- Full native plates keep the name visible when it is the only remaining
-- element. A neutral or friendly NPC may use either native friendly template.
local function CheckNameDisplay(overrides, expected)
    Reset()
    local options = Config(KEEP_TEXT)
    for key, value in pairs(overrides) do options[key] = value end
    live.nameplateSimplifiedTypes = string.char(2, 64 + 31, 65)
    Apply(options)
    if expected == nil then
        assert(restored.nameplateForceShowUnitName and restored.nameplateSimplifiedTypes
            and not writes.nameplateForceShowUnitName and not writes.nameplateSimplifiedTypes,
            "an inactive Name only setting retained a native display override")
    else
        assert(writes.nameplateForceShowUnitName == "1", "Name only left the native name conditional")
        assert(writes.nameplateSimplifiedTypes == string.char(2, 64 + 16 + expected, 65),
            "Name only changed the wrong simplification flags or lost unknown bits")
        Apply(KEEP_TEXT)
        assert(restored.nameplateForceShowUnitName and restored.nameplateSimplifiedTypes,
            "leaving Name only kept the visibility override")
    end
end
CheckNameDisplay({ friendlyNamesOnly = 2 }, 11)
CheckNameDisplay({ friendlyNamesOnly = 3 }, 11)
CheckNameDisplay({ enemyPlateNameOnly = true }, 12)
CheckNameDisplay({ friendlyNPCs = 5 }, 0)
CheckNameDisplay({ neutralPlateNameOnly = true, neutralNameOnlyMode = 2 }, 0)
CheckNameDisplay({ neutralPlateNameOnly = true, neutralNameOnlyMode = 3 }, 0)
CheckNameDisplay({ neutralPlateNameOnly = true, plateSimpleFriendlyPlayer = 2, plateSimpleMinus = 2 }, 6)
CheckNameDisplay({ friendlyNamesOnly = 2, friendlySkinEnabled = false })
CheckNameDisplay({ friendlyNPCs = 5, friendlyNpcSkinEnabled = false })
CheckNameDisplay({ neutralPlateNameOnly = true, neutralSkinEnabled = false })
CheckNameDisplay({ enemyPlateNameOnly = true, enemySkinEnabled = false })
CheckNameDisplay({ enemyTextMode = 4, enemySkinEnabled = false, neutralSkinEnabled = false })
CheckNameDisplay({ friendlyNamesOnly = 4, friendlyNPCs = 4 })

-- On reload the stored CVar may already contain the former profile's full
-- plate mask. Keep takes untouched categories from native recovery.
Reset()
live.nameplateSimplifiedTypes = string.char(2)
S.CVarBaseline = function(_, key, current)
    if key == "nameplateSimplifiedTypes" then return string.char(2, 79) end
    return current
end
Apply({ enemyTextMode = 1, friendlyNamesOnly = 2 })
assert(Flags(writes.nameplateSimplifiedTypes) == 11, "reload discarded native simplification for unrelated types")
S.CVarBaseline = nil

Reset()
Apply({ plateShowAll = 2, plateOffscreen = 3, plateEnemyMinus = 2, enemyTextMode = 1, enemyRarityIcon = 1 })
assert(writes.nameplateShowAll == "1" and writes.nameplateShowOffscreen == "0" and writes.nameplateShowEnemyMinus == "1",
    "visibility toggles did not write Blizzard's on/off values")

-- Combat: nothing is written until it ends (Skin.lua OnCombatEnded).
Reset()
combat = true
Apply({ plateShowAll = 2 })
assert(next(writes) == nil and next(restored) == nil and module.cvarsPending, "a CVar was written in combat")
combat = false
CVars.Apply(module)
assert(writes.nameplateShowAll == "1" and not module.cvarsPending, "the held-back CVars were not applied after combat")

if arg[2] == "cvars" then
    print("Suite nameplates: visibility CVars, Name only modes, bitfield recovery and combat deferral passed")
    return
end

------------------------------------------------------------------ Selection
local hooks = {}
NAMEPLATE_BORDER_TARGET_COLOR = { r = 1, g = 1, b = 1 }
NAMEPLATE_BORDER_FOCUS_TARGET_COLOR = { r = 1, g = 0.5, b = 0 }
local function Texture()
    local t = { alpha = 1, writes = 0 }
    function t:CanBeAccessedInContext() return true end
    function t:SetAlpha(alpha) self.alpha, self.writes = alpha, self.writes + 1 end
    function t:GetAlpha() return self.alpha end
    function t:SetShown(shown) self.shown = shown end
    function t:Show() self.shown = true end
    function t:Hide() self.shown = false end
    function t:SetWidth(width) self.width = width end
    function t:SetHeight(height) self.height = height end
    function t:SetTexture(texture) self.texture = texture end
    function t:SetAtlas(atlas) self.atlas = atlas end
    function t:ClearAllPoints() self.points = {} end
    function t:SetPoint(...) self.points[#self.points + 1] = { ... } end
    function t:SetDrawLayer(layer, sublayer) self.layer, self.sublayer = layer, sublayer end
    function t:SetSize(width, height) self.width, self.height = width, height end
    function t:SetTexCoord() end
    function t:SetVertexColor(r, g, b) self.color, self.writes = { r, g, b }, self.writes + 1 end
    t.SetColorTexture = t.SetVertexColor
    function t:SetVertexOffset(index, x, y)
        self.vertices = self.vertices or {}
        self.vertices[index] = { x, y }
    end
    return t
end
NamePlateHealthBarMixin = {}
function NamePlateHealthBarMixin.UpdateSelectionBorder(self)
    local color = self.isTarget == true and NAMEPLATE_BORDER_TARGET_COLOR or NAMEPLATE_BORDER_FOCUS_TARGET_COLOR
    self.selectedBorder:SetVertexColor(color.r, color.g, color.b)
end
hooksecurefunc = function(owner, method, callback)
    assert(method == "UpdateSelectionBorder", "the selection module hooked " .. method)
    hooks[#hooks + 1] = owner
    local original = owner[method]
    owner[method] = function(...) original(...) callback(...) end
end
local function Health()
    local bar = { selectedBorder = Texture(), deselectedOverlay = Texture(), isTarget = false, isFocus = false,
        UpdateSelectionBorder = NamePlateHealthBarMixin.UpdateSelectionBorder, created = {} }
    function bar:CreateTexture()
        local texture = Texture()
        self.created[#self.created + 1] = texture
        return texture
    end
    return bar
end
assert(loadfile(root .. "/MSUF_Suite_Nameplates/Selection.lua"))("MSUF_Suite_Nameplates", private)
local Selection = private.Selection
local health = Health()

Selection.Configure(Config())
assert(not Selection.inUse and #hooks == 0, "Blizzard's look installed a selection hook or a plate pass")

Selection.Configure(Config({ selectionBorder = 2, selectionTargetColor = "00ff00", selectionFocusColor = "0000ff" }))
assert(Selection.inUse, "custom border colors must enable the plate pass")
Selection.Apply(health, true)
assert(#hooks == 2 and health.selectedBorder.color[2] == 1, "custom target color or hooks missing")
local before = health.selectedBorder.writes
Selection.Apply(health, true)
assert(health.selectedBorder.writes == before, "an unchanged plate pass rewrote the border")
health.isFocus = true
health:UpdateSelectionBorder()
assert(health.selectedBorder.color[3] == 1 and health.selectedBorder.color[1] == 0,
    "the focus color was lost after Blizzard's own update")
health.isTarget, health.isFocus = "secret", true
health:UpdateSelectionBorder()
assert(health.selectedBorder.color[3] == 1, "a secret target with a known focus must keep the focus color")
local fresh = Health()
fresh.UpdateSelectionBorder = NamePlateHealthBarMixin.UpdateSelectionBorder
Selection.Apply(fresh, true)
assert(#hooks == 2, "a health bar made after the mixin hook was hooked twice")

Selection.Configure(Config({ selectionBorder = 3, selectionDim = 2, selectionDimPercent = 30 }))
Selection.Apply(health, true)
assert(health.selectedBorder.alpha == 0 and math.abs(health.deselectedOverlay.alpha - 0.3) < 1e-9,
    "hidden border or dim strength not applied")
Selection.Configure(Config({ selectionDim = 3 }))
Selection.Apply(health, true)
assert(health.deselectedOverlay.alpha == 0 and health.selectedBorder.alpha == 1, "dim off or border restore failed")
Selection.Apply(health, false)
assert(health.deselectedOverlay.alpha == 1, "an unskinned side kept the custom dimming")
-- Blizzard's look: styled plates get one restore pass, then the module idles.
Selection.Configure(Config({ selectionDim = 2, look = 2 }))
assert(Selection.inUse, "styled plates under Blizzard's look lost their restore pass")
Selection.Apply(fresh, true)
assert(not Selection.inUse, "Blizzard's look must switch the selection styling off")
Selection.Configure(Config({ selectionDim = 2 }))
Selection.Apply(health, true)
Selection.Configure(Config())
assert(Selection.inUse, "a styled plate must still get its restore pass")
Selection.Apply(health, true)
assert(health.deselectedOverlay.alpha == 1 and not Selection.inUse, "Keep did not restore Blizzard's dimming")

------------------------------------------------------------------ Borderless health bars
do
    local config = Config({ look = 2, hideHealthBarBorders = true })
    local retail = Health()
    retail.bgTexture = Texture()
    retail.bgTexture.alpha, retail.selectedBorder.alpha, retail.deselectedOverlay.alpha = 0.68, 0.72, 0.55
    Selection.Configure(config)
    assert(Selection.inUse, "borderless mode must work on the Blizzard look")
    Selection.Apply(retail, false, nil, "friendly")
    assert(retail.bgTexture.alpha == 0 and retail.selectedBorder.alpha == 0,
        "Retail native borders remained on an unskinned plate")
    assert(retail.deselectedOverlay.alpha == 0.55 and retail.deselectedOverlay.writes == 0,
        "borderless mode took over the independent native dimming")
    local writes = retail.bgTexture.writes + retail.selectedBorder.writes
    Selection.Apply(retail, false, nil, "friendly")
    assert(retail.bgTexture.writes + retail.selectedBorder.writes == writes, "warm plate pass rewrote hidden borders")
    config.hideHealthBarBorders = false
    Selection.Configure(config)
    Selection.Apply(retail, false, nil, "friendly")
    assert(retail.bgTexture.alpha == 0.68 and retail.selectedBorder.alpha == 0.72,
        "turning borders back on did not restore their original opacity")

    config = Config({ enemyBorderStyle = 2, enemyOuterFrame = true, enemyShadowEnabled = true,
        enemyGlowEnabled = true, enemyThresholdEnabled = true, enemyTargetStyle = 14 })
    local style = NS.NameplateStyle
    local framed = style.Decor.Plan(config, "enemy")
    assert(framed.border and framed.outer and framed.shadow and framed.glow ~= 1)
    config.hideHealthBarBorders = true
    local plain = style.Decor.Plan(config, "enemy")
    assert(not plain.border and not plain.outer and not plain.shadow and plain.glow == 1 and plain.threshold,
        "borderless mode left Suite frames visible or removed the health threshold")
    local target = style.TargetConfig(config)
    assert(target.hideBorder and target.bossTargetStyle == "BORDER_ARROW", "the target arrow must retain its shape")
end

------------------------------------------------------------------ Frame outline and highlight priority on recycled nameplates
do
    local bar = Health()
    bar.bgTexture = Texture()
    bar.bgTexture.alpha = 0.68
    local status = 2
    UnitAffectingCombat = function() return false end
    UnitThreatSituation = function(player, unit)
        assert(player == "player" and unit == "nameplate1")
        return status
    end
    local unit = { unit = "nameplate1", HealthBarsContainer = { healthBar = bar } }
    private.Mouseover = { IsHovered = function() return true end }
    local c = Config({ enemyOutlineMode = 3, highlightTarget = true, highlightFocus = true, highlightAggro = true,
        highlightMouseover = true, highlightMouseoverColor = "00ff00" })
    local outline = NS.NameplateStyle.CreateBorder(bar)
    Selection.Configure(c)
    Selection.Apply(bar, true, unit, "enemy", outline, 0, "000000")
    local edge = assert(bar.created[1])
    assert(#bar.created == 4 and edge.shown and edge.color[2] == 0x52 / 255 and bar.bgTexture.alpha == 0,
        "Aggro must win over mouseover when both highlights are active")
    bar.isFocus = true
    bar:UpdateSelectionBorder()
    assert(edge.color[3] == 1 and bar.selectedBorder.alpha == 0)
    bar.isTarget = true
    bar:UpdateSelectionBorder()
    assert(edge.color[2] == 1 and #bar.created == 4, "target must win over focus using the same four edges")
    c.enemyOutlineMode = 4
    Selection.Configure(c)
    Selection.Apply(bar, true, unit, "enemy", outline, 0, "000000")
    bar:UpdateSelectionBorder()
    assert(not edge.shown and bar.selectedBorder.alpha == 0 and not Selection.aggroEnabled,
        "Frame Outline Off left the target or highlight border active")
    c.enemyOutlineMode = 3
    Selection.Configure(c)
    Selection.Apply(bar, true, unit, "enemy", outline, 0, "000000")
    assert(edge.shown and bar.selectedBorder.alpha == 0, "re-enabling the outline did not restore the selected highlight")
    local writes = edge.writes
    bar:UpdateSelectionBorder()
    assert(edge.writes == writes, "stable priority state repainted a texture")
    bar.isTarget, bar.isFocus, status = false, false, "secret"
    bar:UpdateSelectionBorder()
    Selection.ThreatChanged(bar, unit.unit)
    assert(edge.color[1] == 0 and edge.color[2] == 1 and bar.selectedBorder.alpha == 1,
        "a protected aggro state displaced mouseover or left the native selection hidden")
    Selection.HighlightMouseover(unit, false)
    assert(not edge.shown)
    bar.bgTexture.alpha = 1
    Selection.RepaintBackground(bar)
    assert(bar.bgTexture.alpha == 0, "restoring the native background exposed the normal border")
    Selection.Restore(bar)
    assert(not edge.shown and bar.bgTexture.alpha == 0.68)
    Selection.Apply(bar, true, unit, "friendly", outline, 1, "000000")
    assert(edge.shown and #bar.created == 4 and bar.bgTexture.alpha == 0.68, "a pooled frame kept its hostile state")
    Selection.HighlightMouseover(unit, false)
    assert(edge.shown and edge.color[2] == 0 and outline.borderSize == 1, "losing a highlight must reveal the regular outline")
    Selection.RestoreAll()
    c.highlightPriority, c.highlightOrder = true, "4312"
    local style = NS.NameplateStyle
    local plan = style.CompileHighlights(c)
    assert(style.HighlightColor(plan, true, true, true, true) == "00ff00", "custom priority did not promote mouseover")
    assert(table.concat(style.HighlightOrder("4499"), ",") == "mouseover,target,focus,aggro")
    c.highlightTarget, c.highlightFocus, c.highlightAggro = false, false, false
    Selection.Configure(c)
    local color, hidesNative = style.HighlightColor(style.CompileHighlights(c), true, false, false, true)
    assert(color == "00ff00" and not hidesNative and not Selection.aggroEnabled,
        "mouseover alone suppressed native selection or added threat processing")
end

do
    local bar = Health()
    bar.bgTexture = Texture()
    bar.isTarget = true
    local config = Config({ look = 2, barsOverride = true, enemyOutlineMode = 4 })
    Selection.Configure(config)
    Selection.Apply(bar, false, nil, "enemy")
    assert(bar.selectedBorder.alpha == 0 and bar.bgTexture.alpha == 0, "Off left a border in the Blizzard look")
    Selection.Restore(bar)
    assert(Selection.inUse, "releasing the last plate stopped applying Off to later plates")
    Selection.Apply(bar, false, nil, "enemy")
    config.enemyOutlineMode = 2
    Selection.Configure(config)
    Selection.Apply(bar, false, nil, "enemy")
    assert(bar.selectedBorder.alpha == 1 and bar.bgTexture.alpha == 1, "Blizzard did not restore the native borders")
end

do
    local bar = Health()
    bar.bgTexture = Texture()
    bar.bgTexture.alpha = 0.65
    local locked = false
    local completeRestore, previousCreateFrame, previousCombat = nil, CreateFrame, NS.IsCombatLocked
    NS.IsCombatLocked = function() return locked end
    CreateFrame = function()
        return { RegisterEvent = function() end, UnregisterEvent = function() end,
            SetScript = function(frame, _, fn) completeRestore = function() fn(frame) end end }
    end
    function bar.bgTexture:CanBeAccessedInContext() return not locked end
    Selection.Configure(Config({ enemyOutlineMode = 4 }))
    Selection.Apply(bar, true, nil, "enemy")
    assert(bar.bgTexture.alpha == 0)
    locked = true
    Selection.Restore(bar)
    assert(bar.bgTexture.alpha == 0)
    locked = false
    assert(completeRestore)()
    assert(bar.bgTexture.alpha == 0.65, "a denied restore lost the original backdrop opacity")
    CreateFrame = previousCreateFrame
    NS.IsCombatLocked = previousCombat
end

------------------------------------------------------------------ Forever chrome and level preview
do
    NS.Client.isForever = true
    local foreverCatalog = setmetatable({}, { __index = NS })
    assert(loadfile(root .. "/MSUF_Suite/Core/SuiteCatalog.lua"))("MSUF_Suite", foreverCatalog)
    assert(loadfile(root .. "/MSUF_Suite/Core/Catalog/Nameplates.lua"))("MSUF_Suite", foreverCatalog)
    local forever = foreverCatalog.SuiteCatalog.nameplates.rules
    assert(rules.hideHealthBarBorders.default == false and forever.hideHealthBarBorders.default == false
        and spec.look.presets[1].hideHealthBarBorders == false and spec.look.presets[4].hideHealthBarBorders == false,
        "the common border preference must be opt-in and reset with either skin preset")
    assert(forever.enemyNativeBorderEnabled.default and forever.friendlyNativeBorderEnabled.default,
        "Forever's native bar border must keep its old default")
    assert(not rules.enemyNativeBorderEnabled and not rules.friendlyNativeBorderEnabled,
        "Forever's native bar border controls leaked into Retail")
    assert(forever.enemyLevelSize.requiresChoice.values[1] and not forever.enemyLevelSize.requiresChoice.values[2],
        "Blizzard badge must not expose an inert size control")

    NamePlateConstants = { TARGET_BORDER_COLOR = { r = 1, g = 0.8, b = 0 },
        FOCUS_TARGET_BORDER_COLOR = { r = 0.4, g = 0.7, b = 1 } }
    local enemy, friendly = Health(), Health()
    enemy.bgTexture, friendly.bgTexture = Texture(), Texture()
    enemy.bgTexture.alpha = 0.67
    local badge = { selectedBorder = Texture(), isTarget = true }
    function badge:UpdateSelectionBorder()
        local color = self.isTarget and NamePlateConstants.TARGET_BORDER_COLOR or NamePlateConstants.FOCUS_TARGET_BORDER_COLOR
        self.selectedBorder:SetVertexColor(color.r, color.g, color.b)
    end
    local uf = { PlayerLevelDiffFrame = badge }
    local config = Config({ enemyNativeBorderEnabled = false, selectionBorder = 3 })
    Selection.Configure(config)
    Selection.Apply(enemy, true, uf, "enemy")
    Selection.Apply(friendly, true, {}, "friendly")
    assert(enemy.bgTexture.alpha == 0 and friendly.bgTexture.alpha == 1, "native border was not scoped per side")
    Selection.Apply(enemy, true, uf, "friendly")
    assert(enemy.bgTexture.alpha == 0.67, "a plate that became friendly kept its enemy native border preference")
    Selection.Apply(enemy, true, uf, "enemy")
    assert(enemy.bgTexture.alpha == 0, "a plate that became hostile kept its friendly native border preference")
    assert(enemy.selectedBorder.alpha == 0 and badge.selectedBorder.alpha == 0,
        "Hide left a native target border on Forever's level badge")
    badge:UpdateSelectionBorder()
    assert(badge.selectedBorder.alpha == 0, "native target update restored the hidden badge border")
    config.selectionBorder, config.selectionFocusColor = 2, "00ff00"
    Selection.Configure(config)
    Selection.Apply(enemy, true, uf, "enemy")
    badge.isTarget, badge.isFocus = false, true
    badge:UpdateSelectionBorder()
    assert(badge.selectedBorder.alpha == 1 and badge.selectedBorder.color[2] == 1,
        "custom focus color did not survive a native badge refresh")
    config.selectionBorder, config.enemyNativeBorderEnabled = 1, true
    Selection.Configure(config)
    Selection.Apply(enemy, true, uf, "enemy")
    assert(enemy.bgTexture.alpha == 0.67 and badge.selectedBorder.color[2] == 0.7,
        "Keep did not restore the previous native backdrop opacity and badge color")
    config.selectionBorder, config.enemyNativeBorderEnabled = 3, false
    Selection.Configure(config)
    Selection.Apply(enemy, true, uf, "enemy")
    Selection.Apply(enemy, false)
    assert(enemy.bgTexture.alpha == 0.67 and badge.selectedBorder.alpha == 1,
        "disabling a side did not restore the backdrop and badge border")
    Selection.Apply(enemy, true, uf, "enemy")
    Selection.RestoreAll()
    assert(enemy.bgTexture.alpha == 0.67 and badge.selectedBorder.alpha == 1,
        "disabling the module did not restore the backdrop and badge border")

    config.hideHealthBarBorders, config.look = true, 2
    Selection.Configure(config)
    Selection.Apply(enemy, false, uf, "enemy")
    Selection.Apply(friendly, false, {}, "friendly")
    assert(enemy.bgTexture.alpha == 0 and friendly.bgTexture.alpha == 0 and badge.selectedBorder.alpha == 0,
        "Forever left a border on a disabled side or level badge")
    Selection.RestoreAll()
    assert(enemy.bgTexture.alpha == 0.67 and friendly.bgTexture.alpha == 1 and badge.selectedBorder.alpha == 1,
        "module disable did not restore all native Forever borders")
    config.hideHealthBarBorders, config.look = false, 3

    local preview = { Suite = NS, Get = function(_, key) return config[key] end, RGB = NS.RGB }
    assert(loadfile(root .. "/MSUF_Suite_Options/Pages/NameplatesPreviewDecor.lua"))("Options", preview)
    local draw = preview.NameplatesPreviewDecor
    local editor = { LayerOn = function() return true end }
    local sample = { prefix = "enemy", bar = {}, state = { target = true },
        nativeBorder = Texture(), selectedBar = Texture(), levelBack = Texture(),
        levelSelected = Texture(), levelSkull = Texture(), levelText = Texture(), level = Texture() }
    local label, level = sample.levelText, sample.level
    function label:SetText(value) self.text = value end
    function label:SetTextHeight(value) self.size = value end
    function label:SetJustifyH(value) self.justify = value end
    function label:SetTextColor() end
    function level:SetSize(width, height) self.width, self.height = width, height end
    local function Setup(_, fallback) return fallback end
    local function Place(_, region, point) region.point = point end
    UnitEffectiveLevel = function() return 13 end
    local metrics = { forever = true, style = 0, horizontal = 1, vertical = 1, classificationScale = 1 }
    config.look, config.enemyLevelEnabled, config.levelAppearance = 3, true, 1
    config.enemyLevelSize = 20
    metrics.levelMode = draw.LevelMode(editor, "enemy", true, false)
    draw.PaintLevel(editor, sample, metrics, Setup, Place)
    assert(level.shown and level.point == "RIGHT" and label.text == 13 and label.size == 20
        and not sample.levelBack.shown, "Forever Classic must preview the configured plain level at the left")
    config.levelAppearance = 2
    metrics.levelMode = draw.LevelMode(editor, "enemy", true, false)
    draw.PaintLevel(editor, sample, metrics, Setup, Place)
    assert(level.shown and level.point == "LEFT" and label.size == 10 and sample.levelBack.shown
        and not sample.levelSelected.shown, "Forever badge ignored its native placement or hidden selection")
    config.enemyLevelEnabled = false
    metrics.levelMode = draw.LevelMode(editor, "enemy", false, false)
    draw.PaintLevel(editor, sample, metrics, Setup, Place)
    assert(not level.shown and not draw.LevelMode(editor, "friendly", false, true),
        "a disabled level or a names-only sample still showed the level")
    draw.PaintHealthChrome(editor, sample, metrics)
    assert(not sample.nativeBorder.shown and not sample.selectedBar.shown,
        "the preview kept a native border that the live settings hide")
    config.look = 2
    draw.PaintHealthChrome(editor, sample, metrics)
    assert(sample.nativeBorder.shown and sample.selectedBar.shown, "Blizzard look did not restore its native preview chrome")
    assert(sample.selectedBar.atlas == "UI-HUD-CoolDownManager-Selected-yellow"
        and sample.selectedBar.points[1][2] == sample.nativeBorder
        and sample.selectedBar.points[1][4] == -3 and sample.selectedBar.points[1][5] == 2,
        "Forever target art does not follow the native backdrop")
    config.hideHealthBarBorders = true
    draw.PaintHealthChrome(editor, sample, metrics)
    assert(not sample.nativeBorder.shown and not sample.selectedBar.shown,
        "the common border switch did not clear the Forever preview")
    metrics.forever, config.hideHealthBarBorders = false, false
    draw.PaintHealthChrome(editor, sample, metrics)
    assert(sample.nativeBorder.shown and sample.selectedBar.atlas == "UI-HUD-Nameplates-Selected"
        and sample.selectedBar.points[1][4] == -1 and sample.selectedBar.points[1][5] == 1,
        "Retail preview did not use its native borders")
    metrics.classic, metrics.reserve, metrics.horizontal, metrics.vertical = true, 20, 1.25, 1.5
    draw.PaintHealthChrome(editor, sample, metrics)
    assert(sample.nativeBorder.width == 160 and sample.nativeBorder.height == 24
        and sample.nativeBorder.layer == "ARTWORK" and sample.nativeBorder.sublayer == 1
        and sample.nativeBorder.points[1][4] == 8.625 * 1.25 and sample.nativeBorder.points[1][5] == -0.75
        and not sample.selectedBar.shown,
        "Classic preview did not keep the fixed-size Blizzard border and disabled target ring")
    local textureWrites, textureReads = 0, 0
    local art = sample.nativeBorder
    function art:SetTexture(path)
        textureWrites = textureWrites + 1
        self.path = path
    end
    function art:ClearTextureSlice() end
    function NS.ResolveTexture(key)
        textureReads = textureReads + 1
        return key
    end
    draw.PaintHealthChrome(editor, sample, metrics, "shared-texture")
    draw.PaintHealthChrome(editor, sample, metrics, "shared-texture")
    assert(art.path == "shared-texture" and art.layer == "BACKGROUND" and textureReads == 1 and textureWrites == 1,
        "the Classic preview reloaded its SharedMedia background on an unchanged paint")
    draw.PaintHealthChrome(editor, sample, metrics, "")
    assert(art.layer == "ARTWORK" and art.path == "Interface\\Tooltips\\Nameplate-Border")
    metrics.classic = false
    draw.PaintHealthChrome(editor, sample, metrics, "shared-texture")
    assert(art.vertices[1][1] == 2 and art.vertices[1][2] == -3
        and art.vertices[4][1] == -6 and art.vertices[4][2] == 6,
        "the Modern preview did not fit the background to the bar")
    assert(sample.selectedBar.points[1][2] == art and art.points[2][4] == 6,
        "fitting the art moved the selected border's anchor")
    draw.PaintHealthChrome(editor, sample, metrics, "")
    assert(art.vertices[4][1] == 0 and art.vertices[4][2] == 0,
        "the native preview background retained the custom vertex offsets")
    assert(draw.LevelMode(editor, "enemy", true, false) == "badge", "Forever Blizzard look lost its native level badge")
    NS.Client.isForever = false
    Enum = { GameRule = { PlayerNameplateDifficultyIcon = 1 } }
    C_GameRules = { IsGameRuleActive = function(rule) return rule == Enum.GameRule.PlayerNameplateDifficultyIcon end }
    editor.enemyPlayer = true
    assert(draw.LevelMode(editor, "enemy", false, false) == "badge",
        "Retail's player difficulty badge is missing from the preview while its game rule is active")
    editor.enemyPlayer = false
    assert(not draw.LevelMode(editor, "enemy", false, false), "Retail displayed the player difficulty badge for an NPC")
end

------------------------------------------------------------------ options
local P = { Gates = {}, SearchPreparers = {}, catalog = { nameplates = spec } }
local options = Config()
P.Tr = function(text) return text end
P.Get = function(_, key) return options[key] end
P.Combat = function() return false end
P.Meta = function(_, _, key) return { key = key } end
P.Confirm = function(_, _, accept) P.accept = accept end
P.SetMany = function(_, values) P.applied = values end
local relayouts, focused = 0, nil
local function Frame()
    local f = { shown = true, scripts = {} }
    function f:SetShown(value) self.shown = value end
    function f:SetPoint() end
    function f:SetScript(event, fn) self.scripts[event] = fn end
    function f:SetEnabled(value) self.enabled = value end
    function f:Hide() self.shown = false end
    return f
end
P.HM = {
    GetSectionEntry = function(body) return body.entry end,
    SetSectionEnsureVisible = function(entry, ensure) entry.ensure = ensure end,
}
P.W = {
    MeasureScopeOverrideBar = function() return { bottomY = -40 } end,
    ScopeOverrideBar = function(_, _, opts)
        local bar = { opts = opts }
        function bar:Refresh() self.value = opts.getValue() end
        return bar
    end,
    RoleButton = function() return Frame() end,
    FocusCollapsibleSection = function(body) focused = body end,
}
P.M = { AddTooltip = function() end, TrackRefresh = function() end }
assert(loadfile(root .. "/MSUF_Suite_Options/Pages/NameplatesWorkspace.lua"))("MSUF_Suite_Options", P)
local gate = P.Gates.nameplates
assert(gate(rules.enemyNameSize, "enemyNameSize") == true and gate(rules.plateShowAll, "plateShowAll") == true,
    "a skinned look greyed a live control")
options.look = 2
local ok, reason = gate(rules.enemyNameSize, "enemyNameSize")
assert(ok == false and reason:find("Blizzard"), "Blizzard's look left skin controls live")
assert(gate(rules.hideHealthBarBorders, "hideHealthBarBorders"), "the common border switch is disabled on Blizzard look")
assert(gate(rules.friendlyNamesOnly, "friendlyNamesOnly") == true and gate(rules.plateStackEnemy, "plateStackEnemy") == true,
    "Blizzard's own options were greyed under Blizzard's look")
options.look, options.enemy = 4, false
ok, reason = gate(rules.enemyRoleColors, "enemyRoleColors")
assert(ok == false and reason:find("Skin enemy nameplates", 1, true), "enemy skin off left enemy controls live")
assert(gate(rules.enemyTargetStyle, "enemyTargetStyle") == true, "target arrows on friendly plates were greyed")
options.enemy = true

-- The type header filters and orders one set of controls. The same Auras
-- body stays in place across type switches; focusing an exclusive section
-- also selects its preview sample.
local builder = { layoutEntries = {}, width = 720 }
function builder:Section() return Frame() end
function builder:RequestRelayoutCollapsibles() relayouts = relayouts + 1 end
local Workspace = P.NameplatesWorkspace
P.T = P.T or {}
P.NameplatesAdvancedAuras = { SelectSide = function() end }
P.ShowNameplatesSample = function() end
local ui = assert(Workspace.Header({ width = 720 }, builder))
local function Section(scopes)
    local body = Frame()
    body.entry = { outer = Frame(), body = body, open = true }
    Workspace.Track(ui, body, scopes)
    return body
end
local enemy, neutral, auras = Section({ enemy = 10 }), Section({ neutral = 10 }), Section({ enemy = 30, neutral = 30 })
Workspace.Finish(ui)
assert(enemy.entry.outer.shown and auras.entry.outer.shown and not neutral.entry.outer.shown)
assert(#builder.layoutEntries == 2 and builder.layoutEntries[1] == enemy.entry)
local sample
P.ShowNameplatesSample = function(_, kind) sample = kind end
neutral.entry.ensure(neutral.entry)
assert(sample == "neutral" and neutral.entry.outer.shown and not enemy.entry.outer.shown and auras.entry.outer.shown)
assert(builder.layoutEntries[1] == neutral.entry and ui.selector.value == "neutral")
auras.entry.ensure(auras.entry)
assert(ui.selector.value == "neutral", "a shared section changed its selected type")
ui.selector.opts.setValue("enemy")
assert(sample == "enemy" and enemy.entry.outer.shown and not neutral.entry.outer.shown)
P.W.ScopeOverrideBar = nil
assert(Workspace.Header({ width = 720 }, builder) == nil, "an older host must keep the full page")

-- Section reset under a preset look takes that look's values.
local resetValues
P.S = { ResetKeys = function(_, values) resetValues = values; return true end }
P.T, P.WithHistory, P.Refresh = {}, function(_, _, fn) return fn() end, function() end
P.Suite = { RGB = NS.RGB, Registry = { AddListener = function() end } }
assert(loadfile(root .. "/MSUF_Suite_Options/Menu/MediaValues.lua"))("MSUF_Suite_Options", P)
assert(loadfile(root .. "/MSUF_Suite_Options/Menu/Controls.lua"))("MSUF_Suite_Options", P)
options.look = 1
local jundies = spec.look.presets[1]
assert(jundies.enemyHealthWidthDelta ~= rules.enemyHealthWidthDelta.default, "Jundies and the catalog defaults no longer differ")
P.ResetRules("nameplates", { rules.enemyHealthWidthDelta, rules.plateShowAll })
assert(resetValues.enemyHealthWidthDelta == jundies.enemyHealthWidthDelta and resetValues.plateShowAll == 1,
    "a section reset under Jundies did not restore Jundies values")

-- Placement (Pages/Nameplates.lua SECTIONS): every visible setting and every
-- color shows exactly once, and search opens the section that shows it.
P.Help = function(summary, details) return { summary = summary, details = details } end
P.Suite.NameplateStyle, P.Suite.HostBridge = NS.NameplateStyle, {}
P.SectionRules = function(_, section)
    local out = {}
    for _, rule in ipairs(spec.controls) do
        if rule.section == section and rule.key ~= "enabled" and not rule.previewOnly then out[#out + 1] = rule end
    end
    return out
end
P.RegisterPage = function() end
-- The page registers a cold exact-target preparer through the host adapter.
P.Suite.HostBridge.RegisterSearchTargetResolver = function(_, name, resolver)
    assert(name == "MSUF_Suite.NameplatesTabs" and type(resolver) == "function")
    return true
end
-- Keep this fixture on native visibility controls. Expanded aura placement
-- and rendering are exercised by suite_nameplates_aura_display_contract.
assert(loadfile(root .. "/MSUF_Suite/Core/Catalog/NameplateExtensions.lua"))("MSUF_Suite", NS)
assert(loadfile(root .. "/MSUF_Suite/Core/NameplateAuraDisplay.lua"))("MSUF_Suite", NS)
assert(loadfile(root .. "/MSUF_Suite/Core/Catalog/NameplateAuras.lua"))("MSUF_Suite", NS)
P.Suite.NameplateAuraDisplay = NS.NameplateAuraDisplay
assert(loadfile(root .. "/MSUF_Suite_Options/Pages/NameplatesAdvancedAuras.lua"))("Options", P)
P.Suite.NameplateExtensions = NS.NameplateExtensions
assert(loadfile(root .. "/MSUF_Suite_Options/Pages/NameplatesExtensions.lua"))("Options", P)
P.NameplatesHostOptions = { Build = function() end }
assert(loadfile(root .. "/MSUF_Suite/Core/NameplateText.lua"))("Core", NS)
P.Suite.NameplateText = NS.NameplateText
P.Suite.HostBridge.NameFormatter = function() end
P.Suite.HostBridge.HasNameplateFontsMenu = function() return false end
P.NameplatesHostOptions.registered = true
assert(loadfile(root .. "/MSUF_Suite_Options/Pages/NameplateBarTextures.lua"))("Options", P)
assert(loadfile(root .. "/MSUF_Suite_Options/Pages/NameplateFonts.lua"))("Options", P)
assert(loadfile(root .. "/MSUF_Suite_Options/Pages/NameplatesStatus.lua"))("Options", P)
assert(loadfile(root .. "/MSUF_Suite_Options/Pages/NameplatesSectionsLayout.lua"))("MSUF_Suite_Options", P)
assert(loadfile(root .. "/MSUF_Suite_Options/Pages/Nameplates.lua"))("MSUF_Suite_Options", P)
P.NameplateSearchTarget(rules.look)
local where = {}
local function See(key, place)
    if rules[key] then where[key] = where[key] or place end
end
See("look", "enemyBasics")
for _, section in ipairs(P.NameplateSections) do
    if section.switch then See(section.switch, section.key) end
    for _, key in ipairs(section.keys or {}) do See(key, section.key) end
    for _, key in ipairs(section.colors or {}) do See(key, section.key) end
    for key in pairs(section.statusOffsets or {}) do See(key, "status_offset_" .. key) end
    for _, tab in ipairs(section.tabs or {}) do
        for _, key in ipairs(tab.keys) do See(key, section.key) end
        for _, key in ipairs(tab.colors or {}) do See(key, section.key) end
    end
    for _, rule in ipairs(section.catalog and P.SectionRules(nil, section.catalog) or {}) do
        if not rule.key:match("Offset[XY]$") then See(rule.key, section.key) end
    end
end
for _, rule in ipairs(spec.getControls()) do
    if rule.key ~= "enabled" and not rule.hidden and not rule.previewOnly and rule.section ~= "auraColors"
        and rule.section ~= "nativeTextures" and rule.section ~= "barGradients" and not P.NameplateFonts.IsTypography(rule.key)
        and rule.key ~= "enemyBorderEnabled" and rule.key ~= "friendlyBorderEnabled"
        and spec.controlAvailable(rule)
        and (not P.NameplatesStatus.IsOffset(rule.key) or where[rule.key] and where[rule.key]:match("^status_offset_")) then
        assert(where[rule.key], rule.key .. " has no place on the nameplate page")
        local target = P.NameplateSearchTarget(rule)
        local palette = rule.color and not rule.key:match("^aura") and target:match("Style$")
        assert(palette or target == "suite_nameplates_" .. where[rule.key], rule.key .. " search opens another section")
    end
end
for _, key in ipairs({ "enemyCastOffsetX", "friendlyCastTargetOffsetY", "auraTimeX", "enemyPowerOffsetX" }) do
    local section, _, exact = P.NameplateSearchTarget(rules[key])
    assert(section:match("^suite_nameplates_preview_") and exact == false, key .. " should route to preview")
end

local settings, stored = {}, {}
P.Get = function(_, key) return settings[key] or 1 end
P.Set = function(_, key, value) stored[key], settings[key] = value, value end
P.SetMany = function(id, values) for key, value in pairs(values) do P.Set(id, key, value) end end
P.Suite.Public = NS.Public
P.ChoiceGates = {}
assert(loadfile(root .. "/MSUF_Suite_Options/Pages/NameplatesDirectSettings.lua"))("Options", P)
local function Control(key) return assert(P.RuleRow("suite_nameplates", "nameplates", rules[key])) end
assert(not spec.controlAvailable(rules.plateEnemies) and not spec.controlAvailable(rules.plateFriendlyPlayers),
    "legacy Show switches are still discoverable")
live.nameplateCastBarDisplay = string.char(1, 64 + 5)
local icon = Control("enemyCastSpellIcon")
assert(not icon.get(), "inherited spell icon did not show the native state")
icon.set(true)
assert(stored.enemyCastDisplay == 2 and stored.enemyCastSpellIcon and stored.enemyCastSpellName and stored.enemyCastSpellTarget
    and stored.enemyCastImportant == false, "direct cast detail toggle did not preserve sibling flags")
for _, rule in ipairs(spec.controls) do
    local legacy = rule.choices and rule.choices[1]
    if spec.controlAvailable(rule) and (legacy == "Keep Blizzard setting" or legacy == "Keep Blizzard settings") then
        local row = Control(rule.key)
        if row.values then
            for _, choice in ipairs(row.values()) do assert(choice.value ~= 1, rule.key .. " exposes inherited mode") end
        else
            assert(row.kind == "toggle", rule.key .. " is not an explicit toggle")
        end
    end
end

print("Suite nameplates: visibility CVars, combat hold, selection border, greying, area header, Quick Setup, preset reset"
    .. " and setting placement passed")

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
local live = {}
C_CVar = { GetCVar = function(key) return live[key] end }
assert(loadfile(root .. "/MSUF_Suite/Core/SuiteCatalog.lua"))("MSUF_Suite", NS)
assert(loadfile(root .. "/MSUF_Suite/Core/NameplateStyle.lua"))("MSUF_Suite", NS)
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
local S = { RestoreCVar = function(_, key) restored[key] = true end }
local private = { NS = NS, Suite = S }
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
local KEEP_TEXT = { enemyTextMode = 1, enemyRarityIcon = 1 }
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
Apply({ enemyTextMode = 4 })
assert(Flags(writes.nameplateSimplifiedTypes) == 12, "forced names kept simplified enemy minion or minor plates")
Apply({ enemyTextMode = 4, plateSimpleMinion = 2, plateSimpleFriendlyNpc = 3 })
assert(Flags(writes.nameplateSimplifiedTypes) == 5, "explicit simplified choices lost against the forced names")

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

------------------------------------------------------------------ Selection
local hooks = {}
NAMEPLATE_BORDER_TARGET_COLOR = { r = 1, g = 1, b = 1 }
NAMEPLATE_BORDER_FOCUS_TARGET_COLOR = { r = 1, g = 0.5, b = 0 }
local function Texture()
    local t = { alpha = 1, writes = 0 }
    function t:SetAlpha(alpha) self.alpha, self.writes = alpha, self.writes + 1 end
    function t:SetVertexColor(r, g, b) self.color, self.writes = { r, g, b }, self.writes + 1 end
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
    return { selectedBorder = Texture(), deselectedOverlay = Texture(), isTarget = false, isFocus = false,
        UpdateSelectionBorder = NamePlateHealthBarMixin.UpdateSelectionBorder }
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
assert(gate(rules.friendlyNamesOnly, "friendlyNamesOnly") == true and gate(rules.plateStackEnemy, "plateStackEnemy") == true,
    "Blizzard's own options were greyed under Blizzard's look")
options.look, options.enemy = 4, false
ok, reason = gate(rules.enemyRoleColors, "enemyRoleColors")
assert(ok == false and reason:find("Skin enemy nameplates", 1, true), "enemy skin off left enemy controls live")
assert(gate(rules.enemyTargetStyle, "enemyTargetStyle") == true, "target arrows on friendly plates were greyed")
options.enemy = true

-- Header: one area at a time, focus and search switch areas, Quick Setup is
-- one confirmed write of the recommended look.
local builder = { layoutEntries = {}, width = 720 }
function builder:Section() return Frame() end
function builder:RequestRelayoutCollapsibles() relayouts = relayouts + 1 end
local Workspace = P.NameplatesWorkspace
local ui = assert(Workspace.Header({ width = 720 }, builder))
local function Section(kind)
    local body = Frame()
    body.entry = { outer = Frame(), body = body, open = true }
    Workspace.Track(ui, body, kind)
    return body
end
local general, visibility, enemy, auras = Section("general"), Section("general"), Section("enemies"), Section("auras")
Workspace.Finish(ui)
assert(general.entry.outer.shown and visibility.entry.outer.shown and not enemy.entry.outer.shown
    and not auras.entry.outer.shown and #builder.layoutEntries == 2, "the page did not open on one area")
enemy.entry.ensure(enemy.entry)
assert(enemy.entry.outer.shown and not general.entry.outer.shown and builder.layoutEntries[1] == enemy.entry
    and ui.selector.value == "enemies", "focusing a section did not switch to its area")
ui.selector.opts.setValue("auras")
assert(auras.entry.outer.shown and not enemy.entry.outer.shown, "the area selector did not switch areas")
-- The preview shows the area's sample; a jump from the preview or search keeps it.
local samples = {}
P.ShowNameplatesSample = function(kind) samples[#samples + 1] = kind end
local friendly = Section("friendly")
ui.selector.opts.setValue("friendly")
assert(samples[1] == "friendly" and friendly.entry.outer.shown, "the friendly area did not show a friendly sample")
enemy.entry.ensure(enemy.entry)
assert(#samples == 1 and enemy.entry.outer.shown, "a preview or search jump changed the preview sample")
ui.selector.opts.setValue("auras")
assert(#samples == 1, "an area without a sample of its own changed the preview")
P.ShowNameplatesSample = nil
Workspace.Track(nil, Section("colors"), "colors")
P.W.ScopeOverrideBar = nil
assert(Workspace.Header({ width = 720 }, builder) == nil, "an older host must keep the full page")

-- The Quick Setup button is the RoleButton made by Header.
P.W.ScopeOverrideBar = function(_, _, opts) return { opts = opts, Refresh = function() end } end
local button
P.W.RoleButton = function() button = Frame(); return button end
Workspace.Header({ width = 720 }, builder)
button.scripts.OnClick()
assert(P.accept and not P.applied, "Quick Setup wrote before it was confirmed")
P.accept()
assert(P.applied.look == 4 and P.applied.enabled and P.applied.enemy and P.applied.friendly
    and P.applied.enemyTextMode == spec.look.presets[4].enemyTextMode, "Quick Setup did not apply the recommended look")

-- Section reset under a preset look takes that look's values.
local resetValues
P.S = { ResetKeys = function(_, values) resetValues = values; return true end }
P.T, P.WithHistory, P.Refresh = {}, function(_, _, fn) return fn() end, function() end
P.Suite = { RGB = NS.RGB }
assert(loadfile(root .. "/MSUF_Suite_Options/Menu/Controls.lua"))("MSUF_Suite_Options", P)
options.look = 1
local jundies = spec.look.presets[1]
assert(jundies.enemyNameFont ~= rules.enemyNameFont.default, "Jundies and the catalog defaults no longer differ")
P.ResetRules("nameplates", { rules.enemyNameFont, rules.plateShowAll })
assert(resetValues.enemyNameFont == jundies.enemyNameFont and resetValues.plateShowAll == 1,
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
assert(loadfile(root .. "/MSUF_Suite_Options/Pages/Nameplates.lua"))("MSUF_Suite_Options", P)
local where = {}
local function See(key, place)
    if not rules[key] then return end
    assert(not where[key], key .. " shows twice: " .. tostring(where[key]) .. " and " .. place)
    where[key] = place
end
for _, key in ipairs({ "look", "enemy", "friendly", "protectImport" }) do See(key, "nameplates_module") end
for _, section in ipairs(P.NameplateSections) do
    for _, key in ipairs(section.keys or {}) do See(key, section.key) end
    for _, key in ipairs(section.colors or {}) do See(key, section.key) end
    for _, tab in ipairs(section.tabs or {}) do
        for _, key in ipairs(tab.keys) do See(key, section.key) end
    end
    for _, rule in ipairs(section.catalog and P.SectionRules(nil, section.catalog) or {}) do
        if not rule.key:match("Offset[XY]$") then See(rule.key, section.key) end
    end
end
for _, rule in ipairs(spec.controls) do
    if rule.key ~= "enabled" and not rule.hidden and not rule.previewOnly and rule.section ~= "auraColors"
        and not rule.key:match("Offset[XY]$") then
        assert(where[rule.key], rule.key .. " has no place on the nameplate page")
        assert(P.NameplateSearchTarget(rule) == "suite_nameplates_" .. where[rule.key], rule.key .. " search opens another section")
    end
end
assert(P.NameplateSearchTarget(rules.enemyCastOffsetX) == "suite_nameplates_preview", "positions must stay with the preview")

print("Suite nameplates: visibility CVars, combat hold, selection border, greying, area header, Quick Setup, preset reset"
    .. " and setting placement passed")

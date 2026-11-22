-- Health and resource formatting shares one renderer with the preview.
local root = assert(arg[1])
local mode, power, text, combat = "native", false, false, false
local config = { unitHealthHeight = 14, unitPowerHeight = 10, unitHealthWidth = 100, unitPowerWidth = 100,
    unitHealthX = 0, unitPowerX = 0, unitHealthY = 0, unitPowerY = 0,
    unitHealthTexture = "Suite fill", unitHealthBackground = "Suite background",
    unitPowerTexture = "Missing pack", unitHealthTextFormat = "", unitHealthTextSize = 0,
    unitHealthTextFont = "", unitHealthTextX = 0, unitHealthTextY = 0 }
local media = { ["Suite fill"] = "Fill.tga", ["Suite background"] = "Track.tga" }
local resolves, mediaRefreshes = 0, 0
local secrets, frames = {}, {}
local function Secret()
    local value = setmetatable({}, { __lt = function() error("secret comparison") end,
        __tostring = function() error("secret formatting in Lua") end })
    secrets[value] = true
    return value
end
local health, healthMax, resource, resourceMax = Secret(), Secret(), Secret(), Secret()
local secretPercent = Secret()
local unitCalls, percentCalls, fonts = 0, 0, 0
local function UnitValue(value)
    return function(unit)
        assert(unit == "target" or unit == "player" or unit == "focus")
        unitCalls = unitCalls + 1
        return value
    end
end
UnitHealth, UnitHealthMax = UnitValue(health), UnitValue(healthMax)
UnitPower, UnitPowerMax = UnitValue(resource), UnitValue(resourceMax)
CurveConstants = { ScaleTo100 = {} }
UnitHealthPercent = function(unit, predicted, curve)
    assert(unit == "target" or unit == "player")
    assert(predicted == true and curve == CurveConstants.ScaleTo100)
    percentCalls = percentCalls + 1
    if combat then return secretPercent end
    return 76.01
end
canaccesstable = function() return true end

Enum = { TooltipDataType = { Unit = 2 }, TooltipDataLineType = { UnitName = 1 } }
local function Frame(parent)
    local frame = { parent = parent, shown = true, height = 8, width = 244, scripts = {}, events = {}, alpha = 1 }
    function frame:SetStatusBarTexture(texture) self.texture = texture end
    function frame:GetStatusBarTexture()
        return { SetDrawLayer = function(_, layer) self.drawLayer = layer end,
            SetColorTexture = function(_, ...) self.solidFill = {...} end }
    end
    function frame:SetStatusBarColor(...) self.color = { ... } end
    function frame:SetAllPoints() end
    function frame:SetColorTexture(...) self.solid = { ... } end
    function frame:SetTexture(path) self.path = path end
    function frame:SetVertexColor(...) self.tint = { ... } end
    function frame:SetWordWrap() end
    function frame:SetPoint(...) self.points = self.points or {}; self.points[#self.points + 1] = { ... } end
    function frame:ClearAllPoints() self.points = nil end
    function frame:GetWidth() return self.width end
    function frame:SetHeight(height) self.height = height end
    function frame:GetHeight() return self.height end
    function frame:SetShown(shown)
        self.shown, self.visibilityWrites = shown, (self.visibilityWrites or 0) + 1
    end
    function frame:Show() self:SetShown(true); if self.scripts.OnShow then self.scripts.OnShow(self) end end
    function frame:Hide() self:SetShown(false); if self.scripts.OnHide then self.scripts.OnHide(self) end end
    function frame:IsShown() return self.shown end
    function frame:GetAlpha() return self.alpha end
    function frame:SetAlpha(value) self.alpha, self.alphaWrites = value, (self.alphaWrites or 0) + 1 end
    function frame:SetMinMaxValues(lo, hi) self.min, self.max = lo, hi end
    function frame:SetValue(value)
        self.value, self.valueWrites = value, (self.valueWrites or 0) + 1
        if self.scripts.OnValueChanged then self.scripts.OnValueChanged(self, value) end
    end
    function frame:GetValue() return self.value end
    function frame:GetMinMaxValues() return self.min, self.max end
    function frame:SetFormattedText(format, value, maximum) self.format, self.raw, self.max = format, value, maximum end
    function frame:SetText(value) self.plain = value end
    function frame:SetFont(path, size, flags) self.font = { path, size, flags }; return true end
    function frame:GetFont() return unpack(self.font or { "native.ttf", 10, "" }) end
    function frame:SetTextColor(...) self.textColor = { ... } end
    function frame:CreateTexture() return Frame(self) end
    function frame:CreateFontString() self.text = Frame(self); return self.text end
    function frame:SetScript(name, script) self.scripts[name] = script end
    function frame:HookScript(name, script) self:SetScript(name, script) end
    function frame:RegisterEvent(event) self.events[event] = true end
    function frame:RegisterUnitEvent(event, unit) self.events[event] = unit end
    function frame:UnregisterAllEvents() self.events = {} end
    frames[#frames + 1] = frame
    return frame
end
CreateFrame = function() return Frame() end
GameTooltip = Frame()
GameTooltip.StatusBar = Frame(GameTooltip)
GameTooltip.StatusBar:SetMinMaxValues(0, 1)
GameTooltip.StatusBar:SetValue(.75)
function GameTooltip:GetPrimaryTooltipData() return self.data end
function GameTooltip:GetUnit() error("native GetUnit wrapper read potentially restricted fields") end
function UnitTokenFromGUID(guid)
    assert(guid == "Creature-public" and not secrets[guid], "resolved a restricted GUID")
    return "target"
end
local observer, deferred, blockFade
local releases = 0
local HostBridge = {
    SetUnitFrameTooltipPanelObserver = function(fn) observer = fn end,
    ReleaseLegacyTooltipHealth = function() releases = releases + 1 end,
}
local function Call(target, name)
    if target and target[name] then return target[name](target) end
end
local NS = {
    DB = { enabled = true }, IsCombatLocked = function() return combat end,
    SuiteCore = function()
        return { HostBridge = HostBridge, ResolveTexture = function(name, fallback)
            resolves = resolves + 1
            return media[name] or fallback
        end, ResolveFont = function(name)
            fonts = fonts + 1
            if name == "Suite test font" then return "suite.ttf" end
        end }
    end,
    CombatGate = { RunOrDefer = function(_, run)
        if combat then deferred = run else run() end
    end },
    Registry = { NotifyListeners = function(domain)
        assert(domain == "tooltipMedia")
        mediaRefreshes = mediaRefreshes + 1
    end },
    ItemTooltipCard = {
        Setting = function(key)
            if key == "unitHealth" then return mode end
            if key == "unitPower" then return power end
            if key == "unitValueText" then return text end
            return config[key]
        end,
        UnitBarColor = function(key) return key == "unitHealthColor" and .4 or .2, .6, .8, 1 end,
    },
    Safety = {
        Public = function(value) return not secrets[value] end,
        IsForbidden = function() return false end,
        HasMethod = function(frame, key) return frame and type(frame[key]) == "function" end,
        CanCreateRegions = function() return true end,
        CreateChildFrame = function(_, parent) return Frame(parent) end,
        Field = function(target, field) return target[field] end, Call = Call,
        Read = function(target, name)
            local value = Call(target, name)
            if not secrets[value] then return value end
        end,
    },
    Cosmetics = {
        Fade = function(frame)
            if blockFade and combat then return false end
            frame:SetAlpha(0)
            return true
        end,
        Restore = function(frame) frame:SetAlpha(1) end,
    },
}
assert(loadfile(root .. "/MSUF_Suite_Tooltips/UnitTooltipVitals.lua"))("Skin", NS)
local vitals = NS.TooltipVitals
local show, hide = GameTooltip.Show, GameTooltip.Hide
-- ItemTooltipCard owns the shared lifecycle. Retain any separately installed
-- scripts here as well, so the disabled-state budget detects them.
function GameTooltip:Show()
    show(self)
    if vitals.Enabled and vitals.NativeShown then vitals.NativeShown() end
end
function GameTooltip:Hide()
    hide(self)
    if vitals.Enabled and vitals.NativeHidden then vitals.NativeHidden() end
end
local unitData = { type = 2, lines = { { type = 1, unitToken = "target" } } }
GameTooltip.data = unitData
assert(not vitals.Refresh() and #frames == 2 and unitCalls == 0, "factory settings allocated hover resources")

mode, combat = "hide", true
assert(vitals.Refresh() and deferred and not HostBridge.TooltipOwnsHealth and releases == 0 and #frames == 2,
    "a deferred bind claimed the native health bar before it could be skinned")
combat = false
deferred()
assert(GameTooltip.StatusBar.alpha == 0 and unitCalls == 0 and HostBridge.TooltipOwnsHealth and releases == 1)
local unitBar, powerBar, event = frames[3], frames[6], frames[9]
assert(not unitBar.shown and not powerBar.shown and not next(event.events), "hiding started a unit watch")
assert(not GameTooltip.StatusBar.scripts.OnValueChanged, "hiding Blizzard health installed a value mirror")
vitals.NativeCleared()
assert(GameTooltip.StatusBar.alpha == 1)

mode, power, text = "show", true, true
assert(vitals.Refresh() and observer and HostBridge.TooltipOwnsHealth)
assert(unitBar.shown and powerBar.shown and unitBar.height == 14 and powerBar.height == 10)
assert(unitBar.value == health and unitBar.max == healthMax and unitBar.text.raw == health)
assert(powerBar.value == resource and powerBar.max == resourceMax and powerBar.text.format == "%d / %d")
assert(event.events.UNIT_HEALTH == "target" and event.events.UNIT_POWER_UPDATE == "target" and not event.scripts.OnUpdate)
combat = true
local reads, lookups = unitCalls, resolves
event.scripts.OnEvent(event, "UNIT_HEALTH")
assert(unitCalls == reads + 2 and powerBar.value == resource and unitBar.value == health)
assert(resolves == lookups, "a health event resolved SharedMedia textures")
assert(percentCalls == 0, "current/max performed a percentage calculation")
local preview = vitals.CreatePreview(Frame())
assert(vitals.PaintPreview(preview, true, false, false, true, true) == 27)
assert(preview.health.height == unitBar.height and preview.power.height == powerBar.height)
assert(preview.health.color[1] == unitBar.color[1] and preview.health.text.format == unitBar.text.format)
assert(preview.health.drawLayer == "ARTWORK" and unitBar.drawLayer == "ARTWORK")
assert(preview.health.texture == "Fill.tga" and unitBar.texture == "Fill.tga")
assert(preview.healthShape.bg.path == "Track.tga" and frames[4].path == "Track.tga")
assert(preview.power.solidFill[1] == 1 and powerBar.solidFill[1] == 1)
assert(preview.healthShape.bg.tint[3] == frames[4].tint[3])
local draft = { unitHealth = { x = 11, y = -2, width = 50, height = 20 } }
vitals.PaintPreview(preview, true, false, false, true, true, draft)
assert(preview.health.points[1][4] == 73 and preview.health.points[1][5] == -3 and preview.health.height == 20)
assert(unitBar.points[1][4] == 2 and unitBar.height == 14, "moving the preview changed live geometry")
config.unitHealthX, config.unitHealthY, config.unitHealthWidth, config.unitHealthHeight = 11, -2, 50, 20
vitals.Refresh()
assert(unitBar.points[1][4] == 73 and unitBar.points[1][5] == -3 and unitBar.height == 20)
GameTooltip.width = 204
vitals.NativeResized(204)
assert(unitBar.points[1][4] == 63, "relative width did not update with the tooltip width")
combat = false
vitals.MediaRegistered("Unrelated")
assert(mediaRefreshes == 0)
media["Missing pack"] = "Late.tga"
vitals.MediaRegistered("Missing pack")
assert(mediaRefreshes == 1 and powerBar.texture == "Late.tga")
vitals.PaintPreview(preview, true, false, false, true, true)
assert(preview.power.texture == "Late.tga")

config.unitHealthTextFormat, config.unitHealthTextFont, config.unitHealthTextSize = "percent", "Suite test font", 18
config.unitHealthTextX, config.unitHealthTextY = 11, -4
combat = false
vitals.Refresh()
local label = unitBar.text
assert(label.format == "%.0f%%" and label.raw == 76.01)
assert(label.font[1] == "suite.ttf" and label.font[2] == 18 and label.textColor[2] == .6)
assert(label.points[1][4] == 13 and label.points[1][5] == -4)
vitals.PaintPreview(preview, true, false, false, true, true, { unitHealthText = { x = 30, y = 5 } })
assert(preview.healthText.font[1] == label.font[1] and preview.healthText.font[2] == label.font[2])
assert(preview.healthText.format == label.format and preview.healthText.points[1][4] == 32)
assert(label.points[1][4] == 13, "preview changed the live text offset")
local fontReads, percentReads, rawReads = fonts, percentCalls, unitCalls
combat = true
assert(event.events.PLAYER_REGEN_DISABLED and event.events.PLAYER_REGEN_ENABLED)
event.scripts.OnEvent(event, "PLAYER_REGEN_DISABLED")
assert(label.raw == secretPercent and label.format == "%.0f%%" and fonts == fontReads and percentCalls == percentReads + 1)
assert(unitBar.value == secretPercent and unitBar.max == 100 and unitCalls == rawReads,
    "percentage mode did not reuse the same value for fill and label")
assert(label.font[2] == 18 and label.points[1][4] == 13, "the HP style changed during combat")
combat = false
event.scripts.OnEvent(event, "PLAYER_REGEN_ENABLED")
assert(label:IsShown() and label.raw == 76.01 and unitBar.value == 76.01 and fonts == fontReads
    and label.font[2] == 18 and label.points[1][4] == 13,
    "leaving combat changed the styling of an open tooltip")

GameTooltip:Hide()
combat = true
vitals.Native(GameTooltip, unitData)
assert(not unitBar.shown and not next(event.events), "the hidden tooltip started watching a unit")
GameTooltip:Show()
assert(label:IsShown() and label.raw == secretPercent and unitBar.value == secretPercent
    and label.font[2] == 18 and label.points[1][4] == 13 and event.events.UNIT_HEALTH == "target",
    "opening the native tooltip during combat changed the style or format")
vitals.PaintPreview(preview, true, false, false, true, true, nil, true)
assert(preview.health:IsShown() and preview.healthText:IsShown() and preview.healthText.raw == 76.01
    and not preview.power:IsShown(), "restricted preview did not show the public native health percentage")
assert(preview.health.texture == "Fill.tga" and preview.healthShape.bg.path == "Track.tga"
    and preview.health.height == 20, "the restricted preview lost the selected material or geometry")
config.unitHealthTextFormat = "value"
vitals.Refresh()
assert(label.raw == health and label.max == healthMax and label.format == "%d / %d")
mode, power = "hide", false
vitals.Refresh()
assert(GameTooltip.StatusBar.alpha == 0 and not next(event.events) and not unitBar.shown and not powerBar.shown,
    "the old custom bars remained visible after switching to hide")
mode, power, blockFade = "show", true, true
GameTooltip:Hide()
vitals.Refresh()
GameTooltip:Show()
assert(GameTooltip.StatusBar.alpha == 1 and not unitBar.shown and event.events.PLAYER_REGEN_ENABLED,
    "the native health bar should remain when its fade is blocked in combat")
combat = false
event.scripts.OnEvent(event, "PLAYER_REGEN_ENABLED")
assert(GameTooltip.StatusBar.alpha == 0 and unitBar.shown and label.raw == health and label.max == healthMax,
    "the open tooltip did not recover its style after combat without a health update")
blockFade = false
local calls = percentCalls
config.unitHealthTextFormat = "off"
vitals.Refresh()
assert(not label:IsShown() and percentCalls == calls and powerBar.text:IsShown(), "hiding HP text affected the power text")

GameTooltip:Hide()
assert(GameTooltip.StatusBar.alpha == 1 and not next(event.events) and not unitBar.shown and not powerBar.shown)
GameTooltip.data = { type = 2, guid = Secret(), lines = { { type = 1, unitToken = Secret() } } }
local native = GameTooltip.StatusBar
local before, mediaBefore = unitCalls, resolves
local maskedHealth = Secret()
native:SetValue(maskedHealth)
combat = true
vitals.Native(GameTooltip, GameTooltip.data)
GameTooltip:Show()
assert(unitCalls == before and native.alpha == 0 and unitBar.shown and unitBar.value == maskedHealth
    and unitBar.min == 0 and unitBar.max == 1 and unitBar.texture == "Fill.tga" and frames[4].path == "Track.tga"
    and unitBar.height == 20 and not label:IsShown() and not powerBar.shown and not next(event.events),
    "restricted identity lost the SharedMedia bar or tried to resolve an unknown unit")
local newerHealth = Secret()
native:SetValue(newerHealth)
assert(unitBar.value == newerHealth and resolves == mediaBefore and unitCalls == before,
    "native health updates performed extra queries or missed the custom bar")
config.unitHealthTextFormat = "percent"
vitals.Refresh()
assert(not label:IsShown(), "the mirror showed a percentage from a secret fraction")
native:SetValue(.61)
assert(label:IsShown() and label.format == "%.0f%%" and math.abs(label.raw - 61) < .01
    and unitBar.value == .61 and unitCalls == before and not powerBar.shown,
    "the native public fraction did not reach the percentage text")
native:SetValue(newerHealth)
assert(not label:IsShown() and unitBar.value == newerHealth, "the mirror retained stale text when the fraction became secret")
local alphaWrites = native.alphaWrites
media["Suite fill"] = "Enemy texture.tga"
vitals.Refresh()
assert(native.alphaWrites == alphaWrites and unitBar.texture == "Enemy texture.tga" and unitBar.value == newerHealth,
    "refreshing SharedMedia interrupted the visible enemy bar")
local valueWrites = unitBar.valueWrites
assert(vitals.NativeCleared())
vitals.Native(GameTooltip, GameTooltip.data)
assert(native.alphaWrites == alphaWrites and unitBar.shown and unitBar.valueWrites == valueWrites,
    "a tooltip rebuild reset a stable mirror or rewrote its current value")
assert(vitals.NativeCleared())
native:SetValue(.31)
assert(unitBar.valueWrites == valueWrites, "unconfirmed tooltip data changed the old bar")
vitals.Native(GameTooltip, GameTooltip.data)
assert(unitBar.value == .31 and unitBar.valueWrites == valueWrites + 1 and native.alphaWrites == alphaWrites,
    "the mirror did not catch up once a new unit tooltip was confirmed")
assert(vitals.NativeCleared())
vitals.FinishNativeClear()
assert(not unitBar.shown and native.alpha == 1, "a tooltip cleared without a replacement retained the mirror")
GameTooltip:Hide()
local writes = unitBar.valueWrites
native:SetValue(.5)
assert(unitBar.valueWrites == writes and native.alpha == 1 and not unitBar.shown,
    "a hidden tooltip kept mirroring the native bar")
GameTooltip.data = Secret()
native:Hide()
vitals.Native(GameTooltip, GameTooltip.data)
GameTooltip:Show()
assert(not unitBar.shown, "the mirror was shown before the native health source")
native:Show()
assert(unitBar.shown and unitBar.value == .5 and native.alpha == 0,
    "the native bar showing after opaque unit data did not start the mirror")
native:Hide()
assert(not unitBar.shown and native.alpha == 1, "the mirror outlived its native source")
GameTooltip:Hide()
combat = false
native:Show()
GameTooltip.data = { type = 2, guid = "Creature-public", lines = { { type = 1, unitToken = Secret() } } }
vitals.Native(GameTooltip, GameTooltip.data)
GameTooltip:Show()
assert(unitBar.shown and label:IsShown() and powerBar.shown and event.events.UNIT_HEALTH == "target",
    "a readable native GUID failed to recover full unit vitals")
GameTooltip:Hide()
config.unitHealthTextFormat = "value"
vitals.Refresh()
GameTooltip.data = { type = 2, lines = { { type = 1, unitToken = "focus" } } }
vitals.Native(GameTooltip, GameTooltip.data)
GameTooltip:Show()
assert(unitBar.shown and unitBar.value == health and powerBar.shown and powerBar.value == resource
    and event.events.UNIT_HEALTH == "focus", "a public focus no longer used the configured unit bars")
GameTooltip:Hide()

local panel = Frame()
observer(panel, "player")
local panelHealth, panelEvents = frames[#frames - 6], frames[#frames]
assert(panelHealth.shown and panelHealth.value == health and panelEvents.events.UNIT_HEALTH == "player")
mode, power = "native", false
assert(not vitals.Refresh() and not observer and not next(panelEvents.events) and not panelHealth.shown)
assert(vitals.PaintPreview(preview, true, true, false, true, true) == 0 and not preview.health.shown)
assert(vitals.PaintPreview(preview, true, false, false, true, true) > 0 and preview.health.height == 8)

local healthWrites, powerWrites = unitBar.visibilityWrites, powerBar.visibilityWrites
local hiddenReads, lastPercentCalls, hiddenAlphaWrites = unitCalls, percentCalls, native.alphaWrites
for _ = 1, 10 do
    GameTooltip:Show()
    native:SetValue(.41)
    GameTooltip:Hide()
    event.scripts.OnEvent(event, "UNIT_HEALTH")
    event.scripts.OnEvent(event, "UNIT_POWER_UPDATE")
end
assert(unitBar.visibilityWrites == healthWrites and powerBar.visibilityWrites == powerWrites,
    "disabled vitals issued visibility writes on the shared tooltip lifecycle")
assert(unitCalls == hiddenReads and percentCalls == lastPercentCalls and native.alphaWrites == hiddenAlphaWrites
    and not next(event.events) and not GameTooltip.scripts.OnSizeChanged,
    "disabled vitals retained unit queries, event work, or a dedicated tooltip layout hook")

local function CheckSingleBar(healthMode, powerOn, disabledBar)
    mode, power = healthMode, powerOn
    GameTooltip.data = unitData
    assert(vitals.Refresh())
    GameTooltip:Show()
    local visibility, values = disabledBar.visibilityWrites, disabledBar.valueWrites
    local reads = unitCalls
    for _ = 1, 10 do
        vitals.NativeCleared()
        vitals.Native(GameTooltip, unitData)
    end
    assert(disabledBar.visibilityWrites == visibility and disabledBar.valueWrites == values,
        "the disabled bar did work while its sibling was active")
    assert(unitCalls == reads + 20, "the disabled bar queried unit values while its sibling was active")
    GameTooltip:Hide()
end
GameTooltip.width = 284
CheckSingleBar("show", false, powerBar)
assert(unitBar.points[1][4] == 83, "enabling health used the old tooltip width")
CheckSingleBar("native", true, unitBar)
print("unit tooltip vitals contract: native lifecycle, disabled bars, protected values, preview, and MSUF provider")

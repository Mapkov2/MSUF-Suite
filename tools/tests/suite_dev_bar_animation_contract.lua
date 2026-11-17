local root, secretPath = assert(arg[1]), assert(arg[2])
local Secrets = assert(loadfile(secretPath))()
Secrets.Install()
Secrets.GUARD_NAMES.falsy.Public, Secrets.GUARD_NAMES.falsy.Finite = true, true

local fighting, driver, creates, visits = false, nil, 0, 0
local function Noop() end
local function Load(relative, suite)
    local path = root .. "/" .. relative
    assert(loadfile(path))("MSUF_Suite", suite)
    return path
end

local function Public(value) return not issecretvalue(value) end
local Suite = {
    IsSecret = issecretvalue, Public = Public,
    PublicText = function(value) return Public(value) and type(value) == "string" and value end,
    Finite = function(value) return Public(value) and type(value) == "number" end,
    Safety = { IsForbidden = function(frame) return frame:IsForbidden() end },
    InCombat = function() return fighting end,
    Dispatch = function(fn, ...) return fn(...) end,
    Finish = function(fn, ...) return true, fn(...) end,
}
wipe = function(t) for key in pairs(t) do t[key] = nil end end

CreateFrame = function(kind, _, parent)
    creates = creates + 1
    if kind == "Frame" then
        driver = { events = {}, scripts = {} }
        function driver:SetScript(name, callback) self.scripts[name] = callback end
        function driver:RegisterEvent(event) self.events[event] = self.scripts.OnEvent end
        function driver:UnregisterAllEvents() wipe(self.events) end
        return driver
    end
    assert(kind == "StatusBar")
    local overlay = {
        EnableMouse = Noop, SetAllPoints = Noop, SetMinMaxValues = Noop,
        SetRotatesTexture = Noop, SetFrameLevel = Noop,
        SetStatusBarColor = function(self, r, g, b, a) self.r, self.g, self.b, self.a = r, g, b, a end,
        IsProtected = function() return false end,
        SetStatusBarTexture = function() return true end,
        GetStatusBarTexture = function() return { SetAlpha = Noop } end,
    }
    function overlay:SetOrientation(value) self.orientation = value end
    function overlay:SetReverseFill(value) self.reverse = value end
    function overlay:SetValue(value) assert(not fighting); self.value = value end
    function overlay:Show() self.shown = true end
    function overlay:Hide() self.shown = false end
    parent.overlay = overlay
    return overlay
end

local function Bar(shown)
    local fill = { IsForbidden = function() return false end }
    function fill:GetTexture() return self.secretAsset or 123 end
    function fill:GetVertexColor() return self.privateColor or 0.1, 0.7, 0.2, 1 end
    function fill:GetAlpha() return self.playing and 0 or 1 end
    function fill:CreateAnimationGroup()
        local fill = self
        assert(not fighting)
        local group = {
            SetToFinalAlpha = function(_, final) assert(final == false) end,
            SetLooping = function(_, loop) assert(loop == "REPEAT") end,
            CreateAnimation = function(_, kind)
                assert(kind == "Alpha")
                return { SetDuration = Noop, SetFromAlpha = Noop, SetToAlpha = Noop }
            end,
            Play = function() fill.playing = true end,
            Stop = function() fill.playing = false end,
            IsPlaying = function() return fill.playing end,
        }
        return group
    end
    local source = { fill = fill, shown = shown, live = 25 }
    function source:IsForbidden() return false end
    function source:IsVisible() return self.shown end
    function source:IsObjectType(kind) return kind == "StatusBar" end
    function source:GetEffectiveAlpha() return 1 end
    function source:GetFrameLevel() return 5 end
    function source:GetMinMaxValues() return 0, 500 end
    function source:GetOrientation() return "VERTICAL" end
    function source:GetReverseFill() return true end
    function source:GetRotatesTexture() return true end
    function source:GetStatusBarTexture() return self.fill end
    -- The visual test must never touch gameplay values or native timers.
    function source:SetValue() error("Wrote a live value") end
    function source:GetValue() error("Read a live value") end
    function source:SetTimerDuration() error("Replaced a live timer") end
    return source
end

local health, group, power, class, cast, swing = Bar(true), Bar(true), Bar(true), Bar(true), Bar(true), Bar(true)
local secretBar, hidden = Bar(true), Bar(false)
secretBar.fill.secretAsset = Secrets.New("string")
local secretStyle = Secrets.New("number")
local function Font(owner, text)
    local font = {
        text = text, shown = true, IsForbidden = function() return false end,
        CreateAnimationGroup = health.fill.CreateAnimationGroup,
        GetAlpha = function(self) return self.playing and 0 or 1 end,
        GetFont = function(self) return self.secretFont or "font", 12, "OUTLINE" end,
        GetTextColor = function(self) return self.secretColor or 1, 1, 1, 1 end,
        GetJustifyH = function() return "CENTER" end, GetJustifyV = function() return "MIDDLE" end,
        GetDrawLayer = function() return "OVERLAY" end,
        GetNumPoints = function(self) return self.points or 0 end,
        parent = owner,
        GetPoint = function(self) return "CENTER", self.parent, "CENTER" end,
        GetParent = function(self) return self.parent end,
        SetParent = function(self, parent) assert(not fighting); self.parent = parent end,
        CanWordWrap = function() return false end, SetWordWrap = Noop,
        GetShadowColor = function() return 0, 0, 0, 1 end,
        GetShadowOffset = function() return 1, -1 end,
        SetAlpha = Noop, SetDrawLayer = Noop, SetJustifyH = Noop, SetJustifyV = Noop,
        SetTextColor = Noop, SetShadowColor = Noop, SetShadowOffset = Noop, ClearAllPoints = Noop,
        SetFont = function(self, font) self.demoFont = font end,
        SetPoint = function(self, _, relative) self.points, self.demoAnchor = 1, relative end,
        IsObjectType = function(_, kind) return kind == "FontString" end,
    }
    font.points = text and 1 or 0
    function font:IsVisible() return self.shown end
    function font:Show() self.shown = true end
    function font:Hide() self.shown = false end
    function font:GetText() error("Read live text") end
    function font:SetFormattedText(format, ...)
        assert(text == nil and not fighting, "modified live text or wrote a demo in combat")
        self.text = format:format(...)
    end
    return font
end

local function Owner(fields)
    fields.IsForbidden = function() return false end
    fields.CreateFontString = function(self, _, _, template)
        local copy = Font(self)
        copy.demoFont = template
        self.copies = self.copies or {}
        self.copies[#self.copies + 1] = copy
        return copy
    end
    return fields
end
local ufOwner = Owner({ Health = health, Power = power, MSUFUnitKey = "player" })
local groupOwner = Owner({ hpBar = group, MSUFUnitKey = "party1" })
local secretMax = Secrets.New("number")
function UnitHealthMax(unit)
    assert(not fighting and (unit == "player" or unit == "party1"))
    return unit == "player" and 500 or secretMax
end
local castOwner = Owner({ statusBar = cast, _msufCountsDown = false })
local swingOwner = Owner({ Bar = swing, config = { fill = "remaining" } })
local healthText, groupText, powerText = Font(ufOwner, "440"), Font(groupOwner, "45%"), Font(ufOwner, "10")
local secretText = Font(ufOwner, "secret style")
secretText.secretFont = Secrets.New("string")
secretText.secretColor = secretStyle
local function Values(slot, current, maximum, percent)
    slot.fs:SetFormattedText("%d/%d %d%%", current, maximum, percent)
end
local hpSlot, groupSlot = { fs = healthText, plainWriter = Values }, { fs = groupText, plainWriter = Values }
ufOwner._msufTextRuntime = {
    healthSlots = { hpSlot, { fs = secretText, plainWriter = Values } }, healthValueSlotCount = 2,
    powerSlots = { { fs = powerText, plainWriter = Values } }, powerSlotCount = 1,
}
groupOwner._msufTextRuntime = { healthSlots = { groupSlot }, healthSlotCount = 1 }
castOwner.timeText, swingOwner.Time = Font(castOwner, "12.0"), Font(swingOwner, "0.6")
local classTextFrame = Owner({})
function classTextFrame:IsVisible() return true end
function classTextFrame:IsObjectType(kind) return kind == "Frame" end
function classTextFrame:GetChildren() end
local classText = Font(classTextFrame, "3")
function classTextFrame:GetRegions() return classText, unpack(self.copies or {}) end
local gradient = { enabled = true, left = true, up = true }
local function GradientRegion()
    local region = { shown = true, CreateAnimationGroup = health.fill.CreateAnimationGroup }
    function region:IsShown() return self.shown end
    function region:IsForbidden() return false end
    function region:SetAlpha(alpha) self.alpha = alpha end
    return region
end
local left, up = GradientRegion(), GradientRegion()
ufOwner.MSUFSpec = { health = { mode = "gradient", barGradient = gradient } }
ufOwner.hpGradients = { left = left, up = up }
health.fill.privateColor = Secrets.New("number")
local privateAlpha = Secrets.New("number")
health.fill.GetAlpha = function() return privateAlpha end
local gradientCopy
local common = {
    PreviewHealthGradientColor = function(spec, progress)
        assert(spec == ufOwner.MSUFSpec.health or spec == nil)
        return 1 - progress, progress, 0
    end,
    ApplyBarGradient = function(owner, overlay, spec, key)
        assert(owner ~= ufOwner and overlay == health.overlay and spec == gradient and key == "gradients")
        if not owner[key] then owner[key] = { left = GradientRegion(), up = GradientRegion() } end
        local copy = owner[key]
        copy.left.shown, copy.up.shown = spec.enabled and spec.left, spec.enabled and spec.up
        gradientCopy = copy
        return copy
    end,
}
MSUF_NS = {
    UFBarTextCommon = common,
    UF = { ForEachFrame = function(fn, a, b, c)
        visits = visits + 1
        fn(ufOwner, nil, a, b, c)
        fn(Owner({ Health = secretBar, Power = hidden }), nil, a, b, c)
    end },
    GF = { ForEachFrame = function(fn, _, a, b)
        fn(groupOwner, "party1", "party", a, b)
    end },
    PublicGlobals = { MSUF_BossCastbars = { castOwner } },
}
MSUF_ClassPowerContainer = Owner({ GetChildren = function() return class, classTextFrame end })
MSUF_SwingTimer_main = swingOwner

Load("MSUF_Suite/Core/HostBridge.lua", Suite)
local bridge = Load("MSUF_Suite/Core/HostBridgeBars.lua", Suite)
local renderText = Load("MSUF_Suite/Core/DevBarAnimationText.lua", Suite)
local feature = Load("MSUF_Suite/Core/DevBarAnimation.lua", Suite)
local A = Suite.DevBarAnimation
assert(creates == 0 and visits == 0 and not A.IsRunning())
assert(not A.IsTextEnabled())
A.SetTextEnabled(true)
assert(A.IsTextEnabled() and creates == 0 and visits == 0, "text preference started background work")
A.SetTextEnabled(false)
assert(not A.Start(nil) and creates == 0, "invalid input armed an undetachable driver")
fighting = true
assert(not A.Start("health") and creates == 0 and visits == 0, "combat start performed discovery")
fighting = false
local stopWatching = Secrets.Watch({ bridge, feature, renderText }, { strict = true })
assert(A.Start("health"))
assert(health.fill.playing and group.fill.playing and not power.overlay)
assert(health.overlay.r == 1 and health.overlay.g == 0 and group.overlay.r == 0.1)
assert(left.playing and up.playing and gradientCopy.left.shown and gradientCopy.up.shown)
assert(rawequal(gradientCopy.left.alpha, privateAlpha), "protected gradient opacity was changed")
assert(not (secretBar.fill.playing or hidden.overlay), "hidden or secret bar was animated")
assert(health.overlay.orientation == "VERTICAL" and health.overlay.reverse)
local update = driver.scripts.OnUpdate
update(driver, 0.125)
assert(health.overlay.r < 1 and health.overlay.g > 0, "health tint only refreshed with discovery")
update(driver, 1.375)
assert(health.overlay.r == 0 and health.overlay.g == 1)
assert(health.overlay.value == 1 and health.fill.playing, "bar did not fill to 100%")
gradient.up = false
update(driver, 0.25)
assert(left.playing and not up.playing and not gradientCopy.up.shown, "removed gradient direction stayed muted")
health.live = 72
update(driver, 1.25)
assert(health.overlay.value == 0 and health.live == 72, "bar did not empty independently of live value")
assert(A.Start("health", true))
assert(health.overlay.shown and not group.overlay.shown)
update(driver, 3)
assert(group.overlay.shown and not health.overlay.shown, "sequential mode did not advance")
assert(not left.playing, "sequence kept the prior bar gradient muted")
assert(not ufOwner.copies, "fill-only mode touched text")
assert(A.Start("all") and class.fill.playing and cast.fill.playing and swing.fill.playing)
A.SetTextEnabled(true)
update(driver, 0)
assert(healthText.playing and groupText.playing and powerText.playing and secretText.playing)
assert(groupOwner.copies[1].text == "0/100000 0%", "secret maximum did not use demo units")
local sample = ufOwner.copies[1]
local safeStyleSample = ufOwner.copies[2]
assert(sample.demoFont == "font" and sample.demoAnchor == ufOwner)
assert(safeStyleSample.demoFont == "GameFontHighlightSmall", "private font lost the readable demo fallback")
local castSample, swingSample = castOwner.copies[1], swingOwner.copies[1]
assert(sample.text == "0/500 0%" and castSample.text == "1.5" and swingSample.text == "0.0")
update(driver, 0.075)
assert(sample.text == "25/500 5%", "text did not move between discovery passes")
update(driver, 1.425)
assert(sample.text == "500/500 100%" and castSample.text == "0.0" and swingSample.text == "1.5")
assert(classText.playing and classTextFrame.copies[1].text == "500")
local newTextLayer = Owner({})
healthText.parent = newTextLayer
update(driver, 0.25)
assert(sample.parent == newTextLayer, "demo text lost its live text layer")
healthText.text = "320" -- the live painter can change text while muted
A.SetTextEnabled(false)
assert(not sample.shown and not healthText.playing and healthText.text == "320" and health.overlay.shown)
A.SetTextEnabled(true)
update(driver, 1.25)
assert(sample.text == "0/500 0%" and healthText.playing and hpSlot.fs == healthText)
assert(power.fill.playing)
cast.shown = false
update(driver, 0.3)
assert(not cast.fill.playing and not cast.overlay.shown, "hidden cast bar retained the overlay")
cast.shown = true
update(driver, 0.3)
assert(cast.fill.playing, "newly shown cast bar was not discovered")
-- Early combat event delivered while InCombatLockdown is still false.
driver.events.PLAYER_REGEN_DISABLED(driver, "PLAYER_REGEN_DISABLED")
assert(not A.IsRunning() and next(driver.events) == nil and driver.scripts.OnUpdate == nil)
assert(not left.playing and not up.playing, "combat retained muted gradient layers")
assert(not sample.shown and not healthText.playing and not swingOwner.Time.playing, "combat retained demo text")
A.SetTextEnabled(false)
for _, bar in ipairs({ health, group, power, class, cast, swing }) do
    assert(not bar.fill.playing and not bar.overlay.shown)
end
assert(A.Start("swing"))
fighting = true -- forced combat can start without an ordinary regen event
update(driver, 0.01)
assert(not A.IsRunning() and not swing.overlay.shown and not swing.fill.playing)
assert(next(driver.events) == nil and driver.scripts.OnUpdate == nil)
fighting = false
MSUF_NS.PublicGlobals.MSUF_UnitPreviewActive = true
assert(not A.Start("all") and not A.IsRunning())
MSUF_NS.PublicGlobals.MSUF_UnitPreviewActive = false
assert(A.Start("swing"))
A.Stop()
assert(not A.IsRunning() and next(driver.events) == nil and driver.scripts.OnUpdate == nil)
local violations = stopWatching()
assert(#violations == 0, table.concat(violations, "\n"))
print("Live unit-frame bar animation, category/sequence, secret guards and inactive lifecycle passed")


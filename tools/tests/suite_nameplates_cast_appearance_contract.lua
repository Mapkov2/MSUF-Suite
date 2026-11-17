local root = ...
local secret = {}
local combat = false
local function Public(value) return value ~= secret end
local namespace = {
    Public = Public,
    AnchorPoints = {},
    Finite = function(value) return Public(value) and type(value) == "number" end,
    InCombat = function() return combat end,
    Safety = { IsForbidden = function(region) return region.forbidden end },
    RGB = function(hex)
        assert(hex == "ffffff")
        return 1, 1, 1
    end,
}

-- Resize cost meter: permission and secret guards, client reads and client
-- writes. Counting is passive, so it leaves every modelled result unchanged.
local meter = { guards = 0, reads = 0, writes = 0 }
local metered = setmetatable({}, { __mode = "k" })
local function Count(kind, call)
    local function counted(...)
        meter[kind] = meter[kind] + 1
        return call(...)
    end
    metered[counted] = true
    return counted
end
local function Meter(object)
    for name, call in pairs(object) do
        if type(call) == "function" and not metered[call] then
            local kind = (name == "CanBeAccessedInContext" or name == "IsProtected") and "guards"
                or (name:find("^Get") or name:find("^Is")) and "reads"
                or (name:find("^Set") or name:find("^Clear") or name:find("^Create")
                    or name == "Show" or name == "Hide") and "writes"
            if kind then object[name] = Count(kind, call) end
        end
    end
    return object
end
for _, name in ipairs({ "Public", "Finite", "InCombat" }) do namespace[name] = Count("guards", namespace[name]) end
namespace.Safety.IsForbidden = Count("guards", namespace.Safety.IsForbidden)

function hooksecurefunc(frame, method, hook)
    local original = assert(frame[method])
    frame[method] = function(self, ...)
        original(self, ...)
        hook(self, ...)
    end
end

NamePlateSetupOptions = { spellNameInsideCastBar = false }
PixelUtil = { GetNearestPixelSize = function(width, scale, min)
    assert(scale == .8 and min == 1)
    return width + .125
end }

local function Region(alpha)
    local region = { alpha = alpha or 1, shown = true, points = {}, tintWrites = 0 }
    function region:CanBeAccessedInContext() return not self.locked end
    function region:GetAlpha() return self.alpha end
    function region:SetAlpha(value) self.alpha = value end
    function region:Hide() self.shown = false end
    function region:Show() self.shown = true end
    function region:IsShown() return self.shown end
    function region:SetShown(shown) self.shown = shown end
    function region:SetDrawLayer(layer, sublevel) self.layer, self.sublevel = layer, sublevel end
    function region:SetColorTexture(r, g, b, a) self.color = { r, g, b, a } end
    function region:SetVertexColor(r, g, b, a)
        self.vertex = { r, g, b, a }
        self.tintWrites = self.tintWrites + 1
    end
    function region:SetVertexColorFromBoolean(value, on, off)
        assert(value == secret)
        local color = self.secretTarget and on or off
        self:SetVertexColor(color.r, color.g, color.b, color.a)
    end
    function region:ClearAllPoints() self.points = {} end
    function region:SetPoint(...) self.points[#self.points + 1] = { ... } end
    function region:SetAllPoints(anchor) self.allPoints = anchor end
    function region:SetSize(width, height) self.width, self.height = width, height end
    function region:SetWidth(width) self.width = width end
    function region:SetHeight(height) self.height = height end
    -- veiled: the client withholds the region's height and keeps it unchanged.
    function region:GetHeight()
        if self.veiled then return secret end
        return self.height
    end
    function region:SetTexture(texture) self.texture = texture end
    function region:SetTexCoord(...) self.coords = { ... } end
    function region:SetDesaturated(value) self.desaturated = value end
    function region:SetBlendMode(mode) self.blend = mode end
    return Meter(region)
end

function CreateColor(r, g, b, a) return { r = r, g = g, b = b, a = a } end

local function GiveTargetWarning(cast)
    cast.CastTargetIndicator = Region(.9)
    function cast:SetIsHighlightedCastTarget(targeted) self.CastTargetIndicator:SetShown(targeted) end
    function cast:GetIsHighlightedCastTarget() return self.CastTargetIndicator:IsShown() end
end

local function Animation(order, duration)
    local animation = { order = order, duration = duration }
    function animation:GetOrder() return self.order end
    function animation:GetDuration() return self.duration end
    function animation:SetOrder(value) self.order = value end
    function animation:SetDuration(value) self.duration = value end
    function animation:SetOffset(x, y) self.offset = { x, y } end
    return animation
end

local function Group(parent)
    local group = { parent = parent, animations = {}, hooks = {}, plays = 0 }
    function group:GetParent() return self.parent end
    function group:GetAnimations() return unpack(self.animations) end
    function group:IsPlaying() return self.playing == true end
    function group:Play() self.playing, self.plays = true, self.plays + 1 end
    function group:Stop() self.playing = false end
    function group:HookScript(script, hook) self.hooks[script] = hook end
    function group:Finish()
        self.playing = false
        self.hooks.OnFinished(self)
    end
    function group:CreateAnimation(kind)
        assert(kind == "Translation")
        local animation = Animation()
        self.animations[#self.animations + 1] = animation
        return animation
    end
    return group
end

-- The resize observer: an unnamed child of the castbar that covers it. Only
-- its OnSizeChanged may be set, and a castbar gets one child for its lifetime.
function CreateFrame(kind, name, parent)
    assert(kind == "Frame" and name == nil, "the resize observer is an unnamed plain frame")
    assert(parent and not parent.observer, "a castbar received a second resize observer")
    local child = { parent = parent, scripts = {}, attached = 0, detached = 0 }
    function child:SetAllPoints(anchor) self.allPoints = anchor end
    function child:SetScript(script, handler)
        assert(script == "OnSizeChanged", "the observer carries a size script only")
        if handler then self.attached = self.attached + 1 else self.detached = self.detached + 1 end
        self.scripts[script] = handler
    end
    parent.observer = child
    return child
end

-- The effective visibility of a castbar: its own shown state and every
-- parent's. The client reports a change through OnShow and OnHide.
local function SetVisible(frame, visible)
    frame.visible = visible
    local hook = rawget(frame.hooks, visible and "OnShow" or "OnHide")
    if hook then hook(frame) end
end
local function Observed(frame)
    return frame.observer and frame.observer.scripts.OnSizeChanged
end

local function Cast()
    local cast = { Border = Region(.72), Spark = Region(.81), Text = Region(), fill = Region(), visible = true,
        created = {}, hooks = {}, classicStyleCastBar = true, reverse = false, width = 160, height = 9 }
    -- hooks.OnSizeChanged is the client's size callback. It only exists on the
    -- observer, and the model delivers it whenever that script is set, also to
    -- a hidden castbar: only a detached script keeps an idle bar silent.
    local function Deliver(_, ...)
        local script = Observed(cast)
        if script then script(cast.observer, ...) end
    end
    setmetatable(cast.hooks, { __index = function(_, script)
        if script == "OnSizeChanged" then return Deliver end
    end })
    local border = cast.Border
    border.alphaReads, border.alphaWrites, border.accessChecks = 0, 0, 0
    function border:GetAlpha()
        self.alphaReads = self.alphaReads + 1
        if self.veiled then return secret end
        return self.alpha
    end
    function border:CanBeAccessedInContext()
        self.accessChecks = self.accessChecks + 1
        return not self.locked
    end
    function border:SetAlpha(value)
        if self.rejectWrite then error("rejected alpha write") end
        self.alphaWrites, self.alpha = self.alphaWrites + 1, value
    end
    cast.Spark.height = 12
    cast.HoldFadeOutAnim = Group(cast)
    cast.HoldFadeOutAnim.animations = { Animation(2, .3), Animation(1, 1) }
    function cast:CanBeAccessedInContext() return not self.locked end
    function cast:IsProtected() return self.protected == true end
    function cast:GetStatusBarTexture() return self.fill end
    -- Every styled spark paint starts with this read, so it counts them.
    function cast:GetReverseFill()
        self.sparkPaints = (self.sparkPaints or 0) + 1
        return self.reverse
    end
    function cast:SetReverseFill(reversed) self.reverse = reversed end
    function cast:GetEffectiveScale() return .8 end
    function cast:GetHeight() return self.height end
    function cast:GetWidth() return self.width end
    function cast:GetSize() return self.width, self.height end
    function cast:HookScript(script, hook)
        assert(script == "OnShow" or script == "OnHide", "the native castbar received a script hook: " .. script)
        assert(not rawget(self.hooks, script), "a native script was hooked twice: " .. script)
        self.hooks[script] = hook
    end
    -- veiledShown: the client withholds the visibility and keeps it unchanged.
    function cast:IsVisible()
        if self.veiledShown then return secret end
        return self.visible
    end
    function cast:CreateTexture(_, layer, _, sublevel)
        local texture = Region()
        texture.layer, texture.sublevel = layer, sublevel
        self.created[#self.created + 1] = texture
        return texture
    end
    function cast:ShowSpark() self.Spark:Show() end
    function cast:HideSpark() self.Spark:Hide() end
    function cast:IsShown() return true end
    function cast:PlayInterruptAnims() self.HoldFadeOutAnim:Play() end
    function cast:StopInterruptAnims() self.HoldFadeOutAnim:Stop() end
    function cast:CreateAnimationGroup()
        self.shake = Group(self)
        return self.shake
    end
    function cast:HandleCastStart(empowered)
        self:ShowSpark()
        self.reverseChanneling = empowered
        self:StopInterruptAnims()
    end
    function cast:SetStatusBarTexture(texture) self.fill = texture end
    function cast:SetNameTextShown(shown) self.Text:SetShown(shown) end
    Meter(border)
    return Meter(cast)
end

assert(loadfile(root .. "/MSUF_Suite/Core/NameplateStyle.lua"))("Test", namespace)
local private = { NS = namespace }
-- The combat-end owner (Textures.DeferCast): how often a castbar asked for it.
local owed = setmetatable({}, { __mode = "k" })
private.Textures = { DeferCast = function(frame) owed[frame] = (owed[frame] or 0) + 1 end }
assert(loadfile((arg and arg[2]) or root .. "/MSUF_Suite_Nameplates/CastAppearance.lua"))("Test", private)
assert(loadfile(root .. "/MSUF_Suite_Nameplates/CastOutline.lua"))("Test", private)
local appearance = assert(private.CastAppearance)

-- Spark geometry of a castbar, counted passively: reads of the cast's height
-- (cast), of its width (width) and of Blizzard's spark height (spark), and
-- size writes to Blizzard's spark or the substitute (writes).
local function SparkGeometry(frame)
    local geo = { cast = 0, width = 0, spark = 0, writes = 0 }
    local function Counted(object, name, field)
        local call = object[name]
        object[name] = function(...)
            geo[field] = geo[field] + 1
            return call(...)
        end
    end
    Counted(frame, "GetHeight", "cast")
    Counted(frame, "GetSize", "cast")
    Counted(frame, "GetWidth", "width")
    Counted(frame.Spark, "GetHeight", "spark")
    Counted(frame.Spark, "SetHeight", "writes")
    Counted(frame.Spark, "SetSize", "writes")
    -- The substitute spark is the one OVERLAY texture at sublevel 6, whether
    -- it exists already or is created later.
    for _, texture in ipairs(frame.created) do
        if texture.layer == "OVERLAY" and texture.sublevel == 6 then Counted(texture, "SetSize", "writes") end
    end
    local create = frame.CreateTexture
    function frame:CreateTexture(name, layer, inherits, sublevel)
        local texture = create(self, name, layer, inherits, sublevel)
        if layer == "OVERLAY" and sublevel == 6 then Counted(texture, "SetSize", "writes") end
        return texture
    end
    function geo:Reset() self.cast, self.width, self.spark, self.writes = 0, 0, 0, 0 end
    -- Everything of the spark: the panel's width is the artwork's own axis.
    function geo:Sparks() return self.cast + self.spark + self.writes end
    return geo
end
local cast = Cast()
local settings = { outlineSize = 3, outlineR = .2, outlineG = .4, outlineB = .7, outlineA = .37,
    showSpark = true, sparkOverflow = true, reverseFill = true, artwork = true, artworkNamePanel = true }

cast.protected, combat = true, true
assert(not appearance.Apply(cast, settings))
assert(#cast.created == 0 and cast.Border.alpha == .72 and cast.Spark.alpha == .81 and not cast.reverse)
combat = false
assert(appearance.Apply(cast, settings))
assert(#cast.created == 7, "a full style creates four edges, two art textures and one spark")
local edge, art, panel, spark = cast.created[1], cast.created[5], cast.created[6], cast.created[7]
assert(edge.shown and edge.height == 3.125 and edge.points[1][4] == -3.125)
assert(edge.layer == "ARTWORK" and edge.vertex[1] == .2 and edge.vertex[2] == .4)
assert(edge.vertex[3] == .7 and edge.vertex[4] == .37)
assert(cast.Border.shown and cast.Border.alpha == 0, "Classic art must hide without changing native shown state")
assert(cast.Spark.shown and cast.Spark.alpha == 0 and cast.reverse)
assert(spark.shown and spark.points[1][2] == cast.fill and spark.points[1][3] == "LEFT")
assert(spark.height == cast.height * 2.1 and spark.texture == 4417031)
assert(art.shown and art.allPoints == cast and art.texture:find("CastFrame.tga", 1, true))
assert(not panel.shown, "the Classic spell name is always inside its castbar")
cast.classicStyleCastBar = false
assert(appearance.Apply(cast, settings) and cast.Border.alpha == 0)
assert(panel.shown and panel.points[1][2] == cast.Text and panel.texture:find("CastName.tga", 1, true))
cast.width, cast.height = 145, 11
cast.hooks.OnSizeChanged(cast)
assert(panel.width == 145 and spark.height == 9 * 2.1, "a size callback moved the panel's width only, never the spark")
appearance.OnLayout(cast)
assert(panel.width == 145 and spark.height == 11 * 2.1, "layout changes resize the native cast visuals")

assert(appearance.Apply(cast, settings) and #cast.created == 7 and edge.tintWrites == 1)
cast:SetNameTextShown(false)
assert(not panel.shown)
cast:SetNameTextShown(true)
assert(panel.shown)
NamePlateSetupOptions.spellNameInsideCastBar = true
assert(appearance.Apply(cast, settings) and not panel.shown)
cast.classicStyleCastBar = true
assert(appearance.Apply(cast, settings) and cast.Border.alpha == 0)
cast.Border:Hide()
assert(appearance.Apply(cast, settings, true) and cast.Border.alpha == 0 and not cast.Border:IsShown())
cast.Border:Show()
assert(appearance.Apply(cast, settings, true) and cast.Border.alpha == 0 and cast.Border:IsShown())
assert(cast.Border.alphaWrites == 1,
    "an anchor reset rewrote an already suppressed border")
local borderChecks = cast.Border.accessChecks
assert(appearance.Apply(cast, settings) and cast.Border.accessChecks == borderChecks,
    "a paint outside the native layout reset checked an owned border")
cast.Border.alpha = .64
assert(appearance.Apply(cast, settings, true) and cast.Border.alpha == 0 and cast.Border.alphaWrites == 2,
    "a native layout reset brought back the castbar border")
cast.Border.alpha = .51
cast.Border.locked = true
assert(not appearance.Apply(cast, settings, true) and cast.Border.alphaReads == 4 and cast.Border.alpha == .51)
cast.Border.locked = false
cast.Border.veiled = true
assert(not appearance.Apply(cast, settings, true) and cast.Border.alphaWrites == 2)
cast.Border.veiled = false
assert(appearance.Apply(cast, settings, true) and cast.Border.alpha == 0 and cast.Border.alphaWrites == 3)

local newFill = Region()
cast:SetStatusBarTexture(newFill)
assert(spark.points[1][2] == newFill, "reattach after Blizzard swaps the fill region")
cast:HideSpark()
assert(not spark.shown)
cast.Spark.alpha = 1 -- A native or skin refresh can reset the alpha before ShowSpark.
cast:ShowSpark()
assert(spark.shown and cast.Spark.alpha == 0, "the reversed bar displayed two sparks after native ShowSpark")
cast:HandleCastStart(true)
assert(not spark.shown and not cast.reverse and cast.Spark.alpha == .81, "preserve the native empowered cursor")
cast:HandleCastStart(false)
assert(spark.shown and cast.reverse and cast.Spark.alpha == 0)
newFill.locked = true
cast:SetStatusBarTexture(newFill)
assert(not spark.shown and cast.Spark.alpha == 0, "do not display a spark on the wrong reverse edge")
newFill.locked = false

settings.outlineSize, settings.outlineA, settings.sparkOverflow, settings.reverseFill = 0, 0, false, false
assert(appearance.Apply(cast, settings))
assert(not edge.shown and cast.Border.alpha == 0 and cast.Spark.height == cast.height)
assert(not cast.reverse and not spark.shown and cast.Spark.alpha == .81, "normal direction must reuse Blizzard's spark")
settings.showSpark, settings.artwork = false, false
assert(appearance.Apply(cast, settings) and not spark.shown and not art.shown and not panel.shown)
cast:ShowSpark()
assert(cast.Spark:IsShown() and cast.Spark.alpha == 0 and cast.Spark.height == 12,
    "keep the Spark checkbox off across native restarts and restore Blizzard's height")

cast.locked = true
assert(not appearance.Restore(cast))
cast.locked = false
assert(appearance.Restore(cast) and cast.Border.alpha == .51 and cast.Spark.alpha == .81 and not cast.reverse)
cast:ShowSpark()
assert(not spark.shown and not edge.shown and cast.Spark.alpha == .81, "released hooks must be inert")

local modern = Cast()
modern.classicStyleCastBar = false
assert(appearance.Apply(modern, { showSpark = true, reverseFill = false }))
assert(#modern.created == 0 and modern.Spark.alpha == .81, "normal direction allocated a second spark")
GiveTargetWarning(modern)
assert(appearance.Apply(modern, { outlineSize = 1, outlineA = 0 }))
assert(modern.Border.alpha == 0 and modern.created[1].vertex[4] == 0,
    "the native decoration covered an explicitly transparent outline")
assert(modern.CastTargetIndicator.alpha == .9, "Blizzard mode lost its native cast target warning")
local targetOutline = { outlineSize = 1, outlineA = 0, targetHighlight = true }
assert(appearance.Apply(modern, targetOutline))
local targetEdge = modern.created[1]
assert(modern.CastTargetIndicator.alpha == 0 and #modern.created == 4 and targetEdge.vertex[1] == 1
    and targetEdge.vertex[4] == 1, "use just the rectangular red outline for a cast targeted at the player")
assert(modern.CastTargetIndicator:IsShown(), "Blizzard still drives the warning's native shown state")
local targetWrites = targetEdge.tintWrites
local targetReads = meter.reads
for _ = 1, 20 do modern:SetIsHighlightedCastTarget(true) end
assert(targetEdge.tintWrites == targetWrites and meter.reads == targetReads,
    "a repeated cast target must not read frame values or repaint")
modern:SetIsHighlightedCastTarget(false)
assert(targetEdge.vertex[4] == 0 and not modern.CastTargetIndicator:IsShown())
targetEdge.secretTarget = true
modern:SetIsHighlightedCastTarget(secret)
assert(targetEdge.vertex[1] == 1 and targetEdge.vertex[4] == 1)
local paintedBorder = namespace.NameplateStyle.PaintBorder
namespace.NameplateStyle.PaintBorder = function() error("a second secret event repainted outline geometry") end
targetEdge.secretTarget = false
modern:SetIsHighlightedCastTarget(secret)
namespace.NameplateStyle.PaintBorder = paintedBorder
assert(targetEdge.vertex[4] == 0, "a new secret signal still reaches the native color setter")
modern:SetIsHighlightedCastTarget(false)
assert(targetEdge.vertex[4] == 0, "the public color cache must be restored after a secret target")

modern.CastTargetIndicator:SetAlpha(.45)
assert(appearance.Apply(modern, targetOutline, true) and modern.CastTargetIndicator.alpha == 0)
targetOutline.outlineSize = 0
assert(appearance.Apply(modern, targetOutline) and not targetEdge.shown)
modern:SetIsHighlightedCastTarget(true)
assert(targetEdge.shown and targetEdge.vertex[1] == 1 and #modern.created == 4,
    "a warning must still fit the castbar with the normal outline turned off")
modern:SetIsHighlightedCastTarget(false)
assert(not targetEdge.shown)
assert(appearance.Apply(modern, { outlineSize = 0 }))
modern:SetIsHighlightedCastTarget(true)
assert(modern.CastTargetIndicator.alpha == .45 and not targetEdge.shown, "switching to Blizzard restores its warning")

local protectedTarget = Cast()
GiveTargetWarning(protectedTarget)
protectedTarget.protected = true
assert(appearance.Apply(protectedTarget, targetOutline) and protectedTarget.CastTargetIndicator.alpha == .9)
assert(appearance.Restore(protectedTarget))

local nativeOutline = Cast()
GiveTargetWarning(nativeOutline)
nativeOutline:SetIsHighlightedCastTarget(false)
assert(appearance.Apply(nativeOutline, { targetHighlight = true }))
assert(#nativeOutline.created == 0 and nativeOutline.Border.alpha == .72, "a standalone warning leaves the idle outline alone")
nativeOutline:SetIsHighlightedCastTarget(true)
assert(#nativeOutline.created == 4 and nativeOutline.CastTargetIndicator.alpha == 0)
assert(appearance.Restore(nativeOutline) and nativeOutline.CastTargetIndicator.alpha == .9)
nativeOutline:SetIsHighlightedCastTarget(false)
nativeOutline:SetIsHighlightedCastTarget(true)
assert(not nativeOutline.created[1].shown, "a released target hook must be inert across pooled casts")

modern.classicStyleCastBar = secret
assert(appearance.Apply(modern, { outlineSize = 0 }) and not modern.created[1].shown)
assert(modern.Border.alpha == 0, "the zero-thickness style showed Blizzard's normal border")
modern.classicStyleCastBar = false
modern.Border.locked = true
assert(not appearance.Restore(modern) and modern.Border.alpha == 0 and modern.Border.alphaWrites == 1)
modern.Border.locked = false
assert(appearance.Restore(modern) and modern.Border.alpha == .72 and modern.Border.alphaWrites == 2)
modern.Border.alpha = .41
local beforeRetry = modern.Border.alphaReads
modern.Border.locked = true
assert(not appearance.Apply(modern, { outlineSize = 0 }) and modern.Border.alphaWrites == 2)
modern.Border.locked = false
modern.Border.rejectWrite = true
local ok, failure = pcall(appearance.Apply, modern, { outlineSize = 0 })
assert(not ok and failure:find("rejected alpha write", 1, true))
modern.Border.rejectWrite = false
assert(appearance.Apply(modern, { outlineSize = 0 }) and modern.Border.alphaWrites == 3 and modern.Border.alpha == 0)
assert(modern.Border.alphaReads == beforeRetry + 2, "the failed write prevented recapturing the current public alpha")
assert(appearance.Restore(modern) and modern.Border.alphaWrites == 4 and modern.Border.alpha == .41)

local interrupted = Cast()
local holdGroup = interrupted.HoldFadeOutAnim
local fade, hold = holdGroup:GetAnimations()
local feedback = { interruptDuration = .5, interruptShake = true, shakeStrength = 11 }
SetVisible(interrupted, false)
local holdReads, getAnimations = 0, holdGroup.GetAnimations
function holdGroup:GetAnimations()
    holdReads = holdReads + 1
    return getAnimations(self)
end
assert(appearance.Apply(interrupted, feedback))
interrupted:StopInterruptAnims()
assert(appearance.Apply(interrupted, feedback, true) and appearance.Restore(interrupted))
assert(holdReads == 0 and hold.duration == 1 and not holdGroup.hooks.OnFinished,
    "an unseen castbar prepared or restored its interrupt animation")
assert(appearance.Apply(interrupted, feedback))
SetVisible(interrupted, true)
assert(holdReads == 1 and hold.duration == .5, "the first visible cast missed its interrupt duration")
assert(appearance.Apply(interrupted, feedback) and hold.duration == .5 and fade.duration == .3)
interrupted:PlayInterruptAnims()
local shake = interrupted.shake
assert(shake.plays == 1 and shake.animations[1].offset[1] == 5.5 and shake.animations[2].offset[1] == -11)
assert(shake.animations[3].offset[1] == 5.5 and shake.animations[3].duration == .05)
assert(appearance.Restore(interrupted) and hold.duration == .5 and not shake:IsPlaying())
holdGroup:Finish()
assert(hold.duration == 1 and fade.duration == .3, "release restores the native duration after an active hold")
feedback.interruptDuration = 0
assert(appearance.Apply(interrupted, feedback) and hold.duration == 0 and fade.duration == .3)
interrupted:HandleCastStart(true)
assert(hold.duration == 1, "empowered early release keeps Blizzard's native hold")
interrupted:HandleCastStart(false)
assert(hold.duration == 0)
feedback.shakeStrength = 0
assert(appearance.Apply(interrupted, feedback))
interrupted:PlayInterruptAnims()
assert(shake.plays == 1 and not shake:IsPlaying())

-- Custom feedback can outlive the hidden native cast: animate the visible
-- overlay with the shared shake, and never animate both bars.
local native, overlay = Cast(), Cast()
local custom = { interruptShake = true, shakeStrength = 8, customFeedback = true }
assert(appearance.Apply(native, custom))
native:PlayInterruptAnims()
local nativeShake = assert(native.shake)
SetVisible(native, false)
appearance.ShakeFeedback(native, overlay)
local feedbackShake = assert(overlay.shake)
assert(feedbackShake.plays == 1 and feedbackShake.animations[2].offset[1] == -8)
native:PlayInterruptAnims()
assert(not nativeShake:IsPlaying() and feedbackShake:IsPlaying(), "both interrupt surfaces were animated")
appearance.StopFeedback(native)
assert(not feedbackShake:IsPlaying())
custom.shakeStrength = 0
assert(appearance.Apply(native, custom))
appearance.ShakeFeedback(native, overlay)
assert(feedbackShake.plays == 1, "zero shake strength still animated the feedback")

local protectedInterrupt = Cast()
SetVisible(protectedInterrupt, false)
protectedInterrupt.protected = true
local protectedHold = protectedInterrupt.HoldFadeOutAnim.animations[2]
assert(appearance.Apply(protectedInterrupt, { interruptDuration = .7 }) and protectedHold.duration == .7)
combat = true
SetVisible(protectedInterrupt, true)
assert(protectedHold.duration == .7, "the first protected cast lost the prepared interrupt duration")
combat = false
assert(appearance.Restore(protectedInterrupt) and protectedHold.duration == 1)

local fading = Cast()
SetVisible(fading, false)
local group = fading.HoldFadeOutAnim
local fadingHold = group.animations[2]
assert(appearance.Apply(fading, { interruptDuration = .6 }))
group:Play()
SetVisible(fading, true)
assert(fadingHold.duration == 1, "the first show altered an active native fade")
SetVisible(fading, false)
group:Finish()
assert(fadingHold.duration == .6, "fade completion after hiding lost the custom duration")
assert(appearance.Restore(fading) and fadingHold.duration == 1)

-- Resize contract. A real layout change moves the cast, fires the client's
-- size callback and ends with the layout owner's handoff (OnLayout). The cast
-- width reaches the name panel through the callback, the cast height reaches
-- the spark through the handoff alone.
local function Resize(target, width, height)
    target.width, target.height = width, height
    target.hooks.OnSizeChanged(target, width, height)
    appearance.OnLayout(target)
end
-- The size callback alone, as plate movement and scaling deliver it during a
-- cast: no layout owner ran, so no handoff follows.
local function Motion(target, width, height)
    target.width, target.height = width, height
    target.hooks.OnSizeChanged(target, width, height)
end
local function ReversedStyle()
    return { outlineSize = 1, showSpark = true, sparkOverflow = true, reverseFill = true, artwork = true }
end
local function NativeStyle()
    return { outlineSize = 1, showSpark = true, reverseFill = false, artwork = true }
end
local function Styled(style, width, height)
    local styled = Cast()
    styled.classicStyleCastBar = false
    if width then styled.width, styled.height = width, height end
    return styled, appearance.Apply(styled, style)
end

-- A substitute spark on the reversed edge and the name panel under the bar.
NamePlateSetupOptions.spellNameInsideCastBar = false
local reversedStyle = ReversedStyle()
local own, applied = Styled(reversedStyle)
local ownPanel, ownSpark = own.created[6], own.created[7]
assert(applied and #own.created == 7 and ownSpark.shown and ownSpark.height == 9 * 2.1)
assert(ownPanel.shown and ownPanel.width == 160)
Resize(own, 150, 9)
assert(ownPanel.width == 150 and ownSpark.height == 9 * 2.1, "a width change must reach the name panel")
Resize(own, 150, 12)
assert(ownPanel.width == 150 and ownSpark.height == 12 * 2.1, "a height change must reach the spark")
Resize(own, 150, 1)
assert(ownSpark.height == 4, "the overflowing spark keeps its minimum height")
Resize(own, 150, 12)

-- A blocked write is repeated by the next callback, including one for the same size.
own.locked = true
Resize(own, 140, 10)
assert(ownPanel.width == 150 and ownSpark.height == 12 * 2.1, "an inaccessible castbar was written")
own.locked = false
Resize(own, 140, 10)
assert(ownPanel.width == 140 and ownSpark.height == 10 * 2.1, "a blocked resize was remembered as applied")
own.protected, combat = true, true
Resize(own, 150, 12)
assert(ownPanel.width == 140 and ownSpark.height == 10 * 2.1, "a protected castbar was written in combat")
combat = false
Resize(own, 150, 12)
assert(ownPanel.width == 150 and ownSpark.height == 12 * 2.1, "a combat resize was lost")
own.protected = false

-- Secret dimensions are never kept. The public size afterwards repaints.
own.width = secret
own.hooks.OnSizeChanged(own, secret, 12)
assert(not ownPanel.shown and ownSpark.height == 12 * 2.1, "a secret width sized the name panel")
Resize(own, 150, 12)
assert(ownPanel.shown and ownPanel.width == 150, "the public width after a secret one was skipped")
own.height = secret
own.hooks.OnSizeChanged(own, 150, secret)
assert(ownSpark.shown and ownSpark.height == 12 * 2.1, "a size callback touched the spark")
appearance.OnLayout(own)
assert(not ownSpark.shown and own.Spark.alpha == 0, "a secret height left a spark of unknown size")
Resize(own, 150, 12)
assert(ownSpark.shown and ownSpark.height == 12 * 2.1 and own.Spark.alpha == 0)

-- Callers that omit the size, and callbacks older than the current layout.
own.width, own.height = 140, 10
own.hooks.OnSizeChanged(own)
assert(ownPanel.width == 140 and ownSpark.height == 12 * 2.1, "a callback without size arguments missed the panel or sized the spark")
appearance.OnLayout(own)
assert(ownPanel.width == 140 and ownSpark.height == 10 * 2.1, "a caller without size arguments was ignored")
own.width, own.height = 150, 12
own.hooks.OnSizeChanged(own, 145, 11)
assert(ownPanel.width == 150 and ownSpark.height == 10 * 2.1, "an outdated callback overwrote the current width or sized the spark")
appearance.OnLayout(own)
assert(ownPanel.width == 150 and ownSpark.height == 12 * 2.1, "an outdated callback overwrote the current size")

-- Spell name visibility arrives through Blizzard's SetNameTextShown.
own:SetNameTextShown(false)
Resize(own, 170, 12)
assert(not ownPanel.shown, "a resize displayed the panel of a hidden spell name")
own:SetNameTextShown(true)
assert(ownPanel.shown and ownPanel.width == 170, "the panel missed the width it received while hidden")
own.Text.locked = true
own:SetNameTextShown(true)
assert(not ownPanel.shown)
own.Text.locked = false
Resize(own, 170, 12)
assert(ownPanel.shown and ownPanel.width == 170, "an inaccessible spell name was remembered as a painted panel")

-- Interrupts and finished casts hide the native spark. The next cast shows it.
own:HideSpark()
Resize(own, 170, 14)
assert(not ownSpark.shown, "a resize displayed the spark of a stopped cast")
own:ShowSpark()
assert(ownSpark.shown and ownSpark.height == 14 * 2.1 and own.Spark.alpha == 0)

-- Empowered casts keep Blizzard's cursor at Blizzard's size.
own:HandleCastStart(true)
Resize(own, 170, 16)
assert(not ownSpark.shown and not own.reverse and own.Spark.alpha == .81 and own.Spark.height == 12,
    "a resize modified the native empowered cursor")
own:HandleCastStart(false)
assert(ownSpark.shown and own.reverse and ownSpark.height == 16 * 2.1 and own.Spark.alpha == 0)

-- A replaced fill region reattaches. A restricted one is retried.
local swapped = Region()
own:SetStatusBarTexture(swapped)
Resize(own, 170, 18)
assert(ownSpark.points[1][2] == swapped and ownSpark.shown and ownSpark.height == 18 * 2.1)
swapped.locked = true
own:SetStatusBarTexture(swapped)
Resize(own, 170, 18)
assert(not ownSpark.shown and own.Spark.alpha == 0)
swapped.locked = false
Resize(own, 170, 18)
assert(ownSpark.shown and ownSpark.height == 18 * 2.1, "a restricted fill region was remembered as a placed spark")

-- A collapsed bar has no spark and no panel until it has a size again.
Resize(own, 170, 0)
assert(not ownSpark.shown and own.Spark.alpha == 0)
Resize(own, 0, 0)
assert(not ownPanel.shown)
Resize(own, 170, 18)
assert(ownSpark.shown and ownSpark.height == 18 * 2.1 and ownPanel.shown and ownPanel.width == 170)

-- Settings changes arrive through Apply and size like a first paint.
reversedStyle.sparkOverflow = false
assert(appearance.Apply(own, reversedStyle) and ownSpark.height == 18)
Resize(own, 170, 20)
assert(ownSpark.height == 20)
reversedStyle.reverseFill = false
assert(appearance.Apply(own, reversedStyle) and not ownSpark.shown and not own.reverse)
assert(own.Spark.alpha == .81 and own.Spark.height == 20)
Resize(own, 170, 22)
assert(own.Spark.height == 22 and not ownSpark.shown, "the native spark missed a height change")
reversedStyle.showSpark = false
assert(appearance.Apply(own, reversedStyle) and own.Spark.alpha == 0 and own.Spark.height == 12)
Resize(own, 170, 24)
assert(own.Spark.height == 12 and own.Spark.alpha == 0 and not ownSpark.shown)
reversedStyle.artwork = false
assert(appearance.Apply(own, reversedStyle) and not ownPanel.shown)
Resize(own, 180, 24)
assert(not ownPanel.shown and ownPanel.width == 170, "a disabled name panel was resized")

-- A released bar is inert. Reuse sizes for the layout it then has.
assert(appearance.Restore(own) and own.Spark.alpha == .81 and own.Spark.height == 12)
Resize(own, 120, 8)
assert(own.Spark.height == 12 and own.Spark.alpha == .81 and not ownSpark.shown and not ownPanel.shown)
assert(appearance.Apply(own, ReversedStyle()))
assert(ownSpark.shown and ownSpark.height == 8 * 2.1 and ownPanel.shown and ownPanel.width == 120)

-- First render: the style can arrive before Blizzard has laid the bar out.
local early = Styled(ReversedStyle(), 0, 0)
Resize(early, 160, 9)
assert(early.created[7].shown and early.created[7].height == 9 * 2.1)
assert(early.created[6].shown and early.created[6].width == 160, "the first layout after an early style was skipped")

-- Blizzard's own spark in normal fill direction.
local native = Styled(NativeStyle())
local nativePanel = native.created[6]
assert(#native.created == 6 and native.Spark.height == 9 * 2.1 and native.Spark.alpha == .81)
Resize(native, 150, 9)
assert(nativePanel.width == 150 and native.Spark.height == 9 * 2.1)
Resize(native, 150, 10)
assert(native.Spark.height == 10 * 2.1 and nativePanel.width == 150 and #native.created == 6)
native.Spark.locked = true
Resize(native, 150, 11)
assert(native.Spark.height == 10 * 2.1, "an inaccessible native spark was written")
native.Spark.locked = false
Resize(native, 150, 11)
assert(native.Spark.height == 11 * 2.1, "a blocked native spark height was remembered as applied")
native.height = secret
native.hooks.OnSizeChanged(native, 150, secret)
assert(native.Spark.height == 11 * 2.1, "a size callback touched Blizzard's spark")
appearance.OnLayout(native)
assert(native.Spark.height == 12, "a secret height must fall back to Blizzard's spark height")
Resize(native, 150, 11)
assert(native.Spark.height == 11 * 2.1)
Resize(native, 150, 0)
assert(native.Spark.height == 12, "a collapsed bar must fall back to Blizzard's spark height")
Resize(native, 150, 11)
assert(native.Spark.height == 11 * 2.1)
native.Spark.height = 14 -- Blizzard's layout chose another spark height.
Resize(native, 150, 10)
assert(native.Spark.height == 10 * 2.1)
assert(appearance.Restore(native) and native.Spark.height == 14, "release must return Blizzard's latest spark height")
local lateNative = Styled(NativeStyle(), 0, 0)
assert(lateNative.Spark.height == 12)
Resize(lateNative, 160, 9)
assert(lateNative.Spark.height == 9 * 2.1 and lateNative.created[6].shown and lateNative.created[6].width == 160)

-- Cost of the size callbacks in a raid: guards, client reads and client
-- writes. The budgets are the ones of the path that sized the spark from the
-- callback: they are ceilings now, and the spark's share of them is gone. No
-- callback moves a spark, whatever the cast's height does (asserted below).
local costs = {}
local function Cost(label, target, guards, reads, writes, size)
    local cost = { label = label, guards = -meter.guards, reads = -meter.reads, writes = -meter.writes,
        guardBudget = guards, readBudget = reads, writeBudget = writes }
    for step = 1, 100 do Motion(target, size(step)) end
    cost.guards, cost.reads, cost.writes = cost.guards + meter.guards, cost.reads + meter.reads, cost.writes + meter.writes
    costs[#costs + 1] = cost
end

local function CostAxes(label, target, guards, reads, writes)
    Cost(label .. ", unchanged size", target, 3, 0, 0, function() return 160, 9 end)
    Cost(label .. ", width only", target, guards[1], reads[1], writes[1], function(step) return 160 + step / 4, 9 end)
    Cost(label .. ", height only", target, guards[2], reads[2], writes[2], function(step) return 185, 9 + step / 4 end)
    Cost(label .. ", width and height", target, guards[3], reads[3], writes[3],
        function(step) return 185 + step, 34 + step end)
end

local raid = Styled(ReversedStyle())
local raidPanel, raidSpark = raid.created[6], raid.created[7]
local raidGeometry = SparkGeometry(raid)
CostAxes("substitute spark", raid, { 9, 9, 10 }, { 1, 1, 1 }, { 1, 1, 2 })
assert(raidGeometry:Sparks() == 0, "400 size callbacks read or wrote spark geometry on the reversed edge")
assert(raidPanel.shown and raidPanel.width == 285 and raidSpark.shown and raidSpark.height == 9 * 2.1,
    "a size callback missed the panel's width or sized the substitute spark")
appearance.OnLayout(raid)
assert(raidPanel.shown and raidPanel.width == 285 and raidSpark.shown and raidSpark.height == 134 * 2.1)
assert(raidGeometry.cast == 1 and raidGeometry.spark == 0 and raidGeometry.writes == 1,
    "the layout handoff is one height sample and one spark size")
assert(raidSpark.points[1][2] == raid.fill and raid.Spark.alpha == 0 and raid.reverse)

local raidNative = Styled(NativeStyle())
local nativeGeometry = SparkGeometry(raidNative)
CostAxes("native spark", raidNative, { 9, 14, 15 }, { 1, 2, 2 }, { 1, 1, 2 })
assert(nativeGeometry:Sparks() == 0, "400 size callbacks read or wrote Blizzard's spark geometry")
assert(raidNative.created[6].shown and raidNative.created[6].width == 285)
assert(raidNative.Spark.height == 9 * 2.1, "a size callback sized Blizzard's spark")
appearance.OnLayout(raidNative)
assert(raidNative.Spark.height == 134 * 2.1 and raidNative.Spark.alpha == .81 and #raidNative.created == 6)
assert(nativeGeometry.cast == 1 and nativeGeometry.spark == 1 and nativeGeometry.writes == 1)

combat = true
Cost("native spark, combat, width and height", raidNative, 17, 2, 2, function(step) return 285 + step, 134 + step end)
assert(raidNative.created[6].width == 385 and raidNative.Spark.height == 134 * 2.1)
appearance.OnLayout(raidNative)
assert(raidNative.created[6].width == 385 and raidNative.Spark.height == 234 * 2.1)
raidNative.protected = true
Cost("protected in combat, unchanged size", raidNative, 3, 0, 0, function() return 385, 234 end)
raidNative.protected, combat = false, false
assert(nativeGeometry.cast == 2, "combat size callbacks sampled the cast height")

raid:HandleCastStart(true)
Cost("empowered cast, height only", raid, 3, 0, 0, function(step) return 285, 134 + step end)
assert(not raidSpark.shown and raid.Spark.height == 12 and raid.Spark.alpha == .81)
raid:HandleCastStart(false)
assert(raidSpark.shown and raidSpark.height == 134 * 2.1, "a cast start sampled the cast height")
appearance.OnLayout(raid)
assert(raidSpark.shown and raidSpark.height == 234 * 2.1)
assert(raidGeometry.cast == 2, "the callbacks and cast starts of an empowered cast sampled the cast height")
raid:SetNameTextShown(false)
Cost("hidden spell name, width only", raid, 3, 0, 0, function(step) return 285 + step, 234 end)
assert(not raidPanel.shown)
raid:SetNameTextShown(true)
assert(raidPanel.shown and raidPanel.width == 385)

local sparkless = Styled({ showSpark = false, artwork = true })
Cost("hidden spark, height only", sparkless, 3, 0, 0, function(step) return 160, 9 + step end)
assert(sparkless.Spark.alpha == 0 and sparkless.Spark.height == 12 and sparkless.created[2].width == 160)

local classic = Cast()
assert(appearance.Apply(classic, ReversedStyle()))
Cost("classic bar without name panel, width only", classic, 3, 0, 0, function(step) return 160 + step, 9 end)
assert(not classic.created[6].shown and classic.created[7].shown and classic.created[7].height == 9 * 2.1)

-- The measured style has a visibility hook and no size observer.
for _, reverse in ipairs({ false, true }) do
    local stock = Styled({ showSpark = true, sparkOverflow = true, reverseFill = reverse })
    local stockGeometry = SparkGeometry(stock)
    assert(not stock.observer and rawget(stock.hooks, "OnShow"),
        "a spark without artwork needs only the visibility event")
    Cost("stock spark, reverse " .. tostring(reverse), stock, 0, 0, 0, function(step) return 160 + step, 9 + step end)
    assert(stockGeometry:Sparks() == 0 and stockGeometry.width == 0, "a stock spark had geometry read by a size callback")
    local sized = reverse and stock.created[1] or stock.Spark
    assert(sized.height == 9 * 2.1, "a size callback sized a stock spark")
    appearance.OnLayout(stock)
    assert(sized.height == 109 * 2.1 and stockGeometry.cast == 1, "a stock spark missed its layout handoff")
end

assert(appearance.Apply(raid, { outlineSize = 1 }))
-- Neither style needs a dimension: the observer is detached and no Lua runs.
Cost("spark and artwork disabled", raid, 0, 0, 0, function(step) return 385 + step, 234 + step end)
assert(not raidSpark.shown and not raidPanel.shown and raid.Spark.alpha == .81 and raid.Spark.height == 12)
assert(appearance.Restore(raid))
Cost("released to the native style", raid, 0, 0, 0, function(step) return 485 + step, 334 + step end)
assert(not raidSpark.shown and not raidPanel.shown and raid.Spark.alpha == .81 and raid.Spark.height == 12)

print("Castbar resize cost per 100 callbacks (budget in parentheses)")
for _, cost in ipairs(costs) do
    print(("  %-43s %4d (%4d) guards  %4d (%3d) reads  %4d (%3d) writes"):format(cost.label,
        cost.guards, cost.guardBudget * 100, cost.reads, cost.readBudget * 100, cost.writes, cost.writeBudget * 100))
end
for _, cost in ipairs(costs) do
    assert(cost.guards <= cost.guardBudget * 100 and cost.reads <= cost.readBudget * 100
        and cost.writes <= cost.writeBudget * 100, "resize budget missed: " .. cost.label)
end

do
    -- Size callbacks: a denied native change of the name panel stays open for
    -- the next callback, and a completed one costs no client call at stable
    -- bounds. A denied change of the spark waits for the next cast event or
    -- layout edge: no size callback repairs it.
    local function Resize(frame, ...)
        meter.guards, meter.reads, meter.writes = 0, 0, 0
        frame.hooks.OnSizeChanged(frame, ...)
        return meter.reads, meter.writes
    end
    NamePlateSetupOptions.spellNameInsideCastBar = false
    local resize = Cast()
    resize.classicStyleCastBar = false
    local resizeSettings = { artwork = true, showSpark = true, reverseFill = true }
    assert(appearance.Apply(resize, resizeSettings))
    local namePanel, ownSpark = assert(resize.created[2]), assert(resize.created[3])
    assert(namePanel.shown and ownSpark.shown and ownSpark.points[1][2] == resize.fill)
    local reads, writes = Resize(resize, resize.width, resize.height)
    assert(reads == 0 and writes == 0, "stable bounds touched the client")

    resize.locked = true
    resize:SetNameTextShown(false)
    local swappedFill = Region()
    resize:SetStatusBarTexture(swappedFill)
    assert(namePanel.shown and ownSpark.points[1][2] ~= swappedFill,"a denied native change wrote to the cast")
    resize.locked = false
    resize.width = resize.width + 1
    Resize(resize, resize.width, resize.height)
    assert(not namePanel.shown, "a denied SetNameTextShown was never repaired")
    assert(ownSpark.points[1][2] ~= swappedFill, "a size callback repainted the spark")
    assert(owed[resize] == 1, "a cast event denied at the castbar did not ask for the combat-end owner")
    resize:ShowSpark()
    assert(ownSpark.points[1][2] == swappedFill, "a denied SetStatusBarTexture was never repaired")
    reads, writes = Resize(resize, resize.width, resize.height)
    assert(reads == 0 and writes == 0, "a repaired cast kept working at stable bounds")

    -- A denied callback without dimensions and a denied layout Apply.
    resize.locked = true
    resize.Text:SetShown(false)
    Resize(resize)
    resize.locked = false
    Resize(resize, resize.width, resize.height)
    assert(not namePanel.shown, "a denied dimensionless callback was not retried")
    resize.locked = true
    resize.Text:SetShown(true)
    assert(not appearance.Apply(resize, resizeSettings, true) and not namePanel.shown)
    resize.locked = false
    Resize(resize, resize.width, resize.height)
    assert(namePanel.shown and namePanel.width == resize.width, "a denied Apply was not retried")
    -- The spark's half of that denied Apply: the layout edge it answered is
    -- sampled by the first cast event that may write, once.
    local resizeGeometry = SparkGeometry(resize)
    resize.height = resize.height + 2
    Resize(resize, resize.width, resize.height)
    assert(ownSpark.height == (resize.height - 2) * 2.1 and resizeGeometry:Sparks() == 0,
        "a size callback made up for a denied layout edge")
    resize:ShowSpark()
    assert(ownSpark.height == resize.height * 2.1 and resizeGeometry.cast == 1,
        "a denied Apply left the spark at the height before it")
    resize:ShowSpark()
    resize:HandleCastStart(false)
    assert(resizeGeometry.cast == 1 and resizeGeometry.writes == 1, "a repaired layout edge was sampled again by a cast event")

    -- The substitute spark could not follow a native hide.
    ownSpark.locked = true
    resize:HideSpark()
    assert(ownSpark.shown)
    ownSpark.locked = false
    Resize(resize, resize.width, resize.height)
    assert(ownSpark.shown, "a size callback repainted the spark")
    appearance.OnLayout(resize)
    assert(not ownSpark.shown, "a denied substitute hide left a spark without a cast")
    reads, writes = Resize(resize, resize.width, resize.height)
    assert(reads == 0 and writes == 0)
    resize:ShowSpark()
    assert(ownSpark.shown and resize.Spark.alpha == 0)

    -- Blizzard's spark: its layout resets the height (UpdateAnchors) while the
    -- castbar denies the Apply that answers it. The first cast event that may
    -- write restores the styled height, and the ones after it read nothing.
    local forward = Cast()
    forward.classicStyleCastBar = false
    local forwardStyle = { showSpark = true, reverseFill = false }
    assert(appearance.Apply(forward, forwardStyle))
    assert(#forward.created == 0 and forward.Spark.height == forward.height * 2.1)
    assert(not forward.observer, "a spark without artwork received a resize observer")
    local forwardGeometry = SparkGeometry(forward)
    forward.locked = true
    forward.Spark.height = 12
    assert(not appearance.Apply(forward, forwardStyle, true))
    forward:ShowSpark()
    assert(forward.Spark.height == 12 and forwardGeometry:Sparks() == 0, "an inaccessible castbar was read or written")
    forward.locked = false
    Resize(forward, forward.width, forward.height)
    assert(forward.Spark.height == 12 and forwardGeometry:Sparks() == 0, "a size callback reached a spark without artwork")
    forward:ShowSpark()
    assert(forward.Spark.height == forward.height * 2.1, "a denied layout reset kept Blizzard's reset spark height")
    assert(forwardGeometry.cast == 1 and forwardGeometry.spark == 1 and forwardGeometry.writes == 1)
    for _ = 1, 100 do
        forward:HideSpark()
        forward:HandleCastStart(false)
        forward:SetStatusBarTexture(Region())
        reads, writes = Resize(forward, forward.width, forward.height)
        assert(reads == 0 and writes == 0)
    end
    assert(forwardGeometry.cast == 1 and forwardGeometry.spark == 1 and forwardGeometry.writes == 1,
        "a repaired spark was read or written again by a cast event")
    assert(appearance.Restore(forward) and forward.Spark.height == 12, "release lost the baseline bound at the repair")
end

do
    -- Size callbacks whose dimensions are no public numbers, the dominant case
    -- of a measured raid. The argument and the cast's own size are each modelled
    -- as secret, missing or nonnumeric. The arguments are hints: the panel
    -- follows the cast's current width, read once per callback, and the spark
    -- follows the height of the layout handoff alone.
    NamePlateSetupOptions.spellNameInsideCastBar = false
    local rows = {}
    -- The size callback alone, as it arrives during a running cast.
    local function Hint(frame, ...) frame.hooks.OnSizeChanged(frame, ...) end
    -- A real layout change: the callback, then the layout owner's handoff.
    local function Call(frame, ...)
        Hint(frame, ...)
        appearance.OnLayout(frame)
    end
    -- 100 callbacks without a layout change. The budgets are the ones of the
    -- path that sized the spark from the callback, kept as ceilings.
    local function Repeat(label, frame, guards, reads, writes, ...)
        local row = { label = label, guards = -meter.guards, reads = -meter.reads, writes = -meter.writes,
            guardBudget = guards, readBudget = reads, writeBudget = writes }
        -- A function in place of the hints moves the cast and returns them.
        local change = type((...)) == "function" and (...)
        local geometry = SparkGeometry(frame)
        for step = 1, 100 do
            if change then Hint(frame, change(frame, step)) else Hint(frame, ...) end
        end
        assert(geometry:Sparks() == 0, "size callbacks read or wrote spark geometry: " .. label)
        row.guards, row.reads, row.writes = row.guards + meter.guards, row.reads + meter.reads, row.writes + meter.writes
        rows[#rows + 1] = row
    end
    local function Plate(style)
        local frame = Cast()
        frame.classicStyleCastBar = false
        assert(appearance.Apply(frame, style))
        return frame
    end
    local function Unkept(...)
        for index = 1, select("#", ...) do
            local region = select(index, ...)
            assert(region.width ~= secret and region.height ~= secret, "a secret dimension was written")
        end
    end

    -- Blizzard's spark in normal fill direction, the measured style.
    local forward = Plate(NativeStyle())
    local forwardPanel = forward.created[6]
    assert(forwardPanel.shown and forwardPanel.width == 160 and forward.Spark.height == 9 * 2.1)
    Repeat("native, secret width hint", forward, 9, 1, 0, secret, 9)
    Repeat("native, nonnumeric width hint", forward, 9, 1, 0, "160", 9)
    Repeat("native, secret height hint", forward, 10, 1, 0, 160, secret)
    Repeat("native, no size hints", forward, 9, 1, 0)
    combat = true
    Repeat("native, combat, secret hints", forward, 11, 1, 0, secret, secret)
    combat = false
    assert(forwardPanel.shown and forwardPanel.width == 160 and forward.Spark.height == 9 * 2.1)

    -- Geometry behind an unreadable hint still reaches both visuals.
    forward.width = 170
    Call(forward, secret, 9)
    assert(forwardPanel.width == 170, "a width change behind a secret width hint was lost")
    forward.height = 10
    Call(forward, secret, secret)
    assert(forward.Spark.height == 10 * 2.1, "a height change behind secret hints was lost")
    forward.width, forward.height = 180, 11
    Call(forward, "x", 11)
    assert(forwardPanel.width == 180 and forward.Spark.height == 11 * 2.1, "a nonnumeric width hint lost the resize")
    forward.height = 11.5
    Call(forward, 180, nil)
    assert(forward.Spark.height == 11.5 * 2.1, "a height change behind a missing height hint was lost")
    forward.height = 11
    Call(forward, nil, 11)
    assert(forward.Spark.height == 11 * 2.1)
    forward.protected, combat = true, true
    forward.width, forward.height = 190, 12
    Call(forward, secret, secret)
    assert(forwardPanel.width == 180 and forward.Spark.height == 11 * 2.1, "a protected castbar was written in combat")
    combat = false
    Call(forward, secret, secret)
    assert(forwardPanel.width == 190 and forward.Spark.height == 12 * 2.1, "a combat resize without hints was lost")
    forward.protected = false

    -- One unreadable hint voids the other: a public hint that still equals its
    -- fit is no evidence that its axis kept its size.
    forward.height = 13
    Call(forward, secret, 12)
    assert(forward.Spark.height == 13 * 2.1 and forwardPanel.width == 190,
        "a height change behind a secret width hint and the last known height was lost")
    forward.width = 195
    Call(forward, 190, secret)
    assert(forwardPanel.width == 195 and forward.Spark.height == 13 * 2.1,
        "a width change behind the last known width and a secret height hint was lost")
    forward.width, forward.height = 190, 12
    Call(forward, nil, 13)
    assert(forward.Spark.height == 12 * 2.1 and forwardPanel.width == 190, "a missing width hint kept a stale size")

    -- The cast's own width is withheld: one paint hides the panel, later
    -- callbacks only look whether the width is public again.
    forward.width = secret
    Call(forward, secret, 12)
    assert(not forwardPanel.shown and forwardPanel.width == 190, "an unreadable width kept or sized the name panel")
    Repeat("native, unreadable width", forward, 9, 1, 0, secret, 12)
    Repeat("native, unreadable width, public hint", forward, 9, 1, 0, 190, 12)
    assert(not forwardPanel.shown)
    -- The spell name and the anchors still repaint while the width is withheld.
    forward:SetNameTextShown(false)
    forward:SetNameTextShown(true)
    assert(not forwardPanel.shown)
    assert(appearance.Apply(forward, NativeStyle(), true) and not forwardPanel.shown)
    Repeat("native, unreadable width after Apply", forward, 9, 1, 0, secret, 12)
    forward.width = 150
    Call(forward, secret, 12)
    assert(forwardPanel.shown and forwardPanel.width == 150, "a width that became public was not painted")
    forward.width = secret
    Call(forward, secret, 12)
    forward.width = 155
    Call(forward, 155, 12)
    assert(forwardPanel.shown and forwardPanel.width == 155, "a public callback after an unreadable width was skipped")
    forward.width = secret
    Call(forward, secret, 12)
    forward:SetNameTextShown(false)
    forward.width = 156
    Call(forward, secret, 12)
    assert(not forwardPanel.shown, "a recovered width displayed the panel of a hidden spell name")
    Repeat("native, hidden spell name, secret hints", forward, 7, 1, 0, secret, secret)
    forward:SetNameTextShown(true)
    assert(forwardPanel.shown and forwardPanel.width == 156)

    -- A denied callback keeps nothing: neither the old fit nor the unreadable one.
    forward.width = secret
    Call(forward, secret, 12)
    forward.locked = true
    forward.width = 157
    Call(forward, secret, 12)
    assert(not forwardPanel.shown, "an inaccessible castbar was written")
    forward.locked = false
    Call(forward, secret, 12)
    assert(forwardPanel.shown and forwardPanel.width == 157, "a denied callback hid a recovered width")
    forward.locked = true
    forward.Text:SetShown(false) -- No native hook reports this one.
    Call(forward, secret, secret)
    forward.locked = false
    Call(forward, secret, secret)
    assert(not forwardPanel.shown, "a denied callback without hints was not retried")
    forward.Text:SetShown(true)
    forward:SetNameTextShown(true)
    assert(forwardPanel.shown and forwardPanel.width == 157)

    -- The cast's own height is withheld: Blizzard's spark keeps Blizzard's height.
    forward.height = secret
    Call(forward, 157, secret)
    assert(forward.Spark.height == 12 and forward.Spark.alpha == .81, "an unreadable height sized Blizzard's spark")
    Repeat("native, unreadable height", forward, 10, 1, 0, 157, secret)
    forward.width = secret
    Call(forward, secret, secret)
    Repeat("native, unreadable width and height", forward, 9, 1, 0, secret, secret)
    Repeat("native, unreadable size, no hints", forward, 9, 1, 0)
    forward.Spark.height = 14 -- Blizzard's layout chose another spark height.
    forward:ShowSpark()
    Call(forward, secret, secret)
    assert(forward.Spark.height == 14 and not forwardPanel.shown, "an unreadable height wrote Blizzard's spark")
    forward.width, forward.height = 160, 9
    Call(forward, secret, secret)
    assert(forward.Spark.height == 9 * 2.1 and forwardPanel.shown and forwardPanel.width == 160,
        "a size that became public was not painted")
    Repeat("native, recovered size, secret hints", forward, 9, 1, 0, secret, secret)
    -- A collapsed bar behind unreadable hints, and its size afterwards.
    forward.width, forward.height = 0, 0
    Call(forward, secret, secret)
    assert(not forwardPanel.shown and forward.Spark.height == 14, "a collapsed bar kept its panel or spark height")
    Repeat("native, collapsed, secret hints", forward, 9, 1, 0, secret, secret)
    forward.width, forward.height = 160, 9
    Call(forward, secret, secret)
    assert(forwardPanel.shown and forwardPanel.width == 160 and forward.Spark.height == 9 * 2.1)
    Unkept(forwardPanel, forward.Spark)
    -- Plate reuse: release while the size is withheld, style the next layout.
    forward.width, forward.height = secret, secret
    Call(forward, secret, secret)
    assert(appearance.Restore(forward) and forward.Spark.height == 14 and not forwardPanel.shown)
    Repeat("native, released, secret hints", forward, 0, 0, 0, secret, secret)
    forward.width, forward.height = 140, 8
    assert(appearance.Apply(forward, NativeStyle()))
    assert(forwardPanel.shown and forwardPanel.width == 140 and forward.Spark.height == 8 * 2.1)
    Repeat("native, reused plate, secret hints", forward, 9, 1, 0, secret, secret)

    -- The substitute spark on the reversed edge.
    local back = Plate(ReversedStyle())
    local backPanel, backSpark = back.created[6], back.created[7]
    assert(backSpark.shown and backSpark.height == 9 * 2.1 and back.Spark.alpha == 0 and back.reverse)
    Repeat("substitute, secret width hint", back, 9, 1, 0, secret, 9)
    Repeat("substitute, no size hints", back, 9, 1, 0)
    back.width, back.height = 170, 10
    Call(back, secret, secret)
    assert(backPanel.width == 170 and backSpark.height == 10 * 2.1 and backSpark.shown,
        "a size change behind secret hints was lost")
    back.height = 11
    Call(back, secret, 10)
    assert(backSpark.height == 11 * 2.1 and backPanel.width == 170,
        "a height change behind a secret width hint and the last known height was lost")
    back.width = 175
    Call(back, 170, secret)
    assert(backPanel.width == 175 and backSpark.height == 11 * 2.1,
        "a width change behind the last known width and a secret height hint was lost")
    back.width, back.height = 170, 10
    Call(back, 175, "11")
    assert(backPanel.width == 170 and backSpark.height == 10 * 2.1, "a nonnumeric height hint kept a stale size")
    back.height = secret
    Call(back, secret, secret)
    assert(not backSpark.shown and back.Spark.alpha == 0 and back.reverse, "an unreadable height left a spark of unknown size")
    Repeat("substitute, unreadable height", back, 9, 1, 0, secret, secret)
    Repeat("substitute, unreadable height, public hint", back, 9, 1, 0, 170, 10)
    assert(not backSpark.shown and back.Spark.alpha == 0)
    -- Native cast changes still repaint while the height is withheld.
    back:HideSpark()
    back.Spark.alpha = 1
    back:ShowSpark()
    assert(not backSpark.shown and back.Spark.alpha == 0, "a restart displayed a spark of unknown size")
    back:HandleCastStart(true)
    assert(not back.reverse and back.Spark.alpha == .81 and not backSpark.shown, "preserve the native empowered cursor")
    Repeat("substitute, empowered, secret hints", back, 8, 1, 0, secret, secret)
    back:HandleCastStart(false)
    assert(back.reverse and back.Spark.alpha == 0 and not backSpark.shown)
    local replaced = Region()
    back:SetStatusBarTexture(replaced)
    Repeat("substitute, unreadable height, new fill", back, 9, 1, 0, secret, secret)
    back.height = 11
    Call(back, secret, secret)
    assert(backSpark.shown and backSpark.height == 11 * 2.1 and backSpark.points[1][2] == replaced
        and back.Spark.alpha == 0, "a height that became public was not painted")
    -- A substitute that could not be hidden is no complete paint.
    backSpark.locked = true
    back.height = secret
    Call(back, secret, secret)
    assert(backSpark.shown)
    backSpark.locked = false
    Call(back, secret, secret)
    assert(not backSpark.shown, "a denied substitute hide was remembered as painted")
    back.height = 11
    Call(back, secret, secret)
    assert(backSpark.shown and backSpark.height == 11 * 2.1)
    -- Explicitly disabled options stay off behind unreadable hints.
    local off = ReversedStyle()
    off.showSpark, off.artworkNamePanel = false, false
    assert(appearance.Apply(back, off) and not backSpark.shown and back.Spark.alpha == 0 and not backPanel.shown)
    back.width, back.height = 200, 20
    Repeat("substitute, spark and panel off, secret hints", back, 1, 0, 0, secret, secret)
    assert(not backSpark.shown and back.Spark.alpha == 0 and back.Spark.height == 12 and not backPanel.shown)
    Unkept(backPanel, backSpark, back.Spark)
    assert(appearance.Restore(back) and back.Spark.alpha == .81 and not back.reverse)

    -- The cast moves behind hints that are absent, or stale next to an absent one.
    local function Moving(label, style, guards, reads, writes)
        local moved = Plate(style)
        Repeat(label .. ", width moves, no hints", moved, guards[1], reads[1], writes[1], function(frame, step)
            frame.width = 160 + step / 4
        end)
        Repeat(label .. ", height moves, no hints", moved, guards[2], reads[2], writes[2], function(frame, step)
            frame.height = 9 + step / 4
            return secret, secret
        end)
        Repeat(label .. ", size moves, no hints", moved, guards[3], reads[3], writes[3], function(frame, step)
            frame.width, frame.height = 185 + step, 34 + step
            return secret
        end)
        Repeat(label .. ", height moves, stale hint", moved, guards[4], reads[2], writes[2], function(frame, step)
            local known = frame.height
            frame.height = 134 + step
            return secret, known
        end)
        Repeat(label .. ", width moves, stale hint", moved, guards[5], reads[1], writes[1], function(frame, step)
            local known = frame.width
            frame.width = 285 + step
            return known, secret
        end)
        return moved
    end
    local moved = Moving("substitute", ReversedStyle(), { 9, 9, 9, 9, 10 }, { 1, 1, 1 }, { 1, 1, 2 })
    assert(moved.created[6].shown and moved.created[6].width == 385)
    assert(moved.created[7].shown and moved.created[7].height == 9 * 2.1 and moved.Spark.alpha == 0,
        "500 size callbacks of a moving cast sized the substitute spark")
    appearance.OnLayout(moved)
    assert(moved.created[7].shown and moved.created[7].height == 234 * 2.1 and moved.Spark.alpha == 0)
    moved = Moving("native", NativeStyle(), { 9, 14, 14, 14, 10 }, { 1, 2, 2 }, { 1, 1, 2 })
    assert(moved.created[6].shown and moved.created[6].width == 385)
    assert(moved.Spark.height == 9 * 2.1, "500 size callbacks of a moving cast sized Blizzard's spark")
    appearance.OnLayout(moved)
    assert(moved.Spark.height == 234 * 2.1 and moved.Spark.alpha == .81 and #moved.created == 6)
    Unkept(moved.created[6], moved.Spark)

    print("Castbar resize cost per 100 callbacks without public size hints (budget in parentheses)")
    for _, row in ipairs(rows) do
        print(("  %-43s %4d (%4d) guards  %4d (%3d) reads  %4d (%3d) writes"):format(row.label,
            row.guards, row.guardBudget * 100, row.reads, row.readBudget * 100, row.writes, row.writeBudget * 100))
    end
    for _, row in ipairs(rows) do
        assert(row.guards <= row.guardBudget * 100 and row.reads <= row.readBudget * 100
            and row.writes <= row.writeBudget * 100, "resize budget missed: " .. row.label)
    end
end

do
    -- Blizzard's spark withholds its own height while it carries a height of
    -- this file, the dominant idle case of a measured city: 913 of 1813 size
    -- callbacks repeated the complete spark paint and wrote nothing. The edge
    -- paint that meets the withheld height is the last one. No size callback
    -- and no cast event looks at that height: the next layout edge does, and
    -- paints again once it is public.
    NamePlateSetupOptions.spellNameInsideCastBar = false
    local rows = {}
    -- A real layout change: the callback, then the layout owner's handoff.
    local function Call(frame, ...)
        frame.hooks.OnSizeChanged(frame, ...)
        appearance.OnLayout(frame)
    end
    -- 100 size callbacks without a layout change. The budgets are the ones of
    -- the path that probed the spark from the callback (printed for reference):
    -- a spark without artwork now runs no Lua, and none paints or reads a spark.
    local function Repeat(label, frame, guards, reads, writes, paints, ...)
        local row = { label = label, guards = -meter.guards, reads = -meter.reads, writes = -meter.writes,
            paints = -(frame.sparkPaints or 0), guardBudget = guards, readBudget = reads, writeBudget = writes,
            paintBudget = paints, artwork = frame.observer ~= nil }
        local geometry = SparkGeometry(frame)
        for _ = 1, 100 do frame.hooks.OnSizeChanged(frame, ...) end
        assert(geometry:Sparks() == 0, "size callbacks read or wrote spark geometry: " .. label)
        row.guards, row.reads, row.writes = row.guards + meter.guards, row.reads + meter.reads, row.writes + meter.writes
        row.paints = row.paints + (frame.sparkPaints or 0)
        rows[#rows + 1] = row
    end
    local function Plate(style)
        local frame = Cast()
        frame.classicStyleCastBar = false
        assert(appearance.Apply(frame, style))
        return frame
    end
    local function Paints(frame, call, ...)
        local before = frame.sparkPaints or 0
        call(frame, ...)
        return (frame.sparkPaints or 0) - before
    end
    local bare = { showSpark = true, reverseFill = false }

    -- The measured style: Blizzard's spark at this file's height, no artwork.
    local idle = Plate(bare)
    local glow = idle.Spark
    assert(#idle.created == 0 and glow.height == 9 * 2.1 and glow.alpha == .81)
    idle.height, glow.veiled = secret, true
    assert(Paints(idle, Call, secret, secret) == 1, "the first withheld height takes one complete paint")
    assert(glow.height == 9 * 2.1 and glow.alpha == .81 and not idle.reverse, "a withheld spark height was written")
    Repeat("owed restore, secret hints", idle, 11, 1, 0, 0, secret, secret)
    Repeat("owed restore, no hints", idle, 11, 1, 0, 0)
    Repeat("owed restore, public hints", idle, 11, 1, 0, 0, 160, 9)
    combat = true
    Repeat("owed restore, combat, secret hints", idle, 13, 1, 0, 0, secret, secret)
    idle.protected = true
    Repeat("owed restore, protected in combat", idle, 8, 0, 0, 0, secret, secret)
    idle.protected, combat = false, false
    assert(glow.height == 9 * 2.1 and glow.alpha == .81)
    -- The first readable height restores Blizzard's, in the same callback.
    glow.veiled = false
    assert(Paints(idle, Call, secret, secret) == 1 and glow.height == 12,
        "the first readable spark height did not restore Blizzard's height")
    Repeat("restored, cast height withheld", idle, 7, 1, 0, 0, secret, secret)
    idle.height = 10
    Call(idle, secret, secret)
    assert(glow.height == 10 * 2.1, "a cast height that became public was not painted")

    -- The cast height is public and the spark height is not: the size is owed.
    glow.veiled, idle.height = true, 11
    Call(idle, 160, 11)
    assert(glow.height == 10 * 2.1, "a withheld spark height was written")
    Repeat("owed size, public hints", idle, 13, 1, 0, 0, 160, 11)
    Repeat("owed size, secret hints", idle, 12, 1, 0, 0, secret, secret)
    idle.height = 12 -- A fresh cast height changes nothing the client lets this file write.
    Repeat("owed size, moved cast, secret hints", idle, 12, 1, 0, 0, secret, secret)
    glow.veiled = false
    Call(idle, secret, secret)
    assert(glow.height == 12 * 2.1, "an owed spark size did not follow the cast's current height")
    Repeat("settled after an owed size", idle, 7, 1, 0, 0, secret, secret)
    Repeat("settled, unchanged public size", idle, 3, 0, 0, 0, 160, 12)
    -- The spark alone with a completed fit: one height read settles a callback
    -- without public hints. Combat and protection are asked once the height
    -- moved, a denial opens the fit, and a lone hint is never trusted.
    idle.protected, combat = true, true
    Repeat("settled, protected in combat", idle, 7, 1, 0, 0, secret, secret)
    idle.height = 12.5
    Call(idle, secret, secret)
    assert(glow.height == 12 * 2.1, "a protected castbar was written in combat")
    combat = false
    assert(Paints(idle, Call, secret, secret) == 1 and glow.height == 12.5 * 2.1,
        "a denied spark resize was not repainted")
    idle.protected, idle.height = false, 12
    assert(Paints(idle, Call, nil, 12.5) == 1 and glow.height == 12 * 2.1,
        "a stale height hint, and not the handoff's sample, settled a moved cast")
    -- The same from the short resize branch, which leaves the previous fit.
    idle.height, glow.veiled = 13, true
    Call(idle, 160, 13)
    Repeat("owed resize, public hints", idle, 13, 1, 0, 0, 160, 13)
    Repeat("owed resize, previous size", idle, 3, 0, 0, 0, 160, 12)
    glow.veiled = false
    Call(idle, 160, 13)
    assert(glow.height == 13 * 2.1, "an owed resize was dropped")
    idle.height = 12
    Call(idle, 160, 12)
    assert(glow.height == 12 * 2.1)

    -- Blizzard's layout picks another spark height behind the veil: it becomes
    -- the height to return, and the recorded one is never the veiled value.
    idle.height, glow.veiled = secret, true
    Call(idle, secret, secret)
    glow.height = 14
    glow.veiled = false
    Call(idle, secret, secret)
    assert(glow.height == 14, "Blizzard's own spark height was overwritten with a stale original")
    idle.height = 12
    Call(idle, secret, secret)
    assert(glow.height == 12 * 2.1)

    -- An access denial is no withheld height: it keeps the complete repaint.
    idle.height, glow.veiled = secret, true
    Call(idle, secret, secret)
    glow.veiled, glow.locked = false, true
    assert(Paints(idle, Call, secret, secret) == 1 and glow.height == 12 * 2.1, "an inaccessible spark was written")
    Repeat("denied spark, secret hints", idle, 13, 2, 0, 100, secret, secret)
    glow.locked = false
    Call(idle, secret, secret)
    assert(glow.height == 14, "a denied restore was remembered as applied")
    idle.height = 12
    Call(idle, secret, secret)
    assert(glow.height == 12 * 2.1)

    -- Native cast changes repaint while the height is owed, also a denied one.
    idle.height, glow.veiled = secret, true
    Call(idle, secret, secret)
    assert(Paints(idle, idle.ShowSpark) == 1 and Paints(idle, idle.SetStatusBarTexture, Region()) == 1)
    Repeat("owed restore after native changes", idle, 11, 1, 0, 0, secret, secret)
    idle.locked = true
    idle:ShowSpark()
    idle.locked = false
    assert(Paints(idle, Call, secret, secret) == 1, "a denied native change was left to the height probe")
    -- The height is still owed: each layout edge looks again, and nothing between two edges does.
    assert(Paints(idle, Call, secret, secret) == 1)
    assert(Paints(idle, idle.hooks.OnSizeChanged, secret, secret) == 0)
    idle.locked = true
    assert(not appearance.Apply(idle, bare, true))
    idle.locked = false
    assert(Paints(idle, Call, secret, secret) == 1, "a denied Apply was left to the height probe")
    idle:HandleCastStart(true)
    assert(glow.alpha == .81 and not idle.reverse and glow.height == 12 * 2.1)
    Repeat("owed restore, empowered", idle, 11, 1, 0, 0, secret, secret)
    idle:HandleCastStart(false)
    glow.veiled = false
    Call(idle, secret, secret)
    assert(glow.height == 14)
    idle.height = 12
    Call(idle, secret, secret)
    assert(glow.height == 12 * 2.1)

    -- Release behind the veil stays open for its caller and keeps the original.
    glow.veiled = true
    assert(not appearance.Restore(idle) and glow.height == 12 * 2.1)
    assert(not Observed(idle), "a blocked release kept its resize observer")
    Repeat("released behind the veil", idle, 0, 0, 0, 0, secret, secret)
    glow.veiled = false
    assert(appearance.Restore(idle) and glow.height == 14, "a release behind the veil lost Blizzard's height")
    assert(glow.height ~= secret and glow.alpha == .81)

    -- With artwork the name panel keeps following its own axis.
    local framed = Plate(NativeStyle())
    local framedPanel = framed.created[6]
    framed.height, framed.Spark.veiled = secret, true
    Call(framed, secret, secret)
    Repeat("owed restore with name panel", framed, 13, 2, 0, 0, secret, secret)
    framed.width = 170
    Call(framed, secret, secret)
    assert(framedPanel.width == 170 and framed.Spark.height == 9 * 2.1, "the panel missed a width behind an owed spark")
    framed.Spark.veiled, framed.height = false, 10
    Call(framed, secret, secret)
    assert(framed.Spark.height == 10 * 2.1 and framedPanel.width == 170)

    -- The other styles that return Blizzard's height: a hidden spark, and the
    -- substitute spark, which stays away until the height is back.
    local hidden = Plate(bare)
    hidden.Spark.veiled = true
    assert(not appearance.Apply(hidden, { showSpark = false }) and hidden.Spark.alpha == 0)
    Repeat("hidden spark, owed restore", hidden, 11, 1, 0, 0, secret, secret)
    hidden.Spark.veiled = false
    Call(hidden, secret, secret)
    hidden:ShowSpark()
    assert(hidden.Spark.height == 9 * 2.1 and hidden.Spark.alpha == 0,
        "a spark without a dimension probed the owed height outside its own layout edge")
    -- The incomplete Apply stays with its caller: the texture owner applies again.
    assert(appearance.Apply(hidden, { showSpark = false }, true))
    assert(hidden.Spark.height == 12 and hidden.Spark.alpha == 0)
    Repeat("hidden spark, restored", hidden, 1, 0, 0, 0, secret, secret)
    local turned = Plate(bare)
    turned.Spark.veiled = true
    assert(not appearance.Apply(turned, { showSpark = true, reverseFill = true }) and turned.reverse)
    assert(#turned.created == 0 and turned.Spark.alpha == .81)
    Repeat("substitute spark, owed restore", turned, 11, 1, 0, 0, secret, secret)
    turned.Spark.veiled = false
    Call(turned, secret, secret)
    assert(turned.Spark.height == 12 and turned.Spark.alpha == 0 and turned.created[1].shown
        and turned.created[1].height == 9 * 2.1, "the substitute spark missed the readable native height")

    print("Castbar resize cost per 100 callbacks behind an unreadable native spark height (budget in parentheses)")
    for _, row in ipairs(rows) do
        print(("  %-38s %4d (%4d) guards %4d (%3d) reads %4d (%3d) writes %4d (%3d) paints"):format(row.label,
            row.guards, row.guardBudget * 100, row.reads, row.readBudget * 100, row.writes, row.writeBudget * 100,
            row.paints, row.paintBudget))
    end
    local missed
    for _, row in ipairs(rows) do
        -- With artwork the callback reads the panel's width, once at most.
        local quiet = row.artwork and row.reads <= 100 and row.guards <= row.guardBudget * 100
            or row.guards == 0 and row.reads == 0
        if not quiet or row.writes ~= 0 or row.paints ~= 0 then missed = missed or row.label end
    end
    assert(not missed, "native spark budget missed: " .. tostring(missed))
end

do
    -- A spark that is only hidden, or only keeps Blizzard's direction, has no
    -- use for a cast dimension, the fill region or Blizzard's shown state. Its
    -- observers stay installed, so a denied paint is repaired by the next
    -- edge, and a completed paint leaves all but the cast start at the state
    -- lookup: no guard, read or write after it.
    NamePlateSetupOptions.spellNameInsideCastBar = false
    local function Fresh(reverse)
        local frame = Cast()
        frame.classicStyleCastBar, frame.reverse = false, reverse == true
        return frame, { show = frame.ShowSpark, hide = frame.HideSpark, fill = frame.SetStatusBarTexture,
            start = frame.HandleCastStart }
    end
    -- The repair edges of a spark are Blizzard's four cast calls. A resize
    -- observer is none of them: only the artwork has one.
    local function Full(frame, native)
        return frame.ShowSpark ~= native.show and frame.HideSpark ~= native.hide
            and frame.SetStatusBarTexture ~= native.fill and frame.HandleCastStart ~= native.start
    end
    local function Work(call, ...)
        local guards, reads, writes = meter.guards, meter.reads, meter.writes
        call(...)
        return meter.guards - guards, meter.reads - reads, meter.writes - writes
    end
    -- Blizzard's own cost of the three native calls, then the hooked calls:
    -- they may add the three state lookups and nothing else.
    local function Quiet(frame, native)
        local paints = frame.sparkPaints or 0
        local guards, reads, writes = Work(function()
            native.hide(frame)
            native.show(frame)
            native.fill(frame, Region())
        end)
        local hookedGuards, hookedReads, hookedWrites = Work(function()
            frame:HideSpark()
            frame:ShowSpark()
            frame:SetStatusBarTexture(Region())
        end)
        local sizeGuards, sizeReads, sizeWrites = Work(frame.hooks.OnSizeChanged, frame, frame.width, frame.height)
        return hookedGuards == guards + 3 and hookedReads == reads and hookedWrites == writes
            and sizeGuards == 0 and sizeReads == 0 and sizeWrites == 0 and (frame.sparkPaints or 0) == paints
    end
    -- The edges that repair a paint denied at the castbar: Blizzard's next
    -- cast call, or the texture owner's Apply at the end of combat. A size
    -- callback is none: a spark without artwork has no observer.
    local wakes = {
        function(frame) frame:ShowSpark() end,
        function(frame) frame:SetStatusBarTexture(Region()) end,
        function(frame, style) assert(appearance.Apply(frame, style)) end,
    }
    local function Asleep(frame)
        local paints = frame.sparkPaints or 0
        frame.hooks.OnSizeChanged(frame, frame.width, frame.height)
        frame.hooks.OnSizeChanged(frame, secret, secret)
        return not frame.observer and (frame.sparkPaints or 0) == paints
    end

    -- original: the fill direction Blizzard had. styled: the one of the style.
    for _, case in ipairs({
        { style = { showSpark = false }, original = false, styled = false, alpha = 0 },
        { style = { showSpark = false, reverseFill = true }, original = false, styled = true, alpha = 0 },
        { style = { showSpark = false, reverseFill = false }, original = true, styled = false, alpha = 0 },
        { style = { reverseFill = false }, original = true, styled = false, alpha = .81 },
    }) do
        local frame, native = Fresh(case.original)
        local glow = frame.Spark
        assert(appearance.Apply(frame, case.style))
        assert(Full(frame, native), "a styled spark lost a repair edge")
        assert(#frame.created == 0 and glow.alpha == case.alpha and glow.height == 12 and glow.shown)
        assert(frame.reverse == case.styled)
        -- Native spark and fill changes and resizes leave the paint as it is.
        assert(Quiet(frame, native), "a completed spark without a dimension did work on a native change")
        assert(glow.shown and glow.alpha == case.alpha and glow.height == 12 and frame.reverse == case.styled)
        -- Empowered casts get Blizzard's cursor and direction, the next cast the style.
        frame:HandleCastStart(true)
        assert(glow.alpha == .81 and glow.height == 12 and frame.reverse == case.original,
            "preserve the native empowered cursor")
        frame:HandleCastStart(false)
        assert(glow.alpha == case.alpha and glow.height == 12 and frame.reverse == case.styled,
            "the cast after an empowered one lost its style")
        -- A denied cast start writes nothing and the next start repaints.
        frame.locked = true
        frame:HandleCastStart(true)
        assert(glow.alpha == case.alpha and frame.reverse == case.styled, "an inaccessible castbar was written")
        frame.locked = false
        frame:HandleCastStart(true)
        assert(glow.alpha == .81 and frame.reverse == case.original, "a denied empowered start was never repaired")
        frame:HandleCastStart(false)
        assert(glow.alpha == case.alpha and frame.reverse == case.styled)
        -- A cast start denied at the castbar is repaired by the very next
        -- native ShowSpark, fill change or Apply, whichever is first, and by
        -- no size callback.
        for index, wake in ipairs(wakes) do
            local asked = owed[frame] or 0
            frame.locked = true
            frame:HandleCastStart(true)
            assert(glow.alpha == case.alpha and frame.reverse == case.styled, "an inaccessible castbar was written")
            assert((owed[frame] or 0) > asked, "a denied cast start did not ask for the combat-end owner")
            frame.locked = false
            assert(Asleep(frame) and glow.alpha == case.alpha and frame.reverse == case.styled,
                "a size callback repainted a spark without artwork")
            wake(frame, case.style)
            assert(glow.alpha == .81 and frame.reverse == case.original and glow.height == 12,
                "a denied empowered start missed repair edge " .. index)
            assert(Quiet(frame, native), "a repaired empowered start kept working on native changes")
            assert(glow.alpha == .81 and frame.reverse == case.original)
            -- The same edges return the style after a denied normal start.
            frame.locked = true
            frame:HandleCastStart(false)
            assert(glow.alpha == .81 and frame.reverse == case.original, "an inaccessible castbar was written")
            frame.locked = false
            wake(frame, case.style)
            assert(glow.alpha == case.alpha and frame.reverse == case.styled and glow.height == 12,
                "a denied cast start missed repair edge " .. index)
            assert(Quiet(frame, native), "a repaired cast start kept working on native changes")
        end
        if case.alpha == 0 then
            glow.alpha = 1 -- A native or skin refresh can reset the alpha before the next cast.
            frame:HandleCastStart(false)
            assert(glow.alpha == 0, "a cast start displayed the hidden spark")
        end
        assert(#frame.created == 0 and Quiet(frame, native), "a completed cast start left the spark paint open")
        assert(appearance.Restore(frame) and glow.alpha == .81 and glow.height == 12 and frame.reverse == case.original)
        frame:HandleCastStart(false)
        assert(glow.alpha == .81 and frame.reverse == case.original, "released hooks must be inert")
    end

    -- Toggling between the two keeps Blizzard's exact alpha and stays quiet.
    local toggled, toggledNative = Fresh()
    assert(appearance.Apply(toggled, { showSpark = false }) and toggled.Spark.alpha == 0)
    assert(appearance.Apply(toggled, { reverseFill = false }) and toggled.Spark.alpha == .81)
    assert(appearance.Apply(toggled, { showSpark = false, reverseFill = true }) and toggled.Spark.alpha == 0)
    assert(toggled.reverse and Quiet(toggled, toggledNative))

    -- A sized spark uses the same hooks at full strength, and they serve the
    -- height owed when the spark is switched off behind a withheld native height.
    assert(appearance.Apply(toggled, { showSpark = true, reverseFill = false }))
    assert(Full(toggled, toggledNative) and toggled.Spark.height == 9 * 2.1 and toggled.Spark.alpha == .81)
    assert(not Quiet(toggled, toggledNative), "a sized spark ignored a native change")
    toggled.Spark.veiled = true
    local off = { showSpark = false }
    assert(not appearance.Apply(toggled, off))
    assert(toggled.Spark.alpha == 0 and toggled.Spark.height == 9 * 2.1, "a withheld spark height was written")
    toggled.Spark.veiled = false
    toggled.hooks.OnSizeChanged(toggled, secret, secret)
    toggled:ShowSpark()
    assert(toggled.Spark.height == 9 * 2.1 and toggled.Spark.alpha == 0, "the owed height was probed between two layout edges")
    -- The incomplete Apply stays with the texture owner, whose next Apply returns the height.
    assert(appearance.Apply(toggled, off, true))
    assert(toggled.Spark.height == 12 and toggled.Spark.alpha == 0, "the height owed at the toggle was not returned")
    assert(appearance.Restore(toggled) and toggled.Spark.alpha == .81 and toggled.Spark.height == 12)

    -- An incomplete paint keeps the repeats it always had.
    local denied, deniedNative = Fresh()
    denied.Spark.locked = true
    assert(not appearance.Apply(denied, { showSpark = false }) and denied.Spark.alpha == .81)
    assert(Full(denied, deniedNative), "an incomplete hidden spark lost its repeats")
    -- While the spark stays denied every edge retries, and none completes.
    denied:ShowSpark()
    denied:SetStatusBarTexture(Region())
    assert(denied.Spark.alpha == .81 and not Quiet(denied, deniedNative), "a denied spark paint went quiet")
    denied.Spark.locked = false
    assert(Asleep(denied) and denied.Spark.alpha == .81, "a size callback repainted a spark without artwork")
    denied:ShowSpark()
    assert(denied.Spark.alpha == 0 and denied.Spark.height == 12, "a denied spark hide was never repaired")
    assert(Quiet(denied, deniedNative))
    for _, wake in ipairs(wakes) do
        local late, lateNative = Fresh()
        local lateStyle = { showSpark = false }
        assert(appearance.Apply(late, lateStyle) and Quiet(late, lateNative))
        late.Spark.locked = true
        late:HandleCastStart(true)
        assert(late.Spark.alpha == 0 and not Quiet(late, lateNative), "an incomplete cast start lost its repeats")
        late.Spark.locked = false
        wake(late, lateStyle)
        assert(late.Spark.alpha == .81, "a denied empowered cursor was never repaired")
        late:HandleCastStart(false)
        assert(late.Spark.alpha == 0 and Quiet(late, lateNative))
    end

    -- A denied Apply opens the paint for the same edges.
    local reapplied, reappliedNative = Fresh()
    assert(appearance.Apply(reapplied, { showSpark = false }))
    reapplied.Spark.alpha = 1
    reapplied.locked = true
    assert(not appearance.Apply(reapplied, { showSpark = false }, true) and reapplied.Spark.alpha == 1)
    reapplied.locked = false
    reapplied:ShowSpark()
    assert(reapplied.Spark.alpha == 0 and Quiet(reapplied, reappliedNative), "a denied Apply was never repaired")

    -- With artwork the size callback follows the panel's axis only.
    local framed, framedNative = Fresh()
    assert(appearance.Apply(framed, { showSpark = false, artwork = true }) and Full(framed, framedNative))
    local framedPanel = framed.created[2]
    assert(framedPanel.shown and framedPanel.width == 160)
    local framedGuards, framedReads, framedWrites = Work(function()
        framed:HideSpark()
        framed:ShowSpark()
        framed:SetStatusBarTexture(Region())
    end)
    -- Three state lookups and Blizzard's own three writes.
    assert(framedGuards == 3 and framedReads == 0 and framedWrites == 3,
        "a completed spark under artwork did work on a native change")
    framed.width, framed.height = 170, 14
    framed.hooks.OnSizeChanged(framed, 170, 14)
    assert(framedPanel.width == 170 and framed.Spark.alpha == 0 and framed.Spark.height == 12)
    framed:HandleCastStart(true)
    assert(framed.Spark.alpha == .81)
    framed:HandleCastStart(false)
    assert(framed.Spark.alpha == 0 and #framed.created == 2)
end

do
    -- The visible-only resize observer. The size script lives on a child of
    -- this addon and is set only while the native castbar is effectively
    -- visible: an idle bar runs no Lua on a resize and has no geometry read.
    NamePlateSetupOptions.spellNameInsideCastBar = false
    local function Work(call, ...)
        local guards, reads, writes = meter.guards, meter.reads, meter.writes
        call(...)
        return meter.guards - guards, meter.reads - reads, meter.writes - writes
    end
    local function Hidden(style)
        local frame = Cast()
        frame.classicStyleCastBar, frame.visible = false, false
        assert(appearance.Apply(frame, style))
        return frame
    end
    -- A size callback of the client that reaches no Lua of this addon.
    local function Idle(frame, ...)
        local guards, reads, writes = Work(frame.hooks.OnSizeChanged, frame, ...)
        return guards == 0 and reads == 0 and writes == 0
    end

    -- Styled while hidden: no observer, no callback, and the paints that need
    -- a cast dimension wait for the first visible frame.
    local idle = Hidden(NativeStyle())
    local idlePanel, glow = idle.created[6], idle.Spark
    assert(not idle.observer, "a hidden castbar allocated a resize observer")
    assert(rawget(idle.hooks, "OnShow") and rawget(idle.hooks, "OnHide"), "the visibility edges were not hooked")
    assert(#idle.created == 6 and glow.alpha == .81 and glow.height == 12 and not idlePanel.shown
        and idlePanel.width == nil, "a hidden castbar had its panel or spark sized")
    idle.width, idle.height = 170, 11
    assert(Idle(idle, 170, 11) and Idle(idle, secret, secret) and Idle(idle), "an idle castbar ran a resize callback")
    assert(idlePanel.width == nil and glow.height == 12)

    -- The first visible frame creates the observer and samples the current size.
    SetVisible(idle, true)
    local observer = idle.observer
    assert(Observed(idle) and observer.parent == idle and observer.allPoints == idle and observer.attached == 1)
    assert(idlePanel.width == 170 and glow.height == 11 * 2.1, "first show missed the current layout")
    local _, reads, writes = Work(idle.hooks.OnSizeChanged, idle, 170, 11)
    assert(reads == 0 and writes == 0, "stable bounds touched the client")
    idle.width, idle.height = 175, 12
    idle.hooks.OnSizeChanged(idle, 175, 12)
    assert(idlePanel.width == 175 and glow.height == 11 * 2.1, "a size callback missed the panel or sized the spark")
    appearance.OnLayout(idle)
    assert(idlePanel.width == 175 and glow.height == 12 * 2.1, "a visible castbar missed a resize")

    -- Hide detaches the script. Reopen attaches the same child and samples.
    SetVisible(idle, false)
    assert(not Observed(idle) and observer.detached == 1, "a hidden castbar kept its size script")
    idle.width, idle.height = 180, 13
    assert(Idle(idle, 180, 13) and idlePanel.width == 175 and glow.height == 12 * 2.1)
    appearance.OnLayout(idle)
    SetVisible(idle, true)
    assert(Observed(idle) and idle.observer == observer and observer.attached == 2)
    assert(idlePanel.width == 180 and glow.height == 13 * 2.1, "a reopened castbar kept the size it was hidden with")
    SetVisible(idle, false)
    _, _, writes = Work(SetVisible, idle, true)
    assert(writes == 0 and Observed(idle), "a reopened castbar of unchanged size was written")

    -- A withheld visibility is never branched on: the last OnShow or OnHide decides.
    idle.veiledShown = true
    SetVisible(idle, false)
    assert(not Observed(idle), "a withheld visibility kept the observer of a hidden castbar")
    assert(appearance.Apply(idle, NativeStyle()) and not Observed(idle), "an Apply behind the veil observed a hidden castbar")
    SetVisible(idle, true)
    assert(Observed(idle), "a withheld visibility lost the observer of a shown castbar")
    idle.veiledShown = false

    -- An event older than the client's current answer leaves no stale script.
    rawget(idle.hooks, "OnHide")(idle)
    assert(Observed(idle), "a hide outdated by a nested show detached a visible castbar")
    SetVisible(idle, false)
    idle.width = 190
    _, _, writes = Work(rawget(idle.hooks, "OnShow"), idle)
    assert(not Observed(idle) and writes == 0 and idlePanel.width == 180,
        "a show outdated by a nested hide observed a hidden castbar")
    SetVisible(idle, true)
    assert(Observed(idle) and idlePanel.width == 190)

    -- A style without a dimension needs no observer. The next one attaches again.
    assert(appearance.Apply(idle, { outlineSize = 1 }) and not Observed(idle))
    assert(Idle(idle, 200, 20))
    assert(appearance.Apply(idle, NativeStyle()) and Observed(idle))

    -- Release detaches, also when the restore itself is blocked, and stays inert.
    assert(appearance.Restore(idle) and not Observed(idle))
    SetVisible(idle, false)
    SetVisible(idle, true)
    assert(not Observed(idle) and Idle(idle, 210, 21), "a released castbar was observed again")
    assert(appearance.Apply(idle, NativeStyle()) and Observed(idle))
    idle.locked = true
    assert(not appearance.Restore(idle) and not Observed(idle), "a blocked restore kept its resize observer")
    SetVisible(idle, false)
    SetVisible(idle, true)
    assert(not Observed(idle), "a blocked restore was observed again")
    idle.locked = false
    assert(appearance.Restore(idle) and glow.height == 12 and glow.alpha == .81)
    assert(idle.observer == observer, "a castbar received a second observer")

    -- Without a sized style (released, or outline and interrupt only) a
    -- visibility edge is the state lookup and nothing of the client.
    local function Unwatched(frame, ...)
        for _, visible in ipairs({ ... }) do
            local guards, reads, writes = Work(SetVisible, frame, visible)
            if guards > 1 or reads ~= 0 or writes ~= 0 then return false end
        end
        return true
    end
    assert(Unwatched(idle, false, true, false, true), "a released castbar asked the client at a visibility edge")
    -- No edge in between: the known visibility stays valid.
    assert(appearance.Apply(idle, NativeStyle()) and Observed(idle))
    assert(appearance.Apply(idle, { outlineSize = 1, interruptShake = true }) and not Observed(idle))
    assert(appearance.Apply(idle, NativeStyle()) and Observed(idle))
    -- Edges that passed unwatched: the next sized style samples the visibility.
    assert(appearance.Apply(idle, { outlineSize = 1, interruptShake = true }))
    assert(Unwatched(idle, true, false), "a style without a dimension asked the client at a visibility edge")
    assert(appearance.Apply(idle, NativeStyle()) and not Observed(idle),
        "a style enabled again observed a castbar hidden in between")
    assert(appearance.Restore(idle) and Unwatched(idle, true))
    idle.width = 195
    assert(appearance.Apply(idle, NativeStyle()) and Observed(idle) and idlePanel.width == 195,
        "a style enabled again missed a castbar shown in between")
    -- A visibility withheld at that sample: hidden until the next OnShow.
    assert(appearance.Restore(idle) and Unwatched(idle, false, true))
    idle.veiledShown = true
    assert(appearance.Apply(idle, NativeStyle()) and not Observed(idle),
        "a style enabled again observed a castbar of withheld visibility")
    SetVisible(idle, true)
    assert(Observed(idle), "a withheld visibility lost the OnShow after a release")
    idle.veiledShown = false
    assert(appearance.Restore(idle) and not Observed(idle) and idle.observer == observer)

    -- Protection: no child is created on a castbar this addon may not write.
    -- The owed observer ends with the hide, or is retried by the cast start.
    local guarded = Hidden(NativeStyle())
    local guardedPanel = guarded.created[6]
    guarded.width, guarded.height = 150, 10
    guarded.protected, combat = true, true
    SetVisible(guarded, true)
    assert(not guarded.observer and guardedPanel.width == nil and guarded.Spark.height == 12,
        "a protected castbar was written in combat")
    SetVisible(guarded, false)
    combat = false
    guarded:HandleCastStart(false)
    assert(not guarded.observer, "an owed observer outlived the hide")
    combat = true
    SetVisible(guarded, true)
    assert(not guarded.observer)
    combat = false
    guarded.height = 11
    guarded:HandleCastStart(false)
    assert(Observed(guarded) and guardedPanel.width == 150 and guarded.Spark.height == 11 * 2.1,
        "an owed observer or first Spark size was not retried by the cast start")
    appearance.OnLayout(guarded)
    assert(guarded.Spark.height == 11 * 2.1)
    -- With its child, a protected show attaches and its denied sample is retried.
    SetVisible(guarded, false)
    guarded.width, guarded.height = 140, 12
    combat = true
    SetVisible(guarded, true)
    assert(Observed(guarded) and guardedPanel.width == 150 and guarded.Spark.height == 11 * 2.1,
        "a protected castbar was written in combat")
    combat = false
    guarded.hooks.OnSizeChanged(guarded, 140, 12)
    assert(guardedPanel.width == 140 and guarded.Spark.height == 11 * 2.1, "a denied first sample was not retried")
    appearance.OnLayout(guarded)
    assert(guarded.Spark.height == 12 * 2.1)
    guarded.protected = false
    -- An inaccessible castbar is not asked for its visibility.
    guarded.locked = true
    _, reads = Work(SetVisible, guarded, false)
    assert(not Observed(guarded) and reads == 0, "an inaccessible castbar was read")
    guarded.locked = false

    -- Reversed fill keeps the established substitute, Empower Blizzard's cursor.
    -- The direction is set during Apply. The substitute is made at first show.
    local turned = Hidden(ReversedStyle())
    assert(#turned.created == 6 and turned.reverse and turned.Spark.alpha == .81,
        "a hidden reverse-fill bar drew a substitute Spark")
    turned.height = 12
    SetVisible(turned, true)
    local turnedSpark = turned.created[7]
    assert(turnedSpark.shown and turnedSpark.height == 12 * 2.1 and turned.Spark.alpha == 0 and turned.reverse)
    turned:HandleCastStart(true)
    assert(not turnedSpark.shown and turned.Spark.alpha == .81 and turned.Spark.height == 12 and not turned.reverse,
        "an empowered cast must draw Blizzard's own cursor")
    turned:HandleCastStart(false)
    assert(turnedSpark.shown and turned.Spark.alpha == 0 and turned.reverse)
end

do
    -- A hidden castbar does no geometry work. Layout notifications mark the
    -- Spark stale. The first visible frame samples the resulting geometry.
    NamePlateSetupOptions.spellNameInsideCastBar = false
    local function Geometry(frame)
        local queries = SparkGeometry(frame)
        function queries:Count() return self.cast + self.width + self.spark end
        return queries
    end
    local function Hidden(style, veiled)
        local frame = Cast()
        frame.classicStyleCastBar = false
        -- veiled: shown, but the client withholds the answer.
        if veiled then frame.veiledShown = true else frame.visible = false end
        local queries = Geometry(frame)
        assert(appearance.Apply(frame, style))
        return frame, queries
    end
    -- 100 events of a hidden bar between two layout edges: native cast calls
    -- and size callbacks. It ends with a running cast.
    local function Churn(frame)
        for step = 1, 100 do
            local kind = step % 7
            if kind == 0 then frame:ShowSpark()
            elseif kind == 1 then frame:SetStatusBarTexture(Region())
            elseif kind == 2 then frame:HideSpark()
            elseif kind == 3 then frame:SetNameTextShown(step % 14 < 7)
            elseif kind == 4 then frame:HandleCastStart(false)
            elseif kind == 5 then frame.hooks.OnSizeChanged(frame, frame.width, frame.height)
            else frame.hooks.OnSizeChanged(frame, secret, secret) end
        end
        frame:SetNameTextShown(true)
        frame:ShowSpark()
    end
    local function Edges(frame, queries, style)
        for _, reset in ipairs({ false, true, true }) do
            queries:Reset()
            assert(appearance.Apply(frame, style, reset))
            appearance.OnLayout(frame)
            assert(queries:Count() == 0 and queries.writes == 0, "a hidden layout edge read or wrote Spark geometry")
        end
    end

    -- Blizzard's spark at a height of this file, with the name panel.
    local forward, queries = Hidden(NativeStyle())
    local forwardPanel = forward.created[6]
    assert(queries:Count() == 0 and queries.writes == 0, "a hidden castbar was sized before its first visible cast")
    Churn(forward)
    assert(queries:Count() == 0 and queries.writes == 0, "a hidden castbar had its geometry read: " .. queries:Count())
    Edges(forward, queries, NativeStyle())
    assert(not forward.observer and #forward.created == 6 and forward.Spark.height == 12
        and forward.Spark.alpha == .81 and not forwardPanel.shown, "a hidden castbar had its panel sized")
    assert(appearance.Restore(forward) and queries:Count() == 0 and queries.writes == 0,
        "a plate released before its first cast had Spark geometry restored")
    assert(appearance.Apply(forward, NativeStyle()))
    forward.width, forward.height = 170, 11
    SetVisible(forward, true)
    assert(Observed(forward) and forwardPanel.shown and forwardPanel.width == 170
        and forward.Spark.alpha == .81, "the first visible frame was not painted")
    assert(queries.width > 0 and queries.cast == 1 and queries.spark == 1 and queries.writes == 1
        and forward.Spark.height == 11 * 2.1, "the first visible cast missed its final Spark geometry")
    queries:Reset()
    forward.hooks.OnSizeChanged(forward, 170, 11)
    assert(queries:Count() == 0, "the first visible paint was left open")

    -- A callback that outlives its observer stops before any geometry.
    local script = Observed(forward)
    SetVisible(forward, false)
    forward.width, forward.height = 180, 13
    script(forward.observer, 180, 13)
    script(forward.observer)
    assert(queries:Count() == 0 and forwardPanel.width == 170 and forward.Spark.height == 11 * 2.1,
        "a detached observer reached the cast's geometry")
    -- Hidden again: the same events stay free, also with a fit from the last show.
    Churn(forward)
    assert(queries:Count() == 0 and queries.writes == 0 and forwardPanel.width == 170
        and forward.Spark.height == 11 * 2.1, "a rehidden castbar had its geometry read: " .. queries:Count())
    appearance.OnLayout(forward)
    assert(queries:Sparks() == 0, "a hidden layout sampled the Spark")
    SetVisible(forward, true)
    assert(forwardPanel.shown and forwardPanel.width == 180 and forward.Spark.height == 13 * 2.1
        and queries.cast == 1 and queries.spark == 1, "a reopened castbar missed a layout change")
    queries:Reset()
    SetVisible(forward, false)
    SetVisible(forward, true)
    assert(queries:Sparks() == 0, "an unchanged reopened cast reread Spark geometry")
    script = Observed(forward)
    assert(appearance.Restore(forward) and forward.Spark.height == 12 and forward.Spark.alpha == .81)
    queries:Reset()
    script(forward.observer, 190, 14)
    assert(queries:Count() == 0 and not forwardPanel.shown, "a released observer reached the cast's geometry")

    -- The substitute on the reversed edge is allocated on the first show.
    local back, backQueries = Hidden(ReversedStyle())
    assert(#back.created == 6 and backQueries:Count() == 0, "a hidden reverse-fill bar allocated a Spark")
    Churn(back)
    assert(backQueries:Count() == 0 and backQueries.writes == 0,
        "a hidden reversed castbar had its geometry read: " .. backQueries:Count())
    Edges(back, backQueries, ReversedStyle())
    assert(not back.observer and #back.created == 6 and back.reverse and back.Spark.height == 12,
        "a hidden castbar received an observer or a second substitute spark")
    back.width, back.height = 170, 11
    SetVisible(back, true)
    local backSpark = back.created[7]
    assert(backQueries.cast == 1 and backQueries.spark == 0 and backQueries.writes == 1)
    assert(backSpark.shown and backSpark.height == 11 * 2.1 and backSpark.points[1][2] == back.fill
        and back.Spark.alpha == 0 and back.reverse, "the layout handoff missed the substitute spark")
    assert(back.created[6].shown and back.created[6].width == 170)
    -- The first visible frame of an empowered cast uses Blizzard's cursor.
    SetVisible(back, false)
    back:HandleCastStart(true)
    SetVisible(back, true)
    assert(not backSpark.shown and back.Spark.alpha == .81 and not back.reverse and back.Spark.height == 12,
        "an empowered cast that started hidden lost Blizzard's cursor")
    -- Setting removal and release while hidden stay exact.
    SetVisible(back, false)
    back:HandleCastStart(false)
    SetVisible(back, true)
    assert(backSpark.shown and back.Spark.alpha == 0 and back.reverse)
    SetVisible(back, false)
    assert(appearance.Apply(back, { outlineSize = 1 }))
    assert(not backSpark.shown and back.Spark.alpha == .81 and not back.reverse and not back.created[6].shown,
        "a setting removed while hidden was not restored at once")
    assert(appearance.Apply(back, ReversedStyle()) and back.reverse and not backSpark.shown and back.Spark.alpha == .81,
        "a setting enabled while hidden drew the Spark prematurely")
    assert(appearance.Restore(back) and back.Spark.alpha == .81 and not back.reverse and back.Spark.height == 12)

    -- A spark that is only hidden needs no dimension. The next cast start
    -- repairs a native alpha reset while the bar is still hidden.
    local dark, darkQueries = Hidden({ showSpark = false, artwork = true })
    local darkPanel = dark.created[2]
    assert(dark.Spark.alpha == 0 and dark.Spark.height == 12)
    Churn(dark)
    assert(darkQueries:Count() == 0 and dark.Spark.alpha == 0 and not darkPanel.shown and not dark.observer)
    dark.Spark.alpha = 1 -- A native or skin refresh can reset the alpha before the cast is shown.
    dark:HandleCastStart(false)
    assert(darkQueries:Count() == 0)
    dark.width = 170
    SetVisible(dark, true)
    assert(dark.Spark.alpha == 0, "the first visible frame displayed the hidden spark")
    assert(darkPanel.shown and darkPanel.width == 170 and dark.Spark.height == 12)
    local bare, bareQueries = Hidden({ showSpark = false })
    bare.Spark.alpha = 1
    bare:HandleCastStart(false)
    SetVisible(bare, true)
    assert(bare.Spark.alpha == 0 and bareQueries:Count() == 0, "a hidden spark cost a geometry read")
    assert(appearance.Restore(bare) and bare.Spark.alpha == .81)

    -- A visibility the client withholds at the first hook: inactive until OnShow.
    local veiled, veiledQueries = Hidden(NativeStyle(), true)
    veiledQueries:Reset()
    Churn(veiled)
    assert(not veiled.observer and veiledQueries:Count() == 0 and veiled.Spark.height == 12,
        "a castbar of withheld visibility was observed before its OnShow")
    SetVisible(veiled, true)
    assert(Observed(veiled) and veiled.Spark.height == 9 * 2.1 and veiled.created[6].shown
        and veiled.created[6].width == 160, "the OnShow of a castbar of withheld visibility was not painted")
    SetVisible(veiled, false)
    assert(not Observed(veiled))
    veiledQueries:Reset()
    Churn(veiled)
    assert(veiledQueries:Count() == 0 and not Observed(veiled), "the last OnHide was not kept behind the veil")
    SetVisible(veiled, true)
    assert(Observed(veiled))

    -- A layout reset denied while hidden survives a protected show. The
    -- next writable layout handoff reapplies the size, even when it matches.
    local guarded, guardedQueries = Hidden(NativeStyle())
    SetVisible(guarded, true)
    assert(guarded.Spark.height == 9 * 2.1)
    SetVisible(guarded, false)
    guarded.Spark.height = 12 -- Blizzard's layout reset the spark behind the hidden bar.
    guardedQueries:Reset()
    guarded.protected, combat = true, true
    assert(not appearance.Apply(guarded, NativeStyle(), true) and guardedQueries:Count() == 0)
    SetVisible(guarded, true)
    assert(Observed(guarded) and guarded.Spark.height == 12, "a protected castbar was written in combat")
    combat = false
    guarded.hooks.OnSizeChanged(guarded, guarded.width, guarded.height)
    assert(guarded.Spark.height == 12 and guardedQueries:Sparks() == 0)
    appearance.OnLayout(guarded)
    assert(guarded.Spark.height == 9 * 2.1 and guarded.created[6].shown and guarded.created[6].width == 160,
        "a fit opened while hidden was lost to a protected show")
    guarded.protected = false

    -- A child the client will not let this file write keeps its script, and
    -- the script is inert until the bar is visible again.
    local observer = guarded.observer
    function observer:CanBeAccessedInContext() return not self.locked end
    local attached, detached = observer.attached, observer.detached
    observer.locked = true
    SetVisible(guarded, false)
    assert(observer.detached == detached and Observed(guarded), "an inaccessible observer was written")
    guarded.width, guarded.height = 150, 10
    guardedQueries:Reset()
    guarded.hooks.OnSizeChanged(guarded, 150, 10)
    assert(guardedQueries:Count() == 0 and guarded.created[6].width == 160, "a hidden castbar ran a resize callback")
    appearance.OnLayout(guarded)
    SetVisible(guarded, true)
    assert(observer.attached == attached and guarded.created[6].width == 150 and guarded.Spark.height == 10 * 2.1,
        "a kept script was set again or missed its sample")
    observer.locked = false
    SetVisible(guarded, false)
    assert(observer.detached == detached + 1 and not Observed(guarded))
end

do
    -- A cast first shown in combat keeps its cached spark size until a
    -- writable layout handoff. A spark without name artwork needs no child.
    local frame = Cast()
    frame.classicStyleCastBar, frame.protected = false, true
    SetVisible(frame, false)
    assert(appearance.Apply(frame, { showSpark = true, reverseFill = false, sparkOverflow = true }))
    combat = true
    SetVisible(frame, true)
    combat = false
    frame.height = 11
    frame.hooks.OnSizeChanged(frame, frame.width, 11)
    assert(frame.Spark.height == 9 * 2.1 and not frame.observer)
    appearance.OnLayout(frame)
    assert(frame.Spark.height == 11 * 2.1)

    -- The prepared child carries no script until the cast is known visible.
    -- Its initial Apply prepares the name panel and sizes the spark.
    NamePlateSetupOptions.spellNameInsideCastBar = false
    local ready = Cast()
    ready.classicStyleCastBar, ready.protected, ready.visible = false, true, false
    local heights, getHeight = 0, ready.GetHeight
    function ready:GetHeight()
        heights = heights + 1
        return getHeight(self)
    end
    assert(appearance.Apply(ready, NativeStyle()))
    local child, readyPanel = ready.observer, ready.created[6]
    assert(child and child.allPoints == ready and child.attached == 0 and not Observed(ready),
        "a protected hidden castbar was not prepared, or received a size script")
    assert(heights == 1 and ready.Spark.height == 9 * 2.1 and readyPanel.shown and readyPanel.width == 160,
        "the preparing Apply did not paint the initial size once")
    assert(appearance.Apply(ready, NativeStyle(), true) and heights == 2 and not Observed(ready),
        "a hidden layout edge did not refresh its cached size")
    ready.hooks.OnSizeChanged(ready, 170, 11)
    assert(heights == 2 and ready.Spark.height == 9 * 2.1, "a prepared hidden castbar ran a resize callback")
    ready.width, ready.height, combat = 170, 11, true
    SetVisible(ready, true)
    assert(ready.observer == child and child.attached == 1 and Observed(ready))
    assert(ready.Spark.height == 9 * 2.1 and readyPanel.width == 160, "a protected castbar was written in combat")
    combat = false
    ready.hooks.OnSizeChanged(ready, 170, 11)
    assert(ready.Spark.height == 9 * 2.1 and heights == 2)
    appearance.OnLayout(ready)
    assert(ready.Spark.height == 11 * 2.1 and readyPanel.width == 170, "the resize after a protected show was lost")

    -- A hidden spark keeps its alpha across the protected show without a child.
    local dark = Cast()
    dark.classicStyleCastBar, dark.protected, dark.visible = false, true, false
    assert(appearance.Apply(dark, { showSpark = false }))
    assert(not dark.observer and not Observed(dark) and dark.Spark.alpha == 0 and dark.Spark.height == 12)
    combat = true
    SetVisible(dark, true)
    assert(not Observed(dark) and dark.Spark.alpha == 0 and dark.Spark.height == 12,
        "the protected show changed a hidden spark")
    combat = false

    -- A withheld visibility prepares as well, and attaches with the OnShow.
    local veiled = Cast()
    veiled.classicStyleCastBar, veiled.protected, veiled.veiledShown = false, true, true
    assert(appearance.Apply(veiled, NativeStyle()))
    assert(veiled.observer and veiled.observer.attached == 0, "a castbar of withheld visibility was not prepared")
    combat = true
    SetVisible(veiled, true)
    assert(Observed(veiled) and veiled.observer.attached == 1)
    combat = false
end

print("Nameplate Castbar inherited outline, artwork, spark, reverse fill, interrupt effects and release passed")

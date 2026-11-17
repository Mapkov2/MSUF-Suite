local root = assert(arg[1], "Suite root is required")
local secret = setmetatable({}, {
    __index = function() error("Secret object was inspected") end,
    __add = function() error("Secret number was added") end,
    __sub = function() error("Secret number was subtracted") end,
    __lt = function() error("Secret number was compared") end,
    __le = function() error("Secret number was compared") end,
})
local combat = false
local private = {
    NS = {
        Public = function(value) return value ~= secret end,
        Finite = function(value)
            return value ~= secret and type(value) == "number"
                and value == value and value > -math.huge and value < math.huge
        end,
        Safety = { IsForbidden = function(region) return region.forbidden == true end },
        InCombat = function() return combat end,
    },
}
function hooksecurefunc(owner, method, callback)
    local original = assert(owner[method], method)
    owner[method] = function(self, ...)
        original(self, ...)
        callback(self, ...)
    end
end
assert(loadfile(root .. "/MSUF_Suite_Nameplates/CastGlowStyle.lua"))("Nameplates", private)
local Glow = private.CastGlowStyle

local function NewCast()
    local cast = { shown = false, fill = {}, hooks = {} }
    function cast:CanBeAccessedInContext() return not self.blocked end
    function cast:IsProtected() return self.protected == true end
    function cast:IsShown() return self.shown end
    function cast:GetStatusBarTexture() return self.fill end
    function cast:SetStatusBarTexture(fill) self.fill = fill end
    function cast:SetStatusBarColor() error("Glow wrote to the native cast color") end
    function cast:HookScript(name, callback)
        assert(name == "OnHide", "unnecessary native script hook " .. name)
        assert(not self.hooks[name], "duplicate script hook")
        self.hooks[name] = callback
    end
    function cast:HandleCastStart(kind, value, total)
        self.casting, self.channeling, self.reverseChanneling = kind == "standard", kind == "channel", kind == "empowered"
        self.shown, self.barType, self.value, self.maxValue = true, kind, value, total
    end
    function cast:HandleCastDelayed(value, total) self.value, self.maxValue = value, total end
    cast.HandleChannelUpdateDelayed = cast.HandleCastDelayed
    function cast:PlayFadeAnim() self.faded = true end
    function cast:PlayInterruptAnims() self.interrupted = true end
    function cast:CreateTexture(_, layer, _, subLevel)
        assert(layer == "ARTWORK" and subLevel == 1 and not self.overlay)
        local texture = { anchored = 0, hides = 0 }
        self.overlay = texture
        function texture:SetColorTexture(r, g, b, a)
            assert(r == 1 and g == 1 and b == 1 and a == 1)
        end
        function texture:SetBlendMode(mode) assert(mode == "BLEND") end
        function texture:CanBeAccessedInContext() return not self.blocked end
        function texture:Hide() self.shown, self.hides = false, self.hides + 1 end
        function texture:Show() self.shown = true end
        function texture:ClearAllPoints() self.anchor = nil end
        function texture:SetAllPoints(fill) self.anchor, self.anchored = fill, self.anchored + 1 end
        function texture:CreateAnimationGroup()
            local group = { plays = 0, stops = 0 }
            self.animation = group
            function group:SetScript(script, callback)
                assert(script == "OnFinished")
                self.finish = callback
            end
            function group:Play() self.plays = self.plays + 1 end
            function group:Stop() self.stops = self.stops + 1 end
            function group:CreateAnimation(kind)
                assert(kind == "Alpha")
                local step = {}
                function step:SetOrder(order) group[order] = self end
                function step:SetFromAlpha(alpha) self.from = alpha end
                function step:SetToAlpha(alpha) self.to = alpha end
                function step:SetDuration(duration) self.duration = duration end
                return step
            end
            return group
        end
        return texture
    end
    return cast
end

local function Approx(actual, expected)
    assert(math.abs(actual - expected) < .000001,
        string.format("expected %f, got %f", expected, actual))
end

local enabled = { glow = true }
local cast = NewCast()
assert(Glow.Apply(cast, {}) and not cast.overlay and not next(cast.hooks), "off loads no glow hooks or objects")
assert(Glow.Apply(cast, enabled) and not cast.overlay, "idle bar should not allocate a glow")
cast:HandleCastStart("standard", 0, 4)
local overlay, group = assert(cast.overlay), assert(cast.overlay.animation)
assert(overlay.shown and overlay.anchor == cast.fill and group.plays == 1, "cast did not start glow")
for i = 1, 4 do
    Approx(group[i].from, ((i - 1) / 4)^2)
    Approx(group[i].to, (i / 4)^2)
    Approx(group[i].duration, 1)
end
for _ = 1, 30 do assert(Glow.Apply(cast, enabled)) end
assert(overlay.anchored == 1 and group.plays == 1, "stable paint restarted the animation")
assert(Glow.Apply(cast, enabled, true))
assert(overlay.anchored == 2 and group.plays == 1, "layout reset did not preserve the running animation")
cast:SetStatusBarTexture({})
assert(overlay.anchor == cast.fill and overlay.anchored == 3, "new fill geometry was not tracked")
cast:HandleCastDelayed(1.5, 3)
assert(group.plays == 2 and group.stops == 1, "delayed cast should reschedule glow")
Approx(group[1].from, .25)
Approx(group[1].duration, .375)
cast:PlayFadeAnim()
assert(cast.faded and not overlay.shown and group.stops == 2, "glow leaked into successful fade")
cast.casting = nil
local hides = overlay.hides
for _ = 1, 30 do assert(Glow.Apply(cast, enabled)) end
assert(overlay.hides == hides, "idle repaint rewrote stopped glow visibility")

cast:HandleCastStart("channel", 2, 4)
Approx(group[1].from, .25)
Approx(group[1].duration, .5)
cast:HandleChannelUpdateDelayed(1, 4)
Approx(group[1].from, .5625)
Approx(group[1].duration, .25)
cast:PlayInterruptAnims()
assert(cast.interrupted and not overlay.shown and group.stops == 4, "glow leaked into red interrupt")
cast:HandleCastStart("standard", 0, 4)
cast.hooks.OnHide(cast)
assert(not overlay.shown and group.stops == 5, "pooled cast retained old glow")
cast:HandleCastStart("standard", 3, 4)
group.finish()
assert(not overlay.shown, "completed animation left a white overlay")
cast:HandleCastStart("standard", 3, 4)
assert(Glow.Restore(cast) and not overlay.shown)
cast:HandleCastStart("standard", 0, 4)
assert(not overlay.shown, "installed hooks ignored a disabled glow")

local inactive = NewCast()
assert(Glow.Apply(inactive, enabled))
inactive:HandleCastStart("empowered", 2, 4)
inactive:HandleCastStart("standard", secret, 4)
inactive:HandleCastStart("standard", 2, secret)
inactive:HandleCastStart(secret, 2, 4)
assert(not inactive.overlay, "empowered or restricted casts must not allocate a glow")
inactive:HandleCastStart("standard", 4, 4)
assert(not inactive.overlay, "expired cast allocated a glow")
inactive:SetStatusBarTexture(secret)
inactive:HandleCastStart("standard", 2, 4)
assert(not inactive.overlay, "secret fill was accessed")
inactive:SetStatusBarTexture({})
assert(Glow.Apply(inactive, enabled) and inactive.overlay.shown)
inactive.overlay.blocked = true
assert(Glow.Restore(inactive) == false, "temporary access failure was not passed to the caller")
inactive.overlay.blocked = false
assert(Glow.Restore(inactive) and not inactive.overlay.shown, "deferred restore did not clean up")

local protected = NewCast()
combat, protected.protected = true, true
assert(Glow.Apply(protected, enabled) == false and not next(protected.hooks), "combat protected writes were not deferred")
combat = false
protected:HandleCastStart("standard", 3, 4)
assert(Glow.Apply(protected, enabled) and protected.overlay.shown, "already-running cast was missed")
print("Nameplate glow: native cast progress, delays, texture rebind, fade/interrupt, reuse and secret guards")

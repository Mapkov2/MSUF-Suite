-- Plate lifecycle of the native texture skin, the aura-list hook, the
-- extension layout pass and the font lease:
-- lua suite_nameplates_lifecycle_contract.lua <repo root> [nameplates dir]
-- (the optional directory loads another Textures.lua / Auras.lua /
-- ExtensionLayout.lua / Text.lua, which is how the budgets below were seen failing on
-- the code before them).
local root = assert(arg[1])
local source = arg[2] or root .. "/MSUF_Suite_Nameplates"
local LOCKED, SECRET = {}, {}

------------------------------------------------------------------ world
local combat, events = false, {}
local publicChecks = 0
local hooks = {}
hooksecurefunc = function(owner, method, callback)
    local original = owner[method]
    owner[method] = function(self, ...)
        original(self, ...)
        callback(self, ...)
    end
    hooks[#hooks + 1] = { owner = owner, method = method, callback = callback }
end
function CreateFrame()
    local frame = {}
    function frame:SetScript(_, fn) self.event = fn end
    function frame:RegisterEvent(name) events[name] = self end
    function frame:UnregisterEvent(name) events[name] = nil end
    function frame:UnregisterAllEvents()
        for name, owner in pairs(events) do
            if owner == self then events[name] = nil end
        end
    end
    return frame
end
local function EndCombat()
    combat = false
    local frame = assert(events.PLAYER_REGEN_ENABLED, "nothing waited for the end of combat")
    frame.event(frame, "PLAYER_REGEN_ENABLED")
end
function CreateColor(r, g, b, a) return { r = r, g = g, b = b, a = a or 1 } end
C_CurveUtil = { EvaluateColorValueFromBoolean = function(value, ifTrue, ifFalse)
    return (value == LOCKED or value == true) and ifTrue or ifFalse
end }
NamePlateSetupOptions = { useClassicHealthBar = false }
CastingBarTypeInfo = {
    standard = { filling = "ui-castingbar-filling-standard", full = "ui-castingbar-full-standard" },
    interrupted = { filling = "ui-castingbar-interrupted", full = "ui-castingbar-interrupted" },
}
local function Public(value)
    publicChecks = publicChecks + 1
    return value ~= SECRET and value ~= LOCKED
end
local NS = {
    Public = Public,
    Client = { isForever = false },
    Finite = function(value) return type(value) == "number" and value == value end,
    Safety = { IsForbidden = function(region) return region.forbidden == true end },
    AnchorPoints = {},
    HostBridge = { CurrentFrameProfile = function() end, Namespace = function()
        return { Public = { ResolveCastbarColors = function() return .2, .5, .8, .8, .3, .1 end } }
    end },
    RGB = function(hex)
        return tonumber(hex:sub(1, 2), 16) / 255, tonumber(hex:sub(3, 4), 16) / 255, tonumber(hex:sub(5, 6), 16) / 255
    end,
    IsCombatLocked = function() return combat end,
    ResolveTexture = function(key) return key end,
}
local observed = 0
local private = {
    NS = NS, Suite = NS,
    Selection = { RepaintBackground = function() end },
    Layout = { Observe = function() observed = observed + 1 end },
    PlatePrefix = function(uf) return uf.isFriend and "friendly" or "enemy" end,
}
assert(loadfile(root .. "/MSUF_Suite/Core/HostBridgeBars.lua"))("Suite", NS)
assert(loadfile(root .. "/MSUF_Suite/Core/NameplateStyle.lua"))("Suite", NS)
assert(loadfile(root .. "/MSUF_Suite/Core/NameplateAuraDisplay.lua"))("Suite", NS)
assert(loadfile(source .. "/Textures.lua"))("Nameplates", private)
local T = private.Textures

-- A texture region that stores scalars only: the fixture must not allocate
-- while a plate cycles, so growth with the collector stopped is the Suite's.
local function Region(atlas)
    local region = { atlas = atlas, textures = 0, atlases = 0, colors = 0, offsets = 0 }
    function region:CanBeAccessedInContext() return not self.locked end
    function region:SetTexture(path)
        assert(not self.locked and not self.forbidden, "wrote a restricted region")
        self.atlas, self.path, self.textures = nil, path, self.textures + 1
        return true
    end
    function region:SetAtlas(value)
        assert(not self.locked and not self.forbidden, "wrote a restricted region")
        self.atlas, self.path, self.atlases, self.slice = value, nil, self.atlases + 1, true
    end
    function region:ClearTextureSlice() self.slice = nil end
    function region:SetTexCoord(left) self.left = left end
    function region:SetDrawLayer(layer) self.layer = layer end
    function region:SetTextureSliceMargins() self.slice = true end
    function region:SetVertexColor(r, g, b)
        assert(not self.locked and not self.forbidden, "wrote a restricted region")
        self.r, self.g, self.b, self.colors = r, g, b, self.colors + 1
    end
    function region:SetVertexColorFromBoolean(value, ifTrue, ifFalse)
        local color = C_CurveUtil.EvaluateColorValueFromBoolean(value, ifTrue, ifFalse)
        self:SetVertexColor(color.r, color.g, color.b)
    end
    function region:SetColorTexture(r) self.solid = r end
    function region:SetVertexOffset() self.offsets = self.offsets + 1 end
    return region
end

local function Plate(unit)
    local health = { barTexture = Region("UI-HUD-CoolDownManager-Bar"), bgTexture = Region("UI-HUD-CoolDownManager-Bar-BG") }
    local cast = { Background = Region("ui-castingbar-background"), barType = "standard", unit = unit, shown = false,
        fill = Region("ui-castingbar-filling-standard"), statusWrites = 0 }
    function cast:IsShown() return self.shown end
    function cast:IsVisible() return self.shown end
    function cast:IsProtected() return false end
    function cast:GetStatusBarTexture() return self.fill end
    function cast:SetStatusBarColor(r, g, b) self.r, self.g, self.b = r, g, b end
    function cast:SetStatusBarTexture(asset)
        self.asset, self.statusWrites = asset, self.statusWrites + 1
        if asset:find("^ui%-castingbar%-") then self.fill:SetAtlas(asset) else self.fill:SetTexture(asset) end
        return true
    end
    function cast:SetColorFill() end
    function cast:PlayInterruptAnims() end
    function cast:PlayFinishAnim() end
    function cast:HookScript(name, callback) self[name] = callback end
    function cast:UpdateBarFillTexture(full)
        self:SetStatusBarTexture(full and "ui-castingbar-full-standard" or "ui-castingbar-filling-standard")
        self:SetStatusBarColor(1, 1, 1)
    end
    local uf = { unit = unit, HealthBarsContainer = { healthBar = health }, CastBarsContainer = { castBar = cast } }
    return uf, health, cast
end
local notInterruptible = false
function UnitCastingInfo() return nil, nil, nil, nil, nil, nil, nil, notInterruptible end
function UnitChannelInfo() return nil end

-- Blizzard's acquire (NamePlateBaseMixin:SetUnit -> ApplyFrameOptions ->
-- UpdateAnchors) rewrites the bar and castbar art before NAME_PLATE_UNIT_ADDED.
local function NativeAcquire(health, cast)
    health.barTexture:SetAtlas("UI-HUD-CoolDownManager-Bar")
    health.bgTexture:SetAtlas("UI-HUD-CoolDownManager-Bar-BG")
    cast.Background:SetAtlas("ui-castingbar-background")
end

local function Grown(cycles, fn)
    fn()
    collectgarbage("collect")
    collectgarbage("stop")
    local before = collectgarbage("count")
    for _ = 1, cycles do fn() end
    local grown = collectgarbage("count") - before
    collectgarbage("restart")
    return grown
end
local function Instructions(fn)
    local count = 0
    debug.sethook(function() count = count + 1 end, "", 1)
    fn()
    debug.sethook()
    return count
end

------------------------------------------------------------------ textures
local config = { nativeHealthFillTexture = "health", nativeHealthBackgroundTexture = "healthBack",
    nativeCastFillTexture = "cast", nativeCastBackgroundTexture = "castBack" }
T.Configure(config)
local uf, health, cast = Plate("nameplate1")
local other, otherHealth, otherCast = Plate("nameplate2")

local function Assets(counter)
    return health.barTexture[counter] + health.bgTexture[counter] + cast.Background[counter]
end

-- A hidden castbar never takes the background. The health textures are
-- applied and restored normally, without allocating during the recycle.
local function Cycle()
    NativeAcquire(health, cast)
    T.Apply(uf)
    T.Restore(uf)
end
cast.shown = true
T.Apply(uf)
assert(health.barTexture.path == "health" and health.bgTexture.path == "healthBack"
    and cast.Background.path == "castBack" and health.bgTexture.offsets == 4, "a new plate was not textured")
assert(observed == 1, "a textured plate did not observe native layout resets")
T.Restore(uf)
assert(health.barTexture.atlas == "UI-HUD-CoolDownManager-Bar" and health.bgTexture.atlas == "UI-HUD-CoolDownManager-Bar-BG"
    and cast.Background.atlas == "ui-castingbar-background" and health.bgTexture.r == 1
    and cast.Background.r == 1 and health.bgTexture.offsets == 8, "a released plate kept Suite art")
assert(not T.HasHealthBackground(uf), "a released plate still reported a custom background")
cast.shown = false

do
    local pooled, nativeHealth, nativeCast = Plate("nameplate4")
    NativeAcquire(nativeHealth, nativeCast)
    T.Apply(pooled)
    local writes = nativeHealth.barTexture.atlases
    T.Restore(pooled, true)
    assert(nativeHealth.barTexture.atlases == writes and nativeHealth.barTexture.path == "health",
        "recycling repainted the native fill before Blizzard's reset")
    assert(nativeHealth.bgTexture.atlas == "UI-HUD-CoolDownManager-Bar-BG"
        and nativeHealth.bgTexture.offsets == 8 and nativeHealth.bgTexture.r == 1,
        "recycling left background styling behind")
    NativeAcquire(nativeHealth, nativeCast)
    T.OnAnchors(pooled)
    assert(nativeHealth.barTexture.atlas == "UI-HUD-CoolDownManager-Bar", "old textures ran during native acquire")
    T.Apply(pooled)
    assert(nativeHealth.barTexture.path == "health", "restyled plate skipped the reset native fill")
    T.Restore(pooled)
    assert(nativeHealth.barTexture.atlas == "UI-HUD-CoolDownManager-Bar", "visible rollback skipped native fill restore")
end

do
    local nativeNameOnly, nativeHealth, nativeCast = Plate("nameplate3")
    nativeNameOnly.showOnlyName = true
    NativeAcquire(nativeHealth, nativeCast)
    T.Apply(nativeNameOnly)
    assert(nativeHealth.barTexture.textures == 0 and T.HasHealthBackground(nativeNameOnly),
        "a names-only plate touched its hidden fill or gave up its background ownership")
    nativeNameOnly.showOnlyName = false
    T.OnAnchors(nativeNameOnly)
    assert(nativeHealth.barTexture.path == "health" and nativeHealth.bgTexture.path == "healthBack",
        "the native anchor rebuild did not style the exposed health bar")
    nativeNameOnly.showOnlyName = true
    NativeAcquire(nativeHealth, nativeCast)
    T.OnAnchors(nativeNameOnly)
    assert(T.HasHealthBackground(nativeNameOnly)
        and nativeHealth.barTexture.atlas == "UI-HUD-CoolDownManager-Bar", "the hidden health bar kept its custom fill")
    local offsets = nativeHealth.bgTexture.offsets
    config.nativeHealthBackgroundTexture = "another background"
    T.Configure(config)
    T.Apply(nativeNameOnly)
    assert(nativeHealth.bgTexture.path == "another background" and nativeHealth.bgTexture.offsets == offsets,
        "changing only the fitted background asset also resized it")
    config.nativeHealthBackgroundTexture = "healthBack"
    T.Configure(config)
    T.Restore(nativeNameOnly)
end

do
    local textures, atlases, seen = Assets("textures"), Assets("atlases"), observed
    local kilobytes = Grown(100, Cycle)
    local wroteTextures, wroteAtlases = Assets("textures") - textures, Assets("atlases") - atlases
    -- 101 cycles: two health assets and two restorations, plus three native
    -- atlas writes per acquisition from the fixture.
    assert(wroteTextures == 202 and wroteAtlases == 505,
        ("a plate cycle changed its asset writes (%d textures, %d atlases)"):format(wroteTextures, wroteAtlases))
    assert(observed == seen + 101, "each cycle observes its plate once")
    print(("textured plate cycle: %.2f KB per 100 acquire/apply/release"):format(kilobytes))
    assert(kilobytes == 0, "100 plate cycles allocated " .. kilobytes .. " KB of texture state")
end

-- Nothing of a finished cycle reaches the next plate on the same frames: an
-- interrupted, locked cast leaves no color, kind or owner behind.
do
    NativeAcquire(health, cast)
    cast.shown, notInterruptible = true, true
    cast.barType = SECRET
    T.Apply(uf)
    cast:UpdateBarFillTexture(false)
    assert(cast.asset == "cast" and cast.fill.r == .8 and cast.fill.g == .3, "a locked cast lost its texture or color")
    cast:PlayInterruptAnims()
    assert(cast.fill.r == 1 and cast.fill.g == .25, "an interrupted cast was not recolored")
    T.Restore(uf)
    assert(health.barTexture.atlas and cast.Background.atlas, "release left Suite art on an interrupted plate")
    -- The next unit on the pooled frame is already casting an ordinary
    -- spell when its plate appears: the plate pass paints the running cast.
    NativeAcquire(health, cast)
    notInterruptible, cast.barType = false, "standard"
    cast:SetStatusBarTexture("ui-castingbar-filling-standard")
    T.Apply(uf)
    assert(cast.asset == "cast" and cast.fill.r == .2 and cast.fill.b == .8,
        "a recycled castbar kept the last plate's interrupt or lock color")
    cast:UpdateBarFillTexture(false)
    assert(cast.asset == "cast" and cast.fill.r == .2 and cast.fill.b == .8,
        "a native fill update on a recycled castbar lost the Suite texture or color")
    cast:PlayFinishAnim()
    assert(cast.fill.r == .2, "a finished cast on a recycled plate lost its color")

    -- Another plate cycles meanwhile: this one's regions stay untouched.
    local writes = Assets("textures") + cast.statusWrites
    NativeAcquire(otherHealth, otherCast)
    T.Apply(other)
    T.Restore(other)
    T.Apply(other)
    assert(otherHealth.barTexture.path == "health" and otherCast.Background.atlas == "ui-castingbar-background")
    assert(Assets("textures") + cast.statusWrites == writes, "another plate's cycle wrote this plate's regions")
    for _ = 1, 3 do
        T.Apply(uf)
        T.Apply(other)
    end
    assert(Assets("textures") + cast.statusWrites == writes, "an unchanged plate was textured again")
end

-- A refused release (restricted region in combat) keeps its state and
-- finishes at the end of combat; the plate then cycles as any other.
do
    combat, health.bgTexture.locked = true, true
    T.Restore(uf)
    assert(health.bgTexture.path == "healthBack" and events.PLAYER_REGEN_ENABLED,
        "a refused release was not held for the end of combat")
    assert(T.HasHealthBackground(uf), "a refused release forgot the background it still has to restore")
    health.bgTexture.locked = false
    EndCombat()
    assert(health.bgTexture.atlas == "UI-HUD-CoolDownManager-Bar-BG" and health.barTexture.atlas
        and cast.Background.atlas and not events.PLAYER_REGEN_ENABLED, "the held release did not finish after combat")
    cast.shown = false
    T.Apply(uf)
    assert(health.bgTexture.path == "healthBack" and health.barTexture.path == "health",
        "a plate was not textured after a held release")

    -- A forbidden plate is never written, on either side of a cycle.
    local forbidden, forbiddenHealth = Plate("nameplate3")
    forbidden.forbidden = true
    T.Apply(forbidden)
    T.Restore(forbidden)
    assert(forbiddenHealth.barTexture.textures == 0 and forbiddenHealth.barTexture.atlases == 0, "wrote a forbidden plate")

    -- Switching the textures off releases every plate, also a recycled one.
    assert(T.Configure({}) == true, "switching textures off must ask for a release")
    T.RestoreAll()
    assert(health.barTexture.atlas and health.bgTexture.atlas and cast.Background.atlas
        and otherHealth.barTexture.atlas and otherCast.Background.atlas, "switching textures off left Suite art")
    local atlases, textures = Assets("atlases"), Assets("textures")
    T.Apply(uf)
    T.Restore(uf)
    assert(Assets("atlases") == atlases and Assets("textures") == textures, "an untextured plate was written")
end

------------------------------------------------------------------ auras
C_Secrets = { ShouldAurasBeSecret = function() return false end }
C_Timer = { After = function() error("no duplicate filter is active") end }
assert(loadfile(source .. "/Auras.lua"))("Nameplates", private)
local Auras = private.Auras
local module = { active = true, config = { auraClickthrough = true },
    auraHooks = setmetatable({}, { __mode = "k" }), auraButtons = setmetatable({}, { __mode = "k" }), pendingPlates = {} }
Auras.Bind(module)

local function Button()
    local button = { clicks = true, writes = 0 }
    function button:CanBeAccessedInContext() return true end
    function button:IsProtected() return self.protected == true end
    function button:IsMouseClickEnabled() return self.clicks end
    function button:GetParent() return self.parent end
    function button:SetMouseClickEnabled(value) self.clicks, self.writes = value, self.writes + 1 end
    return button
end
local function AuraPlate()
    local active, counts, walks = {}, 0, 0
    local auras = { DebuffListFrame = {}, BuffListFrame = {}, CrowdControlListFrame = {} }
    auras.auraItemFramePool = {
        GetNumActive = function()
            counts = counts + 1
            return #active
        end,
        GetNextActive = function(_, current)
            if current == nil then
                walks = walks + 1
                return active[1]
            end
            for i = 1, #active do
                if active[i] == current then return active[i + 1] end
            end
        end,
        EnumerateActive = function() error("EnumerateActive allocates an iterator per refresh") end,
    }
    function auras:RefreshList() end
    function auras:RefreshLossOfControl() end
    -- Both clients: debuffs, buffs, then crowd control (RefreshAuras).
    function auras:RefreshAuras()
        self:RefreshList(self.DebuffListFrame)
        self:RefreshList(self.BuffListFrame)
        self:RefreshList(self.CrowdControlListFrame)
    end
    return { AurasFrame = auras }, auras, active, function() return counts, walks end
end

do
    local plate, auras, active, Reads = AuraPlate()
    active[1], active[2] = Button(), Button()
    Auras.Apply(plate)
    assert(module.auraHooks[auras] == plate, "the aura frame lost its plate")
    assert(active[1].clicks == false and active[2].clicks == false and active[1].writes == 1,
        "shown aura buttons kept their clicks")
    local counts, walks = Reads()
    assert(counts == 1 and walks == 1)

    -- A refresh with no more buttons than the last complete walk: the two
    -- first lanes do nothing, the last one asks the pool for its count once.
    auras:RefreshAuras()
    counts, walks = Reads()
    assert(counts == 2 and walks == 1 and active[1].writes == 1, "an unchanged aura refresh walked the pool or wrote a button")

    -- Budget (Lua 5.1 VM instructions, this fixture's Public and wrapper
    -- included): a lane that is not the last cost 42 with a frame field
    -- read and two checks, 29 with the lane checked once against the lane
    -- Observe verified; an unchanged refresh ran 8 checks, now 5. Two of
    -- three hook calls take the first path.
    local LANE_BUDGET, REFRESH_CHECKS = 29, 5
    local hook
    for _, entry in ipairs(hooks) do
        if entry.owner == auras and entry.method == "RefreshList" then hook = entry.callback end
    end
    assert(hook, "no aura-list post-hook")
    publicChecks = 0
    local lane = Instructions(function() hook(auras, auras.BuffListFrame) end)
    local laneChecks = publicChecks
    publicChecks = 0
    auras:RefreshAuras()
    print(("aura lane that is not the last: %d instructions, %d check(s); unchanged refresh: %d checks"):format(
        lane, laneChecks, publicChecks))
    assert(laneChecks == 1 and lane <= LANE_BUDGET,
        ("an intermediate aura lane cost %d instructions and %d checks (budget %d and 1)"):format(lane, laneChecks, LANE_BUDGET))
    assert(publicChecks <= REFRESH_CHECKS,
        "an unchanged aura refresh ran " .. publicChecks .. " checks (budget " .. REFRESH_CHECKS .. ")")
    assert(Grown(100, function() auras:RefreshAuras() end) == 0, "aura refreshes allocated")

    -- A restricted or missing lane is never compared; nothing runs for it.
    counts = Reads()
    hook(auras, SECRET)
    hook(auras, nil)
    assert(Reads() == counts, "a restricted or missing lane reached the pool")

    -- A button the pool had to create shows up on the last lane only.
    active[3] = Button()
    hook(auras, auras.DebuffListFrame)
    hook(auras, auras.BuffListFrame)
    assert(active[3].clicks == true, "an intermediate lane walked the pool")
    hook(auras, auras.CrowdControlListFrame)
    assert(active[3].clicks == false and active[3].writes == 1 and active[1].writes == 1,
        "a new aura button kept its clicks after the refresh completed")

    -- A protected button in combat waits with its plate; the plate pass at
    -- the end of combat walks again.
    active[4] = Button()
    active[4].protected, combat = true, true
    auras:RefreshAuras()
    assert(active[4].clicks == true and module.pendingPlates[plate] == true, "a protected aura button was written in combat")
    combat, module.pendingPlates[plate] = false, nil
    Auras.Apply(plate)
    assert(active[4].clicks == false and not module.pendingPlates[plate], "the held aura button stayed clickable after combat")

    -- Switched off: the hook stays (a secure hook cannot be removed), hands
    -- the clicks back and writes nothing more.
    module.config.auraClickthrough = false
    Auras.Apply(plate)
    assert(active[1].clicks == true and active[4].clicks == true and next(module.auraButtons) == nil,
        "switching click-through off kept aura buttons unclickable")
    active[5] = Button()
    auras:RefreshAuras()
    assert(active[5].clicks == true and active[5].writes == 0, "a disabled click-through wrote an aura button")
    module.config.auraClickthrough = true
    auras:RefreshAuras()
    assert(active[5].clicks == false and active[1].clicks == false, "re-enabled click-through missed buttons added meanwhile")
end

-- One Blizzard pool reuses buttons across lanes. A row override follows the
-- new lane even when the pool size is unchanged, and migration preserves the
-- original value on all the untouched rows.
do
    Auras.RestoreClicks()
    local plate, auras, active, Reads = AuraPlate()
    local buff, debuff, control = Button(), Button(), Button()
    buff.parent, debuff.parent, control.parent = auras.BuffListFrame, auras.DebuffListFrame, auras.CrowdControlListFrame
    active[1], active[2], active[3] = buff, debuff, control
    local loss = Button()
    auras.LossOfControlFrame = { AuraItemFrame = loss }
    local config = module.config
    config.auraEnemyDebuffClickthrough, config.auraEnemyControlClickthrough = 3, 3
    Auras.Configure(config)
    Auras.Apply(plate)
    assert(not buff.clicks and debuff.clicks and control.clicks and loss.clicks, "row override lost its inherited or explicit click state")
    assert(Reads() == 0, "the mixed row path used the homogeneous count")
    buff.parent, debuff.parent = auras.DebuffListFrame, auras.BuffListFrame
    auras:RefreshAuras()
    assert(buff.clicks and not debuff.clicks and control.clicks and loss.clicks, "recycled Blizzard button kept its previous lane's clicking")
    assert(buff.writes == 2 and debuff.writes == 1 and control.writes == 0 and loss.writes == 0, "recycled pool wrote an unchanged row")
    debuff.protected, combat = true, true
    debuff.parent = auras.DebuffListFrame
    auras:RefreshAuras()
    assert(not debuff.clicks and module.pendingPlates[plate], "protected mixed-row restoration did not defer")
    combat, module.pendingPlates[plate] = false, nil
    Auras.Apply(plate)
    assert(debuff.clicks, "protected mixed-row restoration did not finish after combat")
    plate.isFriend = true
    Auras.Apply(plate)
    assert(not buff.clicks and not debuff.clicks and not control.clicks and not loss.clicks, "enemy overrides leaked onto a friendly plate")
    config.auraFriendlyBuffClickthrough, config.auraFriendlyDebuffClickthrough, config.auraFriendlyControlClickthrough = 3, 3, 3
    Auras.Configure(config)
    Auras.Apply(plate)
    assert(buff.clicks and debuff.clicks and control.clicks and loss.clicks, "disabling all friendly rows left owned clicks disabled")
    local unseen, unseenAuras = AuraPlate()
    unseen.isFriend = true
    Auras.Apply(unseen)
    assert(not module.auraHooks[unseenAuras], "disabled rows attached click-through hooks to a fresh plate")
    config.auraEnemyDebuffClickthrough, config.auraEnemyControlClickthrough = nil, nil
    config.auraFriendlyBuffClickthrough, config.auraFriendlyDebuffClickthrough, config.auraFriendlyControlClickthrough = nil, nil, nil
    Auras.Configure(config)
end

-- An aura frame whose last lane is restricted or forbidden is not observed.
do
    local before = #hooks
    local plate, auras = AuraPlate()
    auras.CrowdControlListFrame = SECRET
    Auras.Apply(plate)
    local forbidden, forbiddenAuras = AuraPlate()
    forbiddenAuras.CrowdControlListFrame.forbidden = true
    Auras.Apply(forbidden)
    assert(#hooks == before and not module.auraHooks[auras] and not module.auraHooks[forbiddenAuras],
        "an aura frame without a readable last lane was hooked")
end

------------------------------------------------------------------ extension layout
-- The layout pass of the optional extensions runs once per plate lease:
-- L.Anchors on NAME_PLATE_UNIT_ADDED, L.Restore on NAME_PLATE_UNIT_REMOVED.
-- It writes six regions (unit frame, name, raid marker, castbar, cast icon,
-- cast text). 2026-11-16 Ironforge trace (32 added, 36 removed plates): the
-- preflight repeated safety checks for native regions. It now checks the
-- combat lock once, while the edits recheck permissions at the point of use.
do
    local forbiddenReads, combatReads, protectedReads, reapplied = 0, 0, 0, 0
    local log, logging = {}, true
    local XNS = setmetatable({
        IsSecret = function(value) return value == SECRET end,
        IsCombatLocked = function()
            combatReads = combatReads + 1
            return combat
        end,
        Safety = { IsForbidden = function(region)
            forbiddenReads = forbiddenReads + 1
            return region.forbidden == true
        end },
        Client = { isForever = false },
    }, { __index = NS })
    local P = { NS = XNS, Suite = XNS,
        Geometry = { Point = function(region, ...) region:SetPoint(...) end },
        Layout = { Reapply = function() reapplied = reapplied + 1 end, CastWidthDelta = function() return 0 end,
            Restore = function() error("an active module reapplies its layout") end } }
    assert(loadfile(source .. "/ExtensionLayout.lua"))("Nameplates", P)
    local L = P.ExtensionLayout
    local setup = NamePlateSetupOptions
    NamePlateSetupOptions = { castIconHeight = 12 }

    local function Frame(name)
        local frame = { name = name, level = 3 }
        local function Write(self, what)
            assert(not self.forbidden, "wrote the forbidden " .. name)
            assert(not (combat and self.protected), "wrote the protected " .. name .. " in combat")
            if logging then log[#log + 1] = name .. " " .. what end
        end
        function frame:IsProtected()
            protectedReads = protectedReads + 1
            return self.protected or false
        end
        function frame:GetFrameLevel() return self.level end
        function frame:SetFrameLevel(level)
            Write(self, "level")
            self.level = level
        end
        function frame:ClearAllPoints() Write(self, "clear") end
        function frame:SetPoint(point, owner, relative)
            Write(self, logging and point .. ">" .. owner.name .. "." .. relative)
        end
        return frame
    end
    local uf, cast = Frame("uf"), Frame("cast")
    uf.name, uf.RaidTargetFrame, uf.showOnlyName = Frame("name"), Frame("raid"), false
    uf.HealthBarsContainer, uf.CastBarsContainer = Frame("health"), Frame("casts")
    cast.Icon, cast.Text = Frame("icon"), Frame("text")
    local owner = { pendingPlates = {}, config = {}, active = true }
    local plan = { enemy = { foreground = true, iconAnchor = 2, raidAnchor = 2 } }
    local state = { uf = uf, cast = cast, health = uf.HealthBarsContainer, owner = owner, prefix = "enemy" }
    local function Acquire()
        state.plan = plan
        L.Anchors(state)
    end
    local function Pass(fn)
        forbiddenReads, combatReads, protectedReads, log = 0, 0, 0, {}
        local result = fn(state)
        return table.concat(log, ", "), result
    end
    local ACQUIRED = "cast level, cast clear, cast BOTTOMLEFT>casts.BOTTOMLEFT, cast BOTTOMRIGHT>casts.BOTTOMRIGHT, "
        .. "icon clear, icon RIGHT>cast.LEFT, text clear, text LEFT>cast.LEFT, raid clear, raid RIGHT>name.LEFT"
    local RELEASED = "cast level, icon clear, icon BOTTOMLEFT>casts.BOTTOMLEFT, cast clear, cast BOTTOM>icon.TOP, "
        .. "cast LEFT>casts.BOTTOMLEFT, cast RIGHT>casts.BOTTOMRIGHT, text clear, text LEFT>icon.RIGHT, "
        .. "raid clear, raid RIGHT>health.LEFT"
    -- Every case below runs before the budgets are judged, so the code
    -- before this budget is seen to write the same and to miss only it.
    local missed = {}
    local function Budget(label, value, budget)
        if value > budget then missed[#missed + 1] = ("%s %d (budget %d)"):format(label, value, budget) end
    end

    -- Acquire and release of one lease: every write once, in the old order.
    local wrote = Pass(Acquire)
    assert(wrote == ACQUIRED and cast.level == 13, "an acquired plate was laid out as: " .. wrote)
    local acquireForbidden, acquireCombat = forbiddenReads, combatReads
    assert(protectedReads == 0, "a layout pass out of combat read protection")
    assert(Pass(Acquire) == "" and forbiddenReads == 0 and combatReads == 0, "an unchanged plan ran a layout pass")
    local released
    wrote, released = Pass(L.Restore)
    assert(released == true and wrote == RELEASED and cast.level == 3 and reapplied == 1
        and not state.iconMoved and not state.raidMoved and not state.layoutPlan,
        "a released plate was handed back as: " .. wrote)
    local releaseForbidden, releaseCombat = forbiddenReads, combatReads
    Budget("acquire forbidden reads", acquireForbidden, 7)
    Budget("acquire combat reads", acquireCombat, 2)
    Budget("release forbidden reads", releaseForbidden, 7)
    Budget("release combat reads", releaseCombat, 2)

    -- Lua 5.1 VM instructions of the two passes, this fixture's frames and
    -- counters included: 1179 and 1181 before (17 forbidden and 7 combat
    -- reads each, every region moved), 766 and 768 after the change;
    -- the budgets are those +2 %. The passes themselves allocate nothing:
    -- the first lease after a collection interns the setting keys Icon and
    -- Raid build for a moved region again, so it runs before the count.
    local ACQUIRE_BUDGET, RELEASE_BUDGET = 784, 787
    logging = false
    local acquire = Instructions(Acquire)
    local release = Instructions(function() L.Restore(state) end)
    local function Lease()
        Acquire()
        L.Restore(state)
    end
    collectgarbage("collect")
    collectgarbage("stop")
    Lease()
    local kilobytes = collectgarbage("count")
    for _ = 1, 100 do Lease() end
    kilobytes = collectgarbage("count") - kilobytes
    collectgarbage("restart")
    logging = true
    print(("extension layout pass: acquire %d forbidden + %d combat reads, %d instructions; "
        .. "release %d + %d, %d instructions; %.2f KB per 100 leases"):format(
        acquireForbidden, acquireCombat, acquire, releaseForbidden, releaseCombat, release, kilobytes))
    Budget("acquire instructions", acquire, ACQUIRE_BUDGET)
    Budget("release instructions", release, RELEASE_BUDGET)
    assert(kilobytes == 0, "100 layout leases allocated " .. kilobytes .. " KB")

    -- A recycled plate is read again: the icon comes back forbidden, the
    -- pass leaves it and the castbar anchors that follow it alone, and
    -- nothing of that verdict reaches the lease after it.
    cast.Icon.forbidden = true
    wrote = Pass(Acquire)
    assert(wrote == "cast level, raid clear, raid RIGHT>name.LEFT" and not state.iconMoved and state.raidMoved,
        "a forbidden cast icon was laid out as: " .. wrote)
    Budget("forbidden icon: forbidden reads", forbiddenReads, 7)
    wrote, released = Pass(L.Restore)
    assert(released == true and wrote == "cast level, raid clear, raid RIGHT>health.LEFT",
        "a plate with a forbidden cast icon was handed back as: " .. wrote)
    cast.Icon.forbidden = nil
    wrote = Pass(Acquire)
    assert(wrote == ACQUIRED, "a plate kept the forbidden verdict of the lease before it: " .. wrote)

    -- Permission lost during the lease: the release writes nothing on the
    -- castbar, keeps what it still owes and finishes once it may.
    cast.forbidden = true
    wrote, released = Pass(L.Restore)
    assert(released == false and wrote == "" and state.iconMoved and state.raidMoved and state.baseCastLevel == 3,
        "a release wrote or forgot a plate whose castbar turned forbidden: " .. wrote)
    cast.forbidden = nil
    wrote, released = Pass(L.Restore)
    assert(released == true and wrote == RELEASED, "the held release finished as: " .. wrote)

    -- In combat the read-only preflight asks each region once, followed by
    -- the existing fresh guard at the native cast-layer edit.
    combat = true
    wrote = Pass(Acquire)
    assert(wrote == ACQUIRED and next(owner.pendingPlates) == nil, "an unprotected plate was laid out in combat as: " .. wrote)
    Budget("combat acquire protection reads", protectedReads, 8)
    Budget("combat acquire combat reads", combatReads, 2)
    for _, protected in ipairs({ true, SECRET }) do
        cast.Text.protected = protected
        wrote, released = Pass(L.Restore)
        assert(released == false and wrote == "" and owner.pendingPlates[uf] == true and state.iconMoved,
            "a release in combat wrote beside a protected cast text: " .. wrote)
        owner.pendingPlates[uf] = nil
    end
    cast.Text.protected, uf.protected = nil, true
    wrote, released = Pass(L.Restore)
    assert(released == false and wrote == "" and owner.pendingPlates[uf] == true and forbiddenReads == 1,
        "a protected unit frame was written or its parts were read in combat")
    uf.protected, owner.pendingPlates[uf] = nil, nil
    state.layoutPlan = nil
    cast.Icon.protected = true
    assert(Pass(Acquire) == "" and owner.pendingPlates[uf] == true and not state.layoutPlan,
        "an acquire in combat wrote beside a protected cast icon")
    cast.Icon.protected, owner.pendingPlates[uf], combat = nil, nil, false
    wrote, released = Pass(L.Restore)
    assert(released == true and wrote == RELEASED, "the release after combat finished as: " .. wrote)

    -- A plate without a castbar: its marker moves, no cast region is read.
    state.cast = nil
    wrote = Pass(Acquire)
    assert(wrote == "raid clear, raid RIGHT>name.LEFT", "a plate without a castbar was laid out as: " .. wrote)
    Budget("no castbar: forbidden reads", forbiddenReads, 3)
    wrote, released = Pass(L.Restore)
    assert(released == true and wrote == "raid clear, raid RIGHT>health.LEFT",
        "a plate without a castbar was handed back as: " .. wrote)
    -- A native edit earlier in the pass can change another region.
    state.cast = cast
    local setLevel = cast.SetFrameLevel
    function cast:SetFrameLevel(level)
        setLevel(self, level)
        uf.RaidTargetFrame.forbidden = true
    end
    wrote = Pass(Acquire)
    assert(not state.raidMoved and not wrote:find("raid clear", 1, true),
        "layout reused a permission answer after a native write")
    cast.SetFrameLevel = setLevel
    uf.RaidTargetFrame.forbidden = nil
    assert(select(2, Pass(L.Restore)) == true, "the plate could not restore after the callback")
    -- A forbidden unit frame ends the pass at its first read.
    state.cast, uf.forbidden = cast, true
    wrote, released = Pass(L.Restore)
    assert(released == false and wrote == "" and forbiddenReads == 1 and Pass(Acquire) == "" and forbiddenReads == 1,
        "a forbidden unit frame was written or its parts were read")
    uf.forbidden = nil

    NamePlateSetupOptions = setup
    assert(#missed == 0, "extension layout pass over budget: " .. table.concat(missed, "; "))
end

------------------------------------------------------------------ fonts
-- Text.Apply on NAME_PLATE_UNIT_ADDED and every refresh, Text.Restore on
-- NAME_PLATE_UNIT_REMOVED, Text.Invalidate after Blizzard's ApplyFrameOptions.
-- 2026-11-16 trace (25 applies/restores, PaintFonts 4.35 ms): every lease
-- wrote font, shadow color, shadow offset and tint in both directions, also
-- where the pooled label already held the value. A setter now runs for a
-- value that differs from the one read on acquire, or that cannot be known.
do
    NS.Suite = NS
    GameFontHighlightSmall = { GetFont = function() return "fallback.ttf", 10, "" end }
    assert(loadfile(root .. "/MSUF_Suite/Core/FontBridge.lua"))("Suite", NS)
    assert(loadfile(source .. "/Text.lua"))("Nameplates", private)
    local Text = private.Text

    -- A FontString that stores scalars only and counts reads and writes.
    local function Label()
        local label = { fonts = 0, shadows = 0, offsets = 0, colors = 0, reads = 0 }
        local function Writable(self) assert(not self.forbidden, "wrote a forbidden label") end
        function label:GetFont()
            self.reads = self.reads + 1
            return self.fontSecret and SECRET or self.path, self.size, self.flags
        end
        function label:SetFont(path, size, flags)
            Writable(self)
            self.fonts = self.fonts + 1
            if path == "missing.ttf" then return false end
            self.path, self.size, self.flags = path, size, flags
            return true
        end
        function label:GetShadowColor()
            self.reads = self.reads + 1
            if self.noShadow then return end
            return self.sr, self.sg, self.sb, self.shadowSecret and SECRET or self.sa
        end
        function label:SetShadowColor(r, g, b, a)
            Writable(self)
            self.sr, self.sg, self.sb, self.sa, self.shadows = r, g, b, a, self.shadows + 1
        end
        function label:GetShadowOffset()
            self.reads = self.reads + 1
            if self.noShadow then return end
            return self.sx, self.sy
        end
        function label:SetShadowOffset(x, y)
            Writable(self)
            self.sx, self.sy, self.offsets = x, y, self.offsets + 1
        end
        function label:GetTextColor()
            self.reads = self.reads + 1
            return self.r, self.g, self.b, self.colorSecret and SECRET or self.a
        end
        function label:SetTextColor(r, g, b, a)
            Writable(self)
            self.r, self.g, self.b, self.a, self.colors = r, g, b, a, self.colors + 1
        end
        return label
    end
    -- Blizzard's raw resets (acquire, ApplyFrameOptions): no setter of the
    -- label runs. Blizzard differs from the Suite style in every field,
    -- Equal in none.
    local function Blizzard(label)
        label.path, label.size, label.flags = "native.ttf", 10, ""
        label.sr, label.sg, label.sb, label.sa, label.sx, label.sy = 0, 0, 0, .5, 2, -2
        label.r, label.g, label.b, label.a = 1, .5, 0, 1
    end
    local function Equal(label)
        label.path, label.size, label.flags = "suite.ttf", 12, "OUTLINE"
        label.sr, label.sg, label.sb, label.sa, label.sx, label.sy = 0, 0, 0, 1, 1, -1
        label.r, label.g, label.b, label.a = 1, 1, 1, 1
    end
    local function IsBlizzard(label)
        return label.path == "native.ttf" and label.size == 10 and label.flags == "" and label.sr == 0 and label.sa == .5
            and label.sx == 2 and label.sy == -2 and label.r == 1 and label.g == .5 and label.b == 0 and label.a == 1
    end
    local function IsSuite(label)
        return label.path == "suite.ttf" and label.size == 12 and label.flags == "OUTLINE" and label.sr == 0 and label.sa == 1
            and label.sx == 1 and label.sy == -1 and label.r == 1 and label.g == 1 and label.b == 1 and label.a == 1
    end
    -- The setter calls since the last check.
    local function Wrote(label, fonts, shadows, offsets, colors, what)
        local pattern = "%d font, %d shadow color, %d shadow offset, %d text color"
        local got, want = pattern:format(label.fonts, label.shadows, label.offsets, label.colors),
            pattern:format(fonts, shadows, offsets, colors)
        assert(got == want, what .. ": wrote " .. got .. ", expected " .. want)
        label.fonts, label.shadows, label.offsets, label.colors = 0, 0, 0, 0
    end

    local scales = 0
    local enemy = { enabled = true, font = "suite.ttf", flags = "OUTLINE", shadow = true, shadowAlpha = 1,
        shadowX = 1, shadowY = -1, shadowKey = "true:1:1:-1", color = { r = 1, g = 1, b = 1, a = 1 },
        fontScale = function(region, flags) scales, region.scaleFlags = scales + 1, flags end }
    -- Another role without a font, a color or a shadow of its own.
    local friendly = { enabled = true, flags = "", shadow = false }
    local label = Label()

    -- Native values equal to the style in every field: nothing is written, in
    -- a new lease, a refresh, a release or a recycled lease.
    Equal(label)
    Text.Apply(label, enemy, 12, true)
    Text.Apply(label, enemy, 12, true)
    Text.Restore(label)
    Equal(label)
    Text.Apply(label, enemy, 12, true)
    Text.Restore(label)
    Wrote(label, 0, 0, 0, 0, "a label that already held the style")
    assert(scales == 0 and IsSuite(label), "a label that already held the style was scaled or changed")

    -- Every field differs: one setter each way, the natives come back exactly.
    Blizzard(label)
    Text.Apply(label, enemy, 12, true)
    Wrote(label, 1, 1, 1, 1, "a native label")
    assert(IsSuite(label) and scales == 1 and label.scaleFlags == "OUTLINE", "a native label was not styled")
    Text.Apply(label, enemy, 12, true)
    Wrote(label, 0, 0, 0, 0, "an unchanged refresh")
    Text.Restore(label)
    Wrote(label, 1, 1, 1, 1, "the release of a styled label")
    assert(IsBlizzard(label) and scales == 2 and label.scaleFlags == "", "a released label kept Suite text")
    Text.Restore(label)
    Wrote(label, 0, 0, 0, 0, "a second release")

    -- Each field on its own: a font write does not bring a shadow or tint
    -- write with it, and neither does a shadow color bring its offset.
    Blizzard(label)
    label.sa, label.sx, label.sy, label.g, label.b = 1, 1, -1, 1, 1
    Text.Apply(label, enemy, 12, true)
    Wrote(label, 1, 0, 0, 0, "a label with a native font only")
    assert(IsSuite(label))
    Text.Restore(label)
    Wrote(label, 1, 0, 0, 0, "the release of a label with a native font only")
    assert(label.path == "native.ttf" and label.size == 10 and label.flags == "" and label.sa == 1)
    Equal(label)
    label.sa, label.g = .5, .5
    Text.Apply(label, enemy, 12, true)
    Wrote(label, 0, 1, 0, 1, "a label with a native shadow color and text color only")
    assert(IsSuite(label))
    Text.Restore(label)
    Wrote(label, 0, 1, 0, 1, "the release of a label with a native shadow color and text color only")
    assert(label.path == "suite.ttf" and label.sa == .5 and label.g == .5 and scales == 4)

    -- The opposite role on the same pooled label, and back: each lease reads
    -- its own natives and leaves nothing to the next.
    Blizzard(label)
    Text.Apply(label, friendly, 0, true)
    Wrote(label, 0, 1, 0, 0, "a friendly lease")
    assert(label.path == "native.ttf" and label.sa == 0 and label.sx == 2 and label.sy == -2 and label.g == .5)
    Text.Restore(label)
    Wrote(label, 0, 1, 0, 0, "the release of a friendly lease")
    assert(IsBlizzard(label), "a friendly lease did not hand the natives back")
    Text.Apply(label, enemy, 12, true)
    Wrote(label, 1, 1, 1, 1, "an enemy lease after a friendly one")
    assert(IsSuite(label))

    -- Blizzard resets the label during the lease (ApplyFrameOptions).
    Blizzard(label)
    Text.Invalidate(label)
    Text.Apply(label, enemy, 12, true)
    Wrote(label, 1, 1, 1, 1, "a native reset during a lease")
    assert(IsSuite(label), "a native reset was not styled again")
    -- An invalidation that left the font: shadow and tint are unknown and
    -- are written, also the offset that happens to be right.
    label.sa, label.g = .5, .5
    Text.Invalidate(label)
    Text.Apply(label, enemy, 12, true)
    Wrote(label, 0, 1, 1, 1, "an invalidated shadow and tint")
    assert(IsSuite(label), "an invalidated shadow or tint was trusted")
    -- A font swapped from outside, without a hook: the new font and the
    -- shadow read with it become the originals; the offset just read is equal.
    label.path, label.sa = "other.ttf", .25
    Text.Apply(label, enemy, 12, true)
    Wrote(label, 1, 1, 0, 0, "an external font swap")
    assert(IsSuite(label))
    Text.Restore(label)
    Wrote(label, 1, 1, 1, 1, "the release after an external font swap")
    assert(label.path == "other.ttf" and label.size == 12 and label.sa == .25 and label.g == .5,
        "a release did not hand back the swapped font")

    -- A withheld font: no record, no write.
    local held = Label()
    Blizzard(held)
    held.fontSecret = true
    Text.Apply(held, enemy, 12, true)
    Text.Restore(held)
    Wrote(held, 0, 0, 0, 0, "a label with a withheld font")
    assert(Text.originals[held] == nil, "a withheld font left a record")
    -- Withheld shadow and text colors that are in fact equal: the shadow is
    -- written (nothing proves it), the tint waits for a readable color, and
    -- the release writes back neither.
    held.fontSecret = nil
    Equal(held)
    held.shadowSecret, held.colorSecret = true, true
    Text.Apply(held, enemy, 12, true)
    Wrote(held, 0, 1, 0, 0, "a label with withheld colors")
    Text.Restore(held)
    Wrote(held, 0, 0, 0, 0, "the release of a label with withheld colors")
    held.shadowSecret, held.colorSecret = nil, nil
    Blizzard(held)
    Text.Apply(held, enemy, 12, true)
    Text.Restore(held)
    Wrote(held, 2, 2, 2, 2, "a readable lease after a withheld one")
    assert(IsBlizzard(held))
    -- The other way round: the shadow color of the lease before is never
    -- written to a lease whose own was withheld.
    held.shadowSecret = true
    Text.Apply(held, enemy, 12, true)
    Wrote(held, 1, 1, 1, 1, "a lease with a withheld shadow color")
    Text.Restore(held)
    Wrote(held, 1, 0, 1, 1, "the release of a lease with a withheld shadow color")
    held.shadowSecret = nil
    -- Missing values: no flags, no shadow.
    Blizzard(held)
    held.flags, held.noShadow = nil, true
    Text.Apply(held, enemy, 12, true)
    Wrote(held, 1, 1, 1, 1, "a label without flags and shadow")
    Text.Restore(held)
    Wrote(held, 1, 0, 0, 1, "the release of a label without flags and shadow")
    assert(held.path == "native.ttf" and held.size == 10 and held.flags == "")
    held.noShadow = nil

    -- A font the client refuses falls back (S.SetFont: two writes), is tried
    -- again by every refresh with its shadow, as before, and is released to
    -- the natives.
    local refused = {}
    for key, value in pairs(enemy) do refused[key] = value end
    refused.font = "missing.ttf"
    Blizzard(held)
    Text.Apply(held, refused, 12, true)
    Wrote(held, 2, 1, 1, 1, "a refused font")
    assert(held.path == "fallback.ttf" and held.size == 12 and held.flags == "OUTLINE")
    Text.Apply(held, refused, 12, true)
    Wrote(held, 2, 1, 1, 0, "the refresh of a refused font")
    Text.Restore(held)
    Wrote(held, 1, 1, 1, 1, "the release of a refused font")
    assert(IsBlizzard(held), "a refused font was not released to the natives")

    -- A forbidden label is never written; one that turns forbidden keeps
    -- what its release still owes. A style switched off releases.
    held.forbidden = true
    Text.Apply(held, enemy, 12, true)
    Text.Restore(held)
    held.forbidden = nil
    Text.Apply(held, enemy, 12, true)
    Wrote(held, 1, 1, 1, 1, "a lease after a forbidden one")
    held.forbidden = true
    Text.Restore(held)
    held.forbidden = nil
    Wrote(held, 0, 0, 0, 0, "a forbidden release")
    Text.Apply(held, { enabled = false }, 0, true)
    Wrote(held, 1, 1, 1, 1, "a style switched off")
    assert(IsBlizzard(held), "a style switched off kept Suite text")

    -- A scale callback belongs to its lease: the release of the lease that
    -- ran it calls it once more, and a later lease of the same pooled label
    -- under a provider without one changes the font and calls nothing.
    local pooled, plain, before = Label(), {}, scales
    for key, value in pairs(enemy) do plain[key] = value end
    plain.fontScale = nil
    Blizzard(pooled)
    Text.Apply(pooled, enemy, 12, true)
    assert(scales == before + 1 and pooled.scaleFlags == "OUTLINE", "a scaled lease did not run its scale")
    Text.Restore(pooled)
    Wrote(pooled, 2, 2, 2, 2, "a scaled lease and its release")
    assert(scales == before + 2 and pooled.scaleFlags == "" and IsBlizzard(pooled),
        "the release of a scaled lease did not run its own scale")
    Text.Apply(pooled, plain, 12, true)
    Wrote(pooled, 1, 1, 1, 1, "an unscaled lease after a scaled one")
    assert(IsSuite(pooled) and scales == before + 2, "an unscaled lease ran a scale")
    Text.Restore(pooled)
    Wrote(pooled, 1, 1, 1, 1, "the release of an unscaled lease after a scaled one")
    assert(scales == before + 2 and pooled.scaleFlags == "" and IsBlizzard(pooled),
        "the release of an unscaled lease ran the scale of the lease before")

    -- Budgets over 101 leases (one warms up). Differing natives: one setter
    -- per field and direction, five reads (the font twice), no allocation.
    -- Equal natives: four reads and no setter at all.
    label.reads, scales = 0, 0
    local kilobytes = Grown(100, function()
        Blizzard(label)
        Text.Apply(label, enemy, 12, true)
        Text.Restore(label)
    end)
    local reads = label.reads
    Wrote(label, 202, 202, 202, 202, "101 leases of a native label")
    assert(reads == 505 and scales == 202, ("101 native leases ran %d reads and %d scale calls"):format(reads, scales))
    label.reads = 0
    local equalKilobytes = Grown(100, function()
        Equal(label)
        Text.Apply(label, enemy, 12, true)
        Text.Restore(label)
    end)
    Wrote(label, 0, 0, 0, 0, "101 leases of a label that already holds the style")
    assert(label.reads == 404 and scales == 202, "a lease of an equal label ran " .. label.reads / 101 .. " reads or a scale call")
    print(("font lease: %.2f KB per 100 native, %.2f KB per 100 equal acquire/apply/release"):format(kilobytes, equalKilobytes))
    assert(kilobytes == 0 and equalKilobytes == 0, "font leases allocated")

    Blizzard(label)
    label.reads = 0
    Text.Apply(label, friendly, 0, true)
    assert(label.reads == 2, "disabled shadow read native offsets")
    Text.Apply(label, { enabled = true, flags = "", shadow = true }, 0, true)
    assert(label.sx == 1 and label.sy == -1, "enabled shadow did not acquire its offsets")
    Text.Restore(label)
    assert(IsBlizzard(label), "enabling shadow mid-lease lost the native offset")

    local health = { Text = Label(), LeftText = Label(), RightText = Label() }
    function health:HookScript(script, callback)
        assert(script == "OnShow" and not self.onShow, "health fonts installed a second hook")
        self.onShow = callback
    end
    local labels = { health.Text, health.LeftText, health.RightText }
    for _, text in ipairs(labels) do Blizzard(text) end
    enemy.healthSize = 12
    Text.ApplyHealth(health, enemy, true)
    for _, text in ipairs(labels) do assert(text.reads == 0, "hidden health text read native values") end
    health.forbidden = true
    Text.CancelHealth(health)
    health.forbidden = false
    health.onShow(health)
    for _, text in ipairs(labels) do assert(text.reads == 0, "released health text painted a new unit") end
    Text.ApplyHealth(health, enemy, true)
    health.LeftText.forbidden = true
    health.onShow(health)
    assert(IsBlizzard(health.LeftText), "OnShow attempted to write a forbidden health label")
    health.LeftText.forbidden = false
    health.onShow(health)
    for _, text in ipairs(labels) do assert(IsSuite(text), "native OnShow did not style health text") end
    Text.RestoreHealth(health)
    for _, text in ipairs(labels) do assert(IsBlizzard(text), "health text did not restore") end
    Text.ApplyHealth(health, enemy, SECRET)
    for _, text in ipairs(labels) do assert(IsSuite(text), "a withheld state skipped visible styling") end

    local bar = { Text = Label(), CastTargetNameText = Label() }
    function bar:IsShown() return self.shown end
    function bar:HookScript(script, fn)
        assert(script == "OnShow" and not self.onShow, "cast fonts installed a second hook")
        self.onShow = fn
    end
    Blizzard(bar.Text)
    Blizzard(bar.CastTargetNameText)
    enemy.size = 12
    Text.ApplyCast(bar, enemy)
    assert(bar.Text.reads == 0 and bar.CastTargetNameText.reads == 0, "hidden cast fonts read native values")
    Text.RestoreCast(bar)
    bar.onShow(bar)
    assert(bar.Text.reads == 0, "released cast fonts painted a recycled bar")
    Text.ApplyCast(bar, enemy)
    bar.shown = true
    bar.onShow(bar)
    assert(IsSuite(bar.Text) and IsSuite(bar.CastTargetNameText), "visible cast fonts were not styled")
    bar.shown = false
    Text.RestoreCast(bar)
    assert(IsBlizzard(bar.Text) and IsBlizzard(bar.CastTargetNameText), "release did not restore visible cast fonts")
    bar.shown = true
    Text.ApplyCast(bar, enemy)
    assert(IsSuite(bar.Text), "acquiring an already active cast did not style it")
    bar.Text.forbidden = true
    Text.RestoreCast(bar)
    assert(IsSuite(bar.Text) and IsBlizzard(bar.CastTargetNameText), "release lost the withheld font restore")
    bar.Text.forbidden = false
    Text.ApplyCast(bar, { enabled = false })
    assert(IsBlizzard(bar.Text) and IsBlizzard(bar.CastTargetNameText), "disabled cast style did not retry the restore")
end

print("Nameplate lifecycle: allocation-free textured plate cycles, clean and refused release, recycled castbars, "
    .. "aura lane budget and click-through, extension layout pass budget, font lease setters and budget passed")

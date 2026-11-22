local root = ...
local function Hook(owner, key, callback)
    if type(owner) == "string" then owner, key, callback = _G, owner, key end
    local original = owner[key]
    owner[key] = function(self, ...)
        original(self, ...)
        callback(self, ...)
    end
end
hooksecurefunc = Hook
NamePlateSetupOptions = { useClassicHealthBar = false }
local reads, observes, checks = 0, 0, 0
local combat, events = false, {}
local sharedColors = { .2, .5, .8, .8, .3, .1 }
local secretLocked = {}
local secretInterruptible = {}
local sawSecretTint = false
function CreateColor(r, g, b, a)
    return { r = r, g = g, b = b, a = a or 1 }
end
C_CurveUtil = { EvaluateColorValueFromBoolean = function(value, ifTrue, ifFalse)
    return (value == secretLocked or value == true) and ifTrue or ifFalse
end }
function CreateFrame()
    local frame = {}
    function frame:SetScript(_, fn) self.event = fn end
    function frame:RegisterEvent(name) events[name] = self end
    function frame:UnregisterEvent(name) events[name] = nil end
    return frame
end
local function EndCombat()
    combat = false
    local frame = assert(events.PLAYER_REGEN_ENABLED)
    frame.event(frame)
    assert(not events.PLAYER_REGEN_ENABLED, "a completed retry retained its event")
end
local private = {
    Selection = { RepaintBackground = function() end },
    NS = {
        Public = function(value)
            return value ~= "secret" and value ~= secretLocked and value ~= secretInterruptible
        end,
        Safety = { IsForbidden = function(region)
            checks = checks + 1
            return region.forbidden
        end },
        AnchorPoints = {},
        HostBridge = { CurrentFrameProfile = function() end, Namespace = function()
            return { Public = { ResolveCastbarColors = function() return unpack(sharedColors) end } }
        end },
        RGB = function(hex)
            return tonumber(hex:sub(1, 2), 16) / 255, tonumber(hex:sub(3, 4), 16) / 255, tonumber(hex:sub(5, 6), 16) / 255
        end,
        IsCombatLocked = function() return combat end,
        ResolveTexture = function(key)
            reads = reads + 1
            return key
        end,
    },
    Layout = { Observe = function() observes = observes + 1 end },
}
private.Suite = private.NS
assert(loadfile(root .. "/MSUF_Suite_Nameplates/Modes.lua"))("Nameplates", private)
assert(loadfile(root .. "/MSUF_Suite/Core/HostBridgeBars.lua"))("Suite", private.NS)
local function Region(atlas)
    local region = { atlas = atlas, writes = 0 }
    function region:CanBeAccessedInContext() return not self.locked end
    function region:GetAtlas() return self.atlas end
    function region:GetTexture() return self.path end
    function region:SetTexture(path)
        assert(not self.locked and not self.forbidden)
        self.atlas, self.path, self.writes = nil, path, self.writes + 1
        return true
    end
    function region:SetAtlas(value)
        self.atlas, self.path = value, nil
        self.coords, self.slice = { .25, .75, .1, .9 }, true
    end
    function region:ClearTextureSlice() self.slice = nil end
    function region:SetTexCoord(...) self.coords = { ... } end
    function region:SetDrawLayer(layer) self.layer = layer end
    function region:SetTextureSliceMargins(...) self.slice = { ... } end
    function region:SetVertexColor(...) self.tint = { ... } end
    function region:SetVertexColorFromBoolean(value, ifTrue, ifFalse)
        if value == secretLocked then sawSecretTint = true end
        local color = C_CurveUtil.EvaluateColorValueFromBoolean(value, ifTrue, ifFalse)
        self:SetVertexColor(color.r, color.g, color.b, color.a)
    end
    function region:SetColorTexture(...) self.color = { ... } end
    function region:AddMaskTexture(mask) assert(not self.mask) self.mask = mask end
    function region:RemoveMaskTexture(mask) assert(self.mask == mask) self.mask = nil end
    function region:SetVertexOffset(index, x, y)
        assert(not self.locked and not self.forbidden, "restricted texture geometry write")
        self.vertices = self.vertices or {}
        self.vertices[index] = { x, y }
        self.vertexWrites = (self.vertexWrites or 0) + 1
    end
    return region
end

assert(loadfile(root .. "/MSUF_Suite/Core/NameplateStyle.lua"))("Suite", private.NS)
assert(loadfile(root .. "/MSUF_Suite_Nameplates/CastSettings.lua"))("Nameplates", private)
assert(loadfile((arg and arg[2]) or root .. "/MSUF_Suite_Nameplates/Textures.lua"))("Nameplates", private)
local T = private.Textures
local health = { barTexture = Region("native-health"), bgTexture = Region("native-background") }
local function FitsHealth(texture)
    -- Blizzard's Modern background quad has asymmetric outsets. After moving
    -- each vertex the drawn corners must coincide with the health bar.
    local native = { { -2, 3 }, { -2, -6 }, { 6, 3 }, { 6, -6 } }
    for i, point in ipairs(native) do
        local v = texture.vertices and texture.vertices[i]
        if not v or v[1] + point[1] ~= 0 or v[2] + point[2] ~= 0 then return false end
    end
    return true
end
local fill = Region("ui-castingbar-filling-standard")
local cast = { Background = Region("native-cast-background"), barType = "standard", unit = "nameplate1",
    color = { 1, 1, 1, 1 } }
CastingBarTypeInfo = {
    standard = { filling = "ui-castingbar-filling-standard", full = "ui-castingbar-full-standard" },
    channel = { filling = "ui-castingbar-filling-channel", full = "ui-castingbar-full-channel" },
    uninterruptable = { filling = "ui-castingbar-uninterruptable", full = "ui-castingbar-uninterruptable" },
    interrupted = { filling = "ui-castingbar-interrupted", full = "ui-castingbar-interrupted" },
}
cast.Background:SetAtlas("native-cast-background")
function cast:IsShown() return true end
function cast:IsVisible() return self.visible ~= false end
function cast:IsProtected() return self.protected == true end
function UnitCastingInfo() return nil, nil, nil, nil, nil, nil, nil, cast.notInterruptible end
function UnitChannelInfo() return nil, nil, nil, nil, nil, nil, cast.channelLocked end
function cast:GetStatusBarTexture() return fill end
function cast:SetStatusBarColor(...) self.color = { ... } end
function cast:SetStatusBarTexture(asset)
    if self.rejectCustom and asset == "cast" then return false end
    self.statusBarAsset, self.colorFill = asset, nil
    if asset:find("^ui%-castingbar%-") then
        fill:SetAtlas(asset)
    else
        if self.swapFill then
            self.swapFill = false
            fill = Region()
        end
        -- The widget can update its own region even if Lua can't write to it.
        local locked = fill.locked
        fill.locked = false
        local ok = fill:SetTexture(asset)
        fill.locked = locked
        if self.lockNewFill then fill.locked = true end
        fill:SetTexCoord(0, 1, 0, 1)
        fill:SetVertexColor(1, 1, 1, 1)
        if not self.noSetterResult then return ok end
        return
    end
    return true
end
function cast:SetColorFill(...) self.colorFill = { ... } end
function cast:PlayInterruptAnims() end
function cast:PlayFinishAnim()
    if self.resetOnFinish then fill:SetVertexColor(1, 1, 1, 1) end
end
function cast:RenderProgress()
    -- Model progress and fade draws using the widget's stored color.
    fill:SetVertexColor(unpack(self.color))
end
function cast:HookScript(name, callback)
    local previous = self[name]
    self[name] = previous and function(frame, ...)
        previous(frame, ...)
        callback(frame, ...)
    end or callback
end
function cast:UpdateBarFillTexture(full)
    if self.classicStyleCastBar then
        self:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
        self:SetStatusBarColor(0, 1, 0)
    else
        self:SetStatusBarTexture(full and self.fullAtlas or self.nativeAtlas)
        self:SetStatusBarColor(1, 1, 1)
    end
end
cast.statusBarAsset = fill.atlas
local uf = { HealthBarsContainer = { healthBar = health }, CastBarsContainer = { castBar = cast } }
private.PlatePrefix = function(frame) return frame.side or "enemy" end
local config = { nativeHealthFillTexture = "health", nativeHealthBackgroundTexture = "healthBack",
    nativeCastFillTexture = "cast", nativeCastBackgroundTexture = "castBack" }
T.Configure(config)
cast.barType, cast.notInterruptible = "secret", secretLocked
fill.atlas = "secret"
T.Apply(uf)
assert(health.barTexture.path == "health" and health.bgTexture.path == "healthBack")
assert(FitsHealth(health.bgTexture), "the selected Modern background extends past the health bar")
assert(fill.path == "cast" and cast.Background.path == "castBack")
assert(cast.statusBarAsset == "cast", "the status bar still uses Blizzard's atlas to calculate progress coordinates")
assert(sawSecretTint and fill.tint[1] == .8 and fill.tint[2] == .3, "restricted cast color must reach the active fill texture")
cast:RenderProgress()
assert(fill.tint[1] == .8 and fill.tint[2] == .3, "a running restricted cast rendered with the native color")
assert(cast.Background.coords[1] == 0 and cast.Background.coords[2] == 1
    and cast.Background.coords[3] == 0 and cast.Background.coords[4] == 1,
    "the custom castbar background kept atlas coordinates")
local initialChecks = checks
T.Configure(config)
for _ = 1, 100 do T.Apply(uf) end
assert(checks == initialChecks and reads == 4 and observes == 1, "unchanged plates still run texture work")
assert(health.barTexture.writes == 1 and fill.writes == 1 and cast.Background.writes == 1
    and health.bgTexture.vertexWrites == 4)
cast.nativeAtlas = "ui-castingbar-filling-channel"
cast.barType, cast.notInterruptible, cast.channelLocked = "secret", nil, secretLocked
cast:UpdateBarFillTexture(false)
assert(fill.tint[1] == .8 and fill.tint[2] == .3, "a channel already running when the plate appears lost its lock color")
cast.channelLocked = false
cast:UpdateBarFillTexture(false)
cast:SetStatusBarTexture(cast.nativeAtlas)
cast.noSetterResult = true
cast.swapFill = true
local originalFill = fill
cast:OnEvent("UNIT_SPELLCAST_CHANNEL_START")
cast.noSetterResult = false
assert(fill ~= originalFill, "test did not recreate the replacement widget")
assert(cast.statusBarAsset == "cast", "the final native start event left Blizzard's texture visible")
assert(fill.tint[1] == .2 and fill.tint[3] == .8, "the replacement must be tinted even when the setter returns no value")
combat, cast.lockNewFill, cast.swapFill = true, true, true
cast:OnEvent("UNIT_SPELLCAST_CHANNEL_START")
assert(fill.locked and cast.color[1] == .2 and cast.color[3] == .8 and events.PLAYER_REGEN_ENABLED,
    "a replacement whose texture cannot be accessed left the native bar white")
cast.lockNewFill, fill.locked, fill.slice = false, false, { 1, 1, 1, 1 }
EndCombat()
assert(fill.tint[1] == .2 and fill.tint[3] == .8 and not fill.slice,
    "retry did not finish preparing the replacement region")
local textureWrites = fill.writes
sharedColors[1] = .4
T.RefreshCastColors()
assert(fill.tint[1] == .4 and fill.writes == textureWrites, "a host color change should only recolor the active cast")
config.nativeCastFillColor = "00ff00"
T.Configure(config)
T.Apply(uf)
assert(fill.tint[1] == 0 and fill.tint[2] == 1, "the Nameplates override did not supersede the shared color")
config.nativeCastFillColor = ""
T.Configure(config)
T.Apply(uf)
assert(fill.tint[1] == .4, "clearing the override did not restore the shared color")
cast.nativeAtlas = "ui-castingbar-uninterruptable"
cast.barType = "uninterruptable"
cast:UpdateBarFillTexture(false)
assert(fill.path == "cast" and fill.tint[1] == .8 and fill.tint[2] == .3)
config.nativeCastLockedColor = "ff00ff"
T.Configure(config)
T.Apply(uf)
assert(fill.tint[1] == 1 and fill.tint[2] == 0 and fill.tint[3] == 1, "the locked color override was ignored")
config.nativeCastLockedColor = ""
T.Configure(config)
T.Apply(uf)
cast.barType, cast.notInterruptible = "secret", secretLocked
cast:UpdateBarFillTexture(false)
cast.notInterruptible, cast.channelLocked = nil, false
cast.fullAtlas = CastingBarTypeInfo.standard.full
cast:UpdateBarFillTexture(true)
assert(fill.tint[1] == .8 and fill.tint[2] == .3, "completion read interruptibility after the cast ended")
cast.resetOnFinish = true
cast:PlayFinishAnim()
assert(fill.tint[1] == .8 and fill.tint[2] == .3, "finish setup left the completed bar white")
cast:RenderProgress()
assert(fill.tint[1] == .8 and fill.tint[2] == .3, "the native fade still has a white status bar color")
cast.barType, cast.notInterruptible = "secret", secretInterruptible
cast:UpdateBarFillTexture(false)
cast.notInterruptible = nil
cast:UpdateBarFillTexture(true)
cast:PlayFinishAnim()
cast:RenderProgress()
assert(fill.tint[1] == .4 and fill.tint[3] == .8, "the finished restricted interruptible cast lost its active color")
cast.barType = "standard"
cast:UpdateBarFillTexture(false)
cast:RenderProgress()
assert(fill.tint[1] == .4 and fill.tint[3] == .8, "a running Fireball lost its inherited color")
cast:UpdateBarFillTexture(true)
cast:PlayFinishAnim()
cast:RenderProgress()
assert(fill.tint[1] == .4 and fill.tint[3] == .8, "the next completed cast inherited the previous lock")
config.nativeCastFillColor = "00ff00"
T.Configure(config)
T.Apply(uf)
cast:RenderProgress()
assert(fill.tint[1] == 0 and fill.tint[2] == 1, "a color change during fade left the previous native color")
config.nativeCastFillColor = ""
T.Configure(config)
T.Apply(uf)
config.nativeCastFillTexture = ""
T.Configure(config)
T.Apply(uf)
assert(cast.statusBarAsset == cast.fullAtlas and cast.color[1] == 1 and cast.color[2] == 1,
    "disabling the custom texture during fade retained its native color")
config.nativeCastFillTexture = "cast"
T.Configure(config)
T.Apply(uf)
cast.resetOnFinish = false
for _, kind in ipairs({ "standard", "channel", "uninterruptable", "interrupted" }) do
    cast.barType = kind
    cast.fullAtlas = CastingBarTypeInfo[kind].full
    cast:UpdateBarFillTexture(true)
    assert(cast.statusBarAsset == "cast" and fill.path == "cast" and not fill.slice,
        "a terminal cast state replaced the selected texture: " .. kind)
    if kind == "interrupted" then assert(fill.tint[1] > fill.tint[2]) end
end
cast.barType = "secret"
cast:PlayInterruptAnims()
cast:RenderProgress()
assert(fill.tint[1] == 1 and fill.tint[2] == .25, "the status bar lost its red interrupt feedback")
cast.barType = "uninterruptable"
function fill:GetAtlas() error("Cast texture readback is unavailable") end
function fill:GetTexture() error("Cast texture readback is unavailable") end
cast:UpdateBarFillTexture(false)
assert(fill.path == "cast")
health.bgTexture.vertices = nil -- Blizzard has just rebuilt the native art.
T.OnAnchors(uf)
assert(FitsHealth(health.bgTexture), "a native refresh lost the custom background fit")
assert(health.barTexture.writes == 2 and cast.Background.writes == 2 and observes == 1)
NamePlateSetupOptions.useClassicHealthBar = true
T.OnAnchors(uf)
assert(health.bgTexture.vertices[4][1] == 0 and health.bgTexture.vertices[4][2] == 0,
    "changing style retained Modern offsets")
NamePlateSetupOptions.useClassicHealthBar = false
T.OnAnchors(uf)
assert(FitsHealth(health.bgTexture), "returning to Modern lost the custom background fit")
config.enemyOutlineMode = 2
T.Configure(config)
T.Apply(uf)
assert(health.bgTexture.atlas == "UI-HUD-CoolDownManager-Bar-BG" and health.barTexture.path == "health",
    "the Blizzard outline must restore its background and keep the custom fill")
uf.side = "friendly"
T.Apply(uf)
assert(FitsHealth(health.bgTexture), "a faction change did not restore the custom background for the new side")
uf.side = "enemy"
T.Apply(uf)
assert(health.bgTexture.atlas == "UI-HUD-CoolDownManager-Bar-BG")
config.enemyOutlineMode = 3
T.Configure(config)
T.Apply(uf)
assert(FitsHealth(health.bgTexture), "Custom outline did not restore the selected background")
T.Restore(uf)
assert(fill.atlas == cast.nativeAtlas and cast.statusBarAsset == cast.nativeAtlas
    and cast.Background.atlas == "ui-castingbar-background")
assert(health.barTexture.atlas == "UI-HUD-CoolDownManager-Bar")
assert(health.bgTexture.atlas == "UI-HUD-CoolDownManager-Bar-BG")
for i = 1, 4 do
    assert(health.bgTexture.vertices[i][1] == 0 and health.bgTexture.vertices[i][2] == 0,
        "reset retained an offset on Blizzard's artwork")
end
cast:UpdateBarFillTexture(false)
assert(fill.atlas == cast.nativeAtlas, "a released plate still overrides its castbar")
T.OnAnchors(uf)
assert(health.barTexture.atlas == "UI-HUD-CoolDownManager-Bar", "a pooled plate was repainted")

NamePlateSetupOptions.useClassicHealthBar = true
cast.classicStyleCastBar = true
health.bgTexture.locked = true
T.Apply(uf)
assert(health.bgTexture.atlas == "UI-HUD-CoolDownManager-Bar-BG")
health.bgTexture.locked = false
T.Apply(uf)
assert(health.bgTexture.path == "healthBack" and health.bgTexture.coords[3] == 0)
assert(not FitsHealth(health.bgTexture), "Classic border art received Modern offsets")
T.Configure({})
T.Restore(uf)
assert(health.bgTexture.path == "Interface\\Tooltips\\Nameplate-Border" and health.bgTexture.coords[3] == .5)
assert(cast.Background.color[4] == .5 and cast.Background.tint[4] == 1)

NamePlateSetupOptions.useClassicHealthBar = false
cast.classicStyleCastBar = false
T.Configure(config)
T.Apply(uf)
combat, fill.locked = true, true
local healthWritesBeforeCast = health.barTexture.writes
cast:UpdateBarFillTexture(false)
assert(fill.path == "cast" and cast.color[1] == .8 and cast.color[2] == .3 and events.PLAYER_REGEN_ENABLED,
    "the inaccessible old cast texture prevented replacing the asset and applying color")
fill.locked = false
EndCombat()
assert(fill.path == "cast")
assert(health.barTexture.writes == healthWritesBeforeCast, "a cast-only retry rewrote the health fill")

cast.rejectCustom = true
cast.barType, cast.notInterruptible = "secret", secretInterruptible
cast.nativeAtlas = CastingBarTypeInfo.standard.filling
cast:UpdateBarFillTexture(false)
assert(fill.atlas == cast.nativeAtlas and cast.color[1] == .4 and cast.color[3] == .8,
    "the active cast was left white when the status bar declined the replacement asset")
config.nativeCastFillTexture = ""
T.Configure(config)
T.Apply(uf)
assert(fill.atlas == cast.nativeAtlas and cast.color[1] == 1 and cast.color[2] == 1 and cast.color[3] == 1,
    "disabling the custom cast texture retained a color-only override")
config.nativeCastFillTexture, cast.rejectCustom = "cast", false
cast.barType, cast.notInterruptible = "standard", nil
T.Configure(config)
T.Apply(uf)

combat, fill.locked, health.bgTexture.locked = true, true, true
T.Configure({})
T.RestoreAll()
assert(fill.path == "cast" and health.bgTexture.path == "healthBack")
fill.locked, health.bgTexture.locked = false, false
EndCombat()
assert(fill.atlas == cast.nativeAtlas and health.bgTexture.atlas == "UI-HUD-CoolDownManager-Bar-BG")

combat = true
uf.CanBeAccessedInContext = function() return not combat end
T.Configure(config)
T.Apply(uf)
assert(events.PLAYER_REGEN_ENABLED and fill.atlas == cast.nativeAtlas)
T.Configure({})
T.RestoreAll()
assert(not events.PLAYER_REGEN_ENABLED, "turning textures off retained a deferred paint")
combat = false
uf.forbidden = true
T.Configure(config)
T.Apply(uf)
assert(health.bgTexture.atlas == "UI-HUD-CoolDownManager-Bar-BG" and observes == 3,
    "a forbidden plate reached the layout hook")

uf.forbidden = false
T.Apply(uf)
cast:SetColorFill(0, 0, 0, 0)
cast.barType = "secret"
config.nativeCastFillTexture = "differentCast"
T.Configure(config)
T.Apply(uf)
assert(cast.colorFill and cast.colorFill[4] == 0, "a texture change replaced the empowered stage backing")
cast:UpdateBarFillTexture(true)
assert(cast.statusBarAsset == cast.fullAtlas, "an empowered finish was painted over its stage art")
cast.barType = "uninterruptable"
cast:UpdateBarFillTexture(false)
assert(cast.statusBarAsset == "differentCast", "the next normal cast did not pick up the new texture")
config.look = 1
T.Configure(config)
T.Apply(uf)
assert(cast.Background.tint[1] > 0, "Jundies tinted a custom background pure black")
config.nativeCastBackgroundTexture = "Solid"
T.Configure(config)
T.Apply(uf)
assert(cast.Background.tint[1] == 0 and cast.Background.tint[4] == .5, "Jundies lost its default dark background")
T.Restore(uf)
config.look, config.nativeCastFillTexture, config.nativeCastBackgroundTexture = nil, "cast", "castBack"
T.Configure(config)
do
    local previewOptions = { Suite = setmetatable({
        ResolveTexture = function(key) return key ~= "" and key or nil end,
    }, { __index = private.NS }) }
    local path = (arg and arg[3]) or root .. "/MSUF_Suite_Options/Pages/NameplatesPreviewDecor.lua"
    assert(loadfile(path))("Options", previewOptions)
    local values = { look = 1, enemy = true, nativeCastFillTexture = "cast" }
    local function Get(_, key) return values[key] end
    local sample = {
        prefix = "enemy",
        cast = { GetFrameLevel = function() return 1 end },
        castProgress = cast,
        castBack = Region(),
    }
    local editor, metrics = {}, { opacity = true }
    local Paint = previewOptions.NameplatesPreviewDecor.CastPresentation
    Paint(editor, sample, metrics, Get)
    assert(sample.castBack.atlas == "ui-castingbar-background")
    assert(fill.tint[1] == .4 and fill.tint[3] == .8, "preview did not inherit the same cast color")
    values.nativeCastFillColor = "00ff00"
    Paint(editor, sample, metrics, Get)
    assert(fill.tint[1] == 0 and fill.tint[2] == 1, "preview color did not update without changing the texture")
    editor.uninterruptible = true
    Paint(editor, sample, metrics, Get)
    assert(fill.tint[1] == .8 and fill.tint[2] == .3, "preview did not inherit the locked cast color")
    values.nativeCastBackgroundTexture = "castBack"
    Paint(editor, sample, metrics, Get)
    assert(sample.castBack.path == "castBack" and sample.castBack.tint[1] > 0
        and not sample.castBack.slice and sample.castBack.coords[3] == 0 and sample.castBack.coords[4] == 1,
        "the preview masks the selected background with the native atlas or Jundies tint")
    values.nativeCastBackgroundTexture = "Solid"
    Paint(editor, sample, metrics, Get)
    assert(sample.castBack.tint[1] == 0 and sample.castBack.tint[4] == .5)
end
do
    local NS, bridge = private.NS, private.NS.HostBridge
    local originalNamespace, originalProfile = bridge.Namespace, bridge.CurrentFrameProfile
    local coreProfile = { general = { castbarOutlineThickness = 3, castbarBorderR = .2,
        castbarBorderG = .5, castbarBorderB = .7, castbarBorderA = 0, castbarShowSpark = true,
        castbarSparkOverflow = false, castbarFillDirection = "RTL", castbarSpellNameShortening = 1,
        castbarSpellNameMaxLen = 17, castbarShowPushback = true },
        bars = { barOutlineTexture = "BORDER:Stone", barOutlineThickness = 6 } }
    local export = {
        MSUF_GetCastbarTexture = function() return "hostFill" end,
        MSUF_GetCastbarBackgroundTexture = function() return "hostBack" end,
        MSUF_GetCastbarBackgroundColor = function() return .12, .24, .36, .5 end,
        MSUF_GetCastbarTextColor = function() return .3, .5, 1 end,
        MSUF_ResolveInterruptFeedbackCastColor = function() return .9, .4, .2 end,
        MSUF_UpdateCastbarVisuals = function() end,
    }
    local host = originalNamespace()
    host.PublicGlobals = export
    host.Castbars = { Config = { Refresh = function() end } }
    host.BorderStyles = {
        ResolveFrame = function() error("Nameplate cast outline read the Unitframe outline style") end,
    }
    bridge.Namespace = function() return host end
    bridge.CurrentFrameProfile = function() return coreProfile end
    NS.Finite = function(value) return type(value) == "number" and value == value and math.abs(value) < math.huge end
    local changed = 0
    MSUF_UpdateCastbarTextures_Immediate = function() end
    MSUF_ApplyBarOutlineThickness_All = function() end
    bridge.ObserveSharedCastbarStyle(function() changed = changed + 1 end)
    export.MSUF_UpdateCastbarVisuals()
    host.Castbars.Config.Refresh()
    MSUF_UpdateCastbarTextures_Immediate()
    assert(changed == 3, "Castbar menu and color refreshes did not reach Suite")
    MSUF_ApplyBarOutlineThickness_All()
    assert(changed == 3, "the Unitframe outline setting refreshed the Nameplate cast outline")
    MSUF_UpdateCastbarTextures_Immediate, MSUF_ApplyBarOutlineThickness_All = nil, nil

    local style = assert(NS.NameplateStyle.SharedCastbar(3), "the nameplate did not load its inherited Castbar style")
    assert(NS.NameplateStyle.SharedCastbar(2) == nil, "the Blizzard look inherited the MSUF look")
    assert(style.outlineSize == 3 and style.outlineA == 0 and style.outlineB == .7)
    local suiteMode = { look = 3, castTargetHighlightStyle = 1, enemyCastDisplay = 1 }
    local suiteStyle = assert(T.SharedCastbar(suiteMode))
    assert(suiteStyle.targetHighlight and suiteStyle.outlineSize == 3)
    assert(T.SharedCastbar(suiteMode, suiteStyle) == suiteStyle, "unchanged cast target style invalidated the castbar")
    suiteMode.castTargetHighlightStyle = 2
    assert(not T.SharedCastbar(suiteMode, suiteStyle).targetHighlight, "Blizzard mode applied the Suite warning")
    suiteMode.castTargetHighlightStyle, suiteMode.enemyCastDisplay, suiteMode.enemyCastTargetHighlight = 1, 2, false
    assert(not T.SharedCastbar(suiteMode).targetHighlight, "a disabled warning installed the Suite style")
    suiteMode.look, suiteMode.enemyCastTargetHighlight = 2, true
    assert(T.SharedCastbar(suiteMode) == nil, "the Blizzard look applied the Suite warning")
    assert(style.reverseFill and style.showSpark and not style.sparkOverflow)
    assert(style.nameMax == 17 and style.shortenName and style.showPushback and style.textB == 1)
    local owner, visual = {}, { edges = {} }
    for index = 1, 4 do
        local edge = Region()
        function edge:ClearAllPoints() end
        function edge:SetPoint() end
        function edge:SetHeight() end
        function edge:SetWidth() end
        function edge:Show() self.shown = true end
        function edge:Hide() self.shown = false end
        visual.edges[index] = edge
    end
    local PaintOutline = NS.NameplateStyle.PaintCastOutline
    PaintOutline(visual, owner, style.outlineSize, style)
    assert(visual.edges[1].shown and visual.edges[1].tint[3] == .7 and visual.edges[1].tint[4] == 0)
    coreProfile.general.castbarOutlineThickness, coreProfile.general.castbarBorderA = 2, .65
    local updated = bridge.SharedCastbarStyle()
    PaintOutline(visual, owner, updated.outlineSize, updated)
    assert(visual.borderSize == 2 and visual.edges[1].tint[4] == .65, "Castbar outline updates were ignored")
    coreProfile.general.castbarOutlineThickness = 0
    updated = bridge.SharedCastbarStyle()
    PaintOutline(visual, owner, updated.outlineSize, updated)
    assert(not visual.edges[1].shown, "zero thickness left the normal outline visible")
    local applied, restored
    private.CastAppearance = {
        Apply = function(frame, settings) assert(frame == cast) applied = settings return true end,
        Restore = function(frame) assert(frame == cast) restored = true return true end,
    }
    cast.barType = "standard"
    T.Configure({}, style)
    T.Apply(uf)
    assert(applied == style and fill.path == "hostFill" and cast.Background.path == "hostBack")
    assert(cast.Background.tint[2] == .24 and cast.Background.tint[4] == .5)
    do
        -- The cold-layout handoff: the styled castbar of a painted plate is
        -- told once per layout pass, and nothing else of the plate is painted.
        local appearance = private.CastAppearance
        local plainApply, layouts, applies, owed = appearance.Apply, 0, 0, false
        -- The plate itself stays accessible in this block's combat: the stub
        -- above denies it there, which is tested on its own at the end.
        local blockedAccess = uf.CanBeAccessedInContext
        uf.CanBeAccessedInContext = function() return true end
        appearance.OnLayout = function(frame)
            assert(frame == cast)
            layouts = layouts + 1
        end
        appearance.Apply = function(frame, settings)
            applies = applies + 1
            if owed then T.DeferCast(frame) end
            return plainApply(frame, settings)
        end
        local fillWrites, backWrites = fill.writes, cast.Background.writes
        T.OnLayout(uf)
        assert(layouts == 1 and applies == 0, "the layout handoff missed the styled castbar or repainted the plate")
        assert(fill.writes == fillWrites and cast.Background.writes == backWrites, "the layout handoff wrote textures")
        T.OnLayout({ CastBarsContainer = { castBar = cast } })
        assert(layouts == 1, "an unpainted plate received the layout handoff")
        -- Outside combat an owed cast paint keeps nothing: no event, no repaint.
        T.DeferCast(cast)
        assert(not events.PLAYER_REGEN_ENABLED, "an owed cast paint outside combat registered an event")
        T.Apply(uf)
        assert(applies == 0, "an owed cast paint outside combat repainted a stable plate")
        -- A cast height withheld at a combat layout edge: the Apply is
        -- complete, and its deferral survives it until combat ends.
        combat, owed = true, true
        T.OnAnchors(uf)
        assert(applies == 1 and events.PLAYER_REGEN_ENABLED, "a height withheld in combat lost its combat-end retry")
        T.Apply(uf)
        assert(applies == 2, "a plate that owes a cast height was treated as settled in combat")
        owed = false
        EndCombat()
        assert(applies == 3, "the end of combat did not apply the owing castbar again")
        T.Apply(uf)
        assert(applies == 3, "a settled castbar kept repainting after combat")
        -- A cast event its castbar denied in combat uses the same owner.
        combat = true
        T.DeferCast(cast)
        assert(events.PLAYER_REGEN_ENABLED and applies == 3)
        EndCombat()
        assert(applies == 4, "a denied cast event was not repaired at the end of combat")
        combat = true
        T.DeferCast({})
        assert(not events.PLAYER_REGEN_ENABLED, "an unstyled castbar registered a retry")
        -- A plate the client denies in combat paints nothing and is retried.
        uf.CanBeAccessedInContext = blockedAccess
        T.OnAnchors(uf)
        assert(applies == 4 and events.PLAYER_REGEN_ENABLED, "a denied plate was painted or lost its retry")
        EndCombat()
        assert(applies == 5, "a denied plate was not painted at the end of combat")
        T.Apply(uf)
        assert(applies == 5, "a repaired plate kept repainting after combat")
        combat = false
        appearance.Apply, appearance.OnLayout = plainApply, nil
    end
    cast:PlayInterruptAnims()
    assert(fill.tint[1] == .9 and fill.tint[2] == .4, "interrupted casts ignored the Core feedback color")
    cast:UpdateBarFillTexture(false)

    T.Configure({ nativeCastFillTexture = "localFill", nativeCastBackgroundTexture = "localBack" }, style)
    T.Apply(uf)
    assert(fill.path == "localFill" and cast.Background.path == "localBack", "explicit Nameplates texture selections were overwritten")
    export.MSUF_GetCastbarBackgroundTexture = nil
    T.Configure({}, bridge.SharedCastbarStyle())
    T.Apply(uf)
    assert(cast.Background.color[1] == .12 and cast.Background.color[4] == .5 and cast.Background.tint[1] == 1,
        "shared appearance with unavailable background media retained a decorative Blizzard backdrop")
    T.Configure({})
    T.RestoreAll()
    assert(restored and fill.atlas == cast.nativeAtlas and cast.Background.atlas == "ui-castingbar-background",
        "removing shared cast style retained inherited artwork")
    private.CastAppearance = nil
    bridge.Namespace, bridge.CurrentFrameProfile = originalNamespace, originalProfile
end
do
    local options = { HM = { GetControlTitle = function(widget) return widget.title end } }
    local path = (arg and arg[4]) or root .. "/MSUF_Suite_Options/Menu/Colors.lua"
    assert(loadfile(path))("Options", options)
    local function Row(lines)
        local label, widget = {}, {}
        function label:SetWidth(w) self.width = w end
        function label:SetJustifyH() end
        function label:ClearAllPoints() end
        function label:SetPoint(_, _, _, x, y) self.x, self.y = x, y end
        function label:GetStringHeight() return self.width >= 200 and lines * 14 or lines * 28 end
        function widget:GetWidth() return 44 end
        function widget:ClearAllPoints() end
        function widget:SetPoint(_, _, _, x, y) self.x, self.y = x, y end
        widget.title = label
        return widget
    end
    local controls = { a = Row(4), b = Row(1), c = Row(2) }
    local bottom = options.LayoutColorRows({}, controls, { { id = "a" }, { id = "b" }, { id = "c" } }, -18, 600, 2)
    assert(controls.a.title.width == 235 and controls.a.x == 307 and controls.b.x == 616,
        "color labels and swatches must use the available column width")
    assert(controls.c.title.y == -80 and bottom == -120, "wrapped color labels need room before the next row")
end
local secondHealth = { barTexture = Region("native-health"), bgTexture = Region("native-background") }
local second = { HealthBarsContainer = { healthBar = secondHealth } }
local thirdHealth = { barTexture = Region("native-health"), bgTexture = Region("native-background") }
local third = { HealthBarsContainer = { healthBar = thirdHealth } }
local visibleFocus, focusLookups = nil, 0
C_NamePlate = { GetNamePlateForUnit = function(unit)
    assert(unit == "focus")
    focusLookups = focusLookups + 1
    return visibleFocus
end }
function UnitExists(unit) return unit == "focus" end
local visuals = {}
T.Bind(visuals)
local function Paint(plate)
    local hp = plate.HealthBarsContainer.healthBar
    if not visuals[hp] then visuals[hp] = { fill = Region() } end
end
T.Configure({ nativeFocusHealthFillTexture = "focus" })
T.PrepareFocus()
T.PaintAdded(uf, Paint)
assert(health.barTexture.atlas == "UI-HUD-CoolDownManager-Bar" and focusLookups == 2)
visibleFocus = { UnitFrame = second }
T.PaintAdded(second, Paint)
assert(secondHealth.barTexture.path == "focus" and visuals[secondHealth].focusFill == "focus")
T.OnAnchors(second)
assert(secondHealth.barTexture.path == "focus")
local unchangedWrites = thirdHealth.barTexture.writes
local module = { focusUF = second, units = {} }
T.RefreshFocus(module, uf, function() end, function(plate) T.Paint(plate, Paint) end)
assert(secondHealth.barTexture.atlas == "UI-HUD-CoolDownManager-Bar")
assert(health.barTexture.path == "focus" and visuals[secondHealth].focusFill == nil)
assert(thirdHealth.barTexture.writes == unchangedWrites)
T.Restore(uf)
T.OnAnchors(uf)
assert(health.barTexture.atlas == "UI-HUD-CoolDownManager-Bar" and visuals[health].focusFill == nil)
T.Configure({ nativeHealthFillTexture = "normal", nativeFocusHealthFillTexture = "focus" })
T.SetFocus(second)
T.Paint(second, Paint)
T.Paint(uf, Paint)
assert(secondHealth.barTexture.path == "focus" and health.barTexture.path == "normal")
T.SetFocus(uf)
T.Apply(second)
T.Apply(uf)
assert(secondHealth.barTexture.path == "normal" and health.barTexture.path == "focus")
T.Configure({ nativeHealthFillTexture = "normal" })
T.PrepareFocus()
T.Apply(uf)
assert(health.barTexture.path == "normal" and visuals[health].focusFill == nil)

local callbacks, resets = {}, {}
local P = {
    W = {},
    Gates = {},
    Tr = function(text) return text end,
    Suite = { Client = { isMainline = true }, HostBridge = {
        RegisterBarsScope = function() return false end,
        RegisterPageTail = function(_, page, _, provider) callbacks[page] = provider return true end,
        OpenExactMenuSetting = function(_, page, section, key)
            assert(section and key:match("^msufsuite%.nameplates%."))
            callbacks.opened, callbacks.section, callbacks.setting = page, section, key
            return true
        end,
    } },
    catalog = { nameplates = { rules = {} } },
    S = { ResetKeys = function(_, values) resets = values return true end },
    Meta = function() return {} end,
    Button = function(_, _, _, _, _, _, click) click() end,
}
for key in pairs(config) do P.catalog.nameplates.rules[key] = { key = key, default = "" } end
P.catalog.nameplates.rules.nativeFocusHealthFillTexture = { key = "nativeFocusHealthFillTexture", default = "" }
assert(loadfile(root .. "/MSUF_Suite_Options/Pages/NameplateBarTextures.lua"))("Options", P)
P.NameplateBarTextures.Register()
assert(P.NameplateBarTextures.Target("nativeHealthBackgroundTexture").page == "opt_bars")
assert(P.NameplateBarTextures.Target("nativeFocusHealthFillTexture").page == "opt_bars")
assert(P.NameplateBarTextures.Target("nativeCastBackgroundTexture").page == "opt_castbar")
assert(P.NameplateBarTextures.Target("castTargetHighlightStyle").section == "suite_nameplate_highlights")
P.NameplateBarTextures.LinkCastTarget(nil, nil, 0, 400, "style")
assert(callbacks.opened == "opt_bars" and callbacks.section == "suite_nameplate_highlights"
    and callbacks.setting == "msufsuite.nameplates.castTargetHighlightStyle")
assert(P.NameplateBarTextures.Target("nameplateHealAbsorbMode").section == "suite_nameplate_absorbs")
P.NameplateBarTextures.LinkAbsorbs(nil, nil, 0, 400, "style")
assert(callbacks.opened == "opt_bars" and callbacks.section == "suite_nameplate_absorbs"
    and callbacks.setting == "msufsuite.nameplates.nameplateAbsorbMode")
P.NameplateBarTextures.Link(nil, nil, 0, 400, "basics")
assert(callbacks.opened == "opt_bars")
P.NameplateBarTextures.Link(nil, nil, 0, 400, "castbar", true)
assert(callbacks.opened == "opt_castbar")
assert(callbacks.opt_castbar.reset() and resets.nativeCastFillTexture == "" and not resets.nativeHealthFillTexture)
assert(callbacks.opt_bars.reset() and resets.nativeHealthBackgroundTexture == "" and resets.nativeFocusHealthFillTexture == ""
    and not resets.nativeCastFillTexture)
local fallback = P.NameplateBarTextures.Target("nativeCastBackgroundTexture")
local body = {}
P.M = {
    SelectPage = function(page) callbacks.selected = page end,
    cache = { [fallback.page] = { sections = { [fallback.section] = body } } },
}
P.HM = {
    GetSectionEntry = function(frame)
        assert(frame == body)
        return { SetOpenImmediate = function(open) callbacks.expanded = open end }
    end,
    GetSectionEnsureVisible = function() return function() callbacks.revealed = true end end,
}
P.Suite.HostBridge.OpenExactMenuSetting = function() return false end
P.NameplateBarTextures.Link(nil, nil, 0, 400, "castbar", true)
assert(callbacks.selected == "opt_castbar" and callbacks.revealed and callbacks.expanded,
    "the fallback link did not reveal and open its accordion")

do
    local shared = true
    local selected
    local route
    assert(loadfile(root .. "/MSUF_Suite/Core/HostBridgeMenu.lua"))("MSUF_Suite", P.Suite)
    P.Suite.HostBridge.OpenSharedAggroBorder({ SearchBridge = { OpenSearchTarget = function(page, _, _, _, path, target)
        assert(page == "opt_bars" and path.state.barsHighlightTab == "modes" and path.accordion["opt_bars:bars_highlight"])
        assert(path.general.hpPowerTextSelectedKey == "shared")
        route = target.controlId
    end } })
    assert(route == "menu2.opt.bars.global.highlight.border.mode.aggro.outline.mode")
    local config = { highlightAggro = false, highlightAggroOverride = false }
    local rules = P.catalog.nameplates.rules
    for _, key in ipairs(P.NameplateBarTextures.BarDetailKeys()) do rules[key] = { key = key, default = false } end
    P.catalog.nameplates.controlAvailable = function() return true end
    P.Get = function(_, key) return config[key] end
    P.Set = function(_, key, value) config[key] = value end
    P.SetMany = function(_, values)
        for key, value in pairs(values) do config[key] = value end
    end
    P.Text = function() return { GetStringHeight = function() return 14 end } end
    P.Button, P.AttachRuleColors, P.M.TrackRefresh = function() end, function() end, function() end
    P.Suite.HostBridge.SharedAggroBorderEnabled = function() return shared end
    P.Suite.HostBridge.HighlightPriorityRows = function() end
    P.Suite.NameplateStyle = private.NS.NameplateStyle
    P.RuleRows = function(_, _, controls)
        for _, rule in ipairs(controls) do
            if rule.key == "highlightAggro" then return { rows = { { id = rule.key, kind = "toggle" } } } end
        end
        return { rows = {} }
    end
    P.RuleGrid = function(_, _, _, _, _, y, _, _, _, _, built)
        if built and built.rows[1] then selected = built.rows[1] end
        return y - 24, {}
    end
    P.RuleSection = function(ctx, _, _, _, section, _, _, options)
        if section == "suite_nameplate_highlights" then options.grid({}, 0, 400) end
    end
    P.Suite.HostBridge.RegisterBarsScope = function(_, _, _, provider) callbacks.opt_bars = provider return true end
    P.Suite.HostBridge.RegisterSearchTargetResolver = function() end
    P.NameplateBarTextures.Register()
    callbacks.opt_bars.build({}, {})
    assert(selected and selected.kind == "dropdown" and selected.get() == 1 and selected.values()[1].text == "Shared (On)")
    selected.set(3)
    assert(selected.get() == 3 and not config.highlightAggro)
    selected.set(2)
    assert(selected.get() == 2 and config.highlightAggro)
    shared = false
    selected.set(1)
    assert(selected.get() == 1 and selected.values()[1].text == "Shared (Off)", "the control must reflect Shared again")
end
do
    private.NS.Finite = function(value) return type(value) == "number" end
    private.NS.InCombat = private.NS.IsCombatLocked
    local path = os.getenv("SUITE_CAST_APPEARANCE_OVERRIDE") or root .. "/MSUF_Suite_Nameplates/CastAppearance.lua"
    assert(loadfile(path))("Nameplates", private)
    assert(loadfile(root .. "/MSUF_Suite_Nameplates/CastOutline.lua"))("Nameplates", private)
    local heightReads, sparkReads, sparkWrites = 0, 0, 0
    local spark = { height = 12, alpha = 1 }
    function spark:GetHeight() sparkReads = sparkReads + 1 return self.height end
    function spark:SetHeight(value) sparkWrites = sparkWrites + 1 self.height = value end
    function spark:GetAlpha() return self.alpha end
    function spark:SetAlpha(value) self.alpha = value end
    function spark:IsShown() return self.shown == true end
    cast.Spark = spark
    cast.visible = true
    function cast:IsVisible() return self.visible end
    function cast:GetHeight() heightReads = heightReads + 1 return self.height end
    function cast:IsProtected() return self.protected == true end
    function cast:GetReverseFill() return self.reverseFill == true end
    function cast:SetReverseFill(value) self.reverseFill = value end
    function cast:ShowSpark() self.Spark.shown = true end
    function cast:HideSpark() self.Spark.shown = false end
    function cast:HandleCastStart(empowered) self.reverseChanneling = empowered end
    T.RestoreAll()
    local style = { showSpark = true, reverseFill = false, sparkOverflow = false }
    T.Configure({}, style)

    cast.height, spark.height = 9, 12
    T.PaintAdded(uf, function(frame)
        assert(heightReads == 0 and sparkReads == 0, "a recycled castbar was measured before its final layout")
        cast.height, spark.height = 16, 14
        T.OnLayout(frame)
        assert(heightReads == 0 and sparkReads == 0, "an inner layout measured a castbar before the plate paint ended")
        cast:HandleCastStart(false)
    end)
    assert(heightReads == 1 and sparkReads == 1 and sparkWrites == 1 and spark.height == 16,
        "a recycled castbar did not size the Spark once from its final height")
    for _ = 1, 100 do cast:ShowSpark() end
    cast:HandleCastStart(true)
    assert(spark.height == 14, "Empower lost the native Spark height saved after layout")
    cast:HandleCastStart(false)
    assert(spark.height == 16 and heightReads == 1 and sparkReads == 1)
    T.Restore(uf)
    assert(spark.height == 14)

    heightReads, sparkReads, sparkWrites, cast.visible = 0, 0, 0, false
    T.PaintAdded(uf, function(frame)
        cast.height, spark.height = 17, 14
        T.OnLayout(frame)
    end)
    cast:ShowSpark()
    T.Restore(uf)
    assert(heightReads == 0 and sparkReads == 0 and sparkWrites == 0,
        "a plate that never cast was sized or had its Spark geometry restored")
    T.PaintAdded(uf, function() cast.height = 19 end)
    cast.visible = true
    cast:OnShow()
    assert(heightReads == 1 and sparkReads == 1 and sparkWrites == 1 and spark.height == 19)
    cast.visible = false
    cast:OnHide()
    cast.visible = true
    cast:OnShow()
    assert(heightReads == 1 and sparkReads == 1 and sparkWrites == 1,
        "a second visible cast with the same layout reread geometry")
    T.Restore(uf)

    -- The native layout is final when the Suite geometry pass has no work.
    heightReads, sparkReads, cast.height = 0, 0, 18
    T.Paint(uf, function() assert(heightReads == 0 and sparkReads == 0) end)
    assert(heightReads == 1 and sparkReads == 1 and spark.height == 18)
    T.Restore(uf)

    heightReads, sparkReads, cast.height = 0, 0, 20
    T.Paint(uf, function()
        combat, cast.protected = true, true
    end)
    assert(heightReads == 0 and sparkReads == 0 and events.PLAYER_REGEN_ENABLED,
        "a protected final layout sampled height or lost its replay")
    cast.height = 21
    EndCombat()
    assert(heightReads == 1 and sparkReads == 1 and spark.height == 21)
    T.Restore(uf)

    heightReads, sparkReads, cast.height = 0, 0, 22
    T.Paint(uf, function() spark.height = "secret" end)
    assert(heightReads == 1 and sparkReads == 1 and spark.height == "secret")
    spark.height = 14
    T.Apply(uf)
    assert(heightReads == 2 and sparkReads == 2 and spark.height == 22,
        "a withheld Spark height left the recycled plate marked as complete")
    T.Restore(uf)

    -- Kick Ready consumes the fill direction inside the presentation pass.
    style = { showSpark = true, reverseFill = true }
    T.Configure({}, style)
    heightReads, sparkReads, cast.protected, spark.shown = 0, 0, false, false
    T.Paint(uf, function(frame)
        assert(cast:GetReverseFill() and heightReads == 0 and sparkReads == 0)
        T.Restore(frame)
    end)
    assert(not cast:GetReverseFill() and heightReads == 0 and sparkReads == 0,
        "a lease released during paint retained its pending Spark work")
    T.Configure({})
end
do
    T.RestoreAll()
    T.Configure({ nativeCastBackgroundTexture = "hiddenBack" })
    cast.visible = false
    local bg = cast.Background
    bg:SetAtlas("ui-castingbar-background")
    local writes = bg.writes
    T.Apply(uf)
    T.OnAnchors(uf)
    T.Restore(uf)
    assert(bg.writes == writes and bg.atlas == "ui-castingbar-background",
        "a plate released without a cast changed its background")

    T.Apply(uf)
    T.Configure({ nativeCastBackgroundTexture = "latestBack" })
    T.Apply(uf)
    assert(bg.writes == writes)
    cast.visible = true
    cast:OnShow()
    assert(bg.path == "latestBack" and bg.writes == writes + 1 and bg.tint[1] == .16,
        "the first visible cast missed its latest texture and tint")
    cast:OnShow()
    assert(bg.writes == writes + 1, "an unchanged cast reapplied its background")

    cast.visible = false
    bg:SetAtlas("ui-castingbar-background")
    T.OnAnchors(uf)
    assert(bg.writes == writes + 1, "a hidden Blizzard rebuild applied the background immediately")
    cast.visible, bg.locked, combat = true, true, true
    cast:OnShow()
    assert(bg.writes == writes + 1 and events.PLAYER_REGEN_ENABLED, "a denied first show lost its replay")
    bg.locked = false
    EndCombat()
    assert(bg.path == "latestBack" and bg.writes == writes + 2)
    cast.visible = false
    T.OnAnchors(uf)
    bg.locked, combat = true, true
    T.Restore(uf)
    assert(bg.path == "latestBack" and events.PLAYER_REGEN_ENABLED, "a blocked release forgot its owned background")
    cast.visible = true
    cast:OnShow()
    assert(bg.writes == writes + 2, "a released background's show hook wrote a texture")
    bg.locked = false
    EndCombat()
    assert(bg.atlas == "ui-castingbar-background", "release lost the native background")

    cast.visible, cast.protected = false, true
    T.Apply(uf)
    assert(bg.path == "latestBack", "a protected first cast was left unprepared out of combat")
    T.Restore(uf)
    cast.visible, cast.protected = true, false
    T.Configure({})
end
do
    assert(loadfile(root .. "/MSUF_Suite_Nameplates/SlantedHealth.lua"))("Nameplates", private)
    function cast:CreateMaskTexture()
        local mask = Region()
        function mask:SetAllPoints(owner) self.owner = owner end
        return mask
    end
    local bridge, config = private.NS.HostBridge, { look = 3, nativeCastFillTexture = "cast" }
    local read = bridge.CurrentFrameProfile
    local profile = { general = {}, bars = { slantedBarsEnabled = true, slantedCastbars = true } }
    bridge.CurrentFrameProfile = function() return profile end
    local style = assert(T.SharedCastbar(config))
    assert(style.slanted and T.SharedCastbar({ look = 2 }) == nil)
    profile.bars.slantedBarsEnabled = false
    assert(not T.SharedCastbar(config, style).slanted)
    bridge.CurrentFrameProfile = read
    T.Configure(config, { slanted = style.slanted, outlineSize = 0 })
    T.Apply(uf)
    local before = fill
    assert(before.mask and before.mask.owner == cast and before.mask == cast.Background.mask)
    cast.swapFill = true
    cast:UpdateBarFillTexture(false)
    assert(before ~= fill and not before.mask and fill.mask == cast.Background.mask,
        "the native fill swap detached the slant from an active cast")
    T.Restore(uf)
    assert(not fill.mask and not cast.Background.mask)
    T.Configure({})
end
print("Nameplate textures: native fills and backgrounds, cast states, no repeated writes, release, restriction and links passed")

-- Actual cold painters; texture alpha models the stricter shared native lane.
local root, hostRoot, mutant = assert(arg[1]), arg[2], arg[3]
if hostRoot == "-" then hostRoot = nil end
local checks, writes, creations, fillReads = 0, 0, 0, 0
local function Check(ok, message) checks = checks + 1 assert(ok, message) end
local Widget = {}
Widget.__index = Widget
local function New(kind)
    return setmetatable({ kind = kind, children = {}, shown = true, alpha = 1, w = 32, h = 32 }, Widget)
end
function Widget:CreateTexture(_, layer, _, sub)
    writes, creations = writes + 1, creations + 1
    local texture = New("Texture")
    texture.layer, texture.sub = layer, sub
    self.children[#self.children + 1] = texture
    return texture
end
function Widget:SetTexture(path, h, v) writes = writes + 1 self.path, self.hWrap, self.vWrap = path, h, v end
function Widget:SetVertexColor(r, g, b, a) writes = writes + 1 self.color, self.alpha = { r, g, b }, a or 1 end
function Widget:SetAlpha(alpha) writes = writes + 1 self.alpha = alpha end
function Widget:SetShown(shown) writes = writes + 1 self.shown = shown end
function Widget:Show() self:SetShown(true) end
function Widget:Hide() self:SetShown(false) end
function Widget:SetAllPoints(target) writes = writes + 1 self.target = target end
function Widget:SetPoint(...) writes = writes + 1 self.point = { ... } end
function Widget:ClearAllPoints() writes = writes + 1 self.point = nil end
function Widget:SetTexCoord(...) writes = writes + 1 self.uv = { ... } end
function Widget:SetBlendMode(mode) writes = writes + 1 self.blend = mode end
function Widget:SetDrawLayer(layer, sub) writes = writes + 1 self.layer, self.sub = layer, sub end
function Widget:SetSize(w, h) writes = writes + 1 self.w, self.h = w, h end
function Widget:SetWidth(w) writes = writes + 1 self.w = w end
function Widget:SetHeight(h) writes = writes + 1 self.h = h end
function Widget:GetWidth() return self.w end
function Widget:GetHeight() return self.h end
function Widget:SetRotation() writes = writes + 1 end
function Widget:GetStatusBarTexture() fillReads = fillReads + 1 return self.fill end
local NS = { Suite = { Apply = function() end } }
local function Load(provider)
    MSUF_HostAPI = provider and { version = 1, GetIconSkins = function() return provider end } or nil
    assert(loadfile(root .. "/MSUF_Suite/Core/HostBridge.lua"))("MSUF_Suite", NS)
    assert(loadfile(arg[4] or root .. "/MSUF_Suite/Core/GlossMaterial.lua"))("MSUF_Suite", NS)
    if mutant == "drop-bar" then NS.GlossMaterial.Bar = function() return false end end
    if mutant == "drop-icon" then NS.GlossMaterial.Icon = function() return false end end
    return NS.GlossMaterial
end
local subscriptions, compiles, variants, paints = {}, 0, 0, 0
local recording = { version = 1, DEFAULT = "DEFAULT" }
function recording.Subscribe(key, fn) subscriptions[key] = fn return true end
function recording.Compile(choice, shape)
    compiles = compiles + 1
    Check(choice == "FRAME_BEVEL" and shape == "RECTANGLE", "icon did not use the complete bevel catalog skin")
    return { signature = "opaque" .. compiles }
end
function recording.WithGlossStrength(look, strength)
    variants = variants + 1
    return { signature = look.signature .. strength, strength = strength }
end
function recording.GlossTexture() return "existing-top.tga" end
function recording.Paint(_, look) paints = paints + 1 return look ~= nil end

-- Legacy/partial providers preserve their existing appearance and allocate no art.
for _, provider in ipairs({ false, { version = 1, Subscribe = function() end,
    Compile = function() return { signature = "old" } end, Paint = function() return true end } }) do
    local gloss = Load(provider or nil)
    local owner, icon = New("StatusBar"), New("Texture")
    owner.fill = icon
    local before, reads = creations, fillReads
    Check(not gloss.Bar(owner, true, 50, 1), "old host acquired unsupported bar art")
    Check(not gloss.Icon(owner, icon, true, 50, 32), "old host acquired an unsupported icon look")
    Check(creations == before and fillReads == reads, "old host allocated or queried the fill")
end

local gloss = Load(recording)
Check(gloss.Available(), "current host capability not available")
local bar, fill = New("StatusBar"), New("Texture")
bar.fill = fill
local before, reads = creations, fillReads
for i = 1, 20 do gloss.Bar(bar, false, 50, 1) gloss.Bar(bar, true, 0, 1) end
Check(creations == before and fillReads == reads, "off/zero bar allocated or queried the fill")
Check(gloss.Bar(bar, true, 50, .4), "enabled bar not painted")
Check(creations == before + 2, "enabled bar did not create exactly two retained regions")
local upper, lower = bar.children[1], bar.children[2]
Check(upper.target == fill and lower.target == fill, "bar reflection does not follow native fill geometry")
Check(upper.uv[1] == .125 and upper.uv[2] == .875 and upper.uv[4] == 2 and lower.uv[3] == 2,
    "bar reflection lost the compressed horizontal material")
Check(upper.blend == "ADD" and lower.blend == "ADD", "bar reflection replaced its neutral additive light")
Check(upper.color[1] == .325 and lower.color[1] == .04 and upper.alpha == .4,
    "bar opacity overwrote the independent reflection strength")
before = writes
for i = 1, 20 do gloss.Bar(bar, true, 50, .4) end
Check(writes == before, "unchanged bar style rewrote a native property")
gloss.Bar(bar, true, 75, .4)
Check(upper.color[1] == .75 * .65 and upper.alpha == .4, "strength change lost cached opacity")
gloss.Bar(bar, true, 30, 0)
Check(upper.alpha == 0 and lower.alpha == 0, "zero opacity left a visible reflection")
gloss.Bar(bar, true, 80, 0)
Check(upper.alpha == 0, "strength while transparent restored opacity to one")
gloss.Bar(bar, false, 80, 1)
Check(not upper.shown and not lower.shown, "disabled retained bar is visible")
before = creations
gloss.Bar(bar, true, 80, 1)
Check(upper.shown and lower.shown and creations == before, "bar re-enable replaced or lost the retained regions")
bar.fill = New("Texture")
gloss.Bar(bar, true, 80, 1)
Check(upper.target == bar.fill and lower.target == bar.fill, "bar fill handoff retained a stale anchor")

local owner, icon = New("Frame"), New("Texture")
before = paints
for i = 1, 20 do gloss.Icon(owner, icon, false, 50, 32) gloss.Icon(owner, icon, true, 0, 32) end
Check(paints == before and compiles == 0, "off/zero icon called the host painter")
Check(gloss.Icon(owner, icon, true, 50, 32), "enabled icon did not use the shared full skin")
Check(compiles == 1 and variants == 1 and paints == before + 1, "first icon did not compile one cached look")
before = paints
for i = 1, 20 do gloss.Icon(owner, icon, true, 50, 32) end
Check(paints == before and compiles == 1 and variants == 1, "warm icon repainted or recompiled")
gloss.Icon(owner, icon, true, 75, 32)
Check(variants == 2 and paints == before + 1, "icon strength did not repaint one variant")
gloss.Icon(owner, icon, false, 75, 32)
Check(paints == before + 2, "icon disable did not release only its own look")
before = paints
for i = 1, 20 do gloss.Icon(owner, icon, false, 75, 32) end
Check(paints == before, "unchanged disabled icon called the painter")
gloss.Icon(owner, icon, true, 75, 32)
Check(paints == before + 1 and variants == 2, "icon re-enable did not reuse its cached look")
gloss.Icon(owner, icon, true, 75, 40)
Check(paints == before + 2, "icon resize left stale geometry")
local other = New("Frame")
gloss.Icon(other, New("Texture"), true, 75, 40)
Check(variants == 2, "equal icon styles did not share the same immutable look")
subscriptions.MSUF_Suite("apply")
gloss.Icon(owner, icon, true, 75, 40)
Check(compiles == 2 and variants == 3, "global style notification retained a stale strength variant")

-- Optional actual provider path: full frame + shadow + gloss and immutable variants.
if hostRoot then
    C_Texture = { GetAtlasInfo = function() end }
    local A3, shared = { _runtimeConfigGen = 1 }, { iconSkinDefault = { styleSkin = "FRAME_BEVEL" } }
    function A3.EnsureDB() return {}, shared end
    local MSUF = { MSUF_Auras3 = A3, Util = { InCombat = function() return false end } }
    local providers = { MSUF_PixelLayoutRegion = function(region) return region end,
        MSUF_EventBus_Register = function() end, MSUF_EventBus_Unregister = function() end }
    function MSUF.Require(name) return assert(providers[name], name) end
    function MSUF.RunHostAPIStep(_, step, ...) return true, step(...) end
    function MSUF.ExportPublic(name, value) MSUF[name] = value end
    for _, path in ipairs({ "Runtime/MSUF_BorderStyles.lua", "Auras3/MSUF_Auras3_IconShape.lua",
        "Auras3/MSUF_Auras3_IconSkins.lua", "Auras3/MSUF_Auras3_IconSkins_Catalog.lua",
        "Auras3/MSUF_Auras3_IconSkins_Host.lua" }) do
        assert(loadfile(hostRoot .. "/MidnightSimpleUnitFrames/" .. path))("MidnightSimpleUnitFrames", MSUF)
    end
    local host = A3.IconSkins.Host
    Check(host.WithGlossStrength and host.GlossTexture, "actual host did not publish additive gloss capabilities")
    local base = assert(host.Compile("FRAME_BEVEL", "RECTANGLE"))
    local gr, signature = base.skin.gr, base.signature
    local adjusted = assert(host.WithGlossStrength(base, .4))
    Check(base.skin.gr == gr and base.signature == signature, "strength variant mutated the compiled default")
    Check(adjusted.skin.gr == gr * .4 and adjusted.skin.ga == base.skin.ga, "variant mixed strength and opacity")
    Check(adjusted.skin.def == base.skin.def and adjusted.signature ~= signature, "variant lost frame/shadow or signature")
    local noGloss = assert(host.WithGlossStrength(base, 0))
    Check(noGloss.skin.gloss == false and noGloss.skin.def == base.skin.def, "zero strength removed frame/shadow data")
    gloss = Load(host)
    local actualOwner, actualIcon = New("Frame"), New("Texture")
    Check(gloss.Icon(actualOwner, actualIcon, true, 50, 32), "actual provider did not render the icon")
    local shadow, reflection, band = false, nil, false
    for _, texture in ipairs(actualOwner.children) do
        local path = texture.path or ""
        if path:find("msuf_skin_shadow_outer", 1, true) then shadow = true end
        if path:find("msuf_skin_gloss_top", 1, true) then reflection = texture end
        if path:find("msuf_skin_frame_bevel", 1, true) then band = true end
    end
    Check(shadow and band and reflection, "actual skin omitted frame, shadow or reflected light")
    Check(reflection.color[1] == .5 and reflection.alpha == .12, "actual icon strength/opacity differs")
    before = writes
    gloss.Icon(actualOwner, actualIcon, true, 50, 32)
    Check(writes == before, "actual provider rewrote an unchanged icon")
    gloss.Icon(actualOwner, actualIcon, false, 50, 32)
    Check(not reflection.shown, "actual icon disable left reflected light visible")
    gloss.Icon(actualOwner, actualIcon, true, 50, 32)
    Check(reflection.shown, "actual icon re-enable lost the retained material")
    local actualBar = New("StatusBar")
    actualBar.fill = New("Texture")
    Check(gloss.Bar(actualBar, true, 50, .3), "actual public artwork did not render a bar")
    Check(actualBar.children[1].path == host.GlossTexture(), "bar used an unexposed private artwork path")
    -- A separate Suite switch enables gloss even when the global aura look disables it.
    shared.iconSkinDefault.styleSkinGloss = false
    shared.iconSkinDefault.styleSkinGlossColor = { .3, .6, .9, .27 }
    shared.iconSkinDefault.styleSkinColorOverride = true
    shared.iconSkinDefault.styleSkinColor = { .2, .4, .6, .8 }
    local globalOff = assert(host.Compile("FRAME_BEVEL", "RECTANGLE"))
    local offSignature = globalOff.signature
    Check(globalOff.skin.gloss == false, "global aura switch did not remain off")
    local independent = assert(host.WithGlossStrength(globalOff, .75))
    Check(independent.skin.gloss == true and globalOff.skin.gloss == false and globalOff.signature == offSignature,
        "separate gloss inherited global off or mutated its base look")
    Check(independent.skin.gr == .3 * .75 and independent.skin.gg == .6 * .75 and independent.skin.gb == .9 * .75
        and independent.skin.ga == .27, "separate gloss lost the committed tint or opacity")
    Check(independent.skin.def == globalOff.skin.def and independent.skin.override and independent.skin.r == .2
        and independent.skin.g == .4 and independent.skin.b == .6 and independent.skin.a == .8,
        "separate gloss changed the frame, shadow or committed tint")
    Check(host.WithGlossStrength(globalOff, 0).skin.gloss == false, "global-off strength zero enabled gloss")
    gloss = Load(host)
    local independentOwner, independentIcon = New("Frame"), New("Texture")
    Check(gloss.Icon(independentOwner, independentIcon, true, 75, 32), "global-off Suite icon was not painted")
    local independentReflection
    for _, texture in ipairs(independentOwner.children) do
        if (texture.path or ""):find("msuf_skin_gloss_top", 1, true) then independentReflection = texture end
    end
    Check(independentReflection and independentReflection.color[1] == .3 * .75 and independentReflection.alpha == .27,
        "global-off Suite reflection lost its material strength or opacity")
end
print("suite_gloss_material_contract: PASS (" .. checks .. " checks; cold bar/icon styles, alpha and caches)")

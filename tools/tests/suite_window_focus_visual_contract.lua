-- Exact Menu2 veil artwork, safe clipped canvases, and retargetable native fades.
local root = assert(arg[1], "Suite root required")
local function Read(path)
    local file = assert(io.open(path, "rb"))
    local source = file:read("*a"):gsub("\r\n", "\n")
    file:close()
    return source
end
local source = Read(root .. "/tools/tests/suite_skin_menu_transitions_contract.lua")
local stop = assert(source:find('Load("Rendering/FocusVeil.lua")', 1, true))
local fixture = source:sub(1, stop - 1) .. [[
return { NS = NS, Frame = Frame, frames = frames, groups = groups,
    ForeignWrites = function() return foreignWrites end }
]]
local H = assert(loadstring(fixture, "@window_focus_visual_fixture"))()
local NS, Frame = H.NS, H.Frame
NS.path = "Interface\\AddOns\\MSUF_Suite_Skin\\"
local checks = 0
local function Check(value, message) assert(value, message); checks = checks + 1 end
local function Noop() end
local nativeCreate = CreateFrame
CreateFrame = function(...)
    local frame = nativeCreate(...)
    frame.textures, frame.masks = {}, {}
    function frame:SetScale(value) self.scale = value end
    function frame:GetRegions() return unpack(self.textures) end
    function frame:CreateTexture(_, layer, _, subLevel)
        local texture = Frame(self)
        texture.layer, texture.subLevel, texture.kind = layer, subLevel, "Texture"
        texture.masks = {}
        function texture:AddMaskTexture(mask) self.masks[mask] = true end
        function texture:RemoveMaskTexture(mask) self.masks[mask] = nil end
        function texture:SetColorTexture(...) self.color = { ... }; self.asset = nil end
        function texture:SetVertexColor(...) self.color = { ... } end
        function texture:SetTexture(asset) self.asset = asset end
        function texture:SetBlendMode(blend) self.blend = blend end
        function texture:SetTexCoord(...) self.texCoord = { ... } end
        texture.SetSnapToPixelGrid, texture.SetTexelSnappingBias = Noop, Noop
        self.textures[#self.textures + 1] = texture
        return texture
    end
    function frame:CreateMaskTexture()
        local mask = Frame(self)
        mask.kind = "MaskTexture"
        function mask:ClearTextureSlice() self.margins = nil end
        function mask:SetTexture(asset) self.asset = asset end
        function mask:SetAtlas(atlas) self.atlas = atlas end
        function mask:SetTexCoord(...) self.uv = { ... } end
        function mask:SetTextureSliceMargins(...) self.margins = { ... } end
        function mask:SetTextureSliceMode(value) self.sliceMode = value end
        self.masks[#self.masks + 1] = mask
        return mask
    end
    return frame
end
Enum = { UITextureSliceMode = { Stretched = 1 } }
assert(loadfile(root .. "/MSUF_Suite_Skin/Rendering/Geometry.lua"))("MSUF_Suite_Skin", NS)
assert(loadfile(root .. "/MSUF_Suite_Skin/Rendering/WindowFocusContour.lua"))("MSUF_Suite_Skin", NS)
local function Materials(focus)
    local textures = {}
    for index = 2, #focus.canvas.textures do textures[#textures + 1] = focus.canvas.textures[index] end
    return textures
end
local profile = { general = {} }
local Suite = { HostBridge = { CurrentFrameProfile = function() return profile end } }
NS.SuiteCore = function() return Suite end
assert(loadfile(root .. "/MSUF_Suite/Core/HostBridgeMenu.lua"))("MSUF_Suite", Suite)
local bridge = Suite.HostBridge
C_AddOns = { LoadAddOn = function() error("focus painting forced the host Options to load") end }
_G.MSUF2, _G.MSUF_UI = nil, nil
Check(bridge.MenuFocusVeil and not bridge.MenuFocusVeil({}, "dropdown"), "cold host focus painter did not fail closed")
assert(loadfile(root .. "/MSUF_Suite_Skin/Rendering/WindowFocusVisual.lua"))("MSUF_Suite_Skin", NS)
local Visual = NS.WindowFocusVisual
local function Show(record)
    return Visual.Show(record, { left = 100, bottom = 200, width = 300, height = 100 },
        { left = 80, bottom = 160, width = 650, height = 450 }, "DIALOG", 91)
end
-- Composite the actual visible black textures, including their inherited
-- endpoint alpha. This catches provider-only and fallback-only strength fixes.
local function BlackOpacity(frames)
    local remaining = 1
    for _, frame in ipairs(frames) do
        local inherited = frame:GetAlpha()
        if frame.parent then inherited = inherited * frame.parent:GetAlpha() end
        for _, texture in ipairs(frame.textures) do
            local color = texture.color
            if texture.shown and color and color[1] == 0 and color[2] == 0 and color[3] == 0 then
                remaining = remaining * (1 - color[4] * inherited)
            end
        end
    end
    return 1 - remaining
end
local function CheckStrength(focus, label)
    focus.group:Finish()
    Check(math.abs(BlackOpacity({ focus.overlay, focus.canvas }) - 0.42) < 0.000001,
        label .. " did not composite to the stronger 42% black base")
    Check(#focus.overlay.textures == 0 and focus.canvas.textures[1].allPoints == focus.canvas,
        label .. " duplicated its cached strength layer or escaped the clipped holder")
end
local record = Visual.Create()
Check(Show(record), "cold fallback veil did not show")
Check(record.overlay.parent == UIParent and record.canvas.parent == record.overlay
    and record.overlay.clips and record.overlay.mouse == false and record.canvas.mouse == false,
    "veil inherited native protection or intercepted input")
Check(record.overlay.width == 300 and record.overlay.height == 100
    and record.overlay.points[1][2] == UIParent and record.overlay.points[1][4] == 100,
    "clipped holder escaped the requested rectangle")
Check(record.canvas.width == 650 and record.canvas.height == 450
    and record.canvas.points[1][4] == -20 and record.canvas.points[1][5] == -40,
    "a clipped slice stretched the full-window material")
Check(record.alpha.Duration == 0.095 and record.alpha.Smoothing == "OUT" and record.group:IsPlaying(),
    "veil opening does not match Menu2's 95ms OUT fade")
Check(#Materials(record) == 6, "fallback did not paint the six Menu2 layers")
local expectedAlpha = { 0.145, 0.045, 0.032, 0.026, 0.040, 0.052 }
local expectedRGB = { { 0, 0, 0 }, { 0.010, 0.014, 0.026 }, { 0.018, 0.026, 0.052 },
    { 0.014, 0.022, 0.046 }, { 0.024, 0.034, 0.068 }, { 0.035, 0.040, 0.070 } }
for index, texture in ipairs(Materials(record)) do
    Check(texture.color[4] == expectedAlpha[index], "fallback layer opacity differs from Menu2")
    for component = 1, 3 do
        Check(texture.color[component] == expectedRGB[index][component], "fallback layer hue differs from Menu2")
    end
end
Check(Materials(record)[3].asset == NS.path .. "Media\\Bars\\Smoothv2.tga"
    and Materials(record)[6].asset == NS.path .. "Media\\Bars\\Charcoal.tga",
    "fallback texture paths depend on the host addon")
local frameCount, groupCount, plays = #H.frames, #H.groups, record.group.plays
Show(record)
Check(#H.frames == frameCount and #H.groups == groupCount and record.group.plays == plays,
    "geometry-only refresh recreated artwork or restarted its fade")
record.group.progress = 0.4
Visual.Hide(record)
Check(record.alpha.Duration == 0.080 and record.alpha.Smoothing == "IN" and record.alpha.FromAlpha == 0.4,
    "fade reversal jumped or did not use Menu2's 80ms IN fade")
record.group.progress = 0.5
Show(record)
Check(math.abs(record.alpha.FromAlpha - 0.2) < 0.000001, "rapid refocus restarted from an alpha endpoint")
record.group:Finish()
Check(record.overlay.alpha == 1 and record.overlay.shown, "completed dimming hid its own veil")
CheckStrength(record, "cold fallback")
Visual.Hide(record)
record.group:Finish()
Check(not record.overlay.shown and not record.group:IsPlaying(), "completed focus fade remained active")
local writes = 0
for _, method in ipairs({ "Hide", "SetAlpha", "ClearAllPoints" }) do
    local native = record.overlay[method]
    record.overlay[method] = function(self, ...) writes = writes + 1; return native(self, ...) end
end
local paints, paint = 0, bridge.MenuFocusVeil
bridge.MenuFocusVeil = function(...) paints = paints + 1; return paint(...) end
for _ = 1, 100 do Visual.Hide(record, true); Visual.Refresh(record) end
bridge.MenuFocusVeil = paint
Check(writes == 0 and paints == 0, "cached hidden veil received idle paints or writes")
NS.DB.theme.menuAnimations = false
Show(record)
Check(record.overlay.alpha == 1 and not record.group:IsPlaying(), "animation setting removed dimming instead of snapping")
Visual.Hide(record)
Check(not record.overlay.shown, "animation-off focus recovery retained a veil")
NS.DB.theme.menuAnimations = nil
profile.general.reduceMotion = true
Show(record)
Check(record.overlay.alpha == 1 and not record.group:IsPlaying(), "cold host reduced-motion preference was ignored")
Visual.Hide(record)
profile.general.reduceMotion = nil
NS.DB.theme.reduceMotion = true
Show(record)
Check(record.overlay.alpha == 1 and not record.group:IsPlaying(), "Suite reduced-motion preference was ignored")
Visual.Hide(record)
NS.DB.theme.reduceMotion = nil

-- Use the real painters and token definitions of both host versions. The
-- small source slice excludes unrelated widget construction and boot code.
local function HostTheme(hostRoot, surfaceFile, after)
    local tokens = Read(hostRoot .. "/MidnightSimpleUnitFrames_Options/Shell/Menu2/MSUF_Menu2_Theme_Tokens.lua")
    local first = assert(tokens:find("T.focusVeils =", 1, true))
    local last = assert(tokens:find("-- Menu accent override", first, true))
    local painter = Read(hostRoot .. "/MidnightSimpleUnitFrames_Options/Shell/Menu2/" .. surfaceFile)
    local paintFirst = assert(painter:find("local function ColorTexture", 1, true))
    local paintLast = assert(painter:find(after, paintFirst, true))
    local theme = { media = { bgSmooth = "host-smooth", bgCharcoal = "host-charcoal" } }
    assert(loadstring("local T, PixelLayoutLeaf = ...\nlocal PixelLayoutRegion = PixelLayoutLeaf\n" .. tokens:sub(first, last - 1)
        .. painter:sub(paintFirst, paintLast - 1), "@real_host_focus_painter"))(theme, function(value) return value end)
    theme.ApplyMaterial = function() error("focus veil was turned into a panel material") end
    return theme
end
local hosts = {
    { "MidnightSimpleUnitFrames", "MSUF_Menu2_Theme.lua", "local function ClampMotionDuration" },
    { "MidnightSimpleUnitFrames-7.0", "MSUF_Menu2_Theme_Surfaces.lua", "local function GlassTexture" },
}
for _, host in ipairs(hosts) do
    local theme = HostTheme(root .. "/../" .. host[1], host[2], host[3])
    _G.MSUF2 = { Theme = theme }
    local focus = Visual.Create()
    Check(Show(focus), host[1] .. " host focus painter failed")
    Check(#Materials(focus) == 6 and Materials(focus)[3].asset == "host-smooth",
        host[1] .. " did not use the host's exact veil painter")
    for index, texture in ipairs(Materials(focus)) do
        Check(texture.color[4] == expectedAlpha[index], "host/fallback veil opacity drifted")
        for component = 1, 3 do
            Check(texture.color[component] == expectedRGB[index][component], "host/fallback veil hue drifted")
        end
    end
    Check(Materials(focus)[3].points[1][4] == -5
        and Materials(focus)[3].points[2][4] == 5
        and Materials(focus)[4].texCoord[8] == 1,
        "host veil smear bounds/UVs changed")
    CheckStrength(focus, host[1])
    local dropdown = CreateFrame("Frame", nil, UIParent)
    theme.ApplyFocusVeil(dropdown, "dropdown")
    Check(#dropdown.textures == 6 and math.abs(BlackOpacity({ dropdown }) - 0.145) < 0.000001,
        "stronger window focus leaked into the host dropdown renderer")
    local paints, paint = 0, theme.ApplyFocusVeil
    theme.ApplyFocusVeil = function(...) paints = paints + 1; return paint(...) end
    _G.MSUF2, _G.MSUF_UI = nil, theme
    Visual.Refresh(focus)
    Check(paints == 1, "shared UI focus capability was bypassed")
    _G.MSUF_UI = nil
    _G.MSUF2 = { Theme = theme }
    theme.ReducedMotionEnabled = function() return true end
    Visual.Refresh(focus)
    Check(focus.overlay.alpha == 1 and not focus.group:IsPlaying(), "loaded host reduced motion was ignored")
    Visual.Hide(focus, true)
end
_G.MSUF2, _G.MSUF_UI = nil, nil
Show(record)
local fallbackTextures = #record.canvas.textures
_G.MSUF2 = { Theme = HostTheme(root .. "/../MidnightSimpleUnitFrames-7.0", hosts[2][2], hosts[2][3]) }
Visual.Refresh(record)
Check(#record.canvas.textures == fallbackTextures + 6, "late-loaded host painter was cached as unavailable")
CheckStrength(record, "late host")
for index = 2, fallbackTextures do Check(not record.canvas.textures[index].shown, "late host paint doubled the fallback veil") end
_G.MSUF2 = nil
Visual.Refresh(record)
Check(#record.canvas.textures == fallbackTextures + 6, "missing host recreated an existing fallback")
for index = fallbackTextures + 1, #record.canvas.textures do
    Check(not record.canvas.textures[index].shown, "host removal retained its textures above the fallback")
end
CheckStrength(record, "restored fallback")

-- A slice keeps the full window contour, not a newly rounded rectangle at
-- each cut. Both native masks and every host/fallback texture share it.
local contour = {
    geometry = { fill = NS.path .. "Media\\Shapes\\continuous_r8_fill.png", slice = true,
        margins = { 9.5, 9.5, 9.5, 9.5 } }, inset = 2,
}
local sourceRect = { left = 80, bottom = 160, width = 900, height = 600, unitScale = 1.5, contour = contour }
local clipped = { left = 200, bottom = 300, width = 200, height = 150, source = sourceRect }
local material = { left = 70, bottom = 150, width = 920, height = 620 }
-- Representative alpha samples from continuous_r8_fill.png (20x20):
-- corner=0, center=255. Model only mask application/compositing here; native
-- texture rendering remains an in-game check.
local function MaskSample(mask, x, y)
    local point = mask.points[1]
    local left, bottom = point[4], point[5]
    if x < left or y < bottom or x >= left + mask.width or y >= bottom + mask.height then return 0 end
    if mask.asset == contour.geometry.fill then
        if x - left < 0.1 and y - bottom < 0.1 then return 0 end
        return 1
    end
    return 1
end
local function MaskedBlackOpacity(focus, x, y)
    local remaining = 1
    for _, texture in ipairs(focus.canvas.textures) do
        local color = texture.color
        if texture.shown and color and color[1] == 0 and color[2] == 0 and color[3] == 0 then
            local alpha = color[4] * focus.overlay:GetAlpha()
            for mask in pairs(texture.masks) do alpha = alpha * MaskSample(mask, x, y) end
            remaining = remaining * (1 - alpha)
        end
    end
    return 1 - remaining
end
local function CheckMasks(focus, count, label)
    for _, texture in ipairs(focus.canvas.textures) do
        local attached = 0
        for mask in pairs(texture.masks) do
            attached = attached + 1
            Check(mask.parent == focus.canvas, label .. " mask attached to a foreign parent")
        end
        Check(attached == count, label .. " missed a strength/material layer or retained a stale mask")
    end
end
for _, host in ipairs({ false, hosts[1], hosts[2] }) do
    _G.MSUF2 = host and { Theme = HostTheme(root .. "/../" .. host[1], host[2], host[3]) } or nil
    local focus = Visual.Create()
    Check(Visual.Show(focus, clipped, material, "DIALOG", 91), "contoured veil failed to show")
    CheckMasks(focus, 1, host and host[1] or "fallback")
    local mask = focus.masks[1]
    Check(mask.asset == contour.geometry.fill and mask.margins[1] == 9.5,
        "owned contour did not reuse the actual nine-sliced shell asset")
    Check(focus.canvas.scale == 1.5 and mask.width == 596 and mask.height == 396,
        "scaled contour stretched its corner radius or ignored the registered surface inset")
    Check(math.abs(mask.points[1][4] - 13 / 1.5) < 0.000001,
        "a slice aligned its contour to the cut instead of the original window")
    CheckStrength(focus, "masked provider")
    Check(math.abs(MaskedBlackOpacity(focus, 100, 100) - 0.42) < 0.000001,
        "contour mask weakened the painted window interior")
    Check(MaskedBlackOpacity(focus, 13 / 1.5 + 0.01, 13 / 1.5 + 0.01) == 0,
        "transparent shell corner acquired a rectangular black band")
    local masks = #focus.canvas.masks
    Visual.Show(focus, clipped, material, "DIALOG", 91)
    Check(#focus.canvas.masks == masks, "layout refresh recreated masks")
    Visual.Hide(focus, true)
end
_G.MSUF2 = nil
local native = Visual.Create()
local nativeContour = { art = { asset = "native-book", uv = { 0, 0, 0, 1, 1, 0, 1, 1 } },
    circle = { asset = "native-circle", uv = { 0, 0, 0, 1, 1, 0, 1, 1 }, left = 2/62, bottom = 4/62, width = 58/62, height = 58/62 } }
sourceRect.contour = nativeContour
Visual.Show(native, clipped, material, "DIALOG", 91)
CheckMasks(native, 2, "native portrait")
Check(native.masks[1].asset == "native-book" and native.masks[2].asset == "native-circle",
    "native portrait lost either its texture alpha or Blizzard circle mask")
_G.MSUF2 = { Theme = HostTheme(root .. "/../MidnightSimpleUnitFrames-7.0", hosts[2][2], hosts[2][3]) }
Visual.Refresh(native)
CheckMasks(native, 2, "late host portrait")
sourceRect.contour = nil
Visual.Show(native, clipped, material, "DIALOG", 91)
CheckMasks(native, 0, "reused unmasked root")
Visual.Hide(native, true)
_G.MSUF2 = nil
local unsupported = Visual.Create()
sourceRect.contour = contour
Visual.Show(unsupported, clipped, material, "DIALOG", 91)
unsupported.masks[1].SetTextureSliceMargins = nil
Visual.Refresh(unsupported)
Check(not unsupported.overlay.shown and not unsupported.dim,
    "unavailable mask slicing left an unmasked rectangular veil visible")

Check(H.ForeignWrites() == 0, "focus artwork changed a native frame")
Visual.Hide(record, true)
print("suite_window_focus_visual_contract: " .. checks .. " checks passed")

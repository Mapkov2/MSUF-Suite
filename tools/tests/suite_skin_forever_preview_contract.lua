local root = assert(arg[1], "Suite root required")
local install = arg[2] or root
local file = assert(io.open(root .. "/tools/tests/suite_skin_motion_contract.lua", "rb"))
local source = file:read("*a")
file:close()
local stop = assert(source:find('local parent = Target("Frame", UIParent)', 1, true))
arg[2] = "Forever"
local fixture = assert(loadstring(source:sub(1, stop - 1) .. [[
return { skin = NS, Target = Target, Texture = Texture }
]], "@forever_preview_fixture"))()
local skin, frames = fixture.skin, {}

local function Frame(kind, parent)
    local frame = fixture.Target(kind, parent)
    function frame:SetWidth(width) self.width = width end
    function frame:SetHeight(height) self.height = height end
    function frame:GetWidth() return self.width end
    function frame:GetHeight() return self.height end
    function frame:SetSize(width, height) self.width, self.height = width, height end
    function frame:SetPoint(point, relative, relativePoint, x, y)
        if type(relative) == "number" then x, y, relative = relative, relativePoint, self.parent end
        self.points = self.points or {}
        self.points[point] = { relative = relative, x = x or 0, y = y or 0 }
    end
    function frame:ClearAllPoints() self.points = {} end
    function frame:SetEnabled(enabled) self.enabled = enabled end
    function frame:SetAlpha(alpha) self.alpha = alpha end
    function frame:GetFrameLevel() return self.level or 1 end
    function frame:SetFrameLevel(level) self.level = level end
    function frame:SetShown(shown) if shown then self:Show() else self:Hide() end end
    function frame:GetLeft() return 0 end
    function frame:GetTop() return 0 end
    function frame:SetAllPoints() end
    function frame:EnableMouse() end
    function frame:RegisterForClicks(...) self.clicks = { ... } end
    function frame:LockHighlight() self.highlightLocked = true end
    function frame:UnlockHighlight() self.highlightLocked = false end
    function frame:CreateTexture()
        local texture = fixture.Texture()
        function texture:SetAllPoints() end
        function texture:SetColorTexture(...) self.color = { ... } end
        function texture:SetGradient(direction, from, to) self.gradient = { direction, from, to } end
        function texture:SetShown(shown) if shown then self:Show() else self:Hide() end end
        function texture:SetWidth(width) self.width = width end
        function texture:SetHeight(height) self.height = height end
        return texture
    end
    function frame:CreateFontString()
        local label = Frame("FontString", self)
        function label:SetJustifyH() end
        function label:SetWordWrap() end
        function label:SetText(text) self.text = text end
        function label:SetTextColor(...) self.color = { ... } end
        function label:GetFont() return self.font or "Native.ttf", self.size or 10, "" end
        function label:SetFont(path, size) self.font, self.size = path, size return true end
        function label:GetStringHeight() return 28 end
        function label:GetUnboundedStringWidth() return #(self.text or "") * 6 end
        return label
    end
    function frame:SetDataProvider(entries) self.initializer(Frame("Frame", self), entries[1]) end
    frames[#frames + 1] = frame
    return frame
end

CreateFrame = function(kind, _, parent) return Frame(kind, parent) end
CreateScrollBoxListLinearView = function()
    return { SetElementExtent = function() end, SetElementInitializer = function(self, _, fn) self.init = fn end }
end
ScrollUtil = { InitScrollBoxListWithScrollBar = function(list, _, view) list.initializer = view.init end }
CreateDataProvider = function(data) return data end
local tracked
skin.ScrollMotion = { Track = function(_, _, preview) tracked = preview end }
for _, path in ipairs({ "Core/Cosmetics.lua", "Rendering/IconSkin.lua" }) do
    assert(loadfile(install .. "/MSUF_Suite_Skin/" .. path))("MSUF_Suite_Skin", skin)
end
skin.Typography = { GetSelection = function() return "font" end,
    GetSelectionPath = function() return "Alternate.ttf" end }
local core = { Suite = {}, Skin = { GetWindowCaptionMode = function() return skin.DB.icons.windowActions.glyphMode end } }
local target
core.HostBridge = { OpenExactMenuSetting = function(_, page, section, key)
    target = { page, section, key }
    return true
end }
PixelUtil = { GetPixelToUIUnitFactor = function() return 1 end }
assert(loadfile(install .. "/MSUF_Suite/Core/WindowCaption.lua"))("MSUF_Suite", core)
local P = { Suite = core, S = core.Suite, Tr = function(value) return value end, Combat = function() return false end,
    HM = { GetSectionWidth = function() return 340 end, SkipHistoryCheckpoint = function() end,
        AllowCombatClick = function() end, SetCommandAction = function() end, SetFixedPreviewHeight = function() end },
    M = { TrackRefresh = function() end }, W = {}, T = { colors = { text = { 1, 1, 1, 1 } } } }
function P.T.Font(parent, _, text)
    local label = parent:CreateFontString()
    label:SetText(text)
    return label
end
function P.T.Button(parent, text, width, height)
    assert(text ~= "Open settings", "the preview still creates an Open settings button")
    local button = Frame("Button", parent)
    button:SetSize(width, height)
    return button
end
function P.Text(parent, text)
    local label = parent:CreateFontString()
    label:SetText(text)
    return label
end
function P.SetTranslatedText(label, text) label:SetText(text) end
function P.W.FixedPreviewSection()
    local section = Frame("Frame")
    return section, Frame("Frame", section)
end
for _, path in ipairs({ "Menu/PreviewCanvas.lua", "Menu/PreviewInteraction.lua", "Pages/AppearancePreview.lua" }) do
    assert(loadfile(install .. "/MSUF_Suite_Options/" .. path))("MSUF_Suite_Options", P)
end
local ctx = {}
P.BuildSkinMenuPreview(ctx, { width = 340 }, skin)
local preview = ctx.skinPreview
local buttons, captions = {}, {}
for _, frame in ipairs(frames) do
    if frame.kind == "FontString" and frame.parent:GetScript("OnClick") then buttons[frame.text] = frame.parent end
    if frame.caption then captions[frame.caption.kind] = frame end
end
assert(tracked and preview.panel:IsShown() and not preview.menu:IsShown())
local shell = skin.Registry.GetSurface(preview.shell)
local initialOpacity = select(4, shell.fill:GetVertexColor())
skin.Theme.SetAppearance("shellOpacity", .4)
assert(select(4, shell.fill:GetVertexColor()) < initialOpacity, "live shell opacity waited for global refresh")
local panel = skin.Registry.GetSurface(preview.panel)
local control = skin.Registry.GetSurface(preview.hoverSample)
local function CheckOpacity(key, texture, value)
    local before = select(4, texture:GetVertexColor())
    skin.Theme.SetAppearance(key, value)
    assert(select(4, texture:GetVertexColor()) < before, key .. " did not update the visible example")
end
CheckOpacity("panelOpacity", panel.fill, .42)
CheckOpacity("controlOpacity", control.fill, .43)
CheckOpacity("borderOpacity", shell.edge, .08)
skin.Theme.SetAppearance("materialDepth", .6)
assert(shell.depth and shell.depth:IsShown(), "surface depth did not update live")
skin.Theme.SetGradient(true)
skin.Theme.SetAppearance("gradientDirection", "HORIZONTAL")
skin.Theme.SetAppearance("gradientStrength", 0.5)
assert(shell.fill.gradient[1] == "HORIZONTAL" and shell.fill.gradient[2] ~= shell.fill.gradient[3], "shading was not applied live")
skin.Theme.SetGradient(false)
assert(shell.fill.gradient[2] == shell.fill.gradient[3], "the last gradient was retained after disabling shading")
for _, name in ipairs({ "Window opacity", "Content opacity", "Controls opacity", "Outline opacity" }) do
    assert(not buttons[name], "removed opacity shortcut rendered in the preview: " .. name)
end
local function OpensSetting(sample, section, setting, mouseButton)
    target = nil
    sample:Fire("OnClick", mouseButton or "LeftButton")
    assert(target and target[1] == "suite_skin" and target[2] == "suite_skin_" .. section
        and target[3] == "msufsuite.skin." .. setting, "preview did not open " .. setting)
end
OpensSetting(preview.hoverSample, "shape", "theme.hoverStyle")
OpensSetting(preview.panel, "material", "theme.materialDepth")
OpensSetting(preview.shell, "shape", "geometry.family")
OpensSetting(preview.nav, "shape", "theme.smoothScrolling")
OpensSetting(preview.card, "shape", "theme.readableValues")
OpensSetting(preview.item, "icons", "theme.iconBorderStyle")
OpensSetting(preview.fontSample, "fonts", "font.face")
OpensSetting(buttons.Menu, "shape", "theme.dropdownDimming")
OpensSetting(buttons.Focus, "shape", "theme.windowFocusDimming")
OpensSetting(buttons.Preview, "shape", "theme.menuAnimations")
OpensSetting(buttons["Preview window animation"], "shape", "theme.windowAnimations", "RightButton")
assert(not preview.menu:IsShown() and not preview.focusVeil:IsShown(), "opening settings changed the preview state")
local layerButtons = {}
for _, button in ipairs(preview.layerButtons) do layerButtons[button.key] = button end
OpensSetting(layerButtons.controls, "shape", "theme.hoverStyle", "RightButton")
assert(preview.hoverSample:IsVisible())
layerButtons.controls:Fire("OnClick", "LeftButton")
assert(not preview.hoverSample:IsVisible())
layerButtons.controls:Fire("OnClick", "LeftButton")
assert(preview.hoverSample:IsVisible() and preview.layers.controls)
layerButtons.item:Fire("OnClick", "LeftButton")
assert(not preview.item:IsVisible() and preview.card:IsVisible())
layerButtons.item:Fire("OnClick", "LeftButton")
assert(preview.item:IsVisible())
layerButtons.content:Fire("OnClick", "LeftButton")
layerButtons.controls:Fire("OnClick", "LeftButton")
skin.Theme.SetAppearance("hoverIntensity", 0.6)
assert(preview.hoverSample:IsVisible() and preview.hoverSample.highlightLocked,
    "the hover slider left its preview hidden")
skin.Theme.SetAppearance("hoverIntensity", 0.2)
local lowHover = select(4, control.highlight:GetVertexColor())
skin.Theme.SetAppearance("hoverIntensity", 0.9)
assert(select(4, control.highlight:GetVertexColor()) > lowHover, "the hover sample did not follow slider values")
layerButtons.item:Fire("OnClick", "LeftButton")
skin.Theme.SetAppearance("iconBorderStyle", "quality")
local item = skin.IconSkin.GetState(preview.item)
assert(preview.item:IsVisible() and item.lines[1].color[1] == .64, "the item quality sample did not update")
for _, opacity in ipairs({ .15, .40, .85 }) do
    skin.Theme.SetAppearance("iconBorderOpacity", opacity)
    assert(item.lines[1].color[4] == opacity, "an icon opacity drag step did not repaint")
end

local function CheckLayout(width)
    preview.section:SetWidth(width)
    preview.section:Fire("OnSizeChanged", width)
    local function Top(frame) return -frame.points.TOPLEFT.y end
    local function Bottom(frame) return Top(frame) + frame:GetHeight() end
    local stage = preview.shell
    local footer, chips = preview.footer, preview.chips
    local tabDividerBottom = 8 + 24 + 26 + 3 + 1
    assert(Top(stage) > tabDividerBottom, "preview overlaps the tabs")
    if width >= 712 then
        assert(stage.points.TOPLEFT.x + stage:GetWidth() < footer.points.TOPLEFT.x)
    else assert(Bottom(stage) < Top(footer)) end
    assert(Top(chips) == Bottom(footer) + 6)
    assert(Bottom(chips) < preview.section:GetHeight(), "layer bar exceeds its section")
    assert(stage.points.TOPLEFT.x + stage:GetWidth() <= width, "the sample window exceeds its section")
    assert(chips.points.TOPLEFT.x + chips:GetWidth() <= width)
    for _, button in ipairs(preview.layerButtons) do
        assert(button.points.TOPLEFT.x + button:GetWidth() <= chips:GetWidth() - 10)
    end
end
CheckLayout(280)
assert(preview.nav.points.TOPLEFT.x == preview.card.points.TOPLEFT.x and preview.actionBar.points.TOPLEFT.y < -26)
CheckLayout(940)
assert(preview.nav.points.TOPLEFT.x < preview.card.points.TOPLEFT.x and preview.actionBar.points.TOPLEFT.y == -1)
CheckLayout(340)
assert(preview.dropdownVeil:GetFrameLevel() > buttons.Menu:GetFrameLevel()
    and preview.dropdownVeil:GetFrameLevel() < preview.menu:GetFrameLevel(), "dropdown shade is outside its visual layer")
buttons.Menu:Fire("OnClick", "RightButton")
assert(preview.menu:IsShown() and preview.dropdownVeil:IsShown())
skin.Theme.SetAppearance("dropdownDimming", false)
assert(preview.menu:IsShown() and not preview.dropdownVeil:IsShown())
skin.Theme.SetAppearance("materialDepth", .8)
assert(preview.menu:IsShown(), "a material change dismissed the active dropdown preview")
buttons.Focus:Fire("OnClick", "RightButton")
assert(preview.focusVeil:IsShown())
OpensSetting(captions.minimize, "window_controls", "windowControls.enabled")
assert(preview.panel:IsShown())
captions.minimize:Fire("OnClick", "RightButton")
assert(not preview.panel:IsShown() and not preview.menu:IsShown() and preview.shell:GetHeight() == 35)
buttons.Preview:Fire("OnClick", "RightButton")
assert(preview.panel:IsShown() and preview.shell:GetHeight() == preview.shellHeight)
OpensSetting(captions.maximize, "window_controls", "windowControls.enabled")
captions.maximize:Fire("OnClick", "RightButton")
assert(captions.maximize.caption.kind == "restore")
OpensSetting(captions.close, "icons", "icons.windowActions.closeStyle")
assert(preview.shell:IsShown())
captions.close:Fire("OnClick", "RightButton")
assert(not preview.shell:IsShown())
buttons["Preview window animation"]:Fire("OnClick", "LeftButton")
assert(preview.shell:IsShown() and preview.panel:IsShown())
local opening = assert(skin.ContentMotion.records[preview.shell], "window preview did not start an opening fade")
assert(opening.window and skin.ContentMotion.active[opening], "window preview used the menu animation setting")
assert(skin.Theme.SetAppearance("windowAnimations", "off"))
buttons["Preview window animation"]:Fire("OnClick", "LeftButton")
assert(not skin.ContentMotion.active[opening], "window preview ignored the Off setting")
assert(skin.Theme.SetAppearance("windowAnimations", "subtle"))
local value
for _, row in ipairs(preview.labels) do if row.value then value = row.region end end
local _, original = value:GetFont()
local nativeRefresh, readabilityDomain = skin.Registry.QueueRefresh
skin.Registry.QueueRefresh = function() error("readability requested a full surface refresh") end
local listener = {}
skin.Registry.AddListener(listener, function(_, domain, key)
    if key == "readableValues" then readabilityDomain = domain end
end)
assert(skin.Theme.SetAppearance("readableValues", true))
assert(readabilityDomain == "readability", "readability requested a motion setting change")
local _, size = value:GetFont()
assert(size == original + 2)
assert(skin.Theme.SetAppearance("readableValues", false))
assert(select(2, value:GetFont()) == original, "turning readability off kept the larger sample font")
skin.Registry.RemoveListener(listener)
skin.Registry.QueueRefresh = nativeRefresh
skin.DB.typography.enabled = true
skin.Registry.NotifyListeners("typography", "enabled")
assert(value:GetFont() == "Alternate.ttf", "a font change did not repaint the sample")
skin.DB.typography.enabled = false
skin.Registry.NotifyListeners("typography", "enabled")
assert(value:GetFont() == "Native.ttf", "the native sample font did not come back")
layerButtons.actions:Fire("OnClick", "LeftButton")
assert(not preview.actionBar:IsShown())
skin.WindowActionSkin.SetOption("style", "soft")
assert(preview.actionBar:IsVisible(), "a window action setting left the action samples hidden")
assert(not skin.Registry.GetSurface(captions.close), "the flat caption picked up the action button surface")
assert(skin.Registry.GetSurface(preview.captions[1].cell).fill:IsShown(), "Soft action surface was not demonstrated")
skin.WindowActionSkin.SetOption("surfaceShape", "round")
skin.WindowActionSkin.SetOption("surfaceRadius", 8)
assert(skin.Registry.GetSurface(preview.captions[1].cell).geometry.radius == 8, "action radius did not update live")
-- Run the preview's profile listener before the action renderer, as Registry
-- iteration can do. The queued paint must pick up the renderer's invalidation.
local oldAfter, queued = C_Timer.After, {}
C_Timer.After = function(_, fn) queued[#queued + 1] = fn end
skin.DB.icons.windowActions.surfaceRadius = 12
skin.Registry.listeners[preview](preview, "profile")
skin.Registry.listeners[skin.WindowActionSkin](skin.WindowActionSkin, "profile")
for _, fn in ipairs(queued) do fn() end
C_Timer.After = oldAfter
assert(skin.Registry.GetSurface(preview.captions[1].cell).geometry.radius == 12,
    "the preview kept the last profile's action radius")
skin.WindowActionSkin.SetOption("style", "native")
skin.WindowActionSkin.SetOption("glyphMode", "plusMinus")
assert(captions.minimize.caption.glyphMode == "plusMinus" and captions.maximize.caption.glyphMode == "plusMinus")
assert(not captions.maximize.caption.bars[3]:IsShown(), "the square glyph remained after switching to a plus")
skin.WindowActionSkin.SetOption("glyphMode", "chevrons")
assert(captions.minimize.caption.bars[3]:IsShown() and captions.maximize.caption.bars[3]:IsShown())
assert(captions.maximize.caption.fill.color[4] == 0, "the unhovered caption is no longer flat")
OpensSetting(preview.captions[1].cell, "icons", "icons.windowActions.glyphMode")
OpensSetting(preview.captions[3].cell, "icons", "icons.windowActions.closeStyle")
preview.section:Hide()
assert(not skin.Registry.listeners[preview], "a hidden preview retained its settings listener")
preview.section:Show()
assert(skin.Registry.listeners[preview], "the preview stopped listening after reopening")
print("Forever skin preview: live materials, exact settings, scroll, dimming, flat symbols and action radius passed")

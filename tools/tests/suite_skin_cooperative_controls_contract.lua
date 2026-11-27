-- Exercise the public facade with the same geometry and input model as the native captions.
local root = assert(arg[1])
local function Source(file)
    local handle = assert(io.open(root .. "/tools/tests/" .. file, "rb"))
    local text = handle:read("*a"):gsub("\r\n", "\n")
    handle:close()
    return text
end
local flavor = arg[2] or "Mainline"
arg[2] = nil
local fixture = Source("suite_window_controls_contract.lua")
local cut = assert(fixture:find("-- Managed windows minimize", 1, true))
local NS, Frame, frames, combatJobs, nextFrame, errors, secretValues = assert(loadstring(fixture:sub(1, cut - 1)
    .. "\nreturn NS, Frame, createdFrames, combatJobs, NextFrame, reported, secretValues"))()
arg[2] = flavor
NS.Client.isForever = flavor == "Forever"
local checks, writes, reads, attaches = 0, 0, 0, 0
local function Check(ok, why)
    assert(ok, why .. (errors[1] and " / " .. errors[1] or ""))
    checks = checks + 1
end
local function noop() end
local function Load(file)
    assert(loadfile(root .. "/MSUF_Suite_Skin/" .. file .. ".lua"))("MSUF_Suite_Skin", NS)
end
local plainCreate = CreateFrame
CreateFrame = function(...)
    local frame = plainCreate(...)
    function frame:SetAllPoints(target) self.bounds = target end
    return frame
end
local function Art(parent, kind, alpha)
    local art = { parent = parent, color = { .15, .25, .4, alpha or 1 }, alpha = .75 }
    function art:GetParent() return self.parent end
    function art:GetObjectType() return kind or "Texture" end
    function art:IsProtected() return self.protected or false end
    function art:GetVertexColor() return unpack(self.color) end
    function art:SetVertexColor(...) writes = writes + 1 self.color = { ... } end
    function art:GetAlpha() return self.alpha end
    function art:SetAlpha(value) self.alpha = value end
    art.GetTextColor, art.SetTextColor = art.GetVertexColor, art.SetVertexColor
    return art
end
local secretEnabled = {}
local function Button(parent, kind)
    local button = Frame(nil, parent, kind or "Button")
    function button:HasScript() return true end
    function button:IsEnabled() return not self.disabled end
    function button:SetEnabled(value)
        if value == secretEnabled then
            assert(not self.hooks.OnEnable and not self.hooks.OnDisable, "skin added forbidden button-state scripts")
            return
        end
        self.disabled = not value
    end
    function button:Enable() self.disabled = false end
    function button:Disable() self.disabled = true end
    function button:GetButtonState() return "NORMAL" end
    function button:GetNormalTexture() return self.normal end
    function button:GetCheckedTexture() return self.checked end
    function button:GetDisabledCheckedTexture() return self.disabledChecked end
    function button:SetDisabledTexture(value) self.disabledTex = value end
    return button
end
local function Fire(frame, event)
    if frame.scripts[event] then frame.scripts[event](frame) end
    for _, hook in ipairs(frame.hooks[event] or {}) do hook(frame) end
end
local function Drain()
    _G.combat = false
    local todo = {}
    for key, callback in pairs(combatJobs) do todo[#todo + 1] = callback combatJobs[key] = nil end
    for _, callback in ipairs(todo) do callback() end
    nextFrame()
end

Load("Core/Registry")
Load("../MSUF_Suite/Appearance/Cosmetics")
Load("Rendering/ScrollBarSkin")
NS.publicAPIMajor, NS.publicAPIMinor = 2, 6
NS.DB.addonSkins, NS.DB.blizzardWindowsEnabled = { registered = true, enabled = false }, false
NS.Clamp = function(n, low, high) return math.max(low, math.min(high, tonumber(n) or low)) end
NS.IconSkin = { GetOwner = noop, DisableOwner = noop }
NS.WindowActionSkin.GetOwner, NS.WindowActionSkin.DisableOwner = noop, noop
NS.WindowActionSkin.ApplyExplicit = function(_, _, action, _, options) return { action = action, options = options } end
NS.ControlSkin = { states = {}, GetOwner = noop, DisableOwner = noop,
    ApplyTab = function(tab, _, spec) tab.requested = spec.active return {} end }
NS.Typography = { GetSelection = noop, GetSelectionPath = function() return "Fonts/test.ttf" end }
NS.CombatGate.Cancel = function(key) combatJobs[key] = nil end
NS.Surface.Attach = function(frame, spec)
    attaches = attaches + 1
    local state = { visible = true, spec = spec, refresh = noop }
    NS.Registry.RegisterSurface(frame, state)
    return state
end
NS.Surface.SetActive = function(frame, on) frame.active = on return true end
NS.Surface.SetVisible = function(frame, on)
    local surface = NS.Registry.GetSurface(frame)
    if surface then surface.visible = on end
    return true
end
NS.Surface.SetNativeStateSync, NS.Surface.Refresh = noop, noop
NS.SuiteOwnership.IsOptionsSurface = function(target) return target.hostMenu end
NS.Theme.GetColor = function(key)
    reads = reads + 1
    return unpack((assert(NS.Defaults.theme.colors[key], tostring(key))))
end
DropdownButtonMixin = { Event = { OnMenuOpen = "open", OnMenuClose = "close" } }
for _, name in ipairs({ "Core/LabelStyle", "Rendering/PublicWidgetParts", "Rendering/PublicWidgetSkin", "Rendering/PublicCaption",
    "Rendering/PublicMenuStyle", "Rendering/AddonWindowControls", "Core/PublicAPIControls", "Core/PublicAPI",
    "Core/PublicAPIMethods" }) do Load(name) end
local api = NS.PublicAPI.API
local skin = assert(api:RegisterAddon("BetterFriendlist"))
local settled = 0
assert(skin:SetTargetNotifications(true))
skin.OnTargetsSettled = function() settled = settled + 1 end
local other = assert(api:RegisterAddon("UnrelatedAddon"))
local suite = assert(NS.PublicAPI.RegisterSuiteAddon("settings"))
local host = assert(api:RegisterAddon("MidnightSimpleUnitFrames"))
local tab = Button(UIParent)
tab.IsSelected = function() return true end
Check(select(2, skin:SkinTab(tab, { active = false })) == "pending", "cold registration")
Check(skin:GetTargetStatus(tab) == "pending" and other:GetTargetStatus(tab) == "unknown-target", "scoped status")
NS.PublicAPI.Activate()
NS.PublicAPI.OnPlayerLogin()
Check(tab.requested == false and skin:GetTargetStatus(tab) == "applied", "explicit false lost")
local hidden = Frame(nil, UIParent)
hidden.hostMenu, hidden.shown = true, false
local _, result = host:SkinFrame(hidden)
Check(result == "applied" and host:GetTargetStatus(hidden) == "pending-visible", "hidden host handoff")
hidden:Show()
Check(host:GetTargetStatus(hidden) == "applied", "shown host handoff")

local stable = assert(NS.PublicAPI.RegisterSuiteAddon("perfy-stable"))
local panel = Frame(nil, UIParent)
Check(stable:SkinFrame(panel) and stable:IsCurrent(), "authored scope stayed dirty after its first paint")
local initialAttaches = attaches
for _ = 1, 10 do Check(stable:IsCurrent(), "unchanged authored scope became dirty") end
Check(attaches == initialAttaches, "scope readiness repainted an unchanged surface")
NS.Registry.NotifyListeners("geometry", "windowRadius")
Check(not stable:IsCurrent(), "scope readiness ignored the new settings generation")
Check(stable:RefreshAll() and attaches == initialAttaches + 1 and stable:IsCurrent(), "settings change did not repaint once")
_G.combat = true
Check(stable:ReleaseAll() and not stable:IsCurrent(), "scope readiness ignored a pending release")
Drain()

local drop = Button(UIParent)
drop.Text, drop.Arrow, drop.Background = Art(drop, "FontString"), Art(drop), Art(drop)
local selected, callbacks = 0, {}
drop:SetScript("OnClick", function() selected = selected + 1 end)
function drop:IsMenuOpen() return self.open end
function drop:RegisterCallback(event, callback, owner) callbacks[event] = { callback, owner } end
function drop:UnregisterCallback(event, owner) assert(callbacks[event][2] == owner) callbacks[event] = nil end
Check(skin:SkinDropdown(drop), "WowStyle dropdown")
Check(drop.Background.alpha == 0 and callbacks.open and callbacks.close, "dropdown trigger art")
Fire(drop, "OnEnter")
local first = writes
for _ = 1, 1000 do Fire(drop, "OnEnter") end
Check(writes == first and drop.active, "duplicate hover repainted")
Fire(drop, "OnLeave")
drop.open = true callbacks.open[1](callbacks.open[2])
Check(drop.active, "opened dropdown")
Fire(drop, "OnMouseDown") Fire(drop, "OnMouseUp") Fire(drop, "OnClick")
drop.open = false callbacks.close[1](callbacks.close[2])
drop:SetEnabled(secretEnabled)
drop:Disable()
Check(selected == 1 and drop.Arrow.color[1] == NS.Defaults.theme.colors.disabled[1], "native dropdown input or disabled state")
Check(not other:Fade(drop.Arrow), "foreign scope acquired a dropdown part")
local r, w, a = reads, writes, attaches
for _ = 1, 10000 do assert(skin:GetTargetStatus(drop) == "applied") end
Check(reads == r and writes == w and attaches == a, "status queries caused rendering")
Check(skin:Release(drop) and not next(callbacks) and drop.Background.alpha == .75 and drop.Arrow.color[1] == .15, "dropdown release")

local filter = Button(UIParent)
filter.Background, filter.Text = Art(filter), Art(filter, "FontString")
WowStyle1FilterDropdownMixin = { GetBackgroundAtlas = function() return "common-dropdown-b-button" end }
filter.GetBackgroundAtlas = WowStyle1FilterDropdownMixin.GetBackgroundAtlas
local filterArrow = Art(filter)
filterArrow.Show = function(art) art.shown = true end
filterArrow.Hide = function(art) art.shown = false end
filterArrow.SetTexture, filterArrow.SetPoint, filterArrow.SetSize, filterArrow.SetRotation = noop, noop, noop, noop
local generated = 0
function filter:CreateTexture() generated = generated + 1 return filterArrow end
Check(skin:SkinDropdown(filter) and filterArrow.shown and filter.Background.alpha == 0, "native Filter lost its glyph")
filter:Disable()
Check(filterArrow.color[1] == NS.Defaults.theme.colors.disabled[1], "generated glyph ignored disabled state")
local customArrow = Art(filter)
Check(skin:SkinDropdown(filter, { arrow = customArrow }) and not filterArrow.shown
    and customArrow.color[1] == NS.Defaults.theme.colors.disabled[1], "explicit arrow must win")
Check(skin:SkinDropdown(filter) and filterArrow.shown and generated == 1, "generated arrow was not reused")
Check(skin:Release(filter) and not filterArrow.shown and filter.Background.alpha == .75, "native Filter release")

local check = Button(UIParent, "CheckButton")
check.checked, check.disabledChecked = Art(check, nil, 0), Art(check)
Check(skin:SkinCheckButton(check) and check.checked.color[4] == 0, "hidden radio/check indicator")
local old = check.checked
old.parent, check.checked = UIParent, Art(check)
Check(skin:Refresh(check) and other:Fade(old) and other:Release(old), "detached pooled indicator retained claims")
check:SetEnabled(secretEnabled)
check:SetEnabled(false)
Check(check.disabledChecked.color[1] == NS.Defaults.theme.colors.disabled[1], "disabled checked art")
check.checked.color = { .9, .8, .7, .6 }
Check(skin:Release(check) and check.checked.color[1] == .9 and check.disabledChecked.color[1] == .15, "checked art restore")

local wrapper = Button(UIParent, "Slider")
wrapper.Slider = Button(wrapper, "Slider")
wrapper.Slider.Thumb, wrapper.Slider.Middle = Art(wrapper.Slider), Art(wrapper.Slider)
wrapper.Back, wrapper.Forward = Button(wrapper), Button(wrapper)
wrapper.Back.Texture, wrapper.Forward.Texture = Art(wrapper.Back), Art(wrapper.Forward)
function wrapper:GetThumbTexture() return nil end
function wrapper.Slider:GetThumbTexture() return self.Thumb end
Check(skin:SkinSlider(wrapper) and wrapper.Slider.Thumb.color[1] ~= .15 and wrapper.Back.Texture.color[1] ~= .15,
    "BFL nested slider, native track or steppers")
local moves = 0
wrapper.Slider:SetScript("OnValueChanged", function() moves = moves + 1 end)
r, w, a = reads, writes, attaches
for _ = 1, 10000 do Fire(wrapper.Slider, "OnValueChanged") end
Check(moves == 10000 and reads == r and writes == w and attaches == a and not wrapper.Slider.hooks.OnUpdate
    and not wrapper.Slider.hooks.OnMouseDown, "drag triggered skin work")
Check(not skin:SkinSlider(wrapper, { thumb = drop.Arrow }), "foreign thumb accepted")
Check(skin:Release(wrapper) and wrapper.Slider.Thumb.color[1] == .15, "nested slider release")
Check(skin:SkinScrollBar(wrapper) and skin:Release(wrapper), "ordinary Slider scrollbar fallback")

local backArt, forwardArt, unrelated = Art(wrapper.Back), Art(wrapper.Forward), Art(wrapper.Back)
wrapper.Back.Texture, wrapper.Forward.Texture = nil, nil
function backArt:GetAtlas() return "Minimal_SliderBar_Button_Left" end
function forwardArt:GetAtlas() return "Minimal_SliderBar_Button_Right" end
function wrapper.Back:GetRegions() return unrelated, backArt end
function wrapper.Forward:GetRegions() return forwardArt end
wrapper.Back:Disable()
Check(skin:SkinSlider(wrapper) and backArt.color[1] == NS.Defaults.theme.colors.disabled[1]
    and forwardArt.color[1] == NS.Defaults.theme.colors.blizzardArrow[1] and unrelated.color[1] == .15,
    "anonymous native stepper art or initial endpoint state")
wrapper.Back:Enable()
wrapper.Forward:Disable()
Check(backArt.color[1] == NS.Defaults.theme.colors.blizzardArrow[1]
    and forwardArt.color[1] == NS.Defaults.theme.colors.disabled[1], "per-stepper endpoint painting")
r, w = reads, writes
for _ = 1, 1000 do wrapper.Back:SetEnabled(true) wrapper.Forward:SetEnabled(false) end
Check(reads == r and writes == w, "steady stepper state repainted on native value change")
local forwardEnabled = wrapper.Forward.IsEnabled
local privateEnabled = {}
secretValues[privateEnabled] = true
function wrapper.Forward:IsEnabled() return privateEnabled end
wrapper.Back:Disable()
Check(forwardArt.color[1] == NS.Defaults.theme.colors.disabled[1], "unreadable stepper lost its last known state")
Check(skin:Release(wrapper) and skin:SkinSlider(wrapper) and forwardArt.color[1] == .15,
    "stepper with no known state was painted")
wrapper.Forward.IsEnabled = forwardEnabled
wrapper.Forward:Disable()
_G.combat = true
wrapper.Forward:Enable()
Check(forwardArt.color[1] == NS.Defaults.theme.colors.disabled[1], "stepper repainted in combat")
Drain()
Check(forwardArt.color[1] == NS.Defaults.theme.colors.blizzardArrow[1], "queued stepper repaint lost")
Check(not skin:SkinSlider(wrapper, { backArt = forwardArt }), "another stepper's art accepted")
Check(skin:SkinSlider(wrapper, { backArt = unrelated }) and unrelated.color[1] ~= .15 and backArt.color[1] == .15,
    "named stepper art did not take precedence")
Check(skin:Release(wrapper) and unrelated.color[1] == .15 and forwardArt.color[1] == .15, "stepper release")

local nativeSource = Source("suite_skin_absorption_contract.lua")
local start = assert(nativeSource:find("local function MinimalScrollBar(name)", 1, true))
local finish = assert(nativeSource:find("    return scroll, thumb, back, forward\nend", start, true))
local make = assert(loadstring(nativeSource:sub(start, finish - 1) .. "return scroll, thumb, back, forward end\nreturn MinimalScrollBar"))
local env = { new_frame = function(kind, name, parent) return Frame(name, parent, kind) end, new_region = Art }
setfenv(make, setmetatable(env, { __index = _G }))
local bar, thumb, back, forward = make()("CooperativeScroll")
for _, part in ipairs({ bar.Track, thumb }) do
    for _, key in ipairs({ "Begin", "Middle", "End" }) do part[key].parent = part end
end
back.Texture.parent, forward.Texture.parent = back, forward
local motion = 0
NS.ScrollBarSkin.SetScrollMotionProvider(function() motion = motion + 1 end, noop)
Check(skin:SkinScrollBar(bar), "native MinimalScrollBar")
Check(bar.Track.Begin.alpha == 0 and thumb.Begin.color[1] ~= .12 and motion == 0, "minimal thumb/track and motion")
Check(not other:SkinFrame(thumb), "shared scrollbar child")
local barReads, barWrites = reads, writes
for i = 1, 10000 do bar:SetScrollPercentage(i / 10000) end
Check(bar:GetScrollPercentage() == 1 and reads == barReads and writes == barWrites, "scroll triggered skin work")
Check(skin:Refresh(bar) and skin:Release(bar) and bar.Track.Begin.alpha == 1 and thumb.Begin.color[1] == .12, "scrollbar release")

local win, closeClicks = Frame("BetterFriendlistWindow", UIParent), 0
local close = Button(win)
close.normal = Art(close)
close:SetScript("OnClick", function() closeClicks = closeClicks + 1 win:Hide() end)
local points = { { "TOPLEFT", UIParent, "TOPLEFT", 20, -40 }, { "BOTTOMRIGHT", UIParent, "BOTTOMRIGHT", -80, 65 } }
function win:GetPoint(n) return unpack(points[n]) end
function win:GetNumPoints() return #points end
function win:ClearAllPoints() points = {} end
function win:SetPoint(...) points[#points + 1] = { ... } end
function win:IsAnchoringRestricted() return self.restricted == true end
win.scale = .9
local hiddenState
win:HookScript("OnHide", function() hiddenState = skin:GetWindowState(win) end)
local windowOptions = { closeButton = close, minimize = true, maximize = true, minScale = .75, maxScale = 1.25 }
local from = #frames
Check(skin:RegisterWindow(win, windowOptions), "registered window")
local max, min, restore, cell
for i = from + 1, #frames do
    local frame = frames[i]
    if frame.parent == close then cell = frame
    elseif frame.parent == UIParent then restore = frame
    elseif frame.point and frame.point[2] == close then max = frame
    elseif frame.parent == win then min = frame end
end
Check(cell and max and min and restore and cell.mouseEnabled == false and close.normal.alpha == 0, "caption hit area or controls")
Fire(close, "OnEnter")
Check(cell.textures[2].color[1] == 1 and cell.textures[1].color[4] == .85, "caption white cross and red hover")
Fire(close, "OnMouseDown")
Check(cell.textures[1].color[4] == 1, "caption pressed fill")
close:SetEnabled(secretEnabled)
close:Disable()
Check(cell.textures[1].color[4] < .85, "disabled caption kept pressed art")
close:Enable()
Fire(close, "OnEnter")
Check(cell.textures[1].color[4] == .85, "caption did not repaint after enable")
local captionReads = reads
for _ = 1, 1000 do close:SetEnabled(true) end
Check(reads == captionReads, "unchanged enabled states repainted the caption")
Check(skin:Refresh(close) and close.normal.alpha == 0, "caption failed own claim on refresh")
local original = close.normal
close.normal = Art(close)
Check(skin:Refresh(close) and original.alpha == .75 and close.normal.alpha == 0, "pooled close art")
Fire(max, "OnClick")
Check(win.scale == 1.25 and points[1][3] == "CENTER", "fit bound")
local fitted = skin:GetWindowState(win)
Check(fitted.fitted and not fitted.minimized and not other:GetWindowState(win), "scoped fit state")
fitted.fitted = false
Check(skin:GetWindowState(win).fitted, "window state leaked a mutable reference")
Fire(max, "OnClick")
Check(win.scale == .9 and #points == 2 and points[1][4] == 20 and points[2][5] == 65, "exact two-anchor restore")
win.restricted = true Fire(max, "OnClick") win.restricted = false
_G.combat = true Fire(max, "OnClick") Fire(min, "OnClick")
Check(win.shown and win.scale == .9 and points[1][4] == 20, "combat or restricted geometry writes") Drain()
Fire(min, "OnClick") Check(not win.shown and restore.shown, "minimize")
Check(hiddenState.minimized and not hiddenState.fitted, "minimized state observable during OnHide")
Fire(restore, "OnClick") Check(win.shown and not restore.shown, "restore tab")
Fire(max, "OnClick") Fire(close, "OnClick")
Check(closeClicks == 1 and not win.shown and win.scale == .9, "normal close behavior")
Check(hiddenState.fitted and not skin:GetWindowState(win).fitted, "OnHide must see temporary geometry before it is restored")
win:Show()
Fire(max, "OnClick")
Fire(min, "OnClick")
Check(hiddenState.fitted and hiddenState.minimized, "fit and minimization can coexist")
_G.combat = true
Check(select(2, skin:RestoreWindowGeometry(win)) == "combat" and skin:GetWindowState(win).fitted, "geometry restore in combat")
Drain()
local setPoint, errorCount = win.SetPoint, #errors
function win:SetPoint() error("fixture anchor cycle") end
local restored, restoreReason = skin:RestoreWindowGeometry(win)
win.SetPoint = setPoint
Check(not restored and restoreReason == "geometry-failed" and skin:GetWindowState(win).fitted
    and #errors == errorCount + 1 and errors[#errors]:find("fixture anchor cycle", 1, true),
    "anchor failure lost fit state or escaped the geometry boundary")
errors[#errors] = nil
Check(skin:RestoreWindowGeometry(win) and not win.shown and restore.shown and win.scale == .9 and points[1][4] == 20,
    "explicit geometry restore must preserve visibility and anchors")
Fire(restore, "OnClick")
NS.DB.windowControls.enabled = false NS.Registry.NotifyListeners("windowControls", "enabled")
Check(skin:GetTargetStatus(win) == "suspended" and not min.shown and close.normal.alpha == .75, "window controls toggle")
NS.DB.windowControls.enabled = true NS.Registry.NotifyListeners("windowControls", "enabled")
Check(skin:GetTargetStatus(win) == "applied" and min.shown and close.normal.alpha == 0, "window controls resume")
Check(skin:Release(win) and close.normal.alpha == .75 and not max.shown, "release sponsored close and controls")
Check(not skin:GetWindowState(win), "released window still has public state")
Check(skin:RegisterWindow(win, windowOptions), "register default visibility window")
Fire(min, "OnClick")
Check(skin:Release(win) and win.shown, "default release should restore visibility")
windowOptions.showOnRelease = false
Check(skin:RegisterWindow(win, windowOptions), "register keep-hidden window")
Fire(max, "OnClick") Fire(min, "OnClick")
NS.DB.windowControls.enabled = false NS.Registry.NotifyListeners("windowControls", "enabled")
Check(not win.shown and not restore.shown and win.scale == .9 and points[1][4] == 20, "disable reopened a minimized window")
NS.DB.windowControls.enabled = true NS.Registry.NotifyListeners("windowControls", "enabled")
win:Show()
Fire(min, "OnClick")
Check(skin:Release(win) and not win.shown and not restore.shown, "release reopened a minimized window")
win:Show()
Check(skin:SkinWindowAction(close, "close") and skin:RegisterWindow(win, windowOptions) and close.normal.alpha == 0,
    "registration did not adopt a previously skinned standalone close")
Check(skin:Release(win) and skin:GetTargetStatus(close) == "applied" and close.normal.alpha == .75,
    "releasing registration removed explicit action")
Check(not skin:SkinWindowAction(close, "close", { direction = "left" }), "invalid direction was accepted")
Check(not skin:SkinWindowAction(close, "expand", { appearance = "caption" }), "invalid caption role")
Check(not skin:RegisterWindow(Frame("CharacterFrame", UIParent), windowOptions), "native window accepted")
Check(not skin:RegisterWindow(Frame(nil, win), { minimize = true }), "nested window accepted")
win.restricted = true Check(not skin:RegisterWindow(win, { maximize = true }), "restricted anchors accepted") win.restricted = false

local function Near(left, right)
    return math.abs(left - right) < .00001
end
local fitOptions = {
    maximize = true, minScale = .5, maxScale = 2,
    fitInsets = { left = 100, right = 20, top = 40, bottom = 10 },
    fitRect = { left = 120, right = 960, bottom = 200, top = 900 },
}
Check(skin:RegisterWindow(win, fitOptions), "register custom fit bounds")
fitOptions.fitInsets.left, fitOptions.fitRect.right = 2000, 5
local effectiveScale = win.GetEffectiveScale
UIParent.scale = .8
function win:GetEffectiveScale() return self.scale * UIParent.scale * 1.25 end
Fire(max, "OnClick")
local ratio = win.scale * 1.25
local left = UIParent.width / 2 + (points[1][4] - 100) * ratio
local right = UIParent.width / 2 + (points[2][4] + 20) * ratio
local top = UIParent.height / 2 + (points[1][5] + 40) * ratio
local bottom = UIParent.height / 2 + (points[2][5] - 10) * ratio
Check(skin:GetWindowState(win).fitted and Near(ratio, 840 / 720) and Near(left, 120) and Near(right, 960)
    and Near((top + bottom) / 2, 550) and top <= 900 and bottom >= 200,
    "custom fit did not keep the asymmetric visual bounds in the UIParent rectangle")
Check(skin:RestoreWindowGeometry(win) and win.scale == .9 and points[1][4] == 20 and points[2][5] == 65,
    "custom fit lost the floating geometry")
win.GetEffectiveScale, UIParent.scale = effectiveScale, 1
Check(skin:RegisterWindow(win, { maximize = true, minScale = 1, fitInsets = { left = 2000 } }), "insets-only registration")
Fire(max, "OnClick")
Check(not skin:GetWindowState(win).fitted and win.scale == .9 and points[1][4] == 20, "impossible fit changed the window")
Check(skin:RegisterWindow(win, {
    maximize = true, minScale = .5, fitRect = { left = 1200, right = 3000, bottom = 50, top = 650 },
}), "rectangle-only registration")
Fire(max, "OnClick")
Check(Near(win.scale, 1.2) and Near(UIParent.width / 2 + points[2][4] * win.scale, UIParent.width),
    "fit rectangle was not clipped to the current viewport")
Check(skin:Release(win) and win.scale == .9 and points[1][4] == 20, "releasing a custom fit did not restore anchors")
local secretInset = {}
secretValues[secretInset] = true
for _, options in ipairs({
    { maximize = true, fitInsets = { left = -1 } },
    { maximize = true, fitInsets = { left = math.huge } },
    { maximize = true, fitInsets = { left = secretInset } },
    { maximize = true, fitRect = { left = 0, right = 1, bottom = 5, top = 4 } },
    { maximize = true, fitRect = { left = 0, right = 1, top = 5 } },
    { minimize = true, fitInsets = {} },
}) do
    Check(select(2, skin:RegisterWindow(win, options)) == "invalid-options", "accepted invalid fit bounds")
end

Check(api:HasCapability("menuStyleTokens") and api:HasCapability("targetStatus"), "2.4 capabilities")
Check(api:HasCapability("windowGeometry") and api:HasCapability("menuDescriptionStyling")
    and api:HasCapability("standardWidgetArtwork"), "2.5 capabilities")
Check(api:HasCapability("windowFitBounds") and api:HasCapability("menuDescriptionFontOptions")
    and api:HasCapability("menuSurface") and select(3, api:GetVersion()) == 6, "2.6 capabilities")
local menu = assert(skin:GetMenuStyle())
menu.text[1] = 99
Check(skin:GetMenuStyle().text[1] ~= 99 and menu.font == "Fonts/test.ttf" and #menu.arrow == 4, "detached menu tokens")
local function Description(children)
    local d = { initializers = {} }
    function d:AddInitializer(initializer) self.initializers[#self.initializers + 1] = initializer end
    function d:EnumerateElementDescriptions() return ipairs(children or {}) end
    return d
end
local radio, checkbox, ordinary = Description(), Description(), Description()
local submenu = Description({ radio, checkbox })
local menuRoot = Description({ ordinary, submenu })
menuRoot.AddMenuReleasedCallback = noop
local row = Button(UIParent)
row.AttachTexture, row.AttachFontString, row.AttachFrame, row.AttachTemplate = noop, noop, noop, noop
local fonts = 0
CreateFont = function()
    fonts = fonts + 1
    local font = {}
    function font:SetFont(path, height, flags) self.font, self.height, self.flags = path, height, flags end
    function font:GetFont() return self.font, self.height, self.flags end
    return font
end
local function Acquire(element, art, sampleFont)
    row.fontString, row.highlight = Art(row, "FontString"), Art(row)
    row.fontString.font = sampleFont
    function row.fontString:GetFont() return "Fonts/original.ttf", 12, "" end
    function row.fontString:SetFontObject(font) self.font, self.height = font:GetFont() end
    row.leftTexture1 = art and Art(row)
    row.leftTexture2 = art == "split" and Art(row) or nil
    if art == "classic" then
        function row.leftTexture1:GetAtlas() return "common-dropdown-icon-radialtick-yellow-classic" end
    end
    local compositorMetatable = { __index = function(_, key)
        assert(key ~= "SetFont", "SetFont is forbidden on native Menu font strings")
    end }
    if art ~= "persistent" then setmetatable(row.fontString, compositorMetatable) end
    setmetatable(row.highlight, compositorMetatable)
    if row.leftTexture1 then setmetatable(row.leftTexture1, compositorMetatable) end
    if row.leftTexture2 then setmetatable(row.leftTexture2, compositorMetatable) end
    for _, init in ipairs(element.initializers) do init(row, element) end
end
Check(skin:SkinMenuDescription(menuRoot) and skin:SkinMenuDescription(menuRoot) and #radio.initializers == 1
    and not other:SkinMenuDescription(menuRoot), "menu description binding or ownership")
Acquire(radio, flavor == "Forever" and "classic" or "split")
local mark = row.leftTexture2 or row.leftTexture1
Check(mark.color[1] == NS.Defaults.theme.colors.checkmark[1]
    and row.fontString.color[1] == NS.Defaults.theme.colors.accentBright[1]
    and row.fontString.font == "Fonts/test.ttf" and row.fontString.height == 12
    and row.highlight.color[1] == NS.Defaults.theme.colors.hover[1], "native radio, selected label or hover artwork")
Acquire(checkbox, "split")
Check(row.leftTexture2.color[1] == NS.Defaults.theme.colors.checkmark[1]
    and row.leftTexture1.color[1] == NS.Defaults.theme.colors.borderSoft[1] and fonts == 1,
    "native checkbox and shared menu font")
Acquire(ordinary)
Check(row.fontString.color[1] == NS.Defaults.theme.colors.text[1], "ordinary menu row")
local preserve = { preserveFont = true }
Check(skin:SkinMenuDescription(menuRoot, preserve) and #radio.initializers == 1, "enable menu font preservation")
preserve.preserveFont = false
Acquire(radio, "split", "Fonts/sample.ttf")
Check(row.fontString.font == "Fonts/sample.ttf" and fonts == 1
    and row.fontString.color[1] == NS.Defaults.theme.colors.accentBright[1]
    and row.leftTexture2.color[1] == NS.Defaults.theme.colors.checkmark[1]
    and row.highlight.color[1] == NS.Defaults.theme.colors.hover[1], "font sample lost its font or row styling")
Check(select(2, skin:SkinMenuDescription(menuRoot, { preserveFont = "yes" })) == "invalid-options",
    "invalid menu font option")
Check(skin:SkinMenuDescription(menuRoot, preserve), "reset menu font settings")
Acquire(radio, "split", "Fonts/sample.ttf")
Check(row.fontString.font == "Fonts/test.ttf", "menu font override did not resume")
Acquire(ordinary, "persistent")
Check(row.fontString.color[1] == .15 and row.highlight.color[1] == .15, "persistent menu template regions were recolored")
Acquire(Description())
Check(row.fontString.color[1] == .15 and row.highlight.color[1] == .15, "style leaked on an unrelated pooled row")

local popup = Frame(nil, UIParent)
popup.AttachFontString, popup.AttachFrame, popup.AttachTemplate = noop, noop, noop
function popup:AttachTexture()
    local region = Art(self)
    function region:SetPoint(...) self.anchors[#self.anchors + 1] = { ... } end
    function region:SetDrawLayer(layer) self.layer = layer end
    function region:SetColorTexture(...) self.fill = { ... } end
    function region:SetWidth(width) self.width = width end
    function region:SetHeight(height) self.height = height end
    region.anchors = {}
    self.attachments[#self.attachments + 1] = region
    return region
end
local nativeGenerations = 0
local nativeMixin = {
    Generate = function() nativeGenerations = nativeGenerations + 1 end,
    GetInset = function() return { left = 14 } end,
    GetChildExtentPadding = function() return { width = 5 } end,
}
local popupStyle = assert(skin:CreateMenuMixin(nativeMixin))
Check(select(2, skin:CreateMenuMixin({})) == "invalid-menu-mixin", "accepted incomplete menu mixin")
local function GeneratePopup()
    -- The compositor clears every attachment before the next lease.
    popup.attachments = {}
    popupStyle.Generate(popup)
    return popup.attachments
end
local surface = GeneratePopup()
Check(#surface == 5 and nativeGenerations == 0
    and surface[1].fill[1] == NS.Defaults.theme.colors.popup[1] and surface[1].anchors[1][4] == 1
    and surface[2].fill[1] == NS.Defaults.theme.colors.border[1] and surface[2].width == 1
    and surface[4].height == 1 and surface[5].layer == "BACKGROUND"
    and popupStyle:GetInset().left == 14 and popupStyle:GetChildExtentPadding().width == 5
    and nativeMixin.Generate ~= popupStyle.Generate, "popup surface did not preserve compositor ownership or template layout")
Check(#GeneratePopup() == 5 and popup.attachments[1] ~= surface[1], "new popup lease reused the old surface attachments")
popup.protected = true
Check(#GeneratePopup() == 0 and nativeGenerations == 1, "protected popup did not fall back to its own mixin")
popup.protected = false
_G.combat = true
Acquire(radio, "split")
Check(row.fontString.color[1] == .15, "native menu styling wrote during combat")
Check(#GeneratePopup() == 0 and nativeGenerations == 2, "popup surface styled during combat")
Drain()
local function Switch(on) NS.DB.addonSkins.registered = on NS.Registry.NotifyListeners("addonSkins", "registered") end
Switch(false)
Acquire(radio, "split")
Check(row.fontString.color[1] == .15, "native menu styling ignored the addon skin switch")
Check(#GeneratePopup() == 0 and nativeGenerations == 3, "popup surface ignored the addon skin switch")
Check(not skin:IsEnabled() and skin:GetTargetStatus(tab) == "suspended" and not skin:GetMenuStyle()
    and suite:IsEnabled() and host:IsEnabled() and api:IsEnabled(), "registered switch affected the wrong scope")
Switch(true)
Check(#GeneratePopup() == 5, "popup did not return to the Suite surface after resuming")
Check(skin:IsEnabled() and skin:GetTargetStatus(tab) == "applied" and not NS.DB.blizzardWindowsEnabled, "independent resume")
NS.DB.enabled = false NS.Registry.NotifyListeners("adapter", "master")
Check(not host:IsEnabled() and not suite:IsEnabled() and not skin:IsEnabled(), "master precedence")
NS.DB.enabled = true NS.Registry.NotifyListeners("adapter", "master")
nextFrame()
local priorSignal = settled
Check(skin:SkinBatch({ { kind = "slider", target = wrapper }, { kind = "dropdown", target = drop } })
    and skin:GetTargetStatus(wrapper) == "queued", "queued state")
nextFrame()
Check(skin:GetTargetStatus(wrapper) == "applied" and settled == priorSignal + 1, "one completion signal for both batch targets")
_G.combat = true Check(skin:Refresh(wrapper) and skin:GetTargetStatus(wrapper) == "deferred", "deferred state")
Check(skin:Release(wrapper), "deferred release")
Drain() Check(skin:GetTargetStatus(wrapper) == "released", "deferred release left a stale work item")
local invalid = Button(UIParent, "Frame")
Check(not skin:SkinCheckButton(invalid) and skin:GetTargetStatus(invalid) == "failed", "failed status")
Check(skin:Unregister() and skin:GetTargetStatus(tab) == "released", "registration release")
Check(#GeneratePopup() == 0 and nativeGenerations == 4, "unregister retained popup surface styling")
Acquire(radio, "split")
Check(row.fontString.color[1] == .15 and other:SkinMenuDescription(menuRoot), "unregister retained menu style ownership")
Acquire(radio, "split")
Check(row.fontString.color[1] == NS.Defaults.theme.colors.accentBright[1] and #radio.initializers == 1,
    "pooled description could not be styled by its new scope")
local releasedStyle = assert(other:CreateMenuMixin(nativeMixin))
Check(other:ReleaseAll(), "release all")
popupStyle = releasedStyle
Check(#GeneratePopup() == 0 and nativeGenerations == 5, "release all retained popup surface styling")
Acquire(radio, "split")
Check(row.fontString.color[1] == .15, "release all kept styling menu rows")
Check(#errors == 0, "runtime error")
print(("Cooperative API (%s): %d checks. No paint on 10,000 value changes, scrolls or status queries each."):format(flavor, checks))

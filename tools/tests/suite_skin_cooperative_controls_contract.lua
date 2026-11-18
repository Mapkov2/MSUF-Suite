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
local NS, Frame, frames, combatJobs, nextFrame, errors = assert(loadstring(fixture:sub(1, cut - 1)
    .. "\nreturn NS, Frame, createdFrames, combatJobs, NextFrame, reported"))()
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
local function Button(parent, kind)
    local button = Frame(nil, parent, kind or "Button")
    function button:HasScript() return true end
    function button:IsEnabled() return not self.disabled end
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
Load("Core/Cosmetics")
Load("Rendering/ScrollBarSkin")
NS.publicAPIMajor, NS.publicAPIMinor = 2, 4
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
for _, name in ipairs({ "Rendering/PublicWidgetParts", "Rendering/PublicWidgetSkin", "Rendering/PublicCaption",
    "Rendering/AddonWindowControls", "Core/PublicAPIControls", "Core/PublicAPI", "Core/PublicAPIMethods" }) do Load(name) end
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
drop.disabled = true Fire(drop, "OnDisable")
Check(selected == 1 and drop.Arrow.color[1] == NS.Defaults.theme.colors.disabled[1], "native dropdown input or disabled state")
Check(not other:Fade(drop.Arrow), "foreign scope acquired a dropdown part")
local r, w, a = reads, writes, attaches
for _ = 1, 10000 do assert(skin:GetTargetStatus(drop) == "applied") end
Check(reads == r and writes == w and attaches == a, "status queries caused rendering")
Check(skin:Release(drop) and not next(callbacks) and drop.Background.alpha == .75 and drop.Arrow.color[1] == .15, "dropdown release")

local check = Button(UIParent, "CheckButton")
check.checked, check.disabledChecked = Art(check, nil, 0), Art(check)
Check(skin:SkinCheckButton(check) and check.checked.color[4] == 0, "hidden radio/check indicator")
local old = check.checked
old.parent, check.checked = UIParent, Art(check)
Check(skin:Refresh(check) and other:Fade(old) and other:Release(old), "detached pooled indicator retained claims")
check.disabled = true Fire(check, "OnDisable")
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
Check(skin:Refresh(close) and close.normal.alpha == 0, "caption failed own claim on refresh")
local original = close.normal
close.normal = Art(close)
Check(skin:Refresh(close) and original.alpha == .75 and close.normal.alpha == 0, "pooled close art")
Fire(max, "OnClick")
Check(win.scale == 1.25 and points[1][3] == "CENTER", "fit bound")
Fire(max, "OnClick")
Check(win.scale == .9 and #points == 2 and points[1][4] == 20 and points[2][5] == 65, "exact two-anchor restore")
win.restricted = true Fire(max, "OnClick") win.restricted = false
_G.combat = true Fire(max, "OnClick") Fire(min, "OnClick")
Check(win.shown and win.scale == .9 and points[1][4] == 20, "combat or restricted geometry writes") Drain()
Fire(min, "OnClick") Check(not win.shown and restore.shown, "minimize")
Fire(restore, "OnClick") Check(win.shown and not restore.shown, "restore tab")
Fire(max, "OnClick") Fire(close, "OnClick")
Check(closeClicks == 1 and not win.shown and win.scale == .9, "normal close behavior")
win:Show()
NS.DB.windowControls.enabled = false NS.Registry.NotifyListeners("windowControls", "enabled")
Check(skin:GetTargetStatus(win) == "suspended" and not min.shown and close.normal.alpha == .75, "window controls toggle")
NS.DB.windowControls.enabled = true NS.Registry.NotifyListeners("windowControls", "enabled")
Check(skin:GetTargetStatus(win) == "applied" and min.shown and close.normal.alpha == 0, "window controls resume")
Check(skin:Release(win) and close.normal.alpha == .75 and not max.shown, "release sponsored close and controls")
Check(skin:SkinWindowAction(close, "close") and skin:RegisterWindow(win, windowOptions) and close.normal.alpha == 0,
    "registration did not adopt a previously skinned standalone close")
Check(skin:Release(win) and skin:GetTargetStatus(close) == "applied" and close.normal.alpha == .75,
    "releasing registration removed explicit action")
Check(not skin:SkinWindowAction(close, "close", { direction = "left" }), "invalid direction was accepted")
Check(not skin:SkinWindowAction(close, "expand", { appearance = "caption" }), "invalid caption role")
Check(not skin:RegisterWindow(Frame("CharacterFrame", UIParent), windowOptions), "native window accepted")
Check(not skin:RegisterWindow(Frame(nil, win), { minimize = true }), "nested window accepted")
win.restricted = true Check(not skin:RegisterWindow(win, { maximize = true }), "restricted anchors accepted") win.restricted = false

Check(api:HasCapability("menuStyleTokens") and api:HasCapability("targetStatus"), "2.4 capabilities")
local menu = assert(skin:GetMenuStyle())
menu.text[1] = 99
Check(skin:GetMenuStyle().text[1] ~= 99 and menu.font == "Fonts/test.ttf" and #menu.arrow == 4, "detached menu tokens")
local function Switch(on) NS.DB.addonSkins.registered = on NS.Registry.NotifyListeners("addonSkins", "registered") end
Switch(false)
Check(not skin:IsEnabled() and skin:GetTargetStatus(tab) == "suspended" and not skin:GetMenuStyle()
    and suite:IsEnabled() and host:IsEnabled() and api:IsEnabled(), "registered switch affected the wrong scope")
Switch(true)
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
Check(#errors == 0, "runtime error")
print(("Cooperative API (%s): %d checks. No paint on 10,000 value changes, scrolls or status queries each."):format(flavor, checks))

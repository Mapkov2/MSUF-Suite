-- Real Surface -> ControlSkin -> PublicAPI, driven with deterministic gestures.
-- These are artwork/lifecycle contracts, not a renderer or in-game taint test.
local root = assert(arg[1], "Suite root required")
local checks, textures, frames, foreignWrites, anchorWrites = 0, 0, 0, 0, 0
local function Check(value, message) assert(value, message); checks = checks + 1 end
local function Noop() end
wipe = function(values) for key in pairs(values) do values[key] = nil end end
local secret = {}
issecretvalue = function(value) return value == secret end
securecallfunction = function(callback, ...) return callback(...) end
local lockdown = false
InCombatLockdown = function() return lockdown end
Enum = { UITextureSliceMode = { Stretched = 1 } }
CreateColor = function(r, g, b, a) return { r = r, g = g, b = b, a = a } end
C_Timer = { After = function(_, callback) callback() end }

local function Texture()
    textures = textures + 1
    local region = { alpha = 1, shown = true, points = {}, color = { 1, 1, 1, 1 } }
    for _, method in ipairs({ "SetTexture", "SetGradient", "ClearTextureSlice", "SetTextureSliceMargins",
        "SetTextureSliceMode", "SetDrawLayer", "SetSnapToPixelGrid", "SetTexelSnappingBias", "SetTexCoord" }) do region[method] = Noop end
    function region:ClearAllPoints() for key in pairs(self.points) do self.points[key] = nil end end
    function region:SetPoint(point, relative, relativePoint, x, y)
        anchorWrites = anchorWrites + 1
        local old = self.points[point] or {}; self.points[point] = old
        old.relative, old.relativePoint, old.x, old.y = relative, relativePoint, x, y
    end
    function region:SetVertexColor(r, g, b, a)
        self.color[1], self.color[2], self.color[3], self.color[4] = r, g, b, a
    end
    function region:GetVertexColor() return unpack(self.color) end
    function region:SetAlpha(alpha) self.alpha = alpha end
    function region:GetAlpha() return self.alpha end
    function region:SetSize(width, height) self.width, self.height = width, height end
    function region:SetRotation(rotation) self.rotation = rotation end
    function region:Show() self.shown = true end
    function region:Hide() self.shown = false end
    function region:IsShown() return self.shown end
    return region
end

local created = {}
local function Target(kind, parent, x, y, width, height)
    local target = { kind = kind or "Frame", parent = parent, shown = true, enabled = true,
        x = x or 0, y = y or 0, width = width or 100, height = height or 24,
        scale = 1, scripts = {}, hooks = {}, events = {}, slots = {} }
    function target:IsForbidden() return self.forbidden == true end
    function target:IsProtected() return self.protected == true, self.explicit == true end
    function target:GetObjectType() return self.kind end
    function target:GetAlpha() return self.alpha or 0.4 end
    function target:CreateAnimationGroup()
        local group = { animations = {}, scripts = {} }
        function group:CreateAnimation(kind)
            local animation = { kind = kind, group = self }
            function animation:GetSmoothProgress() return self.group.progress or 0 end
            for _, key in ipairs({ "Duration", "Smoothing", "FromAlpha", "ToAlpha" }) do
                animation["Set" .. key] = function(self, value) self[key] = value end
            end
            self.animations[#self.animations + 1] = animation
            return animation
        end
        function group:Play() self.playing, self.plays = true, (self.plays or 0) + 1 end
        function group:Stop() self.playing = false end
        function group:IsPlaying() return self.playing == true end
        function group:SetScript(event, callback) self.scripts[event] = callback end
        return group
    end
    function target:GetParent() return self.parent end
    function target:GetRect() return self.x, self.y, self.width, self.height end
    function target:GetEffectiveScale() return self.scale end
    function target:IsVisible() return self.shown and (not self.parent or self.parent:IsVisible()) end
    function target:IsShown() return self.shown end
    function target:IsEnabled() return self.enabled end
    function target:SetEnabled(value)
        if issecretvalue(value) then
            assert(not (self.hooks.OnEnable or self.hooks.OnDisable), "secret enabled state met an add-on script")
        end
        self.enabled = value
    end
    function target:HasScript(event)
        return event == "OnShow" or event == "OnHide" or self.kind == "Button" or self.kind == "CheckButton"
            or self.kind == "EditBox"
    end
    function target:SetScript(event, callback) self.scripts[event] = callback end
    function target:GetScript(event) return self.scripts[event] end
    function target:HookScript(event, callback)
        local hooks = self.hooks[event] or {}; self.hooks[event] = hooks; hooks[#hooks + 1] = callback
    end
    function target:Fire(event, ...)
        if self.scripts[event] then self.scripts[event](self, ...) end
        for _, callback in ipairs(self.hooks[event] or {}) do callback(self, ...) end
    end
    function target:Hide() self.shown = false; self:Fire("OnHide") end
    function target:Show()
        local before = self.shown; self.shown = true
        if not before then self:Fire("OnShow") end
    end
    function target:RegisterEvent(event) self.events[event] = true end
    function target:UnregisterEvent(event) self.events[event] = nil end
    function target:CreateTexture() return Texture() end
    function target:SetPoint() foreignWrites = foreignWrites + 1 end
    function target:ClearAllPoints() foreignWrites = foreignWrites + 1 end
    for _, key in ipairs({ "Normal", "Highlight", "Pushed", "Disabled" }) do
        target["Get" .. key .. "Texture"] = function(self) return self.slots[key] end
        target["Set" .. key .. "Texture"] = function(self, texture) self.slots[key] = texture end
    end
    return target
end
UIParent = Target()
CreateFrame = function(kind)
    frames = frames + 1
    local frame = Target(kind)
    created[#created + 1] = frame
    return frame
end
local NS = { path = "", Client = { isForever = arg[2] == "Forever" },
    publicAPIMajor = 2, publicAPIMinor = 1, IsCombatLocked = InCombatLockdown,
    BlizzardYellow = { TrackFrame = Noop } }
local function Load(file)
    local override = os.getenv("SUITE_MOTION_OVERRIDE_ROOT")
    local path = root .. "/MSUF_Suite_Skin/" .. file
    if override then
        local candidate = override .. "/" .. file
        local handle = io.open(candidate, "rb")
        if handle then handle:close(); path = candidate end
    end
    assert(loadfile(path))("MSUF_Suite_Skin", NS)
end
Load("Core/Defaults.lua")
Load("Core/DefaultsLooks.lua")
NS.DB = NS.CopyValue(NS.Defaults)
-- This fixture tests global styles; the independent close-style contract covers its default.
NS.DB.icons.windowActions.closeStyle = "global"
for _, file in ipairs({ "Core/Safety.lua", "Core/Registry.lua", "Core/Theme.lua", "Rendering/Geometry.lua",
    "Rendering/Surface.lua", "Rendering/Motion.lua", "Rendering/SurfaceMotion.lua" }) do Load(file) end
NS.Checkmarks = { GetWindowAction = Noop, TrackButton = Noop, TrackDropdown = Noop,
    UntrackDropdown = Noop, UntrackOwner = Noop }
Load("Rendering/WindowActionSkin.lua")
Load("Rendering/GlyphMotion.lua")
Load("Rendering/WindowActionSettings.lua")
NS.ScrollBarSkin = { GetState = Noop }
NS.IconSkin = { GetOwner = Noop, Disable = Noop, DisableOwner = Noop }
NS.Cosmetics = { GetOwner = Noop, RestoreOwner = Noop }
NS.CombatGate = { Cancel = Noop }
Load("Rendering/ControlSkin.lua")
Load("Core/PublicAPIControls.lua")
Load("Core/PublicAPI.lua")
Load("Core/PublicAPIMethods.lua")
-- Runtime events start after ContentMotion, as in the complete native TOC.
Load("Rendering/ContentMotion.lua")
NS.PublicAPI.OnPlayerLogin()
local Surface, Motion = NS.Surface, NS.Motion
local clock = created[1]
local function Tick(count)
    for _ = 1, count or 20 do
        local callback = clock:GetScript("OnUpdate")
        if callback then callback(clock, 0.01) end
    end
end
local parent = Target("Frame", UIParent)
local button = Target("Button", parent)
local originalClick = function() end
button:SetScript("OnClick", originalClick)
local nativeHighlight = Texture()
button:SetHighlightTexture(nativeHighlight)
Check(NS.ControlSkin.ApplyButton(button, "native", { role = "button" }) ~= nil, "native button did not skin")
local state = NS.Registry.GetSurface(button)
Check(state.motion and clock:GetScript("OnUpdate") == nil, "new idle control installed a ticking driver")
do
    local toggle = Target("CheckButton", parent)
    function toggle:GetChecked() return self.checked end
    local surface = Surface.Attach(toggle, { role = "button" })
    Check(not surface.motion.channels, "cold surface allocated spring channels")
    toggle:Hide()
    toggle.checked = true
    toggle:Show()
    Check(surface.motion.checked == true and not surface.motion.channels and Motion.count == 0,
        "passive checkbox show missed its current value or allocated a spring")
    toggle.checked = false
    toggle:Fire("OnClick")
    Check(Motion.count == 1 and surface.fill:GetAlpha() < 1, "first actual checkbox change lost its reveal")
    Tick()
end
do
    local overlay = state.hoverOverlay
    local colorWrites, visibilityWrites = 0, 0
    local color, show, hide = overlay.SetVertexColor, overlay.Show, overlay.Hide
    function overlay:SetVertexColor(...) colorWrites = colorWrites + 1 color(self, ...) end
    function overlay:Show() visibilityWrites = visibilityWrites + 1 show(self) end
    function overlay:Hide() visibilityWrites = visibilityWrites + 1 hide(self) end
    for _ = 1, 100 do
        button:Fire("OnMouseDown")
        Tick()
        button:Fire("OnMouseUp")
        Tick()
    end
    Check(colorWrites == 0 and visibilityWrites == 0,
        ("unchanged press hover used %d tint and %d visibility writes"):format(colorWrites, visibilityWrites))
    button:Fire("OnEnter")
    Tick()
    Check(colorWrites > 1 and visibilityWrites < colorWrites and overlay:IsShown(),
        "hover interpolation lost color steps or repeated its visibility write on each step")
    overlay:Hide()
    overlay:SetVertexColor(0, 0, 0, 0)
    Surface.Refresh(button)
    Check(overlay:IsShown() and overlay.color[1] == state.motion.hoverR and overlay.color[4] == state.motion.hoverAlpha,
        "full refresh failed to restore hover after another paint")
    button:Fire("OnLeave")
    Tick()
    overlay.SetVertexColor, overlay.Show, overlay.Hide = color, show, hide
end
do
    local control = Target("Button", parent)
    local surface = Surface.Attach(control, { role = "navigation" })
    control:Fire("OnEnter")
    Tick()
    control:Fire("OnLeave")
    Check(surface.hoverOverlay:IsShown(), "static leave hook hid the animated fade-out")
    Tick()
    surface.hoverOverlay:Show()
    control:Hide()
    Check(not surface.hoverOverlay:IsShown(), "hiding the control missed a previously shown overlay")
end
button:Fire("OnEnter")
Check(Motion.count == 1 and state.motion.channels[5].target == 1, "hover did not start owned artwork")
Tick(4)
local before = select(4, state.hoverOverlay:GetVertexColor())
Check(before > 0 and before < 1, "hover did not interpolate")
button:Fire("OnLeave")
Check(state.motion.channels[5].value > 0, "hover leave snapped to zero")
Tick()
Check(Motion.count == 0 and not state.hoverOverlay:IsShown() and clock:GetScript("OnUpdate") == nil,
    "hover leave retained a driver or visible overlay")
button:Fire("OnMouseDown")
Tick(4)
Check(state.fill.points.BOTTOMLEFT.x > 0, "press did not move its owned surface")
button:Fire("OnMouseUp")
Tick()
Check(state.fill.points.BOTTOMLEFT.x == 0 and foreignWrites == 0 and button.scripts.OnClick == originalClick,
    "press changed a native frame or failed to settle")
button:Fire("OnClick"); Tick(4)
Check(state.fill.points.BOTTOMLEFT.x > 0, "keyboard/controller click had no feedback")
Tick()
local savedTextures, savedFrames = textures, frames
for _ = 1, 100 do
    button:Fire("OnEnter"); button:Fire("OnMouseDown"); button:Fire("OnMouseUp"); button:Fire("OnLeave"); Tick()
end
Check(savedTextures == textures and savedFrames == frames, "repeat gestures allocated more native artwork/drivers")
button:Fire("OnEnter"); Tick(3)
Check(NS.ControlSkin.Disable(button), "disable failed")
Check(Motion.count == 0 and not state.hoverOverlay:IsShown(), "skin disable did not cancel motion")
Check(button:GetHighlightTexture() == nativeHighlight, "disable lost native highlight ownership")
Check(NS.ControlSkin.Enable(button), "re-enable failed")
button:SetEnabled(false)
button:Fire("OnEnter")
Check(Motion.count == 0, "disabled tooltip hover restarted motion")
-- The gesture entry refuses a disabled control itself, before the per-frame
-- safety pass (a second, independent enabled read) is asked about it.
local coldDisabled = Target("Button", parent)
Surface.Attach(coldDisabled, { role = "button" })
coldDisabled:SetEnabled(false)
local entryPasses, entryVisible = 0, coldDisabled.IsVisible
function coldDisabled:IsVisible()
    entryPasses = entryPasses + 1
    return entryVisible(self)
end
coldDisabled:Fire("OnEnter")
Check(Motion.count == 0 and entryPasses == 0,
    "disabled tooltip hover restarted motion or reached the animation safety pass")
coldDisabled.IsVisible = entryVisible
button:SetEnabled(true)
button:Fire("OnMouseDown")
Tick(2)
Check(NS.Theme.SetAppearance("readableValues", true) and Motion.count > 0,
    "readability interrupted an active button animation")
button:SetEnabled(secret)
Tick()
Check(Motion.count == 0 and state.fill.points.BOTTOMLEFT.x == 0, "secret disabled state retained a pressed surface")
button:SetEnabled(true)
button:Fire("OnEnter"); Tick(2); button:Hide()
Check(Motion.count == 0 and not state.hoverOverlay:IsShown(), "OnHide did not cancel motion")
button:Show()
-- Opacity and hover-off must survive animated and static paths.
NS.DB.theme.hoverIntensity = 0.2
Surface.Refresh(button)
button:Fire("OnEnter"); Tick()
Check(math.abs(select(4, state.hoverOverlay:GetVertexColor()) - state.motion.hoverAlpha) < 0.000001,
    "hover changed configured opacity")
NS.DB.theme.hoverStyle = "off"
Surface.Refresh(button)
button:Fire("OnEnter"); Tick()
Check(not state.hoverOverlay:IsShown(), "hover-off animated a visible overlay")
NS.DB.theme.hoverStyle = "outline"
local standalone = Target("Button", parent)
Surface.Attach(standalone, { role = "button", interactive = true })
NS.DB.theme.controlOpacity = 0.4
Check(NS.Theme.SetAppearance("menuAnimations", false), "animation switch rejected false")
button:Fire("OnEnter")
Check(Motion.count == 0 and state.highlight:GetAlpha() > 0, "off did not restore native static hover")
standalone:Fire("OnEnter")
Check(NS.Registry.GetSurface(standalone).hoverOverlay:IsShown()
    and select(4, NS.Registry.GetSurface(standalone).hoverOverlay:GetVertexColor()) > 0,
    "turning off motion erased ordinary standalone hover")
local r, g, b, alpha = NS.Theme.GetColor("buttonFill")
Check(math.abs(select(4, state.fill:GetVertexColor()) * state.fill:GetAlpha() - alpha * 0.4) < 0.000001, "motion cleanup overwrote new material opacity")
Check(NS.Theme.SetAppearance("menuAnimations", true), "animation switch failed")
Check(NS.Theme.SetAppearance("windowFocusDimming", false) and NS.DB.theme.windowFocusDimming == false
    and NS.DB.theme.dropdownDimming == nil, "window dimming setting is missing or changed dropdown dimming")
Check(NS.Theme.SetAppearance("windowFocusDimming", true) and NS.DB.theme.windowFocusDimming == true,
    "window dimming cannot be enabled again")
Check(NS.Theme.SetAppearance("reduceMotion", true), "reduced motion failed")
button:Fire("OnMouseDown")
Check(Motion.count == 0, "reduced motion started a driver")
Check(NS.Theme.SetAppearance("reduceMotion", false), "reduced motion could not be disabled")
-- Selection uses same-parent navigation only, preserving native coordinates.
button:Fire("OnEnter")
Tick(3)
Surface.Refresh(button)
button:Fire("OnLeave")
Tick()
Check(state.highlight:GetAlpha() == 1, "material repaint lost static highlight opacity")
local a, b = Target("Button", parent, 10, 10), Target("Button", parent, 120, 10, 120, 24)
local nav = { role = "navigation", activeRole = "navigationActive" }
Surface.SkinOwnedButton(a, nav, true)
Surface.SkinOwnedButton(b, nav, false)
Surface.SetActive(a, false)
Surface.SetActive(b, true)
local selected = NS.Registry.GetSurface(b)
Check(selected.motion.channels[1].value == -110 and Motion.count > 0, "selection did not travel from its previous tab")
Tick()
Check(selected.fill.points.BOTTOMLEFT.x == 0 and selected.motion.channels[1].value == 0,
    "selection did not end at native coordinates")
Surface.SetActive(a, true)
Check(Motion.count == 0, "multiple active tabs were treated as one selection")
Surface.SetActive(b, false); Surface.SetActive(a, false); Surface.SetActive(b, true); Tick()
Surface.SetActive(a, true)
Check(Motion.count == 0, "new-before-old selection moved before native deselection")
Surface.SetActive(b, false)
Check(Motion.count > 0 and NS.Registry.GetSurface(a).motion.channels[1].value == 110,
    "new-before-old selection skipped travel")
Tick()
Surface.SetActive(a, false); Surface.SetActive(b, true); Tick(3)
local movingX = b.x + selected.motion.channels[1].value
local c = Target("Button", parent, 250, 10)
Surface.SkinOwnedButton(c, nav, false)
Surface.SetActive(b, false); Surface.SetActive(c, true)
Check(math.abs(NS.Registry.GetSurface(c).motion.channels[1].value - (movingX - c.x)) < 0.000001,
    "rapid selection jumped to the prior tab's final position")
Check(selected.motion.channels[1].value == 0, "deselected material continued travelling")
Tick()
Surface.SetActive(c, false); Surface.SetActive(b, true); Tick()
Surface.SetActive(a, false); b.x = secret
Surface.SetActive(b, false); Surface.SetActive(a, true)
Check(Motion.count == 0, "secret geometry reached selection arithmetic")
b.x = 120
local poolParent = Target("Frame", UIParent)
local pooled, fresh = Target("Button", poolParent), Target("Button", poolParent, 200, 0)
local poolSpec = { role = "navigation", activeRole = "navigationActive", motionGroup = "pooled" }
Surface.SkinOwnedButton(pooled, poolSpec, true); Surface.SkinOwnedButton(fresh, poolSpec, false)
Surface.SetActive(pooled, false)
pooled.parent = parent
Surface.SetActive(fresh, true)
Check(Motion.count == 0, "a reparented pooled row carried selection across unrelated windows")
-- Focus and structural opening animate only owned art.
local edit = Target("EditBox", parent)
NS.ControlSkin.ApplySearchBox(edit, "search", { role = "input" })
edit:Fire("OnEditFocusGained"); Tick()
Check(NS.Registry.GetSurface(edit).hoverOverlay:IsShown(), "search focus had no animated cue")
edit:Fire("OnEditFocusLost"); Tick()
Check(not NS.Registry.GetSurface(edit).hoverOverlay:IsShown(), "search blur retained focus cue")
local checkbox = Target("CheckButton", parent)
checkbox.checked = false
function checkbox:GetChecked() return self.checked end
Surface.Attach(checkbox, { role = "button" })
checkbox.checked = true; checkbox:Fire("OnClick")
Check(Motion.count > 0 and NS.Registry.GetSurface(checkbox).fill:GetAlpha() < 1,
    "checked-state transition had no feedback")
Tick()
local repaintWindow = Target("Frame", UIParent)
local repaintState = Surface.Attach(repaintWindow, { role = "shell", motion = true })
Check(repaintState.fill:GetAlpha() == 1, "late visible-window adoption restarted a fade without OnShow")
repaintWindow:Hide()
repaintWindow:Show()
Tick(3)
local revealAlpha = repaintState.fill:GetAlpha()
Surface.Refresh(repaintWindow)
Check(math.abs(repaintState.fill:GetAlpha() - revealAlpha) < 0.000001, "material repaint compounded reveal opacity")
Tick()
Check(repaintState.fill:GetAlpha() == 1, "reveal did not settle to full region alpha")

local window = Target("Frame", UIParent)
Surface.Attach(window, { role = "shell" })
window:Hide(); window:Show()
Check(Motion.count > 0 and NS.Registry.GetSurface(window).fill:GetAlpha() == 0,
    "window opening did not reveal the owned skin")
Tick()
Check(window:IsShown() and foreignWrites == 0, "window opening touched native visibility/geometry")
window:Hide()
Check(Motion.count == 0, "window close was delayed")
-- An opening window asks each safety question once per animated frame and
-- again on the next frame. The 2026-11-16 Ironforge trace spent 4.56 ms of
-- Step's 11.79 ms there: IsForbidden ran twice per window frame (three times
-- for a control). Accepted trade: none; every answer is still read per frame.
do
    local probe = Target("Frame", UIParent)
    probe.IsEnabled = nil -- A native Frame or GameTooltip has no IsEnabled.
    local probeState = Surface.Attach(probe, { role = "popup" })
    local calls, natives = {}, {}
    for _, name in ipairs({ "IsForbidden", "IsProtected", "IsVisible" }) do
        local native = probe[name]
        calls[name], natives[name] = 0, native
        probe[name] = function(self, ...)
            calls[name] = calls[name] + 1
            return native(self, ...)
        end
    end
    local function Open(frames)
        probe:Hide(); probe:Show()
        Check(Motion.count == 1, "safety probe window did not start its opening")
        for name in pairs(calls) do calls[name] = 0 end
        Tick(frames)
    end
    local function Rested(message)
        Check(Motion.count == 0 and clock:GetScript("OnUpdate") == nil, message .. " kept the driver")
        Check(probeState.fill.points.BOTTOMLEFT.y == 0 and probeState.fill:GetAlpha() == 1,
            message .. " left transformed artwork")
    end
    Open(3)
    Check(Motion.count == 1 and probeState.fill.points.BOTTOMLEFT.y < 0, "opening window did not travel")
    Check(calls.IsForbidden == 3 and calls.IsProtected == 3 and calls.IsVisible == 3,
        "single object safety pass budget exceeded or a per-frame read was skipped: " .. calls.IsForbidden .. "/"
        .. calls.IsProtected .. "/" .. calls.IsVisible)
    probe.protected = true
    Tick(1)
    Rested("a window protected during its opening")
    probe.protected = false
    Open(2)
    function probe:IsVisible() return secret end
    Tick(1)
    Rested("a secret visibility answer")
    function probe:IsVisible() return natives.IsVisible(self) end
    Open(2)
    probe.IsVisible = nil
    Tick(1)
    Rested("a window without a visibility getter")
    function probe:IsVisible() return natives.IsVisible(self) end
    Open(2)
    function probe:IsProtected() return secret, false end
    Tick(1)
    Rested("a secret protection answer")
    function probe:IsProtected() return natives.IsProtected(self) end
    Open(2)
    probe.AttachTexture, probe.AttachFontString, probe.AttachFrame, probe.AttachTemplate = Noop, Noop, Noop, Noop
    Tick(1)
    Rested("a window that became compositor managed")
    probe.AttachTexture, probe.AttachFontString, probe.AttachFrame, probe.AttachTemplate = nil, nil, nil, nil
    -- A forbidden object rejects every member but IsForbidden.
    Open(2)
    local members = {}
    for key, value in pairs(probe) do
        if key ~= "IsForbidden" then members[key], probe[key] = value, nil end
    end
    setmetatable(probe, { __index = function(_, key)
        if key ~= "forbidden" then error("forbidden window member was read: " .. tostring(key)) end
        return true
    end })
    Tick(1)
    Check(Motion.count == 0 and clock:GetScript("OnUpdate") == nil, "a forbidden window kept the driver")
    setmetatable(probe, nil)
    for key, value in pairs(members) do probe[key] = value end
    probe.forbidden = nil
    probe:Hide()
    -- A control keeps its fresh enabled read on every frame.
    local enabledReads, isEnabled = 0, button.IsEnabled
    function button:IsEnabled()
        enabledReads = enabledReads + 1
        return isEnabled(self)
    end
    -- A retarget joins the running driver; a settled one detaches it again.
    local attached, setScript = 0, clock.SetScript
    function clock:SetScript(event, callback)
        if event == "OnUpdate" and callback then attached = attached + 1 end
        setScript(self, event, callback)
    end
    button:Fire("OnEnter")
    Check(Motion.count == 1 and attached == 1, "hover did not attach the driver once")
    enabledReads = 0
    Tick(2)
    Check(enabledReads == 2, "animated control frame skipped or repeated its enabled read")
    button:Fire("OnMouseDown"); Tick(1); button:Fire("OnMouseUp")
    Check(Motion.count == 1 and attached == 1 and clock:GetScript("OnUpdate") ~= nil,
        "retarget during a running gesture attached the driver again")
    button:Fire("OnLeave"); Tick()
    Check(Motion.count == 0 and clock:GetScript("OnUpdate") == nil, "retargeted gesture retained the driver")
    button:Fire("OnEnter")
    Check(Motion.count == 1 and attached == 2 and clock:GetScript("OnUpdate") ~= nil,
        "a gesture after rest did not attach the driver")
    button:Fire("OnLeave"); Tick()
    clock.SetScript, button.IsEnabled = setScript, isEnabled
end
-- A native callback can stop a gesture during its first paint.
do
    local record = Motion.New({}, Motion.Clear, function() return true end, Noop)
    Motion.Set(record, 7, 0)
    Motion.Play(record)
    Check(Motion.count == 0 and clock:GetScript("OnUpdate") == nil,
        "a gesture that stopped during paint started an empty driver")
end

-- Forever's SmartNavigation reads GetScript("OnMouseUp"/"OnMouseDown") of every
-- frame it scans that is not a Button or EditBox (Blizzard_GamepadSmartNavigation/
-- Utility.lua:196-206): a skin hook there taints that secure scan. A plain Frame
-- has these scripts in the client, so shells and popups must not hook them.
local frameScripts = { OnShow = true, OnHide = true, OnEnter = true, OnLeave = true,
    OnMouseDown = true, OnMouseUp = true, OnMouseWheel = true }
for _, role in ipairs({ "shell", "popup" }) do
    local panel = Target("Frame", UIParent)
    function panel:HasScript(event) return frameScripts[event] == true end
    function panel:IsMouseMotionEnabled() return true end
    Surface.Attach(panel, { role = role })
    Check(NS.Registry.GetSurface(panel).motion and panel.hooks.OnShow and panel.hooks.OnEnter,
        role .. " frame lost its opening or hover motion")
    Check(not panel.hooks.OnMouseDown and not panel.hooks.OnMouseUp,
        role .. " frame got a press hook Forever's SmartNavigation reads")
end
Check(button.hooks.OnMouseDown and button.hooks.OnMouseUp and checkbox.hooks.OnMouseDown
    and edit.hooks.OnMouseDown, "skinned buttons and inputs lost their press feedback")
-- Tooltip and passive shell adoption must not create a new mouse target.
-- HasScript reports supported handlers, not whether native mouse input is on.
-- Model the client enabling input when a mouse script is first attached.
for _, kind in ipairs({ "GameTooltip", "Frame" }) do
    for _, role in ipairs({ "popup", "shell" }) do
        local tip = Target(kind, UIParent)
        local nativeHook = tip.HookScript
        tip.mouseMotion, tip.mouseClick = false, false
        function tip:HasScript(event) return frameScripts[event] == true end
        function tip:IsMouseMotionEnabled() return self.mouseMotion end
        function tip:HookScript(event, callback)
            if event == "OnEnter" or event == "OnLeave" then self.mouseMotion = true end
            if event == "OnMouseDown" or event == "OnMouseUp" then self.mouseClick = true end
            nativeHook(self, event, callback)
        end
        local tipState = Surface.Attach(tip, { role = role })
        Check(tipState and tipState.motion and tip.hooks.OnShow and tip.hooks.OnHide,
            "passive tooltip lost its skin or opening animation")
        Check(not tip.mouseMotion and not tip.mouseClick and not tip.hooks.OnEnter and not tip.hooks.OnLeave,
            "passive tooltip became a mouse target")
        tip:Hide(); tip:Show()
        Tick()
        Surface.Refresh(tip)
        Check(not tip.mouseMotion and not tip.mouseClick and tipState.fill:GetAlpha() == 1,
            "tooltip repaint or opening changed mouse input")
        NS.DB.theme.menuAnimations = false
        Surface.Refresh(tip)
        NS.DB.theme.menuAnimations = true
        Surface.Refresh(tip)
        Check(not tip.mouseMotion and not tip.mouseClick, "motion toggle changed tooltip mouse input")
        tip:Hide()
        Check(Motion.count == 0, "tooltip hide retained an animation driver")
    end
end
-- Secret or unavailable native input state cannot opt a passive frame in.
for _, motionState in ipairs({ secret, "missing" }) do
    local tip = Target("GameTooltip", UIParent)
    function tip:HasScript(event) return frameScripts[event] == true end
    if motionState ~= "missing" then function tip:IsMouseMotionEnabled() return motionState end end
    Surface.Attach(tip, { role = "popup" })
    Check(not tip.hooks.OnEnter and not tip.hooks.OnLeave, "unreadable tooltip input state gained hover hooks")
end
-- Combat changes protection, not the configured visual policy.
button:Fire("OnEnter"); Tick(3)
button:Fire("OnMouseDown"); Tick(1)
clock:Fire("OnEvent", "PLAYER_REGEN_DISABLED")
Check(not lockdown and Motion.count > 0 and state.motion.channels[6].target == 1,
    "combat edge stopped safe active transitions")
Surface.Refresh(button)
button:Fire("OnMouseUp")
Check(Motion.count > 0, "combat refresh disabled safe gestures")
lockdown = true
local combatButton = Target("Button", parent)
Surface.Attach(combatButton, { role = "button" })
combatButton:Fire("OnEnter")
Check(NS.Registry.GetSurface(combatButton).motion.index ~= nil, "cold combat control lost its animation")
combatButton:Hide()
button:Fire("OnLeave"); Tick()
Check(Motion.count == 0 and clock:GetScript("OnUpdate") == nil, "combat gestures retained an idle driver")
lockdown = false
clock:Fire("OnEvent", "PLAYER_REGEN_ENABLED")
button:Fire("OnMouseDown"); Tick()
button.protected = true
clock:Fire("OnEvent", "PLAYER_REGEN_DISABLED")
Check(state.motion.channels[6].value == 0, "combat left an idle pressed control stuck")
clock:Fire("OnEvent", "PLAYER_REGEN_ENABLED")
button.protected = false
button:Fire("OnEnter")
Check(Motion.count > 0, "combat-edge refresh permanently disabled a visible control")
button:Fire("OnLeave"); Tick()
button.protected = true
button:Fire("OnEnter")
Check(Motion.count == 0, "a newly protected target animated")
button.protected = false
button:Fire("OnMouseDown"); Tick(3)
button.protected = true; lockdown = true
clock:Fire("OnEvent", "PLAYER_REGEN_DISABLED")
lockdown = false
clock:Fire("OnEvent", "PLAYER_REGEN_ENABLED")
button.protected = false
Check(state.fill.points.BOTTOMLEFT.x == 0 and next(Motion.deferred) == nil,
    "a newly protected target retained transformed artwork after combat")
local geometryBefore = anchorWrites
for _ = 1, 50 do Surface.Refresh(button) end
Check(anchorWrites == geometryBefore, "idle refresh added native geometry writes")
-- Public addon scopes adopt the same motion, clean up on suspend/release,
-- preserve explicit false, and do not double-animate owned MSUF artwork.
local api = NS.PublicAPI.API
local client = assert(api:RegisterAddon("MotionContract"))
do
    local character = assert(api:RegisterAddon("MSUF_Suite_characterPanel"))
    local tabBar = Target("Frame", parent)
    local overview = Target("Button", tabBar, 10, 0, 88, 32)
    local equipment = Target("Button", tabBar, 98, 0, 105, 32)
    local reputation = Target("Button", tabBar, 203, 0, 130, 32)
    local external = Target("Button", tabBar)
    local spec = { role = "navigation", activeRole = "navigationActive", ownedArt = true, motion = true }
    local pending = {}
    NS.CombatGate.RunOrDefer = function(key, callback) pending[key] = callback end
    lockdown = true
    clock:Fire("OnEvent", "PLAYER_REGEN_DISABLED")
    local applied, reason = character:SkinFrame(overview, spec)
    Check(applied and reason == "applied", "first combat opening deferred the owned navigation art")
    Check(character:SkinFrame(equipment, spec) and character:SkinFrame(reputation, spec), "combat tabs could not attach")
    Check(character:SetActive(overview, true), "cold combat selection did not paint")
    local _, refreshReason = character:RefreshAll()
    Check(refreshReason == "deferred", "combat tab exception changed full-scope refresh policy")
    local _, externalReason = client:SkinFrame(external, spec)
    Check(externalReason == "deferred" and not NS.Registry.GetSurface(external), "foreign navigation bypassed the combat gate")
    local beforeTextures, attachments, attach = textures, 0, Surface.Attach
    Surface.Attach = function(...)
        attachments = attachments + 1
        return attach(...)
    end
    Check(character:SetActive(overview, false) and character:SetActive(equipment, true), "combat selection refused")
    Surface.Attach = attach
    local selected = NS.Registry.GetSurface(equipment)
    local channels = selected.motion.channels
    Check(channels and channels[1].value == -88 and channels[3].value == -17
        and Motion.count > 0 and textures == beforeTextures, "combat selection did not slide and resize from the previous tab")
    Check(attachments == 0, "warm combat selection reattached the tab skins")
    Tick(3)
    local fromX = equipment.x + selected.motion.channels[1].value
    character:SetActive(equipment, false)
    character:SetActive(reputation, true)
    local current = NS.Registry.GetSurface(reputation)
    Check(math.abs(current.motion.channels[1].value - (fromX - reputation.x)) < .000001,
        "combat retarget snapped to the old tab's final position")
    Tick()
    Check(current.active and current.motion.channels[1].value == 0 and not clock:GetScript("OnUpdate"),
        "combat tab motion failed to settle or kept the shared driver running")
    reputation.protected = true
    local beforeProtected = anchorWrites
    local _, protectedReason = character:SetActive(reputation, false)
    Check(protectedReason == "deferred" and anchorWrites == beforeProtected, "combat tab paint bypassed fresh protection")
    reputation.protected = false
    NS.DB.theme.reduceMotion = true
    character:SetActive(reputation, false)
    character:SetActive(overview, true)
    Check(NS.Registry.GetSurface(overview).active and Motion.count == 0, "reduced motion did not snap the combat selector")
    NS.DB.theme.reduceMotion = false
    lockdown = false
    clock:Fire("OnEvent", "PLAYER_REGEN_ENABLED")
    for _, callback in pairs(pending) do callback() end
    NS.CombatGate.RunOrDefer = nil
    character:ReleaseAll()
    client:Release(external)
end
local owned = Target("Button", parent)
Check(client:SkinButton(owned, { ownedArt = true, motion = true }), "public motion opt-in failed")
owned:Fire("OnEnter")
Check(Motion.count > 0, "public owned control did not animate")
NS.DB.enabled = false
Check(NS.PublicAPI.RefreshAll(), "public scope suspend failed")
Check(Motion.count == 0, "public suspend retained motion")
NS.DB.enabled = true
Check(NS.PublicAPI.RefreshAll(), "public scope resume failed")
owned:Fire("OnEnter")
Check(client:Release(owned), "public release failed")
Check(Motion.count == 0, "public release retained motion")
local host = assert(api:RegisterAddon("MidnightSimpleUnitFrames"))
local hostButton = Target("Button", parent)
Check(host:SkinButton(hostButton, { ownedArt = true }), "host control did not skin")
Check(not NS.Registry.GetSurface(hostButton).motion, "host artwork received duplicate motion")
local hostWindow = Target("Frame", UIParent)
Check(host:SkinFrame(hostWindow, { role = "shell" }), "host window did not skin")
Check(not NS.Registry.GetSurface(hostWindow).motion, "host shell received duplicate open motion")
local hostAction = Target("Button", parent)
Check(host:SkinWindowAction(hostAction, "close"), "host window action did not skin")
Check(not NS.GlyphMotion.records[hostAction], "host window action received duplicate motion")
for _, style in ipairs({ "soft", "outline" }) do
    NS.DB.icons.windowActions.style = style
    local hostStyled = Target("Button", parent)
    Check(host:SkinWindowAction(hostStyled, "close"), "host styled action did not skin")
    local hostPlate = NS.Registry.GetSurface(hostStyled)
    Check(hostPlate and not hostPlate.motion, "host styled action plate received duplicate motion")
    local external = Target("Button", parent)
    Check(client:SkinWindowAction(external, "close", { motion = false }), "external action opt-out failed")
    Check(client:SkinWindowAction(external, "close"), "external action default failed")
    Check(NS.Registry.GetSurface(external).motion and hostPlate.spec.motion == false,
        "action motion policy leaked across controls or retained a stale override")
    client:Release(external)
end
NS.DB.icons.windowActions.style = "bare"
local optedOut = Target("Button", parent)
Check(host:SkinButton(optedOut, { motion = false }), "explicit motion=false did not skin")
Check(not NS.Registry.GetSurface(optedOut).motion, "public sanitizer lost explicit motion=false")
-- Bare window actions have no plate; their owned glyphs still animate.
local disclosure = Target("Button", parent)
NS.DB.icons.windowActions.glyphMode = "chevrons"
local action = assert(NS.WindowActionSkin.Apply(disclosure, "disclosure", "expand"))
NS.WindowActionSkin.Apply(disclosure, "disclosure", "collapse")
Check(Motion.count > 0 and action.glyphs.normal.rotation == math.pi, "disclosure did not animate its owned glyph")
Tick()
Check(action.glyphs.normal.rotation == 0 and action.glyphs.normal.width == 12, "disclosure did not settle")
disclosure:Fire("OnMouseDown"); Tick(4)
Check(action.glyphs.normal.width < 12, "bare action click had no motion")
disclosure:SetEnabled(secret)
Tick()
Check(action.glyphs.normal.width == 12 and Motion.count == 0, "secret disabled state retained a pressed glyph")
NS.WindowActionSkin.Disable(disclosure, "disclosure")
Check(action.glyphs.normal.width == 12 and Motion.count == 0, "glyph release left a transformed native slot")
Check(foreignWrites == 0 and clock:GetScript("OnUpdate") == nil, "finished world retained foreign writes/idle motion")
-- Page and completed-search fades run once per content token.
local page = Target("Frame", parent)
Check(client:AnimateContent(page, 1), "page content was not adopted")
local content = NS.ContentMotion.records[page]
Check(content.alpha.FromAlpha == 0 and content.alpha.ToAlpha == 0.4 and content.alpha.Duration == 0.12,
    "content fade changed native opacity or duration")
client:AnimateContent(page, 1)
Check(content.group.plays == 1, "duplicate completed paint restarted fade")
client:AnimateContent(page, false)
Check(not content.group:IsPlaying(), "pending results kept fading")
Check(client:AnimateContent(page, 2) and content.group.plays == 2, "completed results did not fade")
Check(client:Release(page) and not content.group:IsPlaying(), "content-only target release was asymmetric")
Check(client:AnimateContent(page, 3), "released content could not be reacquired")
client:ReleaseAll()
Check(not content.group:IsPlaying(), "ReleaseAll retained content")
client:AnimateContent(page, 4)
page:Hide()
Check(not content.group:IsPlaying(), "hidden page kept fading")
page:Show()
NS.DB.enabled = false
Check(not client:AnimateContent(page, 5), "disabled skin animated page content")
NS.DB.enabled = true
page.alpha = secret
Check(not client:AnimateContent(page, 5), "secret page alpha reached animation arithmetic")
page.alpha = 0.4
page.protected = true
Check(not client:AnimateContent(page, 5), "protected page accepted content animation")
page.protected = false
local proxy = Target("Frame", parent)
proxy.AttachTexture, proxy.AttachFontString, proxy.AttachFrame, proxy.AttachTemplate = Noop, Noop, Noop, Noop
Check(not client:AnimateContent(proxy, 1), "compositor proxy accepted content animation")

-- ESC/native opening has one alpha owner, independent of hook registration order.
local openingOwner = {}
for _, contentFirst in ipairs({ false, true }) do
    local opening = Target("Frame", UIParent)
    if contentFirst then NS.ContentMotion.Watch(opening, openingOwner) end
    local openingState = Surface.Attach(opening, { role = "shell" })
    if not contentFirst then NS.ContentMotion.Watch(opening, openingOwner) end
    opening:Hide()
    opening:Show()
    local openingFade = NS.ContentMotion.records[opening]
    Check(openingFade and openingFade.group:IsPlaying(), "native opening lost its complete-menu fade")
    Check(openingState.motion.channels[7].value == 1 and openingState.fill:GetAlpha() == 1,
        "native opening multiplied root and surface alpha fades")
    local fromWrites, toWrites, playingReads = 0, 0, 0
    local animation, group = openingFade.alpha, openingFade.group
    local setFrom, setTo, isPlaying = animation.SetFromAlpha, animation.SetToAlpha, group.IsPlaying
    function animation:SetFromAlpha(value)
        fromWrites = fromWrites + 1
        setFrom(self, value)
    end
    function animation:SetToAlpha(value)
        toWrites = toWrites + 1
        setTo(self, value)
    end
    function group:IsPlaying()
        playingReads = playingReads + 1
        return isPlaying(self)
    end
    opening:Hide()
    opening:Show()
    Check(fromWrites == 0 and toWrites == 0 and playingReads == 0,
        "reopening with the same alpha reconfigured the animation")
    Check(group.plays == 2 and isPlaying(group), "unchanged endpoints skipped the native opening fade")
    opening:Hide()
    opening.alpha = 0.75
    opening:Show()
    Check(fromWrites == 0 and toWrites == 1 and animation.ToAlpha == 0.75,
        "native alpha change did not refresh exactly the changed endpoint")
    opening:Hide()
end
NS.ContentMotion.UnwatchOwner(openingOwner)

local function HoldNextFrame()
    local earlier, pending = C_Timer.After, {}
    C_Timer.After = function(delay, callback)
        Check(delay == 0, "mail work was not scheduled for the next frame")
        pending[#pending + 1] = callback
    end
    return pending, function()
        C_Timer.After = earlier
        for _, callback in ipairs(pending) do callback() end
    end
end

-- Native mailbox opening still has to run Blizzard's protected reading emote
-- after OnShow. Exercise already-installed motion hooks in both bind orders.
do
    local previousMailbox = MailFrame
    for _, contentFirst in ipairs({ false, true }) do
        local mailbox = Target("Frame", UIParent)
        MailFrame = mailbox
        if contentFirst then NS.ContentMotion.Watch(mailbox, openingOwner) end
        local skin = Surface.Attach(mailbox, { role = "shell" })
        if not contentFirst then NS.ContentMotion.Watch(mailbox, openingOwner) end
        mailbox:Hide()
        mailbox:Show()
        local fade = assert(NS.ContentMotion.records[mailbox], "warm mailbox never acquired its native fade")
        local plays = fade.group.plays
        mailbox:Hide()
        local pending, flush = HoldNextFrame()
        mailbox:Show()
        if NS.Client.isForever then
            Check(fade.group.plays == plays, "mailbox content faded inside the native opening")
            Check(not skin.motion.index and skin.fill.points.BOTTOMLEFT.y == 0,
                "mailbox shell painted inside the native opening")
            mailbox:Hide()
            Check(#pending == 1, "mailbox motion did not share one next-frame flush")
            flush()
            Check(fade.group.plays == plays and not skin.motion.index, "closed mailbox played a queued opening")

            pending, flush = HoldNextFrame()
            mailbox:Show()
            mailbox:Hide()
            mailbox:Show()
            Check(fade.group.plays == plays and #pending == 1, "rapid mailbox opens did not coalesce")
            flush()
        else
            Check(fade.group.plays == plays + 1 and skin.motion.index and #pending == 0,
                "Retail mailbox motion did not start inside its ordinary OnShow")
            flush()
        end
        Check(fade.group.plays == plays + 1 and fade.group:IsPlaying() and skin.motion.index
            and skin.fill:GetAlpha() == 1, "mailbox opening lost its shared fade or shell motion")
        mailbox:Hide()
        NS.ContentMotion.Unwatch(openingOwner, mailbox)
    end
    MailFrame = previousMailbox
end

-- A second content-ready signal continues from the displayed opacity.
local rapid = Target("Frame", UIParent)
NS.ContentMotion.Play(rapid, openingOwner, 1)
local rapidRecord = NS.ContentMotion.records[rapid]
rapidRecord.group.progress = 0.5
NS.ContentMotion.Play(rapid, openingOwner, 2)
Check(math.abs(rapidRecord.alpha.FromAlpha - 0.2) < 0.000001, "content-ready retarget flashed back to transparent")
rapid:Hide()
rapid:Show()
Check(NS.ContentMotion.Play(rapid, openingOwner, 3) and rapidRecord.alpha.FromAlpha == 0,
    "fresh opening retained the interrupted start alpha")
NS.ContentMotion.StopOwner(openingOwner)

-- Only final search data and actual page switches pass the bridge.
local suite = { HostBridge = {} }
assert(loadfile(root .. "/MSUF_Suite/Core/HostBridgeMenu.lua"))("MSUF_Suite", suite)
hooksecurefunc = function(target, name, callback)
    local original = target[name]
    target[name] = function(...) original(...) callback(...) end
end
local results = Target("Frame", parent)
local menu = { cache = { page = { wrapper = page }, search = { wrapper = page,
    _msuf2SearchView = { results = results } } }, searchResults = {} }
menu.SelectPage = function(key) menu.activeKey = key end
menu.Search = { _Render = { ShowSearchPage = function() menu.SelectPage("search") end } }
suite.HostBridge.WatchMenuContent(menu, function(frame, token) client:AnimateContent(frame, token) end)
menu.SelectPage("page")
local pagePlays = content.group.plays
menu.SelectPage("page")
Check(content.group.plays == pagePlays, "same-page refresh restarted content")
menu.searchResultsPending = true
menu.Search._Render.ShowSearchPage()
Check(NS.ContentMotion.records[results] == nil, "typing faded pending search skeleton")
menu.searchResultsPending = nil
menu.Search._Render.ShowSearchPage()
local resultMotion = NS.ContentMotion.records[results]
Check(resultMotion.group.plays == 1, "completed search did not fade exactly once")
menu.Search._Render.ShowSearchPage()
Check(resultMotion.group.plays == 1, "duplicate search paint restarted result fade")
menu.searchResultsPending = true
menu.Search._Render.ShowSearchPage()
Check(not resultMotion.group:IsPlaying(), "new typing retained old result motion")
menu.searchResultsPending, menu.searchResults = nil, {}
menu.Search._Render.ShowSearchPage()
Check(resultMotion.group.plays == 2, "new completed result set did not fade")
NS.Theme.SetAppearance("reduceMotion", true)
Check(not resultMotion.group:IsPlaying() and not client:AnimateContent(page, 6), "reduced motion retained content")
NS.Theme.SetAppearance("reduceMotion", false)

-- The actual Options callback also accepts already-running legacy providers.
local pageCallback, providedClient
local compatibilitySuite = { SuiteOrder = {}, Menu = {}, Skin = { RegisterMenu = Noop, Acquire = function() return providedClient end },
    HostBridge = { WatchMenuContent = function(_, callback) pageCallback = callback end,
        RegisterPageResets = function() return "test" end, RegisterPageExtension = function() return false end } }
local compatibilityOptions = { Suite = compatibilitySuite, M = { navItems = {} }, S = {}, catalog = {}, pages = {},
    Refresh = function() end }
-- The actual Register file also registers icon-skin areas. Use its real
-- core catalog metadata while keeping the motion provider boundary isolated.
local iconCatalog = { Client = NS.Client, Text = function(text) return text end }
for _, file in ipairs({ "SuiteCatalog.lua", "Catalog/CooldownManager.lua", "Catalog/CooldownManagerData.lua", "Catalog/ActionBars.lua" }) do
    assert(loadfile(root .. "/MSUF_Suite/Core/" .. file))("MSUF_Suite", iconCatalog)
end
compatibilitySuite.CDM = assert(iconCatalog.CDM)
compatibilitySuite.IconShapeIds = assert(iconCatalog.IconShapeIds)
compatibilitySuite.ActionBarEnum = assert(iconCatalog.ActionBarEnum)
compatibilityOptions.Tr = function(text) return text end
compatibilitySuite.HostBridge.OnIconSkinsChanged = Noop
-- This isolated host explicitly supports the area registration tested below.
compatibilitySuite.HostBridge.HasIconSkinAreas = function() return true end
local skinAreaRegistrations = 0
compatibilitySuite.HostBridge.RegisterIconSkinAreas = function(hostMenu, specs)
    Check(hostMenu == compatibilityOptions.M and #specs >= 4, "actual icon areas were not registered")
    for _, spec in ipairs(specs) do
        Check(type(spec.read) == "function" and type(spec.write) == "function"
            and type(spec.available) == "function", "actual icon area contract incomplete")
    end
    skinAreaRegistrations = skinAreaRegistrations + 1
end
-- This legacy menu host has no Workbench. Load the real Suite history owner
-- just as the core TOC does, retaining its designed absent-host fallback.
compatibilitySuite.SuiteProfiles, compatibilitySuite.ProfileIO = {}, {}
compatibilitySuite.HostBridge.ProfileWorkbench = function() end
assert(loadfile(root .. "/MSUF_Suite/Core/ProfileWorkbenchBridge.lua"))("MSUF_Suite", compatibilitySuite)
Check(type(compatibilitySuite.SuiteProfiles.CaptureWorkbenchSkin) == "function"
    and not compatibilitySuite.ProfileWorkbenchBridge.HistoryOwned(), "actual absent-host history bridge did not load")
assert(loadfile(root .. "/MSUF_Suite_Options/Pages/Gameplay.lua"))("MSUF_Suite_Options", compatibilityOptions)
-- This Skin-only fixture has no native tooltip page or search router.
compatibilitySuite.HostBridge.RegisterPageTail = function() return false end
compatibilitySuite.HostBridge.RegisterSearchTargetResolver = function() return false end
assert(loadfile(root .. "/MSUF_Suite_Options/Pages/QualityOfLifeOwners.lua"))("MSUF_Suite_Options", compatibilityOptions)
assert(loadfile(root .. "/MSUF_Suite_Options/Menu/Register.lua"))("MSUF_Suite_Options", compatibilityOptions)
Check(skinAreaRegistrations == 1, "actual icon area registration was skipped")
pageCallback(page, 20) -- No skin provider available.
providedClient = {} -- Legacy skin has no content command.
pageCallback(page, 21)
providedClient = client
pageCallback(page, 22)
Check(content.token == 22 and content.group:IsPlaying(), "options callback did not support old and current skin APIs")
client:ReleaseAll()

-- Declared descendants share their registered root owner after explicit paint.
NS.GenericWindows = { SetMenuMotionProvider = Noop }
NS.ResultMotion, NS.ScrollMotion, NS.LegacyScrollMotion = { ReleaseOwner = Noop }, { ReleaseOwner = Noop }, { ReleaseOwner = Noop }
NS.Adapters = { SetMenuMotionProvider = Noop }
NS.AdapterKit = { SetMotionProvider = Noop }
NS.SocialUISkin = { SetMotionProvider = Noop }
NS.CollapseCollections = { Track = Noop }
NS.AddonListMotion = { DisableOwner = Noop }
NS.Checkmarks.SetSettingsMotionProvider = Noop
Load("Rendering/MenuMotion.lua")
do
    local mailbox = Target("Frame", UIParent)
    local first, second, peer = Target("Button", mailbox), Target("Button", mailbox), Target("Button", mailbox)
    local previousMailbox, previousFirst, previousSecond = MailFrame, MailFrameTab1, MailFrameTab2
    local previousHook = hooksecurefunc
    local refresh, selection = NS.ControlSkin.Refresh, NS.MenuMotion.SelectionChanged
    MailFrame, MailFrameTab1, MailFrameTab2 = mailbox, first, second
    local installedHooks, refreshed, animated = {}, {}, {}
    hooksecurefunc = function(name, callback) installedHooks[name] = callback end
    Load("Rendering/TabMotion.lua")
    hooksecurefunc = previousHook
    NS.ControlSkin.Refresh = function(tab, selected)
        local log = refreshed[tab] or {}
        refreshed[tab] = log
        log[#log + 1] = selected
    end
    NS.MenuMotion.SelectionChanged = function(tab) animated[tab] = (animated[tab] or 0) + 1 end
    for _, tab in ipairs({ first, second, peer }) do NS.ControlSkin.states[tab] = { enabled = true } end
    local selectTab = assert(installedHooks.PanelTemplates_SelectTab)
    local deselectTab = assert(installedHooks.PanelTemplates_DeselectTab)
    local pending, flush = HoldNextFrame()
    selectTab(second)
    deselectTab(second)
    selectTab(first)
    selectTab(peer)
    Check(refreshed[peer][1] == true and animated[peer] == 1, "native non-mail tab repaint was delayed")
    if NS.Client.isForever then
        Check(not refreshed[first] and not refreshed[second] and not animated[second] and #pending == 1,
            "mail tab repaint or selection fade ran before the native opening finished")
        flush()
        Check(#refreshed[first] == 1 and refreshed[first][1] == true and animated[first] == 1
            and #refreshed[second] == 1 and refreshed[second][1] == false and not animated[second],
            "queued mail tabs did not keep only their latest selection state")
        pending, flush = HoldNextFrame()
        selectTab(second)
        mailbox:Hide()
        flush()
        Check(#refreshed[second] == 1 and not animated[second], "closed mail tab was painted by an old job")
    else
        Check(refreshed[first][1] == true and refreshed[second][1] == true and refreshed[second][2] == false
            and animated[first] == 1 and animated[second] == 1 and #pending == 0, "Retail mail tab repaint was delayed")
        flush()
    end
    NS.ControlSkin.Refresh, NS.MenuMotion.SelectionChanged = refresh, selection
    for _, tab in ipairs({ first, second, peer }) do NS.ControlSkin.states[tab] = nil end
    MailFrame, MailFrameTab1, MailFrameTab2 = previousMailbox, previousFirst, previousSecond
end
local nestedRoot, nestedBody = Target("Frame", UIParent), Target("Frame")
nestedRoot.Content, nestedBody.parent = nestedBody, nestedRoot
local nestedClient = assert(api:RegisterAddon("NestedContentProbe"))
Check(nestedClient:RegisterMenu(nestedRoot), "public menu root was not registered")
Check(nestedClient:AnimateContent(nestedBody, 1), "declared descendant did not animate")
local nestedRecord = NS.ContentMotion.records[nestedBody]
local nestedPlays = nestedRecord.group.plays
nestedBody:Hide()
nestedBody:Show()
Check(nestedRecord.group.plays == nestedPlays + 1, "descendant signal and watcher used different owners")
Check(nestedClient:Release(nestedBody) and not nestedRecord.group:IsPlaying(), "Release(child) missed ancestor-owned fade")
Check(nestedClient:AnimateContent(nestedBody, 2), "released child could not animate again")
nestedClient:ReleaseAll()
Check(not nestedRecord.group:IsPlaying(), "public menu release retained descendant motion")

-- Palette retarget starts at its displayed colors. Picker edits stay direct.
Load("Rendering/PaletteMotion.lua")
local shell = Target("Frame", UIParent)
local paletteState = Surface.Attach(shell, { role = "shell", motion = true })
Tick()
local palette = paletteState.paletteMotion
local initial = palette.current[1]
local hostPaletteFrame = Target("Frame", UIParent)
Check(host:SkinFrame(hostPaletteFrame, { role = "shell", paletteMotion = true }), "host palette policy rejected")
local hostPaletteState = NS.Registry.GetSurface(hostPaletteFrame)
Check(not hostPaletteState.motion and hostPaletteState.paletteMotion, "host palette motion duplicated host gestures")
-- Match native After: queued refresh follows all synchronous setting listeners.
C_Timer.After = function() end
NS.Theme.ApplyPreset("glass")
Surface.Refresh(shell)
Check(palette.index and palette.current[1] == initial, "palette switch snapped to its final colors")
Surface.Refresh(hostPaletteFrame)
Check(hostPaletteState.paletteMotion.index, "host gesture opt-out suppressed explicit palette motion")
Tick(3)
local displayed = palette.current[1]
NS.Theme.ApplyPreset("midnight")
Surface.Refresh(shell)
Check(palette.index and palette.current[1] == displayed, "rapid palette retarget lost the displayed color")
Tick()
Check(not palette.index and clock:GetScript("OnUpdate") == nil, "palette transition retained idle driver")
NS.Theme.ApplyPreset("glass")
Surface.Refresh(shell)
NS.Theme.SetColor("background", 0.23, 0.31, 0.42, 0.8)
Surface.Refresh(shell)
Check(not palette.index, "direct color-picker edit retained palette interpolation")
NS.Theme.ApplyPreset("midnight")
Surface.Refresh(shell)
NS.Theme.SetAppearance("menuAnimations", false)
Check(not palette.index and not client:AnimateContent(page, 7), "animation off retained palette or page motion")
Check(foreignWrites == 0, "content transitions wrote native alpha or anchors")
print("Suite skin motion: " .. checks .. " checks passed")

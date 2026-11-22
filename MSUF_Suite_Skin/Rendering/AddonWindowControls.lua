local _, NS = ...
local Windows = {}
NS.AddonWindowControls = Windows
local S, Widgets = NS.Safety, NS.PublicWidgets
local states = setmetatable({}, { __mode = "k" })
local activeWindows = setmetatable({}, { __mode = "k" })
local function Enabled()
    return NS.DB and NS.DB.windowControls and NS.DB.windowControls.enabled ~= false
end
Windows.Enabled = Enabled

local function CanAnchor(frame)
    local restricted = S.Call(frame, "IsAnchoringRestricted")
    return S.Public(restricted) and not restricted
end

function Windows.Validate(frame, options)
    if not Widgets.Safe(frame) or not S.HasMethod(frame, "GetNumPoints") or not S.HasMethod(frame, "SetScale")
        or not S.HasMethod(frame, "HookScript") or frame == UIParent then return false, "unsupported-window" end
    if options.maximize and not CanAnchor(frame) then return false, "restricted-anchors" end
    local parent = S.Read(frame, "GetParent")
    if not parent or (parent ~= UIParent and parent ~= S.Read(_G, "GetAppropriateTopLevelParent")) then return false, "not-top-level" end
    local name = S.Read(frame, "GetName")
    if NS.WindowControls.states[frame] or name and UIPanelWindows[name]
        or NS.WindowControlPolicy.IdentifyFocusWindow(frame) then return false, "native-window" end
    local close = options.closeButton
    if close and (not Widgets.Safe(close) or not Widgets.Belongs(frame, close) or close == frame
        or S.Read(close, "GetObjectType") ~= "Button") then return false, "invalid-close-button" end
    return true
end

local function Available(state)
    return state.enabled and Enabled() and not NS.IsCombatLocked() and Windows.Validate(state.frame, state.options)
end

local function SetGeometry(frame, scale, points)
    frame:SetScale(scale)
    frame:ClearAllPoints()
    for _, point in ipairs(points) do frame:SetPoint(unpack(point, 1, 5)) end
    return true
end

local function ChangeGeometry(state, scale, points)
    state.geometryChanging = true
    local applied = S.Dispatch(SetGeometry, state.frame, scale, points)
    state.geometryChanging = nil
    return applied == true
end

local function RestoreSize(state)
    local fit, frame = state.fit, state.frame
    if state.geometryChanging then return false, "geometry-changing" end
    if not fit then return true end
    if not CanAnchor(frame) then return false, "restricted-anchors" end
    for _, p in ipairs(fit.points) do
        if p[2] and S.IsForbidden(p[2]) then return false, "restricted-anchors" end
    end
    if not ChangeGeometry(state, fit.scale, fit.points) then return false, "geometry-failed" end
    state.fit = nil
    return true
end

local function UpdateGlyph(state)
    if not state.maximize then return end
    state.maxArt.kind = state.fit and "restore" or "maximize"
    NS.SuiteCore().WindowCaption.UpdateGlyph(state.maximize, state.maxArt, true)
    NS.WindowControlChrome.PaintActionCell(state.maximize, true)
end

function Windows.GetState(entry)
    local state = entry.addonWindow
    return {
        fitted = state ~= nil and state.fit ~= nil,
        minimized = state ~= nil and state.minimized == true,
    }
end

function Windows.RestoreGeometry(entry)
    local state = entry.addonWindow
    if not state then return true, "normal" end
    if NS.IsCombatLocked() then return false, "combat" end
    if not Widgets.Safe(state.frame) then return false, "protected-target" end
    local fitted = state.fit ~= nil
    local ok, why = RestoreSize(state)
    if not ok then return false, why end
    if fitted then UpdateGlyph(state) end
    return true, fitted and "restored" or "normal"
end

local function Positive(value)
    return type(value) == "number" and value > 0 and value < math.huge
end

local function FitGeometry(state, w, h, scale, effective)
    local uiWidth, uiHeight = S.Read(UIParent, "GetWidth"), S.Read(UIParent, "GetHeight")
    local uiScale = S.Read(UIParent, "GetEffectiveScale")
    if not Positive(w) or not Positive(h) or not Positive(scale) or not Positive(effective)
        or not Positive(uiWidth) or not Positive(uiHeight) or not Positive(uiScale) then return end

    local options = state.options
    local rect, insets = options.fitRect, options.fitInsets
    local left, right, bottom, top = 8, uiWidth - 8, 8, uiHeight - 8
    if rect then
        left, right = rect.left, math.min(rect.right, uiWidth)
        bottom, top = rect.bottom, math.min(rect.top, uiHeight)
    end
    local availableWidth, availableHeight = right - left, top - bottom
    if availableWidth <= 0 or availableHeight <= 0 then return end

    local outerWidth, outerHeight = w, h
    if insets then
        outerWidth = w + insets.left + insets.right
        outerHeight = h + insets.top + insets.bottom
    end
    local factor = effective / scale / uiScale
    local fit = math.min(availableWidth / outerWidth, availableHeight / outerHeight) / factor
    if not Positive(fit) then return end
    local limits = NS.WindowLayoutLimits
    local minimum, maximum = options.minScale or limits.minScale, options.maxScale or limits.maxScale
    if (rect or insets) and math.min(fit, maximum) < minimum then return end
    fit = math.max(minimum, math.min(maximum, fit))

    local ratio = fit * factor
    if not Positive(ratio) then return end
    -- SetPoint offsets are in the fitted frame's units, relative to UIParent's center.
    local x = rect and (left + availableWidth / 2 - uiWidth / 2) / ratio or 0
    local y = rect and (bottom + availableHeight / 2 - uiHeight / 2) / ratio or 0
    if insets then
        x = x + (insets.left - insets.right) / 2
        y = y + (insets.bottom - insets.top) / 2
    end
    if not (math.abs(x) + w / 2 < math.huge and math.abs(y) + h / 2 < math.huge) then return end
    return fit, {
        { "TOPLEFT", UIParent, "CENTER", x - w / 2, y + h / 2 },
        { "BOTTOMRIGHT", UIParent, "CENTER", x + w / 2, y - h / 2 },
    }
end

local function ToggleFit(state)
    if not Available(state) or state.geometryChanging then return end
    if state.fit then
        RestoreSize(state)
    else
        local frame = state.frame
        local points = NS.WindowControlPolicy.CaptureNativePoints(frame)
        local scale, effective = S.Read(frame, "GetScale"), S.Read(frame, "GetEffectiveScale")
        local w, h = S.Read(frame, "GetWidth"), S.Read(frame, "GetHeight")
        if not points then return end
        local fit, fitPoints = FitGeometry(state, w, h, scale, effective)
        if not fit then return end
        state.fit = { scale = scale, points = points }
        local applied = ChangeGeometry(state, fit, fitPoints)
        if not applied or (not state.minimized and S.Read(frame, "IsShown") == false) then RestoreSize(state) end
    end
    UpdateGlyph(state)
end

local function Restore(state, keepHidden)
    if not state.minimized then return end
    state.minimized = nil
    state.restore:Hide()
    if not keepHidden then state.frame:Show() end
end

local function Minimize(state)
    if not Available(state) or state.minimized or S.Read(state.frame, "IsShown") ~= true then return end
    local frame, bar = state.frame, state.restore
    local left, top = S.Read(frame, "GetLeft"), S.Read(frame, "GetTop")
    local effective = S.Read(frame, "GetEffectiveScale")
    bar:ClearAllPoints()
    if left and top and effective then
        local ratio = effective / UIParent:GetEffectiveScale()
        bar:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left * ratio, top * ratio)
    else bar:SetPoint("CENTER", UIParent, "CENTER") end
    state.minimized = true
    frame:Hide()
    if S.Read(frame, "IsShown") then state.minimized = nil else bar:Show() end
end

local function OnShown(frame)
    local state = states[frame]
    if state and state.enabled and state.minimized and Widgets.Safe(frame) then
        state.minimized = nil
        state.restore:Hide()
    end
end

local function Closed(frame)
    local state = states[frame]
    if not state or not state.enabled or state.minimized or not state.fit then return end
    NS.CombatGate.RunOrDefer(state, function()
        if state.enabled and state.fit and not state.minimized and not S.Read(frame, "IsShown") and Available(state) then
            RestoreSize(state)
            UpdateGlyph(state)
        end
    end)
end

local function NewButton(state, kind, action)
    local button = S.CreateChildFrame("Button", state.frame)
    local art = NS.WindowControlChrome.Control(button, kind, 2, false)
    button:RegisterForClicks("LeftButtonUp")
    button:SetScript("OnClick", function() action(state) end)
    return button, art
end

local function Prepare(state)
    local options = state.options
    if options.maximize and not state.maximize then state.maximize, state.maxArt = NewButton(state, "maximize", ToggleFit) end
    if options.minimize and not state.minimize then
        state.minimize = NewButton(state, "minimize", Minimize)
        state.restore = NS.WindowControlChrome.CreateRestore(state, function()
            if Available(state) then Restore(state) end
        end)
    end
    local right = options.closeButton
    for _, key in ipairs({ "maximize", "minimize" }) do
        local button = state[key]
        if button and options[key] then
            button:ClearAllPoints()
            if right then button:SetPoint("RIGHT", right, "LEFT", -1, 0)
            else button:SetPoint("TOPRIGHT", state.frame, "TOPRIGHT", -2, -2) end
            button:Show()
            right = button
        elseif button then button:Hide() end
    end
    if state.restoreLabel then
        state.restoreLabel:SetText(options.title or S.Read(state.frame, "GetName") or state.addon)
        state.restoreLabel:SetTextColor(NS.Theme.GetColor("text"))
    end
    UpdateGlyph(state)
end

local function Recolor()
    for state in pairs(activeWindows) do
        if state.enabled and not NS.IsCombatLocked() and Widgets.Safe(state.frame) then
            if state.maximize then NS.WindowControlChrome.PaintActionCell(state.maximize, true) end
            if state.minimize then
                NS.WindowControlChrome.PaintActionCell(state.minimize, true)
                NS.WindowControlChrome.RecolorControl(state.restore)
                state.restoreLabel:SetTextColor(NS.Theme.GetColor("text"))
            end
        end
    end
end
local function Setting(_, domain, key)
    if domain == "theme" or domain == "profile" or domain == "windowAction"
        or domain == "color" and (key == "text" or key == "disabled" or key == "popup") then NS.Registry.QueueJob(Recolor) end
end

function Windows.Release(entry)
    local state = entry.addonWindow
    if not state then return true end
    local ok, why = RestoreSize(state)
    if not ok then return false, why end
    state.enabled, activeWindows[state] = false, nil
    if not next(activeWindows) then NS.Registry.RemoveListener(Windows) end
    NS.CombatGate.Cancel(state)
    Restore(state, entry.window.showOnRelease == false)
    if state.minimize then state.minimize:Hide() state.restore:Hide() end
    if state.maximize then state.maximize:Hide() end
    state.options, entry.addonWindow = nil, nil
    return true
end

function Windows.Apply(entry, options, addon)
    local frame = entry.target
    if not Enabled() then
        local released, why = Windows.Release(entry)
        return released, released and "suspended" or why
    end
    local state = states[frame]
    if not state then
        state = { frame = frame, name = S.Read(frame, "GetName") or addon }
        states[frame] = state
        frame:HookScript("OnShow", OnShown)
        frame:HookScript("OnHide", Closed)
    end
    state.options, state.addon, state.enabled, entry.addonWindow = options, addon, true, state
    if not next(activeWindows) then NS.Registry.AddListener(Windows, Setting) end
    activeWindows[state] = true
    if not options.maximize then
        local ok, why = RestoreSize(state)
        if not ok then return false, why end
    end
    if not options.minimize then Restore(state, options.showOnRelease == false) end
    Prepare(state)
    return true
end

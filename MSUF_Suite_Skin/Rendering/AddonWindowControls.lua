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

local function RestoreSize(state)
    local fit, frame = state.fit, state.frame
    if not fit then return true end
    if not CanAnchor(frame) then return false, "restricted-anchors" end
    for _, p in ipairs(fit.points) do
        if p[2] and S.IsForbidden(p[2]) then return false, "restricted-anchors" end
    end
    frame:SetScale(fit.scale)
    frame:ClearAllPoints()
    for _, p in ipairs(fit.points) do frame:SetPoint(unpack(p, 1, 5)) end
    state.fit = nil
    return true
end

local function UpdateGlyph(state)
    if not state.maximize then return end
    state.maxArt.kind = state.fit and "restore" or "maximize"
    NS.SuiteCore().WindowCaption.UpdateGlyph(state.maximize, state.maxArt, true)
    NS.WindowControlChrome.PaintActionCell(state.maximize, true)
end

local function ToggleFit(state)
    if not Available(state) then return end
    if state.fit then
        RestoreSize(state)
    else
        local frame = state.frame
        local points = NS.WindowControlPolicy.CaptureNativePoints(frame)
        local scale, effective = S.Read(frame, "GetScale"), S.Read(frame, "GetEffectiveScale")
        local w, h = S.Read(frame, "GetWidth"), S.Read(frame, "GetHeight")
        if not points or not w or not h or not scale or not effective or w <= 0 or h <= 0 or scale <= 0 or effective <= 0 then return end
        local factor = effective / scale / UIParent:GetEffectiveScale()
        local fit = math.min((UIParent:GetWidth() - 16) / w, (UIParent:GetHeight() - 16) / h) / factor
        local limits = NS.WindowLayoutLimits
        fit = math.max(state.options.minScale or limits.minScale, math.min(state.options.maxScale or limits.maxScale, fit))
        state.fit = { scale = scale, points = points }
        frame:SetScale(fit)
        frame:ClearAllPoints()
        frame:SetPoint("TOPLEFT", UIParent, "CENTER", -w / 2, h / 2)
        frame:SetPoint("BOTTOMRIGHT", UIParent, "CENTER", w / 2, -h / 2)
    end
    UpdateGlyph(state)
end

local function Restore(state)
    if not state.minimized then return end
    state.minimized = nil
    state.restore:Hide()
    state.frame:Show()
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
    Restore(state)
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
    if not options.minimize then Restore(state) end
    Prepare(state)
    return true
end

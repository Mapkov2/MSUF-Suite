local _, NS = ...
local W, S = NS.PublicWidgets, NS.Safety
local active = setmetatable({}, { __mode = "k" })
local WatchTheme, UnwatchTheme
local watched = setmetatable({}, { __mode = "k" })
local tracks = setmetatable({}, { __mode = "k" })
local filterArrows = setmetatable({}, { __mode = "k" })
local BORDER = { role = "button", activeRole = "buttonPrimary", useControlShape = true, ownedArt = true, motion = false }

local function RestoreColor(part, saved)
    if not W.Safe(part) then return end
    local r, g, b, a = S.ReadColor(part, saved.getter)
    if r and S.ColorMatches(saved.applied, r, g, b, a, S.COLOR_OWN) then
        part[saved.setter](part, unpack(saved.original))
    end
end

local function PaintColor(state, part, spec, role)
    if not W.Safe(part) or not W.Belongs(state.plan.root, part) then return end
    local r, g, b, a = S.ReadColor(part, spec.getter)
    if not r then return end
    local saved = state.colors[part]
    if not saved then
        saved = { original = { r, g, b, a }, applied = {}, getter = spec.getter, setter = spec.setter }
        state.colors[part] = saved
    elseif not S.ColorMatches(saved.applied, r, g, b, a, S.COLOR_OWN) then
        local base, previous = saved.original, saved.applied
        if math.abs(r - previous[1]) > S.COLOR_OWN or math.abs(g - previous[2]) > S.COLOR_OWN or math.abs(b - previous[3]) > S.COLOR_OWN then
            base[1], base[2], base[3] = r, g, b
        end
        if math.abs(a - previous[4]) > S.COLOR_OWN then base[4] = a end
    end
    local cr, cg, cb, ca = NS.Theme.GetColor(role)
    ca = (ca or 1) * saved.original[4]
    saved.applied[1], saved.applied[2], saved.applied[3], saved.applied[4] = cr, cg, cb, ca
    if not S.ColorMatches(saved.applied, r, g, b, a, S.COLOR_OWN) then part[spec.setter](part, cr, cg, cb, ca) end
end

local function DropdownRole(visual, idleRole)
    if visual == "disabled" then return "disabled" end
    if visual == "pressed" or visual == "open" then return "accentBright" end
    if visual == "hover" then return "accent" end
    return idleRole
end

local function StepperDisabled(plan, button, previous)
    if not button then return end
    if W.Safe(button) and W.Belongs(plan.root, button) then
        local enabled = S.Read(button, "IsEnabled")
        if enabled ~= nil then return enabled == false end
    end
    return previous
end

local function ColorRole(state, spec)
    if state.visual == "disabled" then return "disabled" end
    if spec.input then
        local disabled = state.forwardDisabled
        if spec.input == state.plan.back then disabled = state.backDisabled end
        if disabled == nil then return end
        if disabled then return "disabled" end
    end
    if spec.role == "arrow" then return DropdownRole(state.visual, "blizzardArrow") end
    if spec.role == "label" then return DropdownRole(state.visual, "text") end
    return spec.role
end

local function Paint(state, force)
    local plan = state.plan
    if not plan or not W.Safe(plan.root) or NS.IsCombatLocked() then return end
    local trigger = plan.trigger
    if trigger and (not W.Safe(trigger) or not W.Belongs(plan.root, trigger)) then return end
    local disabled = S.Read(trigger or plan.slider or plan.root, "IsEnabled") == false
    local open = trigger and S.Read(plan.root, "IsMenuOpen") == true
    local down = trigger and (state.down or S.Read(trigger, "GetButtonState") == "PUSHED")
    local visual = disabled and "disabled" or down and "pressed" or open and "open" or state.hover and "hover" or "normal"
    local backDisabled = StepperDisabled(plan, plan.back, state.backDisabled)
    local forwardDisabled = StepperDisabled(plan, plan.forward, state.forwardDisabled)
    local visualChanged = state.visual ~= visual
    if not force and not visualChanged and state.backDisabled == backDisabled
        and state.forwardDisabled == forwardDisabled then return end
    state.visual = visual
    state.backDisabled, state.forwardDisabled = backDisabled, forwardDisabled
    if trigger then
        local selected = visual ~= "normal" and visual ~= "disabled"
        if force or selected ~= state.selected then NS.Surface.SetActive(plan.root, selected) end
        state.selected = selected
    end
    if state.filterArrow then
        state.filterArrow:SetVertexColor(NS.Theme.GetColor(DropdownRole(visual, "blizzardArrow")))
    end
    for part, spec in pairs(plan.colors) do
        local role = ColorRole(state, spec)
        if role and (force or spec.lastRole ~= role or spec.role == "arrow" or spec.role == "label") then
            PaintColor(state, part, spec, role)
            spec.lastRole = role
        end
    end
    if state.track and (force or visualChanged) then
        state.track:SetColorTexture(NS.Theme.GetColor(disabled and "disabled" or "borderSoft"))
    end
end

local function Changed(target, flag, value)
    local state = active[target]
    if not state then return end
    if flag and state[flag] == value then return end
    if flag then state[flag] = value end
    if NS.IsCombatLocked() then NS.CombatGate.RunOrDefer(state, state.repaint) else Paint(state) end
end

local function Enter(button) Changed(button, "hover", true) end
local function Leave(button) Changed(button, "hover", false) end
local function Down(button) Changed(button, "down", true) end
local function Up(button) Changed(button, "down", false) end
local function Enabled(button)
    local state = active[button]
    if not state then return end
    local plan = state.plan
    if button == plan.back or button == plan.forward then
        local enabled = S.ReadUnprotected(button, "IsEnabled")
        if enabled == nil then return end
        local disabled = not enabled
        if button == plan.back and disabled == state.backDisabled then return end
        if button == plan.forward and disabled == state.forwardDisabled then return end
    end
    Changed(button)
end
local function Hide(button)
    local state = active[button]
    if state then state.down, state.hover = nil, nil end
end

local enabledMethods = { "SetEnabled", "Enable", "Disable" }

-- Supplying OnEnable/OnDisable scripts prevents the client from passing a
-- secret argument to SetEnabled. Observe native methods without adding scripts.
function W.WatchEnabled(target, callback)
    local observer = S.Isolated(callback)
    for _, method in ipairs(enabledMethods) do
        if S.HasMethod(target, method) then hooksecurefunc(target, method, observer) end
    end
end

local function Watch(target, dropdown)
    local level = watched[target]
    if level == "dropdown" or level and not dropdown then return end
    if not level then W.WatchEnabled(target, Enabled) end
    if dropdown then
        target:HookScript("OnEnter", Enter)
        target:HookScript("OnLeave", Leave)
        target:HookScript("OnMouseDown", Down)
        target:HookScript("OnMouseUp", Up)
        target:HookScript("OnHide", Hide)
        target:HookScript("OnShow", Enabled)
    end
    watched[target] = dropdown and "dropdown" or "enabled"
end

local function MenuChanged(state) if state.plan then Changed(state.plan.root) end end
local function Unbind(state)
    local plan = state.plan
    if not plan then return end
    if state.events and W.Safe(plan.root) then
        plan.root:UnregisterCallback(state.events.OnMenuOpen, state)
        plan.root:UnregisterCallback(state.events.OnMenuClose, state)
        state.events = nil
    end
    active[plan.root] = nil
    if plan.trigger then active[plan.trigger] = nil end
    if plan.slider then active[plan.slider] = nil end
    if plan.back then active[plan.back] = nil end
    if plan.forward then active[plan.forward] = nil end
end

local function RestoreFade(root, part, owner)
    if W.Safe(part) and W.Belongs(root, part) then NS.Cosmetics.Restore(part, owner)
    else NS.Cosmetics.Forget(part, owner) end
end

function W.Release(entry)
    local state = entry.widget
    if not state then return end
    Unbind(state)
    if not state.plan.nativeBar then UnwatchTheme(state) end
    NS.CombatGate.Cancel(state)
    if state.plan.nativeBar then NS.ScrollBarSkin.DisableOwner(entry.owner) end
    for part, saved in pairs(state.colors) do
        if W.Belongs(state.plan.root, part) then RestoreColor(part, saved) end
    end
    for part in pairs(state.plan.fades or {}) do RestoreFade(state.plan.root, part, entry.owner) end
    if state.track and W.Safe(state.plan.slider) and W.Belongs(state.plan.root, state.plan.slider) then state.track:Hide() end
    if state.filterArrow then state.filterArrow:Hide() end
    if state.surface then NS.Surface.SetVisible(state.plan.root, false) end
    state.plan, entry.widget = nil, nil
end

local function TrackFor(slider)
    local track = tracks[slider]
    if not track then track = slider:CreateTexture(nil, "BACKGROUND") tracks[slider] = track end
    track:ClearAllPoints()
    if S.Read(slider, "GetOrientation") == "VERTICAL" then
        track:SetPoint("TOP", slider, "TOP") track:SetPoint("BOTTOM", slider, "BOTTOM") track:SetWidth(3)
    else
        track:SetPoint("LEFT", slider, "LEFT") track:SetPoint("RIGHT", slider, "RIGHT") track:SetHeight(3)
    end
    track:Show()
    return track
end

local function UpdateFilterArrow(state, plan)
    if not plan.filterArrow then
        if state.filterArrow then state.filterArrow:Hide() end
        state.filterArrow = nil
        return
    end
    local arrow = filterArrows[plan.root]
    if not arrow then
        arrow = plan.root:CreateTexture(nil, "OVERLAY")
        arrow:SetTexture("Interface\\ChatFrame\\ChatFrameExpandArrow")
        arrow:SetSize(14, 14)
        arrow:SetPoint("RIGHT", plan.root, "RIGHT", -4, 0)
        arrow:SetRotation(-math.pi / 2)
        filterArrows[plan.root] = arrow
    end
    state.filterArrow = arrow
    arrow:Show()
end

local function BindStepper(button, state)
    if not button then return end
    active[button] = state
    Watch(button)
end

function W.Apply(entry, plan)
    local state = entry.widget
    if state and (state.plan.trigger ~= plan.trigger or state.plan.slider ~= plan.slider
        or state.plan.back ~= plan.back or state.plan.forward ~= plan.forward or state.plan.kind ~= plan.kind
        or (state.plan.nativeBar ~= nil) ~= (plan.nativeBar ~= nil)) then W.Release(entry) state = nil end
    if not state then
        state = { colors = {} }
        state.repaint = function() if state.plan then Paint(state) end end
        entry.widget = state
    end
    if state.plan and state.plan.fades then
        for part in pairs(state.plan.fades) do
            if not (plan.fades and plan.fades[part]) then RestoreFade(plan.root, part, entry.owner) end
        end
    end
    state.plan = plan
    if plan.nativeBar then
        local bar, why = NS.ScrollBarSkin.Apply(plan.root, entry.owner, plan.parts, plan.nativeBar)
        return bar ~= nil, why
    end
    for part, saved in pairs(state.colors) do
        if not plan.colors[part] then
            if W.Belongs(plan.root, part) then RestoreColor(part, saved) end
            state.colors[part] = nil
        end
    end
    active[plan.root] = state
    if plan.trigger then
        state.surface = NS.Surface.Attach(plan.root, BORDER)
        if not state.surface then return false, "unsupported-control" end
        active[plan.trigger] = state
        Watch(plan.trigger, true)
        state.hover = S.Read(plan.trigger, "IsMouseOver") == true
        if plan.fades then
            for part in pairs(plan.fades) do
                if not NS.Cosmetics.Fade(part, entry.owner) then return false, "unsupported-dropdown-art" end
            end
        end
        UpdateFilterArrow(state, plan)
        if not state.events and S.HasMethod(plan.root, "IsMenuOpen") and S.HasMethod(plan.root, "RegisterCallback")
            and S.HasMethod(plan.root, "UnregisterCallback") then
            state.events = DropdownButtonMixin.Event
            plan.root:RegisterCallback(state.events.OnMenuOpen, MenuChanged, state)
            plan.root:RegisterCallback(state.events.OnMenuClose, MenuChanged, state)
        end
    else
        local input = plan.slider or plan.root
        active[input] = state
        if S.HasMethod(input, "HookScript") then Watch(input) end
        BindStepper(plan.back, state)
        BindStepper(plan.forward, state)
        if plan.slider and not plan.hasTrack then state.track = TrackFor(plan.slider)
        elseif state.track then state.track:Hide() state.track = nil end
    end
    WatchTheme(state)
    Paint(state, true)
    return true
end

local themed = setmetatable({}, { __mode = "k" })
local tokens = { text = true, accent = true, accentBright = true, blizzardArrow = true, borderSoft = true,
    disabled = true, checkmark = true, hover = true }
local function Refresh()
    for state in pairs(themed) do Paint(state, true) end
end
local function Setting(_, domain, key)
    if domain == "theme" or domain == "profile" or domain == "color" and tokens[key] then NS.Registry.QueueJob(Refresh) end
end
WatchTheme = function(state)
    if not next(themed) then NS.Registry.AddListener(W, Setting) end
    themed[state] = true
end
UnwatchTheme = function(state)
    themed[state] = nil
    if not next(themed) then NS.Registry.RemoveListener(W) end
end

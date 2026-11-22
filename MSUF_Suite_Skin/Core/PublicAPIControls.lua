local _, NS = ...
local S, W = NS.Safety, NS.PublicWidgets
local widgetOptions = {
    SkinDropdown = { kind = "dropdown", "trigger", "label", "arrow" },
    SkinCheckButton = { kind = "checkButton", "indicator", "label" },
    SkinSlider = { kind = "slider", "track", "thumb", "back", "forward", "backArt", "forwardArt" },
    SkinScrollBar = { kind = "scrollBar", "track", "thumb", "back", "forward", "backArt", "forwardArt" },
}
local menuColors = {
    background = "popup", border = "border", text = "text", title = "title", disabled = "disabled",
    highlight = "hover", selection = "active", check = "checkmark", arrow = "blizzardArrow",
}
local directions = { left = true, right = true, up = true, down = true }
local edges = { "left", "right", "top", "bottom" }

local function Options(options)
    return S.Public(options) and (options == nil or type(options) == "table" and getmetatable(options) == nil)
end

local function Bounds(value, default)
    if not Options(value) or not value then return nil end
    local bounds = {}
    for _, edge in ipairs(edges) do
        local offset = rawget(value, edge)
        if not S.Public(offset) then return nil end
        if offset == nil then offset = default end
        if type(offset) ~= "number" or not (offset >= 0 and offset < math.huge) then return nil end
        bounds[edge] = offset
    end
    return bounds
end

local defaultAction = {}
local function ActionOptions(kind, options)
    if not S.Public(options) then return nil, "invalid-options" end
    local direction, appearance
    if type(options) == "table" then
        direction, appearance = rawget(options, "direction"), rawget(options, "appearance")
        if not S.Public(direction) or not S.Public(appearance) then return nil, "invalid-options" end
    end
    if direction ~= nil and (not directions[direction] or kind ~= "expand" and kind ~= "collapse") then return nil, "invalid-direction" end
    if appearance ~= nil and appearance ~= "standalone" and appearance ~= "caption" then return nil, "invalid-appearance" end
    if appearance == "caption" and (kind == "expand" or kind == "collapse") then return nil, "invalid-appearance" end
    if not direction and appearance ~= "caption" then return defaultAction end
    return { direction = direction, appearance = appearance }
end

local function WidgetMethod(definition, safe, request)
    return function(self, root, options)
        local ok, reason = safe(root, true)
        if not ok then return false, reason end
        if not Options(options) then return false, "invalid-options" end
        local spec = {}
        if options then
            for i = 1, #definition do
                local key = definition[i]
                local part = rawget(options, key)
                if not S.Public(part) then return false, "protected-target" end
                if part ~= nil then
                    if not W.Safe(part) then return false, "protected-target" end
                    if not W.Belongs(root, part) then return false, "foreign-region" end
                    spec[key] = part
                end
            end
        end
        return request(self, root, "control", { kind = definition.kind, widget = true, spec = spec }, true)
    end
end

local function WindowOptions(options)
    if not Options(options) or not options then return nil end
    local spec = {}
    for _, key in ipairs({
        "closeButton", "minimize", "maximize", "minScale", "maxScale", "title", "showOnRelease", "fitInsets", "fitRect",
    }) do
        local value = rawget(options, key)
        if not S.Public(value) then return nil end
        spec[key] = value
    end
    if spec.minimize ~= nil and type(spec.minimize) ~= "boolean" or spec.maximize ~= nil and type(spec.maximize) ~= "boolean" then return nil end
    if spec.showOnRelease ~= nil and type(spec.showOnRelease) ~= "boolean" then return nil end
    if not (spec.closeButton or spec.minimize or spec.maximize) then return nil end
    for _, key in ipairs({ "minScale", "maxScale" }) do
        local value = spec[key]
        if value ~= nil and (type(value) ~= "number" or not (value > 0 and value < math.huge)) then return nil end
    end
    if spec.minScale and spec.maxScale and spec.minScale > spec.maxScale then return nil end
    if spec.title ~= nil and (type(spec.title) ~= "string" or #spec.title > 128) then return nil end
    if spec.fitInsets ~= nil then
        spec.fitInsets = Bounds(spec.fitInsets, 0)
        if not spec.fitInsets or not spec.maximize then return nil end
    end
    if spec.fitRect ~= nil then
        local rect = Bounds(spec.fitRect)
        if not rect or not spec.maximize or rect.left >= rect.right or rect.bottom >= rect.top then return nil end
        spec.fitRect = rect
    end
    return spec
end

local function WindowEntry(scope, frame)
    if not S.Public(frame) or frame == nil then return nil, "unknown-window" end
    local entry = scope.targets[frame]
    if not entry or not entry.window then return nil, "unknown-window" end
    return entry
end

local function InstallWindowMethods(methods, getScope, safe, request)
    function methods:RegisterWindow(frame, options)
        local ok, reason = safe(frame, true)
        if not ok then return false, reason end
        local spec = WindowOptions(options)
        if not spec then return false, "invalid-options" end
        ok, reason = NS.AddonWindowControls.Validate(frame, spec)
        if not ok then return false, reason end
        return request(self, frame, "window", spec, true)
    end
    function methods:GetWindowState(frame)
        local scope, reason = getScope(self)
        if not scope then return nil, reason end
        local entry, why = WindowEntry(scope, frame)
        if not entry then return nil, why end
        return NS.AddonWindowControls.GetState(entry)
    end
    function methods:RestoreWindowGeometry(frame)
        local scope, reason = getScope(self)
        if not scope then return false, reason end
        local entry, why = WindowEntry(scope, frame)
        if not entry then return false, why end
        return NS.AddonWindowControls.RestoreGeometry(entry)
    end
end

function NS.InstallPublicControls(methods, getScope, safe, request, enabled)
    for name, definition in pairs(widgetOptions) do methods[name] = WidgetMethod(definition, safe, request) end
    InstallWindowMethods(methods, getScope, safe, request)
    function methods:GetTargetStatus(target)
        local scope = getScope(self)
        if not scope then return "released" end
        if not S.Public(target) or target == nil then return "unknown-target" end
        local entry = scope.targets[target]
        if not entry then
            local outcome = scope.outcomes and scope.outcomes[target]
            if outcome == true then return "released" end
            if outcome then return "failed", outcome end
            return "unknown-target"
        end
        if scope.pendingOperation then return NS.PublicAPI.playerReady and "deferred" or "pending" end
        local status = entry.status
        if status == "applied" or status == "native" then
            local action = entry.control
            if action and action.kind == "windowAction" and not (action.caption or entry.captionHost) and NS.WindowActionSkin.GetState then
                local state = NS.WindowActionSkin.GetState(target)
                if state and state.owner == entry.owner then return state.style == "native" and "native" or "applied" end
            end
            if entry.widget and entry.widget.plan.nativeBar then
                local state = NS.ScrollBarSkin.GetState(target)
                if not state or not state.enabled or state.owner ~= entry.owner then return "failed", "scrollbar-contract-changed" end
            end
        end
        return status or "pending", entry.failure
    end
    function methods:OnTargetsSettled() end
    function methods:SetTargetNotifications(on)
        local scope, reason = getScope(self)
        if not scope then return false, reason end
        if not S.Public(on) or type(on) ~= "boolean" then return false, "invalid-options" end
        scope.notifyTargets = on
        if on and not scope.signalJob then
            -- Give hooksecurefunc a concrete method on this client only.
            rawset(self, "OnTargetsSettled", self.OnTargetsSettled)
            scope.signalJob = function()
                if scope.notifyTargets and not scope.client.released and not scope.client.unregisterPending then
                    S.Dispatch(self.OnTargetsSettled, self)
                end
            end
        end
        return true
    end
    function methods:GetMenuStyle()
        local scope = getScope(self)
        if not scope then return nil, "released" end
        if not enabled(scope) or scope.suspended then return nil, "inactive" end
        local result = { font = self:GetFont() }
        for name, role in pairs(menuColors) do result[name] = { NS.Theme.GetColor(role) } end
        return result
    end
    function methods:SkinMenuDescription(description, options)
        local scope, reason = getScope(self)
        if not scope then return false, reason end
        if not Options(options) then return false, "invalid-options" end
        local preserveFont = options and rawget(options, "preserveFont")
        if not S.Public(preserveFont) or preserveFont ~= nil and type(preserveFont) ~= "boolean" then
            return false, "invalid-options"
        end
        return NS.PublicMenuStyle.Bind(description, scope, enabled, preserveFont)
    end
    function methods:CreateMenuMixin(base)
        local scope, reason = getScope(self)
        if not scope then return nil, reason end
        return NS.PublicMenuStyle.CreateMixin(base, scope, enabled)
    end
    return ActionOptions
end

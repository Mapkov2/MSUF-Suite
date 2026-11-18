local _, NS = ...
local S, W = NS.Safety, NS.PublicWidgets
local widgetOptions = {
    SkinDropdown = { kind = "dropdown", "trigger", "label", "arrow" },
    SkinCheckButton = { kind = "checkButton", "indicator", "label" },
    SkinSlider = { kind = "slider", "track", "thumb", "back", "forward" },
    SkinScrollBar = { kind = "scrollBar", "track", "thumb", "back", "forward" },
}
local menuColors = {
    background = "popup", border = "border", text = "text", title = "title", disabled = "disabled",
    highlight = "hover", selection = "active", check = "checkmark", arrow = "blizzardArrow",
}
local directions = { left = true, right = true, up = true, down = true }

local function Options(options)
    return S.Public(options) and (options == nil or type(options) == "table" and getmetatable(options) == nil)
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
    for _, key in ipairs({ "closeButton", "minimize", "maximize", "minScale", "maxScale", "title" }) do
        local value = rawget(options, key)
        if not S.Public(value) then return nil end
        spec[key] = value
    end
    if spec.minimize ~= nil and type(spec.minimize) ~= "boolean" or spec.maximize ~= nil and type(spec.maximize) ~= "boolean" then return nil end
    if not (spec.closeButton or spec.minimize or spec.maximize) then return nil end
    for _, key in ipairs({ "minScale", "maxScale" }) do
        local value = spec[key]
        if value ~= nil and (type(value) ~= "number" or not (value > 0 and value < math.huge)) then return nil end
    end
    if spec.minScale and spec.maxScale and spec.minScale > spec.maxScale then return nil end
    if spec.title ~= nil and (type(spec.title) ~= "string" or #spec.title > 128) then return nil end
    return spec
end

function NS.InstallPublicControls(methods, getScope, safe, request, enabled)
    for name, definition in pairs(widgetOptions) do methods[name] = WidgetMethod(definition, safe, request) end
    function methods:RegisterWindow(frame, options)
        local ok, reason = safe(frame, true)
        if not ok then return false, reason end
        local spec = WindowOptions(options)
        if not spec then return false, "invalid-options" end
        ok, reason = NS.AddonWindowControls.Validate(frame, spec)
        if not ok then return false, reason end
        return request(self, frame, "window", spec, true)
    end
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
    return ActionOptions
end

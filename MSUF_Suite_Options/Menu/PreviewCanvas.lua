local _, P = ...
local K = {}
P.PreviewCanvas = K

function K.Text(parent, text, x, y, width)
    return P.Text(parent, text, x, y, width, P.T.colors.text)
end
function K.Button(parent, x, y, width, height, open)
    local button = CreateFrame("Button", nil, parent)
    button:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    button:SetSize(width, height)
    if open then button:SetScript("OnClick", open) end
    P.HM.SkipHistoryCheckpoint(button)
    return button
end
function K.Jump(ui, region, parent, section)
    local button = CreateFrame("Button", nil, parent)
    button:SetAllPoints(region)
    button:SetFrameLevel(parent:GetFrameLevel() + 6)
    button:SetScript("OnClick", function() ui:Focus(section) end)
    button:SetScript("OnEnter", function() P.PreviewInteraction.Outline(button, true) end)
    button:SetScript("OnLeave", function() P.PreviewInteraction.Outline(button, false) end)
    P.HM.SkipHistoryCheckpoint(button)
    return button
end
-- No snapshots, closures or tables are allocated by a warm refresh.
function K.Changed(state, config, rules)
    local changed = false
    for key in pairs(rules) do
        if state[key] ~= config[key] then state[key], changed = config[key], true end
    end
    return changed
end
local failedLoads = {}
function K.Runtime(addon, export)
    if P.S[export] then return true end
    if P.Combat() or failedLoads[addon] then return false end
    C_AddOns.LoadAddOn(addon)
    if not P.S[export] then failedLoads[addon] = true end
    return P.S[export] ~= nil
end
function K.Watch(ui, paint)
    local events = CreateFrame("Frame", nil, ui.header)
    local queued, pending = false, false
    local function Refresh()
        if ui.header:IsVisible() and ui.ctx.wrapper:IsVisible() then
            pending = false
            paint()
            return true
        end
        return false
    end
    local function Replay()
        queued = false
        if not pending then return end
        pending = false
        Refresh()
    end
    local function Request()
        if Refresh() then return end
        if not ui.header:IsShown() or not ui.ctx.wrapper:IsShown() then return end
        if not ui.header:IsVisible() and not ui.ctx.wrapper:IsVisible() then return end
        -- Detached owners can become visible in different layout callbacks.
        -- Retry once after that transition; Replay never schedules more work.
        pending = true
        if queued then return end
        queued = true
        C_Timer.After(0, Replay)
    end
    local function Activate()
        events:RegisterEvent("PLAYER_REGEN_ENABLED")
        Request()
    end
    events:SetScript("OnShow", Activate)
    events:SetScript("OnHide", function()
        pending = false
        events:UnregisterAllEvents()
    end)
    events:SetScript("OnEvent", Request)
    ui.ctx.wrapper:HookScript("OnShow", Request)
    ui.ctx.wrapper:HookScript("OnHide", function() pending = false end)
    ui.refreshPreview = Request
    P.M.TrackRefresh(ui.ctx, Request)
    if events:IsVisible() then Activate() end
end

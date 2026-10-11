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
    local function Refresh()
        if ui.header:IsVisible() then paint() end
    end
    local function Activate()
        events:RegisterEvent("PLAYER_REGEN_ENABLED")
        Refresh()
    end
    events:SetScript("OnShow", Activate)
    events:SetScript("OnHide", function() events:UnregisterAllEvents() end)
    events:SetScript("OnEvent", Refresh)
    ui.refreshPreview = Refresh
    P.M.TrackRefresh(ui.ctx, Refresh)
    if events:IsVisible() then Activate() end
end

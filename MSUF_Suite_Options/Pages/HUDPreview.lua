local _, P = ...
local Suite, S, M, Tr, HM = P.Suite, P.S, P.M, P.Tr, P.HM
local Preview = {}
P.HUDPreview = Preview
local modes = { objectives = "quests", runSummary = "raid", announcements = "zone", afkScreen = "character" }

function Preview.Stop(ui)
    if ui.dismissTimer then
        ui.dismissTimer:Cancel()
        ui.dismissTimer = nil
    end
    if ui.animation then
        ui.animation:Stop()
        ui.leave:Stop()
    end
    ui.playing, ui.finished = false, false
    ui.canvas:SetAlpha(1)
end

local function Animation(ui)
    local group = ui.canvas:CreateAnimationGroup()
    group:SetToFinalAlpha(true)
    local enter = group:CreateAnimation("Alpha")
    enter:SetOrder(1)
    enter:SetFromAlpha(0)
    enter:SetToAlpha(1)
    enter:SetDuration(.22)
    group:SetScript("OnFinished", function()
        -- Commit the visible hold after the native fade, instead of relying
        -- on its transient alpha until the independent display clock expires.
        if ui.playing and ui.dismissTimer then ui.canvas:SetAlpha(1) end
    end)
    local leave = ui.canvas:CreateAnimationGroup()
    leave:SetToFinalAlpha(true)
    local fadeOut = leave:CreateAnimation("Alpha")
    fadeOut:SetFromAlpha(1)
    fadeOut:SetToAlpha(0)
    fadeOut:SetDuration(.36)
    leave:SetScript("OnFinished", function()
        ui.playing, ui.finished = false, true
        ui.canvas:SetAlpha(0)
    end)
    ui.animation, ui.leave = group, leave
end

function Preview.Play(ui)
    if ui.id ~= "announcements" or not ui.host:IsVisible() then return end
    Preview.Stop(ui)
    if not ui.animation then Animation(ui) end
    local duration = S.Config("announcements").duration
    ui.lastDuration, ui.playing = duration, true
    ui.animation:Play()
    -- Match the actual banner: fade-in and the display clock start together;
    -- only the one-shot deadline starts the independent fade-out group.
    local timer
    timer = C_Timer.NewTimer(duration, function()
        if ui.dismissTimer ~= timer then return end
        ui.dismissTimer = nil
        if ui.playing and ui.id == "announcements" and ui.host:IsVisible() then ui.leave:Play() end
    end)
    ui.dismissTimer = timer
end

-- Read the already loaded public palette, without acquiring a runtime skin
-- client or loading/enabling a feature just to display its example.
function Preview.Color(c, key, fallback, token)
    if c.colorStyle == 2 then return P.RGB(c[key]) end
    local provider = _G.MapkoSkin
    if token and Suite.Skin.enabled and type(provider) == "table" and type(provider.GetAPI) == "function" then
        local api = provider.GetAPI(2, 0)
        if api then return api:GetColor(token) end
    end
    return unpack(fallback)
end

function Preview.Label(ui, text, x, y, width, size, color, shadow, distance)
    ui.used = ui.used + 1
    local label = ui.labels[ui.used]
    if not label then
        label = ui.canvas:CreateFontString(nil, "OVERLAY")
        ui.labels[ui.used] = label
    end
    P.StylePreviewFont(label, Suite.ResolveFont(ui.config.font), size, "OUTLINE", 1, true, shadow or 70, distance or 1)
    label:ClearAllPoints()
    label:SetPoint("TOPLEFT", x, y)
    label:SetWidth(width)
    label:SetJustifyH("LEFT")
    label:SetWordWrap(false)
    label:SetText(text)
    label:SetTextColor(unpack(color))
    label:Show()
    return label
end

function Preview.Fill(ui, x, y, width, height, color, alpha)
    ui.fillsUsed = ui.fillsUsed + 1
    local fill = ui.fills[ui.fillsUsed]
    if not fill then
        fill = ui.canvas:CreateTexture(nil, "BACKGROUND")
        ui.fills[ui.fillsUsed] = fill
    end
    fill:ClearAllPoints()
    fill:SetPoint("TOPLEFT", x, y)
    fill:SetSize(width, height)
    fill:SetDrawLayer("BACKGROUND", 0)
    fill:SetColorTexture(color[1], color[2], color[3], alpha or 1)
    fill:Show()
    return fill
end

local function Paint(ui)
    if not ui.id or not ui.host:IsVisible() then return end
    ui.config, ui.used, ui.fillsUsed = S.Config(ui.id), 0, 0
    if ui.afk then ui.afk.host:Hide() end
    local width, height = Preview.Render[ui.id](ui, modes[ui.id])
    for i = ui.used + 1, #ui.labels do ui.labels[i]:Hide() end
    for i = ui.fillsUsed + 1, #ui.fills do ui.fills[i]:Hide() end
    ui.canvas:SetSize(width, height)
    ui.canvas:SetScale(math.min((ui.config.scale or 100) / 100, ui.width / width, 182 / height))
    if not ui.playing then ui.canvas:SetAlpha(ui.finished and 0 or 1) end
    if ui.id == "announcements" then
        local duration = ui.config.duration
        if ui.lastDuration and ui.lastDuration ~= duration then Preview.Play(ui) end
        ui.lastDuration = duration
    end
end

local function Focus(ui)
    local workspace = ui.ctx._msufSuiteHUDWorkspace
    local group = workspace.groups[ui.id]
    local body = group.appearance or group.body
    if P.W.FocusCollapsibleSection then P.W.FocusCollapsibleSection(body, { flash = true }) end
end

local function Select(ui, id)
    if ui.id ~= id then Preview.Stop(ui) end
    ui.id = id
    if ui.selection then
        P.PreviewInteraction.Select(ui.selection, ui.canvas, P.catalog[id].title, function() Focus(ui) end)
    end
    ui.playButton:SetShown(id == "announcements")
    for key, picker in pairs(ui.pickers) do P.W.SetControlShown(picker, key == id) end
    -- Only the AFK example reads character events, and only while visible.
    ui.host:UnregisterAllEvents()
    if id == "afkScreen" and ui.host:IsVisible() then
        for _, event in ipairs({ "PLAYER_EQUIPMENT_CHANGED", "UNIT_MODEL_CHANGED", "ZONE_CHANGED_NEW_AREA" }) do
            ui.host:RegisterEvent(event)
        end
    end
    Paint(ui)
end

local function Pickers(ui, parent)
    for id, choices in pairs(Preview.Choices) do
        local feature, values = id, {}
        for _, choice in ipairs(choices) do
            values[#values + 1] = { value = choice[1], text = Tr(choice[2]) }
        end
        local width = math.min(300, id == "announcements" and ui.width - 162 or ui.width)
        local picker = M.BindDropdownAt(ui.ctx, parent, "Preview", 16, -42, values, width,
            function() return modes[feature] end, function(value)
                modes[feature] = value
                Preview.Stop(ui)
                Paint(ui)
            end, P.Meta("suite_hud", feature, "view.preview", "ephemeral"))
        ui.pickers[id] = picker
    end
end

function Preview.Build(ctx, parent, width)
    local host = CreateFrame("Frame", nil, parent)
    host:SetPoint("TOPLEFT", 16, -99)
    host:SetSize(width, 186)
    host:SetClipsChildren(true)
    local canvas = CreateFrame("Button", nil, host)
    canvas:SetPoint("CENTER")
    HM.SkipHistoryCheckpoint(canvas)
    HM.AllowCombatClick(canvas)
    local ui = { ctx = ctx, host = host, canvas = canvas, width = width, labels = {}, fills = {}, pickers = {} }
    canvas:SetScript("OnClick", function()
        P.PreviewInteraction.Select(ui.selection, canvas, P.catalog[ui.id].title, function() Focus(ui) end)
        Focus(ui)
    end)
    ui.Select, ui.Paint = Select, Paint
    Pickers(ui, parent)
    ui.playButton = P.T.Button(parent, "Play preview", 146, 26)
    ui.playButton:SetPoint("TOPLEFT", width - 130, -66)
    HM.SkipHistoryCheckpoint(ui.playButton)
    HM.AllowCombatClick(ui.playButton)
    ui.playButton:SetScript("OnClick", function() Preview.Play(ui) end)
    ui.selection = P.PreviewInteraction.Bar(ctx, parent, width, "Sample preview. Changes update here even when the feature is off.")
    ui.selection:SetPoint("TOPLEFT", parent, "TOPLEFT", 16, -291)
    local height = 326
    HM.SetFixedPreviewHeight(parent, height)
    parent:SetHeight(height)
    host:SetScript("OnShow", function() if ui.id then Select(ui, ui.id) end end)
    host:SetScript("OnHide", function()
        host:UnregisterAllEvents()
        Preview.Stop(ui)
    end)
    host:SetScript("OnEvent", function(_, event, unit)
        if event == "UNIT_MODEL_CHANGED" and (Suite.IsSecret(unit) or unit ~= "player") then return end
        Paint(ui)
    end)
    M.TrackRefresh(ctx, function() Paint(ui) end)
    return ui
end

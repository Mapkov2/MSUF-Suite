local _, P = ...
local S = P.Suite
local ID = "floatingCombatText"
local PREVIEW_SLOTS = 10
local SHOWCASE = { "crit", "dodge", "parry", "xp" }
local min, max, floor, abs = math.min, math.max, math.floor, math.abs

local function UpdateModel(ui)
    if not ui.modelDirty or ui.menu.Combat() then return end
    local restricted = C_Secrets.ShouldUnitIdentityBeSecret("player")
    if not S.Public(restricted) or restricted then return end
    local model = ui.model
    if not model then
        -- PaperDollFrame_SetPlayer uses this same scene setup. Our actor
        -- dresses the current unit with its own camera and frame.
        model = CreateFrame("ModelScene", nil, ui.content, "NonInteractableModelSceneMixinTemplate")
        model:SetPoint("CENTER")
        ui.model = model
    end
    ModelSceneUtil.SetUpCharacterSheetScene(model)
    local sceneID = model:GetModelSceneID()
    local bound = S.Finite(sceneID) and sceneID > 0
    model:SetSize(ui.modelWidth or 160, 210)
    model:SetShown(bound)
    if not bound then SetPortraitTexture(ui.portrait, "player") end
    ui.portrait:SetShown(not bound)
    ui.modelDirty = false
end

local function MeasureSamples(ui, config, font)
    local fontString, widths = ui.probe, ui.widths
    local normal, critical = config.fontSize, config.fontSize * config.critScale / 100
    wipe(widths)
    for _, sample in ipairs(S.FloatingTextSamples) do
        S.SetFont(fontString, font, sample.critical and critical or normal, "OUTLINE")
        if sample.format then fontString:SetFormattedText(sample.format, sample.value)
        else
            fontString:SetText(sample.value)
        end
        local route = sample.route
        local width = fontString:GetStringWidth()
        widths[route] = max(widths[route] or 0, S.Finite(width) and width or 0)
    end
end

local function Fit(ui, c)
    local display, sizes = ui.display, ui.widths
    local plate, left = display.placements[1], display.placements[2]
    local sideWidth, plateWidth = 0, 0
    for route, width in pairs(sizes) do
        if display.routes[route] == 1 then plateWidth = max(plateWidth, width)
        else
            sideWidth = max(sideWidth, width)
        end
    end
    local halfHeight = (left.rows * left.step - 8) / 2 + abs(c.screenY)
    local plateSpan = (plate.rows - 1) * plate.step + display.height + plate.dy
    local usesPlate = plateWidth > 0
    if usesPlate then halfHeight = max(halfHeight, plateSpan / 2 + 20) end
    local halfWidth = max(c.sideOffset + sideWidth + abs(left.dx), plateWidth / 2)
    local scale = min(1, (ui.width - 32) / (2 * halfWidth), (ui.height - 40) / (2 * halfHeight))
    ui.content:SetScale(scale)
    ui.content:SetSize(ui.width / scale, ui.height / scale)
    ui.plate:ClearAllPoints()
    ui.plate:SetPoint("CENTER", ui.content, "CENTER", 0, -plateSpan / 2 - c.offset - 8)
    ui.plate:SetShown(usesPlate)
    ui.modelWidth = min(172, c.sideOffset * 1.8)
    if ui.model then ui.model:SetWidth(ui.modelWidth) end
end

local function Show(ui, sample, stationary)
    ui.display:Show(sample.route, sample.critical, sample.format, sample.value, ui.plate, stationary)
end

local function Play(ui, sample)
    if not ui.stage:IsVisible() or not ui.display then return end
    if ui.stationary or not sample then ui.display:Clear() end
    ui.stationary = nil
    if sample then
        Show(ui, sample)
    else
        for _, key in ipairs(SHOWCASE) do Show(ui, ui.samples[key]) end
    end
end

local function TestButton(ui, parent, sample, label, x, y, width)
    local button = ui.menu.T.Button(parent, label, width, 24)
    button:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    button:SetScript("OnClick", function() Play(ui, sample) end)
    ui.menu.HM.SkipHistoryCheckpoint(button)
    return button
end

local function Buttons(ui)
    local grid, columns = ui.grid, ui.columns
    local width = (ui.width - (columns - 1) * 6) / columns
    for i, sample in ipairs(S.FloatingTextSamples) do
        ui.samples[sample.key] = sample
        local x = (i - 1) % columns * (width + 6)
        local y = -floor((i - 1) / columns) * 29
        ui.buttons[sample.key] = TestButton(ui, grid, sample, sample.label, x, y, width)
    end
    local y = -math.ceil(#S.FloatingTextSamples / columns) * 29 - 2
    ui.buttons.burst = TestButton(ui, grid, nil, "Play sample burst", 0, y, min(ui.width, 180))
end

local function Paint(ui)
    if not ui.stage:IsVisible() then return end
    local config = S.Config(ID)
    local font = S.ResolveFont(config.font) or S.GlobalFontPath()
    if not ui.display then
        ui.display = S.FloatingTextDisplay.New(ui.content, PREVIEW_SLOTS)
        Buttons(ui)
    end
    local changed = ui.menu.PreviewCanvas.Changed(ui.settings, config, ui.menu.catalog[ID].rules)
    if not ui.ready or changed or ui.font ~= font then
        ui.ready, ui.font, ui.stationary = true, font, true
        ui.display:Configure(config, font)
        MeasureSamples(ui, config, font)
        Fit(ui, config)
        for _, key in ipairs(SHOWCASE) do Show(ui, ui.samples[key], true) end
    end
    UpdateModel(ui)
end

local function CreateStage(ui, parent, y)
    local menu, T = ui.menu, ui.menu.T
    local stage = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    stage:SetPoint("TOPLEFT", parent, "TOPLEFT", 16, y)
    stage:SetSize(ui.width, ui.height)
    stage:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
    stage:SetBackdropColor(.036, .052, .073, 1)
    stage:SetBackdropBorderColor(.19, .28, .36, 1)
    local left = menu.Text(stage, "Left", 12, -9, 100, T.colors.muted)
    local right = menu.Text(stage, "Right", ui.width - 112, -9, 100, T.colors.muted)
    left:SetWordWrap(false)
    right:SetJustifyH("RIGHT")
    local content = CreateFrame("Frame", nil, stage)
    content:SetPoint("CENTER")
    local portrait = content:CreateTexture(nil, "ARTWORK")
    portrait:SetPoint("CENTER")
    portrait:SetSize(84, 84)
    portrait:Hide()
    local plate = CreateFrame("Frame", nil, content)
    plate:SetSize(116, 13)
    local bar = plate:CreateTexture(nil, "BACKGROUND")
    bar:SetAllPoints()
    bar:SetColorTexture(.5, .16, .18, .9)
    local label = T.Font(plate, "GameFontHighlightSmall", "Enemy nameplate", T.colors.text, "control")
    label:SetPoint("CENTER")
    ui.stage, ui.content, ui.plate, ui.portrait = stage, content, plate, portrait
    ui.probe = S.CreateFontString(stage, nil, "ARTWORK")
    ui.probe:Hide()
    stage.floatingTextPreview = ui
end

local function WatchPreview(ui, ctx)
    local stage = ui.stage
    local function Shown()
        ui.modelDirty = true
        stage:RegisterUnitEvent("UNIT_MODEL_CHANGED", "player")
        stage:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
        stage:RegisterEvent("UPDATE_SHAPESHIFT_FORM")
        stage:RegisterEvent("PLAYER_REGEN_ENABLED")
        Paint(ui)
    end
    stage:SetScript("OnShow", Shown)
    stage:SetScript("OnHide", function()
        stage:UnregisterAllEvents()
        if ui.display then ui.display:Clear() end
        ui.ready = false
    end)
    stage:SetScript("OnEvent", function(_, event)
        if event ~= "PLAYER_REGEN_ENABLED" then ui.modelDirty = true end
        Paint(ui)
    end)
    ui.menu.M.TrackRefresh(ctx, function() Paint(ui) end)
    if stage:IsVisible() then Shown() end
end

function S.BuildFloatingCombatTextPreview(menu, ctx, parent, width, y)
    local room = width - 32
    local title = menu.Text(parent, "Interactive preview", 16, y, room)
    y = y - max(18, math.ceil(title:GetStringHeight() or 18)) - 4
    local hint = menu.Text(parent, "Click an event to preview its movement.", 16, y, room, menu.T.colors.muted)
    y = y - max(16, math.ceil(hint:GetStringHeight() or 16)) - 8
    local ui = { menu = menu, width = room, height = 306, columns = max(2, min(6, floor(room / 128))),
        settings = {}, widths = {}, samples = {}, buttons = {} }
    CreateStage(ui, parent, y)
    y = y - ui.height - 8
    ui.grid = CreateFrame("Frame", nil, parent)
    local height = (math.ceil(#S.FloatingTextSamples / ui.columns) + 1) * 29 + 4
    ui.grid:SetPoint("TOPLEFT", parent, "TOPLEFT", 16, y)
    ui.grid:SetSize(room, height)
    ctx.floatingTextPreview = ui
    WatchPreview(ui, ctx)
    return y - height - 10
end

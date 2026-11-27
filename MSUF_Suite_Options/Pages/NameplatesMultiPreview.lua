local _, P = ...
local Multi = {}
P.NameplatesMultiPreview = Multi
local WIDTH, HEIGHT = 1080, 150
local SAMPLES = {
    { side = "enemy", scope = "enemy", role = 4, health = 53, cast = true },
    { side = "enemy", scope = "neutral", role = 8, health = 100 },
    { side = "friendly", scope = "friendly", health = 83, cast = true },
    { side = "friendly", scope = "friendlyNpc", health = 100 },
}
local LABELS = { enemy = "Enemy", neutral = "Neutral", friendly = "Friendly", friendlyNpc = "Friendly NPC" }

local function BindStatic(_, handle)
    handle:EnableMouse(false)
    handle:EnableMouseWheel(false)
end

local function LayerOn(editor, key)
    return key ~= "guides" and P.NameplatesEditorLayers.On(editor, key)
end

-- The ordinary sample owns all painters and geometry. These display-only
-- editors carry independent sample facts while sharing the current settings.
local function Build(ui)
    local frame = CreateFrame("Frame", nil, ui.stage)
    frame:SetSize(WIDTH, HEIGHT)
    frame:SetPoint("CENTER", ui.stage, "CENTER", 0, 0)
    local group = { frame = frame, samples = {} }
    for index, info in ipairs(SAMPLES) do
        local editor = setmetatable({ stage = frame, sampleCells = {}, renderers = {}, layers = ui.layers,
            isGroupSample = true, sampleKind = info.side, scope = info.scope, Bind = BindStatic, LayerOn = LayerOn,
            enemyPlayer = false, friendlyElite = info.scope == "friendlyNpc", friendlyOutsider = false,
            statusSample = false, allStatusSamples = false, statusOffsetSample = false,
            castSample = false, interruptedSample = false, castingSample = info.cast == true, questSample = false,
            textSample = false, auraSample = false,
            targetSample = index == 1, focusSample = false, aggroSample = false, highlightSample = false,
            raidMarked = false, raidIndex = 8, softTargetSample = false, uninterruptible = false,
            previewRole = info.role, previewRoleSource = P.Get("nameplates", "enemyPreviewRole"),
        }, { __index = ui })
        local sample = P.NameplatesPreview.Sample(editor, info.side, 0)
        sample.state.health, sample.state.cast = info.health, info.cast == true
        sample.castProgress:SetValue(57)
        sample.cell:ClearAllPoints()
        sample.cell:SetPoint("CENTER", frame, "CENTER", (index - 2.5) * 270, -8)
        local button = P.T.Button(frame, LABELS[info.scope], 140, 22)
        button:SetPoint("BOTTOM", sample.cell, "TOP", 0, -23)
        button:SetScript("OnClick", function() P.NameplatesWorkspace.Open(info.scope) end)
        group.samples[index] = { editor = editor, sample = sample, button = button }
    end
    ui.groupPreview = group
    return group
end

function Multi.Set(ui, enabled)
    enabled = enabled == true
    if ui.groupPreviewEnabled == enabled then return end
    ui:CancelDrag()
    ui:Select(nil)
    if enabled then
        ui.singlePreviewView = { zoom = ui.zoom, x = ui.panX, y = ui.panY, fit = ui.fitMode }
        ui.zoom, ui.panX, ui.panY, ui.fitMode = 1, 0, 0, nil
    elseif ui.singlePreviewView then
        local view = ui.singlePreviewView
        ui.zoom, ui.panX, ui.panY, ui.fitMode = view.zoom, view.x, view.y, view.fit
        ui.singlePreviewView = nil
    end
    ui.groupPreviewEnabled = enabled
    ui:Layout()
    ui:Paint()
end

function Multi.Attach(ui)
    local button = P.T.Button(ui.toolbar or ui.body, "Compare all", 108, 20)
    -- The caption toggles; one width fits both translated captions on one line.
    P.SetButtonText(button, P.Tr("Single preview"))
    P.PreviewCanvas.FitToolbarButton(button)
    P.SetButtonText(button, P.Tr("Compare all"))
    P.PreviewCanvas.FitToolbarButton(button)
    button:SetScript("OnClick", function() Multi.Set(ui, not ui.groupPreviewEnabled) end)
    P.NameplatesEditorLayers.Register(button, "groupPreview", "Compare all")
    ui.groupPreviewButton = button
end

function Multi.Paint(ui)
    if not ui.groupPreviewButton then return false end
    local active = ui.groupPreviewEnabled
    P.SetButtonText(ui.groupPreviewButton, P.Tr(active and "Single preview" or "Compare all"))
    ui.samples:SetShown(not ui.compact and not active)
    ui.raidPalette:SetShown(not ui.compact and not active)
    if not active then
        if ui.groupPreview then ui.groupPreview.frame:Hide() end
        return false
    end
    local group = ui.groupPreview or Build(ui)
    for _, cell in pairs(ui.sampleCells) do cell:Hide() end
    group.frame:SetScale(math.max(.05, math.min(1,
        (ui.canvas:GetWidth() - 24) / WIDTH, (ui.canvas:GetHeight() - 32) / HEIGHT)))
    group.frame:Show()
    for index, record in ipairs(group.samples) do
        record.editor.previewRole, record.editor.previewRoleSource = SAMPLES[index].role, P.Get("nameplates", "enemyPreviewRole")
        record.editor.enemyPlayer = SAMPLES[index].scope == "enemy" and ui.enemyPlayer == true
        record.button:SetAlpha(ui.scope == SAMPLES[index].scope and 1 or 0.8)
        P.NameplatesPreview.Render(record.editor, record.sample)
    end
    return true
end

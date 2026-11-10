local _, P = ...
local Multi = {}
P.NameplatesMultiPreview = Multi
local WIDTH, HEIGHT = 1080, 360
local HEALTH = { 83, 49, 21, 66, 100, 35 }
local ROLES = { 1, 3, 4, 6, 8, 9 }

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
    for index = 1, #HEALTH do
        local editor = setmetatable({ stage = frame, sampleCells = {}, renderers = {}, layers = ui.layers,
            isGroupSample = true, sampleKind = "enemy", Bind = BindStatic, LayerOn = LayerOn,
            personal = false, enemyPlayer = false, friendlyElite = false, friendlyOutsider = false,
            targetSample = index == 1, focusSample = index == 2, aggroSample = index == 3,
            raidMarked = index == 4, raidIndex = 8, softTargetSample = false, uninterruptible = index == 5,
            previewRole = ROLES[index], previewRoleSource = P.Get("nameplates", "enemyPreviewRole"),
        }, { __index = ui })
        local sample = P.NameplatesPreview.Sample(editor, "enemy", 0)
        sample.state.health, sample.state.cast = HEALTH[index], index ~= 3 and index ~= 6
        sample.castProgress:SetValue(20 + index * 11)
        sample.cell:ClearAllPoints()
        sample.cell:SetPoint("CENTER", frame, "CENTER", ((index - 1) % 3 - 1) * 350,
            index <= 3 and 85 or -85)
        group.samples[index] = { editor = editor, sample = sample }
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
        ui.singlePreviewView = { zoom = ui.zoom, x = ui.panX, y = ui.panY }
        ui.zoom, ui.panX, ui.panY = 1, 0, 0
    elseif ui.singlePreviewView then
        local view = ui.singlePreviewView
        ui.zoom, ui.panX, ui.panY = view.zoom, view.x, view.y
        ui.singlePreviewView = nil
    end
    ui.groupPreviewEnabled = enabled
    ui:Paint()
end

function Multi.Attach(ui)
    local button = P.T.Button(ui.tools, "Group preview", 122, 20)
    button:SetPoint("TOPLEFT", ui.tools, "TOPLEFT", 188, 0)
    button:SetScript("OnClick", function() Multi.Set(ui, not ui.groupPreviewEnabled) end)
    P.NameplatesEditorLayers.Register(button, "groupPreview", "Group preview")
    ui.groupPreviewButton = button
end

function Multi.Paint(ui)
    if not ui.groupPreviewButton then return false end
    local active = ui.groupPreviewEnabled and not ui.compact
    ui.groupPreviewButton:SetText(P.Tr(active and "Single preview" or "Group preview"))
    ui.samples:SetShown(not ui.compact and not active)
    ui.raidPalette:SetShown(not ui.compact and not active)
    if ui.targetStateButton then
        ui.targetStateButton:SetShown(not active)
        ui.focusStateButton:SetShown(not active)
    end
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
        record.editor.previewRole, record.editor.previewRoleSource = ROLES[index], P.Get("nameplates", "enemyPreviewRole")
        P.NameplatesPreview.Render(record.editor, record.sample)
    end
    return true
end

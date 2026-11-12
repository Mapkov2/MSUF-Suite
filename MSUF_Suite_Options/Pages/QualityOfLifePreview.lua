local _, P = ...
local S, K, Tr = P.S, P.PreviewCanvas, P.Tr
local EXPORTS = {
    glimmer = "DrawGlimmerPreview", xpBar = "DrawExperienceBarPreview", skyriding = "DrawSkyridingPreview",
    lootRolls = "DrawLootRollPreview", actionTracker = "DrawActionTrackerPreview",
    battleRes = "DrawBattleResPreview", enemyCastStack = "DrawEnemyCastStackPreview",
}
local RETAIL = { skyriding = true, battleRes = true, enemyCastStack = true }
local function GlossGate(rule)
    if rule.key == "glossEnabled" or rule.key == "glossStrength" then
        return P.Suite.GlossMaterial.Available(), "This look requires MSUF 7.0."
    end
    return true
end
for _, id in ipairs({ "actionTracker", "battleRes", "enemyCastStack", "skyriding" }) do P.Gates[id] = GlossGate end

-- Hit areas belong to the menu, above the runtime's unchanged sample artwork.
-- The broad surface is behind the smaller text/rested targets.
local TARGETS = {
    xpBar = { key = "displayStyle" },
    glimmer = { key = "size" },
    skyriding = { view = "suiteFlightPreview", key = "width",
        { "speed", "speedHeight" }, { "title", "fontSize" }, { "state", "displayStyle" } },
    lootRolls = { key = "width" },
    actionTracker = { key = "rowHeight" },
    battleRes = { key = "scale" },
    enemyCastStack = { key = "rowHeight" },
}

local function OpenTarget(ui, key)
    if P.Combat() or not ui.stage:IsVisible() then return false end
    local group = P.QoLView.FindFeature(ui.id)
    local page = P.QoLView.GetFeaturePage(group)
    local exact = P.Meta(page, ui.id, key, "setting", P.QoLView.FeatureSectionId(group))
    local called, opened, focused = P.M.SearchBridge.OpenSearchTarget(page, "", nil, nil, {}, exact)
    return called == true and opened == true and focused == true
end

local function Target(ui, host, region, key, priority)
    if not region then return end
    local handle = ui.targets[key]
    if not handle then
        handle = CreateFrame("Button", nil, host)
        handle:SetFrameLevel(host:GetFrameLevel() + 20 + priority)
        handle:EnableMouse(true)
        handle:SetScript("OnClick", function() OpenTarget(ui, key) end)
        handle:SetScript("OnEnter", function() P.PreviewInteraction.Outline(handle, true) end)
        handle:SetScript("OnLeave", function() P.PreviewInteraction.Outline(handle, false) end)
        handle:SetScript("OnHide", function() P.PreviewInteraction.Outline(handle, false) end)
        P.HM.SkipHistoryCheckpoint(handle)
        local rule = P.catalog[ui.id].rules[key]
        P.M.AddTooltip(handle, Tr(rule.label), Tr("Click an element to open its settings."), { hook = true })
        ui.targets[key] = handle
    end
    if handle.region ~= region then
        handle:ClearAllPoints()
        handle:SetAllPoints(region)
        handle.region = region
    end
    handle:SetShown(region:IsShown())
end

local function BindTargets(ui, host)
    local spec = TARGETS[ui.id]
    Target(ui, host, host, spec.key, 0)
    if ui.id == "xpBar" then P.XPBarPreviewEditor.Bind(ui, ui.stage.suiteXPPreview) end
    if ui.id == "lootRolls" then P.LootRollPreviewEditor.Bind(ui, ui.stage.suiteLootRollPreview) end
    local view = spec.view and ui.stage[spec.view]
    if not view then return end
    for index, row in ipairs(spec) do Target(ui, host, view[row[1]], row[2], index) end
end

local function SampleSlider(ui, parent, key, label, maximum, step, y)
    local title = P.Text(parent, label, 16, y, ui.width)
    y = y - math.max(16, math.ceil(title:GetStringHeight() or 16)) - 6
    local slider = CreateFrame("Slider", nil, parent)
    slider:SetPoint("TOPLEFT", parent, "TOPLEFT", 16, y)
    slider:SetSize(ui.width - 60, 20)
    slider:SetOrientation("HORIZONTAL")
    slider:EnableMouse(true)
    slider:SetMinMaxValues(0, maximum)
    slider:SetValueStep(step)
    slider:SetObeyStepOnDrag(true)
    slider:SetThumbTexture("Interface\\Buttons\\WHITE8X8")
    local thumb = slider:GetThumbTexture()
    thumb:SetSize(8, 18)
    thumb:SetColorTexture(unpack(P.T.colors.accent))
    local track = slider:CreateTexture(nil, "BACKGROUND")
    track:SetColorTexture(unpack(P.T.colors.border))
    track:SetPoint("LEFT", slider, "LEFT")
    track:SetPoint("RIGHT", slider, "RIGHT")
    track:SetHeight(4)
    local value = P.Text(parent, "", 16 + ui.width - 52, y, 52)
    value:SetJustifyH("RIGHT")
    slider:SetScript("OnValueChanged", function(_, number)
        number = math.floor(math.max(0, math.min(maximum, number)) / step + .5) * step
        ui.sample[key] = number
        value:SetText(step < 1 and ("%.1f"):format(number) or tostring(number))
        ui.Paint()
    end)
    P.HM.SkipHistoryCheckpoint(slider)
    ui.sliders[key] = slider
    slider:SetValue(ui.sample[key])
    return y - 30
end

local function Paint(ui)
    if not ui.stage:IsVisible() then return end
    if not K.Runtime("MSUF_Suite_QualityOfLife", EXPORTS[ui.id]) then
        P.SetTranslatedText(ui.status, Tr("Preview is available outside combat."))
        return
    end
    P.SetTranslatedText(ui.status, "")
    local config = S.Config(ui.id)
    local native = UIParent:GetEffectiveScale() / ui.stage:GetEffectiveScale()
    ui.viewport.scale = native * (config.scale or 100) / 100
    if ui.restore then ui.restore() end
    local host, _, _, dx, dy = S[EXPORTS[ui.id]](ui.stage, config, ui.sample, ui.viewport)
    host:ClearAllPoints()
    host:SetPoint("CENTER", ui.stage, "CENTER", dx or 0, dy or 0)
    host:Show()
    BindTargets(ui, host)
end

-- Lazy feature details call this once. Only these sliders' sample table changes;
-- normal appearance controls still edit the active profile and repaint here.
function P.BuildQoLIndicatorPreview(ctx, parent, id, width, y)
    if not EXPORTS[id] or RETAIL[id] and P.Suite.Client.isForever then return y end
    local room = width - 32
    local title = P.Text(parent, "Interactive preview", 16, y, room, P.T.colors.text)
    y = y - math.max(16, math.ceil(title:GetStringHeight() or 16)) - 6
    local note = P.Text(parent, "Sample values. Changes update here even when the feature is off.", 16, y, room)
    P.SetTranslatedText(note, Tr("Sample values. Changes update here even when the feature is off.")
        .. "\n" .. Tr("Click an element to open its settings."))
    y = y - math.max(28, math.ceil(note:GetStringHeight() or 28)) - 8
    local height = id == "xpBar" and 160 or id == "glimmer" and 190 or 230
    local stage = CreateFrame("Frame", nil, parent)
    stage:SetPoint("TOPLEFT", parent, "TOPLEFT", 16, y)
    stage:SetSize(room, height)
    stage:SetClipsChildren(true)
    local ui = { id = id, ctx = ctx, stage = stage, width = room, height = height, sliders = {}, targets = {},
        viewport = { width = room, height = height },
        sample = { xp = 62, rested = 25, vigor = 4.5, speed = 760 } }
    ui.status = P.Text(stage, "", 0, -8, room)
    ui.Paint = function() Paint(ui) end
    ui.OpenTarget = function(key) return OpenTarget(ui, key) end
    y = y - height - 8
    if id == "xpBar" then
        y = SampleSlider(ui, parent, "xp", "Preview XP (percent)", 100, 1, y)
        y = SampleSlider(ui, parent, "rested", "Preview rested XP (percent)", 100, 1, y)
    elseif id == "skyriding" then
        y = SampleSlider(ui, parent, "vigor", "Preview Vigor", 6, .1, y)
        y = SampleSlider(ui, parent, "speed", "Preview speed (percent)", 1500, 10, y)
    end
    stage:SetScript("OnShow", function()
        stage:RegisterEvent("PLAYER_REGEN_ENABLED")
        ui.Paint()
    end)
    stage:SetScript("OnHide", function()
        stage:UnregisterAllEvents()
        if id == "glimmer" and S.HideGlimmerPreview then S.HideGlimmerPreview(stage) end
    end)
    stage:SetScript("OnEvent", ui.Paint)
    P.M.TrackRefresh(ctx, ui.Paint)
    ctx.qolIndicatorPreviews = ctx.qolIndicatorPreviews or {}
    ctx.qolIndicatorPreviews[id] = ui
    if stage:IsVisible() then
        stage:RegisterEvent("PLAYER_REGEN_ENABLED")
        ui.Paint()
    end
    if id == "xpBar" then y = P.XPBarPreviewEditor.Build(ui, parent, y, room) end
    if id == "lootRolls" then y = P.LootRollPreviewEditor.Build(ui, parent, y, room) end
    return y - 14
end

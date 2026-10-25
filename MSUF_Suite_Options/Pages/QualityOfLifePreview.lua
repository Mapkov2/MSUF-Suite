local _, P = ...
local S, K, Tr = P.S, P.PreviewCanvas, P.Tr
local EXPORTS = { xpBar = "DrawExperienceBarPreview", skyriding = "DrawSkyridingPreview",
    actionTracker = "DrawActionTrackerPreview", battleRes = "DrawBattleResPreview", enemyCastStack = "DrawEnemyCastStackPreview" }
local RETAIL = { skyriding = true, battleRes = true, enemyCastStack = true }
local function GlossGate(rule)
    if rule.key == "glossEnabled" or rule.key == "glossStrength" then
        return P.Suite.GlossMaterial.Available(), "This look requires MSUF 7.0."
    end
    return true
end
for _, id in ipairs({ "actionTracker", "battleRes", "enemyCastStack", "skyriding" }) do P.Gates[id] = GlossGate end

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
    ui.viewport.scale = native * config.scale / 100
    local host = S[EXPORTS[ui.id]](ui.stage, config, ui.sample, ui.viewport)
    host:ClearAllPoints()
    host:SetPoint("CENTER", ui.stage, "CENTER")
    host:Show()
end

-- Lazy feature details call this once. Only these sliders' sample table changes;
-- normal appearance controls still edit the active profile and repaint here.
function P.BuildQoLIndicatorPreview(ctx, parent, id, width, y)
    if not EXPORTS[id] or RETAIL[id] and P.Suite.Client.isForever then return y end
    local room = width - 32
    local title = P.Text(parent, "Interactive preview", 16, y, room, P.T.colors.text)
    y = y - math.max(16, math.ceil(title:GetStringHeight() or 16)) - 6
    local note = P.Text(parent, "Sample values. Changes update here even when the feature is off.", 16, y, room)
    y = y - math.max(28, math.ceil(note:GetStringHeight() or 28)) - 8
    local height = id == "xpBar" and 90 or 230
    local stage = CreateFrame("Frame", nil, parent)
    stage:SetPoint("TOPLEFT", parent, "TOPLEFT", 16, y)
    stage:SetSize(room, height)
    stage:SetClipsChildren(true)
    local ui = { id = id, ctx = ctx, stage = stage, width = room, height = height, sliders = {},
        viewport = { width = room, height = height },
        sample = { xp = 62, rested = 25, vigor = 4.5, speed = 760 } }
    ui.status = P.Text(stage, "", 0, -8, room)
    ui.Paint = function() Paint(ui) end
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
    stage:SetScript("OnHide", function() stage:UnregisterAllEvents() end)
    stage:SetScript("OnEvent", ui.Paint)
    P.M.TrackRefresh(ctx, ui.Paint)
    ctx.qolIndicatorPreviews = ctx.qolIndicatorPreviews or {}
    ctx.qolIndicatorPreviews[id] = ui
    if stage:IsVisible() then
        stage:RegisterEvent("PLAYER_REGEN_ENABLED")
        ui.Paint()
    end
    return y - 14
end

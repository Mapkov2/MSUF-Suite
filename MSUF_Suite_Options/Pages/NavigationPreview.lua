local _, P = ...
local Suite, Tr = P.S, P.Tr
local ID = "navigation"
local SCENES = { "Far destination", "Near destination", "Off-screen destination", "No destination" }

local function Paint(ui)
    if not ui.stage:IsVisible() then return end
    if not P.PreviewCanvas.Runtime("MSUF_Suite_QualityOfLife", "DrawNavigationPreview") then return end
    local config = Suite.Config(ID)
    local navigation = Suite.Navigation
    navigation.Sample(ui.sample, config, ui.scene, ui.distance)
    ui.view = Suite.DrawNavigationPreview(ui.stage, config, ui.sample)
    local ratio = math.min(1, ui.width / 800)
    local x = ui.scene == 3 and (110 + config.navigatorX * ratio) or 0
    local y = ui.scene == 3 and (config.navigatorY * ratio) or -28
    ui.anchor:ClearAllPoints()
    ui.anchor:SetPoint("CENTER", ui.stage, "CENTER", x, y)
    ui.view.root:ClearAllPoints()
    ui.view.root:SetPoint("CENTER", ui.anchor, "CENTER")
    ui.view.root:SetScale((ui.view.scale or 1) * math.min(.85, ratio * 1.25))
    for _, handle in ipairs(ui.handles.list) do
        handle:SetShown(ui.view.root:IsShown())
        handle:ClearAllPoints()
        handle:SetAllPoints(ui.view.root)
    end
    for _, item in ipairs(ui.targets) do
        local region = ui.view[item[1]]
        item.button:SetShown(region:IsShown() and ui.view.root:IsShown())
        item.button:ClearAllPoints()
        item.button:SetAllPoints(region)
    end
end

local function Select(ui, key)
    if ui.select then ui.select(key) end
end

local function Handles(ui)
    ui.host = P.Suite.PreviewKit.NewHost(nil, { frame = ui.stage, paint = function() Paint(ui) end })
    ui.handles = P.PreviewInteraction.Handles(ui.host, {
        owner = ui.stage,
        click = function() Select(ui, ui.scene == 3 and "navigatorX" or ui.scene == 2 and "cardWidth" or "markerSize") end,
        tip = function(handle, entering) P.PreviewInteraction.Outline(handle, entering) end,
    })
    local handle = CreateFrame("Button", nil, ui.stage)
    handle:SetFrameLevel(ui.stage:GetFrameLevel() + 20)
    P.HM.SkipHistoryCheckpoint(handle)
    ui.handles:Add("direction", handle,
        function() local config = Suite.Config(ID) return config.navigatorX, config.navigatorY end,
        function(x, y)
            if ui.scene ~= 3 then return false end
            return P.SetMany(ID, { navigatorX = math.floor(x + .5), navigatorY = math.floor(y + .5) })
        end, {
            can = function() return ui.scene == 3 end,
            scale = function() return ui.stage:GetEffectiveScale() * math.min(1, ui.width / 800) end,
            follow = function(_, dx, dy)
                local config, ratio = Suite.Config(ID), math.min(1, ui.width / 800)
                ui.anchor:ClearAllPoints()
                ui.anchor:SetPoint("CENTER", ui.stage, "CENTER", 110 + (config.navigatorX + dx) * ratio,
                    (config.navigatorY + dy) * ratio)
            end,
        })
    ui.targets = {}
    for _, item in ipairs({ { "card", "cardWidth" }, { "beam", "beamHeight" }, { "distance", "fontSize" } }) do
        local key = item[2]
        item.button = CreateFrame("Button", nil, ui.stage)
        item.button:SetFrameLevel(ui.stage:GetFrameLevel() + 22)
        item.button:SetScript("OnClick", function() Select(ui, key) end)
        item.button:SetScript("OnEnter", function(button) P.PreviewInteraction.Outline(button, true) end)
        item.button:SetScript("OnLeave", function(button) P.PreviewInteraction.Outline(button, false) end)
        P.HM.SkipHistoryCheckpoint(item.button)
        ui.targets[#ui.targets + 1] = item
    end
end

function P.BuildNavigationPreview(ctx, parent, width, select)
    local ui = { ctx = ctx, width = width - 32, scene = 1, distance = 450, sample = {}, select = select }
    P.Text(parent, "Interactive preview", 16, -16, ui.width, P.T.colors.text)
    P.Text(parent, "Choose a situation. Click the marker for settings; drag the off-screen indicator to position it.",
        16, -38, ui.width)
    ui.stage = CreateFrame("Frame", nil, parent)
    ui.stage:SetPoint("TOPLEFT", 16, -82)
    ui.stage:SetSize(ui.width, 230)
    ui.stage:SetClipsChildren(true)
    ui.anchor = CreateFrame("Frame", nil, ui.stage)
    ui.anchor:SetSize(1, 1)
    local background = ui.stage:CreateTexture(nil, "BACKGROUND")
    background:SetAllPoints()
    background:SetColorTexture(.035, .055, .08, .8)
    local columns = ui.width < 520 and 2 or 4
    for index, name in ipairs(SCENES) do
        local slot = index - 1
        P.Button(ctx, parent, name, 16 + slot % columns * (ui.width / columns),
            -320 - math.floor(slot / columns) * 32, ui.width / columns - 5, function()
                ui.scene, ui.distance = index, index == 2 and 25 or 450
                ui.slider:SetValue(ui.distance)
                Paint(ui)
            end, nil, P.Meta("suite_qualityOfLife", ID, "preview." .. index, "action"))
    end
    local y = -320 - math.ceil(4 / columns) * 32
    local slider = CreateFrame("Slider", nil, parent)
    ui.slider = slider
    slider:SetPoint("TOPLEFT", 24, y - 12)
    slider:SetSize(ui.width - 95, 18)
    slider:SetOrientation("HORIZONTAL")
    slider:SetMinMaxValues(0, 1000)
    slider:SetValueStep(5)
    slider:SetObeyStepOnDrag(true)
    slider:SetThumbTexture("Interface\\Buttons\\WHITE8X8")
    slider:GetThumbTexture():SetSize(8, 18)
    local label = P.Text(parent, "Preview distance", 16, y - 37, ui.width)
    slider:SetScript("OnValueChanged", function(_, value)
        ui.distance = math.floor(value + .5)
        label:SetText(Tr("Preview distance: %d yd"):format(ui.distance))
        Paint(ui)
    end)
    P.HM.SkipHistoryCheckpoint(slider)
    Handles(ui)
    slider:SetValue(ui.distance)
    ui.stage:SetScript("OnShow", function() ui.host:Activate() Paint(ui) end)
    ui.stage:SetScript("OnHide", function() ui.host:Deactivate() end)
    P.M.TrackRefresh(ctx, function() Paint(ui) end)
    if ui.stage:IsVisible() then ui.host:Activate() Paint(ui) end
    return y - 70, ui
end

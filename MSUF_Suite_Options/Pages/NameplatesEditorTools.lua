local _, P = ...
-- The nameplate preview's tool rows: zoom, snap and guides under the canvas,
-- the sample switches on it, the target and focus samples and the raid mark
-- palette. NameplatesEditor.lua builds them through Tools.Build and
-- Tools.BuildRaidPalette.
local M, T, Tr, HM = P.M, P.T, P.Tr, P.HM
local ID = "nameplates"
local H = M.PreviewHelpers or {}
local Layers = P.NameplatesEditorLayers
local Elements = P.NameplatesElements
local Templates = P.NameplatesLayoutTemplates
local Register, OpenSetting = Layers.Register, Layers.OpenSetting
local Layout = P.NameplatesPreviewLayout
local Snap = P.PreviewSnap
local Tools = {}
P.NameplatesEditorTools = Tools
local RAID_MARK_NAMES = { [0] = "Off", [1] = "Star", [2] = "Circle", [3] = "Diamond",
    [4] = "Triangle", [5] = "Moon", [6] = "Blue square", [7] = "Cross", [8] = "Skull" }
local SNAP_HELP = "While dragging, elements snap to the edges and centers of the other elements and of the plate. Hold Alt to place freely."

local function Button(parent, key, label, width, action)
    local button = T.Button(parent, label, width, 20)
    Layout.StyleButton(button)
    button:SetScript("OnClick", action)
    Register(button, key, label)
    return button
end

local function BuildZoomTools(ui)
    local body, canvas = ui.body, ui.canvas
    local tools = CreateFrame("Frame", nil, body)
    tools:SetPoint("TOPLEFT", canvas, "BOTTOMLEFT", 0, -4)
    tools:SetPoint("TOPRIGHT", canvas, "BOTTOMRIGHT", 0, -4)
    ui.tools = tools
    tools:SetHeight(46)
    local fit = Button(tools, "fit", "Fit", 36, function() Layout.Fit(ui) end)
    local actual = Button(tools, "actual", "1:1", 36, function() Layout.SetZoom(ui, 1) end)
    local zoomOut = Button(tools, "zoomOut", "-", 24, function() Layout.StepZoom(ui, -1) end)
    ui.zoomLabel = T.Font(tools, "GameFontDisableSmall", "100%", T.colors.text)
    ui.zoomLabel:SetJustifyH("CENTER")
    ui.zoomLabel:SetWordWrap(false)
    local zoomIn = Button(tools, "zoomIn", "+", 24, function() Layout.StepZoom(ui, 1) end)
    local snap = Button(tools, "snap", "Snap", 52, function()
        Snap.SetEnabled(not Snap.Enabled())
        P.PreviewInteraction.RefreshLayerButton(ui.snapButton, Snap.Enabled())
    end)
    ui.snapButton = snap
    HM.SkipHistoryCheckpoint(snap)
    HM.SetCommandAction(snap, { kind = "toggle", historyMode = "none", get = Snap.Enabled,
        set = function(on)
            Snap.SetEnabled(on == true)
            P.PreviewInteraction.RefreshLayerButton(snap, Snap.Enabled())
            return true
        end })
    if M.AddTooltip then M.AddTooltip(snap, "Snap", SNAP_HELP, { hook = true }) end
    -- The preview guides (sample titles and outlines) were a layer chip.
    local guides = Button(tools, "guides", "Guides", 58, function() Layers.Toggle(ui, "guides") end)
    ui.guidesButton = guides
    HM.SkipHistoryCheckpoint(guides)
    if M.AddTooltip then M.AddTooltip(guides, "Guides", "Click: show or hide preview guides", { hook = true }) end
    local inactive = Button(tools, "inactiveElements", "Show inactive elements", 126, function()
        ui.showInactive = ui.showInactive == false
        ui:Paint()
    end)
    ui.inactiveButton = inactive
    HM.SkipHistoryCheckpoint(inactive)
    local templates = Button(tools, "layoutTemplates", "Layout templates", 100, function(button) Templates.Open(ui, button) end)
    ui.templatesButton = templates
    HM.SkipHistoryCheckpoint(templates)
    for _, button in ipairs({ fit, actual, zoomOut, zoomIn, snap, guides, inactive, templates }) do P.PreviewCanvas.FitToolbarButton(button) end
    ui.zoomControls = { { fit, fit:GetWidth() }, { actual, actual:GetWidth() }, { zoomOut, zoomOut:GetWidth() },
        { ui.zoomLabel, 40 }, { zoomIn, zoomIn:GetWidth() }, { snap, snap:GetWidth() }, { guides, guides:GetWidth() },
        { inactive, inactive:GetWidth() }, { templates, templates:GetWidth() } }
end

local SCENARIOS = {
    { label = "Trash pack casting", role = 2, casting = true, raid = true },
    { label = "Boss with aggro", role = 4, target = true, aggro = true, raid = true },
    { label = "Quest mob", role = 1, quest = true },
    { label = "PvP player", player = true, target = true, casting = true, uninterruptible = true },
}

local function BeginCustomSample(ui)
    ui.sampleScenario = nil
    ui.highlightSample, ui.statusSample, ui.allStatusSamples, ui.statusOffsetSample = nil, nil, nil, nil
    ui.castSample, ui.interruptedSample = nil, nil
    ui.auraSample, ui.sharedAuraText, ui.textSample, ui.opacitySample, ui.editFullPlate = nil, nil, nil, nil, nil
    ui.layerContext = "anchor"
end

local function SetType(ui, role, player)
    ui.previewRole, ui.previewRoleSource = role, P.Get(ID, "enemyPreviewRole")
    ui.enemyPlayer, ui.questSample = player == true, false
end

local function SetRaid(ui, on)
    ui.raidMarked = on
    if on then
        if not ui.raidIndex or ui.raidIndex == 0 then ui.raidIndex = 8 end
    end
end

local function SelectScenario(ui, scenario)
    if P.Combat() then return end
    if scenario and ui.scope ~= "enemy" then P.NameplatesWorkspace.Open("enemy") end
    BeginCustomSample(ui)
    if scenario then
        ui.sampleScenario = scenario
        SetType(ui, scenario.role, scenario.player)
        ui.targetSample, ui.focusSample = scenario.target == true, false
        ui.castingSample, ui.uninterruptible = scenario.casting == true, scenario.uninterruptible == true
        ui.aggroSample, ui.questSample = scenario.aggro == true, scenario.quest == true
        SetRaid(ui, scenario.raid == true)
    end
    ui:Paint()
end

local function OpenType(ui, button)
    P.AnchoredContextMenu(button, function(_, menu)
        local roles = P.Suite.NameplateStyle.Roles
        for index, role in ipairs(roles) do
            menu:CreateButton(Tr(role.label), function()
                if P.Combat() then return end
                BeginCustomSample(ui)
                SetType(ui, index)
                ui:Paint()
            end)
        end
        menu:CreateButton(Tr("Player"), function()
            if P.Combat() then return end
            BeginCustomSample(ui)
            SetType(ui, nil, true)
            ui:Paint()
        end)
    end)
end

local function SampleButton(ui, parent, key, label, action)
    local button = Button(parent, key, label, 20, function(self)
        if P.Combat() then return end
        action(self)
    end)
    HM.SkipHistoryCheckpoint(button)
    return button
end

local function Toggle(ui, parent, key, label, action)
    return SampleButton(ui, parent, key, label, function()
        -- Capture toggle intent before releasing a settings-specific sample.
        local active = action(true)
        BeginCustomSample(ui)
        action(false, not active)
        ui:Paint()
    end)
end

local function StateButton(ui, parent, key, label, field, effective, after)
    return Toggle(ui, parent, key, label, function(read, on)
        if read then
            if effective then return effective(ui) end
            return ui[field]
        end
        ui[field] = on
        if after then after(ui, on) end
    end)
end

local function BuildSampleButtons(ui)
    local body, canvas = ui.body, ui.canvas
    local samples = CreateFrame("Frame", nil, body)
    ui.samples = samples
    samples:SetPoint("TOPLEFT", canvas, "TOPLEFT", 8, -8)
    samples:SetSize(540, 20)
    ui.softTypeButton = SampleButton(ui, samples, "softType", "Soft: enemy / interact", function()
        ui.softInteract = not ui.softInteract
        ui:Select(nil)
        ui:Paint()
    end)
    ui.friendlyButtons = {}
    ui.friendlyButtons[1] = SampleButton(ui, samples, "friendlyMode", "Friendly player display", function()
        OpenSetting("friendlyNamesOnly")
    end)
    ui.friendlyButtons[2] = SampleButton(ui, samples, "friendlyGroup", "Group / outsider", function()
        ui.friendlyOutsider = not ui.friendlyOutsider
        ui:Paint()
    end)
    if H.EnsurePreviewBackgroundButton then
        local background = H.EnsurePreviewBackgroundButton(body, samples)
        if background then
            background:ClearAllPoints()
            background:SetPoint("RIGHT", canvas, "TOPRIGHT", -8, -18)
            ui.backgroundButton = background
        end
    end
end

local function Target(ui)
    return ui.highlightSample == "target" or (not ui.highlightSample or ui.highlightSample == "aggro")
        and (ui.targetSample == true or ui.targetSample == nil and ui.sampleKind == "enemy")
end

local function Focus(ui)
    return ui.highlightSample == "focus" or (not ui.highlightSample or ui.highlightSample == "aggro") and ui.focusSample == true
end

local function Quest(ui)
    return not ui.enemyPlayer and (ui.questSample or (ui.previewRole or P.Get(ID, "enemyPreviewRole")) == 5)
end

local function Casting(ui) return ui.castSample ~= nil or ui.castingSample ~= false end
local function Uninterruptible(ui) return ui.castSample == "CastShield" or ui.uninterruptible == true end

local function BuildSampleStates(ui)
    local samples = ui.samples
    ui.targetStateButton = StateButton(ui, samples, "targetSample", "Target", "targetSample", Target)
    ui.focusStateButton = StateButton(ui, samples, "focusSample", "Focus", "focusSample", Focus)
    ui.castingButton = StateButton(ui, samples, "castingSample", "Casting", "castingSample", Casting,
        function(_, on) if not on then ui.uninterruptible = false end end)
    ui.uninterruptibleButton = StateButton(ui, samples, "uninterruptibleSample", "Uninterruptible", "uninterruptible",
        Uninterruptible, function(_, on) if on then ui.castingSample = true end end)
    ui.aggroButton = StateButton(ui, samples, "aggroSample", "Aggro", "aggroSample",
        function() return ui.highlightSample == "aggro" or ui.aggroSample == true end)
    ui.questButton = StateButton(ui, samples, "questSample", "Quest", "questSample", Quest, function(_, on)
        if on then ui.enemyPlayer = false
        elseif (ui.previewRole or P.Get(ID, "enemyPreviewRole")) == 5 then SetType(ui, 1) end
    end)
    ui.raidButton = Toggle(ui, samples, "raidSample", "Raid mark", function(read, on)
        if read then return ui.raidMarked or ui.statusSample == "RaidIcon" end
        SetRaid(ui, on)
    end)
    ui.typeButton = SampleButton(ui, samples, "enemyType", "Type", function(button) OpenType(ui, button) end)
    ui.scenarioButton = SampleButton(ui, samples, "sampleScenario", "Scenario", function(button)
        P.AnchoredContextMenu(button, function(_, menu)
            menu:CreateButton(Tr("Custom"), function() SelectScenario(ui) end)
            for _, scenario in ipairs(SCENARIOS) do
                menu:CreateButton(Tr(scenario.label), function() SelectScenario(ui, scenario) end)
            end
        end)
    end)
    ui.sampleButtons = { ui.targetStateButton, ui.focusStateButton, ui.castingButton, ui.uninterruptibleButton,
        ui.aggroButton, ui.questButton, ui.raidButton, ui.typeButton, ui.scenarioButton,
        ui.softTypeButton, ui.friendlyButtons[1], ui.friendlyButtons[2] }
end

function Tools.Build(ui)
    BuildZoomTools(ui)
    BuildSampleButtons(ui)
    BuildSampleStates(ui)
end

function Tools.BuildSelection(ui)
    local bar = CreateFrame("Frame", nil, ui.canvas, "BackdropTemplate")
    ui.selectedTools = bar
    if H.ApplyPreviewChrome then H.ApplyPreviewChrome(bar, "sidebar", T) end
    bar:SetFrameLevel(ui.canvas:GetFrameLevel() + 25)
    bar:SetPoint("TOPLEFT", ui.samples, "BOTTOMLEFT", 0, -6)
    bar.title = T.Font(bar, "GameFontHighlightSmall", "", T.colors.text)
    bar.title:SetJustifyH("LEFT")
    bar.title:SetWordWrap(false)
    bar.title:SetMaxLines(1)
    bar.title:SetPoint("TOPLEFT", bar, "TOPLEFT", 6, -4)
    local function Action(key, label, callback)
        return SampleButton(ui, bar, key, label, function() callback(Elements.Current(ui)) end)
    end
    bar.settings = Action("selectedSettings", "Settings", function() Elements.OpenSettings(ui) end)
    bar.reset = Action("selectedReset", "Reset", function(_, handle) if handle then ui:ResetHandle(handle) end end)
    bar.eye = Action("selectedVisibility", "Hide", function(def)
        if def then
            ui.inspectedKey = def.key
            Layers.Toggle(ui, def.key)
        end
    end)
    bar.plate = Action("selectedPresence", "Remove", function(def)
        if not def then return end
        local key, on = Elements.Presence(ui, def)
        if key then P.NameplatesElementPanel.SetPresence(ui, def, not on) end
    end)
    bar.buttons = { bar.settings, bar.reset, bar.eye, bar.plate }
    bar:Hide()
end

function Tools.RefreshSelection(ui)
    local bar = ui.selectedTools
    if not bar then return end
    local def, handle = Elements.Current(ui)
    bar:SetShown(not ui.compact and not ui.groupPreviewEnabled and (def ~= nil or handle ~= nil))
    if not bar:IsShown() then return end
    P.SetTranslatedText(bar.title, Tr(Elements.Label(def, handle)))
    bar.reset:SetShown(handle ~= nil and ui:CanMoveHandle(handle))
    local useList = ui.elementPanel:IsShown()
    bar.eye:SetShown(not useList and def ~= nil)
    if bar.eye:IsShown() then P.SetButtonText(bar.eye, Tr(ui:LayerOn(def.key) and "Hide" or "Show")) end
    local key, on
    if def then key, on = Elements.Presence(ui, def) end
    bar.plate:SetShown(not useList and key ~= nil and not def.locked)
    if bar.plate:IsShown() then
        P.SetButtonText(bar.plate, Tr(on and "Remove" or "Add"))
        bar.plate:SetEnabled(Elements.Locked(ui, def) == nil)
    end
end

function Tools.RefreshSamples(ui)
    if not ui.samples then return end
    P.PreviewInteraction.RefreshLayerButton(ui.inactiveButton, ui.showInactive ~= false)
    ui.templatesButton:SetEnabled(Templates.Available(ui))
    local enemy = ui.sampleKind == "enemy" and ui.scope ~= "neutral"
    local friendly = ui.sampleKind == "friendly" and ui.scope ~= "friendlyNpc"
    ui.typeButton:SetShown(enemy)
    ui.questButton:SetShown(enemy)
    ui.aggroButton:SetShown(enemy)
    ui.softTypeButton:SetShown(ui.sampleKind == "enemy")
    for _, button in ipairs(ui.friendlyButtons) do button:SetShown(friendly) end
    local role = P.Suite.NameplateStyle.Roles[ui.previewRole or P.Get(ID, "enemyPreviewRole")]
    local typeName = ui.enemyPlayer and "Player" or ui.questSample and "Quest" or role and role.label
    P.SetButtonText(ui.typeButton, typeName and Tr("Type: %s"):format(Tr(typeName)) or Tr("Type"))
    P.SetButtonText(ui.scenarioButton, Tr("Scenario: %s"):format(Tr(ui.sampleScenario and ui.sampleScenario.label or "Custom")))
    local states = { Target(ui), Focus(ui), Casting(ui), Uninterruptible(ui),
        ui.highlightSample == "aggro" or ui.aggroSample == true, Quest(ui), ui.raidMarked or ui.statusSample == "RaidIcon" }
    for index = 1, 7 do P.PreviewInteraction.RefreshLayerButton(ui.sampleButtons[index], states[index] == true) end
end

function Tools.BuildRaidPalette(ui)
    local strip = CreateFrame("Frame", nil, ui.canvas)
    ui.raidPalette = strip
    strip:SetPoint("TOPRIGHT", ui.canvas, "TOPRIGHT", -8, -39)
    strip:SetSize(165, 22)
    local title = T.Font(strip, "GameFontDisableSmall", "RAID MARKS", T.colors.muted)
    title:SetPoint("BOTTOMRIGHT", strip, "TOPRIGHT", 0, 1)
    ui.raidChoices = {}
    for index = 1, 8 do
        local button = CreateFrame("Button", nil, strip)
        button:SetSize(18, 18)
        button:SetPoint("LEFT", strip, "LEFT", (index - 1) * 21, 0)
        button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        button.index = index
        local icon = button:CreateTexture(nil, "ARTWORK")
        icon:SetAllPoints(button)
        icon:SetTexture("Interface\\TargetingFrame\\UI-RaidTargetingIcon_" .. index)
        local border = P.Suite.NameplateStyle.CreateBorder(button)
        button.outline = function(size, color)
            P.Suite.NameplateStyle.PaintBorder(border, button, size, color)
        end
        button:SetScript("OnClick", function(_, mouseButton)
            if P.Combat() then return end
            if mouseButton == "RightButton" or not ui:LayerAvailable("raidIcon") then
                Layers.Focus(ui, "elements", "raidIcon")
                return
            end
            BeginCustomSample(ui)
            SetRaid(ui, not (ui.raidMarked and ui.raidIndex == index))
            ui.raidIndex = index
            ui:Paint()
        end)
        button:SetScript("OnEnter", function()
            P.SetTranslatedText(ui.hint, Tr("Raid mark: %s"):format(Tr(RAID_MARK_NAMES[index])) .. " - "
                .. Tr("Click to preview; right-click for settings"))
        end)
        button:SetScript("OnLeave", function() P.SetTranslatedText(ui.hint, ui.help) end)
        Register(button, "raidMark." .. index, Tr("Raid mark: %s"):format(Tr(RAID_MARK_NAMES[index])))
        ui.raidChoices[index] = button
    end
end


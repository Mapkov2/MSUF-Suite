local _, P = ...
-- Selection feedback belongs to the preview, never to the saved settings.
-- Navigation previews share a small selection bar; movable previews retain
-- the host's exact X/Y bar and its existing keyboard/drag ownership.
local Interaction = {}
P.PreviewInteraction = Interaction
local T, Tr, HM = P.T, P.Tr, P.HM
local WHITE = "Interface\\Buttons\\WHITE8X8"
local HINT = "Click an element to open its settings."
local MOVE_HINT = "Drag or use arrows to move; click for settings."

function Interaction.Outline(handle, selected, thickness)
    if not handle then return end
    thickness = thickness or 2
    local edges = handle._suitePreviewSelectionEdges
    if not edges and not selected then return end
    if not edges then
        edges = {}
        for index = 1, 4 do
            local edge = handle:CreateTexture(nil, "OVERLAY")
            edge:SetTexture(WHITE)
            if index <= 2 then
                local point = index == 1 and "TOP" or "BOTTOM"
                edge:SetPoint(point .. "LEFT", handle, point .. "LEFT")
                edge:SetPoint(point .. "RIGHT", handle, point .. "RIGHT")
                edge:SetHeight(2)
            else
                local point = index == 3 and "LEFT" or "RIGHT"
                edge:SetPoint("TOP" .. point, handle, "TOP" .. point)
                edge:SetPoint("BOTTOM" .. point, handle, "BOTTOM" .. point)
                edge:SetWidth(2)
            end
            edges[index] = edge
        end
        handle._suitePreviewSelectionEdges = edges
    end
    local color = T.colors.accent or T.colors.coreGlow or T.colors.text
    if edges.selected == selected and edges.r == color[1] and edges.g == color[2] and edges.b == color[3] and edges.thickness == thickness then return end
    edges.selected, edges.r, edges.g, edges.b = selected, color[1], color[2], color[3]
    edges.thickness = thickness
    for index, edge in ipairs(edges) do
        if index <= 2 then edge:SetHeight(thickness) else edge:SetWidth(thickness) end
        edge:SetColorTexture(color[1], color[2], color[3], 1)
        edge:SetShown(selected == true)
    end
end

-- The Suite's preview kit (MSUF_Suite/Core/PreviewKit.lua) with this menu's
-- host helpers wired in: secure arrow bindings (opts.bindings), keyboard
-- capture, the duplicate-key filter and the moved cue. The kit itself names
-- none of them, so an older host without a helper just loses that helper.
-- Arrow steps stay Shift 5 and Ctrl 10 in every Suite preview.
local STEPS = { shift = 5, ctrl = 10 }
local SELECTED = { selectedField = "_selectedHandle" }
function Interaction.Handles(host, opts)
    local helpers = P.M.PreviewHelpers or {}
    opts.steps, opts.combat = opts.steps or STEPS, opts.combat or P.Combat
    opts.dedupe = opts.dedupe or helpers.ShouldSkipDuplicateNudge
    opts.moved = opts.moved or helpers.NotePreviewElementMoved
    opts.focus = opts.focus or function(owner, region, active)
        if P.M.SetPreviewArrowBindings then P.M.SetPreviewArrowBindings(owner, active, opts.bindings) end
        if active and helpers.FocusKeyboardTarget then helpers.FocusKeyboardTarget(owner, region, false, SELECTED)
        elseif not active and helpers.ReleaseKeyboardCapture then helpers.ReleaseKeyboardCapture(owner) end
    end
    local controller = P.Suite.PreviewKit.Handles(host, opts)
    -- rekey: the host's own arrow handler, which gives the keyboard back after a nudge.
    if opts.rekey and helpers.ArrowKeyDown then
        local spec = { owner = function() return controller.owner end, selectedField = "_selectedHandle",
            nudge = function(_, dx, dy) return controller:Arrow(dx, dy) end }
        opts.keydown = function(frame, key) return helpers.ArrowKeyDown(frame, key, spec) end
    end
    return controller
end

function Interaction.SetHint(label, selectedLabel, movable)
    local hint = movable and MOVE_HINT or HINT
    P.SetTranslatedText(label, selectedLabel and Tr("%s - %s"):format(Tr(selectedLabel), Tr(hint)) or Tr(hint))
end

function Interaction.Refresh(bar)
    local target = bar._suitePreviewTarget
    if target and not target:IsShown() then
        Interaction.Outline(target, false)
        bar._suitePreviewTarget, bar._suitePreviewOpen, bar._suitePreviewLabel = nil, nil, nil
        target = nil
    end
    P.SetTranslatedText(bar.label, Tr(bar._suitePreviewLabel or bar.hint or HINT))
    bar.button:SetEnabled(target ~= nil)
    bar.button:SetAlpha(target and 1 or .45)
    -- Thickness 0 names the selection in the bar without outlining it.
    if target then Interaction.Outline(target, bar._suitePreviewThickness ~= 0, bar._suitePreviewThickness) end
end

function Interaction.Select(bar, handle, label, open, thickness)
    if not bar then return end
    if bar._suitePreviewTarget ~= handle then Interaction.Outline(bar._suitePreviewTarget, false) end
    bar._suitePreviewTarget, bar._suitePreviewOpen, bar._suitePreviewLabel, bar._suitePreviewThickness = handle, open, label, thickness
    Interaction.Refresh(bar)
end

function Interaction.SizeBar(bar, width)
    width = math.max(24, width)
    bar:SetSize(width, 24)
    local buttonWidth = math.min(width - 12, bar.preferredButtonWidth)
    bar.button:SetWidth(buttonWidth)
    bar.label:SetWidth(math.max(20, width - buttonWidth - 28))
    bar.label:SetShown(width - buttonWidth >= 68)
end

function Interaction.Bar(ctx, parent, width, help)
    local bar = CreateFrame("Frame", nil, parent)
    bar:EnableMouse(true)
    local chrome = P.M.PreviewHelpers
    if chrome and chrome.ApplyPreviewChrome then chrome.ApplyPreviewChrome(bar, "sidebar", T) end
    bar.label = T.Font(bar, "GameFontHighlightSmall", "Open settings", T.colors.muted, "supporting")
    bar.preferredButtonWidth = math.max(100, math.ceil(bar.label:GetUnboundedStringWidth() + 28))
    bar.label:SetPoint("LEFT", bar, "LEFT", 8, 0)
    bar.label:SetWordWrap(false)
    bar.button = T.Button(bar, "Open settings", bar.preferredButtonWidth, 18)
    bar.button:SetPoint("RIGHT", bar, "RIGHT", -6, 0)
    Interaction.SizeBar(bar, width)
    HM.SkipHistoryCheckpoint(bar.button)
    HM.AllowCombatClick(bar.button)
    bar.button:SetScript("OnClick", function()
        if bar._suitePreviewTarget and bar._suitePreviewTarget:IsShown() and bar._suitePreviewOpen then bar._suitePreviewOpen() end
    end)
    if P.M.AddTooltip then
        P.M.AddTooltip(bar, "Preview", help or HINT, { hook = true })
        P.M.AddTooltip(bar.button, "Open settings", help or HINT, { hook = true })
    end
    bar:SetScript("OnHide", function() Interaction.Outline(bar._suitePreviewTarget, false) end)
    bar:SetScript("OnShow", function() Interaction.Refresh(bar) end)
    P.M.TrackRefresh(ctx, function() if bar:IsVisible() then Interaction.Refresh(bar) end end)
    Interaction.Refresh(bar)
    return bar
end

local LAYER_TITLE_COLOR = { 0.94, 0.81, 0.47, 1 }
local LAYER_BACKDROP = { bgFile = WHITE, edgeFile = WHITE, edgeSize = 1 }
function Interaction.LayerRailTitle(rail)
    local helpers = P.M.PreviewHelpers
    if helpers and helpers.ApplyPreviewLayerRail then
        helpers.ApplyPreviewLayerRail(rail)
    elseif rail.SetBackdrop then
        rail:SetBackdrop(LAYER_BACKDROP)
        rail:SetBackdropColor(0.04, 0.06, 0.09, 0.96)
        rail:SetBackdropBorderColor(0.62, 0.60, 0.50, 1)
    end
    return T.Font(rail, "GameFontDisableSmall", "Preview Layers", T.colors.previewLayerTitle or LAYER_TITLE_COLOR, "card")
end

function Interaction.BindLayerClick(button, toggle, open, blocked)
    button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    button:SetScript("OnClick", function(_, mouse)
        local setting = blocked and blocked()
        if mouse == "RightButton" or setting then return not P.Combat() and open(setting) end
        return toggle()
    end)
    if blocked and P.M.AddTooltip then
        P.M.AddTooltip(button, "Open settings", nil, { hook = true, enabled = function() return blocked() ~= nil end })
    end
end

-- The availability callback returns the setting that keeps a layer off.
function Interaction.BuildLayerRail(owner, parent, specs, toggle, open, blocked)
    local chips = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    owner.chips, owner.layerButtons = chips, {}
    local H = P.M.PreviewHelpers or {}
    local title = Interaction.LayerRailTitle(chips)
    title:SetPoint("TOPLEFT", chips, "TOPLEFT", 10, -5)
    local measure = T.Font(chips, "GameFontDisableSmall", "", T.colors.muted)
    measure:Hide()
    local opts
    if H.LayerChipButtonOpts then
        opts = H.LayerChipButtonOpts(Tr, T.colors, H.PreviewChromePalette(T), {
            IsOn = function(ui, key) return ui.layers[key] ~= false end,
            IsAvailable = function(_, key) return not (blocked and blocked(key)) end,
        })
    end
    for index, spec in ipairs(specs) do
        local key, label, button = spec[1], spec[2]
        if H.CreateLayerButton and opts then
            button = H.CreateLayerButton(chips, owner, { key = key, label = label, color = { .30, .74, 1 } }, index, 95, opts)
        else
            P.SetTranslatedText(measure, Tr(label))
            button = T.Button(chips, label, math.max(64, measure:GetUnboundedStringWidth() + 30), 20)
            button.key = key
        end
        local check = blocked and function() return blocked(key) end
        button._suiteLayerBlocked = check
        Interaction.BindLayerClick(button, function() return toggle(key, owner.layers[key] == false) end,
            function(setting) return open(spec, setting) end, check)
        HM.SkipHistoryCheckpoint(button)
        HM.SetCommandAction(button, { kind = "toggle", historyMode = "none",
            get = function() return owner.layers[key] ~= false end,
            set = function(value) return toggle(key, value == true) end })
        owner.layerButtons[index] = button
    end
end

function Interaction.LayoutLayerRail(owner, width)
    local chips, x, row = owner.chips, 10, 0
    for _, button in ipairs(owner.layerButtons) do
        button._suiteLayerWidth = button._suiteLayerWidth or button:GetWidth()
        local size = math.min(math.max(1, width - 20), button._suiteLayerWidth)
        if button:GetWidth() ~= size then
            button:SetWidth(size)
            if button.fs then
                button.fs:SetPoint("RIGHT", button, "RIGHT", -5, 0)
                button.fs:SetWordWrap(false)
            end
        end
        if x > 10 and x + size > width - 10 then x, row = 10, row + 1 end
        button:ClearAllPoints()
        button:SetPoint("TOPLEFT", chips, "TOPLEFT", x, -25 - row * 24)
        x = x + size + 5
    end
    chips:SetSize(width, 50 + row * 24)
end

function Interaction.RefreshLayerRail(owner)
    for _, button in ipairs(owner.layerButtons) do
        if button.Refresh then button:Refresh()
        else
            local blocked = button._suiteLayerBlocked and button._suiteLayerBlocked()
            button:SetAlpha((blocked or owner.layers[button.key] == false) and .42 or 1)
        end
    end
end

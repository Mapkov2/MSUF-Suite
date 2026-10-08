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
    P.SetTranslatedText(bar.label, Tr(bar._suitePreviewLabel or HINT))
    bar.button:SetEnabled(target ~= nil)
    bar.button:SetAlpha(target and 1 or .45)
    if target then Interaction.Outline(target, true, bar._suitePreviewThickness) end
end

function Interaction.Select(bar, handle, label, open, thickness)
    if not bar then return end
    if bar._suitePreviewTarget ~= handle then Interaction.Outline(bar._suitePreviewTarget, false) end
    bar._suitePreviewTarget, bar._suitePreviewOpen, bar._suitePreviewLabel, bar._suitePreviewThickness = handle, open, label, thickness
    Interaction.Refresh(bar)
end

function Interaction.Bar(ctx, parent, width, help)
    local bar = CreateFrame("Frame", nil, parent)
    width = math.max(24, width)
    bar:SetSize(width, 24)
    bar:EnableMouse(true)
    local chrome = P.M.PreviewHelpers
    if chrome and chrome.ApplyPreviewChrome then chrome.ApplyPreviewChrome(bar, "sidebar", T) end
    bar.label = T.Font(bar, "GameFontHighlightSmall", "Open settings", T.colors.muted, "supporting")
    local buttonWidth = math.min(width - 12, math.max(100, math.ceil(bar.label:GetUnboundedStringWidth() + 28)))
    bar.label:SetPoint("LEFT", bar, "LEFT", 8, 0)
    bar.label:SetWidth(math.max(20, width - buttonWidth - 28))
    bar.label:SetWordWrap(false)
    bar.label:SetShown(width - buttonWidth >= 68)
    bar.button = T.Button(bar, "Open settings", buttonWidth, 18)
    bar.button:SetPoint("RIGHT", bar, "RIGHT", -6, 0)
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

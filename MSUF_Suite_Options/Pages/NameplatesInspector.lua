local _, P = ...
-- The inspector explains where the selected element is visible. The canvas
-- toolbar and the Elements list own the usual editing actions.
local M, T, Tr, HM = P.M, P.T, P.Tr, P.HM
local Elements, Layers = P.NameplatesElements, P.NameplatesEditorLayers
local Inspector = {}
P.NameplatesInspector = Inspector
local PAD, FACTS_TOP, GAP = 12, 52, 10
local SNAP_HELP = "Drag to move it. It snaps to the edges and centers of the other elements; hold Alt to place it freely."
local PAN_HELP = "Ctrl+wheel zooms. Drag the empty canvas to pan."

local Current = Elements.Current

local function Describe(ui, def, handle)
    local lines = {}
    if not def then return lines, false end
    local key, on = Elements.Presence(ui, def)
    local locked = Elements.Locked(ui, def)
    local layerOn = ui:LayerOn(def.key)
    local inactive = on ~= false and layerOn and (not ui:LayerActive(def.key) or handle and not handle:IsVisible())
    if on == false then
        lines[#lines + 1] = Tr("Not on your nameplates. Its settings are kept.")
    elseif not layerOn then
        lines[#lines + 1] = Tr(on and "Hidden in the preview only. Your nameplates still show it." or "Hidden")
    elseif inactive then
        lines[#lines + 1] = Tr("Not shown in this sample.")
    end
    if not key and def.presence then
        lines[#lines + 1] = Tr("A Blizzard setting decides whether it shows. Its settings can take over.")
    end
    if type(locked) == "string" then lines[#lines + 1] = locked end
    local canReveal = inactive and (def.context or def.status or def.highlight) and not Layers.Blocked(ui, def.key)
    return lines, canReveal == true
end

function Inspector.Build(ui)
    local inspector = CreateFrame("Frame", nil, ui.body, "BackdropTemplate")
    ui.inspector = inspector
    local chrome = M.PreviewHelpers
    if chrome and chrome.ApplyPreviewChrome then chrome.ApplyPreviewChrome(inspector, "sidebar", T) end
    inspector.swatch = inspector:CreateTexture(nil, "ARTWORK")
    inspector.swatch:SetSize(10, 10)
    inspector.swatch:SetPoint("TOPLEFT", inspector, "TOPLEFT", PAD, -14)
    inspector.title = T.Font(inspector, "GameFontNormal", "", T.colors.text, "card")
    inspector.title:SetPoint("TOPLEFT", inspector, "TOPLEFT", PAD + 16, -11)
    inspector.title:SetJustifyH("LEFT")
    inspector.title:SetWordWrap(false)
    inspector.group = T.Font(inspector, "GameFontDisableSmall", "", T.colors.muted)
    inspector.group:SetPoint("TOPLEFT", inspector.title, "BOTTOMLEFT", 0, -3)
    inspector.facts = T.Font(inspector, "GameFontHighlightSmall", "", T.colors.text)
    inspector.facts:SetPoint("TOPLEFT", inspector, "TOPLEFT", PAD, -FACTS_TOP)
    inspector.facts:SetJustifyH("LEFT")
    inspector.facts:SetSpacing(3)
    inspector.show = T.Button(inspector, "Show in the preview", 120, 22)
    HM.SkipHistoryCheckpoint(inspector.show)
    inspector.show:SetScript("OnClick", function()
        if P.Combat() then return end
        local def, handle = Current(ui)
        local _, canReveal = Describe(ui, def, handle)
        if canReveal then Elements.Inspect(ui, def, true) end
    end)
    inspector.show:Hide()
    return inspector
end

local function ShowEmpty(inspector)
    inspector.swatch:Hide()
    P.SetTranslatedText(inspector.title, Tr("No element selected"))
    inspector.group:SetText("")
    inspector.facts:SetText(Tr(SNAP_HELP) .. "\n\n" .. Tr(PAN_HELP))
    inspector.show:Hide()
end

function Inspector.Refresh(ui)
    local inspector = ui.inspector
    if not inspector or not inspector:IsShown() then return end
    local width = (inspector:GetWidth() or 0) - 2 * PAD
    if width < 40 then return end
    inspector.title:SetWidth(width - 16)
    inspector.facts:SetWidth(width)
    local def, handle = Current(ui)
    if not def and not handle then return ShowEmpty(inspector) end
    local layer = def and Layers.Def(def.key)
    local color = layer and layer.color or { 0.3, 0.74, 1 }
    inspector.swatch:SetColorTexture(color[1], color[2], color[3], 1)
    inspector.swatch:Show()
    P.SetTranslatedText(inspector.title, Tr(Elements.Label(def, handle)))
    local group = def and Elements.GROUP_TITLE[def.group]
    P.SetTranslatedText(inspector.group, group and Tr(group) or "")
    local lines, canReveal = Describe(ui, def, handle)
    inspector.facts:SetText(table.concat(lines, "\n"))
    inspector.show:SetShown(canReveal)
    if canReveal then
        inspector.show:ClearAllPoints()
        inspector.show:SetPoint("TOPLEFT", inspector, "TOPLEFT", PAD, -(FACTS_TOP + inspector.facts:GetStringHeight() + GAP))
        inspector.show:SetWidth(width)
    end
end

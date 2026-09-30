local _, P = ...
local M, W, SB = P.M, P.W, P.M.PreviewSelectionBar
local Layout = {}
P.NameplatesPreviewLayout = Layout

function Layout.Apply(self)
    local body, canvas, tools, rail = self.body, self.canvas, self.tools, self.layerRail
    canvas:ClearAllPoints()
    canvas:SetPoint("TOPLEFT", body, "TOPLEFT", 0, 0)
    tools:SetShown(not self.compact)
    if SB then SB.SetShown(body, not self.compact) end
    rail:SetShown(not self.compact)
    self.samples:SetShown(not self.compact)
    self.raidPalette:SetShown(not self.compact)
    self.hint:SetShown(not self.compact)
    if self.compact then
        canvas:SetPoint("BOTTOMRIGHT", body, "BOTTOMRIGHT", 0, 8)
        return
    end
    self:LayoutLayerRail()
    -- Anchor each row above the actual wrapped rail, leaving all remaining
    -- height to the canvas. Width changes therefore need no guessed row count.
    local anchor = rail
    if self.selection then
        self.selection:ClearAllPoints()
        self.selection:SetPoint("BOTTOMLEFT", rail, "TOPLEFT", 0, 6)
        self.selection:SetPoint("BOTTOMRIGHT", rail, "TOPRIGHT", 0, 6)
        anchor = self.selection
    end
    tools:ClearAllPoints()
    tools:SetPoint("BOTTOMLEFT", anchor, "TOPLEFT", 0, 5)
    tools:SetPoint("BOTTOMRIGHT", anchor, "TOPRIGHT", 0, 5)
    canvas:SetPoint("BOTTOMRIGHT", tools, "TOPRIGHT", 0, 4)
end

function Layout.Attach(ui, section, toolbar, record)
    local body, ctx = ui.body, ui.ctx
    local function Refresh()
        ui:Layout()
        ui:Paint()
    end
    body.Refresh = Refresh
    function body:ApplyCompactPreviewPresentation(compact)
        ui:CancelDrag()
        ui:Select(nil)
        ui.compact = compact == true
        Refresh()
    end
    -- Use the same page ownership lifecycle as UF/GF. The fixed section owns
    -- the header anchor; scrolling only moves the settings wrapper below it.
    if W.AttachPinnedPreview then
        W.AttachPinnedPreview(section, body, { stateKey = "nameplatePreview",
            pageKey = ctx.key, wrapper = ctx.wrapper })
    end
    local expander
    if W.AttachFixedPreviewExpander then
        expander = W.AttachFixedPreviewExpander(section, toolbar, body, {
            pageKey = ctx.key, wrapper = ctx.wrapper,
            compactHeight = 116, compactTop = -38,
            expandedHeight = 370, expandedTop = -38, expandedSectionHeight = 416,
            refreshPreview = Refresh,
        })
    end
    if expander and expander.button then
        ui.hint:ClearAllPoints()
        ui.hint:SetPoint("LEFT", section.title or toolbar, section.title and "RIGHT" or "LEFT", section.title and 12 or 160, 0)
        ui.hint:SetPoint("RIGHT", expander.button, "LEFT", -8, 0)
    end
    -- FixedPreviewSection reserves the compact height on construction. The
    -- expander registers controls but does not initialize their presentation.
    -- Initialize before activation even if another page selected Compact.
    body:ApplyCompactPreviewPresentation(true)
    body:SetScript("OnSizeChanged", Refresh)
    body:SetScript("OnShow", Refresh)
    if record then
        record.onActivate = function()
            if expander and M.ShouldExpandFixedPreview and M.ShouldExpandFixedPreview() then
                if expander.expanded then expander:Relayout("NAMEPLATES_PREVIEW")
                else expander:Open("NAMEPLATES_PREVIEW") end
            end
            Refresh()
        end
    end
end

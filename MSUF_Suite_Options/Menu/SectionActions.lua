local _, P = ...
local M, W, T, Tr = P.M, P.W, P.T, P.Tr
local Controller = P.Suite.Client

-- The "..." button in a Suite section header and its popup: Reset section,
-- plus Copy section where the page offers one (P.AttachSectionReset).
-- Same header action pattern as the GF/UF accordions. The color shortcut in
-- the body remains available for color sections.
-- copy (optional) adds "Copy section" below the reset, like the UF/GF popup:
--   source() -> id, sourceLabel(id) -> text, targets(id) -> dropdown items,
--   run(source, target) -> ok, label: dropdown title,
--   targetOff(id) -> true keeps a switched-off target listed but locked (offLabel).
local function OffTargetText(text, label)
    text = text .. " - " .. Tr(label or "Disabled")
    local c = T.colors and T.colors.danger
    if not c then return text end
    return ("|cff%02x%02x%02x%s|r"):format(math.floor(c[1] * 255 + 0.5), math.floor(c[2] * 255 + 0.5),
        math.floor(c[3] * 255 + 0.5), text)
end
-- The "..." button in a section header; the feature switch moves left of it.
local function SectionActionButton(ctx, entry)
    local more = W.TopButton(entry.header, "...", 24, 22)
    if W.StyleSectionActionButton then W.StyleSectionActionButton(more) end
    more:SetPoint("RIGHT", entry.header, "RIGHT", -10, 0)
    more:SetFrameLevel(entry.header:GetFrameLevel() + 4)
    more._msuf2SkipHistoryCheckpoint = true
    entry._msuf2SectionActions = more
    entry._msufSuiteResetButton = more
    entry._msuf2ActionReserve = 34
    if not entry._msuf2UXSummary then
        entry._msuf2ColorSwatchReserve = (entry._msuf2ColorSwatchReserve or 0) + 34
    end
    local function AlignSwitch()
        if entry.featureSwitch then
            entry.featureSwitch:ClearAllPoints()
            entry.featureSwitch:SetPoint("RIGHT", entry.header, "RIGHT", -48, 0)
        end
    end
    AlignSwitch()
    if ctx and M.TrackRefresh then M.TrackRefresh(ctx, AlignSwitch) end
    if entry._msuf2RefreshLayout then entry._msuf2RefreshLayout() end
    return more
end

-- A section's popup state: body, title, header entry, "..." button, the
-- popup once built and the copy source fixed when it opened.
local function ClosePopup(state)
    if state.popup then state.popup:Hide() end
end

local function ShowFeedback(ok, done)
    if M.ShowStatusFeedback then M.ShowStatusFeedback(Tr(ok and done or "Action failed"), ok and "ok" or "danger", 1.5) end
end

-- The source is fixed when the popup opens; Copy refuses once it changed.
local function CopySection(state, target)
    local spec = state.body._msufSuiteSectionCopy
    if P.Combat() or not (spec and target) then return false end
    local source = state.source
    local ok = spec.source() == source and target ~= source
        and not (spec.targetOff and spec.targetOff(target))
        and spec.run(source, target) == true
    ShowFeedback(ok, "Section copied")
    ClosePopup(state)
    return ok
end

-- The destination defaults to the first target that is switched on; with
-- every target off the first one shows marked and Copy locks.
local function RefreshCopyTargets(state, select, copyButton)
    local current = state.body._msufSuiteSectionCopy
    local choices, first = {}, nil
    for _, item in ipairs(current.targets(state.source)) do
        if current.targetOff and current.targetOff(item.value) then
            item = { value = item.value, text = OffTargetText(item.text, current.offLabel),
                translate = false, disabled = true }
        elseif first == nil then
            first = item.value
        end
        choices[#choices + 1] = item
    end
    state.popup.destination = first
    select:SetValues(choices)
    select:SetValue(first or (choices[1] and choices[1].value))
    W.SetControlEnabled(copyButton, first ~= nil)
end

-- "Copy section": the destination dropdown and its button.
local function BuildCopyRow(state, spec)
    local popup = state.popup
    local select = W.Dropdown(popup, Tr(spec.label or "Copy to"), {}, 250)
    W.MoveWidget(select, popup, 14, -76, 250)
    select:SetOnValueChanged(function(value) popup.destination = value end)
    local copyButton = W.TopButton(popup, Tr("Copy section"), 250, 24)
    copyButton:SetPoint("TOPLEFT", popup, "TOPLEFT", 14, -132)
    copyButton:SetScript("OnClick", function() CopySection(state, popup.destination) end)
    popup:SetHeight(174)
    popup.RefreshTargets = function() RefreshCopyTargets(state, select, copyButton) end
    popup._msufSuiteCopySection = function(target) return CopySection(state, target) end
end

local function BuildSectionPopup(state, spec)
    local popup = M.CreateMenuPopupPanel(_G.UIParent)
    state.popup = popup
    popup:SetClampedToScreen(true)
    popup:SetSize(288, 82)
    local heading = T.Font(popup, "GameFontHighlight", Tr(state.title), T.colors.text)
    heading:SetPoint("TOPLEFT", popup, "TOPLEFT", 14, -12)
    heading:SetWidth(242)
    heading:SetWordWrap(false)
    popup.heading = heading
    local close = W.TopButton(popup, "x", 20, 20)
    close:SetPoint("TOPRIGHT", popup, "TOPRIGHT", -6, -6)
    close:SetScript("OnClick", function() ClosePopup(state) end)
    if spec and W.Dropdown and W.MoveWidget then BuildCopyRow(state, spec) end
    local button = W.TopButton(popup, Tr("Reset section"), 250, 24)
    button:SetPoint("TOPLEFT", popup, "TOPLEFT", 14, -42)
    button:SetScript("OnClick", function()
        if P.Combat() then return end
        ShowFeedback(state.body._msufSuiteSectionReset(), "Section reset")
        ClosePopup(state)
    end)
    popup._msuf2ResetSection = function() return state.body._msufSuiteSectionReset() end
    state.entry.outer:HookScript("OnHide", function() ClosePopup(state) end)
    Controller.AttachControllerWindow(popup)
    if Controller.isForever then
        popup.SmartNavigationCloseHandler = function() ClosePopup(state); return true end
    end
end

local function ToggleSectionPopup(state)
    if P.Combat() then return end
    local popup = state.popup
    if popup and popup:IsShown() then
        ClosePopup(state)
        return
    end
    local spec = state.body._msufSuiteSectionCopy
    state.source = spec and spec.source() or nil
    if not popup then
        BuildSectionPopup(state, spec)
        popup = state.popup
    end
    if popup.RefreshTargets then popup.RefreshTargets() end
    local title = Tr(state.title)
    popup.heading:SetText(state.source ~= nil and (spec.sourceLabel(state.source) .. " \194\183 " .. title) or title)
    popup:ClearAllPoints()
    popup:SetPoint("TOPRIGHT", state.more, "BOTTOMRIGHT", 0, -4)
    if M.ApplyPopupFramePriority then M.ApplyPopupFramePriority(popup) end
    popup:Show()
    Controller.ResumeControllerWindow(popup)
    Controller.RaiseControllerCursor()
end

function P.AttachSectionReset(ctx, body, title, reset, copy)
    if not body or type(reset) ~= "function" then return end
    body._msufSuiteSectionReset, body._msufSuiteSectionCopy = reset, copy
    local entry = body._msuf2CollapsibleEntry
    if not (entry and entry.header and W.TopButton and M.CreateMenuPopupPanel) then return end
    if entry._msufSuiteResetButton then return entry._msufSuiteResetButton end
    local more = SectionActionButton(ctx, entry)
    local state = { body = body, title = title, entry = entry, more = more }
    more:SetScript("OnClick", function() ToggleSectionPopup(state) end)
    more._msuf2GetSectionPopup = function() return state.popup end
    if M.AddTooltip then M.AddTooltip(more, "Section actions", nil, { hook = true }) end
    return more
end

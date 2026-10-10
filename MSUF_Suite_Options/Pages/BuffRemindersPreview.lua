local _, P = ...
local S, M, Tr = P.S, P.M, P.Tr
local ADDON = "MSUF_Suite_BuffReminders"
local loadFailure
-- The LoD addon registers its renderer without enabling the module. Its
-- ordinary menu buttons never cast spells or borrow the secure live host.
local function EnsureRuntime()
    if S.BuffRemindersDrawPreview then return true end
    if loadFailure or P.Combat() then return false end
    local loaded, reason = C_AddOns.LoadAddOn(ADDON)
    if not S.BuffRemindersDrawPreview then
        loadFailure = P.Suite.Client.LoadReasonText(reason or loaded, Tr("not installed"))
    end
    return S.BuffRemindersDrawPreview ~= nil
end

local EVENTS = { "BAG_UPDATE_DELAYED", "SPELLS_CHANGED", "PLAYER_SPECIALIZATION_CHANGED",
    "PLAYER_EQUIPMENT_CHANGED", "GROUP_ROSTER_UPDATE", "PLAYER_ENTERING_WORLD",
    "ZONE_CHANGED_NEW_AREA", "ZONE_CHANGED", "ZONE_CHANGED_INDOORS", "ITEM_DATA_LOAD_RESULT",
    "PLAYER_REGEN_ENABLED" }

function P.MenuSamples.Reminders(ui)
    if not ui then return end
    local width = ui.width - 54
    local title = P.Text(ui.header, "Preview", 16, -52, width)
    local viewport = CreateFrame("ScrollFrame", nil, ui.header, "ScrollFrameTemplate")
    viewport.ScrollBar:SetHideIfUnscrollable(true)
    viewport:SetPoint("TOPLEFT", 16, -76)
    viewport:SetSize(width, 76)
    local stage = CreateFrame("Frame", nil, viewport)
    stage:SetSize(width, 76)
    viewport:SetScrollChild(stage)
    local status = P.Text(viewport, "", 0, 0, width)
    local footer = P.Text(ui.header, "Sample values. Click an element to open its settings.", 16, -160, width)
    local dirty = true
    local function Refresh()
        if not viewport:IsVisible() then return end
        local height = 76
        if EnsureRuntime() then
            local w, h, count = S.BuffRemindersDrawPreview(stage, S.Config("buffReminders"), dirty,
                function() ui:Focus("suite_buffReminders_appearance") end)
            dirty = false
            -- Match the live UIParent size despite the menu's own scale. Only
            -- a row wider than the panel is fitted; its scale stays explicit.
            local nativeScale = UIParent:GetEffectiveScale() / viewport:GetEffectiveScale()
            local fit = math.min(1, width / (w * nativeScale))
            stage:SetScale(nativeScale * fit)
            height = math.min(180, math.max(38, h * nativeScale * fit))
            P.SetTranslatedText(title, fit < .995 and Tr("Preview %d%%"):format(math.floor(fit * 100 + .5)) or Tr("Preview"))
            P.SetTranslatedText(status, count == 0 and Tr("No reminders are configured for this character.") or "")
        else
            P.SetTranslatedText(status, loadFailure and Tr("Cannot load %s: %s"):format(Tr("Buff reminders"), loadFailure)
                or Tr("Preview is available outside combat."))
        end
        viewport:SetHeight(height)
        footer:ClearAllPoints()
        footer:SetPoint("TOPLEFT", ui.header, "TOPLEFT", 16, -84 - height)
        P.MenuWorkspace.FitHeader(ui, 100 + height + math.ceil(footer:GetStringHeight() or 14))
    end
    local function Activate()
        dirty = true
        for _, event in ipairs(EVENTS) do viewport:RegisterEvent(event) end
        Refresh()
    end
    viewport:SetScript("OnShow", Activate)
    viewport:SetScript("OnHide", function()
        viewport:UnregisterAllEvents()
        if S.BuffRemindersReleasePreview then S.BuffRemindersReleasePreview(stage) end
    end)
    viewport:SetScript("OnEvent", function() dirty = true
        M.RequestRefresh(ui.ctx, "suite-buff-preview") end)
    ui.reminderPreview = { stage = stage, viewport = viewport, title = title, status = status }
    ui.refreshPreview = Refresh
    M.TrackRefresh(ui.ctx, Refresh)
    if viewport:IsVisible() then Activate() end
end

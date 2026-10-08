local _, Private = ...
local NS, O = Private.NS, Private.Options
local L = NS.L

-- Profile switches, creation and import activate another profile, so a
-- successful one drops the undo step instead of recording one (and
-- ClearHistory repaints the options once); a refused one (combat, invalid
-- name, bad import) keeps it. Only a confirmed replacement by an import
-- records a step: the replaced profile (ReplaceProfile below).
local function Replaced(ok, ...)
    if ok then O.ClearHistory() end
    return ok, ...
end

-- Readable text for a refusal met in normal play; other reasons show as the
-- engine reports them.
local REFUSAL_TEXT = {
    combat = L["Profiles can only change outside combat."],
}

-- How long a two-click confirmation (delete, import replace) stays armed.
local ARM_SECONDS = 5

local function BuildProfileControls(page, view)
    local names = view.names
    -- A switch reports its outcome on the page like every profile action; a
    -- click refused in combat does too.
    local active = O.CreateCycle(page, L["Active profile"], names, function()
        return NS.Database.GetActiveProfileName()
    end, function(value)
        local ok, reason = Replaced(NS.Database.SetActiveProfile(value))
        view.Result(ok, reason, ok and L["Active: %s"]:format(reason) or nil)
    end, 520, nil, { history = false, refused = view.Refused })
    active:SetPoint("TOPLEFT", 4, -70)

    local nameRow = O.CreateInput(page, L["Profile name"], function() return view.draftName end,
        function(value) view.draftName = value end, 520, { history = false })
    nameRow:SetPoint("TOPLEFT", active, "BOTTOMLEFT", 0, -10)

    view.status = O.CreateText(page, "", 11, "muted")
    view.status:SetPoint("TOPLEFT", nameRow, "BOTTOMLEFT", 4, -45)
    view.status:SetPoint("RIGHT", -4, 0)

    local function CreateProfile(copyCurrent, successText)
        local ok, reason = NS.Database.CreateProfile(NS.Database.NormalizeProfileName(view.draftName), copyCurrent)
        if ok then ok, reason = Replaced(NS.Database.SetActiveProfile(reason)) end
        view.Result(ok, reason, successText)
    end
    local create = O.CreateSettingButton(page, L["Create clean"], 126, 28, function()
        CreateProfile(false, L["Clean profile created"])
    end, nil, view.Refused)
    create:SetPoint("TOPLEFT", nameRow, "BOTTOMLEFT", 0, -8)
    local copy = O.CreateSettingButton(page, L["Copy current"], 126, 28, function()
        CreateProfile(true, L["Current profile copied"])
    end, nil, view.Refused)
    copy:SetPoint("LEFT", create, "RIGHT", 8, 0)
    -- A delete cannot be undone, so it takes two clicks like an import that
    -- replaces a profile: the first arms the button for the active profile,
    -- only a second click within ARM_SECONDS on that same profile deletes it.
    -- The last profile is never armed; the engine refuses it at once.
    local confirmation
    local remove = O.CreateSettingButton(page, L["Delete active"], 126, 28, function()
        local name = NS.Database.GetActiveProfileName()
        if #names > 1 and not confirmation.IsArmed(name) then
            confirmation.Arm(name)
            view.Result(false, nil, nil,
                L["Click Confirm delete within 5 seconds to delete profile %s."]:format(tostring(name)))
            return
        end
        confirmation.Disarm()
        view.Result(Replaced(NS.Database.DeleteProfile(name)))
    end, nil, view.Refused)
    confirmation = O.CreateConfirmation(remove, L["Delete active"], L["Confirm delete"], ARM_SECONDS)
    remove:SetPoint("LEFT", copy, "RIGHT", 8, 0)
    return create
end

local function CreateTransferBox(transfer)
    local scroll = CreateFrame("ScrollFrame", nil, transfer)
    scroll:SetPoint("TOPLEFT", 12, -58)
    scroll:SetPoint("BOTTOMRIGHT", -12, 50)
    NS.Surface.Attach(scroll, { role = "input", shape = "continuous", radius = 4, border = 1 })

    local edit = CreateFrame("EditBox", nil, scroll)
    edit:SetMultiLine(true)
    edit:SetAutoFocus(false)
    edit:SetMaxLetters(NS.ProfileIO.maxEncodedBytes + 16)
    edit:SetFontObject(ChatFontNormal)
    edit:SetWidth(736)
    edit:SetHeight(180)
    edit:SetTextInsets(8, 8, 8, 8)
    edit:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    scroll:SetScrollChild(edit)
    return edit
end

-- An import never replaces a profile silently (ProfileIO.ImportProfile). A
-- taken name arms the import button; only a second click within ARM_SECONDS,
-- on the same text and name, replaces that profile. The replacement is one
-- undo step whose snapshot is the replaced profile.

local function ReplaceProfile(view, text, name)
    local label = L["Import profile"]
    local began = O.BeginUserChange(label, name)
    local ok, reason = NS.ProfileIO.ImportProfile(text, name, true)
    if began and ok then
        O.CommitUserChange(label)
    elseif began then
        O.CancelUserChange()
    elseif ok then
        O.ClearHistory()
    end
    view.Result(ok, reason, ok and L["Profile %s replaced"]:format(tostring(reason)) or nil)
end

local function ImportProfile(view, confirmation, text)
    local draftName = view.draftName ~= "" and view.draftName or nil
    local pending = view.pendingReplace
    view.pendingReplace = nil
    if pending and confirmation.IsArmed(pending) and pending.text == text
        and pending.draftName == draftName then
        confirmation.Disarm()
        ReplaceProfile(view, text, pending.name)
        return
    end
    confirmation.Disarm()
    local ok, reason, existing = NS.ProfileIO.ImportProfile(text, draftName)
    if not ok and reason == "profile-exists" then
        view.pendingReplace = { text = text, draftName = draftName, name = existing }
        confirmation.Arm(view.pendingReplace)
        view.Result(false, reason, nil,
            L["Profile %s already exists. Click Confirm replace within 5 seconds to overwrite it."]
                :format(tostring(existing)))
        return
    end
    ok, reason = Replaced(ok, reason)
    view.Result(ok, reason, ok and L["Profile imported as %s"]:format(tostring(reason)) or nil)
end

local function BuildTransfer(page, anchor, view)
    local transfer = O.CreatePanel(page, "card")
    transfer:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -42)
    transfer:SetPoint("BOTTOMRIGHT", -4, 4)

    local transferTitle = O.CreateText(transfer, L["IMPORT / EXPORT"], 11, "accent")
    transferTitle:SetPoint("TOPLEFT", 14, -12)
    local transferHint = O.CreateText(transfer,
        L["MSKIN1 is a versioned, compressed Blizzard-CBOR format. Imports are bounded and only known settings are accepted."],
        11, "muted")
    transferHint:SetPoint("TOPLEFT", transferTitle, "BOTTOMLEFT", 0, -6)
    transferHint:SetPoint("RIGHT", -14, 0)
    local edit = CreateTransferBox(transfer)

    local function Export(exporter, successText)
        local text, reason = exporter()
        if text then
            edit:SetText(text)
            edit:HighlightText()
            edit:SetFocus()
        end
        view.Result(text ~= nil, reason, successText)
    end
    local exportProfile = O.CreateButton(transfer, L["Export profile"], 134, 28, function()
        Export(NS.ProfileIO.ExportProfile, L["Active profile exported"])
    end, "buttonPrimary")
    exportProfile:SetPoint("BOTTOMLEFT", 12, 10)
    local exportAll = O.CreateButton(transfer, L["Export all"], 118, 28, function()
        Export(NS.ProfileIO.ExportAll, L["All profiles exported"])
    end)
    exportAll:SetPoint("LEFT", exportProfile, "RIGHT", 8, 0)

    local confirmation
    local importProfile = O.CreateSettingButton(transfer, L["Import profile"], 134, 28, function()
        ImportProfile(view, confirmation, edit:GetText())
    end, "buttonPrimary", view.Refused)
    confirmation = O.CreateConfirmation(importProfile, L["Import profile"], L["Confirm replace"], ARM_SECONDS)
    importProfile:SetPoint("LEFT", exportAll, "RIGHT", 18, 0)
    local importAll = O.CreateSettingButton(transfer, L["Import all"], 118, 28, function()
        view.Result(Replaced(NS.ProfileIO.ImportAll(edit:GetText())))
    end, nil, view.Refused)
    importAll:SetPoint("LEFT", importProfile, "RIGHT", 8, 0)
end

O.RegisterPage("profiles", NS.L.PROFILES, function(page)
    O.CreateSectionTitle(page, L["Profiles and sharing"],
        L["Every color, look, geometry, font, icon, Micro Bar, Blizzard skin and HUD setting travels with the profile."])

    local view = { names = {}, draftName = "" }
    local function RefreshNames()
        local names = view.names
        for index = #names, 1, -1 do names[index] = nil end
        local current = NS.Database.GetProfileNames()
        for index = 1, #current do names[index] = current[index] end
    end
    RefreshNames()
    -- Shows the outcome. A replaced profile was repainted by ClearHistory;
    -- an export or a refused operation changed no setting to repaint.
    view.Result = function(ok, value, successText, failureText)
        local text
        if ok then
            text = successText or tostring(value or L["Done"])
        else
            text = failureText or REFUSAL_TEXT[value] or L["Error: %s"]:format(tostring(value))
        end
        view.statusProfile = NS.DB
        view.status:SetText(text)
        O.SetTextColor(view.status, ok and "success" or "danger")
        RefreshNames()
    end
    -- A profile button refused in combat reports it like the engine would.
    view.Refused = function(_, reason)
        view.Result(false, reason)
    end

    BuildTransfer(page, BuildProfileControls(page, view), view)
    O.TrackRefresh(function()
        RefreshNames()
        local status = view.status
        local text = status:GetText()
        if text == nil or text == "" or view.statusProfile ~= NS.DB then
            view.statusProfile = NS.DB
            O.SetTextColor(status, "muted")
            status:SetText(L["Active: %s"]:format(NS.Database.GetActiveProfileName()))
        end
    end)
end)

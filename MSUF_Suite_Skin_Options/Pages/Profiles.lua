local _, Private = ...
local NS, O = Private.NS, Private.Options
local L = NS.L

-- Profile switches, creation and import replace the whole skin database, so
-- they drop the undo step instead of recording one.
local function BuildProfileControls(page, view)
    local names = view.names
    local active = O.CreateCycle(page, L["Active profile"], names, function()
        return NS.Database.GetActiveProfileName()
    end, function(value)
        O.ClearHistory()
        NS.Database.SetActiveProfile(value)
    end, 520, nil, { history = false })
    active:SetPoint("TOPLEFT", 4, -70)

    local nameRow = O.CreateInput(page, L["Profile name"], function() return view.draftName end,
        function(value) view.draftName = value end, 520, { history = false })
    nameRow:SetPoint("TOPLEFT", active, "BOTTOMLEFT", 0, -10)

    view.status = O.CreateText(page, "", 11, "muted")
    view.status:SetPoint("TOPLEFT", nameRow, "BOTTOMLEFT", 4, -45)
    view.status:SetPoint("RIGHT", -4, 0)

    local function CreateProfile(copyCurrent, successText)
        O.ClearHistory()
        local ok, reason = NS.Database.CreateProfile(view.draftName, copyCurrent)
        if ok then ok, reason = NS.Database.SetActiveProfile(reason) end
        view.Result(ok, reason, successText)
    end
    local create = O.CreateButton(page, L["Create clean"], 126, 28, function()
        CreateProfile(false, L["Clean profile created"])
    end)
    create:SetPoint("TOPLEFT", nameRow, "BOTTOMLEFT", 0, -8)
    local copy = O.CreateButton(page, L["Copy current"], 126, 28, function()
        CreateProfile(true, L["Current profile copied"])
    end)
    copy:SetPoint("LEFT", create, "RIGHT", 8, 0)
    local remove = O.CreateButton(page, L["Delete active"], 126, 28, function()
        O.ClearHistory()
        view.Result(NS.Database.DeleteProfile(NS.Database.GetActiveProfileName()))
    end)
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
    edit:SetFontObject(ChatFontNormal or GameFontHighlightSmall)
    edit:SetWidth(736)
    edit:SetHeight(180)
    edit:SetTextInsets(8, 8, 8, 8)
    edit:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    scroll:SetScrollChild(edit)
    return edit
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

    local importProfile = O.CreateButton(transfer, L["Import profile"], 134, 28, function()
        O.ClearHistory()
        view.Result(NS.ProfileIO.ImportProfile(edit:GetText(), view.draftName ~= "" and view.draftName or nil))
    end, "buttonPrimary")
    importProfile:SetPoint("LEFT", exportAll, "RIGHT", 18, 0)
    local importAll = O.CreateButton(transfer, L["Import all"], 118, 28, function()
        O.ClearHistory()
        view.Result(NS.ProfileIO.ImportAll(edit:GetText()))
    end)
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
    view.Result = function(ok, value, successText)
        view.status:SetText(ok and (successText or tostring(value or L["Done"]))
            or L["Error: %s"]:format(tostring(value)))
        O.SetTextColor(view.status, ok and "success" or "danger")
        RefreshNames()
        O.RefreshAll()
    end

    BuildTransfer(page, BuildProfileControls(page, view), view)
    O.TrackRefresh(function()
        RefreshNames()
        local status = view.status
        local text = status:GetText()
        if text == nil or text == "" then
            status:SetText(L["Active: %s"]:format(NS.Database.GetActiveProfileName()))
        end
    end)
end)

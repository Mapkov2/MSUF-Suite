local _, Private = ...
local NS, O = Private.NS, Private.Options

O.RegisterPage("profiles", NS.L.PROFILES, function(page)
    O.CreateSectionTitle(page, "Profiles and sharing",
        "Every color, look, geometry, font, icon, Micro Bar, Blizzard skin and HUD setting travels with the profile.")

    local names = {}
    local function RefreshNames()
        for index = #names, 1, -1 do names[index] = nil end
        local current = NS.Database.GetProfileNames()
        for index = 1, #current do names[index] = current[index] end
    end
    RefreshNames()

    local active = O.CreateCycle(page, "Active profile", names, function()
        return NS.Database.GetActiveProfileName()
    end, function(value)
        O.ClearHistory()
        NS.Database.SetActiveProfile(value)
    end, 520, nil, { history = false })
    active:SetPoint("TOPLEFT", 4, -70)

    local draftName = ""
    local nameRow = O.CreateInput(page, "Profile name", function() return draftName end,
        function(value) draftName = value end, 520, { history = false })
    nameRow:SetPoint("TOPLEFT", active, "BOTTOMLEFT", 0, -10)

    local status = O.CreateText(page, "", 11, "muted")
    status:SetPoint("TOPLEFT", nameRow, "BOTTOMLEFT", 4, -45)
    status:SetPoint("RIGHT", -4, 0)

    local function Result(ok, value, successText)
        status:SetText(ok and (successText or tostring(value or "Done")) or ("Error: " .. tostring(value)))
        O.SetTextColor(status, ok and "success" or "danger")
        RefreshNames()
        O.RefreshAll()
    end

    local create = O.CreateButton(page, "Create clean", 126, 28, function()
        O.ClearHistory()
        local ok, reason = NS.Database.CreateProfile(draftName, false)
        if ok then ok, reason = NS.Database.SetActiveProfile(reason) end
        Result(ok, reason, "Clean profile created")
    end)
    create:SetPoint("TOPLEFT", nameRow, "BOTTOMLEFT", 0, -8)

    local copy = O.CreateButton(page, "Copy current", 126, 28, function()
        O.ClearHistory()
        local ok, reason = NS.Database.CreateProfile(draftName, true)
        if ok then ok, reason = NS.Database.SetActiveProfile(reason) end
        Result(ok, reason, "Current profile copied")
    end)
    copy:SetPoint("LEFT", create, "RIGHT", 8, 0)

    local remove = O.CreateButton(page, "Delete active", 126, 28, function()
        O.ClearHistory()
        Result(NS.Database.DeleteProfile(NS.Database.GetActiveProfileName()))
    end)
    remove:SetPoint("LEFT", copy, "RIGHT", 8, 0)

    local transfer = O.CreatePanel(page, "card")
    transfer:SetPoint("TOPLEFT", create, "BOTTOMLEFT", 0, -42)
    transfer:SetPoint("BOTTOMRIGHT", -4, 4)

    local transferTitle = O.CreateText(transfer, "IMPORT / EXPORT", 11, "accent")
    transferTitle:SetPoint("TOPLEFT", 14, -12)
    local transferHint = O.CreateText(transfer,
        "MSKIN1 is a versioned, compressed Blizzard-CBOR format. Imports are bounded and only known settings are accepted.",
        11, "muted")
    transferHint:SetPoint("TOPLEFT", transferTitle, "BOTTOMLEFT", 0, -6)
    transferHint:SetPoint("RIGHT", -14, 0)

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

    local exportProfile = O.CreateButton(transfer, "Export profile", 134, 28, function()
        local text, reason = NS.ProfileIO.ExportProfile()
        if text then edit:SetText(text); edit:HighlightText(); edit:SetFocus() end
        Result(text ~= nil, reason, "Active profile exported")
    end, "buttonPrimary")
    exportProfile:SetPoint("BOTTOMLEFT", 12, 10)

    local exportAll = O.CreateButton(transfer, "Export all", 118, 28, function()
        local text, reason = NS.ProfileIO.ExportAll()
        if text then edit:SetText(text); edit:HighlightText(); edit:SetFocus() end
        Result(text ~= nil, reason, "All profiles exported")
    end)
    exportAll:SetPoint("LEFT", exportProfile, "RIGHT", 8, 0)

    local importProfile = O.CreateButton(transfer, "Import profile", 134, 28, function()
        O.ClearHistory()
        Result(NS.ProfileIO.ImportProfile(edit:GetText(), draftName ~= "" and draftName or nil))
    end, "buttonPrimary")
    importProfile:SetPoint("LEFT", exportAll, "RIGHT", 18, 0)

    local importAll = O.CreateButton(transfer, "Import all", 118, 28, function()
        O.ClearHistory()
        Result(NS.ProfileIO.ImportAll(edit:GetText()))
    end)
    importAll:SetPoint("LEFT", importProfile, "RIGHT", 8, 0)

    O.TrackRefresh(function()
        RefreshNames()
        local current = NS.Database.GetActiveProfileName()
        status:SetText(status:GetText() ~= "" and status:GetText() or ("Active: " .. current))
    end)
end)

local _, Private = ...
local NS, O = Private.NS, Private.Options

O.RegisterPage("typography", NS.L.TYPOGRAPHY, function(page)
    O.CreateSectionTitle(page, "Global fonts",
        "Choose one font for Blizzard UI text. Existing sizes, outlines, shadows and accessibility scaling are preserved.")

    local enabled = O.CreateToggle(page, "Override Blizzard fonts", function()
        return NS.DB.typography.enabled
    end, function(value)
        NS.Typography.SetEnabled(value)
    end, 520)
    enabled:SetPoint("TOPLEFT", 4, -70)

    local face = O.CreateDropdown(page, "Font", NS.Typography.GetSelectionValues, function()
        return NS.Typography.GetSelection()
    end, function(value)
        NS.Typography.SetSelection(value)
    end, 700, NS.Typography.GetSelectionLabel, NS.Typography.GetSelectionPath,
        { countLabel = "fonts" })
    face:SetPoint("TOPLEFT", enabled, "BOTTOMLEFT", 0, -10)

    local chat = O.CreateToggle(page, "Chat, Communities and console text", function()
        return NS.DB.typography.applyChat
    end, function(value)
        NS.Typography.SetApplyChat(value)
    end, 520)
    chat:SetPoint("TOPLEFT", face, "BOTTOMLEFT", 0, -10)

    local special = O.CreateToggle(page, "Quest, mail, number and combat styles", function()
        return NS.DB.typography.includeSpecial
    end, function(value)
        NS.Typography.SetIncludeSpecial(value)
    end, 520)
    special:SetPoint("TOPLEFT", chat, "BOTTOMLEFT", 0, -10)

    local custom = O.CreateInput(page, "Custom font path (used by Custom path)", function()
        return NS.DB.typography.customPath
    end, function(value)
        NS.Typography.SetCustomPath(value)
    end, 520)
    custom:SetPoint("TOPLEFT", special, "BOTTOMLEFT", 0, -10)

    local preview = O.CreatePanel(page, "navigation")
    preview:SetPoint("TOPLEFT", custom, "BOTTOMLEFT", 0, -14)
    preview:SetPoint("TOPRIGHT", -4, 0)
    preview:SetHeight(160)
    local previewTitle = O.CreateText(preview, "THE QUICK BROWN FOX JUMPS OVER THE LAZY DOG", 18, "title")
    previewTitle:SetPoint("TOPLEFT", 16, -18)
    local previewBody = O.CreateText(preview,
        "0123456789  ÄÖÜ äöü ß  —  Blizzard keeps every original font size and style flag.",
        13, "text")
    previewBody:SetPoint("TOPLEFT", previewTitle, "BOTTOMLEFT", 0, -12)
    previewBody:SetPoint("RIGHT", -16, 0)

    local status = O.CreateText(preview, "", 11, "muted")
    status:SetPoint("BOTTOMLEFT", 16, 16)
    O.TrackRefresh(function()
        local current = NS.Typography.GetStatus()
        local state = current.enabled and (current.error and "ERROR: " .. current.error or "ACTIVE") or "OFF"
        status:SetText(("%s  |  %d Blizzard FontObjects  |  %d direct text frames"):format(
            state, current.fontObjects or 0, current.directFrames or 0))
        O.SetTextColor(status, current.error and "danger" or current.enabled and "success" or "muted")
    end)
end)

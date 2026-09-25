local _, Private = ...
local NS, O = Private.NS, Private.Options
local L = NS.L

local function TypographyGetter(key)
    return function() return NS.DB.typography[key] end
end

local function BuildControls(page)
    local enabled = O.CreateToggle(page, L["Override Blizzard fonts"], TypographyGetter("enabled"),
        NS.Typography.SetEnabled, 520)
    enabled:SetPoint("TOPLEFT", 4, -70)

    local face = O.CreateDropdown(page, L["Font"], NS.Typography.GetSelectionValues, NS.Typography.GetSelection,
        NS.Typography.SetSelection, 700, NS.Typography.GetSelectionLabel, NS.Typography.GetSelectionPath,
        { countLabel = L["fonts"], countSingular = L["font"] })
    face:SetPoint("TOPLEFT", enabled, "BOTTOMLEFT", 0, -10)

    local chat = O.CreateToggle(page, L["Chat, Communities and console text"], TypographyGetter("applyChat"),
        NS.Typography.SetApplyChat, 520)
    chat:SetPoint("TOPLEFT", face, "BOTTOMLEFT", 0, -10)

    local special = O.CreateToggle(page, L["Quest, mail, number and combat styles"],
        TypographyGetter("includeSpecial"), NS.Typography.SetIncludeSpecial, 520)
    special:SetPoint("TOPLEFT", chat, "BOTTOMLEFT", 0, -10)

    local custom = O.CreateInput(page, L["Custom font path (used by Custom path)"], TypographyGetter("customPath"),
        NS.Typography.SetCustomPath, 520)
    custom:SetPoint("TOPLEFT", special, "BOTTOMLEFT", 0, -10)
    return custom
end

local function BuildPreview(page, anchor)
    local preview = O.CreatePanel(page, "navigation")
    preview:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -14)
    preview:SetPoint("TOPRIGHT", -4, 0)
    preview:SetHeight(160)
    local previewTitle = O.CreateText(preview, L["THE QUICK BROWN FOX JUMPS OVER THE LAZY DOG"], 18, "title")
    previewTitle:SetPoint("TOPLEFT", 16, -18)
    local previewBody = O.CreateText(preview,
        "0123456789  ÄÖÜ äöü ß  —  " .. L["Blizzard keeps every original font size and style flag."],
        13, "text")
    previewBody:SetPoint("TOPLEFT", previewTitle, "BOTTOMLEFT", 0, -12)
    previewBody:SetPoint("RIGHT", -16, 0)

    local status = O.CreateText(preview, "", 11, "muted")
    status:SetPoint("BOTTOMLEFT", 16, 16)
    O.TrackRefresh(function()
        local current = NS.Typography.GetStatus()
        local state = L["OFF"]
        if current.enabled then
            state = current.error and L["ERROR: %s"]:format(current.error) or L["ACTIVE"]
        end
        status:SetText(L["%s  |  %d Blizzard FontObjects  |  %d direct text frames"]:format(
            state, current.fontObjects or 0, current.directFrames or 0))
        O.SetTextColor(status, current.error and "danger" or current.enabled and "success" or "muted")
    end)
end

O.RegisterPage("typography", NS.L.TYPOGRAPHY, function(page)
    O.CreateSectionTitle(page, L["Global fonts"],
        L["Choose one font for Blizzard UI text. Existing sizes, outlines, shadows and accessibility scaling are preserved."])
    BuildPreview(page, BuildControls(page))
end)

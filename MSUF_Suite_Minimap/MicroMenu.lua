local _, P = ...
local NS, S = P.NS, P.Suite
local MM = P.Minimap
local M = MM.M
-- The middle-click flyout of the Suite's micro menu (S.MicroMenuEntries in
-- MSUF_Suite_Modules/MicroMenu.lua: the offered buttons, their order and
-- labels; the game menu button is not offered here). A Blizzard panel opened
-- from an addon's click runs tainted and can later block talent changes or
-- group finder sign-ups, so the flyout holds secure "click" buttons: a row's
-- hardware click makes SecureActionButton_OnClick click the Blizzard micro
-- button from secure code. The flyout opens only out of combat and closes on
-- a choice, a click elsewhere, the combat start (PLAYER_REGEN_DISABLED comes
-- before the lockdown) and when the minimap stops.
local ROW, WIDTH, PAD, FONT = 20, 190, 6, 12
local flyout
local rows, entries = {}, {}

-- The flyout carries secure rows, so it is protected: it moves, shows and
-- hides out of combat only.
local function Close()
    if flyout and flyout:IsShown() and not NS.IsCombatLocked() then flyout:Hide() end
end
MM.CloseMicroMenu = Close

local function ClickAway()
    local over = flyout:IsMouseOver()
    if S.Public(over) and over then return end
    Close()
end

local function Row(index)
    local row = rows[index]
    if row then return row end
    row = S.CreateFrame("Button", nil, flyout, "SecureActionButtonTemplate")
    row:SetSize(WIDTH - PAD * 2, ROW)
    row:SetPoint("TOPLEFT", flyout, "TOPLEFT", PAD, -(PAD + ROW * index))
    row:SetAttribute("type", "click")
    -- SecureActionButton_OnClick acts on the press while ActionButtonUseKeyDown
    -- is on; the rows register the release, which must be the click.
    row:SetAttribute("useOnKeyDown", false)
    row:RegisterForClicks("LeftButtonUp")
    -- PostClick runs after the secure OnClick has clicked the micro button.
    row:SetScript("PostClick", Close)
    local highlight = S.CreateTexture(row, nil, "HIGHLIGHT")
    highlight:SetAllPoints(row)
    highlight:SetColorTexture(1, 1, 1, .12)
    row.label = S.CreateFontString(row, nil, "OVERLAY")
    row.label:SetPoint("LEFT", row, "LEFT", 6, 0)
    row.label:SetPoint("RIGHT", row, "RIGHT", -6, 0)
    row.label:SetJustifyH("LEFT")
    rows[index] = row
    return row
end

local function Build()
    if flyout then return end
    flyout = S.CreateFrame("Frame", nil, UIParent)
    flyout:SetFrameStrata("DIALOG")
    flyout:SetClampedToScreen(true)
    flyout:EnableMouse(true)
    flyout.back = S.CreateTexture(flyout, nil, "BACKGROUND")
    flyout.back:SetAllPoints(flyout)
    flyout.back:SetColorTexture(.05, .05, .05, .92)
    flyout.edges = {}
    for i = 1, 4 do flyout.edges[i] = S.CreateTexture(flyout, nil, "BORDER") end
    flyout.title = S.CreateFontString(flyout, nil, "OVERLAY")
    flyout.title:SetPoint("TOPLEFT", flyout, "TOPLEFT", PAD + 6, -PAD - 4)
    flyout:SetScript("OnHide", function()
        if not M.context then return end
        MM.Unlisten("GLOBAL_MOUSE_DOWN", "micro")
        MM.Unlisten("PLAYER_REGEN_DISABLED", "micro")
    end)
    flyout:Hide()
    MM.microMenu = flyout
end

-- One row per offered micro button; returns how many rows show.
local function Fill()
    local count, font = S.MicroMenuEntries(entries, false), S.GlobalFontPath()
    for i = 1, count do
        local entry, row = entries[i], Row(i)
        row:SetAttribute("clickbutton", entry.button)
        row:SetEnabled(entry.enabled)
        S.SetFont(row.label, font, FONT, "")
        row.label:SetText(entry.label)
        local shade = entry.enabled and 1 or .5
        row.label:SetTextColor(shade, shade, shade)
        row:Show()
    end
    for i = count + 1, #rows do
        rows[i]:Hide()
        rows[i]:SetAttribute("clickbutton", nil)
    end
    S.SetFont(flyout.title, font, FONT, "")
    flyout.title:SetText(S.Text("Micro menu"))
    flyout.title:SetTextColor(.8, .8, .8)
    return count
end

-- Opens the flyout at the cursor; a second middle click closes it.
function MM.OpenMicroMenu()
    if not M.active or NS.IsCombatLocked() then return end
    Build()
    if flyout:IsShown() then
        Close()
        return
    end
    local count = Fill()
    if count == 0 then return end
    flyout:SetSize(WIDTH, PAD * 2 + ROW * (count + 1))
    local r, g, b = MM.BorderRGB()
    S.PlaceEdges(flyout.edges, flyout, 1, r, g, b, 1)
    local x, y = GetCursorPosition()
    local scale = UIParent:GetEffectiveScale()
    flyout:ClearAllPoints()
    flyout:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", x / scale, y / scale)
    flyout:Show()
    MM.Listen("GLOBAL_MOUSE_DOWN", "micro", ClickAway)
    MM.Listen("PLAYER_REGEN_DISABLED", "micro", Close)
end

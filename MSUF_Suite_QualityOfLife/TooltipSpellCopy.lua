local _, P = ...
local NS, S = P.NS, P.Suite

-- C_OS.CopyToClipboard is restricted. Keep the last public spell tooltip ID
-- for a user-invoked, selected edit box instead.
local M = {}
local COMMAND = "MSUFSUITECOPYSPELL"

local function MakeLabel(parent, text, size)
    local label = S.CreateFontString(parent, nil, "ARTWORK")
    S.SetFont(label, nil, size or 12, "")
    label:SetText(S.Text(text))
    return label
end

local function CreateDialog()
    local panel = S.CreateFrame("Frame", nil, UIParent)
    panel:SetSize(270, 100)
    panel:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    panel:SetFrameStrata("DIALOG")
    panel:EnableMouse(true)
    panel:SetMovable(true)
    panel:SetClampedToScreen(true)

    local background = S.CreateTexture(panel, nil, "BACKGROUND")
    background:SetAllPoints()
    background:SetColorTexture(.065, .075, .085, .97)
    local accent = S.CreateTexture(panel, nil, "BORDER")
    accent:SetPoint("TOPLEFT")
    accent:SetPoint("TOPRIGHT")
    accent:SetHeight(2)
    accent:SetColorTexture(.8, .68, .42, 1)

    local title = MakeLabel(panel, "Copy spell ID", 14)
    title:SetPoint("TOPLEFT", 14, -12)
    local drag = S.CreateFrame("Button", nil, panel)
    drag:SetPoint("TOPLEFT", 0, 0)
    drag:SetPoint("TOPRIGHT", -32, 0)
    drag:SetHeight(39)
    drag:RegisterForDrag("LeftButton")
    drag:SetScript("OnDragStart", function() panel:StartMoving() end)
    drag:SetScript("OnDragStop", function() panel:StopMovingOrSizing() end)

    local close = S.CreateFrame("Button", nil, panel)
    close:SetSize(22, 22)
    close:SetPoint("TOPRIGHT", -7, -7)
    local cross = MakeLabel(close, "X", 13)
    cross:SetPoint("CENTER")
    close:SetScript("OnClick", function() panel:Hide() end)

    local edit = S.CreateFrame("EditBox", nil, panel, "InputBoxTemplate")
    edit:SetSize(210, 24)
    edit:SetPoint("TOP", panel, "TOP", 0, -46)
    edit:SetAutoFocus(false)
    edit:SetScript("OnEscapePressed", function() panel:Hide() end)
    panel.edit = edit
    local hint = MakeLabel(panel, "Press Ctrl+C to copy", 11)
    hint:SetPoint("BOTTOM", 0, 8)
    panel:Hide()
    return panel
end

local function ShowCopy(message)
    if not M.active then return end
    local id = M.lastID
    local typed = S.PublicText(message)
    if typed and typed:match("^%s*%d+%s*$") then
        local parsed = tonumber(typed)
        if S.Finite(parsed) and parsed > 0 then id = parsed end
    end
    if not S.Finite(id) or id < 1 then
        S.Print(S.Text("Hover a spell first, then use /msufcopyspell"))
        return
    end
    local panel = M.dialog or CreateDialog()
    M.dialog = panel
    panel.edit:SetText(tostring(math.floor(id)))
    panel:Show()
    panel.edit:SetFocus()
    panel.edit:HighlightText()
end

local function Spell(tooltip, data)
    if not M.active or tooltip ~= _G.GameTooltip or NS.Safety.IsForbidden(tooltip)
        or not S.Public(data) or type(data) ~= "table" then return end
    local id = data.id
    if S.Finite(id) and id > 0 then M.lastID = math.floor(id) end
end

local function Install()
    if M.hooked then return end
    TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Spell, Spell)
    M.hooked = true
end

function M:Enable()
    _G["SLASH_" .. COMMAND .. "1"] = "/msufcopyspell"
    SlashCmdList[COMMAND] = ShowCopy
    Install()
end

function M:Refresh() end

function M:Disable()
    _G["SLASH_" .. COMMAND .. "1"] = nil
    SlashCmdList[COMMAND] = nil
    self.lastID = nil
    if self.dialog then
        self.dialog:Hide()
        self.dialog.edit:ClearFocus()
        self.dialog.edit:SetText("")
    end
end

S.Install("tooltipSpellCopy", M)

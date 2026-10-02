local _, P = ...
local NS, S = P.NS, P.Suite

-- The player explicitly previews and creates a character macro. The builder
-- never edits an existing macro, executes a command, or runs in combat.
local M = { selected = 1 }
local COMMAND = "MSUFSUITEMACROBUILDER"
local ICON = 134400 -- question mark: #showtooltip resolves the spell icon
local TEMPLATES = {
    { label = "Mouseover ally", body = "/cast [@mouseover,help,nodead][help,nodead][@player] %s" },
    { label = "Mouseover enemy", body = "/cast [@mouseover,harm,nodead][harm,nodead] %s" },
    { label = "Focus enemy", body = "/cast [@focus,harm,nodead][harm,nodead] %s" },
}

local function Button(parent, text, x, y, width, click)
    local button = S.CreateFrame("Button", nil, parent)
    button:SetSize(width, 25)
    button:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    local background = S.CreateTexture(button, nil, "BACKGROUND")
    background:SetAllPoints()
    background:SetColorTexture(.18, .21, .23, .95)
    button.background = background
    local caption = S.QoLLabel(button, text, 12)
    caption:SetPoint("CENTER")
    button:SetScript("OnClick", click)
    return button
end

local function Status(text)
    if M.panel then M.panel.status:SetText(S.Text(text)) end
end

local function SpellName(input)
    if not S.PublicText(input) then return nil end
    input = input:match("^%s*(.-)%s*$")
    if input == "" or #input > 100 then return nil end
    local identifier = tonumber(input) or input
    if type(identifier) == "number" and (not S.Finite(identifier) or identifier < 1) then return nil end
    local info = C_Spell.GetSpellInfo(identifier)
    local name = S.Public(info) and type(info) == "table" and S.PublicText(info.name)
    if not name or name:find("[\r\n;/%%[%]{}]") then return nil end
    return name
end

local function Build(panel)
    local spell = SpellName(panel.spell:GetText())
    if not spell then
        panel.preview:SetText("")
        Status("Enter a valid spell name or ID")
        return nil
    end
    local body = "#showtooltip\n" .. string.format(TEMPLATES[M.selected].body, spell)
    if #body > 255 then
        panel.preview:SetText("")
        Status("The macro exceeds the 255-character limit")
        return nil
    end
    panel.preview:SetText(body)
    Status("Preview ready. Press Create to save it.")
    return body
end

local function NameExists(name)
    local account, character = GetNumMacros()
    local base = Constants.MacroConsts.MAX_ACCOUNT_MACROS
    if not S.Finite(account) or not S.Finite(character) or not S.Finite(base) then return true end
    local requested = name:lower()
    for i = 1, account do
        local existing = GetMacroInfo(i)
        if S.PublicText(existing) and existing:lower() == requested then return true end
    end
    for i = base + 1, base + character do
        local existing = GetMacroInfo(i)
        if S.PublicText(existing) and existing:lower() == requested then return true end
    end
    return false
end

local function CreateCharacterMacro(panel)
    if NS.IsCombatLocked() then
        Status("Create macros after combat")
        return
    end
    local body = Build(panel)
    if not body then return end
    local name = S.PublicText(panel.name:GetText())
    name = name and name:match("^%s*(.-)%s*$")
    -- SetMaxLetters below enforces the visible 16-character limit. UTF-8
    -- characters can occupy several bytes, so a byte-length check is wrong.
    if not name or name == "" or #name > 64 or name:find("[\r\n]") then
        Status("Enter a macro name of up to 16 characters")
        return
    end
    local _, count = GetNumMacros()
    local limit = Constants.MacroConsts.MAX_CHARACTER_MACROS
    if not S.Finite(count) or not S.Finite(limit) or count >= limit then
        Status("Character macro slots are full")
        return
    end
    if NameExists(name) then
        Status("That macro name already exists")
        return
    end
    -- An error from the client is reported (BugSack) like any other.
    local ok, index = S.Dispatch(NS.Finish, CreateMacro, name, ICON, body, true)
    if not ok or not S.Finite(index) or index < 1 then
        Status("WoW could not create the macro")
        return
    end
    Status("Created. Open /macro to drag it to an action bar.")
end

local function AddTemplates(panel)
    local prompt = S.QoLLabel(panel, "Choose a template", 12)
    prompt:SetPoint("TOPLEFT", 14, -45)
    panel.templates = {}
    for i = 1, #TEMPLATES do
        panel.templates[i] = Button(panel, TEMPLATES[i].label, 14 + (i - 1) * 140, -63, 132, function()
            M.selected = i
            for j = 1, #panel.templates do
                local bright = i == j
                panel.templates[j].background:SetColorTexture(bright and .30 or .18,
                    bright and .26 or .21, bright and .17 or .23, .95)
            end
            Build(panel)
        end)
    end
    panel.templates[M.selected].background:SetColorTexture(.30, .26, .17, .95)
end

local function AddFields(panel)
    local spellLabel = S.QoLLabel(panel, "Spell name or ID", 12)
    spellLabel:SetPoint("TOPLEFT", 16, -102)
    local spell = S.CreateFrame("EditBox", nil, panel, "InputBoxTemplate")
    spell:SetSize(239, 22)
    spell:SetPoint("TOPLEFT", 176, -97)
    spell:SetAutoFocus(false)
    spell:SetScript("OnEnterPressed", function()
        spell:ClearFocus()
        Build(panel)
    end)
    spell:SetScript("OnEscapePressed", function() spell:ClearFocus() end)
    panel.spell = spell

    local nameLabel = S.QoLLabel(panel, "Character macro name", 12)
    nameLabel:SetPoint("TOPLEFT", 16, -134)
    local name = S.CreateFrame("EditBox", nil, panel, "InputBoxTemplate")
    name:SetSize(239, 22)
    name:SetPoint("TOPLEFT", 176, -129)
    name:SetAutoFocus(false)
    name:SetMaxLetters(16)
    name:SetText("MSUF Mouseover")
    name:SetScript("OnEnterPressed", function()
        name:ClearFocus()
        Build(panel)
    end)
    name:SetScript("OnEscapePressed", function() name:ClearFocus() end)
    panel.name = name

    local previewLabel = S.QoLLabel(panel, "Macro preview (select text to copy)", 11)
    previewLabel:SetPoint("TOPLEFT", 16, -165)
    local preview = S.CreateFrame("EditBox", nil, panel, "InputBoxTemplate")
    preview:SetSize(394, 43)
    preview:SetPoint("TOPLEFT", 24, -182)
    preview:SetAutoFocus(false)
    preview:SetMultiLine(true)
    preview:SetScript("OnEscapePressed", function() preview:ClearFocus() end)
    panel.preview = preview
end

local function CreatePanel()
    local panel = S.QoLWindow(442, 282, "Macro builder", 16)
    AddTemplates(panel)
    AddFields(panel)
    Button(panel, "Preview", 16, -235, 96, function() Build(panel) end)
    Button(panel, "Create character macro", 119, -235, 178,
        function() CreateCharacterMacro(panel) end)
    local status = S.QoLLabel(panel, "Type a spell, then preview the macro", 11)
    status:SetPoint("BOTTOMLEFT", 15, 10)
    panel.status = status
    panel:Hide()
    return panel
end

local function Open()
    if not M.active then return end
    local panel = M.panel or CreatePanel()
    M.panel = panel
    if panel:IsShown() then panel:Hide() else panel:Show() end
end

function M:Enable()
    S.RegisterSlash(COMMAND, Open, "/msufmacro")
end

function M:Refresh() end

function M:Disable()
    S.UnregisterSlash(COMMAND, Open)
    if self.panel then
        self.panel:Hide()
        self.panel.spell:ClearFocus()
        self.panel.preview:ClearFocus()
    end
end

S.Install("macroBuilder", M)

local root = assert(arg[1], "repository root required")
local modules, widgets, notices = {}, {}, {}
local spellPostCall
local combat = false
local accountCount, characterCount = 0, 0
local storedMacros = {}
local created = 0

local function Widget(kind, parent)
    local widget = { kind = kind, parent = parent, shown = false, scripts = {} }
    widgets[#widgets + 1] = widget
    function widget:SetSize() end
    function widget:SetPoint() end
    function widget:SetFrameStrata() end
    function widget:EnableMouse() end
    function widget:SetMovable() end
    function widget:SetClampedToScreen() end
    function widget:SetHeight() end
    function widget:SetAllPoints() end
    function widget:RegisterForDrag() end
    function widget:SetAutoFocus() end
    function widget:SetMaxLetters(value) self.maxLetters = value end
    function widget:SetMultiLine(value) self.multiline = value end
    function widget:SetColorTexture(...) self.color = { ... } end
    function widget:SetScript(name, callback) self.scripts[name] = callback end
    function widget:SetText(value)
        if self.kind == "FontString" then assert(self.font, "FontString:SetText without a font") end
        self.text = value
    end
    function widget:GetText() return self.text or "" end
    function widget:Show() self.shown = true end
    function widget:Hide() self.shown = false end
    function widget:IsShown() return self.shown end
    function widget:SetFocus() self.focus = true end
    function widget:ClearFocus() self.focus = false end
    function widget:HighlightText() self.selected = true end
    function widget:StartMoving() end
    function widget:StopMovingOrSizing() end
    return widget
end

local S = {
    Install = function(id, module) modules[id] = module end,
    CreateFrame = function(kind, _, parent) return Widget(kind, parent) end,
    CreateTexture = function(parent) return Widget("Texture", parent) end,
    CreateFontString = function(parent) return Widget("FontString", parent) end,
    SetFont = function(font) font.font = true end,
    Text = function(value) return value end,
    Print = function(value) notices[#notices + 1] = value end,
    Public = function(value) return value ~= "secret" end,
    PublicText = function(value) return type(value) == "string" and value ~= "secret" and value or nil end,
    Finite = function(value) return type(value) == "number" and value == value end,
}
local NS = {
    Safety = { IsForbidden = function() return false end },
    IsCombatLocked = function() return combat end,
}
UIParent = Widget("Frame")
GameTooltip = Widget("Frame")
SlashCmdList = {}
Enum = { TooltipDataType = { Spell = 4 } }
TooltipDataProcessor = {
    AddTooltipPostCall = function(kind, callback)
        assert(kind == 4 and not spellPostCall)
        spellPostCall = callback
    end,
}
Constants = { MacroConsts = { MAX_ACCOUNT_MACROS = 120, MAX_CHARACTER_MACROS = 30 } }
C_Spell = { GetSpellInfo = function(value)
    if value == 123 or value == "Heal" then return { name = "Heal" } end
    if value == "Injected" then return { name = "Heal; /run print(1)" } end
end }
GetNumMacros = function() return accountCount, characterCount end
GetMacroInfo = function(index) return storedMacros[index] end
CreateMacro = function(name, icon, body, isCharacter)
    assert(icon == 134400 and isCharacter == true and body:find("^#showtooltip\n/cast"))
    created = created + 1
    characterCount = characterCount + 1
    storedMacros[120 + characterCount] = name
    return 120 + characterCount
end

local P = { NS = NS, Suite = S }
assert(loadfile(root .. "/MSUF_Suite_QualityOfLife/TooltipSpellCopy.lua"))("QoL", P)
assert(loadfile(root .. "/MSUF_Suite_QualityOfLife/MacroBuilder.lua"))("QoL", P)

local copy = assert(modules.tooltipSpellCopy)
local events = {}
copy.active = true
copy.context = {
    Event = function(_, event, callback) events[event] = callback end,
    RemoveEvent = function(_, event) events[event] = nil end,
}
copy:Enable()
assert(SLASH_MSUFSUITECOPYSPELL1 == "/msufcopyspell" and spellPostCall)
SlashCmdList.MSUFSUITECOPYSPELL("")
assert(#notices == 1 and not copy.dialog, "empty spell ID opened an unusable dialog")
spellPostCall(GameTooltip, { id = 123 })
spellPostCall(Widget("Frame"), { id = 999 })
spellPostCall(GameTooltip, { id = "secret" })
SlashCmdList.MSUFSUITECOPYSPELL("")
assert(copy.dialog and copy.dialog.edit.text == "123" and copy.dialog.edit.selected,
    "public tooltip spell ID was not selected for Ctrl+C")
copy.active = false
copy:Disable()
assert(not SlashCmdList.MSUFSUITECOPYSPELL and not copy.dialog.shown
    and copy.dialog.edit.text == "", "spell copy retained state when disabled")

local macro = assert(modules.macroBuilder)
macro.active = true
macro:Enable()
assert(SLASH_MSUFSUITEMACROBUILDER1 == "/msufmacro" and created == 0,
    "macro builder created a macro before a click")
SlashCmdList.MSUFSUITEMACROBUILDER()
local panel = assert(macro.panel)
assert(panel.shown and panel.preview.multiline and panel.name.maxLetters == 16)
panel.spell:SetText("123")
local function Click(caption)
    for i = 1, #widgets do
        local widget = widgets[i]
        if widget.kind == "FontString" and widget.text == caption
            and widget.parent and widget.parent.scripts.OnClick then
            widget.parent.scripts.OnClick(widget.parent)
            return
        end
    end
    error("button not found: " .. caption)
end
Click("Preview")
assert(panel.preview.text:find("%[@mouseover,help,nodead%]") and created == 0,
    "preview did not build a safe mouseover macro")
Click("Create character macro")
assert(created == 1 and storedMacros[121] == "MSUF Mouseover", "explicit creation failed")
Click("Create character macro")
assert(created == 1 and panel.status.text == "That macro name already exists",
    "duplicate macro name created another macro")
panel.name:SetText("Another macro")
combat = true
Click("Create character macro")
assert(created == 1 and panel.status.text == "Create macros after combat",
    "macro creation ran in combat")
combat = false
characterCount = 30
Click("Create character macro")
assert(created == 1 and panel.status.text == "Character macro slots are full",
    "full character macro storage was ignored")
characterCount = 1
panel.spell:SetText("Injected")
Click("Create character macro")
assert(created == 1 and panel.preview.text == "", "spell name injected macro syntax")
macro.active = false
macro:Disable()
assert(not SlashCmdList.MSUFSUITEMACROBUILDER and not panel.shown,
    "macro builder retained the command or window on disable")
print("Suite spell copy and manual macro builder lifecycle passed")

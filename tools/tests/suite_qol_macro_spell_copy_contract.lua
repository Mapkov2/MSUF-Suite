local root = assert(arg[1], "repository root required")
local Support = dofile(root .. "/tools/tests/suite_test_support.lua")
local modules, widgets, notices, reported = {}, {}, {}, {}
local combat = false

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
    -- The client's securecallfunction: an error is reported, nothing returned.
    Dispatch = function(callback, ...)
        local results = { pcall(callback, ...) }
        if not results[1] then reported[#reported + 1] = tostring(results[2]) return end
        return unpack(results, 2)
    end,
}
local NS = {
    Safety = { IsForbidden = function() return false end },
    IsCombatLocked = function() return combat end,
    Finish = function(callback, ...) return true, callback(...) end,
}
UIParent = Widget("Frame")
GameTooltip = Widget("Frame")
local slash = Support.SlashRegistry()
Support.QoLStyleFixture(root, S)
Enum = { TooltipDataType = { Spell = 4 } }
local tooltips = Support.TooltipFixture(root, S, NS)
local function spellPostCall(tooltip, data) tooltips.Run(4, tooltip, data) end
local P = { NS = NS, Suite = S }
assert(loadfile(root .. "/MSUF_Suite_QualityOfLife/SlashCommands.lua"))("QoL", P)
assert(loadfile(root .. "/MSUF_Suite_QualityOfLife/TooltipSpellCopy.lua"))("QoL", P)

local copy = assert(modules.tooltipSpellCopy)
local events = {}
copy.active = true
copy.context = {
    Event = function(_, event, callback) events[event] = callback end,
    RemoveEvent = function(_, event) events[event] = nil end,
}
copy:Enable()
assert(SLASH_MSUFSUITECOPYSPELL1 == "/msufcopyspell" and #tooltips.post[4] == 1)
assert(slash.Type("/msufcopyspell"))
assert(#notices == 1 and not copy.dialog, "empty spell ID opened an unusable dialog")
spellPostCall(GameTooltip, { id = 123 })
spellPostCall(Widget("Frame"), { id = 999 })
spellPostCall(GameTooltip, { id = "secret" })
assert(slash.Type("/msufcopyspell"))
assert(copy.dialog and copy.dialog.edit.text == "123" and copy.dialog.edit.selected,
    "public tooltip spell ID was not selected for Ctrl+C")
copy.active = false
copy:Disable()
assert(not SlashCmdList.MSUFSUITECOPYSPELL and not copy.dialog.shown
    and copy.dialog.edit.text == "", "spell copy retained state when disabled")
assert(not slash.Type("/msufcopyspell 123"), "the disabled spell copy kept its typed command")

print("Suite spell copy lifecycle passed; macro workshop has dedicated contracts")

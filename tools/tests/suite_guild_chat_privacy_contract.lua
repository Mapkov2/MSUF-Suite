local root = assert(arg[1], "repository root required")
local module, combat = nil, false
local hooks, queued = {}, 0
local function Widget(kind, parent)
    local widget = { kind = kind, parent = parent, shown = false, scripts = {}, groups = {}, level = 1 }
    function widget:SetSize() end
    function widget:SetPoint() end
    function widget:SetFrameStrata() end
    function widget:SetFrameLevel(level) self.level = level end
    function widget:GetFrameLevel() return self.level end
    function widget:SetHeight() end
    function widget:SetWidth() end
    function widget:SetAllPoints() end
    function widget:SetColorTexture() end
    function widget:SetScript(name, callback) self.scripts[name] = callback end
    function widget:SetText(value)
        if self.kind == "FontString" then assert(self.font, "uninitialized font") end
        self.text = value
    end
    function widget:ContainsMessageGroup(group) return self.groups[group] == true end
    function widget:Show() self.shown = true end
    function widget:Hide() self.shown = false end
    function widget:SetShown(value) self.shown = value end
    function widget:GetMessageInfo() error("guild privacy read chat text") end
    return widget
end
local S = {
    Install = function(_, value) module = value end,
    CreateFrame = function(kind, _, parent) return Widget(kind, parent) end,
    CreateTexture = function(parent) return Widget("Texture", parent) end,
    CreateFontString = function(parent) return Widget("FontString", parent) end,
    SetFont = function(label) label.font = true end,
    Text = function(value) return value end,
    Queue = function(id) assert(id == "guildChatPrivacy"); queued = queued + 1 end,
}
local NS = {
    Safety = { IsForbidden = function() return false end },
    IsCombatLocked = function() return combat end,
}
SlashCmdList = {}
CHAT_FRAMES = { "ChatFrame1", "ChatFrame2" }
ChatFrame1 = Widget("ChatFrame")
ChatFrame2 = Widget("ChatFrame")
ChatFrame1.groups.GUILD = true
ChatFrame2.groups.SAY = true
FCF_OpenNewWindow = function() end
FCF_OpenTemporaryWindow = function() end
hooksecurefunc = function(name, callback)
    assert(not hooks[name], "window hook installed twice")
    hooks[name] = callback
end
assert(loadfile(root .. "/MSUF_Suite_QualityOfLife/GuildChatPrivacy.lua"))(
    "MSUF_Suite_QualityOfLife", { NS = NS, Suite = S })
local events = {}
module.context = { Event = function(_, event, callback) events[event] = callback end }
module.active = true
local savedFrames = CHAT_FRAMES
CHAT_FRAMES = nil
module:Refresh()
assert(not module.control, "guild cover accessed chat frames before they existed")
CHAT_FRAMES = savedFrames
module:Enable()
assert(SLASH_MSUFSUITEGUILDPRIVACY1 == "/msufguildprivacy"
    and module.control and module.control.label.text == "Guild privacy: OFF"
    and not module.overlays[ChatFrame1], "privacy cover was not opt-in within the module")
SlashCmdList.MSUFSUITEGUILDPRIVACY()
assert(module.covered and module.overlays[ChatFrame1].shown
    and not module.overlays[ChatFrame2]
    and module.control.label.text == "Guild privacy: ON",
    "only guild chat windows should be covered")
ChatFrame2.groups.OFFICER = true
hooks.FCF_OpenTemporaryWindow()
assert(module.overlays[ChatFrame2].shown, "new officer chat window was left exposed")
ChatFrame1.groups.GUILD = false
events.UPDATE_CHAT_WINDOWS(module)
assert(not module.overlays[ChatFrame1].shown and module.overlays[ChatFrame2].shown,
    "removing a guild channel did not release the cover")
combat = true
SlashCmdList.MSUFSUITEGUILDPRIVACY()
assert(not module.overlays[ChatFrame2].shown and queued == 1,
    "existing privacy cover did not toggle safely in combat")
combat = false
module:Refresh()
assert(not module.covered and module.control.label.text == "Guild privacy: OFF")
module.active = false
module:Disable()
assert(not SlashCmdList.MSUFSUITEGUILDPRIVACY and not module.control.shown
    and not module.overlays[ChatFrame2].shown,
    "disable left the privacy command or visual cover active")
module.active = true
module:Enable()
assert(hooks.FCF_OpenNewWindow and hooks.FCF_OpenTemporaryWindow,
    "native window hooks were not installed")
print("Suite manual guild chat privacy cover lifecycle passed")

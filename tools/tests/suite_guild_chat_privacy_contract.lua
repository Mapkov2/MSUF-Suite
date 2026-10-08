local root = assert(arg[1], "repository root required")
local Support = dofile(root .. "/tools/tests/suite_test_support.lua")
local module, combat = nil, false
local hooks, queued = {}, 0
local keys = { ctrl = false, shift = false, alt = false }
IsControlKeyDown = function() return keys.ctrl end
IsShiftKeyDown = function() return keys.shift end
IsAltKeyDown = function() return keys.alt end
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
    Public = function() return true end,
    Queue = function(id) assert(id == "guildChatPrivacy"); queued = queued + 1 end,
}
local NS = {
    Safety = { IsForbidden = function() return false end },
    IsCombatLocked = function() return combat end,
}
local slash = Support.SlashRegistry()
Support.QoLStyleFixture(root, S)
assert(loadfile(root .. "/MSUF_Suite_QualityOfLife/SlashCommands.lua"))("MSUF_Suite_QualityOfLife", { Suite = S })
-- Blizzard_ChatFrameBase loads before any addon: its chat frames exist.
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
module.context = {
    Event = function(_, event, callback) events[event] = callback end,
    RemoveEvent = function(_, event) events[event] = nil end,
}
module.config = { revealClick = 2, communities = true }
module.active = true
module:Enable()
assert(SLASH_MSUFSUITEGUILDPRIVACY1 == "/msufguildprivacy"
    and module.control and module.control.label.text == "Guild privacy: OFF"
    and not (module.overlays[ChatFrame1] and module.overlays[ChatFrame1].shown), "privacy cover was not opt-in within the module")
combat = true
assert(slash.Type("/msufguildprivacy"))
combat = false
assert(module.covered and module.overlays[ChatFrame1] and module.overlays[ChatFrame1].shown
    and not module.overlays[ChatFrame2]
    and module.control.label.text == "Guild privacy: ON",
    "only guild chat windows should be covered")
-- The reveal click is the player's choice; the cover names it.
local cover = module.overlays[ChatFrame1]
assert(cover.hint.text == "Whole window hidden. Ctrl + left-click to reveal.",
    "the cover did not name the chosen reveal click")
cover.scripts.OnClick(cover, "LeftButton")
assert(module.covered and cover.shown, "a plain left-click revealed a Ctrl + left-click cover")
keys.ctrl = true
cover.scripts.OnClick(cover, "RightButton")
assert(module.covered and cover.shown, "a right-click revealed the cover")
cover.scripts.OnClick(cover, "LeftButton")
keys.ctrl = false
assert(not module.covered and not cover.shown, "Ctrl + left-click did not reveal the cover")
module.config.revealClick = 1
assert(slash.Type("/msufguildprivacy"))
assert(cover.hint.text == "Whole window hidden. Click to reveal.", "the hint kept the old reveal click")
cover.scripts.OnClick(cover, "LeftButton")
assert(not module.covered, "the left-click choice still asked for a key")
module.config.revealClick = 2
assert(slash.Type("/msufguildprivacy"))
ChatFrame2.groups.OFFICER = true
hooks.FCF_OpenTemporaryWindow()
assert(module.overlays[ChatFrame2].shown, "new officer chat window was left exposed")
ChatFrame1.groups.GUILD = false
events.UPDATE_CHAT_WINDOWS(module)
assert(not module.overlays[ChatFrame1].shown and module.overlays[ChatFrame2].shown,
    "removing a guild channel did not release the cover")
combat = true
assert(slash.Type("/msufguildprivacy"))
assert(not module.overlays[ChatFrame2].shown and queued == 2,
    "existing privacy cover did not toggle safely in combat")
combat = false
module:Refresh()
assert(not module.covered and module.control.label.text == "Guild privacy: OFF")
module.active = false
module:Disable()
assert(not SlashCmdList.MSUFSUITEGUILDPRIVACY and not module.control.shown
    and not module.overlays[ChatFrame2].shown,
    "disable left the privacy command or visual cover active")
assert(not slash.Type("/msufguildprivacy") and not module.covered,
    "the disabled privacy cover kept its typed command")
module.active = true
module:Enable()
assert(hooks.FCF_OpenNewWindow and hooks.FCF_OpenTemporaryWindow,
    "native window hooks were not installed")

-- Blizzard_Communities loads on demand; its chat pane is covered only while
-- the guild is the selected club, through the frame's own ClubSelected.
assert(events.ADDON_LOADED, "the Communities window was not awaited")
CommunitiesFrameMixin = { Event = { ClubSelected = "ClubSelected" } }
local guild, callbacks = true, {}
CommunitiesFrame = Widget("Frame")
CommunitiesFrame.Chat = Widget("Frame", CommunitiesFrame)
function CommunitiesFrame:IsGuildSelected() return guild end
function CommunitiesFrame:RegisterCallback(event, callback, owner)
    assert(type(event) == "string" and owner == module, "club callback without the module as owner")
    callbacks[event] = callback
end
function CommunitiesFrame:UnregisterCallback(event, owner)
    assert(owner == module)
    callbacks[event] = nil
end
events.ADDON_LOADED(module, "ADDON_LOADED", "Blizzard_Bags")
assert(not callbacks.ClubSelected, "another addon's load hooked the Communities window")
events.ADDON_LOADED(module, "ADDON_LOADED", "Blizzard_Communities")
assert(callbacks.ClubSelected and not events.ADDON_LOADED, "club changes were not followed")
local club = assert(module.clubCover, "the Communities cover was not built ahead of combat")
assert(not club.shown, "the Communities chat was covered while privacy was off")
combat = true
assert(slash.Type("/msufguildprivacy"))
assert(club.parent == CommunitiesFrame.Chat and club.shown and club.hint.text == "Ctrl + left-click to reveal.",
    "the Communities cover is not a child of the chat pane or names the wrong click")
combat = false
guild = false
callbacks.ClubSelected(module, 7)
assert(not club.shown and module.overlays[ChatFrame2].shown,
    "another community was covered, or switching clubs released the chat windows")
guild = true
callbacks.ClubSelected(module, 1)
assert(club.shown, "returning to the guild left its chat exposed")
combat = true
guild = false
callbacks.ClubSelected(module, 7)
assert(not club.shown, "a club change in combat kept the cover")
combat, guild = false, true
callbacks.ClubSelected(module, 1)
keys.ctrl = true
club.scripts.OnClick(club, "LeftButton")
keys.ctrl = false
assert(not module.covered and not club.shown and not module.overlays[ChatFrame2].shown,
    "Ctrl + left-click on the Communities cover did not reveal all guild chat")
module.config.communities = false
module:Refresh()
assert(not callbacks.ClubSelected, "the switched-off Communities cover kept its club callback")
assert(slash.Type("/msufguildprivacy"))
assert(not club.shown and module.overlays[ChatFrame2].shown,
    "the switched-off Communities cover still hid the guild chat")
module.config.communities = true
module:Refresh()
assert(callbacks.ClubSelected and club.shown, "switching the Communities cover back on did not cover it")
module.active = false
module:Disable()
assert(not callbacks.ClubSelected and not club.shown, "disable left the Communities cover active")
print("Suite manual guild chat privacy cover lifecycle passed")

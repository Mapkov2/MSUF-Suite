-- The real Chat page shows the comfort settings: the new sections come before
-- the keyword notices, the keyword settings follow their switch, and the
-- preview marks a word while the highlight is on.
local root = assert(arg[1])
SUITE_OPTIONS_FIXTURE = true
local F = dofile(root .. "/tools/tests/suite_options_menu_contract.lua")
local P, S = F.optionsNS, F.S
-- Use the runtime surface painters now shared by the interactive preview.
local runtime = { NS = P.Suite, Suite = S }
assert(loadfile(root .. "/MSUF_Suite_Modules/Runtime.lua"))("MSUF_Suite_Modules", {})
assert(loadfile(root .. "/MSUF_Suite_Modules/Surfaces.lua"))("MSUF_Suite_Modules", {})
for _, file in ipairs({ "Shared", "Appearance", "MinimalChrome", "Unread", "Sidebar", "Positions", "CompleteMessages", "Window", "PreviewSnapshot", "Preview" }) do
    assert(loadfile(root .. "/MSUF_Suite_Chat/" .. file .. ".lua"))("MSUF_Suite_Chat", runtime)
end
GENERAL_CHAT_DOCK = {}
local menuHook = hooksecurefunc
hooksecurefunc = function(name, callback)
    if name == "FCF_SetChatWindowFontSize" or name == "FCFDock_SelectWindow" or name == "FCFDock_UpdateTabs" then return end
    return menuHook(name, callback)
end
BNGetNumFriends = function() return 0, 0 end
C_FriendList = { GetNumOnlineFriends = function() return 0 end }
-- Font API behavior belongs to the real-host interactive preview contract.
S.ChatStylePreviewFonts = function() end
local create, textures = CreateFrame, {}
CreateFrame = function(...)
    local frame = create(...)
    frame.CombatLogQuickButtonFrame, frame.visual, frame.visibleLines, frame.entry = false, false, false, false
    local texture = frame.CreateTexture
    function frame:CreateTexture(...)
        local part = texture(self, ...)
        function part:SetGradient(direction, left, right)
            self.gradient = { direction, left, right }
        end
        textures[#textures + 1] = part
        return part
    end
    return frame
end

local function eq(a, b, label) assert(a == b, (label or "value") .. ": " .. tostring(a) .. " ~= " .. tostring(b)) end
local ctx = { key = "suite_chat", width = 720, refreshers = {}, widgets = {}, sections = {}, pageItems = {} }
F.SetCurrent(ctx)
F.M.pages.suite_chat.build(ctx)
if ctx.fixedPreview.record.onActivate then ctx.fixedPreview.record.onActivate() end
local function Refresh() for _, fn in ipairs(ctx.refreshers) do fn() end end
Refresh()

local order = {}
for index, section in ipairs(ctx.sections) do order[section.sectionId] = index end
assert(order.suite_chat_tools and order.suite_chat_sounds and order.suite_chat_highlight, "a comfort section is missing")
assert(order.suite_chat_tools < order.suite_chat_sounds and order.suite_chat_sounds < order.suite_chat_highlight
    and order.suite_chat_highlight < order.suite_chat_keywordAlerts_module
    and order.suite_chat_keywordAlerts_module < order.suite_chat_bubbles, "the comfort sections are out of order")
eq(ctx.sections[order.suite_chat_sounds].title, "Channel sounds", "sounds title")
eq(ctx.sections[order.suite_chat_highlight].title, "Keyword highlight", "highlight title")
eq(#P.SectionRules("chat", "sounds"), 2 * (#P.Suite.ChatSoundChannels - 1), "a kit and a file for every channel but whisper")
eq(#P.SectionRules("chat", "highlight"), 4, "the highlight settings")

-- The word list, own-name switch and color follow the highlight switch.
local rules = P.catalog.chat.rules
local lines = ctx.chatPreview.lines
for _, key in ipairs({ "highlightWords", "highlightOwnName", "highlightColor" }) do
    assert(not P.RuleEnabled("chat", rules[key]), key .. " is on while the highlight is off")
end
assert(P.RuleEnabled("chat", rules.highlightKeywords), "the highlight switch is disabled")
assert(not lines:GetText():find("[Raid]", 1, true), "the preview shows a highlight line by default")

assert(P.Set("chat", "highlightKeywords", true))
Refresh()
for _, key in ipairs({ "highlightWords", "highlightOwnName", "highlightColor" }) do
    assert(P.RuleEnabled("chat", rules[key]), key .. " stays off with the highlight on")
end
assert(lines:GetText():find("|cffffd100keyword|r", 1, true), "the preview marks no stand-in word")
assert(P.Set("chat", "highlightWords", " LFM , tank"))
Refresh()
assert(lines:GetText():find("|cffffd100LFM|r", 1, true), "the preview does not mark the first word of the list")
assert(P.Set("chat", "highlightColor", "12ab34"))
Refresh()
assert(lines:GetText():find("|cff12ab34LFM|r", 1, true), "the preview ignores the highlight color")
assert(P.Set("chat", "highlightWords", ""))
assert(P.Set("chat", "highlightOwnName", true))
Refresh()
assert(lines:GetText():find("|cff12ab34" .. UnitName("player") .. "|r", 1, true), "the preview does not mark the player's name")
assert(P.Set("chat", "highlightKeywords", false))
Refresh()
assert(not lines:GetText():find("[Raid]", 1, true), "the preview keeps the highlight line after the switch went off")
print("Chat comfort page: sections, gates and preview passed")

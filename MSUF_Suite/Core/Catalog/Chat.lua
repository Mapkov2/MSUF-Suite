local _, NS = ...
local B = NS.CatalogBuild.ForAddon("MSUF_Suite_Chat")

B.Module("chat", {
    title = "Chat",
    description = "Style Blizzard's native chat windows, tabs and input line. Links, channels, filters, docking and message delivery remain Blizzard-owned.",
    page = "suite_chat", optIn = true,
    conflicts = { "EllesmereUIChat", "ElvUI", "Glass", "Glassy", "Prat-3.0", "Chattynator", "Chatter" },
    summary = "look fontSize tabFontSize tabAccent panelAlpha sidebarPanel sidebarWidth inputPanel inputAlpha"
        .. " copyMessages",
})

local id = "chat"
local midnight = {
    panelColor = "0a1220", panelAlpha = 74,
    borderColor = "41627a", borderAlpha = 78, borderSize = 1,
    accentColor = "57c7df", accentAlpha = 88,
    tabActiveColor = "f4f7fb", tabInactiveColor = "aab5c2",
    tabPanel = true, tabAccent = true, sidebarPanel = true, sidebarWidth = 28,
    inputPanel = true,
    inputColor = "0a1522", inputAlpha = 86,
    padding = 4, fontSize = 0,
}
local midnightDark = {
    panelColor = "151719", panelAlpha = 82,
    borderColor = "575b58", borderAlpha = 78, borderSize = 1,
    accentColor = "b9ab86", accentAlpha = 78,
    tabActiveColor = "e9e9e4", tabInactiveColor = "b9bdb9",
    tabPanel = true, tabAccent = true, sidebarPanel = true, sidebarWidth = 28,
    inputPanel = true,
    inputColor = "111315", inputAlpha = 88,
    padding = 4, fontSize = 0,
}
local forever = {
    panelColor = "14181b", panelAlpha = 77,
    borderColor = "9f8960", borderAlpha = 85, borderSize = 1,
    accentColor = "d8b66a", accentAlpha = 92,
    tabActiveColor = "f1e3c4", tabInactiveColor = "d4dce2",
    tabPanel = true, tabAccent = true, sidebarPanel = true, sidebarWidth = 28,
    inputPanel = true,
    inputColor = "111517", inputAlpha = 88,
    padding = 4, fontSize = 0,
}

local cleanModern = {
    panelColor = "101010", panelAlpha = 82,
    borderColor = "333333", borderAlpha = 90, borderSize = 1,
    accentColor = "e6ecf2", accentAlpha = 88,
    tabActiveColor = "f5f5f5", tabInactiveColor = "bfc4c9",
    tabPanel = true, tabAccent = true, sidebarPanel = true, sidebarWidth = 28,
    inputPanel = true, inputColor = "0a0a0a", inputAlpha = 90,
    padding = 4, fontSize = 0,
}
NS.ChatLookPresets = { [1] = midnight, [2] = midnightDark, [3] = forever, [5] = cleanModern }
NS.ChatLookPresets[6] = B.ClassPreset(cleanModern, { borderColor = "border", accentColor = "accent", tabActiveColor = "label" })
-- Appended choice: existing profiles and global palettes keep their indices.
local immersive = {}
for key, value in pairs(cleanModern) do immersive[key] = value end
immersive.panelColor, immersive.panelAlpha, immersive.borderSize, immersive.sidebarPanel = "000000", 40, 0, false
immersive.inputColor, immersive.inputAlpha, immersive.panelGradient = "000000", 60, true
immersive.minimalChrome, immersive.padding = true, 0
immersive.tabHeight, immersive.tabPadding, immersive.tabGap, immersive.tabPanelGap = 20, 15, 4, 0
immersive.tabIndividualPanels = false
immersive.accentColor, immersive.accentAlpha = "dfba69", 100
immersive.tabActiveColor, immersive.tabInactiveColor = "dfba69", "d9d9d9"
immersive.font, immersive.tabFont = "__BLIZZARD_CHAT_FONT__", "__BLIZZARD_CHAT_FONT__"
immersive.fontSize, immersive.tabFontSize, immersive.fontOutline, immersive.fontRendering = 12, 12, 4, 1
immersive.fontShadow, immersive.fontShadowOpacity, immersive.fontShadowDistance = 2, 70, 1
immersive.idleSeconds, immersive.idleAlpha, immersive.idleFadeDuration = 12, 0, 0.35
immersive.messageFading, immersive.messageTimeVisible, immersive.messageFadeDuration = true, 20, 3
immersive.coloredUnreadTabs = true
NS.ChatLookPresets[7] = immersive
for index, preset in pairs(NS.ChatLookPresets) do
    if index ~= 7 then
        preset.panelGradient, preset.idleFadeDuration, preset.messageFading, preset.coloredUnreadTabs = false, 0, false, false
        preset.idleSeconds, preset.idleAlpha = 0, 20
        preset.minimalChrome = false
        preset.tabHeight, preset.tabPadding, preset.tabGap, preset.tabPanelGap = 24, 0, 0, 0
        preset.tabIndividualPanels = false
        preset.font, preset.tabFont, preset.tabFontSize = "", "", 0
        preset.fontOutline, preset.fontRendering, preset.fontShadow = 1, 3, 1
        preset.fontShadowOpacity, preset.fontShadowDistance = 100, 1
    end
end
NS.ChatLookVisualKeys = {}
for key in pairs(midnight) do NS.ChatLookVisualKeys[key] = true end
NS.ChatLookVisualKeys.panelGradient = true
for key in pairs(immersive) do NS.ChatLookVisualKeys[key] = true end
NS.SuiteCatalog[id].look = {
    key = "look", presets = NS.ChatLookPresets, visualKeys = NS.ChatLookVisualKeys,
    custom = 4, global = true,
}
local initial = NS.Client.isForever and forever or midnightDark

B.Section(id, "look", "Choose a look", {
    B.Choice("look", "Style preset", NS.Client.isForever and 3 or 2,
        { "Midnight Blue", "Midnight Dark", "MSUF Forever", "Custom", "Clean Modern", "Class Style", "Immersive" }),
})
B.Section(id, "window", "Chat window", {
    B.Texture("panelTexture", "Background texture"),
    B.Texture("borderTexture", "Border texture"),
    B.Bool("lockWindowSize", "Keep the main chat window at a fixed size", false),
    B.Number("windowWidth", "Locked width", 420, 200, 1200),
    B.Number("windowHeight", "Locked height", 180, 80, 800),
    B.Tooltip(B.Bool("lockWindowPosition", "Anchor the main chat window to the bottom left", false),
        "While this is on, move the window in MSUF Edit Mode or with the two positions below. While it is off, Blizzard's Edit Mode places it."),
    B.Number("windowX", "Horizontal position", 12, -4000, 4000),
    B.Number("windowY", "Vertical position", 12, -3000, 3000),
    B.Number("idleSeconds", "Fade after inactivity (seconds; 0 disables)", 0, 0, 300),
    B.Number("idleAlpha", "Idle panel opacity (percent)", 20, 0, 100),
    B.Number("idleFadeDuration", "Idle fade duration (seconds; 0 is instant)", 0, 0, 2, 0.05),
    B.Bool("panelGradient", "Fade background edges to transparent", false),
    B.Bool("minimalChrome", "Minimal chat style", false),
    B.Color("panelColor", "Background color", initial.panelColor),
    B.Number("panelAlpha", "Background opacity (percent)", initial.panelAlpha, 0, 100, 5),
    B.Color("borderColor", "Border color", initial.borderColor),
    B.Number("borderAlpha", "Border opacity (percent)", initial.borderAlpha, 0, 100, 5),
    B.Number("borderSize", "Border thickness", initial.borderSize, 0, 4),
    B.Number("padding", "Background padding", initial.padding, 0, 16),
})
B.Section(id, "tabs", "Tabs and accent", {
    B.Number("tabX", "Horizontal position", 0, -400, 400),
    B.Number("tabY", "Vertical position", 0, -300, 300),
    B.Number("tabHeight", "Tab height", 24, 18, 48),
    B.Number("tabPadding", "Tab text padding", 0, 0, 24),
    B.Number("tabGap", "Space between docked tabs", 0, 0, 24),
    B.Number("tabPanelGap", "Tab strip distance from messages", 0, 0, 24),
    B.Bool("tabIndividualPanels", "Individual tab backgrounds and borders", false),
    B.Color("tabActiveBackground", "Active tab background", initial.panelColor),
    B.Color("tabInactiveBackground", "Inactive tab background", initial.panelColor),
    B.Number("tabActiveAlpha", "Active tab background opacity", 80, 0, 100),
    B.Number("tabInactiveAlpha", "Inactive tab background opacity", 50, 0, 100),
    B.Number("tabBorderSize", "Tab border thickness", 0, 0, 4),
    B.Color("tabActiveBorder", "Active tab border", initial.accentColor),
    B.Color("tabInactiveBorder", "Inactive tab border", initial.borderColor),
    B.Bool("hideTabArt", "Hide Blizzard tab backgrounds", false),
    B.Bool("tabPanel", "Dark tab strip", initial.tabPanel),
    B.Bool("tabAccent", "Underline chat tabs", initial.tabAccent),
    B.Bool("coloredUnreadTabs", "Color unread tabs by message type", false),
    B.Font("tabFont", "Font"),
    B.Number("tabFontSize", "Font size", 0, 0, 24),
    B.Bool("tabClassColor", "Class-colored active tab", false),
    B.Color("tabActiveColor", "Active tab text", initial.tabActiveColor),
    B.Color("tabInactiveColor", "Other tab text", initial.tabInactiveColor),
    B.Color("accentColor", "Accent color", initial.accentColor),
    B.Number("accentAlpha", "Accent opacity (percent)", initial.accentAlpha, 0, 100, 5),
})
B.Section(id, "sidebar", "Button sidebar", {
    B.Choice("sidebarSide", "Sidebar side", 1, {"Left", "Right"}),
    B.Color("sidebarColor", "Sidebar background", initial.panelColor),
    B.Number("sidebarAlpha", "Sidebar background opacity", 82, 0, 100),
    B.Number("sidebarGap", "Sidebar button spacing", 2, 0, 20),
    B.Choice("scrollButtonPlace", "Newest message button", 1, {"Sidebar", "Chat panel"}),
    B.Bool("sidebarPanel", "Use MSUF chat icons and button sidebar", initial.sidebarPanel),
    B.Bool("hideNativeButtons", "Hide Blizzard chat buttons", false),
    B.Number("sidebarWidth", "Sidebar width", initial.sidebarWidth, 20, 48),
    B.Bool("sidebarClassColor", "Use class color for sidebar icons", false),
})
B.Section(id, "input", "Input line", {
    B.Number("inputX", "Horizontal position", 0, -400, 400),
    B.Number("inputY", "Vertical position", 0, -300, 300),
    B.Bool("inputTop", "Place input above the chat panel", false),
    B.Number("inputHeight", "Input height (0 follows Blizzard)", 0, 0, 60),
    B.Bool("inputPanel", "Show input background", initial.inputPanel),
    B.Color("inputColor", "Input background color", initial.inputColor),
    B.Number("inputAlpha", "Input opacity (percent)", initial.inputAlpha, 0, 100, 5),
    B.Tooltip(B.Bool("saveInputHistory", "Remember typed lines between sessions", false),
        "Brings back the lines you typed last time with the Up arrow. Lines that start with /script, /run or /dump are never saved."),
})
-- Shift-dragged sidebar icons (Chat/Sidebar.lua); labels translate their format.
-- An icon's position acts only on the MSUF sidebar, and only once it is moved.
for index = 1, 5 do
    local prefix = "sidebarButton" .. index
    local moved = B.Add(id, B.Bool(prefix .. "Moved", NS.Text("Custom position for sidebar icon %d"):format(index), false), "sidebar")
    moved.enableKey = "sidebarPanel"
    B.Add(id, B.Number(prefix .. "X", NS.Text("Sidebar icon %d X"):format(index), 0, -400, 400), "sidebar").enableKey = moved.key
    B.Add(id, B.Number(prefix .. "Y", NS.Text("Sidebar icon %d Y"):format(index), 0, -800, 800), "sidebar").enableKey = moved.key
end
B.Section(id, "text", "Message text", {
    B.Number("messageTextX", "Horizontal position", 0, -400, 400),
    B.Number("messageTextY", "Vertical position", 0, -300, 300),
    B.Bool("messageFading", "Fade individual messages", false),
    B.Number("messageTimeVisible", "Message visibility (seconds)", 20, 5, 120),
    B.Number("messageFadeDuration", "Message fade duration (seconds)", 3, 0.1, 10, 0.1),
    B.Number("fontSize", "Font size", 0, 0, 24),
    B.Font("font", "Font"),
    B.Choice("fontOutline", "Text outline", 1, { "Follow Blizzard", "Outline", "Thick outline", "None" }),
    B.Choice("fontRendering", "Font rendering", 3, { "Smooth", "Sharp / pixel", "Slug" }),
    B.Choice("fontShadow", "Text shadow", 1, { "Follow Blizzard", "On", "Off" }),
    B.Number("fontShadowOpacity", "Shadow opacity (percent)", 100, 20, 100, 5),
    B.Choice("fontShadowDistance", "Shadow distance", 1, { "1 px", "2 px" }),
})
-- The scrollback a window can keep: choice 1 leaves Blizzard's 128 lines
-- alone, the later choices are these limits (Chat's History.lua applies them).
NS.ChatLineLimits = { 256, 512, 1000, 2000 }
local lineChoices = { "Keep Blizzard's setting" }
for index, lines in ipairs(NS.ChatLineLimits) do lineChoices[index + 1] = NS.Text("%d lines"):format(lines) end
B.Section(id, "tools", "Chat tools", {
    B.Bool("saveHistory", "Save chat history for this character and tab", false),
    B.Number("historyLines", "Saved lines per tab", 200, 20, 1000, 20),
    B.Tooltip(B.Choice("maxLines", "Lines kept per chat window", 1, lineChoices),
        "Blizzard keeps 128 lines in each window. A higher limit lets you scroll back further and lets saved history fill the window."),
    B.Bool("linkURLs", "Clickable URLs with a copy box", false),
    B.Bool("allTimestamps", "Timestamp every public displayed message", false),
    B.String("timestampFormat", "Custom timestamp format", "[%H:%M]", 64),
    B.Bool("shortenChannels", "Abbreviate channel prefixes", false),
    B.String("channelShortcuts", "World channel shortcuts (name=short; name=short)", "", 256),
    B.Bool("colorMentionNames", "Class colors for group names in message text", false),
    B.Number("whisperSoundKit", "Whisper sound kit ID (0 disables)", 0, 0, 1000000),
    B.String("whisperSound", "Custom whisper sound file", "", 240),
    B.Bool("completeMessages", "Show only complete messages", false),
    B.Bool("copyMessages", "Show Copy button for chat messages", false),
    B.Number("copyButtonX", "Copy button X", 0, -200, 200),
    B.Number("copyButtonY", "Copy button Y", 0, -200, 200),
})
-- The channels that can play a sound: the chat events of each and the
-- settings holding its sound, a sound kit ID or a custom file (the file wins).
-- Whisper keeps the settings it always had, in Chat tools; Chat's Messages.lua
-- listens only for the channels that have a sound.
NS.ChatSoundChannels = {
    { label = "Whisper", events = { "CHAT_MSG_WHISPER" }, kit = "whisperSoundKit", file = "whisperSound" },
    { label = "Battle.net whisper", events = { "CHAT_MSG_BN_WHISPER" },
      kit = "bnWhisperSoundKit", file = "bnWhisperSound" },
    { label = "Guild", events = { "CHAT_MSG_GUILD" }, kit = "guildSoundKit", file = "guildSound" },
    { label = "Officer", events = { "CHAT_MSG_OFFICER" }, kit = "officerSoundKit", file = "officerSound" },
    { label = "Party", events = { "CHAT_MSG_PARTY" }, kit = "partySoundKit", file = "partySound" },
    { label = "Party leader", events = { "CHAT_MSG_PARTY_LEADER" },
      kit = "partyLeaderSoundKit", file = "partyLeaderSound" },
    { label = "Raid", events = { "CHAT_MSG_RAID" }, kit = "raidSoundKit", file = "raidSound" },
    { label = "Raid leader", events = { "CHAT_MSG_RAID_LEADER" },
      kit = "raidLeaderSoundKit", file = "raidLeaderSound" },
    { label = "Instance", events = { "CHAT_MSG_INSTANCE_CHAT" },
      kit = "instanceSoundKit", file = "instanceSound" },
}
local soundRules = {}
for index = 2, #NS.ChatSoundChannels do
    local channel = NS.ChatSoundChannels[index]
    local name = NS.Text(channel.label)
    soundRules[#soundRules + 1] = B.Number(channel.kit, NS.Text("%s sound kit ID (0 disables)"):format(name), 0, 0, 1000000)
    soundRules[#soundRules + 1] = B.String(channel.file, NS.Text("%s custom sound file"):format(name), "", 240)
end
B.Section(id, "sounds", "Channel sounds", soundRules)
B.Section(id, "highlight", "Keyword highlight", {
    B.Bool("highlightKeywords", "Highlight keywords in chat messages", false),
    B.String("highlightWords", "Words to highlight (separated by commas)", "", 256),
    B.Tooltip(B.Bool("highlightOwnName", "Also highlight my character name", false),
        "Marks your character's name inside messages, so you notice when somebody mentions you."),
    B.Color("highlightColor", "Highlight color", "ffd100"),
})
-- Where a speech bubble's text came from. Blizzard switches nearby, party
-- and raid bubbles separately (chatBubbles, chatBubblesParty,
-- chatBubblesRaid); yells, creature speech and emotes show with the nearby
-- ones. Chat's Bubbles.lua styles a bubble for the source whose chat event
-- carried its text; `edge` is that chat type's default color, the source's
-- own border.
NS.ChatBubbleSources = {
    { key = "Nearby", label = "Nearby speech", edge = "ffffff", events = { "CHAT_MSG_SAY" } },
    { key = "Yell", label = "Yells", edge = "ff4040", events = { "CHAT_MSG_YELL" } },
    { key = "Party", label = "Party members", edge = "aaaaff",
      events = { "CHAT_MSG_PARTY", "CHAT_MSG_PARTY_LEADER" } },
    { key = "Raid", label = "Raid members", edge = "ff7f00",
      events = { "CHAT_MSG_RAID", "CHAT_MSG_RAID_LEADER" } },
    { key = "Creature", label = "Creatures", edge = "ffff9f",
      events = { "CHAT_MSG_MONSTER_SAY", "CHAT_MSG_MONSTER_YELL", "CHAT_MSG_MONSTER_PARTY" } },
    { key = "Emote", label = "Emotes", edge = "ff8040",
      events = { "CHAT_MSG_EMOTE", "CHAT_MSG_TEXT_EMOTE", "CHAT_MSG_MONSTER_EMOTE" } },
}
B.Section(id, "bubbles", "Speech bubbles", {
    B.Bool("styleBubbles", "MSUF look for speech bubbles outside instances", false),
    B.Bool("hideInstanceBubbles", "Turn speech bubbles off inside instances", false),
    B.Font("bubbleFont", "Bubble font"),
    B.Number("bubbleFontSize", "Bubble text size", 14, 8, 30),
    B.Color("bubbleTextColor", "Bubble text color", "ffffff"),
    B.Color("bubbleBackground", "Bubble background color", "101010"),
    B.Number("bubbleAlpha", "Bubble background opacity (percent)", 80, 0, 100),
    B.Color("bubbleBorder", "Bubble border color", "575b58"),
    B.Number("bubblePadding", "Space around bubble text", 8, 0, 24),
    B.Number("bubbleMaxWidth", "Widest bubble text (pixels)", 300, 80, 600),
})
-- Per source: keep Blizzard's look or the MSUF one, either the shared look
-- above or the source's own font, size, colors, spacing and width. Labels
-- translate their format and the source name.
for _, source in ipairs(NS.ChatBubbleSources) do
    local key, label = source.key, NS.Text(source.label)
    local function Label(format) return NS.Text(format):format(label) end
    local rules = {
        B.Bool("bubbleStyle" .. key, Label("%s: MSUF bubble look"), true),
        B.Bool("bubbleOwn" .. key, Label("%s: own bubble look"), false),
        B.Font("bubbleFont" .. key, Label("%s: bubble font")),
        B.Number("bubbleSize" .. key, Label("%s: bubble text size"), 14, 8, 30),
        B.Color("bubbleText" .. key, Label("%s: bubble text color"), "ffffff"),
        B.Color("bubbleFill" .. key, Label("%s: bubble background color"), "101010"),
        B.Number("bubbleOpacity" .. key, Label("%s: bubble background opacity (percent)"), 80, 0, 100),
        B.Color("bubbleEdge" .. key, Label("%s: bubble border color"), source.edge),
        B.Number("bubblePad" .. key, Label("%s: space around bubble text"), 8, 0, 24),
        B.Number("bubbleWidth" .. key, Label("%s: widest bubble text (pixels)"), 300, 80, 600),
    }
    -- The MSUF look needs the bubble styling on, the own look needs the MSUF
    -- look, and each part of it (the rules after the two switches) the own look.
    rules[1].enableKey = "styleBubbles"
    rules[2].enableKey = rules[1].key
    for index = 3, #rules do rules[index].enableKey = rules[2].key end
    for _, rule in ipairs(rules) do B.Add(id, rule, "bubbles") end
end
local textRules = NS.SuiteCatalog[id].rules
-- Settings that act only while their switch is on stay greyed out until then
-- (the menu only; stored values never change).
textRules.windowWidth.enableKey = "lockWindowSize"
textRules.windowHeight.enableKey = "lockWindowSize"
textRules.windowX.enableKey = "lockWindowPosition"
textRules.windowY.enableKey = "lockWindowPosition"
textRules.historyLines.enableKey = "saveHistory"
textRules.timestampFormat.enableKey = "allTimestamps"
textRules.copyButtonX.enableKey = "copyMessages"
textRules.copyButtonY.enableKey = "copyMessages"
textRules.channelShortcuts.enableKey = "shortenChannels"
-- The sidebar settings shape the MSUF sidebar only; hiding Blizzard's buttons
-- works without it. The input colors paint the MSUF input background.
for _, key in ipairs({ "sidebarSide", "sidebarColor", "sidebarAlpha", "sidebarGap", "scrollButtonPlace",
    "sidebarWidth", "sidebarClassColor" }) do
    textRules[key].enableKey = "sidebarPanel"
end
textRules.inputColor.enableKey = "inputPanel"
textRules.inputAlpha.enableKey = "inputPanel"
-- The tab strip gap, and the individual tab backgrounds with their parts, need the dark tab strip.
textRules.tabPanelGap.enableKey = "tabPanel"
textRules.tabIndividualPanels.enableKey = "tabPanel"
for _, key in ipairs({ "tabActiveBackground", "tabInactiveBackground", "tabActiveAlpha", "tabInactiveAlpha",
    "tabBorderSize", "tabActiveBorder", "tabInactiveBorder" }) do
    textRules[key].enableKey = "tabIndividualPanels"
end
for _, key in ipairs({ "bubbleFont", "bubbleFontSize", "bubbleTextColor", "bubbleBackground", "bubbleAlpha",
    "bubbleBorder", "bubblePadding", "bubbleMaxWidth" }) do
    textRules[key].enableKey = "styleBubbles"
end
textRules.messageTimeVisible.enableKey = "messageFading"
textRules.messageFadeDuration.enableKey = "messageFading"
for _, key in ipairs({ "highlightWords", "highlightOwnName", "highlightColor" }) do
    textRules[key].enableKey = "highlightKeywords"
end
textRules.font.defaultLabel = "MSUF global font (default)"
textRules.tabFont.defaultLabel = "MSUF global font (default)"
for _, key in ipairs({ "fontShadowOpacity", "fontShadowDistance" }) do
    textRules[key].requiresChoice = { key = "fontShadow", values = { [2] = true } }
end

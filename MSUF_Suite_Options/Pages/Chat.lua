local _, P = ...
local M, Tr, HM = P.M, P.Tr, P.HM
local PAGE, ID = "suite_chat", "chat"
P.Gates[ID] = function(rule)
    if rule.key == "panelTexture" then return not P.Get(ID, "panelGradient") end
    -- The fade acts only while a delay is set; 0 is off, which an enableKey cannot say.
    if rule.key == "idleAlpha" or rule.key == "idleFadeDuration" then return P.Get(ID, "idleSeconds") > 0 end
    if rule.key == "fontShadow" or rule.key == "fontShadowOpacity"
        or rule.key == "fontShadowDistance" then
        return P.Get(ID, "fontRendering") ~= P.Suite.FontRendering.SLUG
    end
    return true
end
-- Build native timestamps and history controls only when Chat tools opens.
local function ToolsExtra(ctx, body, y, width)
    local function TimestampValues()
        local TIMESTAMP_KEYS = {
            "TIMESTAMP_FORMAT_HHMM", "TIMESTAMP_FORMAT_HHMMSS",
            "TIMESTAMP_FORMAT_HHMM_AMPM", "TIMESTAMP_FORMAT_HHMMSS_AMPM",
            "TIMESTAMP_FORMAT_HHMM_24HR", "TIMESTAMP_FORMAT_HHMMSS_24HR",
        }
        local values = { { value = "none", text = Tr("Off") } }
        local example = { year = 2010, month = 12, day = 15, hour = 15, min = 27, sec = 32 }
        local when = time(example)
        for _, key in ipairs(TIMESTAMP_KEYS) do
            local format = _G[key]
            if type(format) == "string" and format ~= "" then
                local label = TimeUtil.BetterDate(format, when) or format
                values[#values + 1] = { value = format, text = label }
            end
        end
        return values
    end
    local function History(clear)
        if P.Combat() then return end
        if not P.S.instances.chat then C_AddOns.LoadAddOn("MSUF_Suite_Chat") end
        local chat = P.S.instances.chat
        if not chat then return end
        if clear then chat:ClearHistory() else chat:OpenHistory() end
    end
    local row = P.Meta(PAGE, ID, "timestamp", "setting", PAGE .. "_tools")
    row.id, row.label, row.kind = "timestamp", Tr("Timestamps (Blizzard setting)"), "dropdown"
    row.values = TimestampValues
    row.get = function() return C_CVar.GetCVar("showTimestamps") or "none" end
    row.set = function(value) if type(value) == "string" then C_CVar.SetCVar("showTimestamps", value) end end
    row.settingKey = "showTimestamps"
    local grid = P.W.SettingsRows(ctx, body, { x = 16, y = y, width = width, columns = 2, rows = { row } })
    P.Button(ctx, body, "Clear saved chat history", 16, grid.bottomY, width, function()
        P.Confirm("clear-chat-history",
            Tr("Clear the saved chat history of this character in every chat window? This cannot be undone."), function() History(true) end)
    end, function() return not P.Combat() end, P.Meta(PAGE, ID, "clearHistory", "action", PAGE .. "_tools"))
    P.Button(ctx, body, "Search saved chat", 16, grid.bottomY - 36, width, function() History(false) end,
        function() return not P.Combat() end, P.Meta(PAGE, ID, "searchHistory", "action", PAGE .. "_tools"))
    return grid.bottomY - 76
end

local function ImmersiveButton(ctx)
    return function(body, y, width)
        local button = P.T.Button(body, "Immersive", width, 26)
        button:SetPoint("TOPLEFT", body, "TOPLEFT", 16, y)
        button:SetScript("OnClick", function()
            if not P.Combat() then P.Set(ID, "look", 7) end
        end)
        if M.RegisterControlMetadata then
            M.RegisterControlMetadata(button, P.Meta(PAGE, ID, "look.7", "action", PAGE .. "_look"), "Immersive", "button")
        end
        M.TrackRefresh(ctx, function()
            button:SetAlpha(P.Get(ID, "look") == 7 and 1 or 0.65)
            button:SetEnabled(P.RuleEnabled(ID, P.catalog[ID].rules.look))
        end)
        return y - 38
    end
end

-- The sections after Chat tools: a sound per channel and the keyword highlight.
local function BuildMessageSections(ctx, b)
    P.ChatPreviewPositions.CoordinateSection(ctx, b, PAGE .. "_sounds", Tr("Channel sounds"),
        P.SectionRules(ID, "sounds"), {
            help = "A channel plays a sound kit ID or a sound file (the file wins) for new messages. A burst plays once. Whisper is under Chat tools.",
        })
    P.ChatPreviewPositions.CoordinateSection(ctx, b, PAGE .. "_highlight", Tr("Keyword highlight"),
        P.SectionRules(ID, "highlight"), {
            help = "Words from your list are colored inside chat messages, whatever their capitals. Links and URLs stay as they are.",
        })
end

local function Build(ctx)
    local b = P.W.PageBuilder(ctx)
    P.ChatPreview.Build(ctx, b)
    P.ModuleCard(ctx, b, PAGE, ID)
    P.ChatPreviewPositions.CoordinateSection(ctx, b, PAGE .. "_look", Tr("Choose a look"),
        P.SectionRules(ID, "look"), {
            open = true,
            help = P.Help("Choose a look, then adjust its colors.", "Clean Modern is the Retail default; MSUF Forever is the Forever default. Midnight Blue keeps the original blue glass. Open a section's three-dot menu to change its colors, or use MSUF Colors for the full palette. Your own color changes become Custom."),
            extra = P.LookPresetButtons(ctx, PAGE, ID, PAGE .. "_look", ImmersiveButton(ctx)),
        })
    P.ChatPreviewPositions.CoordinateSection(ctx, b, PAGE .. "_window", Tr("Chat window"),
        P.SectionRules(ID, "window"), {
            open = true,
            help = "A click-through surface follows each Blizzard chat window. Blizzard and MSUF Edit Mode keep their normal move and resize controls.",
        })
    P.ChatPreviewPositions.CoordinateSection(ctx, b, PAGE .. "_tabs", Tr("Tabs and accent"),
        P.SectionRules(ID, "tabs"), {
            help = "Tabs stay clickable and keep Blizzard's dock and unread state. The dark strip connects them to the message panel.",
        })
    P.ChatPreviewPositions.CoordinateSection(ctx, b, PAGE .. "_sidebar", Tr("Button sidebar"),
        P.SectionRules(ID, "sidebar"), {
            help = "MSUF icons replace the scattered Blizzard chat controls. Friends, channels, text to speech and the chat menu keep their Blizzard actions; the bottom icon jumps to the newest message. Turn this off to restore the native buttons.",
        })
    P.ChatPreviewPositions.CoordinateSection(ctx, b, PAGE .. "_input", Tr("Input line"),
        P.SectionRules(ID, "input"), {
            help = "The native input box keeps autocomplete, links and chat commands.",
        })
    P.ChatPreviewPositions.CoordinateSection(ctx, b, PAGE .. "_text", Tr("Message text"),
        P.SectionRules(ID, "text"), {
            help = "The default font follows MSUF Fonts while the default size follows Blizzard's chat size. Choose Blizzard chat font to keep its own face. Slug has no shadow.",
        })
    P.ChatPreviewPositions.CoordinateSection(ctx, b, PAGE .. "_tools", Tr("Chat tools"),
        P.SectionRules(ID, "tools"), {
            help = "Timestamps use Blizzard's chat setting across all chat windows. Copy is off by default; when enabled, move its button with X/Y, choose a message, then press Ctrl+C. The displayed timestamp is included when timestamps are on. The message tools leave the Combat Log alone (its own settings can add a timestamp to every line); its lines still wake the idle fade. Saved history belongs to this character.",
            extra = function(body, y, width) return ToolsExtra(ctx, body, y, width) end,
        })
    BuildMessageSections(ctx, b)
    P.BuildOwnedTool(ctx, b, "keywordAlerts")
    P.ChatPreviewPositions.CoordinateSection(ctx, b, PAGE .. "_bubbles", Tr("Speech bubbles"), P.SectionRules(ID, "bubbles"), {
        help = "Bubbles outside instances can take the MSUF look; Blizzard locks the ones inside instances. Each source keeps Blizzard's look or uses the MSUF one: the shared look or its own font, size, colors, spacing and width. A bubble is matched to the line it shows right after that line arrives. Turning bubbles off inside instances uses Blizzard's bubble settings and gives them back when you leave or turn it off.",
    })
end

P.RegisterPage({ key = PAGE, label = "Chat", title = "Chat", build = Build, icon = { 4, 0 },
    nav = "interface", navOrder = 5,
    aliases = { "chat", "chatframes", "chatframe" } })

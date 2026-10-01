local _, P = ...
local M, Tr = P.M, P.Tr
local PAGE, ID = "suite_chat", "chat"
-- A bubble source's own look shows only while that source uses it.
local OWN_PARTS = { "bubbleFont", "bubbleSize", "bubbleText", "bubbleFill", "bubbleOpacity", "bubbleEdge",
    "bubblePad", "bubbleWidth" }
local OWNED = {}
for _, source in ipairs(P.Suite.ChatBubbleSources) do
    for _, part in ipairs(OWN_PARTS) do OWNED[part .. source.key] = "bubbleOwn" .. source.key end
end
P.Gates[ID] = function(rule)
    local own = OWNED[rule.key]
    if own then return P.Get(ID, own) == true end
    if rule.key == "tabActiveBackground" or rule.key == "tabInactiveBackground"
        or rule.key == "tabActiveAlpha" or rule.key == "tabInactiveAlpha"
        or rule.key == "tabBorderSize" or rule.key == "tabActiveBorder"
        or rule.key == "tabInactiveBorder" then
        return P.Get(ID, "tabIndividualPanels") == true
    end
    if rule.key == "fontShadow" or rule.key == "fontShadowOpacity"
        or rule.key == "fontShadowDistance" then
        return P.Get(ID, "fontRendering") ~= 3
    end
    return true
end
local WHITE = "Interface\\Buttons\\WHITE8X8"
local GLYPHS = "Interface\\AddOns\\MSUF_Suite_Chat\\Media\\MSUFChatGlyphs.png"

-- Blizzard owns chat timestamps through the global showTimestamps CVar. Keep
-- this row bound to that native setting so Suite profiles cannot silently
-- override a choice made in Blizzard's Social options.
local TIMESTAMP_KEYS = {
    "TIMESTAMP_FORMAT_HHMM", "TIMESTAMP_FORMAT_HHMMSS",
    "TIMESTAMP_FORMAT_HHMM_AMPM", "TIMESTAMP_FORMAT_HHMMSS_AMPM",
    "TIMESTAMP_FORMAT_HHMM_24HR", "TIMESTAMP_FORMAT_HHMMSS_24HR",
}

local function TimestampValues()
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

local function TimestampSetting()
    return C_CVar.GetCVar("showTimestamps") or "none"
end

local function SetTimestamp(value)
    if type(value) == "string" then C_CVar.SetCVar("showTimestamps", value) end
end

-- Saved lines live in the Chat addon's per-character saved variables. A
-- character whose Chat module is off loads the addon (load on demand) to
-- clear them; loading it enables nothing.
local function ClearHistory()
    if not P.S.instances.chat then C_AddOns.LoadAddOn("MSUF_Suite_Chat") end
    local chat = P.S.instances.chat
    if chat then chat:ClearHistory() end
end

local function Color(texture, hex, alpha)
    local r, g, b = P.RGB(hex)
    texture:SetVertexColor(r, g, b, (alpha or 100) / 100)
end

local function RefreshSampleText(label, otherTab, lines, fonts)
    local ar, ag, ab = P.RGB(P.Get(ID, "tabActiveColor"))
    local ir, ig, ib = P.RGB(P.Get(ID, "tabInactiveColor"))
    label:SetTextColor(ar, ag, ab)
    otherTab:SetTextColor(ir, ig, ib)
    local selectedTabSize = tonumber(P.Get(ID, "tabFontSize")) or 0
    local selectedMessageSize = tonumber(P.Get(ID, "fontSize")) or 0
    if fonts.tab then
        local size = selectedTabSize > 0 and selectedTabSize or fonts.tabSize
        label:SetFont(fonts.tab, size, fonts.tabFlags)
        otherTab:SetFont(fonts.tab, size, fonts.tabFlags)
    end
    if fonts.message then
        lines:SetFont(fonts.message, selectedMessageSize > 0 and selectedMessageSize or fonts.messageSize,
            fonts.messageFlags)
    end
end

local function Sample(body, y, width, ctx)
    local sample = CreateFrame("Frame", nil, body)
    sample:SetPoint("TOPLEFT", body, "TOPLEFT", 16, y)
    sample:SetSize(width, 108)
    local fill = sample:CreateTexture(nil, "BACKGROUND")
    fill:SetAllPoints(sample)
    fill:SetTexture(WHITE)
    local sidebar = sample:CreateTexture(nil, "BORDER")
    sidebar:SetTexture(WHITE)
    sidebar:SetPoint("TOPLEFT")
    sidebar:SetPoint("BOTTOMLEFT")
    sidebar:SetWidth(28)
    local icons = {}
    for i, glyphIndex in ipairs({ 0, 1, 3, 4 }) do
        local icon = sample:CreateTexture(nil, "ARTWORK")
        icon:SetTexture(GLYPHS)
        icon:SetTexCoord(glyphIndex / 8, (glyphIndex + 1) / 8, 0, 1)
        icon:SetPoint("TOPLEFT", sample, "TOPLEFT", 5, -4 - (i - 1) * 25)
        icon:SetSize(18, 18)
        icons[#icons + 1] = icon
    end
    local top = sample:CreateTexture(nil, "BORDER")
    top:SetTexture(WHITE)
    top:SetPoint("TOPLEFT")
    top:SetPoint("TOPRIGHT")
    top:SetHeight(1)
    local accent = sample:CreateTexture(nil, "ARTWORK")
    accent:SetTexture(WHITE)
    accent:SetPoint("TOPLEFT", sample, "TOPLEFT", 38, -27)
    accent:SetSize(42, 2)
    local label = sample:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    label:SetPoint("TOPLEFT", sample, "TOPLEFT", 38, -8)
    label:SetText(Tr("General"))
    local otherTab = sample:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    otherTab:SetPoint("LEFT", label, "RIGHT", 16, 0)
    otherTab:SetText(Tr("Party"))
    local lines = sample:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    lines:SetPoint("TOPLEFT", sample, "TOPLEFT", 39, -43)
    lines:SetWidth(width - 50)
    lines:SetJustifyH("LEFT")
    lines:SetText("|cff9fc3e7[" .. Tr("Guild") .. "]|r Mapko: " .. Tr("Welcome to MSUF.") .. "\n|cffc9d4dd["
        .. Tr("Party") .. "]|r " .. Tr("Chat links and channels stay native."))
    local input = sample:CreateTexture(nil, "BORDER")
    input:SetTexture(WHITE)
    input:SetPoint("BOTTOMLEFT", sample, "BOTTOMLEFT", 36, 8)
    input:SetPoint("BOTTOMRIGHT", sample, "BOTTOMRIGHT", -8, 8)
    input:SetHeight(17)
    local prompt = sample:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    prompt:SetPoint("BOTTOMLEFT", sample, "BOTTOMLEFT", 43, 10)
    prompt:SetText(Tr("Say:"))
    local fonts = {}
    fonts.tab, fonts.tabSize, fonts.tabFlags = label:GetFont()
    fonts.message, fonts.messageSize, fonts.messageFlags = lines:GetFont()
    M.TrackRefresh(ctx, function()
        Color(fill, P.Get(ID, "panelColor"), P.Get(ID, "panelAlpha"))
        Color(sidebar, P.Get(ID, "panelColor"), math.min(100, P.Get(ID, "panelAlpha") + 8))
        sidebar:SetShown(P.Get(ID, "sidebarPanel"))
        local r, g, b = P.RGB(P.Get(ID, "accentColor"))
        for _, icon in ipairs(icons) do
            icon:SetVertexColor(r, g, b, P.Get(ID, "accentAlpha") / 100)
            icon:SetShown(P.Get(ID, "sidebarPanel"))
        end
        Color(top, P.Get(ID, "accentColor"), P.Get(ID, "accentAlpha"))
        top:SetHeight(2)
        top:SetShown(P.Get(ID, "tabPanel") and P.Get(ID, "tabAccent")
            and P.Get(ID, "accentAlpha") > 0)
        Color(accent, P.Get(ID, "accentColor"), P.Get(ID, "accentAlpha"))
        accent:SetShown(P.Get(ID, "tabPanel") and P.Get(ID, "tabAccent")
            and P.Get(ID, "accentAlpha") > 0)
        RefreshSampleText(label, otherTab, lines, fonts)
        Color(input, P.Get(ID, "inputColor"), P.Get(ID, "inputAlpha"))
        input:SetShown(P.Get(ID, "inputPanel"))
    end)
    return y - 121
end

local function Build(ctx)
    local b = P.W.PageBuilder(ctx)
    local preview = P.W.FixedPreviewSection(ctx, b, {
        title = Tr("Preview"), height = 176, gap = 8,
    })
    if preview then
        local width = math.max(240, (preview._msuf2Width or b.width or 720) - 32)
        Sample(preview, -48, width, ctx)
    end
    P.ModuleCard(ctx, b, PAGE, ID)
    P.RuleSection(ctx, b, PAGE, ID, PAGE .. "_look", Tr("Choose a look"),
        P.SectionRules(ID, "look"), {
            open = true,
            help = P.Help("Choose a look, then adjust its colors.", "Clean Modern is the Retail default; MSUF Forever is the Forever default. Midnight Blue keeps the original blue glass. Open a section's three-dot menu to change its colors, or use MSUF Colors for the full palette. Your own color changes become Custom."),
            extra = P.LookPresetButtons(ctx, PAGE, ID, PAGE .. "_look"),
        })
    P.RuleSection(ctx, b, PAGE, ID, PAGE .. "_window", Tr("Chat window"),
        P.SectionRules(ID, "window"), {
            open = true,
            help = "A click-through surface follows each Blizzard chat window. Blizzard and MSUF Edit Mode keep their normal move and resize controls.",
        })
    P.RuleSection(ctx, b, PAGE, ID, PAGE .. "_tabs", Tr("Tabs and accent"),
        P.SectionRules(ID, "tabs"), {
            help = "Tabs stay clickable and keep Blizzard's dock and unread state. The dark strip connects them to the message panel.",
        })
    P.RuleSection(ctx, b, PAGE, ID, PAGE .. "_sidebar", Tr("Button sidebar"),
        P.SectionRules(ID, "sidebar"), {
            help = "MSUF icons replace the scattered Blizzard chat controls. Friends, channels, text to speech and the chat menu keep their Blizzard actions; the bottom icon jumps to the newest message. Turn this off to restore the native buttons.",
        })
    P.RuleSection(ctx, b, PAGE, ID, PAGE .. "_input", Tr("Input line"),
        P.SectionRules(ID, "input"), {
            help = "The native input box keeps autocomplete, links and chat commands.",
        })
    P.RuleSection(ctx, b, PAGE, ID, PAGE .. "_text", Tr("Message text"),
        P.SectionRules(ID, "text"), {
            help = "The default font follows MSUF Fonts while the default size follows Blizzard's chat size. Choose Blizzard chat font to keep its own face. Slug has no shadow.",
        })
    P.RuleSection(ctx, b, PAGE, ID, PAGE .. "_tools", Tr("Chat tools"),
        P.SectionRules(ID, "tools"), {
            help = "Timestamps use Blizzard's chat setting across all chat windows. Copy is off by default; when enabled, move its button with X/Y, choose a message, then press Ctrl+C. The displayed timestamp is included when timestamps are on. The message tools leave the Combat Log alone (its own settings can add a timestamp to every line); its lines still wake the idle fade. Saved history belongs to this character.",
            extra = function(body, y, width)
                local row = P.Meta(PAGE, ID, "timestamp", "setting", PAGE .. "_tools")
                row.id = "timestamp"
                row.label = Tr("Timestamps (Blizzard setting)")
                row.kind = "dropdown"
                row.values = TimestampValues
                row.get = TimestampSetting
                row.set = SetTimestamp
                row.settingKey = "showTimestamps"
                local grid = P.W.SettingsRows(ctx, body, {
                    x = 16, y = y, width = width, columns = 2,
                    rows = { row },
                })
                P.Button(ctx, body, "Clear saved chat history", 16, grid.bottomY, width, ClearHistory,
                    function() return not P.Combat() end,
                    P.Meta(PAGE, ID, "clearHistory", "action", PAGE .. "_tools"))
                return grid.bottomY - 40
            end,
        })
    P.RuleSection(ctx, b, PAGE, ID, PAGE .. "_bubbles", Tr("Speech bubbles"), P.SectionRules(ID, "bubbles"), {
        help = "Bubbles outside instances can take the MSUF look; Blizzard locks the ones inside instances. Each source keeps Blizzard's look or uses the MSUF one: the shared look or its own font, size, colors, spacing and width. A bubble is matched to the line it shows right after that line arrives. Turning bubbles off inside instances uses Blizzard's bubble settings and gives them back when you leave or turn it off.",
    })
end

P.RegisterPage({ key = PAGE, label = "Chat", title = "Chat", build = Build, icon = { 4, 0 },
    aliases = { "chat", "chatframes", "chatframe" } })

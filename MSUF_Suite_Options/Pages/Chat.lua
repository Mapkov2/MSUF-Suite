local _, P = ...
local S, M, T, Tr = P.S, P.M, P.T, P.Tr
local PAGE, ID = "suite_chat", "chat"
P.Gates[ID] = function(rule)
    if rule.key == "fontShadow" or rule.key == "fontShadowOpacity"
        or rule.key == "fontShadowDistance" then
        return P.Get(ID, "fontRendering") ~= 3
    end
    return true
end
local WHITE = "Interface\\Buttons\\WHITE8X8"
local GLYPHS = "Interface\\AddOns\\MSUF_Suite_Chat\\Media\\MSUFChatGlyphs.png"

local function Color(texture, hex, alpha)
    local r, g, b = P.RGB(hex)
    texture:SetVertexColor(r, g, b, (alpha or 100) / 100)
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
    local lines = sample:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    lines:SetPoint("TOPLEFT", sample, "TOPLEFT", 39, -43)
    lines:SetWidth(width - 50)
    lines:SetJustifyH("LEFT")
    lines:SetText("|cff9fc3e7[Guild]|r Mapko: Welcome to MSUF.\n|cffc9d4dd[Party]|r Chat links and channels stay native.")
    local input = sample:CreateTexture(nil, "BORDER")
    input:SetTexture(WHITE)
    input:SetPoint("BOTTOMLEFT", sample, "BOTTOMLEFT", 36, 8)
    input:SetPoint("BOTTOMRIGHT", sample, "BOTTOMRIGHT", -8, 8)
    input:SetHeight(17)
    local prompt = sample:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    prompt:SetPoint("BOTTOMLEFT", sample, "BOTTOMLEFT", 43, 10)
    prompt:SetText(Tr("Say:"))
    M.TrackRefresh(ctx, function()
        Color(fill, P.Get(ID, "panelColor"), P.Get(ID, "panelAlpha"))
        Color(sidebar, P.Get(ID, "panelColor"), math.min(100, P.Get(ID, "panelAlpha") + 8))
        sidebar:SetShown(P.Get(ID, "sidebarPanel"))
        local r, g, b = P.RGB(P.Get(ID, "accentColor"))
        for _, icon in ipairs(icons) do
            icon:SetVertexColor(r, g, b, P.Get(ID, "accentAlpha") / 100)
            icon:SetShown(P.Get(ID, "sidebarPanel"))
        end
        Color(top, P.Get(ID, "borderColor"), P.Get(ID, "borderAlpha"))
        top:SetHeight(math.max(1, P.Get(ID, "borderSize")))
        top:SetShown(P.Get(ID, "borderSize") > 0 and P.Get(ID, "borderAlpha") > 0)
        Color(accent, P.Get(ID, "accentColor"), P.Get(ID, "accentAlpha"))
        accent:SetShown(P.Get(ID, "tabAccent"))
        Color(input, P.Get(ID, "inputColor"), P.Get(ID, "inputAlpha"))
        input:SetShown(P.Get(ID, "inputPanel"))
    end)
    return y - 121
end

local function Build(ctx)
    local b = P.W.PageBuilder(ctx)
    P.ModuleCard(ctx, b, PAGE, ID, {
        { "Reset module", function()
            P.WithHistory("Reset chat", "suite:chat.reset", function() return S.Reset(ID) end)
        end, function() return S.Availability(ID) end, key = "reset" },
    })
    P.RuleSection(ctx, b, PAGE, ID, PAGE .. "_look", Tr("Choose a look"),
        P.SectionRules(ID, "look"), {
            open = true,
            help = "Midnight Dark is the Retail default; MSUF Forever is the Forever default. Midnight Blue keeps the original blue glass. Your own color changes become Custom.",
            extra = function(body, y, width)
                local gap = 8
                local buttonWidth = math.floor((width - 2 * gap) / 3)
                for index, name in ipairs({ "Midnight Blue", "Midnight Dark", "MSUF Forever" }) do
                    local button = T.Button(body, Tr(name), buttonWidth, 26)
                    button:SetPoint("TOPLEFT", body, "TOPLEFT", 16 + (index - 1) * (buttonWidth + gap), y)
                    button:SetScript("OnClick", function()
                        if not P.Combat() then P.Set(ID, "look", index) end
                    end)
                    if M.RegisterControlMetadata then
                        M.RegisterControlMetadata(button, P.Meta(PAGE, ID, "look." .. index, "action", PAGE .. "_look"),
                            Tr(name), "button")
                    end
                    M.TrackRefresh(ctx, function()
                        button:SetAlpha(P.Get(ID, "look") == index and 1 or 0.65)
                        button:SetEnabled(P.RuleEnabled(ID, P.catalog[ID].rules.look))
                    end)
                end
                return Sample(body, y - 38, width, ctx)
            end,
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
            help = "Leave font and size at their defaults to follow Blizzard or MSUF Fonts. Choose an outline, shadow and Smooth, Sharp or Slug rendering for chat messages. Slug has no shadow.",
        })
end

P.RegisterPage({ key = PAGE, label = "Chat", title = "Chat", build = Build, icon = { 4, 0 },
    aliases = { "chat", "chatframes", "chatframe" } })

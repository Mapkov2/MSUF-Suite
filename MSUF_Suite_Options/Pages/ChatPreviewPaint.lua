local _, P = ...
local Paint, ID = {}, "chat"
P.ChatPreviewPaint = Paint
local Tr = P.Tr

local function SampleText()
    local lines = { Tr("|cff9fc3e7[Guild]|r %s: Welcome to MSUF."):format("Mapko"),
        Tr("|cffc9d4dd[Party]|r Chat links and channels stay native.") }
    if P.Get(ID, "highlightKeywords") then
        local function HighlightedWord()
            local word = P.Get(ID, "highlightWords"):match("[^,;\r\n]+")
            word = word and word:match("^%s*(.-)%s*$")
            if not word or word == "" then
                word = Tr("keyword")
                if P.Get(ID, "highlightOwnName") then
                    local name = UnitName("player")
                    if not P.Suite.IsSecret(name) and type(name) == "string" then word = name end
                end
            end
            local hex = P.Get(ID, "highlightColor"):match("^%x%x%x%x%x%x$") or "ffd100"
            return "|cff" .. hex .. word .. "|r"
        end
        lines[3] = Tr("|cffc9d4dd[Raid]|r %s: Pull when %s is ready."):format("Mapko", HighlightedWord())
    end
    return table.concat(lines, "\n")
end

function Paint.Build(ui)
    local function Font(owner, template, text)
        local label = owner:CreateFontString(nil, "OVERLAY", template)
        label:SetText(Tr(text))
        return label
    end

    local sample = CreateFrame("Frame", nil, ui.stage)
    sample:SetSize(420, 180)
    local parts = { sample = sample, settings = {}, tabs = {}, icons = {}, width = 420 }
    ui.parts, ui.ctx.chatPreview = parts, parts
    parts.tabGroup = CreateFrame("Frame", nil, sample)
    for index, label in ipairs({ "General", "Party" }) do
        local tab = CreateFrame("Frame", nil, parts.tabGroup)
        tab.Text = Font(tab, "GameFontNormalSmall", label)
        tab.Text:SetPoint("CENTER")
        parts.tabs[index] = tab
    end
    parts.label, parts.otherTab = parts.tabs[1].Text, parts.tabs[2].Text
    parts.textClip = CreateFrame("Frame", nil, sample)
    parts.textClip:SetAllPoints(sample)
    parts.textClip:SetClipsChildren(true)
    parts.messageLines = {}
    for index = 1, 3 do
        local line = Font(parts.textClip, "GameFontHighlightSmall", "")
        line:SetJustifyH("LEFT")
        parts.messageLines[index] = line
    end
    parts.lines = parts.messageLines[1]
    parts.lines:SetPoint("BOTTOMLEFT", sample, "BOTTOMLEFT", 0, 0)
    parts.textHit = CreateFrame("Frame", nil, parts.textClip)
    parts.textHit:SetAllPoints(parts.lines)
    parts.text = SampleText()
    parts.sidebar = CreateFrame("Frame", nil, sample)
    for index = 1, 5 do
        local icon = CreateFrame("Button", nil, parts.sidebar)
        icon:SetSize(24, 24)
        parts.icons[index] = icon
    end
    parts.input = CreateFrame("Frame", nil, sample)
    parts.prompt = Font(parts.input, "GameFontHighlightSmall", "Say:")
    parts.prompt:SetPoint("LEFT", 15, 0)
    parts.copy = CreateFrame("Button", nil, sample)
    parts.copy:SetSize(46, 19)
    parts.copy.label = Font(parts.copy, "GameFontNormalSmall", "Copy")
    parts.copy.label:SetPoint("CENTER")
    local fonts = {}
    fonts.tab, fonts.tabSize, fonts.tabFlags = parts.label:GetFont()
    fonts.message, fonts.messageSize, fonts.messageFlags = parts.lines:GetFont()
    local _, _, _, alpha = parts.lines:GetShadowColor()
    fonts.shadowAlpha, fonts.shadowX = alpha or 0, parts.lines:GetShadowOffset() or 1
    parts.fonts = fonts
end

function Paint.Refresh(ui)
    local parts = ui.parts
    if not parts.sample:IsVisible() then return end
    local config = P.S.Config(ID)
    local changed = P.PreviewCanvas.Changed(parts.settings, config, P.catalog[ID].rules)
    local font = P.Suite.GlobalFontPath()
    local ready = P.PreviewCanvas.Runtime("MSUF_Suite_Chat", "ChatStylePreviewFonts")
    local painter = P.S.ChatPaintMenuPreview -- Optional until the Chat runtime finishes loading.
    local nativeChanged = ready and P.S.ChatPreviewSnapshot(parts)
    if ready then P.S.ChatWatchPreview(ui.viewport, ui.runtimeRefresh, parts.source) end
    if not changed and not nativeChanged and parts.fontPath == font and parts.fontReady == ready and parts.viewWidth == ui.width
        and parts.painter == painter then return end
    parts.fontPath, parts.fontReady, parts.viewWidth = font, ready, ui.width
    parts.painter = painter
    local width = config.lockWindowSize and config.windowWidth or parts.nativeWidth or 420
    local height = config.lockWindowSize and config.windowHeight or parts.nativeHeight or 180
    local side = config.sidebarPanel and config.sidebarWidth or 0
    local top = config.tabHeight + config.tabPanelGap + (config.inputTop and math.max(26, config.inputHeight) or 0) + 12
    local bottom = config.inputTop and 12 or math.max(26, config.inputHeight) + 12
    local scale = math.min(1, (ui.width - 24) / (width + side + 2 * config.padding), 216 / (height + top + bottom))
    ui.stage:SetScale(scale)
    ui.stage:SetSize(width + side + 2 * config.padding, height + top + bottom)
    parts.sample:ClearAllPoints()
    parts.sample:SetPoint("TOPLEFT", ui.stage, "TOPLEFT", config.padding + (config.sidebarSide == 1 and side or 0), -top)
    parts.sample:SetSize(width, height)
    for _, line in ipairs(parts.messageLines) do line:SetWidth(width) end
    parts.width, ui.canvasHeight = width, (height + top + bottom) * scale
    ui.viewport:SetHeight(ui.canvasHeight)
    parts.text = SampleText()
    if ready then P.S.ChatStylePreviewFonts(parts, parts.fonts, config) end
    if painter then painter(parts, config) end
end

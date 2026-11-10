local _, NS = ...

-- The preview and live places use the same three texture layers.
NS.DataTextProgressWidth = 112
function NS.ClampDataTextProgress(value)
    return math.min(1, math.max(0, value))
end

function NS.PrepareDataTextProgress(button, create)
    if button.dataProgress then return end
    local track = create(button, nil, "ARTWORK", nil, 0)
    local rested = create(button, nil, "ARTWORK", nil, 1)
    local fill = create(button, nil, "ARTWORK", nil, 2)
    track:SetColorTexture(.15, .16, .18, .95)
    rested:SetColorTexture(.29, .43, .68, 1)
    fill:SetColorTexture(.25, .78, .62, 1)
    for _, texture in ipairs({ rested, fill }) do
        texture:SetPoint("TOPLEFT", track, "TOPLEFT")
        texture:SetPoint("BOTTOMLEFT", track, "BOTTOMLEFT")
        texture:Hide()
    end
    track:Hide()
    button.dataProgress = { track = track, bonus = rested, fill = fill }
end

function NS.PaintDataTextProgress(button, progress, rested)
    local visual = button.dataProgress
    local width = visual.width
    if not width or (visual.progress == progress and visual.rested == rested and visual.paintWidth == width) then return end
    visual.progress, visual.rested, visual.paintWidth = progress, rested, width
    local shown = progress ~= nil and width > 0
    visual.track:SetShown(shown)
    local fill, bonus = visual.fill, visual.bonus
    fill:SetShown(shown and progress > 0)
    bonus:SetShown(shown and rested ~= nil and rested > progress)
    if shown and progress > 0 then fill:SetWidth(width * progress) end
    if shown and rested and rested > progress then bonus:SetWidth(width * rested) end
end

function NS.LayoutDataTextProgress(button, available, inset, pixel)
    local visual = button.dataProgress
    local width = math.max(0, math.min(NS.DataTextProgressWidth, available - 2 * inset))
    visual.width = width
    local track = visual.track
    track:ClearAllPoints()
    track:SetPoint("BOTTOM", button, "BOTTOM", 0, pixel)
    track:SetSize(math.max(pixel, width), 2 * pixel)
    NS.PaintDataTextProgress(button, visual.progress, visual.rested)
end

local DATA_ICONS = {
    homeLatency = "Home", latency = "World", location = "Location", durability = "Durability",
}

function NS.DataTextMenuCaption(value)
    if type(value) == "string" then
        local caption = value:gsub("%c", " "):match("^%s*(.-)%s*$")
        if caption ~= "" then return (caption:gsub("|", "||")) end
    end
    return NS.Text("Menu")
end

local FPS_LABEL, MS_LABEL = NS.Text("FPS"), NS.Text("MS")
function NS.FormatDataText(label, value, severity, style, key, alternate)
    if key == "bags" and style.bagsPercent then value = alternate or "\226\128\148" end
    local valueColor = severity == "bad" and style.warningColor or style.valueColor
    if key == "fpsLatency" and style.performanceLabels then
        local fps, latency = value:match("^(%d+) / (%d+)")
        if fps then
            local plain = FPS_LABEL .. ": " .. fps .. " " .. MS_LABEL .. ": " .. latency
            return plain, "|cff" .. style.labelColor .. FPS_LABEL .. ": |r|cff" .. valueColor .. fps
                .. "|r |cff" .. style.labelColor .. MS_LABEL .. ": |r|cff" .. valueColor .. latency .. "|r"
        end
    elseif key == "memory" and style.colorMemoryUnit then
        value = value:gsub(" MB$", " |cff" .. style.memoryUnitColor .. "MB|r")
    end
    if style.showLabels and label and key ~= "progressBar" and (key ~= "clock" or style.clockLabel) then
        local separator = style.labelColon and ": " or " "
        return label .. separator .. value,
            "|cff" .. style.labelColor .. label .. separator .. "|r|cff" .. valueColor .. value .. "|r"
    end
    return value, "|cff" .. valueColor .. value .. "|r"
end

function NS.DecoratedDataText(label, value, severity, style, key, alternate)
    if key == "fps" and style.fpsAccent then value = value .. " fps" end
    local plain, text = NS.FormatDataText(label, value, severity, style, key, alternate)
    if key == "fps" and style.fpsAccent and severity ~= "bad" then
        local suffix = "|cff" .. style.valueColor .. value .. "|r"
        text = text:sub(1, #text - #suffix) .. "|cff" .. style.accentColor .. value .. "|r"
    end
    local icon = style.sourceIcons and DATA_ICONS[key]
    if icon then text = "|TInterface\\AddOns\\MSUF_Suite\\Media\\DataTextIcons\\" .. icon .. ".tga:12:12|t " .. text end
    return plain, text
end

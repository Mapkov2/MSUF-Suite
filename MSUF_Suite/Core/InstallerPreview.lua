local _, Suite = ...
local Preview = {}
Suite.InstallerPreview = Preview
local WHITE = "Interface\\Buttons\\WHITE8X8"
local max, min = math.max, math.min
local Text, Appearance = Suite.Text, Suite.InstallerAppearance
local ICONS = { "Interface\\Icons\\Spell_Holy_WordFortitude", "Interface\\Icons\\Spell_Holy_Renew",
    "Interface\\Icons\\Spell_Frost_FrostNova", "Interface\\Icons\\Spell_Nature_Lightning" }

local function Texture(parent, layer)
    local texture = parent:CreateTexture(nil, layer or "ARTWORK")
    texture:SetTexture(WHITE)
    return texture
end

local function Region(canvas)
    local frame = CreateFrame("Button", nil, canvas)
    frame.edge = Texture(frame, "BACKGROUND")
    frame.edge:SetAllPoints(frame)
    frame.fill = Texture(frame)
    frame.fill:SetPoint("TOPLEFT", frame, "TOPLEFT", 1, -1)
    frame.fill:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -1, 1)
    frame:EnableMouse(true)
    frame:SetScript("OnEnter", function() frame.panel.info:SetText(Text(frame.label)) end)
    frame:SetScript("OnLeave", function() frame.panel.info:SetText(frame.panel.selectionText) end)
    frame:SetScript("OnClick", function()
        local panel = frame.panel
        panel.selectedModule = frame.module
        if panel.navigate then panel.navigate(frame.module) end
    end)
    frame.details = {}
    for index = 1, 12 do frame.details[index] = Texture(frame, "OVERLAY") end
    return frame
end

local function Tint(region, hex, alpha)
    region:SetVertexColor(Suite.RGB(hex or "e6ecf2"))
    region:SetAlpha(alpha or 1)
end

local function Details(region, item, color)
    local icons = item.kind == "icons"
    local rows = item.kind == "meter" and 5 or item.kind == "list" and 8 or icons and (item.count or 12) or 0
    local width, height = region:GetWidth(), region:GetHeight()
    for index, texture in ipairs(region.details) do
        texture:SetShown(index <= rows)
        if index <= rows then
            texture:ClearAllPoints()
            if icons then
                local columns, lines = item.columns or rows, item.rows or 1
                local cellW, cellH = width / columns, height / lines
                local size = min(cellW, cellH)
                texture:SetTexture(ICONS[(index - 1) % #ICONS + 1])
                texture:SetSize(max(1, size - 1), max(1, size - 1))
                texture:SetPoint("TOPLEFT", region, "TOPLEFT", ((index - 1) % columns) * cellW,
                    -math.floor((index - 1) / columns) * cellH)
                texture:SetVertexColor(1, 1, 1, 1)
                texture:SetAlpha(1)
            else
                texture:SetTexture(WHITE)
                texture:SetSize(max(1, width * (1 - (index - 1) * .07) - 4), max(1, height / (rows + 2) - 1))
                texture:SetPoint("TOPLEFT", region, "TOPLEFT", 2, -2 - (index - 1) * height / (rows + 1))
                Tint(texture, color, .8)
            end
        end
    end
end

function Preview.Build(window, profile, frames, navigate)
    local panel = Appearance.Panel(window, 564, 58, 340, 390)
    panel.title = Appearance.Label(panel, "GameFontNormal", 14, -12, 312, 24, "section")
    panel.title:SetText(Text("Layout preview"))
    panel.canvas = CreateFrame("Frame", nil, panel)
    panel.canvas:SetPoint("TOPLEFT", panel, "TOPLEFT", 14, -44)
    panel.canvas:SetSize(312, 175.5)
    panel.canvas:SetClipsChildren(true)
    local background = Texture(panel.canvas, "BACKGROUND")
    background:SetAllPoints(panel.canvas)
    background:SetColorTexture(.025, .035, .045, 1)
    panel.regions = {}
    panel.viewport = Appearance.Label(panel, "GameFontHighlightSmall", 14, -226, 312, 18)
    panel.frameSource = Appearance.Label(panel, "GameFontHighlightSmall", 14, -248, 312, 18)
    panel.info = Appearance.Label(panel, "GameFontHighlightSmall", 14, -274, 312, 18, "section")
    panel.note = Appearance.Label(panel, "GameFontHighlightSmall", 14, -298, 312, 44)
    panel.modules = Appearance.Button(panel, 14, 12, 312, Text("Choose modules"), function()
        if panel.navigate then panel.navigate() end
    end)
    panel.navigate = navigate
    window.layoutPreview = panel
    panel.profile, panel.frames = profile, frames
    panel:Hide()
    return panel
end

local function Paint(panel, profile, frames, layout, overrides, viewport)
    local scene = Suite.InstallerPreviewModel.Build(profile, frames, layout, overrides, viewport)
    local meter = profile and profile.suite and profile.suite.modules.damageMeter or {}
    local color, background, border = meter.barColor or "e6ecf2", meter.bgColor or "101010", meter.borderColor or "575b58"
    local scale = min(312 / scene.width, 175.5 / scene.height)
    local width, height = scene.width * scale, scene.height * scale
    panel.canvas:SetSize(width, height)
    panel.canvas:ClearAllPoints()
    panel.canvas:SetPoint("TOPLEFT", panel, "TOPLEFT", 14 + (312 - width) / 2, -44 - (175.5 - height) / 2)
    for index, item in ipairs(scene) do
        local region = panel.regions[index]
        if not region then
            region = Region(panel.canvas)
            panel.regions[index] = region
        end
        region.panel, region.label, region.module = panel, item.label, item.module
        region:ClearAllPoints()
        region:SetPoint("TOPLEFT", panel.canvas, "TOPLEFT", item.x * scale, -item.y * scale)
        region:SetSize(max(2, item.width * scale), max(2, item.height * scale))
        Tint(region.edge, panel.selectedModule == item.module and color or border)
        Tint(region.fill, (item.kind == "bar" or item.kind == "resource") and color or background)
        -- A minimap sample has its own art, independent of the menu theme.
        region.fill:SetTexture(item.kind == "map" and "Interface\\Minimap\\UI-Minimap-Background" or WHITE)
        Details(region, item, color)
        region:Show()
    end
    for index = #scene + 1, #panel.regions do panel.regions[index]:Hide() end
    return scene
end

local function Context(panel, profile, overrides, options, viewport, scene)
    local id = panel.selectedModule
    local spec = id and Suite.SuiteCatalog[id]
    local config = spec and profile and profile.suite.modules[id]
    local enabled = config and config.enabled == true
    if overrides and id and overrides[id] ~= nil then enabled = overrides[id] == true end
    panel.selectionText = spec and Text("%s - %s"):format(Text(spec.title), enabled and Text("ON") or Text("OFF"))
        or Text("Click an element to choose its module.")
    panel.info:SetText(panel.selectionText)
    local scaleText = options and options.useScale and Text("%d x %d - UI scale %.0f%%")
        or Text("%d x %d - Current UI scale %.0f%%")
    panel.viewport:SetText(scaleText:format(
        viewport.physicalWidth, viewport.physicalHeight, viewport.scale * 100))
    panel.frameSource:SetText(not scene.frameSettingsAvailable and Text("MSUF frame preview unavailable")
        or options and options.keepFrames and Text("Current MSUF frames") or Text("Factory MSUF frames"))
    panel.note:SetText(scene.externalFrames and Text("Externally anchored frames are not shown. Icons use sample values.")
        or Text("Module choices and UI scale update here. Icons use sample values."))
end

function Preview.Show(window, shown, layout)
    local panel = window.layoutPreview
    if not panel then return end
    window:SetWidth(shown and 940 or 580)
    panel:SetShown(shown)
    if not shown then
        window:SetScale(1)
        return
    end
    local width, height = _G.UIParent:GetWidth(), _G.UIParent:GetHeight()
    local scale = min(1, max(.1, (width - 32) / window:GetWidth()), max(.1, (height - 32) / window:GetHeight()))
    window:SetScale(scale)
    local profile, overrides, options = panel.profile()
    local viewport = Suite.InstallerPreviewModel.Viewport(options)
    local frames = options and options.keepFrames and Suite.HostBridge.CurrentFramePreview() or nil
    if not (options and options.keepFrames) then frames = panel.frames(layout) end
    local scene = Paint(panel, profile, frames, layout, overrides, viewport)
    Context(panel, profile, overrides, options, viewport, scene)
end

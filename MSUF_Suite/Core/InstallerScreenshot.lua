local _, Suite = ...
local Shot = {}
Suite.InstallerScreenshot = Shot
local A, Text = Suite.InstallerAppearance, Suite.Text
local MEDIA = "Interface\\AddOns\\MSUF_Suite\\Media\\"
local MODERN = {
    { art = MEDIA .. "ModernDarkLayout.tga", ratio = 16 / 9, bottom = 576 / 1024, reference = true },
    { art = MEDIA .. "ModernDarkPreview.tga", ratio = 2559 / 1439, bottom = 1152 / 2048 },
}
local DARK_RAID = { art = MEDIA .. "DarkRaidPreview.tga", ratio = 2550 / 1438, bottom = 577 / 1024 }
local WAYFARER = { art = MEDIA .. "WayfarerPreview.tga", ratio = 2552 / 1204, bottom = 483 / 512 }
local BLIZZARD = {
    { art = MEDIA .. "BlizzardPreviewSolo.tga", ratio = 2560 / 1072, bottom = 429 / 512 },
    { art = MEDIA .. "BlizzardPreviewGroup.tga", ratio = 2560 / 1072, bottom = 429 / 512 },
}

local function Paint(texture, spec)
    texture:SetTexture(spec.art)
    texture:SetTexCoord(0, 1, 0, spec.bottom)
end

local function Picture(parent)
    local texture = parent:CreateTexture(nil, "ARTWORK")
    texture:SetAllPoints(parent)
    return texture
end

local function Enlarge(panel)
    local spec, zoom = panel.screenshotSpec, panel.screenshotZoom
    if not spec then return end
    if not zoom then
        zoom = CreateFrame("Frame", "MSUFSuiteScreenshotFrame", UIParent)
        panel.screenshotZoom = zoom
        zoom:SetFrameStrata("DIALOG")
        zoom:SetFrameLevel(600)
        zoom:EnableMouse(true)
        zoom:SetPoint("CENTER", UIParent, "CENTER")
        zoom.chrome = A.Panel(zoom, 0, 0, 1, 1)
        zoom.chrome:SetAllPoints(zoom)
        zoom.title = A.Label(zoom, "GameFontNormal", 16, -12, 500, 24, "section")
        zoom.picture = CreateFrame("Frame", nil, zoom)
        zoom.picture:SetPoint("TOPLEFT", zoom, "TOPLEFT", 16, -44)
        zoom.art = Picture(zoom.picture)
        zoom.close = A.Button(zoom, 16, 12, 140, Text("Close"), function() zoom:Hide() end)
        panel:HookScript("OnHide", function() zoom:Hide() end)
        Suite.Client.AttachControllerWindow(zoom)
        UISpecialFrames[#UISpecialFrames + 1] = "MSUFSuiteScreenshotFrame"
    end
    local width = math.max(1, math.min(1200, UIParent:GetWidth() - 64,
        (UIParent:GetHeight() - 144) * spec.ratio))
    zoom:SetSize(width + 32, width / spec.ratio + 96)
    zoom.picture:SetSize(width, width / spec.ratio)
    zoom.title:SetWidth(width)
    local layout = panel.screenshotLayout
    zoom.title:SetText(Text(layout == "wayfarer" and "Wayfarer - layout reference"
        or layout == "darkRaid" and "Dark Raid - layout reference"
        or layout == "blizzard" and "MSUF Blizzard - layout reference"
        or spec.reference and "Layout reference" or "Modern Dark - in-game screenshot"))
    Paint(zoom.art, spec)
    zoom:Show()
end

function Shot.Build(panel, refresh, window)
    panel.showLayout, panel.screenshotZoom = false, false
    panel.screenshotIndex = 1
    window:HookScript("OnHide", function()
        if panel.screenshotZoom then panel.screenshotZoom:Hide() end
    end)
    panel.screenshot = CreateFrame("Button", nil, panel)
    panel.screenshot:SetPoint("TOPLEFT", panel, "TOPLEFT", 14, -44)
    panel.screenshot.art = Picture(panel.screenshot)
    panel.screenshot:SetScript("OnClick", function() Enlarge(panel) end)
    panel.screenshot:Hide()
    panel.screenshotToggle = A.Button(panel, 200, 350, 126, Text("Layout"), function()
        panel.showLayout = not panel.showLayout
        refresh()
    end)
    panel.screenshotNext = A.Button(panel, 176, 134, 150, Text("Next image"), function()
        local gallery = panel.screenshotGallery
        if not gallery then return end
        panel.screenshotIndex = panel.screenshotIndex % #gallery + 1
        refresh()
    end)
    panel.screenshotToggle:Hide()
    panel.screenshotNext:Hide()
    panel.title:SetWidth(180)
end

function Shot.Show(panel, layout, options)
    local available = (layout == "modernDark" or layout == "blizzard" or layout == "darkRaid" or layout == "wayfarer")
        and options and options.layoutStep == true
    local showing = available and not panel.showLayout
    if panel.screenshotLayout ~= layout then panel.screenshotIndex = 1 end
    panel.screenshotLayout = layout
    local gallery = layout == "modernDark" and MODERN or layout == "blizzard" and BLIZZARD or nil
    panel.screenshotGallery = gallery
    panel.screenshotSpec = gallery and gallery[panel.screenshotIndex]
        or layout == "wayfarer" and WAYFARER or DARK_RAID
    panel.screenshotToggle:SetShown(available)
    panel.screenshotToggle.caption:SetText(Text(showing and "Layout" or "Screenshot"))
    panel.screenshot:SetShown(showing)
    panel.screenshotNext:SetShown(showing and gallery ~= nil)
    panel.canvas:SetShown(not showing)
    if panel.screenshotZoom then panel.screenshotZoom:Hide() end
    if showing then
        local spec = panel.screenshotSpec
        panel.screenshot:SetSize(312, 312 / spec.ratio)
        Paint(panel.screenshot.art, spec)
        panel.viewport:SetText(Text((layout ~= "modernDark" or spec.reference) and "Layout reference" or "In-game screenshot"))
        panel.frameSource:SetText(Text(Suite.InstallerProfiles.LayoutName(layout)))
        panel.info:SetText(Text("Click the screenshot to enlarge."))
        panel.note:SetText(Text((layout == "wayfarer" or spec.reference)
            and "This is the design reference. Use Layout to preview your MSUF settings."
            or layout ~= "modernDark" and "Reference images from another UI. Use Layout to preview your MSUF settings."
            or "The screenshot shows an example character. Use Layout to preview your module and frame color choices."))
    end
end

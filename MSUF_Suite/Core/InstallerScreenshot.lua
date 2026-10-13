local _, Suite = ...
local Shot = {}
Suite.InstallerScreenshot = Shot
local A, Text = Suite.InstallerAppearance, Suite.Text
local ART = "Interface\\AddOns\\MSUF_Suite\\Media\\ModernDarkPreview.tga"
local RATIO, UV_BOTTOM = 2559 / 1439, 1152 / 2048

local function Picture(parent)
    local texture = parent:CreateTexture(nil, "ARTWORK")
    texture:SetTexture(ART)
    texture:SetTexCoord(0, 1, 0, UV_BOTTOM)
    texture:SetAllPoints(parent)
    return texture
end

local function Enlarge(panel)
    local zoom = panel.screenshotZoom
    if not zoom then
        zoom = CreateFrame("Frame", "MSUFSuiteScreenshotFrame", UIParent)
        panel.screenshotZoom = zoom
        zoom:SetFrameStrata("DIALOG")
        zoom:SetFrameLevel(600)
        zoom:EnableMouse(true)
        zoom:ClearAllPoints()
        zoom:SetPoint("CENTER", UIParent, "CENTER")
        zoom.chrome = A.Panel(zoom, 0, 0, 1, 1)
        zoom.chrome:SetAllPoints(zoom)
        zoom.title = A.Label(zoom, "GameFontNormal", 16, -12, 500, 24, "section")
        zoom.title:SetText(Text("Modern Dark - in-game screenshot"))
        zoom.picture = CreateFrame("Frame", nil, zoom)
        zoom.picture:SetPoint("TOPLEFT", zoom, "TOPLEFT", 16, -44)
        zoom.art = Picture(zoom.picture)
        zoom.close = A.Button(zoom, 16, 12, 140, Text("Close"), function() zoom:Hide() end)
        panel:HookScript("OnHide", function() zoom:Hide() end)
        Suite.Client.AttachControllerWindow(zoom)
        UISpecialFrames[#UISpecialFrames + 1] = "MSUFSuiteScreenshotFrame"
    end
    local width = math.max(1, math.min(1200, UIParent:GetWidth() - 64,
        (UIParent:GetHeight() - 144) * RATIO))
    zoom:SetSize(width + 32, width / RATIO + 96)
    zoom.picture:SetSize(width, width / RATIO)
    zoom.title:SetWidth(width)
    zoom:Show()
end

function Shot.Build(panel, refresh, window)
    panel.showLayout, panel.screenshotZoom = false, false
    window:HookScript("OnHide", function()
        if panel.screenshotZoom then panel.screenshotZoom:Hide() end
    end)
    panel.screenshot = CreateFrame("Button", nil, panel)
    panel.screenshot:SetPoint("TOPLEFT", panel, "TOPLEFT", 14, -44)
    panel.screenshot:SetSize(312, 312 / RATIO)
    panel.screenshot.art = Picture(panel.screenshot)
    panel.screenshot:SetScript("OnClick", function() Enlarge(panel) end)
    panel.screenshot:Hide()
    panel.screenshotToggle = A.Button(panel, 200, 350, 126, Text("Layout"), function()
        panel.showLayout = not panel.showLayout
        refresh()
    end)
    panel.screenshotToggle:Hide()
    panel.title:SetWidth(180)
end

function Shot.Show(panel, layout, options)
    local available = layout == "modernDark" and options and options.layoutStep == true
    local showing = available and not panel.showLayout
    panel.screenshotToggle:SetShown(available)
    panel.screenshotToggle.caption:SetText(Text(showing and "Layout" or "Screenshot"))
    panel.screenshot:SetShown(showing)
    panel.canvas:SetShown(not showing)
    if panel.screenshotZoom then panel.screenshotZoom:Hide() end
    if showing then
        panel.viewport:SetText(Text("In-game screenshot"))
        panel.frameSource:SetText(Text("Modern Dark"))
        panel.info:SetText(Text("Click the screenshot to enlarge."))
        panel.note:SetText(Text("The screenshot shows an example character. Use Layout to preview your module and frame color choices."))
    end
end

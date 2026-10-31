local root = assert(arg[1])
local load, private = loadfile
loadfile = function(path)
    local chunk = assert(load(path))
    return function(addon, namespace)
        if path:find("MSUF_Suite_DamageMeter/Data.lua", 1, true) then private = namespace end
        return chunk(addon, namespace)
    end
end
local fixture = arg[2] == "Forever" and "suite_damage_meter_threat_contract.lua" or "suite_damage_meter_contract.lua"
assert(load(root .. "/tools/tests/" .. fixture))()
loadfile = load
local D, S, M = private.DamageMeter, private.Suite, private.DamageMeter.M
M:Disable()
M.active = false
assert(load(root .. "/MSUF_Suite_DamageMeter/Preview.lua"))("MSUF_Suite_DamageMeter", private)
local c = S.Config("damageMeter")
c.timer, c.headerVisible, c.headerOutside, c.iconSkin = false, true, false, "CUSTOM"
c.w1Width, c.w1Height, c.w1Type, c.w1Session, c.iconStyle = 300, 170, 1, 1, 2
local stage = CreateFrame("Frame", nil, UIParent)
local Region = getmetatable(stage).__index
Region.SetTexture = function(self, path) self.texture = path end
Region.SetVertexColor = function(self, ...) self.vertex = { ... } end
Region.SetShadowColor = function(self, ...) self.shadowColor = { ... } end
local statusTexture = Region.SetStatusBarTexture
Region.SetStatusBarTexture = function(self, path)
    statusTexture(self, path)
    self:GetStatusBarTexture().texture = path
end
local function Draw() return S.DamageMeterDrawMenuPreview(stage, 1) end
local win = Draw()
local row = win.rows[1]
assert(not row.fillBorder or not row.fillBorder.materialEdges, "default style allocated material edges")
assert(not row.rowSeparator and not row.iconSeparator and not win.sampleTimer, "unused decorations allocated regions")
local vertex = {}
win.bg.SetVertexColor = function(_, ...) vertex = { ... } end
c.bgTextured, c.bgTexture, c.bgColor, c.bgAlpha = true, "", "336699", 40
Draw()
assert(win.bg.texture and vertex[1] == .2 and vertex[4] == .4, "textured background lost tint/opacity")
c.bgTextured = false
Draw()
assert(vertex[1] == 1 and vertex[4] == 1 and win.bg.color[4] == .4, "flat background retained the texture tint")
c.headerTextured, c.headerTexture = true, ""
Draw()
assert(win.headerBg.texture, "header texture did not reach runtime")

c.rowBorderMode, c.rowBorderStyle, c.rowBorderTop, c.rowBorderGap = 3, 2, false, 2
c.borderStyle, c.borderArea, c.borderLeft = 3, 2, false
c.headerOutside, c.borderSize, c.borderGap = true, 16, 8
c.iconBorder, c.iconBorderCustom, c.iconBorderStyle, c.iconBorderSize = true, true, 4, 3
c.iconBorderAlpha, c.iconBorderColor, c.iconBorderGap = 35, "ff0000", 2
Draw()
assert(win.previewWidth >= c.w1Width + 48 and win.previewHeight >= c.w1Height + c.headerHeight + 48,
    "thick external window border is clipped by preview stage")
local material, icon = assert(row.fillBorder.materialEdges), assert(row.iconBorder.materialEdges)
assert(#material == 8 and not material[1]:IsShown() and material[2]:IsShown(), "row edge mask ignored")
assert(not material[5]:IsShown() and material[7]:IsShown(), "material corner did not follow adjacent edges")
assert(not win.edges[1]:IsShown() and not win.border.materialEdges[3]:IsShown(), "solid edge or disabled material edge leaked")
assert(win.borderBox.points[1][2] == win.header, "window border failed to include external header")
assert(row.fillBorder.points[2][2] == row.bar:GetStatusBarTexture(), "filled border does not follow the native fill")
assert(row.fillBorder.points[1][4] == -2 and icon[1].texture:find("Gold", 1, true), "gap or independent icon style lost")
assert(M.style.iconBorder.size == 3 and M.style.iconBorder.alpha == .35 and M.style.iconBorder.r == 1,
    "independent icon width/opacity/color ignored")
local originalWidth = row.bar.GetWidth
row.bar.GetWidth = function() error("secret fill geometry read") end
D.StyleRow(row)
row.bar.GetWidth = originalWidth
assert(row.fillBorder.materialEdges == material and row.iconBorder.materialEdges == icon, "style refresh reallocated border pieces")
c.rowBorderStyle, c.borderStyle, c.rowBorderTop, c.iconBorderCustom = 1, 1, true, false
c.borderSize, c.borderGap = 1, 0
Draw()
assert(not material[2]:IsShown() and row.fillBorder.edges[1]:IsShown(), "material to solid transition leaked edges")
assert(M.style.iconBorder == M.style.rowBorder and not icon[1]:IsShown(), "icon inheritance did not restore")

c.rowSeparators, c.iconSeparator, c.headerSeparator = true, true, true
c.separatorAlpha, c.separatorSize, c.separatorInset = 30, 2, 1
Draw()
local line = assert(row.rowSeparator)
assert(line:IsShown() and line.color[4] == .3 and line:GetHeight() == 2, "row separator style lost")
assert(row.iconSeparator:IsShown() and win.header.separator:IsShown(), "icon/header separators missing")
c.rowSeparators, c.iconSeparator, c.headerSeparator = false, false, false
Draw()
assert(not line:IsShown() and not row.iconSeparator:IsShown() and not win.header.separator:IsShown(), "disabled separators leaked")

c.namesFontCustom, c.valuesFontCustom, c.headerFontCustom, c.detailsFontCustom, c.timerFontCustom = true, true, true, true, true
c.namesOutline, c.valuesOutline, c.headerOutline, c.detailsOutline, c.timerOutline = 3, 4, 2, 1, 5
c.namesRendering, c.valuesRendering, c.headerRendering, c.detailsRendering, c.timerRendering = 1, 1, 1, 1, 1
c.namesFont, c.valuesFont, c.headerFont, c.detailsFont, c.timerFont = "", "", "", "", ""
Draw()
assert(row.nameText.font[3] == "THICKOUTLINE" and row.valueText.font[3] == "", "name/value text styles not independent")
assert(win.title.font[3] == "OUTLINE" and M.style.fonts.details.shadow, "header/details text styles ignored")
local details = D.CreateRow(win.body, win, "tip")
D.StyleRow(details)
assert(details.nameText.font[3] == "" and details.nameText.shadowColor[4] > 0, "details row did not use its font role")
c.breakdownOwnTexture, c.breakdownTexture = true, "Interface\\Buttons\\WHITE8X8"
S.DamageMeterDrawMenuPreview(stage, 1, true)
assert(win.detailsSample and win.panel and win.panel:IsShown() and win.bdRows[1].nameText.shadowColor[4] > 0,
    "detail preview did not use native breakdown painter and font")
assert(win.bdRows[1].bar:GetStatusBarTexture().texture == M.style.breakdownTexture, "detail preview lost its separate texture")
S.DamageMeterDrawMenuPreview(stage, 1, false)
assert(not win.panel:IsShown(), "detail sample remained over main rows")
c.namesFontCustom, c.valuesFontCustom, c.rendering = false, false, 1
c.font = "Fonts\\FRIZQT__.TTF"
Draw()
assert(row.nameText.font[1] == M.style.font and row.nameText.font[3] == M.style.outline, "font inheritance did not restore")

c.headerOutside = false
Draw()
local oldCapacity = win.capacity
c.headerOutside, c.headerVisible, c.combatTime, c.headerTimer = false, false, true, true
Draw()
assert(not win.header:IsShown() and win.header:GetHeight() == 0 and win.capacity > oldCapacity, "hidden header kept space")
assert(win.timer.text == "" and not win.buttons.type.configuredShown and not M.style.headerClock, "hidden header retained controls or clock")
c.headerVisible = true
Draw()
assert(win.header:IsShown() and win.capacity == oldCapacity and M.style.headerClock, "header restore lost layout/clock")

c.timer, c.timerAnchor, c.timerWindow, c.timerDockX, c.timerDockY, c.timerAlign = true, 3, 1, 7, 9, 3
Draw()
local timer = assert(win.sampleTimer)
local point = timer.points[1]
assert(win.previewTimerShown and point[1] == "BOTTOMRIGHT" and point[2] == win.header and point[4] == 7 and point[5] == 9,
    "timer sample ignored native corner docking")
assert(win.previewWidth > c.w1Width and win.previewHeight > c.w1Height, "sample clips docked timer")
assert(timer.text.font[3] == "OUTLINE", "floating timer font role missing")
D.windows[1].shown, D.windows[1].faded = true, false
assert(D.TimerAnchorShown(), "visible dock target rejected")
D.StyleTimer()
assert(M.timerFrame.points[1][2] == D.windows[1].header, "live timer not attached to chosen window")
M.forced, M.inCombat, M.lastDuration, c.timerKeep = false, false, 95, true
c.visibility, D.windows[1].hover, D.windows[1].faded = D.VISIBILITY.MOUSEOVER, true, false
D.UpdateTimer()
assert(M.timerFrame:IsShown(), "hovered dock did not show the kept timer")
D.windows[1].hover = false
D.ApplyHover(D.windows[1])
assert(not M.timerFrame:IsShown(), "fading dock left the whole-second timer visible")
D.windows[1].shown = false
D.UpdateTimer()
assert(not D.TimerAnchorShown() and not M.timerFrame:IsShown(), "hidden dock target left a floating timer")
c.timerWindow = 2
Draw()
assert(not win.previewTimerShown and not timer:IsShown(), "different-window timer leaked into sample")
c.timerAnchor, c.timerX, c.timerY = 1, 123, 234
Draw()
D.StyleTimer()
assert(win.previewTimerShown and M.timerFrame.points[1][4] == 123 and M.timerFrame.points[1][5] == 234,
    "undocking lost free screen coordinates or sample")
c.timer = false
Draw()
assert(not timer:IsShown(), "disabled floating timer remained in preview")
local layout = D.StyleWindowLayout
D.StyleWindowLayout = function() error("warm preview restyled") end
for i = 1, 100 do Draw() end
D.StyleWindowLayout = layout
for _, frame in ipairs({ row, row.fillBorder, row.iconBorder, win.border, timer }) do
    assert(not frame:GetScript("OnUpdate") and not frame:GetScript("OnSizeChanged"), "styling introduced Lua tracking")
end
print("Damage meter styling: surfaces, native fill borders, icon inheritance, separators, font roles, header space, timer docking and warm reuse passed")

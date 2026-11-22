-- Two unrelated Blizzard windows share the name "Flight Map" in the UI.
-- The old frame stores the actual map in InsetBg. The load-on-demand canvas
-- instead places its portrait border in BorderFrame above ScrollContainer.
local root = assert(arg[1], "Suite root required")
local flavor = arg[2] or "Mainline"
assert(flavor == "Mainline" or flavor == "Forever", "unsupported client flavor")
local fixture = assert(loadfile(root .. "/tools/tests/suite_skin_generic_windows_contract.lua"))("flight-map-fixture", flavor)
local NS, genericLoadFrame, ColdSource = fixture.NS, fixture.loadFrame, fixture.source
local Frame, Expect, InCombat, SetCombat = fixture.frame, fixture.expect, fixture.inCombat, fixture.setCombat
local NoErrors, Finish = fixture.noErrors, fixture.finish
local GenericWindows = NS.GenericWindows
assert(loadfile(ColdSource("../MSUF_Suite/Appearance/Cosmetics.lua")))("MSUF_Suite_Skin", NS)
local registryNS = {Safety = NS.Safety, IsCombatLocked = NS.IsCombatLocked}
assert(loadfile(ColdSource("Core/Registry.lua")))("MSUF_Suite_Skin", registryNS)
registryNS.Registry.QueueJob = NS.Registry.QueueJob
NS.Registry.WatchSettings = registryNS.Registry.WatchSettings
local colors = {ink = .12, background = .24, border = .37}
NS.Theme.GetColor = function(token) return colors[token] or .8, .23, .44, 1 end
NS.DB = {
    enabled = true, blizzardWindowsEnabled = true, skinCategories = {npc = true, map = true},
    skins = {blizzardWindows = true}
}
local afterCombat = {}
NS.CombatGate.RunOrDefer = function(key, cb)
    if not InCombat() then
        cb()
        return true
    end
    afterCombat[key] = cb
    return false, "combat"
end
NS.CombatGate.Cancel = function(key) afterCombat[key] = nil end
local function EndCombat()
    SetCombat(false)
    local held = afterCombat
    afterCombat = {}
    for _, cb in pairs(held) do cb() end
end
InCombatLockdown = InCombat
local function Widget(name, parent, kind)
    local w = Frame(name)
    w.parent, w.kind, w.alpha, w.shown, w.rgba = parent, kind or "Frame", 1, true, {1, 1, 1, 1}
    w.hooks, w.scripts, w.points, w.regions = {}, {}, {}, {}
    if name then _G[name] = w end
    if parent then
        local list = (kind == "Texture" or kind == "FontString") and parent.regions or parent.children
        list[#list + 1] = w
    end
    function w:GetObjectType() return self.kind end
    function w:GetParent() return self.parent end
    function w:GetRegions() return unpack(self.regions) end
    function w:GetAlpha() return self.alpha end
    function w:SetAlpha(v) self.alpha, self.rgba[4] = v, v end
    function w:GetVertexColor() return unpack(self.rgba) end
    function w:SetVertexColor(r, g, b, a)
        self.rgba = {r, g, b, a or 1}
        self.alpha = a or 1
    end
    w.SetColorTexture = w.SetVertexColor
    function w:SetPoint(...) self.points[#self.points + 1] = {...} end
    function w:GetPoint(i) return unpack(self.points[i] or {}) end
    function w:ClearAllPoints() self.points = {} end
    function w:SetAllPoints(target) self.allPoints = target or self.parent end
    function w:SetWidth(x) self.width = x end
    function w:SetHeight(y) self.height = y end
    function w:SetSize(x, y) self.width, self.height = x, y end
    function w:GetWidth() return self.width or 590 end
    function w:GetHeight() return self.height or 608 end
    function w:SetTexture(v) self.texture = v end
    function w:GetTexture() return self.texture end
    function w:SetAtlas(v) self.atlas = v end
    function w:GetAtlas() return self.atlas end
    function w:GetDrawLayer() return self.layer end
    function w:SetDrawLayer(l, s) self.layer, self.sublevel = l, s end
    function w:CreateTexture(_, layer, _, sublevel)
        local r = Widget(nil, self, "Texture")
        r.layer, r.sublevel, r.created = layer, sublevel, true
        return r
    end
    function w:CreateFontString(_, layer)
        local r = Widget(nil, self, "FontString")
        r.layer = layer
        return r
    end
    function w:GetText() return self.text end
    function w:SetText(s) self.text = s end
    function w:GetTextColor() return unpack(self.rgba) end
    function w:SetTextColor(...) self.rgba = {...} end
    function w:IsShown() return self.shown end
    function w:IsVisible() return self.shown and (not self.parent or self.parent:IsVisible()) end
    function w:IsProtected() return self.implicit == true, self.explicit == true end
    function w:HookScript(key, cb)
        assert(key ~= "OnUpdate", "flight map installed a polling script")
        self.hooks[key] = self.hooks[key] or {}
        table.insert(self.hooks[key], cb)
    end
    function w:GetScript(key) return self.scripts[key] end
    function w:Fire(key, ...)
        if self.scripts[key] then self.scripts[key](self, ...) end
        for _, cb in ipairs(self.hooks[key] or {}) do cb(self, ...) end
    end
    function w:Show()
        if not self.shown then
            self.shown = true
            self:Fire("OnShow")
        end
    end
    function w:Hide()
        if self.shown then
            self.shown = false
            self:Fire("OnHide")
        end
    end
    function w:SetShown(v)
        if v then
            self:Show()
        else
            self:Hide()
        end
    end
    return w
end
local function Field(p, k, kind)
    local n = Widget(nil, p, kind)
    p[k] = n
    return n
end
local function Tex(p, k) return Field(p, k, "Texture") end
local function Covered(region) return not region:IsShown() or region:GetAlpha() == 0 end
local function Entry(frame) return assert(NS.BlizzardCatalog.FindByFrame(frame)) end
local function TitleAndTrim(host)
    local header, trim = 0, 0
    for _, art in ipairs(host.regions) do
        if art.created and art:IsShown() and art.alpha > 0 and #art.points == 2 and art.layer == "BORDER" and
            art.sublevel == 1 then
            if art.height and art.height >= 12 and art.height < 32 then
                header = header + 1
            else
                trim = trim + 1
            end
        end
    end
    return header, trim
end
local function Painted(host, token)
    local count = 0
    for _, art in ipairs(host.regions) do
        if art.created and art:IsShown() and art.rgba[1] == colors[token] then count = count + 1 end
    end
    return count
end
local function StaysOutsideMap(host, top, left, right, bottom)
    local function Coordinate(anchor)
        local point = anchor[1]
        if anchor[2] ~= host or point ~= anchor[3] then return end
        local x = point:find("RIGHT", 1, true) and host:GetWidth() or 0
        local y = point:find("BOTTOM", 1, true) and host:GetHeight() or 0
        return x + anchor[4], y - anchor[5]
    end
    for _, art in ipairs(host.regions) do
        if art.created and art:IsShown() then
            if #art.points ~= 2 then return false end
            local x1, y1 = Coordinate(art.points[1])
            local x2, y2 = Coordinate(art.points[2])
            if not x1 or not x2 then return false end
            if x1 == x2 and art.width then
                if art.points[1][1]:find("LEFT", 1, true) then
                    x2 = x1 + art.width
                else
                    x1 = x2 - art.width
                end
            end
            if y1 == y2 and art.height then
                if art.points[1][1]:find("TOP", 1, true) then
                    y2 = y1 + art.height
                else
                    y1 = y2 - art.height
                end
            end
            if x2 > left and x1 < host:GetWidth() - right and y2 > top and y1 < host:GetHeight() - bottom then
                return false
            end
        end
    end
    return true
end
NS.Registry.GetSurface = function(w) return w and w.surfaceSpec and {spec = w.surfaceSpec, target = w} end
NS.ControlSkin.ApplyButton = function(b)
    b.control = true
    return true
end
NS.WindowControls.Attach = function(w) w.caption = true end
local taken, hover, zoom = 0, nil, 0
local function RunNode(node)
    hover = nil
    node:Fire("OnEnter")
    node:Fire("OnClick", "LeftButton")
    return hover == node and taken == node.slot
end
local function Pin(p, kind, slot)
    local b = Widget(nil, p, kind)
    b.slot = slot
    b.scripts.OnEnter = function(self) hover = self end
    function b:GetID() return self.slot end
    if kind == "Button" then
        b.scripts.OnClick = function(self) taken = self:GetID() end
    else
        b.taxiNodeData = {slotIndex = slot}
        b.scripts.OnClick = function(self, button)
            if button == "LeftButton" and not self.isMapLayerTransition then
                taken = self.taxiNodeData.slotIndex
            end
        end
    end
    return b
end
UIParent = Widget("UIParent")
UIParent.width, UIParent.height = 1920, 1080
local owner = "blizzardWindows"
local taxi = Widget("TaxiFrame", UIParent)
taxi.shown = false
taxi.width, taxi.height = 590, 608
local outer = {
    "TopLeftCorner", "TopRightCorner", "BotLeftCorner", "BotRightCorner", "TopBorder", "BottomBorder",
    "LeftBorder", "RightBorder"
}
local inset = {
    "InsetBorderTopLeft", "InsetBorderTopRight", "InsetBorderBottomLeft", "InsetBorderBottomRight",
    "InsetBorderTop", "InsetBorderBottom", "InsetBorderLeft", "InsetBorderRight"
}
for _, keys in ipairs({outer, inset, {"Bg", "TitleBg", "TopTileStreaks"}}) do
    for _, key in ipairs(keys) do Tex(taxi, key) end
end
local map = Tex(taxi, "InsetBg")
map:SetTexture("world/taxi-map/eastern-kingdoms")
taxi.TitleText = Field(taxi, "TitleText", "FontString")
taxi.TitleText.text = "Flight Map"
taxi.CloseButton = Field(taxi, "CloseButton", "Button")
taxi.CloseButton.scripts.OnClick = function() taxi:Hide() end
local routeMap = Widget("TaxiRouteMap", taxi)
local route = Tex(routeMap, "Route")
route.texture = "taxi-line"
local node = Pin(routeMap, "Button", 6)
node.NormalTexture = Tex(node, "NormalTexture")
node.NormalTexture.texture = "taxi-icon-white"
taxi.scripts.OnShow = function(self)
    self.TitleText:SetText("Flight Map")
    self.InsetBg:SetTexture("world/taxi-map/eastern-kingdoms")
end
GenericWindows.ApplyEntry(Entry("TaxiFrame"), owner)
Expect(not taxi.surfaceSpec and map.alpha == 1, "hidden TaxiFrame was painted before native show")
taxi:Show()
NoErrors()
Expect(taxi.surfaceSpec and taxi.surfaceSpec.fillVisible == false and taxi.caption,
    "TaxiFrame shell or caption is missing")
for _, key in ipairs(outer) do Expect(Covered(taxi[key]), "TaxiFrame native outside border is visible: " .. key) end
for _, key in ipairs(inset) do Expect(Covered(taxi[key]), "TaxiFrame native inset surround is visible: " .. key) end
Expect(Covered(taxi.TitleBg) and Covered(taxi.TopTileStreaks), "TaxiFrame native title tile is still visible")
local header, edges = TitleAndTrim(taxi)
Expect(header == 1 and edges >= 3, "old flight map is missing the visible Suite title band or frame trim")
Expect(StaysOutsideMap(taxi, 24, 4, 6, 4), "classic chrome overlaps the native InsetBg map")
Expect(map.texture == "world/taxi-map/eastern-kingdoms" and map.alpha == 1 and map.shown and
           not NS.Cosmetics.GetOwner(map), "TaxiFrame semantic InsetBg map texture was modified")
Expect(route.alpha == 1 and node.NormalTexture.alpha == 1 and RunNode(node) and not routeMap.surfaceSpec and
           not node.surfaceSpec and routeMap.childReads == 0,
    "TaxiFrame route or node art, hover or native flight choice changed")
taxi.TopBorder:SetAlpha(0.72)
taxi.TopBorder:Show()
taxi.TitleBg:SetVertexColor(0.5, 0.4, 0.3, 0.85)
taxi.TitleBg:Show()
Expect(Covered(taxi.TopBorder) and Covered(taxi.TitleBg), "late write exposed the classic title or border")
taxi.CloseButton:Fire("OnClick")
Expect(not taxi.shown, "classic close action lost")
taxi:Show()
Expect(RunNode(node) and taxi.TitleText.text == "Flight Map", "classic reopen lost native title or node")
local addonLoaded = false
NS.Client.IsAddOnLoaded = function(addon) return addon ~= "Blizzard_FlightMap" or addonLoaded end
local entry = Entry("FlightMapFrame")
local _, why = GenericWindows.ApplyEntry(entry, owner)
Expect(why == "waiting" and genericLoadFrame.events.ADDON_LOADED, "flight map did not wait for its native addon")
local modern = Widget("FlightMapFrame", UIParent)
modern.shown = false
modern.width, modern.height = 1004, 689
local border = Field(modern, "BorderFrame")
border.layoutType = "PortraitFrameTemplate"
border.width, border.height = modern.width, modern.height
local nine = Field(border, "NineSlice")
for _, key in ipairs({
    "TopEdge", "BottomEdge", "LeftEdge", "TopLeftCorner", "TopRightCorner", "BottomLeftCorner",
    "BottomRightCorner", "Center"
}) do Tex(nine, key) end
local top = Tex(border, "TopBorder")
top.atlas = "AdventureMap_TopBorder"
local streak = Tex(border, "TopTileStreaks")
streak:Hide()
local backing = Tex(border, "Bg")
backing.parent = modern
local under = Tex(border, "Underlay")
under:Hide()
local pc = Field(border, "PortraitContainer")
local portrait = Tex(pc, "portrait")
portrait.texture = "icon_petfamily_flying"
local title = Field(border, "TitleContainer")
title.TitleText = Field(title, "TitleText", "FontString")
title.TitleText.text = "Flight Map"
border.CloseButton = Field(border, "CloseButton", "Button")
border.CloseButton.scripts.OnClick = function() modern:Hide() end
local scroll = Field(modern, "ScrollContainer", "ScrollFrame")
local child = Field(scroll, "Child")
local tile = Tex(child, "Tile")
tile.texture = "map-detail"
scroll.scripts.OnMouseWheel = function(_, direction) zoom = zoom + direction end
local fmPin = Pin(child, "Frame", 9)
local fmIcon = Tex(fmPin, "Icon")
fmIcon.texture = "taxi-icon-green"
local transition = Pin(child, "Frame", 10)
transition.isMapLayerTransition = true
addonLoaded = true
genericLoadFrame.scripts.OnEvent(genericLoadFrame, "ADDON_LOADED", "Blizzard_FlightMap")
Expect(not modern.surfaceSpec, "load-on-demand activated a still-hidden map")
modern:Show()
NoErrors()
Expect(modern.surfaceSpec and modern.surfaceSpec.fillVisible == false,
    "modern root covered its canvas with a surface fill")
Expect(Covered(nine.TopEdge) and Covered(nine.BottomRightCorner) and Covered(top),
    "modern flight window's separate portrait frame or atlas ornament remained visible")
header, edges = TitleAndTrim(border)
Expect(header == 1 and edges >= 3, "modern nested border is missing the visible Suite title band or frame trim")
Expect(StaysOutsideMap(border, 20, 1, 1, 1), "Suite chrome overlaps the visible MapCanvas scroll container")
Expect(not Covered(backing) and not NS.Cosmetics.GetOwner(backing) and not under.shown and
           not NS.Cosmetics.GetOwner(under), "modern skin changed the reparented map backing or hidden overlay")
scroll:Fire("OnMouseWheel", 2)
Expect(RunNode(fmPin) and zoom == 2 and not Covered(tile) and not Covered(fmIcon) and not Covered(portrait) and
           scroll.childReads == 0 and child.childReads == 0 and tile.texture == "map-detail" and fmIcon.texture ==
           "taxi-icon-green" and portrait.texture == "icon_petfamily_flying",
    "modern map tiles, pin, portrait, zoom or native flight action changed")
transition:Fire("OnClick", "LeftButton")
fmPin:Fire("OnClick", "RightButton")
Expect(taken == 9, "map layer transition or secondary click booked a flight")
top:SetAlpha(.68)
top:Show()
nine.TopEdge:SetAlpha(.77)
nine.TopEdge:Show()
Expect(Covered(top) and Covered(nine.TopEdge), "late native repaint re-exposed the modern map border")
title.TitleText:SetText("Flight Routes")
border.CloseButton:Fire("OnClick")
Expect(not modern.shown, "modern native close failed")
local lateEdge = Tex(nine, "RightEdge")
modern:Show()
Expect(title.TitleText:GetText() == "Flight Routes" and RunNode(fmPin),
    "modern reopen changed native title or node")
GenericWindows.ApplyEntry(entry, owner)
Expect(Covered(lateEdge), "a catalog refresh missed a newly available NineSlice edge")
for _, token in ipairs({"ink", "border", "background"}) do
    local beforeOld, beforeNew = Painted(taxi, token), Painted(border, token)
    colors[token] = colors[token] + .09
    registryNS.Registry.NotifyListeners("color", token)
    Expect(beforeOld > 0 and beforeNew > 0 and Painted(taxi, token) == beforeOld and Painted(border, token) ==
               beforeNew, "color change skipped flight-map " .. token)
end
local secondOwner = "flight-map-contract-second-owner"
GenericWindows.ApplyEntry(Entry("TaxiFrame"), secondOwner)
GenericWindows.ApplyEntry(entry, secondOwner)
GenericWindows.Disable(secondOwner)
Expect(Painted(taxi, "ink") == 1 and Painted(border, "ink") == 1 and Covered(taxi.TopBorder) and Covered(top),
    "releasing a second owner removed the first owner's chrome")
SetCombat(true)
GenericWindows.Disable(owner)
Expect(next(afterCombat) ~= nil, "combat teardown skipped deferral")
EndCombat()
NoErrors()
Expect(taxi.TopBorder.alpha == .72 and taxi.TopBorder:IsShown() and taxi.TitleBg.alpha == .85 and top.alpha ==
           .68 and top:IsShown() and nine.TopEdge.alpha == .77,
    "disable did not restore latest border/title state")
Expect(taxi.surfaceVisible == false and modern.surfaceVisible == false and map.alpha == 1 and RunNode(node) and
           RunNode(fmPin), "disable left a Suite shell or damaged native interaction")
local oldHeader, oldTrim = TitleAndTrim(taxi)
local newHeader, newTrim = TitleAndTrim(border)
Expect(oldHeader + oldTrim + newHeader + newTrim == 0,
    "disabling the flight skin left a Suite title band or frame trim visible")
NS.DB.skinCategories.npc = false
GenericWindows.ApplyEntry(Entry("TaxiFrame"), owner)
NS.DB.skinCategories.map = false
GenericWindows.ApplyEntry(entry, owner)
taxi.TitleBg:SetAlpha(.44)
top:SetAlpha(.45)
Expect(GenericWindows.GetStatus(entry.id) == "disabled" and taxi.TitleBg.alpha == .44 and top.alpha == .45,
    "category-disabled flight skin reclaimed native art")
print("suite_skin_flight_map_chrome_contract (" .. flavor .. "): " .. Finish() .. " flight-map checks passed")

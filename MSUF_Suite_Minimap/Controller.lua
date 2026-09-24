local _, P = ...
local NS, S = P.NS, P.Suite
local MM = P.Minimap
local M = MM.M
-- Lifecycle and the split apply. A category re-runs only when one of its
-- settings changed, so a slider touches only what it affects; geometry is the
-- only category that re-renders the map (the zoom nudge).
local HOST_ELEMENT = "external:msuf.blizzard:minimap"
local CATEGORIES = {
    { name = "geometry", keys = { "size", "shape", "hoverResize", "hoverWidth", "hoverHeight" } },
    { name = "position", keys = { "point", "x", "y" } },
    { name = "border", keys = { "size", "shape", "borderSize", "borderColor", "borderClassColor",
        "borderAlpha", "shadowSize", "shadowColor", "shadowAlpha", "stylePreset", "styleTexture", "styleTexturePath",
        "styleColor", "styleAlpha", "styleScale", "styleX", "styleY", "stylePlacement", "styleBlend", "styleRotation",
        "styleGlow", "styleGlowColor", "styleGlowAlpha", "styleGlowScale", "styleBackdrop", "styleBackdropColor",
        "styleBackdropAlpha", "styleBackdropPadding" } },
    { name = "input", keys = { "visibility", "hoverResize", "rotate", "scrollZoom", "zoomResetSeconds", "zoomButtons", "middleClick",
        "zoomInX", "zoomInY", "zoomOutX", "zoomOutY",
        "showLanding", "collectButtons", "drawerMouseover", "infoCoordinates", "infoCoordinatesMode" } },
    { name = "elements", keys = { "showTracking", "showCalendar", "showMail", "showCrafting", "showDifficulty", "showLanding", "landingIcon",
        "landingX", "landingY", "difficultyButtonX", "difficultyButtonY", "showCompartment", "elementRow", "elementSize", "elementSpacing", "elementDistance", "infoDifficulty", "borderSize" } },
    { name = "drawer", keys = { "collectButtons", "drawerRow", "drawerX", "drawerY", "drawerButtonSize", "drawerColumns", "drawerMouseover",
        "elementRow", "elementSize", "elementSpacing", "elementDistance", "borderSize", "borderColor", "borderClassColor" } },
    { name = "texts", keys = { "borderSize", "borderColor", "borderClassColor", "showCalendar" } },
}
for _, name in ipairs({ "Tracking", "Calendar", "Mail", "Crafting", "Battlefield", "Queue", "WorldMap", "Compartment" }) do
    local keys = CATEGORIES[5].keys
    keys[#keys + 1] = "button" .. name .. "X"
    keys[#keys + 1] = "button" .. name .. "Y"
end
-- Every information and tooltip setting belongs to the texts category.
do
    local texts = CATEGORIES[#CATEGORIES].keys
    local names = {}
    for key in pairs(NS.SuiteCatalog.minimap.rules) do
        if key:find("^info") or key:find("^tooltip") then names[#names + 1] = key end
    end
    table.sort(names)
    for i = 1, #names do texts[#texts + 1] = names[i] end
end

local function Dirty(self)
    local c, applied, force, dirty = self.config, self.applied, self.force, self.dirty
    for i = 1, #CATEGORIES do
        local category = CATEGORIES[i]
        local changed = force[category.name] == true
        local keys = category.keys
        for j = 1, #keys do
            if changed then break end
            if applied[keys[j]] ~= c[keys[j]] then changed = true end
        end
        dirty[category.name], force[category.name] = changed, nil
    end
    return dirty
end
local function Commit(self)
    for key, value in pairs(self.config) do self.applied[key] = value end
end

local function AddonLoaded(_, _, name)
    if name == "Blizzard_HybridMinimap" then
        if M.mapOwned then MM.ApplyHybrid() end
    elseif name == "Blizzard_TimeManager" then
        if M.mapOwned and not NS.IsCombatLocked() then MM.ApplyDecorations() end
    end
    -- Blizzard addons create more minimap buttons (queue eye, clock).
    if type(name) == "string" and name:find("^Blizzard_") then MM.Queue("rows") end
end
-- WoW Forever's skin swaps the mask when rotation changes; ours goes back on after it.
local function CVarChanged(_, _, name)
    if name == "rotateMinimap" and M.mapOwned then MM.Queue("mask") end
end
MM.flushers.mask = function()
    if M.mapOwned then MM.ApplyMap(true) end
end
MM.flushers.hoverSize = function()
    local width, height, active = MM.Dimensions()
    if width == MM.width and height == MM.height and active == MM.hoverGeometryActive then return end
    if NS.IsCombatLocked() then MM.Force("geometry"); S.Queue("minimap"); return end
    MM.ApplyHost()
    if M.mapOwned then MM.ApplyMap(true) end
    MM.ApplyBorder()
    MM.LayoutElements()
    MM.LayoutDrawer()
end
MM.OnHover(function()
    if M.active and M.config.hoverResize then MM.Queue("hoverSize") end
end)

function M:Enable()
    self.applied, self.force, self.dirty = {}, {}, {}
    self.mapOwned = false
    S.states.minimap.reloadRequired = nil
    MM.EnsureFrames()
    MM.HookMap()
    MM.InstallShape()
    MM.Listen("ADDON_LOADED", "host", AddonLoaded)
    MM.Listen("PLAYER_ENTERING_WORLD", "elements", MM.ReassertElements)
    if _G.MinimapCompassTextureUnderlay then MM.Listen("CVAR_UPDATE", "mask", CVarChanged) end
    S.SuppressHostElement("minimap", HOST_ELEMENT, true)
    MM.PrepareCapture()
    self:Refresh()
end

function M:Refresh()
    if NS.IsCombatLocked() then S.Queue("minimap"); return end
    MM.EnsureFrames()
    local c, dirty = self.config, Dirty(self)
    if dirty.geometry or dirty.position then MM.ApplyHost() end
    if dirty.geometry then
        if self.mapOwned then MM.ApplyMap(true) end
        if not c.collectButtons then MM.RefreshIcons() end
    end
    if not self.mapOwned then MM.Queue("claim") end
    if dirty.border or dirty.geometry then MM.ApplyBorder() end
    if dirty.input then MM.ApplyInput() end
    if dirty.elements or dirty.geometry then MM.LayoutElements() end
    if dirty.drawer then MM.ApplyDrawer() elseif dirty.geometry then MM.LayoutDrawer() end
    if dirty.texts then MM.RefreshTexts() elseif MM.HideInfoTooltip then MM.HideInfoTooltip() end
    MM.ApplyVisibility()
    MM.NotifyHover()
    Commit(self)
end

function M:Disable()
    if MM.style then MM.style:Hide() end
    MM.ReleaseTexts()
    if MM.HideInfoTooltip then MM.HideInfoTooltip() end
    MM.ReleaseDrawer()
    MM.ReleaseElements()
    MM.ReleaseInput()
    local lost = MM.ReleaseHost()
    MM.RemoveShape()
    MM.UnlistenAll()
    S.SuppressHostElement("minimap", HOST_ELEMENT, false)
    self.applied, self.force = {}, {}
    if lost then S.states.minimap.reloadRequired = S.Text("Reload the UI to restore Blizzard's minimap layout") end
end

function M:RegisterMovers()
    S.RegisterOwnedMover("minimap", "map", {
        label = MM.Label("MINIMAP_LABEL", "Minimap"), order = 500,
        getFrame = function() return MM.host end,
        xKey = "x", yKey = "y", pointKey = "point",
        point = function() return MM.ANCHORS[M.config.point] or "TOPRIGHT" end,
        isEnabled = function() return M.active == true and MM.host ~= nil end,
        historyKeys = { "size" },
        extraControls = {
            { id = "size", label = "Size", kind = "number", min = 100, max = 600, step = 5,
              get = function() return S.Config("minimap").size end,
              set = function(value) return S.Set("minimap", "size", value) end },
        },
    })
end

function S.CanShapeMinimap()
    local map = _G.Minimap
    return MM.Usable(map) and type(map.SetMaskTexture) == "function" and type(map.SetParent) == "function" or false
end

S.Install("minimap", M)

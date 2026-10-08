local _, P = ...
local NS, S = P.NS, P.Suite
local MM = P.Minimap
local M = MM.M
-- Lifecycle and the split apply. A category re-runs only when one of its
-- settings changed, so a slider touches only what it affects; geometry is the
-- only category that re-renders the map (the zoom nudge).
local HOST_ELEMENT = "external:msuf.blizzard:minimap"
-- A category re-runs when a setting of one of its catalog sections changed
-- (MSUF_Suite/Core/Catalog/Minimap.lua; prefix: every section whose name
-- starts with it) or one of its extra keys: settings another section owns
-- that this category also reads. A new setting of a section joins its
-- categories without another list to maintain.
local CATEGORIES = {
    { name = "geometry", sections = { "hover_size" }, extra = { "size", "shape" } },
    { name = "position", extra = { "point", "x", "y" } },
    { name = "border", sections = { "shape", "style_presets", "style_art", "style_glow", "style_backdrop" },
        extra = { "size" } },
    { name = "input", sections = { "behavior" }, extra = { "hoverResize", "showLanding", "collectButtons",
        "drawerMouseover", "infoCoordinates", "infoCoordinatesMode" } },
    { name = "elements", sections = { "elements", "landing" }, extra = { "infoDifficulty", "borderSize" } },
    { name = "drawer", sections = { "addons" }, extra = { "elementRow", "elementSize", "elementSpacing",
        "elementDistance", "borderSize", "borderColor", "borderClassColor" } },
    { name = "specialization", sections = { "specialization" }, extra = { "borderColor", "borderClassColor" } },
    -- Every information text and its tooltip settings.
    { name = "texts", prefix = "info_", extra = { "borderSize", "borderColor", "borderClassColor", "showCalendar" } },
}
MM.applyCategories = CATEGORIES

local function Covers(category, section)
    if not section then return false end
    if category.prefix and section:sub(1, #category.prefix) == category.prefix then return true end
    for _, name in ipairs(category.sections or {}) do
        if name == section then return true end
    end
    return false
end

-- category.keys: its extra keys, then its sections' settings in catalog order.
for _, category in ipairs(CATEGORIES) do
    local keys, listed = {}, {}
    for _, key in ipairs(category.extra or {}) do keys[#keys + 1], listed[key] = key, true end
    for _, rule in ipairs(NS.SuiteCatalog.minimap.controls) do
        if not listed[rule.key] and Covers(category, rule.section) then
            keys[#keys + 1], listed[rule.key] = rule.key, true
        end
    end
    category.keys = keys
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
    local fontPath, fontEpoch = S.GlobalFontPath(), _G.MSUF_FontApplyEpoch
    if applied.__fontPath ~= fontPath or applied.__fontEpoch ~= fontEpoch then
        dirty.texts = true
    end
    return dirty
end
local function Commit(self)
    for key, value in pairs(self.config) do self.applied[key] = value end
    self.applied.__fontPath, self.applied.__fontEpoch = S.GlobalFontPath(), _G.MSUF_FontApplyEpoch
end

local function AddonLoaded(_, _, name)
    if name == "MinimapButtonButton" then
        -- Yield any buttons already in our drawer before MBB collects them on
        -- PLAYER_LOGIN. The normal Suite refresh defers protected work in combat.
        if M.active then
            MM.Force("drawer")
            MM.Force("input")
            S.Apply("minimap")
        end
    elseif name == "Blizzard_HybridMinimap" then
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
-- Placing the protected map waits for combat to end (geometry re-applies it).
MM.flushers.mask = function()
    if not M.mapOwned then return end
    if NS.IsCombatLocked() then
        MM.Force("geometry")
        S.Queue("minimap")
        return
    end
    MM.ApplyMap(true)
end
MM.flushers.hoverSize = function()
    local width, height, active = MM.Dimensions()
    if width == MM.width and height == MM.height and active == MM.hoverGeometryActive then return end
    if NS.IsCombatLocked() then
        MM.Force("geometry")
        S.Queue("minimap")
        return
    end
    MM.ApplyHost()
    if M.mapOwned then MM.ApplyMap(true) end
    MM.ApplyBorder()
    MM.LayoutElements()
    MM.LayoutDrawer()
    MM.ApplySpecialization()
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
    -- The underlay exists on WoW Forever's Camelot skin only.
    if _G.MinimapCompassTextureUnderlay then MM.Listen("CVAR_UPDATE", "mask", CVarChanged) end
    S.SuppressHostElement("minimap", HOST_ELEMENT, true)
    MM.PrepareCapture()
    self:Refresh()
end

function M:Refresh()
    if NS.IsCombatLocked() then
        S.Queue("minimap")
        return
    end
    -- Reset replaces geometry with explicit defaults. An already-owned map
    -- must never defer first-enable capture over edits made after that reset.
    if self.mapOwned and not self.config.captured then S.Set("minimap", "captured", true) end
    MM.EnsureFrames()
    local dirty = Dirty(self)
    if dirty.geometry or dirty.position then MM.ApplyHost() end
    if dirty.geometry then
        if self.mapOwned then MM.ApplyMap(true) end
        if not MM.CollectsButtons() then MM.RefreshIcons() end
    end
    if not self.mapOwned then MM.Queue("claim") end
    if dirty.border or dirty.geometry then MM.ApplyBorder() end
    if dirty.input then MM.ApplyInput() end
    if dirty.elements or dirty.geometry then MM.LayoutElements() end
    if dirty.drawer then MM.ApplyDrawer() elseif dirty.geometry then MM.LayoutDrawer() end
    if dirty.specialization or dirty.geometry then MM.ApplySpecialization() end
    if dirty.texts then MM.RefreshTexts() else MM.HideInfoTooltip() end
    MM.ApplyVisibility()
    MM.NotifyHover()
    Commit(self)
end

function M:Disable()
    if MM.style then MM.style:Hide() end
    MM.ReleaseTexts()
    MM.HideInfoTooltip()
    MM.ReleaseSpecialization()
    MM.ReleaseDrawer()
    MM.ReleaseElements()
    MM.ReleaseInput()
    local lost = MM.ReleaseHost()
    MM.RemoveShape()
    MM.UnlistenAll()
    S.SuppressHostElement("minimap", HOST_ELEMENT, false)
    self.applied, self.force = {}, {}
    -- Stored in English; the menu translates statuses when it shows them.
    if lost then S.states.minimap.reloadRequired = "Reload the UI to restore Blizzard's minimap layout" end
end

function M:RegisterMovers()
    S.RegisterOwnedMover("minimap", "map", {
        label = S.BlizzardText("MINIMAP_LABEL", "Minimap"), order = 500,
        getFrame = function() return MM.host end,
        xKey = "x", yKey = "y", pointKey = "point",
        point = function() return MM.ANCHORS[M.config.point] or "TOPRIGHT" end,
        isEnabled = function() return M.active == true and MM.host ~= nil end,
        historyKeys = { "size" },
        extraControls = {
            { id = "size", label = "Size", kind = "number", min = 100, max = 600, step = 1,
                get = function() return S.Config("minimap").size end,
                set = function(value) return S.Set("minimap", "size", value) end },
        },
    })
end

function S.CanShapeMinimap()
    return MM.Usable(_G.Minimap)
end

S.Install("minimap", M)

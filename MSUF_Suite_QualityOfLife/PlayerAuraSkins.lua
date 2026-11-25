local _, P = ...
local NS, S = P.NS, P.Suite
local M = {}
-- MSUF's icon skins (the Icon Skins page rows "Buffs" and "Debuffs": the
-- Player aura layout settings buffSkin and debuffSkin) on Blizzard's own
-- player buffs and debuffs, at Blizzard's size and layout, while Player aura
-- layout (PlayerAuras.lua, which paints them itself) is off.
--
-- Blizzard_BuffFrame (live 12.1.5 and Forever 1.60.1) makes every aura button
-- once, when it loads (AuraFrame_OnLoad: maxAuras buttons per frame); aura
-- updates only show, hide and refill them, and the grid layout (Edit Mode
-- too) scales a button and anchors its fixed 30x30 Icon again. A skin is
-- textures of the button around its Icon, so it follows all of that by
-- itself: every button is painted once, out of combat (enable, a choice on
-- the Icon Skins page, MSUF's report, Player aura layout going off), and no
-- aura update, layout or combat runs any code here. Private aura anchors
-- (isAuraAnchor), the deadly debuff and external defensives frames stay
-- Blizzard's. Side tables only; nothing is written onto Blizzard frames.
-- After a reload in combat the Suite starts its modules when combat ends (the
-- controller's rule, as for the action bars' skins), so the skins appear then:
-- painting in combat would make textures in combat.
--   painted  button -> { look, w, h } it shows
--   layers   native region -> its original draw layer and sublevel
local painted, layers = {}, {}
local yielded = false -- Player aura layout paints the buttons now
local waiting -- a frame that paints at the combat end
local IsSecret, IsForbidden = NS.IsSecret, NS.Safety.IsForbidden

local function Layer(region, target)
    if IsSecret(region) or not region or IsForbidden(region) or not region.SetDrawLayer then return end
    local before = layers[region]
    if target and not before then
        local layer, sublayer = region:GetDrawLayer()
        if IsSecret(layer) or IsSecret(sublayer) then return end
        layers[region] = { layer, sublayer or 0 }
        region:SetDrawLayer(target, 0)
    elseif not target and before then
        layers[region] = nil
        region:SetDrawLayer(before[1], before[2])
    end
end

-- AuraButtonArtTemplate puts Icon on BACKGROUND and the native dispel and
-- enchant borders on OVERLAY. Keep their colors above Icon, below the skin's
-- ARTWORK and gloss. Count and Symbol already draw above the gloss.
local function SetLayers(button, skin)
    Layer(button.Duration, skin and "OVERLAY")
    Layer(button.DebuffBorder, skin and "BORDER")
    Layer(button.TempEnchantBorder, skin and "BORDER")
end

-- One button at its Icon's size; a button that never showed a skin never
-- calls MSUF.
local function PaintLook(cache, button, icon, look, w, h)
    local shown = cache[button]
    if not (look or shown) then return end
    if shown and shown.look == look and shown.w == w and shown.h == h then return true end
    local skin = NS.HostBridge.PaintIconSkin(button, look, w, h, icon)
    cache[button] = skin and { look = look, w = w, h = h } or nil
    SetLayers(button, skin)
    return skin
end

local function NativeIcon(button)
    local icon, private = button.Icon, button.isAuraAnchor
    if not (IsSecret(private) or private or IsSecret(icon) or not icon or IsForbidden(icon)) then return icon end
end

local function NativeGrid(container)
    if IsSecret(container) or not container or IsForbidden(container) then return end
    local cache = container.currentGridLayoutInfo
    if not IsSecret(cache) and type(cache) == "table" then return cache end
end

local OPPOSITE = { TOP = "BOTTOM", BOTTOM = "TOP", LEFT = "RIGHT", RIGHT = "LEFT" }

-- The loaded BuffFrame grid anchors the icon to its slot and the timer to the
-- opposite edge of the icon, including Edit Mode's vertical and upward layouts.
local function NativePoints(button, region, container)
    local cache = NativeGrid(container)
    if not cache or IsForbidden(button) then return end
    local icon = NativeIcon(button)
    if not icon then return end
    local horizontal, up, right = cache.isHorizontal, cache.addIconsToTop, cache.addIconsToRight
    if IsSecret(horizontal) or IsSecret(up) or IsSecret(right) then return end
    local point
    if horizontal then point = up and "BOTTOM" or "TOP"
    else point = right and "LEFT" or "RIGHT" end
    if region == icon then return { { n = 5, point, button, point, 0, 0 } } end
    local duration = button.Duration
    if not IsSecret(duration) and region == duration then
        return { { n = 5, point, icon, OPPOSITE[point], 0, 0 } }
    end
end

-- Restore native geometry while keeping the layout cache on an owned receiver.
local GRID_KEYS = { "isHorizontal", "iconStride", "iconPadding", "addIconsToRight", "addIconsToTop" }
local function RestoreGrid(frame)
    if IsForbidden(frame) then return end
    local container = frame.AuraContainer
    local cache = NativeGrid(container)
    if not cache then return end
    local anchor, layout = cache.anchor, cache.layout
    if IsSecret(anchor) or IsSecret(layout) or not anchor or not layout then return end
    -- Reuse the last native layout even while new settings are pending.
    local proxy = { currentGridLayoutInfo = cache, iconScale = container.iconScale,
        GetParent = function() return frame end }
    for _, key in ipairs(GRID_KEYS) do
        local value = cache[key]
        if IsSecret(value) then return end
        proxy[key] = value
    end
    local icons, collect = frame.auraFrames, frame.ConsolidatedBuffs
    local include = collect and collect:ShouldShow()
    if IsSecret(include) then return end
    if include then
        icons = { collect }
        for _, button in ipairs(frame.auraFrames) do icons[#icons + 1] = button end
    end
    for _, button in ipairs(icons) do
        if not button.Icon or not button.Duration or IsForbidden(button)
            or IsForbidden(button.Icon) or IsForbidden(button.Duration) then return end
    end
    AuraContainerMixin.UpdateGridLayout(proxy, icons, frame.doNotAnchorDisabledFrames)
end
-- While a button uses the native grid, its artwork may still have secret resolved bounds.
local function PaintNative(button, look, cache)
    if IsSecret(button) or not button or IsForbidden(button) then return end
    local icon = NativeIcon(button)
    if not icon then return end
    local w, h = icon:GetWidth(), icon:GetHeight()
    if not S.Finite(w) or w <= 0 then w = icon:GetWidth(true) end
    if not S.Finite(h) or h <= 0 then h = icon:GetHeight(true) end
    -- Ordinary AuraButtonArtTemplate textures on both clients start at 30 x 30.
    PaintLook(cache, button, icon, look, S.Finite(w) and w > 0 and w or 30, S.Finite(h) and h > 0 and h or 30)
end

local function PaintNativeRow(frame, look, cache)
    for _, button in ipairs(frame.auraFrames) do NS.Dispatch(PaintNative, button, look, cache) end
    if frame.ConsolidatedBuffs then NS.Dispatch(PaintNative, frame.ConsolidatedBuffs, look, cache) end
end

-- Natively anchored artwork can have secret bounds; PaintNative then sizes the skin from the template.
local function Paint(button, look)
    if look then return PaintNative(button, look, painted) end
    if IsSecret(button) or not button or IsForbidden(button) then return end
    PaintLook(painted, button)
end
local function PaintFrame(name, look)
    local frame = _G[name]
    if not frame then return end
    for _, button in ipairs(frame.auraFrames or {}) do Paint(button, look) end
    -- BuffFrame's consolidated buffs button (BuffFrame.xml) is its own child.
    Paint(frame.ConsolidatedBuffs, look)
end

-- The rows' looks while the piece runs and Player aura layout is off; else
-- none (every skin it painted goes). Out of combat only: a change in a fight
-- (a reload in combat) waits for its end.
local function Apply()
    if NS.IsCombatLocked() then
        if not waiting then
            waiting = S.CreateFrame("Frame")
            waiting:SetScript("OnEvent", function(frame)
                frame:UnregisterEvent("PLAYER_REGEN_ENABLED")
                Apply()
            end)
        end
        waiting:RegisterEvent("PLAYER_REGEN_ENABLED")
        return
    end
    local on, c = M.active and not yielded, S.Config("playerAuras")
    local bridge = NS.HostBridge
    PaintFrame("BuffFrame", on and bridge.PlayerAuraSkin(c.buffSkin) or nil)
    PaintFrame("DebuffFrame", on and bridge.PlayerAuraSkin(c.debuffSkin) or nil)
end

local function NativeLoaded(self, _, addon)
    if addon ~= "Blizzard_BuffFrame" then return end
    self.context:RemoveEvent("ADDON_LOADED")
    Apply()
end

function M:Enable()
    self.active = true
    -- MSUF's default icon skin changed: Refresh paints the new look.
    NS.HostBridge.WatchIconSkins("playerAuraSkins", true)
    if not (BuffFrame and DebuffFrame) then
        self.context:Event("ADDON_LOADED", NativeLoaded)
    end
    Apply()
end

function M:Refresh()
    Apply()
end

function M:Disable()
    self.active = false
    self.context:RemoveEvent("ADDON_LOADED")
    NS.HostBridge.WatchIconSkins("playerAuraSkins", false)
    Apply()
end

-- Player aura layout starts (on) or has let go of the buttons (off): the
-- skins it would paint over go first, and come back after it.
P.PlayerAuraSkins = {
    PaintNativeRow = PaintNativeRow,
    PaintLook = PaintLook,
    SetLayers = SetLayers,
    NativePoints = NativePoints,
    RestoreGrid = RestoreGrid,
    Yield = function(on)
        yielded = on == true
        Apply()
    end,
}

S.Install("playerAuraSkins", M)

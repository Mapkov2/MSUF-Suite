local _, P = ...
local NS, S = P.NS, P.Suite

-- The dungeon teleports of the keystone window: a listed key whose dungeon
-- the player has a learned portal for gets a secure spell button over its
-- row, built the way DungeonPortals.lua builds its buttons. They belong to a
-- secure layer on UIParent, which a state driver hides in combat, and anchor
-- to a plain proxy that copies the window's rect. The window keeps no
-- protected child and nothing protected anchors to it, so it closes, moves
-- and scales in combat too. A protected frame cannot change in combat: the
-- layer is built, aimed and moved after the window outside combat only.
local Teleport = {}
P.KeystoneTeleport = Teleport
local ICON_SIZE = 18
local ABOVE_WINDOW = 2 -- frame levels over the window and its own buttons
local VISIBILITY = "[combat] hide; show"

-- The learned portals by challenge map are read once per window opening and
-- request (DungeonPortals.lua scans the spell book), never per paint.
function Teleport.Reset(self)
    self.portals = nil
end

-- The learned portal to a challenge map, the newer spell when two lead there.
-- DungeonPortals.lua is absent on WoW Forever, which has no keystone window.
local function PortalFor(self, mapID)
    local choices = S.DungeonPortalChoices
    if not choices then return nil end
    if not self.portals then
        self.portals = {}
        for _, group in pairs((choices())) do
            for _, choice in ipairs(group) do
                local best = choice.learned and choice.map and self.portals[choice.map]
                if choice.learned and choice.map and (not best or choice.id > best.id) then
                    self.portals[choice.map] = choice
                end
            end
        end
    end
    return self.portals[mapID]
end

local function ShowTooltip(button)
    GameTooltip:SetOwner(button, "ANCHOR_LEFT")
    GameTooltip:SetSpellByID(button.spellID)
    GameTooltip:Show()
end

-- Leaving a row closes only the tooltip it still owns.
local function HideTooltip(button)
    if GameTooltip:IsOwned(button) then GameTooltip:Hide() end
end

local function NewButton(self, layer, index)
    local layout, proxy = self.layout, self.teleportProxy
    local y = -layout.top - (index - 1) * layout.step
    local button = S.CreateFrame("Button", nil, layer, "SecureActionButtonTemplate")
    button:SetPoint("TOPLEFT", proxy, "TOPLEFT", layout.inset, y)
    button:SetPoint("TOPRIGHT", proxy, "TOPRIGHT", -layout.inset, y)
    button:SetHeight(layout.step - 1)
    button:SetAttribute("type", "spell")
    button:SetAttribute("useOnKeyDown", false)
    button:RegisterForClicks("AnyUp")
    local highlight = S.CreateTexture(button, nil, "HIGHLIGHT")
    highlight:SetAllPoints()
    highlight:SetColorTexture(1, 1, 1, .08)
    button.icon = S.CreateTexture(button, nil, "ARTWORK")
    button.icon:SetSize(ICON_SIZE, ICON_SIZE)
    button.icon:SetPoint("RIGHT", -4, 0)
    button:SetScript("OnEnter", ShowTooltip)
    button:SetScript("OnLeave", HideTooltip)
    return button
end

-- The proxy covers the window's rect in UIParent units, the way
-- DungeonPortals.lua copies the minimap's corner, and the layer takes the
-- window's effective scale: the rows' offsets and heights are window units.
local function Mirror(self)
    local host, proxy, Finite = self.host, self.teleportProxy, S.Finite
    local left, bottom, width, height = host:GetRect()
    local scale, own = host:GetEffectiveScale(), proxy:GetEffectiveScale()
    if not (Finite(left) and Finite(bottom) and Finite(width) and Finite(height)
        and Finite(scale) and Finite(own) and own > 0) then return end
    local ratio = scale / own
    self.teleportLayer:SetScale(ratio)
    proxy:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", left * ratio, bottom * ratio)
    proxy:SetSize(width * ratio, height * ratio)
end

-- Out of combat the layer follows the window: it takes the window's rect and
-- shows while the window shows (moving: a drag runs, and the layer waits for
-- the drop). In combat the state driver keeps the layer hidden, and the
-- change waits for Teleport.CombatEnded. Returns true while it waits.
function Teleport.Follow(self, moving)
    local layer = self.teleportLayer
    if not layer then return false end
    if NS.IsCombatLocked() then
        self.teleportStale = true
        return true
    end
    self.teleportStale = nil
    local shown = self.host:IsShown() and not moving
    if shown then Mirror(self) end
    if shown == self.teleportShown then return false end
    self.teleportShown = shown
    if shown then
        RegisterStateDriver(layer, "visibility", VISIBILITY)
    else
        -- The driver shows its frame again on every update while it holds it.
        UnregisterStateDriver(layer, "visibility")
        layer:Hide()
    end
    return false
end

function Teleport.CombatEnded(self)
    if self.teleportStale then Teleport.Follow(self) end
end

-- The layer draws over the window: its buttons take the strata and the
-- frame level it has when they are created.
local function Layer(self)
    if self.teleportLayer then return self.teleportLayer end
    local host = self.host
    local layer = S.CreateFrame("Frame", nil, UIParent, "SecureHandlerStateTemplate")
    layer:SetAllPoints(UIParent)
    layer:SetFrameStrata(host:GetFrameStrata())
    layer:SetFrameLevel(host:GetFrameLevel() + ABOVE_WINDOW)
    layer:Hide()
    self.teleportLayer, self.teleportButtons, self.teleportShown = layer, {}, false
    self.teleportProxy = S.CreateFrame("Frame", nil, UIParent)
    Teleport.Follow(self)
    return layer
end

-- Aims one button per listed row at the portal to that row's dungeon
-- (maps[i] is the row's challenge map or nil) and hides the others. Combat
-- locks the protected buttons: then nothing changes, and the window paints
-- again when combat ends.
function Teleport.Paint(self, maps)
    if NS.IsCombatLocked() then return end
    local portals, any = self.rowPortals or {}, false
    self.rowPortals = portals
    for i = 1, self.layout.rows do
        portals[i] = maps[i] and PortalFor(self, maps[i]) or false
        any = any or portals[i] ~= false
    end
    if not any and not self.teleportLayer then return end
    local layer = Layer(self)
    for i = 1, self.layout.rows do
        local button = self.teleportButtons[i] or NewButton(self, layer, i)
        self.teleportButtons[i] = button
        local portal = portals[i]
        if portal then
            button.spellID = portal.id
            button:SetAttribute("spell", portal.id)
            button.icon:SetTexture(portal.icon)
            button:Show()
        else
            button:Hide()
        end
    end
end

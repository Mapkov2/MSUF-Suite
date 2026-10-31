local _, private = ...
local NS = private.NS
local Style = NS.NameplateStyle
local LOOK_BLIZZARD = private.Mode.LOOK_BLIZZARD
local Prefix = private.PlatePrefix
-- A highlight on the skinned nameplate under the mouse (Blizzard indicators >
-- Target and focus). UPDATE_MOUSEOVER_UNIT reports a change of the mouseover
-- unit; Blizzard's compact frames set and clear their mouseover highlight on
-- this event alone (CompactUnitFrame_UpdateSelectionHighlight, upstream/live
-- and forever). Only the plate that lost the mouse and the one that gained it
-- repaint, as on a target change (Skin.lua OnTargetChanged). The event is
-- registered only while the setting is on; the highlight is the Suite's own
-- texture on the health bar (NameplateStyle.lua CreateHighlight), made on a
-- plate's first highlight.
local Hover = {}
private.Mouseover = Hover
local M
local IN_COMBAT = { inCombat = true }
local highlights = setmetatable({}, { __mode = "k" })
-- The unit frame highlighted now, and the color of the current settings.
local hovered, color
local listening = false

function Hover.Bind(module) M = module end

local function Safe(frame)
    return frame and not NS.Safety.IsForbidden(frame)
end

local function HealthBar(uf)
    local health = uf.HealthBarsContainer and uf.HealthBarsContainer.healthBar
    if Safe(health) then return health end
end

local function Hide(uf)
    local health = HealthBar(uf)
    local texture = health and highlights[health]
    if texture then texture:Hide() end
end

local function Show(uf)
    local health = HealthBar(uf)
    if not health then return end
    local texture = highlights[health]
    if not texture then
        texture = Style.CreateHighlight(health)
        highlights[health] = texture
    end
    if texture._npColor ~= color then
        Style.PaintHighlight(texture, color)
        texture._npColor = color
    end
    texture:Show()
end

-- Whether the skin styles this plate's side.
local function Styled(uf)
    local prefix = Safe(uf) and Prefix(uf)
    return prefix and M.config[prefix] and true or false
end

local function OnMouseover()
    local plate = C_NamePlate.GetNamePlateForUnit("mouseover")
    local current = Safe(plate) and plate.UnitFrame or nil
    if current and not Styled(current) then current = nil end
    if current == hovered then return end
    if hovered then Hide(hovered) end
    hovered = current
    if current then Show(current) end
end

local function Clear()
    if hovered then Hide(hovered) end
    hovered = nil
end

-- Settings changed (Skin.lua Refresh): the event follows the setting, and
-- the plate under the mouse takes the new color or loses its highlight.
function Hover.Configure()
    local c = M.config
    local on = c.mouseoverHighlight == true and c.look ~= LOOK_BLIZZARD
    color = c.mouseoverHighlightColor or "ffffff"
    if on and not listening then
        M.context:Event("UPDATE_MOUSEOVER_UNIT", OnMouseover, IN_COMBAT)
        listening = true
    elseif not on and listening then
        M.context:RemoveEvent("UPDATE_MOUSEOVER_UNIT")
        listening = false
    end
    Clear()
    if on then OnMouseover() end
end

-- A plate that leaves (Skin.lua RestorePlate) takes its highlight along.
function Hover.Restore(uf)
    Hide(uf)
    if hovered == uf then hovered = nil end
end

function Hover.Disable()
    Clear()
    listening = false
end

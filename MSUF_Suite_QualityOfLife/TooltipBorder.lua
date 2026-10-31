local _, P = ...
local NS, S = P.NS, P.Suite

-- Colors the border of Blizzard's main tooltip by item quality or by the
-- unit's class or reaction. The color is chosen once per tooltip build, from
-- the item link of the tooltip data or the unit token (TooltipLines.lua), and
-- given back when the tooltip clears or hides, and when the helper stops.
-- Whoever draws the border paints it. The Suite skin fades Blizzard's border
-- art and draws its own edge on the tooltip (MSUF_Suite_Skin core-tooltips
-- entry), so while it does the color goes to that edge (Skin.TintEdge).
-- Otherwise Blizzard's NineSlice shows the border and takes the color.
local B = {}
S.TooltipBorder = B
-- Values of the "Tooltip border color" choice (1 keeps the border as it is).
local ITEMS, UNITS, BOTH = 2, 3, 4
local SKIN, NATIVE = "skin", "native"
local painted
-- Blizzard's border color before ours: r, g, b, alpha.
local native = {}

local function ItemColor(data)
    local link = S.PublicText(data.hyperlink)
    if not link then return end
    local quality = C_Item.GetItemQualityByID(link)
    if not S.Finite(quality) then return end
    local r, g, b = C_Item.GetItemQualityColor(quality)
    if S.Finite(r) and S.Finite(g) and S.Finite(b) then return r, g, b end
end

-- Players take their class color, every other unit its reaction color.
local function UnitColor(unit)
    local player = UnitIsPlayer(unit)
    if not S.Public(player) then return end
    local color
    if player then
        local _, class = UnitClass(unit)
        class = S.PublicText(class)
        color = class and RAID_CLASS_COLORS[class]
    else
        local reaction = UnitReaction(unit, "player")
        color = S.Finite(reaction) and FACTION_BAR_COLORS[reaction]
    end
    if color then return color.r, color.g, color.b end
end

local function PaintNative(tooltip, r, g, b)
    local slice = tooltip.NineSlice
    if not slice then return false end
    native[1], native[2], native[3], native[4] = slice:GetBorderColor()
    slice:SetBorderColor(r, g, b, native[4])
    return true
end

function B.Restore(tooltip)
    local owner = painted
    painted = nil
    if not owner or NS.Safety.IsForbidden(tooltip) then return end
    if owner == SKIN then
        NS.Skin.TintEdge(tooltip)
    elseif native[1] then
        tooltip.NineSlice:SetBorderColor(native[1], native[2], native[3], native[4])
    end
end

local function Paint(tooltip, r, g, b)
    B.Restore(tooltip)
    if NS.Skin.TintEdge(tooltip, r, g, b) then
        painted = SKIN
    elseif PaintNative(tooltip, r, g, b) then
        painted = NATIVE
    end
end

-- mode is the "Tooltip border color" choice: item tooltips take theirs in
-- the item and both modes, unit tooltips in the unit and both modes.
function B.Item(tooltip, data, mode)
    if mode ~= ITEMS and mode ~= BOTH then return end
    local r, g, b = ItemColor(data)
    if r then Paint(tooltip, r, g, b) end
end

function B.Unit(tooltip, unit, mode)
    if mode ~= UNITS and mode ~= BOTH then return end
    local r, g, b = UnitColor(unit)
    if r then Paint(tooltip, r, g, b) end
end

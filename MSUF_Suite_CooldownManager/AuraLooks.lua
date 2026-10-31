local _, P = ...
local NS, S = P.NS, P.Suite
local C = P.CDM
-- Per-spell looks inside Blizzard's aura buttons (AuraButtons.lua's
-- ApplyEntry asks, with the same dry/write contract and only while the
-- buttons accept writes): the border while the buff is active (a button
-- shows only while its aura is active, so its border is the active one),
-- and a buff bar's own fill color and name. Each part keeps what it was
-- painted with; the button's style pass (Style) paints the bar's look and
-- drops these memos, so an unchanged sync writes nothing and an entry
-- without these choices costs three compares.
local K = C.Const
local max = math.max
local AuraLooks = {}
C.AuraLooks = AuraLooks

-- "Border color while active" (activeBorder; "" the bar's border): square
-- buttons draw it as their edges, at least one pixel wide; shaped ones
-- tint their rings.
local function Border(rec, part, ov, dry)
    local hex = ov.activeBorder
    if hex == "" then hex = nil end
    if part.borderHex == hex then return false end
    if dry then return true end
    part.borderHex = hex
    local lk = rec.lk
    local r, g, b = lk.er, lk.eg, lk.eb
    if hex then r, g, b = K.HexRGB(hex) end
    if rec.role ~= "bar" and lk.shape ~= K.SQUARE then
        local rings = part.rings or C.EMPTY
        for i = 1, #rings do rings[i]:SetVertexColor(r, g, b, 1) end
    else
        K.PlaceEdges(part.edges, part.button, hex and max(lk.bw, lk.px) or lk.bw, r, g, b, 1)
    end
    return false
end

-- A buff bar's fill (barColor; "" the bar's color) and its background.
local function Fill(rec, part, ov, dry)
    local hex = ov.barColor
    if hex == "" then hex = nil end
    if part.fillHex == hex or not part.bar then return false end
    if dry then return true end
    part.fillHex = hex
    local lk = rec.lk
    local r, g, b = lk.fr, lk.fg, lk.fb
    if hex then r, g, b = K.HexRGB(hex) end
    part.bar:SetStatusBarColor(r, g, b, 1)
    part.bg:SetVertexColor(r * .25, g * .25, b * .25, lk.bgA)
    return false
end

-- A buff bar's own name (barText; "" the spell's): Blizzard keeps writing
-- the spell's name into its bound string, which steps aside (alpha) while
-- the label (made with the button where the bar asks for it) shows ours.
local function Label(part, ov, dry)
    local label = part.label
    if not label then return false end
    local text = ov.barText
    if text == "" then text = nil end
    if part.labelText == text then return false end
    if dry then return true end
    part.labelText = text
    label:SetText(text or "")
    label:SetShown(text ~= nil)
    part.name:SetAlpha(text and 0 or 1)
    return false
end

-- part.looked: the part shows one of them, so it is asked again after the
-- bar's entries stop choosing any (AuraButtons.lua ApplyEntry).
function AuraLooks.Apply(rec, part, ov, dry)
    if Border(rec, part, ov, dry) then return true end
    if rec.role == "bar" and (Fill(rec, part, ov, dry) or Label(part, ov, dry)) then return true end
    if not dry then part.looked = part.borderHex ~= nil or part.fillHex ~= nil or part.labelText ~= nil end
    return false
end

-- The style pass painted the bar's edges and fill: those memos start over
-- (the label keeps its text and shown state through a restyle).
function AuraLooks.Restyled(part)
    part.borderHex, part.fillHex = nil, nil
end

-- Diagnostics and tests: what a part shows now.
function C.Diagnostics.AuraLook(part)
    return part.borderHex, part.fillHex, part.labelText
end

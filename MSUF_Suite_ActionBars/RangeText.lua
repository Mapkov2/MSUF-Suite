local _, P = ...
local AB = P.ActionBars
local USABLE = P.Suite.USABLE
local IsSecret = P.NS.IsSecret
local OK, UNUSABLE, RANGE = USABLE.USABLE, USABLE.UNUSABLE, USABLE.OUT_OF_RANGE

-- The default painter stays a direct function call with no optional-mode
-- branch. The controller selects the alternative only on a style change.
function AB.TintIcon(rec)
    local icon = rec.button.icon
    if not icon then return end
    local style, code = AB.style, rec.usable or OK
    local key = rec.outOfRange and RANGE or code
    if rec.tint == key then return end
    if key == RANGE then
        icon:SetVertexColor(style.rr, style.rg, style.rb)
    else
        local color = style.tints[key] or style.tints[UNUSABLE]
        icon:SetVertexColor(color[1], color[2], color[3])
    end
    rec.tint = key
end

-- No native lookup: range events already resolve the action button and
-- state. Only the optional text mode enters here; unchanged colors do not
-- write to the font string again.
function AB.RangeKey(rec)
    local text = rec.keyText or rec.button.HotKey
    if not text then return end
    local style = AB.style
    local out = rec.outOfRange == true
    if rec.keyRange == out and rec.keyRangeStyle == AB.styleGen then return end
    rec.keyRange, rec.keyRangeStyle = out, AB.styleGen
    if out then text:SetTextColor(style.rr, style.rg, style.rb)
    else
        text:SetTextColor(style.kr, style.kg, style.kb)
    end
end

function AB.TintWithKey(rec, nativePaint)
    AB.RangeKey(rec)
    if AB.style.rangeIcon then return AB.TintIcon(rec) end
    -- A native post-hook has just painted usability. Keep that result without
    -- duplicating its query. Cold refreshes still resolve an unknown state so
    -- switching away from icon range coloring restores the right mana tint.
    if nativePaint and not AB.style.customTints then return end
    if rec.usable == nil and rec.slot then
        local usable, noMana = AB.Painter.api.Usable(rec.slot)
        rec.usable = (not IsSecret(usable) and usable) and OK
            or (not IsSecret(noMana) and noMana) and USABLE.NO_POWER or UNUSABLE
    end
    local out = rec.outOfRange
    rec.outOfRange = nil
    AB.TintIcon(rec)
    rec.outOfRange = out
end

function AB.ConfigureRangeTint()
    AB.Painter.SetTint(AB.style.rangeKey and AB.TintWithKey or AB.TintIcon)
end

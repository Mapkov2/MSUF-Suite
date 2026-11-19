local _, P = ...
local S = P.Suite

-- Another Suite surface can stand in for the MSUF experience bar for a
-- while: the flight route timer's Timer bar takes its place while the player
-- flies (FlightTimer.lua, replaceXPBar). The slot is the shown bar's host, nil
-- while there is none to replace. A covered bar keeps its layout, events and
-- place, so nothing anchored to it moves: it only draws nothing and takes no
-- mouse until it is handed back.
-- The stand-in learns when the bar shows or hides (S.ExperienceSlotChanged,
-- after the bar's own OnShow/OnHide), so a bar that is switched off or hidden
-- at the level cap is handed back. The hooks join the host the first time a
-- slot is asked for; ExperienceBar.lua itself stays unaware of stand-ins.
local covered, watched = false, nil

local function Changed()
    S.ExperienceSlotChanged()
end

function S.ExperienceBarSlot()
    local bar = S.instances.xpBar
    local host = bar.host
    if not host then return nil end
    if watched ~= host then
        watched = host
        host:HookScript("OnShow", Changed)
        host:HookScript("OnHide", Changed)
    end
    if bar.active and bar.hostVisible then return host end
end

function S.CoverExperienceBar(cover)
    local bar = S.instances.xpBar
    local host = bar.host
    cover = cover == true
    if not host or covered == cover then return end
    covered = cover
    host:SetAlpha(cover and 0 or 1)
    host:EnableMouse(not cover)
    -- The bar's own OnLeave closes a tooltip the pointer left open over it.
    if cover and bar.hovered then host:GetScript("OnLeave")(host) end
end

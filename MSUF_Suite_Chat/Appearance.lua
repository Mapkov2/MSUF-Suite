local _, P = ...
local S = P.Suite
local C = P.Chat
local NATIVE_FADE = {
    { "GetFading", "SetFading" }, { "GetTimeVisible", "SetTimeVisible" }, { "GetFadeDuration", "SetFadeDuration" },
}

-- Own only textures; native text, clipping and message heights stay native.
function C.PaintGradient(visual, panel, config)
    if config.panelGradient and config.panelAlpha > 0 then
        if not visual.gradientLeft then
            visual.gradientLeft = C.Fill(visual.frame, "BACKGROUND")
            visual.gradientRight = C.Fill(visual.frame, "BACKGROUND")
        end
        C.PlaceGradient(visual, panel, config.minimalChrome)
        local r, g, b = S.RGB(config.panelColor)
        local edge, center = CreateColor(r, g, b, 0), CreateColor(r, g, b, config.panelAlpha / 100)
        visual.gradientLeft:SetGradient("HORIZONTAL", config.minimalChrome and center or edge, center)
        visual.gradientRight:SetGradient("HORIZONTAL", center, edge)
        visual.gradientLeft:Show()
        visual.gradientRight:Show()
        panel:Hide()
    else
        C.HideGradient(visual)
    end
end

function C.HideGradient(visual)
    if visual.gradientLeft then
        visual.gradientLeft:Hide()
        visual.gradientRight:Hide()
    end
end

-- ScrollingMessageFrameSecureMixin exposes these setters as elevation
-- barriers (upstream/live and upstream/forever ScrollingMessageFrame.lua).
-- Never set native Lua fields or replace their methods. Keep restoration
-- separate from geometry ownership: focus can change during combat.
local function OwnFade(visual, index, value)
    local pair = NATIVE_FADE[index]
    local current = visual.frame[pair[1]](visual.frame)
    if not S.Public(current) then return end
    if visual.nativeFadeBefore[index] == nil or current ~= visual.nativeFadeApplied[index] then
        visual.nativeFadeBefore[index] = current
    end
    visual.frame[pair[2]](visual.frame, value)
    visual.nativeFadeApplied[index] = value
end

function C.ReleaseMessageFade(visual)
    if not visual.nativeFadeBefore then return end
    for index, pair in ipairs(NATIVE_FADE) do
        local before = visual.nativeFadeBefore[index]
        if before ~= nil then
            local current = visual.frame[pair[1]](visual.frame)
            if S.Public(current) and current == visual.nativeFadeApplied[index] then
                visual.frame[pair[2]](visual.frame, before)
            end
        end
    end
    visual.nativeFadeBefore, visual.nativeFadeApplied = nil, nil
end

function C.ApplyMessageFade(visual, config)
    -- Blizzard_CombatLog owns its own continuously rebuilt message display.
    if not config.messageFading or visual.frame == ChatFrame2 then
        C.ReleaseMessageFade(visual)
        return
    end
    visual.nativeFadeBefore = visual.nativeFadeBefore or {}
    visual.nativeFadeApplied = visual.nativeFadeApplied or {}
    OwnFade(visual, 1, not (visual.hovered or visual.frame.editBox:HasFocus()))
    OwnFade(visual, 2, config.messageTimeVisible)
    OwnFade(visual, 3, config.messageFadeDuration)
end

function C.MessageFadeFocus(visual, focused)
    if visual.nativeFadeBefore then OwnFade(visual, 1, not focused) end
end

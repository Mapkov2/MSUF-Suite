local _, P = ...
local S = P.Suite
local C = P.Chat
local NATIVE_FADE = { { "GetTimeVisible", "SetTimeVisible" }, { "GetFadeDuration", "SetFadeDuration" } }

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
--
-- Native fading has a second owner, QoL's "Keep chat messages visible"
-- (MSUF_Suite_QualityOfLife/DailyComfort.lua). Both hold a chat frame
-- through one record in S.chatFading: native is the frame's own value,
-- applied the last value written, keep and fade each one's hold. Keeping the
-- messages visible wins while both hold, the one left holding gets its own
-- value, and the last to let go writes native back. A change from elsewhere
-- since the last write becomes the new native value. QoL holds through
-- S.HoldChatFading once this addon is loaded and keeps the record itself
-- before that, while nothing else can hold the frame.
local fading = S.chatFading or setmetatable({}, { __mode = "k" })
S.chatFading = fading

-- Sets key's hold on the frame's fading (nil lets go) and writes the value
-- the holders leave.
local function HoldFading(frame, key, value)
    local record = fading[frame]
    if not record then
        if value == nil then return end
        record = {}
        fading[frame] = record
    end
    record[key] = value
    local current = frame:GetFading()
    if not S.Public(current) then return end
    if current ~= record.applied then record.native = current end
    local wanted = record.native
    if record.keep then
        wanted = false
    elseif record.fade ~= nil then
        wanted = record.fade
    else
        fading[frame] = nil
    end
    if wanted ~= current then frame:SetFading(wanted) end
    record.applied = wanted
end
S.HoldChatFading = HoldFading

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
    HoldFading(visual.frame, "fade", nil)
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
    HoldFading(visual.frame, "fade", not (visual.hovered or visual.frame.editBox:HasFocus()))
    OwnFade(visual, 1, config.messageTimeVisible)
    OwnFade(visual, 2, config.messageFadeDuration)
end

function C.MessageFadeFocus(visual, focused)
    if visual.nativeFadeBefore then HoldFading(visual.frame, "fade", not focused) end
end

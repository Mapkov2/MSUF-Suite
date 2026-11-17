local _, P = ...
local S, O = P.Suite, P.Objectives
local Public, Finite = S.Public, S.Finite
local GLYPHS = { play = "▶", stop = "■", replay = "↻" }

local function Overlay()
    local voice = _G.VoiceOver
    if not Public(voice) or type(voice) ~= "table" then return end
    local overlay = voice.QuestOverlayUI
    if Public(overlay) and type(overlay) == "table"
        and Public(overlay.ShowsTrackerButton) and type(overlay.ShowsTrackerButton) == "function"
        and Public(overlay.BindPlayButton) and type(overlay.BindPlayButton) == "function" then return overlay end
end

local function SetState(button, state)
    button.state = state
    button.glyph:SetText(GLYPHS[state] or GLYPHS.play)
end

local function SetPlayState(button, playing)
    local overlay = button.overlay
    if overlay and Public(overlay.FollowQueue) and type(overlay.FollowQueue) == "function" then
        S.Dispatch(overlay.FollowQueue, button)
    else
        SetState(button, playing and "stop" or "play")
    end
end

local function ShowTooltip(button)
    local overlay = button.overlay
    if overlay and Public(overlay.ShowPlayTip) and type(overlay.ShowPlayTip) == "function"
        and not P.NS.Safety.IsForbidden(GameTooltip) then
        S.Dispatch(overlay.ShowPlayTip, overlay, button)
    end
end

local function HideTooltip(button)
    if GameTooltip and not P.NS.Safety.IsForbidden(GameTooltip) and GameTooltip:IsOwned(button) then
        GameTooltip:Hide()
    end
end

local function Create(row)
    local button = S.CreateFrame("Button", nil, row)
    button:SetSize(20, 20)
    button:SetFrameLevel(row:GetFrameLevel() + 2)
    button:RegisterForClicks("LeftButtonUp")
    button.glyph = S.CreateFontString(button, nil, "OVERLAY", "GameFontHighlightSmall")
    button.glyph:SetPoint("CENTER", 0, 0)
    button:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")
    button.SetState, button.setPlayState = SetState, SetPlayState
    button:SetScript("OnEnter", ShowTooltip)
    button:SetScript("OnLeave", HideTooltip)
    button:SetScript("OnHide", HideTooltip)
    row.voiceButton = button
    return button
end

local function Release(row)
    local button = row.voiceButton
    if not button or not button.overlay then return end
    button:Hide()
    button:SetScript("OnClick", nil)
    button.questID, button.soundData, button.overlay, button.title = nil, nil, nil, nil
end
O.ReleaseQuestVoice = Release

function O.PaintQuestVoice(row, item, inset, color)
    local questID = item.questID
    local overlay = item.kind == "entry" and Finite(questID) and questID > 0 and Overlay()
    if not overlay then
        Release(row)
        return inset
    end
    local shown = S.Dispatch(overlay.ShowsTrackerButton, overlay, questID)
    if not Public(shown) or shown ~= true then
        Release(row)
        return inset
    end
    local title = Public(item.menuTitle) and type(item.menuTitle) == "string" and item.menuTitle or item.text
    if not Public(title) or type(title) ~= "string" then
        Release(row)
        return inset
    end
    local button = row.voiceButton or Create(row)
    if button.questID ~= questID or button.overlay ~= overlay or button.title ~= title then
        button:SetScript("OnClick", nil)
        button.soundData, button.questID, button.overlay, button.title = nil, questID, overlay, title
        S.Dispatch(overlay.BindPlayButton, overlay, button, questID, title, "MSUF Suite objective tracker")
        if not button:GetScript("OnClick") then
            Release(row)
            return inset
        end
        SetPlayState(button, false)
    end
    button:ClearAllPoints()
    button:SetPoint("RIGHT", row, "RIGHT", -inset, 0)
    button.glyph:SetTextColor(color[1], color[2], color[3])
    button:Show()
    return inset + 23
end

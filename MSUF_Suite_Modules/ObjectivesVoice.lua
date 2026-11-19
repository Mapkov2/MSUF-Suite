local _, P = ...
local S, O = P.Suite, P.Objectives
local Public, Finite = S.Public, S.Finite
local BUTTON_SIZE, ICON_SIZE = 18, 14
local CONTROLS = "Interface\\AddOns\\MSUF_Suite\\Media\\QuestVoiceControls.tga"
local ICON_TILES = { play = 0, stop = 1, replay = 2 }

local function Overlay()
    local voice = _G.VoiceOver
    if not Public(voice) or type(voice) ~= "table" then return end
    local overlay = voice.QuestOverlayUI
    if Public(overlay) and type(overlay) == "table"
        and Public(overlay.ShowsTrackerButton) and type(overlay.ShowsTrackerButton) == "function"
        and Public(overlay.BindPlayButton) and type(overlay.BindPlayButton) == "function" then return overlay end
end

local function SetState(button, state)
    local tile = Public(state) and ICON_TILES[state]
    if not tile then state, tile = "play", ICON_TILES.play end
    button.state = state
    -- Each control occupies one 16px column of the 64px texture.
    button.icon:SetTexCoord(tile / 4, (tile + 1) / 4, 0, 1)
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
    if overlay and GameTooltip and Public(overlay.ShowPlayTip) and type(overlay.ShowPlayTip) == "function"
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
    button:SetSize(BUTTON_SIZE, BUTTON_SIZE)
    button:SetFrameLevel(row:GetFrameLevel() + 2)
    button:EnableMouse(true)
    button:RegisterForClicks("LeftButtonUp")
    local icon = S.CreateTexture(button, nil, "ARTWORK")
    icon:SetTexture(CONTROLS)
    icon:SetSize(ICON_SIZE, ICON_SIZE)
    icon:SetPoint("CENTER", button, "CENTER", 0, 0)
    button.icon = icon
    button.SetState, button.setPlayState = SetState, SetPlayState
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
        -- Spoken can install default tooltip scripts while binding its click handler.
        button:SetScript("OnEnter", ShowTooltip)
        button:SetScript("OnLeave", HideTooltip)
        SetPlayState(button, false)
    end
    button:ClearAllPoints()
    button:SetPoint("RIGHT", row, "RIGHT", -inset, 0)
    button.icon:SetVertexColor(color[1], color[2], color[3])
    button:Show()
    return inset + BUTTON_SIZE + 2
end

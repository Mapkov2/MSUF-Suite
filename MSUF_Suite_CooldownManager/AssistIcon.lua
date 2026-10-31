local _, P = ...
local NS, S = P.NS, P.Suite
local C = P.CDM
-- The standalone recommendation shares the bar visibility choices and
-- frame-rectangle probes. Suggestions only repaint changed appearance;
-- target/combat transitions update its visibility separately.
local K = C.Const
local Effects = C.Effects
local recommendation
local watchingEssential = false
local ANCHOR_EVENT = "MSUFSuite.CooldownManager.AnchorChanged"
function Effects.RecommendationFrame() return recommendation end
function Effects.RecommendationGCD()
    local frame = recommendation
    if not frame or not frame:IsShown() then return end
    if not C.state.assistIconGCD then
        frame.cd:Clear()
        return
    end
    local duration = C_Spell.GetSpellCooldownDuration(K.GCD_SPELL)
    if duration then frame.cd:SetCooldownFromDurationObject(duration, true) else frame.cd:Clear() end
end

function Effects.RecommendationVisibility()
    local state = C.state
    if not state.assistIcon then return end
    local shown = true
    if state.assistIconVis == K.VIS.COMBAT then
        shown = state.inCombat == true
    elseif state.assistIconVis == K.VIS.COMBAT_OR_TARGET then
        shown = state.inCombat == true
        if not shown then
            local answer = SecureCmdOptionParse("[@target,exists] show; hide")
            shown = S.Public(answer) and answer == "show"
        end
    end
    if state.assistIconVisible ~= shown then
        state.assistIconVisible = shown
        Effects.Recommendation()
    end
end

local function NewRecommendation()
    local frame = S.CreateFrame("Frame", nil, UIParent)
    frame:EnableMouse(false)
    frame.tex = S.CreateTexture(frame, nil, "ARTWORK")
    frame.tex:SetAllPoints(frame)
    frame.cd = S.CreateFrame("Cooldown", nil, frame, "CooldownFrameTemplate")
    frame.cd:SetAllPoints(frame.tex)
    frame.cd:SetHideCountdownNumbers(true)
    frame.cd:SetDrawEdge(false)
    frame.cd:SetDrawBling(false)
    frame.over = S.CreateFrame("Frame", nil, frame)
    frame.over:SetAllPoints(frame)
    frame.over:SetFrameLevel(frame.cd:GetFrameLevel() + 1)
    frame.key = S.CreateFontString(frame.over, nil, "OVERLAY")
    frame.badge = S.CreateTexture(frame.over, nil, "BACKGROUND")
    frame.badge:SetPoint("TOPLEFT", frame.key, "TOPLEFT", -2, 2)
    frame.badge:SetPoint("BOTTOMRIGHT", frame.key, "BOTTOMRIGHT", 2, -2)
    frame.badge:SetColorTexture(0, 0, 0, .85)
    return frame
end

-- MSUF's player frame is sampled through Layout's existing safe rectangle
-- reader. The icon itself stays attached to UIParent, including in combat.
function Effects.RecommendationPlace(overrideX, overrideY)
    local frame = recommendation
    if not frame or not frame.layShown then return false end
    local state = C.state
    local x, y = overrideX or state.assistIconX or 0, overrideY or state.assistIconY or -180
    local parent = UIParent
    if state.assistIconAnchor == 2 then
        local bar = C.bars.ess
        if bar then parent = bar.frame end
    elseif state.assistIconAnchor == 3 then
        local left, bottom, right, top = C.Layout.FrameRect("player")
        if left then
            local cx, cy = UIParent:GetCenter()
            x, y = x + (left + right) / 2 - cx, y + (bottom + top) / 2 - cy
        end
    end
    if frame.layX ~= x or frame.layY ~= y or frame.layParent ~= parent or S.editMode then
        frame.layX, frame.layY, frame.layParent = x, y, parent
        frame:ClearAllPoints()
        frame:SetPoint("CENTER", parent, "CENTER", x, y)
    end
    return true
end

-- The Essential bar may not exist during the first settings read. Its
-- existing coalesced placement notification settles the attachment after
-- layout. No callback is registered while the assisted icon is off or free.
local function EssentialPlaced() Effects.RecommendationPlace() end
function Effects.RecommendationWatchAnchor()
    local state = C.state
    local wanted = C.M.active == true and state.assistIcon == true and state.assistIconAnchor == 2
    if watchingEssential == wanted then return end
    watchingEssential = wanted
    if wanted then
        EventRegistry:RegisterCallback(ANCHOR_EVENT, EssentialPlaced, Effects)
    else
        EventRegistry:UnregisterCallback(ANCHOR_EVENT, Effects)
    end
end

local function Look(frame, state)
    local border = state.assistIconBorder or 0
    local color = state.assistIconBorderColor or "000000"
    if frame.layBorder ~= border or frame.layBorderColor ~= color then
        frame.layBorder, frame.layBorderColor = border, color
        if border > 0 and not frame.border then
            frame.border = S.CreateTexture(frame, nil, "BACKGROUND")
            frame.border:SetAllPoints(frame)
        end
        if frame.border then
            frame.border:SetColorTexture(K.HexRGB(color))
            frame.border:SetShown(border > 0)
        end
        frame.tex:ClearAllPoints()
        frame.tex:SetPoint("TOPLEFT", frame, "TOPLEFT", border, -border)
        frame.tex:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -border, border)
    end
    local zoom = state.assistIconZoom or 8
    if frame.layZoom ~= zoom then
        frame.layZoom = zoom
        local crop = zoom / 100
        frame.tex:SetTexCoord(crop, 1 - crop, crop, 1 - crop)
    end
    local alpha = state.assistIconAlpha or 100
    if frame.layAlpha ~= alpha then
        frame.layAlpha = alpha
        frame:SetAlpha(alpha / 100)
    end
    local point = K.POINTS[state.assistIconKeyPos or 9]
    if frame.layKeyPoint ~= point then
        frame.layKeyPoint = point
        local pos = state.assistIconKeyPos or 9
        frame.key:ClearAllPoints()
        frame.key:SetPoint(point, frame, point, K.POINT_X[pos] * 3, K.POINT_Y[pos] * 3)
    end
end

function Effects.Recommendation()
    local state = C.state
    local spell = Effects.AssistSpell()
    local show = state.assistIcon == true and (spell ~= nil or state.preview == true)
        and (state.preview == true or state.assistIconVisible ~= false)
    local frame = recommendation
    if not frame and not show then return end
    if not frame then
        frame = NewRecommendation()
        recommendation = frame
    end
    local edge = frame.layShown ~= show
    if edge then
        frame.layShown = show
        frame:SetShown(show)
    end
    if not show then
        if edge then frame.cd:Clear() end
        return
    end
    local size = state.assistIconSize or 48
    if frame.laySize ~= size then
        frame.laySize = size
        frame:SetSize(size, size)
    end
    Effects.RecommendationPlace()
    Look(frame, state)
    local texture = spell and C_Spell.GetSpellTexture(spell) or K.QUESTION_ICON
    if frame.layTexture ~= texture then
        frame.layTexture = texture
        frame.tex:SetTexture(texture)
    end
    local own = state.assistIconKeySize or 0
    local fontSize = own > 0 and own or K.TextSize(nil, K.FONT.keybind, size)
    if frame.layFontSize ~= fontSize or frame.layText ~= state.textGen then
        frame.layFontSize, frame.layText = fontSize, state.textGen
        S.SetStyledFont(frame.key, state.font, fontSize, state.fontFlags,
            state.fontRendering, state.fontShadow, state.fontShadowOpacity, state.fontShadowDistance)
    end
    local key = state.assistIconKeybind and spell and C.Keybinds.Text(spell) or ""
    if frame.layKey ~= key then
        frame.layKey = key
        frame.key:SetText(key)
        frame.badge:SetShown(key ~= "")
    end
    if edge or frame.layGCD ~= state.assistIconGCD then
        frame.layGCD = state.assistIconGCD
        Effects.RecommendationGCD()
    end
end

function Effects.ReleaseRecommendation()
    if watchingEssential then
        watchingEssential = false
        EventRegistry:UnregisterCallback(ANCHOR_EVENT, Effects)
    end
    if recommendation then
        recommendation.layShown = false
        recommendation:Hide()
        recommendation.cd:Clear()
    end
end

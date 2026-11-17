local _, P = ...
local NS, S, AB = P.NS, P.Suite, P.ActionBars

function AB.ResolveMediaBorder(key)
    local media = NS.SharedMedia()
    local path = media and media:Fetch("border", key, true)
    return S.Public(path) and type(path) == "string" and path ~= "" and path or nil
end

-- Configuration/layout time only. The backdrop and its table belong to
-- the Suite; the action button carries no addon fields.
function AB.StyleMediaBorder(rec)
    local style, config = AB.style, AB.M.config
    local frame = rec.mediaBorderFrame
    if rec.masqued or not style.mediaBorder then
        if frame then frame:Hide() end
        return
    end
    if not frame then
        frame = S.CreateFrame("Frame", nil, rec.button, "BackdropTemplate")
        frame:EnableMouse(false)
        rec.mediaBorderFrame = frame
    end
    local level = rec.button:GetFrameLevel()
    if S.Finite(level) then frame:SetFrameLevel(level + 8) end
    local padding = config.mediaBorderPadding
    frame:ClearAllPoints()
    frame:SetPoint("TOPLEFT", rec.button, "TOPLEFT", -padding, padding)
    frame:SetPoint("BOTTOMRIGHT", rec.button, "BOTTOMRIGHT", padding, -padding)
    local backdrop = rec.mediaBackdrop or {}
    rec.mediaBackdrop = backdrop
    backdrop.edgeFile, backdrop.edgeSize = style.mediaBorder, config.mediaBorderSize
    frame:SetBackdrop(backdrop)
    frame:SetBackdropBorderColor(style.br, style.bg, style.bb, 1)
    frame:Show()
end

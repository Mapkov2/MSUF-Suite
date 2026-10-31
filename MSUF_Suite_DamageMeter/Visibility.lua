local _, P = ...
local D, S = P.DamageMeter, P.Suite
local M = D.M

-- This owned, eventless child follows UIParent's effective visibility.
-- Native OnShow/OnHide propagation keeps visibility queries off paint paths.
local function VisibilityChanged(frame)
    if not M.active then return end
    local hidden = not frame:IsVisible()
    if hidden == M.uiHidden then return end
    M.uiHidden = hidden
    for i = 1, M.config.windowCount do
        local win = D.windows[i]
        if win and win.shown then D.ApplyHover(win, true) end
    end
    D.SyncWatch()
    D.UpdateEvents()
    D.CancelPaint()
    D.UpdateTimer()
    D.SyncClock()
    if hidden then
        D.timerJob:Clear()
        D.lateJob:Clear()
        if D.threatJob then D.threatJob:Clear() end
    else
        D.SnapshotIdentities()
        D.PaintDirty()
        D.SyncClock()
    end
end

function D.TrackUIVisibility()
    local frame = M.visibilityProbe
    if not frame then
        frame = S.CreateFrame("Frame", nil, UIParent)
        frame:EnableMouse(false)
        M.visibilityProbe = frame
    end
    frame:SetScript("OnShow", VisibilityChanged)
    frame:SetScript("OnHide", VisibilityChanged)
    M.uiHidden = not frame:IsVisible()
end

function D.UntrackUIVisibility()
    local frame = M.visibilityProbe
    if not frame then return end
    frame:SetScript("OnShow", nil)
    frame:SetScript("OnHide", nil)
end

local _, P = ...
local NS, S = P.NS, P.Suite
local M = {}
local active
local art = setmetatable({}, { __mode = "k" })
local PATH = "Interface\\AddOns\\MSUF_Suite\\Media\\BlizzardFrames\\"

local function Paint(frame, bar, name, below)
    if not active then return end
    if not bar or NS.Safety.IsForbidden(frame) or frame:IsProtected() then return end
    local entry = art[frame]
    if not entry then
        entry = { border = S.CreateTexture(bar, nil, "OVERLAY"), name = S.CreateTexture(bar, nil, "BACKGROUND") }
        entry.border:SetTexture(PATH .. "CastFrame.tga")
        entry.border:SetAllPoints(frame)
        entry.name:SetTexture(PATH .. "CastName.tga")
        art[frame] = entry
    end
    entry.border:Show()
    if name and below and M.config.namePanel then
        entry.name:ClearAllPoints()
        entry.name:SetPoint("TOP", name, "TOP", 0, 2)
        entry.name:SetPoint("BOTTOM", name, "BOTTOM", 0, -2)
        entry.name:SetWidth(frame:GetWidth())
        entry.name:Show()
    else
        entry.name:Hide()
    end
end

function M:Enable()
    active = true
    NS.HostBridge.CastbarArtwork(Paint, true)
end

function M:Refresh()
    NS.HostBridge.CastbarArtwork(Paint)
end

function M:Disable()
    active = false
    for _, entry in pairs(art) do
        entry.border:Hide()
        entry.name:Hide()
    end
end

S.Install("castbarArt", M)

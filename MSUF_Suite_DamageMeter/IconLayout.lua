local _, P = ...
local D, S = P.DamageMeter, P.Suite
local M = D.M

local function Holder(row)
    local frame = S.CreateFrame("Frame", nil, row)
    frame:SetAllPoints(row)
    frame:EnableMouse(false)
    return frame
end

function D.CreateRowSurfaces(row)
    if row.kind ~= "list" then return end
    row.iconHost, row.nameHost, row.valueHost = Holder(row), Holder(row), Holder(row)
end

-- Shared 0..30 slots, on Suite-owned frames only. Blizzard's live/forever
-- DamageMeterEntry.xml likewise owns an Icon frame beside its StatusBar.
-- Preview levels use one constant bias; their ordering stays identical.
local function Level(row, frame, layer, automatic, detail)
    local level = S.OwnedElementLevel(layer, detail)
    if level and row.win.menuPreview then
        level = level - S.OwnedElementLevel(0, 0) + row:GetFrameLevel()
    end
    level = level or automatic
    if frame:GetFrameLevel() ~= level then frame:SetFrameLevel(level) end
end

function D.StyleRowSurfaces(row)
    if row.kind ~= "list" then return end
    local c = M.config
    Level(row, row.bar, c.barsLayer, row:GetFrameLevel() + 1, 0)
    Level(row, row.nameHost, c.nameLayer, row.bar:GetFrameLevel() + 4, 8)
    Level(row, row.valueHost, c.valueLayer, row.bar:GetFrameLevel() + 4, 8)
    Level(row, row.iconHost, c.iconLayer, row.bar:GetFrameLevel() + 2, 0)
end

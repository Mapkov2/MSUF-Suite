local _, P = ...
local NS, M = P.NS, P.BagsModule
local Motion = { geometry = {} }
P.BagWindowMotion = Motion
local floor, max, min = math.floor, math.max, math.min

function Motion.Cancel(snap)
    local active = Motion.active
    if Motion.driver then Motion.driver:SetScript("OnUpdate", nil) Motion.driver:Hide() end
    Motion.active = nil
    local view = P.InventoryView
    if snap and active and M.active and view.active and not NS.IsCombatLocked() and view.frame:IsShown() then
        view.frame:SetSize(Motion.width, Motion.height)
        P.InventoryRendering.Suite(true)
    end
end

local function Resize(width, height)
    local frame = P.InventoryView.frame
    if frame:GetWidth() ~= width or frame:GetHeight() ~= height then frame:SetSize(width, height) end
end

function Motion.Viewport(g)
    if not Motion.active then return g.columns, g.rows end
    local frame = P.InventoryView.frame
    local padding = g.panel and g.rail + 32 or g.sidebar + 12
    return max(1, min(g.columns, floor((frame:GetWidth() - padding) / 40))),
        max(1, min(g.rows, floor((frame:GetHeight() - g.top - g.bottom) / 40)))
end

local function Tick(_, elapsed)
    local view = P.InventoryView
    if NS.InCombat() or not M.active or not view.active or not view.frame:IsShown() then
        Motion.Cancel()
        return
    end
    Motion.elapsed = min(Motion.duration, Motion.elapsed + elapsed)
    local t = Motion.elapsed / Motion.duration
    local eased = 1 - (1 - t) * (1 - t) * (1 - t)
    Resize(floor(Motion.fromW + (Motion.width - Motion.fromW) * eased + .5),
        floor(Motion.fromH + (Motion.height - Motion.fromH) * eased + .5))
    local columns, rows = Motion.Viewport(view.geometry)
    local repaint = columns ~= Motion.columns or rows ~= Motion.rows
    Motion.columns, Motion.rows = columns, rows
    if Motion.elapsed == Motion.duration then
        Motion.Cancel()
        Resize(Motion.width, Motion.height)
        P.InventoryRendering.Suite(true)
        M:RefreshWindowLayout()
    elseif repaint then
        P.InventoryRendering.Suite(true)
    end
end

function Motion.Target(width, height)
    local view, frame = P.InventoryView, P.InventoryView.frame
    if Motion.active and Motion.width == width and Motion.height == height then return end
    local w, h = frame:GetWidth(), frame:GetHeight()
    if not Motion.active and w == width and h == height then return end
    local animate = view.layout == "suite" and P.BagMotion.Mode(M.config) ~= NS.BagsAnimation.OFF
        and not P.BagResize.active and not view.positionsDirty
    Motion.Cancel()
    if w == width and h == height then return end
    if not animate then
        Resize(width, height)
        M:RefreshWindowLayout()
        return
    end
    Motion.driver = Motion.driver or P.ChildFrame("Frame", UIParent)
    Motion.width, Motion.height, Motion.fromW, Motion.fromH = width, height, w, h
    Motion.elapsed, Motion.duration = 0, M.config.animationMode == NS.BagsAnimation.FULL and .16 or .12
    Motion.active = true
    Motion.columns, Motion.rows = Motion.Viewport(view.geometry)
    Motion.driver:SetScript("OnUpdate", Tick)
    Motion.driver:Show()
end

local _, P = ...
local NS, S = P.NS, P.Suite
local C = P.Chat

-- Keep each client's native anchor and its stretch width. Restoration is
-- conditional on ownership, so a fresh Blizzard layout becomes the new base.
local widths = setmetatable({}, { __mode = "k" })
function C.OffsetNative(self, region, x, y)
    if not self.preview and NS.InCombat() then
        S.Queue("chat")
        return
    end
    local context = self.context
    context:RestorePoints(region)
    if widths[region] then
        context:RestoreProperty(region, "SetWidth")
        widths[region] = nil
    end
    if x == 0 and y == 0 then return end
    local point, relative, relativePoint, bx, by = region:GetPoint(1)
    if not S.Public(point) or not S.Public(relative) or not S.Public(relativePoint)
        or not S.Finite(bx) or not S.Finite(by) then return end
    local stretched, width = region:GetNumPoints() > 1
    if stretched then
        width = region:GetWidth()
        if not S.Finite(width) then return end
    end
    context:Anchor(region, point, relative, relativePoint, bx + x, by + y)
    if stretched then
        context:Property(region, "GetWidth", "SetWidth", width)
        widths[region] = true
    end
end

function C.PositionTabs(self)
    local c = self.config
    if not self.preview and NS.InCombat() then
        S.Queue("chat")
        return
    end
    C.OffsetNative(self, _G.GENERAL_CHAT_DOCK, c.tabX or 0, c.tabY or 0)
    for frame, visual in pairs(self.visuals) do
        if not frame.isDocked and visual.tab then
            C.OffsetNative(self, visual.tab, c.tabX or 0, c.tabY or 0)
        end
    end
end

-- The native layout anchors its first visible line to the window; every
-- subsequent line follows that line. Preserve clipping and native hyperlinks.
local positioned = setmetatable({}, { __mode = "k" })
function C.PositionMessages(self, frame)
    local previous = positioned[frame]
    local x, y = self.config.messageTextX or 0, self.config.messageTextY or 0
    if not previous and x == 0 and y == 0 then return end
    if not self.preview and NS.InCombat() then
        S.Queue("chat")
        return
    end
    local line = frame.visibleLines and frame.visibleLines[1]
    if previous and previous ~= line then self.context:RestorePoints(previous) end
    if not line or x == 0 and y == 0 then
        if previous then self.context:RestorePoints(previous) end
        positioned[frame] = nil
        return
    end
    local point, relative, relativePoint, bx, by = line:GetPoint(1)
    if not S.Public(point) or not S.Public(relative) or not S.Public(relativePoint)
        or not S.Finite(bx) or not S.Finite(by) then return end
    if relative ~= frame or relativePoint ~= point or point ~= "TOPLEFT" and point ~= "BOTTOMLEFT" then return end
    if previous ~= line or bx ~= x or by ~= y then
        self.context:RestorePoints(line)
        self.context:Anchor(line, point, frame, point, x, y)
    end
    positioned[frame] = line
end

function C.ReleaseMessagePosition(self, frame)
    local line = positioned[frame]
    if line then self.context:RestorePoints(line) positioned[frame] = nil end
end

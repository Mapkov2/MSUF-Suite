local _, P = ...
local NS, S = P.NS, P.Suite
local C = P.Chat

-- Native Edit Mode can re-anchor the primary window after our refresh.
-- Coalesce a layout burst after it finishes; never fight a mover drag or
-- write Blizzard's saved layout/position-manager fields.
local watched = setmetatable({}, { __mode = "k" })
local pendingContext
local function CanHoldWindow()
    local m = C.M
    return m.active and m.context and m.config.lockWindowPosition and not S.editMode
        and not EditModeManagerFrame:IsShown()
end

local function WindowAtPosition(frame, x, y)
    local point, relative, relativePoint, px, py = frame:GetPoint(1)
    return S.Public(point) and S.Public(relative) and S.Public(relativePoint)
        and S.Finite(px) and S.Finite(py) and frame:GetNumPoints() == 1
        and point == "BOTTOMLEFT" and relative == UIParent and relativePoint == "BOTTOMLEFT"
        and px == x and py == y
end

local function RecoverWindowPosition()
    local context = pendingContext
    pendingContext = nil
    local m = C.M
    if not CanHoldWindow() or m.context ~= context then
        if m.nativePositionContext == context then m.nativePositionContext = nil end
        return
    end
    local frame = m.positionFrame
    if not frame or NS.Safety.IsForbidden(frame) then return end
    if NS.InCombat() then
        S.Queue("chat")
        return
    end
    if WindowAtPosition(frame, m.config.windowX or 12, m.config.windowY or 12) then
        m.nativePositionContext = nil
        return
    end
    C.ApplyWindowPosition(m, m.visuals[frame], frame, true)
end

local function WindowAnchorChanged(frame)
    local m = C.M
    if not CanHoldWindow() or frame ~= m.positionFrame or m.positionApplying then return end
    m.nativePositionContext = m.context
    if NS.InCombat() then
        S.Queue("chat")
        return
    end
    if pendingContext then return end
    pendingContext = m.context
    C_Timer.After(0, RecoverWindowPosition)
end

local function NativeEditClosed() WindowAnchorChanged(C.M.positionFrame) end

function C.ApplyWindowPosition(self, visual, frame, primary)
    if not primary then return end
    local c, context = self.config, self.context
    if c.lockWindowPosition then
        if not self.preview then
            self.positionFrame = frame
            if not watched[frame] then
                hooksecurefunc(frame, "SetPoint", WindowAnchorChanged)
                watched[frame] = true
            end
            -- Blizzard_EditMode creates this at startup on both supported clients.
            local manager = EditModeManagerFrame
            if not watched[manager] then
                manager:HookScript("OnHide", NativeEditClosed)
                watched[manager] = true
            end
        end
        if NS.InCombat() and not self.preview then
            S.Queue("chat")
            return
        end
        local x, y = c.windowX or 12, c.windowY or 12
        self.positionApplying = true
        if self.nativePositionContext == context and not S.editMode and not WindowAtPosition(frame, x, y) then
            context:RestorePoints(frame)
        end
        self.nativePositionContext = nil
        context:Anchor(frame, "BOTTOMLEFT", UIParent, "BOTTOMLEFT", x, y)
        self.positionApplying = nil
        visual.positionLocked = true
    elseif visual.positionLocked then
        self.positionApplying = true
        context:RestorePoints(frame)
        self.positionApplying = nil
        visual.positionLocked = nil
    end
end

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

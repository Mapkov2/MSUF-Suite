local _, P = ...
local NS, S = P.NS, P.Suite
local C = P.Chat
local M, Finite = C.M, P.Suite.Finite
-- Both supported clients currently expose ten persistent chat slots.
local CHAT_WINDOW_LIMIT = 10
local generations = {}
local watchingClosures

function C.MaxFloatingWindows()
    return math.min(Constants.ChatFrameConstants.MaxChatWindows, CHAT_WINDOW_LIMIT)
end

function C.FloatingMoverID(index)
    return "floating" .. index
end

local function Floating(index)
    local frame = _G["ChatFrame" .. index]
    if frame and not NS.Safety.IsForbidden(frame) and frame:IsShown()
        and not frame.isDocked and not frame.isTemporary and not frame.minimized then return frame end
end

local function FloatingTitle(index)
    local title = GetChatWindowInfo(index)
    if S.PublicText(title) and title ~= "" then return title end
    return S.Text("Chat window %d"):format(index)
end

-- The options preview reads geometry and titles only, even when Chat styling is off.
function S.ChatDetachedWindows(rows)
    local count = 0
    for index = 2, C.MaxFloatingWindows() do
        local frame = Floating(index)
        if frame then
            local width, height = frame:GetWidth(), frame:GetHeight()
            if Finite(width) and Finite(height) and width > 0 and height > 0 then
                count = count + 1
                local row = rows[count] or {}
                row.index, row.title, row.width, row.height = index, FloatingTitle(index), width, height
                rows[count] = row
            end
        end
    end
    return count
end

local function Deletable(index)
    local frame = _G["ChatFrame" .. index]
    if frame and not NS.Safety.IsForbidden(frame) and not frame.isTemporary
        and not FCF_IsChatWindowIndexReserved(index) and not IsBuiltinChatWindow(frame)
        and FCF_IsChatWindowIndexActive(index) then return frame end
end

-- The preview's availability check needs only the count. Snapshot names and
-- generations when the user opens the delete menu.
function S.ChatDeletableTabs(rows)
    if rows then C.WatchFloatingClosures() end
    local count = 0
    for index = 2, C.MaxFloatingWindows() do
        if Deletable(index) then
            count = count + 1
            if rows then
                local row = rows[count] or {}
                row.index, row.title, row.generation = index, FloatingTitle(index), generations[index] or 0
                rows[count] = row
            end
        end
    end
    if rows then
        for i = #rows, count + 1, -1 do rows[i] = nil end
    end
    return count
end

function S.ChatDeleteTabs(rows)
    if NS.InCombat() then return end
    local selected = FCF_GetCurrentChatFrameID()
    local closed, selectedClosed
    for _, row in ipairs(rows) do
        local index = row.index
        local frame = Deletable(index)
        if frame and row.generation == (generations[index] or 0) and row.title == FloatingTitle(index) then
            FCF_PopInWindow(frame)
            closed = true
            if selected == index then selectedClosed = true end
        end
    end
    if closed then C.RefreshTabFilters(selectedClosed) end
end

function S.ChatOpenDetachedMover(index)
    local id = C.FloatingMoverID(index)
    if not M.active or NS.InCombat() or not Floating(index) or not S.HasOwnedMover("chat", id) then return false end
    return S.OpenEditMode("chat", id, true)
end

local function Scale(frame)
    local scale, root = frame:GetEffectiveScale(), UIParent:GetEffectiveScale()
    if Finite(scale) and Finite(root) and scale > 0 and root > 0 then return scale / root end
end

local function Bounds(bounds, frame)
    local scale = Scale(frame)
    if not scale then
        bounds:Hide()
        return
    end
    local padding = M.config.padding
    bounds:SetScale(scale)
    bounds:ClearAllPoints()
    bounds:SetPoint("TOPLEFT", frame, "TOPLEFT", -padding, C.HeaderTop(M.config, frame))
    bounds:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", padding, -padding)
    bounds:Show()
end

function C.HideFloatingMovers(self)
    for _, bounds in pairs(self.floatingMovers or {}) do bounds:Hide() end
end

function C.UpdateFloatingMoverBounds(self)
    if not S.editMode then
        if self.floatingMovers then C.HideFloatingMovers(self) end
        return
    end
    self.floatingMovers = self.floatingMovers or {}
    local changed = false
    for index = 2, C.MaxFloatingWindows() do
        local frame, bounds = Floating(index), self.floatingMovers[index]
        if frame then
            if not bounds or not bounds:IsShown() then changed = true end
            if not bounds then
                bounds = S.CreateFrame("Frame", nil, UIParent)
                bounds:EnableMouse(false)
                bounds:SetAlpha(0)
                self.floatingMovers[index] = bounds
            end
            Bounds(bounds, frame)
        elseif bounds and bounds:IsShown() then
            bounds:Hide()
            changed = true
        end
    end
    return changed
end

local function Capture(index)
    local frame = Floating(index)
    local scale = frame and Scale(frame)
    if not scale then return end
    local x, y = frame:GetLeft(), frame:GetBottom()
    local rootX, rootY = UIParent:GetLeft(), UIParent:GetBottom()
    if not (Finite(x) and Finite(y) and Finite(rootX) and Finite(rootY)) then return end
    return { x = x * scale - rootX, y = y * scale - rootY, generation = generations[index] or 0 }
end

-- The drag preview moves Suite's own bounds. Blizzard receives one position
-- and one save at commit or history replay, outside combat.
local function Place(index, state, x, y, preview)
    if not M.active or NS.InCombat() or not state or state.generation ~= (generations[index] or 0)
        or not (Finite(x) and Finite(y)) then return false end
    local frame = Floating(index)
    local scale = frame and Scale(frame)
    if not scale then return false end
    local bounds = M.floatingMovers and M.floatingMovers[index]
    if preview then
        if not bounds or not bounds:IsShown() then return false end
        local width, height = bounds:GetWidth(), bounds:GetHeight()
        if not (Finite(width) and Finite(height) and width > 0 and height > 0) then return false end
        local padding = M.config.padding
        bounds:ClearAllPoints()
        bounds:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", x / scale - padding, y / scale - padding)
        bounds:SetSize(width, height)
        return true
    end
    local current = Capture(index)
    if not current then return false end
    if math.abs(x - current.x) > .01 or math.abs(y - current.y) > .01 then
        if not (Finite(frame:GetWidth()) and Finite(frame:GetHeight())) then return false end
        frame:ClearAllPoints()
        frame:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", x / scale, y / scale)
        FCF_SavePositionAndDimensions(frame)
    end
    if bounds and S.editMode then Bounds(bounds, frame) end
    return true
end

function C.FloatingMoverSpec(index)
    local sessionGeneration, lateOrigin
    local function Read() return Capture(index) end
    local function Restore(state)
        return state and Place(index, state, state.x, state.y, false) or false
    end
    local function Commit(state, x, y)
        if S.editMode and state.generation ~= sessionGeneration
            and (not lateOrigin or lateOrigin.generation ~= state.generation) then
            local origin = Read()
            if not Place(index, state, x, y, false) then return false end
            lateOrigin = origin
            return true
        end
        return Place(index, state, x, y, false)
    end
    local controls = {}
    for _, axis in ipairs({ "x", "y" }) do
        controls[#controls + 1] = { id = axis, label = axis:upper(), kind = "number",
            min = -5000, max = 5000, step = 1, get = function()
                local state = Read()
                return state and state[axis] or 0
            end, set = function(value)
                local state = Read()
                if not state then return false end
                local x, y = state.x, state.y
                if axis == "x" then x = value else y = value end
                return Commit(state, x, y)
            end }
    end
    return {
        label = S.Text("Chat window %d"):format(index), order = 870 + index,
        getFrame = function()
            local frame = Floating(index)
            local bounds = M.floatingMovers and M.floatingMovers[index]
            if frame then return bounds and bounds:IsShown() and bounds or frame end
        end,
        extraControls = controls,
        nativePosition = {
            capture = Read, restore = Restore,
            -- An undock during Edit Mode can appear after the host snapshot.
            onSessionChanged = function(active, reason)
                if active then
                    local state = Read()
                    sessionGeneration = state and state.generation
                elseif reason == "discard" and lateOrigin then
                    Restore(lateOrigin)
                end
                lateOrigin = nil
            end,
            move = function(request)
                local state = request and request.state
                if not state or not (Finite(state.x) and Finite(state.y)
                    and Finite(request.deltaX) and Finite(request.deltaY)) then return false end
                local x, y = state.x + request.deltaX, state.y + request.deltaY
                if request.phase == "preview" then return Place(index, state, x, y, true) end
                return Commit(state, x, y)
            end,
        },
    }
end

function C.FloatingWindowClosed(frame, fallback)
    frame = fallback or frame or FCF_GetCurrentChatFrame()
    if frame and not NS.Safety.IsForbidden(frame) then
        local index = frame:GetID()
        if Finite(index) then generations[index] = (generations[index] or 0) + 1 end
    end
    if M.active and S.editMode and not NS.InCombat() then
        C.UpdateFloatingMoverBounds(M)
        S.RefreshOwnedMovers("chat")
    end
end

function C.WatchFloatingClosures()
    if watchingClosures then return end
    hooksecurefunc("FCF_Close", C.FloatingWindowClosed)
    watchingClosures = true
end

function C.FloatingDragStopped(frame)
    if not M.active then return end
    if NS.InCombat() then
        S.Queue("chat")
        return
    end
    if frame and not NS.Safety.IsForbidden(frame) and not frame.isDocked then C.ApplyWindow(M, frame, true) end
    if S.editMode then
        C.UpdateFloatingMoverBounds(M)
        S.RefreshOwnedMovers("chat")
    end
end

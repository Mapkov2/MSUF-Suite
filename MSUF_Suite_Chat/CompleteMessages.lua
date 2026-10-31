local _, P = ...
local NS, S = P.NS, P.Suite
local C = P.Chat
local watched = setmetatable({}, { __mode = "k" })
-- upstream/ptr and Forever ScrollingMessageFrame: RefreshDisplay invokes
-- this public callback after native fonts, text, alpha and wrapping settle.
-- Native layout deliberately allocates one extra, partially clipped message.
function C.PaintMessageLines(self, frame)
    C.PositionMessages(self, frame)
    if not self.config.completeMessages then return end
    local top, bottom = frame:GetTop(), frame:GetBottom()
    if not (S.Finite(top) and S.Finite(bottom)) then return end
    for _, line in ipairs(frame.visibleLines) do
        local lineTop, lineBottom = line:GetTop(), line:GetBottom()
        if S.Finite(lineTop) and S.Finite(lineBottom)
            and (lineTop > top + .5 or lineBottom < bottom - .5) then
            local r, g, b = line:GetTextColor()
            line:SetTextColor(r, g, b, 0)
        end
    end
end

local function Refreshed(frame)
    if C.M.active then C.PaintMessageLines(C.M, frame) end
end

function C.ApplyCompleteMessages(self, frame)
    local c = self.config
    if not watched[frame] and (c.completeMessages or (c.messageTextX or 0) ~= 0 or (c.messageTextY or 0) ~= 0) then
        watched[frame] = true
        frame:AddOnDisplayRefreshedCallback(Refreshed)
    end
    if watched[frame] then frame:MarkDisplayDirty() end
end

function C.ReleaseCompleteMessages(frame)
    C.ReleaseMessagePosition(C.M, frame)
    if watched[frame] then frame:MarkDisplayDirty() end
end

local _, P = ...
local NS, S = P.NS, P.Suite
local C = P.Chat
local M = C.M

-- Only this owned proxy moves/sizes. Native movable/locked/layout fields and
-- scripts stay with Blizzard. There is no idle or gesture OnUpdate script.
local function ResizeProxy(proxy)
    local gesture = M.toolbarGesture
    if not gesture or not gesture.resize or NS.IsCombatLocked() then return end
    local width, height = proxy:GetWidth(), proxy:GetHeight()
    if not S.Finite(width) or not S.Finite(height) then return end
    M.context:Property(ChatFrame1, "GetWidth", "SetWidth", width)
    M.context:Property(ChatFrame1, "GetHeight", "SetHeight", height)
end

function C.StopToolbarGesture(save)
    local gesture = M.toolbarGesture
    if not gesture then return end
    local proxy, context = M.toolbarProxy, gesture.context
    proxy:StopMovingOrSizing()
    proxy:UnregisterEvent("PLAYER_REGEN_DISABLED")
    if NS.IsCombatLocked() then
        S.Queue("chat")
        return
    end
    local values = {}
    C.CaptureWindowPosition(values, ChatFrame1)
    values.windowWidth, values.windowHeight = proxy:GetWidth(), proxy:GetHeight()
    values.lockWindowPosition, values.lockWindowSize = true, true
    local commit = save and M.active and M.context == context and M.config == gesture.config
        and S.Finite(values.windowX) and S.Finite(values.windowY)
        and S.Finite(values.windowWidth) and S.Finite(values.windowHeight)
    if commit then
        context:Anchor(ChatFrame1, "BOTTOMLEFT", UIParent, "BOTTOMLEFT", values.windowX, values.windowY)
        context:Property(ChatFrame1, "GetWidth", "SetWidth", values.windowWidth)
        context:Property(ChatFrame1, "GetHeight", "SetHeight", values.windowHeight)
    else
        context:RestorePoints(ChatFrame1)
        context:RestoreProperty(ChatFrame1, "SetWidth")
        context:RestoreProperty(ChatFrame1, "SetHeight")
    end
    M.toolbarGesture = nil
    proxy:Hide()
    if commit and not S.CommitEditPosition("chat", values) then S.Queue("chat") end
end

local function Released() C.StopToolbarGesture(true) end
local function CombatStarted() C.StopToolbarGesture(true) end

local function Proxy()
    if M.toolbarProxy then return M.toolbarProxy end
    local proxy = S.CreateFrame("Frame", nil, UIParent)
    proxy:SetMovable(true)
    proxy:SetResizable(true)
    proxy:SetResizeBounds(200, 80, 1200, 800)
    proxy:SetClampedToScreen(true)
    proxy:SetScript("OnSizeChanged", ResizeProxy)
    proxy:SetScript("OnEvent", CombatStarted)
    proxy:Hide()
    M.toolbarProxy = proxy
    return proxy
end

local function Begin(button)
    local frame = ChatFrame1
    if not M.active or M.config.toolbarLocked or NS.InCombat() or S.editMode
        or EditModeManagerFrame:IsShown() or NS.Safety.IsForbidden(frame) or frame:IsProtected() then return end
    local values = {}
    C.CaptureWindowPosition(values, frame)
    if not S.Finite(values.windowX) or not S.Finite(values.windowY) then return end
    local proxy = Proxy()
    proxy:SetScale(frame:GetEffectiveScale() / UIParent:GetEffectiveScale())
    proxy:ClearAllPoints()
    proxy:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", values.windowX, values.windowY)
    proxy:SetSize(frame:GetWidth(), frame:GetHeight())
    proxy:Show()
    M.toolbarGesture = { context = M.context, config = M.config, resize = button.resize == true }
    M.context:Anchor(frame, "BOTTOMLEFT", proxy, "BOTTOMLEFT", 0, 0)
    proxy:RegisterEvent("PLAYER_REGEN_DISABLED")
    if button.resize then proxy:StartSizing("BOTTOMRIGHT") else proxy:StartMoving() end
end

function C.PaintChatResizeGrip(button)
    if button.grip then return end
    local label = S.CreateFontString(button, nil, "OVERLAY", "GameFontNormalSmall")
    label:SetPoint("CENTER", button, "CENTER")
    label:SetText("/")
    button.grip = label
end

local function ControlEnter(button) C.ToolbarHover(button, true) end
local function ControlLeave(button) C.ToolbarHover(button, false) end

local function Control(resize)
    local button = S.CreateFrame("Button", nil, GENERAL_CHAT_DOCK)
    button.resize = resize
    button:RegisterForDrag("LeftButton")
    button:SetScript("OnDragStart", Begin)
    button:SetScript("OnDragStop", Released)
    button:SetScript("OnMouseUp", Released)
    button:SetScript("OnEnter", ControlEnter)
    button:SetScript("OnLeave", ControlLeave)
    if resize then C.PaintChatResizeGrip(button) end
    return button
end

function C.ApplyToolbarGeometry()
    if M.toolbarGesture then C.StopToolbarGesture(false) end
    local unlocked = M.config.headerToolbar and not M.config.toolbarLocked
    if not unlocked then
        if M.toolbarDrag then M.toolbarDrag:Hide() end
        if M.toolbarResize then M.toolbarResize:Hide() end
        return
    end
    local drag, resize = M.toolbarDrag or Control(false), M.toolbarResize or Control(true)
    M.toolbarDrag, M.toolbarResize = drag, resize
    drag:ClearAllPoints()
    drag:SetPoint("BOTTOMLEFT", ChatFrame1, "TOPLEFT", 0, M.config.tabY or 0)
    drag:SetPoint("TOPRIGHT", M.toolbar, "TOPLEFT", 0, 0)
    -- Native tabs sit above the empty drag surface and retain their clicks.
    drag:SetFrameLevel(GENERAL_CHAT_DOCK:GetFrameLevel())
    resize:ClearAllPoints()
    resize:SetPoint("BOTTOMRIGHT", ChatFrame1, "BOTTOMRIGHT", M.config.padding, -M.config.padding)
    resize:SetSize(16, 16)
    resize:SetFrameLevel(M.toolbar:GetFrameLevel())
    drag:Show()
    resize:Show()
end

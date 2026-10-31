local _, P = ...
local NS, S, M = P.NS, P.Suite, P.BagsModule
if NS.Client.isForever then return end
-- The bank window's size and place (the bankWindow* settings). BankFrame is a
-- left panel of Blizzard's panel manager (UIPanelWindows): every pass of
-- UpdateUIPanelPositions anchors it at the top left of the screen, in its own
-- scale. The scale is therefore set before a pass reads it, and the player's
-- position is applied after each pass (hooksecurefunc below), never in place
-- of it. The panel's background is BankInventory.lua's.
local floor = math.floor
local Finite = S.Finite
local POINT = "TOPLEFT"
local BankWindow = { applied = {} }
P.BankWindow = BankWindow

local function Place()
    local c = M.config
    if c.bankWindowMoved then M.context:Position(BankFrame, POINT, c.bankWindowX, c.bankWindowY) end
end

-- The pass puts the bank where it belongs; a pass for another panel leaves a
-- closed bank alone.
local function AfterPanelPass(frame)
    if M.active and (frame == BankFrame or BankFrame:IsShown()) then Place() end
end

-- Blizzard's own pass, to anchor the bank again in the scale just set (or at
-- its normal place); AfterPanelPass applies the player's position after it.
local function PanelPass()
    if BankFrame:IsShown() and not NS.IsCombatLocked() then UpdateUIPanelPositions(BankFrame) end
end

-- Edit Mode lists the bank while it is open.
local function MoverStateChanged()
    if M.active then S.RefreshOwnedMovers("bags") end
end

local function InstallHooks()
    if BankWindow.hooked then return end
    hooksecurefunc("UpdateUIPanelPositions", AfterPanelPass)
    BankFrame:HookScript("OnShow", MoverStateChanged)
    BankFrame:HookScript("OnHide", MoverStateChanged)
    BankWindow.hooked = true
end

-- Applies the settings when one of them changed.
function BankWindow.Refresh()
    InstallHooks()
    local c, last = M.config, BankWindow.applied
    if last.scale == c.bankWindowScale and last.moved == c.bankWindowMoved
        and last.x == c.bankWindowX and last.y == c.bankWindowY then
        return
    end
    last.scale, last.moved, last.x, last.y = c.bankWindowScale, c.bankWindowMoved, c.bankWindowX, c.bankWindowY
    M.context:Scale(BankFrame, c.bankWindowScale)
    PanelPass()
end

-- The module hands the scale back before Blizzard anchors the bank again.
function BankWindow.Disable()
    local last = BankWindow.applied
    last.scale, last.moved, last.x, last.y = nil, nil, nil, nil
    M.context:RestoreProperty(BankFrame, "SetScale")
    PanelPass()
end

-- The bank's top left corner against the screen's, in its own scale: the
-- offsets Place and Edit Mode's drag use.
local function Offset(frame)
    local left, bottom, _, height = frame:GetScaledRect()
    local parentLeft, parentBottom, _, parentHeight = UIParent:GetScaledRect()
    local scale = frame:GetEffectiveScale()
    if not (Finite(left) and Finite(bottom) and Finite(height) and Finite(parentLeft)
        and Finite(parentBottom) and Finite(parentHeight) and Finite(scale)) or scale <= 0 then
        return nil
    end
    return (left - parentLeft) / scale, (bottom + height - parentBottom - parentHeight) / scale
end

-- A drag of the bank that never moved starts where the panel manager put it.
local function Capture(values)
    if M.config.bankWindowMoved then return end
    local x, y = Offset(BankFrame)
    if x then values.bankWindowX, values.bankWindowY = x, y end
end

-- The Edit Mode element (registered by BagWindow.lua's RegisterMovers).
BankWindow.mover = {
    label = "Bank window", order = 877,
    getFrame = function() return BankFrame end,
    isEnabled = function() return BankFrame:IsShown() end,
    xKey = "bankWindowX", yKey = "bankWindowY", point = POINT,
    capture = Capture,
    moveValues = { bankWindowMoved = true }, resetKeys = { "bankWindowMoved" },
    historyKeys = { "bankWindowMoved", "bankWindowScale" },
    extraControls = {
        {
            id = "size", label = "Size %", kind = "number", min = 65, max = 150, step = 1,
            get = function() return floor(S.Config("bags").bankWindowScale * 100 + 0.5) end,
            set = function(value) return S.Set("bags", "bankWindowScale", value / 100) end,
        },
    },
}

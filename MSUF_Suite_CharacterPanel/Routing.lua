local _, NS = ...
local Routing = {}
NS.Routing = Routing

local root, paperDoll, onVisibility, onSize

function Routing.Root() return root end

function Routing.Shown()
    if root and root:IsVisible() and paperDoll:IsVisible() then return root end
end

local function Shown()
    if onVisibility then onVisibility(Routing.Shown()) end
end

local function Hidden()
    if onVisibility then onVisibility(nil) end
end

local function Resized()
    if onSize and Routing.Shown() then onSize() end
end

-- The actual Character binding and native show/close lifecycle own the window.
-- Observe it from our side without replacing any of its scripts or bindings.
function Routing.Sync(visibility, size)
    onVisibility, onSize = visibility, size
    if not visibility then return end
    if not root then
        if not CharacterFrame or not PaperDollFrame then return end
        root, paperDoll = CharacterFrame, PaperDollFrame
        root:HookScript("OnShow", Shown)
        root:HookScript("OnHide", Hidden)
        root:HookScript("OnSizeChanged", Resized)
        hooksecurefunc(root, "SetPoint", Resized)
        hooksecurefunc(root, "SetScale", Resized)
        hooksecurefunc(root, "StopMovingOrSizing", Resized)
        paperDoll:HookScript("OnShow", Shown)
        paperDoll:HookScript("OnHide", Hidden)
    end
    Shown()
end

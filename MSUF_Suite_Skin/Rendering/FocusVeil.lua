local _, NS = ...

-- The root window is dimmed by our own non-interactive frame. Modern menu
-- compositor proxies are only used as a layer reference, never as a parent.
-- Native dropdown close callbacks retain ownership of every menu operation.
local FocusVeil = { roots = setmetatable({}, { __mode = "k" }) }
NS.FocusVeil = FocusVeil
local WindowMenuOpened, WindowMenuClosed = function() end, function() end
function FocusVeil.SetWindowFocusProvider(opened, closed) WindowMenuOpened, WindowMenuClosed = opened, closed end
local Safety, Motion = NS.Safety, NS.Motion
local combat = NS.IsCombatLocked()
local strata = { BACKGROUND = 1, LOW = 2, MEDIUM = 3, HIGH = 4, DIALOG = 5,
    FULLSCREEN = 6, FULLSCREEN_DIALOG = 7, TOOLTIP = 8 }

local function Allowed()
    local db = NS.DB
    return db and db.enabled and db.theme.dropdownDimming ~= false
end

local function Writable()
    return not Safety.IsForbidden(FocusVeil.overlay)
        and (not Safety.GetProtection(FocusVeil.overlay) or not combat and not NS.IsCombatLocked())
end

function FocusVeil.Clear()
    FocusVeil.lease, FocusVeil.menu, FocusVeil.root = nil, nil, nil
    FocusVeil.closingLease = nil
    FocusVeil.hiding = false
    if FocusVeil.group then FocusVeil.group:Stop() end
    if FocusVeil.overlay then
        if not Writable() then FocusVeil.pending = true return end
        FocusVeil.pending = nil
        FocusVeil.overlay:Hide()
        FocusVeil.overlay:SetAlpha(0)
        FocusVeil.overlay:ClearAllPoints()
    end
end

local function Finished()
    if FocusVeil.hiding and not FocusVeil.lease then FocusVeil.Clear() end
end

local function EnsureOverlay()
    if FocusVeil.overlay then return FocusVeil.overlay end
    local overlay = Safety.CreateChildFrame("Frame", UIParent)
    overlay:EnableMouse(false)
    overlay:Hide()
    overlay:SetAlpha(0)
    local fill = overlay:CreateTexture(nil, "BACKGROUND")
    fill:SetAllPoints(overlay)
    fill:SetColorTexture(0, 0, 0, 0.42)
    local group = overlay:CreateAnimationGroup()
    local alpha = group:CreateAnimation("Alpha")
    alpha:SetDuration(0.12)
    alpha:SetSmoothing("IN_OUT")
    group:SetToFinalAlpha(true)
    group:SetScript("OnFinished", Finished)
    FocusVeil.overlay, FocusVeil.group, FocusVeil.alpha = overlay, group, alpha
    return overlay
end

local function Fade(to)
    if not Writable() then FocusVeil.Clear() return end
    local overlay = FocusVeil.overlay
    local from = Safety.Read(overlay, "GetAlpha") or 0
    if Safety.Read(FocusVeil.group, "IsPlaying") then
        local progress = Safety.Read(FocusVeil.alpha, "GetSmoothProgress")
        if type(progress) == "number" then
            from = FocusVeil.from + (FocusVeil.to - FocusVeil.from) * progress
        end
    end
    FocusVeil.group:Stop()
    if not Motion.Enabled() then
        overlay:SetAlpha(to)
        if to == 0 then FocusVeil.Clear() end
        return
    end
    FocusVeil.alpha:SetFromAlpha(from)
    FocusVeil.alpha:SetToAlpha(to)
    FocusVeil.from, FocusVeil.to = from, to
    overlay:SetAlpha(from)
    FocusVeil.group:Play()
end

local function RootHidden(root)
    if FocusVeil.root == root then FocusVeil.Clear() end
end

local function FindRoot(dropdown)
    local current, candidate = dropdown, nil
    for _ = 1, 16 do
        current = Safety.Read(current, "GetParent")
        if not current or current == UIParent or Safety.IsForbidden(current) then break end
        local surface = NS.Registry.GetSurface(current)
        if surface and surface.visible ~= false then
            local role = surface.spec.role
            if role == "shell" or role == "popup" then return current end
            if role == "panel" then candidate = current end
        end
    end
    return candidate
end

function FocusVeil.Open(lease, dropdown, menu)
    WindowMenuOpened(lease, dropdown, menu)
    if not Allowed() or not menu or Safety.IsForbidden(menu) then
        FocusVeil.Clear()
        return
    end
    local root = FindRoot(dropdown)
    if not root or not Safety.CanDecorate(root) or Safety.Read(root, "IsVisible") ~= true then
        FocusVeil.Clear()
        return
    end
    local layer, level = Safety.Read(menu, "GetFrameStrata"), Safety.Read(menu, "GetFrameLevel")
    if not strata[layer] or type(level) ~= "number" or level <= 0 then
        FocusVeil.Clear()
        return
    end
    local overlay = EnsureOverlay()
    if not Writable() then FocusVeil.Clear() return end
    FocusVeil.pending = nil
    FocusVeil.lease, FocusVeil.menu, FocusVeil.root = lease, menu, root
    FocusVeil.closingLease = nil
    FocusVeil.hiding = false
    overlay:ClearAllPoints()
    overlay:SetPoint("TOPLEFT", root, "TOPLEFT", 0, 0)
    overlay:SetPoint("BOTTOMRIGHT", root, "BOTTOMRIGHT", 0, 0)
    overlay:SetFrameStrata(layer)
    overlay:SetFrameLevel(level - 1)
    if not FocusVeil.roots[root] then
        FocusVeil.roots[root] = true
        root:HookScript("OnHide", RootHidden)
    end
    overlay:Show()
    Fade(1)
end

function FocusVeil.Close(lease, menu)
    WindowMenuClosed(lease, menu)
    if FocusVeil.lease ~= lease or menu and FocusVeil.menu ~= menu then return end
    FocusVeil.closingLease = lease
    FocusVeil.lease, FocusVeil.menu = nil, nil
    FocusVeil.hiding = true
    Fade(0)
end

function FocusVeil.Release(lease)
    if FocusVeil.lease == lease or FocusVeil.closingLease == lease then FocusVeil.Clear() end
end

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
eventFrame:SetScript("OnEvent", function(_, event)
    combat = event == "PLAYER_REGEN_DISABLED"
    if FocusVeil.pending or FocusVeil.root and not Safety.CanDecorate(FocusVeil.root) then FocusVeil.Clear() end
end)
local function SettingsChanged(_, domain)
    if not FocusVeil.root then return end
    local surface = NS.Registry.GetSurface(FocusVeil.root)
    if not Allowed() or domain == "profile" or not surface or surface.visible == false
        or Safety.Read(FocusVeil.root, "IsVisible") ~= true then
        FocusVeil.Clear()
    elseif domain == "motion" then
        Fade(FocusVeil.hiding and 0 or 1)
    end
end
NS.Registry.AddListener(FocusVeil, SettingsChanged)
NS.Checkmarks.SetMenuFocusProvider(FocusVeil.Open, FocusVeil.Close, FocusVeil.Release)

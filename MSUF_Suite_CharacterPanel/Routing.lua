local _, NS = ...
local Routing = {}
NS.Routing = Routing

local root, paperDoll, onVisibility, onSize
local gearClick, gearOwner, clickRequest, requestedGear, requestedShortcut
local shortcutTabs = { gear = true, reputation = true, currency = true }
local gearTabs = { overview = true, gear = true }
local tabs = { PaperDollFrame = "overview", ReputationFrame = "reputation", TokenFrame = "currency" }
if NS.Host.Client.isForever then
    tabs.SkillsFrame, tabs.PVPRankFrame, tabs.StatisticsFrame = "skills", "pvp", "statistics"
end

function Routing.Root() return root end

function Routing.PaperDollShown()
    return paperDoll and paperDoll:IsVisible()
end

function Routing.Shown()
    if not root or not root:IsVisible() then return end
    local name = NS.String(root.activeSubframe)
    if not name and Routing.PaperDollShown() then return root, tabs.PaperDollFrame end
    local tab = name and tabs[name]
    local pane = tab and _G[name]
    if pane and pane:IsVisible() then return root, tab end
end

function Routing.TakeTabRequest()
    local shown, tab = Routing.Shown()
    local requested = requestedShortcut or (tab == "overview" and requestedGear or nil)
    requestedGear, requestedShortcut = nil, nil
    return shown, tab, requested
end

-- Start at the native owner, then take the Suite tab through the existing visibility job.
-- A gear shortcut from a different Blizzard pane uses the read-only Equipment report.
function NS.Suite.OpenCharacterPanelTab(tab)
    if not NS.Public(tab) or not shortcutTabs[tab] or not onVisibility or not NS.CanReplace() then return false end
    if not NS.Suite.ShowPanel("character") then return false end
    local visible = Routing.Shown()
    if not visible then return false end
    requestedShortcut = tab
    onVisibility(visible)
    return true
end

function Routing.ReleaseGearClick()
    if clickRequest or not gearOwner then return end
    gearOwner = nil
    if not NS.Host.InCombat() then gearClick:Hide() end
end

local function BeginGearClick()
    clickRequest = gearOwner and gearOwner.id
end

local function EndGearClick()
    local tab = clickRequest
    clickRequest = nil
    Routing.ReleaseGearClick()
    if tab and onVisibility and Routing.PaperDollShown() then
        requestedGear = tab
        onVisibility(root)
    end
end

local function GearClick()
    if gearClick then return gearClick end
    -- Match the Suite's secure DataText click path. Use a detached hit area
    -- so neither the Suite tab strip nor Blizzard's window gains protection.
    local button = NS.Suite.CreateFrame("Button", nil, UIParent, "SecureActionButtonTemplate")
    button:Hide()
    button:RegisterForClicks("LeftButtonUp")
    button:SetAttribute("useOnKeyDown", false)
    button:SetAttribute("type1", "click")
    button:SetScript("PreClick", BeginGearClick)
    button:SetScript("PostClick", EndGearClick)
    button:SetScript("OnLeave", Routing.ReleaseGearClick)
    RegisterStateDriver(button, "visibility", "[combat] hide")
    gearClick = button
    return button
end

function Routing.HoverGearTab(tab)
    local view = tab.view
    if not onVisibility or not view.nativeLayout or not gearTabs[tab.id]
        or NS.Host.InCombat() or Routing.PaperDollShown() or not view.frame:IsVisible() then return end
    if gearOwner == tab and gearClick:IsShown() then return end
    local target = CharacterMicroButton
    if not NS.Public(target) or not target or target:IsForbidden() then return end
    local enabled = target:IsEnabled()
    if not NS.Public(enabled) or enabled ~= true then return end
    local left, bottom, width, height = tab:GetRect()
    local scale, parentScale = NS.Number(tab:GetEffectiveScale()), NS.Number(UIParent:GetEffectiveScale())
    left, bottom, width, height = NS.Number(left), NS.Number(bottom), NS.Number(width), NS.Number(height)
    if not left or not bottom or not width or not height or width <= 0 or height <= 0
        or not scale or scale <= 0 or not parentScale or parentScale <= 0 then return end
    scale = scale / parentScale
    local button = GearClick()
    gearOwner = tab
    button:SetAttribute("clickbutton1", target)
    button:SetFrameStrata(tab:GetFrameStrata())
    button:SetFrameLevel(tab:GetFrameLevel() + 1)
    button:ClearAllPoints()
    button:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", left * scale, bottom * scale)
    button:SetSize(width * scale, height * scale)
    button:Show()
end

local function Shown()
    if onVisibility then onVisibility(Routing.Shown()) end
end

local function Hidden()
    Routing.ReleaseGearClick()
    requestedGear, requestedShortcut = nil, nil
    if onVisibility then onVisibility(nil) end
end

local function Switched()
    -- Retail stores activeSubframe after showing the child; observe the
    -- complete switch, not the outgoing paper doll's intermediate OnHide.
    if not onVisibility or not root:IsVisible() then return end
    requestedShortcut = nil
    Routing.ReleaseGearClick()
    Shown()
end

local function ExplicitOpen(name, onlyShow)
    if not onVisibility or not NS.Public(onlyShow) or onlyShow ~= true then return end
    local shown, tab = Routing.Shown()
    if shown and tabs[NS.String(name)] == tab then onVisibility(shown, tab) end
end

local function Resized()
    Routing.ReleaseGearClick()
    if onSize and Routing.Shown() then onSize() end
end

-- The actual Character binding and native show/close lifecycle own the window.
-- Observe it from our side without replacing any of its scripts or bindings.
function Routing.Sync(visibility, size)
    onVisibility, onSize = visibility, size
    if not visibility then
        requestedShortcut = nil
        return Routing.ReleaseGearClick()
    end
    if not root then
        if not CharacterFrame or not PaperDollFrame then return end
        root, paperDoll = CharacterFrame, PaperDollFrame
        root:HookScript("OnShow", Shown)
        root:HookScript("OnHide", Hidden)
        root:HookScript("OnSizeChanged", Resized)
        hooksecurefunc(root, "SetPoint", Resized)
        hooksecurefunc(root, "SetScale", Resized)
        hooksecurefunc(root, "StopMovingOrSizing", Resized)
        hooksecurefunc(root, "ShowSubFrame", Switched)
        -- A link may explicitly open a pane Blizzard already shows.
        hooksecurefunc("ToggleCharacter", ExplicitOpen)
    end
    Shown()
end

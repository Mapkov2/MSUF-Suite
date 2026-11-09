local _, P = ...
local NS, S, Actions = P.NS, P.Suite, P.DataTextActions
local VISIBILITY = NS.DataTextVisibility
local CombatMenu, launchers = {}, {}
P.DataTextCombatMenu = CombatMenu
Actions.combatMicroLaunchers = launchers

-- The launcher and popup are detached from the bars. Anchoring a protected
-- frame to a bar would protect its layout and health/visibility updates.
local OPEN = [[
    local menu = self:GetFrameRef("menu")
    local id = self:GetAttribute("launcherID")
    if menu:IsShown() and menu:GetAttribute("launcherID") == id then
        menu:UnregisterAutoHide()
        menu:Hide()
        return
    end
    menu:UnregisterAutoHide()
    menu:SetAttribute("launcherID", id)
    menu:ClearAllPoints()
    menu:SetPoint(self:GetAttribute("menuPoint"), self, self:GetAttribute("menuRelative"),
        self:GetAttribute("menuX"), self:GetAttribute("menuY"))
    menu:SetWidth(self:GetAttribute("menuWidth"))
    menu:Show()
    menu:RegisterAutoHide(.2)
    menu:AddToAutoHide(self)
]]
local OWNER_HIDDEN = [[
    if control:GetAttribute("launcherID") == self:GetAttribute("launcherID") then
        control:UnregisterAutoHide()
        control:Hide()
    end
]]

local X = { TOPRIGHT = 1, RIGHT = 1, BOTTOMRIGHT = 1, TOP = .5, CENTER = .5, BOTTOM = .5 }
local Y = { TOPLEFT = 1, TOP = 1, TOPRIGHT = 1, LEFT = .5, CENTER = .5, RIGHT = .5 }

local function CreateLauncher(index, menu)
    local launcher = S.CreateFrame("Button", nil, UIParent, "SecureHandlerClickTemplate")
    launcher:Hide()
    launcher:RegisterForClicks("AnyUp")
    launcher:SetAttribute("launcherID", index)
    launcher:SetAttribute("_onclick", OPEN)
    SecureHandlerSetFrameRef(launcher, "menu", menu)
    SecureHandlerWrapScript(launcher, "OnHide", menu, OWNER_HIDDEN)
    launchers[index] = launcher
    return launcher
end

-- Geometry is converted to UIParent units before configuring secure frames.
local function Rect(frame)
    local left, bottom, width, height = frame:GetRect()
    if not (S.Finite(left) and S.Finite(bottom) and S.Finite(width) and S.Finite(height)
        and width > 0 and height > 0) then return end
    local scale = frame:GetEffectiveScale()
    if not S.Finite(scale) or scale <= 0 then return end
    scale = scale / UIParent:GetEffectiveScale()
    return left * scale, bottom * scale, width * scale, height * scale
end

local function ConfigureLauncher(index, menu, button, driver)
    local x, y, width, height = Rect(button)
    if not x then return false end
    local panel = Actions.MicroMenuPanel(button)
    local ax, ay, aw, ah
    if panel then ax, ay, aw, ah = Rect(panel) end
    if not ax then ax, ay, ah = x, y, height end
    local below = ay > UIParent:GetHeight() - ay - ah
    local launcher = launchers[index] or CreateLauncher(index, menu)
    launcher:ClearAllPoints()
    local _, _, relative = button.bar.frame:GetPoint()
    relative = relative or "BOTTOMLEFT"
    launcher:SetPoint("BOTTOMLEFT", UIParent, relative,
        x - UIParent:GetWidth() * (X[relative] or 0), y - UIParent:GetHeight() * (Y[relative] or 0))
    launcher:SetSize(width, height)
    launcher:SetFrameStrata(button:GetFrameStrata())
    launcher:SetFrameLevel(button:GetFrameLevel() + 5)
    launcher:SetAttribute("menuPoint", below and "TOPLEFT" or "BOTTOMLEFT")
    launcher:SetAttribute("menuRelative", below and "BOTTOMLEFT" or "TOPLEFT")
    launcher:SetAttribute("menuX", ax - x)
    launcher:SetAttribute("menuY", below and ay - y - 3 or ay + ah - y - height + 3)
    launcher:SetAttribute("menuWidth", aw or 240)
    if launcher.driver ~= driver then
        if launcher.driver then UnregisterStateDriver(launcher, "visibility") end
        launcher.driver = driver
        RegisterStateDriver(launcher, "visibility", driver)
    end
    return true
end

-- Conditions with Lua-only visibility can change after lockdown. Refuse the
-- detached overlay for these bars so an invisible bar cannot capture clicks.
local function Eligible(module, bar)
    local c = module.config
    local mode = c[bar.visibilityKey]
    return module.presentIDs[bar.index] and c[bar.enabledKey] == true
        and mode ~= VISIBILITY.OUT_OF_COMBAT and mode ~= VISIBILITY.MOUSEOVER
        and not (c[bar.injuredKey] or c[bar.instanceKey] or c[bar.housingKey])
end

local function PrepareBar(module, bar, index, menu)
    if not Eligible(module, bar) then return index, menu end
    local driver
    for _, button in ipairs(bar.slots) do
        if button.extra and button.extra.kind == "microMenu" then
            menu = menu or Actions.PrepareCombatMicro()
            if not menu then break end
            driver = driver or "[nocombat] hide; " .. (bar.visibilityMacro or "show")
            if ConfigureLauncher(index + 1, menu, button, driver) then index = index + 1 end
        end
    end
    return index, menu
end

local function ReleaseLaunchers(first)
    for i = first, #launchers do
        local launcher = launchers[i]
        if launcher.driver then
            UnregisterStateDriver(launcher, "visibility")
            launcher.driver = nil
            launcher:Hide()
            launcher:ClearAllPoints()
        end
    end
end

function CombatMenu.Sync(module)
    if NS.IsCombatLocked() then return end
    local count, menu = 0, nil
    for _, bar in pairs(module.bars) do count, menu = PrepareBar(module, bar, count, menu) end
    ReleaseLaunchers(count + 1)
end

function CombatMenu.Disable()
    if NS.IsCombatLocked() then return end
    local menu = Actions.combatMicroPopup
    if menu then menu:Hide() end
    ReleaseLaunchers(1)
end

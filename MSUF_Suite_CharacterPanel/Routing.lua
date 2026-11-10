local _, NS = ...
local Suite, Bindings = NS.Suite, NS.Host.CharacterBindings
local Routing = {}
NS.Routing = Routing

local root, paperDoll, onVisibility, onSize, nativeGearSidebar
local gearClick, gearOwner, clickRequest, requestedGear, requestedShortcut
local shortcutTabs = { gear = true, reputation = true, currency = true }
local gearTabs = { overview = true, gear = true }
local nativeBindings = { overview = "character", reputation = "reputation", currency = "currency" }
local tabs = { PaperDollFrame = "overview", ReputationFrame = "reputation", TokenFrame = "currency" }
if NS.Host.Client.isForever then
    tabs.SkillsFrame, tabs.PVPRankFrame, tabs.StatisticsFrame = "skills", "pvp", "statistics"
    nativeBindings.pvp = "pvp"
end

local bindingConfig, bindingOwner, bindingListening, bindingWriting
local activeRoutes, wantedRoutes = {}, {}
local APPLY_BINDINGS = [[
self:ClearBindings()
if self:GetAttribute("state-characterkeys") == "suite" then
    for i = 1, self:GetAttribute("count") or 0 do
        self:SetBinding(false, self:GetAttribute("key" .. i), self:GetAttribute("command" .. i))
    end
end
]]

local function CollectKeys(binding, context, ...)
    for i = 1, select("#", ...) do
        local key = NS.String(select(i, ...))
        if key and key ~= "" then
            local current = NS.String(GetBindingAction(key, true, context))
            if current and (current == binding.command or current == activeRoutes[key]) then
                wantedRoutes[key] = binding.override
            end
        end
    end
end

local function SameRoutes()
    for key, command in pairs(activeRoutes) do if wantedRoutes[key] ~= command then return false end end
    for key, command in pairs(wantedRoutes) do if activeRoutes[key] ~= command then return false end end
    return true
end

function Routing.UpdateBindings()
    if bindingWriting or (not bindingConfig and not next(activeRoutes)) or NS.Host.InCombat() then return end
    wipe(wantedRoutes)
    if bindingConfig and NS.CanReplace() then
        for _, binding in ipairs(Bindings.Native) do
            if binding.override and Bindings.NativeTab(bindingConfig, binding.id) then
                local context = C_KeyBindings.GetBindingContextForAction(binding.command)
                if NS.Public(context) then CollectKeys(binding, context, GetBindingKey(binding.command, nil, context)) end
            end
        end
    end
    if SameRoutes() then return end
    activeRoutes, wantedRoutes = wantedRoutes, activeRoutes
    bindingWriting = true
    local owner = bindingOwner
    if not owner then
        owner = Suite.CreateFrame("Frame", nil, UIParent, "SecureHandlerStateTemplate")
        owner:SetScript("OnEvent", function(frame)
            frame:UnregisterEvent("PLAYER_REGEN_ENABLED")
            Routing.UpdateBindings()
        end)
        owner:SetAttribute("_onstate-characterkeys", APPLY_BINDINGS)
        bindingOwner = owner
    end
    local count = 0
    for key, command in pairs(activeRoutes) do
        count = count + 1
        owner:SetAttribute("key" .. count, key)
        owner:SetAttribute("command" .. count, command)
    end
    owner:SetAttribute("count", count)
    SecureHandlerExecute(owner, APPLY_BINDINGS)
    if count > 0 and not next(wantedRoutes) then
        RegisterStateDriver(owner, "characterkeys", "[combat][petbattle][vehicleui] native; suite")
    elseif count == 0 then
        UnregisterStateDriver(owner, "characterkeys")
        owner:SetAttribute("state-characterkeys", nil)
    end
    bindingWriting = nil
end

function Routing.RefreshBindings(config, context)
    Bindings.RefreshLabels(config)
    bindingConfig = nil
    if config then
        for _, binding in ipairs(Bindings.Native) do
            if binding.override and Bindings.NativeTab(config, binding.id) then
                bindingConfig = config
                break
            end
        end
    end
    if bindingConfig and not bindingListening then
        context:Event("UPDATE_BINDINGS", Routing.UpdateBindings)
        context:Event("ACTIVE_GAME_MODE_UPDATED", Routing.UpdateBindings)
        bindingListening = true
    elseif not bindingConfig and bindingListening then
        context:RemoveEvent("UPDATE_BINDINGS")
        context:RemoveEvent("ACTIVE_GAME_MODE_UPDATED")
        bindingListening = nil
    end
    if not bindingConfig and next(activeRoutes) and NS.Host.InCombat() then
        bindingOwner:RegisterEvent("PLAYER_REGEN_ENABLED")
    else
        Routing.UpdateBindings()
    end
end

function Routing.HasBindingRoutes()
    return bindingConfig ~= nil
end

function Routing.Root() return root end

function Routing.PaperDollShown()
    return paperDoll and paperDoll:IsVisible()
end

function Routing.Shown()
    if not root or nativeGearSidebar or not root:IsVisible() then return end
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

local function TabVisible(tab)
    return Suite.CharacterHeader.TabVisible(Suite.Config("characterPanel"), "tab", tab)
end

-- Start at the native owner, then take the Suite tab through the existing visibility job.
-- A gear shortcut from a different Blizzard pane uses the read-only Equipment report.
local function OpenTab(tab)
    if not Suite.ShowPanel("character") then return false end
    nativeGearSidebar = nil
    local visible = Routing.Shown()
    if not visible then return false end
    requestedShortcut = tab
    onVisibility(visible)
    return true
end

function Suite.OpenCharacterPanelTab(tab)
    if not NS.Public(tab) or not shortcutTabs[tab] or not onVisibility or not NS.CanReplace() or not TabVisible(tab) then return false end
    return OpenTab(tab)
end

function Suite.OpenBoundCharacterTab(command)
    if not onVisibility or not NS.CanReplace() then return false end
    command = NS.String(command)
    local tab = command and Bindings.DirectTab(Suite.Config("characterPanel"), command)
    return tab and OpenTab(tab) or false
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
        requestedGear, requestedShortcut = tab, nil
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
    requestedGear, requestedShortcut, nativeGearSidebar = nil, nil, nil
    if onVisibility then onVisibility(nil) end
end

local function Switched()
    -- Retail stores activeSubframe after showing the child; observe the
    -- complete switch, not the outgoing paper doll's intermediate OnHide.
    if not onVisibility or not root:IsVisible() then return end
    requestedGear, requestedShortcut, nativeGearSidebar = nil, nil, nil
    Routing.ReleaseGearClick()
    Shown()
end

local function NativeToggle(name, onlyShow)
    if not onVisibility or not NS.Public(onlyShow) then return end
    local shown, tab = Routing.Shown()
    if shown and tabs[NS.String(name)] == tab then
        local binding = not onlyShow and nativeBindings[tab]
        requestedShortcut = binding and Bindings.NativeTab(Suite.Config("characterPanel"), binding) or tab
        onVisibility(shown, requestedShortcut)
    end
end

-- The Planner's native fallback explicitly opens the equipment-manager sidebar.
-- Let its native surface own this open cycle when Suite Equipment is hidden.
local function NativeSidebar(owner)
    if not onVisibility or not NS.Public(owner) or owner ~= nil or not Routing.PaperDollShown() or TabVisible("gear") then return end
    local pane = paperDoll.EquipmentManagerPane
    if not NS.Public(pane) or not pane then return end
    local visible = pane:IsVisible()
    if not NS.Public(visible) or visible ~= true then return end
    nativeGearSidebar, requestedGear, requestedShortcut = true, nil, nil
    onVisibility(nil)
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
        requestedGear, requestedShortcut, nativeGearSidebar = nil, nil, nil
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
        -- The native toggle owns input and visibility, including closes on the same pane.
        hooksecurefunc("ToggleCharacter", NativeToggle)
        hooksecurefunc("PaperDollFrame_SetSidebar", NativeSidebar)
    end
    Shown()
end

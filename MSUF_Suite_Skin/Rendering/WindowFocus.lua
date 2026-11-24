local _, NS = ...

-- A visible-only window inventory, independent of move/scale permission.
-- Native input and geometry are observed; only our own veils are changed.
local Focus = { records = setmetatable({}, { __mode = "k" }) }
NS.WindowFocus = Focus
local Safety, Geometry, Visual = NS.Safety, NS.WindowFocusGeometry, NS.WindowFocusVisual
local visible, generations = {}, {}
local presentations = setmetatable({}, { __mode = "k" })
local count, serial = 0, 0
local driver = CreateFrame("Frame")
driver:Hide()
local mouseListening, geometryPending, scaleListening = false, false, false
local moving = {}
local movingCount = 0
local inputWindow
local Reconcile, UpdateListeners, QueueGeometry, GamepadChanged
local gamepadRegistry
local GAMEPAD_FOCUS_EVENT = "Gamepad.RefreshFrameFocus"
local mailFocusQueued = false
local mailOutlines = {}
local tradingBags = {
    ContainerFrameCombinedBags = true,
    ContainerFrame1 = true, ContainerFrame2 = true, ContainerFrame3 = true,
    ContainerFrame4 = true, ContainerFrame5 = true, ContainerFrame6 = true,
}

local function Enabled()
    return NS.DB and NS.DB.enabled ~= false and NS.DB.theme and NS.DB.theme.windowFocusDimming ~= false
end

local function Owned(state)
    for owner, generation in pairs(state.owners) do
        if generations[owner] == generation then return true end
    end
    return false
end

local function IsVisible(frame)
    return Safety.Read(frame, "IsVisible") == true
end

local function HideOutline(state)
    if state.outline then state.outline:Hide() end
    if state.tooltipOutline then state.tooltipOutline:Hide() end
end

local function UpdateOutline(state)
    local db, frame = NS.DB, state.frame
    local theme = db and db.theme
    local pixels = theme and theme.windowOutline or 0
    local matchTooltip = theme and theme.windowOutlineMatchTooltip == true
    if (not matchTooltip and pixels == 0) or db.enabled == false or db.blizzardWindowsEnabled == false
        or db.skins and db.skins.blizzardWindows == false or presentations[frame] or not IsVisible(frame) then
        HideOutline(state)
        return
    end
    if NS.IsCombatLocked() then
        driver:RegisterEvent("PLAYER_REGEN_ENABLED")
        return
    end
    if not Safety.CanCreateRegions(frame) or not Geometry.Layer(state) then
        HideOutline(state)
        return
    end
    if matchTooltip then
        if state.outline then state.outline:Hide() end
        state.tooltipOutline = Visual.PaintTooltipOutline(frame, state.tooltipOutline, state.strata, state.level)
        return
    end
    if state.tooltipOutline then state.tooltipOutline:Hide() end
    local outline = NS.SuiteCore().WindowOutline
    local r, g, b, a = NS.Theme.GetColor("windowOutline")
    state.outline = outline.Paint(frame, state.outline, pixels, r, g, b, a, state.strata, state.level, true)
end

local function Hide(state, immediate)
    for index = 1, #state.veils do Visual.Hide(state.veils[index], immediate) end
end

local function StopDriver()
    geometryPending, inputWindow = false, nil
    for state in pairs(moving) do moving[state] = nil end
    movingCount = 0
    driver:UnregisterEvent("GLOBAL_MOUSE_UP")
    driver:SetScript("OnUpdate", nil)
    driver:Hide()
end

local function ChooseActive()
    local active
    for _, state in pairs(visible) do
        if not active or state.order > active.order then active = state end
    end
    Focus.active = active
    return active
end

local function Paint(state)
    if state.keepClear or not state.readable then Hide(state, false) return end
    if not Geometry.Begin(state) then Hide(state, true) return end
    for _, other in pairs(visible) do
        if other ~= state and other.readable and (other.keepClear or Geometry.Above(other, state))
            and not Geometry.SubtractWindow(state, other) then Hide(state, true) return end
    end
    if not NS.WindowFocusPopups.Subtract(state) then Hide(state, true) return end
    for index = 1, state.sliceCount do
        local veil = state.veils[index]
        if not veil then
            veil = Visual.Create()
            state.veils[index] = veil
        end
        Visual.Show(veil, state.slices[index], state.materialRect, state.paintStrata, state.paintLevel)
    end
    for index = state.sliceCount + 1, #state.veils do Visual.Hide(state.veils[index], true) end
end

Reconcile = function()
    if mailFocusQueued then return end
    local active = ChooseActive()
    if not Enabled() or count < 2 or not active then
        for _, state in pairs(visible) do Hide(state, true) end
        UpdateListeners()
        return
    end
    local merchant = visible[Safety.Field(_G, "MerchantFrame")]
    local auction = visible[Safety.Field(_G, "AuctionHouseFrame")]
    local bank = visible[Safety.Field(_G, "BankFrame")]
    local mail = visible[Safety.Field(_G, "MailFrame")]
    local openMail = visible[Safety.Field(_G, "OpenMailFrame")]
    local bagsOpen = false
    for frame, state in pairs(visible) do
        local surface = presentations[frame]
        state.presentation = IsVisible(surface) and surface or nil
        state.readable = IsVisible(frame) and Geometry.Read(state.presentation or frame, state.rect)
            and Geometry.Layer(state)
        if state.readable then
            NS.WindowFocusChrome.Update(state)
            NS.WindowFocusLayers.Prepare(state)
        end
        if tradingBags[state.name] then bagsOpen = true end
    end
    -- These workflows use multiple windows together. Keep their participants
    -- clear even when another window receives input.
    local shopping = bagsOpen and (merchant or auction)
    local banking = bagsOpen and bank
    local mailing = bagsOpen and (mail or openMail)
    local backpack = visible[Safety.Field(_G, "ContainerFrameCombinedBags")]
    local reagent = visible[Safety.Field(_G, "ContainerFrame6")]
    local bagPair = backpack and reagent
    local character = visible[Safety.Field(_G, "CharacterFrame")]
    local upgrade = visible[Safety.Field(_G, "ItemUpgradeFrame")]
    local upgrading = character and upgrade
    local clearBounds = active.readable
    for _, state in pairs(visible) do
        state.keepClear = state == active or upgrading and (state == character or state == upgrade)
            or shopping and (state == merchant or state == auction or tradingBags[state.name])
            or banking and (state == bank or tradingBags[state.name])
            or mailing and (state == mail or state == openMail or tradingBags[state.name])
            or bagPair and (state == backpack or state == reagent)
        if state.keepClear and not state.readable then clearBounds = false end
    end
    for _, state in pairs(visible) do
        if clearBounds then Paint(state) else Hide(state, true) end
    end
    UpdateListeners()
end

local function SettleMailFocus()
    mailFocusQueued = false
    for state in pairs(mailOutlines) do
        mailOutlines[state] = nil
        if state.focusVisible and IsVisible(state.frame) then UpdateOutline(state) end
    end
    Reconcile()
end

local function UpdateOpeningOutline(state)
    local policy = NS.WindowControlPolicy
    if (state.name == "MailFrame" or tradingBags[state.name]) and policy.MailIsOpen() then
        -- Forever shows the panel and opens inventory before the protected
        -- reading emote. The focus pass discovers and hooks native chrome.
        mailOutlines[state] = true
        if not mailFocusQueued then
            mailFocusQueued = true
            C_Timer.After(0, SettleMailFocus)
        end
        return
    end
    UpdateOutline(state)
end

local function Step()
    geometryPending = false
    if movingCount > 0 and not IsMouseButtonDown("LeftButton") and not IsMouseButtonDown("RightButton") then
        for state in pairs(moving) do moving[state] = nil end
        movingCount = 0
        if not inputWindow then driver:UnregisterEvent("GLOBAL_MOUSE_UP") end
    end
    Reconcile()
    if movingCount == 0 and not geometryPending then
        driver:SetScript("OnUpdate", nil)
        driver:Hide()
    end
end

QueueGeometry = function()
    if count < 2 or not Enabled() then return end
    geometryPending = true
    driver:SetScript("OnUpdate", Step)
    driver:Show()
end

UpdateListeners = function()
    local listen = Enabled() and count >= 2
    if listen ~= mouseListening then
        mouseListening = listen
        NS.WindowFocusPopups.SetActive(listen)
        if listen then
            driver:RegisterEvent("GLOBAL_MOUSE_DOWN")
            NS.WindowFocusPopups.Discover()
        else
            driver:UnregisterEvent("GLOBAL_MOUSE_DOWN")
        end
    end
    local theme = NS.DB and NS.DB.theme
    local scale = listen or count > 0 and theme ~= nil
        and (theme.windowOutlineMatchTooltip == true or (theme.windowOutline or 0) > 0)
    if scale ~= scaleListening then
        scaleListening = scale
        if scale then
            driver:RegisterEvent("UI_SCALE_CHANGED")
            driver:RegisterEvent("DISPLAY_SIZE_CHANGED")
        else
            driver:UnregisterEvent("UI_SCALE_CHANGED")
            driver:UnregisterEvent("DISPLAY_SIZE_CHANGED")
        end
    end
    if listen and not gamepadRegistry then
        local manager = Safety.Field(Safety.Field(_G, "GamepadMode"), "FrameControlsManager")
        local events = Safety.Field(_G, "EventRegistry")
        if Safety.HasMethod(manager, "GetActiveFrame") and Safety.HasMethod(events, "RegisterCallback") then
            gamepadRegistry = events
            events:RegisterCallback(GAMEPAD_FOCUS_EVENT, GamepadChanged, Focus)
        end
    elseif not listen and gamepadRegistry then
        gamepadRegistry:UnregisterCallback(GAMEPAD_FOCUS_EVENT, Focus)
        gamepadRegistry = nil
    end
    if not listen then StopDriver() end
end

local function Promote(state)
    state.chromeDirty = true
    serial = serial + 1
    state.order = serial
    Reconcile()
end

local function FindMouseWindow(frame)
    for _ = 1, 24 do
        if not Safety.Public(frame) or not frame or Safety.IsForbidden(frame) then return end
        local state = visible[frame]
        if state then return state end
        frame = Safety.Read(frame, "GetParent")
    end
end

GamepadChanged = function()
    local manager = Safety.Field(Safety.Field(_G, "GamepadMode"), "FrameControlsManager")
    local state = FindMouseWindow(Safety.Read(manager, "GetActiveFrame"))
    if state and state ~= Focus.active then Promote(state) end
end

local function MouseDown()
    local getFoci = Safety.Field(_G, "GetMouseFoci")
    local foci = getFoci and getFoci()
    if not Safety.Public(foci) or type(foci) ~= "table" then return end
    local state = FindMouseWindow(foci[1])
    if state then
        if state ~= Focus.active then Promote(state) end
        state.chromeDirty, inputWindow = true, state
        driver:RegisterEvent("GLOBAL_MOUSE_UP")
        QueueGeometry()
    end
end

driver:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_REGEN_ENABLED" then
        driver:UnregisterEvent(event)
        for _, state in pairs(visible) do UpdateOutline(state) end
    elseif event == "GLOBAL_MOUSE_DOWN" then MouseDown()
    elseif event == "GLOBAL_MOUSE_UP" then
        local state = inputWindow
        StopDriver()
        Reconcile()
        if state and state.focusVisible then
            state.chromeDirty = true
            QueueGeometry()
        end
    else
        for _, state in pairs(visible) do UpdateOutline(state) end
        QueueGeometry()
    end
end)

local function Shown(frame)
    local state = Focus.records[frame]
    if not state or not Owned(state) or not IsVisible(frame) then return end
    if not visible[frame] then visible[frame], count = state, count + 1 end
    state.focusVisible = true
    UpdateOpeningOutline(state)
    Promote(state)
end

local function Hidden(frame)
    local state = Focus.records[frame]
    if not state then return end
    state.focusVisible = false
    HideOutline(state)
    if visible[frame] then visible[frame], count = nil, count - 1 end
    if moving[state] then moving[state], movingCount = nil, movingCount - 1 end
    Hide(state, true)
    Reconcile()
end

local function GeometryChanged(frame)
    if visible[frame] then QueueGeometry() end
end

local function LayoutChanged(frame)
    local state = visible[frame]
    if state then
        state.chromeDirty = true
        if not mailOutlines[state] then UpdateOutline(state) end
    end
    GeometryChanged(frame)
end

local function Moving(frame)
    local state = visible[frame]
    if not state or count < 2 or not Enabled() then return end
    if not moving[state] then moving[state], movingCount = true, movingCount + 1 end
    driver:RegisterEvent("GLOBAL_MOUSE_UP")
    QueueGeometry()
end

local function Moved(frame)
    local state = Focus.records[frame]
    if state and moving[state] then moving[state], movingCount = nil, movingCount - 1 end
    if movingCount == 0 and not inputWindow then driver:UnregisterEvent("GLOBAL_MOUSE_UP") end
    GeometryChanged(frame)
end

local geometryMethods = { "SetPoint", "ClearAllPoints", "SetScale", "SetFrameLevel", "SetFrameStrata", "Raise" }
local function Observe(frame)
    frame:HookScript("OnShow", Shown)
    frame:HookScript("OnHide", Hidden)
    frame:HookScript("OnSizeChanged", LayoutChanged)
    for index = 1, #geometryMethods do
        local method = geometryMethods[index]
        if Safety.HasMethod(frame, method) then
            local layout = method == "SetFrameLevel" or method == "SetFrameStrata" or method == "Raise" or method == "SetScale"
            local callback = layout and LayoutChanged or GeometryChanged
            hooksecurefunc(frame, method, callback)
        end
    end
    if Safety.HasMethod(frame, "StartMoving") then hooksecurefunc(frame, "StartMoving", Moving) end
    if Safety.HasMethod(frame, "StartSizing") then hooksecurefunc(frame, "StartSizing", Moving) end
    if Safety.HasMethod(frame, "StopMovingOrSizing") then hooksecurefunc(frame, "StopMovingOrSizing", Moved) end
end

-- A native window can present a wider Suite shell while keeping the same input owner.
function Focus.Present(frame, surface)
    if presentations[frame] == surface then return end
    presentations[frame] = surface
    local state = visible[frame]
    if state then
        state.chromeDirty = true
        UpdateOutline(state)
        Reconcile()
    end
end

function Focus.Track(frame, owner)
    local name = NS.WindowControlPolicy.IdentifyFocusWindow(frame)
    if not name or not Safety.HasMethod(frame, "HookScript") then return false end
    local state = Focus.records[frame]
    if not state then
        state = { frame = frame, name = name, owners = {}, rect = {}, veils = {}, order = 0 }
        Focus.records[frame] = state
        Observe(frame)
    end
    owner = owner or "blizzardWindows"
    if generations[owner] == nil then generations[owner] = 0 end
    state.owners[owner] = generations[owner]
    if IsVisible(frame) and not visible[frame] then
        visible[frame], count = state, count + 1
        state.focusVisible, state.chromeDirty = true, true
        UpdateOpeningOutline(state)
        if state.order == 0 then
            serial = serial + 1
            state.order = serial
        end
        Reconcile()
    end
    return true
end

function Focus.ReleaseOwner(owner)
    generations[owner] = (generations[owner] or 0) + 1
    for frame, state in pairs(visible) do
        if not Owned(state) then
            state.focusVisible = false
            HideOutline(state)
            if visible[frame] then visible[frame], count = nil, count - 1 end
            if moving[state] then moving[state], movingCount = nil, movingCount - 1 end
            Hide(state, true)
        end
    end
    Reconcile()
end

local function SettingsChanged(_, domain)
    if domain == "profile" or domain == "motion" or domain == "adapter" or domain == "theme"
        or domain == "color" or domain == "appearance" or domain == "geometry" or domain == "tooltipStyle" then
        for _, state in pairs(visible) do
            UpdateOutline(state)
            for index = 1, #state.veils do Visual.Refresh(state.veils[index]) end
        end
        Reconcile()
    end
end

NS.WindowFocusChrome.Initialize(QueueGeometry)
NS.WindowFocusPopups.Initialize(QueueGeometry)
NS.Registry.AddListener(Focus, SettingsChanged)
-- Our caption fades Blizzard's caption buttons outside the observed geometry
-- hooks: the window's chrome is discovered again, without those buttons.
function Focus.RefreshChrome(frame) LayoutChanged(frame) end
NS.WindowFocusChrome.SetHidden(NS.WindowControlChrome.IsFaded)
NS.WindowControlChrome.SetFocusRefresh(Focus.RefreshChrome)
NS.WindowControls.SetFocusProvider(Focus.Track, Focus.ReleaseOwner)

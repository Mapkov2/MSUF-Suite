local _, NS = ...

-- Blizzard owns the macro selector, icon data and command editor. This adapter
-- replaces only its verified slot art and decorative frame textures.
local MacroWindow = { states = setmetatable({}, { __mode = "k" }) }
NS.MacroWindow = MacroWindow
local loadFrame = CreateFrame("Frame")
local requestedOwner

local divider = "interface\\classtrainerframe\\ui-classtrainer-horizontalbar"
local slotBackdrop = "interface\\buttons\\ui-emptyslot-disabled"

-- MacroFrame's native art is laid out above its background. Keep exact
-- original alpha values like Bags does, so the adapter can restore them when
-- Blizzard-window skinning is disabled without depending on another owner.
local function HideNative(state, region)
    if not region or type(region.GetAlpha) ~= "function"
        or type(region.SetAlpha) ~= "function"
        or not NS.Safety.CanDecorate(region, true) then return false end
    if state.nativeAlpha[region] == nil then
        local alpha = region:GetAlpha()
        if type(alpha) ~= "number"
            or (type(issecretvalue) == "function" and issecretvalue(alpha)) then
            return false
        end
        state.nativeAlpha[region] = alpha
    end
    region:SetAlpha(0)
    return true
end

local function RestoreNative(state)
    for region, alpha in pairs(state.nativeAlpha) do
        if region:GetAlpha() == 0 then region:SetAlpha(alpha) end
        state.nativeAlpha[region] = nil
    end
end

local function TexturePath(region)
    if not region or type(region.GetTexture) ~= "function" then return nil end
    local path = region:GetTexture()
    if type(path) ~= "string" then return nil end
    return path:gsub("/", "\\"):lower():gsub("%.blp$", "")
end

local function FadeDividerRegions(state, ...)
    for index = 1, select("#", ...) do
        local region = select(index, ...)
        local followsLeft = false
        if region and type(region.GetTexture) == "function"
            and type(region.GetPoint) == "function" then
            local point, relativeTo, relativePoint = region:GetPoint(1)
            followsLeft = point == "LEFT" and relativeTo == _G.MacroHorizontalBarLeft
                and relativePoint == "RIGHT"
        end
        if TexturePath(region) == divider or followsLeft then
            HideNative(state, region)
        end
    end
end

local function HasReadyView(scrollBox)
    return scrollBox and type(scrollBox.HasView) == "function"
        and scrollBox:HasView() == true
end

local function FadeBackgroundRegions(state, ...)
    -- SelectorButtonTemplate has one BACKGROUND texture for the empty slot.
    -- Its icon is the NormalTexture, so it remains Blizzard-owned and visible.
    for index = 1, select("#", ...) do
        local region = select(index, ...)
        local templateCoords = false
        if region and type(region.GetTexCoord) == "function" then
            local left, right, top, bottom = region:GetTexCoord()
            templateCoords = left == 0.140625 and right == 0.84375
                and top == 0.140625 and bottom == 0.84375
        end
        if region and type(region.GetDrawLayer) == "function"
            and region:GetDrawLayer() == "BACKGROUND"
            and (TexturePath(region) == slotBackdrop or templateCoords) then
            HideNative(state, region)
        end
    end
end

local function FadeSlotBackdrop(button, state)
    if type(button.GetRegions) == "function" then
        FadeBackgroundRegions(state, button:GetRegions())
    end
end

local function Selected(button)
    local texture = button and button.SelectedTexture
    if not texture or type(texture.IsShown) ~= "function" then return false end
    local shown = texture:IsShown()
    if type(issecretvalue) == "function" and issecretvalue(shown) then return false end
    return shown == true
end

local function RefreshVisibleSelection(state)
    if not state.active or NS.IsCombatLocked() then return end
    local scrollBox = state.scrollBox
    if not HasReadyView(scrollBox) then return end
    scrollBox:ForEachFrame(function(button)
        if state.buttons[button] then NS.Surface.SetActive(button, Selected(button)) end
    end)
end

local function StyleSlot(state, button)
    if not state.active or NS.IsCombatLocked() or not button
        or not NS.Safety.CanCreateRegions(button, true)
        or not button.Icon or not button.SelectedTexture then return false end
    FadeSlotBackdrop(button, state)
    HideNative(state, button.SelectedTexture)
    HideNative(state, button.Highlight)
    local surface = NS.Surface.Attach(button, {
        role = "button", activeRole = "navigationActive",
        shape = "continuous", radius = 4, inset = 0,
        forceEdge = true, activeEdge = true, interactive = true,
        allowImplicitProtected = true,
    })
    if not surface then return false end
    -- The icon is native ARTWORK. Put the transparent edge above it while
    -- retaining Blizzard's normal icon, name, drag and click behavior.
    surface.edge:SetDrawLayer("OVERLAY", 2)
    state.buttons[button] = true
    NS.Surface.SetActive(button, Selected(button))
    if not state.clickHooks[button] and type(button.HookScript) == "function" then
        button:HookScript("OnClick", function() RefreshVisibleSelection(state) end)
        state.clickHooks[button] = true
    end
    return true
end

local function StyleFrame(state, frame)
    local owner = state.owner
    local previous = NS.Registry and NS.Registry.GetSurface
        and NS.Registry.GetSurface(frame)
    if NS.Surface.Attach(frame, {
        role = "popup", shape = "continuous", radius = 6,
        border = 1, fillAlphaScale = 1.10,
        inset = 0, allowImplicitProtected = true,
    }) and not previous then state.rootOwned = true end
    HideNative(state, frame.Bg)
    HideNative(state, frame.NineSlice)
    HideNative(state, _G.MacroFramePortrait)
    local portraitContainer = frame.PortraitContainer
    HideNative(state, portraitContainer)
    HideNative(state, portraitContainer and portraitContainer.portrait)
    HideNative(state, _G.MacroFrameSelectedMacroBackground)
    HideNative(state, _G.MacroHorizontalBarLeft)
    if type(frame.GetRegions) == "function" then
        FadeDividerRegions(state, frame:GetRegions())
    end
    local inset = frame.Inset
    if inset and NS.Safety.CanCreateRegions(inset, true) then
        HideNative(state, inset.Bg)
        HideNative(state, inset.NineSlice)
        if NS.Surface.Attach(inset, {
            role = "panel", shape = "continuous", radius = 4,
            inset = 0, allowImplicitProtected = true,
        }) then state.inset = inset end
    end
    local background = _G.MacroFrameTextBackground
    if background and NS.Safety.CanCreateRegions(background, true) then
        HideNative(state, background.NineSlice)
        if NS.Surface.Attach(background, {
            role = "input", shape = "continuous", radius = 6,
            inset = 0, allowImplicitProtected = true,
        }) then state.textBackground = background end
    end
    StyleSlot(state, frame.SelectedMacroButton)
end

function MacroWindow.Apply(frame, owner)
    if not frame or NS.IsCombatLocked() or not NS.Safety.CanCreateRegions(frame, true) then
        return false
    end
    local state = MacroWindow.states[frame]
    if not state then
        state = {
            buttons = setmetatable({}, { __mode = "k" }),
            clickHooks = setmetatable({}, { __mode = "k" }),
            nativeAlpha = setmetatable({}, { __mode = "k" }),
        }
        MacroWindow.states[frame] = state
    end
    state.active, state.owner, state.frame = true, owner, frame
    if not state.showHooked and type(frame.HookScript) == "function" then
        frame:HookScript("OnShow", function()
            if state.active then MacroWindow.Apply(frame, state.owner) end
        end)
        state.showHooked = true
    end
    -- Blizzard rebuilds the macro selector on opening, tab changes and
    -- UPDATE_MACROS. As with Bags:UpdateItems, finish its native Update first.
    if not state.updateHooked and type(hooksecurefunc) == "function"
        and type(frame.Update) == "function" then
        hooksecurefunc(frame, "Update", function()
            if state.active then MacroWindow.Apply(frame, state.owner) end
        end)
        state.updateHooked = true
    end
    -- ADDON_LOADED fires while the hidden MacroFrame still has no selector
    -- view. The frame's OnShow hook applies chrome after Blizzard opens it.
    if type(frame.IsShown) == "function" and frame:IsShown() ~= true then return true end
    StyleFrame(state, frame)
    local selector = frame.MacroSelector
    local scrollBox = selector and selector.ScrollBox
    -- The selector can finish initializing after ADDON_LOADED. OnShow retries
    -- once Blizzard has built it; older clients keep the generic window skin.
    if not scrollBox or type(scrollBox.ForEachFrame) ~= "function" then return true end
    state.scrollBox = scrollBox
    local event = ScrollBoxListMixin and ScrollBoxListMixin.Event
        and ScrollBoxListMixin.Event.OnInitializedFrame
    if event and not state.registered and type(scrollBox.RegisterCallback) == "function" then
        scrollBox:RegisterCallback(event, function(_, button)
            if state.active then StyleSlot(state, button) end
        end, state)
        state.registered, state.event = true, event
    end
    if HasReadyView(scrollBox) then
        scrollBox:ForEachFrame(function(button) StyleSlot(state, button) end)
    end
    return true
end

function MacroWindow.Start(owner)
    requestedOwner = owner
    local frame = _G.MacroFrame
    if frame then
        loadFrame:UnregisterEvent("ADDON_LOADED")
        return MacroWindow.Apply(frame, owner)
    end
    if NS.Client and NS.Client.HasAddOn("Blizzard_MacroUI") == false then
        return false
    end
    loadFrame:RegisterEvent("ADDON_LOADED")
    return true
end

loadFrame:SetScript("OnEvent", function(self, event, addon)
    if event ~= "ADDON_LOADED" or addon ~= "Blizzard_MacroUI" then return end
    self:UnregisterEvent("ADDON_LOADED")
    if requestedOwner and _G.MacroFrame then
        MacroWindow.Apply(_G.MacroFrame, requestedOwner)
    end
end)

function MacroWindow.Disable(owner)
    if NS.IsCombatLocked() then return false end
    if requestedOwner == owner then
        requestedOwner = nil
        loadFrame:UnregisterEvent("ADDON_LOADED")
    end
    for _, state in pairs(MacroWindow.states) do
        if state.owner == owner and state.active then
            state.active = false
            if state.registered and state.scrollBox
                and type(state.scrollBox.UnregisterCallback) == "function" then
                state.scrollBox:UnregisterCallback(state.event, state)
            end
            state.registered = false
            RestoreNative(state)
            for button in pairs(state.buttons) do NS.Surface.SetVisible(button, false) end
            if state.rootOwned then NS.Surface.SetVisible(state.frame, false) end
            if state.inset then NS.Surface.SetVisible(state.inset, false) end
            if state.textBackground then NS.Surface.SetVisible(state.textBackground, false) end
        end
    end
    return true
end

return MacroWindow

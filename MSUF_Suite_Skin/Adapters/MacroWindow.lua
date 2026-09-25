local _, NS = ...

-- Blizzard owns the macro selector, icon data and command editor. This adapter
-- replaces only its verified slot art and decorative frame textures.
local MacroWindow = { states = setmetatable({}, { __mode = "k" }) }
NS.MacroWindow = MacroWindow
local loadFrame = CreateFrame("Frame")
local requestedOwner

local MACRO_ADDON = "Blizzard_MacroUI"
local divider = "interface\\classtrainerframe\\ui-classtrainer-horizontalbar"
local slotBackdrop = "interface\\buttons\\ui-emptyslot-disabled"

-- Surface keeps a reference to its spec, so these are shared and unchanged.
local SLOT_SPEC = {
    role = "button", activeRole = "navigationActive",
    shape = "continuous", radius = 4, inset = 0,
    forceEdge = true, activeEdge = true, interactive = true,
    allowImplicitProtected = true,
}
local FRAME_SPEC = {
    role = "popup", shape = "continuous", radius = 6,
    border = 1, fillAlphaScale = 1.10,
    inset = 0, allowImplicitProtected = true,
}
local INSET_SPEC = {
    role = "panel", shape = "continuous", radius = 4,
    inset = 0, allowImplicitProtected = true,
}
local TEXT_SPEC = {
    role = "input", shape = "continuous", radius = 6,
    inset = 0, allowImplicitProtected = true,
}

local function IsSecret(value)
    return type(issecretvalue) == "function" and issecretvalue(value)
end

-- MacroFrame's native art is laid out above its background. Keep exact
-- original alpha values like Bags does, so the adapter can restore them when
-- Blizzard-window skinning is disabled without depending on another owner.
local function HideNative(state, region)
    if not region or type(region.GetAlpha) ~= "function"
        or type(region.SetAlpha) ~= "function"
        or not NS.Safety.CanDecorate(region, true) then
        return false
    end
    if state.nativeAlpha[region] == nil then
        local alpha = region:GetAlpha()
        if type(alpha) ~= "number" or IsSecret(alpha) then
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

-- The divider's right half is an anonymous texture anchored to the named
-- left half; secret anchors are never compared.
local function FollowsDividerLeft(region)
    if type(region.GetPoint) ~= "function" then return false end
    local point, relativeTo, relativePoint = region:GetPoint(1)
    if IsSecret(point) or IsSecret(relativeTo) or IsSecret(relativePoint) then return false end
    return point == "LEFT" and relativeTo == _G.MacroHorizontalBarLeft
        and relativePoint == "RIGHT"
end

local function FadeDividerRegions(state, ...)
    for index = 1, select("#", ...) do
        local region = select(index, ...)
        if region and type(region.GetTexture) == "function"
            and (TexturePath(region) == divider or FollowsDividerLeft(region)) then
            HideNative(state, region)
        end
    end
end

local function HasReadyView(scrollBox)
    return scrollBox and type(scrollBox.HasView) == "function"
        and scrollBox:HasView() == true
end

local function HasTemplateCoords(region)
    if type(region.GetTexCoord) ~= "function" then return false end
    local left, right, top, bottom = region:GetTexCoord()
    return left == 0.140625 and right == 0.84375
        and top == 0.140625 and bottom == 0.84375
end

-- SelectorButtonTemplate has one BACKGROUND texture for the empty slot. Its
-- icon is the NormalTexture, so it remains Blizzard-owned and visible.
local function FadeBackgroundRegions(state, ...)
    for index = 1, select("#", ...) do
        local region = select(index, ...)
        if region and type(region.GetDrawLayer) == "function"
            and region:GetDrawLayer() == "BACKGROUND"
            and (TexturePath(region) == slotBackdrop or HasTemplateCoords(region)) then
            HideNative(state, region)
        end
    end
end

local function Selected(button)
    local texture = button and button.SelectedTexture
    if not texture or type(texture.IsShown) ~= "function" then return false end
    local shown = texture:IsShown()
    return not IsSecret(shown) and shown == true
end

local function StyleSlot(state, button)
    if not state.active or NS.IsCombatLocked() or not button
        or not NS.Safety.CanCreateRegions(button, true)
        or not button.Icon or not button.SelectedTexture then
        return false
    end
    if type(button.GetRegions) == "function" then
        FadeBackgroundRegions(state, button:GetRegions())
    end
    HideNative(state, button.SelectedTexture)
    HideNative(state, button.Highlight)
    local surface = NS.Surface.Attach(button, SLOT_SPEC)
    if not surface then return false end
    -- The icon is native ARTWORK. Put the transparent edge above it while
    -- retaining Blizzard's normal icon, name, drag and click behavior.
    surface.edge:SetDrawLayer("OVERLAY", 2)
    state.buttons[button] = true
    NS.Surface.SetActive(button, Selected(button))
    if not state.clickHooks[button] and type(button.HookScript) == "function" then
        button:HookScript("OnClick", state.refreshSelection)
        state.clickHooks[button] = true
    end
    return true
end

local function SyncSelection(state, button)
    if state.buttons[button] then NS.Surface.SetActive(button, Selected(button)) end
end

local function RefreshVisibleSelection(state)
    if not state.active or NS.IsCombatLocked() or not HasReadyView(state.scrollBox) then return end
    state.scrollBox:ForEachFrame(state.syncSelection)
end

local function StyleFrame(state, frame)
    local previous = NS.Registry and NS.Registry.GetSurface
        and NS.Registry.GetSurface(frame)
    if NS.Surface.Attach(frame, FRAME_SPEC) and not previous then state.rootOwned = true end
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
        if NS.Surface.Attach(inset, INSET_SPEC) then state.inset = inset end
    end
    local background = _G.MacroFrameTextBackground
    if background and NS.Safety.CanCreateRegions(background, true) then
        HideNative(state, background.NineSlice)
        if NS.Surface.Attach(background, TEXT_SPEC) then state.textBackground = background end
    end
    StyleSlot(state, frame.SelectedMacroButton)
end

-- Per-frame state; its callbacks are built once, never per row or click.
local function FrameState(frame)
    local state = MacroWindow.states[frame]
    if state then return state end
    state = {
        buttons = setmetatable({}, { __mode = "k" }),
        clickHooks = setmetatable({}, { __mode = "k" }),
        nativeAlpha = setmetatable({}, { __mode = "k" }),
    }
    state.styleSlot = function(button) StyleSlot(state, button) end
    state.syncSelection = function(button) SyncSelection(state, button) end
    state.refreshSelection = function() RefreshVisibleSelection(state) end
    state.onRowInitialized = function(_, button)
        if state.active then StyleSlot(state, button) end
    end
    state.reapply = function()
        if state.active then MacroWindow.Apply(frame, state.owner) end
    end
    MacroWindow.states[frame] = state
    return state
end

local function HookFrame(state, frame)
    if not state.showHooked and type(frame.HookScript) == "function" then
        frame:HookScript("OnShow", state.reapply)
        state.showHooked = true
    end
    -- Blizzard rebuilds the macro selector on opening, tab changes and
    -- UPDATE_MACROS. As with Bags:UpdateItems, finish its native Update first.
    if not state.updateHooked and type(hooksecurefunc) == "function"
        and type(frame.Update) == "function" then
        hooksecurefunc(frame, "Update", state.reapply)
        state.updateHooked = true
    end
end

function MacroWindow.Apply(frame, owner)
    if not frame or NS.IsCombatLocked() or not NS.Safety.CanCreateRegions(frame, true) then
        return false
    end
    local state = FrameState(frame)
    state.active, state.owner, state.frame = true, owner, frame
    HookFrame(state, frame)
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
        scrollBox:RegisterCallback(event, state.onRowInitialized, state)
        state.registered, state.event = true, event
    end
    if HasReadyView(scrollBox) then
        scrollBox:ForEachFrame(state.styleSlot)
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
    if NS.Client and NS.Client.HasAddOn(MACRO_ADDON) == false then
        return false
    end
    loadFrame:RegisterEvent("ADDON_LOADED")
    return true
end

loadFrame:SetScript("OnEvent", function(self, event, addon)
    if event ~= "ADDON_LOADED" or addon ~= MACRO_ADDON then return end
    self:UnregisterEvent("ADDON_LOADED")
    if requestedOwner and _G.MacroFrame then
        MacroWindow.Apply(_G.MacroFrame, requestedOwner)
    end
end)

local function ReleaseState(state)
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

function MacroWindow.Disable(owner)
    if NS.IsCombatLocked() then return false end
    if requestedOwner == owner then
        requestedOwner = nil
        loadFrame:UnregisterEvent("ADDON_LOADED")
    end
    for _, state in pairs(MacroWindow.states) do
        if state.owner == owner and state.active then
            ReleaseState(state)
        end
    end
    return true
end

return MacroWindow

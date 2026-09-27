local _, NS = ...

-- Blizzard owns the macro selector, icon data and command editor. This adapter
-- replaces only its verified slot art and decorative frame textures.
local MacroWindow = { states = setmetatable({}, { __mode = "k" }) }
NS.MacroWindow = MacroWindow
local loadFrame = CreateFrame("Frame")
local requestedOwner

local Safety = NS.Safety
local Read = Safety.Read
local Public = Safety.Public
local Dispatch = Safety.Dispatch
local Kit = NS.AdapterKit

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

-- MacroFrame's native art is laid out above its background. Keep exact
-- original alpha values like Bags does, so the adapter can restore them when
-- Blizzard-window skinning is disabled without depending on another owner.
local function HideNative(state, region)
    if not region or not Safety.HasMethod(region, "SetAlpha")
        or not Safety.CanDecorate(region, true) then
        return false
    end
    if state.nativeAlpha[region] == nil then
        local alpha = Read(region, "GetAlpha")
        if type(alpha) ~= "number" then
            return false
        end
        state.nativeAlpha[region] = alpha
    end
    region:SetAlpha(0)
    return true
end

local function RestoreNative(state)
    for region, alpha in pairs(state.nativeAlpha) do
        if Read(region, "GetAlpha") == 0 then region:SetAlpha(alpha) end
        state.nativeAlpha[region] = nil
    end
end

local function TexturePath(region)
    local path = Read(region, "GetTexture")
    if type(path) ~= "string" then return nil end
    return path:gsub("/", "\\"):lower():gsub("%.blp$", "")
end

-- The divider's right half is an anonymous texture anchored to the named
-- left half; secret anchors are never compared.
local function FollowsDividerLeft(region)
    local point, relativeTo, relativePoint = Safety.Call(region, "GetPoint", 1)
    if not Public(point) or not Public(relativeTo) or not Public(relativePoint) then return false end
    return point == "LEFT" and relativeTo == _G.MacroHorizontalBarLeft
        and relativePoint == "RIGHT"
end

local function FadeDividerRegions(state, ...)
    for index = 1, select("#", ...) do
        local region = select(index, ...)
        if Safety.HasMethod(region, "GetTexture")
            and (TexturePath(region) == divider or FollowsDividerLeft(region)) then
            HideNative(state, region)
        end
    end
end

local function HasTemplateCoords(region)
    local left, right, top, bottom = Safety.Call(region, "GetTexCoord")
    if not Public(left) or not Public(right) or not Public(top) or not Public(bottom) then
        return false
    end
    return left == 0.140625 and right == 0.84375
        and top == 0.140625 and bottom == 0.84375
end

-- SelectorButtonTemplate has one BACKGROUND texture for the empty slot. Its
-- icon is the NormalTexture, so it remains Blizzard-owned and visible.
local function FadeBackgroundRegions(state, ...)
    for index = 1, select("#", ...) do
        local region = select(index, ...)
        if Read(region, "GetDrawLayer") == "BACKGROUND"
            and (TexturePath(region) == slotBackdrop or HasTemplateCoords(region)) then
            HideNative(state, region)
        end
    end
end

local function Selected(button)
    return Read(button and button.SelectedTexture, "IsShown") == true
end

-- True while a pooled slot still carries the art and surface of this pass.
-- A slot whose surface another skin replaced meanwhile takes a new one.
local function SlotStyled(state, button)
    local surface = state.slotSurfaces[button]
    return state.styledSlots[button] == state.pass and surface ~= nil
        and surface.spec == SLOT_SPEC and surface.visible ~= false
end

local function StyleSlot(state, button)
    if not state.active or NS.IsCombatLocked() or not button
        or not Safety.CanCreateRegions(button, true)
        or not button.Icon or not button.SelectedTexture then
        return false
    end
    -- Blizzard initializes pooled slots on every scroll and Update; a slot
    -- styled in this pass only follows the selection.
    if SlotStyled(state, button) then
        NS.Surface.SetActive(button, Selected(button))
        return true
    end
    FadeBackgroundRegions(state, Safety.Call(button, "GetRegions"))
    HideNative(state, button.SelectedTexture)
    HideNative(state, button.Highlight)
    local surface = NS.Surface.Attach(button, SLOT_SPEC)
    if not surface then return false end
    -- The icon is native ARTWORK. Put the transparent edge above it while
    -- retaining Blizzard's normal icon, name, drag and click behavior.
    surface.edge:SetDrawLayer("OVERLAY", 2)
    state.buttons[button] = true
    state.slotSurfaces[button] = surface
    state.styledSlots[button] = state.pass
    NS.Surface.SetActive(button, Selected(button))
    if not state.clickHooks[button] and Safety.HasMethod(button, "HookScript") then
        button:HookScript("OnClick", state.refreshSelection)
        state.clickHooks[button] = true
    end
    return true
end

local function SyncSelection(state, button)
    if state.buttons[button] then NS.Surface.SetActive(button, Selected(button)) end
end

local function RefreshVisibleSelection(state)
    if not state.active or NS.IsCombatLocked() then return end
    Kit.ForEachRow(state.scrollBox, state.syncSelection)
end

local function StyleFrame(state, frame)
    local previous = NS.Registry.GetSurface(frame)
    if NS.Surface.Attach(frame, FRAME_SPEC) and not previous then state.rootOwned = true end
    HideNative(state, frame.Bg)
    HideNative(state, frame.NineSlice)
    HideNative(state, _G.MacroFramePortrait)
    local portraitContainer = frame.PortraitContainer
    HideNative(state, portraitContainer)
    HideNative(state, portraitContainer and portraitContainer.portrait)
    HideNative(state, _G.MacroFrameSelectedMacroBackground)
    HideNative(state, _G.MacroHorizontalBarLeft)
    FadeDividerRegions(state, Safety.Call(frame, "GetRegions"))
    local inset = frame.Inset
    if inset and Safety.CanCreateRegions(inset, true) then
        HideNative(state, inset.Bg)
        HideNative(state, inset.NineSlice)
        if NS.Surface.Attach(inset, INSET_SPEC) then state.inset = inset end
    end
    local background = _G.MacroFrameTextBackground
    if background and Safety.CanCreateRegions(background, true) then
        HideNative(state, background.NineSlice)
        if NS.Surface.Attach(background, TEXT_SPEC) then state.textBackground = background end
    end
    StyleSlot(state, frame.SelectedMacroButton)
end

-- CallbackRegistry passes the registration owner first: the frame state.
local function OnRowInitialized(state, button)
    if state.active then StyleSlot(state, button) end
end

-- Styles the window chrome once per pass, then the visible slots. The first
-- pass waits until Blizzard shows the window: ADDON_LOADED fires while the
-- hidden MacroFrame still has no selector view.
local function Refresh(state)
    local frame = state.frame
    if not state.active or NS.IsCombatLocked() or not Safety.CanCreateRegions(frame, true) then
        return false
    end
    if Safety.HasMethod(frame, "IsShown") and Read(frame, "IsShown") ~= true then return true end
    if state.chromePass ~= state.pass then
        StyleFrame(state, frame)
        state.chromePass = state.pass
    end
    local selector = frame.MacroSelector
    local scrollBox = selector and selector.ScrollBox
    -- The selector can finish initializing after ADDON_LOADED. OnShow retries
    -- once Blizzard has built it.
    if not Safety.HasMethod(scrollBox, "ForEachFrame") then return true end
    state.scrollBox = scrollBox
    if not state.event then
        state.event = Kit.RegisterRowCallback(scrollBox, OnRowInitialized, state)
    end
    -- ForEachRow waits for Blizzard's list view; the row callback covers the
    -- rows Blizzard initializes once the view exists.
    Kit.ForEachRow(scrollBox, state.styleSlot)
    return true
end

-- Per-frame state; its callbacks are built once, never per row or click.
local function FrameState(frame)
    local state = MacroWindow.states[frame]
    if state then return state end
    state = {
        buttons = setmetatable({}, { __mode = "k" }),
        clickHooks = setmetatable({}, { __mode = "k" }),
        nativeAlpha = setmetatable({}, { __mode = "k" }),
        -- pooled slot -> the pass that styled it, and its surface
        styledSlots = setmetatable({}, { __mode = "k" }),
        slotSurfaces = setmetatable({}, { __mode = "k" }),
        pass = 0,
    }
    state.styleSlot = function(button) StyleSlot(state, button) end
    state.syncSelection = function(button) SyncSelection(state, button) end
    state.refreshSelection = function() RefreshVisibleSelection(state) end
    -- Blizzard's OnShow and Update run this inside their own call chain.
    state.refresh = function() Dispatch(Refresh, state) end
    MacroWindow.states[frame] = state
    return state
end

local function HookFrame(state, frame)
    if not state.showHooked and Safety.HasMethod(frame, "HookScript") then
        frame:HookScript("OnShow", state.refresh)
        state.showHooked = true
    end
    -- Blizzard rebuilds the macro selector on opening, tab changes and
    -- UPDATE_MACROS. As with Bags:UpdateItems, finish its native Update first.
    if not state.updateHooked and Kit.HookFunction(frame, "Update", state.refresh) then
        state.updateHooked = true
    end
end

-- A full pass: each enable, and the catalog pass (GenericWindows applies this
-- again after its own pass over the window). Blizzard's OnShow and Update
-- only style what the current pass has not styled yet.
function MacroWindow.Apply(frame, owner)
    if not frame or NS.IsCombatLocked() or not Safety.CanCreateRegions(frame, true) then
        return false
    end
    local state = FrameState(frame)
    state.active, state.owner, state.frame = true, owner, frame
    state.pass = state.pass + 1
    HookFrame(state, frame)
    return Refresh(state)
end

function MacroWindow.Start(owner)
    requestedOwner = owner
    local frame = _G.MacroFrame
    if frame then
        loadFrame:UnregisterEvent("ADDON_LOADED")
        return MacroWindow.Apply(frame, owner)
    end
    if NS.Client.HasAddOn(MACRO_ADDON) == false then
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
    if state.event then
        Kit.UnregisterRowCallback(state.scrollBox, state.event, state)
        state.event = nil
    end
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
